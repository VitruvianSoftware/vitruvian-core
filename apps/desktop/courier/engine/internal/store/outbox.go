// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	"go.mau.fi/util/dbutil"
)

// The outbox holds three kinds of message that haven't gone yet.
//
//   - undo: a message held for undo send. It is already an events row, with status queued (in the chat, its preview
//     and search), and its outbox row says when the window ends. Unhold (Undo) deletes both; a claim makes it pending,
//     for the bridge to send.
//   - later: a scheduled message. It lives only in its outbox row (its type and content) until it fires: not in the
//     timeline, not in search. A claim inserts it as a new pending event, sent now.
//   - offline: a message waiting for its network (spec §5, "sends queue as pending"): written while the network was
//     starting or down, or put back by a hand-off that found it down. It is an events row with status waiting (in the
//     chat, its preview and search), and its row is due at once but waits for the network, not the clock: ClaimDue
//     and NextDue pass over it, and only ClaimWaiting, for a network whose login is logged in, takes it. There is no
//     cut-off (Review Focus 1); Unhold (Don't Send) takes it back as it takes a held one.
//
// Every claim takes outbox rows and leaves the messages it returns pending, in one transaction, so a message comes back
// from at most one claim, and a claim racing an Undo ends one way: the transactions are BEGIN IMMEDIATE (sqlite.Open),
// so one of them runs first and the other finds the row gone. A crash after a claim and before the bridge took the
// message leaves it pending, and FailInterruptedSends at the next start makes it failed with ReasonMayHaveBeenSent: it
// is never sent twice, and never lost without the person seeing it.

// MaxLate is how late an outbox message may be sent by itself: a held message more late than this becomes failed
// (ReasonNotSent), a scheduled one waits as missed.
// Inferred: an hour; a message hours late can be wrong, and the person should see it first.
const MaxLate = time.Hour

// ReasonNotSent is the status_reason of a held message whose window ended more than MaxLate before the engine could
// send it (Courier was closed): nothing was sent. The app words it.
const ReasonNotSent = "not sent"

// ErrAlreadySent is Unhold's answer once a message is no longer held: its window ended and it was claimed.
var ErrAlreadySent = errors.New("it has already gone")

// StatusWaiting is the status of a message of mine waiting for its network to send it (an offline outbox row).
// Inferred: there is no cut-off; it goes when the network is back, however long that takes, and the person sees it
// waiting all along, with Don't Send (WhatsApp's own app behaves this way).
const StatusWaiting = "waiting"

// The kinds and states of outbox rows. (An outbox row's state "waiting" is the row's, and says nothing of the kind:
// every claim of the clock filters out offline rows by kind.)
const (
	outboxUndo    = "undo"
	outboxLater   = "later"
	outboxOffline = "offline"

	stateWaiting  = "waiting"
	stateCanceled = "canceled"
	stateMissed   = "missed"
)

// sourceKey is the content key that carries what the composer typed (its text and entities), so Undo and Edit
// Scheduled give back exactly that. It is never sent: every claim writes the content without it.
const sourceKey = "fi.courier.source"

// SourceKey is sourceKey for the actions that write it: what the composer typed, carried by a held or scheduled
// message's content and dropped by every claim.
const SourceKey = sourceKey

// Scheduled is a message scheduled to be sent later.
type Scheduled struct {
	ID                    int64
	RoomID, EventID, Type string
	Content               json.RawMessage
	DueAt, SetAt          time.Time
	Condition, State      string // if_no_reply | always; waiting | canceled | missed
}

// withoutSource is content less sourceKey, ready for a bridge. Content that isn't a JSON object, or doesn't have
// the key, is returned as it is.
func withoutSource(content json.RawMessage) json.RawMessage {
	var m map[string]json.RawMessage
	if json.Unmarshal(content, &m) != nil || m == nil {
		return content
	}
	if _, ok := m[sourceKey]; !ok {
		return content
	}
	delete(m, sourceKey)
	b, err := json.Marshal(m)
	if err != nil {
		return content
	}
	return b
}

