// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// Protocol 5's presence: who has read my messages (Event.read_by, Event.delivered), my typing (room.setTyping), Mark
// as Unread from a message (room.setUnreadFrom) and Reply Privately's chat (room.directChat). Each handler has the
// shape of the others: strict params, the required ones checked by name, then one actions call whose sentinel errors
// map to their codes. Nothing here logs who: user IDs and names only ever go to the app.

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// myUserID is my Matrix ID as the store keeps senders, for code where the ids package name is taken.
var myUserID = string(ids.Me)

// reasonNoAccount is a waiting message's status_reason when none of my accounts is in its chat any more: it can't go
// until one is.
const reasonNoAccount = "no account"

// personName is userID as the app names people in a chat (typing, read_by): their name in the chat (member, their
// member content there; nil when the chat doesn't list them), else their profile's, else their ID's localpart.
// profiles caches profile names across a page.
func (d *Deps) personName(ctx context.Context, userID string, member json.RawMessage, profiles map[string]string) (string, error) {
	var m struct {
		DisplayName string `json:"displayname"`
	}
	_ = json.Unmarshal(member, &m) // not a member, or content that can't be read: no name from it
	if m.DisplayName != "" {
		return m.DisplayName, nil
	}
	name, ok := profiles[userID]
	if !ok {
		var err error
		if name, _, _, err = d.Store.GetProfile(ctx, userID); err != nil {
			return "", err
		}
		profiles[userID] = name
	}
	if name == "" {
		name = localpart(userID)
	}
	return name, nil
}

// readerNames is the name of each reader on a page, by user ID.
type readerNames map[string]string

// of is readers on the wire, in their order (newest receipt first), at most store.MaxReaders.
func (n readerNames) of(readers []store.Reader) []readerJSON {
	out := make([]readerJSON, 0, min(len(readers), store.MaxReaders))
	for _, r := range readers {
		if len(out) == store.MaxReaders {
			break
		}
		out = append(out, readerJSON{UserID: r.UserID, Name: n[r.UserID], TS: ms(r.TS)})
	}
	return out
}

// readersOf names everyone who has read a message of a page's (receipts, store.ReceiptsFor's answer for it), with one
// read of the chat's members and one of each reader's profile at most. A reader the chat lists is named as typing
// names them (personName); one it doesn't (its members can arrive later than a receipt, and a receipt is outside
// data) by their ID's localpart, never a name taken from elsewhere (Global Constraints).
func (d *Deps) readersOf(ctx context.Context, roomID string, receipts map[string]store.Receipts) (readerNames, error) {
	names := readerNames{}
	for _, r := range receipts {
		for _, reader := range r.ReadBy {
			names[reader.UserID] = ""
		}
	}
	if len(names) == 0 {
		return names, nil
	}
	members, err := d.Store.Members(ctx, roomID)
	if err != nil {
		return nil, err
	}
	profiles := map[string]string{}
	for userID := range names {
		member, listed := members[userID]
		if !listed {
			names[userID] = localpart(userID)
			continue
		}
		if names[userID], err = d.personName(ctx, userID, member, profiles); err != nil {
			return nil, err
		}
	}
	return names, nil
}

// noAccountReason is the status_reason of a waiting message in roomID: reasonNoAccount when none of my accounts is
// in the chat any more, so it can't go until one is (the carry from Task 5: a shared chat whose only account of mine
// was signed out would otherwise wait with nothing said); "" while it is just waiting. Which account a chat goes
// through is the actions' one rule (Actions.HasAccountFor, loginOf's), never worked out again here. It is asked as
// the page is read, so it clears by itself once an account is in the chat again; a network that isn't running can't
// say, and its messages are just waiting.
func (d *Deps) noAccountReason(ctx context.Context, roomID string) (string, error) {
	if d.Actions == nil {
		return "", nil
	}
	has, err := d.Actions.HasAccountFor(ctx, roomID)
	if errors.Is(err, store.ErrNotFound) {
		return "", nil // deleted since its page was read: nothing to say of it, and the page still answers
	}
	if err != nil || has {
		return "", err
	}
	return reasonNoAccount, nil
}

// roomSetTyping tells the chat's network I am typing, or stopped. It answers at once and is best effort: a chat whose
// network isn't connected (not running, starting, or the chat's account down) is told nothing and that is no error,
// so unlike the actions that go out through the network it doesn't check that the network runs (Ruling C6). Only an
// unknown chat is refused.
func roomSetTyping(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Typing *bool   `json:"typing"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := requiredBool("typing", p.Typing); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetTyping(ctx, *p.RoomID, *p.Typing) // an unknown chat is store.ErrNotFound
}

// roomSetUnreadFrom marks a chat unread from a message on. It names only the message, and the chat is the message's
// (Ruling C18). A note is not supported (Ruling P2), and the mark stays on this Mac.
func roomSetUnreadFrom(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID *string `json:"event_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	_, err := d.Actions.SetUnreadFromEvent(ctx, *p.EventID)
	return nil, err
}

// roomResult is a RoomResult: the chat a method found or made.
type roomResult struct {
	RoomID string `json:"room_id"`
}

// roomDirectChat is Reply Privately's chat: the one-to-one chat with a person in a group, found in the store first
// (no network needed), else made by the network (actions.DirectChat says when each refusal comes).
func roomDirectChat(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		UserID *string `json:"user_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := required("user_id", p.UserID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	roomID, err := d.Actions.DirectChat(ctx, *p.RoomID, *p.UserID)
	if err != nil {
		return nil, err
	}
	return roomResult{RoomID: roomID}, nil
}
