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
// Inferred (inventory 01 §4): the 4 s pulse, and the app's stop 5 s after the last change, are Courier's; the
// inventory says typing shows, not how often it is sent.
const TypingRepeat = 4 * time.Second

// typingRenew is how old my last start must be for a pulse to renew it: a stop, then a start. bridgev2 hands a start
// to the network only when the chat's typing list changes (portal.go:1038-1053 of mautrix v0.31.0), and the networks
// time a start out (Telegram after about 5 s), so a start that is never renewed blinks off. It is a second short of
// TypingRepeat (Ruling C14): the app's pulse that comes a few milliseconds early still renews, rather than waiting a
// whole second pulse (8 s, past Telegram's timeout).
//
// Inferred (inventory 01 §4): the renewal, as a stop then a start, is Courier's answer to bridgev2 sending a start
// once.
const typingRenew = TypingRepeat - time.Second

// typingState is my typing per chat, as the networks were last told it, and the typing events still to be handed to
// the bridges. It lives in memory: after a restart nobody is typing.
//
// Deciding is quick and happens on the caller's goroutine; handing an event to the bridge is not. With
// PortalEventBuffer 0 bridgev2 handles a chat's events in line, under the chat's lock, and calls the network's
// HandleMatrixTyping inside it, so a typing event can wait behind a send still in flight in that chat (an upload, a
// slow network). So each chat's events go out on a goroutine of their own, in the order they were decided (one
// drainer per chat at a time, which ends when the chat's queue is empty), and nothing a person does waits for them:
// a held message is still answered at once (dispatch).
type typingState struct {
	mu     sync.Mutex
	chats  map[string]*chatTyping
	closed bool           // StopTyping has run: nothing more is handed over
	wg     sync.WaitGroup // the drainers running
}

// chatTyping is my typing in one chat: when my last start went out, and the events decided and not yet handed over.
type chatTyping struct {
	since    time.Time // zero while I'm not typing
	queue    []typingSend
	draining bool // a drainer is handing queue over
}

// typingSend is one typing event to hand over: me typing (on) in room, or nobody, through h.
type typingSend struct {
	ctx  context.Context
	h    *host.Host
	room store.Room
	on   bool
}

// chat is roomID's typing state, made on first use. The caller holds t.mu.
func (t *typingState) chat(roomID string) *chatTyping {
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
// It answers at once: the events go to the bridge behind the chat's earlier ones (typingState), never ahead of them.
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
	t := &a.typing
	t.mu.Lock()
	defer t.mu.Unlock()
	ct := t.chat(roomID)
	now := a.now()
	switch {
	case !typing:
		if ct.since.IsZero() {
			return nil
		}
		ct.since = time.Time{}
		a.queueTyping(ct, typingSend{ctx: ctx, h: h, room: room, on: false})
	case ct.since.IsZero():
		ct.since = now
		a.queueTyping(ct, typingSend{ctx: ctx, h: h, room: room, on: true})
	case now.Sub(ct.since) >= typingRenew:
		ct.since = now
		a.queueTyping(ct, typingSend{ctx: ctx, h: h, room: room, on: false}, typingSend{ctx: ctx, h: h, room: room, on: true})
	}
	return nil
}

// stopTyping sends a stop for my typing in room, if I'm typing there and its network is connected. A new message
// stops it first (dispatch, the one path every new message takes: Ruling C8). It doesn't wait for the stop to reach
// the bridge (typingState).
func (a *Actions) stopTyping(ctx context.Context, h *host.Host, room store.Room) {
	if h == nil || !a.connected(ctx, h, room) {
		return
	}
	t := &a.typing
	t.mu.Lock()
	defer t.mu.Unlock()
	ct := t.chat(room.ID)
	if ct.since.IsZero() {
		return
	}
	ct.since = time.Time{}
	a.queueTyping(ct, typingSend{ctx: ctx, h: h, room: room, on: false})
}

// queueTyping puts sends at the end of ct's queue and starts its drainer if none is running. The caller holds
// a.typing.mu. After StopTyping nothing is queued. A send keeps its caller's values but not its cancellation: the
// request it came from has been answered by the time it goes.
func (a *Actions) queueTyping(ct *chatTyping, sends ...typingSend) {
	t := &a.typing
	if t.closed {
		return
	}
	for _, s := range sends {
		s.ctx = context.WithoutCancel(s.ctx)
		ct.queue = append(ct.queue, s)
	}
	if ct.draining {
		return
	}
	ct.draining = true
	t.wg.Add(1)
	go a.drainTyping(ct)
}

// drainTyping hands ct's queued events to the bridge, oldest first, until the queue is empty. Each one is bounded by
// the bridge: bridgev2 handles it once the chat's earlier events are done, and a stopped bridge refuses it at once.
func (a *Actions) drainTyping(ct *chatTyping) {
	t := &a.typing
	defer t.wg.Done()
	for {
		t.mu.Lock()
		if len(ct.queue) == 0 {
			ct.draining = false
			t.mu.Unlock()
			return
		}
		s := ct.queue[0]
		ct.queue = ct.queue[1:]
		t.mu.Unlock()
		a.sendTyping(s.ctx, s.h, s.room, s.on)
	}
}

// StopTyping ends typing hand-overs: nothing more is queued, and it waits for the events already queued to reach the
// bridges. The engine calls it on shutdown, before the bridges stop.
func (a *Actions) StopTyping() {
	a.typing.mu.Lock()
	a.typing.closed = true
	a.typing.mu.Unlock()
	a.typing.wg.Wait()
}

// typingSettled waits until every typing event queued so far has been handed to its bridge (for tests). Nothing may
// queue while it waits.
func (a *Actions) typingSettled() { a.typing.wg.Wait() }

// sendTyping hands the bridge an m.typing ephemeral event for room: me typing (on), or nobody. It has no sender or ID,
// the way bridgev2 receives typing from a Matrix server (as MarkRead's receipt). bridgev2 tells the network of the
// change in the chat's typing list (handleMatrixTyping) through the network's TypingHandlingNetworkAPI; a network
// without one gets nothing.
//
// bridgev2's handleMatrixTyping answers success whatever the network says (it logs a failure itself, under its own
// logger), so the warning below is only a guard for an event bridgev2 couldn't take at all (no portal, a stopped
// bridge). It names the network and the kind of thing only.
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
