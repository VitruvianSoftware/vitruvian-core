// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
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
		require.NoError(t, s.SetLoginState(ctx, fmt.Sprintf("n%d", i), "", json.RawMessage(`{}`)))
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

	require.NoError(t, s.SetLoginState(ctx, "after", "", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "resync"}, nextChange(t, slow), "the first delivery after a drop is a resync")
	require.Equal(t, Change{Kind: "bridge", RoomID: "after"}, nextChange(t, slow))

	require.NoError(t, s.SetLoginState(ctx, "last", "", json.RawMessage(`{}`)))
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
		require.NoError(t, s.SetLoginState(ctx, fmt.Sprintf("n%d", i), "", json.RawMessage(`{}`)))
	}
	<-ch // one slot free
	require.NoError(t, s.SetLoginState(ctx, "one-slot", "", json.RawMessage(`{}`)))
	for i := 1; i < SubscriberBuffer; i++ {
		require.Equal(t, fmt.Sprintf("n%d", i), nextChange(t, ch).RoomID)
	}
	require.NoError(t, s.SetLoginState(ctx, "room-for-both", "", json.RawMessage(`{}`)))
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
		require.NoError(t, s.SetLoginState(ctx, fmt.Sprintf("n%d", i), "", json.RawMessage(`{}`)))
	}
	require.False(t, f.TakeDropped(), "not while changes are still waiting to be read")
	for i := 0; i < SubscriberBuffer; i++ {
		require.Equal(t, fmt.Sprintf("n%d", i), nextChange(t, f.C).RoomID)
	}
	require.True(t, f.TakeDropped(), "caught up after a drop")
	require.False(t, f.TakeDropped(), "said once")

	require.NoError(t, s.SetLoginState(ctx, "after", "", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "bridge", RoomID: "after"}, nextChange(t, f.C), "no second resync in band")
}

// When the resync went in band first, there is nothing left to take.
func TestInBandResyncClearsTheDrop(t *testing.T) {
	s, ctx := open(t), context.Background()
	f := s.Feed()
	defer f.Close()
	for i := 0; i <= SubscriberBuffer; i++ {
		require.NoError(t, s.SetLoginState(ctx, fmt.Sprintf("n%d", i), "", json.RawMessage(`{}`)))
	}
	for i := 0; i < SubscriberBuffer; i++ {
		nextChange(t, f.C)
	}
	require.NoError(t, s.SetLoginState(ctx, "after", "", json.RawMessage(`{}`)))
	require.Equal(t, Change{Kind: "resync"}, nextChange(t, f.C))
	require.Equal(t, "after", nextChange(t, f.C).RoomID)
	require.False(t, f.TakeDropped())
}

func TestProfileRoundTripAndPartialUpdate(t *testing.T) {
	s, ctx := open(t), context.Background()
	_, ok, err := s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.False(t, ok)

	name, avatar := "Gia đình 👨‍👩‍👧", "mxc://courier.local/abc"
	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", &name, nil))
	p, ok, err := s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, name, p.DisplayName)
	require.Equal(t, "", p.AvatarURI)

	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", nil, &avatar))
	p, _, err = s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.Equal(t, name, p.DisplayName, "a nil name leaves the name unchanged")
	require.Equal(t, avatar, p.AvatarURI)

	empty := ""
	require.NoError(t, s.SetProfile(ctx, "@g:courier.local", &empty, nil))
	p, _, err = s.GetProfile(ctx, "@g:courier.local")
	require.NoError(t, err)
	require.Equal(t, "", p.DisplayName, "a pointer to an empty string clears the name")
	require.Equal(t, avatar, p.AvatarURI)
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

func loginStates(t *testing.T, s *Store, network string) map[string]string {
	t.Helper()
	list, err := s.LoginStates(context.Background(), network)
	require.NoError(t, err)
	out := map[string]string{}
	for _, l := range list {
		out[l.LoginID] = string(l.State)
	}
	return out
}

