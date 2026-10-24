// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
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
	CodePinned           = -32021
	CodeNotEntitled      = -32022
	CodeNotSupported     = -32023
	CodeTooOld           = -32024
	CodeAlreadySent      = -32025
	CodeNotYours         = -32026
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
	CodePinned:           "a pinned chat can't be archived",
	CodeNotEntitled:      "this isn't part of your plan",
	CodeNotSupported:     "this network can't do that",
	CodeTooOld:           "that message is too old to change",
	CodeAlreadySent:      "it has already gone",
	CodeNotYours:         "you can only change your own messages",
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
	// A network that won't run this session, found by the action itself (it stopped between the check and the
	// action); and one still starting, for an action that isn't queued (a reaction retried): not connected yet.
	{engine.ErrNotRunning, CodeNotRunning},
	{engine.ErrStarting, CodeNotConnected},
	{actions.ErrNotFailed, CodeNotFailed},
	{actions.ErrNotSupported, CodeNotSupported},
	// The network said no to a change Courier waits on (a disappearing timer): it can't do that, as it stands.
	{actions.ErrNetworkRefused, CodeNotSupported},
	{actions.ErrNotEntitled, CodeNotEntitled},
	{actions.ErrTooOld, CodeTooOld},
	{actions.ErrAlreadySent, CodeAlreadySent}, // store.ErrAlreadySent
	{actions.ErrNotYours, CodeNotYours},
	{store.ErrBadValue, CodeBadValue},
	{store.ErrNotFound, CodeNotFound},
	{store.ErrPinned, CodePinned},
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
	if errors.Is(err, store.ErrBadCursor) {
		return invalidParams("cursor is not one this query handed out"), false
	}
	// Before ErrBadValue, which wraps it: formatting that doesn't fit the text is a bad parameter, not a bad value.
	if errors.Is(err, richtext.ErrBadEntity) {
		return invalidParams("entities don't fit the text"), false
	}
	if errors.Is(err, actions.ErrTooLong) {
		return invalidParams("text is too long"), false
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

	// Message actions (messages.go).
	"room.features":         roomFeatures,
	"room.members":          roomMembers,
	"room.setDisappearing":  roomSetDisappearing,
	"message.edit":          messageEdit,
	"message.unsend":        messageUnsend,
	"message.deleteForMe":   messageDeleteForMe,
	"message.forward":       messageForward,
	"message.undo":          messageUndo,
	"message.sendHeld":      messageSendHeld,
	"message.setBookmarked": messageSetBookmarked,
	"message.history":       messageHistory,
	"message.schedule":      messageSchedule,
	"scheduled.list":        scheduledList,
	"scheduled.update":      scheduledUpdate,
	"scheduled.sendNow":     scheduledSendNow,
	"scheduled.delete":      scheduledDelete,
	"poll.create":           pollCreate,
	"poll.vote":             pollVote,

	"login.start":  loginStart,
	"login.submit": loginSubmit,
	"login.wait":   loginWait,
	"login.cancel": loginCancel,

	// Organising the inbox (organise.go).
	"spaces.list":           spacesList,
	"spaces.setLayout":      spacesSetLayout,
	"spaces.update":         spacesUpdate,
	"labels.create":         labelsCreate,
	"labels.update":         labelsUpdate,
	"labels.delete":         labelsDelete,
	"room.setPinned":        roomSetPinned,
	"room.setArchived":      roomSetArchived,
	"room.setLowPriority":   roomSetLowPriority,
	"room.setHidden":        roomSetHidden,
	"room.setMarkedUnread":  roomSetMarkedUnread,
	"room.setLabel":         roomSetLabel,
	"room.setDraft":         roomSetDraft,
	"room.acceptRequest":    roomAcceptRequest,
	"reminder.set":          reminderSet,
	"reminder.clear":        reminderClear,
	"reminder.clearAll":     reminderClearAll,
	"inbox.archiveMatching": inboxArchiveMatching,
	"inbox.markAllRead":     inboxMarkAllRead,
	"autoArchive.list":      autoArchiveList,
	"autoArchive.set":       autoArchiveSet,
	"autoArchive.delete":    autoArchiveDelete,

	// Search (search.go).
	"search.query": searchQuery,
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
	return d.status(network).Running
}

