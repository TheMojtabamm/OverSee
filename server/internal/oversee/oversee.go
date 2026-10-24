// Package oversee holds the logic behind the `oversee` server tool: where its files
// live, editing the lock allow-list and app keys, talking to systemd, and running
// the gate daemon. Both the TUI and the plain CLI subcommands use it.
package oversee

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"oversea/server/internal/gate"
)

const ServiceName = "oversee-gate"

// Paths of everything the tool reads and writes.
type Paths struct {
	Dir     string // /etc/oversea
	Allow   string
	Keys    string
	Stats   string
	Proxies string // CDN IP ranges (proxies.txt)
	Probe   string // nonce for `oversee cdn-test` (probe.nonce)
	Conf    string
	Certs   string
}

func DefaultPaths() Paths {
	dir := os.Getenv("OVERSEE_DIR")
	if dir == "" {
		dir = "/etc/oversea"
	}
	return Paths{
		Dir:     dir,
		Allow:   filepath.Join(dir, "allow.txt"),
		Keys:    filepath.Join(dir, "keys.txt"),
		Stats:   filepath.Join(dir, "stats.json"),
		Proxies: filepath.Join(dir, "proxies.txt"),
		Probe:   filepath.Join(dir, "probe.nonce"),
		Conf:    filepath.Join(dir, "gate.conf"),
		Certs:   filepath.Join(dir, "certs"),
	}
}

// ---- settings (gate.conf: KEY=VALUE) ----------------------------------------------

type Settings struct {
	Domain   string // public domain for TLS (Let's Encrypt)
	Upstream string // Xray inbound host:port
	Plain    string // optional plain-HTTP listen address (testing / TLS elsewhere)
	LeakIPs  int    // warn when one lock is used from more distinct IPs than this per day (0 = off)

	// NoIPLimit turns off the per-IP block (20 bad tokens a minute => 10 minutes refused).
	NoIPLimit bool

	// CDN fronting. CDN is "", "cloudflare", "fastly" or "generic". OnlyProxy refuses any
	// connection that did not come through the CDN. Cert/Key serve TLS from files (e.g. a
	// Cloudflare Origin CA certificate) instead of Let's Encrypt, which can't validate an
	// origin that is hidden behind a CDN.
	CDN       string
	OnlyProxy bool

	// TokenDays widens the accepted token-day window to ±TokenDays (default 1, max 7).
	TokenDays int
	Cert      string
	Key       string

	// Port is the TLS listen port (0 = 443). Ignored in plain mode (see Plain).
	Port int
}

// EntryPort is the port the gate listens on for clients (or for the CDN), and whether it
// speaks TLS: plain HTTP when Plain is set, TLS otherwise.
func (s Settings) EntryPort() (port int, tls bool) {
	if s.Plain != "" {
		if i := strings.LastIndex(s.Plain, ":"); i >= 0 {
			fmt.Sscanf(s.Plain[i+1:], "%d", &port)
		}
		return port, false
	}
	if s.Port > 0 {
		return s.Port, true
	}
	return 443, true
}

// UpstreamPort is the port of the Xray inbound behind the gate.
func (s Settings) UpstreamPort() int {
	port := 10000
	if i := strings.LastIndex(s.Upstream, ":"); i >= 0 {
		fmt.Sscanf(s.Upstream[i+1:], "%d", &port)
	}
	return port
}

func DefaultSettings() Settings { return Settings{Upstream: "127.0.0.1:10000"} }

