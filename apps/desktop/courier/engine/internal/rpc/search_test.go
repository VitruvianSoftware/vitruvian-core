// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// wireHits is a MessageHits as it comes off the wire.
type wireHits struct {
	Hits []struct {
		EventID    string `json:"event_id"`
		RoomID     string `json:"room_id"`
		SenderName string `json:"sender_name"`
		Snippet    string `json:"snippet"`
		Ranges     []struct {
			Start  int `json:"start"`
			Length int `json:"length"`
		} `json:"ranges"`
	} `json:"hits"`
	NextCursor *string `json:"next_cursor"`
}

type wireSearch struct {
	Chats        []wireRow        `json:"chats"`
	InGroups     []map[string]any `json:"in_groups"`
	Media        *wireHits        `json:"media"`
	Messages     *wireHits        `json:"messages"`
	LastArchived *wireRow         `json:"last_archived"`
	Complete     bool             `json:"complete"`
	Hint         string           `json:"hint"`
}

// say adds a text message to roomID from sender at ts and returns its event ID.
func say(t *testing.T, s *store.Store, roomID, sender, body string, ts time.Time) string {
	t.Helper()
	b, err := json.Marshal(map[string]string{"msgtype": "m.text", "body": body})
	require.NoError(t, err)
	id := fmt.Sprintf("$say%d", ts.UnixNano())
	_, err = s.InsertEvent(context.Background(), store.Event{
		RoomID: roomID, EventID: id, Sender: sender, Type: "m.room.message", Content: b, TS: ts, Status: "sent",
	})
	require.NoError(t, err)
	return id
}

func TestSearchQueryValidatesParams(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	tooMany := make([]string, 101)
	for i := range tooMany {
		tooMany[i] = w.room
	}
	for _, tc := range []struct {
		params map[string]any
		reason string
	}{
		{map[string]any{}, "text is required"},
		{map[string]any{"text": strings.Repeat("a", 501)}, "text is too long"},
		{map[string]any{"text": "ab", "sections": []string{"starred"}}, "sections is not one of chats, in_groups, bookmarks, media, messages"},
		{map[string]any{"text": "ab", "cursor": "eyJ4IjoxfQ"}, "cursor needs exactly one of bookmarks, media or messages"},
		{map[string]any{"text": "ab", "sections": []string{"chats"}, "cursor": "eyJ4IjoxfQ"}, "cursor needs exactly one of bookmarks, media or messages"},
		{map[string]any{"text": "ab", "sections": []string{"messages"}, "cursor": "eyJxIjoiYW5vdGhlciJ9"}, "cursor is not one this query handed out"},
		{map[string]any{"text": "ab", "sections": []string{"messages"}, "cursor": ""}, "cursor is not one this query handed out"},
		{map[string]any{"text": "ab", "limit": 0}, "limit must be 1 to 50"},
		{map[string]any{"text": "ab", "limit": 51}, "limit must be 1 to 50"},
		{map[string]any{"text": "ab", "sections": []string{"chats"}, "limit": 101}, "limit must be 1 to 100"},
		{map[string]any{"text": "ab", "filters": map[string]any{"since": 2000, "until": 1000}}, "since must be before until"},
		{map[string]any{"text": "ab", "filters": map[string]any{"since": 1000, "until": 1000}}, "since must be before until"},
		{map[string]any{"text": "ab", "filters": map[string]any{"kinds": []string{"gif"}}}, "unknown kind"},
		{map[string]any{"text": "ab", "filters": map[string]any{"networks": []string{"carrier-pigeon"}}}, "unknown network"},
		{map[string]any{"text": "ab", "filters": map[string]any{"sender": "@whatsapp_contact:courier.local"}}, "unknown sender"},
		{map[string]any{"text": "ab", "filters": map[string]any{"chat_type": "channel"}}, "unknown chat_type"},
		{map[string]any{"text": "ab", "filters": map[string]any{"room_ids": []string{}}}, "room_ids must name 1 to 100 chats"},
		{map[string]any{"text": "ab", "filters": map[string]any{"room_ids": tooMany}}, "room_ids must name 1 to 100 chats"},
		{map[string]any{"text": "ab", "filters": map[string]any{"mood": "happy"}}, "unknown parameter filters.mood"},
		{map[string]any{"text": 5}, "text has the wrong type"},
	} {
		e := c.fails(CodeInvalidParams, "search.query", tc.params)
		require.Equal(t, tc.reason, reason(t, e), "%v", tc.params)
	}

	e := c.fails(CodeNotFound, "search.query", map[string]any{"text": "ab", "filters": map[string]any{"room_ids": []string{"!nope:courier.local"}}})
	require.Equal(t, "no such chat or message", e.Message, "the code's own message, not the store's")

	// What is fine: 500 characters, a known network, every sender and chat type the protocol has.
	c.ok("search.query", map[string]any{"text": strings.Repeat("é", 500)}, nil)
	c.ok("search.query", map[string]any{"text": "one", "filters": map[string]any{
		"networks": []string{"whatsapp"}, "sender": "others", "chat_type": "dm", "kinds": []string{"text", "link"},
		"since": 1, "until": time.Now().Add(time.Hour).UnixMilli(), "partial": true, "room_ids": []string{w.room},
	}}, nil)
}

