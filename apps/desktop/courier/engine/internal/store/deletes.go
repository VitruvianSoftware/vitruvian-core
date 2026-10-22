// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

// A message leaves this Mac three ways, and each sets redacted = 1, so it is no longer the chat's latest message,
// unread or searchable (4.2's events_unindex_redacted trigger takes its doc out): an unsend (my redaction, which the
// network may still refuse), Delete for Me (deleted_for_me = 1 too: gone here only, with no placeholder), and a
// disappearing timer running out. A refused unsend puts the message back (unredact), unless it was also deleted for
// me or another redaction of it stands.

// listedBookmarksSQL lists the bookmarks a person can see, newest first: those whose message isn't deleted. The row
// of a deleted message's bookmark stays, so a refused unsend that puts the message back gives the bookmark back too;
// DeleteEvent forgets it (the foreign key cascades). Every list of bookmarks keeps to this rule.
const listedBookmarksSQL = `SELECT b.event_id FROM bookmarks b JOIN events e ON e.event_id = b.event_id
WHERE e.redacted = 0 ORDER BY b.created_at DESC, b.event_id`

// afterSendExpiry is when an after_send disappearing timer in content takes a message sent at ts: ts plus
// com.beeper.disappearing_timer.timer (ms), for a timer above 0. Anything else never expires (NULL). (SQL twin:
// afterSendTimerSQL, which migration 5 runs over the messages already on disk.)
func afterSendExpiry(content json.RawMessage, ts time.Time) sql.NullInt64 {
	var c struct {
		Timer *struct {
			Type  string  `json:"type"`
			Timer float64 `json:"timer"`
		} `json:"com.beeper.disappearing_timer"`
	}
	if json.Unmarshal(content, &c) != nil || c.Timer == nil || c.Timer.Type != "after_send" || int64(c.Timer.Timer) <= 0 {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: ts.UnixMilli() + int64(c.Timer.Timer), Valid: true}
}

// SetDeletedForMe deletes a message on this Mac only (Delete for Me): redacted and deleted_for_me, in one
// transaction. It is no longer unread, searchable or listed as a bookmark; if it was the chat's latest message, the
// chat goes back to the newest one left; if it was an edit, its message is re-indexed with the edit before it. The
// change feed gets a "status" change for it, as DeleteEvent gives. An unknown event is ErrNotFound.
func (s *Store) SetDeletedForMe(ctx context.Context, eventID string) error {
	var gone Event
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		gone, err = scanEvent(s.db.QueryRow(ctx, "UPDATE events SET redacted=1, deleted_for_me=1 WHERE event_id=$1 RETURNING "+eventCols, eventID))
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if _, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1 AND last_event_id=$2", gone.RoomID, eventID); err != nil {
			return err
		}
		if isEdit(gone.Content) {
			return s.applyEdit(ctx, gone)
		}
		return nil
	})
	if err == nil {
		s.publish(Change{Kind: "status", RoomID: gone.RoomID, EventID: eventID, Seq: gone.Seq})
	}
	return err
}

// unredactSQL puts back message $1 of chat $2, deleted by an unsend of mine the network refused, and returns it.
// It doesn't when the message was also deleted for me, when its disappearing timer has run out by $3 (now, in ms),
// or when another redaction of it that hasn't failed stands (the network's own, or a second unsend), found through
// events_redacts.
var unredactSQL = `UPDATE events SET redacted = 0 WHERE event_id = $1 AND room_id = $2 AND redacted = 1 AND deleted_for_me = 0
  AND (expires_at IS NULL OR expires_at > $3)
  AND NOT EXISTS (SELECT 1 FROM events r WHERE r.type = 'm.room.redaction' AND r.status <> 'failed' AND r.room_id = $2
    AND ` + redactionTargetSQL("r.content") + ` = $1)
RETURNING ` + eventCols

// unredact undoes redact for an unsend the network refused, inside SetStatus's transaction (the redaction is already
// failed): the message is back in the chat, unread if it was, searchable (indexEvent; an edit re-indexes its
// message instead) and, if it is the newest, the chat's latest again. back reports whether it came back. A message
// past its disappearing timer stays gone, so a refused unsend never lets it outstay its time.
func (s *Store) unredact(ctx context.Context, roomID, target string) (back bool, err error) {
	if target == "" {
		return false, nil
	}
	e, err := scanEvent(s.db.QueryRow(ctx, unredactSQL, target, roomID, s.now().UnixMilli()))
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if err = s.indexEvent(ctx, e); err != nil {
		return false, err
	}
	if _, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1", roomID); err != nil {
		return false, err
	}
	return true, nil
}
