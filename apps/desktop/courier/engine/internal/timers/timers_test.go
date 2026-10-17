// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package timers

import (
	"context"
	"encoding/json"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
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
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
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
