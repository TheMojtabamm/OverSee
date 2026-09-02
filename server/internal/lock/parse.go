package lock

import (
	"strings"
)

// ConfigMeta holds the display metadata extracted from a raw config string so
// a locked blob can show useful public info (title/protocol/host) without
// revealing the raw config itself.
type ConfigMeta struct {
	Protocol string
	Title    string
	Host     string
}

// ParseConfigMeta extracts protocol, host and a display title from common
// URL-style config strings (vless://, vmess://, ss://, trojan://, ...). It
// never parses secrets; it only reads the public scheme/host/remark fields.
func ParseConfigMeta(raw string) ConfigMeta {
	raw = strings.TrimSpace(raw)
	m := ConfigMeta{}

	// Determine protocol from the URI scheme.
	if i := strings.Index(raw, "://"); i > 0 {
		m.Protocol = strings.ToLower(raw[:i])
	} else if strings.HasPrefix(raw, "ss-") {
		m.Protocol = "shadowsocks"
	} else {
		m.Protocol = "unknown"
	}

	// Extract host:port from the segment right after the scheme (and after any
	// userinfo like uuid@ or base64@).
	rest := raw
	if strings.Contains(rest, "://") {
		rest = rest[strings.Index(rest, "://")+3:]
	}
	// Strip query/fragment for host derivation.
	if i := strings.IndexAny(rest, "?#"); i >= 0 {
		rest = rest[:i]
	}
	// Strip userinfo@
	if at := strings.Index(rest, "@"); at >= 0 {
		rest = rest[at+1:]
	}
	// Take host part before first '/'
	if i := strings.Index(rest, "/"); i >= 0 {
		rest = rest[:i]
	}
	// Strip trailing ':port'
	if i := strings.LastIndex(rest, ":"); i > 0 && !strings.Contains(rest[i:], "[") {
		rest = rest[:i]
	}
	m.Host = rest

	// Title: from '#remark' fragment or 'name=' query param at the very end.
	title := ""
	if h := strings.Index(raw, "#"); h >= 0 {
		title = raw[h+1:]
	}
	if title == "" {
		// try common 'name='/'remark=' query params
		title = queryParam(raw, "name")
		if title == "" {
			title = queryParam(raw, "remark")
		}
	}
	m.Title = strings.TrimSpace(title)
	return m
}

// queryParam extracts a URL query parameter value (URL-decoded).
func queryParam(raw, key string) string {
	q := raw
	if i := strings.Index(q, "?"); i >= 0 {
		q = q[i+1:]
	} else {
		return ""
	}
	// strip fragment
	if i := strings.Index(q, "#"); i >= 0 {
		q = q[:i]
	}
	for _, pair := range strings.Split(q, "&") {
		kv := strings.SplitN(pair, "=", 2)
		if len(kv) == 2 && kv[0] == key {
			// minimal percent-decode for the value
			v := strings.ReplaceAll(kv[1], "%20", " ")
			v = strings.ReplaceAll(v, "+", " ")
			return v
		}
	}
	return ""
}
