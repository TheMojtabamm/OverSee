// Package tui is the interactive terminal UI of `oversee`.
package tui

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"oversea/server/internal/gate"
	"oversea/server/internal/oversee"
)

type tab int

const (
	tabStatus tab = iota
	tabLocks
	tabKeys
	tabSetup
	tabLogs
	tabGuide
)

var tabNames = []string{"Status", "Locks", "Keys", "Setup", "Logs", "Guide"}

var (
	accent = lipgloss.Color("#38E1D4")
	ink    = lipgloss.Color("#0b0f14")
	bright = lipgloss.Color("#e8eef4")
	dim    = lipgloss.Color("#7a8591")
	bad    = lipgloss.Color("#ff6b6b")
	good   = lipgloss.Color("#5fd38d")
	warn   = lipgloss.Color("#f5c451")
	panel  = lipgloss.Color("#16202b")

	bannerStyle = lipgloss.NewStyle().Bold(true).Foreground(ink).Background(accent).Padding(0, 2)
	titleStyle  = lipgloss.NewStyle().Bold(true).Foreground(accent)
	subStyle    = lipgloss.NewStyle().Bold(true).Foreground(bright)
	tabOn       = lipgloss.NewStyle().Bold(true).Foreground(ink).Background(accent).Padding(0, 2)
	tabOff      = lipgloss.NewStyle().Bold(true).Foreground(dim).Padding(0, 2)
	dimStyle    = lipgloss.NewStyle().Foreground(dim)
	badStyle    = lipgloss.NewStyle().Bold(true).Foreground(bad)
	goodStyle   = lipgloss.NewStyle().Bold(true).Foreground(good)
	warnStyle   = lipgloss.NewStyle().Bold(true).Foreground(warn)
	selStyle    = lipgloss.NewStyle().Bold(true).Foreground(accent)
	boxStyle    = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(dim).Padding(1, 2)
	helpStyle   = lipgloss.NewStyle().Foreground(dim)
	headerStyle = lipgloss.NewStyle().Bold(true).Foreground(bright)
	labelStyle  = lipgloss.NewStyle().Bold(true).Foreground(dim)
	valueStyle  = lipgloss.NewStyle().Bold(true).Foreground(bright)
	sectionBar  = lipgloss.NewStyle().Bold(true).Foreground(accent)
	keyBadge    = lipgloss.NewStyle().Bold(true).Foreground(ink).Background(dim).Padding(0, 1)
	cmdStyle    = lipgloss.NewStyle().Bold(true).Foreground(good).Background(panel).Padding(0, 1)
)

// mode is what the keyboard is currently doing inside a tab.
type mode int

const (
	modeBrowse mode = iota
	modeAddLock
	modeConfirmRevoke
	modeAddKey
	modeConfirmKeyDelete
	modeEditDomain
	modeEditUpstream
	modeEditLeak
	modeEditPort
)

type Model struct {
	p    oversee.Paths
	tab  tab
	mode mode

	w, h int

	svc      oversee.ServiceState
	locks    []oversee.Lock
	keys     []string
	settings oversee.Settings
	stats    map[string]gate.LockSnapshot
	statsAge time.Duration
	rejects  map[string]int
	logs     string
	problems []oversee.Finding

	sel      int // selection in Locks / Keys / Guide topics
	scroll   int // Guide: first visible line
	input    textinput.Model
	msg      string
	msgIsErr bool

	// Setup tab: a throwaway example inbound + link
	exUUID string
	exPath string
}

func New(p oversee.Paths) Model {
	ti := textinput.New()
	ti.CharLimit = 300
	ti.Prompt = "› "
	m := Model{p: p, input: ti, exUUID: oversee.NewUUID(), exPath: "/" + oversee.RandomHex(4)}
	m.refresh()
	return m
}

func (m *Model) refresh() {
	m.svc = oversee.Status()
	m.locks, _ = m.p.Locks()
	oversee.SortLocks(m.locks)
	m.keys, _ = m.p.ListKeys()
	m.settings = m.p.LoadSettings()
	m.problems = nil
	for _, f := range m.p.Doctor(oversee.RealDoctorEnv()) {
		if f.Level != oversee.OK {
			m.problems = append(m.problems, f)
		}
	}
	m.stats, m.rejects, m.statsAge = map[string]gate.LockSnapshot{}, nil, -1
	if sn, err := gate.ReadSnapshot(m.p.Stats); err == nil {
		for _, l := range sn.Locks {
			m.stats[l.CodeID] = l
		}
		m.rejects, m.statsAge = sn.Rejects, time.Since(sn.Updated)
	}
	if m.sel >= m.listLen() {
		m.sel = max(0, m.listLen()-1)
	}
}

