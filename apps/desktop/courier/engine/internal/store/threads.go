// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"cmp"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"slices"
	"strings"
	"time"
)

// Threads: every reply in a thread (inThreadSQL), also one broadcast to the channel, is read through events_threads,
// by its chat and its root, newest first. The main timeline leaves out only those that stay in the thread
// (mainTimelineSQL), so a broadcast reply shows in both and counts once in its thread.

// maxThreadSenders is how many of a thread's newest repliers its summary names.
const maxThreadSenders = 3

// ThreadSummary is what a thread's root shows: how many replies it has, when the newest came, and who wrote the
// newest ones, by name, newest first, at most 3 people.
type ThreadSummary struct {
	Replies     int
	LastTS      time.Time
	LastSenders []string
}

// threadRepliesWhereSQL is the condition, with events_threads' own WHERE repeated so the planner uses it, for the
// thread replies of chat $1.
var threadRepliesWhereSQL = `room_id = $1 AND type IN ('m.room.message', 'm.sticker') AND ` + inThreadSQL("content")

// threadSummariesSQL lists, newest first in each thread, the replies of the threads whose roots are in the JSON array
// $2, in chat $1, that aren't deleted and didn't fail to send: a range scan of events_threads per root.
var threadSummariesSQL = `SELECT ` + threadRootSQL("content") + `, sender, ts FROM events
WHERE ` + threadRepliesWhereSQL + ` AND ` + threadRootSQL("content") + ` IN (SELECT value FROM json_each($2))
  AND redacted = 0 AND status <> 'failed'
ORDER BY ` + threadRootSQL("content") + `, ts DESC, seq DESC`

// ThreadSummaries summarises the threads of roomID whose roots are rootIDs, keyed by root; a root with no reply
// (deleted and failed ones don't count) is left out.
func (s *Store) ThreadSummaries(ctx context.Context, roomID string, rootIDs []string) (map[string]ThreadSummary, error) {
	out := map[string]ThreadSummary{}
	roots := distinct(rootIDs)
	if len(roots) == 0 {
		return out, nil
	}
	b, _ := json.Marshal(roots)
	rows, err := s.db.Query(ctx, threadSummariesSQL, roomID, string(b))
	if err != nil {
		return nil, err
	}
	senders := map[string][]string{} // root → its newest distinct repliers, by user ID
	for rows.Next() {
		var root, sender string
		var ts int64
		if err := rows.Scan(&root, &sender, &ts); err != nil {
			rows.Close()
			return nil, err
		}
		sum, seen := out[root]
		if !seen {
			sum.LastTS = time.UnixMilli(ts)
		}
		sum.Replies++
		out[root] = sum
		if list := senders[root]; len(list) < maxThreadSenders && !slices.Contains(list, sender) {
			senders[root] = append(list, sender)
		}
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return nil, err
	}
	names := map[string]string{}
	for root, users := range senders {
		sum := out[root]
		for _, u := range users {
			name, ok := names[u]
			if !ok {
				if name, err = s.nameIn(ctx, roomID, u); err != nil {
					return nil, err
				}
				names[u] = name
			}
			sum.LastSenders = append(sum.LastSenders, name)
		}
		out[root] = sum
	}
	return out, nil
}

// nameIn is userID's name in roomID: their display name in the chat, else their profile's, else their ID's localpart.
func (s *Store) nameIn(ctx context.Context, roomID, userID string) (string, error) {
	var content, profile string
	err := s.db.QueryRow(ctx, `SELECT COALESCE((SELECT content FROM members WHERE room_id=$1 AND user_id=$2), ''),
		COALESCE((SELECT display_name FROM profiles WHERE user_id=$2), '')`, roomID, userID).Scan(&content, &profile)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	var m struct {
		DisplayName string `json:"displayname"`
	}
	_ = json.Unmarshal([]byte(content), &m) // not a member, or content that can't be read: no name from it
	switch {
	case m.DisplayName != "":
		return m.DisplayName, nil
	case profile != "":
		return profile, nil
	}
	local, _, _ := strings.Cut(strings.TrimPrefix(userID, "@"), ":")
	return local, nil
}

