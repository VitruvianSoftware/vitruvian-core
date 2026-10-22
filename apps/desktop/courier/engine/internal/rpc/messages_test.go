// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/timers"
)

const contact = "@whatsapp_contact:courier.local"

// everything is a chat that can do all Courier offers, as WhatsApp's features read with a thread and Slack's @room.
func everything() *event.RoomFeatures {
	full := event.CapLevelFullySupported
	return &event.RoomFeatures{
		Formatting: event.FormattingFeatureMap{
			event.FmtBold: full, event.FmtItalic: full, event.FmtStrikethrough: full, event.FmtInlineCode: full,
			event.FmtCodeBlock: full, event.FmtBlockquote: full, event.FmtUnorderedList: full, event.FmtOrderedList: full,
			event.FmtInlineLink: full, event.FmtUserLink: full, event.FmtAtRoomMention: full,
		},
		MaxTextLength: 4000, Poll: full, PollMaxOptions: 12, PollOptionMaxLength: 100,
		Reply: full, Thread: full, Edit: full, EditMaxAge: &jsontime.Seconds{Duration: 15 * time.Minute}, EditMaxCount: 10,
		Delete: full, DeleteMaxAge: &jsontime.Seconds{Duration: 48 * time.Hour}, Reaction: full,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types:  []event.DisappearingType{event.DisappearingTypeAfterSend},
			Timers: []jsontime.Milliseconds{jsontime.MS(24 * time.Hour), jsontime.MS(7 * 24 * time.Hour)},
		},
		File: event.FileFeatureMap{event.MsgFile: {MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": full}}},
	}
}

// can gives the world's chat features rf: stored as the bridge stores them, and what the network answers from now on.
func (w *world) can(t *testing.T, rf *event.RoomFeatures) {
	t.Helper()
	raw, err := json.Marshal(rf)
	require.NoError(t, err)
	_, err = w.s.SetState(context.Background(), w.room, event.StateBeeperRoomFeatures.Type, "whatsapp", raw)
	require.NoError(t, err)
	w.wa.SetFeatures(rf)
}

// put stores an event in the world's chat and returns its ID.
func (w *world) put(t *testing.T, id, sender, typ, content string, ts time.Time) string {
	t.Helper()
	_, err := w.s.InsertEvent(context.Background(), store.Event{
		RoomID: w.room, EventID: id, Sender: sender, Type: typ, Content: json.RawMessage(content), TS: ts, Status: "sent",
	})
	require.NoError(t, err)
	return id
}

func inThread(root, body string) string {
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": body,
		"m.relates_to": map[string]any{
			"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
			"m.in_reply_to": map[string]string{"event_id": root},
		},
	})
	return string(b)
}

func pollOf(question string, maxSelections int, answers ...string) string {
	var as []map[string]any
	for i, a := range answers {
		as = append(as, map[string]any{"id": fmt.Sprint(i + 1), "org.matrix.msc1767.text": a})
	}
	b, _ := json.Marshal(map[string]any{"org.matrix.msc3381.poll.start": map[string]any{
		"kind": "org.matrix.msc3381.poll.disclosed", "max_selections": maxSelections,
		"question": map[string]any{"org.matrix.msc1767.text": question}, "answers": as,
	}})
	return string(b)
}

func voteOn(poll string, answers ...string) string {
	b, _ := json.Marshal(map[string]any{
		"m.relates_to":                     map[string]any{"rel_type": "m.reference", "event_id": poll},
		"org.matrix.msc3381.poll.response": map[string]any{"answers": answers},
	})
	return string(b)
}

func reactionTo(target, key string) string {
	return fmt.Sprintf(`{"m.relates_to":{"rel_type":"m.annotation","event_id":%q,"key":%q}}`, target, key)
}

func editOf(target, body string) string {
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": "* " + body,
		"m.new_content": map[string]any{"msgtype": "m.text", "body": body},
		"m.relates_to":  map[string]any{"rel_type": "m.replace", "event_id": target},
	})
	return string(b)
}

// wireEvent is an Event as it comes off the wire, with protocol 4's fields.
type wireEvent struct {
	EventID    string          `json:"event_id"`
	Type       string          `json:"type"`
	Content    json.RawMessage `json:"content"`
	Status     string          `json:"status"`
	Bookmarked bool            `json:"bookmarked"`
	ExpiresAt  int64           `json:"expires_at"`
	Poll       *struct {
		Question string `json:"question"`
		Options  []struct {
			ID    string `json:"id"`
			Text  string `json:"text"`
			Votes int    `json:"votes"`
		} `json:"options"`
		MaxSelections int      `json:"max_selections"`
		Voters        int      `json:"voters"`
		Mine          []string `json:"mine"`
		Ended         bool     `json:"ended"`
	} `json:"poll"`
	Thread *struct {
		Replies     int      `json:"replies"`
		LastTS      int64    `json:"last_ts"`
		LastSenders []string `json:"last_senders"`
	} `json:"thread"`
}

