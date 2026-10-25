// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type ContactCandidate struct {
	UserID      string   `json:"user_id"`
	Name        string   `json:"name"`
	AvatarPath  string   `json:"avatar_path"`
	Network     string   `json:"network"`
	AccountID   string   `json:"account_id"`
	Identifiers []string `json:"identifiers"`
	RoomID      string   `json:"room_id,omitempty"`
}

func (a *Actions) defaultAfter() func(time.Duration) <-chan time.Time {
	return time.After
}

// ListContacts queries the connected bridge account(s) for their contact list (GetContactList) and, when query is
// non-empty, user search hits (SearchUsers), merging and filtering the results into ContactCandidate rows.
func (a *Actions) ListContacts(ctx context.Context, network, accountID, query string) ([]ContactCandidate, error) {
	var networks []string
	if network != "" {
		networks = []string{network}
	} else {
		networks = a.eng.Names()
	}

	q := strings.ToLower(strings.TrimSpace(query))
	byKey := make(map[string]int)
	out := []ContactCandidate{}

	mergeCandidate := func(c ContactCandidate) {
		key := c.Network + "\x00" + c.AccountID + "\x00" + c.UserID
		if idx, exists := byKey[key]; exists {
			cur := &out[idx]
			if cur.Name == "" {
				cur.Name = c.Name
			}
			if cur.AvatarPath == "" {
				cur.AvatarPath = c.AvatarPath
			}
			if cur.RoomID == "" {
				cur.RoomID = c.RoomID
			}
			for _, idStr := range c.Identifiers {
				if !slices.Contains(cur.Identifiers, idStr) {
					cur.Identifiers = append(cur.Identifiers, idStr)
				}
			}
			return
		}
		byKey[key] = len(out)
		out = append(out, c)
	}

	for _, netName := range networks {
		h, ok := a.eng.Host(netName)
		if !ok || h == nil {
			continue
		}
		logCtx := h.Bridge.Log.WithContext(ctx)
		for _, login := range myLogins(h) {
			if accountID != "" && string(login.ID) != accountID {
				continue
			}
			if login.Client == nil || !login.Client.IsLoggedIn() {
				continue
			}
			if api, ok := login.Client.(bridgev2.ContactListingNetworkAPI); ok {
				contacts, err := api.GetContactList(logCtx)
				if err != nil {
					return nil, fmt.Errorf("%w: %w", ErrNetworkRefused, err)
				}
				for _, r := range contacts {
					if r == nil {
						continue
					}
					c, err := a.candidateFromResolve(ctx, h, login, r, false)
					if err != nil {
						return nil, err
					}
					mergeCandidate(c)
				}
			}
			if q != "" {
				if api, ok := login.Client.(bridgev2.UserSearchingNetworkAPI); ok {
					hits, err := api.SearchUsers(logCtx, query)
					if err != nil {
						return nil, fmt.Errorf("%w: %w", ErrNetworkRefused, err)
					}
					for _, r := range hits {
						if r == nil {
							continue
						}
						c, err := a.candidateFromResolve(ctx, h, login, r, false)
						if err != nil {
							return nil, err
						}
						mergeCandidate(c)
					}
				}
			}
		}
	}

	if q == "" {
		return out, nil
	}
	filtered := make([]ContactCandidate, 0, len(out))
	for _, c := range out {
		if matchesContactQuery(c, q) {
			filtered = append(filtered, c)
		}
	}
	return filtered, nil
}

func matchesContactQuery(c ContactCandidate, q string) bool {
	if strings.Contains(strings.ToLower(c.Name), q) || strings.Contains(strings.ToLower(c.UserID), q) {
		return true
	}
	for _, idStr := range c.Identifiers {
		if strings.Contains(strings.ToLower(idStr), q) {
			return true
		}
	}
	return false
}