func TestMigrationFromMilestone4_3(t *testing.T) {
	s, path := openFixture(t, "m7.sql")
	ctx := context.Background()
	require.GreaterOrEqual(t, userVersion(t, s), 7)
	require.Equal(t, len(migrations), userVersion(t, s))

	// Each network's one state lands under its login: WhatsApp's carried the login's remote_id, Slack's is the
	// bridge's own. bridge_state is left empty (schema.sql would bring it back if it were dropped).
	require.Equal(t, map[string]string{
		"login-a": `{"state_event":"CONNECTED","timestamp":1790812900,"ttl":3600,"remote_id":"login-a","remote_name":"Test Account"}`,
	}, loginStates(t, s, "whatsapp"))
	require.Equal(t, map[string]string{"": `{"state_event":"UNCONFIGURED","timestamp":1790812900,"ttl":3600}`}, loginStates(t, s, "slack"))
	require.Zero(t, count(t, s, "SELECT count(*) FROM bridge_state"))
	for _, table := range []string{"receipts", "deliveries"} {
		require.Zero(t, count(t, s, "SELECT count(*) FROM "+table), table)
	}

	// The inbox reads as before: no chat knows its login yet, the marks and markers hold, and the ticks start.
	rows := inboxByID(t, s)
	require.Len(t, rows, 4)
	for id, r := range rows {
		require.Empty(t, r.LoginID, id)
	}
	require.True(t, rows["!pat:courier.local"].MarkedUnread)
	require.Equal(t, "sent", rows["!pat:courier.local"].PreviewStatus)
	require.Equal(t, "", rows["!kim:courier.local"].PreviewStatus, "held: not gone yet")
	require.True(t, rows["!family:courier.local"].MarkedUnread)
	require.Equal(t, 2, rows["!family:courier.local"].Unread, "after the phone's marker: $f3 and $f5, not the reaction")
	require.Equal(t, 4, rows["!team:courier.local"].Unread)

	backfillAll(t, s, 2000)
	require.Equal(t, []string{"$k1"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("parcel")})))
	scheduled, err := s.ScheduledIn(ctx, "")
	require.NoError(t, err)
	require.Len(t, scheduled, 1)
	require.Equal(t, "$later1", scheduled[0].EventID)

	// The held message is still held: nothing before its window ends, then it goes once.
	require.NoError(t, s.Close())
	s = reopen(t, path, time.UnixMilli(1790812816000))
	require.Empty(t, claimDue(t, s))
	require.Equal(t, "queued", statusOf(t, s, "$k3"))
	s.SetClock(func() time.Time { return time.UnixMilli(1790812817000) })
	require.Equal(t, []string{"$k3"}, claimDue(t, s))
}

// Once a network runs, the states of accounts its bridge no longer has are dropped; the bridge's own, the accounts it
// has and other networks' stay.
func TestPruneLoginStatesKeepsTheBridgesAccounts(t *testing.T) {
	s, ctx := open(t), context.Background()
	for _, id := range []string{"", "A", "gone"} {
		require.NoError(t, s.SetLoginState(ctx, "whatsapp", id, []byte(`{"state_event":"LOGGED_OUT"}`)))
	}
	require.NoError(t, s.SetLoginState(ctx, "signal", "gone", []byte(`{"state_event":"CONNECTED"}`)))
	ch, cancel := s.Subscribe()
	defer cancel()
	n, err := s.PruneLoginStates(ctx, "whatsapp", []string{"A"})
	require.NoError(t, err)
	require.Equal(t, 1, n)
	require.Equal(t, Change{Kind: "bridge", RoomID: "whatsapp"}, nextChange(t, ch))
	require.Equal(t, map[string]string{"": `{"state_event":"LOGGED_OUT"}`, "A": `{"state_event":"LOGGED_OUT"}`}, loginStates(t, s, "whatsapp"))
	require.Equal(t, map[string]string{"gone": `{"state_event":"CONNECTED"}`}, loginStates(t, s, "signal"), "another network's")
	n, err = s.PruneLoginStates(ctx, "whatsapp", nil)
	require.NoError(t, err)
	require.Equal(t, 1, n, "no accounts: only the bridge's own stays")
	require.Equal(t, map[string]string{"": `{"state_event":"LOGGED_OUT"}`}, loginStates(t, s, "whatsapp"))
}

// Review Focus 5: each login of a network keeps its own state, and the bridge's own ("") sorts first. Writing one
// leaves the others, and every write tells the feed the network changed.
func TestLoginStatesAreKeptPerLogin(t *testing.T) {
	s, ctx := open(t), context.Background()
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "B", []byte(`{"state_event":"BAD_CREDENTIALS"}`)))
	require.Equal(t, Change{Kind: "bridge", RoomID: "whatsapp"}, nextChange(t, ch))
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "A", []byte(`{"state_event":"CONNECTING"}`)))
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "", []byte(`{"state_event":"UNCONFIGURED"}`)))
	require.NoError(t, s.SetLoginState(ctx, "signal", "A", []byte(`{"state_event":"CONNECTED"}`)))
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "A", []byte(`{"state_event":"CONNECTED"}`)))
	list, err := s.LoginStates(ctx, "whatsapp")
	require.NoError(t, err)
	require.Equal(t, []LoginState{
		{LoginID: "", State: []byte(`{"state_event":"UNCONFIGURED"}`)},
		{LoginID: "A", State: []byte(`{"state_event":"CONNECTED"}`)},
		{LoginID: "B", State: []byte(`{"state_event":"BAD_CREDENTIALS"}`)},
	}, list)
	require.Equal(t, map[string]string{"A": `{"state_event":"CONNECTED"}`}, loginStates(t, s, "signal"))
	none, err := s.LoginStates(ctx, "telegram")
	require.NoError(t, err)
	require.Empty(t, none)

	drain(ch)
	s.NetworkChanged("telegram")
	require.Equal(t, Change{Kind: "bridge", RoomID: "telegram"}, nextChange(t, ch))

	// Each login keeps its own row: a later state of one replaces only its own, and the bridge's own ("") is apart.
	require.NoError(t, s.SetLoginState(ctx, "slack", "T1", []byte(`{"state_event":"CONNECTED","remote_id":"T1"}`)))
	require.NoError(t, s.SetLoginState(ctx, "slack", "T2", []byte(`{"state_event":"CONNECTED","remote_id":"T2"}`)))
	require.NoError(t, s.SetLoginState(ctx, "slack", "", []byte(`{"state_event":"UNCONFIGURED"}`)))
	require.NoError(t, s.SetLoginState(ctx, "slack", "T1", []byte(`{"state_event":"LOGGED_OUT","remote_id":"T1"}`)))
	require.Equal(t, map[string]string{
		"T1": `{"state_event":"LOGGED_OUT","remote_id":"T1"}`, "T2": `{"state_event":"CONNECTED","remote_id":"T2"}`,
		"": `{"state_event":"UNCONFIGURED"}`,
	}, loginStates(t, s, "slack"))
}

