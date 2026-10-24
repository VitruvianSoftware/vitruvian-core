// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// deny is a plan that leaves out some features.
type deny map[entitlement.Feature]bool

func (d deny) Allowed(f entitlement.Feature) bool { return !d[f] }

func TestHeldSendReturnsAtOnceAndStaysQueued(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 4}}

	id, err := w.a.Send(ctx, room, "held back", SendOptions{Entities: bold, Hold: 5 * time.Second})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, "queued", e.Status)
	require.Empty(t, w.n.Sent, "nothing reaches the network while it is held")
	src, ok := SourceOf(e.Content)
	require.True(t, ok)
	require.Equal(t, Source{Text: "held back", Entities: bold}, src)

	// Not due yet: nothing goes.
	clock.Set(clock.Now().Add(4 * time.Second))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Empty(t, due)
	// Due: the loop hands it off, once.
	clock.Set(clock.Now().Add(time.Second))
	due, err = w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 1)
	w.a.HandOff(ctx, due[0])
	require.Equal(t, "held back", recv(t, w.n.Sent, "the held message").Body)
	w.waitStatus(t, id, "sent")
	_, err = w.a.Undo(ctx, id)
	require.ErrorIs(t, err, ErrAlreadySent)
}

func TestHoldNeedsAWindowFromTheList(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	for _, hold := range []time.Duration{-time.Second, time.Millisecond, 4 * time.Second, time.Minute} {
		_, err := w.a.Send(ctx, room, "x", SendOptions{Hold: hold})
		require.ErrorIs(t, err, ErrBadValue, hold)
	}
	require.Equal(t, 1, w.eventCount(t, room))
	for _, hold := range HoldWindows[1:] {
		id, err := w.a.Send(ctx, room, "x", SendOptions{Hold: hold})
		require.NoError(t, err, hold)
		require.Equal(t, "queued", w.get(t, id).Status)
	}
}

func TestHoldAndScheduleNeedTheirEntitlement(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()

	// Held and scheduled while the plan had them.
	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	undone, err := w.a.Send(ctx, room, "undone", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	sc, err := w.a.Schedule(ctx, room, "later", SendOptions{}, clock.Now().Add(time.Hour), "always")
	require.NoError(t, err)

	// The plan lapses: nothing new is held or scheduled, and nothing is stored trying.
	w.a.Entitlement = deny{entitlement.UndoSend: true, entitlement.SendLater: true}
	before := w.eventCount(t, room)
	_, err = w.a.Send(ctx, room, "x", SendOptions{Hold: time.Second})
	require.ErrorIs(t, err, ErrNotEntitled)
	_, err = w.a.SendFileWith(ctx, room, "/nonexistent", SendOptions{Hold: time.Second})
	require.ErrorIs(t, err, ErrNotEntitled)
	_, err = w.a.Schedule(ctx, room, "x", SendOptions{}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrNotEntitled)
	require.Equal(t, before, w.eventCount(t, room))
	list, err := w.s.ScheduledIn(ctx, room)
	require.NoError(t, err)
	require.Len(t, list, 1)

	// What is already held or scheduled is never stranded: it can be undone, changed, and sent.
	_, err = w.a.Undo(ctx, undone)
	require.NoError(t, err)
	text := "later, changed"
	_, err = w.a.UpdateScheduled(ctx, sc.ID, nil, &text, nil, nil)
	require.NoError(t, err)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, "held", recv(t, w.n.Sent, "the held message").Body)
	w.waitStatus(t, held, "sent")
	require.NoError(t, w.a.SendScheduledNow(ctx, sc.ID))
	require.Equal(t, "later, changed", recv(t, w.n.Sent, "the scheduled message").Body)
	// And sending at once needs no plan.
	_, err = w.a.Send(ctx, room, "now", SendOptions{})
	require.NoError(t, err)
	recv(t, w.n.Sent, "the message")
}

