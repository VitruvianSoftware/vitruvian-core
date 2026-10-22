// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package timers is the engine's one timer loop: it fires reminders, carries out auto-archive rules, sends held and
// scheduled messages (the outbox) and deletes disappearing messages when they come due. Everything it waits for is in
// courier.db, so nothing is lost when the engine stops: what came due while Courier was quit, or the Mac slept,
// happens once at the next chance.
package timers

import (
	"context"
	"sync"
	"time"

	"github.com/rs/zerolog"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// MaxSleep is the longest the loop sleeps. Go's timers can stop counting while a Mac sleeps, so a long sleep could
// wake far past its time; the loop instead wakes at least this often and looks at the wall clock (Review Focus 2).
const MaxSleep = 30 * time.Second

// SweepEvery is how often the older_than rules are run.
const SweepEvery = 15 * time.Minute

// Clock is the loop's wall clock and its timers.
type Clock interface {
	Now() time.Time
	After(time.Duration) <-chan time.Time
}

// RealClock is the system clock.
type RealClock struct{}

// Now is time.Now.
func (RealClock) Now() time.Time { return time.Now() }

// After is time.After.
func (RealClock) After(d time.Duration) <-chan time.Time { return time.After(d) }

// Dispatcher hands a message of mine that store.ClaimDue made pending to its network: *actions.Actions. HandOff
// returns once the network has the message or it is marked failed; it never sends one twice, because each claim
// returns a message at most once.
type Dispatcher interface {
	HandOff(ctx context.Context, e store.Event)
}

// Timers runs reminders, auto-archive rules, the outbox and disappearing timers over a store.
type Timers struct {
	s     *store.Store
	ent   entitlement.Provider
	clock Clock
	log   zerolog.Logger
	poke  chan struct{}

	d        Dispatcher     // nil: the outbox isn't claimed
	handOffs sync.WaitGroup // hand-offs in flight; Run waits for them
}

// New makes the loop. Run starts it. The store's own clock should agree with clock (in the engine both are the
// system clock).
func New(s *store.Store, ent entitlement.Provider, clock Clock, log zerolog.Logger) *Timers {
	return &Timers{s: s, ent: ent, clock: clock, log: log, poke: make(chan struct{}, 1)}
}

// SetDispatcher sets what the loop hands claimed outbox messages to. Call it before Run. Without one (nil) the loop
// claims nothing: held and scheduled messages wait, untouched, for a loop that can send them.
func (t *Timers) SetDispatcher(d Dispatcher) { t.d = d }

// Poke tells the loop that a reminder, a rule or the outbox changed (the rpc layer pokes it after Hold, Schedule and
// UpdateScheduled), so it looks again now instead of when it next wakes: a 750 ms hold is handed off at its time, not
// at the next MaxSleep wake. It never blocks; pokes that arrive together are one.
func (t *Timers) Poke() {
	select {
	case t.poke <- struct{}{}:
	default:
	}
}

// Run runs the loop until ctx ends, then waits for the hand-offs it started. Each time it wakes it does what is due:
//   - it deletes the messages whose disappearing timer has run out (store.ExpireDue);
//   - with a dispatcher, it claims the due outbox messages (store.ClaimDue, which applies MaxLate) and hands each to
//     the dispatcher on its own goroutine, so one waiting on a network never holds up the loop;
//   - when reminders are allowed, it fires the due reminders;
//   - when auto-archive is allowed, it carries out the due archives, and runs the older_than rules at start and
//     then once SweepEvery has passed.
//
// The outbox and disappearing timers run whatever the entitlements say: a lapsed plan never strands a message
// already held or scheduled, nor keeps one past its timer. What is not allowed waits, untouched, until it is. It
// then sleeps until the next thing is due, the next sweep, or MaxSleep, whichever is first. A poke, a new message
// or a read wakes it early: a message or a read can schedule an archive that is due at once.
func (t *Timers) Run(ctx context.Context) {
	// Deferred first, so it runs last: the engine stops the bridges and closes the store once Run returns, and no
	// hand-off may be left using either.
	defer t.handOffs.Wait()
	feed := t.s.Feed()
	defer feed.Close()
	forwarded := make(chan struct{})
	go func() {
		defer close(forwarded)
		t.pokeOnChanges(ctx, feed)
	}()
	defer func() { <-forwarded }()

	var nextSweep time.Time // the zero time: sweep at start
	for {
		passAt := t.clock.Now()
		nextSweep = t.pass(ctx, passAt, nextSweep)
		wait := t.wait(ctx, passAt, nextSweep)
		select {
		case <-ctx.Done():
			return
		case <-t.poke:
		case <-t.clock.After(wait):
		}
	}
}

// pokeOnChanges pokes the loop for each change that can schedule an archive: a new event (my reply, or their
// message cancelling one) or a read. A resync means changes were missed, so it pokes too.
func (t *Timers) pokeOnChanges(ctx context.Context, feed *store.Feed) {
	for {
		select {
		case <-ctx.Done():
			return
		case c := <-feed.C:
			switch c.Kind {
			case "event", "read", store.ChangeResync:
				t.Poke()
			}
		}
	}
}

// pass does what is due at passAt and returns when the next sweep is.
func (t *Timers) pass(ctx context.Context, passAt, nextSweep time.Time) time.Time {
	if _, err := t.s.ExpireDue(ctx); err != nil && ctx.Err() == nil {
		t.log.Warn().Err(err).Msg("couldn't delete expired disappearing messages; trying again later")
	}
	t.sendDue(ctx)
	if t.ent.Allowed(entitlement.Reminders) {
		if _, err := t.s.FireDueReminders(ctx); err != nil && ctx.Err() == nil {
			t.log.Warn().Err(err).Msg("couldn't fire reminders; trying again later")
		}
	}
	if !t.ent.Allowed(entitlement.AutoArchive) {
		return nextSweep
	}
	if _, err := t.s.ArchiveDue(ctx); err != nil && ctx.Err() == nil {
		t.log.Warn().Err(err).Msg("couldn't carry out auto-archives; trying again later")
	}
	if passAt.Before(nextSweep) {
		return nextSweep
	}
	if _, err := t.s.SweepOlderThan(ctx); err != nil && ctx.Err() == nil {
		t.log.Warn().Err(err).Msg("couldn't run the auto-archive rules; trying again later")
	}
	return passAt.Add(SweepEvery)
}

// sendDue claims the due outbox messages and hands each to the dispatcher on its own goroutine. A claim that fails
// leaves the outbox as it was, for the next pass.
func (t *Timers) sendDue(ctx context.Context) {
	if t.d == nil {
		return
	}
	claimed, err := t.s.ClaimDue(ctx)
	if err != nil {
		if ctx.Err() == nil {
			t.log.Warn().Err(err).Msg("couldn't claim due outbox messages; trying again later")
		}
		return
	}
	ctx = t.log.WithContext(ctx) // HandOff logs through zerolog.Ctx: the engine's log, not a silent default
	for _, e := range claimed {
		t.handOffs.Add(1)
		go func() {
			defer t.handOffs.Done()
			t.d.HandOff(ctx, e)
		}()
	}
}

// wait is how long to sleep after the pass at passAt: until the next thing is due, the next sweep, or MaxSleep,
// whichever is first. Something that was already due at passAt and is still there was left on purpose (its
// feature is not allowed) or failed; it doesn't shorten the sleep, so the loop never spins on it, and it doesn't
// hide what is due after passAt either (NextDueAfter).
func (t *Timers) wait(ctx context.Context, passAt, nextSweep time.Time) time.Duration {
	now := t.clock.Now()
	wait := MaxSleep
	if t.ent.Allowed(entitlement.AutoArchive) {
		wait = min(wait, nextSweep.Sub(now))
	}
	next, ok, err := t.s.NextDueAfter(ctx, passAt)
	switch {
	case err != nil:
		if ctx.Err() == nil {
			t.log.Warn().Err(err).Msg("couldn't read when the next timer is due")
		}
	case ok:
		wait = min(wait, next.Sub(now))
	}
	return max(wait, 0)
}