// ResolveIdentifier resolves a phone number, username, or network user ID on (network, accountID) via
// IdentifierResolvingNetworkAPI. When startChat is true, it also creates or reuses the 1:1 DM room and populates
// PortalInfo via GetChatInfo if the bridge returned a nil PortalInfo.
func (a *Actions) ResolveIdentifier(ctx context.Context, network, accountID, identifier string, startChat bool) (ContactCandidate, error) {
	if strings.TrimSpace(identifier) == "" {
		return ContactCandidate{}, ErrBadValue
	}
	h, login, err := a.loginForAccount(ctx, network, accountID)
	if err != nil {
		return ContactCandidate{}, err
	}
	api, ok := login.Client.(bridgev2.IdentifierResolvingNetworkAPI)
	if !ok {
		return ContactCandidate{}, fmt.Errorf("%s does not resolve identifiers: %w", h.Network, ErrNotSupported)
	}
	logCtx := h.Bridge.Log.WithContext(ctx)
	resp, err := api.ResolveIdentifier(logCtx, identifier, startChat)
	if err != nil {
		return ContactCandidate{}, startFailure(h.Network, err)
	}
	if resp == nil {
		return ContactCandidate{}, store.ErrNotFound
	}
	return a.candidateFromResolve(ctx, h, login, resp, startChat)
}

func (a *Actions) candidateFromResolve(ctx context.Context, h *host.Host, login *bridgev2.UserLogin, resp *bridgev2.ResolveIdentifierResponse, startChat bool) (ContactCandidate, error) {
	logCtx := h.Bridge.Log.WithContext(ctx)
	var userMXID id.UserID
	if resp.Ghost != nil {
		userMXID = resp.Ghost.Intent.GetMXID()
	} else {
		userMXID = ids.GhostMXID(h.Network, resp.UserID)
	}

	var name string
	var avatarURI string
	var identifiers []string

	if resp.UserInfo != nil {
		if resp.UserInfo.Name != nil {
			name = *resp.UserInfo.Name
		}
		if len(resp.UserInfo.Identifiers) > 0 {
			identifiers = append(identifiers, resp.UserInfo.Identifiers...)
		}
	}
	if resp.Ghost != nil {
		if startChat && resp.UserInfo != nil {
			resp.Ghost.UpdateInfo(logCtx, resp.UserInfo)
		}
		if name == "" && resp.Ghost.Name != "" {
			name = resp.Ghost.Name
		}
		if resp.Ghost.AvatarMXC != "" {
			avatarURI = string(resp.Ghost.AvatarMXC)
		}
		for _, idStr := range resp.Ghost.Identifiers {
			if !slices.Contains(identifiers, idStr) {
				identifiers = append(identifiers, idStr)
			}
		}
	}

	var roomID string
	if resp.Chat != nil {
		if resp.Chat.PortalKey.IsEmpty() {
			return ContactCandidate{}, fmt.Errorf("%s gave no chat: %w", h.Network, ErrNotSupported)
		}
		portal := resp.Chat.Portal
		if portal == nil {
			var err error
			portal, err = h.Bridge.GetPortalByKey(logCtx, resp.Chat.PortalKey)
			if err != nil {
				return ContactCandidate{}, err
			}
		}
		if startChat {
			if err := a.ensurePortalRoom(ctx, h, login, portal, resp.Chat.PortalInfo, "resolve_identifier"); err != nil {
				return ContactCandidate{}, err
			}
		}
		if portal != nil && portal.MXID != "" {
			roomID = string(portal.MXID)
			if name == "" && portal.Name != "" {
				name = portal.Name
			}
			if name == "" {
				if room, ok, err := a.s.GetRoom(ctx, roomID); err == nil && ok && room.Name != "" {
					name = room.Name
				}
			}
		}
	}
	if roomID == "" {
		if found, ok, err := a.s.DirectRoomWith(ctx, h.Network, string(login.ID), string(userMXID)); err == nil && ok {
			roomID = found
		}
	}

	if prof, ok, err := a.s.GetProfile(ctx, string(userMXID)); err == nil && ok {
		name = cmp.Or(name, prof.DisplayName)
		avatarURI = cmp.Or(avatarURI, prof.AvatarURI)
		for _, idStr := range prof.Identifiers {
			if !slices.Contains(identifiers, idStr) {
				identifiers = append(identifiers, idStr)
			}
		}
	}

	if startChat && (name != "" || avatarURI != "" || len(identifiers) > 0) {
		_ = a.s.UpsertProfile(ctx, store.Profile{
			UserID:      string(userMXID),
			DisplayName: name,
			AvatarURI:   avatarURI,
			Identifiers: identifiers,
		})
	}
	if identifiers == nil {
		identifiers = []string{}
	}

	return ContactCandidate{
		UserID:      string(userMXID),
		Name:        name,
		AvatarPath:  a.mediaPath(avatarURI),
		Network:     h.Network,
		AccountID:   string(login.ID),
		Identifiers: identifiers,
		RoomID:      roomID,
	}, nil
}

