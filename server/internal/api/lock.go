package api

import (
	"errors"
	"net/http"
	"strconv"

	"oversea/server/internal/lock"
)

// LockHandler serves the lock endpoints. It holds a lock.Service (derivation +
// store logic) and the store for rate/install context it may need.
type LockHandler struct {
	svc *lock.Service
}

// component handles GET /v1/lock/component?blobId=&epoch=
// Requires an install token (see server wiring). Returns the server component
// for the (blobId, epoch) pair, or 404/410 if the blob is unknown/revoked.
func (h *LockHandler) component(w http.ResponseWriter, r *http.Request) {
	blobID := r.URL.Query().Get("blobId")
	if blobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "blobId is required"})
		return
	}
	epochStr := r.URL.Query().Get("epoch")
	if epochStr == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "epoch is required"})
		return
	}
	epoch, err := strconv.ParseInt(epochStr, 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "epoch must be an integer"})
		return
	}

	installID := installIDFrom(r)
	comp, err := h.svc.Component(r.Context(), installID, blobID, epoch)
	if err != nil {
		switch {
		case errors.Is(err, lock.ErrUnknownBlob):
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "unknown blob"})
		case errors.Is(err, lock.ErrRevoked):
			writeJSON(w, http.StatusGone, map[string]any{"error": "blob revoked"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "internal error"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"blobId":    blobID,
		"epoch":     epoch,
		"component": comp,
	})
}

// status handles GET /v1/lock/status?blobId=
// Returns whether a blob is currently openable. Public (no token) is fine since
// it only reveals a boolean, not any secret.
func (h *LockHandler) status(w http.ResponseWriter, r *http.Request) {
	blobID := r.URL.Query().Get("blobId")
	if blobID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "blobId is required"})
		return
	}
	status, err := h.svc.Status(r.Context(), blobID)
	if err != nil {
		if errors.Is(err, lock.ErrUnknownBlob) {
			writeJSON(w, http.StatusNotFound, map[string]any{"error": "unknown blob", "status": "unknown"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": "internal error"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"blobId": blobID, "status": status})
}
