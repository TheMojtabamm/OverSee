package oversee

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"oversea/server/internal/gate"
)

// CDNTest asks the running gate, THROUGH the public URL (so through the CDN), what the
// request looked like on arrival. It answers the questions that decide whether the lock
// works behind a CDN: does the token arrive intact, on a normal request and on a
// WebSocket upgrade, and does the gate see the real client IP from a trusted edge?
//
// baseURL is e.g. https://vpn.example.com (default: https://<domain from settings>).
func (p Paths) CDNTest(ctx context.Context, baseURL string, client *http.Client) ([]Finding, error) {
	s := p.LoadSettings()
	if baseURL == "" {
		if s.Domain == "" {
			return nil, fmt.Errorf("no domain configured: oversee set domain vpn.example.com (or pass --url)")
		}
		baseURL = "https://" + s.Domain
	}
	baseURL = strings.TrimRight(baseURL, "/")
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}

	// One-time nonce, valid for a few minutes: the probe URL doesn't exist otherwise.
	nonce := RandomHex(16)
	if err := os.MkdirAll(p.Dir, 0o750); err != nil {
		return nil, err
	}
	body := fmt.Sprintf("%s %d\n", nonce, time.Now().Add(5*time.Minute).Unix())
	if err := writeAtomic(p.Probe, []byte(body), 0o640); err != nil {
		return nil, err
	}
	defer os.Remove(p.Probe)

	var out []Finding
	add := func(l Level, title, detail, fix string) { out = append(out, Finding{l, title, detail, fix}) }

	// Same shape as the token the app sends (day.mac-ish length), but obviously a test value.
	token := "cdntest." + RandomHex(24)
	want := gate.HeaderDigest(token)

	for _, mode := range []struct {
		name    string
		upgrade bool
	}{{"normal request", false}, {"WebSocket upgrade", true}} {
		req, err := http.NewRequestWithContext(ctx, "GET", baseURL+gate.ProbePath+nonce, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set(gate.Header, token)
		if mode.upgrade {
			req.Header.Set("Connection", "Upgrade")
			req.Header.Set("Upgrade", "websocket")
			req.Header.Set("Sec-WebSocket-Version", "13")
			req.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
		}
		resp, err := client.Do(req)
		if err != nil {
			add(Fail, mode.name+": request failed", err.Error(), "is the gate running and reachable at "+baseURL+" ? (oversee doctor)")
			continue
		}
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
		resp.Body.Close()
		var rep gate.ProbeReport
		if resp.StatusCode != 200 || json.Unmarshal(raw, &rep) != nil || !rep.OK {
			add(Fail, mode.name+": the gate did not answer the probe",
				fmt.Sprintf("HTTP %d from %s — the CDN may be caching/blocking the path, pointing at a different origin, or the gate isn't the one behind this URL", resp.StatusCode, baseURL),
				"check the CDN's origin settings and that this gate is running with the same config directory")
			continue
		}
		switch {
		case !rep.HeaderPresent:
			add(Fail, mode.name+": the token was STRIPPED", "the token never reached the gate, so locked files can't connect through this CDN",
				"remove any CDN rule that drops unknown request data (Fastly VCL / Cloudflare Transform Rules); if you can't, tell me and I'll add a query-string carrier")
		case rep.HeaderSHA256 != want || rep.HeaderLen != len(token):
			add(Fail, mode.name+": the token was ALTERED in transit", fmt.Sprintf("sent %d bytes, gate received %d", len(token), rep.HeaderLen), "look for rewriting rules on the CDN")
		default:
			add(OK, mode.name+": token arrived intact", fmt.Sprintf("%d bytes, hash matches", rep.HeaderLen), "")
		}
		if mode.upgrade {
			continue
		}
		// Client IP / trust (checked once).
		switch {
		case s.CDN == "":
			add(OK, "Direct mode", "no CDN configured; the gate sees the connecting address "+rep.ClientIP, "")
		case !rep.ViaTrustedCDN:
			add(Fail, "The request did not come from a trusted CDN range",
				fmt.Sprintf("the gate saw peer %s", rep.Peer),
				"oversee proxies update (ranges may be old); if you aren't actually behind "+s.CDN+", run: oversee set cdn none")
		default:
			add(OK, "Real client IP is visible", fmt.Sprintf("the gate sees %s (peer %s is a trusted %s edge)", rep.ClientIP, rep.Peer, s.CDN), "")
		}
	}
	return out, nil
}
