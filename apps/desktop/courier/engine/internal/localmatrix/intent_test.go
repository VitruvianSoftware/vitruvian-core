// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func newTestConnector(t *testing.T) *Connector {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return New("whatsapp", s, &media.Store{Dir: filepath.Join(dir, "media")})
}

func textContent(body string) *event.Content {
	return &event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: body}}
}

func TestSendMessageRoundTripsUnicode(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("15550001111@s.whatsapp.net")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{Name: "Gia đình 👨‍👩‍👧", IsDirect: false})
	require.NoError(t, err)
	body := "Chào cả nhà 🌸 " + strings.Repeat("ạ", 20000)
	key := networkid.PortalKey{ID: "chat1"}
	resp, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent(body),
		&bridgev2.MatrixSendExtra{Timestamp: time.Unix(100, 0), MessageMeta: &database.Message{ID: "m1", Room: key}})
	require.NoError(t, err)
	require.Equal(t, ids.EventID(roomID, key, "m1", ""), resp.EventID)
	got, err := ghost.GetEvent(ctx, roomID, resp.EventID)
	require.NoError(t, err)
	require.Equal(t, body, got.Content.AsMessage().Body)
	room, _, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.Equal(t, "Gia đình 👨‍👩‍👧", room.Name)
}

func TestSendMessageTwiceIsOneEvent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	extra := &bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: networkid.PortalKey{ID: "c"}}}
	r1, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"), extra)
	require.NoError(t, err)
	r2, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"), extra)
	require.NoError(t, err)
	require.Equal(t, r1.EventID, r2.EventID)
	evs, err := c.store.Events(ctx, string(roomID), 10)
	require.NoError(t, err)
	n := 0
	for _, e := range evs {
		if e.Type == event.EventMessage.Type {
			n++
		}
	}
	require.Equal(t, 1, n)
}

func TestUploadThenDownloadMedia(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	uri, file, err := bot.UploadMedia(ctx, "", []byte("PNGDATA"), "a.png", "image/png")
	require.NoError(t, err)
	require.Nil(t, file)
	got, err := bot.DownloadMedia(ctx, uri, nil)
	require.NoError(t, err)
	require.Equal(t, "PNGDATA", string(got))
	_, err = bot.DownloadMedia(ctx, "mxc://elsewhere/x", nil)
	require.Error(t, err)
}

func TestReactionEventIDMatchesConnector(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	r := &database.Reaction{MessageID: "m1", MessagePartID: "p", SenderID: "u1", EmojiID: "👍", Emoji: "👍"}
	resp, err := c.GhostIntent("u1").SendMessage(ctx, roomID, event.EventReaction, textContent("👍"), &bridgev2.MatrixSendExtra{ReactionMeta: r})
	require.NoError(t, err)
	require.Equal(t, c.GenerateReactionEventID(roomID, &database.Message{ID: "m1", PartID: "p"}, "u1", "👍"), resp.EventID)
}

func countEvents(t *testing.T, c *Connector, roomID id.RoomID, typ string) int {
	t.Helper()
	evs, err := c.store.Events(context.Background(), string(roomID), 100)
	require.NoError(t, err)
	n := 0
	for _, e := range evs {
		if e.Type == typ {
			n++
		}
	}
	return n
}

func TestEditCreatesASecondEvent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	key := networkid.PortalKey{ID: "c"}
	orig, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"),
		&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: key}})
	require.NoError(t, err)
	// bridgev2 passes the ORIGINAL message (with its MXID set) when it edits.
	edit, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("* b"),
		&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: key, MXID: orig.EventID}})
	require.NoError(t, err)
	require.NotEqual(t, orig.EventID, edit.EventID)
	require.Equal(t, 2, countEvents(t, c, roomID, event.EventMessage.Type))
	got, err := ghost.GetEvent(ctx, roomID, edit.EventID)
	require.NoError(t, err)
	require.Equal(t, "* b", got.Content.AsMessage().Body)
}

func TestRedactionCreatesItsOwnEvent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	key := networkid.PortalKey{ID: "c"}
	orig, err := ghost.SendMessage(ctx, roomID, event.EventMessage, textContent("a"),
		&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: key}})
	require.NoError(t, err)
	// Even when the message has no MXID in the meta, a redaction is never deterministic.
	for _, mxid := range []id.EventID{orig.EventID, ""} {
		red, err := ghost.SendMessage(ctx, roomID, event.EventRedaction,
			&event.Content{Parsed: &event.RedactionEventContent{Redacts: orig.EventID}},
			&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m1", Room: key, MXID: mxid}})
		require.NoError(t, err)
		require.NotEqual(t, orig.EventID, red.EventID)
	}
	require.Equal(t, 2, countEvents(t, c, roomID, event.EventRedaction.Type))
	require.Equal(t, 1, countEvents(t, c, roomID, event.EventMessage.Type))
}

func TestReactionRemovalCreatesItsOwnEvent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	r := &database.Reaction{MessageID: "m1", SenderID: "u1", EmojiID: "👍"}
	added, err := ghost.SendMessage(ctx, roomID, event.EventReaction, textContent("👍"), &bridgev2.MatrixSendExtra{ReactionMeta: r})
	require.NoError(t, err)
	removed := *r
	removed.MXID = added.EventID
	red, err := ghost.SendMessage(ctx, roomID, event.EventRedaction,
		&event.Content{Parsed: &event.RedactionEventContent{Redacts: added.EventID}},
		&bridgev2.MatrixSendExtra{ReactionMeta: &removed})
	require.NoError(t, err)
	require.NotEqual(t, added.EventID, red.EventID)
	require.Equal(t, 1, countEvents(t, c, roomID, event.EventRedaction.Type))
}

