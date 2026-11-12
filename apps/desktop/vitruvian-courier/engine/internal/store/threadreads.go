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

// Thread unread state. A reply that stays in its thread (isThreadReplySQL) isn't in the chat's main timeline, so
// reading the chat here doesn't read it: it is read in the thread pane. What is read of a thread is the later of two
// bounds:
//   - the thread's marker (thread_reads): the newest reply the pane showed (MarkThreadRead);
//   - the chat's floor (room_prefs.threads_read_*): every thread is read up to it. Marking the chat read from the
//     inbox (MarkThreadsRead) moves it to the chat's newest event, and so does a read from another device
//     (readThreadsFromAnotherDevice).
//
// A reply broadcast to the channel is a message of the main timeline too, and is read with the chat.
//
// The floor is also kept close to the chat's newest message (settleThreadFloor) whenever a read marker moves: up to
// that message, or to just before the oldest unread thread reply, whichever is earlier. That reads nothing, and keeps
// the range scan of unreadSQLFor short: it starts at the earlier of the chat's bound and the floor.

// threadFloorFor is room_prefs p's thread floor, (ts, seq), as two SQL expressions: (0, 0) when the chat has none.
func threadFloorFor(p string) (ts, seq string) {
	return `COALESCE(` + p + `.threads_read_ts, 0)`, `COALESCE(` + p + `.threads_read_seq, 0)`
}

// earlierOf is the earlier of two (ts, seq) positions given as SQL expressions.
func earlierOf(aTS, aSeq, bTS, bSeq string) (ts, seq string) {
	aFirst := `(` + aTS + `, ` + aSeq + `) <= (` + bTS + `, ` + bSeq + `)`
	return `CASE WHEN ` + aFirst + ` THEN ` + aTS + ` ELSE ` + bTS + ` END`, `CASE WHEN ` + aFirst + ` THEN ` + aSeq + ` ELSE ` + bSeq + ` END`
}

// threadUnreadSQLFor is the condition on a thread reply u for "not read in its thread": after the chat's floor (its
// room_prefs p) and after its thread's marker, when the thread has one.
func threadUnreadSQLFor(p string) string {
	floorTS, floorSeq := threadFloorFor(p)
	return `((u.ts, u.seq) > (` + floorTS + `, ` + floorSeq + `)
         AND NOT EXISTS (SELECT 1 FROM thread_reads thr WHERE thr.room_id = u.room_id
                         AND thr.root_id = ` + threadRootSQL("u.content") + ` AND (thr.ts, thr.seq) >= (u.ts, u.seq)))`
}

// unreadThreadReplyFor is the condition on an event u, with room_prefs p, for "an unread reply in a thread": a reply
// that stays in its thread, that unreadSQLFor would count but for its bound (me is the parameter holding my user ID),
// and that isn't read in its thread (threadUnreadSQLFor).
func unreadThreadReplyFor(me string) string {
	return `u.type IN (` + unreadTypes + `) AND u.sender <> ` + me + ` AND u.redacted = 0 AND u.status <> 'failed'
  AND (` + isThreadReplySQL("u.content") + `) IS 1
  AND (` + isTimerNoteSQL("u.content") + `) IS NOT 1 AND (` + isCallRecordSQL("u.content") + `) IS NOT 1
  AND ` + threadUnreadSQLFor("p")
}

// oldestUnreadThreadReplySQL is the oldest unread thread reply in chat $2 ($1 is my user ID), by (ts, seq).
var oldestUnreadThreadReplySQL = `SELECT u.ts, u.seq FROM events u LEFT JOIN room_prefs p ON p.room_id = u.room_id
WHERE u.room_id = $2 AND ` + unreadThreadReplyFor("$1") + `
ORDER BY u.ts, u.seq LIMIT 1`

// position is an event's place in its chat, (ts in ms, seq).
type position struct{ ts, seq int64 }

func (a position) before(b position) bool { return a.ts < b.ts || (a.ts == b.ts && a.seq < b.seq) }

// threadFloor is roomID's thread floor: (0, 0) when it has none.
func (s *Store) threadFloor(ctx context.Context, roomID string) (position, error) {
	var p position
	err := s.db.QueryRow(ctx, `SELECT threads_read_ts, threads_read_seq FROM room_prefs WHERE room_id=$1`, roomID).
		Scan(&p.ts, &p.seq)
	if errors.Is(err, sql.ErrNoRows) {
		return position{}, nil
	}
	return p, err
}

