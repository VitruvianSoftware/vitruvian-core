// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// unsendable reports whether a message type can be unsent: a message (not an edit of one), a sticker or a poll.
func unsendable(typ string, isEdit bool) bool {
	switch typ {
	case event.EventMessage.Type:
		return !isEdit
	case event.EventSticker.Type, event.EventUnstablePollStart.Type:
		return true
	}
	return false
}

// takesReactionRemoval reports whether some login of h's network takes back a reaction
// (bridgev2.ReactionHandlingNetworkAPI), which is how bridgev2 delivers a redaction of one.
func takesReactionRemoval(h *host.Host) bool {
	for _, l := range myLogins(h) {
		if _, ok := l.Client.(bridgev2.ReactionHandlingNetworkAPI); ok {
			return true
		}
	}
	return false
}

// Unsend deletes a message of mine for everyone, or takes back a reaction of mine, and returns the ID of the stored
// redaction. The message leaves the chat at once; the redaction is pending until the network answers, and a network
// that refuses it brings the message back, in the chat, the inbox and search (the store's rule).
//
// A message must be mine (else ErrNotYours), sent and not deleted, in a chat whose network can unsend (else
// ErrNotSupported: Google Messages, whose bridge takes a redaction but only deletes from the phone, never can), and
// no older than the chat's UnsendMaxAge (else ErrTooOld). bridgev2 doesn't check that age, so this is the only place
// it is kept: a message past it is refused before anything is stored or sent. A held message (queued) is
// ErrNotSupported: Undo takes that back. So is a timer-change note, the engine's own or a bridge's.
//
// A reaction of mine has no age limit; it needs a network that takes reactions back.
func (a *Actions) Unsend(ctx context.Context, eventID string) (string, error) {
	e, redacted, err := a.message(ctx, eventID)
	if err != nil {
		return "", err
	}
	if e.Sender != string(ids.Me) {
		return "", ErrNotYours
	}
	if e.Status != "sent" || redacted {
		return "", ErrNotSupported
	}
	h, err := a.eng.HostForRoom(ctx, e.RoomID)
	if err != nil {
		return "", err
	}
	if e.Type == event.EventReaction.Type {
		if !takesReactionRemoval(h) {
			return "", ErrNotSupported
		}
	} else {
		if _, isEdit := messageShape(e.Content); !unsendable(e.Type, isEdit) {
			return "", ErrNotSupported
		}
		f, err := a.Features(ctx, e.RoomID)
		if err != nil {
			return "", err
		}
		if !f.Unsend {
			return "", ErrNotSupported
		}
		if f.UnsendMaxAge > 0 && a.now().Sub(e.TS) > f.UnsendMaxAge {
			return "", ErrTooOld
		}
	}
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
	}
	// Storing the redaction (pending) deletes its target here at once.
	evt, err := a.stage(ctx, e.RoomID, event.EventRedaction, &event.RedactionEventContent{Redacts: id.EventID(eventID)})
	if err != nil {
		return "", err
	}
	evt.Redacts = id.EventID(eventID)
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return string(evt.ID), nil
}

// DeleteForMe deletes a message on this Mac only, anyone's: it leaves the chat, the inbox and search, with no
// placeholder. In a chat whose network deletes for me too (DeleteReachesPhone: Google Messages, where it also leaves
// the phone's own Messages app), a redaction is then sent to the network, and stored nowhere. That send is best
// effort, as a chat change is (bestEffort): skipped while the network isn't connected, logged at warn when the
// network doesn't take it, and the message stays deleted here either way.
//
// A held message (queued) is ErrNotSupported: Undo takes that back.
func (a *Actions) DeleteForMe(ctx context.Context, eventID string) error {
	e, _, err := a.stored(ctx, eventID)
	if err != nil {
		return err
	}
	if e.Status == "queued" {
		return ErrNotSupported
	}
	f, err := a.Features(ctx, e.RoomID)
	if err != nil {
		return err
	}
	if err = a.s.SetDeletedForMe(ctx, eventID); err != nil {
		return err
	}
	if !f.DeleteReachesPhone {
		return nil
	}
	h, err := a.hostOf(ctx, e.RoomID)
	if err != nil || h == nil {
		return nil // deleted here; a network that isn't running isn't told
	}
	a.bestEffort(ctx, h, "delete_for_me", func(c bridgev2.NetworkAPI) bool {
		_, ok := c.(bridgev2.RedactionHandlingNetworkAPI)
		return ok
	}, &event.Event{
		Type: event.EventRedaction, RoomID: id.RoomID(e.RoomID), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: a.now().UnixMilli(), Redacts: id.EventID(eventID),
		Content: event.Content{Parsed: &event.RedactionEventContent{Redacts: id.EventID(eventID)}},
	})
	return nil
}
