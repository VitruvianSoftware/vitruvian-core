// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import "context"

// LinkPreviewImageKeyPrefix starts the key of each remembered link-card picture in the settings table (one row per
// address, whose value is JSON with a "state" and an "at" in Unix milliseconds: actions.PreviewImageForURL).
const LinkPreviewImageKeyPrefix = "link_preview_image:"

// LinkPreviewImageRowsKept is how many remembered addresses are kept, newest first.
const LinkPreviewImageRowsKept = 5000

// PruneLinkPreviewImages removes the remembered link-card pictures that are over their lifetime ("none" rows recorded
// before noneBefore, "unknown" rows before unknownBefore, both Unix milliseconds) and then all but the newest keep
// rows. A "found" row is never expired: only the cap removes it. It returns how many rows it removed.
func (s *Store) PruneLinkPreviewImages(ctx context.Context, noneBefore, unknownBefore int64, keep int) (int64, error) {
	n := len(LinkPreviewImageKeyPrefix)
	// A row that is not JSON can't be read by the queries below (json_extract fails on it): it goes first.
	bad, err := s.db.Exec(ctx, `DELETE FROM settings WHERE substr(key, 1, $1) = $2 AND NOT json_valid(value)`,
		n, LinkPreviewImageKeyPrefix)
	if err != nil {
		return 0, err
	}
	invalid, _ := bad.RowsAffected()
	expired, err := s.db.Exec(ctx, `DELETE FROM settings WHERE substr(key, 1, $1) = $2 AND (
  (json_extract(value, '$.state') = 'none' AND json_extract(value, '$.at') < $3) OR
  (json_extract(value, '$.state') = 'unknown' AND json_extract(value, '$.at') < $4) OR
  json_extract(value, '$.state') IS NULL)`, n, LinkPreviewImageKeyPrefix, noneBefore, unknownBefore)
	if err != nil {
		return 0, err
	}
	removed, _ := expired.RowsAffected()
	removed += invalid
	over, err := s.db.Exec(ctx, `DELETE FROM settings WHERE substr(key, 1, $1) = $2 AND key NOT IN (
  SELECT key FROM settings WHERE substr(key, 1, $1) = $2
  ORDER BY json_extract(value, '$.at') DESC, key LIMIT $3)`, n, LinkPreviewImageKeyPrefix, keep)
	if err != nil {
		return removed, err
	}
	more, _ := over.RowsAffected()
	return removed + more, nil
}
