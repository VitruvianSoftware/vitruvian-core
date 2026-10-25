// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// SetRoomName updates the group's remote name on the bridge and stores the confirmed name in rooms.name.
func (a *Actions) SetRoomName(ctx context.Context, roomID, name string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanSetName {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	content := &event.RoomNameEventContent{Name: name}
	raw, err := json.Marshal(content)
	if err != nil {
		return err
	}
	emptyKey := ""
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.StateRoomName,
		StateKey:  &emptyKey,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: content,
		},
	}
	if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
		return err
	}

	portal.Name = name
	if _, err := a.s.SetState(ctx, roomID, event.StateRoomName.Type, "", raw); err != nil {
		return err
	}
	room.Name = name
	return a.s.UpsertRoom(ctx, room)
}

// SetRoomTopic updates the group's remote topic/description on the bridge and stores the confirmed topic in rooms.topic.
func (a *Actions) SetRoomTopic(ctx context.Context, roomID, topic string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanSetTopic {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	content := &event.TopicEventContent{Topic: topic}
	raw, err := json.Marshal(content)
	if err != nil {
		return err
	}
	emptyKey := ""
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.StateTopic,
		StateKey:  &emptyKey,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: content,
		},
	}
	if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
		return err
	}

	portal.Topic = topic
	if _, err := a.s.SetState(ctx, roomID, event.StateTopic.Type, "", raw); err != nil {
		return err
	}
	room.Topic = topic
	return a.s.UpsertRoom(ctx, room)
}

// SetRoomAvatar uploads filePath to the media store (unless already an mxc:// URI or empty), dispatches
// m.room.avatar to the bridge, and stores the confirmed avatar URI in rooms.avatar_uri.
func (a *Actions) SetRoomAvatar(ctx context.Context, roomID, filePath string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanSetAvatar {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	var mxcURI id.ContentURIString
	switch {
	case filePath == "":
		mxcURI = ""
	case strings.HasPrefix(filePath, "mxc://"):
		mxcURI = id.ContentURIString(filePath)
	default:
		data, err := os.ReadFile(filePath)
		if err != nil {
			return err
		}
		hash, err := a.m.Put(data)
		if err != nil {
			return err
		}
		mxcURI = ids.ContentURI(hash)
	}

	content := &event.RoomAvatarEventContent{URL: mxcURI}
	raw, err := json.Marshal(content)
	if err != nil {
		return err
	}
	emptyKey := ""
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.StateRoomAvatar,
		StateKey:  &emptyKey,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: content,
		},
	}
	if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
		return err
	}

	portal.AvatarMXC = mxcURI
	if _, err := a.s.SetState(ctx, roomID, event.StateRoomAvatar.Type, "", raw); err != nil {
		return err
	}
	room.AvatarURI = string(mxcURI)
	return a.s.UpsertRoom(ctx, room)
}

// InviteMembers invites each user in userIDs to roomID on the bridge and records their invite membership in SQLite.
func (a *Actions) InviteMembers(ctx context.Context, roomID string, userIDs []string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanInvite {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	for _, userID := range userIDs {
		stateKey := string(ghostMXIDForBridge(room.Network, userID))
		content := &event.MemberEventContent{Membership: event.MembershipInvite}
		evt := &event.Event{
			ID:        ids.RandomEventID(),
			RoomID:    id.RoomID(roomID),
			Sender:    ids.Me,
			Type:      event.StateMember,
			StateKey:  &stateKey,
			Timestamp: a.now().UnixMilli(),
			Content: event.Content{
				Parsed: content,
			},
			Unsigned: event.Unsigned{
				PrevContent: &event.Content{
					Raw:    map[string]any{"membership": string(event.MembershipLeave)},
					Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
				},
			},
		}
		if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
			return err
		}
		if err := a.setMemberMembership(ctx, roomID, userID, string(event.MembershipInvite)); err != nil {
			return err
		}
	}
	a.s.RoomChanged(roomID)
	return nil
}

// KickMember removes userID from roomID on the bridge and updates their membership in SQLite to leave.
func (a *Actions) KickMember(ctx context.Context, roomID, userID, reason string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanKick {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	stateKey := string(ghostMXIDForBridge(room.Network, userID))
	content := &event.MemberEventContent{
		Membership: event.MembershipLeave,
		Reason:     reason,
	}
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.StateMember,
		StateKey:  &stateKey,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: content,
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipJoin)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
			},
		},
	}
	if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
		return err
	}
	if err := a.setMemberMembership(ctx, roomID, userID, string(event.MembershipLeave)); err != nil {
		return err
	}
	a.s.RoomChanged(roomID)
	return nil
}