// setThreadFloor moves roomID's thread floor to at, and drops the thread markers it covers: they say nothing more.
func (s *Store) setThreadFloor(ctx context.Context, roomID string, at position) error {
	if _, err := s.db.Exec(ctx, `INSERT INTO room_prefs (room_id, threads_read_ts, threads_read_seq) VALUES ($1,$2,$3)
		ON CONFLICT(room_id) DO UPDATE SET threads_read_ts=excluded.threads_read_ts, threads_read_seq=excluded.threads_read_seq`,
		roomID, at.ts, at.seq); err != nil {
		return err
	}
	_, err := s.db.Exec(ctx, `DELETE FROM thread_reads WHERE room_id=$1 AND (ts, seq) <= ($2, $3)`, roomID, at.ts, at.seq)
	return err
}

// newestEvent is the position of roomID's newest event of any kind; ok is false for a chat with none.
func (s *Store) newestEvent(ctx context.Context, roomID string) (position, bool, error) {
	var p position
	err := s.db.QueryRow(ctx, `SELECT ts, seq FROM events WHERE room_id=$1 ORDER BY ts DESC, seq DESC LIMIT 1`, roomID).
		Scan(&p.ts, &p.seq)
	if errors.Is(err, sql.ErrNoRows) {
		return position{}, false, nil
	}
	return p, err == nil, err
}

// settleThreadFloor moves roomID's thread floor up to its newest event, or to just before its oldest unread thread
// reply when that is earlier, if that is later than where it is. It reads nothing: every reply under the new floor
// was already read in its thread. It runs inside the caller's transaction.
func (s *Store) settleThreadFloor(ctx context.Context, roomID string) error {
	to, ok, err := s.newestEvent(ctx, roomID)
	if err != nil || !ok {
		return err
	}
	var oldest position
	err = s.db.QueryRow(ctx, oldestUnreadThreadReplySQL, myID, roomID).Scan(&oldest.ts, &oldest.seq)
	switch {
	case err == nil:
		if justBefore := (position{oldest.ts, oldest.seq - 1}); justBefore.before(to) {
			to = justBefore
		}
	case !errors.Is(err, sql.ErrNoRows):
		return err
	}
	floor, err := s.threadFloor(ctx, roomID)
	if err != nil || !floor.before(to) {
		return err
	}
	return s.setThreadFloor(ctx, roomID, to)
}

// newestThreadReplySQL is the newest reply, deleted or not, in the thread of root $2 in chat $1.
var newestThreadReplySQL = `SELECT event_id, ts, seq FROM events
WHERE ` + threadRepliesWhereSQL + ` AND ` + threadRootSQL("content") + ` = $2
ORDER BY ts DESC, seq DESC LIMIT 1`

// MarkThreadRead records that the thread pane showed the newest reply of rootID's thread in roomID: every reply in
// it is read. The thread's marker only moves forward, and a thread with no reply has nothing to read. When it
// moves, the chat's unread count changes too, so it publishes a "read" change for the chat, as a read marker does.
func (s *Store) MarkThreadRead(ctx context.Context, roomID, rootID string) (bool, error) {
	moved := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var eventID string
		var newest position
		err := s.db.QueryRow(ctx, newestThreadReplySQL, roomID, rootID).Scan(&eventID, &newest.ts, &newest.seq)
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		var cur position
		err = s.db.QueryRow(ctx, `SELECT ts, seq FROM thread_reads WHERE room_id=$1 AND root_id=$2`, roomID, rootID).
			Scan(&cur.ts, &cur.seq)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		floor, err := s.threadFloor(ctx, roomID)
		if err != nil {
			return err
		}
		if !cur.before(newest) || !floor.before(newest) {
			return nil // read up to it already
		}
		if _, err = s.db.Exec(ctx, `INSERT INTO thread_reads (room_id, root_id, event_id, ts, seq) VALUES ($1,$2,$3,$4,$5)
			ON CONFLICT(room_id, root_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts, seq=excluded.seq`,
			roomID, rootID, eventID, newest.ts, newest.seq); err != nil {
			return err
		}
		moved = true
		return s.settleThreadFloor(ctx, roomID)
	})
	if err == nil && moved {
		s.publish(Change{Kind: "read", RoomID: roomID})
	}
	return moved && err == nil, err
}

