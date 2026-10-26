// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"strings"
	"time"
)

// MaxRecentMediaLimit is the maximum number of recent stickers or GIFs returned from history.
const MaxRecentMediaLimit = 40

// RecentMedia describes a recent sticker or GIF event deduplicated by its content URL.
type RecentMedia struct {
	EventID          string
	RoomID           string
	URL              string
	Body             string
	MimeType         string
	Width            int
	Height           int
	BridgedNetwork   string
	BridgedPackURL   string
	BridgedStickerID string
	BridgedEmoji     string
	TS               time.Time
}

// ListRecentStickers returns up to limit (default/max 40) unique m.sticker events ordered newest first and deduplicated by URL.
func (s *Store) ListRecentStickers(ctx context.Context, limit int) ([]RecentMedia, error) {
	return s.listRecentMedia(ctx, `
		SELECT event_id, room_id, content, ts
		FROM events
		WHERE type = 'm.sticker' AND redacted = 0 AND deleted_for_me = 0
		ORDER BY ts DESC, seq DESC
		LIMIT $1`, limit)
}

// ListRecentGIFs returns up to limit (default/max 40) unique GIF events (m.room.message with fi.mau.gif) ordered newest first and deduplicated by URL.
func (s *Store) ListRecentGIFs(ctx context.Context, limit int) ([]RecentMedia, error) {
	return s.listRecentMedia(ctx, `
		SELECT event_id, room_id, content, ts
		FROM events
		WHERE type = 'm.room.message' AND redacted = 0 AND deleted_for_me = 0
		  AND (CASE WHEN json_valid(content) THEN (json_extract(content, '$.info."fi.mau.gif"') = 1 OR json_extract(content, '$."fi.mau.gif"') = 1) END)
		ORDER BY ts DESC, seq DESC
		LIMIT $1`, limit)
}

func (s *Store) listRecentMedia(ctx context.Context, query string, limit int) ([]RecentMedia, error) {
	if limit <= 0 || limit > MaxRecentMediaLimit {
		limit = MaxRecentMediaLimit
	}
	rows, err := s.db.Query(ctx, query, limit*4)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	seen := make(map[string]bool, limit)
	out := make([]RecentMedia, 0, limit)
	for rows.Next() {
		var eventID, roomID, rawContent string
		var tsMS int64
		if err := rows.Scan(&eventID, &roomID, &rawContent, &tsMS); err != nil {
			return nil, err
		}
		var parsed struct {
			Body string `json:"body"`
			URL  string `json:"url"`
			Info *struct {
				MimeType       string `json:"mimetype"`
				Width          int    `json:"w"`
				Height         int    `json:"h"`
				BridgedSticker *struct {
					Network string `json:"network"`
					PackURL string `json:"pack_url"`
					ID      string `json:"id"`
					Emoji   string `json:"emoji"`
				} `json:"fi.mau.bridged_sticker"`
			} `json:"info"`
		}
		if json.Unmarshal([]byte(rawContent), &parsed) != nil {
			continue
		}
		u := strings.TrimSpace(parsed.URL)
		if u == "" || seen[u] {
			continue
		}
		seen[u] = true
		item := RecentMedia{
			EventID: eventID,
			RoomID:  roomID,
			URL:     u,
			Body:    parsed.Body,
			TS:      time.UnixMilli(tsMS),
		}
		if parsed.Info != nil {
			item.MimeType = parsed.Info.MimeType
			item.Width = parsed.Info.Width
			item.Height = parsed.Info.Height
			if bs := parsed.Info.BridgedSticker; bs != nil {
				item.BridgedNetwork = bs.Network
				item.BridgedPackURL = bs.PackURL
				item.BridgedStickerID = bs.ID
				item.BridgedEmoji = bs.Emoji
			}
		}
		out = append(out, item)
		if len(out) >= limit {
			break
		}
	}
	return out, rows.Err()
}
