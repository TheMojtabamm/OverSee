// Package api wires the HTTP layer: router, middleware, and v1 handlers.
//
// This file contains the server bootstrap (router + middleware stack) and the
// health endpoint. Feature handlers (app, feed, owner, stats, lock) are added in
// later phases on the same router.
package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
	"golang.org/x/time/rate"

	"oversea/server/internal/config"
	"oversea/server/internal/lock"
	"oversea/server/internal/store"
)

// Server bundles the dependencies the HTTP handlers need.
type Server struct {
	cfg   config.Config
	store *store.Store

	// Per-IP rate limiter state.
	limMu  sync.Mutex
	limits map[string]*rate.Limiter
}

// New builds a Server from config + store.
func New(cfg config.Config, st *store.Store) *Server {
	return &Server{cfg: cfg, store: st, limits: make(map[string]*rate.Limiter)}
}

// Handler returns the fully-wired http.Handler (router + middleware).
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	// Public / health
	mux.HandleFunc("GET /v1/health", s.handleHealth)

	// Free-config feed (public, matches the Flutter client contract)
	feed := &FeedHandler{Store: s.store}
	mux.HandleFunc("GET /v1/channels", feed.ListChannels)
	mux.HandleFunc("GET /v1/channels/{ref}/configs", feed.GetConfigs)

	// Lock endpoints: component requires an install token; status is public.
	lockSvc := lock.NewService(s.cfg.LOCK_SERVER_KEY, s.store, 5)
	lockH := &LockHandler{svc: lockSvc}
	mux.Handle("GET /v1/lock/component", s.installTokenAuth(http.HandlerFunc(lockH.component)))
	mux.HandleFunc("GET /v1/lock/status", lockH.status)

	// App install registration (no token required to register once).
	mux.HandleFunc("POST /v1/app/register", s.register)

	// Owner (dashboard) endpoints: protected by JWT when OwnerAuthEnabled.
	ownerH := &OwnerHandler{Cfg: s.cfg, Store: s.store, Lock: lockSvc}
	mux.HandleFunc("POST /v1/owner/register", ownerH.register)
	mux.HandleFunc("POST /v1/owner/login", ownerH.login)
	mux.Handle("POST /v1/owner/channels", ownerH.ownerAuth(http.HandlerFunc(ownerH.createChannel)))
	mux.Handle("GET /v1/owner/channels", ownerH.ownerAuth(http.HandlerFunc(ownerH.listChannels)))
	mux.Handle("GET /v1/owner/channels/{ref}/stats", ownerH.ownerAuth(http.HandlerFunc(ownerH.getChannelStats)))
	mux.Handle("POST /v1/owner/channels/{ref}/blobs", ownerH.ownerAuth(http.HandlerFunc(ownerH.createBlob)))
	mux.Handle("DELETE /v1/owner/blobs/{blobId}", ownerH.ownerAuth(http.HandlerFunc(ownerH.revokeBlob)))
	mux.Handle("DELETE /v1/owner/channels/{ref}", ownerH.ownerAuth(http.HandlerFunc(ownerH.revokeChannel)))

	// Seed first owner from env (idempotent).
	if s.cfg.SeedEmail != "" && s.cfg.SeedPassword != "" {
		s.seedOwner(s.cfg.SeedEmail, s.cfg.SeedPassword)
	}

	var h http.Handler = mux
	h = s.withRecover(h)
	h = s.withLogging(h)
	h = s.withCORS(h)
	h = s.withRateLimit(h)
	return h
}

// ---- health ----------------------------------------------------------------

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := s.store.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"status": "degraded",
			"error":  err.Error(),
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"service": "oversea",
		"time":    time.Now().UTC().Format(time.RFC3339),
	})
}

// seedOwner creates the first owner on startup if one does not exist.
func (s *Server) seedOwner(email, password string) {
	_, err := s.store.OwnerByEmail(context.Background(), email)
	if err == nil {
		return // already exists
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("seed owner: hash failed: %v", err)
		return
	}
	oid, err := s.store.CreateOwner(context.Background(), email, string(hash))
	if err != nil {
		log.Printf("seed owner: create failed: %v", err)
		return
	}
	log.Printf("seed owner created: id=%d email=%s", oid, email)
}

// ---- middleware -------------------------------------------------------------

func (s *Server) withRecover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic: %v", rec)
				writeJSON(w, http.StatusInternalServerError, map[string]any{
					"error": "internal server error",
				})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s (%s)", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start))
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The Flutter app and the owner dashboard both call from other origins;
		// allow all for now (lock down before production).
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) withRateLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		lim := s.limiterFor(ip)
		if !lim.Allow() {
			writeJSON(w, http.StatusTooManyRequests, map[string]any{
				"error": "rate limit exceeded",
			})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) limiterFor(ip string) *rate.Limiter {
	s.limMu.Lock()
	defer s.limMu.Unlock()
	lim, ok := s.limits[ip]
	if !ok {
		lim = rate.NewLimiter(rate.Limit(s.cfg.RPS), s.cfg.Burst)
		s.limits[ip] = lim
	}
	return lim
}

func clientIP(r *http.Request) string {
	// Behind a single proxy the X-Real-IP / X-Forwarded-For is set. For now
	// fall back to RemoteAddr (host:port); strip the port.
	addr := r.RemoteAddr
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		addr = fwd
	}
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[:i]
		}
		if addr[i] == '.' || addr[i] == ']' {
			break
		}
	}
	return addr
}

// ---- JSON helpers ------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