func TestReactionSwapWithoutEmojiIDKeepsBothEvents(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	send := func(emoji string) id.EventID {
		r := &database.Reaction{MessageID: "m1", SenderID: "u1", Emoji: emoji}
		resp, err := ghost.SendMessage(ctx, roomID, event.EventReaction, textContent(emoji), &bridgev2.MatrixSendExtra{ReactionMeta: r})
		require.NoError(t, err)
		return resp.EventID
	}
	thumbs, heart := send("👍"), send("❤️")
	require.NotEqual(t, thumbs, heart)
	require.Equal(t, thumbs, send("👍"), "re-sending the same reaction stays idempotent")
	require.Equal(t, 2, countEvents(t, c, roomID, event.EventReaction.Type))
}

func TestSendStateMirrorsRoomAndMembers(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{Name: "old"})
	require.NoError(t, err)
	send := func(typ event.Type, key string, content any) {
		t.Helper()
		_, err := bot.SendState(ctx, roomID, typ, key, &event.Content{Parsed: content}, time.Now())
		require.NoError(t, err)
	}
	send(event.StateRoomName, "", &event.RoomNameEventContent{Name: "new"})
	send(event.StateTopic, "", &event.TopicEventContent{Topic: "about"})
	send(event.StateRoomAvatar, "", &event.RoomAvatarEventContent{URL: mustMXC("abc")})
	send(event.StateMember, "@x:courier.local", &event.MemberEventContent{Membership: event.MembershipJoin, Displayname: "X"})
	room, ok, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "new", room.Name)
	require.Equal(t, "about", room.Topic)
	require.Equal(t, string(ids.ContentURI("abc")), room.AvatarURI)
	m, err := c.GetMemberInfo(ctx, roomID, "@x:courier.local")
	require.NoError(t, err)
	require.Equal(t, "X", m.Displayname)
}

func TestCreateRoomUsesLocalIDAndKeepsInitialMemberProfile(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	want := c.GenerateDeterministicRoomID(networkid.PortalKey{ID: "chat1"})
	ghost := c.GhostIntent("u1")
	key := c.FormatGhostMXID("u1")
	sk := string(key)
	roomID, err := ghost.CreateRoom(ctx, &mautrix.ReqCreateRoom{
		BeeperLocalRoomID: want,
		InitialState: []*event.Event{{
			Type: event.StateMember, StateKey: &sk,
			Content: event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin, Displayname: "Gia"}},
		}},
	})
	require.NoError(t, err)
	require.Equal(t, want, roomID)
	m, err := c.GetMemberInfo(ctx, roomID, key)
	require.NoError(t, err)
	require.Equal(t, "Gia", m.Displayname)
}

func TestRecreatingRoomKeepsAvatar(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	req := &mautrix.ReqCreateRoom{BeeperLocalRoomID: "!r:courier.local", Name: "n"}
	roomID, err := bot.CreateRoom(ctx, req)
	require.NoError(t, err)
	_, err = bot.SendState(ctx, roomID, event.StateRoomAvatar, "", &event.Content{Parsed: &event.RoomAvatarEventContent{URL: mustMXC("abc")}}, time.Now())
	require.NoError(t, err)
	_, err = bot.CreateRoom(ctx, req)
	require.NoError(t, err)
	room, _, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.Equal(t, string(ids.ContentURI("abc")), room.AvatarURI)
}

func TestGetEventUnknownIsNotFound(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	_, err = c.BotIntent().GetEvent(ctx, roomID, "$nope")
	require.ErrorIs(t, err, mautrix.MNotFound)
}

func TestGetEventKeepsUnknownTypeAsRaw(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	custom := event.Type{Type: "com.example.thing", Class: event.MessageEventType}
	resp, err := c.BotIntent().SendMessage(ctx, roomID, custom, &event.Content{Raw: map[string]any{"k": "v"}}, nil)
	require.NoError(t, err)
	got, err := c.BotIntent().GetEvent(ctx, roomID, resp.EventID)
	require.NoError(t, err)
	require.Equal(t, "v", got.Content.Raw["k"])
}

func TestUploadMediaStreamAndReplacementFile(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	uri, file, err := bot.UploadMediaStream(ctx, "", 0, false, func(w io.Writer) (*bridgev2.FileStreamResult, error) {
		_, err := w.Write([]byte("STREAMED"))
		return &bridgev2.FileStreamResult{}, err
	})
	require.NoError(t, err)
	require.Nil(t, file)
	got, err := bot.DownloadMedia(ctx, uri, nil)
	require.NoError(t, err)
	require.Equal(t, "STREAMED", string(got))

	repl := filepath.Join(t.TempDir(), "repl")
	require.NoError(t, os.WriteFile(repl, []byte("REPLACED"), 0o600))
	uri, _, err = bot.UploadMediaStream(ctx, "", 0, true, func(w io.Writer) (*bridgev2.FileStreamResult, error) {
		_, err := w.Write([]byte("ORIGINAL"))
		return &bridgev2.FileStreamResult{ReplacementFile: repl}, err
	})
	require.NoError(t, err)
	got, err = bot.DownloadMedia(ctx, uri, nil)
	require.NoError(t, err)
	require.Equal(t, "REPLACED", string(got))
	require.NoFileExists(t, repl, "the replacement file is handed over to the connector")
}

func TestDownloadMediaToFile(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	uri, _, err := bot.UploadMedia(ctx, "", []byte("DATA"), "", "")
	require.NoError(t, err)
	var seen string
	require.NoError(t, bot.DownloadMediaToFile(ctx, uri, nil, false, func(f *os.File) error {
		b, err := io.ReadAll(f)
		seen = string(b)
		return err
	}))
	require.Equal(t, "DATA", seen)
	err = bot.DownloadMediaToFile(ctx, uri, nil, false, func(*os.File) error { return os.ErrInvalid })
	var cbErr bridgev2.CallbackError
	require.ErrorAs(t, err, &cbErr)
}

