// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// t0 is the tests' "now": every outbox test drives the store's clock from it.
var t0 = time.UnixMilli(1_790_000_000_000)

// composed is message content as the composer sends it: its body plus what was typed, under sourceKey.
func composed(body string) json.RawMessage {
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": body,
		sourceKey: map[string]any{"text": body, "entities": []any{}},
	})
	return b
}

// held is my new message id in roomID, as the composer hands it to Hold.
func held(roomID, id, body string, ts time.Time) Event {
	return Event{RoomID: roomID, EventID: id, Sender: me, Type: "m.room.message", Content: composed(body), TS: ts}
}

// requireNoSource fails if content still carries what the composer typed.
func requireNoSource(t *testing.T, content json.RawMessage) {
	t.Helper()
	var m map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(content, &m))
	require.NotContains(t, m, sourceKey)
	require.Contains(t, m, "body")
}

func getEvent(t *testing.T, s *Store, id string) (Event, bool) {
	t.Helper()
	e, ok, err := s.GetEvent(context.Background(), id)
	require.NoError(t, err)
	return e, ok
}

func schedule(t *testing.T, s *Store, roomID, id, body string, due time.Time, condition string) Scheduled {
	t.Helper()
	sc, err := s.Schedule(context.Background(), Scheduled{
		RoomID: roomID, EventID: id, Type: "m.room.message", Content: composed(body), DueAt: due, Condition: condition,
	})
	require.NoError(t, err)
	return sc
}

func claimDue(t *testing.T, s *Store) []string {
	t.Helper()
	evs, err := s.ClaimDue(context.Background())
	require.NoError(t, err)
	return idsOf(evs)
}

func scheduledStates(t *testing.T, s *Store, roomID string) map[string]string {
	t.Helper()
	list, err := s.ScheduledIn(context.Background(), roomID)
	require.NoError(t, err)
	out := map[string]string{}
	for _, sc := range list {
		out[sc.EventID] = sc.State
	}
	return out
}

func TestHoldThenUndoLeavesNothing(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), t0.Add(-time.Minute))

	require.NoError(t, s.Hold(ctx, held("!r", "$h", "see you soon", t0), t0.Add(5*time.Second)))
	e, ok := getEvent(t, s, "$h")
	require.True(t, ok)
	require.Equal(t, "queued", e.Status)
	require.Equal(t, "$h", lastEventID(t, s, "!r"), "a held message is the chat's latest")
	require.Equal(t, "see you soon", inboxByID(t, s)["!r"].Preview)
	require.Equal(t, []string{"$h"}, matches(t, s, `"soon"`), "and searchable")
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM outbox"))
	require.ErrorIs(t, s.Hold(ctx, held("!r", "$h", "again", t0), t0.Add(time.Second)), ErrBadValue, "an ID already here")
	require.ErrorIs(t, s.Hold(ctx, held("!nowhere", "$x", "hi", t0), t0.Add(time.Second)), ErrNotFound)
	schedule(t, s, "!r", "$sched", "later", t0.Add(time.Hour), condAlways)
	require.ErrorIs(t, s.Hold(ctx, held("!r", "$sched", "hi", t0), t0.Add(time.Second)), ErrBadValue, "an ID a scheduled message will use")
	_, ok = getEvent(t, s, "$sched")
	require.False(t, ok)

	ch, cancel := s.Subscribe()
	defer cancel()
	back, err := s.Unhold(ctx, "$h")
	require.NoError(t, err)
	require.Equal(t, "$h", back.EventID)
	require.JSONEq(t, string(composed("see you soon")), string(back.Content), "Undo gives back exactly what was typed")
	require.Equal(t, Change{Kind: "status", RoomID: "!r", EventID: "$h", Seq: e.Seq}, nextChange(t, ch))

	_, ok = getEvent(t, s, "$h")
	require.False(t, ok, "no row")
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM outbox WHERE kind = 'undo'"), "no undo row; only the scheduled one is left")
	require.Empty(t, matches(t, s, `"soon"`), "no doc")
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_messages"), "only the first message's")
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
	require.Equal(t, "first", inboxByID(t, s)["!r"].Preview, "the room preview is back")

	_, err = s.Unhold(ctx, "$h")
	require.ErrorIs(t, err, ErrAlreadySent)
}

func TestUndoAfterClaimIsAlreadySent(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "on my way", t0), t0.Add(5*time.Second)))

	require.Empty(t, claimDue(t, s), "not due yet")
	clock.set(t0.Add(5 * time.Second))
	evs, err := s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	require.Equal(t, "pending", evs[0].Status)
	requireNoSource(t, evs[0].Content)

	_, err = s.Unhold(ctx, "$h")
	require.ErrorIs(t, err, ErrAlreadySent)
	e, ok := getEvent(t, s, "$h")
	require.True(t, ok)
	require.Equal(t, "pending", e.Status)
	requireNoSource(t, e.Content)
	require.Equal(t, []string{"$h"}, matches(t, s, `"way"`), "still searchable once sent")
	require.Empty(t, claimDue(t, s))
}

// Review Focus 2: Undo at the last moment does exactly one thing. ClaimDue and Unhold start together on one signal;
// exactly one of them takes the message each round: it is pending (and Undo says it already went), or it is gone
// (and the claim didn't return it). Run under race.
func TestClaimAndUndoRaceEndsOneWay(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	claims, undos := 0, 0
	for i := range 200 {
		id := fmt.Sprintf("$h%d", i)
		require.NoError(t, s.Hold(ctx, held("!r", id, "race", t0), t0)) // due now: a claim takes it

		start := make(chan struct{})
		claimed := make(chan []Event, 1)
		claimErr := make(chan error, 1)
		undone := make(chan error, 1)
		go func() {
			<-start
			evs, err := s.ClaimDue(ctx)
			claimErr <- err
			claimed <- evs
		}()
		go func() {
			<-start
			_, err := s.Unhold(ctx, id)
			undone <- err
		}()
		close(start)
		require.NoError(t, <-claimErr)
		evs, undoErr := <-claimed, <-undone

		e, present := getEvent(t, s, id)
		switch {
		case undoErr == nil:
			undos++
			require.Empty(t, evs, "round %d: undone and claimed", i)
			require.False(t, present, "round %d: undone but still here", i)
		default:
			claims++
			require.ErrorIs(t, undoErr, ErrAlreadySent, "round %d", i)
			require.Equal(t, []string{id}, idsOf(evs), "round %d: neither undone nor claimed", i)
			require.True(t, present, "round %d", i)
			require.Equal(t, "pending", e.Status, "round %d", i)
		}
		require.Equal(t, 0, count(t, s, "SELECT count(*) FROM outbox"), "round %d", i)
	}
	t.Logf("claims %d, undos %d", claims, undos)
}

