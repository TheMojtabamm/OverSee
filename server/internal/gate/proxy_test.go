package gate

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func nets(t *testing.T, lines ...string) *TrustedProxies {
	t.Helper()
	n, err := ParseCIDRs(bufio.NewScanner(strings.NewReader(strings.Join(lines, "\n"))))
	if err != nil {
		t.Fatal(err)
	}
	return NewTrustedProxies(n)
}

func req(peer string, hdr map[string]string) *http.Request {
	r := httptest.NewRequest("GET", "/ws", nil)
	r.RemoteAddr = peer
	for k, v := range hdr {
		r.Header.Set(k, v)
	}
	return r
}

func TestParseCIDRs(t *testing.T) {
	tp := nets(t, "# cloudflare", "173.245.48.0/20", "  2400:cb00::/32  # v6", "", "198.51.100.7")
	for ip, want := range map[string]bool{
		"173.245.50.1": true, "173.245.64.1": false, "2400:cb00::1": true, "2400:cb01::1": false,
		"198.51.100.7": true, "198.51.100.8": false,
	} {
		if got := tp.Contains(net.ParseIP(ip)); got != want {
			t.Errorf("%s: got %v want %v", ip, got, want)
		}
	}
	for _, bad := range []string{"not-an-ip", "10.0.0.0/33", "999.1.1.1"} {
		if _, err := ParseCIDRs(bufio.NewScanner(strings.NewReader(bad))); err == nil {
			t.Errorf("should reject %q", bad)
		}
	}
	if (*TrustedProxies)(nil).Contains(net.ParseIP("1.1.1.1")) {
		t.Error("nil set trusts nobody")
	}
}

func TestResolveClientIP_Cloudflare(t *testing.T) {
	tp := nets(t, "173.245.48.0/20")
	cases := []struct {
		name    string
		r       *http.Request
		wantIP  string
		wantVia bool
	}{
		{"via cloudflare, header used", req("173.245.48.9:443", map[string]string{"CF-Connecting-IP": "203.0.113.5"}), "203.0.113.5", true},
		{"via cloudflare, IPv6 client", req("173.245.48.9:443", map[string]string{"CF-Connecting-IP": "2001:db8::7"}), "2001:db8::7", true},
		// SPOOFING: someone hits the origin directly and sets the header themselves
		{"direct connection, header ignored", req("198.51.100.99:5555", map[string]string{"CF-Connecting-IP": "203.0.113.5"}), "198.51.100.99", false},
		{"header missing behind CDN -> proxy ip", req("173.245.48.9:443", nil), "173.245.48.9", true},
		{"header garbage -> proxy ip", req("173.245.48.9:443", map[string]string{"CF-Connecting-IP": "not-an-ip"}), "173.245.48.9", true},
		{"header list rejected (single IP only)", req("173.245.48.9:443", map[string]string{"CF-Connecting-IP": "1.1.1.1, 2.2.2.2"}), "173.245.48.9", true},
		{"other CDN's header is not honoured", req("173.245.48.9:443", map[string]string{"Fastly-Client-IP": "203.0.113.5"}), "173.245.48.9", true},
	}
	for _, c := range cases {
		ip, via := ResolveClientIP(c.r, tp, ProviderCloudflare)
		if ip != c.wantIP || via != c.wantVia {
			t.Errorf("%s: got (%s,%v) want (%s,%v)", c.name, ip, via, c.wantIP, c.wantVia)
		}
	}
}

func TestResolveClientIP_FastlyAndNone(t *testing.T) {
	tp := nets(t, "151.101.0.0/16")
	ip, via := ResolveClientIP(req("151.101.1.1:443", map[string]string{"Fastly-Client-IP": "203.0.113.5"}), tp, ProviderFastly)
	if ip != "203.0.113.5" || !via {
		t.Fatalf("%s %v", ip, via)
	}
	// provider none: never trust any header, peer is the client even if "trusted"
	ip, via = ResolveClientIP(req("151.101.1.1:443", map[string]string{"Fastly-Client-IP": "203.0.113.5"}), tp, ProviderNone)
	if ip != "151.101.1.1" || via {
		t.Fatalf("%s %v", ip, via)
	}
}

func TestResolveClientIP_GenericXForwardedFor(t *testing.T) {
	tp := nets(t, "10.0.0.0/8")
	// client spoofs the left side; only what the trusted hop appended counts
	r := req("10.0.0.2:443", map[string]string{"X-Forwarded-For": "1.2.3.4, 203.0.113.5, 10.0.0.9"})
	if ip, via := ResolveClientIP(r, tp, ProviderGeneric); ip != "203.0.113.5" || !via {
		t.Fatalf("rightmost untrusted must win, got %s %v", ip, via)
	}
	// untrusted peer: XFF ignored entirely
	r = req("198.51.100.1:1", map[string]string{"X-Forwarded-For": "203.0.113.5"})
	if ip, via := ResolveClientIP(r, tp, ProviderGeneric); ip != "198.51.100.1" || via {
		t.Fatalf("%s %v", ip, via)
	}
	// garbage in the chain: do not guess
	r = req("10.0.0.2:443", map[string]string{"X-Forwarded-For": "203.0.113.5, banana"})
	if ip, _ := ResolveClientIP(r, tp, ProviderGeneric); ip != "10.0.0.2" {
		t.Fatalf("%s", ip)
	}
}

