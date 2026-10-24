// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// switchable is an entitlement provider a test can turn to deny-all.
type switchable struct{ deny atomic.Bool }

func (s *switchable) Allowed(entitlement.Feature) bool { return !s.deny.Load() }

// wireRow is an InboxRow as it comes off the wire.
type wireRow struct {
	RoomID           string   `json:"room_id"`
	Preview          string   `json:"preview"`
	Unread           int      `json:"unread"`
	UnreadMentions   int      `json:"unread_mentions"`
	Muted            bool     `json:"muted"`
	Pinned           bool     `json:"pinned"`
	Archived         bool     `json:"archived"`
	LowPriority      bool     `json:"low_priority"`
	Hidden           bool     `json:"hidden"`
	MarkedUnread     bool     `json:"marked_unread"`
	Request          bool     `json:"request"`
	Draft            string   `json:"draft"`
	Labels           []int64  `json:"labels"`
	MutedBy          string   `json:"muted_by"`
	MutedByName      string   `json:"muted_by_name"`
	Typing           []string `json:"typing"`
	PreviewMediaPath string   `json:"preview_media_path"`
	Reminder         *struct {
		DueAt     int64  `json:"due_at"`
		Condition string `json:"condition"`
		Fired     bool   `json:"fired"`
	} `json:"reminder"`
}

type wirePage struct {
	Rooms      []wireRow `json:"rooms"`
	NextCursor *string   `json:"next_cursor"`
}

// row reads one chat's inbox row through inbox.list's room_ids.
func (c *client) row(roomID string) wireRow {
	c.t.Helper()
	var p wirePage
	c.ok("inbox.list", map[string]any{"room_ids": []string{roomID}}, &p)
	require.Len(c.t, p.Rooms, 1, "inbox.list room_ids %s", roomID)
	return p.Rooms[0]
}

// received waits for the fake network to be handed something on ch.
func received[T any](t *testing.T, ch <-chan T) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(10 * time.Second):
		t.Fatal("the network was never told")
		var zero T
		return zero
	}
}

// reason is an invalid-params error's reason.
func reason(t *testing.T, e *wireError) string {
	t.Helper()
	var d struct {
		Reason string `json:"reason"`
	}
	require.NoError(t, json.Unmarshal(e.Data, &d))
	return d.Reason
}

// addRooms adds n chats on network with no messages, and returns their IDs.
func addRooms(t *testing.T, s *store.Store, network, prefix string, n int) []string {
	t.Helper()
	var out []string
	for i := range n {
		id := fmt.Sprintf("!%s%04d:courier.local", prefix, i)
		require.NoError(t, s.UpsertRoom(context.Background(), store.Room{ID: id, Network: network, Name: "Example chat"}))
		out = append(out, id)
	}
	return out
}

func TestInboxListPagesThroughTheCursor(t *testing.T) {
	w := newWorld(t)
	want := append(addRooms(t, w.s, "whatsapp", "page", 10), w.room)
	c := dial(t, w.path)
	c.hello()

	var got []string
	var sizes []int
	var cursor *string
	for {
		params := map[string]any{"limit": 4}
		if cursor != nil {
			params["cursor"] = *cursor
		}
		var p wirePage
		c.ok("inbox.list", params, &p)
		sizes = append(sizes, len(p.Rooms))
		for _, r := range p.Rooms {
			got = append(got, r.RoomID)
		}
		if p.NextCursor == nil {
			break
		}
		cursor = p.NextCursor
	}
	require.Equal(t, []int{4, 4, 3}, sizes)
	require.ElementsMatch(t, want, got, "every chat once, across the pages")

	// A cursor this query didn't hand out is refused, by name.
	e := c.fails(CodeInvalidParams, "inbox.list", map[string]any{"cursor": "not-a-cursor"})
	require.Contains(t, reason(t, e), "cursor")
	var first wirePage
	c.ok("inbox.list", map[string]any{"limit": 2}, &first)
	require.NotNil(t, first.NextCursor)
	e = c.fails(CodeInvalidParams, "inbox.list", map[string]any{"sort": "oldest", "cursor": *first.NextCursor})
	require.Contains(t, reason(t, e), "cursor", "another query's cursor")

	// The page size is 1 to 500.
	for _, limit := range []int{0, 501} {
		e = c.fails(CodeInvalidParams, "inbox.list", map[string]any{"limit": limit})
		require.Contains(t, reason(t, e), "limit")
	}
}

// Ruling 11: "All" is no filters. "all" itself is not a filter, and nor is anything else the store doesn't know.
func TestInboxListRefusesWhatItDoesNotKnowByName(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	var p wirePage
	c.ok("inbox.list", map[string]any{"filters": []string{}}, &p)
	require.Len(t, p.Rooms, 1, "no filters is All")
	c.ok("inbox.list", map[string]any{"filters": []string{"unread"}, "sort": "oldest", "space": "inbox"}, &p)
	require.Len(t, p.Rooms, 1)

	for _, tc := range []struct {
		params map[string]any
		names  string
	}{
		{map[string]any{"filters": []string{"all"}}, "filters"},
		{map[string]any{"filters": []string{"unread", "everything"}}, "filters"},
		{map[string]any{"sort": "alphabetical"}, "sort"},
		{map[string]any{"space": "nowhere"}, "space"},
		{map[string]any{"space": ""}, "space"},
	} {
		e := c.fails(CodeInvalidParams, "inbox.list", tc.params)
		require.Contains(t, reason(t, e), tc.names, "%v", tc.params)
	}
}

