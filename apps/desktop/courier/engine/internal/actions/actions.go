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
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
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
)

// Actions sends things on the user's behalf. Safe for concurrent use.
type Actions struct {
	// LoginWait bounds how long an action waits for a linked network to log in. New sets DefaultLoginWait.
	LoginWait time.Duration

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

// stage stores an outgoing event as pending, ready to be handed to the bridge with h.Bridge.QueueMatrixEvent.
// Callers have done every check that could refuse it, so a refused action leaves no trace.
func (a *Actions) stage(ctx context.Context, roomID string, typ event.Type, parsed any) (*event.Event, error) {
	now := time.Now()
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
// stored message.
func (a *Actions) SendText(ctx context.Context, roomID, text, replyTo string) (string, error) {
	if strings.TrimSpace(text) == "" {
		return "", ErrEmpty
	}
	// Never the first host or any other fallback: a message must go out through the chat's own network.
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	if err = refuseBridgeCommand(h.Network, text, "text"); err != nil {
		return "", err
	}
	if replyTo != "" {
		if err = a.target(ctx, roomID, replyTo, "reply to"); err != nil {
			return "", err
		}
	}
	// Wait before storing or queueing anything, so a refused send leaves no trace.
	if err = WaitForLogin(ctx, h, a.LoginWait); err != nil {
		return "", err
	}
	return a.submit(ctx, h, roomID, event.EventMessage, &event.MessageEventContent{
		MsgType: event.MsgText, Body: text, RelatesTo: replyRelation(replyTo),
	})
}

// SendFile sends the file at path to a chat, as a reply to replyTo if that is not empty. The kind of message
// (image, video, audio or plain file) comes from the file's contents and extension. A file over MaxFileBytes is
// refused before anything is read or stored.
func (a *Actions) SendFile(ctx context.Context, roomID, path, replyTo string) (string, error) {
	if a.m == nil {
		return "", errors.New("no media store: cannot send files")
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
	if replyTo != "" {
		if err = a.target(ctx, roomID, replyTo, "reply to"); err != nil {
			return "", err
		}
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
	return a.submit(ctx, h, roomID, event.EventMessage, &event.MessageEventContent{
		MsgType: msgType, Body: name, FileName: name, URL: ids.ContentURI(hash), Info: info,
		RelatesTo: replyRelation(replyTo),
	})
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
// alone), both here first. A chat that was marked unread is then marked read on a network that takes unread
// marks, the same best-effort way as SetMarkedUnread.
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
	wasMarked, err := a.s.SetMarkedUnread(ctx, []string{roomID}, false)
	if err != nil {
		return err
	}
	if err = a.s.ClearFiredReminder(ctx, roomID); err != nil {
		return err
	}
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return err
	}
	if len(wasMarked) > 0 {
		a.tell(ctx, h, roomID, syncUnread, event.AccountDataMarkedUnread, &event.MarkedUnreadEventContent{Unread: false})
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
	evt := &event.Event{
		Type: event.NewEventType(e.Type), RoomID: id.RoomID(e.RoomID), Sender: ids.Me,
		ID: id.EventID(e.EventID), Timestamp: e.TS.UnixMilli(),
	}
	if err = json.Unmarshal(e.Content, &evt.Content); err != nil {
		return fmt.Errorf("stored message %s is unreadable: %w", eventID, err)
	}
	if err = evt.Content.ParseRaw(evt.Type); err != nil {
		return fmt.Errorf("stored message %s is unreadable: %w", eventID, err)
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
