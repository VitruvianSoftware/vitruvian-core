// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package localmatrix lets stock mautrix bridges run with courier's local store in place of a Matrix server.
package localmatrix

import (
	"context"
	"encoding/json"
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
	if err := c.store.SetStatus(ctx, string(info.SourceEventID), st, statusReason(ms)); err != nil {
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

// applyRoomState mirrors name/topic/avatar/member state into the rooms and members tables the app reads.
func (c *Connector) applyRoomState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, raw json.RawMessage) error {
	if evtType == event.StateMember {
		return c.store.SetMember(ctx, string(roomID), stateKey, raw)
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
