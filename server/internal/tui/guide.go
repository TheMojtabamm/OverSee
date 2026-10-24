package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// The Guide tab: how to set the gate up for each kind of config. Written as lines with a tiny
// markup: "# heading", "$ command", "! warning", "✓ good news", "- bullet", blank, or plain text.
type guideTopic struct {
	short string // in the topic list
	title string // heading of the page
	body  string
}

var guideTopics = []guideTopic{
	{"How it works", "How it works", `# The picture
The phone connects to the GATE (ports 80/443 on your server). The gate checks a secret header from the Oversea app and only then passes the connection to Xray, which listens on 127.0.0.1:10000 and is not reachable from outside.
- With a CDN:   phone → Cloudflare/Fastly → gate → Xray
- Without CDN:  phone → gate → Xray

# Six steps, whatever your setup
- 1. Install: curl -fsSL https://github.com/themojtabamm/OverSee/releases/download/server-latest/install.sh | sudo bash
- 2. Keys tab: add the GATE_KEY your app was built with (n)
- 3. Choose how clients reach the gate: topics 2, 3, 4 or 5 of this guide
- 4. Put the Xray inbound behind the gate: topic 6 (Setup tab prints one)
- 5. In the app: Share → Locked file → Server gate. Paste the line it shows into the Locks tab (a)
- 6. Run  oversee doctor  : every red line is something that makes the lock pointless

! The gate and Xray must NOT both listen publicly. If Xray is reachable directly, nobody needs the gate. Xray must listen on 127.0.0.1.`},

	{"Ports (entry vs Xray)", "Ports: where clients connect vs where Xray listens", `# Two different ports — do not mix them up
- ENTRY port = the port the GATE listens on. Clients (or the CDN) connect here.
- XRAY port = the port of the inbound you create in Xray / 3x-ui. Only the gate talks to it, on 127.0.0.1.
They must be different numbers.

# Set them in this tool
- Setup tab, key p: entry port (e.g. 8080).
- Setup tab, key m: switch the entry between TLS and plain HTTP.
- Setup tab, key u: the Xray port (e.g. 10000). Create the 3x-ui inbound with exactly that port.
- The same from the shell:
$ sudo oversee set plain :8080          entry = plain HTTP on 8080
$ sudo oversee set port 8443            entry = TLS on 8443 (needs a certificate file)
$ sudo oversee set upstream 10000       Xray inbound port

# Typical combinations
- Cloudflare, Flexible, entry 8080 plain, Xray 10000. Clients still use 443 + TLS (Cloudflare adds the TLS).
- Cloudflare, Full (strict), entry 443 TLS with an Origin certificate, Xray 10000.
- No CDN, Let's Encrypt: entry 443 TLS, Xray 10000.
- No CDN, no TLS: entry 1001 plain, Xray 10000; clients connect to 1001 with security=none.

! Cloudflare only forwards certain ports. HTTP: 80, 8080, 8880, 2052, 2082, 2086, 2095. HTTPS: 443, 2053, 2083, 2087, 2096, 8443. oversee doctor warns about any other port.
! Free the port first: 3x-ui's own panel or another service must not already use the entry port.`},

	{"Direct + TLS", "Direct + TLS (no CDN)", `# Use this when clients connect straight to your server's IP with your own domain.
- 1. DNS: an A record  vpn.example.com → your server IP. If the domain is on Cloudflare, make the cloud GREY (DNS only).
- 2. Open ports 80 and 443 in the firewall (port 80 is only for the certificate check).
- 3. Tell the gate the domain; it gets a free Let's Encrypt certificate by itself:
$ sudo oversee set domain vpn.example.com
$ sudo systemctl restart oversee-gate
- 4. Xray: WebSocket inbound on 127.0.0.1:10000, security none (topic 6).
- 5. Client link:
$ vless://UUID@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&type=ws&host=vpn.example.com&path=%2Fws
- 6. sudo oversee doctor

✓ TLS is real here: the phone ↔ server traffic is encrypted.
! Let's Encrypt cannot reach a server hidden behind an orange-cloud CDN. For that, use topic 3.`},

	{"CDN (Cloudflare)", "Behind a CDN (Cloudflare)", `# Large channels hide the server behind a CDN. The gate supports it, but the CDN must carry WebSockets and keep the X-Oversea-Auth header.
- 1. Cloudflare DNS: A record vpn.example.com → your IP, cloud ORANGE (proxied).
- 2. Cloudflare → SSL/TLS → mode "Full (strict)".
- 3. Cloudflare → SSL/TLS → Origin Server → Create Certificate (RSA, 15 years). Save the two files on the server:
$ /etc/oversea/origin.pem   (certificate)
$ /etc/oversea/origin.key   (private key)
$ sudo chmod 640 /etc/oversea/origin.key
- 4. Tell the gate (one block):
$ sudo oversee set domain vpn.example.com
$ sudo oversee set cdn cloudflare
$ sudo oversee proxies update
$ sudo oversee set cert /etc/oversea/origin.pem
$ sudo oversee set key /etc/oversea/origin.key
$ sudo oversee set only-proxy on
$ sudo systemctl restart oversee-gate
- 5. Check that the CDN really passes the secret header (it fails loudly if it does not):
$ sudo oversee cdn-test
- 6. Client link: address = your domain, port 443, TLS on, sni and host = your domain:
$ vless://UUID@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&type=ws&host=vpn.example.com&path=%2Fws

# Good to know
- only-proxy makes the gate refuse anything that did not come through the CDN, so the origin IP is useless to scanners.
- Cloudflare proxies HTTPS on 443, 2053, 2083, 2087, 2096, 8443.
- WebSockets are on by default in Cloudflare (Network tab). Fastly: enable WebSocket support and make sure your VCL does not strip or cache X-Oversea-Auth.
! A CDN can suspend accounts that carry VPN traffic. Read its terms.`},

	{"CDN, no certificate", "CDN without a certificate (Flexible)", `# Cloudflare "Flexible": the CDN talks HTTPS to the phone and plain HTTP to your server. No certificate on your server.
- 1. Cloudflare DNS: orange cloud. SSL/TLS mode: "Flexible".
- 2. Gate in plain mode on a port Cloudflare proxies over HTTP: 80, 8080, 8880, 2052, 2082, 2086, 2095.
$ sudo oversee set cdn cloudflare
$ sudo oversee proxies update
$ sudo oversee set plain :80
$ sudo oversee set only-proxy on
$ sudo systemctl restart oversee-gate
- 3. Client link: the phone still uses TLS to Cloudflare, port 443:
$ vless://UUID@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&type=ws&host=vpn.example.com&path=%2Fws
- 4. sudo oversee cdn-test

! Between Cloudflare and your server the traffic is NOT encrypted. Prefer topic 3 (Origin certificate) when you can.`},

	{"No TLS (plain)", "No TLS at all (plain)", `# Plain WebSocket, like  vless://…@host:1001?security=none&type=ws  — many panels hand these out.
The gate can sit in front of it too: it just listens in plain HTTP on the port your clients already use.
- 1. Move Xray to 127.0.0.1:10000 (ws, security none).
- 2. Let the gate take the public port, e.g. 1001:
$ sudo oversee set plain :1001
$ sudo systemctl restart oversee-gate
- 3. Clients keep the same kind of link; only the secret header is new:
$ vless://UUID@vpn.example.com:1001?encryption=none&security=none&type=ws&host=vpn.example.com&path=%2Fws
- 4. Lock it in the app (Share → Locked file → Server gate) and add the line in the Locks tab.

! Nothing is encrypted between the phone and the server: anyone on the path (ISP, Wi-Fi owner) can read the traffic. The app marks such configs "Not encrypted". The gate still stops decoded links from working elsewhere, but it cannot hide the traffic.
- Use this only if TLS is impossible. Port 80/443 are not required in this mode (no Let's Encrypt).`},

	{"Own certificate", "Your own certificate", `# Any certificate works: certbot, Cloudflare Origin CA, a purchased one, or your own CA.
- 1. Put two PEM files on the server, readable by the gate (the service user "oversee"):
$ /etc/oversea/fullchain.pem
$ /etc/oversea/privkey.pem
$ sudo chown root:oversee /etc/oversea/*.pem && sudo chmod 640 /etc/oversea/privkey.pem
- 2. Tell the gate:
$ sudo oversee set cert /etc/oversea/fullchain.pem
$ sudo oversee set key /etc/oversea/privkey.pem
$ sudo systemctl restart oversee-gate
- 3. The client link's sni must match a name on the certificate.

# certbot (standalone) example
$ sudo systemctl stop oversee-gate
$ sudo certbot certonly --standalone -d vpn.example.com
$ sudo cp /etc/letsencrypt/live/vpn.example.com/fullchain.pem /etc/oversea/
$ sudo cp /etc/letsencrypt/live/vpn.example.com/privkey.pem /etc/oversea/
$ sudo systemctl start oversee-gate
(After each renewal copy the files again and restart the gate. Using  oversee set domain  instead renews by itself.)

# Self-signed
Works only if every client skips verification (allowInsecure=1), which also removes protection against interception. Fine for a test, not for real users.
! oversee doctor warns when the certificate is about to expire.`},

	{"Xray + links", "Xray inbound + links", `# Xray (or 3x-ui) inbound that sits behind the gate. Fields in 3x-ui "Add inbound":
- Protocol: vless      Listen IP: 127.0.0.1      Port: 10000
- Transmission: WebSocket      Path: /ws (any path; it goes in the link)
- Security: None   (the gate does TLS, not Xray)
- Client: one UUID, flow empty
! Never leave Listen IP empty or 0.0.0.0: the gate would be bypassed. Move 3x-ui's own panel off ports 80/443 so the gate can use them.

# The Setup tab prints a ready inbound and a matching link with a fresh UUID.

# Link templates (UUID and path are yours)
- Direct TLS or CDN:
$ vless://UUID@vpn.example.com:443?encryption=none&security=tls&sni=vpn.example.com&type=ws&host=vpn.example.com&path=%2Fws
- Plain (no TLS) on port 1001:
$ vless://UUID@vpn.example.com:1001?encryption=none&security=none&type=ws&host=vpn.example.com&path=%2Fws

# Transports the gate can protect
- WebSocket and HTTPUpgrade: yes (they carry the secret header).
- Reality over plain TCP, gRPC, XHTTP: no. The app refuses to lock those as "gated".`},

	{"Check & fix", "Check & fix", `# Always start here
$ sudo oversee doctor        what is wrong with this setup
$ sudo oversee cdn-test      does the CDN keep the secret header
$ sudo oversee status        service state and counts
$ sudo journalctl -u oversee-gate -n 50    recent gate log (Logs tab shows it too)

# Symptoms
- Every connection refused: no app key (Keys tab), or the lock's line is not in the Locks tab yet.
- Works for a day, then stops: the phone's clock or token window. Try  sudo oversee set token-days 3  and check the phone's date/time.
- Refused for ten minutes after testing with plain links: the per-IP block. A valid lock still passes; to switch the block off for good:  sudo oversee set ip-limit off  then restart the gate.
- A config got copied around (a bot hands out a ready-made config): cap the IPs per lock with  sudo oversee set lock-ips 5  (0 = no cap). A shared token then works for the first 5 IPs of the day only; revoke the lock and issue a new file.
- Works without CDN, fails with CDN: run cdn-test. It tells you if the header is stripped or the real client IP is not visible.
- "Refused" counters rise in the Locks tab: someone is probing with a decoded or re-locked config. That is the gate doing its job.
- A lock is used from many IPs ("shared?"): revoke it (Locks → d) and issue a new file.
- Phone connects but nothing loads: Xray is not on 127.0.0.1:10000, or its outbound is blocked. Check Xray's own log.

# Revoking
Locks tab → d. Every copy of that lock stops working within seconds, including the real app.`},
}

