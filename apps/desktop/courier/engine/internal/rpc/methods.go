// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/logscrub"
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
	CodeNetworkRefused   = -32027
	CodeNeedsFFmpeg      = -32028
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
	CodeNetworkRefused:   "network refused",
	CodeNeedsFFmpeg:      "sending voice notes on this network needs ffmpeg",
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
	{actions.ErrVoiceTranscodeUnavailable, CodeNeedsFFmpeg},
	// The network turned the change down: nothing changed on this Mac.
	{actions.ErrNetworkRefused, CodeNetworkRefused},
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
	// Before ErrBadValue, which wraps it: an account_id that is no account of the network's is a bad parameter.
	if errors.Is(err, login.ErrUnknownAccount) {
		return invalidParams(reasonUnknownAccount), false
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
	"accounts.list":        accountsList,
	"inbox.list":           inboxList,
	"room.events":          roomEvents,
	"room.markRead":        roomMarkRead,
	"room.setMuted":        roomSetMuted,
	"message.send":         messageSend,
	"message.sendFile":     messageSendFile,
	"message.sendVoice":    messageSendVoice,
	"message.sendLocation": messageSendLocation,
	"message.sendSticker":  messageSendSticker,
	"message.sendGIF":      messageSendGIF,
	"message.markPlayed":   messageMarkPlayed,
	"message.react":        messageReact,
	"message.retry":        messageRetry,
	"message.discard":      messageDiscard,

	// Presence & chat info / group actions (presence.go).
	"room.setTyping":        roomSetTyping,
	"room.setUnreadFrom":    roomSetUnreadFrom,
	"room.directChat":       roomDirectChat,
	"room.info":             roomInfo,
	"room.setLocalOverride": roomSetLocalOverride,
	"room.export":           roomExport,
	"room.reportSpam":       roomReportSpam,
	"room.setName":          roomSetName,
	"room.setTopic":         roomSetTopic,
	"room.setAvatar":        roomSetAvatar,
	"room.invite":           roomInvite,
	"room.kick":             roomKick,
	"room.setAdmin":         roomSetAdmin,
	"room.leave":            roomLeave,
	"room.delete":           roomDelete,

	// People & starting chats (people.go).
	"people.contacts":  peopleContacts,
	"people.resolve":   peopleResolve,
	"room.createGroup": roomCreateGroup,
	"blast.send":       blastSend,

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
	"merge.create":          mergeCreate,
	"merge.update":          mergeUpdate,
	"merge.delete":          mergeDelete,
	"merge.list":            mergeList,
	"merge.suggest":         mergeSuggest,

	// Search (search.go).
	"search.query": searchQuery,

	// Stickers & custom emoji catalog (stickers.go).
	"stickers.list":   stickersList,
	"stickers.import": stickersImport,

	// Bridges, account removal, sub-accounts, and diagnostics (protocol 9).
	"bridges.list":           bridgesList,
	"bridges.restart":        bridgesRestart,
	"accounts.remove":        accountsRemove,
	"accounts.subAccounts":   accountsSubAccounts,
	"accounts.setSubAccount": accountsSetSubAccount,
	"diagnostics.export":     diagnosticsExport,
}

var errMissing = errors.New("a dependency this method needs is missing")

func required(name string, v *string) error {
	if v == nil || *v == "" {
		return invalidParams(name + " is required")
	}
	if (name == "room_id" || name == "last_room_id") && strings.HasPrefix(*v, "merge:") {
		return invalidParams(name + " must not be a merge_id")
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
	if strings.HasPrefix(roomID, "merge:") {
		return store.Room{}, invalidParams("room_id must not be a merge_id")
	}
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
	Network        string      `json:"network"`
	DisplayName    string      `json:"display_name"`
	Flows          []string    `json:"flows"`
	State          string      `json:"state"`
	Error          string      `json:"error"`
	RemoteName     string      `json:"remote_name"`
	NotStarted     string      `json:"not_started"`
	Syncs          []string    `json:"syncs"`
	CanCreateGroup bool        `json:"can_create_group"`
	Logins         []loginJSON `json:"logins"`
}

// loginJSON is a Login: one account signed in on a network. Its ID is account_id on the wire, never login_id, which
// is a sign-in's (Ruling C16).
type loginJSON struct {
	AccountID      string `json:"account_id"`
	RemoteName     string `json:"remote_name"`
	State          string `json:"state"`
	Error          string `json:"error"`
	CanCreateGroup bool   `json:"can_create_group"`
}

// bridgeState is the part of a bridge state (status.BridgeState) the protocol shows.
type bridgeState struct {
	StateEvent string `json:"state_event"`
	Error      string `json:"error"`
	Message    string `json:"message"`
	RemoteName string `json:"remote_name"`
	Timestamp  int64  `json:"timestamp"` // seconds; 0 when it doesn't say
}

// readState reads a stored bridge state; one that can't be read is no state.
func readState(raw json.RawMessage) bridgeState {
	var st bridgeState
	_ = json.Unmarshal(raw, &st)
	return st
}

// state is the state's state_event, UNCONFIGURED when it says none: the bridge is running and has said nothing.
func (st bridgeState) state() string {
	if st.StateEvent == "" {
		return "UNCONFIGURED"
	}
	return st.StateEvent
}

// errorText is what went wrong, for people: the bridge's message, else its error code.
func (st bridgeState) errorText() string {
	if st.Message != "" {
		return st.Message
	}
	return st.Error
}

func accountsList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	out, err := d.buildAccounts(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]any{"accounts": out}, nil
}