// Hold stores my new message e as held for undo send until due: e, with status queued, through InsertEvent's rules
// (it moves the chat and is indexed), and its undo row, in one transaction. A chat that isn't known is ErrNotFound;
// an event ID that is already here, as an event or in the outbox, is ErrBadValue.
func (s *Store) Hold(ctx context.Context, e Event, due time.Time) error {
	return s.keep(ctx, e, "queued", outboxUndo, due)
}

// Wait stores my new message e as waiting for its network: e, with status waiting, through InsertEvent's rules (it
// moves the chat and is indexed), and its offline row, due now, in one transaction. Its content keeps sourceKey until
// a claim, so Don't Send gives back what was typed. A chat that isn't known is ErrNotFound; an event ID that is
// already here, as an event or in the outbox, is ErrBadValue.
func (s *Store) Wait(ctx context.Context, e Event) error {
	return s.keep(ctx, e, StatusWaiting, outboxOffline, s.now())
}

// keep is Hold's and Wait's body: e with status, and its outbox row of kind, due at due.
func (s *Store) keep(ctx context.Context, e Event, status, kind string, due time.Time) error {
	e.Status, e.StatusReason = status, ""
	seq := s.nextSeq()
	var cameBack bool
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		ok, err := s.roomExists(ctx, e.RoomID)
		if err != nil {
			return err
		}
		if !ok {
			return ErrNotFound
		}
		var taken bool
		if err = s.db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM outbox WHERE event_id=$1)", e.EventID).Scan(&taken); err != nil {
			return err
		}
		if taken {
			return ErrBadValue // a scheduled message will be sent as this ID
		}
		inserted, back, err := s.insertEvent(ctx, e, seq)
		if err != nil {
			return err
		}
		if !inserted {
			return ErrBadValue
		}
		cameBack = back
		_, err = s.db.Exec(ctx, `INSERT INTO outbox (room_id, kind, event_id, due_at, set_at, condition, state)
			VALUES ($1, $2, $3, $4, $5, 'always', '`+stateWaiting+`')`,
			e.RoomID, kind, e.EventID, due.UnixMilli(), s.now().UnixMilli())
		return err
	})
	if err != nil {
		return err
	}
	s.publishInserted(e, seq, true, cameBack)
	return nil
}

// Unhold takes back a held message (Undo) or a waiting one (Don't Send): its undo or offline row and its event go,
// in one transaction, and the event is returned as it was kept, content and all, for the composer. The chat goes
// back to the newest message left, and the message's doc leaves search (events_unindex). Once the message is no
// longer held or waiting (claimed, or never kept) it is ErrAlreadySent.
func (s *Store) Unhold(ctx context.Context, eventID string) (Event, error) {
	var gone Event
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var kind string
		err := s.db.QueryRow(ctx, `DELETE FROM outbox WHERE event_id=$1 AND kind IN ('`+outboxUndo+`', '`+outboxOffline+`') RETURNING kind`,
			eventID).Scan(&kind)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrAlreadySent
		}
		if err != nil {
			return err
		}
		gone, err = scanEvent(s.db.QueryRow(ctx, "DELETE FROM events WHERE event_id=$1 AND status=$2 RETURNING "+eventCols,
			eventID, keptStatus(kind)))
		if errors.Is(err, sql.ErrNoRows) {
			return ErrAlreadySent // its event went another way (deleted): nothing to give back
		}
		if err != nil {
			return err
		}
		_, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1 AND last_event_id=$2", gone.RoomID, eventID)
		return err
	})
	if err != nil {
		return Event{}, err
	}
	s.publish(Change{Kind: "status", RoomID: gone.RoomID, EventID: eventID, Seq: gone.Seq})
	return gone, nil
}