type wirePage4 struct {
	Events []wireEvent `json:"events"`
	Before *cursor     `json:"before"`
	After  *cursor     `json:"after"`
}

func (p wirePage4) ids() []string {
	out := []string{}
	for _, e := range p.Events {
		out = append(out, e.EventID)
	}
	return out
}

func (p wirePage4) event(t *testing.T, id string) wireEvent {
	t.Helper()
	for _, e := range p.Events {
		if e.EventID == id {
			return e
		}
	}
	t.Fatalf("%s is not on the page: %v", id, p.ids())
	return wireEvent{}
}

func TestParamsValidation(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	at := map[string]any{"ts": 1760599990000, "seq": 1}
	tooMany := []string{}
	for i := range actions.MaxForwardRooms + 1 {
		tooMany = append(tooMany, fmt.Sprintf("!chat%02d:courier.local", i))
	}
	for _, tc := range []struct {
		name, method string
		params       map[string]any
		reason       string
	}{
		{
			"hold not offered", "message.send",
			map[string]any{"room_id": w.room, "text": "hi", "hold_ms": 1234},
			"hold_ms must be one of 0, 750, 1000, 2000, 3000, 5000, 10000",
		},
		{
			"file hold not offered", "message.sendFile",
			map[string]any{"room_id": w.room, "path": "/etc/hosts", "hold_ms": 4000},
			"hold_ms must be one of 0, 750, 1000, 2000, 3000, 5000, 10000",
		},
		{
			"forward to none", "message.forward",
			map[string]any{"event_id": w.events[0], "room_ids": []string{}},
			"room_ids must name 1 to 20 chats",
		},
		{
			"forward to 21", "message.forward",
			map[string]any{"event_id": w.events[0], "room_ids": tooMany},
			"room_ids must name 1 to 20 chats",
		},
		{"forward with no rooms", "message.forward", map[string]any{"event_id": w.events[0]}, "room_ids is required"},
		{
			"thread with around", "room.events",
			map[string]any{"room_id": w.room, "thread": w.events[0], "around": w.events[1]},
			"thread can't be given with around or after",
		},
		{
			"thread with after", "room.events",
			map[string]any{"room_id": w.room, "thread": w.events[0], "after": at},
			"thread can't be given with around or after",
		},
		{"entities out of range", "message.send", map[string]any{
			"room_id": w.room, "text": "hi",
			"entities": []map[string]any{{"type": "bold", "offset": 1, "length": 5}},
		}, "entities don't fit the text"},
		{"entities of a schedule", "message.schedule", map[string]any{
			"room_id": w.room, "text": "hi",
			"entities": []map[string]any{{"type": "glow", "offset": 0, "length": 2}},
			"due_at":   time.Now().Add(time.Hour).UnixMilli(), "condition": "always",
		}, "entities don't fit the text"},
		{"entities of an edit", "message.edit", map[string]any{
			"event_id": w.events[0], "text": "hi",
			"entities": []map[string]any{{"type": "bold", "offset": 0, "length": 3}},
		}, "entities don't fit the text"},
		{"unknown key in a range", "message.send", map[string]any{
			"room_id": w.room, "text": "hi",
			"entities": []map[string]any{{"type": "bold", "offset": 0, "length": 2, "colour": "red"}},
		}, "unknown parameter entities.0.colour"},
		{
			"text too long", "message.send",
			map[string]any{"room_id": w.room, "text": strings.Repeat("a", actions.MaxTextBytes+1)},
			"text is too long",
		},
		{"members limit", "room.members", map[string]any{"room_id": w.room, "query": "", "limit": 51}, "limit must be 1 to 50"},
		{"members query", "room.members", map[string]any{"room_id": w.room}, "query is required"},
		{"schedule condition", "message.schedule", map[string]any{
			"room_id": w.room, "text": "hi",
			"due_at": time.Now().Add(time.Hour).UnixMilli(),
		}, "condition is required"},
		{
			"schedule due", "message.schedule",
			map[string]any{"room_id": w.room, "text": "hi", "condition": "always"},
			"due_at is required",
		},
		{
			"timer", "room.setDisappearing",
			map[string]any{"room_id": w.room, "type": "after_send", "timer_ms": -1},
			"timer_ms must not be negative",
		},
		{"vote", "poll.vote", map[string]any{"event_id": w.events[0]}, "option_ids is required"},
		{
			"poll options", "poll.create",
			map[string]any{"room_id": w.room, "question": "Lunch?", "multiple": false},
			"options is required",
		},
		{"outbox id", "scheduled.delete", map[string]any{}, "outbox_id is required"},
	} {
		e := c.fails(CodeInvalidParams, tc.method, tc.params)
		require.Equal(t, tc.reason, reason(t, e), tc.name)
	}
}

