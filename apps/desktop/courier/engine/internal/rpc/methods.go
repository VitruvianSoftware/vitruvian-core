// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// The error codes protocol.json defines.
const (
	CodeParseError       = -32700
	CodeInvalidRequest   = -32600
	CodeMethodNotFound   = -32601
	CodeInvalidParams    = -32602
	CodeInternal         = -32603
	CodeProtocolMismatch = -32001
	CodeHelloRequired    = -32002
	CodeNotLinked        = -32010
	CodeBridgeCommand    = -32011
	CodeTooLarge         = -32012
	CodeAlreadyLinked    = -32013
	CodeBadValue         = -32014
	CodeUnknownLogin     = -32015
	CodeNotRunning       = -32016
	CodeLoginInProgress  = -32017
	CodeNotConnected     = -32018
	CodeNotFailed        = -32019
	CodeNotFound         = -32020
)

// errorMessages is each code's fixed message, as protocol.json has it. A message never carries a value that was
// sent, because what was sent can be a password, a token or a cookie.
var errorMessages = map[int]string{
	CodeParseError:       "parse error",
	CodeInvalidRequest:   "invalid request",
	CodeMethodNotFound:   "method not found",
	CodeInvalidParams:    "invalid params",
	CodeInternal:         "internal error",
	CodeProtocolMismatch: "protocol mismatch",
	CodeHelloRequired:    "hello first",
	CodeNotLinked:        "this network isn't linked",
	CodeBridgeCommand:    "the bridge would run this as a command",
	CodeTooLarge:         "the file is too large to send (the limit is 90 MB)",
	CodeAlreadyLinked:    "this network is already linked",
	CodeBadValue:         "that isn't accepted",
	CodeUnknownLogin:     "no sign-in in progress with that ID",
	CodeNotRunning:       "this network isn't running",
	CodeLoginInProgress:  "a sign-in is already in progress for this network",
	CodeNotConnected:     "the network isn't connected yet",
	CodeNotFailed:        "only a failed message can be retried or discarded",
	CodeNotFound:         "no such chat or message",
}

// Error is a JSON-RPC error as it goes on the wire.
type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *Error) Error() string { return e.Message }

func newError(code int) *Error { return &Error{Code: code, Message: errorMessages[code]} }

// invalidParams is -32602 with a reason that names the parameter. The reason is always written here, never
// built from what was sent.
func invalidParams(reason string) *Error {
	e := newError(CodeInvalidParams)
	e.Data = map[string]string{"reason": reason}
	return e
}

var errNotFound = newError(CodeNotFound)

// sentinels maps the engine's errors to their codes. Only the code's fixed message goes out: the error's own text
// can quote a network name, a flow, a path or a field that was sent.
var sentinels = []struct {
	err  error
	code int
}{
	{actions.ErrNotLinked, CodeNotLinked},
	{actions.ErrBridgeCommand, CodeBridgeCommand},
	{actions.ErrTooLarge, CodeTooLarge},
	{actions.ErrNotConnected, CodeNotConnected},
	{actions.ErrNotFailed, CodeNotFailed},
	{login.ErrAlreadyLinked, CodeAlreadyLinked},
	{login.ErrBadValue, CodeBadValue},
	{login.ErrUnknownLogin, CodeUnknownLogin},
	{login.ErrNotRunning, CodeNotRunning},
	{login.ErrLoginInProgress, CodeLoginInProgress},
}

// toError turns any error into the one that goes on the wire. Anything unknown is an internal error, with no detail.
func toError(err error) *Error {
	e, _ := classify(err)
	return e
}

// classify is toError, and says whether err was unknown: one with no code of its own, sent as a bare internal error.
func classify(err error) (*Error, bool) {
	var e *Error
	if errors.As(err, &e) {
		return e, false
	}
	if errors.Is(err, actions.ErrEmpty) {
		return invalidParams("there is nothing to send"), false
	}
	for _, s := range sentinels {
		if errors.Is(err, s.err) {
			return newError(s.code), false
		}
	}
	return newError(CodeInternal), true
}

type handler func(ctx context.Context, d *Deps, params json.RawMessage) (any, error)

// methods is every method but hello, which the connection answers itself.
var methods = map[string]handler{
	"accounts.list":    accountsList,
	"inbox.list":       inboxList,
	"room.events":      roomEvents,
	"room.markRead":    roomMarkRead,
	"room.setMuted":    roomSetMuted,
	"message.send":     messageSend,
	"message.sendFile": messageSendFile,
	"message.react":    messageReact,
	"message.retry":    messageRetry,
	"message.discard":  messageDiscard,
	"login.start":      loginStart,
	"login.submit":     loginSubmit,
	"login.wait":       loginWait,
	"login.cancel":     loginCancel,
}