func TestRoomIDsAndSpaceAreExclusive(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	for _, other := range []map[string]any{
		{"space": "inbox"}, {"filters": []string{"unread"}}, {"sort": "newest"},
	} {
		params := map[string]any{"room_ids": []string{w.room}}
		for k, v := range other {
			params[k] = v
		}
		e := c.fails(CodeInvalidParams, "inbox.list", params)
		require.Contains(t, reason(t, e), "room_ids", "%v", other)
	}

	// Alone, room_ids is a lookup: those chats, wherever they are; one the engine doesn't have is left out.
	_, err := w.s.SetArchived(context.Background(), []string{w.room}, true)
	require.NoError(t, err)
	var p wirePage
	c.ok("inbox.list", map[string]any{"room_ids": []string{w.room, "!gone:courier.local"}}, &p)
	require.Len(t, p.Rooms, 1)
	require.Equal(t, w.room, p.Rooms[0].RoomID)
	require.True(t, p.Rooms[0].Archived, "an archived chat is found too")
	require.Nil(t, p.NextCursor)

	for _, n := range []int{0, 101} {
		ids := make([]string, n)
		for i := range ids {
			ids[i] = fmt.Sprintf("!r%d:courier.local", i)
		}
		e := c.fails(CodeInvalidParams, "inbox.list", map[string]any{"room_ids": ids})
		require.Contains(t, reason(t, e), "room_ids")
	}
}

// Review Focus 3: the biggest page an app can ask for fits comfortably in a frame. Every row here is as heavy as
// the protocol lets a typical chat be: a 140-character preview, five labels, a 2,000-character draft and three
// people typing.
//
// 500 such rows can't be one frame under 1 MiB: the drafts alone are 1,000,000 bytes. The draft has to arrive
// whole (the composer takes row.draft), so the engine pages by size as well as by count: a page stops before it
// would pass 1 MiB, and next_cursor carries on from there. So each frame is under 1 MiB, every chat comes once, and
// every draft is whole, even with every draft at its 16,384-character limit.
func TestLargestPageFitsInAFrame(t *testing.T) {
	s, path := storeOnly(t)
	ctx := context.Background()
	rooms := addRooms(t, s, "whatsapp", "big", 500)
	preview := strings.Repeat("p", 140)
	for i, id := range rooms {
		_, err := s.InsertEvent(ctx, store.Event{
			RoomID: id, EventID: fmt.Sprintf("$big%04d", i), Sender: "@whatsapp_contact:courier.local", Type: "m.room.message",
			Content: json.RawMessage(`{"msgtype":"m.text","body":"` + preview + `and more"}`), TS: time.Now(), Status: "sent",
		})
		require.NoError(t, err)
	}
	for i := range 5 {
		l, err := s.CreateLabel(ctx, fmt.Sprintf("Label %d", i), i, "tag")
		require.NoError(t, err)
		_, err = s.SetLabel(ctx, rooms, l.ID, true)
		require.NoError(t, err)
	}
	var typers []string
	for i := range 3 {
		u := fmt.Sprintf("@whatsapp_typer%d:courier.local", i)
		name := fmt.Sprintf("Example Person %d", i)
		require.NoError(t, s.SetProfile(ctx, u, &name, nil))
		typers = append(typers, u)
	}
	setDrafts := func(n int) string {
		draft := strings.Repeat("d", n)
		for _, id := range rooms {
			require.NoError(t, s.SetDraft(ctx, id, draft))
		}
		return draft
	}
	draft := setDrafts(2000)
	for _, id := range rooms {
		for _, u := range typers {
			s.SetTyping(id, u, time.Now().Add(time.Hour))
		}
	}

	c := dial(t, path)
	c.hello()
	readAll := func(draft string) (pages int) {
		t.Helper()
		seen := map[string]bool{}
		var cursor *string
		for {
			params := map[string]any{"limit": 500}
			if cursor != nil {
				params["cursor"] = *cursor
			}
			m := c.call("inbox.list", params)
			require.Nil(t, m.Error, "%s", m.Error)
			require.Less(t, len(m.raw), 1<<20, "page %d is under 1 MiB", pages)
			var p wirePage
			require.NoError(t, json.Unmarshal(m.Result, &p))
			require.NotEmpty(t, p.Rooms)
			for _, r := range p.Rooms {
				require.False(t, seen[r.RoomID], "%s listed twice", r.RoomID)
				seen[r.RoomID] = true
				require.Len(t, r.Preview, 140)
				require.Len(t, r.Labels, 5)
				require.Equal(t, []string{"Example Person 0", "Example Person 1", "Example Person 2"}, r.Typing)
				require.Equal(t, draft, r.Draft, "the draft is whole")
			}
			pages++
			if p.NextCursor == nil {
				break
			}
			cursor = p.NextCursor
		}
		require.Len(t, seen, len(rooms), "every chat once")
		return pages
	}
	t.Logf("2,000-character drafts: %d pages", readAll(draft))
	t.Logf("16,384-character drafts: %d pages", readAll(setDrafts(16384)))
}

