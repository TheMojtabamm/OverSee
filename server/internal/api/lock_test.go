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
	"oversea/server/internal/store"
)

// newLockServer builds a full Server wired with lock endpoints and returns the
// httptest server plus the store (for seeding).
func newLockServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	cfg := config.Config{
		ListenAddr:       "127.0.0.1:0",
		DBPath:           filepath.Join(t.TempDir(), "lock.db"),
		LOCK_SERVER_KEY:  "test-lock-master-key-123",
		JWTSecret:        "test-jwt-secret",
		OwnerAuthEnabled: false,
		RPS:              10000,
		Burst:            20000,
	}
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { st.Close() })

	srv := New(cfg, st)
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return ts, st
}

// seedLockBlob inserts an owner, a channel and one active blob; returns blobID.
func seedLockBlob(t *testing.T, st *store.Store, blobID string) int64 {
	t.Helper()
	ctx := context.Background()

	if _, err := st.DB().ExecContext(ctx,
		`INSERT INTO owners (email, pass_hash) VALUES (?, ?)`, "owner@lock.local", "x"); err != nil {
		t.Fatalf("insert owner: %v", err)
	}
	var ownerID int64
	if err := st.DB().QueryRowContext(ctx, `SELECT id FROM owners WHERE email=?`, "owner@lock.local").Scan(&ownerID); err != nil {
		t.Fatalf("owner id: %v", err)
	}
	if _, err := st.DB().ExecContext(ctx,
		`INSERT INTO channels (ref, owner_id, title, status) VALUES ('lock-chan', ?, 'Lock Chan', 'active')`,
		ownerID); err != nil {
		t.Fatalf("insert channel: %v", err)
	}
	var channelID int64
	if err := st.DB().QueryRowContext(ctx, `SELECT id FROM channels WHERE ref='lock-chan'`).Scan(&channelID); err != nil {
		t.Fatalf("channel id: %v", err)
	}

	if err := st.CreateBlob(ctx, store.Blob{
		BlobID:      blobID,
		ChannelID:   channelID,
		Epoch:       1,
		Protocol:    "vless",
		PublicTitle: "lock server",
		LockedBlob:  "ENC:lock-blob-data",
		Status:      "active",
	}); err != nil {
		t.Fatalf("insert blob: %v", err)
	}
	return channelID
}

func registerInstall(t *testing.T, ts *httptest.Server) string {
	t.Helper()
	res, err := http.Post(ts.URL+"/v1/app/register", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(res.Body)
		t.Fatalf("register status=%d body=%s", res.StatusCode, b)
	}
	var body struct {
		InstallID string `json:"installId"`
		Token     string `json:"token"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode register: %v", err)
	}
	if body.Token == "" {
		t.Fatal("register returned no token")
	}
	return body.Token
}

func TestLockFullCycle(t *testing.T) {
	ts, st := newLockServer(t)
	blobID := "blob-abc-123"
	seedLockBlob(t, st, blobID)

	token := registerInstall(t, ts)

	// 1) component with valid token + epoch
	req, _ := http.NewRequest("GET", ts.URL+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	req.Header.Set("X-Install-Token", token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("component req: %v", err)
	}
	if res.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(res.Body)
		t.Fatalf("component status=%d body=%s", res.StatusCode, b)
	}
	var comp struct {
		Component string `json:"component"`
	}
	_ = json.NewDecoder(res.Body).Decode(&comp)
	res.Body.Close()
	if comp.Component == "" {
		t.Fatal("expected a non-empty component")
	}

	// 2) status is ok
	res2, _ := http.Get(ts.URL + "/v1/lock/status?blobId=" + blobID)
	var stBody struct {
		Status string `json:"status"`
	}
	_ = json.NewDecoder(res2.Body).Decode(&stBody)
	res2.Body.Close()
	if stBody.Status != "ok" {
		t.Fatalf("status = %q, want ok", stBody.Status)
	}

	// 3) component without a token is rejected
	req3, _ := http.NewRequest("GET", ts.URL+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	res3, _ := http.DefaultClient.Do(req3)
	res3.Body.Close()
	if res3.StatusCode != http.StatusUnauthorized {
		t.Fatalf("no-token status=%d, want 401", res3.StatusCode)
	}

	// 4) BOGUS token rejected
	req4, _ := http.NewRequest("GET", ts.URL+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	req4.Header.Set("X-Install-Token", "not-a-real-token")
	res4, _ := http.DefaultClient.Do(req4)
	res4.Body.Close()
	if res4.StatusCode != http.StatusUnauthorized {
		t.Fatalf("bogus-token status=%d, want 401", res4.StatusCode)
	}
}

func TestLockRevoke(t *testing.T) {
	ts, st := newLockServer(t)
	blobID := "blob-rev-9"
	seedLockBlob(t, st, blobID)
	token := registerInstall(t, ts)

	// Revoke the blob
	if err := st.RevokeBlob(context.Background(), blobID); err != nil {
		t.Fatalf("revoke: %v", err)
	}

	// status should now be revoked
	res, _ := http.Get(ts.URL + "/v1/lock/status?blobId=" + blobID)
	var b struct {
		Status string `json:"status"`
	}
	_ = json.NewDecoder(res.Body).Decode(&b)
	res.Body.Close()
	if b.Status != "revoked" {
		t.Fatalf("status = %q, want revoked", b.Status)
	}

	// component should now be 410 gone even with a valid token
	req, _ := http.NewRequest("GET", ts.URL+"/v1/lock/component?blobId="+blobID+"&epoch=1", nil)
	req.Header.Set("X-Install-Token", token)
	res2, _ := http.DefaultClient.Do(req)
	res2.Body.Close()
	if res2.StatusCode != http.StatusGone {
		t.Fatalf("revoked component status=%d, want 410", res2.StatusCode)
	}
}