var errMissing = errors.New("a dependency this method needs is missing")

func required(name string, v *string) error {
	if v == nil || *v == "" {
		return invalidParams(name + " is required")
	}
	return nil
}

func ms(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixMilli()
}

// path is where a content URI's file is, when the engine has it, or "".
func (d *Deps) path(uri string) string {
	if d.Media == nil || uri == "" {
		return ""
	}
	hash, ok := ids.ParseContentURI(id.ContentURIString(uri))
	if !ok {
		return ""
	}
	p, err := d.Media.Path(hash)
	if err != nil {
		return ""
	}
	if p, err = filepath.Abs(p); err != nil {
		return ""
	}
	if fi, err := os.Stat(p); err != nil || !fi.Mode().IsRegular() {
		return ""
	}
	return p
}

// running reports whether a network's bridge is running.
func (d *Deps) running(network string) bool {
	if d.Engine == nil {
		return false
	}
	_, ok := d.Engine.Host(network)
	return ok
}

// room loads a chat the request names, or not_found.
func (d *Deps) room(ctx context.Context, roomID string) (store.Room, error) {
	r, ok, err := d.Store.GetRoom(ctx, roomID)
	if err != nil {
		return store.Room{}, err
	}
	if !ok {
		return store.Room{}, errNotFound
	}
	return r, nil
}

// sendableRoom is room, for an action that goes out through the chat's network: that network must be running.
func (d *Deps) sendableRoom(ctx context.Context, roomID string) (store.Room, error) {
	r, err := d.room(ctx, roomID)
	if err != nil {
		return r, err
	}
	if d.Actions == nil {
		return r, errMissing
	}
	if !d.running(r.Network) {
		return r, newError(CodeNotRunning)
	}
	return r, nil
}

// eventIn checks that an event the request names is in roomID.
func (d *Deps) eventIn(ctx context.Context, roomID, eventID string) error {
	e, ok, err := d.Store.GetEvent(ctx, eventID)
	if err != nil {
		return err
	}
	if !ok || e.RoomID != roomID {
		return errNotFound
	}
	return nil
}

type account struct {
	Network     string   `json:"network"`
	DisplayName string   `json:"display_name"`
	Flows       []string `json:"flows"`
	State       string   `json:"state"`
	Error       string   `json:"error"`
	RemoteName  string   `json:"remote_name"`
	NotStarted  string   `json:"not_started"`
}

func accountsList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	out := make([]account, 0, len(d.Networks))
	for _, n := range d.Networks {
		a := account{Network: n.Name, DisplayName: n.DisplayName, Flows: append([]string{}, n.Flows...)}
		reason, notStarted := d.NotStarted[n.Name]
		switch {
		case notStarted || !d.running(n.Name):
			a.State, a.NotStarted = "NOT_STARTED", reason
			if a.NotStarted == "" {
				a.NotStarted = errorMessages[CodeNotRunning]
			}
		default:
			raw, ok, err := d.Store.BridgeState(ctx, n.Name)
			if err != nil {
				return nil, err
			}
			var st struct {
				StateEvent string `json:"state_event"`
				Error      string `json:"error"`
				Message    string `json:"message"`
				RemoteName string `json:"remote_name"`
			}
			if ok {
				_ = json.Unmarshal(raw, &st) // state that can't be read is no state
			}
			a.State, a.Error, a.RemoteName = st.StateEvent, st.Message, st.RemoteName
			if a.Error == "" {
				a.Error = st.Error
			}
			if a.State == "" {
				a.State = "UNCONFIGURED"
			}
		}
		out = append(out, a)
	}
	return map[string]any{"accounts": out}, nil
}

type inboxRow struct {
	RoomID      string `json:"room_id"`
	Network     string `json:"network"`
	Name        string `json:"name"`
	AvatarPath  string `json:"avatar_path"`
	IsDirect    bool   `json:"is_direct"`
	LastTS      int64  `json:"last_ts"`
	Preview     string `json:"preview"`
	PreviewKind string `json:"preview_kind"`
	PreviewMine bool   `json:"preview_mine"`
	Unread      int    `json:"unread"`
	Muted       bool   `json:"muted"`
}

