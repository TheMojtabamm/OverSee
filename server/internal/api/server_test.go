package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"oversea/server/internal/config"
	"oversea/server/internal/store"
)

func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	cfg := config.Config{
		ListenAddr:       "127.0.0.1:0",
		DBPath:           "", // in-memory via temp handled in helper
		LOCK_SERVER_KEY:  "test-lock-key",
		JWTSecret:        "test-jwt-secret",
		OwnerAuthEnabled: false,
		RPS:              1000,
		Burst:            2000,
	}
	// Use an on-disk temp file so migrations can run.
	dir := t.TempDir()
	cfg.DBPath = dir + "/test.db"
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { st.Close() })

	srv := New(cfg, st)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts
}

func TestHealthOK(t *testing.T) {
	ts := newTestServer(t)
	res, err := http.Get(ts.URL + "/v1/health")
	if err != nil {
		t.Fatalf("GET /v1/health: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	var body map[string]any
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("status field = %v, want ok", body["status"])
	}
	if body["service"] != "oversea" {
		t.Fatalf("service field = %v, want oversea", body["service"])
	}
}

func TestUnknownRoute404(t *testing.T) {
	ts := newTestServer(t)
	res, err := http.Get(ts.URL + "/v1/nope")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", res.StatusCode)
	}
}

func TestHealthReportsOKJSON(t *testing.T) {
	ts := newTestServer(t)
	res, err := http.Get(ts.URL + "/v1/health")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer res.Body.Close()
	ct := res.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("content-type = %q, want application/json", ct)
	}
}