func (p Paths) LoadSettings() Settings {
	s := DefaultSettings()
	b, err := os.ReadFile(p.Conf)
	if err != nil {
		return s
	}
	for _, line := range strings.Split(string(b), "\n") {
		k, v, ok := strings.Cut(strings.TrimSpace(line), "=")
		if !ok || strings.HasPrefix(k, "#") {
			continue
		}
		switch strings.TrimSpace(k) {
		case "DOMAIN":
			s.Domain = strings.TrimSpace(v)
		case "UPSTREAM":
			s.Upstream = strings.TrimSpace(v)
		case "PLAIN":
			s.Plain = strings.TrimSpace(v)
		case "CDN":
			s.CDN = strings.TrimSpace(v)
		case "ONLY_PROXY":
			s.OnlyProxy = strings.TrimSpace(v) == "1" || strings.TrimSpace(v) == "true"
		case "IP_LIMIT":
			switch strings.ToLower(strings.TrimSpace(v)) {
			case "off", "0", "false", "no":
				s.NoIPLimit = true
			}
		case "TOKEN_DAYS":
			fmt.Sscanf(strings.TrimSpace(v), "%d", &s.TokenDays)
		case "CERT":
			s.Cert = strings.TrimSpace(v)
		case "KEY":
			s.Key = strings.TrimSpace(v)
		case "PORT":
			fmt.Sscanf(strings.TrimSpace(v), "%d", &s.Port)
		case "LEAK_IPS":
			fmt.Sscanf(strings.TrimSpace(v), "%d", &s.LeakIPs)
		}
	}
	return s
}

func (p Paths) SaveSettings(s Settings) error {
	if err := os.MkdirAll(p.Dir, 0o750); err != nil {
		return err
	}
	op := "0"
	if s.OnlyProxy {
		op = "1"
	}
	lim := "on"
	if s.NoIPLimit {
		lim = "off"
	}
	body := fmt.Sprintf("# managed by `oversee`\nDOMAIN=%s\nUPSTREAM=%s\nPLAIN=%s\nLEAK_IPS=%d\nCDN=%s\nONLY_PROXY=%s\nCERT=%s\nKEY=%s\nTOKEN_DAYS=%d\nPORT=%d\nIP_LIMIT=%s\n",
		s.Domain, s.Upstream, s.Plain, s.LeakIPs, s.CDN, op, s.Cert, s.Key, s.TokenDays, s.Port, lim)
	return writeAtomic(p.Conf, []byte(body), 0o640)
}

// ---- locks (allow-list) ---------------------------------------------------------

// Lock is one allow-list entry.
type Lock struct {
	CodeID    string
	Code      string
	CreatorFp string
	Note      string
}

func (p Paths) Locks() ([]Lock, error) {
	lines, err := readLines(p.Allow)
	if err != nil {
		return nil, err
	}
	var out []Lock
	for _, l := range lines {
		if e, ok := parseLine(l); ok {
			out = append(out, Lock{CodeID: gate.CodeID(e.Code), Code: e.Code, CreatorFp: e.CreatorFp, Note: e.Note})
		}
	}
	return out, nil
}

func parseLine(l string) (gate.Entry, bool) {
	m, err := gate.ParseAllowList(bufio.NewScanner(strings.NewReader(l)))
	if err != nil || len(m) != 1 {
		return gate.Entry{}, false
	}
	for _, e := range m {
		return e, true
	}
	return gate.Entry{}, false
}

// AddLock validates and appends a line (`<code> <fingerprint> [note]`). Adding the
// same code twice replaces the old line, so re-pasting is harmless.
func (p Paths) AddLock(line string) (Lock, error) {
	line = strings.TrimSpace(line)
	e, ok := parseLine(line)
	if !ok {
		return Lock{}, errors.New("not a valid line: expected `<32-hex code> <creator fingerprint> [note]`")
	}
	if err := os.MkdirAll(p.Dir, 0o750); err != nil {
		return Lock{}, err
	}
	lines, err := readLines(p.Allow)
	if err != nil {
		return Lock{}, err
	}
	id := gate.CodeID(e.Code)
	kept := lines[:0:0]
	for _, l := range lines {
		if x, ok := parseLine(l); ok && gate.CodeID(x.Code) == id {
			continue
		}
		kept = append(kept, l)
	}
	kept = append(kept, fmt.Sprintf("%s %s%s", e.Code, e.CreatorFp, noteSuffix(e.Note)))
	if err := writeAtomic(p.Allow, []byte(strings.Join(kept, "\n")+"\n"), 0o640); err != nil {
		return Lock{}, err
	}
	return Lock{CodeID: id, Code: e.Code, CreatorFp: e.CreatorFp, Note: e.Note}, nil
}