// A2: the chats that have no login yet (kept before 4.4, or before a second account came) take theirs from the
// bridge's portals when the network starts. A chat that has a login keeps it, a chat with no portal (none in the
// map) stays "", another network's chat is left alone, and each chat filled publishes a "room" change once.
func TestFillRoomLoginsFillsOnlyTheEmptyOnes(t *testing.T) {
	s, ctx := open(t), context.Background()
	for _, r := range []Room{
		{ID: "!empty", Network: "telegram"},
		{ID: "!has", Network: "telegram"},
		{ID: "!noportal", Network: "telegram"},
		{ID: "!other", Network: "signal"},
	} {
		require.NoError(t, s.UpsertRoom(ctx, r))
	}
	require.NoError(t, s.SetRoomLogin(ctx, "!has", "A"))
	ch, cancel := s.Subscribe()
	defer cancel()

	logins := map[string]string{"!empty": "B", "!has": "B", "!other": "B", "!unknown": "B"}
	n, err := s.FillRoomLogins(ctx, "telegram", logins)
	require.NoError(t, err)
	require.Equal(t, 1, n)
	require.Equal(t, Change{Kind: "room", RoomID: "!empty"}, nextChange(t, ch))
	requireNoChange(t, ch)
	got := map[string]string{}
	rooms, err := s.ListRooms(ctx)
	require.NoError(t, err)
	for _, r := range rooms {
		got[r.ID] = r.LoginID
	}
	require.Equal(t, map[string]string{"!empty": "B", "!has": "A", "!noportal": "", "!other": ""}, got)

	// Again: nothing left to fill, nothing published.
	n, err = s.FillRoomLogins(ctx, "telegram", logins)
	require.NoError(t, err)
	require.Zero(t, n)
	requireNoChange(t, ch)
	n, err = s.FillRoomLogins(ctx, "telegram", nil)
	require.NoError(t, err)
	require.Zero(t, n)
}

// A chat remembers the login it belongs to; the bridge sending the chat again doesn't forget it, and setting it
// publishes nothing (it changes nothing a person sees by itself).
func TestRoomRemembersItsLogin(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetRoomLogin(ctx, "!r", "A"))
	requireNoChange(t, ch)
	require.ErrorIs(t, s.SetRoomLogin(ctx, "!unknown", "A"), ErrNotFound)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r", Network: "whatsapp", Name: "renamed"}))
	r, ok, err := s.GetRoom(ctx, "!r")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "A", r.LoginID)
	require.Equal(t, "A", inboxByID(t, s)["!r"].LoginID)
	rooms, err := s.ListRooms(ctx)
	require.NoError(t, err)
	require.Equal(t, "A", rooms[0].LoginID)
}

func TestMigrationFromMilestone4_4(t *testing.T) {
	s, _ := openFixture(t, "m8.sql")
	ctx := context.Background()
	require.GreaterOrEqual(t, SchemaVersion, 8)
	require.Equal(t, SchemaVersion, userVersion(t, s))
	require.Equal(t, len(migrations), userVersion(t, s))

	var identJSON, tz string
	var isBot int
	require.NoError(t, s.db.QueryRow(ctx, "SELECT identifiers_json, tz, is_bot FROM profiles WHERE user_id='@u1:courier.local'").
		Scan(&identJSON, &tz, &isBot))
	require.Equal(t, "[]", identJSON)
	require.Equal(t, "", tz)
	require.Equal(t, 0, isBot)

	var localName, localAvatar string
	var spamReportedAt int64
	require.NoError(t, s.db.QueryRow(ctx, "SELECT local_name, local_avatar_uri, spam_reported_at FROM room_prefs WHERE room_id='!r1:courier.local'").
		Scan(&localName, &localAvatar, &spamReportedAt))
	require.Equal(t, "", localName)
	require.Equal(t, "", localAvatar)
	require.Zero(t, spamReportedAt)

	prof, ok, err := s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice Example", prof.DisplayName)
	require.Equal(t, "mxc://courier.local/alice", prof.AvatarURI)
	require.Empty(t, prof.Identifiers)
	require.Empty(t, prof.Timezone)
	require.False(t, prof.IsBot)

	r, ok, err := s.GetRoom(ctx, "!r1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice Example", r.Name)
	require.Equal(t, "Alice Example", r.RemoteName)
	require.Equal(t, "", r.LocalName)
	require.Equal(t, "", r.LocalAvatarURI)
	require.Zero(t, r.SpamReportedAt)
	require.Equal(t, "", r.MergeID)

	for _, table := range []string{"receipts", "deliveries", "login_state"} {
		require.Equal(t, 1, count(t, s, "SELECT count(*) FROM "+table), table)
	}
	for _, table := range []string{"merged_chats", "merged_chat_rooms"} {
		require.Zero(t, count(t, s, "SELECT count(*) FROM "+table), table)
	}
}