// reopen opens the database at path again, with the clock at now, as the engine does at start.
func reopen(t *testing.T, path string, now time.Time) *Store {
	t.Helper()
	s, err := Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	clockAt(s, now)
	return s
}

// Review Focus 3: a message that came due while Courier was quit fires once at the next start, and never again.
func TestScheduledClaimedOnceAcrossReopen(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	schedule(t, s, "!r", "$later", "happy birthday", t0.Add(8*time.Hour), condAlways)
	require.NoError(t, s.Close())

	// Courier was quit through the due time; it starts 10 minutes after it.
	s = reopen(t, path, t0.Add(8*time.Hour+10*time.Minute))
	evs, err := s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	require.Equal(t, "$later", evs[0].EventID)
	require.Equal(t, "pending", evs[0].Status)
	require.Equal(t, me, evs[0].Sender)
	require.Equal(t, t0.Add(8*time.Hour+10*time.Minute).UnixMilli(), evs[0].TS.UnixMilli(), "sent now")
	requireNoSource(t, evs[0].Content)
	require.Empty(t, scheduledStates(t, s, ""), "the claim took its row")
	require.Equal(t, "$later", lastEventID(t, s, "!r"), "it moves the chat")
	require.Equal(t, []string{"$later"}, matches(t, s, `"birthday"`), "and is searchable once sent")
	require.Empty(t, claimDue(t, s))
	require.NoError(t, s.SetStatus(ctx, "$later", "sent", ""))
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(9*time.Hour))
	require.Empty(t, claimDue(t, s))
	e, ok := getEvent(t, s, "$later")
	require.True(t, ok)
	require.Equal(t, "sent", e.Status)
}

// Review Focus 3: the engine dies after a claim, before the bridge took the messages. At the next start they are
// "may have been sent" and no claim returns them again: never sent twice.
func TestCrashAfterClaimNeverSendsTwice(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(5*time.Second)))
	sc := schedule(t, s, "!r", "$s", "scheduled", t0.Add(time.Minute), condAlways)
	s.SetClock(func() time.Time { return t0.Add(time.Minute) })
	require.ElementsMatch(t, []string{"$h", "$s"}, claimDue(t, s))
	require.NoError(t, s.Close()) // no hand-off: the engine died here

	s = reopen(t, path, t0.Add(2*time.Minute))
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.EqualValues(t, 2, n)
	for _, id := range []string{"$h", "$s"} {
		e, ok := getEvent(t, s, id)
		require.True(t, ok, id)
		require.Equal(t, "failed", e.Status, id)
		require.Equal(t, ReasonMayHaveBeenSent, e.StatusReason, id)
	}
	require.Empty(t, claimDue(t, s))
	heldNow, err := s.ClaimHeld(ctx, "")
	require.NoError(t, err)
	require.Empty(t, heldNow)
	_, err = s.ClaimScheduled(ctx, sc.ID)
	require.ErrorIs(t, err, ErrNotFound)
}

// Review Focus 3, final fix wave: a held or scheduled message claimed as Courier quits, whose hand-off the quit cut
// short before anything reached the network, goes back to the outbox (Requeue). At the next start it fires once if
// it is under MaxLate late, and is failed "not sent" (Retry, Delete) if it is over.
func TestRequeuedAtQuitFiresOnceAfterRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(5*time.Second)))
	schedule(t, s, "!r", "$s", "scheduled", t0.Add(time.Minute), condAlways)
	s.SetClock(func() time.Time { return t0.Add(time.Minute) })
	require.ElementsMatch(t, []string{"$h", "$s"}, claimDue(t, s))
	for _, id := range []string{"$h", "$s"} { // the quit cut both hand-offs short
		ok, err := s.Requeue(ctx, id)
		require.NoError(t, err)
		require.True(t, ok, id)
		e, _ := getEvent(t, s, id)
		require.Equal(t, "queued", e.Status, id)
	}
	ok, err := s.Requeue(ctx, "$h")
	require.NoError(t, err)
	require.False(t, ok, "only a pending message goes back")
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(30*time.Minute))
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n, "back in the outbox, not an interrupted send")
	require.ElementsMatch(t, []string{"$h", "$s"}, claimDue(t, s), "under an hour late: they go, once")
	require.Empty(t, claimDue(t, s))
	require.NoError(t, s.Close())

	// Requeued again, and Courier stays closed past MaxLate: failed "not sent", for the person to Retry or Delete.
	s = reopen(t, path, t0.Add(30*time.Minute))
	for _, id := range []string{"$h", "$s"} {
		ok, err := s.Requeue(ctx, id)
		require.NoError(t, err)
		require.True(t, ok, id)
	}
	require.NoError(t, s.Close())
	s = reopen(t, path, t0.Add(2*time.Hour))
	require.Empty(t, claimDue(t, s))
	for _, id := range []string{"$h", "$s"} {
		e, _ := getEvent(t, s, id)
		require.Equal(t, "failed", e.Status, id)
		require.Equal(t, ReasonNotSent, e.StatusReason, id)
	}
}

// A held message survives a quit: its row is still there at the next start, FailInterruptedSends leaves it (it was
// never handed over), and it is claimed once.
func TestHeldMessageSurvivesAQuit(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(5*time.Second)))
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(time.Minute))
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n)
	require.Equal(t, []string{"$h"}, claimDue(t, s))
	require.Empty(t, claimDue(t, s))
}