func TestErrorsMapExactly(t *testing.T) {
	for _, tc := range []struct {
		err    error
		code   int
		reason string
	}{
		{actions.ErrNotEntitled, CodeNotEntitled, ""},
		{fmt.Errorf("%w: %w", actions.ErrNetworkRefused, errors.New("the bridge said no")), CodeNotSupported, ""},
		{actions.ErrNetworkRefused, CodeNotSupported, ""},
		{actions.ErrNotSupported, CodeNotSupported, ""},
		{actions.ErrTooOld, CodeTooOld, ""},
		{actions.ErrAlreadySent, CodeAlreadySent, ""},
		{store.ErrAlreadySent, CodeAlreadySent, ""},
		{actions.ErrNotYours, CodeNotYours, ""},
		{actions.ErrTooLong, CodeInvalidParams, "text is too long"},
		{
			fmt.Errorf("%w: %w", actions.ErrBadValue, fmt.Errorf("%w: range 0: out of bounds", richtext.ErrBadEntity)), CodeInvalidParams,
			"entities don't fit the text",
		},
		{actions.ErrBadValue, CodeBadValue, ""},
		{actions.ErrEmpty, CodeInvalidParams, "there is nothing to send"},
		{fmt.Errorf("network x: %w — nothing was sent", actions.ErrNotConnected), CodeNotConnected, ""},
	} {
		e, unknown := classify(tc.err)
		require.False(t, unknown, "%v", tc.err)
		require.Equal(t, tc.code, e.Code, "%v", tc.err)
		require.Equal(t, errorMessages[tc.code], e.Message, "only the code's own message: %v", tc.err)
		if tc.reason == "" {
			require.Nil(t, e.Data, "%v", tc.err)
		} else {
			require.Equal(t, map[string]string{"reason": tc.reason}, e.Data, "%v", tc.err)
		}
	}
	require.Equal(t, "that message is too old to change", errorMessages[CodeTooOld])
	require.Equal(t, "it has already gone", errorMessages[CodeAlreadySent])
	require.Equal(t, "you can only change your own messages", errorMessages[CodeNotYours])
}

// The plan's undo send: a hold above 0 needs it, and a refused one stores nothing. Sending at once never does.
func TestHoldNeedsTheEntitlement(t *testing.T) {
	w := newWorld(t)
	w.ent.deny.Store(true)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()

	e := c.fails(CodeNotEntitled, "message.send", map[string]any{"room_id": w.room, "text": "held", "hold_ms": 2000})
	require.Equal(t, "this isn't part of your plan", e.Message)
	c.fails(CodeNotEntitled, "message.sendFile", map[string]any{"room_id": w.room, "path": "/etc/hosts", "hold_ms": 750})
	evs, err := w.s.Events(ctx, w.room, 10)
	require.NoError(t, err)
	require.Len(t, evs, 3, "nothing was stored")

	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "at once", "hold_ms": 0}, &sent)
	require.Equal(t, "at once", received(t, w.wa.Sent).Body)
}

// The plan's send later: a refused schedule stores nothing. One already scheduled can still be changed, sent or
// deleted after the plan lapses: nothing is stranded.
func TestScheduleNeedsTheEntitlement(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	due := time.Now().Add(time.Hour).UnixMilli()
	var kept struct {
		OutboxID int64 `json:"outbox_id"`
	}
	c.ok("message.schedule", map[string]any{"room_id": w.room, "text": "kept", "due_at": due, "condition": "always"}, &kept)

	w.ent.deny.Store(true)
	c.fails(CodeNotEntitled, "message.schedule", map[string]any{"room_id": w.room, "text": "refused", "due_at": due, "condition": "always"})
	var list struct {
		Scheduled []struct {
			OutboxID int64  `json:"outbox_id"`
			Text     string `json:"text"`
		} `json:"scheduled"`
	}
	c.ok("scheduled.list", map[string]any{"room_id": w.room}, &list)
	require.Len(t, list.Scheduled, 1, "the refused one was not stored")
	require.Equal(t, "kept", list.Scheduled[0].Text)

	c.ok("scheduled.update", map[string]any{"outbox_id": kept.OutboxID, "text": "kept, changed"}, nil)
	c.ok("scheduled.delete", map[string]any{"outbox_id": kept.OutboxID}, nil)
	c.fails(CodeNotFound, "scheduled.delete", map[string]any{"outbox_id": kept.OutboxID})
}

