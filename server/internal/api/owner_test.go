package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"oversea/server/internal/config"
	"oversea/server/internal/lock"
	"oversea/server/internal/store"
)

func newOwnerServer(t *testing.T) *httptest.Server {
	t.Helper()
	cfg := config.Config{
		ListenAddr:        "127.0.0.1:0",
		DBPath:            filepath.Join(t.TempDir(), "owner.db"),
		LOCK_SERVER_KEY:   "owner-test-key-12345",
		ClientKeyMaterial: "test-client-key-material",
		JWTSecret:         "owner-test-jwt-secret",
		OwnerAuthEnabled:  true,
		RPS:               10000,
		Burst:             20000,
	}
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

// do is a test helper for making requests and reading JSON responses.
func do(t *testing.T, method, url, body, token string) (int, map[string]any) {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, url, r)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do request: %v", err)
	}
	defer res.Body.Close()
	var m map[string]any
	json.NewDecoder(res.Body).Decode(&m)
	return res.StatusCode, m
}

func TestOwnerFullFlow(t *testing.T) {
	ts := newOwnerServer(t)
	B := ts.URL

	// 1) Register owner
	code, body := do(t, "POST", B+"/v1/owner/register",
		`{"email":"test@oversea.app","password":"secret123"}`, "")
	if code != 200 {
		t.Fatalf("register: %d %v", code, body)
	}
	token := body["token"].(string)
	if token == "" {
		t.Fatal("no token from register")
	}

	// 2) Login with same credentials
	code, body = do(t, "POST", B+"/v1/owner/login",
		`{"email":"test@oversea.app","password":"secret123"}`, "")
	if code != 200 {
		t.Fatalf("login: %d %v", code, body)
	}
	token2 := body["token"].(string)
	if token2 == "" {
		t.Fatal("no token from login")
	}

	// 3) Wrong password fails
	code, _ = do(t, "POST", B+"/v1/owner/login",
		`{"email":"test@oversea.app","password":"wrong"}`, "")
	if code != 401 {
		t.Fatalf("wrong password should be 401, got %d", code)
	}

	// 4) Create a channel
	code, body = do(t, "POST", B+"/v1/owner/channels",
		`{"title":"My VPN Channel","adText":"Join us!","telegramUrl":"https://t.me/myvpn"}`, token)
	if code != 200 {
		t.Fatalf("create channel: %d %v", code, body)
	}
	ref := body["ref"].(string)
	if ref == "" {
		t.Fatal("no ref from create channel")
	}

	// 5) List channels
	code, body = do(t, "GET", B+"/v1/owner/channels", "", token)
	if code != 200 {
		t.Fatalf("list channels: %d", code)
	}
	chans := body["channels"].([]any)
	if len(chans) != 1 {
		t.Fatalf("expected 1 channel, got %d", len(chans))
	}

	// 6) Create a locked blob
	code, body = do(t, "POST", B+"/v1/owner/channels/"+ref+"/blobs",
		`{"config":"vless://uuid@1.2.3.4:443?security=tls#MyServer","title":"My Server"}`, token)
	if code != 200 {
		t.Fatalf("create blob: %d %v", code, body)
	}
	blobID := body["blobId"].(string)
	locked := body["locked"].(string)
	if blobID == "" || locked == "" {
		t.Fatalf("blobId=%q locked=%q", blobID, locked)
	}

	// Verify the locked blob is decodable
	env, err := lock.DecodeBlob(locked)
	if err != nil {
		t.Fatalf("DecodeBlob: %v", err)
	}
	if env.BlobID != blobID {
		t.Fatalf("blob envelope blobId=%q, want %q", env.BlobID, blobID)
	}
	if env.Protocol != "vless" {
		t.Fatalf("protocol=%q, want vless", env.Protocol)
	}

	// 7) Channel stats
	code, body = do(t, "GET", B+"/v1/owner/channels/"+ref+"/stats", "", token)
	if code != 200 {
		t.Fatalf("channel stats: %d %v", code, body)
	}
	if body["totalConnections"] != float64(0) {
		t.Fatalf("total connections should be 0, got %v", body["totalConnections"])
	}

	// 8) Feed shows the channel and blob (public endpoint)
	code, body = do(t, "GET", B+"/v1/channels", "", "")
	if code != 200 {
		t.Fatalf("feed channels: %d", code)
	}

	code, body = do(t, "GET", B+"/v1/channels/"+ref+"/configs", "", "")
	if code != 200 {
		t.Fatalf("feed configs: %d", code)
	}
	configs := body["configs"].([]any)
	if len(configs) != 1 {
		t.Fatalf("expected 1 config, got %d", len(configs))
	}

	// 9) Lock component with install token
	_, regBody := do(t, "POST", B+"/v1/app/register", `{}`, "")
	installToken := regBody["token"].(string)
	req, _ := http.NewRequest("GET", B+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	req.Header.Set("X-Install-Token", installToken)
	res, _ := http.DefaultClient.Do(req)
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("lock component: %d", res.StatusCode)
	}

	// 10) Revoke blob
	code, body = do(t, "DELETE", B+"/v1/owner/blobs/"+blobID, "", token)
	if code != 200 {
		t.Fatalf("revoke blob: %d %v", code, body)
	}

	// 11) After revoke: status is revoked
	code, body = do(t, "GET", B+"/v1/lock/status?blobId="+blobID, "", "")
	if code != 200 {
		t.Fatalf("lock status: %d", code)
	}
	if body["status"] != "revoked" {
		t.Fatalf("status=%v, want revoked", body["status"])
	}

	// 12) Component returns 410 Gone for revoked blob
	req2, _ := http.NewRequest("GET", B+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	req2.Header.Set("X-Install-Token", installToken)
	res2, _ := http.DefaultClient.Do(req2)
	res2.Body.Close()
	if res2.StatusCode != http.StatusGone {
		t.Fatalf("revoked component: %d, want 410", res2.StatusCode)
	}

	// 13) Unauthenticated owner requests are rejected
	code, _ = do(t, "GET", B+"/v1/owner/channels", "", "")
	if code != 401 {
		t.Fatalf("unauth list channels: %d, want 401", code)
	}

	// 14) Seed idempotency: create owner with same seed shouldn't fail
	// (tested implicitly by server startup; we verify register duplicate fails)
	code, _ = do(t, "POST", B+"/v1/owner/register",
		`{"email":"test@oversea.app","password":"secret123"}`, "")
	if code != 409 {
		t.Fatalf("duplicate register: %d, want 409", code)
	}

	// Suppress unused import warning.
	_ = context.Background()
}