// Review Focus 3: with "if no reply", someone else writing after it was set cancels it. One who wrote before, my own
// message and a reaction don't; "always" ignores replies.
func TestReplyCancelsIfNoReply(t *testing.T) {
	s := open(t)
	clock := clockAt(s, t0)
	for _, r := range []string{"!quiet", "!replied", "!always"} {
		mkRoom(t, s, r, time.Unix(1, 0))
		mkMsg(t, s, r, "$before"+r, ghost, "m.room.message", text("before"), t0.Add(-time.Minute))
	}
	schedule(t, s, "!quiet", "$q", "ping", t0.Add(time.Hour), condIfNoReply)
	schedule(t, s, "!replied", "$r", "ping", t0.Add(time.Hour), condIfNoReply)
	schedule(t, s, "!always", "$a", "ping", t0.Add(time.Hour), condAlways)

	// In !quiet: my own message, their reaction and their edit of an older message.
	mkMsg(t, s, "!quiet", "$mine", me, "m.room.message", text("mine"), t0.Add(time.Minute))
	mkMsg(t, s, "!quiet", "$react", ghost, "m.reaction",
		`{"m.relates_to":{"rel_type":"m.annotation","event_id":"$mine","key":"👍"}}`, t0.Add(2*time.Minute))
	mkMsg(t, s, "!quiet", "$edit", ghost, "m.room.message", editTo("$before!quiet", "before, edited"), t0.Add(3*time.Minute))
	// ... a bridge's notice, and a message of theirs that was deleted.
	mkMsg(t, s, "!quiet", "$notice", ghost, "m.room.message", `{"msgtype":"m.notice","body":"Disappearing messages are on"}`,
		t0.Add(4*time.Minute))
	mkMsg(t, s, "!quiet", "$oops", ghost, "m.room.message", text("wrong chat"), t0.Add(5*time.Minute))
	mkMsg(t, s, "!quiet", "$del", ghost, "m.room.redaction", redactionOf("$oops"), t0.Add(6*time.Minute))
	// In !replied and !always: they write.
	mkMsg(t, s, "!replied", "$reply", ghost, "m.room.message", text("hi!"), t0.Add(time.Minute))
	mkMsg(t, s, "!always", "$reply2", ghost, "m.room.message", text("hi!"), t0.Add(time.Minute))

	ch, cancel := s.Subscribe()
	defer cancel()
	clock.set(t0.Add(time.Hour))
	require.ElementsMatch(t, []string{"$q", "$a"}, claimDue(t, s))
	require.Equal(t, map[string]string{"$r": stateCanceled}, scheduledStates(t, s, ""), "canceled stays listed")
	_, ok := getEvent(t, s, "$r")
	require.False(t, ok, "a canceled message isn't sent")
	changesUntil(t, ch, Change{Kind: "scheduled", RoomID: "!replied"})
	require.Empty(t, claimDue(t, s), "a canceled message isn't claimed again")
}

// Review Focus 3: a scheduled message more than an hour late waits as missed; under an hour late, it goes.
func TestOverAnHourLateWaitsAsMissed(t *testing.T) {
	s := open(t)
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	schedule(t, s, "!r", "$late", "late", t0.Add(time.Minute), condAlways)
	schedule(t, s, "!r", "$ok", "ok", t0.Add(3*time.Minute), condAlways)
	ch, cancel := s.Subscribe()
	defer cancel()

	clock.set(t0.Add(62 * time.Minute)) // $late is 61 minutes late, $ok 59
	require.Equal(t, []string{"$ok"}, claimDue(t, s))
	require.Equal(t, map[string]string{"$late": stateMissed}, scheduledStates(t, s, "!r"))
	_, ok := getEvent(t, s, "$late")
	require.False(t, ok)
	changesUntil(t, ch, Change{Kind: "scheduled", RoomID: "!r"})
	require.Empty(t, claimDue(t, s), "a missed message waits for the person")
}

func TestLateHeldMessageBecomesNotSent(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$late", "late", t0), t0.Add(5*time.Second)))
	require.NoError(t, s.Hold(ctx, held("!r", "$ok", "ok", t0), t0.Add(2*time.Minute+5*time.Second)))

	clock.set(t0.Add(61*time.Minute + 5*time.Second)) // $late is 61 minutes late, $ok 59
	require.Equal(t, []string{"$ok"}, claimDue(t, s))
	e, ok := getEvent(t, s, "$late")
	require.True(t, ok, "never lost")
	require.Equal(t, "failed", e.Status)
	require.Equal(t, ReasonNotSent, e.StatusReason)
	requireNoSource(t, e.Content)
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM outbox"))
	_, err := s.Unhold(ctx, "$late")
	require.ErrorIs(t, err, ErrAlreadySent)
}

func TestSendNowWorksFromEveryState(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	waiting := schedule(t, s, "!r", "$w", "waiting", t0.Add(3*time.Hour), condAlways)
	canceled := schedule(t, s, "!r", "$c", "canceled", t0.Add(time.Minute), condIfNoReply)
	missed := schedule(t, s, "!r", "$m", "missed", t0.Add(2*time.Minute), condAlways)
	mkMsg(t, s, "!r", "$reply", ghost, "m.room.message", text("hi"), t0.Add(30*time.Second))
	clock.set(t0.Add(2 * time.Hour))
	require.Empty(t, claimDue(t, s))
	require.Equal(t, map[string]string{"$w": stateWaiting, "$c": stateCanceled, "$m": stateMissed}, scheduledStates(t, s, ""))

	now := t0.Add(2*time.Hour + time.Second)
	clock.set(now)
	for _, sc := range []Scheduled{waiting, canceled, missed} {
		e, err := s.ClaimScheduled(ctx, sc.ID)
		require.NoError(t, err, sc.EventID)
		require.Equal(t, sc.EventID, e.EventID)
		require.Equal(t, "pending", e.Status)
		require.Equal(t, now.UnixMilli(), e.TS.UnixMilli())
		requireNoSource(t, e.Content)
		stored, ok := getEvent(t, s, sc.EventID)
		require.True(t, ok)
		require.Equal(t, "pending", stored.Status)
		_, err = s.ClaimScheduled(ctx, sc.ID)
		require.ErrorIs(t, err, ErrNotFound, "sent once")
	}
	require.Empty(t, scheduledStates(t, s, ""))
	_, err := s.ClaimScheduled(ctx, 999)
	require.ErrorIs(t, err, ErrNotFound)
}

