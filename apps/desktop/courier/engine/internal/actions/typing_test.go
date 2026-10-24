// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// My typing goes out through bridgev2 (an m.typing ephemeral event for the chat) and reaches the network's
// HandleMatrixTyping: a start, then a stop. A stop while I'm not typing says nothing new.
func TestTypingReachesTheNetworkThroughBridgev2(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	require.NoError(t, w.a.SetTyping(ctx, room, true))
	require.Equal(t, fakenet.TypingChange{PortalID: "chat1", Typing: true}, recv(t, w.n.Typings, "the typing start"))
	require.NoError(t, w.a.SetTyping(ctx, room, false))
	require.Equal(t, fakenet.TypingChange{PortalID: "chat1", Typing: false}, recv(t, w.n.Typings, "the typing stop"))
	require.NoError(t, w.a.SetTyping(ctx, room, false))
	none(t, w.n.Typings, "a stop while not typing")

	require.ErrorIs(t, w.a.SetTyping(ctx, "!nope:courier.local", true), store.ErrNotFound, "an unknown chat")
}

// Review Focus 3, surprise 4: bridgev2 sends a start once per change, and the networks time a start out (Telegram
// after about 5 s), so the app pulses every TypingRepeat while the text keeps changing and the engine turns a pulse
// into a stop and a start once the last start is a second short of TypingRepeat old (Ruling C14: a pulse a little
// early still renews it). A pulse sooner is nothing. Sending stops my typing first.
func TestTypingRepeatsEveryFourSecondsAndStopsOnSend(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	clock := w.clocked()
	start := clock.Now()
	at := func(d time.Duration) { clock.Set(start.Add(d)) }
	pulse := func() {
		t.Helper()
		require.NoError(t, w.a.SetTyping(ctx, room, true))
	}
	started := fakenet.TypingChange{PortalID: "chat1", Typing: true}
	stopped := fakenet.TypingChange{PortalID: "chat1", Typing: false}

	pulse()
	require.Equal(t, started, recv(t, w.n.Typings, "the first start"))
	at(2999 * time.Millisecond)
	pulse()
	none(t, w.n.Typings, "a pulse 3 s after the start")

	at(3990 * time.Millisecond) // the app's 4 s pulse, a little early
	pulse()
	require.Equal(t, stopped, recv(t, w.n.Typings, "the renewal's stop"))
	require.Equal(t, started, recv(t, w.n.Typings, "the renewal's start"))
	at(5990 * time.Millisecond)
	pulse()
	none(t, w.n.Typings, "a pulse 2 s after the renewal")

	at(7990 * time.Millisecond) // the next 4 s pulse
	pulse()
	require.Equal(t, stopped, recv(t, w.n.Typings, "the second renewal's stop"))
	require.Equal(t, started, recv(t, w.n.Typings, "the second renewal's start"))

	at(8500 * time.Millisecond)
	_, err := w.a.SendText(ctx, room, "done typing", "")
	require.NoError(t, err)
	require.Equal(t, stopped, recv(t, w.n.Typings, "the stop on send"))
	require.Equal(t, "done typing", recv(t, w.n.Sent, "the message").Body)
	require.NoError(t, w.a.SetTyping(ctx, room, false))
	none(t, w.n.Typings, "a stop after the send's")

	// Typing again after the send is a new start at once.
	at(9 * time.Second)
	pulse()
	require.Equal(t, started, recv(t, w.n.Typings, "the start after sending"))

	// A send while not typing tells the network nothing about typing.
	require.NoError(t, w.a.SetTyping(ctx, room, false))
	require.Equal(t, stopped, recv(t, w.n.Typings, "the stop"))
	_, err = w.a.SendText(ctx, room, "again", "")
	require.NoError(t, err)
	recv(t, w.n.Sent, "the second message")
	none(t, w.n.Typings, "typing from a send while not typing")
}

