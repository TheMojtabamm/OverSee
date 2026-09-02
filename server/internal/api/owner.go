package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"oversea/server/internal/auth"
	"oversea/server/internal/config"
	"oversea/server/internal/lock"
	"oversea/server/internal/store"
)

// OwnerHandler serves the /v1/owner/* endpoints.
type OwnerHandler struct {
	Cfg   config.Config
	Store *store.Store
	Lock  *lock.Service
}

// ---- JWT owner auth middleware ---------------------------------------------

func (h *OwnerHandler) ownerAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !h.Cfg.OwnerAuthEnabled {
			next(w, r)
			return
		}
		authz := r.Header.Get("Authorization")
		token := strings.TrimPrefix(authz, "Bearer ")
		if token == authz || token == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "missing bearer token"})
			return
		}
		oid, err := auth.ParseOwnerToken(h.Cfg.JWTSecret, token)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "invalid or expired token"})
			return
		}
		next(w, r.WithContext(ctxWithOwnerID(r.Context(), oid)))
	}
}

// ---- register / login ------------------------------------------------------

type emailPassReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *OwnerHandler) register(w http.ResponseWriter, r *http.Request) {
	var req emailPassReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "bad request"})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || len(req.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "email required and password >= 6 chars"})
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "hash failed"})
		return
	}
	oid, err := h.Store.CreateOwner(r.Context(), req.Email, string(hash))
	if err != nil {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "email already registered"})
		return
	}
	tok, err := auth.IssueOwnerToken(h.Cfg.JWTSecret, oid, 30*24*time.Hour)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "token issue failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ownerId": oid, "token": tok})
}

func (h *OwnerHandler) login(w http.ResponseWriter, r *http.Request) {
	var req emailPassReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "bad request"})
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	o, err := h.Store.OwnerByEmail(r.Context(), req.Email)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "invalid credentials"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "lookup failed"})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(o.PassHash), []byte(req.Password)) != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "invalid credentials"})
		return
	}
	tok, err := auth.IssueOwnerToken(h.Cfg.JWTSecret, o.ID, 30*24*time.Hour)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "token issue failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ownerId": o.ID, "token": tok})
}

// ---- channels --------------------------------------------------------------

type channelReq struct {
	Title       string `json:"title"`
	AdText      string `json:"adText,omitempty"`
	TelegramURL string `json:"telegramUrl,omitempty"`
}

func (h *OwnerHandler) createChannel(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	var req channelReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "bad request"})
		return
	}
	if strings.TrimSpace(req.Title) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "title required"})
		return
	}
	var adText, tgURL *string
	if req.AdText != "" {
		adText = &req.AdText
	}
	if req.TelegramURL != "" {
		tgURL = &req.TelegramURL
	}
	ref := generateRef(req.Title)
	_, err := h.Store.CreateChannel(r.Context(), oid, ref, req.Title, adText, tgURL)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "create failed: " + err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ref": ref})
}

func (h *OwnerHandler) listChannels(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	chans, err := h.Store.ChannelsByOwner(r.Context(), oid)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "query failed"})
		return
	}
	out := make([]map[string]any, 0, len(chans))
	for _, c := range chans {
		item := channelDTO(c)
		stats, _ := h.channelStats(r, c.ID)
		item["stats"] = stats
		out = append(out, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"channels": out})
}

func (h *OwnerHandler) channelStats(r *http.Request, channelID int64) (map[string]any, error) {
	ctx := r.Context()
	live, err := h.Store.LiveInstallCount(ctx, channelID)
	if err != nil {
		return nil, err
	}
	total, err := h.Store.TotalConnections(ctx, channelID)
	if err != nil {
		return nil, err
	}
	return map[string]any{"liveConnections": live, "totalConnections": total}, nil
}

func (h *OwnerHandler) getChannelStats(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	ref := r.PathValue("ref")
	ch, err := h.Store.ChannelOwnedBy(r.Context(), oid, ref)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "channel not found"})
		return
	}
	stats, err := h.channelStats(r, ch.ID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "stats failed"})
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// ---- blob creation (lock a config) ----------------------------------------

type blobReq struct {
	Config string `json:"config"`
	Title  string `json:"title,omitempty"`
}

func (h *OwnerHandler) createBlob(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	ref := r.PathValue("ref")
	ch, err := h.Store.ChannelOwnedBy(r.Context(), oid, ref)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "channel not found"})
		return
	}
	var req blobReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "bad request"})
		return
	}
	if strings.TrimSpace(req.Config) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "config required"})
		return
	}

	meta := lock.ParseConfigMeta(req.Config)
	if req.Title != "" {
		meta.Title = req.Title
	}

	blobID := newUUID()
	epoch := lock.NowEpoch()
	mk := lock.NewMasterKey(h.Cfg.LOCK_SERVER_KEY)

	locked, err := mk.BuildLockedBlob(h.Cfg.ClientKeyMaterial, blobID, req.Config, meta, epoch)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "lock failed: " + err.Error()})
		return
	}

	if err := h.Store.CreateBlob(r.Context(), store.Blob{
		BlobID:      blobID,
		ChannelID:   ch.ID,
		Epoch:       epoch,
		Protocol:    meta.Protocol,
		PublicTitle: meta.Title,
		PublicHost:  &meta.Host,
		LockedBlob:  locked,
		Status:      "active",
	}); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "persist failed: " + err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"blobId": blobID,
		"locked": locked,
		"meta":   meta,
		"epoch":  epoch,
	})
}

// ---- revoke ----------------------------------------------------------------

func (h *OwnerHandler) revokeBlob(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	blobID := r.PathValue("blobId")
	b, err := h.Store.BlobByID(r.Context(), blobID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "blob not found"})
		return
	}
	ch, err := h.Store.ChannelByID(r.Context(), b.ChannelID)
	if err != nil || ch.OwnerID != oid {
		writeJSON(w, http.StatusForbidden, map[string]any{"error": "not your blob"})
		return
	}
	if err := h.Store.RevokeBlob(r.Context(), blobID); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "revoke failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"revoked": blobID})
}

func (h *OwnerHandler) revokeChannel(w http.ResponseWriter, r *http.Request) {
	oid := ownerIDFromCtx(r.Context())
	ref := r.PathValue("ref")
	ch, err := h.Store.ChannelOwnedBy(r.Context(), oid, ref)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "channel not found"})
		return
	}
	if err := h.Store.RevokeChannel(r.Context(), ch.ID); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "revoke failed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"revoked": ref})
}

// ---- helpers ---------------------------------------------------------------

func generateRef(title string) string {
	base := strings.ToLower(strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		if r == ' ' {
			return '-'
		}
		return -1
	}, strings.TrimSpace(title)))
	if base == "" {
		base = "channel"
	}
	return base + "-" + newUUID()[:6]
}

// Ensure compile-time that referenced helpers exist.
var _ = context.Background
