package api

import (
	"context"
	"net/http"
	"strings"
	"time"

	"oversea/server/internal/auth"
)

type installIDKey struct{}

// installIDFrom returns the install ID stored in the request context by
// the installTokenAuth middleware.
func installIDFrom(r *http.Request) string {
	if id, ok := r.Context().Value(installIDKey{}).(string); ok {
		return id
	}
	return ""
}

// installTokenAuth is a middleware that validates the install token carried in
// the Authorization header (Bearer <token>) or the X-Install-Token header.
// On success it stores the install ID in the request context.
func (s *Server) installTokenAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := extractInstallToken(r)
		if token == "" {
			writeJSON(w, http.StatusUnauthorized, map[string]any{
				"error": "missing install token",
			})
			return
		}

		hash := auth.HashToken(token)
		ok, err := s.store.InstallHashValid(r.Context(), hash)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{
				"error": "auth lookup failed",
			})
			return
		}
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]any{
				"error": "invalid install token",
			})
			return
		}

		// Refresh last_seen in a best-effort goroutine.
		ctx := r.Context()
		id, _ := s.store.InstallIDByHash(ctx, hash)
		if id != "" {
			go func() {
				bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
				defer cancel()
				_ = s.store.TouchInstall(bgCtx, id)
			}()
		}

		ctx = context.WithValue(ctx, installIDKey{}, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func extractInstallToken(r *http.Request) string {
	// X-Install-Token header (explicit)
	if tok := r.Header.Get("X-Install-Token"); tok != "" {
		return tok
	}
	// Bearer token in Authorization
	auth := r.Header.Get("Authorization")
	if strings.HasPrefix(auth, "Bearer ") {
		return strings.TrimPrefix(auth, "Bearer ")
	}
	return ""
}
