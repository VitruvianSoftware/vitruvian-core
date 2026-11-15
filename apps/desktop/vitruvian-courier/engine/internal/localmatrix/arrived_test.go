// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"path/filepath"
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

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// gmMeta is a Google Messages part's bridge metadata as mautrix-gmessages keeps it: the message's state in "type".
type gmMeta struct {
	Type     int    `json:"type,omitempty"`
	TextHash string `json:"text_hash,omitempty"`
}

func newNetworkConnector(t *testing.T, network string) *Connector {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return New(network, s, &media.Store{Dir: filepath.Join(dir, "media")})
}

// directRoom is a one-to-one chat with friend, as bridgev2 creates one.
func directRoom(t *testing.T, c *Connector, friend networkid.UserID) id.RoomID {
	t.Helper()
	roomID, err := c.GhostIntent(friend).CreateRoom(context.Background(), &mautrix.ReqCreateRoom{IsDirect: true, Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	return roomID
}

// The bug: mautrix-gmessages only sends a read receipt when it sees a message's state change to displayed. A
// message of mine it first meets already displayed (a backfill, or one read while another web client was the active
// session) said "Delivered" for good. The state is in the part's metadata, so the message now arrives read.
func TestGoogleMessagesMessageArrivingReadIsSeen(t *testing.T) {
	c, ctx := newNetworkConnector(t, "gmessages"), context.Background()
	roomID := directRoom(t, c, "1.220")
	meIntent, _, err := c.NewUserIntent(ctx, ids.Me, "")
	require.NoError(t, err)
	friend := c.GhostIntent("1.220")
	send := func(in bridgev2.MatrixAPI, msgID string, meta any, at int64) id.EventID {
		t.Helper()
		resp, err := in.SendMessage(ctx, roomID, event.EventMessage, textContent(msgID), &bridgev2.MatrixSendExtra{
			Timestamp:   time.Unix(at, 0),
			MessageMeta: &database.Message{ID: networkid.MessageID(msgID), Room: networkid.PortalKey{ID: "1.177"}, Metadata: meta},
		})
		require.NoError(t, err)
		return resp.EventID
	}

	delivered := send(meIntent, "1.1", &gmMeta{Type: 2}, 10)
	require.Empty(t, receiptsOf(t, c, roomID, delivered).ReadBy, "delivered is not seen")

	read := send(meIntent, "1.2", &gmMeta{Type: 11, TextHash: "x"}, 20)
	got := receiptsOf(t, c, roomID, read)
	require.Equal(t, []string{string(c.FormatGhostMXID("1.220"))}, readerIDs(got), "the other person read it")
	require.True(t, got.ReadBy[0].TS.IsZero(), "the state says nothing of when: no time is made up")
	require.Equal(t, []string{string(c.FormatGhostMXID("1.220"))}, readerIDs(receiptsOf(t, c, roomID, delivered)),
		"reading my newer message is reading the older one too")

	// Their message in the displayed state is them reading nothing of mine; an edit (MXID set) is no new message.
	theirs := send(friend, "1.3", &gmMeta{Type: 11}, 30)
	require.Empty(t, receiptsOf(t, c, roomID, theirs).ReadBy)
	later := send(meIntent, "1.4", &gmMeta{Type: 1}, 40)
	_, err = meIntent.SendMessage(ctx, roomID, event.EventMessage, textContent("edit"), &bridgev2.MatrixSendExtra{
		Timestamp:   time.Unix(50, 0),
		MessageMeta: &database.Message{ID: "1.4", MXID: later, Metadata: &gmMeta{Type: 11}},
	})
	require.NoError(t, err)
	require.Empty(t, receiptsOf(t, c, roomID, later).ReadBy, "an edit's state is not the message arriving read")
}

// Only a network that keeps the state there reads it, and only in a one-to-one chat with one other person.
func TestArrivingReadNeedsGoogleMessagesAndADirectChat(t *testing.T) {
	ctx := context.Background()
	t.Run("another network", func(t *testing.T) {
		c := newNetworkConnector(t, "whatsapp")
		roomID := directRoom(t, c, "friend")
		meIntent, _, _ := c.NewUserIntent(ctx, ids.Me, "")
		resp, err := meIntent.SendMessage(ctx, roomID, event.EventMessage, textContent("x"),
			&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m", Metadata: &gmMeta{Type: 11}}})
		require.NoError(t, err)
		require.Empty(t, receiptsOf(t, c, roomID, resp.EventID).ReadBy)
	})
	t.Run("a group", func(t *testing.T) {
		c := newNetworkConnector(t, "gmessages")
		roomID, err := c.GhostIntent("a").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me, c.FormatGhostMXID("b")}})
		require.NoError(t, err)
		meIntent, _, _ := c.NewUserIntent(ctx, ids.Me, "")
		resp, err := meIntent.SendMessage(ctx, roomID, event.EventMessage, textContent("x"),
			&bridgev2.MatrixSendExtra{MessageMeta: &database.Message{ID: "m", Metadata: &gmMeta{Type: 11}}})
		require.NoError(t, err)
		require.Empty(t, receiptsOf(t, c, roomID, resp.EventID).ReadBy, "a group's readers aren't known from the state")
	})
}

