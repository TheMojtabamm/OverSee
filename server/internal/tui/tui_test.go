package tui

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"oversea/server/internal/gate"
	"oversea/server/internal/oversee"
)

const (
	code = "0123456789abcdef0123456789abcdef"
	fp   = "3FA9-0C21-B7D4-9E10"
)

func newModel(t *testing.T) Model {
	t.Setenv("OVERSEE_DIR", filepath.Join(t.TempDir(), "etc"))
	return New(oversee.DefaultPaths())
}

func key(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "tab":
		return tea.KeyMsg{Type: tea.KeyTab}
	case "down":
		return tea.KeyMsg{Type: tea.KeyDown}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
}

func send(m Model, keys ...string) Model {
	for _, k := range keys {
		nm, _ := m.Update(key(k))
		m = nm.(Model)
	}
	return m
}

func typ(m Model, text string) Model {
	for _, r := range text {
		nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
		m = nm.(Model)
	}
	return m
}

func TestEmptyStatusTellsWhatToDo(t *testing.T) {
	v := newModel(t).View()
	for _, want := range []string{"oversee", "Status", "Locks", "Keys", "Setup", "Logs", "Guide", "Needs attention", "No app key"} {
		if !strings.Contains(strings.ToLower(v), strings.ToLower(want)) {
			t.Errorf("missing %q in:\n%s", want, v)
		}
	}
}

func TestAddAndRevokeLockThroughTheUI(t *testing.T) {
	m := newModel(t)
	m = send(m, "2", "a") // Locks tab, add
	m = typ(m, code+" "+fp+" my-channel")
	m = send(m, "enter")

	locks, _ := m.p.Locks()
	if len(locks) != 1 || locks[0].CreatorFp != fp {
		t.Fatalf("lock not saved: %v", locks)
	}
	v := m.View()
	if !strings.Contains(v, gate.CodeID(code)) || !strings.Contains(v, "my-channel") {
		t.Fatalf("lock not shown:\n%s", v)
	}

	m = send(m, "d")
	if !strings.Contains(m.View(), "Revoke") {
		t.Fatal("must ask before revoking")
	}
	m = send(m, "n") // anything but y cancels
	if l, _ := m.p.Locks(); len(l) != 1 {
		t.Fatal("cancel must keep the lock")
	}
	m = send(m, "d", "y")
	if l, _ := m.p.Locks(); len(l) != 0 {
		t.Fatalf("revoke failed: %v", l)
	}
}

func TestBadLockLineKeepsTheInputOpenWithAnError(t *testing.T) {
	m := newModel(t)
	m = send(m, "2", "a")
	m = typ(m, "not a valid line")
	m = send(m, "enter")
	if m.mode != modeAddLock || !m.msgIsErr {
		t.Fatalf("should stay in input with an error, mode=%v msg=%q", m.mode, m.msg)
	}
	if l, _ := m.p.Locks(); len(l) != 0 {
		t.Fatal("nothing may be saved")
	}
	m = send(m, "esc")
	if m.mode != modeBrowse {
		t.Fatal("esc must leave the input")
	}
}

func TestKeysGenerateSaveAndRemove(t *testing.T) {
	m := newModel(t)
	m = send(m, "3", "g") // Keys tab, generate -> prefilled input
	if m.input.Value() == "" || m.mode != modeAddKey {
		t.Fatal("generate must prefill the input")
	}
	m = send(m, "enter")
	keys, _ := m.p.ListKeys()
	if len(keys) != 1 || len(keys[0]) != 32 {
		t.Fatalf("%v", keys)
	}
	v := m.View()
	if strings.Contains(v, keys[0]) {
		t.Fatal("the key must be masked on screen")
	}
	if !strings.Contains(v, "current") {
		t.Fatal("newest key labelled current")
	}
	m = send(m, "d", "y")
	if k, _ := m.p.ListKeys(); len(k) != 0 {
		t.Fatal("remove failed")
	}
}

func TestSetupSavesDomainAndShowsMatchingLink(t *testing.T) {
	m := newModel(t)
	m = send(m, "4", "e")
	m = typ(m, "vpn.example.com")
	m = send(m, "enter")
	if m.p.LoadSettings().Domain != "vpn.example.com" {
		t.Fatal("domain not saved")
	}
	v := m.View()
	if !strings.Contains(v, "vless://") || !strings.Contains(v, "vpn.example.com") || !strings.Contains(v, m.exUUID) {
		t.Fatalf("setup view should show the matching link:\n%s", v)
	}
}

