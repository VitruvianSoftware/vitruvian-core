// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// Protocol 5's presence: who has read my messages (Event.read_by, Event.delivered), my typing (room.setTyping), Mark
// as Unread from a message (room.setUnreadFrom) and Reply Privately's chat (room.directChat). Each handler has the
// shape of the others: strict params, the required ones checked by name, then one actions call whose sentinel errors
// map to their codes. Nothing here logs who: user IDs and names only ever go to the app.

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// myUserID is my Matrix ID as the store keeps senders, for code where the ids package name is taken.
var myUserID = string(ids.Me)

// reasonNoAccount is a waiting message's status_reason when none of my accounts is in its chat any more: it can't go
// until one is.
const reasonNoAccount = "no account"

// personName is userID as the app names people in a chat (typing, read_by): their name in the chat (member, their
// member content there; nil when the chat doesn't list them), else their profile's, else their ID's localpart.
// profiles caches profile names across a page.
func (d *Deps) personName(ctx context.Context, userID string, member json.RawMessage, profiles map[string]string) (string, error) {
	var m struct {
		DisplayName string `json:"displayname"`
	}
	_ = json.Unmarshal(member, &m) // not a member, or content that can't be read: no name from it
	if m.DisplayName != "" {
		return m.DisplayName, nil
	}
	name, ok := profiles[userID]
	if !ok {
		prof, _, err := d.Store.GetProfile(ctx, userID)
		if err != nil {
			return "", err
		}
		name = prof.DisplayName
		profiles[userID] = name
	}
	if name == "" {
		name = localpart(userID)
	}
	return name, nil
}

// readerNames is the name of each reader on a page, by user ID.
type readerNames map[string]string

// of is readers on the wire, in their order (newest receipt first), at most store.MaxReaders.
func (n readerNames) of(readers []store.Reader) []readerJSON {
	out := make([]readerJSON, 0, min(len(readers), store.MaxReaders))
	for _, r := range readers {
		if len(out) == store.MaxReaders {
			break
		}
		out = append(out, readerJSON{UserID: r.UserID, Name: n[r.UserID], TS: ms(r.TS)})
	}
	return out
}

// readersOf names everyone who has read a message of a page's (receipts, store.ReceiptsFor's answer for it), with one
// read of the chat's members and one of each reader's profile at most. A reader the chat lists is named as typing
// names them (personName); one it doesn't (its members can arrive later than a receipt, and a receipt is outside
// data) by their ID's localpart, never a name taken from elsewhere (Global Constraints).
func (d *Deps) readersOf(ctx context.Context, roomID string, receipts map[string]store.Receipts) (readerNames, error) {
	names := readerNames{}
	for _, r := range receipts {
		for _, reader := range r.ReadBy {
			names[reader.UserID] = ""
		}
	}
	if len(names) == 0 {
		return names, nil
	}
	members, err := d.Store.Members(ctx, roomID)
	if err != nil {
		return nil, err
	}
	profiles := map[string]string{}
	for userID := range names {
		member, listed := members[userID]
		if !listed {
			names[userID] = localpart(userID)
			continue
		}
		if names[userID], err = d.personName(ctx, userID, member, profiles); err != nil {
			return nil, err
		}
	}
	return names, nil
}

// noAccountReason is the status_reason of a waiting message in roomID: reasonNoAccount when none of my accounts is
// in the chat any more, so it can't go until one is (the carry from Task 5: a shared chat whose only account of mine
// was signed out would otherwise wait with nothing said); "" while it is just waiting. Which account a chat goes
// through is the actions' one rule (Actions.HasAccountFor, loginOf's), never worked out again here. It is asked as
// the page is read, so it clears by itself once an account is in the chat again; a network that isn't running can't
// say, and its messages are just waiting.
func (d *Deps) noAccountReason(ctx context.Context, roomID string) (string, error) {
	if d.Actions == nil {
		return "", nil
	}
	has, err := d.Actions.HasAccountFor(ctx, roomID)
	if errors.Is(err, store.ErrNotFound) {
		return "", nil // deleted since its page was read: nothing to say of it, and the page still answers
	}
	if err != nil || has {
		return "", err
	}
	return reasonNoAccount, nil
}