func TestMarkReadAndDeleteRoom(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	require.NoError(t, bot.MarkRead(ctx, roomID, id.EventID("$e"), time.Unix(5, 0))) // the bot's receipt: ignored
	require.NoError(t, bot.DeleteRoom(ctx, roomID, false))
	_, ok, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.False(t, ok)
}

func mustMXC(hash string) id.ContentURIString { return ids.ContentURI(hash) }

func TestUploadMediaStreamHandsTheCallbackARealFile(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	uri, _, err := c.BotIntent().UploadMediaStream(ctx, "", 0, true, func(w io.Writer) (*bridgev2.FileStreamResult, error) {
		f, ok := w.(*os.File)
		require.True(t, ok, "requireFile must give the callback an *os.File, got %T", w)
		if _, err := f.Write([]byte("ABCDEFGH")); err != nil {
			return nil, err
		}
		if _, err := f.Seek(0, io.SeekStart); err != nil {
			return nil, err
		}
		_, err := f.Write([]byte("XXXX")) // rewrite the start, as a bridge fixing up a header would
		return &bridgev2.FileStreamResult{}, err
	})
	require.NoError(t, err)
	got, err := c.BotIntent().DownloadMedia(ctx, uri, nil)
	require.NoError(t, err)
	require.Equal(t, "XXXXEFGH", string(got))
	left, err := filepath.Glob(filepath.Join(c.media.Dir, ".*"))
	require.NoError(t, err)
	require.Empty(t, left, "no temp files may be left behind")
}

func TestDeleteRoomPuppetsOnlyKeepsHistory(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.GhostIntent("u1").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	_, err = c.GhostIntent("u1").SendMessage(ctx, roomID, event.EventMessage, textContent("keep me"), nil)
	require.NoError(t, err)

	require.NoError(t, c.BotIntent().DeleteRoom(ctx, roomID, true))

	_, ok, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.True(t, ok, "room must survive")
	require.Equal(t, 1, countEvents(t, c, roomID, event.EventMessage.Type), "history must survive")
	m, err := c.GetMembers(ctx, roomID)
	require.NoError(t, err)
	require.NotContains(t, m, c.FormatGhostMXID("u1"))
	require.Contains(t, m, ids.Me)

	require.NoError(t, c.BotIntent().DeleteRoom(ctx, roomID, false))
	_, ok, err = c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.False(t, ok, "puppetsOnly=false still deletes the room")
}

func TestCreateRoomStoresPowerLevelOverride(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{
		PowerLevelOverride: &event.PowerLevelsEventContent{UsersDefault: 9},
	})
	require.NoError(t, err)
	pl, err := c.GetPowerLevels(ctx, roomID)
	require.NoError(t, err)
	require.Equal(t, 9, pl.UsersDefault)
}

func TestInitialStateNameRoundTripsUnicode(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	const name = "Gia đình 👨‍👩‍👧"
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{
		InitialState: []*event.Event{{
			Type: event.StateRoomName, StateKey: ptr(""),
			Content: event.Content{Parsed: &event.RoomNameEventContent{Name: name}},
		}},
	})
	require.NoError(t, err)
	room, ok, err := c.store.GetRoom(ctx, string(roomID))
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, name, room.Name)
}

func ptr[T any](v T) *T { return &v }

func TestGhostProfileReachesTheStore(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	ghost := c.GhostIntent("u1")
	mxid := string(c.FormatGhostMXID("u1"))
	require.NoError(t, ghost.SetDisplayName(ctx, "Gia đình 👨‍👩‍👧"))
	require.NoError(t, ghost.SetAvatarURL(ctx, mustMXC("abc")))
	prof, ok, err := c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Gia đình 👨‍👩‍👧", prof.DisplayName)
	require.Equal(t, string(mustMXC("abc")), prof.AvatarURI)

	// A full-profile write that carries a name and avatar updates both; extra keys are ignored.
	require.NoError(t, ghost.SetProfile(ctx, json.RawMessage(`{"displayname":"New","avatar_url":"mxc://courier.local/def","com.beeper.bridge.service":"wa"}`)))
	prof, _, err = c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.Equal(t, "New", prof.DisplayName)
	require.Equal(t, "mxc://courier.local/def", prof.AvatarURI)

	// Data without a name or avatar leaves the profile alone.
	require.NoError(t, ghost.SetExtraProfileMeta(ctx, &event.BeeperProfileExtra{RemoteID: "u1"}))
	prof, _, err = c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.Equal(t, "New", prof.DisplayName)
	require.Equal(t, "mxc://courier.local/def", prof.AvatarURI)
}

// unreadOf is the inbox's unread count for roomID.
func unreadOf(t *testing.T, c *Connector, roomID id.RoomID) int {
	t.Helper()
	rows, err := c.store.Inbox(context.Background())
	require.NoError(t, err)
	for _, r := range rows {
		if r.ID == string(roomID) {
			return r.Unread
		}
	}
	t.Fatalf("no inbox row for %s", roomID)
	return 0
}

