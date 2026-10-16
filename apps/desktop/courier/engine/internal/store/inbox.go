// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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
//   - the unread count is a range scan of events_room_ts (room_id, ts, seq) from the read marker onward, so it
//     only touches messages that are actually newer than the marker.
//
// There are two markers: the network's read (reads) and this device's (local_reads). A message is unread when it
// is after both, which is the same as being after the later one. "After" compares (ts, seq), so a message in
// the same millisecond as the marker but received later still counts. Edits are never unread.
var inboxSQL = `SELECT r.room_id, r.network, r.name, r.topic, r.avatar_uri, r.is_direct, r.created_at,
  r.last_ts,
  COALESCE(ev.sender, ''), COALESCE(ev.type, ''), COALESCE(ev.content, ''),
  COALESCE(p.muted, 0),
  (SELECT COUNT(*) FROM events u
     WHERE u.room_id = r.room_id
       AND (u.ts, u.seq) > (COALESCE(rd.ts, 0), ` + markerSeq("rd", "rde") + `)
       AND (u.ts, u.seq) > (COALESCE(lr.ts, 0), ` + markerSeq("lr", "lre") + `)
       AND u.type IN (` + unreadTypes + `) AND u.sender <> $1 AND ` + notEditSQL("u.content") + `)
FROM rooms r
LEFT JOIN events ev ON ev.event_id = r.last_event_id
LEFT JOIN room_prefs p ON p.room_id = r.room_id
LEFT JOIN reads rd ON rd.room_id = r.room_id
LEFT JOIN events rde ON rde.event_id = rd.event_id AND rde.ts = rd.ts
LEFT JOIN local_reads lr ON lr.room_id = r.room_id
LEFT JOIN events lre ON lre.event_id = lr.event_id AND lre.ts = lr.ts
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
// apart from SetRead, which is the network's own report; the unread count uses whichever is later. The local
// marker only moves forward: an older (ts, seq) than the one already kept is ignored, and publishes nothing.
func (s *Store) MarkReadLocal(ctx context.Context, roomID, eventID string, ts time.Time) error {
	_, err := s.AdvanceReadLocal(ctx, roomID, eventID, ts)
	return err
}

// AdvanceReadLocal is MarkReadLocal that also says whether the marker moved. It does not move when the chat was
// already read up to that event or beyond it.
func (s *Store) AdvanceReadLocal(ctx context.Context, roomID, eventID string, ts time.Time) (bool, error) {
	moved := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		newSeq := int64(math.MaxInt64) // an event we do not have yet: compare on ts alone
		err := s.db.QueryRow(ctx, "SELECT seq FROM events WHERE event_id=$1 AND ts=$2", eventID, ts.UnixMilli()).Scan(&newSeq)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var curTS, curSeq int64
		err = s.db.QueryRow(ctx, `SELECT lr.ts, `+markerSeq("lr", "e")+` FROM local_reads lr
			LEFT JOIN events e ON e.event_id = lr.event_id AND e.ts = lr.ts WHERE lr.room_id=$1`, roomID).Scan(&curTS, &curSeq)
		switch {
		case err == nil:
			if newTS := ts.UnixMilli(); newTS < curTS || (newTS == curTS && newSeq <= curSeq) {
				return nil // not later than what we have
			}
		case !errors.Is(err, sql.ErrNoRows):
			return err
		}
		_, err = s.db.Exec(ctx, `INSERT INTO local_reads (room_id, event_id, ts) VALUES ($1,$2,$3)
			ON CONFLICT(room_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`, roomID, eventID, ts.UnixMilli())
		moved = err == nil
		return err
	})
	if err == nil && moved {
		s.publish(Change{Kind: "read", RoomID: roomID, EventID: eventID})
	}
	return moved && err == nil, err
}

// LastMessage returns the chat's newest message-like event: the one its inbox row previews (rooms.last_event_id),
// so a reaction, an edit or a state event never counts. ok is false for a chat with no message yet.
func (s *Store) LastMessage(ctx context.Context, roomID string) (Event, bool, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id = (SELECT last_event_id FROM rooms WHERE room_id=$1)", roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return Event{}, false, nil
	}
	return e, err == nil, err
}

// FindReaction returns the ID of sender's reaction with key to target in roomID, if there is one that has not
// failed (pending or sent). A failed reaction does not count, so it can be sent again.
func (s *Store) FindReaction(ctx context.Context, roomID, sender, target, key string) (string, bool, error) {
	var id string
	err := s.db.QueryRow(ctx, `SELECT event_id FROM events
		WHERE room_id=$1 AND sender=$2 AND type='m.reaction' AND status <> 'failed'
		  AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END) = $3
		  AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".key') END) = $4
		ORDER BY ts, seq LIMIT 1`, roomID, sender, target, key).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return id, err == nil, err
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
