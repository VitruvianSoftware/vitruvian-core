// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// The outbox's actions: held messages (undo send) and scheduled ones (send later). The store keeps them and decides,
// in one transaction per claim, which messages go (store.ClaimDue, ClaimHeld, ClaimScheduled); these actions hand
// what a claim returns to the network. The plan is asked only when a message is held or scheduled: one already in
// the outbox always goes, whatever the plan says now.

// HandOff hands a claimed message of mine (pending, from a store claim) to its network: it waits up to LoginWait for
// the network to log in, then queues it, and the bridge reports back through the store (sent or failed). When the
// network isn't running, or doesn't log in in time, the message becomes failed with ReasonNotConnected, so it never
// stays pending with nothing sending it; the app offers Retry. The timer loop calls it for each message ClaimDue
// returns.
func (a *Actions) HandOff(ctx context.Context, e store.Event) {
	log := zerolog.Ctx(ctx).With().Str("event_id", e.EventID).Logger()
	fail := func(reason string) {
		if err := a.s.SetStatus(ctx, e.EventID, "failed", reason); err != nil {
			log.Warn().Err(err).Msg("couldn't mark an outbox message failed")
		}
	}
	h, err := a.eng.HostForRoom(ctx, e.RoomID)
	if err != nil {
		fail(ReasonNotConnected)
		return
	}
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		fail(ReasonNotConnected)
		return
	}
	evt, err := storedEvent(e)
	if err != nil {
		log.Warn().Msg("an outbox message is unreadable, so it wasn't sent")
		fail("unreadable")
		return
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
}

// Undo takes back a held message before its window ends: it leaves the chat and search, and is returned as it was
// held, its content carrying what was typed (SourceOf), for the composer. Once it has gone it is ErrAlreadySent.
// Undo needs no entitlement: a lapsed plan never strands a held message.
func (a *Actions) Undo(ctx context.Context, eventID string) (store.Event, error) {
	return a.s.Unhold(ctx, eventID)
}

// SendHeldNow sends every message held in roomID now, without waiting for its window to end, oldest first.
func (a *Actions) SendHeldNow(ctx context.Context, roomID string) error {
	if roomID == "" {
		return ErrBadValue // "" would be every chat's
	}
	claimed, err := a.s.ClaimHeld(ctx, roomID)
	if err != nil {
		return err
	}
	for _, e := range claimed {
		a.HandOff(ctx, e)
	}
	return nil
}

// scheduledContent renders a message to be sent later in roomID, as Send would now: the ranges the chat keeps, the
// reply or thread, and the chat's disappearing timer, with what was typed under store.SourceKey.
func (a *Actions) scheduledContent(ctx context.Context, roomID, network, text string, o SendOptions) (json.RawMessage, error) {
	if err := checkText(text, o.Entities); err != nil {
		return nil, err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return nil, err
	}
	c := textContent(f, text, o.Entities)
	if err = refuseBridgeCommand(network, c.Body, "text"); err != nil {
		return nil, err
	}
	if c.RelatesTo, err = a.relation(ctx, roomID, f, o); err != nil {
		return nil, err
	}
	if c.BeeperDisappearingTimer, err = a.chatTimer(ctx, roomID); err != nil {
		return nil, err
	}
	return withSource(c, Source{Text: text, Entities: o.Entities, ReplyTo: o.ReplyTo, ThreadRoot: o.ThreadRoot})
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

// scheduled finds scheduled message id, in any state; ErrNotFound when there is none.
func (a *Actions) scheduled(ctx context.Context, id int64) (store.Scheduled, error) {
	all, err := a.s.ScheduledIn(ctx, "")
	if err != nil {
		return store.Scheduled{}, err
	}
	for _, sc := range all {
		if sc.ID == id {
			return sc, nil
		}
	}
	return store.Scheduled{}, store.ErrNotFound
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
		sc, err := a.scheduled(ctx, id)
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
		o := SendOptions{Entities: src.Entities, ReplyTo: src.ReplyTo, ThreadRoot: src.ThreadRoot}
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
