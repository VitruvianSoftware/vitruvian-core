// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

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
	e := Event{
		RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"body":"hi"}`), TS: time.Unix(10, 0),
	}
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
		_, err := s.InsertEvent(ctx, Event{
			RoomID: "!r:courier.local", EventID: fmt.Sprintf("$%d", i), Sender: "@x:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(int64(i), 0), Status: "pending",
		})
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
	changed, err := s.SetState(ctx, "!r:courier.local", "m.room.power_levels", "", json.RawMessage(`{"users_default":0}`))
	require.NoError(t, err)
	require.True(t, changed, "a new state event is a change")
	changed, err = s.SetState(ctx, "!r:courier.local", "m.room.power_levels", "", json.RawMessage(`{"users_default":0}`))
	require.NoError(t, err)
	require.False(t, changed, "the same content again is not")
	got, ok, err := s.GetState(ctx, "!r:courier.local", "m.room.power_levels", "")
	require.NoError(t, err)
	require.True(t, ok)
	require.JSONEq(t, `{"users_default":0}`, string(got))
	changed, err = s.SetState(ctx, "!r:courier.local", "m.room.power_levels", "", json.RawMessage(`{"users_default":50}`))
	require.NoError(t, err)
	require.True(t, changed, "new content is a change")
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
				_, err := s.InsertEvent(ctx, Event{
					RoomID: fmt.Sprintf("!r%d:courier.local", r), EventID: fmt.Sprintf("$%d-%d", r, i),
					Sender: "@x:courier.local", Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Now(),
				})
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

func TestEventsOrderBySentTimeNotArrival(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	// Arrival order is 300, 100, 200; sent order is 100, 200, 300.
	for _, sec := range []int64{300, 100, 200} {
		_, err := s.InsertEvent(ctx, Event{
			RoomID: "!r:courier.local", EventID: fmt.Sprintf("$%d", sec), Sender: "@x:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(sec, 0),
		})
		require.NoError(t, err)
	}
	evs, err := s.Events(ctx, "!r:courier.local", 3)
	require.NoError(t, err)
	require.Len(t, evs, 3)
	require.Equal(t, []string{"$300", "$200", "$100"}, []string{evs[0].EventID, evs[1].EventID, evs[2].EventID})
}

// nextChange waits up to one second for the next change on ch.
func nextChange(t *testing.T, ch <-chan Change) Change {
	t.Helper()
	select {
	case c := <-ch:
		return c
	case <-time.After(time.Second):
		t.Fatal("no change delivered")
	}
	return Change{}
}

func TestInsertEventPublishesEventChange(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	ch, cancel := s.Subscribe()
	defer cancel()
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(1, 0),
	})
	require.NoError(t, err)
	require.Equal(t, Change{Kind: "event", RoomID: "!r:courier.local", EventID: "$a", Seq: 1}, nextChange(t, ch))
}

func TestDuplicateInsertEventPublishesNothing(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	ch, cancel := s.Subscribe()
	defer cancel()
	e := Event{
		RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(1, 0),
	}
	_, err := s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.Equal(t, Change{Kind: "event", RoomID: "!r:courier.local", EventID: "$a", Seq: 1}, nextChange(t, ch))
	ins, err := s.InsertEvent(ctx, e)
	require.NoError(t, err)
	require.False(t, ins)
	select {
	case c := <-ch:
		t.Fatalf("duplicate insert published %+v", c)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestSetStatusPublishesStatusChange(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!r:courier.local", EventID: "$a", Sender: "@x:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(1, 0), Status: "pending",
	})
	require.NoError(t, err)
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetStatus(ctx, "$a", "sent", ""))
	require.Equal(t, Change{Kind: "status", RoomID: "!r:courier.local", EventID: "$a", Seq: 1}, nextChange(t, ch))
}

func TestUnreadSubscriberDoesNotBlockWriters(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r:courier.local", Network: "whatsapp"}))
	ch, cancel := s.Subscribe()
	defer cancel()
	_ = ch // never read: the 256-slot buffer fills and writes must still succeed
	done := make(chan error, 1)
	go func() {
		for i := 0; i < 300; i++ {
			if _, err := s.InsertEvent(ctx, Event{
				RoomID: "!r:courier.local", EventID: fmt.Sprintf("$%d", i),
				Sender: "@x:courier.local", Type: "m.room.message", Content: json.RawMessage(`{}`), TS: time.Unix(int64(i), 0),
			}); err != nil {
				done <- err
				return
			}
		}
		done <- nil
	}()
	select {
	case err := <-done:
		require.NoError(t, err)
	case <-time.After(2 * time.Second):
		t.Fatal("writers blocked by an unread subscriber")
	}
}

// A subscriber that falls behind loses changes, but it is told: the next change it can take comes after one
// "resync", however many were dropped, and a subscriber that kept up never sees one.
func TestDroppedChangesAreFollowedByOneResync(t *testing.T) {
	s, ctx := open(t), context.Background()
	slow, cancelSlow := s.Subscribe()
	defer cancelSlow()
	fast, cancelFast := s.Subscribe()
	defer cancelFast()
	fastGot := make(chan []Change, 1)
	go func() {
		var got []Change
		for c := range fast {
			got = append(got, c)
			if c.RoomID == "last" {
				break
			}
		}
		fastGot <- got
	}()

	const burst = SubscriberBuffer + 50 // more than the buffer holds, while slow reads nothing
	for i := 0; i < burst; i++ {
		require.NoError(t, s.SetBridgeState(ctx, fmt.Sprintf("n%d", i), json.RawMessage(`{}`)))
	}
	for i := 0; i < SubscriberBuffer; i++ { // what fitted is delivered, in order, with no resync among it
		c := nextChange(t, slow)
		require.Equal(t, Change{Kind: "bridge", RoomID: fmt.Sprintf("n%d", i)}, c)
	}
	select {
	case c := <-slow:
		t.Fatalf("the dropped changes must not be delivered, got %+v", c)
	default:
	}

	require.NoError(t, s.SetBridgeState(ctx, "after", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "resync"}, nextChange(t, slow), "the first delivery after a drop is a resync")
	require.Equal(t, Change{Kind: "bridge", RoomID: "after"}, nextChange(t, slow))

	require.NoError(t, s.SetBridgeState(ctx, "last", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "bridge", RoomID: "last"}, nextChange(t, slow), "one resync, not one per drop")

	got := <-fastGot
	require.Len(t, got, burst+2, "a subscriber that keeps up loses nothing")
	for _, c := range got {
		require.NotEqual(t, "resync", c.Kind, "a subscriber that keeps up is never told to resync")
	}
}

// A subscriber whose buffer has room for the change but not for the resync before it keeps dropping, so the
// resync is never lost behind a change it should have come before.
func TestResyncWaitsForRoomForBoth(t *testing.T) {
	s, ctx := open(t), context.Background()
	ch, cancel := s.Subscribe()
	defer cancel()
	for i := 0; i <= SubscriberBuffer; i++ { // one more than fits: dropped
		require.NoError(t, s.SetBridgeState(ctx, fmt.Sprintf("n%d", i), json.RawMessage(`{}`)))
	}
	<-ch // one slot free
	require.NoError(t, s.SetBridgeState(ctx, "one-slot", json.RawMessage(`{}`)))
	for i := 1; i < SubscriberBuffer; i++ {
		require.Equal(t, fmt.Sprintf("n%d", i), nextChange(t, ch).RoomID)
	}
	require.NoError(t, s.SetBridgeState(ctx, "room-for-both", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "resync"}, nextChange(t, ch))
	require.Equal(t, "room-for-both", nextChange(t, ch).RoomID)
}

// A feed that has caught up after a drop can ask, so it is told even if nothing ever changes again. It is told
// once: asking clears the mark, so no resync comes in band after it.
func TestFeedSaysItDroppedOnceItHasCaughtUp(t *testing.T) {
	s, ctx := open(t), context.Background()
	f := s.Feed()
	defer f.Close()
	require.False(t, f.TakeDropped(), "nothing dropped yet")
	for i := 0; i <= SubscriberBuffer; i++ { // one more than fits
		require.NoError(t, s.SetBridgeState(ctx, fmt.Sprintf("n%d", i), json.RawMessage(`{}`)))
	}
	require.False(t, f.TakeDropped(), "not while changes are still waiting to be read")
	for i := 0; i < SubscriberBuffer; i++ {
		require.Equal(t, fmt.Sprintf("n%d", i), nextChange(t, f.C).RoomID)
	}
	require.True(t, f.TakeDropped(), "caught up after a drop")
	require.False(t, f.TakeDropped(), "said once")

	require.NoError(t, s.SetBridgeState(ctx, "after", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "bridge", RoomID: "after"}, nextChange(t, f.C), "no second resync in band")
}

// When the resync went in band first, there is nothing left to take.
func TestInBandResyncClearsTheDrop(t *testing.T) {
	s, ctx := open(t), context.Background()
	f := s.Feed()
	defer f.Close()
	for i := 0; i <= SubscriberBuffer; i++ {
		require.NoError(t, s.SetBridgeState(ctx, fmt.Sprintf("n%d", i), json.RawMessage(`{}`)))
	}
	for i := 0; i < SubscriberBuffer; i++ {
		nextChange(t, f.C)
	}
	require.NoError(t, s.SetBridgeState(ctx, "after", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "resync"}, nextChange(t, f.C))
	require.Equal(t, "after", nextChange(t, f.C).RoomID)
	require.False(t, f.TakeDropped())
}

func TestProfileRoundTripAndPartialUpdate(t *testing.T) {
	s, ctx := open(t), context.Background()
	_, _, ok, err := s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.False(t, ok)

	name, avatar := "Gia đình 👨‍👩‍👧", "mxc://courier.local/abc"
	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", &name, nil))
	n, a, ok, err := s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, name, n)
	require.Equal(t, "", a)

	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", nil, &avatar))
	n, a, _, err = s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.Equal(t, name, n, "a nil name leaves the name unchanged")
	require.Equal(t, avatar, a)

	empty := ""
	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", &empty, nil))
	n, a, _, err = s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.Equal(t, "", n, "a pointer to an empty string clears the name")
	require.Equal(t, avatar, a)
}

func TestSetProfilePublishesProfileChange(t *testing.T) {
	s, ctx := open(t), context.Background()
	ch, cancel := s.Subscribe()
	defer cancel()
	name := "Mum"
	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", &name, nil))
	select {
	case c := <-ch:
		require.Equal(t, Change{Kind: "profile"}, c)
	case <-time.After(time.Second):
		t.Fatal("no profile change published")
	}
}

func TestDeleteMemberRemovesOnlyThatMember(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r", Network: "whatsapp"}))
	require.NoError(t, s.SetMember(ctx, "!r", "@a", json.RawMessage(`{}`)))
	require.NoError(t, s.SetMember(ctx, "!r", "@b", json.RawMessage(`{}`)))
	require.NoError(t, s.DeleteMember(ctx, "!r", "@a"))
	m, err := s.Members(ctx, "!r")
	require.NoError(t, err)
	require.NotContains(t, m, "@a")
	require.Contains(t, m, "@b")
	require.NoError(t, s.DeleteMember(ctx, "!r", "@nobody"), "deleting an absent member is not an error")
}