func TestBulkLimits(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ids := func(n int) []string {
		out := make([]string, n)
		for i := range out {
			out[i] = fmt.Sprintf("!bulk%03d:courier.local", i)
		}
		return out
	}
	due := time.Now().Add(time.Hour).UnixMilli()
	for _, m := range []struct {
		method string
		params func([]string) map[string]any
	}{
		{"room.setArchived", func(r []string) map[string]any { return map[string]any{"room_ids": r, "archived": true} }},
		{"room.setLowPriority", func(r []string) map[string]any { return map[string]any{"room_ids": r, "on": true} }},
		{"room.setHidden", func(r []string) map[string]any { return map[string]any{"room_ids": r, "on": true} }},
		{"room.setMarkedUnread", func(r []string) map[string]any { return map[string]any{"room_ids": r, "on": true} }},
		{"room.setLabel", func(r []string) map[string]any { return map[string]any{"room_ids": r, "label_id": 1, "on": true} }},
		{"reminder.set", func(r []string) map[string]any {
			return map[string]any{"room_ids": r, "due_at": due, "condition": "always"}
		}},
		{"reminder.clear", func(r []string) map[string]any { return map[string]any{"room_ids": r} }},
	} {
		for _, n := range []int{0, 501} {
			e := c.fails(CodeInvalidParams, m.method, m.params(ids(n)))
			require.Contains(t, reason(t, e), "room_ids", "%s with %d", m.method, n)
		}
		without := m.params(nil)
		delete(without, "room_ids")
		c.fails(CodeInvalidParams, m.method, without)
		// 500 is allowed: these chats just don't exist.
		c.fails(CodeNotFound, m.method, m.params(ids(500)))
	}
}

func TestNotEntitledIsRefusedAndStoresNothing(t *testing.T) {
	w := newWorld(t)
	w.ent.deny.Store(true)
	c := dial(t, w.path)
	c.hello()

	e := c.fails(CodeNotEntitled, "reminder.set", map[string]any{
		"room_ids": []string{w.room}, "due_at": time.Now().Add(time.Hour).UnixMilli(), "condition": "always", "archive": true,
	})
	require.Equal(t, "this isn't part of your plan", e.Message)
	c.fails(CodeNotEntitled, "room.setLowPriority", map[string]any{"room_ids": []string{w.room}, "on": true})
	c.fails(CodeNotEntitled, "autoArchive.set", map[string]any{
		"rule_id": 0, "scope": "all", "trigger": "after_read", "chat_type": "all", "duration_ms": 600000, "enabled": true,
	})

	r := c.row(w.room)
	require.Nil(t, r.Reminder, "no reminder was stored")
	require.False(t, r.Archived, "nor was the chat archived")
	require.False(t, r.LowPriority)
	rules, err := w.s.Rules(context.Background())
	require.NoError(t, err)
	require.Empty(t, rules)
	var listed struct {
		Rules []json.RawMessage `json:"rules"`
	}
	c.ok("autoArchive.list", nil, &listed)
	require.Empty(t, listed.Rules)

	// Taking a chat out of Low priority is never refused: nothing is kept from someone whose plan ended.
	c.ok("room.setLowPriority", map[string]any{"room_ids": []string{w.room}, "on": false}, nil)
}

func TestArchivingAPinnedChatSaysWhy(t *testing.T) {
	w := newWorld(t)
	other := addRooms(t, w.s, "whatsapp", "other", 1)[0]
	c := dial(t, w.path)
	c.hello()
	c.ok("room.setPinned", map[string]any{"room_id": w.room, "pinned": true}, nil)
	require.True(t, c.row(w.room).Pinned)
	received(t, w.wa.Tags) // the pin reached WhatsApp, which takes pins

	e := c.fails(CodePinned, "room.setArchived", map[string]any{"room_ids": []string{w.room}, "archived": true})
	require.Equal(t, "a pinned chat can't be archived", e.Message)
	require.False(t, c.row(w.room).Archived)

	// With a chat that isn't pinned too, that one is archived and the pinned one is left: no error.
	var res struct {
		RoomIDs []string `json:"room_ids"`
	}
	c.ok("room.setArchived", map[string]any{"room_ids": []string{w.room, other}, "archived": true}, &res)
	require.Equal(t, []string{other}, res.RoomIDs)
	require.True(t, c.row(other).Archived)
	require.False(t, c.row(w.room).Archived)
}

