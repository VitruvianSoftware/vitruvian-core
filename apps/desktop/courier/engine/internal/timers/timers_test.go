// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package timers

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

const (
	ghost = "@ghost:courier.local"
	day   = 24 * time.Hour
)

// guard bounds how long a test waits for the loop to do something. It only stops a broken test from hanging: no
// test asserts how long anything took.
const guard = 10 * time.Second

// fakeClock is the loop's clock. The wall clock (Now) and the timers (After) are separate, as on a Mac that
// sleeps: jump moves the wall clock without firing a timer, fire fires the timers without moving the wall clock,
// and advance does both. Every After call is reported on slept, so a test can wait for the loop to go to sleep.
type fakeClock struct {
	mu      sync.Mutex
	now     time.Time
	waiters []waiter
	slept   chan time.Duration
}

type waiter struct {
	at time.Time
	ch chan time.Time
}

func newFakeClock(t time.Time) *fakeClock {
	return &fakeClock{now: t, slept: make(chan time.Duration, 1024)}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) After(d time.Duration) <-chan time.Time {
	c.mu.Lock()
	ch := make(chan time.Time, 1)
	c.waiters = append(c.waiters, waiter{at: c.now.Add(d), ch: ch})
	c.mu.Unlock()
	c.slept <- d
	return ch
}

// jump moves the wall clock only: the Mac slept, and its timers didn't count.
func (c *fakeClock) jump(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	c.mu.Unlock()
}

// fire fires every pending timer, whatever its time.
func (c *fakeClock) fire() {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, w := range c.waiters {
		w.ch <- c.now
	}
	c.waiters = nil
}

// advance moves the wall clock and fires the timers that are due by then.
func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
	kept := c.waiters[:0]
	for _, w := range c.waiters {
		if w.at.After(c.now) {
			kept = append(kept, w)
			continue
		}
		w.ch <- c.now
	}
	c.waiters = kept
}

// awaitSleep waits for the loop's next sleep and returns how long it asked for.
func (c *fakeClock) awaitSleep(t *testing.T) time.Duration {
	t.Helper()
	select {
	case d := <-c.slept:
		return d
	case <-time.After(guard):
		t.Fatal("the loop never went to sleep")
		return 0
	}
}

// settle waits until the loop has gone to sleep and nothing has woken it again: it takes every sleep reported
// and returns the last.
func (c *fakeClock) settle(t *testing.T) time.Duration {
	t.Helper()
	d := c.awaitSleep(t)
	for {
		select {
		case d = <-c.slept:
		case <-time.After(20 * time.Millisecond):
			return d
		}
	}
}

// switchable is a Provider whose answer the test sets.
type switchable struct{ yes atomic.Bool }

func (p *switchable) Allowed(entitlement.Feature) bool { return p.yes.Load() }

type rig struct {
	s     *store.Store
	clock *fakeClock
	t     *Timers
	stop  func()
}

func newRig(t *testing.T, start time.Time, ent entitlement.Provider) *rig {
	t.Helper()
	return newRigAt(t, filepath.Join(t.TempDir(), "courier.db"), start, ent)
}

// newRigAt is newRig on the database at path, so a test can stop the loop, close the store and start again on the
// same courier.db, as Courier quitting and opening does.
func newRigAt(t *testing.T, path string, start time.Time, ent entitlement.Provider) *rig {
	t.Helper()
	s, err := store.Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	clock := newFakeClock(start)
	s.SetClock(clock.Now)
	return &rig{s: s, clock: clock, t: New(s, ent, clock, zerolog.Nop())}
}

// run starts the loop; it is stopped, and waited for, when the test ends.
func (r *rig) run(t *testing.T) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		r.t.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(guard):
			t.Error("Run didn't return after its context ended")
		}
	})
}

