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
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func seconds(d time.Duration) *jsontime.Seconds { s := jsontime.S(d); return &s }

func TestFeaturesOfMapsEveryField(t *testing.T) {
	full := &event.RoomFeatures{
		Formatting: event.FormattingFeatureMap{
			event.FmtBold:          event.CapLevelFullySupported,
			event.FmtItalic:        event.CapLevelFullySupported,
			event.FmtStrikethrough: event.CapLevelFullySupported,
			event.FmtInlineCode:    event.CapLevelFullySupported,
			event.FmtCodeBlock:     event.CapLevelFullySupported,
			event.FmtBlockquote:    event.CapLevelPartialSupport, // the bridge converts it: kept
			event.FmtUnorderedList: event.CapLevelPartialSupport,
			event.FmtOrderedList:   event.CapLevelPartialSupport,
			event.FmtInlineLink:    event.CapLevelPartialSupport,
			event.FmtUserLink:      event.CapLevelFullySupported,
			event.FmtSpoiler:       event.CapLevelFullySupported,
			event.FmtAtRoomMention: event.CapLevelFullySupported,
			event.FmtHeaders:       event.CapLevelFullySupported, // no kind of Courier's: ignored
		},
		MaxTextLength:       4000,
		Poll:                event.CapLevelFullySupported,
		PollMaxOptions:      12,
		PollOptionMaxLength: 100,
		Reply:               event.CapLevelFullySupported,
		Thread:              event.CapLevelPartialSupport,
		Edit:                event.CapLevelPartialSupport,
		EditMaxAge:          seconds(15 * time.Minute),
		EditMaxCount:        10,
		Delete:              event.CapLevelFullySupported,
		DeleteMaxAge:        seconds(48 * time.Hour),
		DeleteHide:          true,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types:  []event.DisappearingType{event.DisappearingTypeAfterSend},
			Timers: []jsontime.Milliseconds{jsontime.MS(24 * time.Hour), jsontime.MS(7 * 24 * time.Hour)},
		},
	}
	require.Equal(t, Features{
		Reply: true, Thread: true,
		Edit: true, EditMaxAge: 15 * time.Minute, EditMaxCount: 10,
		Unsend: true, UnsendMaxAge: 48 * time.Hour, HideDeletedPlaceholder: true,
		Poll:         &PollFeatures{MaxOptions: 12, OptionMaxLength: 100},
		Disappearing: &DisappearingFeatures{Type: "after_send", Timers: []time.Duration{24 * time.Hour, 7 * 24 * time.Hour}},
		Formatting:   richtext.Kinds,
		MentionRoom:  true, MaxTextLength: 4000,
	}, FeaturesOf(full))

	// Unsupported, dropped and rejected are all "no"; nothing set at all is a chat that can do nothing.
	none := &event.RoomFeatures{
		Formatting: event.FormattingFeatureMap{
			event.FmtBold: event.CapLevelUnsupported, event.FmtItalic: event.CapLevelDropped,
			event.FmtSpoiler: event.CapLevelRejected, event.FmtAtRoomMention: event.CapLevelDropped,
		},
		Reply: event.CapLevelDropped, Thread: event.CapLevelUnsupported, Edit: event.CapLevelRejected,
		Delete: event.CapLevelRejected, Poll: event.CapLevelRejected, PollMaxOptions: 10,
	}
	require.Equal(t, Features{Formatting: []richtext.Kind{}}, FeaturesOf(none))
	require.Equal(t, Features{Formatting: []richtext.Kind{}}, FeaturesOf(&event.RoomFeatures{}))

	// Threads and no replies: a reply goes to the thread (Slack, WhatsApp community announcement groups).
	threads := FeaturesOf(&event.RoomFeatures{Thread: event.CapLevelFullySupported})
	require.True(t, threads.ReplyIsThread)
	require.False(t, threads.Reply)
	require.True(t, threads.Thread)

	// delete_for_me: the redaction reaches the phone but deletes for me only, so it is no unsend (Google Messages).
	gm := FeaturesOf(&event.RoomFeatures{Delete: event.CapLevelFullySupported, DeleteForMe: true})
	require.False(t, gm.Unsend)
	require.True(t, gm.DeleteReachesPhone)
	require.True(t, FeaturesOf(&event.RoomFeatures{DeleteForMe: true}).DeleteReachesPhone)

	// A poll needs the option limit the bridge advertises.
	require.Nil(t, FeaturesOf(&event.RoomFeatures{Poll: event.CapLevelFullySupported}).Poll)

	// After-read timers with no list are Signal's: Courier offers SignalTimers.
	signal := FeaturesOf(&event.RoomFeatures{DisappearingTimer: &event.DisappearingTimerCapability{
		Types: []event.DisappearingType{event.DisappearingTypeAfterRead},
	}})
	require.Equal(t, &DisappearingFeatures{Type: "after_read", Timers: SignalTimers}, signal.Disappearing)
	signal.Disappearing.Timers[0] = time.Nanosecond
	require.Equal(t, 30*time.Second, SignalTimers[0], "a chat's timers are its own copy")
	// After-send with no list takes any length: no choices to offer.
	require.Equal(t, &DisappearingFeatures{Type: "after_send"}, FeaturesOf(&event.RoomFeatures{
		DisappearingTimer: &event.DisappearingTimerCapability{Types: []event.DisappearingType{event.DisappearingTypeAfterSend}},
	}).Disappearing)
	require.Nil(t, FeaturesOf(&event.RoomFeatures{DisappearingTimer: &event.DisappearingTimerCapability{}}).Disappearing)

	require.Equal(t, NoFeatures, FeaturesOf(nil))
	for _, k := range richtext.Kinds {
		require.True(t, FeaturesOf(full).Keeps(k), k)
		require.False(t, FeaturesOf(none).Keeps(k), k)
	}
	require.False(t, FeaturesOf(&event.RoomFeatures{Formatting: event.FormattingFeatureMap{event.FmtBold: event.CapLevelFullySupported}}).Keeps(richtext.Italic))
}