// mark_read marks what it archived read: "Archive and mark as read".
func TestArchiveCanMarkWhatItArchivedRead(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	require.Equal(t, 3, c.row(w.room).Unread)
	var res struct {
		RoomIDs []string `json:"room_ids"`
	}
	c.ok("room.setArchived", map[string]any{"room_ids": []string{w.room}, "archived": true, "mark_read": true}, &res)
	require.Equal(t, []string{w.room}, res.RoomIDs)
	r := c.row(w.room)
	require.True(t, r.Archived)
	require.Zero(t, r.Unread)
	received(t, w.wa.Receipts) // the read reached the network

	// A chat that was already archived didn't change, so it isn't marked read.
	_, err := w.s.SetMarkedUnread(context.Background(), []string{w.room}, true)
	require.NoError(t, err)
	c.ok("room.setArchived", map[string]any{"room_ids": []string{w.room}, "archived": true, "mark_read": true}, &res)
	require.Empty(t, res.RoomIDs)
	require.True(t, c.row(w.room).MarkedUnread)
}

func TestAcceptRequestNotSupported(t *testing.T) {
	w := newWorld(t)
	ctx := context.Background()
	// Signal is running but has no account: there's no one to send an accept for it.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!request:courier.local", Network: "signal", Name: "Someone new"}))
	require.NoError(t, w.s.SetRequest(ctx, "!request:courier.local", true))
	c := dial(t, w.path)
	c.hello()
	e := c.fails(CodeNotSupported, "room.acceptRequest", map[string]any{"room_id": "!request:courier.local"})
	require.Equal(t, "this network can't do that", e.Message)
	require.True(t, c.row("!request:courier.local").Request, "nothing changed")
	c.fails(CodeNotFound, "room.acceptRequest", map[string]any{"room_id": "!gone:courier.local"})

	// WhatsApp's fake takes accepts.
	require.NoError(t, w.s.SetRequest(ctx, w.room, true))
	require.True(t, c.row(w.room).Request)
	c.ok("room.acceptRequest", map[string]any{"room_id": w.room}, nil)
	require.False(t, c.row(w.room).Request)
	received(t, w.wa.Accepts)
}

// Ruling 1: room.markRead ends a reminder that fired (Actions.MarkRead does it), and leaves one still to come.
func TestMarkReadClearsAFiredReminder(t *testing.T) {
	w := newWorld(t)
	ctx := context.Background()
	require.NoError(t, w.s.SetReminder(ctx, []string{w.room}, time.Now().Add(time.Minute), "always"))
	w.s.SetClock(func() time.Time { return time.Now().Add(2 * time.Minute) })
	fired, err := w.s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{w.room}, fired)

	c := dial(t, w.path)
	c.hello()
	r := c.row(w.room)
	require.NotNil(t, r.Reminder)
	require.True(t, r.Reminder.Fired)
	require.Equal(t, "always", r.Reminder.Condition)
	require.True(t, r.MarkedUnread, "a fired reminder marks the chat unread")

	c.ok("room.markRead", map[string]any{"room_id": w.room}, nil)
	r = c.row(w.room)
	require.Nil(t, r.Reminder, "reading the chat is what a fired reminder waited for")
	require.False(t, r.MarkedUnread)

	due := time.Now().Add(time.Hour)
	c.ok("reminder.set", map[string]any{"room_ids": []string{w.room}, "due_at": due.UnixMilli(), "condition": "if_no_reply"}, nil)
	c.ok("room.markRead", map[string]any{"room_id": w.room}, nil)
	r = c.row(w.room)
	require.NotNil(t, r.Reminder, "a reminder still to come stays")
	require.Equal(t, due.UnixMilli(), r.Reminder.DueAt)
	require.False(t, r.Reminder.Fired)
}

func TestRemindersOverTheSocket(t *testing.T) {
	w := newWorld(t)
	pinned := addRooms(t, w.s, "whatsapp", "pinned", 1)[0]
	c := dial(t, w.path)
	c.hello()
	c.ok("room.setPinned", map[string]any{"room_id": pinned, "pinned": true}, nil)
	due := time.Now().Add(time.Hour).UnixMilli()

	// archive archives the chats once the reminder is set, but never a pinned one, and that's no error.
	c.ok("reminder.set", map[string]any{"room_ids": []string{w.room, pinned}, "due_at": due, "condition": "always", "archive": true}, nil)
	r := c.row(w.room)
	require.NotNil(t, r.Reminder)
	require.True(t, r.Archived)
	r = c.row(pinned)
	require.NotNil(t, r.Reminder)
	require.False(t, r.Archived)

	c.fails(CodeBadValue, "reminder.set", map[string]any{"room_ids": []string{w.room}, "due_at": time.Now().Add(-time.Hour).UnixMilli(), "condition": "always"})
	c.fails(CodeBadValue, "reminder.set", map[string]any{"room_ids": []string{w.room}, "due_at": due, "condition": "sometimes"})
	c.fails(CodeInvalidParams, "reminder.set", map[string]any{"room_ids": []string{w.room}, "condition": "always"})

	c.ok("reminder.clear", map[string]any{"room_ids": []string{w.room}}, nil)
	require.Nil(t, c.row(w.room).Reminder)
	require.NotNil(t, c.row(pinned).Reminder)
	c.fails(CodeNotFound, "reminder.clear", map[string]any{"room_ids": []string{"!gone:courier.local"}})
	c.ok("reminder.clearAll", nil, nil)
	require.Nil(t, c.row(pinned).Reminder)
}