func (m Model) listLen() int {
	switch m.tab {
	case tabLocks:
		return len(m.locks)
	case tabKeys:
		return len(m.keys)
	case tabGuide:
		return len(guideTopics)
	}
	return 0
}

func (m *Model) say(s string, err bool) { m.msg, m.msgIsErr = s, err }

func (m Model) Init() tea.Cmd { return textinput.Blink }

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = v.Width, v.Height
		return m, nil
	case tea.KeyMsg:
		if m.mode != modeBrowse {
			return m.updateInput(v)
		}
		return m.updateBrowse(v)
	}
	return m, nil
}

func (m Model) updateBrowse(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	switch s {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "tab", "right", "l":
		m.tab = (m.tab + 1) % tab(len(tabNames))
		m.sel, m.scroll, m.msg = 0, 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "shift+tab", "left", "h":
		m.tab = (m.tab + tab(len(tabNames)) - 1) % tab(len(tabNames))
		m.sel, m.scroll, m.msg = 0, 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "1", "2", "3", "4", "5", "6":
		m.tab = tab(int(s[0] - '1'))
		m.sel, m.scroll, m.msg = 0, 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "up", "k":
		if m.sel > 0 {
			m.sel--
			m.scroll = 0
		}
		return m, nil
	case "down", "j":
		if m.sel < m.listLen()-1 {
			m.sel++
			m.scroll = 0
		}
		return m, nil
	case " ", "pgdown", "f":
		if m.tab == tabGuide {
			m.scroll += max(3, m.guideHeight()-2)
		}
		return m, nil
	case "pgup", "b":
		if m.tab == tabGuide {
			m.scroll = max(0, m.scroll-max(3, m.guideHeight()-2))
		}
		return m, nil
	case "r":
		m.refresh()
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		m.say("refreshed", false)
		return m, nil
	}

	switch m.tab {
	case tabStatus:
		return m.statusKeys(s)
	case tabLocks:
		switch s {
		case "a", "n":
			m.mode = modeAddLock
			m.input.Placeholder = "paste the line from the app:  <code> <fingerprint> [note]"
			m.input.SetValue("")
			m.input.Focus()
			m.say("", false)
		case "d", "x", "delete":
			if len(m.locks) > 0 {
				m.mode = modeConfirmRevoke
			}
		}
	case tabKeys:
		switch s {
		case "n", "a":
			m.mode = modeAddKey
			m.input.Placeholder = "new app key (the GATE_KEY of your newest Oversea build)"
			m.input.SetValue("")
			m.input.Focus()
			m.say("", false)
		case "g":
			key := oversee.RandomHex(16)
			m.input.SetValue(key)
			m.mode = modeAddKey
			m.input.Focus()
			m.say("generated — Enter to save it, then build the app with this GATE_KEY", false)
		case "d", "x", "delete":
			if len(m.keys) > 0 {
				m.mode = modeConfirmKeyDelete
			}
		}
	case tabSetup:
		switch s {
		case "e":
			m.mode = modeEditDomain
			m.input.SetValue(m.settings.Domain)
			m.input.Placeholder = "vpn.example.com"
			m.input.Focus()
		case "u":
			m.mode = modeEditUpstream
			m.input.SetValue(fmt.Sprint(m.settings.UpstreamPort()))
			m.input.Placeholder = "the Xray inbound port, e.g. 10000"
			m.input.Focus()
		case "p":
			ep, _ := m.settings.EntryPort()
			m.mode = modeEditPort
			m.input.SetValue(fmt.Sprint(ep))
			m.input.Placeholder = "the port clients (or the CDN) connect to, e.g. 8080"
			m.input.Focus()
		case "m":
			st := m.settings
			ep, tls := st.EntryPort()
			if tls { // → plain HTTP on the same port (443 would clash with nothing, but 80 is the usual plain port)
				if ep == 443 {
					ep = 80
				}
				st.Plain = fmt.Sprintf(":%d", ep)
			} else {
				if st.Domain == "" && st.Cert == "" {
					m.say("TLS needs a domain (Let's Encrypt) or a certificate file first — see Guide → Own certificate", true)
					return m, nil
				}
				st.Plain = ""
				st.Port = ep
			}
			if err := m.p.SaveSettings(st); err != nil {
				m.say(err.Error(), true)
			} else {
				np, nt := st.EntryPort()
				m.say(fmt.Sprintf("entry is now %s on port %d — restart the gate (Status → R) to apply", map[bool]string{true: "TLS", false: "plain HTTP"}[nt], np), false)
			}
			m.refresh()
		case "c":
			st := m.settings
			st.CDN = oversee.NextCDN(st.CDN)
			if st.CDN == "" {
				st.OnlyProxy = false // can't refuse non-CDN traffic without a CDN
			}
			if err := m.p.SaveSettings(st); err != nil {
				m.say(err.Error(), true)
			} else if st.CDN == "cloudflare" || st.CDN == "fastly" {
				m.say("CDN: "+st.CDN+" — restart the gate; it downloads the IP ranges itself (or: oversee proxies update)", false)
			} else {
				m.say("CDN: "+orNone(st.CDN)+" — restart the gate to apply", false)
			}
			m.refresh()
		case "o":
			st := m.settings
			if st.CDN == "" {
				m.say("pick a CDN first (c)", true)
			} else {
				st.OnlyProxy = !st.OnlyProxy
				if err := m.p.SaveSettings(st); err != nil {
					m.say(err.Error(), true)
				} else {
					m.say("only-proxy "+onOff(st.OnlyProxy)+" — restart the gate to apply", false)
				}
				m.refresh()
			}
		case "t":
			m.mode = modeEditLeak
			m.input.SetValue(fmt.Sprint(m.settings.LeakIPs))
			m.input.Placeholder = "0 = off"
			m.input.Focus()
		case "g":
			m.exUUID, m.exPath = oversee.NewUUID(), "/"+oversee.RandomHex(4)
		}
	}
	return m, nil
}

