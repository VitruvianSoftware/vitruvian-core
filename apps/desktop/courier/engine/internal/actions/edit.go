// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// stored is the message eventID with whether it is deleted here; an unknown one is store.ErrNotFound.
func (a *Actions) stored(ctx context.Context, eventID string) (e store.Event, redacted bool, err error) {
	e, ok, err := a.s.GetEvent(ctx, eventID)
	if err != nil {
		return store.Event{}, false, err
	}
	if !ok {
		return store.Event{}, false, fmt.Errorf("no message %s: %w", eventID, store.ErrNotFound)
	}
	redacted, err = a.s.Redacted(ctx, eventID)
	return e, redacted, err
}

// message is the stored message eventID that Edit, Unsend and Forward act on: as stored, but a timer-change note
// (the engine's own, never handed to a bridge, or a bridge's) or a bridge's call note is ErrNotSupported, whoever's
// it is. Delete for Me takes one off this Mac; nothing else acts on it.
func (a *Actions) message(ctx context.Context, eventID string) (e store.Event, redacted bool, err error) {
	if e, redacted, err = a.stored(ctx, eventID); err == nil && (store.IsTimerNote(e) || store.IsCallNote(e)) {
		return store.Event{}, false, ErrNotSupported
	}
	return e, redacted, err
}

// messageShape is what a message's content says about it: its msgtype and whether it is an edit of another one.
func messageShape(content json.RawMessage) (msgType event.MessageType, isEdit bool) {
	var c struct {
		MsgType   event.MessageType `json:"msgtype"`
		RelatesTo *struct {
			Type event.RelationType `json:"rel_type"`
		} `json:"m.relates_to"`
	}
	if json.Unmarshal(content, &c) != nil {
		return "", false
	}
	return c.MsgType, c.RelatesTo != nil && c.RelatesTo.Type == event.RelReplace
}

// editable reports whether a message is text a person can edit: an m.room.message of msgtype text, notice or emote,
// that isn't itself an edit.
func editable(e store.Event) (event.MessageType, bool) {
	if e.Type != event.EventMessage.Type {
		return "", false
	}
	mt, isEdit := messageShape(e.Content)
	switch mt {
	case event.MsgText, event.MsgNotice, event.MsgEmote:
		return mt, !isEdit
	}
	return "", false
}

// Edit replaces the text of a message of mine with text and its ranges, rendered for the chat (as Send renders). It
// returns the ID of the stored edit, which is pending until the network answers: a network that refuses it makes it
// failed, and the message reads as it did before, in the chat and in search (the store's rule).
//
// It is refused, with nothing stored or sent:
//   - ErrNotYours for someone else's message;
//   - ErrNotSupported for a timer-change note, whoever's, and for anything but text (an m.room.message of msgtype
//     text, notice or emote, not itself an edit),
//     a message that isn't sent or is deleted, or a chat whose network can't edit;
//   - ErrTooOld for a message older than the chat's EditMaxAge, or with EditMaxCount live edits already.
func (a *Actions) Edit(ctx context.Context, eventID, text string, ents []richtext.Entity) (string, error) {
	e, redacted, err := a.message(ctx, eventID)
	if err != nil {
		return "", err
	}
	if e.Sender != string(ids.Me) {
		return "", ErrNotYours
	}
	msgType, ok := editable(e)
	if !ok || e.Status != "sent" || redacted {
		return "", ErrNotSupported
	}
	if err = checkText(text, ents); err != nil {
		return "", err
	}
	f, err := a.Features(ctx, e.RoomID)
	if err != nil {
		return "", err
	}
	if !f.Edit {
		return "", ErrNotSupported
	}
	if f.EditMaxAge > 0 && a.now().Sub(e.TS) > f.EditMaxAge {
		return "", ErrTooOld
	}
	if f.EditMaxCount > 0 {
		versions, err := a.s.EditHistory(ctx, eventID)
		if err != nil {
			return "", err
		}
		if len(versions)-1 >= f.EditMaxCount { // the first version is the message as sent
			return "", ErrTooOld
		}
	}
	h, err := a.eng.HostForRoom(ctx, e.RoomID)
	if err != nil {
		return "", err
	}
	if err = a.waitLogin(ctx, h); err != nil {
		return "", err
	}
	nc := textContent(f, text, ents)
	nc.MsgType = msgType
	// The fallback is for a client that can't read edits: "* " and the new text. Mentions go in m.new_content only,
	// so nobody is notified twice.
	c := &event.MessageEventContent{
		MsgType: msgType, Body: "* " + nc.Body, Mentions: &event.Mentions{}, NewContent: nc,
		RelatesTo: (&event.RelatesTo{}).SetReplace(id.EventID(eventID)),
	}
	if nc.FormattedBody != "" {
		c.Format, c.FormattedBody = event.FormatHTML, "* "+nc.FormattedBody
	}
	return a.submit(ctx, h, e.RoomID, event.EventMessage, c)
}
