package oversee

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"oversea/server/internal/gate"
)

const (
	codeA = "0123456789abcdef0123456789abcdef"
	codeB = "ffffffffffffffffffffffffffffffff"
	fp    = "3FA9-0C21-B7D4-9E10"
)

func paths(t *testing.T) Paths {
	t.Setenv("OVERSEE_DIR", filepath.Join(t.TempDir(), "etc"))
	return DefaultPaths()
}

func TestAddListRevokeLock(t *testing.T) {
	p := paths(t)
	if l, _ := p.Locks(); len(l) != 0 {
		t.Fatal("empty at start")
	}
	if _, err := p.AddLock(codeA + " " + fp + " channel A"); err != nil {
		t.Fatal(err)
	}
	if _, err := p.AddLock(codeB + " " + fp); err != nil {
		t.Fatal(err)
	}
	locks, _ := p.Locks()
	if len(locks) != 2 {
		t.Fatalf("%v", locks)
	}

	// re-adding the same code replaces, not duplicates
	if _, err := p.AddLock(codeA + " " + fp + " renamed"); err != nil {
		t.Fatal(err)
	}
	locks, _ = p.Locks()
	if len(locks) != 2 {
		t.Fatalf("duplicate created: %v", locks)
	}

	// the file the gate reads is valid and contains exactly these entries
	f, _ := os.Open(p.Allow)
	defer f.Close()
	m, err := gate.ParseAllowList(newScanner(f))
	if err != nil || len(m) != 2 {
		t.Fatalf("%v %v", m, err)
	}

	// revoke by code-id prefix
	id := gate.CodeID(codeA)
	got, err := p.RevokeLock(id[:6])
	if err != nil || got.Code != codeA {
		t.Fatalf("%v %v", got, err)
	}
	locks, _ = p.Locks()
	if len(locks) != 1 || locks[0].Code != codeB {
		t.Fatalf("%v", locks)
	}
}

func TestRevokeErrors(t *testing.T) {
	p := paths(t)
	p.AddLock(codeA + " " + fp)
	if _, err := p.RevokeLock("ab"); err == nil {
		t.Error("too short must be rejected")
	}
	if _, err := p.RevokeLock("zzzzzz"); err == nil {
		t.Error("no match must error")
	}
	// ambiguous: both codes start with different chars but we force a shared prefix
	p.AddLock(codeA[:31] + "0 " + fp)
	if _, err := p.RevokeLock(codeA[:8]); err == nil || !strings.Contains(err.Error(), "ambiguous") {
		t.Errorf("want ambiguous, got %v", err)
	}
}

func TestAddLockValidation(t *testing.T) {
	p := paths(t)
	for _, bad := range []string{"", "hello", codeA, "short " + fp, "zz" + codeA[2:] + " " + fp} {
		if _, err := p.AddLock(bad); err == nil {
			t.Errorf("should reject %q", bad)
		}
	}
	if l, _ := p.Locks(); len(l) != 0 {
		t.Fatal("nothing may be written for bad input")
	}
}

func TestLockPreservesCommentsOfOtherLines(t *testing.T) {
	p := paths(t)
	os.MkdirAll(p.Dir, 0o750)
	os.WriteFile(p.Allow, []byte("# my notes\n"+codeA+" "+fp+" A\n"), 0o640)
	p.AddLock(codeB + " " + fp + " B")
	b, _ := os.ReadFile(p.Allow)
	if !strings.HasPrefix(string(b), "# my notes\n") {
		t.Fatalf("comment lost:\n%s", b)
	}
	p.RevokeLock(gate.CodeID(codeA)[:6])
	b, _ = os.ReadFile(p.Allow)
	if !strings.Contains(string(b), "# my notes") || strings.Contains(string(b), codeA) {
		t.Fatalf("%s", b)
	}
}

func TestKeys(t *testing.T) {
	p := paths(t)
	if k, _ := p.ListKeys(); len(k) != 0 {
		t.Fatal()
	}
	if err := p.AddKey("first-key-123"); err != nil {
		t.Fatal(err)
	}
	if err := p.AddKey("second-key-456"); err != nil {
		t.Fatal(err)
	}
	k, _ := p.ListKeys()
	if len(k) != 2 || k[0] != "second-key-456" || k[1] != "first-key-123" {
		t.Fatalf("newest must be first: %v", k)
	}
	p.AddKey("first-key-123") // moves to front, no duplicate
	k, _ = p.ListKeys()
	if len(k) != 2 || k[0] != "first-key-123" {
		t.Fatalf("%v", k)
	}
	if err := p.RemoveKey(0); err != nil {
		t.Fatal(err)
	}
	k, _ = p.ListKeys()
	if len(k) != 1 || k[0] != "second-key-456" {
		t.Fatalf("%v", k)
	}
	for _, bad := range []string{"short", "has space 12345", "with#hash123"} {
		if p.AddKey(bad) == nil {
			t.Errorf("should reject %q", bad)
		}
	}
	if p.RemoveKey(9) == nil {
		t.Error("out of range")
	}
	st, _ := os.Stat(p.Keys)
	if st.Mode().Perm() != 0o640 {
		t.Errorf("keys file mode %v, want 0640 (group oversee reads it)", st.Mode().Perm())
	}
	// the gate can load what we wrote
	kf, err := gate.LoadKeyFile(p.Keys, nil)
	if err != nil || len(kf.Get()) != 1 {
		t.Fatalf("%v", err)
	}
}

