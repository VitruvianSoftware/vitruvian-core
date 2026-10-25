// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package actions is what a person can do in a chat: reply, react, send a file, mark it read, and retry or
// discard a message that failed. Each action goes out through the bridge of the network the chat belongs to.
//
// An outgoing message is stored as "pending" first and then handed to the bridge, which reports back through the
// store ("sent" or "failed"). The send actions return once the bridge has handled the event, so the row is
// usually settled by then, but a network may answer later: callers follow the change feed, not the return.
//
// A new message whose chat can't send now (its network is still starting, or its login isn't logged in) is stored
// "waiting" instead and answered at once; the timer loop hands it over when the login is back (SendWaiting). There is
// no cut-off (Review Focus 1). Everything else a person does to a message (an edit, a reaction, an unsend, a poll, a
// timer change) is not queued: it waits up to LoginWait for the login, as before.
package actions

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif"  // register the decoders image.DecodeConfig uses to read a picture's size
	_ "image/jpeg" // (see above)
	_ "image/png"  // (see above)
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// MaxFileBytes is the largest file SendFile accepts: 90 MB.
const MaxFileBytes int64 = 90 * 1024 * 1024

// DefaultLoginWait is how long an action waits for a linked network to finish logging in before giving up.
const DefaultLoginWait = 30 * time.Second

var (
	// ErrNotLinked means the network has no login at all, so waiting would never help.
	ErrNotLinked = errors.New("isn't linked")
	// ErrNotConnected means a linked network did not become logged in in time for an action that isn't queued (an
	// edit, a reaction, an unsend, a poll, a timer change, a forward). Nothing was sent. A new message never gets it:
	// it waits instead.
	ErrNotConnected = errors.New("not connected yet")
	// ErrBridgeCommand means the text starts with the network's bridge command prefix and would be run as an
	// admin command instead of being sent.
	ErrBridgeCommand = errors.New("the bridge would run it as an admin command")
	// ErrTooLarge means a file is over MaxFileBytes.
	ErrTooLarge = errors.New("file is too large to send (the limit is 90 MB)")
	// ErrNotFailed means the message is not in the failed state, which is the only state Retry and Discard act on.
	ErrNotFailed = errors.New("only a failed message can be retried or discarded")
	// ErrEmpty means there is nothing to send.
	ErrEmpty = errors.New("nothing to send")
	// ErrTooLong means a message's text is over MaxTextBytes.
	ErrTooLong = errors.New("that message is too long to send")
	// ErrTooOld means the network no longer lets that message be changed: it is past the chat's edit or unsend
	// window, or at its most edits. Nothing was sent.
	ErrTooOld = errors.New("that message is too old to change")
	// ErrNotYours means the message is someone else's, and only my own can be edited or unsent.
	ErrNotYours = errors.New("you can only change your own messages")
	// ErrAlreadySent is Undo's answer once the held message has gone (its window ended, or it was sent now).
	ErrAlreadySent = store.ErrAlreadySent
	// ErrBadValue means a value the action doesn't take: a hold window not in HoldWindows, a poll or timer the chat
	// doesn't offer, formatting that doesn't fit the text, a time out of range.
	ErrBadValue = store.ErrBadValue
	// ErrNotEntitled means the plan doesn't include the feature (undo send, send later). Nothing was stored.
	ErrNotEntitled = errors.New("the plan doesn't include that")
	// ErrNetworkRefused means the network answered no to a change Courier waits on (a disappearing timer), so
	// nothing changed here. It wraps the bridge's own reason when there is one.
	ErrNetworkRefused = errors.New("the network refused the change")
)

// MaxTextBytes is the most UTF-8 bytes a message's text may have: 64 KiB. Formatting ranges (richtext) set no
// limit of their own, and nothing between the composer and a bridge does either, so this keeps one runaway paste
// from making an event the size of a file. It is above the limits the bridges advertise (Telegram 4,096
// characters, Slack 40,000: Features.MaxTextLength), which a network enforces by failing the message.
const MaxTextBytes = 64 * 1024

// ReasonUnreadable is the status_reason of a held or scheduled message HandOff couldn't send because its stored
// content can't be read back as an event. Nothing was sent.
const ReasonUnreadable = "unreadable"

// ReasonNotConnected is the status_reason of a held or scheduled message HandOff couldn't hand to its network because
// the network isn't running this session: there is nothing to wait for. Nothing was sent; the app offers Retry. (A
// network that is starting or down makes the message wait instead.)
const ReasonNotConnected = "not connected"

// HoldWindows are the undo-send windows a message may be held for: ComposerPreferences.undoSendMillis. 0 sends at
// once.
var HoldWindows = []time.Duration{0, 750 * time.Millisecond, time.Second, 2 * time.Second, 3 * time.Second, 5 * time.Second, 10 * time.Second}

// SendOptions are how a message is sent.
type SendOptions struct {
	// Entities are the formatting ranges of the text (richtext); a file ignores them.
	Entities []richtext.Entity
	// ReplyTo is the message replied to; ThreadRoot the thread it goes in (only where the chat has threads).
	ReplyTo, ThreadRoot string
	// Hold is the undo-send window: one of HoldWindows, 0 = at once. Above 0 needs entitlement.UndoSend.
	Hold time.Duration
}