func (m Model) statusKeys(s string) (tea.Model, tea.Cmd) {
	var action string
	switch s {
	case "s":
		action = "start"
	case "x":
		action = "stop"
	case "R":
		action = "restart"
	case "e":
		action = "enable"
	case "D":
		action = "disable"
	default:
		return m, nil
	}
	if !m.svc.Available {
		m.say("systemd not available here — run `oversee gate` yourself", true)
		return m, nil
	}
	if err := oversee.Control(action); err != nil {
		m.say(err.Error(), true)
	} else {
		m.say(action+" ok", false)
	}
	m.refresh()
	return m, nil
}

func (m Model) updateInput(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch m.mode {
	case modeConfirmRevoke, modeConfirmKeyDelete:
		switch k.String() {
		case "y", "Y":
			if m.mode == modeConfirmRevoke && m.sel < len(m.locks) {
				l, err := m.p.RevokeLock(m.locks[m.sel].CodeID)
				if err != nil {
					m.say(err.Error(), true)
				} else {
					m.say(fmt.Sprintf("revoked %s — every copy of this lock stops working within seconds", l.CodeID), false)
				}
			}
			if m.mode == modeConfirmKeyDelete {
				if err := m.p.RemoveKey(m.sel); err != nil {
					m.say(err.Error(), true)
				} else {
					m.say("key removed", false)
				}
			}
			m.mode = modeBrowse
			m.refresh()
		default:
			m.mode = modeBrowse
			m.say("cancelled", false)
		}
		return m, nil
	}

	switch k.String() {
	case "esc", "ctrl+c":
		m.mode = modeBrowse
		m.input.Blur()
		m.say("cancelled", false)
		return m, nil
	case "enter":
		val := strings.TrimSpace(m.input.Value())
		switch m.mode {
		case modeAddLock:
			if l, err := m.p.AddLock(val); err != nil {
				m.say(err.Error(), true)
				return m, nil // stay in the input so the user can fix it
			} else {
				m.say(fmt.Sprintf("lock %s added — live within seconds", l.CodeID), false)
			}
		case modeAddKey:
			if err := m.p.AddKey(val); err != nil {
				m.say(err.Error(), true)
				return m, nil
			}
			m.say("key added as the current key (older ones still accepted until you remove them)", false)
		case modeEditDomain, modeEditUpstream, modeEditLeak, modeEditPort:
			s := m.settings
			switch m.mode {
			case modeEditDomain:
				s.Domain = val
			case modeEditUpstream:
				if n, err := strconv.Atoi(val); err == nil && n >= 1 && n <= 65535 {
					val = "127.0.0.1:" + val // a bare port means Xray on loopback
				}
				if !strings.Contains(val, ":") {
					m.say("enter the Xray inbound port (e.g. 10000) or host:port", true)
					return m, nil
				}
				s.Upstream = val
			case modeEditPort:
				n, err := strconv.Atoi(val)
				if err != nil || n < 1 || n > 65535 {
					m.say("enter a port between 1 and 65535", true)
					return m, nil
				}
				if _, tls := s.EntryPort(); tls {
					s.Port = n
				} else {
					s.Plain = fmt.Sprintf(":%d", n)
				}
			default:
				n, err := strconv.Atoi(val)
				if err != nil || n < 0 {
					m.say("enter a whole number, 0 turns the alert off", true)
					return m, nil
				}
				s.LeakIPs = n
			}
			if err := m.p.SaveSettings(s); err != nil {
				m.say(err.Error(), true)
				return m, nil
			}
			m.say("saved — restart the gate (Status → R) to apply", false)
		}
		m.mode = modeBrowse
		m.input.Blur()
		m.refresh()
		return m, nil
	}
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(k)
	return m, cmd
}