func TestSearchQueryAnswersEverySection(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	var res wireSearch
	c.ok("search.query", map[string]any{"text": "tw"}, &res)
	require.Empty(t, res.Hint)
	require.True(t, res.Complete)
	require.NotNil(t, res.Chats)
	require.NotNil(t, res.InGroups)
	require.NotNil(t, res.Media)
	require.Empty(t, res.Media.Hits)
	require.NotNil(t, res.Messages)
	require.Len(t, res.Messages.Hits, 1)
	hit := res.Messages.Hits[0]
	require.Equal(t, w.events[1], hit.EventID)
	require.Equal(t, "two", hit.Snippet)
	require.Len(t, hit.Ranges, 1, "the word being typed is highlighted")
	require.Equal(t, 0, hit.Ranges[0].Start)
	require.Equal(t, 3, hit.Ranges[0].Length)
	require.Nil(t, res.LastArchived)

	// Emoji alone run no search: every section is null, and the hint says why.
	c.ok("search.query", map[string]any{"text": "🎉"}, &res)
	require.Equal(t, "emoji_only", res.Hint)
	require.Nil(t, res.Chats)
	require.Nil(t, res.Messages)
}

func TestMessagesPageEndsBeforeOneMiB(t *testing.T) {
	for _, long := range []string{"chat names", "sender names"} {
		t.Run(long, func(t *testing.T) {
			w := newWorld(t)
			ctx := context.Background()
			// "€" is three bytes, and not a word: 8,000 of them make a name of 24,000 bytes that nothing matches.
			name := strings.Repeat("€", 8000)
			sender := "@whatsapp_long:courier.local"
			require.NoError(t, w.s.SetProfile(ctx, sender, ptrTo("Someone"), nil))
			if long == "sender names" {
				require.NoError(t, w.s.SetProfile(ctx, sender, &name, nil))
			}
			t0 := time.Now().Add(-time.Hour)
			var newestFirst []string
			for i := range 50 {
				room := fmt.Sprintf("!long%02d:courier.local", i)
				roomName := "Group"
				if long == "chat names" {
					roomName = name
				}
				require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: room, Network: "whatsapp", Name: roomName}))
				id := say(t, w.s, room, sender, fmt.Sprintf("quokka %d", i), t0.Add(time.Duration(i)*time.Second))
				newestFirst = append([]string{id}, newestFirst...)
			}

			c := dial(t, w.path)
			c.hello()
			m := c.call("search.query", map[string]any{"text": "quokka", "sections": []string{"messages"}, "limit": 50})
			require.Nil(t, m.Error, "%s", m.raw)
			require.Less(t, len(m.raw), 1<<20, "the answer stays under 1 MiB")
			var res wireSearch
			require.NoError(t, json.Unmarshal(m.Result, &res))
			n := len(res.Messages.Hits)
			require.Positive(t, n)
			require.Less(t, n, 50, "a page ends before its limit to stay under 1 MiB")
			for i, h := range res.Messages.Hits {
				require.Equal(t, newestFirst[i], h.EventID)
			}
			require.NotNil(t, res.Messages.NextCursor, "and says there is more")

			var rest wireSearch
			c.ok("search.query", map[string]any{
				"text": "quokka", "sections": []string{"messages"}, "limit": 50, "cursor": *res.Messages.NextCursor,
			}, &rest)
			require.Equal(t, newestFirst[n], rest.Messages.Hits[0].EventID, "the next page starts at the first hit left out")
		})
	}
}

func ptrTo[T any](v T) *T { return &v }

// wireEvents is an EventsPage as it comes off the wire.
type wireEvents struct {
	Events []struct {
		EventID string `json:"event_id"`
		TS      int64  `json:"ts"`
		Seq     int64  `json:"seq"`
	} `json:"events"`
	Before *cursor `json:"before"`
	After  *cursor `json:"after"`
}

func (p wireEvents) ids() []string {
	var out []string
	for _, e := range p.Events {
		out = append(out, e.EventID)
	}
	return out
}

