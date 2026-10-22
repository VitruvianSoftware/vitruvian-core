// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package search

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf16"
	"unicode/utf8"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// The fixture: chats and people named "Garden …", and messages holding "garden" of every kind. All text is
// synthetic.

var t0 = time.Date(2026, 3, 1, 9, 0, 0, 0, time.UTC)

type fixture struct {
	s   *store.Store
	svc *Service
	n   int // messages added so far
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return &fixture{s: s, svc: New(s)}
}

func (f *fixture) chat(t *testing.T, id, network, name string, direct bool) string {
	t.Helper()
	require.NoError(t, f.s.UpsertRoom(context.Background(), store.Room{ID: id, Network: network, Name: name, IsDirect: direct, CreatedAt: t0}))
	return id
}

// person puts someone named name in roomID.
func (f *fixture) person(t *testing.T, roomID, userID, name string) {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, f.s.SetProfile(ctx, userID, &name, nil))
	b, err := json.Marshal(map[string]string{"membership": "join", "displayname": name})
	require.NoError(t, err)
	require.NoError(t, f.s.SetMember(ctx, roomID, userID, b))
}

// msg adds a message of kind (text, image, video, file) to roomID, a minute after the one before, and returns its
// event ID.
func (f *fixture) msg(t *testing.T, roomID, sender, kind, body string) string {
	t.Helper()
	f.n++
	c := map[string]any{"msgtype": "m." + kind, "body": body}
	if kind != "text" {
		c["url"] = fmt.Sprintf("mxc://courier.test/f%d", f.n)
	}
	b, err := json.Marshal(c)
	require.NoError(t, err)
	id := fmt.Sprintf("$m%d", f.n)
	_, err = f.s.InsertEvent(context.Background(), store.Event{
		RoomID: roomID, EventID: id, Sender: sender, Type: "m.room.message", Content: b,
		TS: t0.Add(time.Duration(f.n) * time.Minute), Status: "sent",
	})
	require.NoError(t, err)
	return id
}

func (f *fixture) query(t *testing.T, r Request) Response {
	t.Helper()
	res, err := f.svc.Query(context.Background(), r)
	require.NoError(t, err)
	return res
}

// garden is a fixture with 30 group chats named "Garden <i>", each with a person "Garden person <i>" who has no
// DM with me, and in them 30 text messages and 15 images and 15 videos saying "garden".
func garden(t *testing.T) *fixture {
	t.Helper()
	f := newFixture(t)
	for i := range 30 {
		room := f.chat(t, fmt.Sprintf("!g%02d:courier.local", i), "whatsapp", fmt.Sprintf("Garden %d", i), false)
		f.person(t, room, fmt.Sprintf("@wa-p%02d:courier.local", i), fmt.Sprintf("Garden person %d", i))
	}
	for i := range 60 {
		kind := []string{"text", "image", "text", "video"}[i%4]
		r := i / 2 // each chat has a text message and an image or a video
		f.msg(t, fmt.Sprintf("!g%02d:courier.local", r), fmt.Sprintf("@wa-p%02d:courier.local", r), kind, fmt.Sprintf("garden note %d", i))
	}
	return f
}

func kindsOf(p *MessagePage) map[string]int {
	out := map[string]int{}
	for _, h := range p.Hits {
		out[h.Kind]++
	}
	return out
}

func badReason(t *testing.T, err error) string {
	t.Helper()
	require.ErrorIs(t, err, ErrBadRequest)
	var br *BadRequestError
	require.True(t, errors.As(err, &br))
	return br.Reason
}