// ---- view -----------------------------------------------------------------------

// contentW is the width of the working area: the terminal width, within sane limits.
func (m Model) contentW() int {
	w := m.w
	if w <= 0 {
		w = 100
	}
	w -= 4
	if w > 118 {
		w = 118
	}
	if w < 60 {
		w = 60
	}
	return w
}

// gap is the blank line(s) between rows: roomy when the terminal is tall enough.
func (m Model) gap() string {
	if m.h > 0 && m.h < 36 {
		return "\n"
	}
	return "\n\n"
}

func (m Model) box() lipgloss.Style { return boxStyle.Width(m.contentW() - 2) }

func (m Model) sec(title string) string {
	return sectionBar.Render("▌ " + strings.ToUpper(title))
}

func (m Model) banner() string {
	left := bannerStyle.Render("◆ OVERSEE") + "  " + subStyle.Render("oversee") + dimStyle.Render(" · gate manager")
	chip := dimStyle.Render("systemd n/a")
	if m.svc.Available {
		switch m.svc.Active {
		case "active":
			chip = goodStyle.Render("● RUNNING")
		case "inactive", "failed":
			chip = badStyle.Render("● " + strings.ToUpper(m.svc.Active))
		default:
			chip = warnStyle.Render("● " + strings.ToUpper(m.svc.Active))
		}
	}
	pad := m.contentW() - lipgloss.Width(left) - lipgloss.Width(chip)
	return left + strings.Repeat(" ", max(2, pad)) + chip
}

func (m Model) View() string {
	var b strings.Builder
	cw := m.contentW()
	b.WriteString("\n " + m.banner() + "\n\n")

	var tabs []string
	for i, n := range tabNames {
		label := fmt.Sprintf("%d %s", i+1, n)
		if tab(i) == m.tab {
			tabs = append(tabs, tabOn.Render(label))
		} else {
			tabs = append(tabs, tabOff.Render(label))
		}
	}
	b.WriteString(" " + lipgloss.JoinHorizontal(lipgloss.Top, tabs...) + "\n")
	b.WriteString(" " + dimStyle.Render(strings.Repeat("━", cw)) + "\n\n")

	var body string
	switch m.tab {
	case tabStatus:
		body = m.viewStatus()
	case tabLocks:
		body = m.viewLocks()
	case tabKeys:
		body = m.viewKeys()
	case tabSetup:
		body = m.viewSetup()
	case tabLogs:
		body = m.sec("Gate logs") + "\n" + m.box().Render(orDashPlain(m.logs))
	case tabGuide:
		body = m.viewGuide()
	}
	b.WriteString(indent(body, " "))

	b.WriteString("\n")
	switch m.mode {
	case modeAddLock, modeAddKey, modeEditDomain, modeEditUpstream, modeEditLeak, modeEditPort:
		b.WriteString("\n " + m.input.View() + "\n " + helpStyle.Render("enter save · esc cancel") + "\n")
	case modeConfirmRevoke:
		if m.sel < len(m.locks) {
			l := m.locks[m.sel]
			b.WriteString("\n " + warnStyle.Render(fmt.Sprintf("Revoke %s (%s)? All copies of this lock stop working. [y/N]", l.CodeID, orDash(l.Note))) + "\n")
		}
	case modeConfirmKeyDelete:
		b.WriteString("\n " + warnStyle.Render("Remove this app key? Apps built with it will be refused. [y/N]") + "\n")
	}
	if m.msg != "" {
		st := goodStyle
		if m.msgIsErr {
			st = badStyle
		}
		b.WriteString("\n " + st.Render(m.msg) + "\n")
	}
	b.WriteString("\n " + m.helpBar() + "\n")
	return b.String()
}

