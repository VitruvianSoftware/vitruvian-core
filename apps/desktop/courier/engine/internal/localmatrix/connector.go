// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package localmatrix lets stock mautrix bridges run with courier's local store in place of a Matrix server.
package localmatrix

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Connector is the bridgev2.MatrixConnector for one network. It answers every
// call a bridge would make to a homeserver from the local store.
type Connector struct {
	network string
	store   *store.Store
	media   *media.Store
	br      *bridgev2.Bridge
	log     zerolog.Logger
}

var _ bridgev2.MatrixConnector = (*Connector)(nil)

func New(network string, s *store.Store, m *media.Store) *Connector {
	return &Connector{network: network, store: s, media: m, log: zerolog.Nop()}
}

// Bridge returns the bridge this connector was initialised with, or nil before Init.
func (c *Connector) Bridge() *bridgev2.Bridge { return c.br }

func (c *Connector) Init(br *bridgev2.Bridge) {
	c.br = br
	c.log = br.Log.With().Str("component", "localmatrix").Logger()
}

// Start, PreStop and Stop have nothing to do: there is no server connection to open or close.
func (c *Connector) Start(context.Context) error { return nil }
func (c *Connector) PreStop()                    {}
func (c *Connector) Stop()                       {}

func (c *Connector) GetCapabilities() *bridgev2.MatrixCapabilities {
	// AutoJoinInvites: no real invites exist locally. ArbitraryMemberChange: we write any member row directly.
	return &bridgev2.MatrixCapabilities{AutoJoinInvites: true, ArbitraryMemberChange: true}
}

func (c *Connector) ParseGhostMXID(userID id.UserID) (networkid.UserID, bool) {
	return ids.ParseGhostMXID(c.network, userID)
}

func (c *Connector) FormatGhostMXID(userID networkid.UserID) id.UserID {
	return ids.GhostMXID(c.network, userID)
}

func (c *Connector) GhostIntent(userID networkid.UserID) bridgev2.MatrixAPI {
	return newIntent(c, c.FormatGhostMXID(userID), false)
}

func (c *Connector) NewUserIntent(_ context.Context, userID id.UserID, _ string) (bridgev2.MatrixAPI, string, error) {
	// The local user is "double puppeted" by definition: messages sent from other devices appear as sent by @me.
	return newIntent(c, userID, true), "", nil
}

func (c *Connector) BotIntent() bridgev2.MatrixAPI {
	return newIntent(c, id.NewUserID(c.network+"bot", ids.ServerName), false)
}

func (c *Connector) SendBridgeStatus(ctx context.Context, st *status.BridgeState) error {
	raw, err := json.Marshal(st)
	if err != nil {
		return err
	}
	return c.store.SetBridgeState(ctx, c.network, raw)
}

func (c *Connector) SendMessageStatus(ctx context.Context, ms *bridgev2.MessageStatus, info *bridgev2.MessageStatusEventInfo) {
	var st string
	switch ms.Status {
	case event.MessageStatusSuccess:
		st = "sent"
	case event.MessageStatusFail, event.MessageStatusRetriable:
		st = "failed"
	case event.MessageStatusPending:
		st = "pending"
	default:
		// A status we do not know must never be shown as "sent": leave the row as it is.
		c.log.Warn().Str("status", string(ms.Status)).Str("event_id", string(info.SourceEventID)).
			Msg("ignoring unknown message status")
		return
	}
	err := c.store.SetStatus(ctx, string(info.SourceEventID), st, statusReason(ms))
	if errors.Is(err, sql.ErrNoRows) {
		// Not a stored message: a chat change such as accepting a message request also gets a status.
		return
	}
	if err != nil {
		c.log.Warn().Err(err).Str("event_id", string(info.SourceEventID)).Msg("failed to store message status")
	}
}

// statusReason picks the text a user sees for a message status. Most errors reach bridgev2's
// WrapErrorInStatus, which leaves Message empty and puts the detail in InternalError.
func statusReason(ms *bridgev2.MessageStatus) string {
	if ms.InternalError != nil && (ms.Message == "" || ms.ErrorAsMessage) {
		return ms.InternalError.Error()
	}
	if ms.Message != "" {
		return ms.Message
	}
	return string(ms.ErrorReason)
}

func (c *Connector) GenerateContentURI(_ context.Context, mediaID networkid.MediaID) (id.ContentURIString, error) {
	return "", fmt.Errorf("direct media is not supported locally (media %s)", mediaID)
}

func (c *Connector) ParseContentURI(_ context.Context, uri id.ContentURIString) (networkid.MediaID, error) {
	return nil, fmt.Errorf("direct media is not supported locally (%s)", uri)
}

func (c *Connector) GetPowerLevels(ctx context.Context, roomID id.RoomID) (*event.PowerLevelsEventContent, error) {
	raw, ok, err := c.store.GetState(ctx, string(roomID), event.StatePowerLevels.Type, "")
	if err != nil {
		return nil, err
	}
	if !ok {
		return &event.PowerLevelsEventContent{}, nil
	}
	var content event.Content
	if err = json.Unmarshal(raw, &content); err != nil {
		return nil, err
	}
	if err = content.ParseRaw(event.StatePowerLevels); err != nil {
		return nil, err
	}
	return content.AsPowerLevels(), nil
}

