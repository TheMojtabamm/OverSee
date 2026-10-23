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
	for _, want := range []string{"oversee", "Status", "Locks", "Keys", "Setup", "Logs", "add an app key", "set your domain"} {
		if !strings.Contains(v, want) {
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
	if !strings.Contains(m.View(), "CDN fronting") || !strings.Contains(m.View(), "none (clients connect directly)") {
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
