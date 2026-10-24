// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"sync"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// TypingRepeat is how often the app pulses my typing (room.setTyping true) while the text keeps changing
// (surprise 4). It is protocol.json's conventions.typing_repeat_ms: Task 7 adds that key and pins this constant to it
// (TestTypingRepeatMatchesTheProtocol), as Task 8 pins the app's ComposerModel.typingRepeat.
//
// Inferred: the 4 s pulse, and the app's stop 5 s after the last change, are Courier's (01 §4 says typing shows, not
// how often it is sent).
const TypingRepeat = 4 * time.Second

// typingRenew is how old my last start must be for a pulse to renew it: a stop, then a start. bridgev2 hands a start
// to the network only when the chat's typing list changes (portal.go:1038-1053 of mautrix v0.31.0), and the networks
// time a start out (Telegram after about 5 s), so a start that is never renewed blinks off. It is a second short of
// TypingRepeat (Ruling C14): the app's pulse that comes a few milliseconds early still renews, rather than waiting a
// whole second pulse (8 s, past Telegram's timeout).
const typingRenew = TypingRepeat - time.Second

// typingState is my typing per chat, as the networks were last told it. It lives in memory: after a restart nobody
// is typing.
type typingState struct {
	mu    sync.Mutex
	chats map[string]*chatTyping
}

// chatTyping is my typing in one chat. Its lock is held while the chat's typing events are handed to the bridge, so
// they reach the network in the order they were decided; other chats don't wait for it.
type chatTyping struct {
	mu    sync.Mutex
	since time.Time // when my last start went out; zero while I'm not typing
}

// chat is roomID's typing state, made on first use.
func (t *typingState) chat(roomID string) *chatTyping {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.chats == nil {
		t.chats = map[string]*chatTyping{}
	}
	c := t.chats[roomID]
	if c == nil {
		c = &chatTyping{}
		t.chats[roomID] = c
	}
	return c
}

// SetTyping tells the chat's network that I am typing in roomID, or that I stopped (01 §4, §5). The app pulses true
// every TypingRepeat while the text keeps changing, and false when I stop, clear the box or leave the chat:
//   - true while I'm not typing sends a start. True again sooner than typingRenew after the last start is nothing;
//     later, it is a stop and then a start, so the network keeps showing it (surprise 4).
//   - false sends a stop, only while I'm typing.
//
// It is best effort: a chat whose network isn't connected (not running, starting, or the chat's login logged out)
// gets nothing, and that is no error (Review Focus 3). Nothing is kept for later: typing then would be stale. An
// unknown chat is store.ErrNotFound. Never logs who.
func (a *Actions) SetTyping(ctx context.Context, roomID string, typing bool) error {
	room, h, err := a.chatHost(ctx, roomID)
	if err != nil {
		return err
	}
	if h == nil || !a.connected(ctx, h, room) {
		return nil
	}
	ct := a.typing.chat(roomID)
	ct.mu.Lock()
	defer ct.mu.Unlock()
	now := a.now()
	switch {
	case !typing:
		if ct.since.IsZero() {
			return nil
		}
		ct.since = time.Time{}
		a.sendTyping(ctx, h, room, false)
	case ct.since.IsZero():
		ct.since = now
		a.sendTyping(ctx, h, room, true)
	case now.Sub(ct.since) >= typingRenew:
		ct.since = now
		a.sendTyping(ctx, h, room, false)
		a.sendTyping(ctx, h, room, true)
	}
	return nil
}

// stopTyping sends a stop for my typing in room, if I'm typing there and its network is connected. A new message
// stops it first (dispatch, the one path every new message takes: Ruling C8).
func (a *Actions) stopTyping(ctx context.Context, h *host.Host, room store.Room) {
	if h == nil || !a.connected(ctx, h, room) {
		return
	}
	ct := a.typing.chat(room.ID)
	ct.mu.Lock()
	defer ct.mu.Unlock()
	if ct.since.IsZero() {
		return
	}
	ct.since = time.Time{}
	a.sendTyping(ctx, h, room, false)
}

// sendTyping hands the bridge an m.typing ephemeral event for room: me typing (on), or nobody. It has no sender or ID,
// the way bridgev2 receives typing from a Matrix server (as MarkRead's receipt). bridgev2 tells the network of the
// change in the chat's typing list (handleMatrixTyping) through the network's TypingHandlingNetworkAPI; a network
// without one gets nothing. A failure is logged at warn with the network and the kind of thing only.
func (a *Actions) sendTyping(ctx context.Context, h *host.Host, room store.Room, on bool) {
	users := []id.UserID{}
	if on {
		users = []id.UserID{ids.Me}
	}
	res := h.Bridge.QueueMatrixEvent(ctx, &event.Event{
		Type: event.EphemeralEventTyping, RoomID: id.RoomID(room.ID),
		Content: event.Content{Parsed: &event.TypingEventContent{UserIDs: users}},
		Mautrix: event.MautrixInfo{EventSource: event.SourceEphemeral},
	})
	if !res.Success || res.Ignored || res.Error != nil {
		h.Bridge.Log.Warn().Str("network", h.Network).Str("change", "typing").Msg("the network wasn't told of typing")
	}
}