func (r *rig) chat(t *testing.T, id string, ts time.Time) {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, r.s.UpsertRoom(ctx, store.Room{ID: id, Network: "whatsapp", Name: id, IsDirect: true, CreatedAt: time.Unix(1, 0)}))
	body, _ := json.Marshal(map[string]string{"msgtype": "m.text", "body": "hello"})
	_, err := r.s.InsertEvent(ctx, store.Event{RoomID: id, EventID: "$" + id, Sender: ghost, Type: "m.room.message", Content: body, TS: ts})
	require.NoError(t, err)
}

func (r *rig) row(t *testing.T, id string) store.InboxRow {
	t.Helper()
	rows, _, err := r.s.InboxPage(context.Background(), store.InboxQuery{RoomIDs: []string{id}})
	require.NoError(t, err)
	require.Len(t, rows, 1)
	return rows[0]
}

func fired(t *testing.T, r *rig, id string) bool {
	t.Helper()
	rem := r.row(t, id).Reminder
	return rem != nil && !rem.FiredAt.IsZero()
}

// awaitChange waits for a change of kind for roomID on ch.
func awaitChange(t *testing.T, ch <-chan store.Change, kind, roomID string) {
	t.Helper()
	timeout := time.After(guard)
	for {
		select {
		case c := <-ch:
			if c.Kind == kind && c.RoomID == roomID {
				return
			}
		case <-timeout:
			t.Fatalf("no %s change for %s", kind, roomID)
		}
	}
}

// Review Focus 2: Go timers can stop counting while a Mac sleeps, so the loop never sleeps longer than 30 s and
// looks at the wall clock each time it wakes.
func TestLoopNeverSleepsLongerThan30s(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.SetReminder(context.Background(), []string{"!r"}, t0.Add(2*time.Hour), "always"))
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)

	require.Equal(t, MaxSleep, r.clock.awaitSleep(t), "a reminder two hours away is still checked on every 30 s")
	for range 5 {
		r.clock.advance(MaxSleep)
		require.LessOrEqual(t, r.clock.awaitSleep(t), MaxSleep)
	}
	require.False(t, fired(t, r, "!r"))

	// The Mac sleeps through the due time: the wall clock moves three hours, and the loop's timer wakes it as if
	// only its 30 s had passed. It looks at the wall clock and fires the reminder, once.
	r.clock.jump(3 * time.Hour)
	r.clock.fire()
	awaitChange(t, ch, "reminder", "!r")
	require.True(t, fired(t, r, "!r"))
	require.LessOrEqual(t, r.clock.settle(t), MaxSleep)
	for range 3 {
		r.clock.advance(MaxSleep)
		require.LessOrEqual(t, r.clock.awaitSleep(t), MaxSleep)
	}
	for {
		select {
		case c := <-ch:
			require.NotEqual(t, "reminder", c.Kind, "it fired twice")
			continue
		default:
		}
		break
	}
}

func TestPokeRearmsForAnEarlierReminder(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	ctx := context.Background()
	r.chat(t, "!late", t0.Add(-time.Hour))
	r.chat(t, "!soon", t0.Add(-time.Hour))
	require.NoError(t, r.s.SetReminder(ctx, []string{"!late"}, t0.Add(20*time.Second), "always"))
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)
	require.Equal(t, 20*time.Second, r.clock.settle(t), "it sleeps until the reminder is due")

	require.NoError(t, r.s.SetReminder(ctx, []string{"!soon"}, t0.Add(5*time.Second), "always"))
	r.t.Poke()
	require.Equal(t, 5*time.Second, r.clock.settle(t), "a poke re-arms for the earlier one")
	r.clock.advance(5 * time.Second)
	awaitChange(t, ch, "reminder", "!soon")
	require.False(t, fired(t, r, "!late"))
	require.Equal(t, 15*time.Second, r.clock.settle(t))
}

