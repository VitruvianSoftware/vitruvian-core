// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package actions is what a person can do in a chat: reply, react, send a file, mark it read, and retry or
// discard a message that failed. Each action goes out through the bridge of the network the chat belongs to.
//
// An outgoing message is stored as "pending" first and then handed to the bridge, which reports back through the
// store ("sent" or "failed"). The send actions return once the bridge has handled the event, so the row is
// usually settled by then, but a network may answer later: callers follow the change feed, not the return.
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
	// ErrNotConnected means a linked network did not become logged in in time. Nothing was sent.
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

// ReasonNotConnected is the status_reason of a held or scheduled message HandOff couldn't hand to its network: the
// network wasn't running, or didn't log in within LoginWait. Nothing was sent; the app offers Retry.
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

// WaitForLogin waits until at least one of the local user's logins on this network reports it is logged in.
// The bridge's Start only connects the logins: the connection counts as logged in a moment later, when the
// server's success message arrives. A message queued before then is refused as "not logged in" and marked
// failed. A network with no login at all is not going to get one by waiting, so that fails at once.
func WaitForLogin(ctx context.Context, h *host.Host, timeout time.Duration) error {
	me, err := h.Me(ctx)
	if err != nil {
		return err
	}
	if len(me.GetUserLogins()) == 0 {
		return fmt.Errorf("%s %w — run link --network %s first", h.Network, ErrNotLinked, h.Network)
	}
	deadline := time.After(timeout)
	for {
		for _, login := range me.GetUserLogins() {
			if login.Client != nil && login.Client.IsLoggedIn() {
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("%s: %w — nothing was sent", h.Network, ErrNotConnected)
		case <-deadline:
			return fmt.Errorf("%s: %w — nothing was sent", h.Network, ErrNotConnected)
		case <-time.After(200 * time.Millisecond):
		}
	}
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

// newestInThread is the newest reply of a thread that the network has (not failed, held or still pending), or the
// root when there is none.
func (a *Actions) newestInThread(ctx context.Context, roomID, root string) (string, error) {
	replies, _, err := a.s.ThreadEventsBefore(ctx, roomID, root, nil, 20)
	if err != nil {
		return "", err
	}
	for _, e := range replies {
		switch e.Status {
		case "failed", "queued", "pending":
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

// dispatch sends a new message that has passed every check: it waits for the network to log in, gives it the
// chat's disappearing timer, and then either holds it for undo send (hold > 0: stored as queued with its source,
// answered at once) or stores it as pending and hands it to the bridge.
func (a *Actions) dispatch(ctx context.Context, h *host.Host, roomID string, c *event.MessageEventContent, hold time.Duration, src Source) (string, error) {
	// Wait before storing or queueing anything, so a refused send leaves no trace.
	if err := WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
	}
	timer, err := a.chatTimer(ctx, roomID)
	if err != nil {
		return "", err
	}
	c.BeeperDisappearingTimer = timer
	if hold <= 0 {
		return a.submit(ctx, h, roomID, event.EventMessage, c)
	}
	raw, err := withSource(c, src)
	if err != nil {
		return "", err
	}
	now := a.now()
	e := store.Event{
		RoomID: roomID, EventID: string(ids.RandomEventID()), Sender: string(ids.Me),
		Type: event.EventMessage.Type, Content: raw, TS: now,
	}
	if err = a.s.Hold(ctx, e, now.Add(hold)); err != nil {
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
// ends (HandOff), SendHeldNow sooner, and Undo takes it back. Every check, the login wait included, runs first, so a
// refused send leaves no trace.
func (a *Actions) Send(ctx context.Context, roomID, text string, o SendOptions) (string, error) {
	if err := checkText(text, o.Entities); err != nil {
		return "", err
	}
	if err := a.checkHold(o.Hold); err != nil {
		return "", err
	}
	// Never the first host or any other fallback: a message must go out through the chat's own network.
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return "", err
	}
	c := textContent(f, text, o.Entities)
	if err = refuseBridgeCommand(h.Network, c.Body, "text"); err != nil {
		return "", err
	}
	if c.RelatesTo, err = a.relation(ctx, roomID, f, o); err != nil {
		return "", err
	}
	return a.dispatch(ctx, h, roomID, c, o.Hold, Source{Text: text, Entities: o.Entities, ReplyTo: o.ReplyTo, ThreadRoot: o.ThreadRoot})
}

// SendFile sends the file at path to a chat, as a reply to replyTo if that is not empty. It is SendFileWith with
// no thread or hold.
func (a *Actions) SendFile(ctx context.Context, roomID, path, replyTo string) (string, error) {
	return a.SendFileWith(ctx, roomID, path, SendOptions{ReplyTo: replyTo})
}

// SendFileWith sends the file at path to a chat with options o, as Send does a text (o.Entities are ignored). The
// kind of message (image, video, audio or plain file) comes from the file's contents and extension. A file over
// MaxFileBytes is refused before anything is read or stored.
func (a *Actions) SendFileWith(ctx context.Context, roomID, path string, o SendOptions) (string, error) {
	if a.m == nil {
		return "", errors.New("no media store: cannot send files")
	}
	if err := a.checkHold(o.Hold); err != nil {
		return "", err
	}
	h, err := a.eng.HostForRoom(ctx, roomID)
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
	if err = refuseBridgeCommand(h.Network, name, "a file named"); err != nil {
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
		if cfg, _, derr := image.DecodeConfig(f); derr == nil { // a picture we cannot measure is still sent
			info.Width, info.Height = cfg.Width, cfg.Height
		}
	}
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
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
	return a.dispatch(ctx, h, roomID, &event.MessageEventContent{
		MsgType: msgType, Body: name, FileName: name, URL: ids.ContentURI(hash), Info: info, RelatesTo: rel,
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
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
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
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if !moved {
		return nil // no message, or already read up to it
	}
	receipt := event.ReceiptEventContent{}
	receipt.Set(id.EventID(last.EventID), event.ReceiptTypeRead, ids.Me, event.ReadReceipt{Timestamp: last.TS})
	// An ephemeral event with no sender or ID, the way bridgev2 receives a receipt from a Matrix server.
	h.Bridge.QueueMatrixEvent(ctx, &event.Event{
		Type: event.EphemeralEventReceipt, RoomID: id.RoomID(roomID),
		Content: event.Content{Parsed: &receipt},
		Mautrix: event.MautrixInfo{EventSource: event.SourceEphemeral},
	})
	return nil
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
// A failure is not always a certain one (a handler that timed out may still have delivered), so retrying after an
// uncertain failure can deliver the message twice.
func (a *Actions) Retry(ctx context.Context, eventID string) error {
	a.mu.Lock()
	e, err := a.failedEvent(ctx, eventID)
	a.mu.Unlock()
	if err != nil {
		return err
	}
	h, err := a.eng.HostForRoom(ctx, e.RoomID)
	if err != nil {
		return err
	}
	// Wait first, with the row still failed, so a retry that cannot go out changes nothing.
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return err
	}
	evt, err := storedEvent(e)
	if err != nil {
		return err
	}
	// Check again under the lock: of two retries at once, only one gets to put the row back to pending.
	a.mu.Lock()
	if _, err = a.failedEvent(ctx, eventID); err == nil {
		err = a.s.SetStatus(ctx, eventID, "pending", "")
	}
	a.mu.Unlock()
	if err != nil {
		return err
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
