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

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
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
		InitialState: []*event.Event{{Type: event.StateMember, StateKey: &sk,
			Content: event.Content{Parsed: &event.MemberEventContent{Membership: event.MembershipJoin, Displayname: "Gia"}}}},
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
	require.NoError(t, bot.MarkRead(ctx, roomID, id.EventID("$e"), time.Unix(5, 0)))
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
		InitialState: []*event.Event{{Type: event.StateRoomName, StateKey: ptr(""),
			Content: event.Content{Parsed: &event.RoomNameEventContent{Name: name}}}},
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
	name, avatar, ok, err := c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Gia đình 👨‍👩‍👧", name)
	require.Equal(t, string(mustMXC("abc")), avatar)

	// A full-profile write that carries a name and avatar updates both; extra keys are ignored.
	require.NoError(t, ghost.SetProfile(ctx, json.RawMessage(`{"displayname":"New","avatar_url":"mxc://courier.local/def","com.beeper.bridge.service":"wa"}`)))
	name, avatar, _, err = c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.Equal(t, "New", name)
	require.Equal(t, "mxc://courier.local/def", avatar)

	// Data without a name or avatar leaves the profile alone.
	require.NoError(t, ghost.SetExtraProfileMeta(ctx, &event.BeeperProfileExtra{RemoteID: "u1"}))
	name, avatar, _, err = c.store.GetProfile(ctx, mxid)
	require.NoError(t, err)
	require.Equal(t, "New", name)
	require.Equal(t, "mxc://courier.local/def", avatar)
}