// status is where a network is this session (engine.Status); with no engine, nowhere.
func (d *Deps) status(network string) engine.Status {
	if d.Engine == nil {
		return engine.Status{}
	}
	return d.Engine.Status(network)
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

// queueableRoom is sendableRoom for a new message (message.send, message.sendFile) and a retry of one
// (message.retry): a network still starting passes too, since the message waits for it there (Ruling C6). One that
// won't run this session is still -32016.
func (d *Deps) queueableRoom(ctx context.Context, roomID string) (store.Room, error) {
	r, err := d.room(ctx, roomID)
	if err != nil {
		return r, err
	}
	if d.Actions == nil {
		return r, errMissing
	}
	if st := d.status(r.Network); !st.Running && !st.Starting {
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
	Syncs       []string `json:"syncs"`
}

func accountsList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	out := make([]account, 0, len(d.Networks))
	for _, n := range d.Networks {
		a := account{Network: n.Name, DisplayName: n.DisplayName, Flows: append([]string{}, n.Flows...), Syncs: []string{}}
		if d.Actions != nil {
			a.Syncs = d.Actions.Syncs(n.Name) // never nil; empty for a network that isn't running or has no account
		}
		st := d.status(n.Name)
		switch {
		case st.Starting:
			// Not started yet, and it will be: no reason and no error, so the app shows no banner (spec §7).
			a.State = "STARTING"
		case !st.Running:
			a.State, a.NotStarted = "NOT_STARTED", st.NotStarted
			if a.NotStarted == "" {
				a.NotStarted = errorMessages[CodeNotRunning]
			}
		default:
			raw, ok, err := accountState(ctx, d.Store, n.Name, d.hasLogin(n.Name))
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

// accountState is the state a network's account shows: its login's. The bridge's own state (login ID "") is what it
// says with no login at all: UNCONFIGURED before any account is linked, and again at a start that finds none. So it
// counts only when no login has a state, or when it is newer than every login's (the bridge spoke after them all: the
// login it had is gone); the UNCONFIGURED from before linking is not the account's once its login has spoken. A tie
// goes to the login. With more than one login it is the first's for now. ok is false when the network has no state.
// Inferred (inventory 01): the account summary state; Task 7 makes it a summary over every login.
//
// Only the logins the bridge has count (live; nil counts every row): a login's state outlives the login, so a login
// signed in again as another account (deleted by login.Driver, as bridgev2 does) leaves a LOGGED_OUT row that is no
// account's any more.
func accountState(ctx context.Context, s *store.Store, network string, live func(loginID string) bool) (json.RawMessage, bool, error) {
	states, err := s.LoginStates(ctx, network)
	if err != nil {
		return nil, false, err
	}
	var own, first json.RawMessage
	var newestLogin int64
	for _, l := range states {
		if l.LoginID == "" {
			own = l.State
			continue
		}
		if live != nil && !live(l.LoginID) {
			continue
		}
		if first == nil {
			first = l.State
		}
		newestLogin = max(newestLogin, stateTime(l.State))
	}
	switch {
	case first == nil:
		return own, own != nil, nil
	case own != nil && stateTime(own) > newestLogin:
		return own, true, nil
	default:
		return first, true, nil
	}
}

// stateTime is when a bridge state was sent (its timestamp, in seconds); 0 when it doesn't say.
func stateTime(raw json.RawMessage) int64 {
	var st struct {
		Timestamp int64 `json:"timestamp"`
	}
	_ = json.Unmarshal(raw, &st) // a state that can't be read says no time
	return st.Timestamp
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
	Bookmarked       bool            `json:"bookmarked"`
	Poll             *pollTallyJSON  `json:"poll"`
	Thread           *threadJSON     `json:"thread"`
	ExpiresAt        int64           `json:"expires_at"`
}

type pollOptionJSON struct {
	ID    string `json:"id"`
	Text  string `json:"text"`
	Votes int    `json:"votes"`
}

type pollTallyJSON struct {
	Question      string           `json:"question"`
	Options       []pollOptionJSON `json:"options"`
	MaxSelections int              `json:"max_selections"`
	Voters        int              `json:"voters"`
	Mine          []string         `json:"mine"`
	Ended         bool             `json:"ended"`
}

type threadJSON struct {
	Replies     int      `json:"replies"`
	LastTS      int64    `json:"last_ts"`
	LastSenders []string `json:"last_senders"`
}

type sender struct{ name, avatarPath string }

// localpart is the part of a Matrix ID before the server name, without the @.
func localpart(userID string) string {
	if local, _, err := id.UserID(userID).Parse(); err == nil && local != "" {
		return local
	}
	return strings.TrimPrefix(userID, "@")
}

// sender is who userID is to the app: their profile's name (else their ID's localpart) and picture. senders caches
// them across a page.
func (d *Deps) sender(ctx context.Context, userID string, senders map[string]sender) (sender, error) {
	if who, ok := senders[userID]; ok {
		return who, nil
	}
	name, avatar, _, err := d.Store.GetProfile(ctx, userID)
	if err != nil {
		return sender{}, err
	}
	if name == "" {
		name = localpart(userID)
	}
	who := sender{name: name, avatarPath: d.path(avatar)}
	senders[userID] = who
	return who, nil
}

// toEvent is one event on the wire, without what toEvents adds.
func (d *Deps) toEvent(ctx context.Context, e store.Event, senders map[string]sender) (eventJSON, error) {
	who, err := d.sender(ctx, e.Sender, senders)
	if err != nil {
		return eventJSON{}, err
	}
	content := e.Content
	var fields map[string]json.RawMessage
	if json.Unmarshal(content, &fields) != nil || fields == nil {
		content = json.RawMessage("{}") // content is always an object on the wire
	} else if _, ok := fields[store.SourceKey]; ok {
		// A held message carries what was typed, for Undo; the timeline shows what will be sent.
		delete(fields, store.SourceKey)
		if content, err = json.Marshal(fields); err != nil {
			return eventJSON{}, err
		}
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
		Status: status, StatusReason: e.StatusReason, MediaPath: d.path(url), ExpiresAt: ms(e.ExpiresAt),
	}, nil
}

// pollStartType is a poll's event type (MSC3381): its event carries the poll's tally.
var pollStartType = event.EventUnstablePollStart.Type

// toEvents is a page of roomID's events on the wire, in their order, leaving out those deleted for me. What the
// page's events carry besides themselves takes one query each: which are bookmarked, the polls' tallies and the
// threads' summaries.
func (d *Deps) toEvents(ctx context.Context, roomID string, evs []store.Event, senders map[string]sender) ([]eventJSON, error) {
	var ids, polls []string
	for _, e := range evs {
		if e.DeletedForMe {
			continue
		}
		ids = append(ids, e.EventID)
		if e.Type == pollStartType {
			polls = append(polls, e.EventID)
		}
	}
	bookmarked, err := d.Store.Bookmarked(ctx, ids)
	if err != nil {
		return nil, err
	}
	tallies, err := d.Store.PollTallies(ctx, roomID, polls)
	if err != nil {
		return nil, err
	}
	threads, err := d.Store.ThreadSummaries(ctx, roomID, ids)
	if err != nil {
		return nil, err
	}
	out := make([]eventJSON, 0, len(ids))
	for _, e := range evs {
		if e.DeletedForMe {
			continue
		}
		ev, err := d.toEvent(ctx, e, senders)
		if err != nil {
			return nil, err
		}
		ev.Bookmarked = bookmarked[e.EventID]
		if t, ok := tallies[e.EventID]; ok {
			ev.Poll = toTally(t)
		}
		if t, ok := threads[e.EventID]; ok {
			senders := t.LastSenders
			if senders == nil {
				senders = []string{}
			}
			ev.Thread = &threadJSON{Replies: t.Replies, LastTS: ms(t.LastTS), LastSenders: senders}
		}
		out = append(out, ev)
	}
	return out, nil
}

func toTally(t store.PollTally) *pollTallyJSON {
	out := &pollTallyJSON{
		Question: t.Question, Options: make([]pollOptionJSON, 0, len(t.Options)), MaxSelections: t.MaxSelections,
		Voters: t.Voters, Mine: t.Mine, Ended: t.Ended,
	}
	if out.Mine == nil {
		out.Mine = []string{}
	}
	for _, o := range t.Options {
		out.Options = append(out.Options, pollOptionJSON{ID: o.ID, Text: o.Text, Votes: o.Votes})
	}
	return out
}

// eventsCursor is a room.events cursor as the store takes it; name says which parameter it is, for the reason.
func eventsCursor(name string, c *cursor) (store.Cursor, error) {
	if c.TS == nil || c.Seq == nil {
		return store.Cursor{}, invalidParams(name + " needs ts and seq")
	}
	return store.Cursor{TS: time.UnixMilli(*c.TS), Seq: *c.Seq}, nil
}

// cursorJSON is a cursor on the wire: null when there is none.
func cursorJSON(c *store.Cursor) any {
	if c == nil {
		return nil
	}
	ts, seq := c.TS.UnixMilli(), c.Seq
	return cursor{TS: &ts, Seq: &seq}
}

// roomEvents is one page of a chat's history, newest first: the newest page, the one older than before, the one
// newer than after, or the one around a message (so a search result opens the chat at it). Every page says where
// the next older (before) and the next newer (after) pages start, so paging both ways from a message reads each
// event exactly once. With thread, it is a page of that thread instead (threadPage).
//
// The main timeline leaves out a reply that stays in its thread, and every page leaves out what was deleted for me.
// A page stays under maxPageBytes, so it can hold fewer than limit events (even none): only its cursors say whether
// there is more.
func roomEvents(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Before *cursor `json:"before"`
		After  *cursor `json:"after"`
		Around *string `json:"around"`
		Thread *string `json:"thread"`
		Limit  *int    `json:"limit"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	given := 0
	for _, set := range []bool{p.Before != nil, p.After != nil, p.Around != nil} {
		if set {
			given++
		}
	}
	if given > 1 {
		return nil, invalidParams("only one of before, after and around can be given")
	}
	if p.Around != nil {
		if err := required("around", p.Around); err != nil {
			return nil, err
		}
	}
	if p.Thread != nil {
		if err := required("thread", p.Thread); err != nil {
			return nil, err
		}
		if p.Around != nil || p.After != nil {
			return nil, invalidParams("thread can't be given with around or after")
		}
	}
	limit := 50
	if p.Limit != nil {
		if *p.Limit < 1 || *p.Limit > 100 {
			return nil, invalidParams("limit must be 1 to 100")
		}
		limit = *p.Limit
	}
	var before, after store.Cursor
	var err error
	if p.Before != nil {
		if before, err = eventsCursor("before", p.Before); err != nil {
			return nil, err
		}
	}
	if p.After != nil {
		if after, err = eventsCursor("after", p.After); err != nil {
			return nil, err
		}
	}
	roomID := *p.RoomID
	if _, err := d.room(ctx, roomID); err != nil {
		return nil, err
	}
	var from *store.Cursor
	if p.Before != nil {
		from = &before
	}
	if p.Thread != nil {
		return d.threadPage(ctx, roomID, *p.Thread, from, limit)
	}
	around := ""
	if p.Around != nil {
		if around, err = d.anchor(ctx, roomID, *p.Around); err != nil {
			return nil, err
		}
	}
	fetch := func(limit int) (evs []store.Event, older, newer *store.Cursor, err error) {
		switch {
		case p.Around != nil:
			// A message that isn't in this chat is not_found, whatever the store calls it: only the code's fixed
			// message goes out (sentinels).
			return d.Store.EventsAround(ctx, roomID, around, limit)
		case p.After != nil:
			evs, newer, err = d.Store.EventsAfter(ctx, roomID, after, limit)
			if err == nil && len(evs) > 0 {
				// The page's oldest event has an older one: the after cursor's own event.
				oldest := evs[len(evs)-1]
				older = &store.Cursor{TS: oldest.TS, Seq: oldest.Seq}
			}
			return evs, older, newer, err
		default:
			evs, older, err = d.Store.EventsBefore(ctx, roomID, from, limit)
			// The newest page has the chat's newest event. A page older than another has newer events: the before
			// cursor's own event, at least.
			if err == nil && from != nil && len(evs) > 0 {
				newer = &store.Cursor{TS: evs[0].TS, Seq: evs[0].Seq}
			}
			return evs, older, newer, err
		}
	}
	senders := map[string]sender{}
	for {
		evs, older, newer, err := fetch(limit)
		if err != nil {
			return nil, err
		}
		out, err := d.toEvents(ctx, roomID, evs, senders)
		if err != nil {
			return nil, err
		}
		n := fitting(out, maxPageBytes-pageSlack)
		if n == len(out) || limit == 1 {
			return map[string]any{"events": out, "before": cursorJSON(older), "after": cursorJSON(newer)}, nil
		}
		// Too big: asked for again with only the stored events up to the last that fits, so the store hands out the
		// cursors of a page that ends there. Each pass asks for fewer.
		limit = min(limit-1, max(1, storedThrough(evs, out[n-1].EventID)))
	}
}

// storedThrough is how many of evs there are up to and including eventID.
func storedThrough(evs []store.Event, eventID string) int {
	for i, e := range evs {
		if e.EventID == eventID {
			return i + 1
		}
	}
	return len(evs)
}

// anchor is the event a page around eventID centres on: eventID itself, or, for a reply that stays in its thread
// (one the main timeline leaves out, as a search hit can be), that thread's root, when the root is in the chat
// (Ruling 23). The app then opens the thread at the reply.
func (d *Deps) anchor(ctx context.Context, roomID, eventID string) (string, error) {
	e, ok, err := d.Store.GetEvent(ctx, eventID)
	if err != nil || !ok || e.RoomID != roomID {
		return eventID, err // not in this chat: the store says not_found
	}
	root, ok := threadOnlyRoot(e.Content)
	if !ok {
		return eventID, nil
	}
	r, ok, err := d.Store.GetEvent(ctx, root)
	if err != nil {
		return "", err
	}
	if !ok || r.RoomID != roomID {
		return eventID, nil // a thread whose root this Mac doesn't have: the reply among its neighbours
	}
	return root, nil
}

// threadOnlyRoot is the root of a reply that stays in its thread: in a thread (m.relates_to.rel_type m.thread) and
// not also sent to the channel (com.beeper.broadcast_outside_thread). It is the store's isThreadReplySQL, in Go.
func threadOnlyRoot(content json.RawMessage) (string, bool) {
	var c struct {
		RelatesTo struct {
			RelType string `json:"rel_type"`
			EventID string `json:"event_id"`
		} `json:"m.relates_to"`
		Broadcast bool `json:"com.beeper.broadcast_outside_thread"`
	}
	if json.Unmarshal(content, &c) != nil || c.RelatesTo.RelType != "m.thread" || c.Broadcast || c.RelatesTo.EventID == "" {
		return "", false
	}
	return c.RelatesTo.EventID, true
}

// threadPage is one page of the thread of rootID in roomID, newest first: up to limit of its replies older than
// before (nil: the newest), with what the main timeline carries for them (their edits, reactions and the redactions
// that delete them, store.RelationsOf), so the thread pane shows them as the timeline would. The oldest page ends
// with the root itself, and what it carries. before is the next older page's cursor; after is always null, since
// after can't be given with thread. A root that isn't in the chat is not_found.
//
// A page stays under maxPageBytes. Each reply is budgeted together with what it carries, newest first, and the page
// ends before the first reply that wouldn't fit, its cursor at the last that did. Only a page's first reply can
// carry more than fits by itself (thousands of reactions): it goes with its redactions and edits, which its text
// depends on, and then as many of its reactions, newest first, as fit.
func (d *Deps) threadPage(ctx context.Context, roomID, rootID string, before *store.Cursor, limit int) (any, error) {
	root, ok, err := d.Store.GetEvent(ctx, rootID)
	if err != nil {
		return nil, err
	}
	if !ok || root.RoomID != roomID {
		return nil, errNotFound
	}
	targets, older, err := d.Store.ThreadEventsBefore(ctx, roomID, rootID, before, limit)
	if err != nil {
		return nil, err
	}
	if older == nil {
		targets = append(targets, root)
	}
	ids := make([]string, 0, len(targets))
	for _, e := range targets {
		ids = append(ids, e.EventID)
	}
	rel, err := d.Store.RelationsOf(ctx, roomID, ids) // newest first
	if err != nil {
		return nil, err
	}
	out, err := d.toEvents(ctx, roomID, append(slices.Clone(targets), rel...), map[string]sender{})
	if err != nil {
		return nil, err
	}
	byID := make(map[string]eventJSON, len(out))
	for _, e := range out {
		byID[e.EventID] = e
	}
	// target → what it carries: first what its text depends on (the redactions that delete it and its edits), then
	// its reactions, each newest first. Only a reply that carries more than fits loses any, and then only reactions.
	carried := map[string][]eventJSON{}
	var reactions []store.Event
	for _, e := range rel {
		if e.Type == event.EventReaction.Type {
			reactions = append(reactions, e)
			continue
		}
		if ev, ok := byID[e.EventID]; ok {
			t := relationTarget(e)
			carried[t] = append(carried[t], ev)
		}
	}
	for _, e := range reactions {
		if ev, ok := byID[e.EventID]; ok {
			t := relationTarget(e)
			carried[t] = append(carried[t], ev)
		}
	}
	size := func(e eventJSON) int { return encodedLen(e) + 1 } // and its comma
	budget, used := maxPageBytes-pageSlack, 2                  // the list's brackets
	page := []eventJSON{}
	for i, t := range targets {
		var group []eventJSON
		if ev, ok := byID[t.EventID]; ok {
			group = append(group, ev)
		}
		group = append(group, carried[t.EventID]...)
		n := 0
		for _, ev := range group {
			n += size(ev)
		}
		if used+n <= budget {
			page, used = append(page, group...), used+n
			continue
		}
		kept := i
		if i == 0 { // the first goes whatever its size, with as much of what it carries as fits
			for j, ev := range group {
				if s := size(ev); j == 0 || used+s <= budget {
					page, used = append(page, ev), used+s
				}
			}
			kept = 1
		}
		if kept < len(targets) {
			last := targets[kept-1]
			older = &store.Cursor{TS: last.TS, Seq: last.Seq}
		}
		break
	}
	slices.SortStableFunc(page, func(a, b eventJSON) int {
		if c := cmp.Compare(b.TS, a.TS); c != 0 {
			return c
		}
		return cmp.Compare(b.Seq, a.Seq)
	})
	return map[string]any{"events": page, "before": cursorJSON(older), "after": nil}, nil
}

// relationTarget is the event a relation points at: a redaction's redacts, else its m.relates_to.event_id.
func relationTarget(e store.Event) string {
	var c struct {
		Redacts   string `json:"redacts"`
		RelatesTo struct {
			EventID string `json:"event_id"`
		} `json:"m.relates_to"`
	}
	_ = json.Unmarshal(e.Content, &c) // RelationsOf matched it by these, so they read
	if e.Type == event.EventRedaction.Type {
		return c.Redacts
	}
	return c.RelatesTo.EventID
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
	return nil, d.markRead(ctx, r)
}

// markRead marks a chat read (Actions.MarkRead): its unread count, an unread mark and a reminder that fired all
// clear, then the network is told.
func (d *Deps) markRead(ctx context.Context, r store.Room) error {
	if d.Actions == nil {
		return errMissing
	}
	if err := d.Actions.MarkRead(ctx, r.ID); err != nil {
		// This device's unread count is cleared before the network is told. A chat on a network that isn't
		// running, or hasn't started yet, can't be told, and the receipt is best effort anyway: the chat is read.
		// Judged by the error, not by asking again: the network may have come up since.
		if errors.Is(err, engine.ErrStarting) || errors.Is(err, engine.ErrNotRunning) {
			return nil
		}
		return err
	}
	return nil
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
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetMuted(ctx, *p.RoomID, *p.Muted) // an unknown chat is store.ErrNotFound
}

type sent struct {
	EventID string `json:"event_id"`
}

func messageSend(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID     *string           `json:"room_id"`
		Text       *string           `json:"text"`
		Entities   []richtext.Entity `json:"entities"`
		ReplyTo    string            `json:"reply_to"`
		ThreadRoot string            `json:"thread_root"`
		HoldMS     *int64            `json:"hold_ms"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := textParam(p.Text, p.Entities); err != nil {
		return nil, err
	}
	hold, err := d.hold(p.HoldMS)
	if err != nil {
		return nil, err
	}
	if _, err := d.queueableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.replyAndThread(ctx, *p.RoomID, p.ReplyTo, p.ThreadRoot); err != nil {
		return nil, err
	}
	o := actions.SendOptions{Entities: p.Entities, ReplyTo: p.ReplyTo, ThreadRoot: p.ThreadRoot, Hold: hold}
	eventID, err := d.Actions.Send(ctx, *p.RoomID, *p.Text, o)
	if err != nil {
		return nil, err
	}
	if hold > 0 {
		d.poke() // Ruling 22: the window ends on time, not at the loop's next wake
	}
	return sent{EventID: eventID}, nil
}

// messageSendFile sends a file. A file has no text, so entities are taken and ignored.
func messageSendFile(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID     *string           `json:"room_id"`
		Path       *string           `json:"path"`
		Entities   []richtext.Entity `json:"entities"`
		ReplyTo    string            `json:"reply_to"`
		ThreadRoot string            `json:"thread_root"`
		HoldMS     *int64            `json:"hold_ms"`
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
	hold, err := d.hold(p.HoldMS)
	if err != nil {
		return nil, err
	}
	if _, err := d.queueableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.replyAndThread(ctx, *p.RoomID, p.ReplyTo, p.ThreadRoot); err != nil {
		return nil, err
	}
	o := actions.SendOptions{ReplyTo: p.ReplyTo, ThreadRoot: p.ThreadRoot, Hold: hold}
	eventID, err := d.Actions.SendFileWith(ctx, *p.RoomID, *p.Path, o)
	if errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
		return nil, invalidParams("path is not a file that can be read")
	}
	if err != nil {
		return nil, err
	}
	if hold > 0 {
		d.poke()
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
	return d.eventByID(ctx, *p.EventID)
}

// eventByID loads an event by its ID, or not_found.
func (d *Deps) eventByID(ctx context.Context, eventID string) (store.Event, error) {
	e, ok, err := d.Store.GetEvent(ctx, eventID)
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
	if _, err := d.queueableRoom(ctx, e.RoomID); err != nil {
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
	// Which account: 4.3's rule until login.start takes its new parameters (Task 7).
	return d.Login.Start(ctx, *p.Network, p.Flow, login.StartOptions{})
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
