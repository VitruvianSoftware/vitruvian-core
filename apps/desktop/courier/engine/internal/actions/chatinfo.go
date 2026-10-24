// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type RoomLink struct {
	EventID string `json:"event_id"`
	Sender  string `json:"sender"`
	TS      int64  `json:"ts"`
	URL     string `json:"url"`
	Host    string `json:"host"`
}

type RoomInfo struct {
	RoomID         string            `json:"room_id"`
	Name           string            `json:"name"`
	RemoteName     string            `json:"remote_name"`
	LocalName      string            `json:"local_name"`
	Topic          string            `json:"topic"`
	AvatarPath     string            `json:"avatar_path"`
	LocalAvatarURI string            `json:"local_avatar_uri"`
	Network        string            `json:"network"`
	AccountID      string            `json:"account_id"`
	IsDirect       bool              `json:"is_direct"`
	Encrypted      bool              `json:"encrypted"`
	DisappearingMs int64             `json:"disappearing_ms"`
	PinnedEventIDs []string          `json:"pinned_event_ids"`
	Members        []store.MemberHit `json:"members"`
	SharedMedia    []store.Event     `json:"shared_media"`
	SharedFiles    []store.Event     `json:"shared_files"`
	SharedLinks    []RoomLink        `json:"shared_links"`
	Features       Features          `json:"features"`
}

func (a *Actions) mediaPath(uri string) string {
	if a.m == nil || uri == "" {
		return ""
	}
	hash, ok := ids.ParseContentURI(id.ContentURIString(uri))
	if !ok {
		return ""
	}
	p, err := a.m.Path(hash)
	if err != nil {
		return ""
	}
	return p
}

func (a *Actions) RoomInfo(ctx context.Context, roomID string, refresh bool) (RoomInfo, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return RoomInfo{}, err
	}
	if !ok {
		return RoomInfo{}, store.ErrNotFound
	}
	if refresh {
		if portal, login := a.portalAndLogin(ctx, roomID); portal != nil && login != nil {
			if info, err := login.Client.GetChatInfo(ctx, portal); err == nil && info != nil {
				portal.UpdateInfo(ctx, info, login, nil, time.Time{})
				portal.UpdateBridgeInfo(ctx)
				if updated, ok, err := a.s.GetRoom(ctx, roomID); err == nil && ok {
					room = updated
				}
			}
		}
	}

	var encrypted bool
	if _, ok, err := a.s.GetState(ctx, roomID, event.StateEncryption.Type, ""); err == nil && ok {
		encrypted = true
	}

	var disappearingMs int64
	if timer, err := a.chatTimer(ctx, roomID); err == nil && timer != nil {
		disappearingMs = timer.Timer.Milliseconds()
	}

	pinnedIDs := []string{}
	if raw, ok, err := a.s.GetState(ctx, roomID, event.StatePinnedEvents.Type, ""); err == nil && ok {
		var pinned event.PinnedEventsEventContent
		if json.Unmarshal(raw, &pinned) == nil {
			for _, eid := range pinned.Pinned {
				pinnedIDs = append(pinnedIDs, string(eid))
			}
		}
	}

	members, err := a.s.RoomMembers(ctx, roomID)
	if err != nil {
		return RoomInfo{}, err
	}
	if members == nil {
		members = []store.MemberHit{}
	}
	for i := range members {
		members[i].AvatarPath = a.mediaPath(members[i].AvatarURI)
		if members[i].Identifiers == nil {
			members[i].Identifiers = []string{}
		}
	}
	sharedMedia, err := a.s.RoomSharedMedia(ctx, roomID, 50)
	if err != nil {
		return RoomInfo{}, err
	}
	sharedFiles, err := a.s.RoomSharedFiles(ctx, roomID, 50)
	if err != nil {
		return RoomInfo{}, err
	}
	rawLinks, err := a.s.RoomSharedLinks(ctx, roomID, 50)
	if err != nil {
		return RoomInfo{}, err
	}
	sharedLinks := make([]RoomLink, 0, len(rawLinks))
	for _, l := range rawLinks {
		sharedLinks = append(sharedLinks, RoomLink{
			EventID: l.EventID,
			Sender:  l.Sender,
			TS:      l.TS.UnixMilli(),
			URL:     l.URL,
			Host:    l.Host,
		})
	}
	feat, err := a.Features(ctx, roomID)
	if err != nil {
		return RoomInfo{}, err
	}

	return RoomInfo{
		RoomID:         room.ID,
		Name:           cmp.Or(room.LocalName, room.Name),
		RemoteName:     cmp.Or(room.RemoteName, room.Name),
		LocalName:      room.LocalName,
		Topic:          room.Topic,
		AvatarPath:     a.mediaPath(cmp.Or(room.LocalAvatarURI, room.AvatarURI)),
		LocalAvatarURI: room.LocalAvatarURI,
		Network:        room.Network,
		AccountID:      room.LoginID,
		IsDirect:       room.IsDirect,
		Encrypted:      encrypted,
		DisappearingMs: disappearingMs,
		PinnedEventIDs: pinnedIDs,
		Members:        members,
		SharedMedia:    sharedMedia,
		SharedFiles:    sharedFiles,
		SharedLinks:    sharedLinks,
		Features:       feat,
	}, nil
}