func TestSettingsRoundTrip(t *testing.T) {
	p := paths(t)
	if s := p.LoadSettings(); s.Upstream != "127.0.0.1:10000" || s.Domain != "" {
		t.Fatalf("%+v", s)
	}
	want := Settings{Domain: "vpn.example.com", Upstream: "127.0.0.1:12345", LeakIPs: 7,
		CDN: "cloudflare", OnlyProxy: true, Cert: "/etc/oversea/origin.pem", Key: "/etc/oversea/origin.key"}
	if err := p.SaveSettings(want); err != nil {
		t.Fatal(err)
	}
	if got := p.LoadSettings(); got != want {
		t.Fatalf("%+v", got)
	}
}

func TestMaskAndSnippet(t *testing.T) {
	if m := MaskKey("abcdefghijkl"); strings.Contains(m, "abcdefgh") || !strings.HasSuffix(m, "ijkl") {
		t.Fatal(m)
	}
	u := NewUUID()
	if len(u) != 36 || u[14] != '4' {
		t.Fatalf("bad uuid %s", u)
	}
	l := ClientLink("vpn.example.com", 443, true, "/ws-ab12", u, "x")
	if !strings.Contains(l, "path=%2Fws-ab12") || !strings.Contains(l, "type=ws") {
		t.Fatal(l)
	}
	if !strings.Contains(XrayInbound(10000, "/ws-ab12", u), `"path": "/ws-ab12"`) {
		t.Fatal("snippet")
	}
}

func newScanner(f *os.File) *bufio.Scanner { return bufio.NewScanner(f) }

func TestSetSetting(t *testing.T) {
	p := paths(t)
	for name, v := range map[string]string{"domain": "vpn.example.com", "upstream": "127.0.0.1:12000", "leak-ips": "40", "cdn": "cloudflare", "cert": "/c.pem", "key": "/k.pem"} {
		if err := p.SetSetting(name, v); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
	}
	if err := p.SetSetting("ip-limit", "off"); err != nil || !p.LoadSettings().NoIPLimit {
		t.Fatalf("ip-limit off: %v", err)
	}
	if err := p.SetSetting("ip-limit", "on"); err != nil || p.LoadSettings().NoIPLimit {
		t.Fatalf("ip-limit on: %v", err)
	}
	if err := p.SetSetting("only-proxy", "on"); err != nil {
		t.Fatal(err)
	}
	if err := p.SetSetting("token-days", "3"); err != nil || p.LoadSettings().TokenDays != 3 {
		t.Fatalf("token-days: %v", err)
	}
	for _, bad := range []string{"0", "8", "x"} {
		if p.SetSetting("token-days", bad) == nil {
			t.Errorf("token-days %q must be rejected", bad)
		}
	}
	s := p.LoadSettings()
	if s.Domain != "vpn.example.com" || s.Upstream != "127.0.0.1:12000" || s.LeakIPs != 40 || s.CDN != "cloudflare" || !s.OnlyProxy || s.Cert != "/c.pem" || s.Key != "/k.pem" {
		t.Fatalf("%+v", s)
	}
	// turning the CDN off also turns only-proxy off (it would refuse everyone otherwise)
	if err := p.SetSetting("cdn", "none"); err != nil {
		t.Fatal(err)
	}
	if s := p.LoadSettings(); s.CDN != "" || s.OnlyProxy {
		t.Fatalf("%+v", s)
	}
	for _, bad := range [][2]string{{"cdn", "akamai"}, {"leak-ips", "-3"}, {"leak-ips", "x"}, {"upstream", "nohostport"}, {"only-proxy", "on"}, {"colour", "red"}} {
		if p.SetSetting(bad[0], bad[1]) == nil {
			t.Errorf("should reject %v", bad)
		}
	}
}

func TestEntryAndUpstreamPorts(t *testing.T) {
	d := DefaultSettings()
	if p, tls := d.EntryPort(); p != 443 || !tls {
		t.Fatalf("default entry = %d %v", p, tls)
	}
	if d.UpstreamPort() != 10000 {
		t.Fatalf("default upstream port = %d", d.UpstreamPort())
	}
	s := Settings{Plain: ":8080", Upstream: "127.0.0.1:12345"}
	if p, tls := s.EntryPort(); p != 8080 || tls {
		t.Fatalf("plain entry = %d %v", p, tls)
	}
	if s.UpstreamPort() != 12345 {
		t.Fatalf("upstream port = %d", s.UpstreamPort())
	}
	if p, tls := (Settings{Port: 8443}).EntryPort(); p != 8443 || !tls {
		t.Fatalf("tls port = %d %v", p, tls)
	}
}

func TestSetPortAndBareUpstream(t *testing.T) {
	p := paths(t)
	if err := p.SetSetting("port", "8443"); err != nil || p.LoadSettings().Port != 8443 {
		t.Fatalf("port: %v %+v", err, p.LoadSettings())
	}
	for _, bad := range []string{"0", "70000", "x", ""} {
		if p.SetSetting("port", bad) == nil {
			t.Errorf("port %q should be refused", bad)
		}
	}
	if err := p.SetSetting("upstream", "12345"); err != nil || p.LoadSettings().Upstream != "127.0.0.1:12345" {
		t.Fatalf("bare upstream port: %v %+v", err, p.LoadSettings())
	}
	if err := p.SetSetting("upstream", "10.0.0.5:9000"); err != nil || p.LoadSettings().Upstream != "10.0.0.5:9000" {
		t.Fatalf("host:port upstream: %v", err)
	}
}