// The bug this guards: a friend's read receipt for my message moved MY read marker to the receipt's time, which
// wiped the unread count of the replies they had sent before reading it.
func TestOnlyMyReadReceiptsMoveMyReadMarker(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.GhostIntent("friend")
	roomID, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	meIntent, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	send := func(in bridgev2.MatrixAPI, body string, at int64) id.EventID {
		t.Helper()
		resp, err := in.SendMessage(ctx, roomID, event.EventMessage, textContent(body), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(at, 0)})
		require.NoError(t, err)
		return resp.EventID
	}
	mine := send(meIntent, "are you coming?", 10)
	reply1 := send(friend, "yes", 20)
	send(friend, "on my way", 30)
	require.Equal(t, 2, unreadOf(t, c, roomID))

	// The friend reads my message, after both replies.
	require.NoError(t, friend.MarkRead(ctx, roomID, mine, time.Unix(40, 0)))
	require.Equal(t, 2, unreadOf(t, c, roomID), "someone else's receipt is not my read")
	require.Equal(t, []string{string(c.FormatGhostMXID("friend"))}, readerIDs(receiptsOf(t, c, roomID, mine)),
		"it is the friend having read my message (milestone 4.4 keeps it)")
	require.NoError(t, c.BotIntent().MarkRead(ctx, roomID, mine, time.Unix(41, 0)))
	require.Equal(t, 2, unreadOf(t, c, roomID), "nor is the bot's")

	// I read the first reply on my phone, and the receipt comes in later still: only that reply clears.
	require.NoError(t, meIntent.MarkRead(ctx, roomID, reply1, time.Unix(50, 0)))
	require.Equal(t, 1, unreadOf(t, c, roomID))

	// I answer from another device without reading the rest, and the friend reads that answer: newer than
	// everything unread, but it is their read, not mine.
	send(friend, "where are you?", 60)
	answer := send(meIntent, "nearly there", 70)
	require.NoError(t, friend.MarkRead(ctx, roomID, answer, time.Unix(80, 0)))
	require.Equal(t, 2, unreadOf(t, c, roomID), "someone else reading my newest message is not my read")
	require.Len(t, receiptsOf(t, c, roomID, answer).ReadBy, 1, "it is their read of my answer")
}

// bridged is a real bridgev2 bridge running the fake network over this package's connector, with the tag and
// mute settings host.Start gives every network (TestStartBridgeConfigMatchesExampleDefaults pins those there; the
// host package imports this one, so its Start can't be used here).
type bridged struct {
	c     *Connector
	n     *fakenet.Network
	login *bridgev2.UserLogin
}

func startBridged(t *testing.T) bridged {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	// br.Stop closes the bridge database itself.
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	n := fakenet.New()
	c := New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix:    "!fake",
		Permissions:      bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		TagOnlyOnCreate:  true,
		MuteOnlyOnCreate: true,
		OnlyBridgeTags:   []event.RoomTag{event.RoomTagFavourite, event.RoomTagLowPriority},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.Nop(), cfg, c, n,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	t.Cleanup(br.Stop)
	login, err := n.Login(ctx, br)
	require.NoError(t, err)
	return bridged{c: c, n: n, login: login}
}