// validScheduleDue reports whether due is after now and at most 5 years ahead (the reminders' rule).
func validScheduleDue(due, now time.Time) bool {
	return due.UnixMilli() > now.UnixMilli() && due.UnixMilli() <= now.AddDate(maxReminderYears, 0, 0).UnixMilli()
}

// Schedule stores a message to be sent later: sc's room, event ID (the ID it will be sent as), type, content, due
// time and condition ("if_no_reply", the default for "", or "always"). due must be after now and at most 5 years
// ahead, the condition one of the two, and the type and event ID set, or it is ErrBadValue; an unknown chat is
// ErrNotFound. It is waiting, set now. The chat joins the send_later space ("scheduled").
func (s *Store) Schedule(ctx context.Context, sc Scheduled) (Scheduled, error) {
	if sc.Condition == "" {
		sc.Condition = condIfNoReply
	}
	now := s.now()
	if sc.Condition != condIfNoReply && sc.Condition != condAlways || !validScheduleDue(sc.DueAt, now) ||
		sc.EventID == "" || sc.Type == "" || !json.Valid(sc.Content) {
		return Scheduled{}, ErrBadValue
	}
	sc.SetAt, sc.State = time.UnixMilli(now.UnixMilli()), stateWaiting
	sc.DueAt = time.UnixMilli(sc.DueAt.UnixMilli())
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		ok, err := s.roomExists(ctx, sc.RoomID)
		if err != nil {
			return err
		}
		if !ok {
			return ErrNotFound
		}
		var taken bool
		if err = s.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM events WHERE event_id=$1) OR EXISTS (SELECT 1 FROM outbox WHERE event_id=$1)`,
			sc.EventID).Scan(&taken); err != nil {
			return err
		}
		if taken {
			return ErrBadValue
		}
		return s.db.QueryRow(ctx, `INSERT INTO outbox (room_id, kind, event_id, type, content, due_at, set_at, condition, state)
			VALUES ($1, '`+outboxLater+`', $2, $3, $4, $5, $6, $7, '`+stateWaiting+`') RETURNING outbox_id`,
			sc.RoomID, sc.EventID, sc.Type, string(sc.Content), sc.DueAt.UnixMilli(), sc.SetAt.UnixMilli(), sc.Condition).Scan(&sc.ID)
	})
	if err != nil {
		return Scheduled{}, err
	}
	s.publish(Change{Kind: "scheduled", RoomID: sc.RoomID})
	return sc, nil
}

const scheduledCols = "outbox_id, room_id, event_id, type, content, due_at, set_at, condition, state"

func scanScheduled(row dbutil.Scannable) (Scheduled, error) {
	var sc Scheduled
	var content string
	var due, set int64
	err := row.Scan(&sc.ID, &sc.RoomID, &sc.EventID, &sc.Type, &content, &due, &set, &sc.Condition, &sc.State)
	sc.Content, sc.DueAt, sc.SetAt = json.RawMessage(content), time.UnixMilli(due), time.UnixMilli(set)
	return sc, err
}

// UpdateScheduled changes scheduled message id: a non-nil due (after now and at most 5 years ahead), a type and
// content (when typ is not ""), a non-nil condition. Whatever it changes, it is waiting again and set now, so a
// reply before this change no longer cancels it. A canceled or missed message needs a new due time to wait again:
// without one it is ErrBadValue, so an edit never sends a past-due message by itself. An unknown ID is ErrNotFound;
// a value it doesn't take ErrBadValue.
func (s *Store) UpdateScheduled(ctx context.Context, id int64, due *time.Time, typ string, content json.RawMessage, condition *string) (Scheduled, error) {
	now := s.now()
	if due != nil && !validScheduleDue(*due, now) ||
		condition != nil && *condition != condIfNoReply && *condition != condAlways ||
		typ != "" && !json.Valid(content) {
		return Scheduled{}, ErrBadValue
	}
	var sc Scheduled
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		sc, err = scanScheduled(s.db.QueryRow(ctx, "SELECT "+scheduledCols+" FROM outbox WHERE outbox_id=$1 AND kind='"+outboxLater+"'", id))
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}
		if due == nil && sc.State != stateWaiting {
			return ErrBadValue // a canceled or missed message waits again only for a new time, never its past one
		}
		if due != nil {
			sc.DueAt = time.UnixMilli(due.UnixMilli())
		}
		if typ != "" {
			sc.Type, sc.Content = typ, content
		}
		if condition != nil {
			sc.Condition = *condition
		}
		sc.SetAt, sc.State = time.UnixMilli(now.UnixMilli()), stateWaiting
		_, err = s.db.Exec(ctx, `UPDATE outbox SET due_at=$2, type=$3, content=$4, condition=$5, set_at=$6, state='`+stateWaiting+`'
			WHERE outbox_id=$1`, id, sc.DueAt.UnixMilli(), sc.Type, string(sc.Content), sc.Condition, sc.SetAt.UnixMilli())
		return err
	})
	if err != nil {
		return Scheduled{}, err
	}
	s.publish(Change{Kind: "scheduled", RoomID: sc.RoomID})
	return sc, nil
}

// ScheduledByID is scheduled message id, in any state; ErrNotFound when there is none (a held message's row isn't
// one).
func (s *Store) ScheduledByID(ctx context.Context, id int64) (Scheduled, error) {
	sc, err := scanScheduled(s.db.QueryRow(ctx, "SELECT "+scheduledCols+" FROM outbox WHERE outbox_id=$1 AND kind='"+outboxLater+"'", id))
	if errors.Is(err, sql.ErrNoRows) {
		return Scheduled{}, ErrNotFound
	}
	return sc, err
}

// ScheduledIn lists the scheduled messages of roomID ("" is every chat), in any state, soonest first.
func (s *Store) ScheduledIn(ctx context.Context, roomID string) ([]Scheduled, error) {
	q := "SELECT " + scheduledCols + " FROM outbox WHERE kind='" + outboxLater + "'"
	var args []any
	if roomID != "" {
		q += " AND room_id=$1"
		args = append(args, roomID)
	}
	rows, err := s.db.Query(ctx, q+" ORDER BY due_at, outbox_id", args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Scheduled{}
	for rows.Next() {
		sc, err := scanScheduled(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, sc)
	}
	return out, rows.Err()
}

// DeleteScheduled deletes scheduled message id, in any state. An unknown ID is ErrNotFound.
func (s *Store) DeleteScheduled(ctx context.Context, id int64) error {
	var roomID string
	err := s.db.QueryRow(ctx, "DELETE FROM outbox WHERE outbox_id=$1 AND kind='"+outboxLater+"' RETURNING room_id", id).Scan(&roomID)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	s.publish(Change{Kind: "scheduled", RoomID: roomID})
	return nil
}

// claimed is what a claim's transaction did, published once it commits.
type claimed struct {
	out       []Event  // the messages now pending, for the bridge
	statuses  []Event  // events whose status changed (held messages claimed, or failed as not sent)
	inserted  []Event  // scheduled messages inserted
	cameBack  []bool   // for each of inserted, whether it brought its chat back from the archive
	scheduled []string // rooms whose scheduled messages changed
}

func (c *claimed) publish(s *Store) {
	for _, e := range c.statuses {
		s.publish(Change{Kind: "status", RoomID: e.RoomID, EventID: e.EventID, Seq: e.Seq})
	}
	for i, e := range c.inserted {
		s.publishInserted(e, e.Seq, true, c.cameBack[i])
	}
	seen := map[string]bool{}
	for _, r := range c.scheduled {
		if !seen[r] {
			seen[r] = true
			s.publish(Change{Kind: "scheduled", RoomID: r})
		}
	}
}

// outboxRow is one row of the outbox, as a claim reads it.
type outboxRow struct {
	id                                  int64
	roomID, kind, eventID, typ, content string
	due, set                            int64
	condition                           string
}

func (s *Store) outboxRows(ctx context.Context, query string, args ...any) ([]outboxRow, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []outboxRow
	for rows.Next() {
		var r outboxRow
		if err := rows.Scan(&r.id, &r.roomID, &r.kind, &r.eventID, &r.typ, &r.content, &r.due, &r.set, &r.condition); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

const outboxRowCols = "outbox_id, room_id, kind, event_id, type, content, due_at, set_at, condition"

// keptStatus is the status of the events row an undo or offline outbox row keeps: queued or waiting.
func keptStatus(kind string) string {
	if kind == outboxOffline {
		return StatusWaiting
	}
	return "queued"
}

// releaseHeld gives held or waiting message r (by its row's kind) status (pending, or failed with reason), with its
// content less sourceKey, and deletes its row, inside a claim's transaction. An event that is gone (deleted
// meanwhile, or redacted: unsent or deleted for me) just loses its row, and is never handed over.
func (s *Store) releaseHeld(ctx context.Context, c *claimed, r outboxRow, status, reason string) error {
	if _, err := s.db.Exec(ctx, "DELETE FROM outbox WHERE outbox_id=$1", r.id); err != nil {
		return err
	}
	kept := keptStatus(r.kind)
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1 AND status=$2 AND redacted=0", r.eventID, kept))
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	// The status check is repeated in the write, so a message leaves queued (or waiting) at most once whatever the
	// locking.
	e, err = scanEvent(s.db.QueryRow(ctx, "UPDATE events SET status=$2, status_reason=$3, content=$4 WHERE event_id=$1 AND status=$5 AND redacted=0 RETURNING "+eventCols,
		r.eventID, status, reason, string(withoutSource(e.Content)), kept))
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	c.statuses = append(c.statuses, e)
	if status != "pending" {
		return nil
	}
	c.out = append(c.out, e)
	// Now it is my reply: with an enabled after_reply rule the chat is archived that long after it, if it is still the
	// chat's newest message (InsertEvent's rule, which Hold left for this moment).
	var newest bool
	if err = s.db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM rooms WHERE room_id=$1 AND last_event_id=$2)", e.RoomID, e.EventID).Scan(&newest); err != nil || !newest {
		return err
	}
	return s.scheduleArchive(ctx, e.RoomID, trigAfterReply, e.TS.UnixMilli())
}

// sendScheduled deletes scheduled row r and inserts its message as my pending event, sent now, through InsertEvent's
// rules (it moves the chat and is indexed), inside a claim's transaction. An event ID that is already here (it went
// some other way) is not sent again.
func (s *Store) sendScheduled(ctx context.Context, c *claimed, r outboxRow, now time.Time) error {
	if _, err := s.db.Exec(ctx, "DELETE FROM outbox WHERE outbox_id=$1", r.id); err != nil {
		return err
	}
	c.scheduled = append(c.scheduled, r.roomID)
	e := Event{
		RoomID: r.roomID, EventID: r.eventID, Sender: myID, Type: r.typ, Content: withoutSource(json.RawMessage(r.content)),
		TS: now, Status: "pending", Seq: s.nextSeq(),
	}
	inserted, cameBack, err := s.insertEvent(ctx, e, e.Seq)
	if err != nil || !inserted {
		return err
	}
	c.out = append(c.out, e)
	c.inserted, c.cameBack = append(c.inserted, e), append(c.cameBack, cameBack)
	return nil
}

// replyCancelsSQL is whether someone else wrote in chat $1 after $3 (Unix ms), $2 being my user ID: a message-like
// event that isn't an edit (messageLikeTypes, notEditSQL), isn't deleted and isn't a notice, a range scan of
// events_room_ts. It is what cancels a scheduled message set "if no reply". A call that is news (it rang, or was
// missed) is them reaching out, even when the bridge sends it as a notice; the record that a call ended isn't.
// Inferred (inventory 01 §5, "canceled by reply"): a message from anyone else in the chat after it was set (or last
// changed) cancels it; my own messages, reactions, deleted messages and m.notice messages (bridge and bot notices,
// not a person writing back) don't.
var replyCancelsSQL = `SELECT EXISTS (SELECT 1 FROM events WHERE room_id = $1 AND ts > $3 AND sender <> $2
	AND type IN (` + messageLikeTypes + `) AND redacted = 0 AND ` + notEditSQL("content") + `
	AND ((CASE WHEN json_valid(content) THEN json_extract(content, '$.msgtype') END) IS NOT 'm.notice' OR (` + isCallNewsSQL("content") + `) IS 1)
	AND (` + isCallRecordSQL("content") + `) IS NOT 1)`

// ClaimDue claims every waiting undo and later outbox row that is due by now, oldest first, in one transaction, and
// returns the messages it made pending, for the bridge (an offline row waits for its network: ClaimWaiting):
//
//   - a held message more than MaxLate late becomes failed with ReasonNotSent, and its row goes; otherwise it goes from
//     queued to pending;
//   - a scheduled message set "if no reply" is canceled when someone else has written in its chat since it was set;
//     one more than MaxLate late waits as missed; otherwise its row goes and it is inserted as my pending message,
//     sent now.
//
// Content always loses sourceKey. Canceled, missed and sent scheduled messages publish "scheduled" for their chat.
func (s *Store) ClaimDue(ctx context.Context) ([]Event, error) {
	now := s.now()
	nowMS := now.UnixMilli()
	late := MaxLate.Milliseconds()
	var c claimed
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		c = claimed{}
		rows, err := s.outboxRows(ctx, "SELECT "+outboxRowCols+" FROM outbox WHERE state='"+stateWaiting+"' AND due_at <= $1 AND kind <> '"+
			outboxOffline+"' ORDER BY due_at, outbox_id", nowMS)
		if err != nil {
			return err
		}
		for _, r := range rows {
			tooLate := nowMS-r.due > late
			switch {
			case r.kind == outboxUndo && tooLate:
				err = s.releaseHeld(ctx, &c, r, "failed", ReasonNotSent)
			case r.kind == outboxUndo:
				err = s.releaseHeld(ctx, &c, r, "pending", "")
			default:
				err = s.claimLater(ctx, &c, r, now, tooLate)
			}
			if err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	c.publish(s)
	return c.out, nil
}

// claimLater is ClaimDue's step for a due scheduled message r.
func (s *Store) claimLater(ctx context.Context, c *claimed, r outboxRow, now time.Time, tooLate bool) error {
	if r.condition == condIfNoReply {
		var replied bool
		if err := s.db.QueryRow(ctx, replyCancelsSQL, r.roomID, myID, r.set).Scan(&replied); err != nil {
			return err
		}
		if replied {
			return s.setOutboxState(ctx, c, r, stateCanceled)
		}
	}
	if tooLate {
		return s.setOutboxState(ctx, c, r, stateMissed)
	}
	return s.sendScheduled(ctx, c, r, now)
}

func (s *Store) setOutboxState(ctx context.Context, c *claimed, r outboxRow, state string) error {
	_, err := s.db.Exec(ctx, "UPDATE outbox SET state=$2 WHERE outbox_id=$1", r.id, state)
	c.scheduled = append(c.scheduled, r.roomID)
	return err
}

// ClaimHeld claims every held message of roomID ("" is every chat) now, before its window ends (send it now), in one
// transaction: each goes from queued to pending, its content less sourceKey, oldest first.
func (s *Store) ClaimHeld(ctx context.Context, roomID string) ([]Event, error) {
	q := "SELECT " + outboxRowCols + " FROM outbox WHERE kind='" + outboxUndo + "'"
	args := []any{}
	if roomID != "" {
		q += " AND room_id=$1"
		args = append(args, roomID)
	}
	var c claimed
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		c = claimed{}
		rows, err := s.outboxRows(ctx, q+" ORDER BY due_at, outbox_id", args...)
		if err != nil {
			return err
		}
		for _, r := range rows {
			if err = s.releaseHeld(ctx, &c, r, "pending", ""); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	c.publish(s)
	return c.out, nil
}

// ClaimScheduled sends scheduled message id now (Send Now), whatever its state: its row goes and it is inserted as my
// pending message, sent now, in one transaction. An unknown ID (or one already sent) is ErrNotFound.
func (s *Store) ClaimScheduled(ctx context.Context, id int64) (Event, error) {
	var c claimed
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		c = claimed{}
		rows, err := s.outboxRows(ctx, "SELECT "+outboxRowCols+" FROM outbox WHERE outbox_id=$1 AND kind='"+outboxLater+"'", id)
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return ErrNotFound
		}
		return s.sendScheduled(ctx, &c, rows[0], s.now())
	})
	if err != nil {
		return Event{}, err
	}
	c.publish(s)
	if len(c.out) == 0 {
		return Event{}, ErrNotFound
	}
	return c.out[0], nil
}

// claimWaitingSQL is the offline rows of the chats of network $1 whose login is one of $2 (a JSON array of login IDs)
// or is shared (""), less the chats $3 names (a JSON array of room IDs), oldest message first: by the message's own
// (ts, seq), which a WaitAgain doesn't change, so a message put back keeps its place (Ruling C3). A row whose message
// has gone sorts first and is just deleted.
var claimWaitingSQL = `SELECT o.outbox_id, o.room_id, o.kind, o.event_id, o.type, o.content, o.due_at, o.set_at, o.condition
FROM outbox o
JOIN rooms r ON r.room_id = o.room_id
LEFT JOIN events e ON e.event_id = o.event_id
WHERE o.kind = '` + outboxOffline + `' AND r.network = $1
  AND (r.login_id = '' OR r.login_id IN (SELECT value FROM json_each($2)))
  AND o.room_id NOT IN (SELECT value FROM json_each($3))