func TestUndoGivesBackWhatWasTyped(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	reply := w.firstID(t, room)
	ents := []richtext.Entity{{Kind: richtext.Italic, Offset: 0, Length: 4}}
	id, err := w.a.Send(ctx, room, "oops, wrong chat", SendOptions{Entities: ents, ReplyTo: reply, Hold: 10 * time.Second})
	require.NoError(t, err)

	e, err := w.a.Undo(ctx, id)
	require.NoError(t, err)
	require.Equal(t, id, e.EventID)
	src, ok := SourceOf(e.Content)
	require.True(t, ok)
	require.Equal(t, Source{Text: "oops, wrong chat", Entities: ents, ReplyTo: reply}, src)
	_, found, err := w.s.GetEvent(ctx, id)
	require.NoError(t, err)
	require.False(t, found, "gone from the chat")
	_, err = w.a.Undo(ctx, id)
	require.ErrorIs(t, err, ErrAlreadySent)
	require.Empty(t, w.n.Sent)
}

// Review Focus 1: a held message whose window ends while its network is down becomes waiting, not failed, and goes
// when the login is back. A held send while down is held first (Ruling C40); so is a scheduled message that comes due
// while down. Nothing reaches the network meanwhile.
func TestHandOffWhileOfflineWaits(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Features = whatsappFeatures()
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	clock := w.clocked()
	room, _ := w.chat(t, "alice", "m1")
	w.a.LoginWait = time.Hour // a hand-off never waits for it
	w.down()

	id, err := w.a.Send(ctx, room, "while offline", SendOptions{Hold: time.Second})
	require.NoError(t, err)
	require.Equal(t, "queued", w.get(t, id).Status, "held first")
	sc, err := w.a.Schedule(ctx, room, "scheduled while offline", SendOptions{}, clock.Now().Add(time.Minute), "always")
	require.NoError(t, err)
	clock.Set(clock.Now().Add(time.Minute))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 2)
	for _, d := range due {
		w.a.HandOff(ctx, d)
	}
	for _, id := range []string{id, sc.EventID} {
		got := w.get(t, id)
		require.Equal(t, store.StatusWaiting, got.Status, id)
		require.Empty(t, got.StatusReason, id)
	}
	none(t, w.n.Sent, "a message while offline")

	w.up()
	w.a.SendWaiting(ctx, "whatsapp")
	require.Equal(t, "while offline", recv(t, w.n.Sent, "the held message").Body)
	require.Equal(t, "scheduled while offline", recv(t, w.n.Sent, "the scheduled message").Body)
	w.waitStatus(t, id, "sent")
	w.waitStatus(t, sc.EventID, "sent")
}