// startFeatureWorld is a linked world whose network says rf about every chat, with one chat made.
func startFeatureWorld(t *testing.T, rf *event.RoomFeatures) (world, string) {
	t.Helper()
	n := fakenet.New()
	n.Features = rf
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	room, _ := w.chat(t, "alice", "m1")
	return w, room
}

func TestStoredFeaturesWinOverTheClient(t *testing.T) {
	ctx := context.Background()
	stored := &event.RoomFeatures{ID: "a", Reply: event.CapLevelFullySupported, Edit: event.CapLevelFullySupported, EditMaxAge: seconds(15 * time.Minute)}
	w, room := startFeatureWorld(t, stored)

	// The bridge stored the chat's features when it made the room.
	f, err := w.a.Features(ctx, room)
	require.NoError(t, err)
	require.Equal(t, "stored", f.Source)
	require.True(t, f.Edit)
	require.Equal(t, 15*time.Minute, f.EditMaxAge)

	// The client would now say otherwise, but what is stored is what the bridge goes by.
	client := &event.RoomFeatures{ID: "b", Thread: event.CapLevelFullySupported, Delete: event.CapLevelFullySupported}
	w.n.SetFeatures(client)
	f, err = w.a.Features(ctx, room)
	require.NoError(t, err)
	require.Equal(t, "stored", f.Source)
	require.True(t, f.Edit)
	require.False(t, f.Unsend)

	// A new stored value (bridgev2's UpdateCapabilities sends it as state, under its bridge ID) is read at once.
	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)
	updated := &event.RoomFeatures{ID: "c", Reply: event.CapLevelFullySupported, Delete: event.CapLevelFullySupported}
	_, err = h.Bridge.Bot.SendState(ctx, id.RoomID(room), event.StateBeeperRoomFeatures, "whatsapp", &event.Content{Parsed: updated}, time.Now())
	require.NoError(t, err)
	f, err = w.a.Features(ctx, room)
	require.NoError(t, err)
	require.Equal(t, "stored", f.Source)
	require.False(t, f.Edit)
	require.True(t, f.Unsend)

	// With nothing stored (a row that holds null reads as none: the store has no way to drop a state row), the
	// logged-in client is asked.
	_, err = w.s.SetState(ctx, room, event.StateBeeperRoomFeatures.Type, "whatsapp", json.RawMessage(`null`))
	require.NoError(t, err)
	f, err = w.a.Features(ctx, room)
	require.NoError(t, err)
	require.Equal(t, "network", f.Source)
	require.True(t, f.ReplyIsThread)
	require.True(t, f.Unsend)
	require.False(t, f.Edit)
}

func TestNoFeaturesOffersOnlySendReplyAndDelete(t *testing.T) {
	ctx := context.Background()
	require.Equal(t, Features{Reply: true, Source: "none"}, NoFeatures)
	for _, k := range richtext.Kinds {
		require.False(t, NoFeatures.Keeps(k), k)
	}

	w := startWorld(t, "whatsapp", false)
	// A chat on a network that isn't running, with nothing stored.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!gone:courier.local", Network: "slack"}))
	f, err := w.a.Features(ctx, "!gone:courier.local")
	require.NoError(t, err)
	require.Equal(t, NoFeatures, f)

	// A chat on a running network with no login, and no portal to ask about.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!r:courier.local", Network: "whatsapp"}))
	f, err = w.a.Features(ctx, "!r:courier.local")
	require.NoError(t, err)
	require.Equal(t, NoFeatures, f)

	// What is stored still counts while the network isn't running.
	raw, err := json.Marshal(&event.RoomFeatures{Edit: event.CapLevelFullySupported})
	require.NoError(t, err)
	_, err = w.s.SetState(ctx, "!gone:courier.local", event.StateBeeperRoomFeatures.Type, "slack", raw)
	require.NoError(t, err)
	f, err = w.a.Features(ctx, "!gone:courier.local")
	require.NoError(t, err)
	require.Equal(t, "stored", f.Source)
	require.True(t, f.Edit)

	_, err = w.a.Features(ctx, "!nonesuch:courier.local")
	require.ErrorIs(t, err, store.ErrNotFound)
}

// A linked network whose login isn't logged in yet has no client to ask: with nothing stored, NoFeatures.
func TestFeaturesWithoutALoggedInClientAreNone(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Features = &event.RoomFeatures{Edit: event.CapLevelFullySupported}
	n.LoginDelay = time.Hour
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	room, _ := w.chat(t, "alice", "m1")
	_, err := w.s.SetState(ctx, room, event.StateBeeperRoomFeatures.Type, "whatsapp", json.RawMessage(`null`))
	require.NoError(t, err)
	f, err := w.a.Features(ctx, room)
	require.NoError(t, err)
	require.Equal(t, NoFeatures, f)
}
