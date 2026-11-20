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