// ReasonNotConnected now means only that the chat's network isn't running this session: a hand-off there can't wait
// for anything, so the message fails, for the person to Retry or Delete.
func TestHandOffOnANetworkNotRunningFailsAsNotConnected(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!gone:courier.local", Network: "telegram"}))
	gone := store.Event{
		RoomID: "!gone:courier.local", EventID: string(ids.RandomEventID()), Sender: string(ids.Me), Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"nowhere"}`), TS: time.Now(), Status: "pending",
	}
	_, err := w.s.InsertEvent(ctx, gone)
	require.NoError(t, err)
	w.a.HandOff(ctx, gone)
	got := w.get(t, gone.EventID)
	require.Equal(t, "failed", got.Status)
	require.Equal(t, ReasonNotConnected, got.StatusReason)
}

// Ruling C25: a quit that cuts short the hand-off of a message claimed from waiting puts it back to waiting
// (WaitAgain): never queued, late or "may have been sent". At the next start it is still waiting, and goes once.
func TestWaitingHandOffCutShortByShutdownStaysWaiting(t *testing.T) {
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	id, err := w.a.SendText(context.Background(), room, "while stopping", "")
	require.NoError(t, err)
	w.n.SetLoggedIn(w.login, true)
	claimed, err := w.s.ClaimWaiting(context.Background(), "fake", []string{string(w.login.ID)})
	require.NoError(t, err)
	require.Len(t, claimed, 1)
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // the engine stops between the claim and the hand-off
	require.True(t, w.a.handOff(ctx, claimed[0], true), "it went back")
	got := w.get(t, id)
	require.Equal(t, store.StatusWaiting, got.Status)
	none(t, w.n.Sent, "a message while stopping")

	n, err := w.s.FailInterruptedSends(context.Background())
	require.NoError(t, err)
	require.Zero(t, n, "never \"may have been sent\"")
	w.a.SendWaiting(context.Background(), "fake")
	require.Equal(t, "while stopping", recv(t, w.n.Sent, "the waiting message").Body)
	w.waitStatus(t, id, "sent")
}

// The engine stops while a hand-off waits for its network to log in (the timer loop's context ends). Nothing was
// sent, so the message goes back to the outbox, queued (store.Requeue): not left pending for the next start to call
// "may have been sent", and not failed "not connected" for a quit the person didn't see (Review Focus 3, final fix
// wave). At the next start it fires once, under MaxLate late.
func TestHandOffCutShortByShutdownFiresAtTheNextStart(t *testing.T) {
	n := fakenet.New()
	n.Features = whatsappFeatures()
	n.LoginDelay = time.Hour // linked, but never logged in during the test
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	clock := w.clocked()
	room, _ := w.chat(t, "alice", "m1")
	w.a.LoginWait = time.Hour

	ctx, cancel := context.WithCancel(context.Background())
	e := store.Event{
		RoomID: room, EventID: string(ids.RandomEventID()), Sender: string(ids.Me), Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"while stopping"}`), TS: clock.Now(),
	}
	require.NoError(t, w.s.Hold(ctx, e, clock.Now()))
	sc, err := w.a.Schedule(ctx, room, "scheduled", SendOptions{}, clock.Now().Add(time.Minute), "always")
	require.NoError(t, err)
	clock.Set(clock.Now().Add(time.Minute))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 2)
	cancel() // the engine is stopping
	for _, d := range due {
		w.a.HandOff(ctx, d)
	}
	for _, id := range []string{e.EventID, sc.EventID} {
		got := w.get(t, id)
		require.Equal(t, "queued", got.Status, id)
		require.Empty(t, got.StatusReason, id)
	}
	none(t, w.n.Sent, "a message while stopping")

	// The next start, half an hour on: claimed once each, and nothing more.
	clock.Set(clock.Now().Add(30 * time.Minute))
	n2, err := w.s.FailInterruptedSends(context.Background())
	require.NoError(t, err)
	require.Zero(t, n2)
	again, err := w.s.ClaimDue(context.Background())
	require.NoError(t, err)
	require.ElementsMatch(t, []string{e.EventID, sc.EventID}, []string{again[0].EventID, again[1].EventID})
	again, err = w.s.ClaimDue(context.Background())
	require.NoError(t, err)
	require.Empty(t, again)
}

func TestTypedSourceNeverReachesTheBridge(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 4}}
	noSource := func(what string) {
		t.Helper()
		raws := w.n.Raws()
		raw := raws[len(raws)-1]
		require.NotEmpty(t, raw, "%s reached the bridge as stored JSON", what)
		var m map[string]any
		require.NoError(t, json.Unmarshal(raw, &m))
		require.NotContains(t, m, store.SourceKey, what)
		require.Equal(t, "<strong>held</strong> back", m["formatted_body"], what)
	}

	held, err := w.a.Send(ctx, room, "held back", SendOptions{Entities: bold, Hold: 3 * time.Second})
	require.NoError(t, err)
	require.Contains(t, content(t, w.get(t, held)), store.SourceKey)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	recv(t, w.n.Sent, "the held message")
	noSource("the held message")
	require.NotContains(t, content(t, w.waitStatus(t, held, "sent")), store.SourceKey)

	sc, err := w.a.Schedule(ctx, room, "held back", SendOptions{Entities: bold}, clock.Now().Add(time.Hour), "always")
	require.NoError(t, err)
	src, ok := SourceOf(sc.Content)
	require.True(t, ok)
	require.Equal(t, "held back", src.Text)
	require.NoError(t, w.a.SendScheduledNow(ctx, sc.ID))
	recv(t, w.n.Sent, "the scheduled message")
	noSource("the scheduled message")
	require.NotContains(t, content(t, w.waitStatus(t, sc.EventID, "sent")), store.SourceKey)
}

