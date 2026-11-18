// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

func backwardFetches(n *fakenet.Network) int {
	c := 0
	for _, f := range n.Fetches() {
		if !f.Forward {
			c++
		}
	}
	return c
}

// historyWorld is a chat whose network has 250 older messages: its first backfill takes the newest 50, and a page of
// older history is 100.
func historyWorld(t *testing.T, gate chan struct{}) (w world, room string) {
	t.Helper()
	n := fakenet.New()
	n.FetchGate = gate
	base := time.Now().Add(-1000 * time.Hour).Truncate(time.Second)
	var h []fakenet.HistoryMessage
	for i := range 250 {
		h = append(h, fakenet.HistoryMessage{ID: fmt.Sprintf("h%03d", i), Sender: "alice", Body: fmt.Sprintf("history %03d", i), At: base.Add(time.Duration(i) * time.Minute)})
	}
	n.SetHistory("chat", h)
	w = startWorldOn(t, "fake", n, true, zerolog.Nop())
	room, _ = w.chat(t, "chat", "live")
	require.Eventually(t, func() bool { return countMessages(t, w.s, room) == 50+1 }, 5*time.Second, 20*time.Millisecond,
		"the first backfill is the newest 50, then the message that arrived")
	return w, room
}

func countMessages(t *testing.T, s *store.Store, room string) int {
	t.Helper()
	evs, err := s.Events(context.Background(), room, 5000)
	require.NoError(t, err)
	n := 0
	for _, e := range evs {
		if e.Type == "m.room.message" && strings.Contains(string(e.Content), "body") {
			n++
		}
	}
	return n
}

// Nothing is loaded until asked: opening a chat makes the first backfill and no page of older history.
func TestOlderHistoryIsNotLoadedInTheBackground(t *testing.T) {
	w, _ := historyWorld(t, nil)
	time.Sleep(300 * time.Millisecond)
	require.Zero(t, backwardFetches(w.n))
}

// One call loads one page; the page after it is the last, and then there is nothing more, which costs no fetch.
func TestLoadOlderLoadsOnePageAtATimeUntilExhausted(t *testing.T) {
	ctx := context.Background()
	w, room := historyWorld(t, nil)

	res, err := w.a.LoadOlder(ctx, room)
	require.NoError(t, err)
	require.Equal(t, LoadOlderResult{Added: 100, HasMore: true}, res)
	require.Equal(t, 1, backwardFetches(w.n), "exactly one page")
	require.Equal(t, 151, countMessages(t, w.s, room))

	res, err = w.a.LoadOlder(ctx, room)
	require.NoError(t, err)
	require.Equal(t, LoadOlderResult{Added: 100, HasMore: false}, res, "the network has no more after this page")
	require.Equal(t, 2, backwardFetches(w.n))
	require.Equal(t, 251, countMessages(t, w.s, room))

	res, err = w.a.LoadOlder(ctx, room)
	require.NoError(t, err)
	require.Equal(t, LoadOlderResult{}, res)
	require.Equal(t, 2, backwardFetches(w.n), "an exhausted chat is not asked again")
}

// A second call while a page is loading does not start another.
func TestLoadOlderRunsOneLoadPerChat(t *testing.T) {
	ctx := context.Background()
	gate := make(chan struct{})
	w, room := historyWorld(t, gate)

	first := make(chan LoadOlderResult, 1)
	go func() {
		r, err := w.a.LoadOlder(ctx, room)
		require.NoError(t, err)
		first <- r
	}()
	require.Eventually(t, func() bool { return backwardFetches(w.n) == 1 }, 5*time.Second, 10*time.Millisecond, "the first load reaches the network")

	res, err := w.a.LoadOlder(ctx, room)
	require.NoError(t, err)
	require.Equal(t, LoadOlderResult{HasMore: true, Loading: true}, res, "a load is already running")
	require.Equal(t, 1, backwardFetches(w.n))

	gate <- struct{}{}
	require.Equal(t, LoadOlderResult{Added: 100, HasMore: true}, <-first)
	require.Equal(t, 1, backwardFetches(w.n), "the second call asked the network nothing")
}

func TestLoadOlderUnknownChatAndNetworksWithoutHistory(t *testing.T) {
	w := startWorld(t, "fake", true)
	_, err := w.a.LoadOlder(context.Background(), "!nowhere:courier.local")
	require.ErrorIs(t, err, store.ErrNotFound)

	room, _ := w.chat(t, "plain", "m1") // a chat whose network has no history to give
	res, err := w.a.LoadOlder(context.Background(), room)
	require.NoError(t, err)
	require.False(t, res.HasMore, "no backfill task: nothing more, so the app shows nothing")
	require.Zero(t, backwardFetches(w.n))
}
