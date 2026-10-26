// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// The outbox's actions: held messages (undo send) and scheduled ones (send later). The store keeps them and decides,
// in one transaction per claim, which messages go (store.ClaimDue, ClaimHeld, ClaimScheduled); these actions hand
// what a claim returns to the network. The plan is asked only when a message is held or scheduled: one already in
// the outbox always goes, whatever the plan says now.

// HandOff hands a held or scheduled message of mine that a store claim made pending (ClaimDue, ClaimHeld,
// ClaimScheduled) to its network, and the bridge reports back through the store (sent or failed). The timer loop
// calls it for each message ClaimDue returns. It never waits:
//   - When ctx has ended (the engine is stopping, or the caller went away), nothing is sent and the message goes back
//     to the outbox (store.Requeue): not left pending for the next start to call "may have been sent", and not failed
//     for a quit the person never saw. The next claim sends it once under MaxLate late, and makes it failed "not sent"
//     over (Ruling C25: this is checked first).
//   - When the chat can't send now (its network is still starting, its login isn't logged in, or the chat has
//     messages waiting ahead of it), it becomes waiting (store.WaitAgain), and goes when the login is back, however
//     long that takes (Review Focus 1). MaxLate applied to its due time, at the claim, not to the wait.
//   - When the network isn't running this session, it becomes failed with ReasonNotConnected, so it never stays
//     pending with nothing sending it; the app offers Retry.
func (a *Actions) HandOff(ctx context.Context, e store.Event) { a.handOff(ctx, e, false) }