// Review Focus 3: nothing goes out for a chat whose network isn't connected (its login is down, or the network isn't
// running), and that is no error: the composer pulses whatever.
func TestTypingToADownNetworkIsNothing(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	require.NoError(t, w.a.SetTyping(ctx, room, true))
	require.NoError(t, w.a.SetTyping(ctx, room, false))
	none(t, w.n.Typings, "typing while the login is down")

	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!tg:courier.local", Network: "telegram", Name: "Elsewhere"}))
	require.NoError(t, w.a.SetTyping(ctx, "!tg:courier.local", true), "a network that isn't running")

	w.up()
	require.NoError(t, w.a.SetTyping(ctx, room, true))
	require.Equal(t, fakenet.TypingChange{PortalID: "chat1", Typing: true}, recv(t, w.n.Typings, "the start once it is back"))
}

// syncBuffer is a bytes.Buffer safe for the bridge's goroutines to log into while the test reads it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// Never log who: typing and receipts carry user IDs, and the engine logs none of them (at the level the engine runs
// at, warn), even when the network refuses typing or a delivery names nothing Courier has. My own ID is
// "@me:courier.local" on every Mac, so it names no one; a contact's ID (their ghost) must never appear.
//
// The warnings this reads are bridgev2's own: its handleMatrixTyping answers success whatever the network says and
// logs the failure itself, so the engine's typing warning (sendTyping) never fires here. What is checked is that the
// typing, receipt and delivery paths, end to end, put no contact in the log.
func TestTypingNeverLogsWho(t *testing.T) {
	ctx := context.Background()
	logs := &syncBuffer{}
	n := fakenet.New()
	direct := true
	n.SetChat("chat1", fakenet.Chat{Direct: &direct}) // one-to-one, so bridgev2 takes its deliveries (surprise 2)
	w := startWorldOn(t, "fake", n, true, zerolog.New(logs).Level(zerolog.WarnLevel))
	room, _ := w.chat(t, "chat1", "m1")

	// Typing in, from the contact, and out, more than the network takes (its buffer fills and it refuses).
	n.Typing(w.login, "chat1", "alice", time.Minute)
	clock := w.clocked()
	for i := range 40 {
		clock.Set(clock.Now().Add(5 * time.Second))
		require.NoError(t, w.a.SetTyping(ctx, room, i%2 == 0))
	}
	// Typing to a down network.
	w.down()
	require.NoError(t, w.a.SetTyping(ctx, room, true))
	w.up()
	// A delivery for a message Courier doesn't have, and the contact's read receipt.
	//
	// Not here: a read receipt naming a message bridgev2 never bridged. bridgev2 itself warns of it ("No target message
	// found for read receipt") with the remote sender's network ID in its log context (remote_sender, which it puts on
	// every remote event it handles). That is bridgev2's logger, not this path's, and it is reported for the engine's
	// log as a whole rather than pinned here.
	n.Receipt(w.login, "chat1", "alice", []string{"no-such-message"}, true)
	n.Receipt(w.login, "chat1", "alice", []string{"m1"}, false)
	// A read of mine, which bridgev2 handles after those: once the chat is read, they have all been handled.
	n.Receipt(w.login, "chat1", "me", []string{"m1"}, false)
	require.Eventually(t, func() bool { return w.unread(t, room) == 0 }, 5*time.Second, 20*time.Millisecond)
	w.a.typingSettled() // every typing event has reached the bridge, and its refusals are logged

	out := logs.String()
	require.NotEmpty(t, out, "fixture: the refused typing was logged")
	ghost := string(ids.GhostMXID("fake", "alice"))
	ghostJSON, _ := json.Marshal(ghost)
	for _, who := range []string{ghost, string(ghostJSON[1 : len(ghostJSON)-1]), "alice"} {
		require.NotContains(t, out, who, "the log names a contact")
	}
}