// SetMemberAdmin promotes (power level 50) or demotes (power level 0) userID in roomID on the bridge and in SQLite.
func (a *Actions) SetMemberAdmin(ctx context.Context, roomID, userID string, isAdmin bool) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanSetAdmin {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}

	var storePL, prevPL, bridgePL event.PowerLevelsEventContent
	if raw, ok, err := a.s.GetState(ctx, roomID, event.StatePowerLevels.Type, ""); err != nil {
		return err
	} else if ok {
		_ = json.Unmarshal(raw, &storePL)
		_ = json.Unmarshal(raw, &prevPL)
		_ = json.Unmarshal(raw, &bridgePL)
	}
	if storePL.Users == nil {
		storePL.Users = make(map[id.UserID]int)
	}

	ghostMXID := ghostMXIDForBridge(room.Network, userID)
	prevLevel := storePL.Users[id.UserID(userID)]
	newLevel := 0
	if isAdmin {
		newLevel = 50
		if prevLevel == 50 {
			prevLevel = 0
		}
	} else if prevLevel == 0 {
		prevLevel = 50
	}

	prevUsers := maps.Clone(storePL.Users)
	prevUsers[ghostMXID] = prevLevel
	prevPL.Users = prevUsers

	bridgeUsers := maps.Clone(storePL.Users)
	bridgeUsers[ghostMXID] = newLevel
	bridgePL.Users = bridgeUsers

	emptyKey := ""
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.StatePowerLevels,
		StateKey:  &emptyKey,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: &bridgePL,
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Parsed: &prevPL,
			},
		},
	}
	if err := checkBridgeResult(portal.Bridge.QueueMatrixEvent(ctx, evt)); err != nil {
		return err
	}

	if isAdmin {
		storePL.Users[id.UserID(userID)] = 50
	} else {
		delete(storePL.Users, id.UserID(userID))
	}
	rawStore, err := json.Marshal(&storePL)
	if err != nil {
		return err
	}
	if _, err := a.s.SetState(ctx, roomID, event.StatePowerLevels.Type, "", rawStore); err != nil {
		return err
	}
	a.s.RoomChanged(roomID)
	return nil
}

// LeaveRoom leaves roomID on the bridge and marks the room hidden and @me:courier.local's membership leave in SQLite.
func (a *Actions) LeaveRoom(ctx context.Context, roomID string) error {
	_, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanLeave {
		return ErrNotSupported
	}
	portal, _ := a.portalAndLogin(ctx, roomID)
	if portal == nil {
		return store.ErrNotFound
	}
	if err := checkBridgeResult(a.leaveOnNetwork(ctx, portal, roomID)); err != nil {
		return err
	}
	if err := a.setMemberMembership(ctx, roomID, string(ids.Me), string(event.MembershipLeave)); err != nil {
		return err
	}
	if _, err := a.s.SetHidden(ctx, []string{roomID}, true); err != nil {
		return err
	}
	a.s.RoomChanged(roomID)
	return nil
}

// DeleteChat deletes roomID on the bridge via DeleteChatHandlingNetworkAPI and marks the room hidden in SQLite.
func (a *Actions) DeleteChat(ctx context.Context, roomID string) error {
	_, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if !feat.CanDelete {
		return ErrNotSupported
	}
	portal, login := a.portalAndLogin(ctx, roomID)
	if portal == nil || login == nil {
		return store.ErrNotFound
	}
	delAPI, ok := login.Client.(bridgev2.DeleteChatHandlingNetworkAPI)
	if !ok {
		return ErrNotSupported
	}

	content := &event.BeeperChatDeleteEventContent{}
	evt := &event.Event{
		ID:        ids.RandomEventID(),
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		Type:      event.BeeperDeleteChat,
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: content,
		},
	}
	if err := delAPI.HandleMatrixDeleteChat(ctx, &bridgev2.MatrixDeleteChat{
		Event:   evt,
		Content: content,
		Portal:  portal,
	}); err != nil {
		return fmt.Errorf("%w: %w", ErrNetworkRefused, err)
	}

	if feat.DeleteLeavesGroup {
		if err := a.setMemberMembership(ctx, roomID, string(ids.Me), string(event.MembershipLeave)); err != nil {
			return err
		}
	}
	if _, err := a.s.SetHidden(ctx, []string{roomID}, true); err != nil {
		return err
	}
	a.s.RoomChanged(roomID)
	return nil
}

func checkBridgeResult(res bridgev2.EventHandlingResult) error {
	if !res.Success || res.Error != nil {
		if res.Error != nil {
			return fmt.Errorf("%w: %w", ErrNetworkRefused, res.Error)
		}
		return ErrNetworkRefused
	}
	return nil
}

func ghostMXIDForBridge(network, userID string) id.UserID {
	mxid := id.UserID(userID)
	if _, ok := ids.ParseGhostMXID(network, mxid); ok {
		return mxid
	}
	if local, server, err := mxid.Parse(); err == nil && server == ids.ServerName && mxid != ids.Me {
		return ids.GhostMXID(network, networkid.UserID(local))
	}
	return ids.GhostMXID(network, networkid.UserID(userID))
}

func (a *Actions) setMemberMembership(ctx context.Context, roomID, userID, membership string) error {
	raw, err := json.Marshal(map[string]string{"membership": membership})
	if err != nil {
		return err
	}
	return a.s.SetMember(ctx, roomID, userID, raw)
}