func TestProfileExtraMetaAndLocalRoomOverrides(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID: "!r1:courier.local", Network: "whatsapp", Name: "Original Name",
		AvatarURI: "mxc://courier.local/orig", IsDirect: true,
	}))
	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@u1:courier.local", DisplayName: "Alice Example", AvatarURI: "mxc://courier.local/alice",
	}))
	require.NoError(t, s.SetProfileExtraMeta(ctx, "@u1:courier.local",
		[]string{"tel:+15550100101", "telegram:alice_test"}, "America/Los_Angeles", true))

	p, ok, err := s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, []string{"tel:+15550100101", "telegram:alice_test"}, p.Identifiers)
	require.Equal(t, "America/Los_Angeles", p.Timezone)
	require.True(t, p.IsBot)

	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@u1:courier.local", DisplayName: "Alice Renamed",
	}))
	p, ok, err = s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice Renamed", p.DisplayName)
	require.Equal(t, "mxc://courier.local/alice", p.AvatarURI)
	require.Equal(t, []string{"tel:+15550100101", "telegram:alice_test"}, p.Identifiers)
	require.Equal(t, "America/Los_Angeles", p.Timezone)
	require.True(t, p.IsBot)

	// SetProfileExtraMeta comes straight from the bridge and can flip is_bot back to false;
	// a plain UpsertProfile leaves is_bot alone (even if IsBot is set on the Profile struct).
	require.NoError(t, s.SetProfileExtraMeta(ctx, "@u1:courier.local",
		[]string{"tel:+15550100101", "telegram:alice_test"}, "America/Los_Angeles", false))
	p, ok, err = s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.False(t, p.IsBot)

	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@u1:courier.local", DisplayName: "Alice Again", IsBot: true,
	}))
	p, ok, err = s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice Again", p.DisplayName)
	require.False(t, p.IsBot, "plain UpsertProfile must leave is_bot alone")

	require.NoError(t, s.SetRoomLocalOverride(ctx, "!r1:courier.local", "Custom Name", "mxc://courier.local/custom"))
	require.NoError(t, s.MarkRoomSpamReported(ctx, "!r1:courier.local", 1700000000000))

	r, ok, err := s.GetRoom(ctx, "!r1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Original Name", r.Name)
	require.Equal(t, "Original Name", r.RemoteName)
	require.Equal(t, "Custom Name", r.LocalName)
	require.Equal(t, "mxc://courier.local/orig", r.AvatarURI)
	require.Equal(t, "mxc://courier.local/custom", r.LocalAvatarURI)
	require.Equal(t, int64(1700000000000), r.SpamReportedAt)

	row := inboxByID(t, s)["!r1:courier.local"]
	require.Equal(t, "Custom Name", row.Name)
	require.Equal(t, "Original Name", row.RemoteName)
	require.Equal(t, "Custom Name", row.LocalName)
	require.Equal(t, "mxc://courier.local/custom", row.AvatarURI)
	require.Equal(t, "mxc://courier.local/custom", row.LocalAvatarURI)
	require.Equal(t, int64(1700000000000), row.SpamReportedAt)

	require.NoError(t, s.SetRoomLocalOverride(ctx, "!r1:courier.local", "", ""))
	r, ok, err = s.GetRoom(ctx, "!r1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Original Name", r.Name)
	require.Equal(t, "Original Name", r.RemoteName)
	require.Equal(t, "", r.LocalName)
	require.Equal(t, "mxc://courier.local/orig", r.AvatarURI)
	require.Equal(t, "", r.LocalAvatarURI)
	row = inboxByID(t, s)["!r1:courier.local"]
	require.Equal(t, "Original Name", row.Name)
	require.Equal(t, "mxc://courier.local/orig", row.AvatarURI)
}