func TestRemindersWaitWhileNotEntitled(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	ent := &switchable{}
	r := newRig(t, t0, ent)
	ctx := context.Background()
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Minute), "always"))
	_, err := r.s.SetRule(ctx, store.Rule{Scope: "all", Trigger: "older_than", ChatType: "all", Duration: 3 * day, Enabled: true})
	require.NoError(t, err)
	r.chat(t, "!old", t0.Add(-10*day))
	r.clock.jump(2 * time.Minute) // the reminder is overdue
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)

	require.Equal(t, MaxSleep, r.clock.settle(t), "an overdue reminder it may not fire doesn't make it spin")
	r.clock.advance(MaxSleep)
	require.Equal(t, MaxSleep, r.clock.settle(t))
	require.False(t, fired(t, r, "!r"), "denied: the reminder waits, untouched")
	require.False(t, r.row(t, "!old").Archived, "denied: no sweep")
	require.False(t, r.row(t, "!r").MarkedUnread)

	ent.yes.Store(true)
	r.t.Poke()
	awaitChange(t, ch, "reminder", "!r")
	r.clock.settle(t)
	require.True(t, fired(t, r, "!r"), "allowed again: it fires")
	require.True(t, r.row(t, "!old").Archived, "and the sweep runs")
}

func TestSweepRunsAtStartAndEvery15Minutes(t *testing.T) {
	t0 := time.UnixMilli(10_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	ctx := context.Background()
	_, err := r.s.SetRule(ctx, store.Rule{Scope: "all", Trigger: "older_than", ChatType: "all", Duration: 3 * day, Enabled: true})
	require.NoError(t, err)
	r.chat(t, "!old", t0.Add(-4*day))
	r.chat(t, "!soon", t0.Add(-3*day+10*time.Minute)) // three days old ten minutes from now
	r.run(t)

	r.clock.settle(t)
	require.True(t, r.row(t, "!old").Archived, "swept at start")
	require.False(t, r.row(t, "!soon").Archived)

	// Every wake-up before the 15 minutes are up leaves !soon alone, even once it is old enough.
	for elapsed := time.Duration(0); elapsed < SweepEvery-MaxSleep; {
		d := r.clock.Now().Sub(t0)
		require.Less(t, d, SweepEvery)
		r.clock.advance(MaxSleep)
		elapsed += MaxSleep
		r.clock.settle(t)
		require.False(t, r.row(t, "!soon").Archived, "no sweep at %v", elapsed)
	}
	r.clock.advance(MaxSleep)
	r.clock.settle(t)
	require.Equal(t, SweepEvery, r.clock.Now().Sub(t0))
	require.True(t, r.row(t, "!soon").Archived, "swept again at 15 minutes")
}

func TestScheduledArchiveWakesTheLoop(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	ctx := context.Background()
	_, err := r.s.SetRule(ctx, store.Rule{Scope: "all", Trigger: "after_read", ChatType: "all", Duration: 0, Enabled: true})
	require.NoError(t, err)
	r.chat(t, "!r", t0.Add(-time.Hour))
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)
	r.clock.settle(t)

	// Reading the chat with "0 min" archives it straight away, without waiting out the loop's 30 s.
	require.NoError(t, r.s.MarkReadLocal(ctx, "!r", "$!r", t0.Add(-time.Hour)))
	awaitChange(t, ch, "room", "!r")
	r.clock.settle(t)
	require.True(t, r.row(t, "!r").Archived)
}

// start runs the loop until the returned stop is called or the test ends; stop waits for Run to return.
func (r *rig) start(t *testing.T) (stop func()) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		r.t.Run(ctx)
	}()
	var once sync.Once
	stop = func() {
		once.Do(func() {
			cancel()
			select {
			case <-done:
			case <-time.After(guard):
				t.Error("Run didn't return after its context ended")
			}
		})
	}
	t.Cleanup(stop)
	return stop
}

// recorder is the loop's dispatcher in tests: it records each message handed to it, and sends its ID on seen.
type recorder struct {
	mu   sync.Mutex
	got  []string
	seen chan string
}

func newRecorder() *recorder { return &recorder{seen: make(chan string, 64)} }

