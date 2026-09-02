package store

import (
	"context"
	"database/sql"
	"errors"
)

// CreateInstall registers a new app install. It stores only the token hash.
// Returns the install (which the caller uses to hand the raw token to the app).
func (s *Store) CreateInstall(ctx context.Context, installID, tokenHash string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO installs (install_id, token_hash, last_seen) VALUES (?, ?, ?)`,
		installID, tokenHash, nowUTC())
	return err
}

// InstallHashValid reports whether the given token hash belongs to a known install.
func (s *Store) InstallHashValid(ctx context.Context, tokenHash string) (bool, error) {
	var one int
	err := s.db.QueryRowContext(ctx,
		`SELECT 1 FROM installs WHERE token_hash = ? LIMIT 1`, tokenHash).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// InstallIDByHash returns the install id for a token hash, and refreshes last_seen.
func (s *Store) InstallIDByHash(ctx context.Context, tokenHash string) (string, error) {
	var id string
	err := s.db.QueryRowContext(ctx,
		`SELECT install_id FROM installs WHERE token_hash = ? LIMIT 1`, tokenHash).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", sql.ErrNoRows
		}
		return "", err
	}
	_, _ = s.db.ExecContext(ctx,
		`UPDATE installs SET last_seen = ? WHERE token_hash = ?`, nowUTC(), tokenHash)
	return id, nil
}

// TouchInstall updates the last_seen ttl for an install (used on lock fetch).
func (s *Store) TouchInstall(ctx context.Context, installID string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE installs SET last_seen = ? WHERE install_id = ?`, nowUTC(), installID)
	return err
}
