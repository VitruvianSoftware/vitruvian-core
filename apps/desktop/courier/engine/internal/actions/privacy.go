// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"maunium.net/go/mautrix"
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
	if err = a.SetUnreadFrom(ctx, e.RoomID, eventID); err != nil {
		return "", err
	}
	return e.RoomID, nil
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
// that can't reach the person (startFailure) is ErrNotSupported; the login not in within LoginWait is ErrNotConnected
// (the wait of every action that isn't queued); a network that won't run this session, or is starting, is
// HostForRoom's error; the network failing, or the bridge not making the chat's room, is ErrNetworkRefused. No error
// names the person.
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
		if !errors.Is(err, ErrNotSupported) { // an unreachable person is an answer, not a fault
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
			// The network said yes, but the bridge couldn't make its room (it asks the network about the chat first
			// when the answer didn't say): as it stands, this chat can't be had.
			return "", fmt.Errorf("%w: the bridge couldn't make the one-to-one chat: %w", ErrNetworkRefused, err)
		}
	}
	made, ok, err := a.s.GetRoom(ctx, string(portal.MXID))
	if err != nil {
		return "", err
	}
	if !ok {
		return "", fmt.Errorf("%w: %s made a one-to-one chat that isn't stored", ErrNetworkRefused, h.Network)
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
// account is room's login (rooms.login_id, else loginOf), or, for a group every account shares whose logins are all
// down, each of mine the bridge has in the group, in loginOf's order: so a chat that exists opens while the network is
// down. With the network starting or not running there is no bridge to say which account a shared group is in (every
// WhatsApp group is one): the network's only account, when the store knows of exactly one (onlyAccount), else none,
// never "the first" of two (Review Focus 5).
func (a *Actions) ownDirectChat(ctx context.Context, h *host.Host, room store.Room, userID string) (string, bool, error) {
	var logins []string
	switch {
	case room.LoginID != "":
		logins = []string{room.LoginID}
	case h == nil:
		only, ok, err := a.onlyAccount(ctx, room.Network)
		if err != nil {
			return "", false, err
		}
		if ok {
			logins = []string{only}
		}
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

// onlyAccount is the network's one account, when the store knows of exactly one: one login state of a login (the
// bridge-wide state, "", is no account). States are kept per login and never dropped when another is added
// (Ruling 11), so two accounts ever seen on the network are two here.
func (a *Actions) onlyAccount(ctx context.Context, network string) (string, bool, error) {
	states, err := a.s.LoginStates(ctx, network)
	if err != nil {
		return "", false, err
	}
	var only []string
	for _, st := range states {
		if st.LoginID != "" {
			only = append(only, st.LoginID)
		}
	}
	if len(only) != 1 {
		return "", false, nil
	}
	return only[0], true, nil
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

// googleMessagesNoPhone is the start and end of mautrix-gmessages' error for a person whose phone number it doesn't
// know (pkg/connector/startchat.go:85-87, v0.2609.0: "phone number of ghost %s not known"), which has no sentinel to
// test for. TestGoogleMessagesBridgeVersionIsTheOneCheckedForUnreachablePeople (networks) fails when the bridge moves.
const (
	googleMessagesNoPhonePrefix = "phone number of ghost "
	googleMessagesNoPhoneSuffix = " not known"
)

// startFailure classifies a chat start's error. A person the login can't reach is ErrNotSupported, an answer and not
// a fault: bridgev2.ErrResolveIdentifierTryNext (another login could: Google Messages' other phone, Telegram without
// the access hash), a RespError of M_INVALID_PARAM or M_NOT_FOUND (Google Messages' invalid number), or Google
// Messages without the phone number. Anything else is the network failing: ErrNetworkRefused, wrapping its reason.
func startFailure(network string, err error) error {
	var re bridgev2.RespError
	msg := err.Error()
	switch {
	case errors.Is(err, bridgev2.ErrResolveIdentifierTryNext),
		errors.As(err, &re) && (re.ErrCode == mautrix.MInvalidParam.ErrCode || re.ErrCode == mautrix.MNotFound.ErrCode),
		strings.HasPrefix(msg, googleMessagesNoPhonePrefix) && strings.HasSuffix(msg, googleMessagesNoPhoneSuffix):
		return fmt.Errorf("%s can't reach them: %w", network, ErrNotSupported)
	}
	return fmt.Errorf("%w: %w", ErrNetworkRefused, err)
}

// startDirectChat asks login's client for its one-to-one chat with the person ghostID, and answers the chat's portal
// and what the network said about it (nil: the bridge asks). A client that starts no chats, or a network that can't
// reach the person, is ErrNotSupported (startFailure); the network's own failure is ErrNetworkRefused.
func startDirectChat(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, ghostID networkid.UserID) (*bridgev2.Portal, *bridgev2.ChatInfo, error) {
	var chat *bridgev2.CreateChatResponse
	switch api := login.Client.(type) {
	case bridgev2.GhostDMCreatingNetworkAPI:
		ghost, err := h.Bridge.GetGhostByID(ctx, ghostID)
		if err != nil {
			return nil, nil, err
		}
		if chat, err = api.CreateChatWithGhost(ctx, ghost); err != nil {
			return nil, nil, startFailure(h.Network, err)
		}
	case bridgev2.IdentifierResolvingNetworkAPI:
		resp, err := api.ResolveIdentifier(ctx, string(ghostID), true)
		if err != nil {
			return nil, nil, startFailure(h.Network, err)
		}
		if resp == nil { // bridgev2's "identifier not found": no pinned bridge answers it when asked to create
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
