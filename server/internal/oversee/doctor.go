package oversee

import (
	"bufio"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// Severity of a doctor finding.
type Level string

const (
	OK   Level = "ok"
	Warn Level = "warn"
	Fail Level = "fail"
)

// Finding is one line of `oversee doctor`.
type Finding struct {
	Level  Level
	Title  string
	Detail string // what is wrong / what was checked
	Fix    string // what to do
}

// Listener is a TCP socket in the LISTEN state.
type Listener struct {
	IP   net.IP
	Port int
}

func (l Listener) Loopback() bool { return l.IP.IsLoopback() }

// DoctorEnv is what the checks look at; tests substitute fakes.
type DoctorEnv struct {
	Listeners func() []Listener
	Now       func() time.Time
	Service   func() ServiceState
}

func RealDoctorEnv() DoctorEnv {
	return DoctorEnv{Listeners: ReadListeners, Now: time.Now, Service: Status}
}

// ReadListeners parses /proc/net/tcp and /proc/net/tcp6 (Linux).
func ReadListeners() []Listener {
	var out []Listener
	for _, f := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		out = append(out, ParseProcNetTCP(string(b))...)
	}
	return out
}

// ParseProcNetTCP extracts LISTEN sockets from the text of /proc/net/tcp[6].
func ParseProcNetTCP(text string) []Listener {
	var out []Listener
	sc := bufio.NewScanner(strings.NewReader(text))
	sc.Scan() // header
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) < 4 || f[3] != "0A" { // 0A = TCP_LISTEN
			continue
		}
		addr, port, ok := strings.Cut(f[1], ":")
		if !ok {
			continue
		}
		ip := parseProcIP(addr)
		pn, err := strconv.ParseUint(port, 16, 16)
		if ip == nil || err != nil {
			continue
		}
		out = append(out, Listener{IP: ip, Port: int(pn)})
	}
	return out
}

// /proc prints each 32-bit word of the address in host (little-endian) byte order.
func parseProcIP(h string) net.IP {
	if len(h) != 8 && len(h) != 32 {
		return nil
	}
	ip := make(net.IP, len(h)/2)
	for w := 0; w < len(h)/8; w++ {
		v, err := strconv.ParseUint(h[w*8:w*8+8], 16, 32)
		if err != nil {
			return nil
		}
		ip[w*4], ip[w*4+1], ip[w*4+2], ip[w*4+3] = byte(v), byte(v>>8), byte(v>>16), byte(v>>24)
	}
	return ip
}

func upstreamPort(upstream string) int {
	_, ps, err := net.SplitHostPort(upstream)
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(ps)
	return n
}

