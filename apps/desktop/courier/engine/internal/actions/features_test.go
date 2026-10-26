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
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
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
		Poll:                  &PollFeatures{MaxOptions: 12, OptionMaxLength: 100},
		Disappearing:          &DisappearingFeatures{Type: "after_send", Timers: []time.Duration{24 * time.Hour, 7 * 24 * time.Hour}},
		Formatting:            richtext.Kinds,
		MentionRoom:           true,
		MaxTextLength:         4000,
		Sticker:               MediaCapFeature{MimeTypes: []string{}},
		GIF:                   MediaCapFeature{MimeTypes: []string{}},
		LinkPreviewsSupported: true,
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
	emptyMedia := MediaCapFeature{MimeTypes: []string{}}
	require.Equal(t, Features{Formatting: []richtext.Kind{}, Sticker: emptyMedia, GIF: emptyMedia}, FeaturesOf(none))
	require.Equal(t, Features{Formatting: []richtext.Kind{}, Sticker: emptyMedia, GIF: emptyMedia}, FeaturesOf(&event.RoomFeatures{}))

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
	emptyMedia := MediaCapFeature{MimeTypes: []string{}}
	require.Equal(t, Features{Reply: true, Formatting: []richtext.Kind{}, Source: "none", Sticker: emptyMedia, GIF: emptyMedia}, NoFeatures)
	require.NotNil(t, NoFeatures.Formatting, "the wire always carries a list")
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

type (
	roomNameMethod interface {
		HandleMatrixRoomName(ctx context.Context, msg *bridgev2.MatrixRoomName) (bool, error)
	}
	roomTopicMethod interface {
		HandleMatrixRoomTopic(ctx context.Context, msg *bridgev2.MatrixRoomTopic) (bool, error)
	}
	roomAvatarMethod interface {
		HandleMatrixRoomAvatar(ctx context.Context, msg *bridgev2.MatrixRoomAvatar) (bool, error)
	}
	membershipMethod interface {
		HandleMatrixMembership(ctx context.Context, msg *bridgev2.MatrixMembershipChange) (*bridgev2.MatrixMembershipResult, error)
	}
	powerLevelMethod interface {
		HandleMatrixPowerLevels(ctx context.Context, msg *bridgev2.MatrixPowerLevelChange) (bool, error)
	}
	deleteChatMethod interface {
		HandleMatrixDeleteChat(ctx context.Context, msg *bridgev2.MatrixDeleteChat) error
	}
	fullGroupAPI interface {
		bridgev2.NetworkAPI
		roomNameMethod
		roomTopicMethod
		roomAvatarMethod
		membershipMethod
		powerLevelMethod
		deleteChatMethod
	}
	apiWithoutRoomName struct {
		bridgev2.NetworkAPI
		roomTopicMethod
		roomAvatarMethod
		membershipMethod
		powerLevelMethod
		deleteChatMethod
	}
	apiWithoutRoomTopic struct {
		bridgev2.NetworkAPI
		roomNameMethod
		roomAvatarMethod
		membershipMethod
		powerLevelMethod
		deleteChatMethod
	}
	apiWithoutRoomAvatar struct {
		bridgev2.NetworkAPI
		roomNameMethod
		roomTopicMethod
		membershipMethod
		powerLevelMethod
		deleteChatMethod
	}
	apiWithoutMembership struct {
		bridgev2.NetworkAPI
		roomNameMethod
		roomTopicMethod
		roomAvatarMethod
		powerLevelMethod
		deleteChatMethod
	}
	apiWithoutPowerLevels struct {
		bridgev2.NetworkAPI
		roomNameMethod
		roomTopicMethod
		roomAvatarMethod
		membershipMethod
		deleteChatMethod
	}
	apiWithoutDeleteChat struct {
		bridgev2.NetworkAPI
		roomNameMethod
		roomTopicMethod
		roomAvatarMethod
		membershipMethod
		powerLevelMethod
	}
)