func TestDefaultSectionsAndLimits(t *testing.T) {
	f := garden(t)
	res := f.query(t, Request{Text: "garden"})
	require.Len(t, res.Chats, 5, "chats default to 5")
	require.Len(t, res.InGroups, 5, "in groups default to 5")
	require.NotNil(t, res.Media)
	require.Len(t, res.Media.Hits, 12, "media defaults to 12")
	require.NotEmpty(t, res.Media.Next, "30 media, so there is a next page")
	require.NotNil(t, res.Messages)
	require.Len(t, res.Messages.Hits, 20, "messages default to 20")
	require.NotEmpty(t, res.Messages.Next)
	require.Nil(t, res.LastArchived)
	require.Empty(t, res.Hint)
	require.True(t, res.Complete)

	// A limit applies to every section asked for, up to the smallest most among them.
	res = f.query(t, Request{Text: "garden", Sections: []Section{Chats, InGroups}, Limit: 100})
	require.Len(t, res.Chats, 30)
	require.Len(t, res.InGroups, 30)
	require.Nil(t, res.Media, "not asked for")
	require.Nil(t, res.Messages, "not asked for")
	res = f.query(t, Request{Text: "garden", Limit: 50})
	require.Len(t, res.Messages.Hits, 30)
	require.Empty(t, res.Messages.Next)
	require.Len(t, res.Media.Hits, 30)

	for _, tc := range []struct {
		sections []Section
		limit    int
		reason   string
	}{
		{nil, 51, "limit must be 1 to 50"},
		{[]Section{Chats}, 101, "limit must be 1 to 100"},
		{[]Section{Chats, Messages}, 51, "limit must be 1 to 50"},
		{[]Section{Media}, -1, "limit must be 1 to 50"},
	} {
		_, err := f.svc.Query(context.Background(), Request{Text: "garden", Sections: tc.sections, Limit: tc.limit})
		require.Equal(t, tc.reason, badReason(t, err), "%v %d", tc.sections, tc.limit)
	}
	require.Equal(t, 100, MaxLimit([]Section{Chats, InGroups}))
	require.Equal(t, 50, MaxLimit(nil))
}

func TestMediaAndMessagesSplitByKind(t *testing.T) {
	f := garden(t)
	res := f.query(t, Request{Text: "garden", Limit: 50})
	require.Equal(t, map[string]int{"image": 15, "video": 15}, kindsOf(res.Media))
	require.Equal(t, map[string]int{"text": 30}, kindsOf(res.Messages), "messages keep everything but images and videos")

	res = f.query(t, Request{Text: "garden", Limit: 50, Filters: Filters{Kinds: []string{"image"}}})
	require.Equal(t, map[string]int{"image": 15}, kindsOf(res.Media))
	require.Nil(t, res.Messages, "a kinds filter of only images leaves messages out")

	res = f.query(t, Request{Text: "garden", Limit: 50, Filters: Filters{Kinds: []string{"text"}}})
	require.Nil(t, res.Media, "a kinds filter with no image or video leaves media out")
	require.Equal(t, map[string]int{"text": 30}, kindsOf(res.Messages))

	res = f.query(t, Request{Text: "garden", Limit: 50, Filters: Filters{Kinds: []string{"video", "text"}}})
	require.Equal(t, map[string]int{"video": 15}, kindsOf(res.Media))
	require.Equal(t, map[string]int{"text": 30}, kindsOf(res.Messages))

	// Other kinds stay in messages: a file is a message, not media.
	f.msg(t, "!g00:courier.local", "@wa-p00:courier.local", "file", "garden plan")
	res = f.query(t, Request{Text: "garden plan"})
	require.Equal(t, map[string]int{"file": 1}, kindsOf(res.Messages))
	require.Empty(t, res.Media.Hits)

	// Sender narrows media and messages only.
	mine := f.msg(t, "!g01:courier.local", string(ids.Me), "text", "garden gloves")
	res = f.query(t, Request{Text: "garden", Filters: Filters{Sender: "me"}})
	require.Len(t, res.Messages.Hits, 1)
	require.Equal(t, mine, res.Messages.Hits[0].Event.EventID)
	require.Empty(t, res.Media.Hits)
	require.Len(t, res.Chats, 5, "a sender doesn't narrow chats")
}

