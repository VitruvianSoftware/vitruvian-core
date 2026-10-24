// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const (
	ana = "@ana:courier.local"
	bob = "@bob:courier.local"
)

// mySent is my message id in roomID, sent at ts.
func mySent(t *testing.T, s *Store, roomID, id string, ts time.Time) Event {
	t.Helper()
	e := Event{RoomID: roomID, EventID: id, Sender: me, Type: "m.room.message", Content: []byte(text(id)), TS: ts, Status: "sent"}
	insert(t, s, e)
	got, _ := getEvent(t, s, id)
	return got
}

func receiptsFor(t *testing.T, s *Store, roomID string, mine ...Event) map[string]Receipts {
	t.Helper()
	got, err := s.ReceiptsFor(context.Background(), roomID, mine)
	require.NoError(t, err)
	return got
}

func readerIDs(r Receipts) []string {
	out := []string{}
	for _, rd := range r.ReadBy {
		out = append(out, rd.UserID)
	}
	return out
}

// Review Focus 2: a receipt marks the message it names and everything before it, never a newer one; one for an older
// message than the person's marker changes nothing; readers are listed newest receipt first.
func TestReceiptMarksOnlyUpToItsMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!g", time.Unix(1, 0))
	m1 := mySent(t, s, "!g", "$m1", t0)
	mkMsg(t, s, "!g", "$o1", ana, "m.room.message", text("hi"), t0.Add(time.Second))
	m2 := mySent(t, s, "!g", "$m2", t0.Add(2*time.Second))
	m3 := mySent(t, s, "!g", "$m3", t0.Add(3*time.Second))
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.SetReceipt(ctx, "!g", ana, "$m2", t0.Add(10*time.Second)))
	require.Equal(t, Change{Kind: "receipt", RoomID: "!g"}, nextChange(t, ch))
	got := receiptsFor(t, s, "!g", m1, m2, m3)
	require.Equal(t, []string{ana}, readerIDs(got["$m1"]))
	require.Equal(t, []string{ana}, readerIDs(got["$m2"]))
	require.Empty(t, readerIDs(got["$m3"]), "a receipt for the second message doesn't mark the third")
	require.Equal(t, t0.Add(10*time.Second).UnixMilli(), got["$m2"].ReadBy[0].TS.UnixMilli(), "the receipt's own time")

	// A later receipt for an older message: Ana's marker stays where it is.
	require.NoError(t, s.SetReceipt(ctx, "!g", ana, "$m1", t0.Add(20*time.Second)))
	requireNoChange(t, ch)
	again := receiptsFor(t, s, "!g", m1, m2, m3)
	require.Equal(t, got, again)

	require.NoError(t, s.SetReceipt(ctx, "!g", bob, "$m3", t0.Add(30*time.Second)))
	require.Equal(t, Change{Kind: "receipt", RoomID: "!g"}, nextChange(t, ch))
	got = receiptsFor(t, s, "!g", m1, m2, m3)
	require.Equal(t, []string{bob}, readerIDs(got["$m3"]))
	require.Equal(t, []string{bob, ana}, readerIDs(got["$m2"]), "newest receipt first")
	require.Equal(t, []string{bob, ana}, readerIDs(got["$m1"]))
}

// Review Focus 2: a receipt for a message the store doesn't have (or one in another chat) is dropped: no row, no
// error, nothing published.
func TestReceiptForUnknownMessageIsDropped(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!g", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	mySent(t, s, "!other", "$elsewhere", t0)
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.SetReceipt(ctx, "!g", ana, "$nope", t0))
	require.NoError(t, s.SetReceipt(ctx, "!g", ana, "$elsewhere", t0))
	require.NoError(t, s.SetReceipt(ctx, "!unknown", ana, "$elsewhere", t0))
	require.NoError(t, s.SetDelivered(ctx, "!g", ana, "$nope", t0))
	require.NoError(t, s.SetDelivered(ctx, "!g", ana, "$elsewhere", t0))
	requireNoChange(t, ch)
	require.Zero(t, count(t, s, "SELECT count(*) FROM receipts"))
	require.Zero(t, count(t, s, "SELECT count(*) FROM deliveries"))
}

// My own reads, from another device, move my marker (SetRead) and never make me a reader of my own messages; a
// receipt in my name is never kept as someone's.
func TestMyOwnReceiptIsNotAReader(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!g", time.Unix(1, 0))
	mkMsg(t, s, "!g", "$o1", ana, "m.room.message", text("hi"), t0)
	m1 := mySent(t, s, "!g", "$m1", t0.Add(time.Second))
	require.Equal(t, 1, inboxByID(t, s)["!g"].Unread)

	require.NoError(t, s.SetRead(ctx, "!g", "$m1", t0.Add(5*time.Second)))
	require.Zero(t, inboxByID(t, s)["!g"].Unread, "my marker moved")
	require.NoError(t, s.SetReceipt(ctx, "!g", me, "$m1", t0.Add(5*time.Second)))
	require.Zero(t, count(t, s, "SELECT count(*) FROM receipts"))
	require.Empty(t, readerIDs(receiptsFor(t, s, "!g", m1)["$m1"]))
	require.Equal(t, "sent", inboxByID(t, s)["!g"].PreviewStatus, "not seen: only I read it")
}

