// Package store owns the SQLite database: connection, schema (migrations),
// and the model records for owners, channels, blobs, installs, sessions, and
// the lock component log.
//
// Only the schema + low-level query helpers live here. HTTP/JSON concerns stay
// in the api package.
package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "modernc.org/sqlite" // pure-Go SQLite driver (no cgo)
)

// Store wraps the database handle.
type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the SQLite database file at path and applies
// the schema migrations. It returns an error if the file cannot be opened.
func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	// modernc sqlite: one writer at a time is safest with a static gate.
	db.SetMaxOpenConns(1)
	if err := migrate(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Store{db: db}, nil
}

// Close closes the underlying database.
func (s *Store) Close() error { return s.db.Close() }

// DB returns the raw database handle. Prefer the typed methods on Store for
// normal use; this is exposed for seeding/admin tooling and tests.
func (s *Store) DB() *sql.DB { return s.db }

// ---- migrations ------------------------------------------------------------

// migrate creates tables if they do not exist. Because this project is in its
// early phase we create tables idempotently (CREATE TABLE IF NOT EXISTS) and
// add columns via ALTER ... in later phases when the schema evolves.
func migrate(db *sql.DB) error {
	schema := []string{
		`CREATE TABLE IF NOT EXISTS owners (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			email         TEXT NOT NULL UNIQUE,
			pass_hash     TEXT NOT NULL,
			created_at    DATETIME NOT NULL DEFAULT (datetime('now'))
		);`,

		`CREATE TABLE IF NOT EXISTS channels (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			ref           TEXT NOT NULL UNIQUE,          -- public slug used in feed URLs
			owner_id      INTEGER NOT NULL REFERENCES owners(id) ON DELETE CASCADE,
			title         TEXT NOT NULL,
			telegram_url  TEXT,                          -- channel link the owner advertises
			ad_text       TEXT,                          -- short ad shown before connect
			status        TEXT NOT NULL DEFAULT 'active',-- active | revoked
			config_count  INTEGER NOT NULL DEFAULT 0,
			created_at    DATETIME NOT NULL DEFAULT (datetime('now'))
		);`,

		`CREATE TABLE IF NOT EXISTS blobs (
			blob_id       TEXT PRIMARY KEY,              -- public token embedded in the locked blob
			channel_id    INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
			epoch         INTEGER NOT NULL,              -- lock epoch at creation (rotation)
			protocol      TEXT NOT NULL DEFAULT 'unknown',
			public_title  TEXT NOT NULL DEFAULT '',
			public_host   TEXT,
			locked_blob   TEXT NOT NULL,                 -- the base64url locked config served by the feed
			status        TEXT NOT NULL DEFAULT 'active',-- active | revoked
			created_at    DATETIME NOT NULL DEFAULT (datetime('now'))
		);`,

		`CREATE TABLE IF NOT EXISTS installs (
			install_id    TEXT PRIMARY KEY,              -- app-generated UUID
			token_hash    TEXT NOT NULL,                 -- sha256(install token), original never stored
			created_at    DATETIME NOT NULL DEFAULT (datetime('now')),
			last_seen     DATETIME
		);`,

		`CREATE TABLE IF NOT EXISTS sessions (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			blob_id       TEXT NOT NULL REFERENCES blobs(blob_id) ON DELETE CASCADE,
			install_id    TEXT NOT NULL,
			event         TEXT NOT NULL,                 -- start | end
			ts            DATETIME NOT NULL DEFAULT (datetime('now')),
			bytes_up      INTEGER NOT NULL DEFAULT 0,
			bytes_down    INTEGER NOT NULL DEFAULT 0
		);
		CREATE INDEX IF NOT EXISTS idx_sessions_blob_ts ON sessions(blob_id, ts);`,

		`CREATE TABLE IF NOT EXISTS component_log (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			install_id    TEXT NOT NULL,
			blob_id       TEXT NOT NULL REFERENCES blobs(blob_id) ON DELETE CASCADE,
			ts            DATETIME NOT NULL DEFAULT (datetime('now'))
		);
		CREATE INDEX IF NOT EXISTS idx_comp_blob ON component_log(blob_id, ts);`,
	}

	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	return nil
}

// ---- generic helpers --------------------------------------------------------

// Ping verifies the connection is alive (used by the health endpoint).
func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

// Now returns the current UTC time in the format SQLite stores by default.
// Provided here so all timestamps share one convention (UTC).
func nowUTC() time.Time {
	return time.Now().UTC()
}
