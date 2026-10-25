// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"fmt"
	"slices"
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
	return a.DirectChatWithAccount(ctx, roomID, "", "", userID)
}

// DirectChatWithAccount creates or reuses the 1:1 DM room with userID. When viaRoomID != "", it resolves the login
// from viaRoomID as in DirectChat. When viaRoomID == "", it resolves the login from (network, accountID) (or the sole
// connected login for network when accountID == "") and starts the DM via CreateChatWithGhost, falling back to
// ResolveIdentifier with the ghost's first stored identifier when the bridge does not implement CreateChatWithGhost.
func (a *Actions) DirectChatWithAccount(ctx context.Context, viaRoomID, network, accountID, userID string) (string, error) {
	if viaRoomID != "" {
		room, ok, err := a.s.GetRoom(ctx, viaRoomID)
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

		h, err = a.eng.HostForRoom(ctx, viaRoomID)
		if err != nil {
			return "", err
		}
		if err = a.waitLogin(ctx, h, viaRoomID); err != nil {
			return "", err
		}
		login := loginOf(ctx, h, room)
		if login == nil {
			return "", fmt.Errorf("%s: %w", h.Network, ErrNotConnected)
		}
		if found, ok, err := a.s.DirectRoomWith(ctx, room.Network, string(login.ID), userID); err != nil || ok {
			return found, err // made meanwhile (the login just came in, or another Reply Privately)
		}
		return a.createDirectChatRoom(ctx, h, login, ghostID, userID, viaRoomID)
	}

	if network == "" {
		return "", store.ErrNotFound
	}
	ghostID, canonicalMXID, ok := parseAccountGhostUserID(network, userID)
	if !ok {
		return "", fmt.Errorf("not a person of this network: %w", store.ErrNotFound)
	}
	if found, ok, err := a.ownAccountDirectChat(ctx, network, accountID, userID, string(canonicalMXID)); err != nil || ok {
		return found, err
	}
	h, login, err := a.loginForAccount(ctx, network, accountID)
	if err != nil {
		return "", err
	}
	for _, candidate := range uniqueStrings(userID, string(canonicalMXID)) {
		if found, ok, err := a.s.DirectRoomWith(ctx, network, string(login.ID), candidate); err != nil || ok {
			return found, err
		}
	}
	return a.createDirectChatRoom(ctx, h, login, ghostID, string(canonicalMXID), "")
}

