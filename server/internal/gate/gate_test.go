package gate

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

const (
	code    = "0123456789abcdef0123456789abcdef" // the lock's secret code
	ownerFp = "3FA9-0C21-B7D4-9E10"
	thiefFp = "AAAA-BBBB-CCCC-DDDD"
)

var (
	appKey  = []byte("test-app-key-0123456789")
	now     = time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC)
	appKeys = [][]byte{appKey}
	allow   = map[string]Entry{CodeID(code): {Code: code, CreatorFp: ownerFp}}
)

func list() map[string]Entry { return allow }

// Fixed vector shared with the Dart test (test/gate_token_test.dart). If either
// side changes the construction, both tests fail.
func TestTokenVector(t *testing.T) {
	got := Token([]byte("vector-key"), "0123456789abcdef0123456789abcdef", "3FA9-0C21-B7D4-9E10",
		time.Unix(86400*20000, 0))
	const want = "db1f62c4499c7e2f.20000.00bd68c142b4aba07b6e724ebb7ebc6287ca684699e1182ffe960cade6a357d5"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}

func TestValid(t *testing.T) {
	good := Token(appKey, code, ownerFp, now)
	otherCode := "ffffffffffffffffffffffffffffffff"
	cases := []struct {
		name string
		tok  string
		now  time.Time
		want bool
	}{
		{"owner's app, current", good, now, true},
		{"yesterday ok", Token(appKey, code, ownerFp, now.Add(-24*time.Hour)), now, true},
		{"tomorrow ok (skew)", Token(appKey, code, ownerFp, now.Add(24*time.Hour)), now, true},
		{"two days old rejected", Token(appKey, code, ownerFp, now.Add(-48*time.Hour)), now, false},
		// THE THIEF CASE: same code (decoded from the file), re-locked and signed with
		// the thief's own identity => the app computes the MAC with the thief's fp.
		{"re-locked under another creator", Token(appKey, code, thiefFp, now), now, false},
		{"right creator, wrong app key", Token([]byte("other-app"), code, ownerFp, now), now, false},
		{"code not on the allow-list", Token(appKey, otherCode, ownerFp, now), now, false},
		{"empty", "", now, false},
		{"garbage", "a.b.c", now, false},
		{"too few parts", CodeID(code) + "." + "20000", now, false},
		{"short mac", good[:len(good)-1], now, false},
		{"non-numeric day", CodeID(code) + ".abc." + strings.Repeat("0", 64), now, false},
	}
	for _, c := range cases {
		if got := Valid(c.tok, allow, appKeys, c.now); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
	}
}

func TestRevocationByRemovingTheLine(t *testing.T) {
	tok := Token(appKey, code, ownerFp, now)
	if !Valid(tok, allow, appKeys, now) {
		t.Fatal("should be valid while listed")
	}
	if Valid(tok, map[string]Entry{}, appKeys, now) {
		t.Fatal("must be rejected once the line is gone (all copies die at once)")
	}
}

func TestAppKeyRotation(t *testing.T) {
	old, cur := []byte("old"), []byte("new")
	both := [][]byte{cur, old}
	if !Valid(Token(old, code, ownerFp, now), allow, both, now) || !Valid(Token(cur, code, ownerFp, now), allow, both, now) {
		t.Fatal("both current and previous app key must be accepted")
	}
	if Valid(Token(old, code, ownerFp, now), allow, [][]byte{cur}, now) {
		t.Fatal("retired app key must be rejected")
	}
}

func TestNoKeysFailsClosed(t *testing.T) {
	if Valid(Token(appKey, code, ownerFp, now), allow, nil, now) {
		t.Fatal("with no app key configured nothing may pass")
	}
}

func TestKeyFileReload(t *testing.T) {
	path := t.TempDir() + "/keys.txt"
	os.WriteFile(path, []byte("# current\nkey-new\nkey-old # previous\n"), 0o600)
	kf, err := LoadKeyFile(path, [][]byte{[]byte("env-key")})
	if err != nil {
		t.Fatal(err)
	}
	got := kf.Get()
	if len(got) != 3 || string(got[0]) != "key-new" || string(got[1]) != "key-old" || string(got[2]) != "env-key" {
		t.Fatalf("%q", got)
	}
	os.WriteFile(path, []byte("key-newer\n"), 0o600)
	if err := kf.reload(); err != nil || len(kf.Get()) != 2 {
		t.Fatalf("%v %q", err, kf.Get())
	}
	// missing file is fine (env keys only)
	kf2, err := LoadKeyFile(t.TempDir()+"/nope", [][]byte{[]byte("e")})
	if err != nil || len(kf2.Get()) != 1 {
		t.Fatalf("%v", err)
	}
}

