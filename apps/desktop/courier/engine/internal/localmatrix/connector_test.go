package localmatrix

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestGhostIDsRoundTripThroughConnector(t *testing.T) {
	c := newTestConnector(t)
	mxid := c.FormatGhostMXID("u1")
	uid, ok := c.ParseGhostMXID(mxid)
	require.True(t, ok)
	require.EqualValues(t, "u1", uid)
	require.Equal(t, ids.ServerName, c.ServerName())
}

func TestMessageStatusUpdatesStore(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	_, err = c.store.InsertEvent(ctx, store.Event{RoomID: string(roomID), EventID: "$mine", Sender: string(ids.Me),
		Type: "m.room.message", Content: json.RawMessage(`{}`), Status: "pending"})
	require.NoError(t, err)
	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusFail, Message: "not delivered"},
		&bridgev2.MessageStatusEventInfo{RoomID: roomID, SourceEventID: "$mine"})
	e, _, err := c.store.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	require.Equal(t, "failed", e.Status)
	require.Equal(t, "not delivered", e.StatusReason)
}

func TestBridgeStateIsStored(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateConnected}))
	raw, ok, err := c.store.BridgeState(ctx, "whatsapp")
	require.NoError(t, err)
	require.True(t, ok)
	require.Contains(t, string(raw), "CONNECTED")
}

func TestMembersReflectCreateRoom(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	roomID, err := c.GhostIntent("u1").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	m, err := c.GetMembers(ctx, roomID)
	require.NoError(t, err)
	require.Contains(t, m, ids.Me)
	require.Contains(t, m, c.FormatGhostMXID("u1"))
}

func TestMessageStatusForUnknownEventDoesNotPanic(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusSuccess},
		&bridgev2.MessageStatusEventInfo{SourceEventID: "$ghost"})
}

func TestPowerLevelsRoundTrip(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	bot := c.BotIntent()
	roomID, err := bot.CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	empty, err := c.GetPowerLevels(ctx, roomID)
	require.NoError(t, err)
	require.NotNil(t, empty)
	pl := &event.PowerLevelsEventContent{UsersDefault: 7}
	_, err = bot.SendState(ctx, roomID, event.StatePowerLevels, "", &event.Content{Parsed: pl}, time.Now())
	require.NoError(t, err)
	got, err := c.GetPowerLevels(ctx, roomID)
	require.NoError(t, err)
	require.Equal(t, 7, got.UsersDefault)
}
