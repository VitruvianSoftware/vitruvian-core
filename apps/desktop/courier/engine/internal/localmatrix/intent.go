// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Intent is the bridgev2.MatrixAPI for one Matrix identity (a ghost, the bot or the local user).
// It never talks to a server: every call reads or writes the local store.
type Intent struct {
	c            *Connector
	mxid         id.UserID
	doublePuppet bool
}

var _ bridgev2.MatrixAPI = (*Intent)(nil)

var joinedMember = json.RawMessage(`{"membership":"join"}`)

func newIntent(c *Connector, mxid id.UserID, doublePuppet bool) *Intent {
	return &Intent{c: c, mxid: mxid, doublePuppet: doublePuppet}
}

func (in *Intent) GetMXID() id.UserID   { return in.mxid }
func (in *Intent) IsDoublePuppet() bool { return in.doublePuppet }

func (in *Intent) SendMessage(ctx context.Context, roomID id.RoomID, evtType event.Type, content *event.Content, extra *bridgev2.MatrixSendExtra) (*mautrix.RespSendEvent, error) {
	evtID := ids.RandomEventID()
	ts := time.Now()
	if extra != nil {
		if !extra.Timestamp.IsZero() {
			ts = extra.Timestamp
		}
		// The deterministic ID is only for NEW events. For edits, redactions and reaction removals bridgev2 passes
		// the ORIGINAL message or reaction (MXID set) as meta; reusing its ID would make the store drop the new event.
		if evtType != event.EventRedaction {
			switch {
			case extra.MessageMeta != nil && extra.MessageMeta.MXID == "":
				m := extra.MessageMeta
				evtID = ids.EventID(roomID, m.Room, m.ID, m.PartID)
			case extra.ReactionMeta != nil && extra.ReactionMeta.MXID == "":
				r := extra.ReactionMeta
				evtID = ids.ReactionEventID(roomID, r.MessageID, r.MessagePartID, r.SenderID, r.EmojiID, r.Emoji)
			}
		}
	}
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	// A duplicate insert is not an error: the same bridge event always maps to the same event ID.
	if _, err = in.c.store.InsertEvent(ctx, store.Event{
		RoomID: string(roomID), EventID: string(evtID), Sender: string(in.mxid),
		Type: evtType.Type, Content: raw, TS: ts, Status: "sent",
	}); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: evtID}, nil
}

func (in *Intent) SendState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, content *event.Content, _ time.Time) (*mautrix.RespSendEvent, error) {
	return in.sendState(ctx, roomID, evtType, stateKey, content, false)
}

// sendState is SendState; created says the state is the initial state of a room CreateRoom has just made.
func (in *Intent) sendState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, content *event.Content, created bool) (*mautrix.RespSendEvent, error) {
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	changed, err := in.c.store.SetState(ctx, string(roomID), evtType.Type, stateKey, raw)
	if err != nil {
		return nil, err
	}
	if err = in.c.applyRoomState(ctx, roomID, evtType, stateKey, raw, created, changed); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: ids.RandomEventID()}, nil
}

// MarkRead is a read receipt bridged from the network. Only mine is kept: bridgev2 sends my reads from another
// device through my own (double-puppet) intent, and they move my read marker to the message read. Anyone else's
// receipt (a ghost's, or the bot's) says nothing about what I have read, so it is not stored in milestone 3.
// ts is when the receipt was made; the store keeps the message's own time and uses ts only for a message it
// does not have.
func (in *Intent) MarkRead(ctx context.Context, roomID id.RoomID, eventID id.EventID, ts time.Time) error {
	if in.mxid != ids.Me {
		return nil
	}
	return in.c.store.SetRead(ctx, string(roomID), string(eventID), ts)
}

// MarkUnread, TagRoom and MuteRoom are my chat list on the network: bridgev2 calls them on my own
// (double-puppet) intent, so a ghost's or the bot's say nothing about it and are dropped. With the bridge config
// host.Start sets (tag_only_on_create, mute_only_on_create, only_bridge_tags), tags and mutes come only when a
// chat first arrives, so a later change on the phone never fights one made in Courier.
func (in *Intent) MarkUnread(ctx context.Context, roomID id.RoomID, unread bool) error {
	if in.mxid != ids.Me {
		return nil
	}
	_, err := in.c.store.SetMarkedUnread(ctx, []string{string(roomID)}, unread)
	return err
}

// TagRoom takes in a network's tag: m.favourite is a pin, m.lowpriority the network's archive. The store ignores
// every other tag.
func (in *Intent) TagRoom(ctx context.Context, roomID id.RoomID, tag event.RoomTag, isTagged bool) error {
	if in.mxid != ids.Me {
		return nil
	}
	return in.c.store.ApplyNetworkTag(ctx, string(roomID), string(tag), isTagged)
}