func (c *Connector) GetMembers(ctx context.Context, roomID id.RoomID) (map[id.UserID]*event.MemberEventContent, error) {
	rows, err := c.store.Members(ctx, string(roomID))
	if err != nil {
		return nil, err
	}
	out := make(map[id.UserID]*event.MemberEventContent, len(rows))
	for u, raw := range rows {
		var m event.MemberEventContent
		if err := json.Unmarshal(raw, &m); err != nil {
			return nil, err
		}
		out[id.UserID(u)] = &m
	}
	return out, nil
}

func (c *Connector) GetMemberInfo(ctx context.Context, roomID id.RoomID, userID id.UserID) (*event.MemberEventContent, error) {
	all, err := c.GetMembers(ctx, roomID)
	if err != nil {
		return nil, err
	}
	return all[userID], nil
}

func (c *Connector) BatchSend(context.Context, id.RoomID, *mautrix.ReqBeeperBatchSend, []*bridgev2.MatrixSendExtra) (*mautrix.RespBeeperBatchSend, error) {
	// GetCapabilities reports BatchSending=false, so bridgev2 backfills through SendMessage instead.
	return nil, fmt.Errorf("batch send not supported")
}

func (c *Connector) GenerateDeterministicRoomID(key networkid.PortalKey) id.RoomID {
	return ids.RoomID(c.network, key)
}

func (c *Connector) GenerateDeterministicEventID(roomID id.RoomID, key networkid.PortalKey, msg networkid.MessageID, part networkid.PartID) id.EventID {
	return ids.EventID(roomID, key, msg, part)
}

func (c *Connector) GenerateReactionEventID(roomID id.RoomID, target *database.Message, sender networkid.UserID, emoji networkid.EmojiID) id.EventID {
	// The interface passes no emoji text, so on networks without emoji IDs this ID cannot tell two emoji apart.
	// Reactions arriving from the network are unaffected: Intent.SendMessage hashes the emoji text itself.
	return ids.ReactionEventID(roomID, target.ID, target.PartID, sender, emoji, "")
}

func (c *Connector) ServerName() string { return ids.ServerName }

// applyRoomState mirrors name/topic/avatar/member state into the rooms and members tables the app reads, and the
// bridge info's message-request flag into the room's request flag. created says the state is the initial state of
// a room that has just been made; changed, that the stored state is not what it was.
func (c *Connector) applyRoomState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, raw json.RawMessage, created, changed bool) error {
	if evtType == event.StateMember {
		return c.store.SetMember(ctx, string(roomID), stateKey, raw)
	}
	if evtType == event.StateBeeperRoomFeatures {
		// What the chat can do (actions.Features reads it from the stored state) changed: bridgev2's
		// UpdateCapabilities sends it when the network's room features do. The app reads the chat again. A room
		// just made is new to the app anyway, and a resend that says nothing new is no churn.
		if changed && !created {
			c.store.RoomChanged(string(roomID))
		}
		return nil
	}
	if evtType == event.StateBridge || evtType == event.StateHalfShotBridge {
		return c.applyBridgeInfo(ctx, roomID, raw, created)
	}
	if evtType != event.StateRoomName && evtType != event.StateTopic && evtType != event.StateRoomAvatar {
		return nil
	}
	var fields struct {
		Name  string              `json:"name"`
		Topic string              `json:"topic"`
		URL   id.ContentURIString `json:"url"`
	}
	if err := json.Unmarshal(raw, &fields); err != nil {
		return fmt.Errorf("invalid %s content: %w", evtType.Type, err)
	}
	room, ok, err := c.store.GetRoom(ctx, string(roomID))
	if err != nil {
		return err
	}
	if !ok {
		room = store.Room{ID: string(roomID), Network: c.network, CreatedAt: time.Now()}
	}
	switch evtType {
	case event.StateRoomName:
		room.Name = fields.Name
	case event.StateTopic:
		room.Topic = fields.Topic
	case event.StateRoomAvatar:
		room.AvatarURI = string(fields.URL)
	}
	return c.store.UpsertRoom(ctx, room)
}

// applyBridgeInfo reads whether the chat is a message request (someone new writing first) from the bridge info
// bridgev2 keeps on each room. The key is left out when it is false, so its absence means "not a request": that
// is how an accepted request reads afterwards.
//
// "Not a request" is taken in at any time, "a request" only in the initial state of a chat just created.
// bridgev2 resends the bridge info on any change to the chat's info (a name, an avatar: portal.go:5196-5229 of
// mautrix v0.31.0), and after an accept made here that the network refused or never heard of (offline), that
// resend still says "request": taking it would undo the accept, and a local change is never undone.
func (c *Connector) applyBridgeInfo(ctx context.Context, roomID id.RoomID, raw json.RawMessage, created bool) error {
	var info struct {
		Channel struct {
			MessageRequest bool `json:"com.beeper.message_request"`
		} `json:"channel"`
	}
	if err := json.Unmarshal(raw, &info); err != nil {
		return fmt.Errorf("invalid bridge info: %w", err)
	}
	if info.Channel.MessageRequest && !created {
		return nil
	}
	// SetRequest writes and publishes only when the flag changes, so a resend that says nothing new is no churn.
	err := c.store.SetRequest(ctx, string(roomID), info.Channel.MessageRequest)
	if errors.Is(err, store.ErrNotFound) {
		return nil // no such room (any more): nothing to flag
	}
	return err
}