func (a *Actions) createDirectChatRoom(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, ghostID networkid.UserID, userID, viaRoomID string) (string, error) {
	portal, info, err := a.startDirectChat(h.Bridge.Log.WithContext(ctx), h, login, ghostID, userID, viaRoomID)
	if err != nil {
		if !errors.Is(err, ErrNotSupported) { // an unreachable person is an answer, not a fault
			h.Bridge.Log.Warn().Str("network", h.Network).Str("action", "direct_chat").Str("reason", "network_refused").
				Msg("a one-to-one chat couldn't be started")
		}
		return "", err
	}
	if err := a.ensurePortalRoom(ctx, h, login, portal, info, "direct_chat"); err != nil {
		return "", err
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

// ensurePortalRoom creates the Matrix room for portal when it has none yet, reusing bridgev2's own
// Portal.CreateMatrixRoom path (which fetches GetChatInfo itself in portal.go when info == nil or info.Members == nil).
func (a *Actions) ensurePortalRoom(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, portal *bridgev2.Portal, info *bridgev2.ChatInfo, action string) error {
	if portal.MXID == "" {
		// Not CleanupOrphanedDM, which provisionutil runs first: it deletes a room whose member list doesn't have me,
		// and Courier has no server copy of a chat's history to get it back from.
		if err := portal.CreateMatrixRoom(h.Bridge.Log.WithContext(ctx), login, info); err != nil {
			h.Bridge.Log.Warn().Str("network", h.Network).Str("action", action).Str("reason", "room_create_failed").
				Msg("a one-to-one chat couldn't be made here")
			// The network said yes, but the bridge couldn't make its room (it asks the network about the chat first
			// when the answer didn't say): as it stands, this chat can't be had.
			return fmt.Errorf("%w: the bridge couldn't make the one-to-one chat", ErrNetworkRefused)
		}
	}
	return nil
}

func parseAccountGhostUserID(network, userID string) (networkid.UserID, id.UserID, bool) {
	mxid := id.UserID(userID)
	if ghostID, ok := ids.ParseGhostMXID(network, mxid); ok {
		return ghostID, mxid, true
	}
	local, server, err := mxid.Parse()
	if err != nil || server != ids.ServerName || mxid == ids.Me || local == "" {
		return "", "", false
	}
	ghostID := networkid.UserID(local)
	return ghostID, ids.GhostMXID(network, ghostID), true
}

func uniqueStrings(vals ...string) []string {
	out := make([]string, 0, len(vals))
	for _, v := range vals {
		if v != "" && !slices.Contains(out, v) {
			out = append(out, v)
		}
	}
	return out
}

func (a *Actions) ownAccountDirectChat(ctx context.Context, network, accountID, userID, canonicalMXID string) (string, bool, error) {
	var logins []string
	switch {
	case accountID != "":
		logins = []string{accountID}
	default:
		if h, ok := a.eng.Host(network); ok && h != nil {
			for _, l := range myLogins(h) {
				logins = append(logins, string(l.ID))
			}
		} else if only, ok, err := a.onlyAccount(ctx, network); err != nil || ok {
			if err != nil {
				return "", false, err
			}
			logins = []string{only}
		}
	}
	candidates := uniqueStrings(userID, canonicalMXID)
	for _, l := range logins {
		for _, c := range candidates {
			if found, ok, err := a.s.DirectRoomWith(ctx, network, l, c); err != nil || ok {
				return found, ok, err
			}
		}
	}
	return "", false, nil
}

func (a *Actions) loginForAccount(ctx context.Context, network, accountID string) (*host.Host, *bridgev2.UserLogin, error) {
	h, ok := a.eng.Host(network)
	if !ok || h == nil {
		return nil, nil, store.ErrNotFound
	}
	pick := func() *bridgev2.UserLogin {
		for _, l := range myLogins(h) {
			if accountID != "" && string(l.ID) != accountID {
				continue
			}
			if l.Client != nil && l.Client.IsLoggedIn() {
				return l
			}
		}
		return nil
	}
	if l := pick(); l != nil {
		return h, l, nil
	}
	if accountID != "" {
		found := false
		for _, l := range myLogins(h) {
			if string(l.ID) == accountID {
				found = true
				break
			}
		}
		if !found {
			return nil, nil, store.ErrNotFound
		}
	}
	feed := a.s.Feed()
	defer feed.Close()
	after := a.after
	if after == nil {
		after = a.defaultAfter()
	}
	if err := waitForLogin(ctx, h, a.LoginWait, after, feed.C, func() bool { return pick() != nil }); err != nil {
		return nil, nil, err
	}
	l := pick()
	if l == nil {
		return nil, nil, fmt.Errorf("%s: %w", h.Network, ErrNotConnected)
	}
	return h, l, nil
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
			logins, _ = loginsIn(ctx, h, room) // none found: the bridge is asked instead
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
func loginsIn(ctx context.Context, h *host.Host, room store.Room) ([]string, error) {
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(room.ID))
	if err != nil || portal == nil {
		return nil, err
	}
	ups, err := h.Bridge.DB.UserPortal.GetAllForUserInPortal(ctx, ids.Me, portal.PortalKey)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(ups))
	for _, up := range ups {
		out = append(out, string(up.LoginID))
	}
	return out, nil
}

// HasAccountFor reports whether the chat roomID has an account of mine that could send it, now or once it is back:
// false means a message waiting there can't go until an account is in the chat again (the app says so: rpc's "no
// account"), true that it is just waiting. It follows loginOf's branches, with two deliberate departures, because it
// answers "is there an account at all", not "which login sends now":
//   - It ignores whether a login is logged in. loginOf (Portal.FindPreferredLogin) takes only a logged-in login of a
//     shared chat, so a group whose only account is down has none there; here it has one, since the message goes when
//     that account is back.
//   - A chat the bridge has no portal for has one while the network has any account of mine, logged in or not, where
//     loginOf takes the first that is logged in.
//
// Otherwise: a chat of one account (rooms.login_id) has one while that account is one of mine the bridge has; a
// shared chat has one while its portal's receiver is mine (a legacy chat whose login_id isn't known yet) or an account
// of mine is in it (its user_portal rows). A network that isn't running can't say, and its chats count as having one.
// An unknown chat is store.ErrNotFound.
func (a *Actions) HasAccountFor(ctx context.Context, roomID string) (bool, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return false, err
	}
	if !ok {
		return false, store.ErrNotFound
	}
	h, ok := a.eng.Host(room.Network)
	if !ok {
		return true, nil
	}
	mine := myLogins(h)
	isMine := func(accountID string) bool {
		return slices.ContainsFunc(mine, func(l *bridgev2.UserLogin) bool { return string(l.ID) == accountID })
	}
	if room.LoginID != "" {
		return isMine(room.LoginID), nil
	}
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(room.ID))
	if err != nil {
		return false, err
	}
	switch {
	case portal == nil:
		return len(mine) > 0, nil
	case portal.Receiver != "": // a legacy chat whose login_id isn't known yet
		return isMine(string(portal.Receiver)), nil
	}
	in, err := loginsIn(ctx, h, room)
	if err != nil {
		return false, err
	}
	return slices.ContainsFunc(in, isMine), nil
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
	return fmt.Errorf("%s refused to start the chat: %w", network, ErrNetworkRefused)
}

