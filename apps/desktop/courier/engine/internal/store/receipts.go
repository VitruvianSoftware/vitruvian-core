// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"cmp"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"slices"
	"time"
)

// Other people's read receipts and deliveries (inventory 01 §5). A receipt moves the person's marker in the chat
// (receipts, one row per person) forward to the message it names, by that message's (ts, seq), so a receipt for an
// older message never marks a newer one read. A delivery names one message of mine that someone's device has
// (deliveries; the bridges only report these in one-to-one chats). Both are kept only for messages the store has:
// one for any other message is dropped, so outside data can't make a message look read that isn't here. My own reads
// from another device are SetRead's, never a receipt: I am never a reader of my own messages (Review Focus 2).

// MaxReaders is the most readers ReceiptsFor lists for one message: the newest receipts.
const MaxReaders = 50

// Reader is someone who has read a message (or anything after it): who, and when their receipt says they read it
// (zero when it carries no time).
type Reader struct {
	UserID string
	TS     time.Time
}

// Receipts is how far a message of mine has got: who has read it, newest receipt first and at most MaxReaders, and
// whose devices have it.
type Receipts struct {
	ReadBy      []Reader
	DeliveredTo []string
}

// SetReceipt moves userID's read marker in roomID to eventID, received at ts (zero when the network gave no time), if
// that message is later by (ts, seq) than the one the marker is at; an older one changes nothing. A receipt for an
// event the store doesn't have in roomID is dropped (nil), and so is one in my name: my own reads are SetRead's. It
// publishes a "receipt" change for the chat when the marker moved.
func (s *Store) SetReceipt(ctx context.Context, roomID, userID, eventID string, ts time.Time) error {
	if userID == myID {
		return nil
	}
	moved := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var newTS, newSeq int64
		err := s.db.QueryRow(ctx, "SELECT ts, seq FROM events WHERE event_id=$1 AND room_id=$2", eventID, roomID).Scan(&newTS, &newSeq)
		if errors.Is(err, sql.ErrNoRows) {
			return nil // not a message we have
		}
		if err != nil {
			return err
		}
		// The marker's own message, by its (ts, seq); one that has gone since compares as (0, 0).
		var curTS, curSeq int64
		err = s.db.QueryRow(ctx, `SELECT COALESCE(e.ts, 0), COALESCE(e.seq, 0) FROM receipts rc
			LEFT JOIN events e ON e.event_id = rc.event_id WHERE rc.room_id=$1 AND rc.user_id=$2`, roomID, userID).Scan(&curTS, &curSeq)
		switch {
		case err == nil:
			if newTS < curTS || (newTS == curTS && newSeq <= curSeq) {
				return nil // not later than where the marker is
			}
		case !errors.Is(err, sql.ErrNoRows):
			return err
		}
		_, err = s.db.Exec(ctx, `INSERT INTO receipts (room_id, user_id, event_id, ts) VALUES ($1,$2,$3,$4)
			ON CONFLICT(room_id, user_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`,
			roomID, userID, eventID, s.clampTS(ts).UnixMilli())
		moved = err == nil
		return err
	})
	if err == nil && moved {
		s.publish(Change{Kind: "receipt", RoomID: roomID})
	}
	return err
}

// SetDelivered records that userID's device has eventID, a message of mine in roomID, at ts (the store's clock when
// zero: a delivery carries no time). Its arguments are in SetReceipt's order. A delivery of anything else (a message
// the store doesn't have in roomID, someone else's message) is dropped (nil), as is one in my name; the first
// delivery to a person is kept. It publishes a "receipt" change for the chat when it recorded one.
func (s *Store) SetDelivered(ctx context.Context, roomID, userID, eventID string, ts time.Time) error {
	if userID == myID {
		return nil
	}
	if ts.IsZero() {
		ts = s.now()
	}
	res, err := s.db.Exec(ctx, `INSERT INTO deliveries (event_id, user_id, ts)
		SELECT event_id, $3, $4 FROM events WHERE event_id=$1 AND room_id=$2 AND sender=$5
		ON CONFLICT(event_id, user_id) DO NOTHING`,
		eventID, roomID, userID, s.clampTS(ts).UnixMilli(), myID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		s.publish(Change{Kind: "receipt", RoomID: roomID})
	}
	return nil
}

