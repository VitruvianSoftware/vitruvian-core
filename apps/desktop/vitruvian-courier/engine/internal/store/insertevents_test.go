// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func historyEvent(room, id string, sec int64, body string) Event {
	return Event{
		RoomID: room, EventID: id, Sender: "@x:courier.local", Type: "m.room.message",
		Content: json.RawMessage(fmt.Sprintf(`{"msgtype":"m.text","body":%q}`, body)), TS: time.Unix(sec, 0), Status: "sent",
	}
}

// A batch is written whole or not at all: one event it can't store leaves none of the others behind.
func TestInsertEventsIsOneTransaction(t *testing.T) {
	s, ctx := open(t), context.Background()
	const room = "!r:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: room, Network: "whatsapp"}))
	_, err := s.InsertEvents(ctx, []Event{
		historyEvent(room, "$a", 10, "a"),
		historyEvent("!nowhere:courier.local", "$b", 20, "b"), // no such room: the foreign key refuses it
	})
	require.Error(t, err)
	evs, err := s.Events(ctx, room, 10)
	require.NoError(t, err)
	require.Empty(t, evs, "the first event of a failed batch must not be stored")
}

func TestInsertEventsSkipsWhatIsStoredAndPublishesWhatIsNew(t *testing.T) {
	s, ctx := open(t), context.Background()
	const room = "!r:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: room, Network: "whatsapp"}))
	batch := []Event{historyEvent(room, "$a", 10, "a"), historyEvent(room, "$b", 20, "b")}
	n, err := s.InsertEvents(ctx, batch)
	require.NoError(t, err)
	require.Equal(t, 2, n)
	n, err = s.InsertEvents(ctx, append(batch, historyEvent(room, "$c", 30, "c")))
	require.NoError(t, err)
	require.Equal(t, 1, n, "only the event that is new counts")
	evs, err := s.Events(ctx, room, 10)
	require.NoError(t, err)
	require.Len(t, evs, 3)
	empty, err := s.RoomHasNoMessages(ctx, room)
	require.NoError(t, err)
	require.False(t, empty)
	empty, err = s.RoomHasNoMessages(ctx, "!other:courier.local")
	require.NoError(t, err)
	require.True(t, empty)
}

func TestInsertEventsOneHundredEventsAcrossTwentyChats(t *testing.T) {
	s, ctx := open(t), context.Background()
	const (
		chats       = 20
		totalEvents = 100
	)
	for i := range chats {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: fmt.Sprintf("!r%d:courier.local", i), Network: "whatsapp"}))
	}
	batch := make([]Event, 0, totalEvents)
	for i := range totalEvents {
		room := fmt.Sprintf("!r%d:courier.local", i%chats)
		batch = append(batch, historyEvent(room, fmt.Sprintf("$e%d", i), int64(100+i), fmt.Sprintf("message %d", i)))
	}

	ch, cancel := s.Subscribe()
	defer cancel()

	start := time.Now()
	n, err := s.InsertEvents(ctx, batch)
	elapsed := time.Since(start)
	require.NoError(t, err)
	require.Equal(t, totalEvents, n)
	t.Logf("InsertEvents(%d events across %d chats) took %s", totalEvents, chats, elapsed)

	eventChanges := 0
	for len(ch) > 0 {
		c := <-ch
		if c.Kind == "event" {
			eventChanges++
		}
	}
	require.Equal(t, chats, eventChanges)
}

func TestInsertEventsBackfillBurstOverSubscriberBufferDoesNotForceResync(t *testing.T) {
	s, ctx := open(t), context.Background()
	const room = "!family:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: room, Network: "gmessages"}))

	const burst = SubscriberBuffer + 30 // 286 events, like the Family chat burst
	batch := make([]Event, 0, burst)
	for i := range burst {
		batch = append(batch, historyEvent(room, fmt.Sprintf("$b%d", i), int64(100+i), fmt.Sprintf("backfill %d", i)))
	}

	feed := s.Feed()
	defer feed.Close()

	n, err := s.InsertEvents(ctx, batch)
	require.NoError(t, err)
	require.Equal(t, burst, n)

	eventChanges := 0
	for len(feed.C) > 0 {
		c := <-feed.C
		require.NotEqual(t, ChangeResync, c.Kind, "backfill burst over SubscriberBuffer must not emit ChangeResync")
		if c.Kind == "event" && c.RoomID == room {
			eventChanges++
		}
	}
	require.GreaterOrEqual(t, eventChanges, 1)
	require.False(t, feed.TakeDropped(), "backfill burst over SubscriberBuffer must not overflow feed or force resync")
}

// What the one coalesced "event" change per room tells its readers: the room, the oldest event the batch inserted
// (the app asks whether it already holds it to learn that older rows arrived), and the room's latest seq. Rooms go out
// in the order the batch first names them, none is left out, and a room's "room" change follows its event change.
// The events themselves are all stored (unread, search and the previews read the store, not the feed).
func TestInsertEventsCoalescedChangeNamesOldestEventLatestSeqAndEveryRoom(t *testing.T) {
	s, ctx := open(t), context.Background()
	const a, b, c = "!a:courier.local", "!b:courier.local", "!c:courier.local"
	for _, r := range []string{a, b, c} {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: r, Network: "whatsapp"}))
	}
	// Not in time order, and rooms interleaved: b is named first, then a, then c.
	batch := []Event{
		historyEvent(b, "$b30", 30, "b30"),
		historyEvent(a, "$a50", 50, "a50"),
		historyEvent(b, "$b10", 10, "b10"), // the oldest of b
		historyEvent(a, "$a20", 20, "a20"), // the oldest of a
		historyEvent(c, "$c40", 40, "c40"),
		historyEvent(a, "$a20", 20, "a20 again"), // already in this batch: not a second insert
	}
	feed := s.Feed()
	defer feed.Close()

	n, err := s.InsertEvents(ctx, batch)
	require.NoError(t, err)
	require.Equal(t, 5, n)

	var got []Change
	for len(feed.C) > 0 {
		got = append(got, <-feed.C)
	}
	require.False(t, feed.TakeDropped())
	require.Len(t, got, 3, "one event change per room, nothing else: %+v", got)
	require.Equal(t, []string{b, a, c}, []string{got[0].RoomID, got[1].RoomID, got[2].RoomID}, "rooms in the order the batch names them")
	require.Equal(t, []string{"$b10", "$a20", "$c40"}, []string{got[0].EventID, got[1].EventID, got[2].EventID}, "each names its oldest inserted event")
	for _, ch := range got {
		require.Equal(t, "event", ch.Kind)
		evs, err := s.Events(ctx, ch.RoomID, 10)
		require.NoError(t, err)
		var maxSeq int64
		for _, e := range evs {
			maxSeq = max(maxSeq, e.Seq)
		}
		require.Equal(t, maxSeq, ch.Seq, "the change carries the room's latest seq: %s", ch.RoomID)
	}
	for room, want := range map[string]int{a: 2, b: 2, c: 1} {
		evs, err := s.Events(ctx, room, 10)
		require.NoError(t, err)
		require.Len(t, evs, want, "every event of the batch is stored: %s", room)
	}

	// The same batch again inserts nothing and says nothing.
	n, err = s.InsertEvents(ctx, batch)
	require.NoError(t, err)
	require.Zero(t, n)
	require.Empty(t, feed.C)
}