// arrive has the network deliver the first message of chatID, which makes the bridge create the chat, and
// returns its room once the message is stored.
func (b bridged) arrive(t *testing.T, chatID string) id.RoomID {
	t.Helper()
	body := "first message of " + chatID
	b.n.Incoming(b.login, chatID, "alice", "m-"+chatID, body)
	var room id.RoomID
	require.Eventually(t, func() bool {
		rooms, err := b.c.store.ListRooms(context.Background())
		if err != nil {
			return false
		}
		for _, r := range rooms {
			evs, err := b.c.store.Events(context.Background(), r.ID, 10)
			if err != nil {
				return false
			}
			for _, e := range evs {
				if strings.Contains(string(e.Content), body) {
					room = id.RoomID(r.ID)
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 20*time.Millisecond, "%s never arrived", chatID)
	return room
}

// rowOf is the inbox row of roomID.
func rowOf(t *testing.T, c *Connector, roomID id.RoomID) store.InboxRow {
	t.Helper()
	rows, err := c.store.Inbox(context.Background())
	require.NoError(t, err)
	for _, r := range rows {
		if r.ID == string(roomID) {
			return r
		}
	}
	t.Fatalf("no inbox row for %s", roomID)
	return store.InboxRow{}
}

func TestNetworkPinAtCreateBecomesPinned(t *testing.T) {
	b := startBridged(t)
	b.n.SetChat("pinned", fakenet.Chat{Tag: ptr(event.RoomTagFavourite)})
	b.n.SetChat("muted", fakenet.Chat{MutedUntil: ptr(event.MutedForever)})
	b.n.SetChat("was-muted", fakenet.Chat{MutedUntil: ptr(bridgev2.Unmuted)})

	pinned := b.arrive(t, "pinned")
	require.False(t, rowOf(t, b.c, pinned).PinnedAt.IsZero(), "a chat pinned on the phone arrives pinned")
	require.False(t, rowOf(t, b.c, pinned).Archived)

	muted := b.arrive(t, "muted")
	require.True(t, rowOf(t, b.c, muted).Muted, "a chat muted on the phone arrives muted")
	require.True(t, rowOf(t, b.c, muted).PinnedAt.IsZero())

	wasMuted := b.arrive(t, "was-muted")
	require.False(t, rowOf(t, b.c, wasMuted).Muted, "a mute that has run out is no mute")

	plain := b.arrive(t, "plain")
	require.True(t, rowOf(t, b.c, plain).PinnedAt.IsZero(), "a chat with no tag arrives unpinned")
	require.False(t, rowOf(t, b.c, plain).Muted)
}

func TestNetworkArchiveTagBecomesArchived(t *testing.T) {
	b := startBridged(t)
	b.n.SetChat("archived", fakenet.Chat{Tag: ptr(event.RoomTagLowPriority)})
	room := b.arrive(t, "archived")
	row := rowOf(t, b.c, room)
	require.True(t, row.Archived, "a network's low priority is what it shows as archived")
	require.False(t, row.LowPriority, "it is Courier's archive, not Courier's low priority")
	require.True(t, row.PinnedAt.IsZero())
}

func TestOtherTagsAreIgnored(t *testing.T) {
	t.Run("from the network at create", func(t *testing.T) {
		b := startBridged(t)
		b.n.SetChat("work", fakenet.Chat{Tag: ptr(event.RoomTag("u.work"))})
		row := rowOf(t, b.c, b.arrive(t, "work"))
		require.True(t, row.PinnedAt.IsZero())
		require.False(t, row.Archived)
		require.False(t, row.LowPriority)
	})
	t.Run("handed to my intent", func(t *testing.T) {
		c, ctx := newTestConnector(t), context.Background()
		roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
		require.NoError(t, err)
		me, _, err := c.NewUserIntent(ctx, ids.Me, "")
		require.NoError(t, err)
		for _, tag := range []event.RoomTag{"u.work", event.RoomTagServerNotice, ""} {
			require.NoError(t, me.TagRoom(ctx, roomID, tag, true), tag)
		}
		row := rowOf(t, c, roomID)
		require.True(t, row.PinnedAt.IsZero())
		require.False(t, row.Archived)
		require.False(t, row.LowPriority)
		require.False(t, row.Hidden)
	})
}

// bridgev2 sends a chat's tags, mute and unread mark through my own (double-puppet) intent. A ghost's or the
// bot's say nothing about my chat list.
func TestOnlyMyTagsAndMutesCount(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	me, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)

	for _, other := range []bridgev2.MatrixAPI{c.GhostIntent("friend"), c.BotIntent()} {
		require.NoError(t, other.TagRoom(ctx, roomID, event.RoomTagFavourite, true))
		require.NoError(t, other.TagRoom(ctx, roomID, event.RoomTagLowPriority, true))
		require.NoError(t, other.MuteRoom(ctx, roomID, event.MutedForever))
		require.NoError(t, other.MarkUnread(ctx, roomID, true))
	}
	row := rowOf(t, c, roomID)
	require.True(t, row.PinnedAt.IsZero())
	require.False(t, row.Archived)
	require.False(t, row.Muted)
	require.False(t, row.MarkedUnread)

	require.NoError(t, me.TagRoom(ctx, roomID, event.RoomTagFavourite, true))
	require.False(t, rowOf(t, c, roomID).PinnedAt.IsZero())
	require.NoError(t, me.TagRoom(ctx, roomID, event.RoomTagFavourite, false))
	require.True(t, rowOf(t, c, roomID).PinnedAt.IsZero())

	require.NoError(t, me.MuteRoom(ctx, roomID, event.MutedForever))
	require.True(t, rowOf(t, c, roomID).Muted)
	require.NoError(t, me.MuteRoom(ctx, roomID, bridgev2.Unmuted))
	require.False(t, rowOf(t, c, roomID).Muted)

	require.NoError(t, me.MarkUnread(ctx, roomID, true))
	require.True(t, rowOf(t, c, roomID).MarkedUnread)
	require.NoError(t, me.MarkUnread(ctx, roomID, false))
	require.False(t, rowOf(t, c, roomID).MarkedUnread)
}

func TestGhostTypingIsKeptUntilTimeout(t *testing.T) {
	b := startBridged(t)
	room := b.arrive(t, "chat1")
	alice := string(ids.GhostMXID("fake", "alice"))
	typing := func() []string { return b.c.store.TypingIn(string(room)) }

	b.n.Typing(b.login, "chat1", "alice", 400*time.Millisecond)
	require.Eventually(t, func() bool { return len(typing()) == 1 && typing()[0] == alice }, 5*time.Second, 10*time.Millisecond,
		"the contact is shown typing")
	require.Eventually(t, func() bool { return len(typing()) == 0 }, 5*time.Second, 20*time.Millisecond,
		"and stops being shown once the timeout passes")

	b.n.Typing(b.login, "chat1", "alice", time.Minute)
	require.Eventually(t, func() bool { return len(typing()) == 1 }, 5*time.Second, 10*time.Millisecond)
	b.n.Typing(b.login, "chat1", "alice", 0)
	require.Eventually(t, func() bool { return len(typing()) == 0 }, 5*time.Second, 10*time.Millisecond,
		"a timeout of 0 is the contact stopping")

	// My own typing (from another device) and the bot's are not someone typing to me.
	ctx := context.Background()
	me, _, err := b.c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	require.NoError(t, me.MarkTyping(ctx, room, bridgev2.TypingTypeText, time.Minute))
	require.NoError(t, b.c.BotIntent().MarkTyping(ctx, room, bridgev2.TypingTypeText, time.Minute))
	require.Empty(t, typing())
}

func TestMessageRequestFromBridgeInfo(t *testing.T) {
	b := startBridged(t)
	b.n.SetChat("stranger", fakenet.Chat{MessageRequest: ptr(true)})
	stranger := b.arrive(t, "stranger")
	require.True(t, rowOf(t, b.c, stranger).Request, "the bridge info of a new chat says it is a message request")
	friend := b.arrive(t, "friend")
	require.False(t, rowOf(t, b.c, friend).Request)

	ctx := context.Background()
	bot := b.c.BotIntent()
	info := func(request bool) *event.Content {
		return &event.Content{Parsed: &event.BridgeEventContent{Channel: event.BridgeInfoSection{ID: "x", MessageRequest: request}}}
	}
	// bridgev2 resends the bridge info whenever the chat's info changes. "Request" in a resend is not taken in:
	// after an accept here that the network refused or never heard of, the resend still says "request".
	for _, typ := range []event.Type{event.StateBridge, event.StateHalfShotBridge} {
		_, err := bot.SendState(ctx, friend, typ, "fake://friend", info(true), time.Now())
		require.NoError(t, err)
		require.False(t, rowOf(t, b.c, friend).Request, "%s resent with the flag doesn't make a chat a request", typ.Type)
	}
	require.NoError(t, b.c.store.SetRequest(ctx, string(stranger), false), "accepted here (the network refused it)")
	_, err := bot.SendState(ctx, stranger, event.StateBridge, "fake://stranger", info(true), time.Now())
	require.NoError(t, err)
	require.False(t, rowOf(t, b.c, stranger).Request, "a resent request flag doesn't undo an accept")

	// "Not a request" is taken in at any time: that is how an accept the network took reads afterwards, from either
	// of the two state events.
	other := b.arrive(t, "other")
	require.NoError(t, b.c.store.SetRequest(ctx, string(other), true), "fixture: a request")
	_, err = bot.SendState(ctx, other, event.StateHalfShotBridge, "fake://other", info(false), time.Now())
	require.NoError(t, err)
	require.False(t, rowOf(t, b.c, other).Request)
	require.NoError(t, b.c.store.SetRequest(ctx, string(other), true))
	_, err = bot.SendState(ctx, other, event.StateBridge, "fake://other", info(false), time.Now())
	require.NoError(t, err)
	require.False(t, rowOf(t, b.c, other).Request)

	// A chat made fresh with the flag in its initial state is a request, whichever event carries it.
	sk := "fake://new"
	newRoom, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{InitialState: []*event.Event{
		{Type: event.StateHalfShotBridge, StateKey: &sk, Content: *info(true)},
	}})
	require.NoError(t, err)
	require.True(t, rowOf(t, b.c, newRoom).Request)
}

// A resend that says nothing new writes nothing: no "room" change reaches the app.
func TestUnchangedBridgeInfoPublishesNothing(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	changes, cancel := c.store.Subscribe()
	defer cancel()
	for _, request := range []bool{false, true} {
		_, err = bot.SendState(ctx, roomID, event.StateBridge, "k",
			&event.Content{Parsed: &event.BridgeEventContent{Channel: event.BridgeInfoSection{ID: "x", MessageRequest: request}}}, time.Now())
		require.NoError(t, err)
	}
	deadline := time.After(100 * time.Millisecond)
	for {
		select {
		case ch := <-changes:
			require.NotEqual(t, "room", ch.Kind, "an unchanged request flag published %+v", ch)
		case <-deadline:
			return
		}
	}
}

// A change of a chat's room features (what it can do: com.beeper.room_features, which actions.Features reads)
// publishes "room" for the chat, so the app reads its actions again. A resend that says nothing new publishes
// nothing.
func TestFeaturesChangePublishesRoom(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	changes, cancel := c.store.Subscribe()
	defer cancel()
	features := func(edit event.CapabilitySupportLevel) *event.Content {
		return &event.Content{Parsed: &event.RoomFeatures{ID: "caps", Reply: event.CapLevelFullySupported, Edit: edit}}
	}
	nextRoom := func(what string) {
		t.Helper()
		select {
		case ch := <-changes:
			require.Equal(t, store.Change{Kind: "room", RoomID: string(roomID)}, ch, what)
		case <-time.After(5 * time.Second):
			t.Fatalf("no room change after %s", what)
		}
	}
	_, err = bot.SendState(ctx, roomID, event.StateBeeperRoomFeatures, "whatsapp", features(event.CapLevelUnsupported), time.Now())
	require.NoError(t, err)
	nextRoom("the first features")
	_, err = bot.SendState(ctx, roomID, event.StateBeeperRoomFeatures, "whatsapp", features(event.CapLevelFullySupported), time.Now())
	require.NoError(t, err)
	nextRoom("a change")

	_, err = bot.SendState(ctx, roomID, event.StateBeeperRoomFeatures, "whatsapp", features(event.CapLevelFullySupported), time.Now())
	require.NoError(t, err)
	select {
	case ch := <-changes:
		t.Fatalf("an unchanged resend published %+v", ch)
	case <-time.After(100 * time.Millisecond):
	}
}

// A call notice from the bridge is stored with Courier's reading of it, by the connector's network: Signal's
// "Call ended" (which comes with no action message) becomes a call note, and the same words on WhatsApp's connector
// stay a message.
func TestSendMessageReadsACallNoticeByItsNetwork(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	notice := func() *event.Content {
		return &event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgNotice, Body: "Call ended"}}
	}
	for _, tc := range []struct {
		network string
		call    bool
	}{{"signal", true}, {"whatsapp", false}} {
		c := New(tc.network, s, &media.Store{Dir: filepath.Join(dir, "media")})
		roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{Name: tc.network, IsDirect: true})
		require.NoError(t, err)
		ghost := c.GhostIntent("u1")
		resp, err := ghost.SendMessage(ctx, roomID, event.EventMessage, notice(), &bridgev2.MatrixSendExtra{
			Timestamp: time.Unix(100, 0), MessageMeta: &database.Message{ID: "m1", Room: networkid.PortalKey{ID: networkid.PortalID(tc.network)}},
		})
		require.NoError(t, err)
		e, ok, err := s.GetEvent(ctx, string(resp.EventID))
		require.NoError(t, err)
		require.True(t, ok)
		require.Equal(t, tc.call, store.IsCallNote(e), "%s: %s", tc.network, e.Content)
		var c2 map[string]any
		require.NoError(t, json.Unmarshal(e.Content, &c2))
		require.Equal(t, "Call ended", c2["body"], "the bridge's body is kept, never shown")
	}
}

