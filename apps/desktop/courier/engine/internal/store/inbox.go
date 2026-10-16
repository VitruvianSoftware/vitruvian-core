// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"math"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// maxPreviewRunes is how much of a message the inbox row shows.
const maxPreviewRunes = 140

// InboxRow is one chat in the list: the room plus what the list shows beside its name.
type InboxRow struct {
	Room
	LastTS      time.Time // zero when the room has no message yet
	Preview     string    // body of the newest message-like event, at most 140 runes
	PreviewKind string    // "text", "image", "video", "audio", "file", "sticker", or "" (nothing readable yet)
	PreviewMine bool      // the newest message is mine
	Unread      int       // messages from others newer than the read marker
	Muted       bool
}

// inboxSQL is the whole inbox in one statement. $1 is my user ID. Every part is an index lookup:
//   - rooms come out of rooms_last_ts already in display order (no sort);
//   - the preview event is a primary-key lookup on rooms.last_event_id;
//   - the unread count is a range scan of events_room_ts (room_id, ts) from the read marker onward, so it
//     only touches messages that are actually newer than the marker.
//
// The read marker is the later of the network's read (reads) and this device's (local_reads).
const inboxSQL = `SELECT r.room_id, r.network, r.name, r.topic, r.avatar_uri, r.is_direct, r.created_at,
  r.last_ts,
  COALESCE(ev.sender, ''), COALESCE(ev.type, ''), COALESCE(ev.content, ''),
  COALESCE(p.muted, 0),
  (SELECT COUNT(*) FROM events u
     WHERE u.room_id = r.room_id AND u.ts > MAX(COALESCE(rd.ts, 0), COALESCE(lr.ts, 0))
       AND u.type IN (` + unreadTypes + `) AND u.sender <> $1)
FROM rooms r
LEFT JOIN events ev ON ev.event_id = r.last_event_id
LEFT JOIN room_prefs p ON p.room_id = r.room_id
LEFT JOIN reads rd ON rd.room_id = r.room_id
LEFT JOIN local_reads lr ON lr.room_id = r.room_id
ORDER BY r.last_ts DESC, r.created_at DESC`

// Inbox lists every room, newest message first; rooms without a message follow, newest created first.
func (s *Store) Inbox(ctx context.Context) ([]InboxRow, error) {
	rows, err := s.db.Query(ctx, inboxSQL, string(ids.Me))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []InboxRow
	for rows.Next() {
		var r InboxRow
		var direct, muted int
		var created, lastTS int64
		var sender, typ, content string
		if err := rows.Scan(&r.ID, &r.Network, &r.Name, &r.Topic, &r.AvatarURI, &direct, &created,
			&lastTS, &sender, &typ, &content, &muted, &r.Unread); err != nil {
			return nil, err
		}
		r.IsDirect, r.CreatedAt, r.Muted = direct == 1, time.UnixMilli(created), muted == 1
		if lastTS != 0 {
			r.LastTS = time.UnixMilli(lastTS)
		}
		r.PreviewMine = sender == string(ids.Me)
		r.Preview, r.PreviewKind = previewOf(typ, content)
		out = append(out, r)
	}
	return out, rows.Err()
}

// previewOf turns the newest message's type and content into the inbox's one-line preview and its kind.
// An encrypted placeholder has nothing readable, so it previews as empty text with no kind.
func previewOf(typ, content string) (preview, kind string) {
	switch typ {
	case "":
		return "", ""
	case "m.room.encrypted":
		return "", ""
	case "m.sticker":
		kind = "sticker"
	default:
		kind = "text"
	}
	var c struct {
		Body    string `json:"body"`
		MsgType string `json:"msgtype"`
	}
	_ = json.Unmarshal([]byte(content), &c) // malformed content just previews as empty
	if typ == "m.room.message" {
		switch c.MsgType {
		case "m.image":
			kind = "image"
		case "m.video":
			kind = "video"
		case "m.audio":
			kind = "audio"
		case "m.file":
			kind = "file"
		}
	}
	if r := []rune(c.Body); len(r) > maxPreviewRunes {
		c.Body = string(r[:maxPreviewRunes])
	}
	return c.Body, kind
}

// Cursor marks a position in a chat's history: the oldest event of the page you already have.
type Cursor struct {
	TS  time.Time
	Seq int64
}

// eventsBeforeSQL pages newest-first through events_room_ts. $1 room, $2 and $3 the cursor's ts (ms) and seq,
// $4 the number of rows wanted. Ordering by (ts, seq) matches the index, so deep pages cost no more than the first.
const eventsBeforeSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id = $1 AND (ts, seq) < ($2, $3)
ORDER BY ts DESC, seq DESC LIMIT $4`

// EventsBefore returns up to limit events older than before, newest first (nil before means the newest page).
// The returned cursor is for the next, older page; it is nil when there is no older event.
func (s *Store) EventsBefore(ctx context.Context, roomID string, before *Cursor, limit int) ([]Event, *Cursor, error) {
	if limit <= 0 {
		limit = 50
	}
	ts, seq := int64(math.MaxInt64), int64(math.MaxInt64)
	if before != nil {
		ts, seq = before.TS.UnixMilli(), before.Seq
	}
	rows, err := s.db.Query(ctx, eventsBeforeSQL, roomID, ts, seq, limit+1) // one extra row says whether an older page exists
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	if len(out) <= limit {
		return out, nil, nil
	}
	out = out[:limit]
	last := out[limit-1]
	return out, &Cursor{TS: last.TS, Seq: last.Seq}, nil
}

// MarkReadLocal records that the user read roomID up to eventID (whose time is ts) on this device. It is kept
// apart from SetRead, which is the network's own report; the unread count uses whichever is later.
func (s *Store) MarkReadLocal(ctx context.Context, roomID, eventID string, ts time.Time) error {
	_, err := s.db.Exec(ctx, `INSERT INTO local_reads (room_id, event_id, ts) VALUES ($1,$2,$3)
		ON CONFLICT(room_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`, roomID, eventID, ts.UnixMilli())
	if err == nil {
		s.publish(Change{Kind: "read", RoomID: roomID, EventID: eventID})
	}
	return err
}

// SetMuted sets whether the user muted roomID. It survives the bridge refreshing the room.
func (s *Store) SetMuted(ctx context.Context, roomID string, muted bool) error {
	_, err := s.db.Exec(ctx, `INSERT INTO room_prefs (room_id, muted) VALUES ($1,$2)
		ON CONFLICT(room_id) DO UPDATE SET muted=excluded.muted`, roomID, b2i(muted))
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}
