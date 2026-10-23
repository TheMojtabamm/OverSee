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
)

var tabNames = []string{"Status", "Locks", "Keys", "Setup", "Logs"}

var (
	accent = lipgloss.Color("#38E1D4")
	dim    = lipgloss.Color("#7a8591")
	bad    = lipgloss.Color("#ff6b6b")
	good   = lipgloss.Color("#5fd38d")
	warn   = lipgloss.Color("#f5c451")

	titleStyle  = lipgloss.NewStyle().Bold(true).Foreground(accent)
	tabOn       = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#0b0f14")).Background(accent).Padding(0, 1)
	tabOff      = lipgloss.NewStyle().Foreground(dim).Padding(0, 1)
	dimStyle    = lipgloss.NewStyle().Foreground(dim)
	badStyle    = lipgloss.NewStyle().Foreground(bad)
	goodStyle   = lipgloss.NewStyle().Foreground(good)
	warnStyle   = lipgloss.NewStyle().Foreground(warn)
	selStyle    = lipgloss.NewStyle().Bold(true).Foreground(accent)
	boxStyle    = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(dim).Padding(0, 1)
	helpStyle   = lipgloss.NewStyle().Foreground(dim)
	headerStyle = lipgloss.NewStyle().Bold(true)
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

	sel      int // selection in Locks / Keys
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
		m.sel, m.msg = 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "shift+tab", "left", "h":
		m.tab = (m.tab + tab(len(tabNames)) - 1) % tab(len(tabNames))
		m.sel, m.msg = 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "1", "2", "3", "4", "5":
		m.tab = tab(int(s[0] - '1'))
		m.sel, m.msg = 0, ""
		if m.tab == tabLogs {
			m.logs = oversee.Logs(30)
		}
		return m, nil
	case "up", "k":
		if m.sel > 0 {
			m.sel--
		}
		return m, nil
	case "down", "j":
		if m.sel < m.listLen()-1 {
			m.sel++
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
			m.input.SetValue(m.settings.Upstream)
			m.input.Placeholder = "127.0.0.1:10000"
			m.input.Focus()
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
		case modeEditDomain, modeEditUpstream, modeEditLeak:
			s := m.settings
			switch m.mode {
			case modeEditDomain:
				s.Domain = val
			case modeEditUpstream:
				s.Upstream = val
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

func (m Model) View() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render("◆ oversee") + dimStyle.Render("  gate manager") + "\n\n")

	var tabs []string
	for i, n := range tabNames {
		label := fmt.Sprintf("%d %s", i+1, n)
		if tab(i) == m.tab {
			tabs = append(tabs, tabOn.Render(label))
		} else {
			tabs = append(tabs, tabOff.Render(label))
		}
	}
	b.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, tabs...) + "\n\n")

	switch m.tab {
	case tabStatus:
		b.WriteString(m.viewStatus())
	case tabLocks:
		b.WriteString(m.viewLocks())
	case tabKeys:
		b.WriteString(m.viewKeys())
	case tabSetup:
		b.WriteString(m.viewSetup())
	case tabLogs:
		b.WriteString(boxStyle.Render(orDash(m.logs)))
	}

	b.WriteString("\n")
	switch m.mode {
	case modeAddLock, modeAddKey, modeEditDomain, modeEditUpstream, modeEditLeak:
		b.WriteString("\n" + m.input.View() + "\n" + helpStyle.Render("enter save · esc cancel") + "\n")
	case modeConfirmRevoke:
		if m.sel < len(m.locks) {
			l := m.locks[m.sel]
			b.WriteString("\n" + warnStyle.Render(fmt.Sprintf("Revoke %s (%s)? All copies of this lock stop working. [y/N]", l.CodeID, orDash(l.Note))) + "\n")
		}
	case modeConfirmKeyDelete:
		b.WriteString("\n" + warnStyle.Render("Remove this app key? Apps built with it will be refused. [y/N]") + "\n")
	}
	if m.msg != "" {
		st := goodStyle
		if m.msgIsErr {
			st = badStyle
		}
		b.WriteString("\n" + st.Render(m.msg) + "\n")
	}
	b.WriteString("\n" + helpStyle.Render(m.help()) + "\n")
	return b.String()
}

