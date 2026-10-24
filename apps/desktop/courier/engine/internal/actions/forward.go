// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"

	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// MaxForwardRooms is how many chats one Forward sends to.
const MaxForwardRooms = 20

// ForwardResult is what Forward did in each chat: the ID of the copy sent there, or why it wasn't.
type ForwardResult struct {
	Sent   map[string]string // room ID → event ID of the copy
	Failed map[string]error  // room ID → why nothing was sent there
}

// mentionLinkRE matches a mention link in a message's HTML (a matrix.to or matrix: user link) and captures its text.
// A link's text holds no other link (richtext and the HTML the bridges write never nest them).
var mentionLinkRE = regexp.MustCompile(`(?is)<a\s+href\s*=\s*["'](?:https://matrix\.to/#/(?:@|%40)|matrix:u/)[^"']*["']\s*>(.*?)</a>`)

// forwardable is the content a copy of message e carries: the message as it reads now (its newest live edit), with
// nothing that belongs to the original: no reply or thread, no mentions (a mention link becomes its text), no
// disappearing timer and no other com.beeper.* key. A sticker goes as an image. Anything else, a poll included, is
// ErrNotSupported.
func (a *Actions) forwardable(ctx context.Context, e store.Event) (*event.MessageEventContent, error) {
	var src event.MessageEventContent
	if err := json.Unmarshal(e.Content, &src); err != nil {
		return nil, ErrNotSupported
	}
	c := &event.MessageEventContent{MsgType: src.MsgType, Body: src.Body}
	switch {
	case e.Type == event.EventSticker.Type:
		c.MsgType = event.MsgImage
	case e.Type != event.EventMessage.Type:
		return nil, ErrNotSupported
	}
	switch c.MsgType {
	case event.MsgText, event.MsgNotice, event.MsgEmote:
		if _, isEdit := messageShape(e.Content); isEdit {
			return nil, ErrNotSupported
		}
		// The newest version, without a reply's fallback (EditHistory reads it as the timeline shows it).
		versions, err := a.s.EditHistory(ctx, e.EventID)
		if err != nil {
			return nil, err
		}
		v := versions[len(versions)-1]
		c.Body = v.Body
		if v.FormattedBody != "" {
			c.Format, c.FormattedBody = event.FormatHTML, mentionLinkRE.ReplaceAllString(v.FormattedBody, "$1")
		}
	case event.MsgImage, event.MsgVideo, event.MsgAudio, event.MsgFile:
		c.URL, c.Info, c.File, c.FileName = src.URL, src.Info, src.File, src.FileName
		c.MSC1767Audio, c.MSC3245Voice = src.MSC1767Audio, src.MSC3245Voice
		if src.Format == event.FormatHTML && src.FormattedBody != "" { // a caption
			c.Format, c.FormattedBody = event.FormatHTML, mentionLinkRE.ReplaceAllString(src.FormattedBody, "$1")
		}
	default:
		return nil, ErrNotSupported
	}
	return c, nil
}

// Forward sends a copy of a message to each of roomIDs (at most MaxForwardRooms; more is ErrBadValue for every one),
// one at a time, as Send sends one without a hold: Courier's copy carries no attribution, on every network. Text,
// notices, emotes, images, videos, audio and files are forwarded, a sticker as an image; anything else, a poll
// included, fails in every chat with ErrNotSupported, as do a deleted message and a timer-change note. Each chat's copy gets that chat's
// disappearing timer, and loses its formatting where the chat keeps none. A chat whose network isn't connected
// right now (linked but reconnecting) fails at once with ErrNotConnected, as a chat change does (bestEffort): Forward
// never waits LoginWait for each chat in turn, which across many chats would outlast any answer the app waits for.
func (a *Actions) Forward(ctx context.Context, eventID string, roomIDs []string) ForwardResult {
	res := ForwardResult{Sent: map[string]string{}, Failed: map[string]error{}}
	failAll := func(err error) ForwardResult {
		for _, r := range roomIDs {
			res.Failed[r] = err
		}
		return res
	}
	if len(roomIDs) > MaxForwardRooms {
		return failAll(ErrBadValue)
	}
	e, redacted, err := a.message(ctx, eventID)
	if err != nil {
		return failAll(err)
	}
	if redacted {
		return failAll(ErrNotSupported)
	}
	content, err := a.forwardable(ctx, e)
	if err != nil {
		return failAll(err)
	}
	for _, roomID := range roomIDs {
		if _, done := res.Sent[roomID]; done {
			continue // named twice: one copy
		}
		c := *content
		if id, err := a.sendCopy(ctx, roomID, &c); err != nil {
			res.Failed[roomID] = err
		} else {
			res.Sent[roomID] = id
		}
	}
	return res
}

// sendCopy sends forwarded content c to roomID through Send's path, without a hold.
func (a *Actions) sendCopy(ctx context.Context, roomID string, c *event.MessageEventContent) (string, error) {
	if len(c.Body) > MaxTextBytes {
		return "", ErrTooLong
	}
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return "", err
	}
	if len(f.Formatting) == 0 {
		c.Format, c.FormattedBody = "", "" // a chat that keeps no formatting gets the plain body only
	}
	if err = refuseBridgeCommand(h.Network, c.Body, "a message"); err != nil {
		return "", err
	}
	if c.BeeperDisappearingTimer, err = a.chatTimer(ctx, roomID); err != nil {
		return "", err
	}
	// Connected now or not at all, and never left waiting (Ruling C11): a zero wait checks the logins once
	// (ErrNotLinked, ErrNotConnected), and a chat whose own login is down, or that has messages waiting, is
	// ErrNotConnected too, so a forward to many chats never leaves a pile of silent waiting copies.
	if err = WaitForLogin(ctx, h, 0); err != nil {
		return "", err
	}
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return "", err
	}
	if !ok {
		return "", store.ErrNotFound
	}
	if now, err := a.goesNow(ctx, h, room); err != nil {
		return "", err
	} else if !now {
		return "", fmt.Errorf("%s: %w — nothing was sent", h.Network, ErrNotConnected)
	}
	// Straight to the bridge, not through dispatch, whose own look could store it waiting after all.
	return a.submit(ctx, h, room.ID, event.EventMessage, c)
}