ORDER BY COALESCE(e.ts, 0), COALESCE(e.seq, 0), o.outbox_id`

// ClaimWaiting hands over the messages waiting for network, now that loginIDs (the network's logins that are logged
// in) can send: those of the network's chats that belong to one of them or are shared by every login (login ""),
// oldest first, each going from waiting to pending with its content less sourceKey and its row deleted, in one
// transaction. With no login given nothing goes: a shared chat needs a login too. Another login's chats and other
// networks' keep waiting (Review Focus 1, 5), and so do the chats except names: shared chats none of whose own logins
// is in (a group only a logged-out account is in: Ruling 12), so a pass never claims them only to put them back.
func (s *Store) ClaimWaiting(ctx context.Context, network string, loginIDs []string, except ...string) ([]Event, error) {
	if len(loginIDs) == 0 {
		return nil, nil
	}
	list, err := json.Marshal(loginIDs)
	if err != nil {
		return nil, err
	}
	skip, err := json.Marshal(append([]string{}, except...))
	if err != nil {
		return nil, err
	}
	var c claimed
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		c = claimed{}
		rows, err := s.outboxRows(ctx, claimWaitingSQL, network, string(list), string(skip))
		if err != nil {
			return err
		}
		for _, r := range rows {
			if err = s.releaseHeld(ctx, &c, r, "pending", ""); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	c.publish(s)
	return c.out, nil
}

// WaitAgain puts a message of mine that a hand-off found its network down for back to waiting: pending becomes
// waiting, with a new offline row, in one transaction. It is the way back for a message ClaimWaiting gave out, also
// when a quit cut its hand-off short (Ruling C2: Requeue is for held and scheduled messages only), so it never comes
// back as queued, late or "may have been sent". It keeps its place among the chat's waiting messages (claims go by its
// (ts, seq)). Only a pending message of mine goes back: ok is false for any other (sent, failed, someone else's,
// gone, or deleted for me while its hand-off ran), and nothing changes. It publishes a "status" change.
func (s *Store) WaitAgain(ctx context.Context, eventID string) (ok bool, err error) {
	return s.putBack(ctx, eventID, "pending", StatusWaiting, outboxOffline, false)
}

// SharedWaiting lists network's shared chats (rooms.login_id "") that have a message of mine waiting: the ones whose
// login SendWaiting has to look up before a claim (ClaimWaiting's except).
func (s *Store) SharedWaiting(ctx context.Context, network string) ([]string, error) {
	rows, err := s.db.Query(ctx, `SELECT DISTINCT o.room_id FROM outbox o JOIN rooms r ON r.room_id = o.room_id
		WHERE o.kind = '`+outboxOffline+`' AND r.network = $1 AND r.login_id = '' ORDER BY o.room_id`, network)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// HasWaiting reports whether roomID has a message of mine waiting for its network (an offline row): a new send in the
// chat then waits behind it, so it never overtakes the messages typed before it (Ruling C33). A message a claim has
// taken is on its way, not waiting.
func (s *Store) HasWaiting(ctx context.Context, roomID string) (bool, error) {
	var ok bool
	err := s.db.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM outbox WHERE room_id=$1 AND kind='"+outboxOffline+"')", roomID).Scan(&ok)
	return ok, err
}

// WaitFailed is Retry for a failed message of mine whose network is down: failed becomes waiting, its reason cleared,
// with a new offline row, in one transaction, so it waits like a new message and goes in its own place (claims go by
// its (ts, seq)). Only a failed message of mine, not deleted, goes: ok is false for any other, and nothing changes. It
// publishes a "status" change.
func (s *Store) WaitFailed(ctx context.Context, eventID string) (ok bool, err error) {
	return s.putBack(ctx, eventID, "failed", StatusWaiting, outboxOffline, false)
}

// putBack is WaitAgain's, Requeue's and WaitFailed's body: my message eventID, in status from and not deleted, goes
// to status to with a new outbox row of kind, in one transaction. The row is due now, or at the message's own time
// (ts) when atTS.
func (s *Store) putBack(ctx context.Context, eventID, from, to, kind string, atTS bool) (ok bool, err error) {
	var c claimed
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		c = claimed{}
		e, err := scanEvent(s.db.QueryRow(ctx, "UPDATE events SET status=$3, status_reason='' WHERE event_id=$1 AND sender=$2 AND status=$4 AND redacted=0 RETURNING "+eventCols,
			eventID, myID, to, from))
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		now := s.now().UnixMilli()
		due := now
		if atTS {
			due = e.TS.UnixMilli()
		}
		if _, err = s.db.Exec(ctx, `INSERT INTO outbox (room_id, kind, event_id, due_at, set_at, condition, state)
			VALUES ($1, $2, $3, $4, $5, 'always', '`+stateWaiting+`')`, e.RoomID, kind, e.EventID, due, now); err != nil {
			return err
		}
		ok = true
		c.statuses = append(c.statuses, e)
		return nil
	})
	if err != nil {
		return false, err
	}
	c.publish(s)
	return ok, nil
}

// Requeue puts a claimed message of mine back in the outbox, for when its hand-off was cut short (Courier quitting)
// before anything reached the network: pending again becomes queued, with an outbox row due at its own time (ts: when
// it was held, or when its scheduled time claimed it), in one transaction. The next claim (ClaimDue, at this start or
// the next) then sends it once if it is under MaxLate late, or makes it failed ReasonNotSent if over. Only a pending
// message of mine goes back: ok is false for any other (sent, failed, gone, or deleted for me), and nothing changes.
// A message that ClaimWaiting gave out goes back with WaitAgain instead, from the hand-off that claimed it (Ruling
// C2), so it waits for its network with no cut-off rather than coming back held and failing as late.
func (s *Store) Requeue(ctx context.Context, eventID string) (ok bool, err error) {
	return s.putBack(ctx, eventID, "pending", "queued", outboxUndo, true)
}