func (m Model) help() string {
	base := "tab/←→ switch · 1-5 jump · r refresh · q quit"
	switch m.tab {
	case tabStatus:
		return "s start · x stop · R restart · e enable · D disable · " + base
	case tabLocks:
		return "↑↓ select · a add · d revoke · " + base
	case tabKeys:
		return "↑↓ select · n new · g generate · d remove · " + base
	case tabSetup:
		return "e domain · u upstream · t leak alert · g new example · " + base
	}
	return base
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
		row("Gate service", state+dimStyle.Render("  (boot: "+m.svc.Enabled+")")),
		row("Domain", orDash(m.settings.Domain)),
		row("Upstream (Xray)", m.settings.Upstream),
		row("Locks allowed", fmt.Sprint(len(m.locks))),
		row("App keys", fmt.Sprint(len(m.keys))),
		row("Config dir", m.p.Dir),
	}
	out := boxStyle.Render(strings.Join(rows, "\n"))
	var todo []string
	if len(m.keys) == 0 {
		todo = append(todo, "• add an app key  →  Keys (the gate refuses everyone until one exists)")
	}
	if m.settings.Domain == "" && m.settings.Plain == "" {
		todo = append(todo, "• set your domain  →  Setup")
	}
	if len(m.locks) == 0 {
		todo = append(todo, "• add a lock line from the app  →  Locks")
	}
	if len(todo) > 0 {
		out += "\n\n" + headerStyle.Render("Next steps") + "\n" + warnStyle.Render(strings.Join(todo, "\n"))
	}
	return out
}

func (m Model) viewLocks() string {
	if len(m.locks) == 0 {
		return dimStyle.Render("No locks yet. In the app: Share → Lock → Server gate, then press ") + selStyle.Render("a") + dimStyle.Render(" and paste the line it shows.")
	}
	var lines []string
	lines = append(lines, dimStyle.Render(fmt.Sprintf("  %-18s %-21s %7s %6s  %s", "LOCK ID", "CREATOR", "CONNS", "IPs", "NOTE")))
	leaks := 0
	for i, l := range m.locks {
		cur := "  "
		st := lipgloss.NewStyle()
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
	out := boxStyle.Render(strings.Join(lines, "\n"))
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
		return intro + warnStyle.Render("No key yet — every connection is refused. Press ") + selStyle.Render("n") + warnStyle.Render(" to add the GATE_KEY your app was built with, or ") + selStyle.Render("g") + warnStyle.Render(" to generate one.")
	}
	var lines []string
	for i, k := range m.keys {
		cur, st := "  ", lipgloss.NewStyle()
		if i == m.sel {
			cur, st = "▸ ", selStyle
		}
		tag := dimStyle.Render("  previous")
		if i == 0 {
			tag = goodStyle.Render("  current")
		}
		lines = append(lines, cur+st.Render(oversee.MaskKey(k))+tag)
	}
	return intro + boxStyle.Render(strings.Join(lines, "\n"))
}

func (m Model) viewSetup() string {
	s := m.settings
	port := 10000
	if i := strings.LastIndex(s.Upstream, ":"); i >= 0 {
		fmt.Sscanf(s.Upstream[i+1:], "%d", &port)
	}
	var b strings.Builder
	b.WriteString(boxStyle.Render(strings.Join([]string{
		row("Domain", orDash(s.Domain)+dimStyle.Render("   e to edit")),
		row("Upstream", s.Upstream+dimStyle.Render("   u to edit")),
		row("Leak alert", leakText(s.LeakIPs)+dimStyle.Render("   t to edit")),
	}, "\n")))
	b.WriteString("\n\n" + headerStyle.Render("Xray inbound to put behind the gate") + dimStyle.Render("  (listens on loopback; the gate does TLS)") + "\n")
	b.WriteString(boxStyle.Render(oversee.XrayInbound(port, m.exPath, m.exUUID)))
	b.WriteString("\n\n" + headerStyle.Render("Matching client link") + dimStyle.Render("  (paste into the app, then lock it with “Server gate”)") + "\n")
	b.WriteString(boxStyle.Render(oversee.ClientLink(s.Domain, m.exPath, m.exUUID, "my-server")))
	return b.String()
}

func leakText(n int) string {
	if n <= 0 {
		return "off"
	}
	return fmt.Sprintf("warn above %d IPs/day per lock", n)
}

func row(k, v string) string {
	return fmt.Sprintf("%s  %s", headerStyle.Render(fmt.Sprintf("%-16s", k)), v)
}

func orDash(s string) string {
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
