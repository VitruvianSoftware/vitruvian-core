// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"errors"
	"slices"
)

// A chat's history read from a point inside it, so that a search result can open the chat at an old message.
// EventsAround and EventsAfter read the same events, in the same (ts, seq) order, as EventsBefore: a page around a
// message, the older pages EventsBefore gives from its before cursor and the newer pages EventsAfter gives from its
// after cursor cover the chat's history exactly once.

// eventAtSQL reads one event of one room: $1 the event ID, $2 the room. An event of another room is no row.
const eventAtSQL = `SELECT ` + eventCols + ` FROM events WHERE event_id = $1 AND room_id = $2`

// eventsAfterSQL pages oldest-first forward through events_room_ts (walking the index backwards, so no sort):
// $1 room, $2 and $3 the cursor's ts (ms) and seq, $4 the number of rows wanted.
const eventsAfterSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id = $1 AND (ts, seq) > ($2, $3)
ORDER BY ts ASC, seq ASC LIMIT $4`

// EventsAround is the page of roomID's history centred on eventID, newest first: up to limit/2 events older than
// it, the event itself, and the rest newer. before is the cursor for the next older page (nil at the oldest); after
// is the newest event of the page (nil when the page has the room's newest event). ErrNotFound when eventID isn't
// in roomID.
//
// Precisely: (limit-1)/2 older events when there are that many, so an even limit leans newer (10 is 4 older, the
// event, 5 newer). When fewer older events exist, the newer side takes the rest of the page; the older side never
// grows past its half, so a page at the newest message is short.
func (s *Store) EventsAround(ctx context.Context, roomID, eventID string, limit int) (evs []Event, before, after *Cursor, err error) {
	if limit <= 0 {
		limit = 50
	}
	centre, err := scanEvent(s.db.QueryRow(ctx, eventAtSQL, eventID, roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, nil, ErrNotFound
	} else if err != nil {
		return nil, nil, nil, err
	}
	at := centre.TS.UnixMilli()

	wantOlder := (limit - 1) / 2
	older, err := s.queryEvents(ctx, eventsBeforeSQL, roomID, at, centre.Seq, wantOlder+1) // newest first
	if err != nil {
		return nil, nil, nil, err
	}
	moreOlder := len(older) > wantOlder
	older = older[:min(len(older), wantOlder)]

	wantNewer := limit - 1 - len(older)
	newer, err := s.queryEvents(ctx, eventsAfterSQL, roomID, at, centre.Seq, wantNewer+1) // oldest first
	if err != nil {
		return nil, nil, nil, err
	}
	moreNewer := len(newer) > wantNewer
	newer = newer[:min(len(newer), wantNewer)]

	slices.Reverse(newer)
	evs = make([]Event, 0, len(newer)+1+len(older))
	evs = append(append(append(evs, newer...), centre), older...)
	if moreOlder {
		oldest := evs[len(evs)-1]
		before = &Cursor{TS: oldest.TS, Seq: oldest.Seq}
	}
	if moreNewer {
		after = &Cursor{TS: evs[0].TS, Seq: evs[0].Seq}
	}
	return evs, before, after, nil
}

// EventsAfter is the limit events just newer than after, newest first, with the cursor of the newest of them (nil
// when that is the room's newest event).
func (s *Store) EventsAfter(ctx context.Context, roomID string, after Cursor, limit int) ([]Event, *Cursor, error) {
	if limit <= 0 {
		limit = 50
	}
	evs, err := s.queryEvents(ctx, eventsAfterSQL, roomID, after.TS.UnixMilli(), after.Seq, limit+1) // one extra row says whether a newer page exists
	if err != nil {
		return nil, nil, err
	}
	more := len(evs) > limit
	evs = evs[:min(len(evs), limit)]
	slices.Reverse(evs)
	if !more {
		return evs, nil, nil
	}
	return evs, &Cursor{TS: evs[0].TS, Seq: evs[0].Seq}, nil
}

// queryEvents runs a query of eventCols and returns its rows as events, in the query's order.
func (s *Store) queryEvents(ctx context.Context, query string, args ...any) ([]Event, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