func TestMergedChatCRUDAndLastRoomTracking(t *testing.T) {
	s, ctx := open(t), context.Background()

	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID: "!wa:courier.local", Network: "whatsapp", Name: "Alice WA",
		AvatarURI: "mxc://courier.local/wa-alice", IsDirect: true,
	}))
	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID: "!sig:courier.local", Network: "signal", Name: "Alice Signal",
		AvatarURI: "mxc://courier.local/sig-alice", IsDirect: true,
	}))

	_, err := s.InsertEvent(ctx, Event{
		EventID: "$wa1", RoomID: "!wa:courier.local", Sender: "@whatsapp_alice:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"hi from wa"}`),
		TS: time.UnixMilli(100),
	})
	require.NoError(t, err)
	_, err = s.InsertEvent(ctx, Event{
		EventID: "$sig1", RoomID: "!sig:courier.local", Sender: "@signal_alice:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"hi from sig"}`),
		TS: time.UnixMilli(200),
	})
	require.NoError(t, err)

	mc, err := s.CreateMergedChat(ctx, "Alice Example", []string{"!wa:courier.local", "!sig:courier.local"})
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(mc.MergeID, "merge:"), "expected merge: prefix, got %q", mc.MergeID)
	require.Equal(t, "Alice Example", mc.Name)
	require.Equal(t, "!sig:courier.local", mc.LastRoomID)
	require.Equal(t, []string{"!wa:courier.local", "!sig:courier.local"}, mc.RoomIDs)
	require.Equal(t, []string{"whatsapp", "signal"}, mc.Networks)

	// Ruling 1: Room.Name remains the network's name; merged_chats holds the merged name.
	waRoom, ok, err := s.GetRoom(ctx, "!wa:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice WA", waRoom.Name)
	require.Equal(t, mc.MergeID, waRoom.MergeID)

	sigRoom, ok, err := s.GetRoom(ctx, "!sig:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Alice Signal", sigRoom.Name)
	require.Equal(t, mc.MergeID, sigRoom.MergeID)

	// Non-message events must not change last_room_id.
	_, err = s.InsertEvent(ctx, Event{
		EventID: "$wa-react", RoomID: "!wa:courier.local", Sender: "@whatsapp_alice:courier.local",
		Type: "m.reaction", Content: json.RawMessage(`{"m.relates_to":{"rel_type":"m.annotation","event_id":"$wa1","key":"👍"}}`),
		TS: time.UnixMilli(250),
	})
	require.NoError(t, err)
	list, err := s.ListMergedChats(ctx)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Equal(t, "!sig:courier.local", list[0].LastRoomID)

	// New message in !wa:courier.local at ts = 300 moves last_room_id to !wa:courier.local.
	_, err = s.InsertEvent(ctx, Event{
		EventID: "$wa2", RoomID: "!wa:courier.local", Sender: "@whatsapp_alice:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"new on wa"}`),
		TS: time.UnixMilli(300),
	})
	require.NoError(t, err)

	list, err = s.ListMergedChats(ctx)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Equal(t, "!wa:courier.local", list[0].LastRoomID)

	updated, err := s.UpdateMergedChat(ctx, mc.MergeID, "Alice Updated", []string{"!wa:courier.local", "!sig:courier.local"}, "!sig:courier.local")
	require.NoError(t, err)
	require.Equal(t, "Alice Updated", updated.Name)
	require.Equal(t, "!sig:courier.local", updated.LastRoomID)

	require.NoError(t, s.DeleteMergedChat(ctx, mc.MergeID))
	list, err = s.ListMergedChats(ctx)
	require.NoError(t, err)
	require.Empty(t, list)

	waRoom, ok, err = s.GetRoom(ctx, "!wa:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "", waRoom.MergeID)
	require.Equal(t, "Alice WA", waRoom.Name)

	sigRoom, ok, err = s.GetRoom(ctx, "!sig:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "", sigRoom.MergeID)
	require.Equal(t, "Alice Signal", sigRoom.Name)
}

func TestMergedTimelineInterleavesAndPaginates(t *testing.T) {
	s, ctx := open(t), context.Background()

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa:courier.local", Network: "whatsapp", Name: "Alice", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig:courier.local", Network: "signal", Name: "Alice", IsDirect: true}))

	for _, tc := range []struct {
		id   string
		room string
		ts   int64
	}{
		{"$e10", "!wa:courier.local", 10},
		{"$e20", "!sig:courier.local", 20},
		{"$e30", "!wa:courier.local", 30},
		{"$e40", "!sig:courier.local", 40},
		{"$e50", "!wa:courier.local", 50},
		{"$e60", "!sig:courier.local", 60},
	} {
		_, err := s.InsertEvent(ctx, Event{
			EventID: tc.id, RoomID: tc.room, Sender: "@u:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"msg"}`),
			TS: time.UnixMilli(tc.ts),
		})
		require.NoError(t, err)
	}

	// A thread reply must be excluded from the merged main timeline just like a single-room timeline.
	_, err := s.InsertEvent(ctx, Event{
		EventID: "$thread-reply", RoomID: "!wa:courier.local", Sender: "@u:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"in thread","m.relates_to":{"rel_type":"m.thread","event_id":"$e30"}}`),
		TS:      time.UnixMilli(45),
	})
	require.NoError(t, err)

	mc, err := s.CreateMergedChat(ctx, "Alice", []string{"!wa:courier.local", "!sig:courier.local"})
	require.NoError(t, err)

	page1, hasMore, err := s.MergedEventsBefore(ctx, mc.MergeID, nil, 4)
	require.NoError(t, err)
	require.True(t, hasMore)
	require.Len(t, page1, 4)
	require.Equal(t, []int64{30, 40, 50, 60}, []int64{
		page1[0].TS.UnixMilli(), page1[1].TS.UnixMilli(), page1[2].TS.UnixMilli(), page1[3].TS.UnixMilli(),
	})

	page2, hasMore, err := s.MergedEventsBefore(ctx, mc.MergeID, &Cursor{TS: page1[0].TS, Seq: page1[0].Seq}, 4)
	require.NoError(t, err)
	require.False(t, hasMore)
	require.Len(t, page2, 2)
	require.Equal(t, []int64{10, 20}, []int64{page2[0].TS.UnixMilli(), page2[1].TS.UnixMilli()})

	around, moreOlder, moreNewer, err := s.MergedEventsAround(ctx, mc.MergeID, "!wa:courier.local", "$e30", 3)
	require.NoError(t, err)
	require.True(t, moreOlder)
	require.True(t, moreNewer)
	require.Len(t, around, 3)
	require.Equal(t, []int64{20, 30, 40}, []int64{
		around[0].TS.UnixMilli(), around[1].TS.UnixMilli(), around[2].TS.UnixMilli(),
	})
}