func noteSuffix(n string) string {
	if n == "" {
		return ""
	}
	return " " + n
}

// RevokeLock removes the entry whose code id or code starts with prefix (min 4
// chars, must be unambiguous). Every copy of that lock stops working within seconds.
func (p Paths) RevokeLock(prefix string) (Lock, error) {
	prefix = strings.ToLower(strings.TrimSpace(prefix))
	if len(prefix) < 4 {
		return Lock{}, errors.New("give at least 4 characters of the lock id or code")
	}
	lines, err := readLines(p.Allow)
	if err != nil {
		return Lock{}, err
	}
	var hit []int
	var found Lock
	for i, l := range lines {
		if e, ok := parseLine(l); ok {
			id := gate.CodeID(e.Code)
			if strings.HasPrefix(id, prefix) || strings.HasPrefix(e.Code, prefix) {
				hit = append(hit, i)
				found = Lock{CodeID: id, Code: e.Code, CreatorFp: e.CreatorFp, Note: e.Note}
			}
		}
	}
	switch len(hit) {
	case 0:
		return Lock{}, errors.New("no lock matches")
	case 1:
	default:
		return Lock{}, errors.New("ambiguous: more than one lock matches, give more characters")
	}
	kept := append(append([]string{}, lines[:hit[0]]...), lines[hit[0]+1:]...)
	body := strings.Join(kept, "\n")
	if body != "" {
		body += "\n"
	}
	return found, writeAtomic(p.Allow, []byte(body), 0o640)
}

// ---- app keys -------------------------------------------------------------------

