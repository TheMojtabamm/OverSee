package oversee

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const procHeader = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"

func procLine(n int, local string, state string) string {
	return "   " + string(rune('0'+n)) + ": " + local + " 00000000:0000 " + state + " 00000000:00000000 00:00000000 00000000     0        0 1000 1 0000000000000000 100 0 0 10 0\n"
}

func TestParseProcNetTCP(t *testing.T) {
	text := procHeader +
		procLine(0, "0100007F:2710", "0A") + // 127.0.0.1:10000 listening
		procLine(1, "00000000:01BB", "0A") + // 0.0.0.0:443 listening
		procLine(2, "0101A8C0:1F90", "0A") + // 192.168.1.1:8080 listening
		procLine(3, "0100007F:D431", "01") + // established -> ignored
		procLine(4, "00000000000000000000000001000000:2710", "0A") + // [::1]:10000
		procLine(5, "00000000000000000000000000000000:0050", "0A") + // [::]:80
		procLine(6, "0000000000000000FFFF00000100007F:2711", "0A") // [::ffff:127.0.0.1]:10001
	got := ParseProcNetTCP(text)
	type want struct {
		ip   string
		port int
		loop bool
	}
	exp := []want{
		{"127.0.0.1", 10000, true}, {"0.0.0.0", 443, false}, {"192.168.1.1", 8080, false},
		{"::1", 10000, true}, {"::", 80, false}, {"127.0.0.1", 10001, true},
	}
	if len(got) != len(exp) {
		t.Fatalf("got %d listeners: %+v", len(got), got)
	}
	for i, e := range exp {
		if !got[i].IP.Equal(net.ParseIP(e.ip)) || got[i].Port != e.port || got[i].Loopback() != e.loop {
			t.Errorf("#%d: got %v:%d loop=%v, want %+v", i, got[i].IP, got[i].Port, got[i].Loopback(), e)
		}
	}
	if len(ParseProcNetTCP("garbage\nmore garbage")) != 0 || len(ParseProcNetTCP("")) != 0 {
		t.Error("garbage must parse to nothing")
	}
}

func env(l ...Listener) DoctorEnv {
	return DoctorEnv{
		Listeners: func() []Listener { return l },
		Now:       func() time.Time { return time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC) },
		Service:   func() ServiceState { return ServiceState{Available: true, Active: "active", Enabled: "enabled"} },
	}
}

func find(f []Finding, sub string) *Finding {
	for i := range f {
		if strings.Contains(f[i].Title, sub) {
			return &f[i]
		}
	}
	return nil
}

func loop(port int) Listener { return Listener{IP: net.ParseIP("127.0.0.1"), Port: port} }

func healthy(t *testing.T) Paths {
	p := paths(t)
	p.AddKey("0123456789abcdef0123")
	p.AddLock(codeA + " " + fp + " ch")
	p.SaveSettings(Settings{Domain: "vpn.example.com", Upstream: "127.0.0.1:10000"})
	return p
}

func TestDoctorHealthySetupHasNoWarnings(t *testing.T) {
	p := healthy(t)
	f := p.Doctor(env(loop(10000)))
	if Worst(f) != OK {
		t.Fatalf("expected all ok, got %+v", f)
	}
	if find(f, "loopback only") == nil {
		t.Fatal("must positively confirm the loopback binding")
	}
}

// The one that matters most: an Xray inbound open to the world makes the gate pointless.
func TestDoctorCatchesXrayExposedAroundTheGate(t *testing.T) {
	p := healthy(t)
	for _, ip := range []string{"0.0.0.0", "::", "203.0.113.7"} {
		f := p.Doctor(env(Listener{IP: net.ParseIP(ip), Port: 10000}))
		x := find(f, "reachable around the gate")
		if x == nil || x.Level != Fail || Worst(f) != Fail {
			t.Fatalf("%s: must FAIL, got %+v", ip, f)
		}
		if !strings.Contains(x.Fix, "127.0.0.1") {
			t.Errorf("fix should say how: %q", x.Fix)
		}
	}
	// a loopback listener AND a public one on the same port: still a failure
	f := p.Doctor(env(loop(10000), Listener{IP: net.ParseIP("0.0.0.0"), Port: 10000}))
	if Worst(f) != Fail {
		t.Fatal("any public listener on the upstream port is a failure")
	}
	// other ports are not our business
	if Worst(p.Doctor(env(loop(10000), Listener{IP: net.ParseIP("0.0.0.0"), Port: 22}))) != OK {
		t.Fatal("ssh on 0.0.0.0 is fine")
	}
}