func TestTabNavigationAndQuit(t *testing.T) {
	m := newModel(t)
	for i := 0; i < len(tabNames); i++ {
		m = send(m, "tab")
	}
	if m.tab != tabStatus {
		t.Fatalf("tab should wrap, got %v", m.tab)
	}
	_, cmd := m.Update(key("q"))
	if cmd == nil {
		t.Fatal("q must quit")
	}
	if msg := cmd(); msg != (tea.QuitMsg{}) {
		t.Fatalf("expected QuitMsg, got %T", msg)
	}
}

func TestLocksShowLiveStatsAndLeakWarning(t *testing.T) {
	m := newModel(t)
	m.p.AddLock(code + " " + fp + " ch")
	m.p.SaveSettings(oversee.Settings{Upstream: "127.0.0.1:10000", LeakIPs: 5})

	st := gate.NewStats()
	now := time.Now()
	for i := 0; i < 9; i++ { // 9 distinct IPs > threshold 5
		st.AcceptForTest(gate.CodeID(code), fmt.Sprintf("10.0.0.%d", i), now)
	}
	if err := st.WriteOnce(m.p.Stats); err != nil {
		t.Fatal(err)
	}
	m.refresh()
	m = send(m, "2")
	v := m.View()
	if !strings.Contains(v, "shared?") || !strings.Contains(v, "more than 5 IPs") {
		t.Fatalf("leak warning missing:\n%s", v)
	}

	// below the threshold: no warning
	m.p.SaveSettings(oversee.Settings{Upstream: "127.0.0.1:10000", LeakIPs: 50})
	m.refresh()
	if strings.Contains(m.View(), "shared?") {
		t.Fatal("no warning expected under the threshold")
	}
	// alert off
	m.p.SaveSettings(oversee.Settings{Upstream: "127.0.0.1:10000"})
	m.refresh()
	if strings.Contains(m.View(), "shared?") {
		t.Fatal("alert off must not warn")
	}
}

func TestLeakThresholdEditValidates(t *testing.T) {
	m := newModel(t)
	m = send(m, "4", "t")
	m.input.SetValue("abc")
	m = send(m, "enter")
	if m.mode != modeEditLeak || !m.msgIsErr {
		t.Fatal("non-number must stay in the input with an error")
	}
	m.input.SetValue("150")
	m = send(m, "enter")
	if m.p.LoadSettings().LeakIPs != 150 {
		t.Fatal("not saved")
	}
}

func TestSetupCDNControls(t *testing.T) {
	m := newModel(t)
	m = send(m, "4")
	if !strings.Contains(strings.ToLower(m.View()), "cdn fronting") || !strings.Contains(m.View(), "none (clients connect directly)") {
		t.Fatalf("default view:\n%s", m.View())
	}
	m = send(m, "o") // only-CDN without a CDN must be refused with a hint
	if !m.msgIsErr || m.p.LoadSettings().OnlyProxy {
		t.Fatal("only-CDN needs a CDN first")
	}
	m = send(m, "c") // cloudflare
	if m.p.LoadSettings().CDN != "cloudflare" || !strings.Contains(m.View(), "cloudflare") {
		t.Fatalf("%+v", m.p.LoadSettings())
	}
	m = send(m, "o")
	if !m.p.LoadSettings().OnlyProxy || !strings.Contains(m.View(), "only-CDN on") {
		t.Fatal("only-CDN should be on")
	}
	m = send(m, "c", "c", "c") // fastly, generic, back to none
	if s := m.p.LoadSettings(); s.CDN != "" || s.OnlyProxy {
		t.Fatalf("cycling back to none must also switch only-CDN off: %+v", s)
	}
}

func TestGuideTabListsTheSetupsAndScrolls(t *testing.T) {
	m := newModel(t)
	m = send(m, "6")
	if m.tab != tabGuide {
		t.Fatalf("6 should open the guide, got tab %v", m.tab)
	}
	v := m.View()
	for _, want := range []string{"How it works", "Ports (entry vs Xray)", "Direct + TLS", "CDN (Cloudflare)", "No TLS (plain)", "Own certificate", "Check & fix"} {
		if !strings.Contains(v, want) {
			t.Errorf("guide topic list is missing %q:\n%s", want, v)
		}
	}
	// pick the CDN topic: it must teach the real commands
	m = send(m, "down", "down", "down")
	v = m.View()
	for _, want := range []string{"Cloudflare", "oversee set cdn cloudflare", "oversee cdn-test", "Origin"} {
		if !strings.Contains(v, want) {
			t.Errorf("CDN topic is missing %q:\n%s", want, v)
		}
	}
	// the no-TLS topic names the plain mode command
	m = send(m, "down", "down")
	if !strings.Contains(m.View(), "oversee set plain :1001") {
		t.Errorf("no-TLS topic should show 'oversee set plain':\n%s", m.View())
	}
}