func TestFeaturesGroupAndChatCapabilitiesByInterfaceAndPowerLevel(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	room, _ := w.chat(t, "group1", "m1")

	base, ok := w.login.Client.(fullGroupAPI)
	require.True(t, ok, "fakenet client must implement all 6 group/chat-management interfaces")

	fAll, err := w.a.Features(ctx, room)
	require.NoError(t, err)
	require.True(t, fAll.CanSetName)
	require.True(t, fAll.CanSetTopic)
	require.True(t, fAll.CanSetAvatar)
	require.True(t, fAll.CanInvite)
	require.True(t, fAll.CanKick)
	require.True(t, fAll.CanSetAdmin)
	require.True(t, fAll.CanLeave)
	require.True(t, fAll.CanDelete)

	cases := []struct {
		name  string
		api   bridgev2.NetworkAPI
		check func(t *testing.T, f Features)
	}{
		{
			name: "omit RoomNameHandlingNetworkAPI",
			api:  apiWithoutRoomName{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanSetName)
				require.True(t, f.CanSetTopic && f.CanSetAvatar && f.CanInvite && f.CanKick && f.CanSetAdmin && f.CanLeave && f.CanDelete)
			},
		},
		{
			name: "omit RoomTopicHandlingNetworkAPI",
			api:  apiWithoutRoomTopic{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanSetTopic)
				require.True(t, f.CanSetName && f.CanSetAvatar && f.CanInvite && f.CanKick && f.CanSetAdmin && f.CanLeave && f.CanDelete)
			},
		},
		{
			name: "omit RoomAvatarHandlingNetworkAPI",
			api:  apiWithoutRoomAvatar{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanSetAvatar)
				require.True(t, f.CanSetName && f.CanSetTopic && f.CanInvite && f.CanKick && f.CanSetAdmin && f.CanLeave && f.CanDelete)
			},
		},
		{
			name: "omit MembershipHandlingNetworkAPI",
			api:  apiWithoutMembership{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanInvite)
				require.False(t, f.CanKick)
				require.False(t, f.CanLeave)
				require.True(t, f.CanSetName && f.CanSetTopic && f.CanSetAvatar && f.CanSetAdmin && f.CanDelete)
			},
		},
		{
			name: "omit PowerLevelHandlingNetworkAPI",
			api:  apiWithoutPowerLevels{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanSetAdmin)
				require.True(t, f.CanSetName && f.CanSetTopic && f.CanSetAvatar && f.CanInvite && f.CanKick && f.CanLeave && f.CanDelete)
			},
		},
		{
			name: "omit DeleteChatHandlingNetworkAPI",
			api:  apiWithoutDeleteChat{base, base, base, base, base, base},
			check: func(t *testing.T, f Features) {
				require.False(t, f.CanDelete)
				require.True(t, f.CanSetName && f.CanSetTopic && f.CanSetAvatar && f.CanInvite && f.CanKick && f.CanSetAdmin && f.CanLeave)
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			w.login.Client = tc.api
			t.Cleanup(func() { w.login.Client = base })
			f, err := w.a.Features(ctx, room)
			require.NoError(t, err)
			tc.check(t, f)
		})
	}

	t.Run("myLevel 0 with required 50", func(t *testing.T) {
		reqLevel := 50
		pl := &event.PowerLevelsEventContent{
			Users:           map[id.UserID]int{ids.Me: 0},
			UsersDefault:    0,
			StateDefaultPtr: &reqLevel,
			InvitePtr:       &reqLevel,
			KickPtr:         &reqLevel,
		}
		raw, err := json.Marshal(pl)
		require.NoError(t, err)
		_, err = w.s.SetState(ctx, room, event.StatePowerLevels.Type, "", raw)
		require.NoError(t, err)

		f, err := w.a.Features(ctx, room)
		require.NoError(t, err)
		require.False(t, f.CanSetName)
		require.False(t, f.CanSetTopic)
		require.False(t, f.CanSetAvatar)
		require.False(t, f.CanInvite)
		require.False(t, f.CanKick)
		require.False(t, f.CanSetAdmin)
		require.True(t, f.CanLeave)
		require.True(t, f.CanDelete)
	})

	t.Run("direct chat disables group capabilities while keeping CanDelete", func(t *testing.T) {
		direct := true
		w.n.SetChat("dm1", fakenet.Chat{Direct: &direct})
		dmRoom, _ := w.secondChat(t, "dm1", "m2", room)

		f, err := w.a.Features(ctx, dmRoom)
		require.NoError(t, err)
		require.False(t, f.CanSetName)
		require.False(t, f.CanSetTopic)
		require.False(t, f.CanSetAvatar)
		require.False(t, f.CanInvite)
		require.False(t, f.CanKick)
		require.False(t, f.CanSetAdmin)
		require.False(t, f.CanLeave)
		require.True(t, f.CanDelete)
	})
}

