// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// timerState is the chat's stored com.beeper.disappearing_timer, or "" when none is stored.
func (w world) timerState(t *testing.T, room string) string {
	t.Helper()
	raw, ok, err := w.s.GetState(context.Background(), room, event.StateBeeperDisappearingTimer.Type, "")
	require.NoError(t, err)
	if !ok {
		return ""
	}
	return string(raw)
}

// roomChange waits on ch for a "room" change of room.
func roomChange(t *testing.T, ch <-chan store.Change, room string) {
	t.Helper()
	for {
		select {
		case c := <-ch:
			if c.Kind == "room" && c.RoomID == room {
				return
			}
		case <-time.After(5 * time.Second):
			t.Fatalf("no room change for %s", room)
		}
	}
}

func TestSetDisappearingTakesOnlyOfferedTimers(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures()) // after send: 1, 7 or 90 days
	before := w.timerState(t, room)                     // the bridge may have stored "no timer" ({}) when it made the chat
	for _, tc := range []struct {
		typ   string
		timer time.Duration
	}{
		{"after_send", time.Hour},
		{"after_read", 24 * time.Hour},
		{"", 24 * time.Hour},
		{"after_send", 0},
	} {
		require.ErrorIs(t, w.a.SetDisappearing(ctx, room, tc.typ, tc.timer), ErrBadValue, "%s %s", tc.typ, tc.timer)
	}
	require.Empty(t, w.n.Timers)
	require.Equal(t, before, w.timerState(t, room))

	ch, cancel := w.s.Subscribe()
	defer cancel()
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 7*24*time.Hour))
	require.Equal(t, fakenet.TimerChange{PortalID: "alice", Type: "after_send", Timer: 7 * 24 * time.Hour}, recv(t, w.n.Timers, "the timer"))
	require.JSONEq(t, `{"type":"after_send","timer":604800000}`, w.timerState(t, room))
	roomChange(t, ch, room)

	require.NoError(t, w.a.SetDisappearing(ctx, room, "", 0))
	require.Equal(t, fakenet.TimerChange{PortalID: "alice"}, recv(t, w.n.Timers, "the timer turned off"))
	require.JSONEq(t, `{}`, w.timerState(t, room))
	roomChange(t, ch, room)

	// A chat whose network has no timer.
	w2, room2 := startFeatureWorld(t, googleMessagesFeatures())
	require.ErrorIs(t, w2.a.SetDisappearing(ctx, room2, "after_send", 24*time.Hour), ErrNotSupported)
	require.ErrorIs(t, w2.a.SetDisappearing(ctx, room2, "", 0), ErrNotSupported)
	require.Empty(t, w2.n.Timers)
}

func TestRefusedTimerChangesNothing(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	before := w.timerState(t, room)
	w.n.Refuse = true
	err := w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour)
	require.ErrorIs(t, err, ErrNetworkRefused)
	require.ErrorContains(t, err, "fakenet:", "the bridge's reason comes with it")
	require.Equal(t, before, w.timerState(t, room), "nothing stored")
	require.Empty(t, w.n.Timers)

	// So a message sent next carries no timer.
	w.n.Refuse = false
	id, err := w.a.Send(ctx, room, "stays", SendOptions{})
	require.NoError(t, err)
	require.NotContains(t, content(t, w.get(t, id)), "com.beeper.disappearing_timer")
	recv(t, w.n.Sent, "the message")
}

// Setting the timer a chat already has is "ignored" by the bridge, with no error: nothing to change, nothing wrong.
func TestSetDisappearingToTheSameTimerIsNoChange(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour))
	recv(t, w.n.Timers, "the timer")
	state := w.timerState(t, room)

	ch, cancel := w.s.Subscribe()
	defer cancel()
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour))
	require.Empty(t, w.n.Timers, "the bridge didn't ask the network again")
	require.Equal(t, state, w.timerState(t, room))
	for {
		select {
		case c := <-ch:
			require.False(t, c.Kind == "room" && c.RoomID == room, "nothing changed, so nothing is published")
			continue
		default:
		}
		break
	}
}
