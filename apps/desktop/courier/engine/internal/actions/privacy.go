// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"fmt"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// SetUnreadFrom marks the chat roomID unread from its message eventID on (Mark as Unread from a message, 02 §3.4.2
// item 8): its unread count runs from that message, until the chat is read. Like Courier's whole-chat mark it stays
// on this Mac and is never sent to the network (SyncsOf says why). A message of mine is allowed (only other people's
// messages count); a note (a timer change, a call) is ErrNotSupported (Ruling P2), and a message that isn't in that
// chat is store.ErrNotFound.
func (a *Actions) SetUnreadFrom(ctx context.Context, roomID, eventID string) error {
	err := a.s.SetUnreadFrom(ctx, roomID, eventID)
	if errors.Is(err, store.ErrNote) {
		return fmt.Errorf("%w: %w", ErrNotSupported, err)
	}
	return err
}

// SetUnreadFromEvent is SetUnreadFrom for the chat eventID is in, which it returns (room.setUnreadFrom names only the
// message: C18). An unknown message is store.ErrNotFound.
func (a *Actions) SetUnreadFromEvent(ctx context.Context, eventID string) (roomID string, err error) {
	e, ok, err := a.s.GetEvent(ctx, eventID)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", store.ErrNotFound
	}
	return e.RoomID, a.SetUnreadFrom(ctx, e.RoomID, eventID)
}

// DirectChat is Reply Privately's chat (02 §3.4.2 item 5): the one-to-one chat with userID, a person of the group
// roomID's network who is a member of it, on the group's own account. It answers the chat's room ID.
//
//   - Courier's own one-to-one chat with them is answered first (store.DirectRoomWith), with no network needed: on the
//     group's login (loginOf), which for a group every account shares is the login actually in it, never "" (C15).
//   - Otherwise the bridge makes it, as each network does (Global Constraints' Reply Privately row), through the
//     group's login: GhostDMCreatingNetworkAPI.CreateChatWithGhost, else IdentifierResolvingNetworkAPI's
//     ResolveIdentifier with the person's network ID. A portal without a room yet gets one through
//     Portal.CreateMatrixRoom, as bridgev2's own start-chat command does (bridgev2/provisionutil, used by
//     commands/startchat.go), whose CreateRoom writes it to the store.
//
// Refusals: an unknown chat, or a userID that isn't a person of the chat's network in it (memberGhost), is
// store.ErrNotFound; a one-to-one chat (there is nothing more private), a login that starts no chats, or a network
// that can't find the person is ErrNotSupported; the login not in within LoginWait is ErrNotConnected (the wait of
// every action that isn't queued); a network that won't run this session, or is starting, is HostForRoom's error; the
// network saying no is ErrNetworkRefused. No error names the person.
func (a *Actions) DirectChat(ctx context.Context, roomID, userID string) (string, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", store.ErrNotFound
	}
	if room.IsDirect {
		return "", fmt.Errorf("a one-to-one chat has no private reply: %w", ErrNotSupported)
	}
	ghostID, err := a.memberGhost(ctx, room, userID)
	if err != nil {
		return "", err
	}
	h, _ := a.eng.Host(room.Network)
	if found, ok, err := a.ownDirectChat(ctx, h, room, userID); err != nil || ok {
		return found, err
	}

	h, err = a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	if err = a.waitLogin(ctx, h, roomID); err != nil {
		return "", err
	}
	login := loginOf(ctx, h, room)
	if login == nil {
		return "", fmt.Errorf("%s: %w", h.Network, ErrNotConnected)
	}
	if found, ok, err := a.s.DirectRoomWith(ctx, room.Network, string(login.ID), userID); err != nil || ok {
		return found, err // made meanwhile (the login just came in, or another Reply Privately)
	}
	portal, info, err := startDirectChat(h.Bridge.Log.WithContext(ctx), h, login, ghostID)
	if err != nil {
		if !errors.Is(err, ErrNotSupported) {
			h.Bridge.Log.Warn().Err(err).Str("network", h.Network).Str("action", "direct_chat").
				Msg("a one-to-one chat couldn't be started")
		}
		return "", err
	}
	if portal.MXID == "" {
		// Not CleanupOrphanedDM, which provisionutil runs first: it deletes a room whose member list doesn't have me,
		// and Courier has no server copy of a chat's history to get it back from.
		if err = portal.CreateMatrixRoom(h.Bridge.Log.WithContext(ctx), login, info); err != nil {
			h.Bridge.Log.Warn().Err(err).Str("network", h.Network).Str("action", "direct_chat").
				Msg("a one-to-one chat couldn't be made here")
			return "", err
		}
	}
	made, ok, err := a.s.GetRoom(ctx, string(portal.MXID))
	if err != nil {
		return "", err
	}
	if !ok {
		return "", fmt.Errorf("%s: the bridge made a one-to-one chat that isn't stored", h.Network)
	}
	return made.ID, nil
}