// What the composer typed comes back exactly: a scheduled message's text, ranges and reply, and a held message the
// person takes back with Undo.
func TestScheduledTextComesBackAsTyped(t *testing.T) {
	w := newWorld(t)
	w.can(t, everything())
	c := dial(t, w.path)
	c.hello()
	typed := "Lunch at *noon* 🍜, ok?"
	ents := []map[string]any{{"type": "bold", "offset": 10, "length": 4}, {"type": "link", "offset": 0, "length": 5, "url": "https://example.test/lunch"}}
	due := time.Now().Add(time.Hour).UnixMilli()

	type scheduled struct {
		OutboxID   int64             `json:"outbox_id"`
		RoomID     string            `json:"room_id"`
		Text       string            `json:"text"`
		Entities   []richtext.Entity `json:"entities"`
		ReplyTo    *string           `json:"reply_to"`
		ThreadRoot *string           `json:"thread_root"`
		DueAt      int64             `json:"due_at"`
		Condition  string            `json:"condition"`
		State      string            `json:"state"`
		SetAt      int64             `json:"set_at"`
	}
	var sc scheduled
	c.ok("message.schedule", map[string]any{
		"room_id": w.room, "text": typed, "entities": ents, "reply_to": w.events[1], "due_at": due, "condition": "if_no_reply",
	}, &sc)
	want := []richtext.Entity{{Kind: "bold", Offset: 10, Length: 4}, {Kind: "link", Offset: 0, Length: 5, URL: "https://example.test/lunch"}}
	require.Equal(t, typed, sc.Text)
	require.Equal(t, want, sc.Entities)
	require.Equal(t, w.events[1], *sc.ReplyTo)
	require.Nil(t, sc.ThreadRoot)
	require.Equal(t, due, sc.DueAt)
	require.Equal(t, "if_no_reply", sc.Condition)
	require.Equal(t, "waiting", sc.State)
	require.Equal(t, w.room, sc.RoomID)

	var list struct {
		Scheduled []scheduled `json:"scheduled"`
	}
	c.ok("scheduled.list", nil, &list)
	require.Equal(t, []scheduled{sc}, list.Scheduled, "every chat's, as scheduled")

	var changed scheduled
	c.ok("scheduled.update", map[string]any{"outbox_id": sc.OutboxID, "text": "Lunch at one", "entities": []map[string]any{}}, &changed)
	require.Equal(t, "Lunch at one", changed.Text)
	require.Empty(t, changed.Entities)
	require.Equal(t, w.events[1], *changed.ReplyTo, "the reply it was scheduled with stays")
	c.ok("scheduled.list", map[string]any{"room_id": w.room}, &list)
	require.Equal(t, []scheduled{changed}, list.Scheduled)

	// A held message: queued in the chat with what was typed left out of its content, and Undo gives it back.
	var held struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": typed, "entities": ents, "reply_to": w.events[2], "hold_ms": 10000}, &held)
	var page wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 1}, &page)
	queued := page.event(t, held.EventID)
	require.Equal(t, "queued", queued.Status)
	require.NotContains(t, string(queued.Content), store.SourceKey, "what was typed stays in the engine")
	var content struct {
		FormattedBody string `json:"formatted_body"`
	}
	require.NoError(t, json.Unmarshal(queued.Content, &content))
	require.Contains(t, content.FormattedBody, "<strong>noon</strong>", "the content is what will be sent")

	var draft struct {
		Text       string            `json:"text"`
		Entities   []richtext.Entity `json:"entities"`
		ReplyTo    *string           `json:"reply_to"`
		ThreadRoot *string           `json:"thread_root"`
	}
	c.ok("message.undo", map[string]any{"event_id": held.EventID}, &draft)
	require.Equal(t, typed, draft.Text)
	require.Equal(t, want, draft.Entities)
	require.Equal(t, w.events[2], *draft.ReplyTo)
	require.Nil(t, draft.ThreadRoot)
	c.fails(CodeAlreadySent, "message.undo", map[string]any{"event_id": w.events[0]})
	c.fails(CodeNotFound, "message.undo", map[string]any{"event_id": "$nope"})
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 1}, &page)
	require.NotEqual(t, held.EventID, page.Events[0].EventID, "taken back: gone from the chat")
}

