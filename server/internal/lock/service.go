package lock

import (
	"context"
	"database/sql"
	"errors"

	"oversea/server/internal/store"
)

// Service combines master-key derivation with the store to answer the two lock
// questions HTTP handlers need: "may this blob be opened, and if so what is its
// component?" and "is it revoked?". It also guards against leaked blobs (one
// blob being opened from many distinct installs).
type Service struct {
	key   *MasterKey
	store *store.Store

	// leakThreshold is the number of distinct installs per day that, when
	// exceeded, marks a channel as leaked. Zero disables the check.
	leakThreshold int
}

// NewService builds the lock service.
func NewService(masterKey string, st *store.Store, leakThreshold int) *Service {
	return &Service{
		key:           NewMasterKey(masterKey),
		store:         st,
		leakThreshold: leakThreshold,
	}
}

// Component returns the per-blob/epoch server component, or an error if the blob
// is missing or revoked. It also records the fetch for leak detection.
func (s *Service) Component(ctx context.Context, installID, blobID string, epoch int64) (string, error) {
	b, err := s.store.BlobByID(ctx, blobID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrUnknownBlob
		}
		return "", err
	}
	if b.Status != "active" {
		return "", ErrRevoked
	}
	// Record the fetch (leak detection). Best-effort: ignore write errors so a
	// logging failure never blocks a legitimate connect.
	_ = s.store.LogComponentFetch(ctx, installID, blobID)
	return s.key.ComponentFor(blobID, epoch), nil
}

// Status reports whether a blob may currently be opened ("ok") or not ("revoked").
func (s *Service) Status(ctx context.Context, blobID string) (string, error) {
	b, err := s.store.BlobByID(ctx, blobID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "unknown", ErrUnknownBlob
		}
		return "", err
	}
	if b.Status == "active" {
		return "ok", nil
	}
	return "revoked", nil
}

// Sentinel errors the HTTP layer maps to status codes.
var (
	ErrUnknownBlob = errors.New("unknown blob")
	ErrRevoked     = errors.New("blob revoked")
)