func (d *Deps) buildAccounts(ctx context.Context) ([]account, error) {
	out := make([]account, 0, len(d.Networks))
	for _, n := range d.Networks {
		a := account{Network: n.Name, DisplayName: n.DisplayName, Flows: append([]string{}, n.Flows...), Syncs: []string{}}
		if d.Actions != nil {
			a.Syncs = d.Actions.Syncs(n.Name) // never nil; empty for a network that isn't running or has no account
			a.CanCreateGroup = d.Actions.CanCreateGroup(n.Name, "")
		}
		states, err := d.Store.LoginStates(ctx, n.Name) // read once: the logins and the summary both come from it
		if err != nil {
			return nil, err
		}
		live := d.hasAccount(n.Name)
		logins := liveLogins(states, live)
		a.Logins = make([]loginJSON, 0, len(logins))
		for _, l := range logins {
			st := readState(l.State)
			var canGroup bool
			if d.Actions != nil {
				canGroup = d.Actions.CanCreateGroup(n.Name, l.LoginID)
			}
			a.Logins = append(a.Logins, loginJSON{
				AccountID:      l.LoginID,
				RemoteName:     d.remoteName(n.Name, l),
				State:          st.state(),
				Error:          st.errorText(),
				CanCreateGroup: canGroup,
			})
		}
		if len(a.Logins) > 0 {
			a.RemoteName = a.Logins[0].RemoteName
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
			var summary bridgeState
			if raw, ok := summaryState(states, live); ok {
				summary = readState(raw)
			}
			a.State, a.Error = summary.state(), summary.errorText()
			if len(a.Logins) == 0 {
				a.RemoteName = summary.RemoteName
			}
		}
		if !st.Running {
			// Its accounts are listed as the engine last knew them, with the account's own state and no error, so
			// none shows a banner either.
			for i := range a.Logins {
				a.Logins[i].State, a.Logins[i].Error = a.State, ""
			}
		}
		out = append(out, a)
	}
	return out, nil
}

// accountLogins is network's accounts (liveLogins of its stored states).
func (d *Deps) accountLogins(ctx context.Context, network string) ([]store.LoginState, error) {
	states, err := d.Store.LoginStates(ctx, network)
	if err != nil {
		return nil, err
	}
	return liveLogins(states, d.hasAccount(network)), nil
}

// liveLogins is a network's accounts, by account ID, from its login states: one per state of a login (the bridge's
// own, "", is no account), counting only the accounts its running bridge has (live): a state outlives its account,
// so one the bridge has deleted leaves a row that is no account's until the next start drops it. While the network
// isn't running (live nil) every stored one counts.
func liveLogins(states []store.LoginState, live func(accountID string) bool) []store.LoginState {
	var out []store.LoginState
	for _, l := range states {
		if l.LoginID == "" || (live != nil && !live(l.LoginID)) {
			continue
		}
		out = append(out, l)
	}
	return out
}

// remoteName is what the network calls the account l is the state of: what its state says, else what the running
// bridge has for it.
func (d *Deps) remoteName(network string, l store.LoginState) string {
	if name := readState(l.State).RemoteName; name != "" {
		return name
	}
	if d.Engine == nil {
		return ""
	}
	h, ok := d.Engine.Host(network)
	if !ok {
		return ""
	}
	if ul := h.Bridge.GetCachedUserLoginByID(networkid.UserLoginID(l.LoginID)); ul != nil && ul.UserMXID == ids.Me {
		return ul.RemoteName
	}
	return ""
}

// needsPerson are the states only the person can fix (the app's banners offer Reconnect), and reconnecting the ones
// in which the bridge is trying to get back online (the app's reconnecting mark).
var (
	needsPerson  = []string{"LOGGED_OUT", "BAD_CREDENTIALS", "UNKNOWN_ERROR"}
	reconnecting = []string{"CONNECTING", "TRANSIENT_DISCONNECT", "BRIDGE_UNREACHABLE"}
)