// receiptsOfRoomSQL is every read marker of chat $1, each with its message's (ts, seq): a range of the receipts
// primary key (TestReceiptLookupUsesTheMarkerIndex). A marker whose message has gone since drops out.
const receiptsOfRoomSQL = `SELECT rc.user_id, rc.ts, e.ts, e.seq FROM receipts rc
JOIN events e ON e.event_id = rc.event_id
WHERE rc.room_id = $1`

// deliveriesOfSQL is the deliveries of the messages in $1 (a JSON array of event IDs), by the deliveries primary key.
const deliveriesOfSQL = `SELECT event_id, user_id, ts FROM deliveries WHERE event_id IN (SELECT value FROM json_each($1))`

// marker is one read marker of a chat, as ReceiptsFor reads it.
type marker struct {
	user        string
	at          int64 // the receipt's own time, Unix ms; 0 = none
	evTS, evSeq int64 // its message's
}

// ReceiptsFor reads how far each of mine, messages of mine in roomID that have gone, has got: who has read it or
// anything after it (by the message's (ts, seq)), newest receipt first and at most MaxReaders, and whose devices have
// it. It is two queries whatever the number of messages: the chat's markers, and these messages' deliveries. The
// answer is keyed by event ID and has an entry only for a message with a reader or a delivery; a message that isn't
// mine, or hasn't gone (pending, queued, waiting, failed), has none.
func (s *Store) ReceiptsFor(ctx context.Context, roomID string, mine []Event) (map[string]Receipts, error) {
	out := map[string]Receipts{}
	var ids []string
	gone := map[string]bool{}
	for _, e := range mine {
		if e.Sender == myID && e.RoomID == roomID && (e.Status == "sent" || e.Status == "") && !gone[e.EventID] {
			gone[e.EventID] = true
			ids = append(ids, e.EventID)
		}
	}
	if len(ids) == 0 {
		return out, nil
	}
	markers, err := s.markersOf(ctx, roomID)
	if err != nil {
		return nil, err
	}
	for _, e := range mine {
		if !gone[e.EventID] {
			continue
		}
		ts, seq := e.TS.UnixMilli(), e.Seq
		var readers []Reader
		for _, m := range markers {
			if m.evTS > ts || (m.evTS == ts && m.evSeq >= seq) {
				readers = append(readers, Reader{UserID: m.user, TS: msTime(m.at)})
				if len(readers) == MaxReaders {
					break
				}
			}
		}
		if len(readers) > 0 {
			out[e.EventID] = Receipts{ReadBy: readers}
		}
	}
	return out, s.addDeliveries(ctx, out, ids)
}

// markersOf is chat roomID's read markers (receiptsOfRoomSQL), newest receipt first (then by user ID, so the order
// is fixed). My own never count, should one be there.
func (s *Store) markersOf(ctx context.Context, roomID string) ([]marker, error) {
	rows, err := s.db.Query(ctx, receiptsOfRoomSQL, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []marker
	for rows.Next() {
		var m marker
		if err := rows.Scan(&m.user, &m.at, &m.evTS, &m.evSeq); err != nil {
			return nil, err
		}
		if m.user != myID {
			out = append(out, m)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	slices.SortFunc(out, func(a, b marker) int {
		if c := cmp.Compare(b.at, a.at); c != 0 {
			return c
		}
		return cmp.Compare(a.user, b.user)
	})
	return out, nil
}

// addDeliveries adds the deliveries of the messages in ids to out (deliveriesOfSQL), each message's in the order they
// arrived (then by user ID).
func (s *Store) addDeliveries(ctx context.Context, out map[string]Receipts, ids []string) error {
	list, _ := json.Marshal(ids)
	rows, err := s.db.Query(ctx, deliveriesOfSQL, string(list))
	if err != nil {
		return err
	}
	defer rows.Close()
	type delivery struct {
		event, user string
		ts          int64
	}
	var all []delivery
	for rows.Next() {
		var d delivery
		if err := rows.Scan(&d.event, &d.user, &d.ts); err != nil {
			return err
		}
		all = append(all, d)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	slices.SortFunc(all, func(a, b delivery) int {
		if c := cmp.Compare(a.ts, b.ts); c != 0 {
			return c
		}
		return cmp.Compare(a.user, b.user)
	})
	for _, d := range all {
		r := out[d.event]
		r.DeliveredTo = append(r.DeliveredTo, d.user)
		out[d.event] = r
	}
	return nil
}