func indent(s, pad string) string {
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		lines[i] = pad + l
	}
	return strings.Join(lines, "\n")
}

// helpPairs are the keys that work right now: {key, what it does}.
func (m Model) helpPairs() [][2]string {
	base := [][2]string{{"tab", "next"}, {"1-6", "jump"}, {"r", "refresh"}, {"q", "quit"}}
	var own [][2]string
	switch m.tab {
	case tabStatus:
		own = [][2]string{{"s", "start"}, {"x", "stop"}, {"R", "restart"}, {"e", "enable"}, {"D", "disable"}}
	case tabLocks:
		own = [][2]string{{"↑↓", "select"}, {"a", "add"}, {"d", "revoke"}}
	case tabKeys:
		own = [][2]string{{"↑↓", "select"}, {"n", "new"}, {"g", "generate"}, {"d", "remove"}}
	case tabSetup:
		own = [][2]string{{"p", "entry port"}, {"m", "TLS/plain"}, {"u", "Xray port"}, {"e", "domain"}, {"c", "CDN"}, {"o", "only-CDN"}, {"t", "leak alert"}, {"g", "example"}}
	case tabGuide:
		own = [][2]string{{"↑↓", "topic"}, {"space", "scroll down"}, {"b", "scroll up"}}
	}
	return append(own, base...)
}

func (m Model) helpBar() string {
	var parts []string
	for _, p := range m.helpPairs() {
		parts = append(parts, keyBadge.Render(p[0])+" "+helpStyle.Render(p[1]))
	}
	return strings.Join(parts, "  ")
}

// help is the same list as plain text.
func (m Model) help() string {
	var parts []string
	for _, p := range m.helpPairs() {
		parts = append(parts, p[0]+" "+p[1])
	}
	return strings.Join(parts, " · ")
}

func (m Model) viewStatus() string {
	state := warnStyle.Render(m.svc.Active)
	switch m.svc.Active {
	case "active":
		state = goodStyle.Render("● running")
	case "inactive", "failed":
		state = badStyle.Render("● " + m.svc.Active)
	}
	if !m.svc.Available {
		state = dimStyle.Render("systemd not available")
	}
	rows := []string{
		row("Gate service", state+dimStyle.Render("   starts at boot: "+m.svc.Enabled)),
		row("Domain", orDash(m.settings.Domain)),
		row("Upstream (Xray)", val(m.settings.Upstream)),
		row("Locks allowed", val(fmt.Sprint(len(m.locks)))),
		row("App keys", val(fmt.Sprint(len(m.keys)))),
		row("Config dir", dimStyle.Render(m.p.Dir)),
	}
	out := m.sec("Overview") + "\n" + m.box().Render(strings.Join(rows, m.gap()))
	if len(m.problems) > 0 {
		var lines []string
		for _, f := range m.problems {
			mark, st := "⚠", warnStyle
			if f.Level == oversee.Fail {
				mark, st = "✗", badStyle
			}
			lines = append(lines, st.Render(fmt.Sprintf("%s %s", mark, f.Title)))
			if f.Fix != "" {
				lines = append(lines, dimStyle.Render("    → "+f.Fix))
			}
		}
		out += "\n\n" + m.sec("Needs attention") + "\n" + strings.Join(lines, "\n")
	} else {
		out += "\n\n" + goodStyle.Render("✓ setup looks right") + dimStyle.Render("   (oversee doctor has the details)")
	}
	out += "\n" + dimStyle.Render("New here? Open the ") + selStyle.Render("6 Guide") + dimStyle.Render(" tab: CDN, TLS, no-TLS and certificates, step by step.")
	return out
}