// threadEventsBeforeSQL pages newest first through one thread's replies on events_threads: $1 chat, $2 root, $3 and
// $4 the cursor's ts (ms) and seq, $5 the number of rows wanted.
var threadEventsBeforeSQL = `SELECT ` + eventCols + ` FROM events
WHERE ` + threadRepliesWhereSQL + ` AND ` + threadRootSQL("content") + ` = $2 AND (ts, seq) < ($3, $4)
ORDER BY ts DESC, seq DESC LIMIT $5`

// ThreadEventsBefore is EventsBefore for the thread of rootID in roomID: up to limit of its replies older than before,
// newest first (nil before is the newest page), and the cursor of the next, older page (nil when there is none). The
// root itself isn't a reply; GetEvent reads it.
func (s *Store) ThreadEventsBefore(ctx context.Context, roomID, rootID string, before *Cursor, limit int) ([]Event, *Cursor, error) {
	if limit <= 0 {
		limit = 50
	}
	ts, seq := int64(math.MaxInt64), int64(math.MaxInt64)
	if before != nil {
		ts, seq = before.TS.UnixMilli(), before.Seq
	}
	out, err := s.queryEvents(ctx, threadEventsBeforeSQL, roomID, rootID, ts, seq, limit+1) // one extra row says whether an older page exists
	if err != nil {
		return nil, nil, err
	}
	if len(out) <= limit {
		return out, nil, nil
	}
	out = out[:limit]
	last := out[limit-1]
	return out, &Cursor{TS: last.TS, Seq: last.Seq}, nil
}

// relationsOfSQL lists what the main timeline carries for the messages in the JSON array $1 that a page of their own
// (a thread's) needs to show them as the main timeline does: their edits (through events_edits), their reactions
// (events_reactions) and the redactions that delete them (events_redacts). An edit or a reaction that was itself
// deleted is left out, as if its redaction were there too. Each part's WHERE repeats its index's own, so the planner
// uses it; the chat is checked in Go, as CurrentText does.
var relationsOfSQL = `SELECT ` + eventCols + ` FROM events
WHERE type = 'm.room.message' AND ` + isEditSQL("content") + ` AND ` + editTargetSQL("content") + ` IN (SELECT value FROM json_each($1))
  AND redacted = 0
UNION ALL
SELECT ` + eventCols + ` FROM events
WHERE type = 'm.reaction' AND ` + editTargetSQL("content") + ` IN (SELECT value FROM json_each($1)) AND redacted = 0
UNION ALL
SELECT ` + eventCols + ` FROM events
WHERE type = 'm.room.redaction' AND ` + redactionTargetSQL("content") + ` IN (SELECT value FROM json_each($1))`

// RelationsOf is what roomID's main timeline carries about the messages targetIDs, which a thread page shows apart
// from it: their edits, their reactions and the redactions that delete them, newest first. A thread's replies stay
// out of the main timeline, but what points at them doesn't, so without these the thread pane would show a reply
// unedited, unreacted and undeleted.
func (s *Store) RelationsOf(ctx context.Context, roomID string, targetIDs []string) ([]Event, error) {
	targets := distinct(targetIDs)
	if len(targets) == 0 {
		return []Event{}, nil
	}
	b, _ := json.Marshal(targets)
	all, err := s.queryEvents(ctx, relationsOfSQL, string(b))
	if err != nil {
		return nil, err
	}
	out := make([]Event, 0, len(all))
	for _, e := range all {
		if e.RoomID == roomID {
			out = append(out, e)
		}
	}
	slices.SortFunc(out, func(a, b Event) int {
		if c := b.TS.Compare(a.TS); c != 0 {
			return c
		}
		return cmp.Compare(b.Seq, a.Seq)
	})
	return out, nil
}
