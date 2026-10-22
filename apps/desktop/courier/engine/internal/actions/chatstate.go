// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// ErrNotSupported means the chat's network has no way to take the change, so nothing was changed.
var ErrNotSupported = errors.New("this network can't do that")

// The chat changes a network can take, in the order Syncs lists them.
const (
	syncPin    = "pin"
	syncMute   = "mute"
	syncAccept = "accept_request"
)

// SyncsOf lists the chat changes Courier sends to a network client, out of "pin", "mute" and "accept_request", in
// that order: the bridgev2 interfaces it implements. Never nil.
//
// "unread" (MarkedUnreadHandlingNetworkAPI, m.marked_unread) is never listed and never sent, whatever the client
// implements: an unread mark stays on this Mac. The only bridge that takes one, WhatsApp, inverts it:
// mautrix-whatsapp's HandleMarkedUnread (pkg/connector/handlematrix.go:667 at v0.2609.0, :696 at v0.2610.0, both
// checked) passes Content.Unread as whatsmeow's BuildMarkChatAsRead(target, read, ...), so "mark unread" would
// mark the chat read on the phone and reading it would mark it unread. Courier doesn't invert it itself: that
// would break silently the day the bridge is fixed. TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks
// (networks) fails when the bridge is bumped, so the handler is looked at again before this is re-enabled.
func SyncsOf(c bridgev2.NetworkAPI) []string {
	out := []string{}
	if _, ok := c.(bridgev2.TagHandlingNetworkAPI); ok {
		out = append(out, syncPin)
	}
	if _, ok := c.(bridgev2.MuteHandlingNetworkAPI); ok {
		out = append(out, syncMute)
	}
	if _, ok := c.(bridgev2.MessageRequestAcceptingNetworkAPI); ok {
		out = append(out, syncAccept)
	}
	return out
}

func takes(c bridgev2.NetworkAPI, change string) bool {
	for _, s := range SyncsOf(c) {
		if s == change {
			return true
		}
	}
	return false
}

// myLogins are the local user's logins on h's network that have a client.
func myLogins(h *host.Host) []*bridgev2.UserLogin {
	var out []*bridgev2.UserLogin
	for _, l := range h.Bridge.GetAllCachedUserLogins() {
		if l.UserMXID == ids.Me && l.Client != nil {
			out = append(out, l)
		}
	}
	return out
}

// Syncs lists which of the chat changes Courier makes reach this network, out of "pin", "mute" and
// "accept_request", in that order (an unread mark never does: see SyncsOf). It follows the network's login
// client: a network that isn't running or isn't linked has none to ask, and lists nothing. Never nil.
func (a *Actions) Syncs(network string) []string {
	h, ok := a.eng.Host(network)
	if !ok {
		return []string{}
	}
	out := []string{}
	for _, change := range []string{syncPin, syncMute, syncAccept} {
		for _, l := range myLogins(h) {
			if takes(l.Client, change) {
				out = append(out, change)
				break
			}
		}
	}
	return out
}

// hostOf is the running host of a chat's network, or nil when that network isn't running: then a change to the
// chat stays in Courier. An unknown chat is store.ErrNotFound.
func (a *Actions) hostOf(ctx context.Context, roomID string) (*host.Host, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, store.ErrNotFound
	}
	h, _ := a.eng.Host(room.Network)
	return h, nil
}

// supported reports whether h's network takes change: some login's client implements its interface.
func supported(h *host.Host, change string) bool {
	if h == nil {
		return false
	}
	for _, l := range myLogins(h) {
		if takes(l.Client, change) {
			return true
		}
	}
	return false
}

// tell hands a chat change to the chat's network, if the network takes that change (bestEffort).
func (a *Actions) tell(ctx context.Context, h *host.Host, roomID, change string, typ event.Type, parsed any) {
	if !supported(h, change) {
		return // a network that doesn't take it: the change is Courier's own
	}
	a.bestEffort(ctx, h, change, func(c bridgev2.NetworkAPI) bool { return takes(c, change) }, &event.Event{
		Type: typ, RoomID: id.RoomID(roomID), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: a.now().UnixMilli(), Content: event.Content{Parsed: parsed},
	})
}