// Someone typing "Call ended" on Signal is a person's words, not the bridge's notice: it stays a message.
func TestSendMessageKeepsTypedCallWordsAMessage(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	c := New("signal", s, &media.Store{Dir: filepath.Join(dir, "media")})
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{Name: "signal", IsDirect: true})
	require.NoError(t, err)
	resp, err := c.GhostIntent("u1").SendMessage(ctx, roomID, event.EventMessage, textContent("Call ended"),
		&bridgev2.MatrixSendExtra{
			Timestamp:   time.Unix(100, 0),
			MessageMeta: &database.Message{ID: "m1", Room: networkid.PortalKey{ID: "signal"}},
		})
	require.NoError(t, err)
	e, ok, err := s.GetEvent(ctx, string(resp.EventID))
	require.NoError(t, err)
	require.True(t, ok)
	require.False(t, store.IsCallNote(e), "%s", e.Content)
	require.JSONEq(t, `{"msgtype":"m.text","body":"Call ended"}`, string(e.Content), "stored exactly as sent")
}

// receiptsOf is how far my message eventID in roomID has got (store.ReceiptsFor).
func receiptsOf(t *testing.T, c *Connector, roomID id.RoomID, eventID id.EventID) store.Receipts {
	t.Helper()
	ctx := context.Background()
	e, ok, err := c.store.GetEvent(ctx, string(eventID))
	require.NoError(t, err)
	require.True(t, ok, "fixture: %s is stored", eventID)
	got, err := c.store.ReceiptsFor(ctx, string(roomID), []store.Event{e})
	require.NoError(t, err)
	return got[string(eventID)]
}

