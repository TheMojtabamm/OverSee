package oversee

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// Official, public IP-range endpoints. Variables so tests can point them at a local server.
var providerURLs = map[string][]string{
	"cloudflare": {"https://www.cloudflare.com/ips-v4", "https://www.cloudflare.com/ips-v6"},
	"fastly":     {"https://api.fastly.com/public-ip-list"},
}

// A list shorter than this is treated as a failed/garbled download and never replaces the
// current one (an empty trust list would silently lock every user out in only-proxy mode).
var minRanges = map[string]int{"cloudflare": 10, "fastly": 10}

// ParseProviderList reads one provider's response body into CIDRs. Cloudflare serves plain
// text (one CIDR per line); Fastly serves JSON {"addresses":[...],"ipv6_addresses":[...]}.
func ParseProviderList(provider string, body []byte) ([]string, error) {
	var out []string
	switch provider {
	case "cloudflare":
		sc := bufio.NewScanner(strings.NewReader(string(body)))
		for sc.Scan() {
			if l := strings.TrimSpace(sc.Text()); l != "" {
				out = append(out, l)
			}
		}
	case "fastly":
		var j struct {
			V4 []string `json:"addresses"`
			V6 []string `json:"ipv6_addresses"`
		}
		if err := json.Unmarshal(body, &j); err != nil {
			return nil, fmt.Errorf("fastly list is not the expected JSON: %w", err)
		}
		out = append(append(out, j.V4...), j.V6...)
	default:
		return nil, fmt.Errorf("no automatic list for %q (use `generic` with your own proxies.txt)", provider)
	}
	for _, c := range out {
		if _, _, err := net.ParseCIDR(c); err != nil {
			return nil, fmt.Errorf("provider returned something that is not a CIDR: %q", c)
		}
	}
	return out, nil
}

// FetchProviderList downloads and validates the current ranges.
func FetchProviderList(ctx context.Context, provider string, client *http.Client) ([]string, error) {
	urls, ok := providerURLs[provider]
	if !ok {
		return nil, fmt.Errorf("no automatic list for %q", provider)
	}
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	var all []string
	for _, u := range urls {
		req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
		if err != nil {
			return nil, err
		}
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		if err != nil {
			return nil, err
		}
		if resp.StatusCode != 200 {
			return nil, fmt.Errorf("%s: HTTP %d", u, resp.StatusCode)
		}
		part, err := ParseProviderList(provider, body)
		if err != nil {
			return nil, err
		}
		all = append(all, part...)
	}
	if len(all) < minRanges[provider] {
		return nil, fmt.Errorf("%s returned only %d ranges; keeping the current list", provider, len(all))
	}
	return all, nil
}

// UpdateProxies refreshes proxies.txt from the provider. The file is only replaced when the
// download is complete and valid.
func (p Paths) UpdateProxies(ctx context.Context, provider string, client *http.Client) (int, error) {
	ranges, err := FetchProviderList(ctx, provider, client)
	if err != nil {
		return 0, err
	}
	body := fmt.Sprintf("# %s IP ranges, fetched %s by `oversee proxies update`\n%s\n",
		provider, time.Now().UTC().Format("2006-01-02 15:04 UTC"), strings.Join(ranges, "\n"))
	if err := writeAtomic(p.Proxies, []byte(body), 0o640); err != nil {
		return 0, err
	}
	return len(ranges), nil
}

// ProxyListInfo describes the current file for the UI.
type ProxyListInfo struct {
	Count int
	Age   time.Duration // -1 when the file doesn't exist
}

func (p Paths) ProxyInfo() ProxyListInfo {
	st, err := statFile(p.Proxies)
	if err != nil {
		return ProxyListInfo{Age: -1}
	}
	lines, _ := readLines(p.Proxies)
	n := 0
	for _, l := range lines {
		if l = strings.TrimSpace(l); l != "" && !strings.HasPrefix(l, "#") {
			n++
		}
	}
	return ProxyListInfo{Count: n, Age: time.Since(st)}
}

var errNoProvider = errors.New("choose a CDN first (cloudflare or fastly)")

// ValidCDN reports whether s is a CDN mode the gate understands.
func ValidCDN(s string) bool {
	switch s {
	case "", "none", "cloudflare", "fastly", "generic":
		return true
	}
	return false
}

// NextCDN cycles the mode in the TUI.
func NextCDN(cur string) string {
	order := []string{"", "cloudflare", "fastly", "generic"}
	for i, o := range order {
		if o == cur || (cur == "none" && o == "") {
			return order[(i+1)%len(order)]
		}
	}
	return ""
}