func TestRoomFilterLeavesOutChatsAndPeople(t *testing.T) {
	f := garden(t)
	room := "!g03:courier.local"
	res := f.query(t, Request{Text: "garden", Filters: Filters{RoomIDs: []string{room}}})
	require.Nil(t, res.Chats)
	require.Nil(t, res.InGroups)
	require.NotNil(t, res.Messages)
	require.NotEmpty(t, res.Messages.Hits)
	for _, h := range append(res.Messages.Hits, res.Media.Hits...) {
		require.Equal(t, room, h.Event.RoomID)
	}

	// Filters only, no text: the chat's media, newest first.
	res = f.query(t, Request{Filters: Filters{RoomIDs: []string{room}}, Sections: []Section{Media}})
	require.NotEmpty(t, res.Media.Hits)

	_, err := f.svc.Query(context.Background(), Request{Text: "garden", Filters: Filters{RoomIDs: []string{"!nope:courier.local"}}})
	require.ErrorIs(t, err, store.ErrNotFound)
	require.ErrorIs(t, err, ErrNoSuchChat)

	tooMany := make([]string, MaxRoomIDs+1)
	for i := range tooMany {
		tooMany[i] = room
	}
	_, err = f.svc.Query(context.Background(), Request{Text: "garden", Filters: Filters{RoomIDs: tooMany}})
	require.Equal(t, "room_ids must name 1 to 100 chats", badReason(t, err))
}

// Ruling 34: filters with no text browse their messages (Received + Last week, Direct messages, Groups). A section
// that had nothing to look for didn't run, so it is null, not an empty list that would read as "nothing matches":
// chats and people need words, and a filter that only leaves messages out picks none to list.
func TestFiltersAloneBrowseAndWhatDidNotRunIsNull(t *testing.T) {
	f := garden(t)
	for name, filters := range map[string]Filters{
		"received in a period": {Sender: "others", Since: t0.Add(30 * time.Minute)},
		"received":             {Sender: "others"},
		"groups":               {ChatType: "group"},
		"until":                {Until: t0.Add(10 * time.Minute)},
	} {
		res := f.query(t, Request{Filters: filters})
		require.Nil(t, res.Chats, name)
		require.Nil(t, res.InGroups, name)
		require.NotNil(t, res.Messages, name)
		require.NotEmpty(t, res.Messages.Hits, name)
		require.NotNil(t, res.Media, name)
		require.NotEmpty(t, res.Media.Hits, name)
		require.Empty(t, res.Hint, name)
	}
	// Ran and found nothing: empty. The garden has no DMs.
	res := f.query(t, Request{Filters: Filters{ChatType: "dm"}})
	require.NotNil(t, res.Messages)
	require.Empty(t, res.Messages.Hits)
	// Nothing to list: null.
	res = f.query(t, Request{Filters: Filters{ExcludeMuted: true}, Sections: []Section{Messages}})
	require.Nil(t, res.Messages)
}