// accountState is the state a network's account shows, summed up over its logins: the first that needs the person,
// else the first reconnecting, else the first (by account ID, as LoginStates lists them), so one account signed out
// is never hidden behind another that works (Review Focus 5). The bridge's own state (login ID "") is what it says
// with no login at all: UNCONFIGURED before any account is linked, and again at a start that finds none. So it counts
// only when no login has a state, or when it is newer than every login's (the bridge spoke after them all: the login
// it had is gone); the UNCONFIGURED from before linking is not the account's once its login has spoken. A tie goes to
// the login. ok is false when the network has no state.
//
// Inferred (inventory 01): the account summary state; the inventory shows one banner per account, not how a network
// with several sums them up.
//
// Only the accounts the bridge has count (live; nil counts every row): an account's state outlives it, so one the
// bridge has deleted (signed out from the network's own side, or by a bridge command) leaves a LOGGED_OUT row that is
// no account's any more. An account deleted and then signed in again under the same ID counts at once, with that old
// row, for the moment until its new login sends its first state (it does as it connects); the row says LOGGED_OUT
// meanwhile, which is what the account was.
func accountState(ctx context.Context, s *store.Store, network string, live func(accountID string) bool) (json.RawMessage, bool, error) {
	states, err := s.LoginStates(ctx, network)
	if err != nil {
		return nil, false, err
	}
	raw, ok := summaryState(states, live)
	return raw, ok, nil
}

// summaryState is accountState over a network's login states, read already.
func summaryState(states []store.LoginState, live func(accountID string) bool) (json.RawMessage, bool) {
	var own json.RawMessage
	for _, l := range states {
		if l.LoginID == "" {
			own = l.State
		}
	}
	var logins []json.RawMessage
	var newestLogin int64
	for _, l := range liveLogins(states, live) {
		logins = append(logins, l.State)
		newestLogin = max(newestLogin, stateTime(l.State))
	}
	switch {
	case len(logins) == 0:
		return own, own != nil
	// The one-second tie rule: the bridge's own state wins only when it is strictly newer than every login's. A
	// bridge state's timestamp is in whole seconds (status.BridgeState.Timestamp), so a bridge state and a login's
	// sent in the same second compare equal, and that tie goes to the login: wrongly taking the bridge's UNCONFIGURED
	// would show a linked account as not linked, the worse mistake. The cost is the other way round: when the bridge
	// speaks in the same second its last login goes, the account still sums up as that login until a later state.
	case own != nil && stateTime(own) > newestLogin:
		return own, true
	}
	for _, group := range [][]string{needsPerson, reconnecting} {
		for _, l := range logins {
			if slices.Contains(group, readState(l).StateEvent) {
				return l, true
			}
		}
	}
	return logins[0], true
}

// stateTime is when a bridge state was sent (its timestamp, in seconds); 0 when it doesn't say.
func stateTime(raw json.RawMessage) int64 {
	return readState(raw).Timestamp
}

type cursor struct {
	TS  *int64 `json:"ts"`
	Seq *int64 `json:"seq"`
}

type linkPreviewItemJSON struct {
	MatchedURL  string `json:"matched_url"`
	URL         string `json:"url,omitempty"`
	Title       string `json:"title,omitempty"`
	SiteName    string `json:"site_name,omitempty"`
	Description string `json:"description,omitempty"`
	ImagePath   string `json:"image_path,omitempty"`
	ImageWidth  int    `json:"image_width,omitempty"`
	ImageHeight int    `json:"image_height,omitempty"`
	Blurhash    string `json:"blurhash,omitempty"`
}

type eventJSON struct {
	EventID          string                `json:"event_id"`
	RoomID           string                `json:"room_id"`
	Sender           string                `json:"sender"`
	SenderName       string                `json:"sender_name"`
	SenderAvatarPath string                `json:"sender_avatar_path"`
	Mine             bool                  `json:"mine"`
	Type             string                `json:"type"`
	Content          json.RawMessage       `json:"content"`
	TS               int64                 `json:"ts"`
	Seq              int64                 `json:"seq"`
	Status           string                `json:"status"`
	StatusReason     string                `json:"status_reason"`
	MediaPath        string                `json:"media_path"`
	ThumbnailPath    string                `json:"thumbnail_path,omitempty"`
	Blurhash         string                `json:"blurhash,omitempty"`
	DurationMS       int64                 `json:"duration_ms,omitempty"`
	Waveform         []int                 `json:"waveform,omitempty"`
	IsGIF            bool                  `json:"is_gif,omitempty"`
	IsAnimated       bool                  `json:"is_animated,omitempty"`
	ViewOnce         bool                  `json:"view_once,omitempty"`
	GeoURI           string                `json:"geo_uri,omitempty"`
	LinkPreviews     []linkPreviewItemJSON `json:"link_previews,omitempty"`
	Played           bool                  `json:"played,omitempty"`
	Bookmarked       bool                  `json:"bookmarked"`
	Poll             *pollTallyJSON        `json:"poll"`
	Thread           *threadJSON           `json:"thread"`
	ExpiresAt        int64                 `json:"expires_at"`
	Delivered        bool                  `json:"delivered"`
	ReadBy           []readerJSON          `json:"read_by"`
}