func TestParseProvider(t *testing.T) {
	for in, want := range map[string]Provider{"": ProviderNone, "none": ProviderNone, "Cloudflare": ProviderCloudflare, " fastly ": ProviderFastly, "generic": ProviderGeneric} {
		got, err := ParseProvider(in)
		if err != nil || got != want {
			t.Errorf("%q: %v %v", in, got, err)
		}
	}
	if _, err := ParseProvider("akamai"); err == nil {
		t.Error("unknown provider must be an error")
	}
}

// The scenario that motivated all this: a CDN edge IP is shared by thousands of real
// users. A scanner behind that edge must be limited on ITS OWN address, never taking
// the edge (and every honest user behind it) down.
func TestHandlerBehindCDN(t *testing.T) {
	up, _ := startUpstream(t)
	edge := nets(t, "127.0.0.0/8") // httptest peers are 127.0.0.1 => acts as the CDN edge
	st := NewStats()
	lim := NewLimiter(3, time.Minute, time.Hour)
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys },
		Options{Limiter: lim, Stats: st, Proxies: edge, Provider: ProviderCloudflare, OnlyProxy: true},
		func() time.Time { return now }))
	defer g.Close()

	do := func(realIP, tok string) int {
		rq, _ := http.NewRequest("GET", g.URL+"/x", nil)
		rq.Header.Set("CF-Connecting-IP", realIP)
		if tok != "" {
			rq.Header.Set(Header, tok)
		}
		resp, err := http.DefaultClient.Do(rq)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		return resp.StatusCode
	}
	good := Token(appKey, code, ownerFp, now)

	// scanner 198.51.100.66 burns through its failures behind the SAME edge IP
	for i := 0; i < 3; i++ {
		if do("198.51.100.66", "bad") != 404 {
			t.Fatal("bad token must 404")
		}
	}
	if do("198.51.100.66", good) != 404 {
		t.Fatal("the scanner's own address is now blocked")
	}
	// ...but honest users behind the same edge are untouched
	if do("203.0.113.10", good) != 200 || do("203.0.113.11", good) != 200 {
		t.Fatal("honest users sharing the CDN edge must not be blocked")
	}
	sn := st.Snapshot(now)
	if len(sn.Locks) != 1 || sn.Locks[0].DistinctIPs != 2 {
		t.Fatalf("distinct IPs must be the real clients (2), got %+v", sn.Locks)
	}
}

func TestOnlyProxyRefusesDirectConnections(t *testing.T) {
	up, seen := startUpstream(t)
	edge := nets(t, "203.0.113.0/24") // the test peer (127.0.0.1) is NOT in the CDN list
	st := NewStats()
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys },
		Options{Stats: st, Proxies: edge, Provider: ProviderCloudflare, OnlyProxy: true},
		func() time.Time { return now }))
	defer g.Close()

	rq, _ := http.NewRequest("GET", g.URL+"/x", nil)
	rq.Header.Set(Header, Token(appKey, code, ownerFp, now)) // even a PERFECT token
	rq.Header.Set("CF-Connecting-IP", "203.0.113.5")         // and a spoofed CDN header
	resp, err := http.DefaultClient.Do(rq)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("direct-to-origin must be refused, got %d", resp.StatusCode)
	}
	select {
	case <-seen:
		t.Fatal("upstream must never see it")
	default:
	}
	if st.Snapshot(now).Rejects["not_via_cdn"] != 1 {
		t.Fatalf("%v", st.Snapshot(now).Rejects)
	}
}

func TestTrustedProxiesFileReloadKeepsPreviousOnBadEdit(t *testing.T) {
	path := t.TempDir() + "/proxies.txt"
	os.WriteFile(path, []byte("10.0.0.0/8\n"), 0o600)
	tp, err := LoadTrustedProxies(path)
	if err != nil || tp.Len() != 1 {
		t.Fatalf("%v", err)
	}
	os.WriteFile(path, []byte("garbage\n"), 0o600)
	if err := tp.reload(); err == nil || tp.Len() != 1 {
		t.Fatal("a bad edit must be rejected and the previous list kept")
	}
	if tp2, err := LoadTrustedProxies(t.TempDir() + "/missing"); err != nil || tp2.Len() != 0 {
		t.Fatalf("missing file = nothing trusted: %v", err)
	}
}