// CreateGroup creates a new group chat on (network, accountID) via GroupCreatingNetworkAPI and returns the new room ID.
func (a *Actions) CreateGroup(ctx context.Context, network, accountID, name string, userIDs []string) (string, error) {
	h, login, err := a.loginForAccount(ctx, network, accountID)
	if err != nil {
		return "", err
	}
	api, ok := login.Client.(bridgev2.GroupCreatingNetworkAPI)
	if !ok {
		return "", fmt.Errorf("%s does not create groups: %w", h.Network, ErrNotSupported)
	}
	logCtx := h.Bridge.Log.WithContext(ctx)
	participants := make([]networkid.UserID, 0, len(userIDs))
	for _, rawUser := range userIDs {
		ghostMXID := ghostMXIDForBridge(h.Network, rawUser)
		ghostID, ok := ids.ParseGhostMXID(h.Network, ghostMXID)
		if !ok {
			ghostID = networkid.UserID(rawUser)
		}
		if _, err := h.Bridge.GetGhostByID(logCtx, ghostID); err != nil {
			return "", err
		}
		participants = append(participants, ghostID)
	}

	params := &bridgev2.GroupCreateParams{
		Type:         "group",
		Name:         &event.RoomNameEventContent{Name: name},
		Participants: participants,
	}
	resp, err := api.CreateGroup(logCtx, params)
	if err != nil {
		return "", fmt.Errorf("%w: %w", ErrNetworkRefused, err)
	}
	if resp == nil || resp.PortalKey.IsEmpty() {
		return "", fmt.Errorf("%s gave no group chat: %w", h.Network, ErrNotSupported)
	}
	portal := resp.Portal
	if portal == nil {
		portal, err = h.Bridge.GetPortalByKey(logCtx, resp.PortalKey)
		if err != nil {
			return "", err
		}
	}
	if err := a.ensurePortalRoom(ctx, h, login, portal, resp.PortalInfo, "create_group"); err != nil {
		return "", err
	}
	made, ok, err := a.s.GetRoom(ctx, string(portal.MXID))
	if err != nil {
		return "", err
	}
	if !ok {
		return "", fmt.Errorf("%w: %s made a group chat that isn't stored", ErrNetworkRefused, h.Network)
	}
	return made.ID, nil
}

// BlastMessage is a single recipient room and personalized message text for SendBlast.
type BlastMessage struct {
	RoomID string `json:"room_id"`
	Text   string `json:"text"`
}

// SendBlast sends each message's text as an independent 1:1 message to its room through the existing SendText path.
// A failure in one room does not stop the remaining rooms; each room's resulting Event is returned in order.
func (a *Actions) SendBlast(ctx context.Context, messages []BlastMessage) ([]store.Event, error) {
	if len(messages) == 0 {
		return nil, fmt.Errorf("%w: messages is empty", store.ErrBadValue)
	}
	for _, msg := range messages {
		if err := checkText(msg.Text, nil); err != nil {
			return nil, err
		}
	}
	out := make([]store.Event, 0, len(messages))
	var errs []error
	for _, msg := range messages {
		roomID := msg.RoomID
		eventID, err := a.SendText(ctx, roomID, msg.Text, "")
		if err != nil {
			out = append(out, store.Event{
				RoomID:       roomID,
				Sender:       string(ids.Me),
				Type:         event.EventMessage.Type,
				Status:       "failed",
				StatusReason: blastFailureReason(err),
				TS:           a.now(),
			})
			continue
		}
		ev, ok, getErr := a.s.GetEvent(ctx, eventID)
		if getErr != nil {
			errs = append(errs, getErr)
			continue
		}
		if ok {
			out = append(out, ev)
		}
	}
	if len(out) == 0 && len(errs) > 0 {
		return out, errors.Join(errs...)
	}
	return out, nil
}

func blastFailureReason(err error) string {
	switch {
	case errors.Is(err, ErrNotConnected), errors.Is(err, ErrNotLinked),
		errors.Is(err, engine.ErrNotRunning), errors.Is(err, engine.ErrStarting):
		return "not connected"
	case errors.Is(err, ErrNetworkRefused):
		return "network_refused"
	default:
		return "not sent"
	}
}
