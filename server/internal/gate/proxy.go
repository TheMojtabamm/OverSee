package gate

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

// Provider names which header carries the real client IP when the gate sits behind a CDN.
type Provider string

const (
	ProviderNone       Provider = ""           // not behind a CDN: the TCP peer is the client
	ProviderCloudflare Provider = "cloudflare" // CF-Connecting-IP
	ProviderFastly     Provider = "fastly"     // Fastly-Client-IP
	ProviderGeneric    Provider = "generic"    // X-Forwarded-For, rightmost entry not in the trusted list
)

func (p Provider) valid() bool {
	switch p {
	case ProviderNone, ProviderCloudflare, ProviderFastly, ProviderGeneric:
		return true
	}
	return false
}

// ParseProvider validates a user-supplied provider name.
func ParseProvider(s string) (Provider, error) {
	p := Provider(strings.ToLower(strings.TrimSpace(s)))
	if p == "none" {
		p = ProviderNone
	}
	if !p.valid() {
		return "", fmt.Errorf("unknown CDN %q (want none, cloudflare, fastly or generic)", s)
	}
	return p, nil
}

// TrustedProxies is a hot-reloadable set of CIDRs whose connections may carry a
// client-IP header. Headers from anyone else are ignored, so a client talking to the
// origin directly cannot pretend to be someone else (or dodge the limiter).
type TrustedProxies struct {
	path    string
	cur     atomic.Pointer[[]*net.IPNet]
	modTime time.Time
}

// ParseCIDRs reads one CIDR (or bare IP) per line; `#` starts a comment.
func ParseCIDRs(sc *bufio.Scanner) ([]*net.IPNet, error) {
	var out []*net.IPNet
	n := 0
	for sc.Scan() {
		n++
		line := strings.TrimSpace(sc.Text())
		if i := strings.Index(line, "#"); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		if line == "" {
			continue
		}
		if !strings.Contains(line, "/") { // bare IP => /32 or /128
			ip := net.ParseIP(line)
			if ip == nil {
				return nil, fmt.Errorf("line %d: %q is not an IP or CIDR", n, line)
			}
			if ip.To4() != nil {
				line += "/32"
			} else {
				line += "/128"
			}
		}
		_, nw, err := net.ParseCIDR(line)
		if err != nil {
			return nil, fmt.Errorf("line %d: %v", n, err)
		}
		out = append(out, nw)
	}
	return out, sc.Err()
}

func NewTrustedProxies(nets []*net.IPNet) *TrustedProxies {
	t := &TrustedProxies{}
	t.cur.Store(&nets)
	return t
}

// LoadTrustedProxies reads path; a missing file means an empty (nothing trusted) set.
func LoadTrustedProxies(path string) (*TrustedProxies, error) {
	t := &TrustedProxies{path: path}
	empty := []*net.IPNet{}
	t.cur.Store(&empty)
	if err := t.reload(); err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	return t, nil
}

func (t *TrustedProxies) reload() error {
	f, err := os.Open(t.path)
	if err != nil {
		return err
	}
	defer f.Close()
	st, _ := f.Stat()
	nets, err := ParseCIDRs(bufio.NewScanner(f))
	if err != nil {
		return err
	}
	t.cur.Store(&nets)
	if st != nil {
		t.modTime = st.ModTime()
	}
	return nil
}

func (t *TrustedProxies) Watch(every time.Duration, onErr func(error)) {
	go func() {
		for range time.Tick(every) {
			st, err := os.Stat(t.path)
			if err != nil || st.ModTime().Equal(t.modTime) {
				continue
			}
			if err := t.reload(); err != nil {
				onErr(err)
				t.modTime = st.ModTime()
			}
		}
	}()
}

func (t *TrustedProxies) Len() int { return len(*t.cur.Load()) }

// Contains reports whether ip is inside any trusted network.
func (t *TrustedProxies) Contains(ip net.IP) bool {
	if t == nil || ip == nil {
		return false
	}
	for _, n := range *t.cur.Load() {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

// ResolveClientIP returns the client's IP and whether the connection came through a
// trusted proxy. Rules:
//
//   - If the TCP peer is not a trusted proxy, headers are IGNORED and the peer is the client.
//   - Behind a trusted proxy, the provider's header is used (CF-Connecting-IP,
//     Fastly-Client-IP) or, for "generic", X-Forwarded-For read right-to-left skipping
//     trusted proxies (the leftmost entries are client-controlled and never trusted).
//   - A missing or malformed header falls back to the proxy's own IP (still "via proxy").
func ResolveClientIP(r *http.Request, tp *TrustedProxies, prov Provider) (ip string, viaProxy bool) {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	peer := net.ParseIP(host)
	if prov == ProviderNone || !tp.Contains(peer) {
		return host, false
	}
	switch prov {
	case ProviderCloudflare:
		if ip := parseSingleIP(r.Header.Get("CF-Connecting-IP")); ip != "" {
			return ip, true
		}
	case ProviderFastly:
		if ip := parseSingleIP(r.Header.Get("Fastly-Client-IP")); ip != "" {
			return ip, true
		}
	case ProviderGeneric:
		parts := strings.Split(strings.Join(r.Header.Values("X-Forwarded-For"), ","), ",")
		for i := len(parts) - 1; i >= 0; i-- {
			cand := net.ParseIP(strings.TrimSpace(parts[i]))
			if cand == nil {
				return host, true // garbage in the chain: don't guess
			}
			if !tp.Contains(cand) {
				return cand.String(), true
			}
		}
	}
	return host, true
}

func parseSingleIP(v string) string {
	v = strings.TrimSpace(v)
	if v == "" || strings.ContainsAny(v, ", ") {
		return ""
	}
	if ip := net.ParseIP(v); ip != nil {
		return ip.String()
	}
	return ""
}