// Source is what the composer typed, which a held or scheduled message carries under store.SourceKey so Undo and
// Edit Scheduled give back exactly that: the text, its ranges, and what it replied to or went in. No claim sends
// it to a network.
type Source struct {
	Text       string            `json:"text"`
	Entities   []richtext.Entity `json:"entities"`
	ReplyTo    string            `json:"reply_to,omitempty"`
	ThreadRoot string            `json:"thread_root,omitempty"`
}

// SourceOf reads the composer's source from a held or scheduled message's content; ok is false when it has none.
func SourceOf(content json.RawMessage) (src Source, ok bool) {
	var c map[string]json.RawMessage
	if json.Unmarshal(content, &c) != nil {
		return Source{}, false
	}
	raw, ok := c[store.SourceKey]
	if !ok || json.Unmarshal(raw, &src) != nil {
		return Source{}, false
	}
	if src.Entities == nil {
		src.Entities = []richtext.Entity{}
	}
	return src, true
}

// Actions sends things on the user's behalf. Safe for concurrent use.
type Actions struct {
	// LoginWait bounds how long an action waits for a linked network to log in. New sets DefaultLoginWait.
	LoginWait time.Duration
	// Entitlement says which plan features are allowed (undo send, send later). nil allows everything. It is asked
	// only when a message is held or scheduled, never when one already held or scheduled goes out.
	Entitlement entitlement.Provider

	eng     *engine.Engine
	s       *store.Store
	m       *media.Store
	maxFile int64
	mu      sync.Mutex // makes "is it failed? then change it" one step for Retry and Discard
	// after is the login wait's timer (waitLogin): nil is time.After. Tests drive it instead (Ruling P5).
	after func(time.Duration) <-chan time.Time

	// flushMu makes a SendWaiting claim and the record of the chats it claimed one step, and a send's "is anything
	// ahead of me?" another, so a send sees a chat's messages either still waiting or on their way (behindWaiting).
	flushMu  sync.Mutex
	inFlight map[string]int // per chat, the waiting messages a SendWaiting run has claimed and not handed over yet

	// Wake, when set, is called when a message is put back to waiting only because messages of its chat were ahead of
	// it, its login being in: nothing else would wake the timer loop to send it (a put-back publishes only "status").
	// The engine sets it to the loop's Poke.
	Wake func()

	untold untold // chat changes not told to their network yet (retell)

	typing typingState // my typing per chat, as the networks were last told it (SetTyping)
}

// New returns the actions over a running engine. m may be nil if SendFile is never used.
func New(e *engine.Engine, s *store.Store, m *media.Store) *Actions {
	return &Actions{LoginWait: DefaultLoginWait, eng: e, s: s, m: m, maxFile: MaxFileBytes}
}

// bridgeCommandPrefix is a bridge's command prefix ("!" + network name). A message body starting with it
// is run by that network's bridge as an admin command instead of being sent.
func bridgeCommandPrefix(network string) string { return "!" + network }

func refuseBridgeCommand(network, body, what string) error {
	prefix := bridgeCommandPrefix(network)
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(body)), prefix) {
		return fmt.Errorf("refusing to send %s starting with %s: %w", what, prefix, ErrBridgeCommand)
	}
	return nil
}

// loginRecheck is how often a login wait looks again at the logins without being woken: a backstop for a connector
// that says it is connected a moment before its client counts as logged in. The store's changes (a login's bridge
// state among them) wake it as they come.
const loginRecheck = 200 * time.Millisecond

// WaitForLogin waits until at least one of the local user's logins on this network reports it is logged in.
// The bridge's Start only connects the logins: the connection counts as logged in a moment later, when the
// server's success message arrives. A message queued before then is refused as "not logged in" and marked
// failed. A network with no login at all is not going to get one by waiting, so that fails at once.
func WaitForLogin(ctx context.Context, h *host.Host, timeout time.Duration) error {
	return waitForLogin(ctx, h, timeout, time.After, nil, anyLoggedIn(h))
}

// anyLoggedIn reports whether some login of mine on h is logged in.
func anyLoggedIn(h *host.Host) func() bool {
	return func() bool {
		for _, l := range myLogins(h) {
			if l.Client.IsLoggedIn() {
				return true
			}
		}
		return false
	}
}

// waitLogin is the wait of the actions that still wait (an edit, a reaction, an unsend, a poll, a vote, a timer
// change, a retried one of those): up to LoginWait for the chat roomID's own login (loginOf) to be logged in, never
// another account's (Review Focus 5, Ruling 4). It goes by a's timer, and is woken by every store change, so a login's
// bridge state coming in (fakenet's SetLoggedIn in tests) ends the wait at once (Ruling P5). A network with no login
// of mine at all is ErrNotLinked; a login that doesn't come in time is ErrNotConnected; an unknown chat is
// store.ErrNotFound.
func (a *Actions) waitLogin(ctx context.Context, h *host.Host, roomID string) error {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !ok {
		return store.ErrNotFound
	}
	feed := a.s.Feed() // before the first look, so a change between the look and the wait isn't missed
	defer feed.Close()
	after := a.after
	if after == nil {
		after = time.After
	}
	return waitForLogin(ctx, h, a.LoginWait, after, feed.C, func() bool { return a.connected(ctx, h, room) })
}