func TestUpdateScheduledResetsTheReplyClock(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	sc := schedule(t, s, "!r", "$s", "first draft", t0.Add(time.Hour), condIfNoReply)
	mkMsg(t, s, "!r", "$reply", ghost, "m.room.message", text("hi"), t0.Add(time.Minute))

	// Changed after their reply: that reply is from before, so it no longer cancels.
	clock.set(t0.Add(2 * time.Minute))
	got, err := s.UpdateScheduled(ctx, sc.ID, nil, "m.room.message", composed("second draft"), nil)
	require.NoError(t, err)
	require.Equal(t, t0.Add(2*time.Minute).UnixMilli(), got.SetAt.UnixMilli())
	require.Equal(t, stateWaiting, got.State)
	require.Equal(t, sc.DueAt, got.DueAt)
	require.Equal(t, condIfNoReply, got.Condition)

	clock.set(t0.Add(time.Hour))
	evs, err := s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	var body struct{ Body string }
	require.NoError(t, json.Unmarshal(evs[0].Content, &body))
	require.Equal(t, "second draft", body.Body, "the changed text is what goes")

	// A canceled one that is changed waits again, with its new time and condition.
	sc = schedule(t, s, "!r", "$s2", "again", t0.Add(2*time.Hour), condIfNoReply)
	mkMsg(t, s, "!r", "$reply2", ghost, "m.room.message", text("hi"), t0.Add(time.Hour+time.Minute))
	clock.set(t0.Add(2 * time.Hour))
	require.Empty(t, claimDue(t, s))
	require.Equal(t, stateCanceled, scheduledStates(t, s, "!r")["$s2"])
	_, err = s.UpdateScheduled(ctx, sc.ID, nil, "m.room.message", composed("edited"), nil)
	require.ErrorIs(t, err, ErrBadValue, "canceled: only a new time makes it wait again")
	require.Equal(t, stateCanceled, scheduledStates(t, s, "!r")["$s2"])
	due, always := t0.Add(3*time.Hour), condAlways
	got, err = s.UpdateScheduled(ctx, sc.ID, &due, "", nil, &always)
	require.NoError(t, err)
	require.Equal(t, stateWaiting, got.State)
	require.Equal(t, due.UnixMilli(), got.DueAt.UnixMilli())
	require.Equal(t, condAlways, got.Condition)
	require.JSONEq(t, string(composed("again")), string(got.Content), "the content is kept")

	past, bad := t0, "sometimes"
	_, err = s.UpdateScheduled(ctx, sc.ID, &past, "", nil, nil)
	require.ErrorIs(t, err, ErrBadValue)
	_, err = s.UpdateScheduled(ctx, sc.ID, nil, "", nil, &bad)
	require.ErrorIs(t, err, ErrBadValue)
	_, err = s.UpdateScheduled(ctx, 999, nil, "", nil, nil)
	require.ErrorIs(t, err, ErrNotFound)
}

func TestScheduleMustBeInTheFuture(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	try := func(sc Scheduled) error {
		if sc.RoomID == "" {
			sc.RoomID = "!r"
		}
		if sc.EventID == "" {
			sc.EventID = "$s"
		}
		if sc.Type == "" {
			sc.Type = "m.room.message"
		}
		if sc.Content == nil {
			sc.Content = composed("hello")
		}
		_, err := s.Schedule(ctx, sc)
		return err
	}
	require.ErrorIs(t, try(Scheduled{DueAt: t0}), ErrBadValue, "now")
	require.ErrorIs(t, try(Scheduled{DueAt: t0.Add(-time.Minute)}), ErrBadValue, "the past")
	require.ErrorIs(t, try(Scheduled{DueAt: t0.AddDate(5, 0, 0).Add(time.Millisecond)}), ErrBadValue, "beyond 5 years")
	require.ErrorIs(t, try(Scheduled{DueAt: t0.Add(time.Hour), Condition: "sometimes"}), ErrBadValue)
	require.ErrorIs(t, try(Scheduled{DueAt: t0.Add(time.Hour), Content: json.RawMessage("not json")}), ErrBadValue)
	require.ErrorIs(t, try(Scheduled{RoomID: "!nowhere", DueAt: t0.Add(time.Hour)}), ErrNotFound)
	mkMsg(t, s, "!r", "$taken", ghost, "m.room.message", text("x"), t0.Add(-time.Hour))
	require.ErrorIs(t, try(Scheduled{EventID: "$taken", DueAt: t0.Add(time.Hour)}), ErrBadValue, "an ID already used")

	sc, err := s.Schedule(ctx, Scheduled{
		RoomID: "!r", EventID: "$s", Type: "m.room.message", Content: composed("hello"),
		DueAt: t0.AddDate(5, 0, 0),
	})
	require.NoError(t, err, "5 years ahead is the limit")
	require.Equal(t, condIfNoReply, sc.Condition, "the default")
	require.Equal(t, stateWaiting, sc.State)
	require.Equal(t, t0.UnixMilli(), sc.SetAt.UnixMilli())
	require.NotZero(t, sc.ID)

	// It lives only in the outbox until it goes: not in the timeline, not in search.
	evs, _, err := s.EventsBefore(ctx, "!r", nil, 10)
	require.NoError(t, err)
	require.Equal(t, []string{"$taken"}, idsOf(evs))
	require.Empty(t, matches(t, s, `"hello"`))

	require.NoError(t, s.DeleteScheduled(ctx, sc.ID))
	require.ErrorIs(t, s.DeleteScheduled(ctx, sc.ID), ErrNotFound)
	require.Empty(t, scheduledStates(t, s, ""))
}