// Typing never holds up what a person does. bridgev2 hands a chat's events to the network in line, one at a time, so
// a typing event can wait behind a send still in flight in that chat. Neither a pulse nor a held message (undo send:
// "answered at once") waits for it, and the chat's typing still reaches the network in order once the send is done.
func TestTypingNeverHoldsUpASendOrAPulse(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Hold = make(chan struct{})
	n.Holding = make(chan struct{}, 4)
	var release sync.Once
	let := func() { release.Do(func() { close(n.Hold) }) }
	t.Cleanup(let)
	w := startWorldOn(t, "fake", n, true, zerolog.Nop())
	room, _ := w.chat(t, "chat1", "m1")
	started := fakenet.TypingChange{PortalID: "chat1", Typing: true}
	stopped := fakenet.TypingChange{PortalID: "chat1", Typing: false}
	within := func(done <-chan error, what string) {
		t.Helper()
		select {
		case err := <-done:
			require.NoError(t, err, what)
		case <-time.After(5 * time.Second):
			t.Fatalf("%s waited for the send in flight", what)
		}
	}
	async := func(f func() error) <-chan error {
		done := make(chan error, 1)
		go func() { done <- f() }()
		return done
	}

	require.NoError(t, w.a.SetTyping(ctx, room, true))
	require.Equal(t, started, recv(t, n.Typings, "the start"))
	// The send's stop and the send itself both want the chat: either may reach it first.
	sent := async(func() error { _, err := w.a.SendText(ctx, room, "slow", ""); return err })
	recv(t, n.Holding, "the send reaching the network")

	// The send is in flight, holding the chat's events: I start typing again, then send with an undo window.
	within(async(func() error { return w.a.SetTyping(ctx, room, true) }), "a pulse")
	within(async(func() error {
		_, err := w.a.Send(ctx, room, "held", SendOptions{Hold: time.Second})
		return err
	}), "a held message")
	// The chat's typing waits behind the send in flight: its drainer is stuck handing over one event (the send's stop,
	// or the pulse's start if the stop went first), and the held message's stop is still queued after it.
	w.a.typing.mu.Lock()
	queue := append([]typingSend(nil), w.a.typing.chats[room].queue...)
	w.a.typing.mu.Unlock()
	require.NotEmpty(t, queue, "typing waits behind the send in flight")
	require.False(t, queue[len(queue)-1].on, "the held message's stop is last")

	let()
	within(sent, "the send in flight")
	w.a.typingSettled()
	require.Equal(t, stopped, recv(t, n.Typings, "the send's stop"))
	require.Equal(t, started, recv(t, n.Typings, "the pulse's start, once the send is done"))
	require.Equal(t, stopped, recv(t, n.Typings, "the held message's stop, after it"))
	require.Empty(t, n.Typings, "nothing more")
}

// Shutdown never hangs on typing: StopTyping waits a bounded time for the typing on its way to the bridges, so typing
// stuck behind a send in flight (what would free it is the bridges stopping, after StopTyping) can't hold it up.
func TestStopTypingWaitsABoundedTime(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Hold = make(chan struct{})
	n.Holding = make(chan struct{}, 4)
	var release sync.Once
	let := func() { release.Do(func() { close(n.Hold) }) }
	t.Cleanup(let)
	w := startWorldOn(t, "fake", n, true, zerolog.Nop())
	room, _ := w.chat(t, "chat1", "m1")

	require.NoError(t, w.a.SetTyping(ctx, room, true))
	recv(t, n.Typings, "the start")
	go func() { _, _ = w.a.SendText(ctx, room, "slow", "") }()
	recv(t, n.Holding, "the send reaching the network")
	clock := w.clocked()
	clock.Set(clock.Now().Add(TypingRepeat))
	require.NoError(t, w.a.SetTyping(ctx, room, true)) // queued behind the send

	stopped := make(chan bool, 1)
	go func() { stopped <- w.a.StopTyping(50 * time.Millisecond) }()
	select {
	case ok := <-stopped:
		require.False(t, ok, "typing was still on its way")
	case <-time.After(5 * time.Second):
		t.Fatal("StopTyping waited for typing stuck behind a send")
	}
	require.NoError(t, w.a.SetTyping(ctx, room, false), "after it nothing more is queued, and that is no error")

	let()
	w.a.typingSettled()
	require.True(t, w.a.StopTyping(time.Minute), "with nothing on its way it is done at once")
}