// MuteRoom takes in a network's mute: muted while until is in the future.
func (in *Intent) MuteRoom(ctx context.Context, roomID id.RoomID, until time.Time) error {
	if in.mxid != ids.Me {
		return nil
	}
	return in.c.store.ApplyNetworkMute(ctx, string(roomID), until)
}

// MarkTyping is a contact typing, for timeout from now; a timeout of 0 is them stopping. Only a ghost (someone on
// the network) counts: my own typing on another device, or the bot's, is nobody typing to me.
func (in *Intent) MarkTyping(_ context.Context, roomID id.RoomID, _ bridgev2.TypingType, timeout time.Duration) error {
	if _, isGhost := ids.ParseGhostMXID(in.c.network, in.mxid); !isGhost {
		return nil
	}
	var until time.Time // zero: stopped
	if timeout > 0 {
		until = time.Now().Add(timeout)
	}
	in.c.store.SetTyping(string(roomID), string(in.mxid), until)
	return nil
}

func (in *Intent) DownloadMedia(_ context.Context, uri id.ContentURIString, _ *event.EncryptedFileInfo) ([]byte, error) {
	hash, ok := ids.ParseContentURI(uri)
	if !ok {
		return nil, fmt.Errorf("not a courier media URI: %s", uri)
	}
	return in.c.media.Read(hash)
}

func (in *Intent) DownloadMediaToFile(ctx context.Context, uri id.ContentURIString, file *event.EncryptedFileInfo, _ bool, cb func(*os.File) error) error {
	data, err := in.DownloadMedia(ctx, uri, file)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp("", "courier-dl-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	if _, err = tmp.Write(data); err != nil {
		return err
	}
	if _, err = tmp.Seek(0, io.SeekStart); err != nil {
		return err
	}
	if err = cb(tmp); err != nil {
		return bridgev2.CallbackError{Type: "read", Wrapped: err}
	}
	return nil
}

// UploadMedia stores the bytes under their content hash. Nothing is encrypted locally, so file info is always nil.
func (in *Intent) UploadMedia(_ context.Context, _ id.RoomID, data []byte, _, _ string) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	hash, err := in.c.media.Put(data)
	if err != nil {
		return "", nil, err
	}
	return ids.ContentURI(hash), nil, nil
}

// UploadMediaStream always gives the callback a real *os.File, which satisfies requireFile: bridges may seek,
// rewrite at offsets or hand the path to ffmpeg. The file is hashed and stored once the callback returns.
func (in *Intent) UploadMediaStream(_ context.Context, _ id.RoomID, _ int64, _ bool, cb bridgev2.FileStreamCallback) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	if err := os.MkdirAll(in.c.media.Dir, 0o700); err != nil {
		return "", nil, err
	}
	tmp, err := os.CreateTemp(in.c.media.Dir, ".stream-*")
	if err != nil {
		return "", nil, err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	res, err := cb(tmp)
	if err != nil {
		return "", nil, bridgev2.CallbackError{Type: "write", Wrapped: err}
	}
	src := tmp
	if res != nil && res.ReplacementFile != "" {
		// The bridge hands the replacement file over to us (the Matrix connector deletes it too).
		defer os.Remove(res.ReplacementFile)
		if src, err = os.Open(res.ReplacementFile); err != nil {
			return "", nil, fmt.Errorf("failed to open replacement file: %w", err)
		}
		defer src.Close()
	} else if _, err = src.Seek(0, io.SeekStart); err != nil {
		return "", nil, err
	}
	hash, err := in.c.media.PutStream(func(w io.Writer) error { _, err := io.Copy(w, src); return err })
	if err != nil {
		return "", nil, err
	}
	return ids.ContentURI(hash), nil, nil
}

// bridgev2 sets ghost profiles globally, not per room, so name and avatar go to the profiles table.
func (in *Intent) SetDisplayName(ctx context.Context, name string) error {
	return in.c.store.SetProfile(ctx, string(in.mxid), &name, nil)
}

func (in *Intent) SetAvatarURL(ctx context.Context, avatarURL id.ContentURIString) error {
	avatar := string(avatarURL)
	return in.c.store.SetProfile(ctx, string(in.mxid), nil, &avatar)
}

// SetExtraProfileMeta and SetProfile carry bridge bookkeeping (remote ID, identifiers, bot flags) that the
// app has no use for; the connector reports ExtraProfileMeta=false so bridgev2 rarely sends them. If the data
// does carry a display name or avatar, those are stored; everything else is dropped.
func (in *Intent) SetExtraProfileMeta(ctx context.Context, data any) error {
	return in.storeProfileFields(ctx, data)
}