// WaitForChat is waitLogin for a caller with no timer loop to send a message that waits (the CLI). A network that
// won't run this session, or is still starting, is HostForRoom's error.
func (a *Actions) WaitForChat(ctx context.Context, roomID string) error {
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return err
	}
	return a.waitLogin(ctx, h, roomID)
}

// waitForLogin is the login wait: it asks ready, and again whenever wake delivers or loginRecheck has passed (both by
// after), until ready is true, timeout has passed, or ctx ends.
func waitForLogin(ctx context.Context, h *host.Host, timeout time.Duration, after func(time.Duration) <-chan time.Time, wake <-chan store.Change, ready func() bool) error {
	if err := linked(ctx, h); err != nil {
		return err
	}
	deadline := after(timeout)
	for {
		if ready() {
			return nil
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("%s: %w — nothing was sent", h.Network, ErrNotConnected)
		case <-deadline:
			return fmt.Errorf("%s: %w — nothing was sent", h.Network, ErrNotConnected)
		case <-wake:
		case <-after(loginRecheck):
		}
	}
}

// linked is ErrNotLinked when h's network has no login of mine at all: no waiting would help.
func linked(ctx context.Context, h *host.Host) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	if len(me.GetUserLogins()) == 0 {
		return fmt.Errorf("%s %w — run link --network %s first", h.Network, ErrNotLinked, h.Network)
	}
	return nil
}

// loginOf is the login of mine on h that room goes out through, the one rule for "the chat's login" (Ruling C9):
// sends, waits, Features, chat changes and receipts all ask it.
//   - A chat of one account (rooms.login_id) goes through that login, logged in or not.
//   - A chat every account shares ("": a WhatsApp group) goes through the login bridgev2 itself sends it with
//     (Portal.FindPreferredLogin): one of mine that is in the chat and logged in, so a group only B is in is down
//     while B is, though A is in (Ruling 12). None is nil. A legacy chat whose portal has a receiver but whose
//     login_id isn't known yet gets that receiver, as bridgev2 does.
//   - Only for a chat the bridge has no portal for is it the first of mine that is logged in.
//
// nil when there is none: the chat's login isn't one of mine here, or no login of a shared chat can send it.
func loginOf(ctx context.Context, h *host.Host, room store.Room) *bridgev2.UserLogin {
	if room.LoginID != "" {
		for _, l := range myLogins(h) {
			if string(l.ID) == room.LoginID {
				return l
			}
		}
		return nil
	}
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(room.ID))
	if err != nil {
		return nil
	}
	if portal == nil {
		for _, l := range myLogins(h) {
			if l.Client.IsLoggedIn() {
				return l
			}
		}
		return nil
	}
	me, err := h.Me(ctx)
	if err != nil {
		return nil
	}
	l, _, _ := portal.FindPreferredLogin(ctx, me, false) // its error only says why there is none
	if l == nil || l.UserMXID != ids.Me || l.Client == nil {
		return nil
	}
	return l
}

// loginFor is loginOf for the chat roomID: ok is false when the chat is unknown or has no login of mine to go
// through. It names an account even for a shared chat, whose rooms.login_id is "": so a one-to-one chat made from
// a group (Reply Privately's store.DirectRoomWith) is looked for under this login's ID, never "" (Ruling C15).
func (a *Actions) loginFor(ctx context.Context, h *host.Host, roomID string) (*bridgev2.UserLogin, bool) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil || !ok {
		return nil, false
	}
	l := loginOf(ctx, h, room)
	return l, l != nil
}

// connected reports whether room can send through h now: its login (loginOf) is logged in. One login of a network
// being in says nothing about another's chats, nor about a shared chat it isn't in (Review Focus 5).
func (a *Actions) connected(ctx context.Context, h *host.Host, room store.Room) bool {
	l := loginOf(ctx, h, room)
	return l != nil && l.Client.IsLoggedIn()
}

// target checks that an event the user points at (a message to reply to or react to) is in this chat.
func (a *Actions) target(ctx context.Context, roomID, eventID, what string) error {
	e, ok, err := a.s.GetEvent(ctx, eventID)
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("no message %s to %s", eventID, what)
	}
	if e.RoomID != roomID {
		return fmt.Errorf("message %s is not in this chat", eventID)
	}
	return nil
}

// now is the store's clock, so an age check goes by the same time as the store's rules.
func (a *Actions) now() time.Time { return a.s.Now() }

// allowed reports whether the plan includes f.
func (a *Actions) allowed(f entitlement.Feature) bool {
	return a.Entitlement == nil || a.Entitlement.Allowed(f)
}

// stage stores an outgoing event as pending, ready to be handed to the bridge with h.Bridge.QueueMatrixEvent.
// Callers have done every check that could refuse it, so a refused action leaves no trace.
func (a *Actions) stage(ctx context.Context, roomID string, typ event.Type, parsed any) (*event.Event, error) {
	now := a.now()
	evt := &event.Event{
		Type: typ, RoomID: id.RoomID(roomID), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: now.UnixMilli(), Content: event.Content{Parsed: parsed},
	}
	raw, err := json.Marshal(&evt.Content)
	if err != nil {
		return nil, err
	}
	if _, err = a.s.InsertEvent(ctx, store.Event{
		RoomID: roomID, EventID: string(evt.ID), Sender: string(ids.Me),
		Type: typ.Type, Content: raw, TS: now, Status: "pending",
	}); err != nil {
		return nil, err
	}
	return evt, nil
}