// readerJSON is a Reader: someone who has read a message of mine, or anything after it.
type readerJSON struct {
	UserID string `json:"user_id"`
	Name   string `json:"name"`
	TS     int64  `json:"ts"`
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
	prof, _, err := d.Store.GetProfile(ctx, userID)
	if err != nil {
		return sender{}, err
	}
	name := prof.DisplayName
	if name == "" {
		name = localpart(userID)
	}
	who := sender{name: name, avatarPath: d.path(prof.AvatarURI)}
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
	ev := eventJSON{
		EventID: e.EventID, RoomID: e.RoomID, Sender: e.Sender, SenderName: who.name, SenderAvatarPath: who.avatarPath,
		Mine: e.Sender == string(ids.Me), Type: e.Type, Content: content, TS: ms(e.TS), Seq: e.Seq,
		Status: status, StatusReason: e.StatusReason, MediaPath: d.path(url), ExpiresAt: ms(e.ExpiresAt),
		ReadBy: []readerJSON{}, Played: e.Played,
	}
	populateEventMedia(ctx, d, e, &ev)
	return ev, nil
}

// withoutRedacted is mine without the messages deleted here (unsent, or past a disappearing timer): one query.
func (d *Deps) withoutRedacted(ctx context.Context, mine []store.Event) ([]store.Event, error) {
	if len(mine) == 0 {
		return mine, nil
	}
	ids := make([]string, 0, len(mine))
	for _, e := range mine {
		ids = append(ids, e.EventID)
	}
	redacted, err := d.Store.RedactedAmong(ctx, ids)
	if err != nil || len(redacted) == 0 {
		return mine, err
	}
	kept := make([]store.Event, 0, len(mine))
	for _, e := range mine {
		if !redacted[e.EventID] {
			kept = append(kept, e)
		}
	}
	return kept, nil
}

// pollStartType is a poll's event type (MSC3381): its event carries the poll's tally.
var pollStartType = event.EventUnstablePollStart.Type