// A thread's replies are in its thread, not in the main timeline; the thread page carries what the main timeline
// carries for them (edits, reactions, deletions), and its root comes last, on the oldest page. A search hit on a
// reply that is only in its thread opens the chat at its root (Ruling 23).
func TestThreadRepliesOnlyInTheirThread(t *testing.T) {
	w := newWorld(t)
	w.can(t, everything())
	base := time.Now().Add(-time.Hour)
	root := w.put(t, "$root", contact, "m.room.message", `{"msgtype":"m.text","body":"Who's in?"}`, base)
	var replies []string
	for i := range 5 {
		replies = append(replies, w.put(t, fmt.Sprintf("$reply%d", i), contact, "m.room.message",
			inThread(root, fmt.Sprintf("reply %d", i)), base.Add(time.Duration(i+1)*time.Minute)))
	}
	edit := w.put(t, "$edit", contact, "m.room.message", editOf(replies[0], "reply zero"), base.Add(10*time.Minute))
	react := w.put(t, "$react", string(ids.Me), "m.reaction", reactionTo(replies[1], "👍"), base.Add(11*time.Minute))
	gone := w.put(t, "$gone", contact, "m.room.redaction", fmt.Sprintf(`{"redacts":%q}`, replies[2]), base.Add(12*time.Minute))
	rootReact := w.put(t, "$rootreact", contact, "m.reaction", reactionTo(root, "🎉"), base.Add(13*time.Minute))
	after := say(t, w.s, w.room, contact, "back in the channel", base.Add(14*time.Minute))
	c := dial(t, w.path)
	c.hello()

	var main wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 100}, &main)
	for _, r := range replies {
		require.NotContains(t, main.ids(), r, "a thread reply is left out of the main timeline")
	}
	require.Contains(t, main.ids(), root)
	require.NotNil(t, main.event(t, root).Thread, "the root carries its thread")
	require.Equal(t, 4, main.event(t, root).Thread.Replies, "the root says how many replies it has, the deleted one not counted")

	var thread wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "thread": root, "limit": 3}, &thread)
	require.Equal(t, []string{gone, replies[4], replies[3], replies[2]}, thread.ids(), "newest first, with the deletion of a reply")
	require.NotNil(t, thread.Before)
	require.Nil(t, thread.After, "a thread page has no after: after can't be given with thread")
	var older wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "thread": root, "limit": 3, "before": thread.Before}, &older)
	require.Equal(t, []string{rootReact, react, edit, replies[1], replies[0], root}, older.ids(),
		"the edit and reaction of its replies, and on the oldest page the root and what it carries")
	require.Nil(t, older.Before)
	require.NotContains(t, append(thread.ids(), older.ids()...), after, "nothing outside the thread")

	c.fails(CodeNotFound, "room.events", map[string]any{"room_id": w.room, "thread": "$nope"})

	var around, atRoot wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "around": replies[3], "limit": 3}, &around)
	c.ok("room.events", map[string]any{"room_id": w.room, "around": root, "limit": 3}, &atRoot)
	require.Equal(t, atRoot.ids(), around.ids(), "a reply only in its thread opens the chat at its root")
	require.Contains(t, around.ids(), root)
	require.NotContains(t, around.ids(), replies[3])
}

// Every event says whether it is bookmarked, a poll's tally, a thread's summary and when it disappears. A message
// deleted for me is left out.
func TestEventsCarryPollsThreadsAndBookmarks(t *testing.T) {
	w := newWorld(t)
	w.can(t, everything())
	ctx := context.Background()
	base := time.Now().Add(-time.Hour)
	poll := w.put(t, "$poll", contact, "org.matrix.msc3381.poll.start", pollOf("Lunch?", 1, "Noodles", "Tacos"), base)
	w.put(t, "$vote1", contact, "org.matrix.msc3381.poll.response", voteOn(poll, "2"), base.Add(time.Minute))
	w.put(t, "$vote2", string(ids.Me), "org.matrix.msc3381.poll.response", voteOn(poll, "2"), base.Add(2*time.Minute))
	root := w.put(t, "$root", contact, "m.room.message", `{"msgtype":"m.text","body":"Plans"}`, base.Add(3*time.Minute))
	w.put(t, "$reply", "@whatsapp_ana:courier.local", "m.room.message", inThread(root, "count me in"), base.Add(4*time.Minute))
	timed := w.put(t, "$timed", contact, "m.room.message",
		`{"msgtype":"m.text","body":"gone soon","com.beeper.disappearing_timer":{"type":"after_send","timer":3600000}}`, base.Add(5*time.Minute))
	mine := w.put(t, "$deleted", contact, "m.room.message", `{"msgtype":"m.text","body":"not for me"}`, base.Add(6*time.Minute))
	require.NoError(t, w.s.SetBookmarked(ctx, root, true))
	require.NoError(t, w.s.SetDeletedForMe(ctx, mine))
	ana := "Ana"
	require.NoError(t, w.s.SetProfile(ctx, "@whatsapp_ana:courier.local", &ana, nil))

	c := dial(t, w.path)
	c.hello()
	var page wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 100}, &page)
	require.NotContains(t, page.ids(), mine, "deleted for me: left out")

	p := page.event(t, poll).Poll
	require.NotNil(t, p)
	require.Equal(t, "Lunch?", p.Question)
	require.Equal(t, 1, p.MaxSelections)
	require.Equal(t, 2, p.Voters)
	require.Equal(t, []string{"2"}, p.Mine)
	require.False(t, p.Ended)
	require.Len(t, p.Options, 2)
	require.Equal(t, "Tacos", p.Options[1].Text)
	require.Equal(t, 2, p.Options[1].Votes)
	require.Nil(t, page.event(t, root).Poll, "only a poll has a tally")

	th := page.event(t, root).Thread
	require.NotNil(t, th)
	require.Equal(t, 1, th.Replies)
	require.Equal(t, []string{"Ana"}, th.LastSenders)
	require.Equal(t, base.Add(4*time.Minute).UnixMilli(), th.LastTS)
	require.Nil(t, page.event(t, poll).Thread, "no replies: no thread")

	require.True(t, page.event(t, root).Bookmarked)
	require.False(t, page.event(t, poll).Bookmarked)

	require.Equal(t, base.Add(5*time.Minute+time.Hour).UnixMilli(), page.event(t, timed).ExpiresAt)
	require.Zero(t, page.event(t, root).ExpiresAt, "0 is never")
}