func (m Model) viewLocks() string {
	if len(m.locks) == 0 {
		return m.sec("Locks") + "\n" + dimStyle.Render("No locks yet. In the app: Share → Lock → Server gate, then press ") + selStyle.Render("a") + dimStyle.Render(" and paste the line it shows.")
	}
	var lines []string
	lines = append(lines, labelStyle.Render(fmt.Sprintf("  %-18s %-21s %7s %6s  %s", "LOCK ID", "CREATOR", "CONNS", "IPs", "NOTE")))
	leaks := 0
	for i, l := range m.locks {
		cur := "  "
		st := valueStyle
		if i == m.sel {
			cur, st = "▸ ", selStyle
		}
		conns, ips := "-", "-"
		leaked := false
		if s, ok := m.stats[l.CodeID]; ok {
			conns, ips = fmt.Sprint(s.Accepted), fmt.Sprint(s.DistinctIPs)
			leaked = m.settings.LeakIPs > 0 && s.DistinctIPs > m.settings.LeakIPs
		}
		row := st.Render(fmt.Sprintf("%-18s %-21s %7s %6s  %s", l.CodeID, l.CreatorFp, conns, ips, l.Note))
		if leaked {
			leaks++
			row += " " + badStyle.Render("⚠ shared?")
		}
		lines = append(lines, cur+row)
	}
	out := m.sec("Locks") + "\n" + m.box().Render(strings.Join(lines, "\n"))
	switch {
	case m.statsAge < 0:
		out += "\n" + dimStyle.Render("no live stats yet (the gate writes them every few seconds while running)")
	default:
		out += "\n" + dimStyle.Render(fmt.Sprintf("today (UTC) · stats %ds old", int(m.statsAge.Seconds())))
	}
	if len(m.rejects) > 0 {
		out += dimStyle.Render(" · refused: " + fmtRejects(m.rejects))
	}
	if leaks > 0 {
		out += "\n" + badStyle.Render(fmt.Sprintf("%d lock(s) used from more than %d IPs today — if that's not your audience, revoke (d) and issue a new file.", leaks, m.settings.LeakIPs))
	}
	return out
}

func fmtRejects(r map[string]int) string {
	keys := make([]string, 0, len(r))
	for k := range r {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s %d", k, r[k]))
	}
	return strings.Join(parts, ", ")
}

func (m Model) viewKeys() string {
	intro := dimStyle.Render("The gate accepts tokens made by these Oversea app keys. Newest first; keep the previous one until old builds age out.") + "\n\n"
	if len(m.keys) == 0 {
		return m.sec("App keys") + "\n" + intro + warnStyle.Render("No key yet — every connection is refused. Press ") + selStyle.Render("n") + warnStyle.Render(" to add the GATE_KEY your app was built with, or ") + selStyle.Render("g") + warnStyle.Render(" to generate one.")
	}
	var lines []string
	for i, k := range m.keys {
		cur, st := "  ", valueStyle
		if i == m.sel {
			cur, st = "▸ ", selStyle
		}
		tag := dimStyle.Render("   previous")
		if i == 0 {
			tag = goodStyle.Render("   current")
		}
		lines = append(lines, cur+st.Render(oversee.MaskKey(k))+tag)
	}
	return m.sec("App keys") + "\n" + intro + m.box().Render(strings.Join(lines, m.gap()))
}