// toEvents is a page of roomID's events on the wire, in their order, leaving out those deleted for me. What the
// page's events carry besides themselves takes one query each: which are bookmarked, the polls' tallies, the
// threads' summaries and my messages' receipts (who has read each, whether a device has it: store.ReceiptsFor). The
// readers are named once per page (presence.go), and a waiting message says when its chat has no account to go
// through (noAccountReason).
func (d *Deps) toEvents(ctx context.Context, roomID string, evs []store.Event, senders map[string]sender) ([]eventJSON, error) {
	var ids, polls []string
	var mine []store.Event
	waiting := false
	for _, e := range evs {
		if e.DeletedForMe {
			continue
		}
		ids = append(ids, e.EventID)
		if e.Type == pollStartType {
			polls = append(polls, e.EventID)
		}
		if e.Sender == myUserID {
			mine = append(mine, e)
			waiting = waiting || e.Status == store.StatusWaiting
		}
	}
	// A message of mine I unsent (or that is otherwise deleted here) carries no receipts: read_by and delivered are
	// for my messages that have gone and are still there. Its redaction may be on a newer page than this one, so the
	// store says which are redacted.
	mine, err := d.withoutRedacted(ctx, mine)
	if err != nil {
		return nil, err
	}
	receipts, err := d.Store.ReceiptsFor(ctx, roomID, mine)
	if err != nil {
		return nil, err
	}
	readers, err := d.readersOf(ctx, roomID, receipts)
	if err != nil {
		return nil, err
	}
	waitingReason := ""
	if waiting {
		if waitingReason, err = d.noAccountReason(ctx, roomID); err != nil {
			return nil, err
		}
	}
	bookmarked, err := d.Store.Bookmarked(ctx, ids)
	if err != nil {
		return nil, err
	}
	played, err := d.Store.MediaPlayedSet(ctx, roomID, ids)
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
		e.Played = played[e.EventID]
		ev, err := d.toEvent(ctx, e, senders)
		if err != nil {
			return nil, err
		}
		ev.Bookmarked = bookmarked[e.EventID]
		ev.Played = played[e.EventID]
		if r, ok := receipts[e.EventID]; ok {
			ev.Delivered = len(r.DeliveredTo) > 0
			ev.ReadBy = readers.of(r.ReadBy)
		}
		if e.Status == store.StatusWaiting && e.Sender == myUserID && ev.StatusReason == "" {
			ev.StatusReason = waitingReason
		}
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
		RoomID  *string `json:"room_id"`
		MergeID *string `json:"merge_id"`
		Before  *cursor `json:"before"`
		After   *cursor `json:"after"`
		Around  *string `json:"around"`
		Thread  *string `json:"thread"`
		Limit   *int    `json:"limit"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	mergeID := ""
	if p.MergeID != nil {
		mergeID = *p.MergeID
	}
	if mergeID == "" {
		if err := required("room_id", p.RoomID); err != nil {
			return nil, err
		}
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
		if mergeID != "" {
			return nil, invalidParams("thread can't be given with merge_id")
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
	var from *store.Cursor
	if p.Before != nil {
		from = &before
	}
	if mergeID != "" {
		roomID := ""
		if p.RoomID != nil {
			if strings.HasPrefix(*p.RoomID, "merge:") {
				return nil, invalidParams("room_id must not be a merge_id")
			}
			roomID = *p.RoomID
		}
		return d.mergedEventsPage(ctx, mergeID, roomID, from, p.After != nil, after, p.Around, limit)
	}
	roomID := *p.RoomID
	if _, err := d.room(ctx, roomID); err != nil {
		return nil, err
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

func (d *Deps) mergedEventsPage(ctx context.Context, mergeID, roomID string, before *store.Cursor, hasAfter bool, after store.Cursor, around *string, limit int) (any, error) {
	merges, err := d.Store.ListMergedChats(ctx)
	if err != nil {
		return nil, err
	}
	found := false
	for _, mc := range merges {
		if mc.MergeID == mergeID {
			found = true
			break
		}
	}
	if !found {
		return nil, errNotFound
	}
	var (
		evs                  []store.Event
		moreOlder, moreNewer bool
	)
	switch {
	case around != nil:
		evs, moreOlder, moreNewer, err = d.Store.MergedEventsAround(ctx, mergeID, roomID, *around, limit)
	case hasAfter:
		evs, moreNewer, err = d.Store.MergedEventsAfter(ctx, mergeID, &after, limit)
		moreOlder = len(evs) > 0
	default:
		evs, moreOlder, err = d.Store.MergedEventsBefore(ctx, mergeID, before, limit)
		moreNewer = before != nil && len(evs) > 0
	}
	if err != nil {
		return nil, err
	}
	// Store returns oldest-to-newest; wire EventsPage is newest-first.
	slices.Reverse(evs)
	var older, newer *store.Cursor
	if len(evs) > 0 {
		if moreOlder {
			oldest := evs[len(evs)-1]
			older = &store.Cursor{TS: oldest.TS, Seq: oldest.Seq}
		}
		if moreNewer {
			newest := evs[0]
			newer = &store.Cursor{TS: newest.TS, Seq: newest.Seq}
		}
	}
	out, err := d.toMergedEvents(ctx, evs)
	if err != nil {
		return nil, err
	}
	return map[string]any{"events": out, "before": cursorJSON(older), "after": cursorJSON(newer)}, nil
}

func (d *Deps) toMergedEvents(ctx context.Context, evs []store.Event) ([]eventJSON, error) {
	if len(evs) == 0 {
		return []eventJSON{}, nil
	}
	senders := map[string]sender{}
	byRoom := map[string][]store.Event{}
	var rooms []string
	for _, e := range evs {
		if _, seen := byRoom[e.RoomID]; !seen {
			rooms = append(rooms, e.RoomID)
		}
		byRoom[e.RoomID] = append(byRoom[e.RoomID], e)
	}
	converted := map[string]eventJSON{}
	for _, rid := range rooms {
		revs, err := d.toEvents(ctx, rid, byRoom[rid], senders)
		if err != nil {
			return nil, err
		}
		for _, ev := range revs {
			converted[rid+"\x00"+ev.EventID] = ev
		}
	}
	out := make([]eventJSON, 0, len(evs))
	for _, e := range evs {
		if ev, ok := converted[e.RoomID+"\x00"+e.EventID]; ok {
			out = append(out, ev)
		}
	}
	return out, nil
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
		RoomID             *string           `json:"room_id"`
		Text               *string           `json:"text"`
		Entities           []richtext.Entity `json:"entities"`
		ReplyTo            string            `json:"reply_to"`
		ThreadRoot         string            `json:"thread_root"`
		HoldMS             *int64            `json:"hold_ms"`
		DisableLinkPreview *bool             `json:"disable_link_preview"`
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
	o := actions.SendOptions{
		Entities:           p.Entities,
		ReplyTo:            p.ReplyTo,
		ThreadRoot:         p.ThreadRoot,
		Hold:               hold,
		DisableLinkPreview: p.DisableLinkPreview,
	}
	eventID, err := d.Actions.Send(ctx, *p.RoomID, *p.Text, o)
	if err != nil {
		return nil, err
	}
	if hold > 0 {
		d.poke() // Ruling 22: the window ends on time, not at the loop's next wake
	}
	return sent{EventID: eventID}, nil
}

func messageMarkPlayed(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		EventID *string `json:"event_id"`
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
	if err := d.Store.MarkMediaPlayed(ctx, *p.RoomID, *p.EventID, time.Now().UnixMilli()); err != nil {
		return nil, err
	}
	d.Store.CleanupPlayedViewOnceMedia(ctx, *p.RoomID, *p.EventID, d.Media)
	return nil, nil
}

func messageSendVoice(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID     *string `json:"room_id"`
		Path       *string `json:"path"`
		DurationMS *int64  `json:"duration_ms"`
		Waveform   []int   `json:"waveform"`
		ReplyTo    string  `json:"reply_to"`
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
	if p.DurationMS == nil || *p.DurationMS < 0 {
		return nil, invalidParams("duration_ms is required")
	}
	if !filepath.IsAbs(*p.Path) {
		return nil, invalidParams("path must be absolute")
	}
	if fi, err := os.Stat(*p.Path); err != nil || !fi.Mode().IsRegular() {
		return nil, invalidParams("path is not a file that can be read")
	}
	if _, err := d.queueableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.replyAndThread(ctx, *p.RoomID, p.ReplyTo, ""); err != nil {
		return nil, err
	}
	res, err := d.Actions.SendVoice(ctx, *p.RoomID, *p.Path, actions.SendVoiceOpts{
		DurationMS: int(*p.DurationMS),
		Waveform:   p.Waveform,
		ReplyTo:    p.ReplyTo,
	})
	if errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
		return nil, invalidParams("path is not a file that can be read")
	}
	if err != nil {
		return nil, err
	}
	return sent{EventID: res.EventID}, nil
}

func messageSendLocation(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID    *string  `json:"room_id"`
		Latitude  *float64 `json:"latitude"`
		Longitude *float64 `json:"longitude"`
		Label     string   `json:"label"`
		ReplyTo   string   `json:"reply_to"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Latitude == nil || *p.Latitude < -90 || *p.Latitude > 90 {
		return nil, invalidParams("latitude must be between -90 and 90")
	}
	if p.Longitude == nil || *p.Longitude < -180 || *p.Longitude > 180 {
		return nil, invalidParams("longitude must be between -180 and 180")
	}
	if _, err := d.queueableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.replyAndThread(ctx, *p.RoomID, p.ReplyTo, ""); err != nil {
		return nil, err
	}
	res, err := d.Actions.SendLocation(ctx, *p.RoomID, *p.Latitude, *p.Longitude, p.Label, p.ReplyTo)
	if err != nil {
		return nil, err
	}
	return sent{EventID: res.EventID}, nil
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

// maxAccountIDBytes is the longest account_id login.start takes (Global Constraints: outside data can't crash the
// engine; a bridge's account IDs are far shorter).
const maxAccountIDBytes = 256

// reasonUnknownAccount is login.start's reason for an account_id that is no account of the network's.
const reasonUnknownAccount = "account_id is no account of this network"

// loginStart starts a sign-in: the network's first account (4.3's rule), a second beside it (another), or one of its
// accounts again (account_id, in a state Reconnect fixes). The account is account_id on the wire, never login_id,
// which names the sign-in (Ruling C16).
func loginStart(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network   *string `json:"network"`
		Flow      string  `json:"flow"`
		Another   bool    `json:"another"`
		AccountID *string `json:"account_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	var o login.StartOptions
	if p.AccountID != nil {
		if n := len(*p.AccountID); n < 1 || n > maxAccountIDBytes {
			return nil, invalidParams(fmt.Sprintf("account_id must be 1 to %d bytes", maxAccountIDBytes))
		}
		if p.Another {
			return nil, invalidParams("another and account_id can't be given together")
		}
		o.AccountID = *p.AccountID
	}
	o.Another = p.Another
	if d.Login == nil {
		return nil, errMissing
	}
	return d.Login.Start(ctx, *p.Network, p.Flow, o)
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

type bridgeInfoJSON struct {
	Network        string    `json:"network"`
	DisplayName    string    `json:"display_name"`
	BridgeID       string    `json:"bridge_id"`
	ModulePath     string    `json:"module_path"`
	Version        string    `json:"version"`
	MautrixVersion string    `json:"mautrix_version"`
	State          string    `json:"state"`
	Error          string    `json:"error,omitempty"`
	Message        string    `json:"message,omitempty"`
	StartedAt      int64     `json:"started_at"`
	Accounts       []account `json:"accounts"`
}

type subAccountItemJSON struct {
	Network     string `json:"network"`
	AccountID   string `json:"account_id"`
	SubID       string `json:"sub_id"`
	Title       string `json:"title"`
	AvatarURI   string `json:"avatar_uri"`
	Kind        string `json:"kind"`
	Enabled     bool   `json:"enabled"`
	ShowInInbox string `json:"show_in_inbox"`
}

type roomDiagnosticJSON struct {
	RoomID   string `json:"room_id"`
	Network  string `json:"network"`
	IsDirect bool   `json:"is_direct"`
}

type messageDiagnosticJSON struct {
	EventID      string `json:"event_id"`
	RoomID       string `json:"room_id"`
	Network      string `json:"network"`
	Type         string `json:"type"`
	TS           int64  `json:"ts"`
	Status       string `json:"status"`
	StatusReason string `json:"status_reason"`
	HasMedia     bool   `json:"has_media"`
	IsRedacted   bool   `json:"is_redacted"`
}

type diagnosticsExportResultJSON struct {
	ProtocolVersion int                    `json:"protocol_version"`
	SchemaVersion   int                    `json:"schema_version"`
	GoVersion       string                 `json:"go_version"`
	Bridges         []bridgeInfoJSON       `json:"bridges"`
	ScrubbedStderr  []string               `json:"scrubbed_stderr"`
	RoomDetails     *roomDiagnosticJSON    `json:"room_details,omitempty"`
	MessageDetails  *messageDiagnosticJSON `json:"message_details,omitempty"`
}

func (d *Deps) knownNetwork(name string) bool {
	for _, n := range d.Networks {
		if n.Name == name {
			return true
		}
	}
	return false
}

func (d *Deps) bridgeInfos(ctx context.Context) ([]bridgeInfoJSON, error) {
	accs, err := d.buildAccounts(ctx)
	if err != nil {
		return nil, err
	}
	byNet := map[string]engine.BridgeReport{}
	if d.Engine != nil {
		reps, err := d.Engine.Bridges(ctx)
		if err != nil {
			return nil, err
		}
		for _, r := range reps {
			byNet[r.Network] = r
		}
	}
	out := make([]bridgeInfoJSON, 0, len(accs))
	for _, a := range accs {
		rep, ok := byNet[a.Network]
		displayName := rep.DisplayName
		if displayName == "" {
			displayName = a.DisplayName
		}
		bridgeID := rep.BridgeID
		if bridgeID == "" {
			bridgeID = a.Network
		}
		modPath := rep.ModulePath
		if modPath == "" {
			modPath = "go.mau.fi/mautrix-" + a.Network
		}
		state := rep.State
		if !ok || state == "" {
			state = a.State
		}
		msg := rep.Message
		if !ok && a.State == "NOT_STARTED" {
			msg = a.NotStarted
		}
		biAccounts := make([]account, 0, len(a.Logins))
		for _, l := range a.Logins {
			biAccounts = append(biAccounts, account{
				Network:        a.Network,
				DisplayName:    a.DisplayName,
				Flows:          a.Flows,
				State:          l.State,
				Error:          l.Error,
				RemoteName:     l.RemoteName,
				NotStarted:     a.NotStarted,
				Syncs:          a.Syncs,
				CanCreateGroup: l.CanCreateGroup,
				Logins:         []loginJSON{l},
			})
		}
		out = append(out, bridgeInfoJSON{
			Network:        a.Network,
			DisplayName:    displayName,
			BridgeID:       bridgeID,
			ModulePath:     modPath,
			Version:        rep.Version,
			MautrixVersion: rep.MautrixVer,
			State:          state,
			Error:          rep.Error,
			Message:        msg,
			StartedAt:      rep.StartedAtMS,
			Accounts:       biAccounts,
		})
	}
	return out, nil
}

func bridgesList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	bridges, err := d.bridgeInfos(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]any{"bridges": bridges}, nil
}

func bridgesRestart(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network *string `json:"network"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if !d.knownNetwork(*p.Network) {
		return nil, store.ErrBadValue
	}
	if d.Engine == nil {
		return nil, errMissing
	}
	if err := d.Engine.RestartNetwork(ctx, *p.Network); err != nil {
		return nil, toError(err)
	}
	return nil, nil
}

func accountsRemove(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network      *string `json:"network"`
		AccountID    *string `json:"account_id"`
		LogoutRemote *bool   `json:"logout_remote"`
		DeleteChats  *bool   `json:"delete_chats"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("account_id", p.AccountID); err != nil {
		return nil, err
	}
	if p.LogoutRemote == nil {
		return nil, invalidParams("logout_remote is required")
	}
	if p.DeleteChats == nil {
		return nil, invalidParams("delete_chats is required")
	}
	if !d.knownNetwork(*p.Network) {
		return nil, store.ErrBadValue
	}
	if d.Engine != nil {
		if err := d.Engine.RemoveAccount(ctx, *p.Network, *p.AccountID, *p.LogoutRemote, *p.DeleteChats); err != nil {
			return nil, err
		}
		return nil, nil
	}
	states, err := d.Store.LoginStates(ctx, *p.Network)
	if err != nil {
		return nil, err
	}
	found := false
	for _, st := range states {
		if st.LoginID == *p.AccountID {
			found = true
			break
		}
	}
	if !found {
		return nil, store.ErrNotFound
	}
	return nil, d.Store.RemoveAccountData(ctx, *p.Network, *p.AccountID, *p.DeleteChats)
}

func accountsSubAccounts(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network   *string `json:"network"`
		AccountID *string `json:"account_id"`
		Refresh   *bool   `json:"refresh"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("account_id", p.AccountID); err != nil {
		return nil, err
	}
	if !d.knownNetwork(*p.Network) {
		return nil, store.ErrBadValue
	}
	var subs []store.SubAccount
	var err error
	if p.Refresh != nil && *p.Refresh && d.Engine != nil {
		subs, err = d.Engine.RefreshSubAccounts(ctx, *p.Network, *p.AccountID)
	} else {
		subs, err = d.Store.SubAccounts(ctx, *p.Network, *p.AccountID)
	}
	if err != nil {
		return nil, err
	}
	items := make([]subAccountItemJSON, 0, len(subs))
	for _, s := range subs {
		items = append(items, subAccountItemJSON{
			Network:     s.Network,
			AccountID:   s.LoginID,
			SubID:       s.SubID,
			Title:       s.Title,
			AvatarURI:   s.AvatarURI,
			Kind:        s.Kind,
			Enabled:     s.Enabled,
			ShowInInbox: s.ShowInInbox,
		})
	}
	return map[string]any{"sub_accounts": items}, nil
}

func accountsSetSubAccount(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Network     *string `json:"network"`
		AccountID   *string `json:"account_id"`
		SubID       *string `json:"sub_id"`
		Enabled     *bool   `json:"enabled"`
		ShowInInbox *string `json:"show_in_inbox"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("network", p.Network); err != nil {
		return nil, err
	}
	if err := required("account_id", p.AccountID); err != nil {
		return nil, err
	}
	if err := required("sub_id", p.SubID); err != nil {
		return nil, err
	}
	if !d.knownNetwork(*p.Network) {
		return nil, store.ErrBadValue
	}
	return nil, d.Store.UpdateSubAccount(ctx, *p.Network, *p.AccountID, *p.SubID, p.Enabled, p.ShowInInbox)
}

func diagnosticsExport(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		EventID *string `json:"event_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	bridges, err := d.bridgeInfos(ctx)
	if err != nil {
		return nil, err
	}
	scrubbedStderr := []string{}
	if d.DataDir != "" {
		if data, err := os.ReadFile(filepath.Join(d.DataDir, logscrub.StderrLogName)); err == nil {
			if lines := logscrub.ScrubStderrExport(string(data)); lines != nil {
				scrubbedStderr = lines
			}
		}
	}
	res := diagnosticsExportResultJSON{
		ProtocolVersion: Protocol,
		SchemaVersion:   store.SchemaVersion,
		GoVersion:       runtime.Version(),
		Bridges:         bridges,
		ScrubbedStderr:  scrubbedStderr,
	}
	if p.RoomID != nil && *p.RoomID != "" {
		r, err := d.room(ctx, *p.RoomID)
		if err != nil {
			return nil, err
		}
		res.RoomDetails = &roomDiagnosticJSON{
			RoomID:   r.ID,
			Network:  r.Network,
			IsDirect: r.IsDirect,
		}
	}
	if p.EventID != nil && *p.EventID != "" {
		e, err := d.eventByID(ctx, *p.EventID)
		if err != nil {
			return nil, err
		}
		if p.RoomID != nil && *p.RoomID != "" && e.RoomID != *p.RoomID {
			return nil, errNotFound
		}
		r, _, err := d.Store.GetRoom(ctx, e.RoomID)
		if err != nil {
			return nil, err
		}
		redacted, err := d.Store.Redacted(ctx, e.EventID)
		if err != nil {
			return nil, err
		}
		var fields map[string]json.RawMessage
		_ = json.Unmarshal(e.Content, &fields)
		var url string
		if fields != nil {
			_ = json.Unmarshal(fields["url"], &url)
		}
		status := e.Status
		if status == "" {
			status = "sent"
		}
		res.MessageDetails = &messageDiagnosticJSON{
			EventID:      e.EventID,
			RoomID:       e.RoomID,
			Network:      r.Network,
			Type:         e.Type,
			TS:           ms(e.TS),
			Status:       status,
			StatusReason: logscrub.Redact(e.StatusReason),
			HasMedia:     url != "",
			IsRedacted:   redacted,
		}
	}
	return res, nil
}
