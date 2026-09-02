package api

import (
	"encoding/json"
	"net/http"
	"strings"

	"oversea/server/internal/auth"
)

// RegisterRequest is the body of POST /v1/app/register. The installId is
// optional; the server generates one when absent.
type RegisterRequest struct {
	InstallID string `json:"installId"`
}

// register handles POST /v1/app/register. It issues a fresh opaque install
// token (returned once) and stores only its sha256 hash, so a leaked DB never
// exposes usable tokens. The raw token is handed to the app exactly once.
func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}

	installID := strings.TrimSpace(req.InstallID)
	if installID == "" {
		installID = newUUID()
	}

	token, hash, err := auth.NewInstallToken()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": "could not generate token",
		})
		return
	}

	if err := s.store.CreateInstall(r.Context(), installID, hash); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]any{
			"error": "could not register install",
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"installId": installID,
		"token":     token,
	})
}