func TestDeleteLeavesGroupByNetworkAndRoomType(t *testing.T) {
	ctx := context.Background()

	for _, tc := range []struct {
		network       string
		wantGroupCan  bool
		wantLeavesGrp bool
	}{
		{network: "whatsapp", wantGroupCan: true, wantLeavesGrp: true},
		{network: "signal", wantGroupCan: true, wantLeavesGrp: false},
		{network: "telegram", wantGroupCan: false, wantLeavesGrp: false},
		{network: "gmessages", wantGroupCan: true, wantLeavesGrp: false},
	} {
		t.Run(tc.network, func(t *testing.T) {
			w := startWorld(t, tc.network, true)
			groupRoom, _ := w.chat(t, "group1", "m1")

			fGroup, err := w.a.Features(ctx, groupRoom)
			require.NoError(t, err)
			require.Equal(t, tc.wantGroupCan, fGroup.CanDelete, "%s group CanDelete", tc.network)
			require.Equal(t, tc.wantLeavesGrp, fGroup.DeleteLeavesGroup, "%s group DeleteLeavesGroup", tc.network)

			// When CanDelete is false (bridge does not implement DeleteChatHandlingNetworkAPI),
			// DeleteLeavesGroup must also be false.
			base, ok := w.login.Client.(fullGroupAPI)
			require.True(t, ok)
			w.login.Client = apiWithoutDeleteChat{base, base, base, base, base, base}
			fNoDelete, err := w.a.Features(ctx, groupRoom)
			require.NoError(t, err)
			require.False(t, fNoDelete.CanDelete)
			require.False(t, fNoDelete.DeleteLeavesGroup, "%s group without CanDelete", tc.network)
			w.login.Client = base

			// Any 1:1 DM chat must have DeleteLeavesGroup == false.
			direct := true
			w.n.SetChat("dm1", fakenet.Chat{Direct: &direct})
			dmRoom, _ := w.secondChat(t, "dm1", "m2", groupRoom)
			fDM, err := w.a.Features(ctx, dmRoom)
			require.NoError(t, err)
			require.True(t, fDM.CanDelete)
			require.False(t, fDM.DeleteLeavesGroup, "%s DM DeleteLeavesGroup", tc.network)
		})
	}
}

func TestFileKindFeaturesMappedFromRoomCapabilities(t *testing.T) {
	rf := &event.RoomFeatures{
		Formatting: event.FormattingFeatureMap{
			event.FmtInlineLink: event.CapLevelPartialSupport,
		},
		LocationMessage: event.CapLevelFullySupported,
		File: event.FileFeatureMap{
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelFullySupported,
					"image/jpeg": event.CapLevelPartialSupport,
					"image/bmp":  event.CapLevelRejected,
					"image/tiff": event.CapLevelUnsupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: 1024,
				MaxSize:          10 * 1024 * 1024,
			},
			event.CapMsgVoice: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"audio/ogg; codecs=opus": event.CapLevelFullySupported,
				},
				Caption:     event.CapLevelUnsupported,
				MaxSize:     100 * 1024 * 1024,
				MaxDuration: seconds(60 * time.Minute),
			},
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelRejected,
				},
				MaxSize: 300 * 1000,
			},
		},
	}

	f := FeaturesOf(rf)
	require.Equal(t, &FileKindFeatures{
		Supported:        true,
		MimeTypes:        []string{"image/jpeg", "image/webp"},
		Caption:          true,
		MaxCaptionLength: 1024,
		MaxSize:          10 * 1024 * 1024,
	}, f.ImageFeatures)
	require.Equal(t, &FileKindFeatures{
		Supported:      true,
		MimeTypes:      []string{"audio/ogg; codecs=opus"},
		Caption:        false,
		MaxSize:        100 * 1024 * 1024,
		MaxDurationSec: 3600,
	}, f.VoiceFeatures)
	require.Nil(t, f.StickerFeatures, "file kind with only rejected MIME types must convert to nil")
	require.Nil(t, f.VideoFeatures)
	require.Nil(t, f.AudioFeatures)
	require.Nil(t, f.FileFeatures)
	require.Nil(t, f.GIFFeatures)
	require.True(t, f.LocationSupported)
	require.True(t, f.LinkPreviewsSupported)

	empty := FeaturesOf(&event.RoomFeatures{})
	require.False(t, empty.LocationSupported)
	require.False(t, empty.LinkPreviewsSupported)
	require.Nil(t, empty.ImageFeatures)
}