// memberGhost is the network ID of userID when it is a person of room's network (a ghost) who is in room as far as
// Courier knows (store.InChat: a member row, whatever its membership, or a message of theirs, since a bridge's member
// list can leave out a sender). Otherwise store.ErrNotFound, naming no one.
func (a *Actions) memberGhost(ctx context.Context, room store.Room, userID string) (networkid.UserID, error) {
	ghostID, isGhost := ids.ParseGhostMXID(room.Network, id.UserID(userID))
	if !isGhost {
		return "", fmt.Errorf("not a person of this chat's network: %w", store.ErrNotFound)
	}
	in, err := a.s.InChat(ctx, room.ID, userID)
	if err != nil {
		return "", err
	}
	if !in {
		return "", fmt.Errorf("not a member of this chat: %w", store.ErrNotFound)
	}
	return ghostID, nil
}

// ownDirectChat is the one-to-one chat Courier already has with userID on room's account (store.DirectRoomWith). The
// account is room's login (loginOf), or, for a group every account shares whose logins are all down, each of mine the
// bridge has in the group, in loginOf's order: so a chat that exists opens while the network is down. With the network
// not running, only a chat of one account (rooms.login_id) can be looked for.
func (a *Actions) ownDirectChat(ctx context.Context, h *host.Host, room store.Room, userID string) (string, bool, error) {
	var logins []string
	switch {
	case room.LoginID != "":
		logins = []string{room.LoginID}
	case h == nil:
	default:
		if l := loginOf(ctx, h, room); l != nil {
			logins = []string{string(l.ID)}
		} else {
			logins = loginsIn(ctx, h, room)
		}
	}
	for _, l := range logins {
		if found, ok, err := a.s.DirectRoomWith(ctx, room.Network, l, userID); err != nil || ok {
			return found, ok, err
		}
	}
	return "", false, nil
}

// loginsIn are the IDs of my logins the bridge records in room's portal (its user_portal rows), logged in or not, as
// Portal.FindPreferredLogin lists them. None when the bridge has no portal for room.
func loginsIn(ctx context.Context, h *host.Host, room store.Room) []string {
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(room.ID))
	if err != nil || portal == nil {
		return nil
	}
	ups, err := h.Bridge.DB.UserPortal.GetAllForUserInPortal(ctx, ids.Me, portal.PortalKey)
	if err != nil {
		return nil
	}
	out := make([]string, 0, len(ups))
	for _, up := range ups {
		out = append(out, string(up.LoginID))
	}
	return out
}

// startDirectChat asks login's client for its one-to-one chat with the person ghostID, and answers the chat's portal
// and what the network said about it (nil: the bridge asks). A client that starts no chats, or a network that can't
// find the person, is ErrNotSupported; the network's own failure is ErrNetworkRefused, wrapping its reason.
func startDirectChat(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, ghostID networkid.UserID) (*bridgev2.Portal, *bridgev2.ChatInfo, error) {
	var chat *bridgev2.CreateChatResponse
	switch api := login.Client.(type) {
	case bridgev2.GhostDMCreatingNetworkAPI:
		ghost, err := h.Bridge.GetGhostByID(ctx, ghostID)
		if err != nil {
			return nil, nil, err
		}
		if chat, err = api.CreateChatWithGhost(ctx, ghost); err != nil {
			return nil, nil, fmt.Errorf("%w: %w", ErrNetworkRefused, err)
		}
	case bridgev2.IdentifierResolvingNetworkAPI:
		resp, err := api.ResolveIdentifier(ctx, string(ghostID), true)
		if err != nil {
			return nil, nil, fmt.Errorf("%w: %w", ErrNetworkRefused, err)
		}
		if resp == nil {
			return nil, nil, fmt.Errorf("%s doesn't know how to reach them: %w", h.Network, ErrNotSupported)
		}
		chat = resp.Chat
	default:
		return nil, nil, fmt.Errorf("%s starts no chats: %w", h.Network, ErrNotSupported)
	}
	if chat == nil || chat.PortalKey.IsEmpty() {
		return nil, nil, fmt.Errorf("%s gave no chat: %w", h.Network, ErrNotSupported)
	}
	portal := chat.Portal
	if portal == nil {
		var err error
		if portal, err = h.Bridge.GetPortalByKey(ctx, chat.PortalKey); err != nil {
			return nil, nil, err
		}
	}
	return portal, chat.PortalInfo, nil
}