func TestScheduleRendersAndUpdateReRenders(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, slackFeatures())
	clock := w.clocked()
	root := w.firstID(t, room)
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 5}}

	_, err := w.a.Schedule(ctx, room, "x", SendOptions{Hold: time.Second}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrBadValue, "a scheduled message isn't held as well")
	_, err = w.a.Schedule(ctx, room, "x", SendOptions{}, clock.Now().Add(-time.Minute), "")
	require.ErrorIs(t, err, ErrBadValue, "in the past")
	_, err = w.a.Schedule(ctx, room, " ", SendOptions{}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrEmpty)

	sc, err := w.a.Schedule(ctx, room, "later today", SendOptions{Entities: bold, ThreadRoot: root}, clock.Now().Add(time.Hour), "")
	require.NoError(t, err)
	require.Equal(t, "if_no_reply", sc.Condition)
	var c map[string]any
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "<strong>later</strong> today", c["formatted_body"])
	require.Equal(t, "m.thread", c["m.relates_to"].(map[string]any)["rel_type"])
	require.Equal(t, 1, w.eventCount(t, room), "not in the timeline until it is sent")

	// New text is rendered again, in the same thread.
	text := "later tonight"
	sc, err = w.a.UpdateScheduled(ctx, sc.ID, nil, &text, []richtext.Entity{{Kind: richtext.Italic, Offset: 6, Length: 7}}, nil)
	require.NoError(t, err)
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "later <em>tonight</em>", c["formatted_body"])
	require.Equal(t, root, c["m.relates_to"].(map[string]any)["event_id"])
	// New ranges alone keep the text.
	sc, err = w.a.UpdateScheduled(ctx, sc.ID, nil, nil, []richtext.Entity{}, nil)
	require.NoError(t, err)
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "later tonight", c["body"])
	require.NotContains(t, c, "formatted_body")
	src, _ := SourceOf(sc.Content)
	require.Equal(t, Source{Text: "later tonight", Entities: []richtext.Entity{}, ThreadRoot: root}, src)
	// Only the time: the content is left as it is.
	due := clock.Now().Add(2 * time.Hour)
	moved, err := w.a.UpdateScheduled(ctx, sc.ID, &due, nil, nil, nil)
	require.NoError(t, err)
	require.JSONEq(t, string(sc.Content), string(moved.Content))
	_, err = w.a.UpdateScheduled(ctx, 9999, nil, &text, nil, nil)
	require.ErrorIs(t, err, store.ErrNotFound)
}

func TestSendFileWithAHold(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	path := writeFile(t, "notes.txt", []byte("some notes"))
	id, err := w.a.SendFileWith(ctx, room, path, SendOptions{Hold: time.Second, Entities: []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 99}}})
	require.NoError(t, err, "a file ignores ranges")
	require.Equal(t, "queued", w.get(t, id).Status)
	require.Empty(t, w.n.Files)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, "notes.txt", recv(t, w.n.Files, "the held file").FileName)
	w.waitStatus(t, id, "sent")
}

