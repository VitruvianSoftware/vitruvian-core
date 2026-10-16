package localmatrix

import (
	"context"
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
	r := &database.Reaction{MessageID: "m1", MessagePartID: "p", SenderID: "u1", EmojiID: "👍"}
	resp, err := c.GhostIntent("u1").SendMessage(ctx, roomID, event.EventReaction, textContent("👍"), &bridgev2.MatrixSendExtra{ReactionMeta: r})
	require.NoError(t, err)
	require.Equal(t, c.GenerateReactionEventID(roomID, &database.Message{ID: "m1", PartID: "p"}, "u1", "👍"), resp.EventID)
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
