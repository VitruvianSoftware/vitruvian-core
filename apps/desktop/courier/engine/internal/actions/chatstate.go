// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"sync"

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

// chatHost is a chat and the running host of its network, nil when that network isn't running: then a change to the
// chat stays in Courier (and is kept for the network while it starts: tellChange). An unknown chat is
// store.ErrNotFound.
func (a *Actions) chatHost(ctx context.Context, roomID string) (store.Room, *host.Host, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return store.Room{}, nil, err
	}
	if !ok {
		return store.Room{}, nil, store.ErrNotFound
	}
	h, _ := a.eng.Host(room.Network)
	return room, h, nil
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

// tell hands a chat change to the chat's network, if the network takes that change (tellChange). While the network
// is still starting nobody can say yet whether it takes it, so the change is kept for when it runs.
func (a *Actions) tell(ctx context.Context, room store.Room, h *host.Host, change string, typ event.Type, parsed any) {
	if h != nil && !supported(h, change) {
		return // a network that doesn't take it: the change is Courier's own
	}
	a.tellChange(ctx, room, h, change, untoldKey{room: room.ID, change: change},
		func(c bridgev2.NetworkAPI) bool { return takes(c, change) }, &event.Event{
			Type: typ, RoomID: id.RoomID(room.ID), Sender: ids.Me, ID: ids.RandomEventID(),
			Timestamp: a.now().UnixMilli(), Content: event.Content{Parsed: parsed},
		})
}

// tellChange hands evt, a change already made here (a pin, a mute, a read, a delete for me), to the network of room
// through h, best effort (bestEffort). With no host it keeps the change while the network is still starting, so it
// is told once the network runs (retell); a network that won't run this session is never told.
func (a *Actions) tellChange(ctx context.Context, room store.Room, h *host.Host, change string, key untoldKey, takesIt func(bridgev2.NetworkAPI) bool, evt *event.Event) {
	if h == nil {
		if a.eng.Status(room.Network).Starting {
			a.untold.keep(room.Network, key, untoldChange{change: change, takesIt: takesIt, evt: evt})
		}
		return
	}
	a.bestEffort(ctx, h, room, change, key, takesIt, evt)
}

// bestEffort hands evt, a change already made here (a pin, a mute, a read, a delete for me), to h's network. It runs
// after the change is stored, and the stored change is the truth: telling is best effort. A network that refuses is
// logged at warn, under the bridge's own network name and the kind of change (and nothing else: no chat, name or
// text), and the change stays as it is here. Nothing retries a refusal or reverts it; the network catches up when the
// chat is next changed.
//
// It is skipped while the chat's login (loginOf) isn't connected or doesn't take the change (takesIt), rather than
// waiting: bridgev2 would hold each change for up to SendReconnectWait, and a change to many chats at once would wait
// that long for every one of them. A skipped change is kept, under key, and told when the login is back (retell, from
// the timer loop's SendWaiting), the newest one of each key only.
func (a *Actions) bestEffort(ctx context.Context, h *host.Host, room store.Room, change string, key untoldKey, takesIt func(bridgev2.NetworkAPI) bool, evt *event.Event) {
	log := h.Bridge.Log.With().Str("change", change).Logger()
	if l := loginOf(h, room.LoginID); l == nil || !takesIt(l.Client) || !l.Client.IsLoggedIn() {
		log.Warn().Msg("not connected, so the network wasn't told of a change yet; it is told once it connects")
		a.untold.keep(h.Network, key, untoldChange{change: change, takesIt: takesIt, evt: evt})
		return
	}
	a.untold.drop(h.Network, key) // told now: an older one kept for later would undo it
	res := h.Bridge.QueueMatrixEvent(ctx, evt)
	if !res.Success || res.Ignored || res.Error != nil {
		log.Warn().Msg("the network didn't take a change; it stays changed here")
	}
}

// untoldKey names a chat change kept for its network: the chat, and the change ("pin", "mute", "read", or
// "delete_for_me" with the message).
type untoldKey struct{ room, change string }

