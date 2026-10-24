// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"slices"
	"strings"
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

// myLogins are the local user's logins on h's network that have a client, by ID: "the first" login is then always
// the same one (the lowest ID, as bridgev2's default login and the store's LoginStates order them), not whichever
// the bridge's map gives first.
func myLogins(h *host.Host) []*bridgev2.UserLogin {
	var out []*bridgev2.UserLogin
	for _, l := range h.Bridge.GetAllCachedUserLogins() {
		if l.UserMXID == ids.Me && l.Client != nil {
			out = append(out, l)
		}
	}
	slices.SortFunc(out, func(a, b *bridgev2.UserLogin) int { return strings.Compare(string(a.ID), string(b.ID)) })
	return out
}

// Syncs lists which of the chat changes Courier makes reach this network, out of "pin", "mute" and
// "accept_request", in that order (an unread mark never does: see SyncsOf). It follows the network's login
// clients, all of them (a change one account's chats take is listed): a network that isn't running or isn't linked
// has none to ask, and lists nothing. A change to one chat goes through that chat's own login (supported). Never nil.
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

// supported reports whether room's network, through h, takes change for that chat: its login's client (loginOf)
// implements the change's interface. A shared chat ("") none of whose logins can send it now asks any login's client
// (they are one connector's: one that isn't logged in still says what it takes), so the change is kept for when its
// login is back (bestEffort) rather than dropped.
func supported(ctx context.Context, h *host.Host, room store.Room, change string) bool {
	if h == nil {
		return false
	}
	if l := loginOf(ctx, h, room); l != nil {
		return takes(l.Client, change)
	}
	if room.LoginID != "" {
		return false // the chat's login is gone: nothing can tell it
	}
	for _, l := range myLogins(h) {
		if takes(l.Client, change) {
			return true
		}
	}
	return false
}

// tell hands a chat change to the chat's network, if the chat's login takes that change (supported, tellChange).
// While the network is still starting nobody can say yet whether it takes it, so the change is kept for when it runs.
func (a *Actions) tell(ctx context.Context, room store.Room, h *host.Host, change string, typ event.Type, parsed any) {
	if h != nil && !supported(ctx, h, room, change) {
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
			a.untold.keep(room.Network, key, untoldChange{change: change, takesIt: takesIt, evt: evt, gen: a.untold.stamp()})
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
	gen := a.untold.stamp() // this change's place among its key's changes, from before it can wait for anything
	if l := loginOf(ctx, h, room); l == nil || !takesIt(l.Client) || !l.Client.IsLoggedIn() {
		h.Bridge.Log.Warn().Str("change", change).Msg("not connected, so the network wasn't told of a change yet; it is told once it connects")
		a.untold.keep(h.Network, key, untoldChange{change: change, takesIt: takesIt, evt: evt, gen: gen})
		return
	}
	a.tellNow(ctx, h, key, change, evt, gen)
}

// tellNow tells h's network evt, change gen of key, unless a newer change of key has been made meanwhile (kept or
// told): then that one is the truth, and this one is never told after it. It holds the network's tell lock, so the
// newest change of a key is the one the network hears last; other networks' tells don't wait for it.
func (a *Actions) tellNow(ctx context.Context, h *host.Host, key untoldKey, change string, evt *event.Event, gen uint64) {
	mu := a.untold.lock(h.Network)
	mu.Lock()
	defer mu.Unlock()
	if !a.untold.claim(h.Network, key, gen) {
		return
	}
	res := h.Bridge.QueueMatrixEvent(ctx, evt)
	if !res.Success || res.Ignored || res.Error != nil {
		h.Bridge.Log.Warn().Str("change", change).Msg("the network didn't take a change; it stays changed here")
	}
}

// untoldKey names a chat change kept for its network: the chat, and the change ("pin", "mute", "read", or
// "delete_for_me" with the message).
type untoldKey struct{ room, change string }

// untoldChange is a change kept for its network: the change's kind (for the log), whether a client takes it, the
// event that tells it, and its generation (stamp).
type untoldChange struct {
	change  string
	takesIt func(bridgev2.NetworkAPI) bool
	evt     *event.Event
	gen     uint64
}

// untold is the chat changes made while their network couldn't be told (starting, or the chat's login not logged
// in), per network, the newest of each key only. It lives in memory: what was changed here stays changed whatever,
// and a change made before a quit reaches the network when the chat is next changed, as before.
//
// Every change, kept or told directly, takes a generation when it is made (stamp), and each key remembers the newest
// it has seen (latest). A change older than its key's latest is superseded: it is neither kept nor told. Each network
// has its own tell lock (lock), held while a change is told, so for one key the newest is told last, and a tell
// held up on one network (bridgev2 can wait out SendReconnectWait) holds up no other.
type untold struct {
	mu     sync.Mutex
	locks  map[string]*sync.Mutex
	m      map[string]map[untoldKey]untoldChange
	latest map[string]map[untoldKey]uint64
	last   uint64
}

// stamp is a new generation, newer than every one before it.
func (u *untold) stamp() uint64 {
	u.mu.Lock()
	defer u.mu.Unlock()
	u.last++
	return u.last
}

// lock is network's tell lock.
func (u *untold) lock(network string) *sync.Mutex {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.locks == nil {
		u.locks = map[string]*sync.Mutex{}
	}
	if u.locks[network] == nil {
		u.locks[network] = &sync.Mutex{}
	}
	return u.locks[network]
}

// supersededLocked reports whether key has seen a change newer than gen; when it hasn't, gen becomes its latest. The
// caller holds u.mu.
func (u *untold) supersededLocked(network string, key untoldKey, gen uint64) bool {
	if u.latest == nil {
		u.latest, u.m = map[string]map[untoldKey]uint64{}, map[string]map[untoldKey]untoldChange{}
	}
	if u.latest[network] == nil {
		u.latest[network] = map[untoldKey]uint64{}
	}
	if u.latest[network][key] > gen {
		return true
	}
	u.latest[network][key] = gen
	return false
}

// keep keeps c as key's change for later, unless a newer one has been made.
func (u *untold) keep(network string, key untoldKey, c untoldChange) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.supersededLocked(network, key, c.gen) {
		return
	}
	if u.m[network] == nil {
		u.m[network] = map[untoldKey]untoldChange{}
	}
	u.m[network][key] = c
}