func TestRoomEventsAroundAndAfter(t *testing.T) {
	w := newWorld(t)
	t0 := time.Now().Add(-time.Hour)
	all := []string{}
	var newest wireEvents
	c := dial(t, w.path)
	c.hello()
	for i := range 30 {
		say(t, w.s, w.room, "@whatsapp_contact:courier.local", fmt.Sprintf("message %d", i), t0.Add(time.Duration(i)*time.Second))
	}
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 100}, &newest)
	all = newest.ids() // newest first: the three the world started with, then these 30
	require.Len(t, all, 33)
	require.Nil(t, newest.Before)
	require.Nil(t, newest.After, "the newest page has the chat's newest event")

	middle := all[16]
	var around wireEvents
	c.ok("room.events", map[string]any{"room_id": w.room, "around": middle, "limit": 5}, &around)
	require.Equal(t, all[14:19], around.ids(), "two newer, the message, two older")
	require.NotNil(t, around.Before)
	require.NotNil(t, around.After)

	// Paging out both ways from the message reads every event exactly once.
	got := around.ids()
	for page := around; page.After != nil; {
		var next wireEvents
		c.ok("room.events", map[string]any{"room_id": w.room, "after": page.After, "limit": 4}, &next)
		require.NotEmpty(t, next.Events)
		require.NotNil(t, next.Before, "a newer page has an older one: the page before it")
		got = append(next.ids(), got...)
		page = next
	}
	for page := around; page.Before != nil; {
		var next wireEvents
		c.ok("room.events", map[string]any{"room_id": w.room, "before": page.Before, "limit": 4}, &next)
		require.NotNil(t, next.After, "an older page has a newer one")
		got = append(got, next.ids()...)
		page = next
	}
	require.Equal(t, all, got)

	// Around the newest and the oldest message, the page is still full.
	c.ok("room.events", map[string]any{"room_id": w.room, "around": all[0], "limit": 5}, &around)
	require.Equal(t, all[:5], around.ids())
	require.Nil(t, around.After)
	c.ok("room.events", map[string]any{"room_id": w.room, "around": all[32], "limit": 5}, &around)
	require.Equal(t, all[28:], around.ids())
	require.Nil(t, around.Before)

	// A message that isn't in the chat is not_found, with the code's own message.
	other := "!other:courier.local"
	require.NoError(t, w.s.UpsertRoom(context.Background(), store.Room{ID: other, Network: "whatsapp", Name: "Other"}))
	elsewhere := say(t, w.s, other, "@whatsapp_contact:courier.local", "elsewhere", time.Now())
	for _, id := range []string{"$nope", elsewhere} {
		e := c.fails(CodeNotFound, "room.events", map[string]any{"room_id": w.room, "around": id})
		require.Equal(t, "no such chat or message", e.Message)
		require.Empty(t, e.Data)
	}
	c.fails(CodeNotFound, "room.events", map[string]any{"room_id": "!nope:courier.local", "around": middle})
}

func TestRoomEventsCursorsAreExclusive(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	at := map[string]any{"ts": 1760599990000, "seq": 1}
	for _, p := range []map[string]any{
		{"before": at, "after": at},
		{"before": at, "around": w.events[1]},
		{"after": at, "around": w.events[1]},
		{"before": at, "after": at, "around": w.events[1]},
	} {
		p["room_id"] = w.room
		e := c.fails(CodeInvalidParams, "room.events", p)
		require.Equal(t, "only one of before, after and around can be given", reason(t, e), "%v", p)
	}
	e := c.fails(CodeInvalidParams, "room.events", map[string]any{"room_id": w.room, "after": map[string]any{"ts": 1}})
	require.Equal(t, "after needs ts and seq", reason(t, e))
	e = c.fails(CodeInvalidParams, "room.events", map[string]any{"room_id": w.room, "around": ""})
	require.Equal(t, "around is required", reason(t, e))
}

func TestSearchNeverLogsWhatWasSearchedFor(t *testing.T) {
	const secret = "do-not-log-7c1d"
	// A database error can quote the query (FTS5's syntax errors do): its text never reaches the log, though it is
	// still the error underneath, and still an internal one on the wire.
	cause := fmt.Errorf(`fts5: syntax error near "%s"`, secret)
	err := searchError(cause)
	require.NotContains(t, err.Error(), secret)
	require.ErrorIs(t, err, cause)
	e, unknown := classify(err)
	require.True(t, unknown)
	require.Equal(t, CodeInternal, e.Code)
	require.Equal(t, CodeInvalidParams, toError(searchError(store.ErrBadCursor)).Code, "errors with a code keep it")

	// Over the socket: a store that fails mid-search logs the method and no text.
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	var logs syncBuffer
	path := serve(t, Deps{Store: s, Search: search.New(s), Version: "test-1", Log: zerolog.New(&logs)})
	c := dial(t, path)
	c.hello()
	c.ok("search.query", map[string]any{"text": secret}, nil)
	require.Empty(t, logs.String(), "a search that works logs nothing")
	require.NoError(t, s.Close())
	c.fails(CodeInternal, "search.query", map[string]any{"text": secret})
	require.Eventually(t, func() bool { return strings.Contains(logs.String(), "search.query") }, 5*time.Second, 10*time.Millisecond)
	require.NotContains(t, logs.String(), secret)
}