// guideHeight is how many lines of the guide fit on screen.
func (m Model) guideHeight() int {
	if m.h <= 0 {
		return 40
	}
	return max(8, m.h-16)
}

// renderGuideBody turns the markup into styled, wrapped lines for a column of width w.
func renderGuideBody(body string, w int) []string {
	var out []string
	text := lipgloss.NewStyle().Foreground(bright)
	wrap := func(st lipgloss.Style, first, hang, s string) {
		block := lipgloss.NewStyle().Width(max(10, w-lipgloss.Width(first))).Render(s)
		for i, l := range strings.Split(block, "\n") {
			l = st.Render(strings.TrimRight(l, " "))
			if i == 0 {
				out = append(out, first+l)
			} else {
				out = append(out, hang+l)
			}
		}
	}
	for _, line := range strings.Split(body, "\n") {
		switch {
		case line == "":
			out = append(out, "")
		case strings.HasPrefix(line, "# "):
			out = append(out, "", sectionBar.Render(strings.TrimPrefix(line, "# ")))
		case strings.HasPrefix(line, "$ "):
			// a command is never re-flowed by the box: cut it into rows of at most w-6 characters
			r := []rune(strings.TrimPrefix(line, "$ "))
			step := max(20, w-6)
			for len(r) > 0 {
				n := min(step, len(r))
				out = append(out, "  "+cmdStyle.Render(string(r[:n])))
				r = r[n:]
			}
		case strings.HasPrefix(line, "! "):
			wrap(warnStyle, "⚠ ", "  ", strings.TrimPrefix(line, "! "))
		case strings.HasPrefix(line, "✓ "):
			wrap(goodStyle, "✓ ", "  ", strings.TrimPrefix(line, "✓ "))
		case strings.HasPrefix(line, "- "):
			item := strings.TrimPrefix(line, "- ")
			if len(item) > 2 && item[0] >= '1' && item[0] <= '9' && item[1] == '.' {
				// numbered step: bold number, hanging indent under the text
				wrap(text, goodStyle.Render(item[:2])+" ", "   ", item[3:])
			} else {
				wrap(text, "• ", "  ", item)
			}
		default:
			wrap(text, "", "", line)
		}
	}
	return out
}