func TestChatStatesOverTheSocket(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	one := []string{w.room}
	var res struct {
		RoomIDs []string `json:"room_ids"`
	}

	c.ok("room.setLowPriority", map[string]any{"room_ids": one, "on": true}, &res)
	require.Equal(t, one, res.RoomIDs)
	require.True(t, c.row(w.room).LowPriority)
	c.ok("room.setLowPriority", map[string]any{"room_ids": one, "on": true}, &res)
	require.Empty(t, res.RoomIDs, "nothing changed")
	require.NotNil(t, res.RoomIDs, "room_ids is a list, even an empty one")

	c.ok("room.setHidden", map[string]any{"room_ids": one, "on": true}, &res)
	require.True(t, c.row(w.room).Hidden)
	c.ok("room.setMarkedUnread", map[string]any{"room_ids": one, "on": true}, &res)
	require.True(t, c.row(w.room).MarkedUnread)
	select {
	case u := <-w.wa.Unreads:
		t.Fatalf("an unread mark stays on this Mac (Ruling 18), got %+v", u)
	case <-time.After(100 * time.Millisecond):
	}

	c.ok("room.setDraft", map[string]any{"room_id": w.room, "text": "half a thought"}, nil)
	require.Equal(t, "half a thought", c.row(w.room).Draft)
	c.fails(CodeBadValue, "room.setDraft", map[string]any{"room_id": w.room, "text": strings.Repeat("x", 16385)})
	c.fails(CodeNotFound, "room.setDraft", map[string]any{"room_id": "!gone:courier.local", "text": "x"})
	c.fails(CodeInvalidParams, "room.setDraft", map[string]any{"room_id": w.room})
	c.ok("room.setDraft", map[string]any{"room_id": w.room, "text": ""}, nil)
	require.Empty(t, c.row(w.room).Draft)

	c.ok("room.setMuted", map[string]any{"room_id": w.room, "muted": true}, nil)
	require.True(t, c.row(w.room).Muted)
	received(t, w.wa.Mutes) // room.setMuted now goes through Actions, so WhatsApp hears of it
	c.fails(CodeNotFound, "room.setPinned", map[string]any{"room_id": "!gone:courier.local", "pinned": true})
}

