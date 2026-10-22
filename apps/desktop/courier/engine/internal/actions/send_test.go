// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
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

// deny is a plan that leaves out some features.
type deny map[entitlement.Feature]bool

func (d deny) Allowed(f entitlement.Feature) bool { return !d[f] }

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

	// A reply to one message of the thread is a real reply, not a fallback.
	third, err := w.a.Send(ctx, room, "third", SendOptions{ThreadRoot: root, ReplyTo: first})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "m.in_reply_to": map[string]any{"event_id": first},
	}, relatesTo(t, w.get(t, third)))
	recv(t, w.n.Sent, "the third reply")

	page, _, err := w.s.ThreadEventsBefore(ctx, room, root, nil, 10)
	require.NoError(t, err)
	require.Len(t, page, 3)
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

func TestHeldSendReturnsAtOnceAndStaysQueued(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 4}}

	id, err := w.a.Send(ctx, room, "held back", SendOptions{Entities: bold, Hold: 5 * time.Second})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, "queued", e.Status)
	require.Empty(t, w.n.Sent, "nothing reaches the network while it is held")
	src, ok := SourceOf(e.Content)
	require.True(t, ok)
	require.Equal(t, Source{Text: "held back", Entities: bold}, src)

	// Not due yet: nothing goes.
	clock.Set(clock.Now().Add(4 * time.Second))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Empty(t, due)
	// Due: the loop hands it off, once.
	clock.Set(clock.Now().Add(time.Second))
	due, err = w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 1)
	w.a.HandOff(ctx, due[0])
	require.Equal(t, "held back", recv(t, w.n.Sent, "the held message").Body)
	w.waitStatus(t, id, "sent")
	_, err = w.a.Undo(ctx, id)
	require.ErrorIs(t, err, ErrAlreadySent)
}

func TestHoldNeedsAWindowFromTheList(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	for _, hold := range []time.Duration{-time.Second, time.Millisecond, 4 * time.Second, time.Minute} {
		_, err := w.a.Send(ctx, room, "x", SendOptions{Hold: hold})
		require.ErrorIs(t, err, ErrBadValue, hold)
	}
	require.Equal(t, 1, w.eventCount(t, room))
	for _, hold := range HoldWindows[1:] {
		id, err := w.a.Send(ctx, room, "x", SendOptions{Hold: hold})
		require.NoError(t, err, hold)
		require.Equal(t, "queued", w.get(t, id).Status)
	}
}

func TestHoldAndScheduleNeedTheirEntitlement(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()

	// Held and scheduled while the plan had them.
	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	undone, err := w.a.Send(ctx, room, "undone", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	sc, err := w.a.Schedule(ctx, room, "later", SendOptions{}, clock.Now().Add(time.Hour), "always")
	require.NoError(t, err)

	// The plan lapses: nothing new is held or scheduled, and nothing is stored trying.
	w.a.Entitlement = deny{entitlement.UndoSend: true, entitlement.SendLater: true}
	before := w.eventCount(t, room)
	_, err = w.a.Send(ctx, room, "x", SendOptions{Hold: time.Second})
	require.ErrorIs(t, err, ErrNotEntitled)
	_, err = w.a.SendFileWith(ctx, room, "/nonexistent", SendOptions{Hold: time.Second})
	require.ErrorIs(t, err, ErrNotEntitled)
	_, err = w.a.Schedule(ctx, room, "x", SendOptions{}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrNotEntitled)
	require.Equal(t, before, w.eventCount(t, room))
	list, err := w.s.ScheduledIn(ctx, room)
	require.NoError(t, err)
	require.Len(t, list, 1)

	// What is already held or scheduled is never stranded: it can be undone, changed, and sent.
	_, err = w.a.Undo(ctx, undone)
	require.NoError(t, err)
	text := "later, changed"
	_, err = w.a.UpdateScheduled(ctx, sc.ID, nil, &text, nil, nil)
	require.NoError(t, err)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, "held", recv(t, w.n.Sent, "the held message").Body)
	w.waitStatus(t, held, "sent")
	require.NoError(t, w.a.SendScheduledNow(ctx, sc.ID))
	require.Equal(t, "later, changed", recv(t, w.n.Sent, "the scheduled message").Body)
	// And sending at once needs no plan.
	_, err = w.a.Send(ctx, room, "now", SendOptions{})
	require.NoError(t, err)
	recv(t, w.n.Sent, "the message")
}