// A page of big polls ends before 1 MiB, with a cursor that carries on: paging reads every event exactly once.
func TestPagesWithPollsEndBeforeOneMiB(t *testing.T) {
	w := newWorld(t)
	base := time.Now().Add(-time.Hour)
	long := strings.Repeat("option text ", 90) // about 1 KB, twice per option: in the content and in the tally
	var answers []string
	for i := range 12 {
		answers = append(answers, fmt.Sprintf("%d %s", i, long))
	}
	want := slices.Clone(w.events) // the world's three, newer than the polls
	slices.Reverse(want)
	for i := range 100 {
		id := w.put(t, fmt.Sprintf("$bigpoll%03d", i), contact, "org.matrix.msc3381.poll.start",
			pollOf(fmt.Sprintf("Question %d", i), 1, answers...), base.Add(time.Duration(i)*time.Second))
		want = slices.Insert(want, 3, id)
	}
	c := dial(t, w.path)
	c.hello()

	var got []string
	var before any
	for pages := 0; ; pages++ {
		require.Less(t, pages, 100, "paging never ends")
		params := map[string]any{"room_id": w.room, "limit": 100}
		if before != nil {
			params["before"] = before
		}
		m := c.call("room.events", params)
		require.Nil(t, m.Error, "%s", m.raw)
		require.Less(t, len(m.raw), 1<<20, "the answer stays under 1 MiB")
		var page wirePage4
		require.NoError(t, json.Unmarshal(m.Result, &page))
		require.NotEmpty(t, page.Events)
		if pages == 0 {
			require.Less(t, len(page.Events), 100, "the first page ends before its limit")
			require.NotNil(t, page.Events[len(page.Events)-1].Poll, "with its tallies")
		}
		got = append(got, page.ids()...)
		if page.Before == nil {
			break
		}
		before = page.Before
	}
	require.Equal(t, want, got)

	// Around and after pages end early too, and still read every event once.
	m := c.call("room.events", map[string]any{"room_id": w.room, "around": want[50], "limit": 100})
	require.Nil(t, m.Error, "%s", m.raw)
	require.Less(t, len(m.raw), 1<<20)
	var around wirePage4
	require.NoError(t, json.Unmarshal(m.Result, &around))
	require.Contains(t, around.ids(), want[50])
	require.Less(t, len(around.Events), 100)
	require.NotNil(t, around.After)
	m = c.call("room.events", map[string]any{"room_id": w.room, "after": around.After, "limit": 100})
	require.Nil(t, m.Error, "%s", m.raw)
	require.Less(t, len(m.raw), 1<<20)
}

// stillClock is a timer loop's clock that never moves and never fires: each sleep the loop asks for is told on slept,
// so a test sees when, and for how long, the loop goes back to sleep.
type stillClock struct {
	now   time.Time
	slept chan time.Duration
}

func (c *stillClock) Now() time.Time { return c.now }
func (c *stillClock) After(d time.Duration) <-chan time.Time {
	c.slept <- d
	return make(chan time.Time)
}

// Ruling 22: scheduling, or moving, a message pokes the timer loop, so one due within the loop's longest sleep is not
// sent late. Nothing else wakes it: a schedule is not an event in the chat.
func TestScheduleWakesTheTimerLoop(t *testing.T) {
	w := newWorld(t)
	now := time.UnixMilli(time.Now().UnixMilli())
	w.s.SetClock(func() time.Time { return now })
	clock := &stillClock{now: now, slept: make(chan time.Duration, 64)}
	tm := timers.New(w.s, w.ent, clock, zerolog.Nop())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		tm.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	require.Equal(t, timers.MaxSleep, received(t, clock.slept), "nothing due: the loop sleeps its longest")

	d := w.deps
	d.Timers = tm
	c := dial(t, serve(t, d))
	c.hello()
	var sc struct {
		OutboxID int64 `json:"outbox_id"`
	}
	c.ok("message.schedule", map[string]any{"room_id": w.room, "text": "soon", "due_at": now.Add(time.Second).UnixMilli(), "condition": "always"}, &sc)
	require.Equal(t, time.Second, received(t, clock.slept), "woken: it now sleeps until the message is due")
	c.ok("scheduled.update", map[string]any{"outbox_id": sc.OutboxID, "due_at": now.Add(2 * time.Second).UnixMilli()}, nil)
	require.Equal(t, 2*time.Second, received(t, clock.slept), "moved: woken again")
}

