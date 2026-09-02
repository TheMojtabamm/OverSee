// Package config loads all server configuration from environment variables.
//
// Secrets (LOCK_SERVER_KEY, JWT_SECRET, ADMIN_SEED_*) are never written to the
// repo — they are injected only through the environment at deploy/run time.
package config

import (
	"os"
	"strconv"
)

// Config holds every runtime setting the server needs.
type Config struct {
	// ListenAddr is the TCP address the HTTP server binds to (e.g. ":8080").
	ListenAddr string
	// DBPath is the SQLite database file path (e.g. "oversea.db").
	DBPath string

	// PublicBaseURL is the externally reachable base URL, used to build public
	// links (privacy policy, etc.) in responses.
	PublicBaseURL string

	// LOCK_SERVER_KEY is the server-side master key for the v2 locked-config
	// system. The per-blob server component is derived from it. REQUIRED.
	LOCK_SERVER_KEY string
	// ClientKeyMaterial is the key material embedded at build-time in the app
	// (--dart-define=LOCK_CLIENT_KEY). It MUST match the app so the server can
	// build locked blobs the client can open. REQUIRED for owner blob creation.
	ClientKeyMaterial string
	// JWTSecret signs owner (dashboard) access tokens. REQUIRED.
	JWTSecret string

	// OwnerAuthEnabled gates the /v1/owner/* endpoints. Always on in production.
	OwnerAuthEnabled bool

	// SeedEmail / SeedPassword, when set, auto-create the first owner on startup
	// (idempotent). Useful for the very first deploy; remove after first login.
	SeedEmail    string
	SeedPassword string

	// RateLimits (requests per second, then burst) applied per-IP.
	RPS   float64
	Burst int
}

// Load reads configuration from the process environment with sensible defaults
// for a local/dev run. It panics on missing required secrets so a misconfigured
// server fails fast at startup instead of half-working.
func Load() Config {
	return Config{
		ListenAddr:       getenv("LISTEN_ADDR", ":8080"),
		DBPath:           getenv("DB_PATH", "oversea.db"),
		PublicBaseURL:    getenv("PUBLIC_BASE_URL", "http://localhost:8080"),
		LOCK_SERVER_KEY:  mustEnv("LOCK_SERVER_KEY"),
		ClientKeyMaterial: getenv("CLIENT_KEY_MATERIAL", ""),
		JWTSecret:        mustEnv("JWT_SECRET"),
		OwnerAuthEnabled: getenvBool("OWNER_AUTH_ENABLED", true),
		SeedEmail:        os.Getenv("ADMIN_SEED_EMAIL"),
		SeedPassword:     os.Getenv("ADMIN_SEED_PASSWORD"),
		RPS:              getenvFloat("RATE_RPS", 20),
		Burst:            getenvInt("RATE_BURST", 40),
	}
}

// ---- env helpers -----------------------------------------------------------

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		panic("required env var " + key + " is not set")
	}
	return v
}

func getenvBool(key string, fallback bool) bool {
	switch v := os.Getenv(key); v {
	case "1", "true", "yes":
		return true
	case "0", "false", "no":
		return false
	default:
		return fallback
	}
}

func getenvInt(key string, fallback int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return fallback
}

func getenvFloat(key string, fallback float64) float64 {
	if v, err := strconv.ParseFloat(os.Getenv(key), 64); err == nil {
		return v
	}
	return fallback
}