func inboxList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	rows, err := d.Store.Inbox(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]inboxRow, 0, len(rows))
	for _, r := range rows {
		out = append(out, inboxRow{
			RoomID: r.ID, Network: r.Network, Name: r.Name, AvatarPath: d.path(r.AvatarURI), IsDirect: r.IsDirect,
			LastTS: ms(r.LastTS), Preview: r.Preview, PreviewKind: r.PreviewKind, PreviewMine: r.PreviewMine,
			Unread: r.Unread, Muted: r.Muted,
		})
	}
	return map[string]any{"rooms": out}, nil
}

type cursor struct {
	TS  *int64 `json:"ts"`
	Seq *int64 `json:"seq"`
}

type eventJSON struct {
	EventID          string          `json:"event_id"`
	RoomID           string          `json:"room_id"`
	Sender           string          `json:"sender"`
	SenderName       string          `json:"sender_name"`
	SenderAvatarPath string          `json:"sender_avatar_path"`
	Mine             bool            `json:"mine"`
	Type             string          `json:"type"`
	Content          json.RawMessage `json:"content"`
	TS               int64           `json:"ts"`
	Seq              int64           `json:"seq"`
	Status           string          `json:"status"`
	StatusReason     string          `json:"status_reason"`
	MediaPath        string          `json:"media_path"`
}

type sender struct{ name, avatarPath string }

// localpart is the part of a Matrix ID before the server name, without the @.
func localpart(userID string) string {
	if local, _, err := id.UserID(userID).Parse(); err == nil && local != "" {
		return local
	}
	return strings.TrimPrefix(userID, "@")
}

func (d *Deps) toEvent(ctx context.Context, e store.Event, senders map[string]sender) (eventJSON, error) {
	who, ok := senders[e.Sender]
	if !ok {
		name, avatar, _, err := d.Store.GetProfile(ctx, e.Sender)
		if err != nil {
			return eventJSON{}, err
		}
		if name == "" {
			name = localpart(e.Sender)
		}
		who = sender{name: name, avatarPath: d.path(avatar)}
		senders[e.Sender] = who
	}
	content := e.Content
	var fields map[string]json.RawMessage
	if json.Unmarshal(content, &fields) != nil || fields == nil {
		content = json.RawMessage("{}") // content is always an object on the wire
	}
	var url string
	_ = json.Unmarshal(fields["url"], &url)
	status := e.Status
	if status == "" {
		status = "sent" // stored without one (the column's default): the network has it
	}
	return eventJSON{
		EventID: e.EventID, RoomID: e.RoomID, Sender: e.Sender, SenderName: who.name, SenderAvatarPath: who.avatarPath,
		Mine: e.Sender == string(ids.Me), Type: e.Type, Content: content, TS: ms(e.TS), Seq: e.Seq,
		Status: status, StatusReason: e.StatusReason, MediaPath: d.path(url),
	}, nil
}