func TestEmptyTextGivesOnlyLastArchived(t *testing.T) {
	f := garden(t)
	ctx := context.Background()
	res := f.query(t, Request{})
	require.Equal(t, Response{Complete: true, Bookmarks: &MessagePage{Hits: []Hit{}}}, res,
		"nothing archived or bookmarked yet: nothing at all")

	f.s.SetClock(func() time.Time { return t0.Add(time.Hour) })
	_, err := f.s.SetArchived(ctx, []string{"!g01:courier.local"}, true)
	require.NoError(t, err)
	f.s.SetClock(func() time.Time { return t0.Add(2 * time.Hour) })
	_, err = f.s.SetArchived(ctx, []string{"!g02:courier.local"}, true)
	require.NoError(t, err)

	for _, text := range []string{"", "   "} {
		res = f.query(t, Request{Text: text})
		require.NotNil(t, res.LastArchived)
		require.Equal(t, "!g02:courier.local", res.LastArchived.ID)
		require.Nil(t, res.Chats)
		require.Nil(t, res.InGroups)
		require.Nil(t, res.Media)
		require.Nil(t, res.Messages)
		require.NotNil(t, res.Bookmarks, "the home lists the newest bookmarks, none here")
		require.Empty(t, res.Bookmarks.Hits)
		require.Empty(t, res.Hint)
	}

	res = f.query(t, Request{OpenRoomID: "!g02:courier.local"})
	require.Equal(t, "!g01:courier.local", res.LastArchived.ID, "the open chat is left out")

	res = f.query(t, Request{Filters: Filters{Networks: []string{"whatsapp"}}})
	require.Nil(t, res.LastArchived, "only with no filters")
	res = f.query(t, Request{Text: "garden"})
	require.Nil(t, res.LastArchived, "only with no text")

	_, err = f.svc.Query(ctx, Request{Sections: []Section{Messages}, Cursor: "eyJ4IjoxfQ"})
	require.ErrorIs(t, err, store.ErrBadCursor, "no query of this kind hands out a cursor")
}

func TestHints(t *testing.T) {
	f := garden(t)
	f.msg(t, "!g00:courier.local", "@wa-p00:courier.local", "text", "東京タワー")

	for _, text := range []string{"🎉", "🎉 !!", "?", "\"\""} {
		res := f.query(t, Request{Text: text})
		require.Equal(t, Response{Complete: true, Hint: HintEmojiOnly}, res, "%q runs nothing", text)
	}

	res := f.query(t, Request{Text: "g"})
	require.Equal(t, HintNeedMoreLetters, res.Hint)
	require.Len(t, res.Chats, 5, "chats are searched from the first letter")
	require.Len(t, res.InGroups, 5)
	require.Nil(t, res.Media, "media needs 2 letters")
	require.Nil(t, res.Messages, "messages need 2 letters")

	res = f.query(t, Request{Text: "ga"})
	require.Empty(t, res.Hint)
	require.Len(t, res.Messages.Hits, 20)

	res = f.query(t, Request{Text: "東"})
	require.Empty(t, res.Hint, "one character of a script without spaces is a word")
	require.Len(t, res.Messages.Hits, 1)
}

func TestCursorNeedsOneSection(t *testing.T) {
	f := garden(t)
	ctx := context.Background()
	first := f.query(t, Request{Text: "garden", Sections: []Section{Messages}, Limit: 7})
	require.Len(t, first.Messages.Hits, 7)
	require.NotEmpty(t, first.Messages.Next)

	for _, sections := range [][]Section{nil, {Chats}, {InGroups}, {Media, Messages}, {Chats, Messages}} {
		_, err := f.svc.Query(ctx, Request{Text: "garden", Sections: sections, Cursor: first.Messages.Next})
		require.Equal(t, "cursor needs exactly one of bookmarks, media or messages", badReason(t, err), "%v", sections)
	}
	_, err := f.svc.Query(ctx, Request{Text: "garden", Sections: []Section{"starred"}})
	require.Equal(t, "sections is not one of chats, in_groups, bookmarks, media, messages", badReason(t, err))

	// The cursor carries on where the first page stopped, and the limit may change.
	seen := map[string]bool{}
	for _, h := range first.Messages.Hits {
		seen[h.Event.EventID] = true
	}
	next := first.Messages.Next
	for next != "" {
		res := f.query(t, Request{Text: "garden", Sections: []Section{Messages}, Cursor: next, Limit: 10})
		require.Nil(t, res.Chats)
		require.Nil(t, res.Media)
		for _, h := range res.Messages.Hits {
			require.False(t, seen[h.Event.EventID], "a hit repeats across pages")
			seen[h.Event.EventID] = true
		}
		next = res.Messages.Next
	}
	require.Len(t, seen, 30)

	// A messages cursor isn't a media one: the store refuses a cursor of another query.
	_, err = f.svc.Query(ctx, Request{Text: "garden", Sections: []Section{Media}, Cursor: first.Messages.Next})
	require.ErrorIs(t, err, store.ErrBadCursor)
}