func TestSendLaterSpaceListsChatsWithScheduledMessages(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	for _, r := range []string{"!waiting", "!canceled", "!archived", "!hidden", "!none"} {
		mkRoom(t, s, r, time.Unix(1, 0))
	}
	schedule(t, s, "!waiting", "$w", "w", t0.Add(3*time.Hour), condAlways)
	schedule(t, s, "!canceled", "$c", "c", t0.Add(time.Hour), condIfNoReply)
	mkMsg(t, s, "!canceled", "$reply", ghost, "m.room.message", text("hi"), t0.Add(time.Minute))
	schedule(t, s, "!archived", "$a", "a", t0.Add(3*time.Hour), condAlways)
	schedule(t, s, "!hidden", "$h", "h", t0.Add(3*time.Hour), condAlways)
	_, err := s.SetArchived(ctx, []string{"!archived"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!hidden"}, true)
	require.NoError(t, err)
	// A held message isn't scheduled.
	require.NoError(t, s.Hold(ctx, held("!none", "$held", "held", t0), t0.Add(5*time.Second)))
	clock.set(t0.Add(time.Hour))
	require.Equal(t, []string{"$held"}, claimDue(t, s), "$c is canceled")

	want := []string{"!waiting", "!canceled", "!archived"}
	require.ElementsMatch(t, want, allPages(t, s, InboxQuery{Space: "send_later"}))
	require.ElementsMatch(t, want, allPages(t, s, InboxQuery{Space: "inbox", Filters: []string{"send_later"}}))
	require.Equal(t, len(want), spacesByID(t, s)["send_later"].Chats, "the count follows")

	// Sent, it leaves the space.
	list, err := s.ScheduledIn(ctx, "!waiting")
	require.NoError(t, err)
	_, err = s.ClaimScheduled(ctx, list[0].ID)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!canceled", "!archived"}, allPages(t, s, InboxQuery{Space: "send_later"}))
	require.Equal(t, 2, spacesByID(t, s)["send_later"].Chats)
}

func TestNextDueIncludesTheOutboxAndExpiry(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	next := func() (time.Time, bool) {
		t.Helper()
		at, ok, err := s.NextDue(ctx)
		require.NoError(t, err)
		return at, ok
	}
	_, ok := next()
	require.False(t, ok)
	// A message waiting for its network is due now, but for the network, not the clock: NextDue ignores it.
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "waiting", t0.Add(-time.Minute))))
	_, ok = next()
	require.False(t, ok, "an offline row waits for no time")

	sc := schedule(t, s, "!r", "$s", "later", t0.Add(time.Hour), condIfNoReply)
	at, ok := next()
	require.True(t, ok)
	require.Equal(t, t0.Add(time.Hour).UnixMilli(), at.UnixMilli())

	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(10*time.Second)))
	at, _ = next()
	require.Equal(t, t0.Add(10*time.Second).UnixMilli(), at.UnixMilli())

	insert(t, s, Event{
		RoomID: "!r", EventID: "$d", Sender: ghost, Type: "m.room.message", TS: t0.Add(-time.Hour),
		Content: json.RawMessage(`{"msgtype":"m.text","body":"x","com.beeper.disappearing_timer":{"type":"after_send","timer":3605000}}`),
	})
	at, _ = next()
	require.Equal(t, t0.Add(5*time.Second).UnixMilli(), at.UnixMilli(), "the disappearing message comes first")

	// Expired, claimed and canceled things wait for nothing.
	clock.set(t0.Add(10 * time.Second))
	rooms, err := s.ExpireDue(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, rooms)
	require.Equal(t, []string{"$h"}, claimDue(t, s))
	at, _ = next()
	require.Equal(t, sc.DueAt.UnixMilli(), at.UnixMilli())
	mkMsg(t, s, "!r", "$reply", ghost, "m.room.message", text("hi"), t0.Add(time.Minute))
	clock.set(t0.Add(time.Hour))
	require.Empty(t, claimDue(t, s))
	_, ok = next()
	require.False(t, ok, "a canceled message waits for the person, not the clock")
}

// ⌘⇧Z: the held messages of one chat go now, before their window ends; another chat's wait.
func TestClaimHeldSendsNowInOneChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!a", time.Unix(1, 0))
	mkRoom(t, s, "!b", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!a", "$a1", "one", t0), t0.Add(10*time.Second)))
	require.NoError(t, s.Hold(ctx, held("!a", "$a2", "two", t0), t0.Add(11*time.Second)))
	require.NoError(t, s.Hold(ctx, held("!b", "$b1", "three", t0), t0.Add(10*time.Second)))

	evs, err := s.ClaimHeld(ctx, "!a")
	require.NoError(t, err)
	require.Equal(t, []string{"$a1", "$a2"}, idsOf(evs))
	for _, e := range evs {
		require.Equal(t, "pending", e.Status)
		requireNoSource(t, e.Content)
	}
	_, err = s.Unhold(ctx, "$a1")
	require.ErrorIs(t, err, ErrAlreadySent)
	e, _ := getEvent(t, s, "$b1")
	require.Equal(t, "queued", e.Status)

	evs, err = s.ClaimHeld(ctx, "")
	require.NoError(t, err)
	require.Equal(t, []string{"$b1"}, idsOf(evs))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM outbox"))
}

// Undo never leaves an auto-archive behind: a held message isn't my reply yet, so an after_reply rule counts it only
// once it is claimed for sending.
func TestHeldMessageSchedulesTheArchiveOnlyOnceSent(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), t0.Add(-time.Minute))

	require.NoError(t, s.Hold(ctx, held("!r", "$h", "undo me", t0), t0.Add(5*time.Second)))
	require.True(t, dueAt(t, s, "!r").IsZero(), "held: not a reply yet")
	_, err := s.Unhold(ctx, "$h")
	require.NoError(t, err)
	require.True(t, dueAt(t, s, "!r").IsZero(), "undone: nothing left behind")

	require.NoError(t, s.Hold(ctx, held("!r", "$h2", "send me", t0.Add(time.Second)), t0.Add(6*time.Second)))
	clock.set(t0.Add(6 * time.Second))
	require.Equal(t, []string{"$h2"}, claimDue(t, s))
	require.Equal(t, t0.Add(time.Second+10*time.Minute), dueAt(t, s, "!r"), "sent: the archive counts from the message")

	// A scheduled message is my reply when it goes.
	mkRoom(t, s, "!s", time.Unix(1, 0))
	schedule(t, s, "!s", "$s", "later", t0.Add(time.Hour), condAlways)
	clock.set(t0.Add(time.Hour))
	require.Equal(t, []string{"$s"}, claimDue(t, s))
	require.Equal(t, t0.Add(time.Hour+10*time.Minute), dueAt(t, s, "!s"))
}