func TestStickerAndGIFRoomFeatures(t *testing.T) {
	// WhatsApp-like capabilities: CapMsgSticker with image/webp full + Caption: CapLevelDropped;
	// CapMsgGIF with video/mp4 full + Caption: CapLevelFullySupported.
	wa := FeaturesOf(&event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp":        event.CapLevelFullySupported,
					"image/png":         event.CapLevelPartialSupport,
					"image/jpeg":        event.CapLevelPartialSupport,
					"video/lottie+json": event.CapLevelPartialSupport,
				},
				Caption: event.CapLevelDropped,
				MaxSize: 16 << 20,
			},
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"video/mp4": event.CapLevelFullySupported,
					"image/gif": event.CapLevelUnsupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: 1024,
				MaxSize:          16 << 20,
			},
		},
	})
	require.Equal(t, MediaCapFeature{
		Supported: true,
		MimeTypes: []string{"image/jpeg", "image/png", "image/webp", "video/lottie+json"},
		Captions:  false,
		MaxSize:   16 << 20,
	}, wa.Sticker)
	require.Equal(t, MediaCapFeature{
		Supported:        true,
		MimeTypes:        []string{"video/mp4"},
		Captions:         true,
		MaxCaptionLength: 1024,
		MaxSize:          16 << 20,
	}, wa.GIF)

	// Google Messages / Slack capabilities: CapMsgGIF with image/gif full, CapMsgSticker absent -> Sticker.Supported == false.
	gm := FeaturesOf(&event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: 4000,
				MaxSize:          50 << 20,
			},
		},
	})
	require.Equal(t, MediaCapFeature{
		Supported: false,
		MimeTypes: []string{},
	}, gm.Sticker)
	require.Equal(t, MediaCapFeature{
		Supported:        true,
		MimeTypes:        []string{"image/gif"},
		Captions:         true,
		MaxCaptionLength: 4000,
		MaxSize:          50 << 20,
	}, gm.GIF)

	// CapLevelRejected / CapLevelUnsupported MIME filtering (only CapLevelFullySupported, CapLevelPartialSupport,
	// and CapLevelDropped count as sendable MIME types; MimeTypes sorted deterministically).
	filtered := FeaturesOf(&event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelDropped,
					"image/png":  event.CapLevelFullySupported,
					"image/apng": event.CapLevelPartialSupport,
					"image/bmp":  event.CapLevelRejected,
					"image/tiff": event.CapLevelUnsupported,
				},
				Caption:          event.CapLevelPartialSupport,
				MaxCaptionLength: 200,
				MaxSize:          512 << 10,
			},
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelRejected,
					"video/mp4": event.CapLevelUnsupported,
				},
				MaxSize: 512 << 10,
			},
		},
	})
	require.Equal(t, MediaCapFeature{
		Supported:        true,
		MimeTypes:        []string{"image/apng", "image/png", "image/webp"},
		Captions:         true,
		MaxCaptionLength: 200,
		MaxSize:          512 << 10,
	}, filtered.Sticker)
	require.Equal(t, MediaCapFeature{
		Supported: false,
		MimeTypes: []string{},
	}, filtered.GIF)
}