func TestBadRequestsSayWhy(t *testing.T) {
	f := newFixture(t)
	day := t0
	for _, tc := range []struct {
		r      Request
		reason string
	}{
		{Request{Text: strings.Repeat("a", MaxTextRunes+1)}, "text is too long"},
		{Request{Text: "ab", Filters: Filters{Kinds: []string{"gif"}}}, "unknown kind"},
		{Request{Text: "ab", Filters: Filters{Sender: "someone"}}, "unknown sender"},
		{Request{Text: "ab", Filters: Filters{ChatType: "channel"}}, "unknown chat_type"},
		{Request{Text: "ab", Filters: Filters{Since: day, Until: day}}, "since must be before until"},
		{Request{Text: "ab", Filters: Filters{Since: day.Add(time.Hour), Until: day}}, "since must be before until"},
	} {
		_, err := f.svc.Query(context.Background(), tc.r)
		require.Equal(t, tc.reason, badReason(t, err))
	}
	// 500 characters, however many bytes, is fine.
	f.query(t, Request{Text: strings.Repeat("é", MaxTextRunes)})
	// A user ID is a sender too (milestone 5's API takes one).
	f.query(t, Request{Text: "ab", Filters: Filters{Sender: "@wa-p01:courier.local"}})
}

func TestSnippetsHighlightTheWords(t *testing.T) {
	f := newFixture(t)
	room := f.chat(t, "!s:courier.local", "signal", "Plans", true)
	long := strings.Repeat("filler words go here ", 30) + "the Gärtner said café at noon " + strings.Repeat("more filler after ", 30)
	f.msg(t, room, "@sg-x:courier.local", "text", long)

	res := f.query(t, Request{Text: "gartner cafe", Sections: []Section{Messages}})
	require.Len(t, res.Messages.Hits, 1)
	h := res.Messages.Hits[0]
	require.Equal(t, long, h.Text, "the hit keeps the whole text")
	require.LessOrEqual(t, utf8.RuneCountInString(h.Snippet), SnippetRunes)
	require.True(t, strings.HasPrefix(h.Snippet, "…") && strings.HasSuffix(h.Snippet, "…"), h.Snippet)
	units := utf16.Encode([]rune(h.Snippet))
	var marked []string
	for _, r := range h.Ranges {
		marked = append(marked, string(utf16.Decode(units[r.Start:r.Start+r.Length])))
	}
	require.Equal(t, []string{"Gärtner", "café"}, marked, "accents fold for matching, and the snippet shows what was written")

	// A word still being typed is highlighted as a prefix.
	res = f.query(t, Request{Text: "gärt", Sections: []Section{Messages}})
	h = res.Messages.Hits[0]
	units = utf16.Encode([]rune(h.Snippet))
	require.Len(t, h.Ranges, 1)
	require.Equal(t, "Gärtner", string(utf16.Decode(units[h.Ranges[0].Start:h.Ranges[0].Start+h.Ranges[0].Length])))
}

func TestCompleteFollowsTheBackfill(t *testing.T) {
	s, _ := seeded(t, 50)
	defer s.Close()
	svc := New(s)
	ctx := context.Background()
	res, err := svc.Query(ctx, Request{Text: "seed"})
	require.NoError(t, err)
	require.False(t, res.Complete, "older messages are still being added")
	require.Empty(t, res.Messages.Hits, "and these aren't in yet")

	RunBackfill(ctx, s, zerolog.Nop())
	res, err = svc.Query(ctx, Request{Text: "seed", Sections: []Section{Messages}, Limit: 50})
	require.NoError(t, err)
	require.True(t, res.Complete)
	require.Len(t, res.Messages.Hits, 50)
}