func (d *recorder) HandOff(_ context.Context, e store.Event) {
	d.mu.Lock()
	d.got = append(d.got, e.EventID)
	d.mu.Unlock()
	d.seen <- e.EventID
}

// The recorder has no networks, so it has no waiting messages to send.
func (d *recorder) Networks() []string                  { return nil }
func (d *recorder) SendWaiting(context.Context, string) {}

func (d *recorder) handedOff() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return append([]string{}, d.got...)
}

// await waits for id to be handed off.
func (d *recorder) await(t *testing.T, id string) {
	t.Helper()
	timeout := time.After(guard)
	for {
		select {
		case got := <-d.seen:
			if got == id {
				return
			}
		case <-timeout:
			t.Fatalf("%s was never handed off; handed off: %v", id, d.handedOff())
		}
	}
}

// heldMessage is my new message id in roomID, as the composer hands it to Hold.
func heldMessage(roomID, id string, ts time.Time) store.Event {
	return store.Event{
		RoomID: roomID, EventID: id, Sender: string(ids.Me), Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"held"}`), TS: ts,
	}
}

func (r *rig) status(t *testing.T, id string) [2]string {
	t.Helper()
	e, ok, err := r.s.GetEvent(context.Background(), id)
	require.NoError(t, err)
	require.True(t, ok, id)
	return [2]string{e.Status, e.StatusReason}
}

// disappearing inserts their message id in roomID, sent at ts, that disappears after ttl.
func (r *rig) disappearing(t *testing.T, roomID, id, body string, ts time.Time, ttl time.Duration) {
	t.Helper()
	content, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": body,
		"com.beeper.disappearing_timer": map[string]any{"type": "after_send", "timer": ttl.Milliseconds()},
	})
	_, err := r.s.InsertEvent(context.Background(), store.Event{RoomID: roomID, EventID: id, Sender: ghost, Type: "m.room.message", Content: content, TS: ts})
	require.NoError(t, err)
}

// Undo send: a poke at Hold re-arms the loop for the window's end, so a 750 ms hold is handed off when the clock
// reaches it, not at the next 30 s wake, and not a millisecond before.
func TestHeldMessageHandedOffAtItsTime(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	d := newRecorder()
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	r.run(t)
	require.Equal(t, MaxSleep, r.clock.settle(t))

	due := t0.Add(750 * time.Millisecond)
	require.NoError(t, r.s.Hold(context.Background(), heldMessage("!r", "$h", t0), due))
	r.t.Poke()
	require.Equal(t, 750*time.Millisecond, r.clock.settle(t), "the poke re-arms for the window's end")

	r.clock.advance(749 * time.Millisecond)
	r.t.Poke() // a pass at due − 1 ms
	require.Equal(t, time.Millisecond, r.clock.settle(t))
	require.Empty(t, d.handedOff(), "not before its time")
	require.Equal(t, [2]string{"queued", ""}, r.status(t, "$h"))

	r.clock.advance(time.Millisecond)
	d.await(t, "$h")
	r.clock.settle(t)
	require.Equal(t, []string{"$h"}, d.handedOff())
	require.Equal(t, [2]string{"pending", ""}, r.status(t, "$h"))
}

// Review Focus 2: quitting during the window loses nothing. The held message is still there at the next start and,
// less than MaxLate late, it is handed off once; a start after that hands off nothing.
func TestHeldMessageSentAfterRestartOnce(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	t0 := time.UnixMilli(1_000_000_000)
	due := t0.Add(5 * time.Second)

	r := newRigAt(t, path, t0, entitlement.Always{})
	d := newRecorder()
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	stop := r.start(t)
	r.clock.settle(t)
	require.NoError(t, r.s.Hold(ctx, heldMessage("!r", "$h", t0), due))
	r.t.Poke()
	require.Equal(t, 5*time.Second, r.clock.settle(t))
	r.clock.advance(4 * time.Second)
	stop() // Courier quits a second before the window ends
	require.Empty(t, d.handedOff())
	require.NoError(t, r.s.Close())

	// Courier opens again 10 s after the window ended: the engine fails interrupted sends first (main.go), which
	// leaves a held message alone, and the loop hands it off once.
	r = newRigAt(t, path, due.Add(10*time.Second), entitlement.Always{})
	n, err := r.s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n)
	d = newRecorder()
	r.t.SetDispatcher(d)
	stop = r.start(t)
	d.await(t, "$h")
	r.clock.settle(t)
	r.clock.advance(MaxSleep)
	r.clock.settle(t)
	stop()
	require.Equal(t, []string{"$h"}, d.handedOff())
	require.NoError(t, r.s.SetStatus(ctx, "$h", "sent", "")) // the bridge's report
	require.NoError(t, r.s.Close())

	// And again: nothing is handed off a second time.
	r = newRigAt(t, path, due.Add(time.Minute), entitlement.Always{})
	n, err = r.s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.Zero(t, n)
	d = newRecorder()
	r.t.SetDispatcher(d)
	r.run(t)
	r.clock.settle(t)
	r.clock.advance(MaxSleep)
	r.clock.settle(t)
	require.Empty(t, d.handedOff())
	require.Equal(t, [2]string{"sent", ""}, r.status(t, "$h"))
}

// Review Focus 2: a held message whose window ended more than MaxLate before the engine could send it is never sent
// by itself: it becomes failed "not sent", for the person to Retry or Delete.
func TestHeldMessageTooLateBecomesNotSent(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	t0 := time.UnixMilli(1_000_000_000)
	due := t0.Add(5 * time.Second)
	r := newRigAt(t, path, t0, entitlement.Always{})
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.Hold(ctx, heldMessage("!r", "$h", t0), due))
	require.NoError(t, r.s.Close()) // Courier quits during the window

	r = newRigAt(t, path, due.Add(2*time.Hour), entitlement.Always{})
	_, err := r.s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	d := newRecorder()
	r.t.SetDispatcher(d)
	r.run(t)
	r.clock.settle(t)
	require.Empty(t, d.handedOff())
	require.Equal(t, [2]string{"failed", store.ReasonNotSent}, r.status(t, "$h"))
}

// Review Focus 3: the Mac sleeps through a scheduled message's time. The loop's timer wakes it as if only its 30 s
// had passed, while the wall clock is 20 minutes past due: it looks at the wall clock and sends it, once.
func TestLoopFiresScheduledOnceAfterSleep(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	d := newRecorder()
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	_, err := r.s.Schedule(context.Background(), store.Scheduled{
		RoomID: "!r", EventID: "$s", Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"later"}`),
		DueAt: t0.Add(10 * time.Minute), Condition: "always",
	})
	require.NoError(t, err)
	r.run(t)
	require.Equal(t, MaxSleep, r.clock.settle(t))

	r.clock.jump(30 * time.Minute)
	r.clock.fire()
	d.await(t, "$s")
	r.clock.settle(t)
	for range 3 {
		r.clock.advance(MaxSleep)
		r.clock.settle(t)
	}
	require.Equal(t, []string{"$s"}, d.handedOff())
	require.Equal(t, [2]string{"pending", ""}, r.status(t, "$s"))
}