// The new actions over the socket, each reaching the network (fakenet) or the store as it should.
func TestMessageActionsOverTheSocket(t *testing.T) {
	w := newWorld(t)
	w.can(t, everything())
	ctx := context.Background()
	c := dial(t, w.path)
	c.hello()

	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "first draft"}, &sent)
	received(t, w.wa.Sent)
	c.changed(func(ch changed) bool { return ch.Kind == "status" && ch.EventID == sent.EventID })
	require.Eventually(t, func() bool {
		e, _, err := w.s.GetEvent(ctx, sent.EventID)
		return err == nil && e.Status == "sent"
	}, 5*time.Second, 10*time.Millisecond)

	var edit struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.edit", map[string]any{"event_id": sent.EventID, "text": "second draft"}, &edit)
	require.Equal(t, "second draft", received(t, w.wa.Edits).Body)
	c.fails(CodeNotYours, "message.edit", map[string]any{"event_id": w.events[0], "text": "theirs"})
	c.fails(CodeNotYours, "message.unsend", map[string]any{"event_id": w.events[0]})
	require.Eventually(t, func() bool {
		var h struct {
			Versions []struct {
				Body string `json:"body"`
			} `json:"versions"`
		}
		c.ok("message.history", map[string]any{"event_id": sent.EventID}, &h)
		return len(h.Versions) == 2 && h.Versions[0].Body == "first draft" && h.Versions[1].Body == "second draft"
	}, 5*time.Second, 20*time.Millisecond, "the history has both versions once the edit went")

	c.ok("message.setBookmarked", map[string]any{"event_id": w.events[1], "on": true}, nil)
	bm, err := w.s.Bookmarked(ctx, []string{w.events[1]})
	require.NoError(t, err)
	require.True(t, bm[w.events[1]])
	c.fails(CodeNotFound, "message.setBookmarked", map[string]any{"event_id": "$nope", "on": true})

	// Forward: the chat named twice gets one copy; a chat the engine doesn't have fails on its own, with its code.
	var fwd struct {
		Sent []struct {
			RoomID  string `json:"room_id"`
			EventID string `json:"event_id"`
		} `json:"sent"`
		Failed []struct {
			RoomID string `json:"room_id"`
			Code   int    `json:"code"`
		} `json:"failed"`
	}
	c.ok("message.forward", map[string]any{"event_id": w.events[0], "room_ids": []string{w.room, "!nope:courier.local", w.room}}, &fwd)
	require.Len(t, fwd.Sent, 1)
	require.Equal(t, w.room, fwd.Sent[0].RoomID)
	require.Equal(t, "one", received(t, w.wa.Sent).Body)
	require.Len(t, fwd.Failed, 1)
	require.Equal(t, "!nope:courier.local", fwd.Failed[0].RoomID)
	require.Equal(t, CodeNotFound, fwd.Failed[0].Code)

	c.ok("message.unsend", map[string]any{"event_id": sent.EventID}, &edit)
	received(t, w.wa.Removes)

	c.ok("message.deleteForMe", map[string]any{"event_id": w.events[2]}, nil)
	var page wirePage4
	c.ok("room.events", map[string]any{"room_id": w.room}, &page)
	require.NotContains(t, page.ids(), w.events[2])

	// Features, with the timer the chat has now.
	var f map[string]any
	c.ok("room.features", map[string]any{"room_id": w.room}, &f)
	require.Equal(t, true, f["edit"])
	require.EqualValues(t, actions.MaxTextBytes, f["max_text_length"], "UTF-8 bytes, the engine's own limit")
	require.EqualValues(t, 900000, f["edit_max_age_ms"])
	require.Nil(t, f["current_timer"])
	require.Equal(t, "stored", f["source"])
	c.ok("room.setDisappearing", map[string]any{"room_id": w.room, "type": "after_send", "timer_ms": 86400000}, nil)
	received(t, w.wa.Timers)
	c.ok("room.features", map[string]any{"room_id": w.room}, &f)
	require.Equal(t, map[string]any{"type": "after_send", "timer_ms": float64(86400000)}, f["current_timer"])
	c.fails(CodeBadValue, "room.setDisappearing", map[string]any{"room_id": w.room, "type": "after_send", "timer_ms": 1000})

	// Polls.
	var poll struct {
		EventID string `json:"event_id"`
	}
	c.ok("poll.create", map[string]any{"room_id": w.room, "question": "Lunch?", "options": []string{"Noodles", "Tacos"}, "multiple": false}, &poll)
	require.Equal(t, "Lunch?", received(t, w.wa.Polls).Question)
	require.Eventually(t, func() bool {
		e, _, err := w.s.GetEvent(ctx, poll.EventID)
		return err == nil && e.Status == "sent"
	}, 5*time.Second, 10*time.Millisecond)
	c.fails(CodeBadValue, "poll.create", map[string]any{"room_id": w.room, "question": "One?", "options": []string{"Only"}, "multiple": false})
	c.ok("poll.vote", map[string]any{"event_id": poll.EventID, "option_ids": []string{"2"}}, &edit)
	require.Equal(t, []string{"2"}, received(t, w.wa.Votes).Answers)

	// Members: the chat's people by name, folded as search folds.
	for id, name := range map[string]string{
		"@whatsapp_ana:courier.local": "Ána Lima", "@whatsapp_ben:courier.local": "Ben Stone", "@whatsapp_left:courier.local": "Ana Gone",
	} {
		membership := "join"
		if strings.Contains(id, "left") {
			membership = "leave"
		}
		b, err := json.Marshal(map[string]string{"membership": membership, "displayname": name})
		require.NoError(t, err)
		require.NoError(t, w.s.SetMember(ctx, w.room, id, b))
	}
	var members struct {
		Members []struct {
			UserID     string `json:"user_id"`
			Name       string `json:"name"`
			AvatarPath string `json:"avatar_path"`
		} `json:"members"`
	}
	c.ok("room.members", map[string]any{"room_id": w.room, "query": "ana li"}, &members)
	require.Len(t, members.Members, 1)
	require.Equal(t, "Ána Lima", members.Members[0].Name)
	c.ok("room.members", map[string]any{"room_id": w.room, "query": "", "limit": 1}, &members)
	require.Len(t, members.Members, 1, "limit")
	c.fails(CodeNotFound, "room.members", map[string]any{"room_id": "!nope:courier.local", "query": ""})

	// Held messages go when asked, in one chat or every chat.
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "held a while", "hold_ms": 10000}, &sent)
	c.ok("message.sendHeld", map[string]any{"room_id": w.room}, nil)
	require.Equal(t, "held a while", received(t, w.wa.Sent).Body)
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "held again", "hold_ms": 10000}, &sent)
	c.ok("message.sendHeld", nil, nil)
	require.Equal(t, "held again", received(t, w.wa.Sent).Body)
	c.fails(CodeAlreadySent, "message.undo", map[string]any{"event_id": sent.EventID})

	// Send Now.
	var sc struct {
		OutboxID int64 `json:"outbox_id"`
	}
	c.ok("message.schedule", map[string]any{"room_id": w.room, "text": "later, now", "due_at": time.Now().Add(time.Hour).UnixMilli(), "condition": "always"}, &sc)
	c.ok("scheduled.sendNow", map[string]any{"outbox_id": sc.OutboxID}, nil)
	require.Equal(t, "later, now", received(t, w.wa.Sent).Body)
	c.fails(CodeNotFound, "scheduled.sendNow", map[string]any{"outbox_id": sc.OutboxID})
}

