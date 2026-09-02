package store

import (
	"context"
	"database/sql"
)

// LogSessionEvent records a start/end session event from an app install, and the
// lock component fetch so we can detect leaked blobs.
func (s *Store) LogSessionEvent(ctx context.Context, blobID, installID, event string, bytesUp, bytesDown int64) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions (blob_id, install_id, event, bytes_up, bytes_down) VALUES (?, ?, ?, ?, ?)`,
		blobID, installID, event, bytesUp, bytesDown)
	return err
}

// LogComponentFetch records that an install requested a lock component for a blob.
func (s *Store) LogComponentFetch(ctx context.Context, installID, blobID string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO component_log (install_id, blob_id) VALUES (?, ?)`, installID, blobID)
	return err
}

// SessionEvent is a single session row used by aggregation queries.
type SessionEvent struct {
	BlobID    string
	InstallID string
	Event     string
	TS        string
}

// LiveInstallCount counts distinct installs that have a 'start' without a
// matching 'end', considered within the given window (unix seconds). This is the
// "how many people are connected right now" figure for the owner dashboard.
func (s *Store) LiveInstallCount(ctx context.Context, channelID int64) (int, error) {
	// A session is "live" if its most recent event for the install/blob pair is
	// 'start'. Simplest robust approach: compare counts of start vs end per
	// (blob, install) scoped to the channel's blobs.
	rows, err := s.db.QueryContext(ctx,
		`SELECT b.blob_id, s.install_id,
		        SUM(CASE WHEN s.event='start' THEN 1 ELSE 0 END) AS starts,
		        SUM(CASE WHEN s.event='end'   THEN 1 ELSE 0 END) AS ends
		 FROM sessions s
		 JOIN blobs b ON b.blob_id = s.blob_id
		 WHERE b.channel_id = ?
		 GROUP BY b.blob_id, s.install_id`, channelID)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	live := 0
	for rows.Next() {
		var starts, ends int
		var blobID, installID string
		if err := rows.Scan(&blobID, &installID, &starts, &ends); err != nil {
			return 0, err
		}
		if starts > ends {
			live++
		}
	}
	return live, rows.Err()
}

// TotalConnections sums all distinct connect (start) events across a channel's blobs.
func (s *Store) TotalConnections(ctx context.Context, channelID int64) (int64, error) {
	var n int64
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM sessions
		 WHERE event='start' AND blob_id IN (SELECT blob_id FROM blobs WHERE channel_id = ?)`,
		channelID).Scan(&n)
	if err != nil {
		return 0, err
	}
	return n, nil
}

// PerBlobConnections returns a map blob_id -> start count for a channel.
type BlobStat struct {
	BlobID      string
	PublicTitle string
	Connections int64
}

func (s *Store) PerBlobConnections(ctx context.Context, channelID int64) ([]BlobStat, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT b.blob_id, b.public_title, COUNT(s.id)
		 FROM blobs b
		 LEFT JOIN sessions s ON s.blob_id = b.blob_id AND s.event='start'
		 WHERE b.channel_id = ?
		 GROUP BY b.blob_id, b.public_title
		 ORDER BY b.created_at`, channelID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []BlobStat
	for rows.Next() {
		var bs BlobStat
		if err := rows.Scan(&bs.BlobID, &bs.PublicTitle, &bs.Connections); err != nil {
			return nil, err
		}
		out = append(out, bs)
	}
	return out, rows.Err()
}

// ChannelExistsByID reports whether a channel id exists.
func (s *Store) ChannelExistsByID(ctx context.Context, id int64) (bool, error) {
	var one int
	err := s.db.QueryRowContext(ctx, `SELECT 1 FROM channels WHERE id=?`, id).Scan(&one)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}