func TestUndoGivesBackWhatWasTyped(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	reply := w.firstID(t, room)
	ents := []richtext.Entity{{Kind: richtext.Italic, Offset: 0, Length: 4}}
	id, err := w.a.Send(ctx, room, "oops, wrong chat", SendOptions{Entities: ents, ReplyTo: reply, Hold: 10 * time.Second})
	require.NoError(t, err)

	e, err := w.a.Undo(ctx, id)
	require.NoError(t, err)
	require.Equal(t, id, e.EventID)
	src, ok := SourceOf(e.Content)
	require.True(t, ok)
	require.Equal(t, Source{Text: "oops, wrong chat", Entities: ents, ReplyTo: reply}, src)
	_, found, err := w.s.GetEvent(ctx, id)
	require.NoError(t, err)
	require.False(t, found, "gone from the chat")
	_, err = w.a.Undo(ctx, id)
	require.ErrorIs(t, err, ErrAlreadySent)
	require.Empty(t, w.n.Sent)
}

func TestHandOffWhileOfflineFailsAsNotConnected(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Features = whatsappFeatures()
	n.LoginDelay = time.Hour // linked, but never logged in during the test
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())
	clock := w.clocked()
	// The bridge makes the chat even while the login isn't counted yet.
	room, _ := w.chat(t, "alice", "m1")
	w.a.LoginWait = 0

	e := store.Event{
		RoomID: room, EventID: string(ids.RandomEventID()), Sender: string(ids.Me), Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"while offline"}`), TS: clock.Now(),
	}
	require.NoError(t, w.s.Hold(ctx, e, clock.Now().Add(time.Second)))
	clock.Set(clock.Now().Add(time.Second))
	due, err := w.s.ClaimDue(ctx)
	require.NoError(t, err)
	require.Len(t, due, 1)
	w.a.HandOff(ctx, due[0])
	got := w.get(t, e.EventID)
	require.Equal(t, "failed", got.Status)
	require.Equal(t, ReasonNotConnected, got.StatusReason)
	require.Empty(t, w.n.Sent)

	// A chat whose network isn't running at all fails the same way.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!gone:courier.local", Network: "telegram"}))
	gone := store.Event{
		RoomID: "!gone:courier.local", EventID: string(ids.RandomEventID()), Sender: string(ids.Me), Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"nowhere"}`), TS: clock.Now(), Status: "pending",
	}
	_, err = w.s.InsertEvent(ctx, gone)
	require.NoError(t, err)
	w.a.HandOff(ctx, gone)
	require.Equal(t, ReasonNotConnected, w.get(t, gone.EventID).StatusReason)
}

func TestTypedSourceNeverReachesTheBridge(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 4}}
	noSource := func(what string) {
		t.Helper()
		raws := w.n.Raws()
		raw := raws[len(raws)-1]
		require.NotEmpty(t, raw, "%s reached the bridge as stored JSON", what)
		var m map[string]any
		require.NoError(t, json.Unmarshal(raw, &m))
		require.NotContains(t, m, store.SourceKey, what)
		require.Equal(t, "<strong>held</strong> back", m["formatted_body"], what)
	}

	held, err := w.a.Send(ctx, room, "held back", SendOptions{Entities: bold, Hold: 3 * time.Second})
	require.NoError(t, err)
	require.Contains(t, content(t, w.get(t, held)), store.SourceKey)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	recv(t, w.n.Sent, "the held message")
	noSource("the held message")
	require.NotContains(t, content(t, w.waitStatus(t, held, "sent")), store.SourceKey)

	sc, err := w.a.Schedule(ctx, room, "held back", SendOptions{Entities: bold}, clock.Now().Add(time.Hour), "always")
	require.NoError(t, err)
	src, ok := SourceOf(sc.Content)
	require.True(t, ok)
	require.Equal(t, "held back", src.Text)
	require.NoError(t, w.a.SendScheduledNow(ctx, sc.ID))
	recv(t, w.n.Sent, "the scheduled message")
	noSource("the scheduled message")
	require.NotContains(t, content(t, w.waitStatus(t, sc.EventID, "sent")), store.SourceKey)
}