func (m Model) viewGuide() string {
	cw := m.contentW()
	idx := m.sel
	if idx < 0 || idx >= len(guideTopics) {
		idx = 0
	}
	t := guideTopics[idx]

	wide := cw >= 96
	listW := 0
	// the box re-wraps anything wider than its inner width (and loses the hanging indents),
	// so the text column must be narrower than the box minus its border and padding
	bodyW := cw - 10
	if wide {
		listW = 30
		bodyW = cw - listW - 14
	}
	lines := renderGuideBody(t.body, bodyW)

	// scrolling
	avail := m.guideHeight()
	scroll := m.scroll
	if scroll > len(lines)-avail {
		scroll = max(0, len(lines)-avail)
	}
	end := min(len(lines), scroll+avail)
	view := strings.Join(lines[scroll:end], "\n")
	foot := ""
	switch {
	case end < len(lines) && scroll > 0:
		foot = dimStyle.Render(fmt.Sprintf("▲▼ more above and below (%d/%d) — space / b", end, len(lines)))
	case end < len(lines):
		foot = dimStyle.Render(fmt.Sprintf("▼ more below (%d/%d) — press space", end, len(lines)))
	case scroll > 0:
		foot = dimStyle.Render("▲ more above — press b")
	}

	title := titleStyle.Render(fmt.Sprintf("%d/%d  %s", idx+1, len(guideTopics), t.title))
	content := title + "\n" + dimStyle.Render(strings.Repeat("─", max(10, min(bodyW, 60)))) + "\n" + view
	if foot != "" {
		content += "\n\n" + foot
	}

	if !wide {
		return m.sec("Guide") + dimStyle.Render("   ↑↓ choose a topic") + "\n" + m.box().Render(content)
	}
	var items []string
	for i, g := range guideTopics {
		label := fmt.Sprintf("%d  %s", i+1, g.short)
		if i == idx {
			items = append(items, tabOn.Width(listW).Render(label))
		} else {
			items = append(items, tabOff.Width(listW).Render(label))
		}
	}
	left := lipgloss.NewStyle().Width(listW + 2).Render(strings.Join(items, "\n"))
	right := boxStyle.Width(cw - listW - 6).Render(content)
	return m.sec("Guide") + dimStyle.Render("   ↑↓ choose a topic · space scrolls") + "\n" + lipgloss.JoinHorizontal(lipgloss.Top, left, right)
}
