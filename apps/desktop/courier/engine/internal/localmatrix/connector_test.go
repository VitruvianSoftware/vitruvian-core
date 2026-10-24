// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/rs/zerolog"
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
	_, err = c.store.InsertEvent(ctx, store.Event{
		RoomID: string(roomID), EventID: "$mine", Sender: string(ids.Me),
		Type: "m.room.message", Content: json.RawMessage(`{}`), Status: "pending",
	})
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

// statusAfter stores a pending event, reports ms for it, and returns the stored status and reason.
func statusAfter(t *testing.T, c *Connector, ms bridgev2.MessageStatus) (status, reason string) {
	t.Helper()
	ctx := context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	_, err = c.store.InsertEvent(ctx, store.Event{
		RoomID: string(roomID), EventID: "$mine", Sender: string(ids.Me),
		Type: "m.room.message", Content: json.RawMessage(`{}`), Status: "pending",
	})
	require.NoError(t, err)
	c.SendMessageStatus(ctx, &ms, &bridgev2.MessageStatusEventInfo{RoomID: roomID, SourceEventID: "$mine"})
	e, _, err := c.store.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	return e.Status, e.StatusReason
}

func TestMessageStatusMapping(t *testing.T) {
	for name, tc := range map[string]struct {
		in   event.MessageStatus
		want string
	}{
		"success":   {event.MessageStatusSuccess, "sent"},
		"fail":      {event.MessageStatusFail, "failed"},
		"retriable": {event.MessageStatusRetriable, "failed"},
		"pending":   {event.MessageStatusPending, "pending"},
	} {
		t.Run(name, func(t *testing.T) {
			got, _ := statusAfter(t, newTestConnector(t), bridgev2.MessageStatus{Status: tc.in})
			require.Equal(t, tc.want, got)
		})
	}
}

func TestUnknownMessageStatusKeepsRowAndWarns(t *testing.T) {
	c := newTestConnector(t)
	var logs bytes.Buffer
	c.log = zerolog.New(&logs)
	got, reason := statusAfter(t, c, bridgev2.MessageStatus{Status: event.MessageStatus("SOMETHING_NEW"), Message: "ignored"})
	require.Equal(t, "pending", got, "a status we do not know must never be recorded as sent")
	require.Empty(t, reason)
	require.Contains(t, logs.String(), `"level":"warn"`)
	require.Contains(t, logs.String(), "SOMETHING_NEW")
}

func TestFailedStatusReasonFallsBack(t *testing.T) {
	wrapped := bridgev2.WrapErrorInStatus(errors.New("boom"))
	require.Empty(t, wrapped.Message, "fixture: WrapErrorInStatus leaves Message empty and the detail in InternalError")

	for name, tc := range map[string]struct {
		ms   bridgev2.MessageStatus
		want string
	}{
		"human message wins": {bridgev2.MessageStatus{
			Status: event.MessageStatusFail, Message: "not delivered",
			InternalError: errors.New("internal"),
		}, "not delivered"},
		"internal error when message is empty": {wrapped, "boom"},
		"error as message prefers the error": {bridgev2.MessageStatus{
			Status: event.MessageStatusFail, Message: "generic",
			InternalError: errors.New("the real cause"), ErrorAsMessage: true,
		}, "the real cause"},
		"error as message without an error keeps the message": {bridgev2.MessageStatus{
			Status:  event.MessageStatusFail,
			Message: "generic", ErrorAsMessage: true,
		}, "generic"},
		"error reason as the last resort": {bridgev2.MessageStatus{
			Status:      event.MessageStatusFail,
			ErrorReason: event.MessageStatusNetworkError,
		}, string(event.MessageStatusNetworkError)},
	} {
		t.Run(name, func(t *testing.T) {
			got, reason := statusAfter(t, newTestConnector(t), tc.ms)
			require.Equal(t, "failed", got)
			require.Equal(t, tc.want, reason)
		})
	}
}

// Review Focus 2: a delivery (bridgev2's message status with DeliveredTo, from a one-to-one chat) says the person's
// device has my message. It is kept as a delivery and leaves the message's own status alone.
func TestDeliveredToBecomesADelivery(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.FormatGhostMXID("friend")
	roomID, err := c.GhostIntent("friend").CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	_, err = c.store.InsertEvent(ctx, store.Event{
		RoomID: string(roomID), EventID: "$mine", Sender: string(ids.Me),
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"x"}`), Status: "pending",
	})
	require.NoError(t, err)
	info := &bridgev2.MessageStatusEventInfo{RoomID: roomID, SourceEventID: "$mine"}
	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusSuccess}, info)
	changes, cancel := c.store.Subscribe()
	defer cancel()

	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusSuccess, DeliveredTo: []id.UserID{friend, ids.Me}}, info)
	e, _, err := c.store.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	require.Equal(t, "sent", e.Status, "the status row stays sent")
	got, err := c.store.ReceiptsFor(ctx, string(roomID), []store.Event{e})
	require.NoError(t, err)
	require.Equal(t, []string{string(friend)}, got["$mine"].DeliveredTo, "the friend's device has it; I am never a recipient")
	require.Empty(t, got["$mine"].ReadBy, "delivered is not seen")
	select {
	case ch := <-changes:
		require.Equal(t, "receipt", ch.Kind, "a delivery is a receipt change, never a status one")
	case <-time.After(time.Second):
		t.Fatal("the delivery published nothing")
	}

	// A delivery of a message Courier doesn't have is dropped, without touching anything.
	c.SendMessageStatus(ctx, &bridgev2.MessageStatus{Status: event.MessageStatusSuccess, DeliveredTo: []id.UserID{friend}},
		&bridgev2.MessageStatusEventInfo{RoomID: roomID, SourceEventID: "$not-here"})
}

// Surprise 6: each login's bridge state is kept under its own remote ID, and the bridge's own (no remote ID) under "".
func TestLoginStatesLandUnderTheirRemoteID(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateUnconfigured}))
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateConnected, RemoteID: "a"}))
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateBadCredentials, RemoteID: "b"}))
	require.NoError(t, c.SendBridgeStatus(ctx, &status.BridgeState{StateEvent: status.StateTransientDisconnect, RemoteID: "a"}))
	states, err := c.store.LoginStates(ctx, "whatsapp")
	require.NoError(t, err)
	got := map[string]status.BridgeStateEvent{}
	for _, l := range states {
		var st status.BridgeState
		require.NoError(t, json.Unmarshal(l.State, &st))
		got[l.LoginID] = st.StateEvent
	}
	require.Equal(t, map[string]status.BridgeStateEvent{
		"": status.StateUnconfigured, "a": status.StateTransientDisconnect, "b": status.StateBadCredentials,
	}, got, "one login's state never replaces another's")
}