func TestSpacesAndLabelsOverTheSocket(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()

	var created struct {
		LabelID int64 `json:"label_id"`
	}
	c.ok("labels.create", map[string]any{"title": "  Work  ", "color": 3, "icon": "briefcase"}, &created)
	require.NotZero(t, created.LabelID)
	c.fails(CodeBadValue, "labels.create", map[string]any{"title": "", "color": 3, "icon": "briefcase"})
	c.fails(CodeBadValue, "labels.create", map[string]any{"title": "Bad", "color": 12, "icon": "briefcase"})
	c.fails(CodeInvalidParams, "labels.create", map[string]any{"title": "No colour", "icon": "briefcase"})
	c.ok("labels.update", map[string]any{"label_id": created.LabelID, "title": "Office"}, nil)
	c.fails(CodeNotFound, "labels.update", map[string]any{"label_id": created.LabelID + 100, "title": "Nope"})
	c.fails(CodeBadValue, "labels.update", map[string]any{"label_id": created.LabelID, "icon": ""})

	var res struct {
		RoomIDs []string `json:"room_ids"`
	}
	c.ok("room.setLabel", map[string]any{"room_ids": []string{w.room}, "label_id": created.LabelID, "on": true}, &res)
	require.Equal(t, []string{w.room}, res.RoomIDs)
	require.Equal(t, []int64{created.LabelID}, c.row(w.room).Labels)
	c.fails(CodeNotFound, "room.setLabel", map[string]any{"room_ids": []string{w.room}, "label_id": created.LabelID + 100, "on": true})

	type space struct {
		SpaceID     string `json:"space_id"`
		Kind        string `json:"kind"`
		Title       string `json:"title"`
		Network     string `json:"network"`
		LabelID     int64  `json:"label_id"`
		Color       int    `json:"color"`
		Icon        string `json:"icon"`
		Hidden      bool   `json:"hidden"`
		Muted       bool   `json:"muted"`
		ShowInInbox string `json:"show_in_inbox"`
		Chats       int    `json:"chats"`
		UnreadChats int    `json:"unread_chats"`
		Attention   int    `json:"attention_chats"`
	}
	spaces := func() map[string]space {
		var r struct {
			Spaces []space `json:"spaces"`
		}
		c.ok("spaces.list", nil, &r)
		out := map[string]space{}
		for _, s := range r.Spaces {
			out[s.SpaceID] = s
		}
		require.Equal(t, "inbox", r.Spaces[0].SpaceID, "inbox comes first")
		return out
	}
	got := spaces()
	labelSpace := fmt.Sprintf("label:%d", created.LabelID)
	require.Equal(t, space{
		SpaceID: labelSpace, Kind: "label", Title: "Office", LabelID: created.LabelID, Color: 3,
		Icon: "briefcase", ShowInInbox: "all", Chats: 1, UnreadChats: 1,
	}, got[labelSpace])
	require.Equal(t, "WhatsApp", got["account:whatsapp"].Title, "the network's display name (Ruling 5)")
	require.Equal(t, 1, got["inbox"].Chats)
	require.Equal(t, 1, got["inbox"].Attention, "the unread chat isn't muted: it is the Dock badge")
	require.NotContains(t, got, "account:signal", "signal has no account, so no space")

	// An account mute says who muted the chat, by the network's display name.
	c.ok("spaces.update", map[string]any{"space_id": "account:whatsapp", "muted": true}, nil)
	r := c.row(w.room)
	require.Equal(t, "account", r.MutedBy)
	require.Equal(t, "WhatsApp", r.MutedByName)
	require.True(t, spaces()["account:whatsapp"].Muted)
	require.Zero(t, spaces()["inbox"].Attention, "a muted account's chat doesn't badge")
	c.fails(CodeBadValue, "spaces.update", map[string]any{"space_id": "inbox", "muted": true})
	c.fails(CodeBadValue, "spaces.update", map[string]any{"space_id": "account:whatsapp", "show_in_inbox": "some"})
	c.fails(CodeNotFound, "spaces.update", map[string]any{"space_id": fmt.Sprintf("label:%d", created.LabelID+100), "muted": true})

	c.ok("spaces.setLayout", map[string]any{"order": []string{"inbox", labelSpace, "archive"}, "hidden": []string{"archive"}}, nil)
	got = spaces()
	require.True(t, got["archive"].Hidden)
	c.fails(CodeBadValue, "spaces.setLayout", map[string]any{"order": []string{"archive", "inbox"}, "hidden": []string{}})
	c.fails(CodeInvalidParams, "spaces.setLayout", map[string]any{"order": []string{"inbox"}})

	c.ok("labels.delete", map[string]any{"label_id": created.LabelID}, nil)
	require.NotContains(t, spaces(), labelSpace)
	require.Empty(t, c.row(w.room).Labels)
	c.fails(CodeNotFound, "labels.delete", map[string]any{"label_id": created.LabelID})
}

func TestArchiveMatchingTakesOnlyTheOfferedAges(t *testing.T) {
	w := newWorld(t)
	old := addRooms(t, w.s, "whatsapp", "old", 1)[0]
	c := dial(t, w.path)
	c.hello()
	var res struct {
		RoomIDs []string `json:"room_ids"`
	}
	c.ok("inbox.archiveMatching", map[string]any{"read_only": false, "older_than_ms": 0, "dry_run": true}, &res)
	require.ElementsMatch(t, []string{w.room, old}, res.RoomIDs, "any age")
	require.False(t, c.row(w.room).Archived, "a dry run changes nothing")

	c.ok("inbox.archiveMatching", map[string]any{"space": "inbox", "read_only": true, "older_than_ms": 0, "dry_run": false}, &res)
	require.Equal(t, []string{old}, res.RoomIDs, "only read chats: w.room has three unread")
	require.True(t, c.row(old).Archived)

	week := (7 * 24 * time.Hour).Milliseconds()
	c.ok("inbox.archiveMatching", map[string]any{"read_only": false, "older_than_ms": week, "dry_run": true}, &res)
	require.Empty(t, res.RoomIDs, "nothing is a week old")
	for _, bad := range []int64{1, week + 1, -week} {
		c.fails(CodeBadValue, "inbox.archiveMatching", map[string]any{"read_only": false, "older_than_ms": bad, "dry_run": true})
	}
	c.fails(CodeBadValue, "inbox.archiveMatching", map[string]any{"space": "archive", "read_only": false, "older_than_ms": 0, "dry_run": true})
	c.fails(CodeInvalidParams, "inbox.archiveMatching", map[string]any{"space": "nowhere", "read_only": false, "older_than_ms": 0, "dry_run": true})
	c.fails(CodeInvalidParams, "inbox.archiveMatching", map[string]any{"read_only": false, "older_than_ms": 0})
}

