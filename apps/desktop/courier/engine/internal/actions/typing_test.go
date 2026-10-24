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
// at, warn), even when the network refuses typing or a receipt names nothing Courier has. My own ID is
// "@me:courier.local" on every Mac, so it names no one; a contact's ID (their ghost) must never appear.
func TestTypingNeverLogsWho(t *testing.T) {
	ctx := context.Background()
	logs := &syncBuffer{}
	n := fakenet.New()
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

	out := logs.String()
	require.NotEmpty(t, out, "fixture: the refused typing was logged")
	ghost := string(ids.GhostMXID("fake", "alice"))
	ghostJSON, _ := json.Marshal(ghost)
	for _, who := range []string{ghost, string(ghostJSON[1 : len(ghostJSON)-1]), "alice"} {
		require.NotContains(t, out, who, "the log names a contact")
	}
}