// startDirectChat asks login's client for its one-to-one chat with the person ghostID, and answers the chat's portal
// and what the network said about it (nil: the bridge asks). A client that starts no chats, or a network that can't
// reach the person, is ErrNotSupported (startFailure); the network's own failure is ErrNetworkRefused.
func (a *Actions) startDirectChat(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, ghostID networkid.UserID, userID, _ string) (*bridgev2.Portal, *bridgev2.ChatInfo, error) {
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
		candidates, err := a.ghostIdentifiers(ctx, h, ghostID, userID)
		if err != nil {
			return nil, nil, err
		}
		if len(candidates) == 0 {
			return nil, nil, fmt.Errorf("%s doesn't know how to reach them: %w", h.Network, ErrNotSupported)
		}
		var lastErr error
		var sawNotFound bool
		var resp *bridgev2.ResolveIdentifierResponse
		for _, ident := range candidates {
			r, resolveErr := api.ResolveIdentifier(ctx, ident, true)
			if resolveErr != nil {
				lastErr = resolveErr
				continue
			}
			if r != nil {
				resp = r
				lastErr = nil
				break
			}
			sawNotFound = true
		}
		if resp == nil && sawNotFound { // bridgev2's "identifier not found": takes precedence over earlier attempt errors
			return nil, nil, fmt.Errorf("%s doesn't know how to reach them: %w", h.Network, ErrNotSupported)
		}
		if lastErr != nil {
			return nil, nil, startFailure(h.Network, lastErr)
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

func (a *Actions) ghostIdentifiers(ctx context.Context, h *host.Host, ghostID networkid.UserID, userID string) ([]string, error) {
	var raw []string
	if strings.TrimSpace(string(ghostID)) != "" {
		raw = append(raw, strings.TrimSpace(string(ghostID)))
	}
	for _, candidate := range uniqueStrings(userID, string(ids.GhostMXID(h.Network, ghostID))) {
		prof, ok, err := a.s.GetProfile(ctx, candidate)
		if err != nil {
			return nil, err
		}
		if ok {
			for _, idStr := range prof.Identifiers {
				if stripped := stripIdentifierScheme(idStr); stripped != "" {
					raw = append(raw, stripped)
				}
			}
		}
	}
	if ghost, err := h.Bridge.GetExistingGhostByID(ctx, ghostID); err == nil && ghost != nil {
		for _, idStr := range ghost.Identifiers {
			if stripped := stripIdentifierScheme(idStr); stripped != "" {
				raw = append(raw, stripped)
			}
		}
	}
	return uniqueStrings(raw...), nil
}

func stripIdentifierScheme(raw string) string {
	s := strings.TrimSpace(raw)
	switch {
	case strings.HasPrefix(s, "tel:"):
		return strings.TrimSpace(strings.TrimPrefix(s, "tel:"))
	case strings.HasPrefix(s, "telegram:"):
		name := strings.TrimSpace(strings.TrimPrefix(s, "telegram:"))
		name = strings.TrimLeft(name, "@")
		if name == "" {
			return ""
		}
		return "@" + name
	default:
		return s
	}
}
