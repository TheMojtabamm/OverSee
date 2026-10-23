// Package gate is a tiny reverse proxy that sits in front of an Xray inbound and
// only lets through connections that prove three things at once:
//
//  1. the client is the Oversea app (it knows the app key),
//  2. it holds a per-lock secret code that this server's owner put on the
//     allow-list, and
//  3. the file it is running was signed by the creator that owns that code.
//
// All three are folded into one HMAC, so there is nothing to "mix and match":
//
//	token = <codeId>.<day>.hex( HMAC(appKey, "ovsea-gate-v2|"+code+"|"+creatorFp+"|"+day) )
//
// The server holds (code, creatorFp) per allow-list line and recomputes the MAC
// with its own copy of creatorFp. A thief who decodes a file and re-locks it in
// the Oversea app signs it with *their* identity, so the unmodified app computes
// the MAC with the thief's fingerprint and the server refuses it. Removing a line
// from the allow-list revokes that lock and every copy of it at once.
//
// The check runs once per connection (WebSocket / HTTPUpgrade handshake), not per
// packet; after it passes the bytes are copied straight through.
package gate

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

const (
	// Header the app sends.
	Header        = "X-Oversea-Auth"
	bucketSeconds = 86400 // UTC-day bucket; previous and next day also accepted
)

// Entry is one allow-list line: a lock's secret code and the creator it belongs to.
type Entry struct {
	Code      string // secret, 32 hex chars
	CreatorFp string // e.g. 3FA9-0C21-B7D4-9E10
	Note      string
}

// CodeID is the non-secret handle the client sends so the server can find the entry.
func CodeID(code string) string {
	h := sha256.Sum256([]byte("ovsea-code-id|" + code))
	return hex.EncodeToString(h[:8])
}

func mac(appKey []byte, code, fp string, day int64) string {
	m := hmac.New(sha256.New, appKey)
	m.Write([]byte("ovsea-gate-v2|" + code + "|" + fp + "|" + strconv.FormatInt(day, 10)))
	return hex.EncodeToString(m.Sum(nil))
}

// Token is what the app sends (the Dart side computes exactly this).
func Token(appKey []byte, code, fp string, t time.Time) string {
	day := t.UTC().Unix() / bucketSeconds
	return CodeID(code) + "." + strconv.FormatInt(day, 10) + "." + mac(appKey, code, fp, day)
}

// Valid reports whether tok is correct for an allow-listed entry and any app key.
func Valid(tok string, entries map[string]Entry, appKeys [][]byte, now time.Time) bool {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 || len(parts[2]) != 64 {
		return false
	}
	e, ok := entries[parts[0]]
	if !ok {
		return false
	}
	day, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return false
	}
	cur := now.UTC().Unix() / bucketSeconds
	if day < cur-1 || day > cur+1 {
		return false
	}
	good := false
	for _, k := range appKeys { // no early exit: constant work per key
		if hmac.Equal([]byte(mac(k, e.Code, e.CreatorFp, day)), []byte(parts[2])) {
			good = true
		}
	}
	return good
}

// ParseAllowList reads lines of `<code> <creatorFp> [note…]`; `#` starts a comment.
func ParseAllowList(r *bufio.Scanner) (map[string]Entry, error) {
	out := map[string]Entry{}
	n := 0
	for r.Scan() {
		n++
		line := strings.TrimSpace(r.Text())
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 2 || len(f[0]) != 32 || !isHex(f[0]) {
			return nil, fmt.Errorf("allow-list line %d: want `<32-hex code> <creator fingerprint>`", n)
		}
		out[CodeID(f[0])] = Entry{Code: f[0], CreatorFp: strings.ToUpper(f[1]), Note: strings.Join(f[2:], " ")}
	}
	return out, r.Err()
}

func isHex(s string) bool {
	_, err := hex.DecodeString(s)
	return err == nil
}

// AllowList is a file-backed allow-list that picks up edits without a restart, so
// revoking a lock is "delete the line".
type AllowList struct {
	path    string
	cur     atomic.Pointer[map[string]Entry]
	modTime time.Time
}

func LoadAllowList(path string) (*AllowList, error) {
	a := &AllowList{path: path}
	if err := a.reload(); err != nil {
		return nil, err
	}
	return a, nil
}

func (a *AllowList) reload() error {
	f, err := os.Open(a.path)
	if err != nil {
		return err
	}
	defer f.Close()
	st, _ := f.Stat()
	m, err := ParseAllowList(bufio.NewScanner(f))
	if err != nil {
		return err
	}
	a.cur.Store(&m)
	if st != nil {
		a.modTime = st.ModTime()
	}
	return nil
}

// Watch re-reads the file when it changes. A bad edit keeps the previous list.
func (a *AllowList) Watch(every time.Duration, onErr func(error)) {
	go func() {
		for range time.Tick(every) {
			st, err := os.Stat(a.path)
			if err != nil || st.ModTime().Equal(a.modTime) {
				continue
			}
			if err := a.reload(); err != nil {
				onErr(err)
				a.modTime = st.ModTime() // don't re-log the same bad edit
			}
		}
	}()
}

func (a *AllowList) Get() map[string]Entry { return *a.cur.Load() }

// New returns a handler that forwards valid requests to upstream and answers
// everything else with a plain 404, so a probe learns nothing about the service.
func New(upstream *url.URL, entries func() map[string]Entry, appKeys [][]byte) http.Handler {
	return newWithClock(upstream, entries, appKeys, time.Now)
}

func newWithClock(upstream *url.URL, entries func() map[string]Entry, appKeys [][]byte, now func() time.Time) http.Handler {
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(upstream)
			r.Out.Header.Del(Header) // do not leak the token to Xray
		},
		FlushInterval: -1, // stream immediately; never buffer a tunnel
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !Valid(r.Header.Get(Header), entries(), appKeys, now()) {
			http.NotFound(w, r)
			return
		}
		proxy.ServeHTTP(w, r)
	})
}