// claim makes change gen of key the one being told now, forgetting any older one kept: false when a newer one has been
// made, which supersedes it.
func (u *untold) claim(network string, key untoldKey, gen uint64) bool {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.supersededLocked(network, key, gen) {
		return false
	}
	if kept, ok := u.m[network][key]; ok && kept.gen <= gen {
		delete(u.m[network], key)
	}
	return true
}

// putBack keeps c again, for the next time, unless it was superseded meanwhile.
func (u *untold) putBack(network string, key untoldKey, c untoldChange) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.latest[network][key] != c.gen {
		return
	}
	if u.m[network] == nil {
		u.m[network] = map[untoldKey]untoldChange{}
	}
	u.m[network][key] = c
}

// forget drops everything kept or remembered for key: its chat is gone.
func (u *untold) forget(network string, key untoldKey) {
	u.mu.Lock()
	defer u.mu.Unlock()
	delete(u.m[network], key)
	delete(u.latest[network], key)
}

// take removes and returns every change kept for network; each key's latest stays, so a change made meanwhile still
// supersedes them.
func (u *untold) take(network string) map[untoldKey]untoldChange {
	u.mu.Lock()
	defer u.mu.Unlock()
	out := u.m[network]
	delete(u.m, network)
	return out
}

// retell tells h's network the chat changes made while it couldn't be told, now that it may be connected
// (retellKept).
func (a *Actions) retell(ctx context.Context, h *host.Host) {
	a.retellKept(ctx, h, a.untold.take(h.Network))
}

// retellKept tells h's network each of kept, changes taken from untold: one whose chat's login is logged in goes (best
// effort, as bestEffort, through tellNow) unless a newer change of its key has been made since; one whose login is
// still down is kept again for the next time; one the network's client doesn't take, or whose chat is gone, is
// dropped.
func (a *Actions) retellKept(ctx context.Context, h *host.Host, kept map[untoldKey]untoldChange) {
	for key, c := range kept {
		room, ok, err := a.s.GetRoom(ctx, key.room)
		if err != nil {
			a.untold.putBack(h.Network, key, c)
			continue
		}
		if !ok {
			a.untold.forget(h.Network, key) // the chat is gone
			continue
		}
		l := loginOf(ctx, h, room)
		if l == nil || !l.Client.IsLoggedIn() {
			a.untold.putBack(h.Network, key, c)
			continue
		}
		if !c.takesIt(l.Client) {
			continue
		}
		a.tellNow(ctx, h, key, c.change, c.evt, c.gen)
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
	if !supported(ctx, h, room, syncAccept) {
		return ErrNotSupported
	}
	if err = a.s.SetRequest(ctx, roomID, false); err != nil {
		return err
	}
	a.tell(ctx, room, h, syncAccept, event.BeeperAcceptMessageRequest, &event.BeeperAcceptMessageRequestEventContent{})
	return nil
}
