// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
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

// timerNotes is room's timer-change notes (content with a disappearing_timer action message), oldest first.
func (w world) timerNotes(t *testing.T, room string) []store.Event {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1000)
	require.NoError(t, err)
	var out []store.Event
	for i := len(evs) - 1; i >= 0; i-- {
		var c struct {
			Action struct {
				Type string `json:"type"`
			} `json:"com.beeper.action_message"`
		}
		if json.Unmarshal(evs[i].Content, &c) == nil && c.Action.Type == "disappearing_timer" {
			out = append(out, evs[i])
		}
	}
	return out
}

// nothingReachedTheNetwork checks that no message, file, edit, deletion, poll or vote was delivered. The note is
// never handed to the bridge, so there is nothing in flight to wait for.
func (w world) nothingReachedTheNetwork(t *testing.T) {
	t.Helper()
	require.Zero(t, len(w.n.Sent), "a message")
	require.Zero(t, len(w.n.Files), "a file")
	require.Zero(t, len(w.n.Edits), "an edit")
	require.Zero(t, len(w.n.Removes), "a deletion")
	require.Zero(t, len(w.n.Polls)+len(w.n.Votes), "a poll")
	require.Empty(t, w.n.Raws())
}

// Ruling 40: a timer changed in Courier gets a note, as one changed on the phone does from the bridge: exactly one,
// in the bridge's shape, mine, never sent to the network, not unread, and previewed as a timer change.
func TestTimerChangeMadeHereLeavesOneQuietNote(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	require.Empty(t, w.timerNotes(t, room))
	unread := w.unread(t, room)

	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 7*24*time.Hour))
	recv(t, w.n.Timers, "the timer")
	notes := w.timerNotes(t, room)
	require.Len(t, notes, 1)
	require.Equal(t, string(ids.Me), notes[0].Sender, "mine: the app never notifies of my own")
	require.Equal(t, "sent", notes[0].Status)
	require.JSONEq(t, `{"msgtype":"m.notice","body":"","m.mentions":{},"fi.courier.local":true,
		"com.beeper.action_message":{"type":"disappearing_timer","timer":604800000,"timer_type":"after_send","implicit":false}}`,
		string(notes[0].Content))
	w.nothingReachedTheNetwork(t)
	require.Equal(t, unread, w.unread(t, room), "not unread")
	row := w.row(t, room)
	require.Equal(t, "timer_change", row.PreviewKind)
	require.Empty(t, row.Preview)
	require.True(t, row.PreviewMine)

	// The timer it already has changes nothing, so there is nothing to note.
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 7*24*time.Hour))
	require.Len(t, w.timerNotes(t, room), 1)

	// Off is a change.
	require.NoError(t, w.a.SetDisappearing(ctx, room, "", 0))
	recv(t, w.n.Timers, "the timer turned off")
	notes = w.timerNotes(t, room)
	require.Len(t, notes, 2)
	require.Equal(t, map[string]any{"type": "disappearing_timer", "timer": float64(0), "timer_type": "", "implicit": false},
		content(t, notes[1])["com.beeper.action_message"])
	w.nothingReachedTheNetwork(t)

	// A change the network refuses never happened: no note.
	w.n.Refuse = true
	require.ErrorIs(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour), ErrNetworkRefused)
	require.Len(t, w.timerNotes(t, room), 2)
}

// bridgeTimerNotice sends what bridgev2 sends for a timer change (UpdateDisappearingSetting, portal.go:5051–5062):
// its English notice with the action message.
func bridgeTimerNotice(ctx context.Context, api bridgev2.MatrixAPI, room id.RoomID, typ event.DisappearingType, timer time.Duration) error {
	_, err := api.SendMessage(ctx, room, event.EventMessage, &event.Content{
		Parsed: bridgev2.DisappearingMessageNotice(timer, false),
		Raw: map[string]any{"com.beeper.action_message": map[string]any{
			"type": "disappearing_timer", "timer": timer.Milliseconds(), "timer_type": typ, "implicit": false,
		}},
	}, nil)
	return err
}

// Ruling 40: if a network echoes a change made here and its bridge passes the echo on as its own note, there is
// still one note, whichever arrives first.
func TestEchoOfATimerChangeIsNoSecondNote(t *testing.T) {
	ctx := context.Background()

	// The echo after my note: it is skipped, and my note stays.
	w, room := startFeatureWorld(t, whatsappFeatures())
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour))
	recv(t, w.n.Timers, "the timer")
	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)
	require.NoError(t, bridgeTimerNotice(ctx, h.Bridge.Bot, id.RoomID(room), event.DisappearingTypeAfterSend, 24*time.Hour))
	notes := w.timerNotes(t, room)
	require.Len(t, notes, 1)
	require.Equal(t, true, content(t, notes[0])["fi.courier.local"])

	// The echo while the change is on its way: the bridge's note is the one, and mine isn't written.
	n := fakenet.New()
	n.Features = whatsappFeatures()
	n.EchoTimers = true
	w2 := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	room2, _ := w2.chat(t, "alice", "m1")
	require.NoError(t, w2.a.SetDisappearing(ctx, room2, "after_send", 24*time.Hour))
	recv(t, w2.n.Timers, "the timer")
	notes = w2.timerNotes(t, room2)
	require.Len(t, notes, 1)
	require.NotContains(t, content(t, notes[0]), "fi.courier.local")
	require.Equal(t, "timer_change", w2.row(t, room2).PreviewKind, "still never the bridge's English")
}