func (in *Intent) SetProfile(ctx context.Context, data any) error {
	return in.storeProfileFields(ctx, data)
}

func (in *Intent) storeProfileFields(ctx context.Context, data any) error {
	raw, err := json.Marshal(data)
	if err != nil {
		return err
	}
	var fields struct {
		DisplayName *string `json:"displayname"`
		AvatarURL   *string `json:"avatar_url"`
	}
	if err = json.Unmarshal(raw, &fields); err != nil || (fields.DisplayName == nil && fields.AvatarURL == nil) {
		return nil // not a profile-shaped value, or nothing we store
	}
	return in.c.store.SetProfile(ctx, string(in.mxid), fields.DisplayName, fields.AvatarURL)
}

func (in *Intent) CreateRoom(ctx context.Context, req *mautrix.ReqCreateRoom) (id.RoomID, error) {
	roomID := req.BeeperLocalRoomID
	if roomID == "" {
		roomID = id.RoomID("!" + string(ids.RandomEventID())[1:] + ":" + ids.ServerName)
	}
	room := store.Room{ID: string(roomID), Network: in.c.network, Name: req.Name, Topic: req.Topic, IsDirect: req.IsDirect}
	// Re-creating a room that already exists must not lose its avatar or creation time.
	old, existed, err := in.c.store.GetRoom(ctx, room.ID)
	if err != nil {
		return "", err
	} else if existed {
		room.AvatarURI, room.CreatedAt = old.AvatarURI, old.CreatedAt
	}
	if err := in.c.store.UpsertRoom(ctx, room); err != nil {
		return "", err
	}
	// Members first, so an initial m.room.member state event with a profile replaces the bare join row.
	for _, u := range append([]id.UserID{in.mxid}, req.Invite...) {
		if err := in.c.store.SetMember(ctx, room.ID, string(u), joinedMember); err != nil {
			return "", err
		}
	}
	if req.PowerLevelOverride != nil {
		if _, err := in.sendState(ctx, roomID, event.StatePowerLevels, "", &event.Content{Parsed: req.PowerLevelOverride}, !existed); err != nil {
			return "", err
		}
	}
	for _, st := range req.InitialState {
		sk := ""
		if st.StateKey != nil {
			sk = *st.StateKey
		}
		if _, err := in.sendState(ctx, roomID, st.Type, sk, &st.Content, !existed); err != nil {
			return "", err
		}
	}
	return roomID, nil
}

// DeleteRoom with puppetsOnly=true removes just the ghosts. bridgev2 does that when portals merge or move, and
// there is no server copy of the history, so the room, its events and its state must stay.
func (in *Intent) DeleteRoom(ctx context.Context, roomID id.RoomID, puppetsOnly bool) error {
	if !puppetsOnly {
		return in.c.store.DeleteRoom(ctx, string(roomID))
	}
	members, err := in.c.store.Members(ctx, string(roomID))
	if err != nil {
		return err
	}
	for userID := range members {
		if _, isGhost := ids.ParseGhostMXID(in.c.network, id.UserID(userID)); !isGhost {
			continue
		}
		if err = in.c.store.DeleteMember(ctx, string(roomID), userID); err != nil {
			return err
		}
	}
	return nil
}

func (in *Intent) EnsureJoined(ctx context.Context, roomID id.RoomID, _ ...bridgev2.EnsureJoinedParams) error {
	return in.c.store.SetMember(ctx, string(roomID), string(in.mxid), joinedMember)
}

// EnsureInvited joins the user straight away: there is no one to accept an invite locally.
func (in *Intent) EnsureInvited(ctx context.Context, roomID id.RoomID, userID id.UserID) error {
	return in.c.store.SetMember(ctx, string(roomID), string(userID), joinedMember)
}

func (in *Intent) GetEvent(ctx context.Context, roomID id.RoomID, eventID id.EventID) (*event.Event, error) {
	e, ok, err := in.c.store.GetEvent(ctx, string(eventID))
	if err != nil {
		return nil, err
	}
	if !ok || e.RoomID != string(roomID) {
		return nil, mautrix.MNotFound
	}
	class := event.MessageEventType
	if e.StateKey != nil {
		class = event.StateEventType
	}
	evt := &event.Event{
		ID: eventID, RoomID: roomID, Sender: id.UserID(e.Sender), Type: event.Type{Type: e.Type, Class: class},
		Timestamp: e.TS.UnixMilli(), StateKey: e.StateKey,
	}
	if err = json.Unmarshal(e.Content, &evt.Content); err != nil {
		return nil, err
	}
	// Event types the SDK has no struct for stay available as raw content.
	if err = evt.Content.ParseRaw(evt.Type); err != nil && !errors.Is(err, event.ErrUnsupportedContentType) {
		return nil, err
	}
	return evt, nil
}