// untoldChange is a change kept for its network: the change's kind (for the log), whether a client takes it, and the
// event that tells it.
type untoldChange struct {
	change  string
	takesIt func(bridgev2.NetworkAPI) bool
	evt     *event.Event
}

// untold is the chat changes made while their network couldn't be told (starting, or the chat's login not logged
// in), per network, the newest of each key only. It lives in memory: what was changed here stays changed whatever,
// and a change made before a quit reaches the network when the chat is next changed, as before.
type untold struct {
	mu sync.Mutex
	m  map[string]map[untoldKey]untoldChange
}

func (u *untold) keep(network string, key untoldKey, c untoldChange) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.m == nil {
		u.m = map[string]map[untoldKey]untoldChange{}
	}
	if u.m[network] == nil {
		u.m[network] = map[untoldKey]untoldChange{}
	}
	u.m[network][key] = c
}

// keepUnlessNewer keeps c under key unless a newer change was kept there meanwhile.
func (u *untold) keepUnlessNewer(network string, key untoldKey, c untoldChange) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if _, newer := u.m[network][key]; newer {
		return
	}
	if u.m == nil {
		u.m = map[string]map[untoldKey]untoldChange{}
	}
	if u.m[network] == nil {
		u.m[network] = map[untoldKey]untoldChange{}
	}
	u.m[network][key] = c
}

func (u *untold) drop(network string, key untoldKey) {
	u.mu.Lock()
	defer u.mu.Unlock()
	delete(u.m[network], key)
}

// take removes and returns every change kept for network.
func (u *untold) take(network string) map[untoldKey]untoldChange {
	u.mu.Lock()
	defer u.mu.Unlock()
	out := u.m[network]
	delete(u.m, network)
	return out
}

// retell tells h's network the chat changes made while it couldn't be told, now that it may be connected: each one
// whose chat's login is logged in goes (best effort, as bestEffort), and the rest are kept for the next time. A
// change the network's client doesn't take is dropped.
func (a *Actions) retell(ctx context.Context, h *host.Host) {
	for key, c := range a.untold.take(h.Network) {
		room, ok, err := a.s.GetRoom(ctx, key.room)
		if err != nil || !ok {
			continue // the chat is gone
		}
		l := loginOf(h, room.LoginID)
		if l == nil || !l.Client.IsLoggedIn() {
			a.untold.keepUnlessNewer(h.Network, key, c)
			continue
		}
		if !c.takesIt(l.Client) {
			continue
		}
		res := h.Bridge.QueueMatrixEvent(ctx, c.evt)
		if !res.Success || res.Ignored || res.Error != nil {
			h.Bridge.Log.Warn().Str("change", c.change).Msg("the network didn't take a change; it stays changed here")
		}
	}
}

// SetPinned pins or unpins a chat in Courier, then tells its network if it takes pins (the m.favourite tag).
func (a *Actions) SetPinned(ctx context.Context, roomID string, pinned bool) error {
	room, h, err := a.chatHost(ctx, roomID)
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
	a.tell(ctx, room, h, syncPin, event.AccountDataRoomTags, &event.TagEventContent{Tags: tags})
	return nil
}

// SetMuted mutes or unmutes a chat in Courier, then tells its network if it takes mutes. A mute is for ever.
func (a *Actions) SetMuted(ctx context.Context, roomID string, muted bool) error {
	room, h, err := a.chatHost(ctx, roomID)
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
	a.tell(ctx, room, h, syncMute, event.AccountDataBeeperMute, &event.BeeperMuteEventContent{MutedUntil: until})
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
	room, h, err := a.chatHost(ctx, roomID)
	if err != nil {
		return err
	}
	if !supported(h, syncAccept) {
		return ErrNotSupported
	}
	if err = a.s.SetRequest(ctx, roomID, false); err != nil {
		return err
	}
	a.tell(ctx, room, h, syncAccept, event.BeeperAcceptMessageRequest, &event.BeeperAcceptMessageRequestEventContent{})
	return nil
}
