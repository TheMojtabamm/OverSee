package gate

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
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
	appKey = []byte("test-app-key-0123456789")
	// Today at noon UTC: reject counters use the real clock, so a fixed date breaks the day after.
	now     = time.Now().UTC().Truncate(24 * time.Hour).Add(12 * time.Hour)
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
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, Options{}, func() time.Time { return now }))
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
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, Options{}, func() time.Time { return now }))
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
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, Options{}, func() time.Time { return now }))
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

func TestCheckReasons(t *testing.T) {
	good := Token(appKey, code, ownerFp, now)
	cases := []struct {
		tok  string
		want Result
	}{
		{good, OK},
		{"", NoToken},
		{"x.y", BadFormat},
		{Token(appKey, "ffffffffffffffffffffffffffffffff", ownerFp, now), UnknownCode},
		{Token(appKey, code, ownerFp, now.Add(-72*time.Hour)), BadDay},
		{Token(appKey, code, thiefFp, now), BadMAC},
	}
	for _, c := range cases {
		if got, _ := Check(c.tok, allow, appKeys, now); got != c.want {
			t.Errorf("%q: got %v want %v", c.tok, got, c.want)
		}
	}
	if r, id := Check(good, allow, appKeys, now); r != OK || id != CodeID(code) {
		t.Fatal(r, id)
	}
}

func TestLimiterBlocksAfterRepeatedFailuresAndRecovers(t *testing.T) {
	l := NewLimiter(3, time.Minute, 10*time.Minute)
	ip := "203.0.113.9"
	for i := 0; i < 2; i++ {
		l.Fail(ip, now)
		if l.Blocked(ip, now) {
			t.Fatal("blocked too early")
		}
	}
	l.Fail(ip, now)
	if !l.Blocked(ip, now) {
		t.Fatal("should be blocked after 3 failures")
	}
	if l.Blocked("198.51.100.1", now) {
		t.Fatal("other IPs unaffected")
	}
	if !l.Blocked(ip, now.Add(9*time.Minute)) || l.Blocked(ip, now.Add(11*time.Minute)) {
		t.Fatal("block must last exactly BlockFor")
	}
	// failures spread beyond the window never accumulate
	l2 := NewLimiter(3, time.Minute, time.Hour)
	for i := 0; i < 10; i++ {
		l2.Fail(ip, now.Add(time.Duration(i)*2*time.Minute))
	}
	if l2.Blocked(ip, now.Add(30*time.Minute)) {
		t.Fatal("slow failures must not trigger a block")
	}
}

func TestHandlerLimiterStatsAndNeverBlocksALegitClientBehindFailures(t *testing.T) {
	up, _ := startUpstream(t)
	st := NewStats()
	lim := NewLimiter(3, time.Minute, time.Hour)
	g := httptest.NewServer(newWithClock(up, list, func() [][]byte { return appKeys }, Options{Limiter: lim, Stats: st}, func() time.Time { return now }))
	defer g.Close()

	get := func(tok string) int {
		req, _ := http.NewRequest("GET", g.URL+"/x", nil)
		if tok != "" {
			req.Header.Set(Header, tok)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	good := Token(appKey, code, ownerFp, now)
	if get(good) != 200 || get(good) != 200 {
		t.Fatal("valid token must pass")
	}
	for i := 0; i < 3; i++ {
		if get("bad") != 404 {
			t.Fatal("bad token must 404")
		}
	}
	// the IP is now blocked for bad tokens: more bad ones stay refused...
	if get("bad") != 404 {
		t.Fatal("blocked IP must keep being refused for bad tokens")
	}
	// ...but a valid token still passes (honest users share IPs behind CGNAT)
	if get(good) != 200 {
		t.Fatal("a valid token must pass even from a blocked IP")
	}
	sn := st.Snapshot(now)
	if len(sn.Locks) != 1 || sn.Locks[0].Accepted != 3 || sn.Locks[0].DistinctIPs != 1 {
		t.Fatalf("%+v", sn.Locks)
	}
	if sn.Rejects["bad_format"] != 3 && sn.Rejects["bad_format"]+sn.Rejects["no_token"] != 3 {
		t.Fatalf("%v", sn.Rejects)
	}
	if sn.Rejects["blocked"] != 1 {
		t.Fatalf("%v", sn.Rejects)
	}
}

func TestStatsDistinctIPsAndDayRollover(t *testing.T) {
	st := NewStats()
	for i := 0; i < 50; i++ {
		st.accept("aaaa", "10.0.0."+itoa(i%10), now) // 10 distinct IPs, 50 connections
	}
	sn := st.Snapshot(now)
	if sn.Locks[0].Accepted != 50 || sn.Locks[0].DistinctIPs != 10 {
		t.Fatalf("%+v", sn.Locks[0])
	}
	if got := st.Snapshot(now.Add(25 * time.Hour)); len(got.Locks) != 0 {
		t.Fatal("counters must reset each UTC day")
	}
}

func itoa(i int) string { return strconv.Itoa(i) }

func TestStatsFileDoesNotContainIPs(t *testing.T) {
	st := NewStats()
	st.accept("aaaa", "203.0.113.77", now)
	path := t.TempDir() + "/stats.json"
	if err := st.WriteOnce(path); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(path)
	if strings.Contains(string(b), "203.0.113.77") {
		t.Fatal("raw IPs must never be written to disk")
	}
	sn, err := ReadSnapshot(path)
	if err != nil || len(sn.Locks) != 1 || sn.Locks[0].DistinctIPs != 1 {
		t.Fatalf("%v %+v", err, sn)
	}
}