func TestMergedTimelineEqualTimestampsAtPageBoundary(t *testing.T) {
	s, ctx := open(t), context.Background()

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa:courier.local", Network: "whatsapp", Name: "Alice", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig:courier.local", Network: "signal", Name: "Alice", IsDirect: true}))

	for _, tc := range []struct {
		id   string
		room string
		ts   int64
	}{
		{"$e1", "!wa:courier.local", 100},
		{"$e2", "!wa:courier.local", 200},
		{"$e3", "!sig:courier.local", 200},
		{"$e4", "!sig:courier.local", 300},
	} {
		_, err := s.InsertEvent(ctx, Event{
			EventID: tc.id, RoomID: tc.room, Sender: "@u:courier.local",
			Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"msg"}`),
			TS: time.UnixMilli(tc.ts),
		})
		require.NoError(t, err)
	}

	mc, err := s.CreateMergedChat(ctx, "Alice", []string{"!wa:courier.local", "!sig:courier.local"})
	require.NoError(t, err)

	// Paginate backwards with limit=2 so the boundary splits the two ts=200 events across rooms.
	bPage1, hasMore, err := s.MergedEventsBefore(ctx, mc.MergeID, nil, 2)
	require.NoError(t, err)
	require.True(t, hasMore)
	require.Len(t, bPage1, 2)
	require.Equal(t, []string{"$e3", "$e4"}, []string{bPage1[0].EventID, bPage1[1].EventID})

	bPage2, hasMore, err := s.MergedEventsBefore(ctx, mc.MergeID, &Cursor{TS: bPage1[0].TS, Seq: bPage1[0].Seq}, 2)
	require.NoError(t, err)
	require.False(t, hasMore)
	require.Len(t, bPage2, 2)
	require.Equal(t, []string{"$e1", "$e2"}, []string{bPage2[0].EventID, bPage2[1].EventID})

	// Paginate forwards with limit=2 across the same equal-timestamp boundary.
	aPage1, hasMore, err := s.MergedEventsAfter(ctx, mc.MergeID, nil, 2)
	require.NoError(t, err)
	require.True(t, hasMore)
	require.Len(t, aPage1, 2)
	require.Equal(t, []string{"$e1", "$e2"}, []string{aPage1[0].EventID, aPage1[1].EventID})

	last := aPage1[len(aPage1)-1]
	aPage2, hasMore, err := s.MergedEventsAfter(ctx, mc.MergeID, &Cursor{TS: last.TS, Seq: last.Seq}, 2)
	require.NoError(t, err)
	require.False(t, hasMore)
	require.Len(t, aPage2, 2)
	require.Equal(t, []string{"$e3", "$e4"}, []string{aPage2[0].EventID, aPage2[1].EventID})
}

func TestSuggestMergedChatsMatchesByPhoneAndName(t *testing.T) {
	s, ctx := open(t), context.Background()

	// Pair 1: WhatsApp + Signal sharing normalized E.164 phone identifier.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-alice:courier.local", Network: "whatsapp", Name: "Alice Example", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!wa-alice:courier.local", "@whatsapp_alice:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@whatsapp_alice:courier.local", DisplayName: "Alice Example",
		Identifiers: []string{"tel:+1 (555) 010-0101"},
	}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig-alice:courier.local", Network: "signal", Name: "Alice E.", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!sig-alice:courier.local", "@signal_alice:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@signal_alice:courier.local", DisplayName: "Alice E.",
		Identifiers: []string{"tel:+15550100101"},
	}))

	// Pair 2: Telegram + Slack sharing exact case-insensitive DisplayName "Bob Carter".
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tg-bob:courier.local", Network: "telegram", Name: "Bob Carter", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!tg-bob:courier.local", "@telegram_bob:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@telegram_bob:courier.local", DisplayName: "Bob Carter",
	}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!slack-bob:courier.local", Network: "slack", Name: "bob carter", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!slack-bob:courier.local", "@slack_bob:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{
		UserID: "@slack_bob:courier.local", DisplayName: "bob carter",
	}))

	// Negative cases: hidden room, group room, same-network rooms, empty name, phone-only display name, already-merged rooms.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!disc-bob:courier.local", Network: "discord", Name: "Bob Carter", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!disc-bob:courier.local", "@discord_bob:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@discord_bob:courier.local", DisplayName: "Bob Carter"}))
	_, err := s.SetHidden(ctx, []string{"!disc-bob:courier.local"}, true)
	require.NoError(t, err)

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!gm-group:courier.local", Network: "gmessages", Name: "Bob Carter", IsDirect: false}))
	require.NoError(t, s.SetMember(ctx, "!gm-group:courier.local", "@gmessages_bob:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@gmessages_bob:courier.local", DisplayName: "Bob Carter"}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-same1:courier.local", Network: "whatsapp", Name: "Same Net", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!wa-same1:courier.local", "@whatsapp_same1:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@whatsapp_same1:courier.local", DisplayName: "Same Net"}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-same2:courier.local", Network: "whatsapp", Name: "Same Net", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!wa-same2:courier.local", "@whatsapp_same2:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@whatsapp_same2:courier.local", DisplayName: "Same Net"}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-num:courier.local", Network: "whatsapp", Name: "+1 555-010-9999", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!wa-num:courier.local", "@whatsapp_num:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@whatsapp_num:courier.local", DisplayName: "+1 555-010-9999"}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig-num:courier.local", Network: "signal", Name: "+1 555-010-9999", IsDirect: true}))
	require.NoError(t, s.SetMember(ctx, "!sig-num:courier.local", "@signal_num:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@signal_num:courier.local", DisplayName: "+1 555-010-9999"}))

	suggestions, err := s.SuggestMergedChats(ctx)
	require.NoError(t, err)
	require.Len(t, suggestions, 2)

	require.Equal(t, "identifier", suggestions[0].Reason)
	require.ElementsMatch(t, []string{"!wa-alice:courier.local", "!sig-alice:courier.local"}, suggestions[0].RoomIDs)
	require.ElementsMatch(t, []string{"whatsapp", "signal"}, suggestions[0].Networks)

	require.Equal(t, "display_name", suggestions[1].Reason)
	require.Equal(t, "Bob Carter", suggestions[1].DisplayName)
	require.ElementsMatch(t, []string{"!tg-bob:courier.local", "!slack-bob:courier.local"}, suggestions[1].RoomIDs)
	require.ElementsMatch(t, []string{"telegram", "slack"}, suggestions[1].Networks)
}

func TestCreateAndUpdateMergedChatRequireDirectAndRefuseStealingRooms(t *testing.T) {
	s, ctx := open(t), context.Background()

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-dm1:courier.local", Network: "whatsapp", Name: "Alice", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig-dm1:courier.local", Network: "signal", Name: "Alice", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tg-dm1:courier.local", Network: "telegram", Name: "Alice", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa-dm2:courier.local", Network: "whatsapp", Name: "Bob", IsDirect: true}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig-grp:courier.local", Network: "signal", Name: "Group Chat", IsDirect: false}))

	// Non-direct (group) room must be refused with ErrBadValue.
	_, err := s.CreateMergedChat(ctx, "Bad Group Merge", []string{"!wa-dm1:courier.local", "!sig-grp:courier.local"})
	require.ErrorIs(t, err, ErrBadValue, "merging a non-direct room must return ErrBadValue")

	// Create first valid merge.
	mc1, err := s.CreateMergedChat(ctx, "Alice Merge", []string{"!wa-dm1:courier.local", "!sig-dm1:courier.local"})
	require.NoError(t, err)

	// Attempting to create a second merge that steals !wa-dm1:courier.local must fail with ErrBadValue.
	_, err = s.CreateMergedChat(ctx, "Stealing Merge", []string{"!wa-dm1:courier.local", "!tg-dm1:courier.local"})
	require.ErrorIs(t, err, ErrBadValue, "creating a merge with an already-merged room must return ErrBadValue")

	// Verify mc1 still owns both of its rooms.
	mergedList, err := s.ListMergedChats(ctx)
	require.NoError(t, err)
	require.Len(t, mergedList, 1)
	require.Equal(t, mc1.MergeID, mergedList[0].MergeID)
	require.ElementsMatch(t, []string{"!wa-dm1:courier.local", "!sig-dm1:courier.local"}, mergedList[0].RoomIDs)

	// Create a second independent merge and verify UpdateMergedChat also refuses stealing and non-direct rooms.
	mc2, err := s.CreateMergedChat(ctx, "Bob Merge", []string{"!wa-dm2:courier.local", "!tg-dm1:courier.local"})
	require.NoError(t, err)

	_, err = s.UpdateMergedChat(ctx, mc2.MergeID, "Bob Steal", []string{"!wa-dm2:courier.local", "!sig-dm1:courier.local"}, "")
	require.ErrorIs(t, err, ErrBadValue, "updating a merge to steal a room from another merge must return ErrBadValue")

	_, err = s.UpdateMergedChat(ctx, mc2.MergeID, "Bob Group", []string{"!wa-dm2:courier.local", "!sig-grp:courier.local"}, "")
	require.ErrorIs(t, err, ErrBadValue, "updating a merge with a non-direct room must return ErrBadValue")
}

func TestMigrationFromMilestone4_5a(t *testing.T) {
	s, _ := openFixture(t, "m9.sql")
	ctx := context.Background()
	require.GreaterOrEqual(t, SchemaVersion, 10)
	require.Equal(t, SchemaVersion, userVersion(t, s))
	require.Equal(t, len(migrations), userVersion(t, s))

	// Existing v8 merged_chats and profiles data are preserved.
	merged, err := s.ListMergedChats(ctx)
	require.NoError(t, err)
	require.Len(t, merged, 1)
	require.Equal(t, "merge:11111111-1111-1111-1111-111111111111", merged[0].MergeID)
	require.Equal(t, "Alice Example", merged[0].Name)
	require.Equal(t, []string{"!r1:courier.local", "!r2:courier.local"}, merged[0].RoomIDs)

	prof, ok, err := s.GetProfile(ctx, "@u1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, []string{"tel:+15550100101"}, prof.Identifiers)
	require.Equal(t, "America/Los_Angeles", prof.Timezone)

	// New media_played table exists and starts empty, then accepts played rows.
	require.Zero(t, count(t, s, "SELECT count(*) FROM media_played"))
	played, err := s.IsMediaPlayed(ctx, "!r1:courier.local", "$e1")
	require.NoError(t, err)
	require.False(t, played)
	require.NoError(t, s.MarkMediaPlayed(ctx, "!r1:courier.local", "$e1", 1790812805000))
	played, err = s.IsMediaPlayed(ctx, "!r1:courier.local", "$e1")
	require.NoError(t, err)
	require.True(t, played)
}

func TestMarkAndQueryMediaPlayed(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r1:courier.local", Network: "whatsapp", Name: "Alice Example", IsDirect: true}))
	_, err := s.InsertEvent(ctx, Event{
		EventID: "$ev1", RoomID: "!r1:courier.local", Sender: "@u1:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.audio","body":"voice.ogg","fi.mau.ishort":true}`),
		TS: time.UnixMilli(1000),
	})
	require.NoError(t, err)

	// 1. IsMediaPlayed returns false before MarkMediaPlayed.
	played, err := s.IsMediaPlayed(ctx, "!r1:courier.local", "$ev1")
	require.NoError(t, err)
	require.False(t, played)

	// 2. MarkMediaPlayed inserts and publishes a status change.
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.MarkMediaPlayed(ctx, "!r1:courier.local", "$ev1", 1700000001000))
	require.Equal(t, Change{Kind: "status", RoomID: "!r1:courier.local", EventID: "$ev1"}, nextChange(t, ch))

	played, err = s.IsMediaPlayed(ctx, "!r1:courier.local", "$ev1")
	require.NoError(t, err)
	require.True(t, played)

	// 3. Re-calling MarkMediaPlayed updates timestamp idempotently without error.
	require.NoError(t, s.MarkMediaPlayed(ctx, "!r1:courier.local", "$ev1", 1700000002000))
	require.Equal(t, Change{Kind: "status", RoomID: "!r1:courier.local", EventID: "$ev1"}, nextChange(t, ch))
	var playedTS int64
	require.NoError(t, s.db.QueryRow(ctx, "SELECT played_ts FROM media_played WHERE room_id = '!r1:courier.local' AND event_id = '$ev1'").Scan(&playedTS))
	require.Equal(t, int64(1700000002000), playedTS)

	// 4. MarkMediaPlayed on a second event in the room succeeds.
	require.NoError(t, s.MarkMediaPlayed(ctx, "!r1:courier.local", "$ev3", 1700000003000))
	require.Equal(t, Change{Kind: "status", RoomID: "!r1:courier.local", EventID: "$ev3"}, nextChange(t, ch))

	// 5. MediaPlayedSet returns the exact subset of played event IDs; empty input returns empty map without hitting SQL.
	emptySet, err := s.MediaPlayedSet(ctx, "!r1:courier.local", nil)
	require.NoError(t, err)
	require.Empty(t, emptySet)

	set, err := s.MediaPlayedSet(ctx, "!r1:courier.local", []string{"$ev1", "$ev2", "$ev3"})
	require.NoError(t, err)
	require.Equal(t, map[string]bool{"$ev1": true, "$ev3": true}, set)
}