// A delivery names one message, not the ones before it.
func TestDeliveryIsPerMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0.Add(time.Minute))
	mkRoom(t, s, "!dm", time.Unix(1, 0))
	m1 := mySent(t, s, "!dm", "$m1", t0)
	m2 := mySent(t, s, "!dm", "$m2", t0.Add(time.Second))
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.SetDelivered(ctx, "!dm", ana, "$m2", time.Time{}))
	require.Equal(t, Change{Kind: "receipt", RoomID: "!dm"}, nextChange(t, ch))
	got := receiptsFor(t, s, "!dm", m1, m2)
	require.Equal(t, []string{ana}, got["$m2"].DeliveredTo)
	require.Empty(t, got["$m1"].DeliveredTo)
	require.Equal(t, t0.Add(time.Minute).UnixMilli(), int64(count(t, s, "SELECT ts FROM deliveries WHERE event_id='$m2'")),
		"a delivery without a time is kept at the store's clock")

	require.NoError(t, s.SetDelivered(ctx, "!dm", ana, "$m2", t0.Add(time.Hour)))
	requireNoChange(t, ch)
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM deliveries"))
}

// A message read by many people lists the newest MaxReaders of them.
func TestReadersAreCappedAtFifty(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!big", time.Unix(1, 0))
	m1 := mySent(t, s, "!big", "$m1", t0)
	for i := 0; i < 60; i++ {
		user := fmt.Sprintf("@u%02d:courier.local", i)
		require.NoError(t, s.SetReceipt(ctx, "!big", user, "$m1", t0.Add(time.Duration(i+1)*time.Second)))
	}
	readers := receiptsFor(t, s, "!big", m1)["$m1"].ReadBy
	require.Len(t, readers, MaxReaders)
	require.Equal(t, "@u59:courier.local", readers[0].UserID)
	require.Equal(t, "@u10:courier.local", readers[MaxReaders-1].UserID)
}

// The two receipt lookups are index lookups: a chat's markers by the primary key's room prefix, and the deliveries
// of a page's messages by theirs.
func TestReceiptLookupUsesTheMarkerIndex(t *testing.T) {
	s := open(t)
	plan := planOf(t, s, receiptsOfRoomSQL, "!g")
	requireIndexed(t, plan)
	require.Contains(t, strings.Join(plan, "\n"), "sqlite_autoindex_receipts_1", "a chat's markers by the primary key")
	plan = planOf(t, s, deliveriesOfSQL, `["$a","$b"]`)
	requireIndexed(t, plan)
	require.Contains(t, strings.Join(plan, "\n"), "sqlite_autoindex_deliveries_1")
}

// A note of mine (a timer change, a call) is not a message anyone reads: it gets no ticks in the row and no readers,
// even with a receipt at it.
func TestNotesGetNoTicks(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0.Add(time.Hour))
	mkRoom(t, s, "!dm", time.Unix(1, 0))
	mySent(t, s, "!dm", "$m", t0)
	require.True(t, insertTimerNote(t, s, "!dm", "$timer", "after_send", time.Hour, t0.Add(time.Second), s.LastSeq()))
	call := `{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call","call_type":"voice"},"fi.courier.call":{"state":"ended","media":"voice"}}`
	insert(t, s, Event{
		RoomID: "!dm", EventID: "$call", Sender: me, Type: "m.room.message", Content: []byte(call),
		TS: t0.Add(2 * time.Second), Status: "sent",
	})
	for _, id := range []string{"$timer", "$call"} {
		require.NoError(t, s.SetReceipt(ctx, "!dm", ana, id, t0.Add(time.Minute)))
		require.NoError(t, s.SetDelivered(ctx, "!dm", ana, id, t0.Add(time.Minute)))
	}
	require.Equal(t, "", inboxByID(t, s)["!dm"].PreviewStatus, "the newest is a note")
	timer, _ := getEvent(t, s, "$timer")
	callNote, _ := getEvent(t, s, "$call")
	m, _ := getEvent(t, s, "$m")
	got := receiptsFor(t, s, "!dm", timer, callNote, m)
	require.NotContains(t, got, "$timer")
	require.NotContains(t, got, "$call")
	require.Equal(t, []string{ana}, readerIDs(got["$m"]), "a message before the note is read")
}
