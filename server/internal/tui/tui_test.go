package tui

import (
	"path/filepath"
	"strings"
	"testing"

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
