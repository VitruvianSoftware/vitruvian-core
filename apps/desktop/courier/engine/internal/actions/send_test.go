// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// testClock is an injected clock a test moves by hand.
type testClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *testClock) Set(t time.Time) {
	c.mu.Lock()
	c.t = t
	c.mu.Unlock()
}

// clocked gives the world's store (and so its actions) a clock fixed at the wall time now, which the test moves.
func (w world) clocked() *testClock {
	c := &testClock{t: time.UnixMilli(time.Now().UnixMilli())}
	w.s.SetClock(c.Now)
	return c
}

func anyFiles() event.FileFeatureMap {
	anyFile := func() *event.FileFeatures {
		return &event.FileFeatures{MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported}}
	}
	return event.FileFeatureMap{event.MsgImage: anyFile(), event.MsgVideo: anyFile(), event.MsgAudio: anyFile(), event.MsgFile: anyFile()}
}

func allFormatting() event.FormattingFeatureMap {
	m := event.FormattingFeatureMap{}
	for _, f := range formattingKinds {
		m[f.feature] = event.CapLevelFullySupported
	}
	return m
}

// slackFeatures is a chat like Slack's: every formatting and @room, threads and no plain replies, edits and unsends.
func slackFeatures() *event.RoomFeatures {
	f := allFormatting()
	f[event.FmtSpoiler] = event.CapLevelUnsupported
	f[event.FmtAtRoomMention] = event.CapLevelFullySupported
	return &event.RoomFeatures{
		Formatting: f, Thread: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Edit: event.CapLevelFullySupported, Delete: event.CapLevelFullySupported, File: anyFiles(),
	}
}

// whatsappFeatures is a chat like WhatsApp's: formatting without spoilers or @room, replies, edits for 15 minutes,
// unsends for 2 days, polls of 12 options of 100 characters, after-send timers of 1, 7 and 90 days.
func whatsappFeatures() *event.RoomFeatures {
	f := allFormatting()
	f[event.FmtSpoiler] = event.CapLevelUnsupported
	return &event.RoomFeatures{
		Formatting: f, Reply: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Edit: event.CapLevelFullySupported, EditMaxAge: seconds(15 * time.Minute),
		Delete: event.CapLevelFullySupported, DeleteMaxAge: seconds(48 * time.Hour),
		Poll: event.CapLevelFullySupported, PollMaxOptions: 12, PollOptionMaxLength: 100,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types: []event.DisappearingType{event.DisappearingTypeAfterSend},
			Timers: []jsontime.Milliseconds{
				jsontime.MS(24 * time.Hour), jsontime.MS(7 * 24 * time.Hour), jsontime.MS(90 * 24 * time.Hour),
			},
		},
		File: anyFiles(),
	}
}

// googleMessagesFeatures is a chat like Google Messages': no formatting, replies, and a deletion that reaches only
// the phone (delete_for_me).
func googleMessagesFeatures() *event.RoomFeatures {
	return &event.RoomFeatures{
		Reply: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Delete: event.CapLevelFullySupported, DeleteForMe: true, File: anyFiles(),
	}
}

// content reads a stored event's content as a map.
func content(t *testing.T, e store.Event) map[string]any {
	t.Helper()
	var m map[string]any
	require.NoError(t, json.Unmarshal(e.Content, &m))
	return m
}

// eventCount is how many events the store has in room, of any kind.
func (w world) eventCount(t *testing.T, room string) int {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1000)
	require.NoError(t, err)
	return len(evs)
}

// mySent sends text and waits for the network to take it.
func (w world) mySent(t *testing.T, room, text string) string {
	t.Helper()
	id, err := w.a.SendText(context.Background(), room, text, "")
	require.NoError(t, err)
	recv(t, w.n.Sent, "the message")
	w.waitStatus(t, id, "sent")
	return id
}

func TestSendRendersForTheChatsFeatures(t *testing.T) {
	ctx := context.Background()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 2}}
	everyone := []richtext.Entity{{Kind: richtext.Mention, Offset: 8, Length: 5, UserID: richtext.RoomMention}}

	// Slack keeps bold, and @room reaches everyone.
	w, room := startFeatureWorld(t, slackFeatures())
	id, err := w.a.Send(ctx, room, "hi there", SendOptions{Entities: bold})
	require.NoError(t, err)
	c := content(t, w.get(t, id))
	require.Equal(t, "hi there", c["body"])
	require.Equal(t, "org.matrix.custom.html", c["format"])
	require.Equal(t, "<strong>hi</strong> there", c["formatted_body"])
	require.NotContains(t, c, "m.mentions", "nobody named")
	require.Equal(t, "hi there", recv(t, w.n.Sent, "the message").Body)
	id, err = w.a.Send(ctx, room, "heads up @room", SendOptions{Entities: everyone})
	require.NoError(t, err)
	require.Equal(t, map[string]any{"room": true}, content(t, w.get(t, id))["m.mentions"])
	recv(t, w.n.Sent, "the @room message")

	// WhatsApp keeps mentions but not @room: it is plain text there and mentions nobody.
	w, room = startFeatureWorld(t, whatsappFeatures())
	id, err = w.a.Send(ctx, room, "heads up @room", SendOptions{Entities: everyone})
	require.NoError(t, err)
	c = content(t, w.get(t, id))
	require.NotContains(t, c, "m.mentions")
	require.NotContains(t, c, "formatted_body")
	recv(t, w.n.Sent, "the message")

	// A chat that keeps no formatting gets the body only.
	w, room = startFeatureWorld(t, googleMessagesFeatures())
	id, err = w.a.Send(ctx, room, "hi there", SendOptions{Entities: bold})
	require.NoError(t, err)
	c = content(t, w.get(t, id))
	require.Equal(t, map[string]any{"msgtype": "m.text", "body": "hi there"}, c)
	require.Equal(t, "hi there", recv(t, w.n.Sent, "the message").Body)

	// Ranges that don't fit the text are refused, and leave no trace.
	before := w.eventCount(t, room)
	_, err = w.a.Send(ctx, room, "hi", SendOptions{Entities: []richtext.Entity{{Kind: richtext.Bold, Offset: 1, Length: 9}}})
	require.ErrorIs(t, err, ErrBadValue)
	require.ErrorIs(t, err, richtext.ErrBadEntity)
	require.Equal(t, before, w.eventCount(t, room))
}