func TestArrivedRead(t *testing.T) {
	require.True(t, arrivedRead("gmessages", &gmMeta{Type: 11}))
	require.True(t, arrivedRead("gmessages", `{"type":11,"part_count":1}`), "the stored JSON reads the same")
	require.True(t, arrivedRead("gmessages", []byte(`{"type": 11}`)))
	require.False(t, arrivedRead("gmessages", &gmMeta{Type: 2}))
	require.False(t, arrivedRead("gmessages", nil))
	require.False(t, arrivedRead("gmessages", "not json"))
	require.False(t, arrivedRead("signal", &gmMeta{Type: 11}))
}

// Messages the bridge stored before (displayed in its own table, never sent a receipt for: 47 one-to-one messages
// of mine in a live Google Messages bridge, and none in its chats' receipts) are caught up on as the bridge starts.
func TestReconcileArrivedReadsFromTheBridgeTable(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	bdb, err := sqlite.Open(filepath.Join(dir, "gmessages.db"))
	require.NoError(t, err)
	c := New("gmessages", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{CommandPrefix: "!gm", Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin}}
	br := bridgev2.NewBridge("gmessages", bdb, zerolog.Nop(), cfg, c, fakenet.New(),
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	t.Cleanup(br.Stop)

	roomID := directRoom(t, c, "1.220")
	groupID, err := c.GhostIntent("1.5").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	meIntent, _, _ := c.NewUserIntent(ctx, ids.Me, "")
	plain := func(room id.RoomID, body string, at int64) id.EventID {
		resp, err := meIntent.SendMessage(ctx, room, event.EventMessage, textContent(body), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(at, 0)})
		require.NoError(t, err)
		return resp.EventID
	}
	older, newer, unread := plain(roomID, "older", 10), plain(roomID, "newer", 20), plain(roomID, "unread", 30)
	inGroup := plain(groupID, "group", 10)

	for _, g := range []networkid.UserID{"1.2", "1.220", "1.5"} {
		require.NoError(t, br.DB.Ghost.Insert(ctx, &database.Ghost{BridgeID: br.ID, ID: g, Metadata: map[string]any{}}))
	}
	dm := networkid.PortalKey{ID: "1.177"}
	group := networkid.PortalKey{ID: "1.64"}
	require.NoError(t, br.DB.Portal.Insert(ctx, &database.Portal{
		BridgeID: br.ID, PortalKey: dm, MXID: roomID,
		OtherUserID: "1.220", RoomType: database.RoomTypeDM, Metadata: map[string]any{},
	}))
	require.NoError(t, br.DB.Portal.Insert(ctx, &database.Portal{
		BridgeID: br.ID, PortalKey: group, MXID: groupID,
		OtherUserID: "1.5", RoomType: database.RoomTypeDefault, Metadata: map[string]any{},
	}))
	part := func(key networkid.PortalKey, msgID string, mxid id.EventID, at int64, status int) {
		require.NoError(t, br.DB.Message.Insert(ctx, &database.Message{
			BridgeID: br.ID, ID: networkid.MessageID(msgID), MXID: mxid,
			Room: key, SenderID: "1.2", SenderMXID: ids.Me, Timestamp: time.Unix(at, 0), Metadata: &gmMeta{Type: status},
		}))
	}
	part(dm, "1.10", older, 10, 11)
	part(dm, "1.11", newer, 20, 11)
	part(dm, "1.12", unread, 30, 2)
	part(group, "1.13", inGroup, 10, 11)

	c.reconcileArrivedReads(ctx)
	friend := string(c.FormatGhostMXID("1.220"))
	require.Equal(t, []string{friend}, readerIDs(receiptsOf(t, c, roomID, newer)), "the newest displayed message is read")
	require.Equal(t, []string{friend}, readerIDs(receiptsOf(t, c, roomID, older)))
	require.Empty(t, receiptsOf(t, c, roomID, unread).ReadBy, "a delivered one after it is not")
	require.Empty(t, receiptsOf(t, c, groupID, inGroup).ReadBy, "a group's readers aren't known from the state")

	c.reconcileArrivedReads(ctx) // again: nothing changes, nothing fails
	require.Equal(t, []string{friend}, readerIDs(receiptsOf(t, c, roomID, newer)))
}