func (a *Actions) SetRoomLocalOverride(ctx context.Context, roomID, localName, localAvatarPath string) error {
	_, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	avatarURI := strings.TrimSpace(localAvatarPath)
	if avatarURI != "" && !strings.HasPrefix(avatarURI, "mxc://") {
		if a.m == nil {
			return fmt.Errorf("no media store to store local avatar")
		}
		data, err := os.ReadFile(avatarURI)
		if err != nil {
			return err
		}
		hash, err := a.m.Put(data)
		if err != nil {
			return err
		}
		avatarURI = string(ids.ContentURI(hash))
	}
	return a.s.SetRoomLocalOverride(ctx, roomID, strings.TrimSpace(localName), avatarURI)
}

func (a *Actions) ExportChat(ctx context.Context, roomID, destPath string) (int, error) {
	_, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return 0, err
	}
	if !ok {
		return 0, store.ErrNotFound
	}
	members, err := a.s.RoomMembers(ctx, roomID)
	if err != nil {
		return 0, err
	}
	names := make(map[string]string, len(members))
	for _, m := range members {
		if m.DisplayName != "" {
			names[m.UserID] = m.DisplayName
		}
	}

	evts, err := a.s.Events(ctx, roomID, 1_000_000)
	if err != nil {
		return 0, err
	}
	slices.Reverse(evts)

	var buf bytes.Buffer
	count := 0
	for _, e := range evts {
		if e.DeletedForMe {
			continue
		}
		if _, _, ok := store.MessageText(e.Type, e.Content); !ok {
			continue
		}
		body, err := a.s.CurrentText(ctx, e)
		if err != nil {
			return 0, err
		}
		sender := names[e.Sender]
		if sender == "" {
			if p, ok, err := a.s.GetProfile(ctx, e.Sender); err == nil && ok && p.DisplayName != "" {
				sender = p.DisplayName
				names[e.Sender] = sender
			} else {
				sender = e.Sender
			}
		}
		fmt.Fprintf(&buf, "[%s] %s: %s\n", e.TS.UTC().Format("2006-01-02 15:04:05 UTC"), sender, body)
		count++
	}
	if err := os.WriteFile(destPath, buf.Bytes(), 0o600); err != nil {
		return 0, err
	}
	return count, nil
}

func (a *Actions) ReportSpam(ctx context.Context, roomID string, leaveOrDelete bool) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	if leaveOrDelete {
		feat, err := a.Features(ctx, roomID)
		if err != nil {
			return err
		}
		if !room.IsDirect && feat.CanLeave {
			if err := a.LeaveRoom(ctx, roomID); err != nil {
				return err
			}
		} else if feat.CanDelete {
			if err := a.DeleteChat(ctx, roomID); err != nil {
				return err
			}
		}
	}
	if _, err := a.s.SetHidden(ctx, []string{roomID}, true); err != nil {
		return err
	}
	return a.s.MarkRoomSpamReported(ctx, roomID, a.now().UnixMilli())
}

// leaveOnNetwork constructs and dispatches a self-leave membership event for roomID to portal's bridge.
func (a *Actions) leaveOnNetwork(ctx context.Context, portal *bridgev2.Portal, roomID string) bridgev2.EventHandlingResult {
	meKey := string(ids.Me)
	evt := &event.Event{
		Type:      event.StateMember,
		RoomID:    id.RoomID(roomID),
		Sender:    ids.Me,
		StateKey:  &meKey,
		ID:        ids.RandomEventID(),
		Timestamp: a.now().UnixMilli(),
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipJoin)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
			},
		},
	}
	return portal.Bridge.QueueMatrixEvent(ctx, evt)
}