func TestGuideCommandsAreRealOnes(t *testing.T) {
	// Every `oversee set <name>` the guide teaches must be a setting the CLI accepts.
	valid := map[string]bool{"domain": true, "upstream": true, "plain": true, "port": true, "leak-ips": true, "cdn": true, "only-proxy": true, "token-days": true, "cert": true, "key": true}
	for _, g := range guideTopics {
		for _, line := range strings.Split(g.body, "\n") {
			i := strings.Index(line, "oversee set ")
			if i < 0 || !strings.HasPrefix(line, "$ ") {
				continue
			}
			name := strings.Fields(line[i+len("oversee set "):])[0]
			if !valid[name] {
				t.Errorf("guide topic %q teaches an unknown setting %q", g.title, name)
			}
		}
	}
}

func TestSetupShowsEntryAndXrayPortsAndEditsThem(t *testing.T) {
	m := newModel(t)
	m = send(m, "4") // Setup
	v := m.View()
	for _, want := range []string{"ENTRY PORT", "XRAY PORT", "GATE :443", "127.0.0.1:10000", "LISTEN IP"} {
		if !strings.Contains(v, want) {
			t.Fatalf("setup should show %q:\n%s", want, v)
		}
	}
	// switch to plain (the Cloudflare Flexible case) and use 8080
	m = send(m, "m")
	if got := m.p.LoadSettings().Plain; got != ":80" {
		t.Fatalf("TLS→plain should pick :80, got %q", got)
	}
	m = send(m, "p")
	m.input.SetValue("")
	m = typ(m, "8080")
	m = send(m, "enter")
	st := m.p.LoadSettings()
	if st.Plain != ":8080" {
		t.Fatalf("entry port edit: %+v", st)
	}
	if p, tls := st.EntryPort(); p != 8080 || tls {
		t.Fatalf("EntryPort = %d %v", p, tls)
	}
	// the Xray port: a bare number means loopback
	m = send(m, "u")
	m.input.SetValue("")
	m = typ(m, "12345")
	m = send(m, "enter")
	if got := m.p.LoadSettings().Upstream; got != "127.0.0.1:12345" {
		t.Fatalf("upstream = %q", got)
	}
	v = m.View()
	for _, want := range []string{"GATE :8080 (plain HTTP)", "127.0.0.1:12345", "security=none"} {
		if !strings.Contains(v, want) {
			t.Fatalf("setup should show %q after the edits:\n%s", want, v)
		}
	}
	// behind a CDN the client link uses 443 + TLS even though the gate is plain on 8080
	m.p.SetSetting("cdn", "cloudflare")
	m.refresh()
	v = m.View()
	if !strings.Contains(v, ":443?") || !strings.Contains(v, "security=tls") || !strings.Contains(v, "CDN terminates TLS") {
		t.Fatalf("CDN + plain entry: link should be 443/TLS:\n%s", v)
	}
	// a bad port is refused and the input stays open
	m = send(m, "p")
	m.input.SetValue("99999")
	m = send(m, "enter")
	if m.mode != modeEditPort || !m.msgIsErr {
		t.Fatalf("a bad port must keep the prompt open with an error (mode %v, msg %q)", m.mode, m.msg)
	}
}

func TestSwitchingToTLSNeedsADomainOrCertificate(t *testing.T) {
	m := newModel(t)
	m.p.SetSetting("plain", ":8080")
	m.refresh()
	m = send(m, "4", "m")
	if m.p.LoadSettings().Plain == "" || !m.msgIsErr {
		t.Fatalf("TLS without domain/cert must be refused: %+v %q", m.p.LoadSettings(), m.msg)
	}
	m.p.SetSetting("domain", "vpn.example.com")
	m.refresh()
	m = send(m, "m")
	if p, tls := m.p.LoadSettings().EntryPort(); !tls || p != 8080 {
		t.Fatalf("plain→TLS should keep the port, got %d tls=%v", p, tls)
	}
}