// roomSetTyping tells the chat's network I am typing, or stopped. It answers at once and is best effort: a chat whose
// network isn't connected (not running, starting, or the chat's account down) is told nothing and that is no error,
// so unlike the actions that go out through the network it doesn't check that the network runs (Ruling C6). Only an
// unknown chat is refused.
func roomSetTyping(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Typing *bool   `json:"typing"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := requiredBool("typing", p.Typing); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetTyping(ctx, *p.RoomID, *p.Typing) // an unknown chat is store.ErrNotFound
}

// roomSetUnreadFrom marks a chat unread from a message on. It names only the message, and the chat is the message's
// (Ruling C18). A note is not supported (Ruling P2), and the mark stays on this Mac.
func roomSetUnreadFrom(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID *string `json:"event_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	_, err := d.Actions.SetUnreadFromEvent(ctx, *p.EventID)
	return nil, err
}

// roomResult is a RoomResult: the chat a method found or made.
type roomResult struct {
	RoomID string `json:"room_id"`
}

// roomDirectChat is Reply Privately's chat (when room_id is given) or starting/reusing a 1:1 DM with a person on
// (network, account_id).
func roomDirectChat(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID    *string `json:"room_id"`
		Network   *string `json:"network"`
		AccountID *string `json:"account_id"`
		UserID    *string `json:"user_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.RoomID != nil {
		if err := required("room_id", p.RoomID); err != nil {
			return nil, err
		}
	} else if p.Network == nil {
		return nil, invalidParams("room_id is required")
	} else if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("user_id", p.UserID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	viaRoomID := ""
	if p.RoomID != nil {
		viaRoomID = *p.RoomID
	}
	network := ""
	if p.Network != nil {
		network = *p.Network
	}
	accountID := ""
	if p.AccountID != nil {
		accountID = *p.AccountID
	}
	roomID, err := d.Actions.DirectChatWithAccount(ctx, viaRoomID, network, accountID, *p.UserID)
	if err != nil {
		return nil, err
	}
	return roomResult{RoomID: roomID}, nil
}

type roomInfoResult struct {
	RoomID         string             `json:"room_id"`
	Name           string             `json:"name"`
	RemoteName     string             `json:"remote_name"`
	LocalName      string             `json:"local_name"`
	Topic          string             `json:"topic"`
	AvatarPath     string             `json:"avatar_path"`
	LocalAvatarURI string             `json:"local_avatar_uri"`
	Network        string             `json:"network"`
	AccountID      string             `json:"account_id"`
	IsDirect       bool               `json:"is_direct"`
	Encrypted      bool               `json:"encrypted"`
	DisappearingMS int64              `json:"disappearing_ms"`
	PinnedEventIDs []string           `json:"pinned_event_ids"`
	Members        []store.MemberHit  `json:"members"`
	SharedMedia    []eventJSON        `json:"shared_media"`
	SharedFiles    []eventJSON        `json:"shared_files"`
	SharedLinks    []actions.RoomLink `json:"shared_links"`
	Features       chatFeatures       `json:"features"`
}

func roomInfo(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		Refresh bool    `json:"refresh"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	info, err := d.Actions.RoomInfo(ctx, *p.RoomID, p.Refresh)
	if err != nil {
		return nil, err
	}
	senders := map[string]sender{}
	mediaEvs, err := d.toEvents(ctx, *p.RoomID, info.SharedMedia, senders)
	if err != nil {
		return nil, err
	}
	fileEvs, err := d.toEvents(ctx, *p.RoomID, info.SharedFiles, senders)
	if err != nil {
		return nil, err
	}
	feat, err := d.toChatFeatures(ctx, *p.RoomID, info.Features)
	if err != nil {
		return nil, err
	}
	for i := range info.Members {
		if info.Members[i].AvatarPath == "" && info.Members[i].AvatarURI != "" {
			info.Members[i].AvatarPath = d.path(info.Members[i].AvatarURI)
		}
		if info.Members[i].Identifiers == nil {
			info.Members[i].Identifiers = []string{}
		}
	}
	if info.PinnedEventIDs == nil {
		info.PinnedEventIDs = []string{}
	}
	if info.SharedLinks == nil {
		info.SharedLinks = []actions.RoomLink{}
	}
	return roomInfoResult{
		RoomID:         info.RoomID,
		Name:           info.Name,
		RemoteName:     info.RemoteName,
		LocalName:      info.LocalName,
		Topic:          info.Topic,
		AvatarPath:     info.AvatarPath,
		LocalAvatarURI: info.LocalAvatarURI,
		Network:        info.Network,
		AccountID:      info.AccountID,
		IsDirect:       info.IsDirect,
		Encrypted:      info.Encrypted,
		DisappearingMS: info.DisappearingMs,
		PinnedEventIDs: info.PinnedEventIDs,
		Members:        info.Members,
		SharedMedia:    mediaEvs,
		SharedFiles:    fileEvs,
		SharedLinks:    info.SharedLinks,
		Features:       feat,
	}, nil
}