// submit stages an outgoing event and hands it to the bridge.
func (a *Actions) submit(ctx context.Context, h *host.Host, roomID string, typ event.Type, parsed any) (string, error) {
	evt, err := a.stage(ctx, roomID, typ, parsed)
	if err != nil {
		return "", err
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return string(evt.ID), nil
}

func replyRelation(replyTo string) *event.RelatesTo {
	if replyTo == "" {
		return nil
	}
	return (&event.RelatesTo{}).SetReplyTo(id.EventID(replyTo))
}

// SendText sends a text message to a chat, as a reply to replyTo if that is not empty. It returns the ID of the
// stored message. It is Send with no formatting, thread or hold.
func (a *Actions) SendText(ctx context.Context, roomID, text, replyTo string) (string, error) {
	return a.Send(ctx, roomID, text, SendOptions{ReplyTo: replyTo})
}

// checkText refuses text that is empty, over MaxTextBytes, or has ranges richtext.Check refuses (ErrBadValue,
// wrapping richtext's reason).
func checkText(text string, ents []richtext.Entity) error {
	if strings.TrimSpace(text) == "" {
		return ErrEmpty
	}
	if len(text) > MaxTextBytes {
		return ErrTooLong
	}
	if err := richtext.Check(text, ents); err != nil {
		return fmt.Errorf("%w: %w", ErrBadValue, err)
	}
	return nil
}

// checkHold refuses a hold window that isn't in HoldWindows, and one above 0 the plan doesn't include.
func (a *Actions) checkHold(hold time.Duration) error {
	if !slices.Contains(HoldWindows, hold) {
		return ErrBadValue
	}
	if hold > 0 && !a.allowed(entitlement.UndoSend) {
		return ErrNotEntitled
	}
	return nil
}

// textContent renders text and its ranges into the content a chat with features f gets: the plain body, the HTML
// only when a kept range needs it, and m.mentions when it names anyone. @room counts only where the chat's network
// takes it (Slack): elsewhere it is plain text and mentions nobody.
func textContent(f Features, text string, ents []richtext.Entity) *event.MessageEventContent {
	r := richtext.Render(text, ents, f.Keeps)
	c := &event.MessageEventContent{MsgType: event.MsgText, Body: r.Body}
	if r.HTML != "" {
		c.Format, c.FormattedBody = event.FormatHTML, r.HTML
	}
	room := r.Room && f.MentionRoom
	if len(r.UserIDs) > 0 || room {
		c.Mentions = &event.Mentions{Room: room}
		for _, u := range r.UserIDs {
			c.Mentions.Add(id.UserID(u))
		}
	}
	return c
}

// relation is the m.relates_to of a new message with options o in roomID: a reply, a reply in a thread, or nil. A
// thread needs the chat's threads (else ErrNotSupported) and, with no message replied to, points its fallback
// reply at the thread's newest message (the root, while it has none), as Matrix clients do.
func (a *Actions) relation(ctx context.Context, roomID string, f Features, o SendOptions) (*event.RelatesTo, error) {
	if o.ReplyTo != "" {
		if err := a.target(ctx, roomID, o.ReplyTo, "reply to"); err != nil {
			return nil, err
		}
	}
	if o.ThreadRoot == "" {
		return replyRelation(o.ReplyTo), nil
	}
	if !f.Thread {
		return nil, ErrNotSupported
	}
	if err := a.target(ctx, roomID, o.ThreadRoot, "reply in the thread of"); err != nil {
		return nil, err
	}
	rel := &event.RelatesTo{Type: event.RelThread, EventID: id.EventID(o.ThreadRoot)}
	if o.ReplyTo != "" {
		rel.InReplyTo = &event.InReplyTo{EventID: id.EventID(o.ReplyTo)}
		return rel, nil
	}
	newest, err := a.newestInThread(ctx, roomID, o.ThreadRoot)
	if err != nil {
		return nil, err
	}
	rel.InReplyTo, rel.IsFallingBack = &event.InReplyTo{EventID: id.EventID(newest)}, true
	return rel, nil
}

// newestInThread is the newest reply of a thread that the network has (not failed, held, waiting or still pending),
// or the root when there is none.
func (a *Actions) newestInThread(ctx context.Context, roomID, root string) (string, error) {
	replies, _, err := a.s.ThreadEventsBefore(ctx, roomID, root, nil, 20)
	if err != nil {
		return "", err
	}
	for _, e := range replies {
		switch e.Status {
		case "failed", "queued", store.StatusWaiting, "pending":
			continue
		}
		return e.EventID, nil
	}
	return root, nil
}

// chatTimer is the chat's disappearing-message timer from its stored com.beeper.disappearing_timer state, or nil
// when it has none (or one that is off).
func (a *Actions) chatTimer(ctx context.Context, roomID string) (*event.BeeperDisappearingTimer, error) {
	raw, ok, err := a.s.GetState(ctx, roomID, event.StateBeeperDisappearingTimer.Type, "")
	if err != nil || !ok {
		return nil, err
	}
	var t event.BeeperDisappearingTimer
	if json.Unmarshal(raw, &t) != nil || t.Timer.Duration <= 0 {
		return nil, nil
	}
	switch t.Type {
	case event.DisappearingTypeAfterSend, event.DisappearingTypeAfterRead:
		return &t, nil
	}
	return nil, nil
}

// withSource is content as JSON with the composer's source under store.SourceKey.
func withSource(parsed any, src Source) (json.RawMessage, error) {
	raw, err := json.Marshal(parsed)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err = json.Unmarshal(raw, &m); err != nil {
		return nil, err
	}
	if src.Entities == nil {
		src.Entities = []richtext.Entity{}
	}
	if m[store.SourceKey], err = json.Marshal(src); err != nil {
		return nil, err
	}
	return json.Marshal(m)
}

// composeText is a new text message to roomID (on network), checked and ready to send: the text (checkText) rendered
// with the ranges the chat keeps (textContent), refused if the bridge would run its body as a command, with its
// reply or thread (relation) and the chat's disappearing timer. Send renders with it now and Schedule (and
// UpdateScheduled) for later, so the two can't drift apart.
func (a *Actions) composeText(ctx context.Context, roomID, network, text string, o SendOptions) (*event.MessageEventContent, error) {
	if err := checkText(text, o.Entities); err != nil {
		return nil, err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return nil, err
	}
	c := textContent(f, text, o.Entities)
	if err = refuseBridgeCommand(network, c.Body, "text"); err != nil {
		return nil, err
	}
	if c.RelatesTo, err = a.relation(ctx, roomID, f, o); err != nil {
		return nil, err
	}
	if c.BeeperDisappearingTimer, err = a.chatTimer(ctx, roomID); err != nil {
		return nil, err
	}
	return c, nil
}

// sendTarget is the chat a new message goes to and the host of its network, nil while that network is still starting
// (it will run: the message waits). A network that won't run this session (engine.ErrNotRunning), one with no login
// of mine at all (ErrNotLinked) and an unknown chat refuse the send: nothing would ever send it. Never the first host
// or any other fallback: a message goes out through the chat's own network.
func (a *Actions) sendTarget(ctx context.Context, roomID string) (store.Room, *host.Host, error) {
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil && !errors.Is(err, engine.ErrStarting) {
		return store.Room{}, nil, err
	}
	room, ok, rerr := a.s.GetRoom(ctx, roomID)
	if rerr != nil {
		return store.Room{}, nil, rerr
	}
	if !ok {
		return store.Room{}, nil, fmt.Errorf("no chat with id %s", roomID)
	}
	if err != nil {
		return room, nil, nil // starting
	}
	if err = linked(ctx, h); err != nil {
		return store.Room{}, nil, err
	}
	return room, h, nil
}

// goesNow reports whether a new message in room can go to the network now rather than wait: the network is running
// (h), the chat's own login is logged in (connected), and nothing in the chat is waiting or being handed over ahead of
// it (Ruling C33: a message never overtakes the ones typed before it).
func (a *Actions) goesNow(ctx context.Context, h *host.Host, room store.Room) (bool, error) {
	if h == nil || !a.connected(ctx, h, room) {
		return false, nil
	}
	behind, err := a.behindWaiting(ctx, room)
	return !behind, err
}

// wake has the timer loop look again now (Wake), for a message put back to waiting with its login in.
func (a *Actions) wake() {
	if a.Wake != nil {
		a.Wake()
	}
}

// behindWaiting reports whether a message in room would go ahead of messages typed before it: the chat has messages
// waiting, or a SendWaiting run has claimed some of the chat's and is still handing them over. Another chat's run
// holds nothing up.
func (a *Actions) behindWaiting(ctx context.Context, room store.Room) (bool, error) {
	a.flushMu.Lock()
	defer a.flushMu.Unlock()
	if a.inFlight[room.ID] > 0 {
		return true, nil
	}
	return a.s.HasWaiting(ctx, room.ID)
}

// dispatch sends a new message that has passed every check, its content complete (the chat's timer included), to room,
// through h (nil while its network is starting):
//   - with hold > 0 it is held for undo send: stored queued with its source and answered at once. The window's end
//     hands it off, and it waits then if the network is down (Ruling C40).
//   - when the chat can't send now (goesNow), it is stored waiting with its source and answered at once: the timer
//     loop hands it over when the chat's login is back (SendWaiting), and Don't Send (Undo) gives back what was typed.
//   - otherwise it is stored as pending and handed to the bridge.
//
// Whichever it is, my typing in the chat stops first (stopTyping): I have sent what I was typing. Every new message
// comes through here, Send's and SendFileWith's alike, so the stop is in this one place (Ruling C8).
func (a *Actions) dispatch(ctx context.Context, h *host.Host, room store.Room, c *event.MessageEventContent, hold time.Duration, src Source) (string, error) {
	a.stopTyping(ctx, h, room)
	now := false
	if hold <= 0 {
		var err error
		if now, err = a.goesNow(ctx, h, room); err != nil {
			return "", err
		}
	}
	if now {
		return a.submit(ctx, h, room.ID, event.EventMessage, c)
	}
	raw, err := withSource(c, src)
	if err != nil {
		return "", err
	}
	at := a.now()
	e := store.Event{
		RoomID: room.ID, EventID: string(ids.RandomEventID()), Sender: string(ids.Me),
		Type: event.EventMessage.Type, Content: raw, TS: at,
	}
	if hold > 0 {
		err = a.s.Hold(ctx, e, at.Add(hold))
	} else {
		err = a.s.Wait(ctx, e) // its "event" change wakes the timer loop, which sends it as soon as it can
	}
	if err != nil {
		return "", err
	}
	return e.EventID, nil
}

// Send sends a text message to a chat and returns the ID of the stored message. The text is rendered with the
// ranges the chat keeps (richtext.Render with Features.Keeps). With ReplyTo it is a reply; with ThreadRoot a reply
// in that thread (ErrNotSupported where the chat has no threads). A chat with a disappearing timer gives the
// message its timer.
//
// With a Hold above 0 (one of HoldWindows; it needs entitlement.UndoSend) the message is held for undo send: it is
// stored as queued, with what was typed (Source), and Send answers at once. The timer loop sends it when the window
// ends (HandOff), SendHeldNow sooner, and Undo takes it back.
//
// A chat whose network is still starting, whose login isn't logged in, or that has messages waiting already, can't
// send now: the message is stored waiting, with what was typed, and Send answers at once (dispatch). It never waits
// for the login. A network that won't run this session (engine.ErrNotRunning) or isn't linked (ErrNotLinked) refuses
// it. Every check runs first, so a refused send leaves no trace.
func (a *Actions) Send(ctx context.Context, roomID, text string, o SendOptions) (string, error) {
	if err := checkText(text, o.Entities); err != nil {
		return "", err // before the chat is looked up: nothing to send is the answer whatever the chat
	}
	if err := a.checkHold(o.Hold); err != nil {
		return "", err
	}
	room, h, err := a.sendTarget(ctx, roomID)
	if err != nil {
		return "", err
	}
	// The chat's network from the store, so a send while it starts composes as one while it runs (Ruling C40).
	c, err := a.composeText(ctx, roomID, room.Network, text, o)
	if err != nil {
		return "", err
	}
	return a.dispatch(ctx, h, room, c, o.Hold, Source{Text: text, Entities: o.Entities, ReplyTo: o.ReplyTo, ThreadRoot: o.ThreadRoot})
}

// SendFile sends the file at path to a chat, as a reply to replyTo if that is not empty. It is SendFileWith with
// no thread or hold.
func (a *Actions) SendFile(ctx context.Context, roomID, path, replyTo string) (string, error) {
	return a.SendFileWith(ctx, roomID, path, SendOptions{ReplyTo: replyTo})
}

// SendFileWith sends the file at path to a chat with options o, as Send does a text (o.Entities are ignored), and
// waits as Send does while the chat can't send. The kind of message (image, video, audio or plain file) comes from
// the file's contents and extension. A file over MaxFileBytes is refused before anything is read or stored.
func (a *Actions) SendFileWith(ctx context.Context, roomID, path string, o SendOptions) (string, error) {
	if a.m == nil {
		return "", errors.New("no media store: cannot send files")
	}
	if err := a.checkHold(o.Hold); err != nil {
		return "", err
	}
	room, h, err := a.sendTarget(ctx, roomID)
	if err != nil {
		return "", err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	fi, err := f.Stat()
	if err != nil {
		return "", err
	}
	if !fi.Mode().IsRegular() {
		return "", fmt.Errorf("%s is not a regular file", path)
	}
	if fi.Size() > a.maxFile {
		return "", ErrTooLarge
	}
	name := filepath.Base(path)
	// The name is the message body, and a body starting with the prefix is run as a command.
	if err = refuseBridgeCommand(room.Network, name, "a file named"); err != nil {
		return "", err
	}
	feats, err := a.Features(ctx, roomID)
	if err != nil {
		return "", err
	}
	rel, err := a.relation(ctx, roomID, feats, o)
	if err != nil {
		return "", err
	}
	head := make([]byte, 512)
	n, err := io.ReadFull(f, head)
	if err != nil && !errors.Is(err, io.EOF) && !errors.Is(err, io.ErrUnexpectedEOF) {
		return "", err
	}
	mimeType, msgType := detect(head[:n], filepath.Ext(name))
	info := &event.FileInfo{MimeType: mimeType}
	if msgType == event.MsgImage {
		if _, err = f.Seek(0, io.SeekStart); err != nil {
			return "", err
		}
		if meta, ierr := media.InspectImage(f); ierr == nil {
			info.Width, info.Height = meta.Width, meta.Height
			info.Blurhash, info.AnoaBlurhash = meta.BlurHash, meta.BlurHash
			info.IsAnimated = meta.IsAnimated
			if mimeType == "image/gif" {
				info.MauGIF = true
			}
		} else if _, err = f.Seek(0, io.SeekStart); err == nil {
			if cfg, _, derr := image.DecodeConfig(f); derr == nil { // a picture we cannot measure is still sent
				info.Width, info.Height = cfg.Width, cfg.Height
			}
		}
	}
	if _, err = f.Seek(0, io.SeekStart); err != nil {
		return "", err
	}
	var size int64
	hash, err := a.m.PutStream(func(w io.Writer) error {
		// One byte past the cap tells a file that grew after we looked from one that fits.
		var cerr error
		size, cerr = io.Copy(w, io.LimitReader(f, a.maxFile+1))
		if cerr == nil && size > a.maxFile {
			return ErrTooLarge
		}
		return cerr
	})
	if err != nil {
		return "", err
	}
	info.Size = int(size)
	timer, err := a.chatTimer(ctx, roomID)
	if err != nil {
		return "", err
	}
	return a.dispatch(ctx, h, room, &event.MessageEventContent{
		MsgType: msgType, Body: name, FileName: name, URL: ids.ContentURI(hash), Info: info, RelatesTo: rel,
		BeeperDisappearingTimer: timer,
	}, o.Hold, Source{Entities: []richtext.Entity{}, ReplyTo: o.ReplyTo, ThreadRoot: o.ThreadRoot})
}

// React reacts to a message in a chat with key (an emoji). The message must be one the bridge knows: a message
// that is itself still pending, say, makes the bridge refuse, and the reaction's row becomes failed.
//
// Reacting is idempotent: if I already have a reaction with this key on this message that has not failed, its ID
// comes back and nothing is stored or sent. A failed (or discarded) reaction does not count, so it can be sent
// again.
func (a *Actions) React(ctx context.Context, roomID, targetEventID, key string) (string, error) {
	if strings.TrimSpace(key) == "" {
		return "", errors.New("a reaction needs an emoji")
	}
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	if err = a.target(ctx, roomID, targetEventID, "react to"); err != nil {
		return "", err
	}
	if existing, ok, err := a.s.FindReaction(ctx, roomID, string(ids.Me), targetEventID, key); err != nil || ok {
		return existing, err
	}
	if err = a.waitLogin(ctx, h, roomID); err != nil {
		return "", err
	}
	// The wait can be long, so another React for the same reaction may have got in. Look again, and store the
	// row, under the lock: of two at once only one stores it. Handing it to the bridge waits for the network, so
	// that happens after the lock is let go.
	a.mu.Lock()
	existing, ok, err := a.s.FindReaction(ctx, roomID, string(ids.Me), targetEventID, key)
	if err != nil || ok {
		a.mu.Unlock()
		return existing, err
	}
	evt, err := a.stage(ctx, roomID, event.EventReaction, &event.ReactionEventContent{
		RelatesTo: event.RelatesTo{Type: event.RelAnnotation, EventID: id.EventID(targetEventID), Key: key},
	})
	a.mu.Unlock()
	if err != nil {
		return "", err
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return string(evt.ID), nil
}

// MarkRead marks a chat read up to its newest message (not a reaction, an edit or other event after it). This
// device's unread count clears first, so it clears even if the network cannot be told. Then a read receipt for
// that message goes to the network, unless this device had already read up to it: asking twice tells the
// network once. The receipt is best effort: the bridge drops it if the network is not logged in yet or takes no
// receipts, and reading is no reason to wait for a login.
//
// Reading a chat also clears its "marked unread" and ends a reminder that has fired (one still to come is left
// alone), both on this Mac only: like SetMarkedUnread, no network is told of the mark (see SyncsOf).
//
// The receipt is handled in line by the chat's bridge, so MarkRead can wait behind a send that is still in
// flight in the same chat. Callers run each request on its own goroutine.
//
// While the chat's network is still starting (MarkRead then returns engine.ErrStarting, the chat read here) or its
// login isn't logged in, the receipt is kept and told once it is (retell), the newest one only.
func (a *Actions) MarkRead(ctx context.Context, roomID string) error {
	last, hasMessage, err := a.s.LastMessage(ctx, roomID)
	if err != nil {
		return err
	}
	moved := false
	if hasMessage {
		if moved, err = a.s.AdvanceReadLocal(ctx, roomID, last.EventID, last.TS); err != nil {
			return err
		}
	}
	if _, err = a.s.SetMarkedUnread(ctx, []string{roomID}, false); err != nil {
		return err
	}
	if err = a.s.ClearFiredReminder(ctx, roomID); err != nil {
		return err
	}
	room, h, err := a.chatHost(ctx, roomID)
	if err != nil {
		return err
	}
	var herr error // why the network can't be told, for the caller: engine.ErrStarting or ErrNotRunning
	if h == nil {
		_, herr = a.eng.HostForRoom(ctx, roomID)
	}
	if !moved {
		return herr // no message, or already read up to it
	}
	receipt := event.ReceiptEventContent{}
	receipt.Set(id.EventID(last.EventID), event.ReceiptTypeRead, ids.Me, event.ReadReceipt{Timestamp: last.TS})
	// An ephemeral event with no sender or ID, the way bridgev2 receives a receipt from a Matrix server.
	a.tellChange(ctx, room, h, "read", untoldKey{room: roomID, change: "read"}, takesReceipts, &event.Event{
		Type: event.EphemeralEventReceipt, RoomID: id.RoomID(roomID),
		Content: event.Content{Parsed: &receipt},
		Mautrix: event.MautrixInfo{EventSource: event.SourceEphemeral},
	})
	return herr
}

// takesReceipts reports whether a network client takes read receipts.
func takesReceipts(c bridgev2.NetworkAPI) bool {
	_, ok := c.(bridgev2.ReadReceiptHandlingNetworkAPI)
	return ok
}

// failedEvent loads a message and checks it is failed. The caller holds a.mu.
func (a *Actions) failedEvent(ctx context.Context, eventID string) (store.Event, error) {
	e, ok, err := a.s.GetEvent(ctx, eventID)
	if err != nil {
		return store.Event{}, err
	}
	if !ok {
		return store.Event{}, fmt.Errorf("no message %s", eventID)
	}
	if e.Status != "failed" {
		return store.Event{}, ErrNotFailed
	}
	return e, nil
}

// Retry sends a failed message again, as the same message: its row goes back to pending and the bridge is given
// the event again. Anything that is not failed is left alone and gives ErrNotFailed.
//
// A message (m.room.message) retried while its chat can't send now (goesNow: the network starting, its login down,
// messages waiting ahead of it) waits like a new one: it becomes waiting (store.WaitFailed) and goes when the login is
// back, in its own place. Anything else (a reaction) waits up to LoginWait for the login, as before, and is refused
// with ErrNotConnected, still failed, if it doesn't come.
//
// A failure is not always a certain one (a handler that timed out may still have delivered), so retrying after an
// uncertain failure can deliver the message twice.
func (a *Actions) Retry(ctx context.Context, eventID string) error {
	a.mu.Lock()
	e, err := a.failedEvent(ctx, eventID)
	a.mu.Unlock()
	if err != nil {
		return err
	}
	evt, err := storedEvent(e)
	if err != nil {
		return err
	}
	var h *host.Host
	now, in := true, false
	if e.Type == event.EventMessage.Type {
		var room store.Room
		if room, h, err = a.sendTarget(ctx, e.RoomID); err != nil {
			return err
		}
		if now, err = a.goesNow(ctx, h, room); err != nil {
			return err
		}
		in = h != nil && a.connected(ctx, h, room)
	} else {
		if h, err = a.eng.HostForRoom(ctx, e.RoomID); err != nil {
			return err
		}
		// Wait first, with the row still failed, so a retry that cannot go out changes nothing.
		if err = a.waitLogin(ctx, h, e.RoomID); err != nil {
			return err
		}
	}
	// Check again under the lock: of two retries at once, only one gets to change the row.
	a.mu.Lock()
	if _, err = a.failedEvent(ctx, eventID); err == nil {
		if now {
			err = a.s.SetStatus(ctx, eventID, "pending", "")
		} else if ok, werr := a.s.WaitFailed(ctx, eventID); werr != nil {
			err = werr
		} else if !ok {
			err = ErrNotFailed
		}
	}
	a.mu.Unlock()
	if err != nil {
		return err
	}
	if !now {
		if in {
			a.wake() // behind the chat's waiting messages, its login in: the loop's next run sends it
		}
		return nil
	}
	h.Bridge.QueueMatrixEvent(ctx, evt)
	return nil
}

// storedEvent is a stored message of mine as the bridge takes it, its content read from what was stored. A
// composer's source (store.SourceKey) never goes with it, though every claim has already dropped it.
func storedEvent(e store.Event) (*event.Event, error) {
	evt := &event.Event{
		Type: event.NewEventType(e.Type), RoomID: id.RoomID(e.RoomID), Sender: ids.Me,
		ID: id.EventID(e.EventID), Timestamp: e.TS.UnixMilli(),
	}
	content := e.Content
	var m map[string]json.RawMessage
	if json.Unmarshal(content, &m) == nil {
		if _, ok := m[store.SourceKey]; ok {
			delete(m, store.SourceKey)
			if b, err := json.Marshal(m); err == nil {
				content = b
			}
		}
	}
	if err := json.Unmarshal(content, &evt.Content); err != nil {
		return nil, fmt.Errorf("stored message %s is unreadable: %w", e.EventID, err)
	}
	if err := evt.Content.ParseRaw(evt.Type); err != nil {
		return nil, fmt.Errorf("stored message %s is unreadable: %w", e.EventID, err)
	}
	return evt, nil
}

// Discard deletes a failed message from this device. Anything that is not failed is left alone and gives
// ErrNotFailed.
func (a *Actions) Discard(ctx context.Context, eventID string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, err := a.failedEvent(ctx, eventID); err != nil {
		return err
	}
	return a.s.DeleteEvent(ctx, eventID)
}

// detect names a file's content type and the kind of message to send it as. The first bytes of the file say
// what it is; the extension only fills in when they say nothing useful.
func detect(head []byte, ext string) (mimeType string, msgType event.MessageType) {
	return pickType(http.DetectContentType(head), mime.TypeByExtension(ext))
}

// pickType decides between what the file's bytes look like (sniffed) and what its extension suggests (byExt).
// Either may be empty or carry parameters ("text/plain; charset=utf-8"); the result has none.
func pickType(sniffed, byExt string) (mimeType string, msgType event.MessageType) {
	s, e := baseType(sniffed), baseType(byExt)
	switch {
	case s == "" || s == "application/octet-stream":
		if e != "" {
			s = e
		} else {
			s = "application/octet-stream"
		}
	case s == "text/plain" && strings.HasPrefix(e, "text/"):
		s = e // a CSV sniffs as plain text; the extension knows better
	case (s == "video/mp4" || s == "video/webm" || s == "application/ogg") &&
		(strings.HasPrefix(e, "audio/") || strings.HasPrefix(e, "video/")):
		s = e // one container holds both sound and video; the extension says which this is
	}
	switch {
	case strings.HasPrefix(s, "image/"):
		return s, event.MsgImage
	case strings.HasPrefix(s, "video/"):
		return s, event.MsgVideo
	case strings.HasPrefix(s, "audio/"):
		return s, event.MsgAudio
	}
	return s, event.MsgFile
}

// baseType is a content type without its parameters, in lower case. "" for anything unparseable.
func baseType(v string) string {
	if v == "" {
		return ""
	}
	base, _, err := mime.ParseMediaType(v)
	if err != nil {
		return ""
	}
	return base
}
