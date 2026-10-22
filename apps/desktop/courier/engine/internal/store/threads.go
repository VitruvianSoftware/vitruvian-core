// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"slices"
	"strings"
	"time"
)

// Threads: a reply that stays in its thread (isThreadReplySQL) is read through events_threads, by its chat and its
// root, newest first; the main timeline leaves it out (mainTimelineSQL).

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
// replies of chat $1 that stay in a thread.
var threadRepliesWhereSQL = `room_id = $1 AND type IN ('m.room.message', 'm.sticker') AND ` + isThreadReplySQL("content")

// threadSummariesSQL lists, newest first in each thread, the replies of the threads whose roots are in the JSON array
// $2, in chat $1, that aren't deleted: a range scan of events_threads per root.
var threadSummariesSQL = `SELECT ` + threadRootSQL("content") + `, sender, ts FROM events
WHERE ` + threadRepliesWhereSQL + ` AND ` + threadRootSQL("content") + ` IN (SELECT value FROM json_each($2)) AND redacted = 0
ORDER BY ` + threadRootSQL("content") + `, ts DESC, seq DESC`

// ThreadSummaries summarises the threads of roomID whose roots are rootIDs, keyed by root; a root with no reply
// (deleted ones don't count) is left out.
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
