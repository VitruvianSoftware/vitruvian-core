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
		switch {
		case extra.MessageMeta != nil:
			m := extra.MessageMeta
			evtID = ids.EventID(roomID, m.Room, m.ID, m.PartID)
		case extra.ReactionMeta != nil:
			r := extra.ReactionMeta
			evtID = ids.ReactionEventID(roomID, r.MessageID, r.MessagePartID, r.SenderID, r.EmojiID)
		}
	}
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	// A duplicate insert is not an error: the same bridge event always maps to the same event ID.
	if _, err = in.c.store.InsertEvent(ctx, store.Event{RoomID: string(roomID), EventID: string(evtID), Sender: string(in.mxid),
		Type: evtType.Type, Content: raw, TS: ts, Status: "sent"}); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: evtID}, nil
}

func (in *Intent) SendState(ctx context.Context, roomID id.RoomID, evtType event.Type, stateKey string, content *event.Content, _ time.Time) (*mautrix.RespSendEvent, error) {
	raw, err := json.Marshal(content)
	if err != nil {
		return nil, err
	}
	if err = in.c.store.SetState(ctx, string(roomID), evtType.Type, stateKey, raw); err != nil {
		return nil, err
	}
	if err = in.c.applyRoomState(ctx, roomID, evtType, stateKey, raw); err != nil {
		return nil, err
	}
	return &mautrix.RespSendEvent{EventID: ids.RandomEventID()}, nil
}

func (in *Intent) MarkRead(ctx context.Context, roomID id.RoomID, eventID id.EventID, ts time.Time) error {
	return in.c.store.SetRead(ctx, string(roomID), string(eventID), ts)
}

// Unread flags, typing, tags and mutes are user-interface state owned by the app in milestone 3; the engine accepts them.
func (in *Intent) MarkUnread(context.Context, id.RoomID, bool) error { return nil }
func (in *Intent) MarkTyping(context.Context, id.RoomID, bridgev2.TypingType, time.Duration) error {
	return nil
}
func (in *Intent) TagRoom(context.Context, id.RoomID, event.RoomTag, bool) error { return nil }
func (in *Intent) MuteRoom(context.Context, id.RoomID, time.Time) error          { return nil }

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

func (in *Intent) UploadMediaStream(_ context.Context, _ id.RoomID, _ int64, _ bool, cb bridgev2.FileStreamCallback) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	var res *bridgev2.FileStreamResult
	hash, err := in.c.media.PutStream(func(w io.Writer) error {
		var cbErr error
		if res, cbErr = cb(w); cbErr != nil {
			return bridgev2.CallbackError{Type: "write", Wrapped: cbErr}
		}
		return nil
	})
	if err != nil {
		return "", nil, err
	}
	if res != nil && res.ReplacementFile != "" {
		// The bridge hands the replacement file over to us (the Matrix connector deletes it too).
		// The first blob stays on disk, unreferenced: other events may already point at it.
		defer os.Remove(res.ReplacementFile)
		f, err := os.Open(res.ReplacementFile)
		if err != nil {
			return "", nil, fmt.Errorf("failed to open replacement file: %w", err)
		}
		defer f.Close()
		if hash, err = in.c.media.PutStream(func(w io.Writer) error { _, err := io.Copy(w, f); return err }); err != nil {
			return "", nil, err
		}
	}
	return ids.ContentURI(hash), nil, nil
}

// Profiles live on member events, written through SendState; the store needs no separate profile table.
func (in *Intent) SetDisplayName(context.Context, string) error            { return nil }
func (in *Intent) SetAvatarURL(context.Context, id.ContentURIString) error { return nil }
func (in *Intent) SetExtraProfileMeta(context.Context, any) error          { return nil }
func (in *Intent) SetProfile(context.Context, any) error                   { return nil }

func (in *Intent) CreateRoom(ctx context.Context, req *mautrix.ReqCreateRoom) (id.RoomID, error) {
	roomID := req.BeeperLocalRoomID
	if roomID == "" {
		roomID = id.RoomID("!" + string(ids.RandomEventID())[1:] + ":" + ids.ServerName)
	}
	room := store.Room{ID: string(roomID), Network: in.c.network, Name: req.Name, Topic: req.Topic, IsDirect: req.IsDirect}
	// Re-creating a room that already exists must not lose its avatar or creation time.
	if old, ok, err := in.c.store.GetRoom(ctx, room.ID); err != nil {
		return "", err
	} else if ok {
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
	for _, st := range req.InitialState {
		sk := ""
		if st.StateKey != nil {
			sk = *st.StateKey
		}
		if _, err := in.SendState(ctx, roomID, st.Type, sk, &st.Content, time.Now()); err != nil {
			return "", err
		}
	}
	return roomID, nil
}

func (in *Intent) DeleteRoom(ctx context.Context, roomID id.RoomID, _ bool) error {
	return in.c.store.DeleteRoom(ctx, string(roomID))
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
	evt := &event.Event{ID: eventID, RoomID: roomID, Sender: id.UserID(e.Sender), Type: event.Type{Type: e.Type, Class: class},
		Timestamp: e.TS.UnixMilli(), StateKey: e.StateKey}
	if err = json.Unmarshal(e.Content, &evt.Content); err != nil {
		return nil, err
	}
	// Event types the SDK has no struct for stay available as raw content.
	if err = evt.Content.ParseRaw(evt.Type); err != nil && !errors.Is(err, event.ErrUnsupportedContentType) {
		return nil, err
	}
	return evt, nil
}