// MarkThreadsRead reads every thread of roomID: its floor moves to the chat's newest event. Marking a chat read from
// the inbox, or marking every chat read, does this; opening the chat doesn't. It publishes a "read" change for the
// chat when the floor moved.
func (s *Store) MarkThreadsRead(ctx context.Context, roomID string) (bool, error) {
	moved := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		to, ok, err := s.newestEvent(ctx, roomID)
		if err != nil || !ok {
			return err
		}
		floor, err := s.threadFloor(ctx, roomID)
		if err != nil || !floor.before(to) {
			return err
		}
		moved = true
		return s.setThreadFloor(ctx, roomID, to)
	})
	if err == nil && moved {
		s.publish(Change{Kind: "read", RoomID: roomID})
	}
	return moved && err == nil, err
}

// readThreadsFromAnotherDevice raises roomID's thread floor to at, the place my read marker from another device
// (SetRead) moved to: what I read there, threads included, is read here. A network reports one marker per chat, so
// it can't say whether a thread was opened; the other device showed the chat up to there, and Vitruvian Courier takes it as
// read. One exception: a marker at the very message this device's own marker is at is most likely the network
// telling me back the receipt this device sent when the chat was opened (Actions.MarkRead), which reads no thread.
// It runs inside SetRead's transaction.
func (s *Store) readThreadsFromAnotherDevice(ctx context.Context, roomID, eventID string, at position) error {
	var local string
	err := s.db.QueryRow(ctx, `SELECT event_id FROM local_reads WHERE room_id=$1`, roomID).Scan(&local)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if local == eventID {
		return nil
	}
	floor, err := s.threadFloor(ctx, roomID)
	if err != nil || !floor.before(at) {
		return err
	}
	return s.setThreadFloor(ctx, roomID, at)
}

// isThreadReply is isThreadReplySQL in Go: content is a reply in a thread (m.relates_to.rel_type m.thread) that
// wasn't also sent to the channel (com.beeper.broadcast_outside_thread).
func isThreadReply(content json.RawMessage) bool {
	var c struct {
		RelatesTo struct {
			RelType string `json:"rel_type"`
		} `json:"m.relates_to"`
		Broadcast bool `json:"com.beeper.broadcast_outside_thread"`
	}
	return json.Unmarshal(content, &c) == nil && c.RelatesTo.RelType == "m.thread" && !c.Broadcast
}

// UnreadThread is a thread of a chat with replies not read in it: how many, whether one mentions me, and the oldest
// of them, where the thread pane opens.
type UnreadThread struct {
	RootID        string
	Unread        int
	MentionsMe    bool
	FirstUnreadID string
	FirstUnreadTS time.Time
}

// unreadThreadRepliesSQL lists the unread thread replies of chat $2 ($1 is my user ID), oldest first, each with its
// root and whether it mentions me.
var unreadThreadRepliesSQL = `SELECT ` + threadRootSQL("u.content") + `, u.event_id, u.ts, (` + mentionsSQL("u.content", "$1") + `) IS 1
FROM events u LEFT JOIN room_prefs p ON p.room_id = u.room_id
WHERE u.room_id = $2 AND ` + unreadThreadReplyFor("$1") + `
ORDER BY u.ts, u.seq`

// UnreadThreads lists roomID's threads that have unread replies, the one whose oldest unread reply is oldest first:
// what the open chat's "New replies in N threads" goes through.
func (s *Store) UnreadThreads(ctx context.Context, roomID string) ([]UnreadThread, error) {
	rows, err := s.db.Query(ctx, unreadThreadRepliesSQL, myID, roomID)
	if err != nil {
		return nil, err
	}
	out := []UnreadThread{}
	at := map[string]int{} // root → its place in out
	for rows.Next() {
		var root, eventID string
		var ts int64
		var mentions bool
		if err := rows.Scan(&root, &eventID, &ts, &mentions); err != nil {
			rows.Close()
			return nil, err
		}
		i, seen := at[root]
		if !seen {
			i = len(out)
			at[root] = i
			out = append(out, UnreadThread{RootID: root, FirstUnreadID: eventID, FirstUnreadTS: time.UnixMilli(ts)})
		}
		out[i].Unread++
		out[i].MentionsMe = out[i].MentionsMe || mentions
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	return out, nil
}