func TestDoctorNothingListening(t *testing.T) {
	f := healthy(t).Doctor(env())
	if x := find(f, "Nothing is listening"); x == nil || x.Level != Warn {
		t.Fatalf("%+v", f)
	}
}

func TestDoctorKeysLocksAndPermissions(t *testing.T) {
	p := paths(t)
	p.SaveSettings(Settings{Domain: "d.example.com", Upstream: "127.0.0.1:10000"})
	f := p.Doctor(env(loop(10000)))
	if find(f, "No app key").Level != Fail || find(f, "No locks").Level != Warn {
		t.Fatalf("%+v", f)
	}
	p.AddKey("short-key-1") // 11 chars
	if x := find(p.Doctor(env(loop(10000))), "App key is short"); x == nil {
		t.Fatal("short key should warn")
	}
	p.AddKey("a-long-enough-key-123456")
	os.Chmod(p.Keys, 0o644)
	if find(p.Doctor(env(loop(10000))), "keys.txt is readable") == nil {
		t.Fatal("world-readable keys file should warn")
	}
}

func TestDoctorCDNChecks(t *testing.T) {
	p := healthy(t)
	p.SetSetting("cdn", "cloudflare")
	f := p.Doctor(env(loop(10000)))
	if find(f, "No CDN IP ranges") == nil || find(f, "reached around the CDN") == nil {
		t.Fatalf("%+v", f)
	}
	os.MkdirAll(p.Dir, 0o750)
	os.WriteFile(p.Proxies, []byte("173.245.48.0/20\n"), 0o640)
	p.SetSetting("only-proxy", "on")
	f = p.Doctor(env(loop(10000)))
	if find(f, "reached around the CDN") != nil || find(f, "CDN IP ranges").Level != OK {
		t.Fatalf("%+v", f)
	}
	old := time.Now().Add(-100 * time.Hour)
	os.Chtimes(p.Proxies, old, old)
	if find(p.Doctor(env(loop(10000))), "ranges are old") == nil {
		t.Fatal("stale ranges should warn")
	}
}

func TestDoctorTransportChecks(t *testing.T) {
	p := healthy(t)
	p.SaveSettings(Settings{Plain: ":8080", Upstream: "127.0.0.1:10000"})
	if x := find(p.Doctor(env(loop(10000))), "Plain HTTP and no CDN"); x == nil || x.Level != Warn {
		t.Fatal("plain HTTP without a CDN exposes the token header")
	}
	p.SaveSettings(Settings{Upstream: "127.0.0.1:10000"})
	if x := find(p.Doctor(env(loop(10000))), "No domain"); x == nil || x.Level != Fail {
		t.Fatal("nothing to listen on is a failure")
	}
}

func TestDoctorCertificateExpiry(t *testing.T) {
	p := healthy(t)
	mk := func(notAfter time.Time) string {
		key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		tpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "origin"},
			NotBefore: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), NotAfter: notAfter}
		der, _ := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
		path := filepath.Join(t.TempDir(), "c.pem")
		os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o600)
		return path
	}
	now := time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC)
	for name, c := range map[string]struct {
		notAfter time.Time
		title    string
		level    Level
	}{
		"valid":   {now.Add(90 * 24 * time.Hour), "Certificate valid", OK},
		"soon":    {now.Add(5 * 24 * time.Hour), "expires soon", Warn},
		"expired": {now.Add(-24 * time.Hour), "expired", Fail},
	} {
		p.SaveSettings(Settings{Upstream: "127.0.0.1:10000", Cert: mk(c.notAfter), Key: "x"})
		x := find(p.Doctor(env(loop(10000))), c.title)
		if x == nil || x.Level != c.level {
			t.Errorf("%s: %+v", name, x)
		}
	}
	p.SaveSettings(Settings{Upstream: "127.0.0.1:10000", Cert: "/nonexistent.pem", Key: "x"})
	if find(p.Doctor(env(loop(10000))), "unreadable").Level != Fail {
		t.Error("missing cert file")
	}
}