func roomSetLocalOverride(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID          *string `json:"room_id"`
		LocalName       *string `json:"local_name"`
		LocalAvatarPath *string `json:"local_avatar_path"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.LocalName == nil {
		return nil, invalidParams("local_name is required")
	}
	if p.LocalAvatarPath == nil {
		return nil, invalidParams("local_avatar_path is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetRoomLocalOverride(ctx, *p.RoomID, *p.LocalName, *p.LocalAvatarPath)
}

func validateExportPath(p string) error {
	p = strings.TrimSpace(p)
	if p == "" || !filepath.IsAbs(p) || filepath.Clean(p) != p {
		return invalidParams("path must be a regular file")
	}
	if fi, err := os.Lstat(p); err == nil {
		if !fi.Mode().IsRegular() {
			return invalidParams("path must be a regular file")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return invalidParams("path must be a regular file")
	}
	dir := filepath.Dir(p)
	dfi, err := os.Lstat(dir)
	if err != nil || dfi.Mode()&os.ModeSymlink != 0 || !dfi.IsDir() {
		return invalidParams("path must be a regular file")
	}
	for cur := dir; filepath.Dir(cur) != "/" && cur != "/"; cur = filepath.Dir(cur) {
		cfi, err := os.Lstat(cur)
		if err != nil || cfi.Mode()&os.ModeSymlink != 0 {
			return invalidParams("path must be a regular file")
		}
	}
	return nil
}

func roomExport(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Path   *string `json:"path"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := required("path", p.Path); err != nil {
		return nil, err
	}
	if err := validateExportPath(*p.Path); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	n, err := d.Actions.ExportChat(ctx, *p.RoomID, *p.Path)
	if err != nil {
		return nil, err
	}
	return map[string]int{"messages_written": n}, nil
}

func roomReportSpam(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID        *string `json:"room_id"`
		LeaveOrDelete bool    `json:"leave_or_delete"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.ReportSpam(ctx, *p.RoomID, p.LeaveOrDelete)
}

func roomSetName(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Text   *string `json:"text"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Text == nil {
		return nil, invalidParams("text is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetRoomName(ctx, *p.RoomID, *p.Text)
}

func roomSetTopic(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Text   *string `json:"text"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Text == nil {
		return nil, invalidParams("text is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetRoomTopic(ctx, *p.RoomID, *p.Text)
}

func roomSetAvatar(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Path   *string `json:"path"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Path == nil {
		return nil, invalidParams("path is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetRoomAvatar(ctx, *p.RoomID, *p.Path)
}

func roomInvite(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string   `json:"room_id"`
		UserIDs *[]string `json:"user_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.UserIDs == nil {
		return nil, invalidParams("user_ids is required")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.InviteMembers(ctx, *p.RoomID, *p.UserIDs)
}

func roomKick(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		UserID *string `json:"user_id"`
		Reason *string `json:"reason"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := required("user_id", p.UserID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	reason := ""
	if p.Reason != nil {
		reason = *p.Reason
	}
	return nil, d.Actions.KickMember(ctx, *p.RoomID, *p.UserID, reason)
}

func roomSetAdmin(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		UserID  *string `json:"user_id"`
		IsAdmin *bool   `json:"is_admin"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := required("user_id", p.UserID); err != nil {
		return nil, err
	}
	if err := requiredBool("is_admin", p.IsAdmin); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetMemberAdmin(ctx, *p.RoomID, *p.UserID, *p.IsAdmin)
}

func roomLeave(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.LeaveRoom(ctx, *p.RoomID)
}

func roomDelete(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.DeleteChat(ctx, *p.RoomID)
}