// handOff is HandOff for a message claimed from the outbox: fromWaiting says it came from ClaimWaiting (an offline
// row), so it goes back with WaitAgain whatever stopped it, never through Requeue (Ruling C2), and doesn't wait behind
// the chat's waiting messages, being one of them. It reports whether the message went back (to waiting, or queued)
// instead of going to the network.
func (a *Actions) handOff(ctx context.Context, e store.Event, fromWaiting bool) (wentBack bool) {
	log := zerolog.Ctx(ctx).With().Str("event_id", e.EventID).Logger()
	wctx := context.WithoutCancel(ctx) // local writes, which the timer loop waits for before the store closes
	waitAgain := func() bool {
		if _, err := a.s.WaitAgain(wctx, e.EventID); err != nil {
			log.Warn().Err(err).Msg("couldn't put an outbox message back to waiting")
		}
		return true
	}
	if ctx.Err() != nil {
		if fromWaiting {
			return waitAgain()
		}
		if _, err := a.s.Requeue(wctx, e.EventID); err != nil {
			log.Warn().Err(err).Msg("couldn't put an outbox message back")
		}
		return true
	}
	fail := func(reason string) bool {
		if err := a.s.SetStatus(wctx, e.EventID, "failed", reason); err != nil {
			log.Warn().Err(err).Msg("couldn't mark an outbox message failed")
		}
		return false
	}
	h, err := a.eng.HostForRoom(ctx, e.RoomID)
	switch {
	case errors.Is(err, engine.ErrStarting):
		return waitAgain()
	case err != nil:
		return fail(ReasonNotConnected)
	}
	room, ok, err := a.s.GetRoom(ctx, e.RoomID)
	if err != nil || !ok {
		return fail(ReasonNotConnected)
	}
	if !a.connected(ctx, h, room) {
		return waitAgain()
	}
	if !fromWaiting {
		// Wait behind the chat's waiting messages, so a held message never overtakes them. When the store can't
		// say, it waits too, and goes on a later pass.
		if behind, err := a.behindWaiting(ctx, room); err != nil || behind {
			waitAgain()
			a.wake() // its login is in: only the loop's next run sends it, so have it run
			return true
		}
	}
	evt, err := storedEvent(e)
	if err != nil {
		log.Warn().Msg("an outbox message is unreadable, so it wasn't sent")
		return fail(ReasonUnreadable)
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return false
}

// Networks lists the networks SendWaiting can send for: the running ones. The timer loop asks it on every pass.
func (a *Actions) Networks() []string { return a.eng.Names() }

// SendWaiting hands network's waiting messages to it, oldest first, now that some of its logins may be logged in:
// those of the chats whose login is logged in, or that every login shares and one of their own logins is in
// (store.ClaimWaiting), each through
// HandOff's rules, one after the other, so a chat's messages arrive in the order they were typed. A chat one of whose
// messages goes back to waiting (its login dropped meanwhile, or ctx ended) keeps the rest waiting too, in order. With
// no login logged in it claims nothing and changes nothing. It first tells the network the chat changes made while it
// couldn't be told (retell).
//
// The timer loop calls it on every pass and whenever a login's bridge state comes in, at most one run per network at
// a time, and waits for it before it stops (Ruling C35); it returns once every message it claimed has gone or gone
// back. While a run hands a chat's messages over, a new message in that chat waits behind them (goesNow); other
// chats are not held up.
func (a *Actions) SendWaiting(ctx context.Context, network string) {
	h, ok := a.eng.Host(network)
	if !ok || ctx.Err() != nil {
		return
	}
	a.retell(ctx, h)
	var loggedIn []string
	for _, l := range myLogins(h) {
		if l.Client.IsLoggedIn() {
			loggedIn = append(loggedIn, string(l.ID))
		}
	}
	if len(loggedIn) == 0 {
		return
	}
	// A shared chat goes through one of its own logins (loginOf), not any login that is in: one none of whose logins
	// is in is left alone, so a pass never claims it only to put it back (Ruling 12).
	shared, err := a.s.SharedWaiting(ctx, network)
	if err != nil {
		if ctx.Err() == nil {
			zerolog.Ctx(ctx).Warn().Err(err).Str("network", network).Msg("couldn't list waiting messages; trying again later")
		}
		return
	}
	var down []string
	for _, roomID := range shared {
		if !a.connected(ctx, h, store.Room{ID: roomID, Network: network}) {
			down = append(down, roomID)
		}
	}
	// The claim and the record of what it claimed are one step under flushMu, so a send in one of these chats sees
	// its messages either still waiting or in flight, and waits behind them (behindWaiting).
	a.flushMu.Lock()
	claimed, err := a.s.ClaimWaiting(ctx, network, loggedIn, down...)
	if err == nil {
		if a.inFlight == nil {
			a.inFlight = map[string]int{}
		}
		for _, e := range claimed {
			a.inFlight[e.RoomID]++
		}
	}
	a.flushMu.Unlock()
	if err != nil {
		if ctx.Err() == nil {
			zerolog.Ctx(ctx).Warn().Err(err).Str("network", network).Msg("couldn't claim waiting messages; trying again later")
		}
		return
	}
	done := func(e store.Event) {
		a.flushMu.Lock()
		if a.inFlight[e.RoomID]--; a.inFlight[e.RoomID] <= 0 {
			delete(a.inFlight, e.RoomID)
		}
		a.flushMu.Unlock()
	}
	back := map[string]bool{} // the chats one of whose messages went back: the rest of each goes back too
	for _, e := range claimed {
		if back[e.RoomID] {
			if _, err := a.s.WaitAgain(context.WithoutCancel(ctx), e.EventID); err != nil {
				zerolog.Ctx(ctx).Warn().Err(err).Str("event_id", e.EventID).Msg("couldn't put an outbox message back to waiting")
			}
		} else if a.handOff(ctx, e, true) {
			back[e.RoomID] = true
		}
		done(e)
	}
}

// Undo takes back a held message before its window ends: it leaves the chat and search, and is returned as it was
// held, its content carrying what was typed (SourceOf), for the composer. Once it has gone it is ErrAlreadySent.
// Undo needs no entitlement: a lapsed plan never strands a held message.
func (a *Actions) Undo(ctx context.Context, eventID string) (store.Event, error) {
	return a.s.Unhold(ctx, eventID)
}

// SendHeldNow sends every message held in roomID now, without waiting for its window to end, oldest first.
// SendAllHeldNow is every chat's.
func (a *Actions) SendHeldNow(ctx context.Context, roomID string) error {
	if roomID == "" {
		return ErrBadValue // "" would be every chat's: SendAllHeldNow says so
	}
	return a.sendHeld(ctx, roomID)
}

// SendAllHeldNow sends every chat's held messages now, oldest first (as the app quits, say).
func (a *Actions) SendAllHeldNow(ctx context.Context) error { return a.sendHeld(ctx, "") }

// sendHeld claims the held messages of roomID ("" is every chat's) and hands each to its network.
func (a *Actions) sendHeld(ctx context.Context, roomID string) error {
	claimed, err := a.s.ClaimHeld(ctx, roomID)
	if err != nil {
		return err
	}
	for _, e := range claimed {
		a.HandOff(ctx, e)
	}
	return nil
}

// scheduledContent is composeText's message, as Send would send it now, with what was typed under
// store.SourceKey.
func (a *Actions) scheduledContent(ctx context.Context, roomID, network, text string, o SendOptions) (json.RawMessage, error) {
	c, err := a.composeText(ctx, roomID, network, text, o)
	if err != nil {
		return nil, err
	}
	return withSource(c, Source{
		Text:               text,
		Entities:           o.Entities,
		ReplyTo:            o.ReplyTo,
		ThreadRoot:         o.ThreadRoot,
		DisableLinkPreview: o.DisableLinkPreview,
	})
}

// Schedule schedules a text message to be sent at due (after now, at most 5 years ahead) with condition
// "if_no_reply" (the default for "") or "always". It needs entitlement.SendLater. The text is rendered now, as Send
// renders it (UpdateScheduled renders it again); o.Hold must be 0. The message lives only in the outbox until it
// fires: not in the timeline, not in search. The network needn't be running now.
func (a *Actions) Schedule(ctx context.Context, roomID, text string, o SendOptions, due time.Time, condition string) (store.Scheduled, error) {
	if !a.allowed(entitlement.SendLater) {
		return store.Scheduled{}, ErrNotEntitled
	}
	if o.Hold != 0 {
		return store.Scheduled{}, ErrBadValue
	}
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return store.Scheduled{}, err
	}
	if !ok {
		return store.Scheduled{}, store.ErrNotFound
	}
	content, err := a.scheduledContent(ctx, roomID, room.Network, text, o)
	if err != nil {
		return store.Scheduled{}, err
	}
	return a.s.Schedule(ctx, store.Scheduled{
		RoomID: roomID, EventID: string(ids.RandomEventID()), Type: event.EventMessage.Type,
		Content: content, DueAt: due, Condition: condition,
	})
}