// SendAllHeldNow sends every chat's held messages now (message.sendHeld with no chat, as the app quits).
func TestSendAllHeldNowSendsEveryChats(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	other, _ := w.secondChat(t, "bob", "m2", room)
	first, err := w.a.Send(ctx, room, "held here", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	second, err := w.a.Send(ctx, other, "held there", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)

	require.NoError(t, w.a.SendAllHeldNow(ctx))
	got := []string{recv(t, w.n.Sent, "a held message").Body, recv(t, w.n.Sent, "a held message").Body}
	require.ElementsMatch(t, []string{"held here", "held there"}, got)
	w.waitStatus(t, first, "sent")
	w.waitStatus(t, second, "sent")
	require.ErrorIs(t, w.a.SendHeldNow(ctx, ""), ErrBadValue, "\"\" is no chat: SendAllHeldNow is every chat")
}

// awaitStatusChange waits on feed for a "status" change for eventID, then returns the message as it is.
func (w world) awaitStatusChange(t *testing.T, feed <-chan store.Change, eventID string) store.Event {
	t.Helper()
	timeout := time.After(5 * time.Second) // a deadlock guard, not a measure
	for {
		select {
		case c := <-feed:
			if c.Kind == "status" && c.EventID == eventID {
				return w.get(t, eventID)
			}
		case <-timeout:
			t.Fatalf("no status change for %s", eventID)
		}
	}
}

// A SendWaiting run in flight for one chat holds up no other: a held message that comes due in a connected chat with
// nothing waiting goes to the network while another chat's waiting message is still being handed over, and ends
// sent, with no clock firing and nothing to wake a loop (review fix round 1).
func TestAHeldMessageIsNotHeldUpByAnotherChatsWaitingRun(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	roomA, _ := w.chat(t, "chatA", "m1")
	roomB, _ := w.secondChat(t, "chatB", "m2", roomA)
	clock := w.clocked()
	w.down()
	waiting, err := w.a.SendText(ctx, roomA, "waiting in A", "")
	require.NoError(t, err)
	w.n.SetLoggedIn(w.login, true)

	feed, cancel := w.s.Subscribe()
	defer cancel()
	w.n.Hold = make(chan struct{}) // the network sits on what it is handed, so the run stays in flight
	run := make(chan struct{})
	go func() {
		defer close(run)
		w.a.SendWaiting(ctx, "fake")
	}()
	require.Equal(t, "pending", w.awaitStatusChange(t, feed, waiting).Status, "A's message is claimed: the run is in flight")

	held, err := w.a.Send(ctx, roomB, "held in B", SendOptions{Hold: time.Second})
	require.NoError(t, err)
	clock.Set(clock.Now().Add(time.Second))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 1)
	handed := make(chan struct{})
	go func() {
		defer close(handed)
		w.a.HandOff(ctx, due[0])
	}()
	close(w.n.Hold)
	<-run
	<-handed
	w.waitStatus(t, waiting, "sent")
	w.waitStatus(t, held, "sent")
}

// Send Now on a held message in a chat whose waiting messages are still being handed over makes it wait behind them,
// and it goes once they have: putting it back wakes the loop (Actions.Wake), so it doesn't sit "Waiting to send"
// until the next 30 s wake (review fix round 1). No loop pass claimed it, so nothing else would. The loop's clock
// never fires here.
func TestAHeldMessageBehindItsChatsWaitingOnesGoesRightAfterThem(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	first, err := w.a.SendText(ctx, room, "first", "")
	require.NoError(t, err)
	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)

	feed, cancel := w.s.Subscribe()
	defer cancel()
	w.n.Hold = make(chan struct{}) // the network sits on "first", so its run stays in flight
	w.loop(t)
	var once sync.Once
	release := func() { once.Do(func() { close(w.n.Hold) }) }
	t.Cleanup(release) // before the loop's cleanup, which waits for the run
	w.up()             // the loop's run claims "first"
	require.Equal(t, "pending", w.awaitStatusChange(t, feed, first).Status)

	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, store.StatusWaiting, w.get(t, held).Status, "behind first, it waits")
	release()
	require.Equal(t, "first", recv(t, w.n.Sent, "the first message").Body)
	require.Equal(t, "held", recv(t, w.n.Sent, "the held message, right after").Body)
	w.waitStatus(t, held, "sent")
}

// A message put back to waiting only because its chat's waiting messages are ahead of it, its login being in, wakes
// the loop (Actions.Wake): nothing else would, as a put-back publishes only "status". One put back for its login
// doesn't: the login's bridge state will (review fix round 1).
func TestAPutBackBehindWaitingMessagesWakesTheLoop(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	woken := make(chan struct{}, 16)
	w.a.Wake = func() { woken <- struct{}{} }
	w.down()
	_, err := w.a.SendText(ctx, room, "first", "")
	require.NoError(t, err)
	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, store.StatusWaiting, w.get(t, held).Status)
	require.Empty(t, woken, "down: its login's state wakes the loop, not this")

	w.n.SetLoggedIn(w.login, true) // in, but no loop has claimed "first" yet
	held, err = w.a.Send(ctx, room, "held again", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, store.StatusWaiting, w.get(t, held).Status, "behind first")
	require.Len(t, woken, 1, "the loop is woken to send them")
	none(t, w.n.Sent, "a message before the loop runs")
}