func TestMarkAllReadReadsEveryUnreadChatInTheSpace(t *testing.T) {
	w := newWorld(t)
	ctx := context.Background()
	marked := addRooms(t, w.s, "whatsapp", "marked", 2)
	_, err := w.s.SetMarkedUnread(ctx, marked[:1], true)
	require.NoError(t, err)
	_, err = w.s.SetArchived(ctx, marked[1:], true)
	require.NoError(t, err)
	_, err = w.s.SetMarkedUnread(ctx, marked[1:], true) // archived: not in the inbox space
	require.NoError(t, err)
	c := dial(t, w.path)
	c.hello()

	var res struct {
		RoomIDs []string `json:"room_ids"`
	}
	c.ok("inbox.markAllRead", nil, &res)
	require.ElementsMatch(t, []string{w.room, marked[0]}, res.RoomIDs)
	require.Zero(t, c.row(w.room).Unread)
	require.False(t, c.row(marked[0]).MarkedUnread)
	require.True(t, c.row(marked[1]).MarkedUnread, "a chat in another space is left alone")

	c.ok("inbox.markAllRead", map[string]any{"space": "archive"}, &res)
	require.Equal(t, marked[1:], res.RoomIDs)
	c.ok("inbox.markAllRead", map[string]any{"space": "archive"}, &res)
	require.Empty(t, res.RoomIDs)
	c.fails(CodeInvalidParams, "inbox.markAllRead", map[string]any{"space": "nowhere"})
}

func TestAutoArchiveRulesOverTheSocket(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	type rule struct {
		RuleID     int64  `json:"rule_id"`
		Scope      string `json:"scope"`
		Trigger    string `json:"trigger"`
		ChatType   string `json:"chat_type"`
		DurationMS int64  `json:"duration_ms"`
		Enabled    bool   `json:"enabled"`
	}
	in := rule{Scope: "all", Trigger: "after_read", ChatType: "read", DurationMS: (10 * time.Minute).Milliseconds(), Enabled: true}
	var got rule
	c.ok("autoArchive.set", in, &got)
	require.NotZero(t, got.RuleID)
	in.RuleID = got.RuleID
	require.Equal(t, in, got)

	in.DurationMS = time.Hour.Milliseconds()
	c.ok("autoArchive.set", in, &got)
	require.Equal(t, in, got)
	var list struct {
		Rules []rule `json:"rules"`
	}
	c.ok("autoArchive.list", nil, &list)
	require.Equal(t, []rule{in}, list.Rules)

	bad := in
	bad.DurationMS = 12345
	c.fails(CodeBadValue, "autoArchive.set", bad)
	second := rule{Scope: "all", Trigger: "after_reply", ChatType: "all", DurationMS: 0, Enabled: true}
	c.fails(CodeBadValue, "autoArchive.set", second) // one enabled General rule at a time
	missing := in
	missing.RuleID = in.RuleID + 100
	c.fails(CodeNotFound, "autoArchive.set", missing)
	c.fails(CodeInvalidParams, "autoArchive.set", map[string]any{"rule_id": 0, "scope": "all", "trigger": "after_read"})

	c.ok("autoArchive.delete", map[string]any{"rule_id": in.RuleID}, nil)
	c.ok("autoArchive.list", nil, &list)
	require.Empty(t, list.Rules)
	require.NotNil(t, list.Rules, "rules is a list, even an empty one")
	c.fails(CodeNotFound, "autoArchive.delete", map[string]any{"rule_id": in.RuleID})
}

func TestInboxRowsSayWhatIsGoingOn(t *testing.T) {
	w := newWorld(t)
	ctx := context.Background()
	c := dial(t, w.path)
	c.hello()

	// Who is typing: their name in the chat, else their profile's, else their ID's localpart; sorted by ID.
	require.NoError(t, w.s.SetMember(ctx, w.room, "@whatsapp_a:courier.local", json.RawMessage(`{"membership":"join","displayname":"Name In Chat"}`)))
	profile := "Profile Name"
	require.NoError(t, w.s.SetProfile(ctx, "@whatsapp_b:courier.local", &profile, nil))
	for _, u := range []string{"@whatsapp_c:courier.local", "@whatsapp_b:courier.local", "@whatsapp_a:courier.local"} {
		w.s.SetTyping(w.room, u, time.Now().Add(time.Minute))
	}
	r := c.row(w.room)
	require.Equal(t, []string{"Name In Chat", "Profile Name", "whatsapp_c"}, r.Typing)
	require.NotNil(t, r.Labels, "labels is a list, even an empty one")
	require.Empty(t, r.MutedBy)
	require.Empty(t, r.PreviewMediaPath, "a text message has no picture")

	// Typing is told as its own change.
	w.s.SetTyping(w.room, "@whatsapp_a:courier.local", time.Time{})
	c.changed(func(ch changed) bool { return ch.Kind == "typing" && ch.RoomID == w.room })
	require.Equal(t, []string{"Profile Name", "whatsapp_c"}, c.row(w.room).Typing)
}

// Ruling 18: no network is listed as taking unread marks.
func TestAccountsSayWhatReachesTheNetwork(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	var res struct {
		Accounts []struct {
			Network string   `json:"network"`
			Syncs   []string `json:"syncs"`
		} `json:"accounts"`
	}
	c.ok("accounts.list", nil, &res)
	syncs := map[string][]string{}
	for _, a := range res.Accounts {
		require.NotNil(t, a.Syncs, "%s: syncs is a list, even an empty one", a.Network)
		syncs[a.Network] = a.Syncs
	}
	require.Equal(t, map[string][]string{
		"whatsapp": {"pin", "mute", "accept_request"},
		"signal":   {}, // running, with no account
		"telegram": {}, // not started
	}, syncs)
}

