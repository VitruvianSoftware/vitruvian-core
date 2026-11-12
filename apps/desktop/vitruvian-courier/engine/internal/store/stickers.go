// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"strings"
	"sync/atomic"
	"time"
)

var recentRowsDecoded atomic.Int64

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
	return s.listRecentMedia(ctx, `type = 'm.sticker'`, limit)
}

// ListRecentGIFs returns up to limit (default/max 40) unique GIF events (m.room.message with fi.mau.gif) ordered newest first and deduplicated by URL.
func (s *Store) ListRecentGIFs(ctx context.Context, limit int) ([]RecentMedia, error) {
	return s.listRecentMedia(ctx, `type = 'm.room.message'
		  AND (CASE WHEN json_valid(content) THEN (json_extract(content, '$.info."fi.mau.gif"') = 1 OR json_extract(content, '$."fi.mau.gif"') = 1) END)`, limit)
}

func (s *Store) listRecentMedia(ctx context.Context, typeFilter string, limit int) ([]RecentMedia, error) {
	if limit <= 0 || limit > MaxRecentMediaLimit {
		limit = MaxRecentMediaLimit
	}
	query := `
		SELECT event_id, room_id, content, ts
		FROM (
			SELECT event_id, room_id, content, ts, seq,
			       ROW_NUMBER() OVER (
			           PARTITION BY CASE
			               WHEN TRIM(json_extract(content, '$.url')) LIKE 'courier://media/%'
			               THEN 'mxc://courier.local/' || SUBSTR(TRIM(json_extract(content, '$.url')), 17)
			               ELSE TRIM(json_extract(content, '$.url'))
			           END
			           ORDER BY ts DESC, seq DESC
			       ) AS rn
			FROM events
			WHERE ` + typeFilter + `
			  AND redacted = 0 AND deleted_for_me = 0
			  AND status NOT IN ('failed', 'held', 'queued')
			  AND CASE WHEN json_valid(content) THEN TRIM(COALESCE(json_extract(content, '$.url'), '')) <> '' ELSE 0 END
		)
		WHERE rn = 1
		ORDER BY ts DESC, seq DESC
		LIMIT $1`
	rows, err := s.db.Query(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]RecentMedia, 0, limit)
	recentRowsDecoded.Store(0)
	for rows.Next() {
		recentRowsDecoded.Add(1)
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
		if u == "" {
			continue
		}
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
	}
	return out, rows.Err()
}
