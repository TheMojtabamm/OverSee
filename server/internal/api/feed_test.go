package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"oversea/server/internal/store"
)

// seedChannel inserts a channel + one blob directly via SQL so the feed tests
// don't depend on the owner endpoints (added in a later phase).
func seedChannel(t *testing.T, st *store.Store, ref, title string) {
	t.Helper()
	ctx := context.Background()

	// Insert an owner row (no password hashing needed for this test).
	_, err := st.DB().ExecContext(ctx,
		`INSERT INTO owners (email, pass_hash) VALUES (?, ?)`, ref+"@test.local", "x")
	if err != nil {
		t.Fatalf("insert owner: %v", err)
	}
	var ownerID int64
	if err := st.DB().QueryRowContext(ctx, `SELECT id FROM owners WHERE email=?`, ref+"@test.local").Scan(&ownerID); err != nil {
		t.Fatalf("get owner id: %v", err)
	}

	if _, err := st.DB().ExecContext(ctx,
		`INSERT INTO channels (ref, owner_id, title, telegram_url, ad_text, status)
		 VALUES (?, ?, ?, ?, ?, 'active')`,
		ref, ownerID, title, "https://t.me/"+ref, "Join our channel"); err != nil {
		t.Fatalf("insert channel: %v", err)
	}
	var channelID int64
	if err := st.DB().QueryRowContext(ctx, `SELECT id FROM channels WHERE ref=?`, ref).Scan(&channelID); err != nil {
		t.Fatalf("get channel id: %v", err)
	}

	if err := st.CreateBlob(ctx, store.Blob{
		BlobID:      ref + "-blob-1",
		ChannelID:   channelID,
		Epoch:       1,
		Protocol:    "vless",
		PublicTitle: title + " server",
		LockedBlob:  "ENC:" + ref + "-locked-data",
		Status:      "active",
	}); err != nil {
		t.Fatalf("insert blob: %v", err)
	}
}

func newFeedTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	// DB() accessor must exist; if not, we adjust below.
	st, err := store.Open(filepath.Join(t.TempDir(), "feed_test.db"))
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { st.Close() })

	// ensure a channel exists via helper regardless of DB() availability
	seedChannel(t, st, "chan1", "Channel One")

	srv := &feedServer{store: st}
	ts := httptest.NewServer(srv.routes())
	t.Cleanup(ts.Close)
	return ts
}

// feedServer is a minimal wrapper exposing the feed handlers over an in-memory router.
type feedServer struct {
	store *store.Store
}

func (fs *feedServer) routes() http.Handler {
	mux := http.NewServeMux()
	f := &FeedHandler{Store: fs.store}
	mux.HandleFunc("GET /v1/channels", f.ListChannels)
	mux.HandleFunc("GET /v1/channels/{ref}/configs", f.GetConfigs)
	return mux
}

func TestFeedListChannels(t *testing.T) {
	ts := newFeedTestServer(t)
	res, err := http.Get(ts.URL + "/v1/channels")
	if err != nil {
		t.Fatalf("GET /v1/channels: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	var body struct {
		Channels []map[string]any `json:"channels"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body.Channels) == 0 {
		t.Fatal("expected at least one channel")
	}
	first := body.Channels[0]
	if first["ref"] != "chan1" {
		t.Fatalf("ref = %v, want chan1", first["ref"])
	}
	if first["configCount"] != float64(1) {
		t.Fatalf("configCount = %v, want 1", first["configCount"])
	}
}

func TestFeedGetConfigs(t *testing.T) {
	ts := newFeedTestServer(t)
	res, err := http.Get(ts.URL + "/v1/channels/chan1/configs")
	if err != nil {
		t.Fatalf("GET configs: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", res.StatusCode)
	}
	var body struct {
		Configs []map[string]any `json:"configs"`
		Ad      map[string]any   `json:"ad"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(body.Configs) != 1 {
		t.Fatalf("configs len = %d, want 1", len(body.Configs))
	}
	if body.Configs[0]["data"] != "ENC:chan1-locked-data" {
		t.Fatalf("config data = %v", body.Configs[0]["data"])
	}
	if body.Ad["text"] != "Join our channel" {
		t.Fatalf("ad text = %v", body.Ad["text"])
	}
	if body.Ad["telegramUrl"] != "https://t.me/chan1" {
		t.Fatalf("ad telegramUrl = %v", body.Ad["telegramUrl"])
	}
}

func TestFeedGetConfigsNotFound(t *testing.T) {
	ts := newFeedTestServer(t)
	res, err := http.Get(ts.URL + "/v1/channels/missing/configs")
	if err != nil {
		t.Fatalf("GET configs: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", res.StatusCode)
	}
}