// Doctor audits the setup for the mistakes that quietly defeat the lock. The most
// important one: if Xray's inbound is reachable directly, nobody needs the gate.
func (p Paths) Doctor(env DoctorEnv) []Finding {
	var out []Finding
	add := func(l Level, title, detail, fix string) { out = append(out, Finding{l, title, detail, fix}) }
	s := p.LoadSettings()
	now := env.Now()

	// 1. Xray must not be reachable except through the gate.
	port := upstreamPort(s.Upstream)
	var exposed, onLoop []Listener
	if env.Listeners != nil && port > 0 {
		for _, l := range env.Listeners() {
			if l.Port != port {
				continue
			}
			if l.Loopback() {
				onLoop = append(onLoop, l)
			} else {
				exposed = append(exposed, l)
			}
		}
	}
	switch {
	case len(exposed) > 0:
		add(Fail, "Xray is reachable around the gate",
			fmt.Sprintf("port %d is listening on %s, not only on 127.0.0.1. Anyone who decodes a file can connect straight to Xray with the plain link — the gate is bypassed.", port, exposed[0].IP),
			`in the Xray inbound set  "listen": "127.0.0.1"  (the Setup tab prints a correct one), then restart Xray`)
	case len(onLoop) == 0 && port > 0:
		add(Warn, "Nothing is listening on the upstream port",
			fmt.Sprintf("no socket on port %d. Either Xray isn't running or %s is the wrong address.", port, s.Upstream),
			"start Xray, or fix the upstream with  oversee set upstream HOST:PORT")
	default:
		add(OK, "Xray listens on loopback only", fmt.Sprintf("port %d is bound to 127.0.0.1 — it can only be reached through the gate", port), "")
	}

	// 2. App key(s).
	keys, _ := p.ListKeys()
	switch {
	case len(keys) == 0:
		add(Fail, "No app key", "the gate refuses every connection until one exists", "add the GATE_KEY your app was built with: oversee key add <key>")
	case len(keys[0]) < 16:
		add(Warn, "App key is short", fmt.Sprintf("%d characters; use at least 16 random ones", len(keys[0])), "generate one in the Keys tab (g)")
	default:
		add(OK, "App key configured", fmt.Sprintf("%d key(s), newest first", len(keys)), "")
	}
	if st, err := os.Stat(p.Keys); err == nil && st.Mode().Perm()&0o007 != 0 {
		add(Warn, "keys.txt is readable by every user", fmt.Sprintf("mode %o", st.Mode().Perm()), "chmod 660 "+p.Keys)
	}

	// 3. Locks.
	if locks, _ := p.Locks(); len(locks) == 0 {
		add(Warn, "No locks allowed yet", "no file made in the app will connect", "add the line the app shows after locking: oversee add \"<line>\"")
	} else {
		add(OK, "Locks allowed", fmt.Sprintf("%d lock(s) on the allow-list", len(locks)), "")
	}

	// 4. How clients reach the gate.
	switch {
	case s.Cert != "":
		out = append(out, p.certFinding(s.Cert, now))
	case s.Domain != "" && s.Plain == "":
		add(OK, "TLS via Let's Encrypt", "certificate for "+s.Domain+" is obtained automatically", "")
		if s.CDN != "" {
			add(Warn, "Let's Encrypt behind a CDN", "validation fails when the origin is hidden behind a proxy", "use a certificate file (oversee set cert/key) or run plain behind the CDN")
		}
	case s.Plain != "":
		if s.CDN == "" {
			add(Warn, "Plain HTTP and no CDN", "the token travels unencrypted, so anyone on the path can copy it", "terminate TLS (oversee set domain/cert) or put a CDN that does in front")
		} else {
			add(OK, "Plain HTTP behind a CDN", "the CDN terminates TLS; keep the CDN→origin hop on a trusted network or use cert/key", "")
		}
	default:
		add(Fail, "No domain, certificate or plain listener", "the gate has nothing to listen on", "oversee set domain vpn.example.com")
	}

	// 4b. Ports: the gate and Xray cannot share one, and a CDN only proxies certain ports.
	if ep, etls := s.EntryPort(); ep > 0 {
		if up := s.UpstreamPort(); ep == up && (strings.HasPrefix(s.Upstream, "127.") || strings.HasPrefix(s.Upstream, "localhost") || strings.HasPrefix(s.Upstream, "0.0.0.0")) {
			add(Fail, fmt.Sprintf("Gate and Xray both use port %d", ep), "the gate listens on the entry port, Xray must be on a different loopback port", "oversee set upstream 10000  (and set the same port in the Xray/3x-ui inbound)")
		}
		if etls && ep != 443 && s.Cert == "" {
			add(Fail, fmt.Sprintf("TLS on port %d needs a certificate file", ep), "Let's Encrypt can only validate on 443/80", "oversee set cert FILE && oversee set key FILE, or oversee set port 443")
		}
		if s.CDN == "cloudflare" {
			okPorts := map[bool][]int{true: {443, 2053, 2083, 2087, 2096, 8443}, false: {80, 8080, 8880, 2052, 2082, 2086, 2095}}
			found := false
			for _, q := range okPorts[etls] {
				if q == ep {
					found = true
				}
			}
			if !found {
				kind := "HTTP"
				if etls {
					kind = "HTTPS"
				}
				add(Warn, fmt.Sprintf("Cloudflare does not proxy %s on port %d", kind, ep), fmt.Sprintf("Cloudflare only forwards %s to these ports: %v", kind, okPorts[etls]), "choose one of them: oversee set port N (TLS) or oversee set plain :N")
			}
		}
	}

	// 5. CDN consistency.
	if s.CDN != "" {
		info := p.ProxyInfo()
		switch {
		case s.CDN == "generic" || info.Age >= 0 && info.Count > 0:
			if info.Age > 72*time.Hour && (s.CDN == "cloudflare" || s.CDN == "fastly") {
				add(Warn, "CDN IP ranges are old", fmt.Sprintf("%s old", info.Age.Round(time.Hour)), "oversee proxies update")
			} else {
				add(OK, "CDN IP ranges", fmt.Sprintf("%d range(s)", info.Count), "")
			}
		default:
			add(Warn, "No CDN IP ranges yet", "the gate downloads them at start; until then client IPs are the CDN's", "oversee proxies update")
		}
		if !s.OnlyProxy {
			add(Warn, "Origin can be reached around the CDN", "only-proxy is off, so a direct connection to the origin is served", "oversee set only-proxy on")
		}
	}

	// 6. Service.
	if env.Service != nil {
		if sv := env.Service(); sv.Available && sv.Active != "active" {
			add(Warn, "Gate service is not running", "state: "+sv.Active, "press s in the Status tab, or: sudo systemctl start oversee-gate")
		}
	}
	return out
}

func (p Paths) certFinding(path string, now time.Time) Finding {
	b, err := os.ReadFile(path)
	if err != nil {
		return Finding{Fail, "Certificate unreadable", err.Error(), "check the path with  oversee set cert"}
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		return Finding{Fail, "Certificate is not PEM", path, "provide a PEM certificate"}
	}
	cert, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		return Finding{Fail, "Certificate unreadable", err.Error(), ""}
	}
	left := cert.NotAfter.Sub(now)
	switch {
	case left < 0:
		return Finding{Fail, "Certificate expired", "expired " + cert.NotAfter.Format("2006-01-02"), "renew it"}
	case left < 14*24*time.Hour:
		return Finding{Warn, "Certificate expires soon", fmt.Sprintf("in %d days", int(left.Hours()/24)), "renew it; the gate picks up the new file without a restart"}
	}
	return Finding{OK, "Certificate valid", fmt.Sprintf("until %s", cert.NotAfter.Format("2006-01-02")), ""}
}

// Worst returns the most severe level among findings.
func Worst(f []Finding) Level {
	w := OK
	for _, x := range f {
		if x.Level == Fail {
			return Fail
		}
		if x.Level == Warn {
			w = Warn
		}
	}
	return w
}
