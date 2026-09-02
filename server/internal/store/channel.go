package store

import (
	"context"
	"database/sql"
	"errors"
)

// Channel is the public shape of a free-config channel as seen by the feed.
type Channel struct {
	ID          int64
	Ref         string
	OwnerID     int64
	Title       string
	TelegramURL *string
	AdText      *string
	Status      string
	ConfigCount int
}

// Blob is a single locked config published by a channel.
type Blob struct {
	BlobID      string
	ChannelID   int64
	Epoch       int64
	Protocol    string
	PublicTitle string
	PublicHost  *string
	LockedBlob  string
	Status      string
}

// ActiveChannels returns all channels with status='active', ordered by title.
func (s *Store) ActiveChannels(ctx context.Context) ([]Channel, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, ref, owner_id, title, telegram_url, ad_text, status, config_count
		 FROM channels WHERE status='active' ORDER BY title`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Channel
	for rows.Next() {
		var c Channel
		if err := rows.Scan(&c.ID, &c.Ref, &c.OwnerID, &c.Title,
			&c.TelegramURL, &c.AdText, &c.Status, &c.ConfigCount); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ChannelByRef returns a channel by its public ref.
func (s *Store) ChannelByRef(ctx context.Context, ref string) (*Channel, error) {
	c := &Channel{}
	err := s.db.QueryRowContext(ctx,
		`SELECT id, ref, owner_id, title, telegram_url, ad_text, status, config_count
		 FROM channels WHERE ref = ?`, ref).
		Scan(&c.ID, &c.Ref, &c.OwnerID, &c.Title, &c.TelegramURL, &c.AdText, &c.Status, &c.ConfigCount)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	return c, nil
}

// ActiveBlobsForChannel returns active locked blobs for a channel.
func (s *Store) ActiveBlobsForChannel(ctx context.Context, channelID int64) ([]Blob, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT blob_id, channel_id, epoch, protocol, public_title, public_host, locked_blob, status
		 FROM blobs WHERE channel_id = ? AND status='active' ORDER BY created_at`, channelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Blob
	for rows.Next() {
		var b Blob
		if err := rows.Scan(&b.BlobID, &b.ChannelID, &b.Epoch, &b.Protocol,
			&b.PublicTitle, &b.PublicHost, &b.LockedBlob, &b.Status); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// BlobByID returns a blob (any status) by id.
func (s *Store) BlobByID(ctx context.Context, blobID string) (*Blob, error) {
	b := &Blob{}
	err := s.db.QueryRowContext(ctx,
		`SELECT blob_id, channel_id, epoch, protocol, public_title, public_host, locked_blob, status
		 FROM blobs WHERE blob_id = ?`, blobID).
		Scan(&b.BlobID, &b.ChannelID, &b.Epoch, &b.Protocol, &b.PublicTitle, &b.PublicHost, &b.LockedBlob, &b.Status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	return b, nil
}

// CreateBlob inserts a new locked blob and bumps the channel's config_count.
func (s *Store) CreateBlob(ctx context.Context, b Blob) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx,
		`INSERT INTO blobs (blob_id, channel_id, epoch, protocol, public_title, public_host, locked_blob, status)
		 VALUES (?, ?, ?, ?, ?, ?, ?, 'active')`,
		b.BlobID, b.ChannelID, b.Epoch, b.Protocol, b.PublicTitle, b.PublicHost, b.LockedBlob); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE channels SET config_count = config_count + 1 WHERE id = ?`, b.ChannelID); err != nil {
		return err
	}
	return tx.Commit()
}

// RevokeBlob marks a blob revoked and decrements the channel's config_count.
func (s *Store) RevokeBlob(ctx context.Context, blobID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var channelID int64
	err = tx.QueryRowContext(ctx,
		`SELECT channel_id FROM blobs WHERE blob_id = ?`, blobID).Scan(&channelID)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE blobs SET status='revoked' WHERE blob_id = ?`, blobID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE channels SET config_count = CASE WHEN config_count > 0 THEN config_count - 1 ELSE 0 END WHERE id = ?`,
		channelID); err != nil {
		return err
	}
	return tx.Commit()
}