// Review Focus 5: the Mac sleeps through a disappearing message's time. When the loop wakes it is gone from the chat
// and its preview, though the bridge's own loop is still asleep. No dispatcher is needed for that.
func TestLoopExpiresAfterSleep(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	r.chat(t, "!r", t0.Add(-time.Hour))
	r.disappearing(t, "!r", "$d", "gone soon", t0, time.Hour)
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)
	require.Equal(t, MaxSleep, r.clock.settle(t))
	require.Equal(t, "gone soon", r.row(t, "!r").Preview)

	r.clock.jump(3 * time.Hour)
	r.clock.fire()
	awaitChange(t, ch, "room", "!r")
	gone, err := r.s.Redacted(context.Background(), "$d")
	require.NoError(t, err)
	require.True(t, gone)
	require.Equal(t, "hello", r.row(t, "!r").Preview, "the preview goes back to the message before")
	require.Equal(t, MaxSleep, r.clock.settle(t), "nothing left due: it doesn't spin")
}

// A lapsed plan never strands a message: the outbox and the disappearing timers run whatever the entitlements say.
// A reminder left overdue because reminders aren't allowed doesn't hide them either: the loop still wakes at the
// hold's time, not at the next 30 s wake.
func TestOutboxFiresWhileNotEntitled(t *testing.T) {
	ctx := context.Background()
	start := time.UnixMilli(1_000_000_000)
	r := newRig(t, start, &switchable{}) // nothing allowed
	d := newRecorder()
	r.t.SetDispatcher(d)
	r.chat(t, "!r", start.Add(-time.Hour))
	require.NoError(t, r.s.SetReminder(ctx, []string{"!r"}, start.Add(time.Minute), "always"))
	r.clock.jump(2 * time.Minute) // the reminder is overdue, and may not fire
	t0 := r.clock.Now()
	require.NoError(t, r.s.Hold(ctx, heldMessage("!r", "$h", t0), t0.Add(time.Second)))
	_, err := r.s.Schedule(ctx, store.Scheduled{
		RoomID: "!r", EventID: "$s", Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"later"}`),
		DueAt: t0.Add(2 * time.Second), Condition: "always",
	})
	require.NoError(t, err)
	r.disappearing(t, "!r", "$d", "gone soon", t0, 3*time.Second)
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)
	require.Equal(t, time.Second, r.clock.settle(t), "the overdue reminder doesn't hide the hold")

	r.clock.advance(time.Second)
	d.await(t, "$h")
	r.clock.settle(t)
	r.clock.advance(time.Second)
	d.await(t, "$s")
	r.clock.settle(t)
	r.clock.advance(time.Second)
	awaitChange(t, ch, "room", "!r")
	r.clock.settle(t)
	require.Equal(t, []string{"$h", "$s"}, d.handedOff())
	gone, err := r.s.Redacted(ctx, "$d")
	require.NoError(t, err)
	require.True(t, gone)
	require.False(t, fired(t, r, "!r"), "the reminder still waits")
}

// syncBuffer is a log sink safe to write from the hand-off goroutines.
type syncBuffer struct {
	mu sync.Mutex
	b  strings.Builder
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.String()
}

// logging is a dispatcher that warns through the logger its context carries, as HandOff does.
type logging struct{ *recorder }

func (d logging) HandOff(ctx context.Context, e store.Event) {
	zerolog.Ctx(ctx).Warn().Msg("hand-off warning")
	d.recorder.HandOff(ctx, e)
}

// A hand-off's warnings reach the engine's log: the loop gives HandOff a context that carries its logger.
func TestHandOffLogsToTheLoopsLog(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	var out syncBuffer
	r.t = New(r.s, entitlement.Always{}, r.clock, zerolog.New(&out))
	d := logging{newRecorder()}
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.Hold(context.Background(), heldMessage("!r", "$h", t0), t0))
	r.run(t)
	d.await(t, "$h")
	require.Contains(t, out.String(), "hand-off warning")
}

// Without a dispatcher the loop claims nothing: a due held message stays held, for a loop that can send it.
func TestNoDispatcherClaimsNothing(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.Hold(context.Background(), heldMessage("!r", "$h", t0), t0))
	r.run(t)
	require.Equal(t, MaxSleep, r.clock.settle(t), "a due message it may not claim doesn't make it spin")
	require.Equal(t, [2]string{"queued", ""}, r.status(t, "$h"))
}

// gated is a dispatcher whose hand-offs wait until release closes.
type gated struct {
	started  chan string
	release  chan struct{}
	returned atomic.Bool
}

func (g *gated) Networks() []string                  { return nil }
func (g *gated) SendWaiting(context.Context, string) {}

func (g *gated) HandOff(_ context.Context, e store.Event) {
	g.started <- e.EventID
	<-g.release
	g.returned.Store(true)
}

// Run waits for the hand-offs it started before it returns, so the engine never closes the store or stops the
// bridges under one.
func TestRunWaitsForHandOffs(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	g := &gated{started: make(chan string, 1), release: make(chan struct{})}
	r.t.SetDispatcher(g)
	r.chat(t, "!r", t0.Add(-time.Hour))
	require.NoError(t, r.s.Hold(context.Background(), heldMessage("!r", "$h", t0), t0))

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		r.t.Run(ctx)
	}()
	select {
	case <-g.started:
	case <-time.After(guard):
		t.Fatal("nothing was handed off")
	}
	cancel()
	// A quiet window, as settle's: Run must not return while the hand-off is still running. No duration is asserted.
	select {
	case <-done:
		t.Fatal("Run returned while a hand-off was still running")
	case <-time.After(20 * time.Millisecond):
	}
	close(g.release)
	select {
	case <-done:
	case <-time.After(guard):
		t.Fatal("Run didn't return once the hand-off did")
	}
	require.True(t, g.returned.Load())
}

// waitingSender is a dispatcher whose SendWaiting hands over, for each network it lists, the waiting messages of the
// logins the test says are logged in (store.ClaimWaiting), and marks them sent. Each run is reported on runs; while
// the test holds them (hold), each run waits after its claim until it lets go.
type waitingSender struct {
	s        *store.Store
	networks []string
	mu       sync.Mutex
	loggedIn []string
	runs     chan string
	gate     chan struct{} // guarded by mu
	running  atomic.Int32
	most     atomic.Int32 // the most runs in flight at once
}

func newWaitingSender(s *store.Store, networks ...string) *waitingSender {
	return &waitingSender{s: s, networks: networks, runs: make(chan string, 64)}
}

func (d *waitingSender) HandOff(context.Context, store.Event) {}
func (d *waitingSender) Networks() []string                   { return d.networks }

func (d *waitingSender) logIn(ids ...string) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.loggedIn = ids
}

func (d *waitingSender) SendWaiting(ctx context.Context, network string) {
	n := d.running.Add(1)
	defer d.running.Add(-1)
	for {
		most := d.most.Load()
		if n <= most || d.most.CompareAndSwap(most, n) {
			break
		}
	}
	d.mu.Lock()
	logins, gate := append([]string(nil), d.loggedIn...), d.gate
	d.mu.Unlock()
	claimed, err := d.s.ClaimWaiting(ctx, network, logins)
	if err == nil {
		for _, e := range claimed {
			_ = d.s.SetStatus(context.WithoutCancel(ctx), e.EventID, "sent", "")
		}
	}
	if gate != nil {
		<-gate
	}
	d.runs <- network
}

// hold makes the runs from now on wait, after their claim, until the returned release is called.
func (d *waitingSender) hold() (release func()) {
	gate := make(chan struct{})
	d.mu.Lock()
	d.gate = gate
	d.mu.Unlock()
	return func() {
		d.mu.Lock()
		d.gate = nil
		d.mu.Unlock()
		close(gate)
	}
}

// awaitRun waits for a SendWaiting run for network to finish.
func (d *waitingSender) awaitRun(t *testing.T, network string) {
	t.Helper()
	timeout := time.After(guard)
	for {
		select {
		case got := <-d.runs:
			if got == network {
				return
			}
		case <-timeout:
			t.Fatalf("SendWaiting never ran for %s", network)
		}
	}
}

// waitingMessage is my message id in roomID, waiting for its network.
func (r *rig) waitingMessage(t *testing.T, roomID, id string, ts time.Time) {
	t.Helper()
	require.NoError(t, r.s.Wait(context.Background(), heldMessage(roomID, id, ts)))
}

// Review Focus 1: a login's bridge state coming in (a "bridge" change) wakes the loop at once, without its clock,
// and the pass sends the messages waiting for that network.
func TestBridgeConnectWakesTheLoopAndSendsWaiting(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	d := newWaitingSender(r.s, "whatsapp")
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	r.waitingMessage(t, "!r", "$w", t0)
	r.run(t)
	d.awaitRun(t, "whatsapp")
	require.Equal(t, MaxSleep, r.clock.settle(t), "a waiting message doesn't make the loop spin")
	require.Equal(t, [2]string{store.StatusWaiting, ""}, r.status(t, "$w"))

	d.logIn("A")
	r.s.NetworkChanged("whatsapp") // the login's CONNECTED, as the bridge reports it
	d.awaitRun(t, "whatsapp")
	require.Equal(t, [2]string{"sent", ""}, r.status(t, "$w"))
}

// While every login is down, a pass claims nothing and changes nothing: no "status" change at all across passes, so
// the app's rows don't flicker every 30 s.
func TestWaitingClaimsNothingWhileEveryLoginIsDown(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	d := newWaitingSender(r.s, "whatsapp")
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	r.waitingMessage(t, "!r", "$w", t0)
	ch, cancel := r.s.Subscribe()
	defer cancel()
	r.run(t)
	for range 3 {
		d.awaitRun(t, "whatsapp")
		r.clock.settle(t)
		r.clock.fire() // the next pass
	}
	d.awaitRun(t, "whatsapp")
	for {
		select {
		case c := <-ch:
			require.NotEqual(t, "status", c.Kind, "a pass changed a message: %+v", c)
			continue
		default:
		}
		break
	}
	require.Equal(t, [2]string{store.StatusWaiting, ""}, r.status(t, "$w"))
}

// Ruling C35: the loop owns the SendWaiting runs. Never two at once for one network: a pass that finds one running
// asks it to go again once it is done, so a message that came in meanwhile goes then, not at the next wake. And Run
// waits for a run in flight before it returns, so none outlives the store.
func TestSendWaitingRunsOnceAtATimePerNetworkAndRunWaitsForIt(t *testing.T) {
	t0 := time.UnixMilli(1_000_000_000)
	r := newRig(t, t0, entitlement.Always{})
	d := newWaitingSender(r.s, "whatsapp")
	release := d.hold()
	r.t.SetDispatcher(d)
	r.chat(t, "!r", t0.Add(-time.Hour))
	ctx, stop := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		r.t.Run(ctx)
	}()
	defer func() {
		stop()
		<-done
	}()
	require.Eventually(t, func() bool { return d.running.Load() == 1 }, guard, time.Millisecond, "the first run")
	d.logIn("A")
	r.waitingMessage(t, "!r", "$w", t0) // a new event pokes the loop while the first run is held
	r.t.Poke()
	r.clock.settle(t)
	require.EqualValues(t, 1, d.running.Load(), "never a second run for the same network")
	require.Equal(t, [2]string{store.StatusWaiting, ""}, r.status(t, "$w"), "the first run claimed before it came")

	release()
	d.awaitRun(t, "whatsapp")
	d.awaitRun(t, "whatsapp") // the run asked for again
	require.Equal(t, [2]string{"sent", ""}, r.status(t, "$w"))
	require.EqualValues(t, 1, d.most.Load())

	// Run waits for a run in flight.
	release = d.hold()
	r.t.Poke()
	require.Eventually(t, func() bool { return d.running.Load() == 1 }, guard, time.Millisecond, "a held run")
	stop()
	select {
	case <-done:
		t.Fatal("Run returned while a SendWaiting run was in flight")
	case <-time.After(20 * time.Millisecond): // a quiet window, as settle's: no duration is asserted
	}
	release()
	select {
	case <-done:
	case <-time.After(guard):
		t.Fatal("Run didn't return once the run did")
	}
}
