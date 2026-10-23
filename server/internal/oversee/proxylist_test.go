package oversee

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// Captured from the real endpoints (shortened but structurally identical).
const cfV4 = "173.245.48.0/20\n103.21.244.0/22\n103.22.200.0/22\n103.31.4.0/22\n141.101.64.0/18\n108.162.192.0/18\n190.93.240.0/20\n188.114.96.0/20\n197.234.240.0/22\n198.41.128.0/17\n162.158.0.0/15\n104.16.0.0/13\n"
const cfV6 = "2400:cb00::/32\n2606:4700::/32\n2803:f800::/32\n"
const fastlyJSON = `{"addresses":["23.235.32.0/20","43.249.72.0/22","90.98.0.0/17","90.98.128.0/18","103.244.50.0/24","103.245.222.0/23","103.245.224.0/24","104.156.80.0/20","140.248.64.0/18","140.248.128.0/17","146.75.0.0/17","151.101.0.0/16"],"ipv6_addresses":["2a04:4e40::/32","2a04:4e42::/31"]}`

func serve(t *testing.T, routes map[string]string) string {
	t.Helper()
	mux := http.NewServeMux()
	for path, body := range routes {
		b := body
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(b)) })
	}
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv.URL
}

func withURLs(t *testing.T, m map[string][]string) {
	old := providerURLs
	providerURLs = m
	t.Cleanup(func() { providerURLs = old })
}

func TestParseProviderLists(t *testing.T) {
	cf, err := ParseProviderList("cloudflare", []byte(cfV4+cfV6))
	if err != nil || len(cf) != 15 {
		t.Fatalf("%d %v", len(cf), err)
	}
	fa, err := ParseProviderList("fastly", []byte(fastlyJSON))
	if err != nil || len(fa) != 14 || fa[len(fa)-1] != "2a04:4e42::/31" {
		t.Fatalf("%d %v", len(fa), err)
	}
	for _, bad := range []struct{ p, body string }{
		{"cloudflare", "<html>blocked</html>"},
		{"cloudflare", "1.2.3.4/99"},
		{"fastly", "not json"},
		{"fastly", `{"addresses":["nope"]}`},
		{"akamai", "1.0.0.0/8"},
	} {
		if _, err := ParseProviderList(bad.p, []byte(bad.body)); err == nil {
			t.Errorf("should reject %s %q", bad.p, bad.body)
		}
	}
}

func TestUpdateProxiesWritesAFileTheGateCanLoad(t *testing.T) {
	url := serve(t, map[string]string{"/v4": cfV4, "/v6": cfV6})
	withURLs(t, map[string][]string{"cloudflare": {url + "/v4", url + "/v6"}})
	t.Setenv("OVERSEE_DIR", t.TempDir())
	p := DefaultPaths()

	n, err := p.UpdateProxies(context.Background(), "cloudflare", nil)
	if err != nil || n != 15 {
		t.Fatalf("%d %v", n, err)
	}
	i := p.ProxyInfo()
	if i.Count != 15 || i.Age < 0 {
		t.Fatalf("%+v", i)
	}
	b, _ := os.ReadFile(p.Proxies)
	if !strings.HasPrefix(string(b), "# cloudflare IP ranges") || !strings.Contains(string(b), "2606:4700::/32") {
		t.Fatalf("%s", b)
	}
}

func TestFailedOrShortDownloadNeverReplacesTheWorkingList(t *testing.T) {
	t.Setenv("OVERSEE_DIR", t.TempDir())
	p := DefaultPaths()
	os.MkdirAll(p.Dir, 0o750)
	os.WriteFile(p.Proxies, []byte("10.0.0.0/8\n"), 0o640)

	// 1) server error  2) truncated list  3) garbage body
	for name, routes := range map[string]map[string]string{
		"short":   {"/v4": "173.245.48.0/20\n"},
		"garbage": {"/v4": "<html>captcha</html>"},
	} {
		url := serve(t, routes)
		withURLs(t, map[string][]string{"cloudflare": {url + "/v4"}})
		if _, err := p.UpdateProxies(context.Background(), "cloudflare", nil); err == nil {
			t.Errorf("%s: should fail", name)
		}
	}
	withURLs(t, map[string][]string{"cloudflare": {"http://127.0.0.1:1/nothing"}})
	if _, err := p.UpdateProxies(context.Background(), "cloudflare", nil); err == nil {
		t.Error("unreachable: should fail")
	}
	b, _ := os.ReadFile(p.Proxies)
	if string(b) != "10.0.0.0/8\n" {
		t.Fatalf("working list was overwritten: %q", b)
	}
}

func TestFastlyUpdate(t *testing.T) {
	url := serve(t, map[string]string{"/list": fastlyJSON})
	withURLs(t, map[string][]string{"fastly": {url + "/list"}})
	t.Setenv("OVERSEE_DIR", t.TempDir())
	p := DefaultPaths()
	if n, err := p.UpdateProxies(context.Background(), "fastly", nil); err != nil || n != 14 {
		t.Fatalf("%d %v", n, err)
	}
}

func TestCDNModes(t *testing.T) {
	for _, ok := range []string{"", "none", "cloudflare", "fastly", "generic"} {
		if !ValidCDN(ok) {
			t.Errorf("%q should be valid", ok)
		}
	}
	if ValidCDN("akamai") {
		t.Error("akamai is not supported")
	}
	seq := []string{""}
	for i := 0; i < 4; i++ {
		seq = append(seq, NextCDN(seq[len(seq)-1]))
	}
	if strings.Join(seq, ",") != ",cloudflare,fastly,generic," {
		t.Fatalf("cycle: %q", seq)
	}
}