// The protocol's lists of filters and sorts are the store's, so neither can grow without the other.
func TestFiltersAndSortsAreTheStores(t *testing.T) {
	p, _ := loadProtocol(t)
	fields := p.Types["InboxListParams"].Fields
	filters := append([]string{}, fields["filters"].Values...)
	sorts := append([]string{}, fields["sort"].Values...)
	sort.Strings(filters)
	sort.Strings(sorts)
	require.Equal(t, store.FilterNames(), filters)
	require.Equal(t, store.SortNames(), sorts)
	require.NotContains(t, filters, "all", "Ruling 11: All is no filters")
}

// A chat whose newest message is a bridge's call notice says so on the wire: preview_kind call, no text (the bridge's
// English), and preview_call with what happened. Any other newest message has preview_call null.
func TestInboxListSaysWhatACallWas(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	var raw struct {
		Rooms []map[string]json.RawMessage `json:"rooms"`
	}
	c.ok("inbox.list", map[string]any{"room_ids": []string{w.room}}, &raw)
	require.Len(t, raw.Rooms, 1)
	require.JSONEq(t, `null`, string(raw.Rooms[0]["preview_call"]))

	call := store.AnnotateCallNote("telegram", "m.room.message", json.RawMessage(`{"msgtype":"m.notice","body":"Video call missed"}`))
	w.put(t, "$call", "@whatsapp_contact:courier.local", "m.room.message", string(call), time.Now())
	c.ok("inbox.list", map[string]any{"room_ids": []string{w.room}}, &raw)
	require.Len(t, raw.Rooms, 1)
	require.JSONEq(t, `"call"`, string(raw.Rooms[0]["preview_kind"]))
	require.JSONEq(t, `""`, string(raw.Rooms[0]["preview"]))
	require.JSONEq(t, `{"state":"missed","media":"video"}`, string(raw.Rooms[0]["preview_call"]))
}

func TestRPCMergedChatsAndEventsList(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	ctx := context.Background()

	const waRoom = "!wa-dm:courier.local"
	const sigRoom = "!sig-dm:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: waRoom, Network: "whatsapp", Name: "Alice Example", IsDirect: true}))
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: sigRoom, Network: "signal", Name: "Alice Example", IsDirect: true}))
	require.NoError(t, w.s.SetMember(ctx, waRoom, "@whatsapp_alice:courier.local", json.RawMessage(`{"membership":"join","displayname":"Alice Example"}`)))
	require.NoError(t, w.s.SetMember(ctx, sigRoom, "@signal_alice:courier.local", json.RawMessage(`{"membership":"join","displayname":"Alice Example"}`)))
	require.NoError(t, w.s.SetProfileExtraMeta(ctx, "@whatsapp_alice:courier.local", []string{"tel:+15550100101"}, "", false))
	require.NoError(t, w.s.SetProfileExtraMeta(ctx, "@signal_alice:courier.local", []string{"tel:+15550100101"}, "", false))

	say(t, w.s, waRoom, "@whatsapp_alice:courier.local", "msg from wa", time.UnixMilli(1700000010000))
	say(t, w.s, sigRoom, "@signal_alice:courier.local", "msg from sig", time.UnixMilli(1700000020000))

	// 1. merge.suggest
	var suggested struct {
		Suggestions []store.MergeSuggestion `json:"suggestions"`
	}
	c.ok("merge.suggest", nil, &suggested)
	require.NotEmpty(t, suggested.Suggestions)
	require.Equal(t, "identifier", suggested.Suggestions[0].Reason)

	// 2. merge.create
	var created store.MergedChat
	c.ok("merge.create", map[string]any{
		"name":     "Alice Merged",
		"room_ids": []string{waRoom, sigRoom},
	}, &created)
	require.NotEmpty(t, created.MergeID)
	require.Equal(t, "Alice Merged", created.Name)
	require.Equal(t, sigRoom, created.LastRoomID)

	// 3. merge.list
	var listed struct {
		MergedChats []store.MergedChat `json:"merged_chats"`
	}
	c.ok("merge.list", nil, &listed)
	require.Len(t, listed.MergedChats, 1)
	require.Equal(t, created.MergeID, listed.MergedChats[0].MergeID)

	// 4. room.events with merge_id
	var page struct {
		Events []struct {
			EventID string `json:"event_id"`
			RoomID  string `json:"room_id"`
			TS      int64  `json:"ts"`
		} `json:"events"`
	}
	c.ok("room.events", map[string]any{"merge_id": created.MergeID, "limit": 10}, &page)
	require.Len(t, page.Events, 2)
	require.Equal(t, sigRoom, page.Events[0].RoomID)
	require.Equal(t, waRoom, page.Events[1].RoomID)

	// 5. merge.delete
	c.ok("merge.delete", map[string]any{"merge_id": created.MergeID}, nil)
	c.ok("merge.list", nil, &listed)
	require.Empty(t, listed.MergedChats)
}