// A forward to more chats than one Forward takes is one -32602, before anything is sent: not 21 failures.
func TestForwardTooManyChatsIsOneError(t *testing.T) {
	w := newWorld(t)
	rooms := addRooms(t, w.s, "whatsapp", "fwd", actions.MaxForwardRooms+1)
	c := dial(t, w.path)
	c.hello()
	c.fails(CodeInvalidParams, "message.forward", map[string]any{"event_id": w.events[0], "room_ids": rooms})
	select {
	case s := <-w.wa.Sent:
		t.Fatalf("something was sent: %v", s)
	default:
	}
	// The same chat named 25 times is one chat.
	same := []string{}
	for range 25 {
		same = append(same, w.room)
	}
	var fwd struct {
		Sent []json.RawMessage `json:"sent"`
	}
	c.ok("message.forward", map[string]any{"event_id": w.events[0], "room_ids": same}, &fwd)
	require.Len(t, fwd.Sent, 1)
}

// Ruling 7: every change to a chat's scheduled messages is a "scheduled" change for that chat, not a resync.
func TestScheduledChangesAreNotified(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	var sc struct {
		OutboxID int64 `json:"outbox_id"`
	}
	c.ok("message.schedule", map[string]any{"room_id": w.room, "text": "later", "due_at": time.Now().Add(time.Hour).UnixMilli(), "condition": "always"}, &sc)
	got := c.changed(func(ch changed) bool { return ch.Kind == "scheduled" || ch.Kind == "resync" })
	require.Equal(t, changed{Kind: "scheduled", RoomID: w.room}, got)
	c.ok("scheduled.delete", map[string]any{"outbox_id": sc.OutboxID}, nil)
	got = c.changed(func(ch changed) bool { return ch.Kind == "scheduled" || ch.Kind == "resync" })
	require.Equal(t, changed{Kind: "scheduled", RoomID: w.room}, got)
}