func TestParseAllowList(t *testing.T) {
	src := "# my locks\n" + code + " 3fa9-0c21-b7d4-9e10  channel A  # trailing\n\n"
	m, err := ParseAllowList(bufio.NewScanner(strings.NewReader(src)))
	if err != nil || len(m) != 1 {
		t.Fatalf("%v %v", m, err)
	}
	e := m[CodeID(code)]
	if e.CreatorFp != ownerFp || e.Note != "channel A" {
		t.Fatalf("%+v", e)
	}
	for _, bad := range []string{"short fp", code, "zz" + code[2:] + " " + ownerFp} {
		if _, err := ParseAllowList(bufio.NewScanner(strings.NewReader(bad))); err == nil {
			t.Errorf("should reject %q", bad)
		}
	}
}

func TestAllowListFileReload(t *testing.T) {
	path := t.TempDir() + "/allow.txt"
	os.WriteFile(path, []byte(code+" "+ownerFp+"\n"), 0o600)
	al, err := LoadAllowList(path)
	if err != nil || len(al.Get()) != 1 {
		t.Fatalf("%v", err)
	}
	// a bad edit must not wipe the list
	os.WriteFile(path, []byte("garbage line\n"), 0o600)
	if err := al.reload(); err == nil || len(al.Get()) != 1 {
		t.Fatal("bad edit must be rejected and the previous list kept")
	}
	os.WriteFile(path, []byte("# revoked\n"), 0o600)
	if err := al.reload(); err != nil || len(al.Get()) != 0 {
		t.Fatalf("%v %d", err, len(al.Get()))
	}
}

func startUpstream(t *testing.T) (*url.URL, chan http.Header) {
	t.Helper()
	seen := make(chan http.Header, 4)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen <- r.Header.Clone()
		if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
			// Minimal upgrade + echo, like an Xray ws inbound.
			hj := w.(http.Hijacker)
			c, buf, _ := hj.Hijack()
			defer c.Close()
			buf.WriteString("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
			buf.Flush()
			io.Copy(c, c)
			return
		}
		io.WriteString(w, "upstream-ok")
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	return u, seen
}

func TestRejectsWithoutTokenAndLooksLikeA404(t *testing.T) {
	up, seen := startUpstream(t)
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, func() time.Time { return now }))
	defer g.Close()

	for _, hdr := range []string{"", "garbage", Token([]byte("wrong"), code, ownerFp, now), Token(appKey, code, thiefFp, now)} {
		req, _ := http.NewRequest("GET", g.URL+"/ws", nil)
		if hdr != "" {
			req.Header.Set(Header, hdr)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 404 || strings.Contains(string(body), "upstream") {
			t.Fatalf("hdr %q: status %d body %q", hdr, resp.StatusCode, body)
		}
	}
	select {
	case <-seen:
		t.Fatal("upstream must never see a rejected request")
	default:
	}
}

func TestForwardsValidRequestAndStripsToken(t *testing.T) {
	up, seen := startUpstream(t)
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, func() time.Time { return now }))
	defer g.Close()

	req, _ := http.NewRequest("GET", g.URL+"/x", nil)
	req.Header.Set(Header, Token(appKey, code, ownerFp, now))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || string(body) != "upstream-ok" {
		t.Fatalf("status %d body %q", resp.StatusCode, body)
	}
	if h := <-seen; h.Get(Header) != "" {
		t.Fatal("token leaked to upstream")
	}
}

func TestWebSocketUpgradeAndStreaming(t *testing.T) {
	up, _ := startUpstream(t)
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, func() time.Time { return now }))
	defer g.Close()

	conn, err := net.Dial("tcp", strings.TrimPrefix(g.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	io.WriteString(conn, "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"+
		"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"+
		Header+": "+Token(appKey, code, ownerFp, now)+"\r\n\r\n")
	r := bufio.NewReader(conn)
	status, _ := r.ReadString('\n')
	if !strings.Contains(status, "101") {
		t.Fatalf("expected 101, got %q", status)
	}
	for { // skip headers
		l, _ := r.ReadString('\n')
		if l == "\r\n" || l == "" {
			break
		}
	}
	io.WriteString(conn, "ping-through-tunnel")
	buf := make([]byte, len("ping-through-tunnel"))
	if _, err := io.ReadFull(r, buf); err != nil || string(buf) != "ping-through-tunnel" {
		t.Fatalf("echo failed: %v %q", err, buf)
	}
}

func BenchmarkValid(b *testing.B) {
	tok := Token(appKey, code, ownerFp, now)
	for i := 0; i < b.N; i++ {
		Valid(tok, allow, appKeys, now)
	}
}
