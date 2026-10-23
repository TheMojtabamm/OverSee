package gate

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

var (
	key  = []byte("test-key-0123456789")
	now  = time.Date(2026, 10, 23, 12, 0, 0, 0, time.UTC)
	keys = [][]byte{key}
)

// Fixed vector shared with the Dart test (test/gate_token_test.dart). If either
// side changes the construction, both tests fail.
func TestTokenVector(t *testing.T) {
	got := Token([]byte("vector-key"), time.Unix(86400*20000, 0))
	const want = "20000.b323d70d7f74fe7b5643d0abe27153bb5ecfb4e931781f6797ac71860cea7d07"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}

func TestValid(t *testing.T) {
	good := Token(key, now)
	cases := []struct {
		name string
		tok  string
		now  time.Time
		want bool
	}{
		{"current", good, now, true},
		{"yesterday's token still ok", Token(key, now.Add(-24*time.Hour)), now, true},
		{"tomorrow's token ok (skew)", Token(key, now.Add(24*time.Hour)), now, true},
		{"two days old rejected", Token(key, now.Add(-48*time.Hour)), now, false},
		{"two days ahead rejected", Token(key, now.Add(48*time.Hour)), now, false},
		{"wrong key", Token([]byte("other"), now), now, false},
		{"empty", "", now, false},
		{"no dot", strings.ReplaceAll(good, ".", ""), now, false},
		{"short sig", good[:len(good)-1], now, false},
		{"non-numeric day", "abc." + strings.Repeat("0", 64), now, false},
		{"day swapped, sig reused", "1." + good[strings.Index(good, ".")+1:], now, false},
	}
	for _, c := range cases {
		if got := Valid(c.tok, keys, c.now); got != c.want {
			t.Errorf("%s: got %v want %v", c.name, got, c.want)
		}
	}
}

func TestKeyRotation(t *testing.T) {
	old, cur := []byte("old"), []byte("new")
	both := [][]byte{cur, old}
	if !Valid(Token(old, now), both, now) || !Valid(Token(cur, now), both, now) {
		t.Fatal("both current and previous key must be accepted")
	}
	if Valid(Token(old, now), [][]byte{cur}, now) {
		t.Fatal("retired key must be rejected")
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
	g := httptest.NewServer(newWithClock(up, keys, func() time.Time { return now }))
	defer g.Close()

	for _, hdr := range []string{"", "garbage", Token([]byte("wrong"), now)} {
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
	g := httptest.NewServer(newWithClock(up, keys, func() time.Time { return now }))
	defer g.Close()

	req, _ := http.NewRequest("GET", g.URL+"/x", nil)
	req.Header.Set(Header, Token(key, now))
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
	g := httptest.NewServer(newWithClock(up, keys, func() time.Time { return now }))
	defer g.Close()

	conn, err := net.Dial("tcp", strings.TrimPrefix(g.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(5 * time.Second))
	io.WriteString(conn, "GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"+
		"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"+
		Header+": "+Token(key, now)+"\r\n\r\n")
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
	tok := Token(key, now)
	for i := 0; i < b.N; i++ {
		Valid(tok, keys, now)
	}
}
