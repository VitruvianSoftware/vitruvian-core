// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package timers is the engine's one timer loop: it fires reminders and carries out auto-archive rules when they
// come due. Everything it waits for is in courier.db, so nothing is lost when the engine stops: what came due
// while Courier was quit, or the Mac slept, happens once at the next chance.
package timers

import (
	"context"
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

// Timers runs reminders and auto-archive rules over a store.
type Timers struct {
	s     *store.Store
	ent   entitlement.Provider
	clock Clock
	log   zerolog.Logger
	poke  chan struct{}
}

// New makes the loop. Run starts it. The store's own clock should agree with clock (in the engine both are the
// system clock).
func New(s *store.Store, ent entitlement.Provider, clock Clock, log zerolog.Logger) *Timers {
	return &Timers{s: s, ent: ent, clock: clock, log: log, poke: make(chan struct{}, 1)}
}

// Poke tells the loop that a reminder or a rule changed, so it looks again now instead of when it next wakes. It
// never blocks; pokes that arrive together are one.
func (t *Timers) Poke() {
	select {
	case t.poke <- struct{}{}:
	default:
	}
}

// Run runs the loop until ctx ends. Each time it wakes it does what is due:
//   - when reminders are allowed, it fires the due reminders;
//   - when auto-archive is allowed, it carries out the due archives, and runs the older_than rules at start and
//     then once SweepEvery has passed.
//
// What is not allowed waits, untouched, until it is. It then sleeps until the next thing is due, the next sweep,
// or MaxSleep, whichever is first. A poke, a new message or a read wakes it early: a message or a read can
// schedule an archive that is due at once.
func (t *Timers) Run(ctx context.Context) {
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

// wait is how long to sleep after the pass at passAt: until the next thing is due, the next sweep, or MaxSleep,
// whichever is first. Something that was already due at passAt and is still there was left on purpose (its
// feature is not allowed) or failed; it doesn't shorten the sleep, so the loop never spins on it.
func (t *Timers) wait(ctx context.Context, passAt, nextSweep time.Time) time.Duration {
	now := t.clock.Now()
	wait := MaxSleep
	if t.ent.Allowed(entitlement.AutoArchive) {
		wait = min(wait, nextSweep.Sub(now))
	}
	next, ok, err := t.s.NextDue(ctx)
	switch {
	case err != nil:
		if ctx.Err() == nil {
			t.log.Warn().Err(err).Msg("couldn't read when the next reminder is due")
		}
	case ok && next.After(passAt):
		wait = min(wait, next.Sub(now))
	}
	return max(wait, 0)
}