// ListKeys returns the app keys in order (first = current).
func (p Paths) ListKeys() ([]string, error) {
	lines, err := readLines(p.Keys)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if i := strings.Index(l, "#"); i >= 0 {
			l = strings.TrimSpace(l[:i])
		}
		if l != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

func (p Paths) writeKeys(keys []string) error {
	if err := os.MkdirAll(p.Dir, 0o750); err != nil {
		return err
	}
	body := "# app keys, newest first. Keep the previous one until old app builds age out.\n" +
		strings.Join(keys, "\n") + "\n"
	return writeAtomic(p.Keys, []byte(body), 0o640) // group "oversee" (the gate) must read it
}

// AddKey puts key first (making it the current one).
func (p Paths) AddKey(key string) error {
	key = strings.TrimSpace(key)
	if len(key) < 8 || strings.ContainsAny(key, " \t#") {
		return errors.New("key must be at least 8 characters, no spaces or #")
	}
	cur, err := p.ListKeys()
	if err != nil {
		return err
	}
	next := []string{key}
	for _, k := range cur {
		if k != key {
			next = append(next, k)
		}
	}
	return p.writeKeys(next)
}

func (p Paths) RemoveKey(index int) error {
	cur, err := p.ListKeys()
	if err != nil {
		return err
	}
	if index < 0 || index >= len(cur) {
		return errors.New("no such key")
	}
	return p.writeKeys(append(cur[:index:index], cur[index+1:]...))
}

// MaskKey shows only the end of a key.
func MaskKey(k string) string {
	if len(k) <= 6 {
		return strings.Repeat("•", len(k))
	}
	return strings.Repeat("•", 8) + k[len(k)-4:]
}

// ---- files ----------------------------------------------------------------------

func readLines(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	s := strings.TrimRight(string(b), "\n")
	if s == "" {
		return nil, nil
	}
	return strings.Split(s, "\n"), nil
}

// writeAtomic replaces path via a temp file + rename, so the running gate (which
// polls the file) never sees a half-written list.
func writeAtomic(path string, data []byte, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	inheritOwner(tmp, filepath.Dir(path))
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// RandomHex returns n random bytes as hex.
func RandomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// ---- systemd --------------------------------------------------------------------

// Service state as shown in the UI.
type ServiceState struct {
	Available bool   // systemctl exists
	Active    string // active / inactive / failed / unknown
	Enabled   string // enabled / disabled / unknown
}

func Status() ServiceState {
	if _, err := exec.LookPath("systemctl"); err != nil {
		return ServiceState{Active: "unknown", Enabled: "unknown"}
	}
	return ServiceState{
		Available: true,
		Active:    systemctlOut("is-active", ServiceName),
		Enabled:   systemctlOut("is-enabled", ServiceName),
	}
}

func systemctlOut(args ...string) string {
	out, _ := exec.Command("systemctl", args...).Output()
	s := strings.TrimSpace(string(out))
	if s == "" {
		return "unknown"
	}
	return s
}

// Control runs `systemctl <action> oversee-gate` (start, stop, restart, enable, disable).
func Control(action string) error {
	switch action {
	case "start", "stop", "restart", "enable", "disable":
	default:
		return fmt.Errorf("unknown action %q", action)
	}
	out, err := exec.Command("systemctl", action, ServiceName).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func Logs(n int) string {
	if _, err := exec.LookPath("journalctl"); err != nil {
		return "journalctl not available on this system"
	}
	out, _ := exec.Command("journalctl", "-u", ServiceName, "-n", fmt.Sprint(n), "--no-pager", "-o", "short").CombinedOutput()
	return strings.TrimSpace(string(out))
}

// SortLocks orders by note then id for stable display.
func SortLocks(l []Lock) {
	sort.Slice(l, func(i, j int) bool {
		if l[i].Note != l[j].Note {
			return l[i].Note < l[j].Note
		}
		return l[i].CodeID < l[j].CodeID
	})
}

func statFile(path string) (time.Time, error) {
	st, err := os.Stat(path)
	if err != nil {
		return time.Time{}, err
	}
	return st.ModTime(), nil
}

// SetSetting changes one gate.conf value by its CLI name (`oversee set <name> <value>`).
func (p Paths) SetSetting(name, value string) error {
	s := p.LoadSettings()
	value = strings.TrimSpace(value)
	switch name {
	case "domain":
		s.Domain = value
	case "upstream":
		if n, err := strconv.Atoi(value); err == nil && n >= 1 && n <= 65535 {
			value = "127.0.0.1:" + value // a bare port means Xray on loopback
		}
		if !strings.Contains(value, ":") {
			return errors.New("upstream must be host:port (or just the port), e.g. 127.0.0.1:10000")
		}
		s.Upstream = value
	case "plain":
		s.Plain = value
	case "leak-ips":
		n := 0
		if _, err := fmt.Sscanf(value, "%d", &n); err != nil || n < 0 {
			return errors.New("leak-ips must be a whole number (0 = off)")
		}
		s.LeakIPs = n
	case "cdn":
		if !ValidCDN(value) {
			return errors.New("cdn must be none, cloudflare, fastly or generic")
		}
		if value == "none" {
			value = ""
		}
		s.CDN = value
		if value == "" {
			s.OnlyProxy = false
		}
	case "only-proxy":
		on := value == "1" || value == "true" || value == "on" || value == "yes"
		if on && s.CDN == "" {
			return errors.New("set a CDN first: oversee set cdn cloudflare")
		}
		s.OnlyProxy = on
	case "ip-limit":
		s.NoIPLimit = !(value == "1" || value == "true" || value == "on" || value == "yes")
	case "token-days":
		n := 0
		if _, err := fmt.Sscanf(value, "%d", &n); err != nil || n < 1 || n > 7 {
			return errors.New("token-days must be 1-7")
		}
		s.TokenDays = n
	case "cert":
		s.Cert = value
	case "key":
		s.Key = value
	case "port":
		n := 0
		if _, err := fmt.Sscanf(value, "%d", &n); err != nil || n < 1 || n > 65535 {
			return errors.New("port must be 1-65535")
		}
		s.Port = n
	default:
		return fmt.Errorf("unknown setting %q (domain, upstream, plain, port, leak-ips, cdn, only-proxy, ip-limit, token-days, cert, key)", name)
	}
	if (s.Cert == "") != (s.Key == "") && (name == "cert" || name == "key") && value != "" {
		// allowed transiently: the user sets one then the other; the gate refuses to start
		// with only one of them and says why.
	}
	return p.SaveSettings(s)
}