func (m Model) viewSetup() string {
	s := m.settings
	ep, etls := s.EntryPort()
	up := s.UpstreamPort()
	edit := func(k string) string { return "   " + keyBadge.Render(k) }
	mode := "plain HTTP"
	if etls {
		mode = "TLS"
	}
	var b strings.Builder

	// 1. Where traffic enters and where it goes
	who := "clients"
	if s.CDN != "" {
		who = "the " + s.CDN + " CDN"
	}
	flow := fmt.Sprintf("%s  ──▶  GATE :%d (%s)  ──▶  XRAY 127.0.0.1:%d",
		strings.ToUpper(who), ep, mode, up)
	b.WriteString(m.sec("Ports") + "\n")
	b.WriteString(m.box().Render(strings.Join([]string{
		headerStyle.Render(flow),
		row("Entry port", val(fmt.Sprintf("%d  (%s)", ep, mode))+edit("p")+" "+keyBadge.Render("m")+dimStyle.Render(" TLS ⇄ plain")),
		dimStyle.Render("    the port the gate listens on: what " + who + " connects to"),
		row("Xray port", val(fmt.Sprint(up))+edit("u")),
		dimStyle.Render("    the port of the inbound you create in Xray / 3x-ui (loopback only)"),
	}, m.gap())))

	// 2. The other settings
	b.WriteString("\n\n" + m.sec("Gate settings") + "\n")
	b.WriteString(m.box().Render(strings.Join([]string{
		row("Domain", orDash(s.Domain)+edit("e")),
		row("CDN fronting", val(cdnText(s, m.p.ProxyInfo()))+edit("c")),
		row("Leak alert", val(leakText(s.LeakIPs))+edit("t")),
	}, m.gap())))

	// 3. What to type in 3x-ui, and the link to give the app
	b.WriteString("\n\n" + m.sec("In Xray / 3x-ui: create this inbound") + dimStyle.Render("   "+keyBadge.Render("g")+" new example") + "\n")
	b.WriteString(m.box().Render(strings.Join([]string{
		row("Protocol", val("vless")),
		row("Listen IP", val("127.0.0.1")+dimStyle.Render("   never empty or 0.0.0.0")),
		row("Port", val(fmt.Sprint(up))+dimStyle.Render("   ← the Xray port above")),
		row("Transmission", val("WebSocket")),
		row("Path", val(m.exPath)),
		row("Security", val("None")+dimStyle.Render("   the gate does TLS")),
		row("Client id", val(m.exUUID)),
	}, "\n")))

	linkPort, linkTLS, note := ep, etls, ""
	if s.CDN != "" && !etls {
		linkPort, linkTLS = 443, true
		note = "the CDN terminates TLS: clients use 443 with TLS, the CDN forwards plain HTTP to port " + fmt.Sprint(ep)
	} else if !etls {
		note = "no TLS: the traffic is readable on the way (the app shows “Not encrypted”)"
	}
	b.WriteString("\n\n" + m.sec("Client link for the app") + dimStyle.Render("   paste it, then lock with “Server gate”") + "\n")
	b.WriteString(m.box().Render(oversee.ClientLink(s.Domain, linkPort, linkTLS, m.exPath, m.exUUID, "my-server")))
	if note != "" {
		b.WriteString("\n" + dimStyle.Render(note))
	}
	b.WriteString("\n" + dimStyle.Render("CDN, certificate file or no TLS? Read ") + selStyle.Render("6 Guide") + dimStyle.Render("."))
	return b.String()
}

func orNone(s string) string {
	if s == "" {
		return "none"
	}
	return s
}

func onOff(b bool) string {
	if b {
		return "on"
	}
	return "off"
}

func cdnText(s oversee.Settings, i oversee.ProxyListInfo) string {
	if s.CDN == "" {
		return "none (clients connect directly)"
	}
	list := "no IP ranges yet"
	if i.Age >= 0 {
		list = fmt.Sprintf("%d ranges, %s old", i.Count, i.Age.Round(time.Minute))
	}
	return fmt.Sprintf("%s · %s · only-CDN %s  (o toggles)", s.CDN, list, onOff(s.OnlyProxy))
}

func leakText(n int) string {
	if n <= 0 {
		return "off"
	}
	return fmt.Sprintf("warn above %d IPs/day per lock", n)
}

func row(k, v string) string {
	return labelStyle.Render(fmt.Sprintf("%-18s", strings.ToUpper(k))) + v
}

// val is a bold, bright value.
func val(s string) string { return valueStyle.Render(s) }

func orDash(s string) string {
	if strings.TrimSpace(s) == "" {
		return dimStyle.Render("—")
	}
	return valueStyle.Render(s)
}

func orDashPlain(s string) string {
	if strings.TrimSpace(s) == "" {
		return dimStyle.Render("—")
	}
	return s
}

// Run starts the TUI.
func Run(p oversee.Paths) error {
	_, err := tea.NewProgram(New(p), tea.WithAltScreen()).Run()
	return err
}