// A missed message waits again only for a new time: an edit alone never sends it late.
func TestEditingAMissedMessageNeedsANewTime(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	sc := schedule(t, s, "!r", "$m", "late", t0.Add(time.Minute), condAlways)
	clock.set(t0.Add(2 * time.Hour))
	require.Empty(t, claimDue(t, s))
	require.Equal(t, stateMissed, scheduledStates(t, s, "!r")["$m"])

	_, err := s.UpdateScheduled(ctx, sc.ID, nil, "m.room.message", composed("edited"), nil)
	require.ErrorIs(t, err, ErrBadValue)
	always := condAlways
	_, err = s.UpdateScheduled(ctx, sc.ID, nil, "", nil, &always)
	require.ErrorIs(t, err, ErrBadValue)
	require.Empty(t, claimDue(t, s))
	require.Equal(t, stateMissed, scheduledStates(t, s, "!r")["$m"])

	due := t0.Add(3 * time.Hour)
	got, err := s.UpdateScheduled(ctx, sc.ID, &due, "m.room.message", composed("edited"), nil)
	require.NoError(t, err)
	require.Equal(t, stateWaiting, got.State)
}

// 4.1's "if no reply" reminder: a message held for undo send isn't my reply yet; Undo may still take it back.
func TestHeldMessageIsNotAReplyForReminders(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("question?"), t0.Add(-time.Minute))
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), condIfNoReply))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "answer", t0.Add(time.Minute)), t0.Add(2*time.Hour)))

	clock.set(t0.Add(time.Hour))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, fired)
}

// A claim takes a held message only while it is queued: one whose status changed some other way loses its row and
// isn't returned.
func TestClaimSkipsAMessageNoLongerQueued(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0))
	require.NoError(t, s.SetStatus(ctx, "$h", "failed", "refused"))

	require.Empty(t, claimDue(t, s))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM outbox"))
	e, _ := getEvent(t, s, "$h")
	require.Equal(t, "failed", e.Status)
	require.Equal(t, "refused", e.StatusReason)
}

// ScheduledByID reads one scheduled message by its outbox ID, in any state; a held message's row is not one.
func TestScheduledByIDReadsOne(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.SetClock(func() time.Time { return t0 })
	mkRoom(t, s, "!r", t0)
	sc, err := s.Schedule(ctx, Scheduled{
		RoomID: "!r", EventID: "$s", Type: "m.room.message", Content: composed("hello"), DueAt: t0.Add(time.Hour),
	})
	require.NoError(t, err)
	got, err := s.ScheduledByID(ctx, sc.ID)
	require.NoError(t, err)
	require.Equal(t, sc, got)

	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(time.Second)))
	_, err = s.ScheduledByID(ctx, sc.ID+1)
	require.ErrorIs(t, err, ErrNotFound, "a held message's row isn't a scheduled message")
	require.NoError(t, s.DeleteScheduled(ctx, sc.ID))
	_, err = s.ScheduledByID(ctx, sc.ID)
	require.ErrorIs(t, err, ErrNotFound)
}

func claimWaiting(t *testing.T, s *Store, network string, loginIDs ...string) []string {
	t.Helper()
	evs, err := s.ClaimWaiting(context.Background(), network, loginIDs)
	require.NoError(t, err)
	for _, e := range evs {
		require.Equal(t, "pending", e.Status, e.EventID)
		requireNoSource(t, e.Content)
	}
	return idsOf(evs)
}

func statusOf(t *testing.T, s *Store, id string) string {
	t.Helper()
	e, ok := getEvent(t, s, id)
	require.True(t, ok, id)
	return e.Status
}

// Review Focus 1: a message sent while the network is down waits, through a quit, is never "may have been sent" (it
// was never handed over), and is claimed exactly once when its login is back.
func TestWaitingMessageSurvivesReopenAndIsClaimedOnce(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), t0.Add(-time.Minute))
	ch, cancel := s.Subscribe()
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "on my way", t0)))
	require.Equal(t, Change{Kind: "event", RoomID: "!r", EventID: "$w", Seq: s.LastSeq()}, nextChange(t, ch))
	cancel()
	require.Equal(t, StatusWaiting, statusOf(t, s, "$w"))
	require.Equal(t, "$w", lastEventID(t, s, "!r"), "a waiting message is the chat's latest")
	require.Equal(t, []string{"$w"}, matches(t, s, `"way"`), "and searchable")
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM outbox WHERE kind='offline' AND event_id='$w'"))
	require.ErrorIs(t, s.Wait(ctx, held("!r", "$w", "again", t0)), ErrBadValue)
	require.ErrorIs(t, s.Wait(ctx, held("!unknown", "$x", "x", t0)), ErrNotFound)
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(3*time.Hour))
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n, "never handed over: not an interrupted send")
	require.Equal(t, StatusWaiting, statusOf(t, s, "$w"))
	require.Empty(t, claimDue(t, s))
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"))
	require.Equal(t, "pending", statusOf(t, s, "$w"))
	require.Zero(t, count(t, s, "SELECT count(*) FROM outbox"))
	require.Empty(t, claimWaiting(t, s, "whatsapp", "A"))
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(4*time.Hour))
	require.Empty(t, claimWaiting(t, s, "whatsapp", "A"))
	require.Empty(t, claimDue(t, s))
}

