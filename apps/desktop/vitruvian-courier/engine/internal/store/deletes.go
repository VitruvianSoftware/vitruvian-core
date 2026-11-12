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

// MaxFutureSkew is how far past now a stored event's time may be: a bridge's time beyond it (a phone whose clock is
// wrong, or a number no clock gives) is stored as now + MaxFutureSkew, and one before 1970 as 1970 (clampTS). Every
// time the app is handed can then be subtracted from another without overflowing.
const MaxFutureSkew = 24 * time.Hour

// MaxDisappearingTimer is the longest after_send timer stored: about ten years, longer than any network offers
// (Telegram's longest is a year). A longer one, or one no duration holds, is stored as this.
const MaxDisappearingTimer = 10 * 365 * 24 * time.Hour

// afterSendExpiry is when an after_send disappearing timer in content takes a message sent at ts: ts plus
// com.beeper.disappearing_timer.timer (ms), for a timer of at least 1 ms, capped at MaxDisappearingTimer. Anything
// else never expires (NULL). (SQL twin:
// afterSendTimerSQL, which migration 5 runs over the messages already on disk.)
func afterSendExpiry(content json.RawMessage, ts time.Time) sql.NullInt64 {
	var c struct {
		Timer *struct {
			Type  string  `json:"type"`
			Timer float64 `json:"timer"`
		} `json:"com.beeper.disappearing_timer"`
	}
	// The float is compared before it is converted: Go's conversion of one past int64 is undefined.
	if json.Unmarshal(content, &c) != nil || c.Timer == nil || c.Timer.Type != "after_send" || !(c.Timer.Timer >= 1) {
		return sql.NullInt64{}
	}
	timer := MaxDisappearingTimer.Milliseconds()
	if c.Timer.Timer < float64(timer) {
		timer = int64(c.Timer.Timer)
	}
	return sql.NullInt64{Int64: ts.UnixMilli() + timer, Valid: true}
}

// clampTS is the time an event is stored with: ts, but not before 1970 nor past now + MaxFutureSkew.
func (s *Store) clampTS(ts time.Time) time.Time {
	if latest := s.now().Add(MaxFutureSkew); ts.After(latest) {
		return time.UnixMilli(latest.UnixMilli())
	}
	if ts.UnixMilli() < 0 {
		return time.UnixMilli(0)
	}
	return ts
}

// SetDeletedForMe deletes a message on this Mac only (Delete for Me): redacted and deleted_for_me, in one
// transaction. It is no longer unread, searchable or listed as a bookmark; if it was the chat's latest message, the
// chat goes back to the newest one left; if it was an edit, its message is re-indexed with the edit before it; if it
// was held for undo send or waiting for its network, its outbox row goes too, so it is never sent. The change feed
// gets a "status" change for it, as DeleteEvent gives. An unknown event is ErrNotFound.
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
		// A held or waiting message deleted before it went is never sent: its undo or offline row goes with it.
		if _, err = s.db.Exec(ctx, "DELETE FROM outbox WHERE event_id=$1 AND kind IN ('"+outboxUndo+"', '"+outboxOffline+"')", eventID); err != nil {
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

// Redacted reports whether event eventID is deleted here: unsent (by me or the network), deleted for me, or past its
// disappearing timer. An unknown event is ErrNotFound.
func (s *Store) Redacted(ctx context.Context, eventID string) (bool, error) {
	var redacted bool
	err := s.db.QueryRow(ctx, "SELECT redacted FROM events WHERE event_id=$1", eventID).Scan(&redacted)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrNotFound
	}
	return redacted, err
}

// RedactedAmong is which of eventIDs are deleted here (Redacted), in one query. Unknown IDs are left out.
func (s *Store) RedactedAmong(ctx context.Context, eventIDs []string) (map[string]bool, error) {
	out := map[string]bool{}
	if len(eventIDs) == 0 {
		return out, nil
	}
	raw, err := json.Marshal(eventIDs)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `SELECT event_id FROM events WHERE redacted = 1
		AND event_id IN (SELECT value FROM json_each($1))`, string(raw))
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

// ExpireDue deletes every message whose after_send disappearing timer has run out by now (expires_at <= now), as the
// network's own loop would, so one never outstays its timer while that loop sleeps (4.1 found Go timers stop while a
// Mac sleeps): redacted = 1, in one transaction, so it leaves the timeline, the chat's preview (each chat goes back to
// the newest message left), unread and search (events_unindex_redacted). An expired edit gives its message back the
// edit before it. It returns the chats it changed, and publishes a "status" change for each message and a "room"
// change for each chat. The lookup is a range scan of events_expiry.
func (s *Store) ExpireDue(ctx context.Context) ([]string, error) {
	now := s.now().UnixMilli()
	var gone []Event
	var rooms []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		gone, err = s.queryEvents(ctx, expireDueSQL, now)
		if err != nil {
			return err
		}
		rooms = nil
		seen := map[string]bool{}
		for _, e := range gone {
			if _, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1 AND last_event_id=$2", e.RoomID, e.EventID); err != nil {
				return err
			}
			if isEdit(e.Content) {
				if err = s.applyEdit(ctx, e); err != nil {
					return err
				}
			}
			if !seen[e.RoomID] {
				seen[e.RoomID] = true
				rooms = append(rooms, e.RoomID)
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	for _, e := range gone {
		s.publish(Change{Kind: "status", RoomID: e.RoomID, EventID: e.EventID, Seq: e.Seq})
	}
	for _, r := range rooms {
		s.publish(Change{Kind: "room", RoomID: r})
	}
	return rooms, nil
}

// expireDueSQL deletes the messages whose disappearing timer ran out by $1 (Unix ms) and returns them, through
// events_expiry (its WHERE is repeated, so the planner can use it).
var expireDueSQL = `UPDATE events SET redacted = 1 WHERE event_id IN (
  SELECT event_id FROM events WHERE expires_at IS NOT NULL AND redacted = 0 AND expires_at <= $1)
RETURNING ` + eventCols
