// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"errors"
	"math"
	"time"
)

// A reminder's condition.
const (
	// Inferred (inventory 01 §18): "If no reply" means "if I haven't sent a message since setting it" (repliedSinceSQL).
	condIfNoReply = "if_no_reply"
	condAlways    = "always"
)

// maxReminderYears is how far ahead a reminder can be set.
const maxReminderYears = 5

// roomExists reports whether roomID is a known chat, inside the caller's transaction.
func (s *Store) roomExists(ctx context.Context, roomID string) (bool, error) {
	var one int
	err := s.db.QueryRow(ctx, "SELECT 1 FROM rooms WHERE room_id=$1", roomID).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// SetReminder sets (or replaces) the reminder of each chat in roomIDs: bring it back at due, under condition
// ("if_no_reply" or "always"). due must be after now and at most 5 years ahead, and condition one of the two, or
// it is ErrBadValue. An unknown chat is ErrNotFound and sets none of them. A replaced reminder starts again: its
// set time is now and it has not fired. Each chat's row changes ("room").
func (s *Store) SetReminder(ctx context.Context, roomIDs []string, due time.Time, condition string) error {
	if condition != condIfNoReply && condition != condAlways {
		return ErrBadValue
	}
	now := s.now()
	dueMS := due.UnixMilli()
	if dueMS <= now.UnixMilli() || dueMS > now.AddDate(maxReminderYears, 0, 0).UnixMilli() {
		return ErrBadValue
	}
	ids := distinct(roomIDs)
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		for _, id := range ids {
			ok, err := s.roomExists(ctx, id)
			if err != nil {
				return err
			}
			if !ok {
				return ErrNotFound
			}
			if _, err = s.db.Exec(ctx, `INSERT INTO reminders (room_id, due_at, condition, set_at, fired_at) VALUES ($1,$2,$3,$4,0)
				ON CONFLICT(room_id) DO UPDATE SET due_at=excluded.due_at, condition=excluded.condition, set_at=excluded.set_at, fired_at=0`,
				id, dueMS, condition, now.UnixMilli()); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, id := range ids {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return nil
}

// ClearReminders removes the reminders of the chats in roomIDs, set or fired; nil removes every reminder (an empty
// list removes none). A chat without one is not an error. Each chat whose reminder went changes ("room").
func (s *Store) ClearReminders(ctx context.Context, roomIDs []string) error {
	var cleared []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		cleared = nil
		if roomIDs == nil {
			rows, err := s.db.Query(ctx, "DELETE FROM reminders RETURNING room_id")
			if err != nil {
				return err
			}
			defer rows.Close()
			for rows.Next() {
				var id string
				if err := rows.Scan(&id); err != nil {
					return err
				}
				cleared = append(cleared, id)
			}
			return rows.Err()
		}
		for _, id := range distinct(roomIDs) {
			res, err := s.db.Exec(ctx, "DELETE FROM reminders WHERE room_id=$1", id)
			if err != nil {
				return err
			}
			if n, _ := res.RowsAffected(); n > 0 {
				cleared = append(cleared, id)
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, id := range cleared {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return nil
}

// ClearFiredReminder ends roomID's reminder if it has fired: opening or reading the chat is what a fired reminder
// was waiting for. A reminder still to come is left alone.
func (s *Store) ClearFiredReminder(ctx context.Context, roomID string) error {
	res, err := s.db.Exec(ctx, "DELETE FROM reminders WHERE room_id=$1 AND fired_at > 0", roomID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return nil
}

// NextDue is the earliest time something is waiting for: a reminder that hasn't fired, a pending auto-archive, a
// waiting outbox message (held or scheduled; one waiting for its network waits for no time), or a message's
// disappearing timer. It may be in the past (overdue:
// due now). ok is false when nothing is waiting. Each part is the first entry of an index (reminders_due,
// archive_due's own, outbox_due, events_expiry).
func (s *Store) NextDue(ctx context.Context) (time.Time, bool, error) {
	return s.nextDue(ctx, math.MinInt64)
}

// NextDueAfter is NextDue counting only what is due strictly after after. The timer loop asks it with the time of
// its last pass: what was due by then and is still waiting was left on purpose (its feature isn't allowed, or the
// call failed), and must not hide something due later in another part, such as a held message due in 750 ms behind
// a reminder left overdue while reminders aren't allowed. Each part filters on its own, so it stays a range scan of
// its index.
func (s *Store) NextDueAfter(ctx context.Context, after time.Time) (time.Time, bool, error) {
	return s.nextDue(ctx, after.UnixMilli())
}

func (s *Store) nextDue(ctx context.Context, afterMS int64) (time.Time, bool, error) {
	var next sql.NullInt64
	err := s.db.QueryRow(ctx, `SELECT MIN(d) FROM (
		SELECT MIN(due_at) AS d FROM reminders WHERE fired_at = 0 AND due_at > $1
		UNION ALL SELECT MIN(due_at) FROM archive_due WHERE due_at > $1
		UNION ALL SELECT MIN(due_at) FROM outbox WHERE state = '`+stateWaiting+`' AND due_at > $1 AND kind <> '`+outboxOffline+`'
		UNION ALL SELECT MIN(expires_at) FROM events WHERE expires_at IS NOT NULL AND redacted = 0 AND expires_at > $1)`,
		afterMS).Scan(&next)
	if err != nil || !next.Valid {
		return time.Time{}, false, err
	}
	return time.UnixMilli(next.Int64), true, nil
}

// repliedSinceSQL is whether I sent a message in room $1 after $3 (Unix ms), $2 being my user ID: a message-like
// event that isn't an edit (messageLikeTypes, notEditSQL, as InsertEvent's isMessageLike), didn't fail to send and
// isn't held for undo send or waiting for its network (queued, waiting: Don't Send may still take it back), and isn't
// a note that I changed the disappearing timer (Ruling 40: changing a setting isn't replying). A call I made is a
// reply, whatever became of it: calling back is replying.
// It is a range scan of events_room_ts.
var repliedSinceSQL = `SELECT EXISTS (SELECT 1 FROM events WHERE room_id = $1 AND ts > $3 AND sender = $2
	AND type IN (` + messageLikeTypes + `) AND status NOT IN ('failed', 'queued', '` + StatusWaiting + `') AND ` + notEditSQL("content") + `
	AND (` + isTimerNoteSQL("content") + `) IS NOT 1)`

// FireDueReminders fires every reminder that is due by now and hasn't fired, and returns the chats whose reminder
// fired. Each goes in its own transaction:
//   - "if_no_reply", and I sent a message in the chat since setting it: the reminder is deleted, and nothing else
//     happens (the row loses its badge: "room");
//   - otherwise the reminder fires: fired_at is now, the chat is marked unread and back from the archive and Low
//     priority (a hidden chat stays hidden), a pending auto-archive of it is dropped (it would hide what the
//     reminder just brought back), and "room" then "reminder" are published.
//
// fired_at is written in the same transaction as everything else, so a reminder fires exactly once however often
// this runs and however the engine stops: one that came due while Courier was quit fires on the first call after
// it starts again. A reminder that fails is reported and left for the next call; the others still run.
func (s *Store) FireDueReminders(ctx context.Context) (fired []string, err error) {
	now := s.now().UnixMilli()
	rows, err := s.db.Query(ctx, "SELECT room_id FROM reminders WHERE fired_at = 0 AND due_at <= $1 ORDER BY due_at, room_id", now)
	if err != nil {
		return nil, err
	}
	var due []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		due = append(due, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	var errs []error
	for _, id := range due {
		outcome, err := s.fireReminder(ctx, id, now)
		switch {
		case err != nil:
			errs = append(errs, err)
		case outcome == reminderFired:
			fired = append(fired, id)
			s.publish(Change{Kind: "room", RoomID: id})
			s.publish(Change{Kind: "reminder", RoomID: id})
		case outcome == reminderDropped:
			s.publish(Change{Kind: "room", RoomID: id})
		}
	}
	return fired, errors.Join(errs...)
}

type reminderOutcome int

const (
	reminderGone    reminderOutcome = iota // cleared, or fired, since FireDueReminders looked
	reminderFired                          // it fired
	reminderDropped                        // "if no reply", and I replied
)

// fireReminder fires roomID's reminder, if it is still due and unfired, in one transaction.
func (s *Store) fireReminder(ctx context.Context, roomID string, now int64) (reminderOutcome, error) {
	var outcome reminderOutcome
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		outcome = reminderGone
		var cond string
		var setAt int64
		err := s.db.QueryRow(ctx, "SELECT condition, set_at FROM reminders WHERE room_id=$1 AND fired_at = 0 AND due_at <= $2",
			roomID, now).Scan(&cond, &setAt)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		if cond == condIfNoReply {
			var replied bool
			if err = s.db.QueryRow(ctx, repliedSinceSQL, roomID, myID, setAt).Scan(&replied); err != nil {
				return err
			}
			if replied {
				_, err = s.db.Exec(ctx, "DELETE FROM reminders WHERE room_id=$1", roomID)
				outcome = reminderDropped
				return err
			}
		}
		if _, err = s.db.Exec(ctx, "UPDATE reminders SET fired_at=$2 WHERE room_id=$1", roomID, now); err != nil {
			return err
		}
		p, err := s.readPrefs(ctx, roomID)
		if err != nil {
			return err
		}
		// Ruling 38b: the chat comes back to the inbox, as the help text promises: out of the archive and out of
		// Low priority, marked unread. A hidden chat stays hidden; hiding it is the stronger choice.
		p.markedUnread, p.archivedAt, p.lowPriority = true, 0, false
		if err = s.writePrefs(ctx, roomID, p); err != nil {
			return err
		}
		if _, err = s.db.Exec(ctx, "DELETE FROM archive_due WHERE room_id=$1", roomID); err != nil {
			return err
		}
		outcome = reminderFired
		return nil
	})
	if err != nil {
		return reminderGone, err
	}
	return outcome, nil
}