// Review Focus 1, Review Focus 5: a claim for the logins that are logged in takes their chats' waiting messages and
// the shared chats', oldest first, and leaves another login's and another network's waiting.
func TestClaimWaitingTakesOnlyTheLoggedInLoginsChats(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkChat(t, s, "!a", "whatsapp", "A", true, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!b", "whatsapp", "B", true, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!shared", "whatsapp", "", false, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!signal", "signal", "A", true, ghost, t0.Add(-time.Hour))
	for _, w := range []struct {
		room, id string
		at       time.Duration
	}{{"!a", "$a2", 4}, {"!shared", "$s1", 2}, {"!b", "$b1", 3}, {"!a", "$a1", 1}, {"!signal", "$o1", 1}} {
		require.NoError(t, s.Wait(ctx, held(w.room, w.id, "m", t0.Add(w.at*time.Second))))
	}
	require.Equal(t, []string{"$a1", "$s1", "$a2"}, claimWaiting(t, s, "whatsapp", "A"), "oldest first, by when each was written")
	require.Equal(t, StatusWaiting, statusOf(t, s, "$b1"))
	require.Equal(t, StatusWaiting, statusOf(t, s, "$o1"))
	require.Empty(t, claimWaiting(t, s, "whatsapp"), "no login is logged in: nothing goes")
	require.Equal(t, []string{"$b1"}, claimWaiting(t, s, "whatsapp", "A", "B"))
	require.Equal(t, []string{"$o1"}, claimWaiting(t, s, "signal", "A"))
}

// Ruling 12: SharedWaiting lists the shared chats with messages waiting, and a claim leaves the chats it is told to
// (shared chats none of whose own logins is in), whoever else is logged in.
func TestClaimWaitingLeavesTheSharedChatsItIsToldTo(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkChat(t, s, "!a", "whatsapp", "A", true, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!onlyB", "whatsapp", "", false, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!both", "whatsapp", "", false, ghost, t0.Add(-time.Hour))
	mkChat(t, s, "!signal", "signal", "", false, ghost, t0.Add(-time.Hour))
	for i, room := range []string{"!a", "!onlyB", "!both", "!onlyB", "!signal"} {
		require.NoError(t, s.Wait(ctx, held(room, fmt.Sprintf("$%d", i), "m", t0.Add(time.Duration(i)*time.Second))))
	}
	shared, err := s.SharedWaiting(ctx, "whatsapp")
	require.NoError(t, err)
	require.Equal(t, []string{"!both", "!onlyB"}, shared, "each once, this network's, shared ones only")

	evs, err := s.ClaimWaiting(ctx, "whatsapp", []string{"A"}, "!onlyB")
	require.NoError(t, err)
	require.Equal(t, []string{"$0", "$2"}, idsOf(evs))
	require.Equal(t, StatusWaiting, statusOf(t, s, "$1"))
	require.Equal(t, StatusWaiting, statusOf(t, s, "$3"))
	require.Equal(t, []string{"$1", "$3"}, claimWaiting(t, s, "whatsapp", "A"), "told nothing, it takes them")
	shared, err = s.SharedWaiting(ctx, "whatsapp")
	require.NoError(t, err)
	require.Empty(t, shared)
}

// A waiting message waits for its network, not the clock: no claim of the outbox takes it, however late it is.
func TestClaimDueLeavesWaitingAlone(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "m", t0)))
	waitingRow := "SELECT count(*) FROM outbox WHERE event_id='$w' AND kind='offline' AND state='waiting'"
	for _, at := range []time.Time{t0.Add(time.Second), t0.Add(2 * MaxLate)} { // due, then long overdue
		clock.set(at)
		require.Empty(t, claimDue(t, s))
		heldNow, err := s.ClaimHeld(ctx, "")
		require.NoError(t, err)
		require.Empty(t, heldNow)
		require.Equal(t, StatusWaiting, statusOf(t, s, "$w"), "never failed as not sent: there is no cut-off")
		require.Equal(t, 1, count(t, s, waitingRow), "its row is still waiting")
		_, ok, err := s.NextDue(ctx)
		require.NoError(t, err)
		require.False(t, ok, "nothing for the clock to wait for")
	}
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"), "it goes when the network is back")
}

// Don't Send: Undo takes a waiting message back as it takes a held one, content and all, until it is claimed.
func TestUndoTakesBackAWaitingMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), t0.Add(-time.Minute))
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "never mind", t0)))
	gone, err := s.Unhold(ctx, "$w")
	require.NoError(t, err)
	require.Equal(t, StatusWaiting, gone.Status)
	require.JSONEq(t, string(composed("never mind")), string(gone.Content), "what was typed comes back")
	_, ok := getEvent(t, s, "$w")
	require.False(t, ok)
	require.Zero(t, count(t, s, "SELECT count(*) FROM outbox"))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
	_, err = s.Unhold(ctx, "$w")
	require.ErrorIs(t, err, ErrAlreadySent)

	require.NoError(t, s.Wait(ctx, held("!r", "$w2", "m", t0)))
	require.Equal(t, []string{"$w2"}, claimWaiting(t, s, "whatsapp", "A"))
	_, err = s.Unhold(ctx, "$w2")
	require.ErrorIs(t, err, ErrAlreadySent, "claimed: on its way")
}

// A hand-off that finds the network down puts the message back to waiting, and it keeps its place: claims go by when
// each message was written, not by when it last went back (Ruling C3).
func TestWaitAgainPutsAPendingMessageBackToWaiting(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$1", "one", t0.Add(time.Second))))
	require.NoError(t, s.Wait(ctx, held("!r", "$2", "two", t0.Add(2*time.Second))))
	require.Equal(t, []string{"$1", "$2"}, claimWaiting(t, s, "whatsapp", "A"))
	ch, cancel := s.Subscribe()
	defer cancel()
	ok, err := s.WaitAgain(ctx, "$1")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "status", nextChange(t, ch).Kind)
	require.NoError(t, s.Wait(ctx, held("!r", "$3", "three", t0.Add(3*time.Second))))
	ok, err = s.WaitAgain(ctx, "$2")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, StatusWaiting, statusOf(t, s, "$1"))
	require.Equal(t, []string{"$1", "$2", "$3"}, claimWaiting(t, s, "whatsapp", "A"))

	// Only my pending message goes back.
	require.NoError(t, s.SetStatus(ctx, "$1", "sent", ""))
	mkMsg(t, s, "!r", "$theirs", ghost, "m.room.message", text("m"), t0.Add(4*time.Second))
	for _, id := range []string{"$1", "$theirs", "$nope"} {
		ok, err = s.WaitAgain(ctx, id)
		require.NoError(t, err)
		require.False(t, ok, id)
	}
	require.Equal(t, "sent", statusOf(t, s, "$1"))
}