func TestTextOverTheCapIsRefused(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	before := w.eventCount(t, room)
	_, err := w.a.Send(ctx, room, strings.Repeat("a", MaxTextBytes+1), SendOptions{})
	require.ErrorIs(t, err, ErrTooLong)
	_, err = w.a.SendText(ctx, room, strings.Repeat("é", MaxTextBytes/2+1), "") // bytes, not characters
	require.ErrorIs(t, err, ErrTooLong)
	require.Equal(t, before, w.eventCount(t, room))
	require.Empty(t, w.n.Sent)

	id, err := w.a.Send(ctx, room, strings.Repeat("a", MaxTextBytes), SendOptions{})
	require.NoError(t, err)
	require.Len(t, recv(t, w.n.Sent, "the longest message").Body, MaxTextBytes)
	w.waitStatus(t, id, "sent")
}

func TestSendIntoAThread(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, slackFeatures())
	root := w.firstID(t, room)

	// The first reply falls back to the root.
	first, err := w.a.Send(ctx, room, "first", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": root},
	}, relatesTo(t, w.get(t, first)))
	require.Equal(t, "first", recv(t, w.n.Sent, "the first reply").Body)
	w.waitStatus(t, first, "sent")

	// The next falls back to the thread's newest reply.
	second, err := w.a.Send(ctx, room, "second", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": first},
	}, relatesTo(t, w.get(t, second)))
	recv(t, w.n.Sent, "the second reply")
	w.waitStatus(t, second, "sent")

	// A newer reply the network refused isn't one to fall back to: the newest sent reply is.
	w.insertMine(t, room, "m.room.message", fmt.Sprintf(
		`{"msgtype":"m.text","body":"refused","m.relates_to":{"rel_type":"m.thread","event_id":%q,"is_falling_back":true,"m.in_reply_to":{"event_id":%q}}}`,
		root, second,
	), "failed", time.Now().Add(time.Second))
	fallback, err := w.a.Send(ctx, room, "after the refused one", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": second},
	}, relatesTo(t, w.get(t, fallback)))
	recv(t, w.n.Sent, "the reply after the refused one")

	// A reply to one message of the thread is a real reply, not a fallback.
	third, err := w.a.Send(ctx, room, "third", SendOptions{ThreadRoot: root, ReplyTo: first})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "m.in_reply_to": map[string]any{"event_id": first},
	}, relatesTo(t, w.get(t, third)))
	recv(t, w.n.Sent, "the third reply")

	page, _, err := w.s.ThreadEventsBefore(ctx, room, root, nil, 10)
	require.NoError(t, err)
	require.Len(t, page, 5, "first, second, the refused one, the one after it and third")
}

// firstID is the ID of the contact's first message in room.
func (w world) firstID(t *testing.T, room string) string {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	return evs[0].EventID
}

func TestThreadOnAChatWithoutThreadsIsRefused(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	root := w.firstID(t, room)
	_, err := w.a.Send(ctx, room, "in a thread", SendOptions{ThreadRoot: root})
	require.ErrorIs(t, err, ErrNotSupported)
	require.Equal(t, 1, w.eventCount(t, room), "nothing stored")
	require.Empty(t, w.n.Sent)
}

func TestSendCarriesTheChatsTimer(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour))
	recv(t, w.n.Timers, "the timer")

	id, err := w.a.Send(ctx, room, "gone tomorrow", SendOptions{})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, map[string]any{"type": "after_send", "timer": float64(86400000)}, content(t, e)["com.beeper.disappearing_timer"])
	require.Equal(t, e.TS.Add(24*time.Hour), e.ExpiresAt, "the store expires it itself")
	recv(t, w.n.Sent, "the message")

	// Off again: messages carry no timer.
	require.NoError(t, w.a.SetDisappearing(ctx, room, "", 0))
	recv(t, w.n.Timers, "the timer turned off")
	id, err = w.a.Send(ctx, room, "stays", SendOptions{})
	require.NoError(t, err)
	require.NotContains(t, content(t, w.get(t, id)), "com.beeper.disappearing_timer")
	require.True(t, w.get(t, id).ExpiresAt.IsZero())
	recv(t, w.n.Sent, "the message")
}

// An after-read timer (Signal) goes with the message too; it starts when the message is read, so the store sets no
// expiry of its own.
func TestSendCarriesAnAfterReadTimer(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, &event.RoomFeatures{
		Reply: event.CapLevelFullySupported,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types: []event.DisappearingType{event.DisappearingTypeAfterRead},
		},
	})
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_read", 30*time.Second))
	recv(t, w.n.Timers, "the timer")
	id, err := w.a.Send(ctx, room, "read and gone", SendOptions{})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, map[string]any{"type": "after_read", "timer": float64(30000)}, content(t, e)["com.beeper.disappearing_timer"])
	require.True(t, e.ExpiresAt.IsZero())
	recv(t, w.n.Sent, "the message")
}
