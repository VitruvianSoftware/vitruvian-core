package store

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func open(t *testing.T) *Store {
	s, err := Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s
}

func TestRoomRoundTrip(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp", Name: "Mum", IsDirect: true}))
	r, ok, err := s.GetRoom(ctx, "!r:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Mum", r.Name)
	require.True(t, r.IsDirect)
}

func TestInsertEventIsIdempotent(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	e := Event{RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"body":"hi"}`), TS: time.Unix(10, 0)}
	ins, err := s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.True(t, ins)
	ins, err = s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.False(t, ins, "second delivery of the same event must not insert")
	evs, err := s.Events(ctx, "!r:courier.local", 10)
	require.NoError(t, err)
	require.Len(t, evs, 1)
}

func TestEventsNewestFirstAndStatus(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	for i := 1; i <= 3; i++ {
		_, err := s.InsertEvent(ctx, Event{RoomID: "!r:courier.local", EventID: fmt.Sprintf("$%d", i), Sender: "@x:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(int64(i), 0), Status: "pending"})
		require.NoError(t, err)
	}
	require.NoError(t, s.SetStatus(ctx, "$3", "failed", "network down"))
	evs, err := s.Events(ctx, "!r:courier.local", 2)
	require.NoError(t, err)
	require.Equal(t, []string{"$3", "$2"}, []string{evs[0].EventID, evs[1].EventID})
	require.Equal(t, "failed", evs[0].Status)
	require.Equal(t, "network down", evs[0].StatusReason)
}

func TestStateAndMembers(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	require.NoError(t, s.SetState(ctx, "!r:courier.local", "m.room.power_levels", "", json.RawMessage(`{"users_default":0}`)))
	got, ok, err := s.GetState(ctx, "!r:courier.local", "m.room.power_levels", "")
	require.NoError(t, err)
	require.True(t, ok)
	require.JSONEq(t, `{"users_default":0}`, string(got))
	require.NoError(t, s.SetMember(ctx, "!r:courier.local", "@a:courier.local", json.RawMessage(`{"membership":"join"}`)))
	m, err := s.Members(ctx, "!r:courier.local")
	require.NoError(t, err)
	require.Contains(t, m, "@a:courier.local")
}

func TestSubscribeReceivesChanges(t *testing.T) {
	s, ctx := open(t), context.Background()
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	select {
	case c := <-ch:
		require.Equal(t, Change{Kind: "room", RoomID: "!r:courier.local"}, c)
	case <-time.After(time.Second):
		t.Fatal("no change delivered")
	}
}

func TestConcurrentInsertsDoNotLock(t *testing.T) {
	s, ctx := open(t), context.Background()
	for r := 0; r < 8; r++ {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: fmt.Sprintf("!r%d:courier.local", r), Network: "whatsapp"}))
	}
	var wg sync.WaitGroup
	errs := make(chan error, 8*50)
	for r := 0; r < 8; r++ {
		wg.Add(1)
		go func(r int) {
			defer wg.Done()
			for i := 0; i < 50; i++ {
				_, err := s.InsertEvent(ctx, Event{RoomID: fmt.Sprintf("!r%d:courier.local", r), EventID: fmt.Sprintf("$%d-%d", r, i),
					Sender: "@x:courier.local", Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Now()})
				errs <- err
			}
		}(r)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		require.NoError(t, err)
	}
}
