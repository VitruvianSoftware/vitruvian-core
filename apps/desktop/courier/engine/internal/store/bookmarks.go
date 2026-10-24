// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

// Bookmarks are on this Mac only. Every list of them keeps to listedBookmarksSQL: a deleted message's bookmark isn't
// listed (its row stays, so a refused unsend gives it back).

// defaultRecentBookmarks is how many bookmarks RecentBookmarks lists when asked for 0.
// Inferred: the five newest bookmarks on the ⌘K home.
const defaultRecentBookmarks = 5

// SetBookmarked bookmarks message eventID (on) or takes its bookmark away. Bookmarking one already bookmarked keeps
// its first time. An unknown or deleted (redacted) message is ErrNotFound. The chat gets a "status" change for the
// message, so it is read again.
func (s *Store) SetBookmarked(ctx context.Context, eventID string, on bool) error {
	var e Event
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		e, err = scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1 AND redacted = 0", eventID))
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if on {
			_, err = s.db.Exec(ctx, `INSERT INTO bookmarks (event_id, room_id, created_at) VALUES ($1, $2, $3)
				ON CONFLICT(event_id) DO NOTHING`, eventID, e.RoomID, s.now().UnixMilli())
		} else {
			_, err = s.db.Exec(ctx, "DELETE FROM bookmarks WHERE event_id=$1", eventID)
		}
		return err
	})
	if err != nil {
		return err
	}
	s.publish(Change{Kind: "status", RoomID: e.RoomID, EventID: eventID, Seq: e.Seq})
	return nil
}

// bookmarkedSQL is which of the messages in the JSON array $1 are listed as bookmarked (listedBookmarksSQL).
var bookmarkedSQL = `SELECT event_id FROM (` + listedBookmarksSQL + `) WHERE event_id IN (SELECT value FROM json_each($1))`

// Bookmarked says which of eventIDs are bookmarked: only those are in the map. A deleted message never is.
func (s *Store) Bookmarked(ctx context.Context, eventIDs []string) (map[string]bool, error) {
	out := map[string]bool{}
	if len(eventIDs) == 0 {
		return out, nil
	}
	b, _ := json.Marshal(distinct(eventIDs))
	rows, err := s.db.Query(ctx, bookmarkedSQL, string(b))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// bookmarkHitSQL is the hit of message $1: the event with its chat (searchColsSQL's columns, with 0 for the doc id).
var bookmarkHitSQL = `SELECT 0, e.room_id, e.event_id, e.sender, e.type, e.state_key, e.content, e.ts, e.status,
  e.status_reason, e.seq, e.deleted_for_me, e.expires_at, COALESCE(NULLIF(p.local_name, ''), r.name), r.network, r.is_direct, ` + placeSQL("r", "p") + `
FROM events e CROSS JOIN rooms r ON r.room_id = e.room_id LEFT JOIN room_prefs p ON p.room_id = r.room_id
WHERE e.event_id = $1`

// RecentBookmarks lists the limit newest bookmarks (0 is 5; 1..50), newest bookmark first, as search hits: the
// message's current text and kind, and its chat. A limit out of range is ErrBadValue.
func (s *Store) RecentBookmarks(ctx context.Context, limit int) ([]MessageHit, error) {
	switch {
	case limit == 0:
		limit = defaultRecentBookmarks
	case limit < 0 || limit > maxMessageLimit:
		return nil, ErrBadValue
	}
	ids, err := s.stringColumn(ctx, listedBookmarksSQL+" LIMIT $1", limit)
	if err != nil {
		return nil, err
	}
	hits := []MessageHit{}
	for _, id := range ids {
		var r searchRow
		var er eventRow
		err := s.db.QueryRow(ctx, bookmarkHitSQL, id).Scan(append(append([]any{&r.docID}, er.dest()...),
			&r.roomName, &r.network, &r.direct, &r.place)...)
		if errors.Is(err, sql.ErrNoRows) {
			continue // forgotten since it was listed
		}
		if err != nil {
			return nil, err
		}
		r.e = er.event()
		h, err := s.hitOf(ctx, r, false)
		if err != nil {
			return nil, err
		}
		hits = append(hits, h)
	}
	return hits, nil
}

// stringColumn runs a query of one text column and returns its values in order.
func (s *Store) stringColumn(ctx context.Context, query string, args ...any) ([]string, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
