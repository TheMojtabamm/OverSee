// Package gate is a tiny reverse proxy that sits in front of an Xray inbound and
// only lets through connections that carry a valid Oversea client token.
//
// Why: a locked config file can always be opened by the app, so anybody who
// decodes one gets a plain vless:// link. Behind this gate that link is useless in
// any other client, because the server refuses connections that lack the
// time-based token only the Oversea app can compute.
//
// The check runs once per connection (WebSocket / HTTPUpgrade handshake), not per
// packet; after it passes the bytes are copied straight through.
package gate

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	// Header the app sends.
	Header = "X-Oversea-Auth"
	// Token validity is a UTC-day bucket; the previous and next day are accepted
	// too, which covers clock skew and connections that reconnect around midnight.
	bucketSeconds = 86400
)

// Token returns "<day>.<hex hmac>" for the given key at time t. The Dart client
// computes exactly this (lib/domain/gate_token.dart); the shared vectors in the
// tests of both sides keep them in lockstep.
func Token(key []byte, t time.Time) string {
	day := t.UTC().Unix() / bucketSeconds
	return strconv.FormatInt(day, 10) + "." + mac(key, day)
}

func mac(key []byte, day int64) string {
	m := hmac.New(sha256.New, key)
	m.Write([]byte("ovsea-gate-v1|" + strconv.FormatInt(day, 10)))
	return hex.EncodeToString(m.Sum(nil))
}

// Valid reports whether tok is a correct token for any of keys within one day of now.
func Valid(tok string, keys [][]byte, now time.Time) bool {
	dayStr, sig, ok := strings.Cut(tok, ".")
	if !ok || len(sig) != 64 {
		return false
	}
	day, err := strconv.ParseInt(dayStr, 10, 64)
	if err != nil {
		return false
	}
	cur := now.UTC().Unix() / bucketSeconds
	if day < cur-1 || day > cur+1 {
		return false
	}
	good := false
	for _, k := range keys { // no early exit: constant work per key
		if hmac.Equal([]byte(mac(k, day)), []byte(sig)) {
			good = true
		}
	}
	return good
}

// New returns a handler that forwards valid requests to upstream and answers
// everything else with a plain 404, so a probe learns nothing about the service.
func New(upstream *url.URL, keys [][]byte) http.Handler {
	return newWithClock(upstream, keys, time.Now)
}

func newWithClock(upstream *url.URL, keys [][]byte, now func() time.Time) http.Handler {
	proxy := &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(upstream)
			r.Out.Header.Del(Header) // do not leak the token to Xray
		},
		FlushInterval: -1, // stream immediately; never buffer a tunnel
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !Valid(r.Header.Get(Header), keys, now()) {
			http.NotFound(w, r)
			return
		}
		proxy.ServeHTTP(w, r)
	})
}