// Ruling C2: a message from the waiting queue whose hand-off a quit cuts short goes back to waiting (WaitAgain, from
// the hand-off that claimed it), not to the undo outbox: at the next start, however late, it is still waiting, and
// goes once when its network is back. A held message cut short the same way still goes back through Requeue.
func TestWaitAgainAtQuitKeepsAClaimedWaitingMessageWaiting(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	s := reopen(t, path, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "waiting", t0)))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(5*time.Second)))
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"))
	s.SetClock(func() time.Time { return t0.Add(5 * time.Second) })
	require.Equal(t, []string{"$h"}, claimDue(t, s))
	ok, err := s.WaitAgain(ctx, "$w") // the quit cut both hand-offs short
	require.NoError(t, err)
	require.True(t, ok)
	ok, err = s.Requeue(ctx, "$h")
	require.NoError(t, err)
	require.True(t, ok)
	require.NoError(t, s.Close())

	s = reopen(t, path, t0.Add(2*time.Hour))
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n)
	require.Empty(t, claimDue(t, s), "the held message is over an hour late: failed, not sent")
	require.Equal(t, "failed", statusOf(t, s, "$h"))
	require.Equal(t, StatusWaiting, statusOf(t, s, "$w"), "the waiting one has no cut-off")
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"))
	require.Empty(t, claimWaiting(t, s, "whatsapp", "A"))
}

// A message deleted before it went is never handed over: Delete for Me takes a held or waiting message's outbox row
// with it, and a claim passes over a kept message that is deleted some other way (an unsend) whose row is still there.
func TestADeletedMessageIsNeverHandedOver(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "waiting", t0)))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(5*time.Second)))
	require.NoError(t, s.Hold(ctx, held("!r", "$h2", "held too", t0), t0.Add(5*time.Second)))
	for _, id := range []string{"$w", "$h", "$h2"} {
		require.NoError(t, s.SetDeletedForMe(ctx, id))
	}
	require.Zero(t, count(t, s, "SELECT count(*) FROM outbox"), "Delete for Me takes the rows with the messages")
	require.Empty(t, claimWaiting(t, s, "whatsapp", "A"))
	heldNow, err := s.ClaimHeld(ctx, "")
	require.NoError(t, err)
	require.Empty(t, heldNow)
	clock.set(t0.Add(time.Minute))
	require.Empty(t, claimDue(t, s))

	// Deleted another way, its row still there: the claim drops the row and hands over nothing.
	require.NoError(t, s.Wait(ctx, held("!r", "$w2", "waiting", t0.Add(time.Minute))))
	require.NoError(t, s.Hold(ctx, held("!r", "$h3", "held", t0.Add(time.Minute)), t0.Add(2*time.Minute)))
	for _, id := range []string{"$w2", "$h3"} {
		_, err := s.db.Exec(ctx, "UPDATE events SET redacted = 1 WHERE event_id = $1", id)
		require.NoError(t, err)
	}
	require.Empty(t, claimWaiting(t, s, "whatsapp", "A"))
	clock.set(t0.Add(3 * time.Minute))
	require.Empty(t, claimDue(t, s))
	require.Zero(t, count(t, s, "SELECT count(*) FROM outbox"))
	for _, id := range []string{"$w2", "$h3"} {
		require.NotEqual(t, "pending", statusOf(t, s, id), id)
	}
}

// Task 3's sends ask whether a chat has messages waiting, so a new one never overtakes them (Ruling C33).
func TestHasWaitingIsAboutOneChatsWaitingMessages(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	has := func(room string) bool {
		t.Helper()
		ok, err := s.HasWaiting(ctx, room)
		require.NoError(t, err)
		return ok
	}
	require.False(t, has("!r"))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(time.Second)))
	require.False(t, has("!r"), "a held message isn't waiting for its network")
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "waiting", t0)))
	require.True(t, has("!r"))
	require.False(t, has("!other"))
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"))
	require.False(t, has("!r"), "claimed: it is on its way")
}

// Retry of a failed message while its network is down waits like a new one: failed becomes waiting, with an offline
// row, and the next claim hands it over in its place (its own ts). Only a failed message of mine goes.
func TestWaitFailedMakesAFailedMessageWait(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$1", "one", t0.Add(time.Second))))
	require.Equal(t, []string{"$1"}, claimWaiting(t, s, "whatsapp", "A"))
	require.NoError(t, s.SetStatus(ctx, "$1", "failed", "network error"))
	require.NoError(t, s.Wait(ctx, held("!r", "$2", "two", t0.Add(2*time.Second))))

	ch, cancel := s.Subscribe()
	defer cancel()
	ok, err := s.WaitFailed(ctx, "$1")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "status", nextChange(t, ch).Kind)
	e, found, err := s.GetEvent(ctx, "$1")
	require.NoError(t, err)
	require.True(t, found)
	require.Equal(t, StatusWaiting, e.Status)
	require.Empty(t, e.StatusReason, "the old failure reason is gone")
	require.Equal(t, []string{"$1", "$2"}, claimWaiting(t, s, "whatsapp", "A"), "in its own place")

	mkMsg(t, s, "!r", "$theirs", ghost, "m.room.message", text("m"), t0.Add(4*time.Second))
	for _, id := range []string{"$1", "$theirs", "$nope"} { // $1 is pending now
		ok, err = s.WaitFailed(ctx, id)
		require.NoError(t, err)
		require.False(t, ok, id)
	}
	require.Equal(t, "pending", statusOf(t, s, "$1"))
}

// A pending message deleted for me while its hand-off ran is not brought back: WaitAgain and Requeue leave it alone,
// so it never shows as waiting or queued again, and is never handed over.
func TestWaitAgainAndRequeueLeaveADeletedMessageAlone(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.Wait(ctx, held("!r", "$w", "waiting", t0)))
	require.NoError(t, s.Hold(ctx, held("!r", "$h", "held", t0), t0.Add(time.Second)))
	require.Equal(t, []string{"$w"}, claimWaiting(t, s, "whatsapp", "A"))
	clock.set(t0.Add(time.Second))
	require.Equal(t, []string{"$h"}, claimDue(t, s))
	for _, id := range []string{"$w", "$h"} {
		require.NoError(t, s.SetDeletedForMe(ctx, id))
	}
	ok, err := s.WaitAgain(ctx, "$w")
	require.NoError(t, err)
	require.False(t, ok)
	ok, err = s.Requeue(ctx, "$h")
	require.NoError(t, err)
	require.False(t, ok)
	require.Zero(t, count(t, s, "SELECT count(*) FROM outbox"))
	require.Equal(t, "pending", statusOf(t, s, "$w"))
	require.Equal(t, "pending", statusOf(t, s, "$h"))
}