// UpdateScheduled changes scheduled message id: a non-nil due, the text (non-nil text, with ents its ranges), the
// ranges of the text it has (nil text, non-nil ents), a non-nil condition. A new text or new ranges are rendered
// again, for the chat as it is now, keeping the reply or thread it was scheduled with. The store's rules apply: it
// waits again, set now, and a canceled or missed one needs a new due.
//
// It needs no entitlement: a lapsed plan never strands a scheduled message, which can still be moved, changed, sent
// now or deleted.
func (a *Actions) UpdateScheduled(ctx context.Context, id int64, due *time.Time, text *string, ents []richtext.Entity, condition *string) (store.Scheduled, error) {
	var typ string
	var content json.RawMessage
	if text != nil || ents != nil {
		sc, err := a.s.ScheduledByID(ctx, id)
		if err != nil {
			return store.Scheduled{}, err
		}
		src, _ := SourceOf(sc.Content)
		if text != nil {
			src.Text, src.Entities = *text, ents
		} else {
			src.Entities = ents
		}
		room, ok, err := a.s.GetRoom(ctx, sc.RoomID)
		if err != nil {
			return store.Scheduled{}, err
		}
		if !ok {
			return store.Scheduled{}, store.ErrNotFound
		}
		o := SendOptions{Entities: src.Entities, ReplyTo: src.ReplyTo, ThreadRoot: src.ThreadRoot, DisableLinkPreview: src.DisableLinkPreview}
		if content, err = a.scheduledContent(ctx, sc.RoomID, room.Network, src.Text, o); err != nil {
			return store.Scheduled{}, err
		}
		typ = event.EventMessage.Type
	}
	return a.s.UpdateScheduled(ctx, id, due, typ, content, condition)
}

// SendScheduledNow sends scheduled message id now, whatever its state (waiting, canceled or missed). It needs no
// entitlement.
func (a *Actions) SendScheduledNow(ctx context.Context, id int64) error {
	e, err := a.s.ClaimScheduled(ctx, id)
	if err != nil {
		return err
	}
	a.HandOff(ctx, e)
	return nil
}