// readerIDs is who has read a message, newest receipt first.
func readerIDs(r store.Receipts) []string {
	var out []string
	for _, rd := range r.ReadBy {
		out = append(out, rd.UserID)
	}
	return out
}

// Review Focus 2: a ghost's receipt is that person reading (kept, by their marker); mine from another device moves my
// own marker and is never a reader of my message.
func TestOthersReceiptsAreKeptAndMineStillMoveMyMarker(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.GhostIntent("friend")
	roomID, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	me, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	send := func(in bridgev2.MatrixAPI, body string, at int64) id.EventID {
		t.Helper()
		resp, err := in.SendMessage(ctx, roomID, event.EventMessage, textContent(body), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(at, 0)})
		require.NoError(t, err)
		return resp.EventID
	}
	first := send(me, "first", 10)
	second := send(me, "second", 20)
	reply := send(friend, "reply", 30)
	require.Equal(t, 1, unreadOf(t, c, roomID))

	require.NoError(t, friend.MarkRead(ctx, roomID, first, time.Unix(40, 0)))
	friendID := string(c.FormatGhostMXID("friend"))
	require.Equal(t, []string{friendID}, readerIDs(receiptsOf(t, c, roomID, first)), "the friend has read my first message")
	require.Empty(t, receiptsOf(t, c, roomID, second).ReadBy, "a receipt for an older message doesn't mark a newer one")
	require.Equal(t, time.Unix(40, 0), receiptsOf(t, c, roomID, first).ReadBy[0].TS, "with the time the receipt carries")
	require.Equal(t, 1, unreadOf(t, c, roomID), "their read is not mine")

	require.NoError(t, friend.MarkRead(ctx, roomID, second, time.Unix(50, 0)))
	require.Equal(t, []string{friendID}, readerIDs(receiptsOf(t, c, roomID, second)))
	require.NoError(t, friend.MarkRead(ctx, roomID, first, time.Unix(60, 0)))
	require.Equal(t, []string{friendID}, readerIDs(receiptsOf(t, c, roomID, second)), "an older receipt after it changes nothing")

	// I read the reply on my phone: my marker moves, and I am never a reader of my own message.
	require.NoError(t, me.MarkRead(ctx, roomID, reply, time.Unix(70, 0)))
	require.Equal(t, 0, unreadOf(t, c, roomID))
	require.Equal(t, []string{friendID}, readerIDs(receiptsOf(t, c, roomID, second)))

	// A receipt for a message Courier doesn't have is dropped without error.
	require.NoError(t, friend.MarkRead(ctx, roomID, "$not-here", time.Unix(80, 0)))
	require.Equal(t, []string{friendID}, readerIDs(receiptsOf(t, c, roomID, second)))
}

// Surprise 1: a network can bridge my own reads from another client under my own network user (Slack's im_marked,
// channel_marked and group_marked carry my user ID). That is my read, never someone having seen my message.
func TestAReceiptFromMyOwnNetworkUserIsMyRead(t *testing.T) {
	b := startBridged(t)
	ctx := context.Background()
	room := b.arrive(t, "chat1")
	me, _, err := b.c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	resp, err := me.SendMessage(ctx, room, event.EventMessage, textContent("mine"), &bridgev2.MatrixSendExtra{Timestamp: time.Now().Add(time.Second)})
	require.NoError(t, err)
	b.n.Incoming(b.login, "chat1", "alice", "m2", "later")
	require.Eventually(t, func() bool { return unreadOf(t, b.c, room) == 2 }, 5*time.Second, 10*time.Millisecond)
	last, ok, err := b.c.store.LastMessage(ctx, string(room))
	require.NoError(t, err)
	require.True(t, ok)

	// The fake network's own user is "me" (IsThisUser): its ghost's receipt is mine.
	require.NoError(t, b.c.GhostIntent("me").MarkRead(ctx, room, id.EventID(last.EventID), time.Now()))
	require.Equal(t, 0, unreadOf(t, b.c, room), "my read from another client moves my marker")
	require.Empty(t, receiptsOf(t, b.c, room, resp.EventID).ReadBy, "and never shows as Seen")
}

// The bot is nobody: its receipt neither moves my marker nor reads my message.
func TestTheBotsReceiptIsDropped(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.GhostIntent("friend")
	roomID, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	me, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	mine, err := me.SendMessage(ctx, roomID, event.EventMessage, textContent("mine"), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(10, 0)})
	require.NoError(t, err)
	theirs, err := friend.SendMessage(ctx, roomID, event.EventMessage, textContent("theirs"), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(20, 0)})
	require.NoError(t, err)
	changes, cancel := c.store.Subscribe()
	defer cancel()

	require.NoError(t, c.BotIntent().MarkRead(ctx, roomID, theirs.EventID, time.Unix(30, 0)))
	require.Empty(t, receiptsOf(t, c, roomID, mine.EventID).ReadBy)
	require.Equal(t, 1, unreadOf(t, c, roomID))
	select {
	case ch := <-changes:
		t.Fatalf("the bot's receipt published %+v", ch)
	case <-time.After(50 * time.Millisecond):
	}
}