func TestScheduleRendersAndUpdateReRenders(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, slackFeatures())
	clock := w.clocked()
	root := w.firstID(t, room)
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 5}}

	_, err := w.a.Schedule(ctx, room, "x", SendOptions{Hold: time.Second}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrBadValue, "a scheduled message isn't held as well")
	_, err = w.a.Schedule(ctx, room, "x", SendOptions{}, clock.Now().Add(-time.Minute), "")
	require.ErrorIs(t, err, ErrBadValue, "in the past")
	_, err = w.a.Schedule(ctx, room, " ", SendOptions{}, clock.Now().Add(time.Hour), "")
	require.ErrorIs(t, err, ErrEmpty)

	sc, err := w.a.Schedule(ctx, room, "later today", SendOptions{Entities: bold, ThreadRoot: root}, clock.Now().Add(time.Hour), "")
	require.NoError(t, err)
	require.Equal(t, "if_no_reply", sc.Condition)
	var c map[string]any
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "<strong>later</strong> today", c["formatted_body"])
	require.Equal(t, "m.thread", c["m.relates_to"].(map[string]any)["rel_type"])
	require.Equal(t, 1, w.eventCount(t, room), "not in the timeline until it is sent")

	// New text is rendered again, in the same thread.
	text := "later tonight"
	sc, err = w.a.UpdateScheduled(ctx, sc.ID, nil, &text, []richtext.Entity{{Kind: richtext.Italic, Offset: 6, Length: 7}}, nil)
	require.NoError(t, err)
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "later <em>tonight</em>", c["formatted_body"])
	require.Equal(t, root, c["m.relates_to"].(map[string]any)["event_id"])
	// New ranges alone keep the text.
	sc, err = w.a.UpdateScheduled(ctx, sc.ID, nil, nil, []richtext.Entity{}, nil)
	require.NoError(t, err)
	c = map[string]any{}
	require.NoError(t, json.Unmarshal(sc.Content, &c))
	require.Equal(t, "later tonight", c["body"])
	require.NotContains(t, c, "formatted_body")
	src, _ := SourceOf(sc.Content)
	require.Equal(t, Source{Text: "later tonight", Entities: []richtext.Entity{}, ThreadRoot: root}, src)
	// Only the time: the content is left as it is.
	due := clock.Now().Add(2 * time.Hour)
	moved, err := w.a.UpdateScheduled(ctx, sc.ID, &due, nil, nil, nil)
	require.NoError(t, err)
	require.JSONEq(t, string(sc.Content), string(moved.Content))
	_, err = w.a.UpdateScheduled(ctx, 9999, nil, &text, nil, nil)
	require.ErrorIs(t, err, store.ErrNotFound)
}

func TestSendFileWithAHold(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	path := writeFile(t, "notes.txt", []byte("some notes"))
	id, err := w.a.SendFileWith(ctx, room, path, SendOptions{Hold: time.Second, Entities: []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 99}}})
	require.NoError(t, err, "a file ignores ranges")
	require.Equal(t, "queued", w.get(t, id).Status)
	require.Empty(t, w.n.Files)
	require.NoError(t, w.a.SendHeldNow(ctx, room))
	require.Equal(t, "notes.txt", recv(t, w.n.Files, "the held file").FileName)
	w.waitStatus(t, id, "sent")
}