// bestEffort hands evt, a change already made here (a pin, a mute, a delete for me), to h's network. It runs after
// the change is stored, and the stored change is the truth: telling is best effort. A network that is offline or
// refuses is logged at warn, under the bridge's own network name and the kind of change (and nothing else: no chat,
// name or text), and the change stays as it is here. Nothing retries it or reverts it; the network catches up when
// the chat is next changed.
//
// It is skipped while no login whose client takes the change (takesIt) is connected, rather than waiting: bridgev2
// would hold each change for up to SendReconnectWait, and a change to many chats at once would wait that long for
// every one of them.
func (a *Actions) bestEffort(ctx context.Context, h *host.Host, change string, takesIt func(bridgev2.NetworkAPI) bool, evt *event.Event) {
	log := h.Bridge.Log.With().Str("change", change).Logger()
	connected := false
	for _, l := range myLogins(h) {
		if takesIt(l.Client) && l.Client.IsLoggedIn() {
			connected = true
			break
		}
	}
	if !connected {
		log.Warn().Msg("not connected, so the network wasn't told of a change; it stays changed here")
		return
	}
	res := h.Bridge.QueueMatrixEvent(ctx, evt)
	if !res.Success || res.Ignored || res.Error != nil {
		log.Warn().Msg("the network didn't take a change; it stays changed here")
	}
}

// SetPinned pins or unpins a chat in Courier, then tells its network if it takes pins (the m.favourite tag).
func (a *Actions) SetPinned(ctx context.Context, roomID string, pinned bool) error {
	h, err := a.hostOf(ctx, roomID)
	if err != nil {
		return err
	}
	if err = a.s.SetPinned(ctx, roomID, pinned); err != nil {
		return err
	}
	tags := event.Tags{}
	if pinned {
		tags[event.RoomTagFavourite] = event.TagMetadata{}
	}
	a.tell(ctx, h, roomID, syncPin, event.AccountDataRoomTags, &event.TagEventContent{Tags: tags})
	return nil
}

// SetMuted mutes or unmutes a chat in Courier, then tells its network if it takes mutes. A mute is for ever.
func (a *Actions) SetMuted(ctx context.Context, roomID string, muted bool) error {
	h, err := a.hostOf(ctx, roomID)
	if err != nil {
		return err
	}
	if err = a.s.SetMuted(ctx, roomID, muted); err != nil {
		return err
	}
	var until int64 // 0: not muted
	if muted {
		until = -1 // for ever
	}
	a.tell(ctx, h, roomID, syncMute, event.AccountDataBeeperMute, &event.BeeperMuteEventContent{MutedUntil: until})
	return nil
}

// SetMarkedUnread marks chats unread (or clears the mark) in Courier, and returns the ones that changed. An
// unknown chat is store.ErrNotFound and changes none of them.
//
// The mark is Courier's own: no m.marked_unread is queued to any network. WhatsApp's bridge, the only one that
// takes it, inverts the flag (mautrix-whatsapp pkg/connector/handlematrix.go:667, v0.2609.0; :696, v0.2610.0); the
// full reason is on SyncsOf.
func (a *Actions) SetMarkedUnread(ctx context.Context, roomIDs []string, unread bool) ([]string, error) {
	return a.s.SetMarkedUnread(ctx, roomIDs, unread)
}

// AcceptRequest accepts a message request (someone new writing first). On a network that can't take an accept it
// is ErrNotSupported and nothing changes. Otherwise the chat stops being a request in Courier first, then the
// network is told.
func (a *Actions) AcceptRequest(ctx context.Context, roomID string) error {
	h, err := a.hostOf(ctx, roomID)
	if err != nil {
		return err
	}
	if !supported(h, syncAccept) {
		return ErrNotSupported
	}
	if err = a.s.SetRequest(ctx, roomID, false); err != nil {
		return err
	}
	a.tell(ctx, h, roomID, syncAccept, event.BeeperAcceptMessageRequest, &event.BeeperAcceptMessageRequestEventContent{})
	return nil
}