// The Bookmarks section (inventory 01 §12) finds what the other sections find, of every kind, but only messages I
// bookmarked; a deleted message's bookmark isn't listed. Like messages, it needs 2 letters, and pages with a cursor.
func TestBookmarksSectionMatchesOnlyBookmarks(t *testing.T) {
	f := garden(t)
	ctx := context.Background()
	text := "$m1"  // "garden note 0", a text message
	image := "$m2" // "garden note 1", an image
	for _, id := range []string{text, image, "$m3"} {
		require.NoError(t, f.s.SetBookmarked(ctx, id, true))
	}

	res := f.query(t, Request{Text: "garden"})
	require.NotNil(t, res.Bookmarks)
	require.ElementsMatch(t, []string{text, image, "$m3"}, hitIDs(res.Bookmarks), "every kind, only bookmarks")
	require.Len(t, res.Messages.Hits, 20, "the other sections are as they were")

	res = f.query(t, Request{Text: "garden note 1", Sections: []Section{Bookmarks}})
	require.Equal(t, []string{image}, hitIDs(res.Bookmarks))
	require.Nil(t, res.Messages, "not asked for")
	require.Nil(t, res.Chats, "not asked for")

	res = f.query(t, Request{Text: "garden", Sections: []Section{Bookmarks}, Filters: Filters{Kinds: []string{"image"}}})
	require.Equal(t, []string{image}, hitIDs(res.Bookmarks), "kinds narrow bookmarks too")

	res = f.query(t, Request{Text: "g"})
	require.Nil(t, res.Bookmarks, "bookmarks need 2 letters, as messages do")

	require.NoError(t, f.s.SetBookmarked(ctx, "$m3", false))
	first := f.query(t, Request{Text: "garden", Sections: []Section{Bookmarks}, Limit: 1})
	require.Len(t, first.Bookmarks.Hits, 1)
	require.NotEmpty(t, first.Bookmarks.Next)
	second := f.query(t, Request{Text: "garden", Sections: []Section{Bookmarks}, Cursor: first.Bookmarks.Next, Limit: 1})
	require.Len(t, second.Bookmarks.Hits, 1)
	require.ElementsMatch(t, []string{text, image}, append(hitIDs(first.Bookmarks), hitIDs(second.Bookmarks)...))
	require.Empty(t, second.Bookmarks.Next)
}

// Inferred (inventory 01 §12): before anything is typed, the Bookmarks section holds the five newest bookmarks,
// newest bookmark first, whenever it was sent.
func TestHomeHoldsTheFiveNewestBookmarks(t *testing.T) {
	f := garden(t)
	ctx := context.Background()
	var order []string
	for i, id := range []string{"$m40", "$m3", "$m22", "$m7", "$m15", "$m31", "$m9"} {
		f.s.SetClock(func() time.Time { return t0.Add(time.Duration(100+i) * time.Hour) })
		require.NoError(t, f.s.SetBookmarked(ctx, id, true))
		order = append([]string{id}, order...)
	}
	res := f.query(t, Request{})
	require.Equal(t, order[:5], hitIDs(res.Bookmarks))
	require.Empty(t, res.Bookmarks.Next, "the home has no further page")
	for _, h := range res.Bookmarks.Hits {
		require.NotEmpty(t, h.Snippet, "each hit reads as the message does")
	}

	res = f.query(t, Request{Sections: []Section{Chats}})
	require.Nil(t, res.Bookmarks, "not asked for")
	res = f.query(t, Request{Filters: Filters{ChatType: "group"}, Sections: []Section{Bookmarks}})
	require.NotNil(t, res.Bookmarks)
	require.Len(t, res.Bookmarks.Hits, 5, "filters alone browse the bookmarks they pick, newest message first")
}

func hitIDs(p *MessagePage) []string {
	out := []string{}
	for _, h := range p.Hits {
		out = append(out, h.Event.EventID)
	}
	return out
}