func roomEvents(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Before *cursor `json:"before"`
		Limit  *int    `json:"limit"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	limit := 50
	if p.Limit != nil {
		if *p.Limit < 1 || *p.Limit > 100 {
			return nil, invalidParams("limit must be 1 to 100")
		}
		limit = *p.Limit
	}
	var before *store.Cursor
	if p.Before != nil {
		if p.Before.TS == nil || p.Before.Seq == nil {
			return nil, invalidParams("before needs ts and seq")
		}
		before = &store.Cursor{TS: time.UnixMilli(*p.Before.TS), Seq: *p.Before.Seq}
	}
	if _, err := d.room(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	evs, next, err := d.Store.EventsBefore(ctx, *p.RoomID, before, limit)
	if err != nil {
		return nil, err
	}
	out := make([]eventJSON, 0, len(evs))
	senders := map[string]sender{}
	for _, e := range evs {
		ev, err := d.toEvent(ctx, e, senders)
		if err != nil {
			return nil, err
		}
		out = append(out, ev)
	}
	var nextJSON any // null when there is no older page
	if next != nil {
		ts, seq := next.TS.UnixMilli(), next.Seq
		nextJSON = cursor{TS: &ts, Seq: &seq}
	}
	return map[string]any{"events": out, "before": nextJSON}, nil
}

func roomMarkRead(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	r, err := d.room(ctx, *p.RoomID)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	if err := d.Actions.MarkRead(ctx, r.ID); err != nil {
		// This device's unread count is cleared before the network is told. A chat on a network that isn't
		// running can't be told, and the receipt is best effort anyway: the chat is read.
		if !d.running(r.Network) {
			return nil, nil
		}
		return nil, err
	}
	return nil, nil
}

func roomSetMuted(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Muted  *bool   `json:"muted"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Muted == nil {
		return nil, invalidParams("muted is required")
	}
	if _, err := d.room(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	return nil, d.Store.SetMuted(ctx, *p.RoomID, *p.Muted)
}

type sent struct {
	EventID string `json:"event_id"`
}

func messageSend(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		Text    *string `json:"text"`
		ReplyTo string  `json:"reply_to"`
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
	if _, err := d.sendableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if p.ReplyTo != "" {
		if err := d.eventIn(ctx, *p.RoomID, p.ReplyTo); err != nil {
			return nil, err
		}
	}
	eventID, err := d.Actions.SendText(ctx, *p.RoomID, *p.Text, p.ReplyTo)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

func messageSendFile(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		Path    *string `json:"path"`
		ReplyTo string  `json:"reply_to"`
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
	if !filepath.IsAbs(*p.Path) {
		return nil, invalidParams("path must be absolute")
	}
	if fi, err := os.Stat(*p.Path); err != nil || !fi.Mode().IsRegular() {
		return nil, invalidParams("path is not a file that can be read")
	}
	if _, err := d.sendableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if p.ReplyTo != "" {
		if err := d.eventIn(ctx, *p.RoomID, p.ReplyTo); err != nil {
			return nil, err
		}
	}
	eventID, err := d.Actions.SendFile(ctx, *p.RoomID, *p.Path, p.ReplyTo)
	if errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
		return nil, invalidParams("path is not a file that can be read")
	}
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

func messageReact(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		EventID *string `json:"event_id"`
		Key     *string `json:"key"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if p.Key == nil || strings.TrimSpace(*p.Key) == "" {
		return nil, invalidParams("key is required")
	}
	if _, err := d.sendableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.eventIn(ctx, *p.RoomID, *p.EventID); err != nil {
		return nil, err
	}
	eventID, err := d.Actions.React(ctx, *p.RoomID, *p.EventID, *p.Key)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

// event loads the event a request names, or not_found.
func (d *Deps) event(ctx context.Context, raw json.RawMessage) (store.Event, error) {
	var p struct {
		EventID *string `json:"event_id"`
	}
	if err := decode(raw, &p); err != nil {
		return store.Event{}, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return store.Event{}, err
	}
	e, ok, err := d.Store.GetEvent(ctx, *p.EventID)
	if err != nil {
		return store.Event{}, err
	}
	if !ok {
		return store.Event{}, errNotFound
	}
	return e, nil
}

func messageRetry(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	if _, err := d.sendableRoom(ctx, e.RoomID); err != nil {
		return nil, err
	}
	return nil, d.Actions.Retry(ctx, e.EventID)
}

func messageDiscard(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.Discard(ctx, e.EventID)
}

func loginStart(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network *string `json:"network"`
		Flow    string  `json:"flow"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if d.Login == nil {
		return nil, errMissing
	}
	return d.Login.Start(ctx, *p.Network, p.Flow)
}

func loginID(raw json.RawMessage, values *map[string]string) (string, error) {
	var p struct {
		LoginID *string            `json:"login_id"`
		Values  *map[string]string `json:"values"`
	}
	if err := decode(raw, &p); err != nil {
		return "", err
	}
	if err := required("login_id", p.LoginID); err != nil {
		return "", err
	}
	if values != nil {
		if p.Values == nil {
			return "", invalidParams("values is required")
		}
		*values = *p.Values
	}
	return *p.LoginID, nil
}

func loginSubmit(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var values map[string]string
	id, err := loginID(raw, &values)
	if err != nil {
		return nil, err
	}
	if d.Login == nil {
		return nil, errMissing
	}
	return d.Login.Submit(ctx, id, values)
}

// loginWait waits on the request's context, which ends when the connection closes: a sign-in whose app went away
// is cancelled, so no half-open pairing is left.
func loginWait(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	id, err := loginID(raw, nil)
	if err != nil {
		return nil, err
	}
	if d.Login == nil {
		return nil, errMissing
	}
	return d.Login.Wait(ctx, id)
}

func loginCancel(_ context.Context, d *Deps, raw json.RawMessage) (any, error) {
	id, err := loginID(raw, nil)
	if err != nil {
		return nil, err
	}
	if d.Login == nil {
		return nil, errMissing
	}
	d.Login.Cancel(id)
	return nil, nil
}