// Ruling 6: the phone saying a chat is no longer marked unread clears the chat's marked-unread flag (as in 4.1), but
// not a mark made on this Mac from a message (Mark as Unread from here): only reading the chat clears that.
func TestAPhonesNotMarkedUnreadKeepsTheUnreadFromMark(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.GhostIntent("friend")
	roomID, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	me, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	var msgs []id.EventID
	for i, body := range []string{"one", "two", "three"} {
		resp, err := friend.SendMessage(ctx, roomID, event.EventMessage, textContent(body), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(int64(10*(i+1)), 0)})
		require.NoError(t, err)
		msgs = append(msgs, resp.EventID)
	}
	require.NoError(t, me.MarkRead(ctx, roomID, msgs[2], time.Unix(40, 0)))
	require.Equal(t, 0, unreadOf(t, c, roomID))
	require.NoError(t, c.store.SetUnreadFrom(ctx, string(roomID), string(msgs[1])))
	require.Equal(t, 2, unreadOf(t, c, roomID), "fixture: unread from the second message on")
	require.NoError(t, me.MarkUnread(ctx, roomID, true))
	require.True(t, rowOf(t, c, roomID).MarkedUnread)

	require.NoError(t, me.MarkUnread(ctx, roomID, false))
	require.False(t, rowOf(t, c, roomID).MarkedUnread, "the phone's flag clears")
	require.Equal(t, 2, unreadOf(t, c, roomID), "the mark made here stays")
}

// Ruling 6: a read of mine from another device that reaches the message the chat is marked unread from (or goes past
// it) clears that mark; one that stops short of it leaves the mark. The chat was read here to the end before it was
// marked, so the count shows the mark: three while it stands (from the second message on), none once it is cleared.
func TestMyReadElsewhereAtOrPastTheUnreadFromMessageClearsIt(t *testing.T) {
	for name, tc := range map[string]struct {
		readTo    int // the message my other device reads up to
		wantAfter int // the unread count after it
	}{
		"short of the mark": {readTo: 0, wantAfter: 3},
		"at the mark":       {readTo: 1, wantAfter: 0},
		"past the mark":     {readTo: 2, wantAfter: 0},
	} {
		t.Run(name, func(t *testing.T) {
			c, ctx := newTestConnector(t), context.Background()
			friend := c.GhostIntent("friend")
			roomID, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
			require.NoError(t, err)
			me, _, err := c.NewUserIntent(ctx, ids.Me, "")
			require.NoError(t, err)
			var msgs []id.EventID
			for i := range 4 {
				resp, err := friend.SendMessage(ctx, roomID, event.EventMessage, textContent("m"), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(int64(10*(i+1)), 0)})
				require.NoError(t, err)
				msgs = append(msgs, resp.EventID)
			}
			require.NoError(t, c.store.MarkReadLocal(ctx, string(roomID), string(msgs[3]), time.Unix(40, 0)))
			require.Equal(t, 0, unreadOf(t, c, roomID), "fixture: read here to the end")
			require.NoError(t, c.store.SetUnreadFrom(ctx, string(roomID), string(msgs[1])))
			require.Equal(t, 3, unreadOf(t, c, roomID), "fixture: unread from the second message on")

			require.NoError(t, me.MarkRead(ctx, roomID, msgs[tc.readTo], time.Unix(100, 0)))
			require.Equal(t, tc.wantAfter, unreadOf(t, c, roomID))
		})
	}
}

// roomLogin is the login (rooms.login_id) the store says roomID belongs to.
func roomLogin(t *testing.T, c *Connector, roomID id.RoomID) string {
	t.Helper()
	r, ok, err := c.store.GetRoom(context.Background(), string(roomID))
	require.NoError(t, err)
	require.True(t, ok)
	return r.LoginID
}

// bridgeInfo is a bridge info whose channel names receiver as the chat's login.
func bridgeInfo(receiver string) *event.Content {
	return &event.Content{Parsed: &event.BridgeEventContent{Channel: event.BridgeInfoSection{ID: "x", Receiver: receiver}}}
}

// A chat remembers its login from the bridge info's fi.mau.receiver; a chat every login shares (a portal with no
// receiver, such as a WhatsApp group) has none.
func TestTheBridgeInfoReceiverBecomesTheChatsLogin(t *testing.T) {
	b := startBridged(t)
	own := b.arrive(t, "own")
	require.Equal(t, "fake-login", roomLogin(t, b.c, own), "the chat is the login's own")

	b.n.IncomingShared(b.login, "group", "alice", "g1", "first message of group")
	var shared id.RoomID
	require.Eventually(t, func() bool {
		rooms, err := b.c.store.ListRooms(context.Background())
		if err != nil {
			return false
		}
		for _, r := range rooms {
			if r.ID != string(own) {
				shared = id.RoomID(r.ID)
				return true
			}
		}
		return false
	}, 5*time.Second, 20*time.Millisecond, "the shared chat never arrived")
	require.Empty(t, roomLogin(t, b.c, shared), "a shared chat belongs to no one login")

	// A later bridge info naming another login moves the chat; one with none leaves it.
	ctx := context.Background()
	_, err := b.c.BotIntent().SendState(ctx, own, event.StateBridge, "fake://own", bridgeInfo("other-login"), time.Now())
	require.NoError(t, err)
	require.Equal(t, "other-login", roomLogin(t, b.c, own))
	_, err = b.c.BotIntent().SendState(ctx, own, event.StateHalfShotBridge, "fake://own", bridgeInfo(""), time.Now())
	require.NoError(t, err)
	require.Equal(t, "other-login", roomLogin(t, b.c, own))
}

// Outside data can't grow a row: a receiver over 256 bytes is ignored, one of 256 is taken.
func TestAnOversizedReceiverIsIgnored(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	_, err = bot.SendState(ctx, roomID, event.StateBridge, "k", bridgeInfo(strings.Repeat("a", 257)), time.Now())
	require.NoError(t, err)
	require.Empty(t, roomLogin(t, c, roomID))
	_, err = bot.SendState(ctx, roomID, event.StateBridge, "k", bridgeInfo(strings.Repeat("b", 256)), time.Now())
	require.NoError(t, err)
	require.Equal(t, strings.Repeat("b", 256), roomLogin(t, c, roomID))
}
