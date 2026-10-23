package oversee

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strings"
	"testing"

	"oversea/server/internal/gate"
)

// gateServer runs the real gate handler (with the probe wired to p's nonce file).
func gateServer(t *testing.T, p Paths, tp *gate.TrustedProxies, prov gate.Provider) *httptest.Server {
	t.Helper()
	up, _ := url.Parse("http://127.0.0.1:1") // never reached by the probe
	h := gate.NewWithOptions(up, func() map[string]gate.Entry { return nil },
		func() [][]byte { return [][]byte{[]byte("k")} },
		gate.Options{Probe: &gate.Probe{File: p.Probe}, Proxies: tp, Provider: prov})
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return srv
}

// edge is a CDN stand-in: optionally edits the header, optionally adds the client IP.
func edge(t *testing.T, origin string, mutate func(h http.Header)) *httptest.Server {
	t.Helper()
	u, _ := url.Parse(origin)
	rp := &httputil.ReverseProxy{Rewrite: func(r *httputil.ProxyRequest) {
		r.SetURL(u)
		r.Out.Header.Set("CF-Connecting-IP", "198.51.100.77")
		if mutate != nil {
			mutate(r.Out.Header)
		}
	}}
	srv := httptest.NewServer(rp)
	t.Cleanup(srv.Close)
	return srv
}

func levels(f []Finding) map[string]Level {
	m := map[string]Level{}
	for _, x := range f {
		m[x.Title] = x.Level
	}
	return m
}

func hasFail(f []Finding, sub string) bool {
	for _, x := range f {
		if x.Level == Fail && strings.Contains(x.Title, sub) {
			return true
		}
	}
	return false
}

func TestCDNTest_HealthyEdge(t *testing.T) {
	p := paths(t)
	p.SetSetting("cdn", "cloudflare")
	tp := gate.NewTrustedProxies(mustNets(t, "127.0.0.0/8"))
	g := gateServer(t, p, tp, gate.ProviderCloudflare)
	e := edge(t, g.URL, nil)

	f, err := p.CDNTest(context.Background(), e.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	if Worst(f) != OK {
		t.Fatalf("%+v", f)
	}
	m := levels(f)
	if m["normal request: token header arrived intact"] != OK || m["WebSocket upgrade: token header arrived intact"] != OK {
		t.Fatalf("both request shapes must pass: %v", m)
	}
	var seen string
	for _, x := range f {
		if x.Title == "Real client IP is visible" {
			seen = x.Detail
		}
	}
	if !strings.Contains(seen, "198.51.100.77") {
		t.Fatalf("must report the real client IP the gate saw, got %q", seen)
	}
}

func TestCDNTest_StrippedHeaderIsCaught(t *testing.T) {
	p := paths(t)
	g := gateServer(t, p, nil, gate.ProviderNone)
	e := edge(t, g.URL, func(h http.Header) { h.Del(gate.Header) })
	f, err := p.CDNTest(context.Background(), e.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !hasFail(f, "STRIPPED") || Worst(f) != Fail {
		t.Fatalf("a CDN that drops the header must be reported: %+v", f)
	}
}

func TestCDNTest_AlteredHeaderIsCaught(t *testing.T) {
	p := paths(t)
	g := gateServer(t, p, nil, gate.ProviderNone)
	e := edge(t, g.URL, func(h http.Header) { h.Set(gate.Header, strings.ToUpper(h.Get(gate.Header))) })
	f, _ := p.CDNTest(context.Background(), e.URL, nil)
	if !hasFail(f, "ALTERED") {
		t.Fatalf("a CDN that rewrites the header must be reported: %+v", f)
	}
}

func TestCDNTest_UntrustedPeerIsCaught(t *testing.T) {
	p := paths(t)
	p.SetSetting("cdn", "cloudflare")
	// the list does not contain the edge's address (stale ranges / wrong CDN)
	tp := gate.NewTrustedProxies(mustNets(t, "173.245.48.0/20"))
	g := gateServer(t, p, tp, gate.ProviderCloudflare)
	e := edge(t, g.URL, nil)
	f, _ := p.CDNTest(context.Background(), e.URL, nil)
	if !hasFail(f, "did not come from a trusted CDN range") {
		t.Fatalf("%+v", f)
	}
}

func TestCDNTest_GateNotReachableOrWrongOrigin(t *testing.T) {
	p := paths(t)
	// nothing listening
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	addr := l.Addr().String()
	l.Close()
	f, _ := p.CDNTest(context.Background(), "http://"+addr, nil)
	if !hasFail(f, "request failed") {
		t.Fatalf("%+v", f)
	}
	// something else answers (not the gate): 404 -> "did not answer the probe"
	other := httptest.NewServer(http.NotFoundHandler())
	defer other.Close()
	f, _ = p.CDNTest(context.Background(), other.URL, nil)
	if !hasFail(f, "did not answer the probe") {
		t.Fatalf("%+v", f)
	}
}

func TestCDNTest_NonceIsOneShotAndCleanedUp(t *testing.T) {
	p := paths(t)
	g := gateServer(t, p, nil, gate.ProviderNone)
	if _, err := p.CDNTest(context.Background(), g.URL, nil); err != nil {
		t.Fatal(err)
	}
	// the probe file is removed afterwards, so the URL stops existing
	resp, err := http.Get(g.URL + gate.ProbePath + "00000000000000000000000000000000")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("probe must be gone, got %d", resp.StatusCode)
	}
}

func TestCDNTest_NeedsADomainOrURL(t *testing.T) {
	if _, err := paths(t).CDNTest(context.Background(), "", nil); err == nil {
		t.Fatal("no domain and no --url must be an error")
	}
}

func mustNets(t *testing.T, cidrs ...string) []*net.IPNet {
	t.Helper()
	var out []*net.IPNet
	for _, c := range cidrs {
		_, n, err := net.ParseCIDR(c)
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, n)
	}
	return out
}
