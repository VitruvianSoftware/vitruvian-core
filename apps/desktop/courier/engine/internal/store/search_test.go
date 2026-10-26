// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
)

// The search fixture: 3 networks, 12 chats (DMs and groups, one in each place), and 200 messages, every one of
// them holding the word "note" and a word only it has ("n<i>"). All text is synthetic.

// searchT0 is the time of the fixture's first message; message i is i minutes later.
var searchT0 = time.Date(2026, 1, 1, 9, 0, 0, 0, time.UTC)

type fixtureRoom struct {
	id, network, name string
	direct            bool
	ghost, ghostName  string
	place             string
}

var fixtureRooms = []fixtureRoom{
	{"!wa-dm1", "whatsapp", "Anna", true, "@wa-anna:courier.local", "Anna Berg", "inbox"},
	{"!wa-dm2", "whatsapp", "+1 555 0100", true, "@wa-joseph:courier.local", "Joseph Bloggs", "archive"},
	{"!wa-grp1", "whatsapp", "Book club (Andrew)", false, "@wa-andrew:courier.local", "Andrew Kay", "inbox"},
	{"!wa-grp2", "whatsapp", "Joanna's group", false, "@wa-joanna:courier.local", "Joanna Reed", "low_priority"},
	{"!tg-dm1", "telegram", "Bram", true, "@tg-bram:courier.local", "Bram Olsen", "hidden"},
	{"!tg-dm2", "telegram", "Cleo", true, "@tg-cleo:courier.local", "Cleo Ward", "requests"},
	{"!tg-grp1", "telegram", "Running", false, "@tg-ruth:courier.local", "Ruth Hale", "inbox"}, // muted by me
	{"!tg-grp2", "telegram", "Family", false, "@tg-finn:courier.local", "Finn Hale", "archive"},
	{"!sg-dm1", "signal", "Dana", true, "@sg-dana:courier.local", "Dana Cole", "inbox"},
	{"!sg-dm2", "signal", "Eli", true, "@sg-eli:courier.local", "Eli Park", "inbox"},
	{"!sg-grp1", "signal", "Climbing", false, "@sg-cara:courier.local", "Cara Moss", "inbox"}, // muted by a label
	{"!sg-grp2", "signal", "Choir", false, "@sg-gus:courier.local", "Gus Tan", "inbox"},
}

type fixtureMsg struct {
	id, room, sender, kind string // kind: text, link, image, video or file
	ts                     time.Time
}

type searchFixture struct {
	s     *Store
	msgs  []fixtureMsg // oldest first
	rooms map[string]fixtureRoom
}

func memberContent(name string) string {
	b, _ := json.Marshal(map[string]string{"membership": "join", "displayname": name})
	return string(b)
}

// fixtureContent is message i's content for its kind.
func fixtureContent(i int, kind string) string {
	var c map[string]any
	switch kind {
	case "image":
		c = map[string]any{
			"msgtype": "m.image", "body": fmt.Sprintf("note n%d", i), "url": fmt.Sprintf("mxc://courier.test/img%d", i),
			"info": map[string]string{"thumbnail_url": fmt.Sprintf("mxc://courier.test/thumb%d", i)},
		}
	case "video":
		c = map[string]any{"msgtype": "m.video", "body": fmt.Sprintf("note n%d", i), "url": fmt.Sprintf("mxc://courier.test/vid%d", i)}
	case "file":
		c = map[string]any{"msgtype": "m.file", "body": fmt.Sprintf("note n%d", i), "url": fmt.Sprintf("mxc://courier.test/file%d", i)}
	case "link":
		c = map[string]any{"msgtype": "m.text", "body": fmt.Sprintf("note n%d https://example.test/page%d", i, i)}
	default:
		c = map[string]any{"msgtype": "m.text", "body": fmt.Sprintf("note n%d", i)}
	}
	b, _ := json.Marshal(c)
	return string(b)
}

func newSearchFixture(t *testing.T) *searchFixture {
	t.Helper()
	s, ctx := open(t), context.Background()
	f := &searchFixture{s: s, rooms: map[string]fixtureRoom{}}
	s.SetClock(func() time.Time { return searchT0 })
	for _, r := range fixtureRooms {
		f.rooms[r.id] = r
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: r.id, Network: r.network, Name: r.name, IsDirect: r.direct, CreatedAt: time.Unix(1, 0)}))
		require.NoError(t, s.SetProfile(ctx, r.ghost, ptr(r.ghostName), ptr("mxc://courier.test/avatar-"+r.id[1:])))
		require.NoError(t, s.SetMember(ctx, r.id, r.ghost, json.RawMessage(memberContent(r.ghostName))))
		require.NoError(t, s.SetMember(ctx, r.id, me, json.RawMessage(memberContent("Me"))))
	}
	kinds := []string{"image", "video", "link", "file", "text", "text", "text", "text", "text", "text"}
	for i := 0; i < 200; i++ {
		r := fixtureRooms[i%len(fixtureRooms)]
		m := fixtureMsg{id: fmt.Sprintf("$n%d", i), room: r.id, sender: r.ghost, kind: kinds[i%len(kinds)], ts: searchT0.Add(time.Duration(i) * time.Minute)}
		if i%3 == 0 {
			m.sender = me
		}
		mkMsg(t, s, m.room, m.id, m.sender, "m.room.message", fixtureContent(i, m.kind), m.ts)
		f.msgs = append(f.msgs, m)
	}
	// One chat in each place.
	_, err := s.SetArchived(ctx, []string{"!wa-dm2"}, true)
	require.NoError(t, err)
	s.SetClock(func() time.Time { return searchT0.Add(time.Hour) })
	_, err = s.SetArchived(ctx, []string{"!tg-grp2"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!wa-grp2"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!tg-dm1"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetRequest(ctx, "!tg-dm2", true))
	require.NoError(t, s.SetMuted(ctx, "!tg-grp1", true))
	quiet := mkLabel(t, s, "Quiet")
	_, err = s.db.Exec(ctx, "UPDATE labels SET muted = 1 WHERE label_id = $1", quiet.ID)
	require.NoError(t, err)
	_, err = s.SetLabel(ctx, []string{"!sg-grp1"}, quiet.ID, true)
	require.NoError(t, err)
	return f
}

// terms is what a person typing q searches for.
func terms(q string) []searchtext.Term { return searchtext.Parse(q) }

// searchAll reads q to its last page and returns every hit, in order.
func searchAll(t *testing.T, s *Store, q MessageQuery) []MessageHit {
	t.Helper()
	var out []MessageHit
	for i := 0; ; i++ {
		require.Less(t, i, 10000, "paging never ends")
		hits, next, err := s.SearchMessages(context.Background(), q)
		require.NoError(t, err)
		out = append(out, hits...)
		if next == "" {
			return out
		}
		q.After = next
	}
}

func hitIDs(hits []MessageHit) []string {
	out := []string{}
	for _, h := range hits {
		out = append(out, h.Event.EventID)
	}
	return out
}

// newestFirst is the IDs of the fixture's messages that keep says to, newest first.
func (f *searchFixture) newestFirst(keep func(m fixtureMsg) bool) []string {
	out := []string{}
	for i := len(f.msgs) - 1; i >= 0; i-- {
		if keep(f.msgs[i]) {
			out = append(out, f.msgs[i].id)
		}
	}
	return out
}

func TestMatchingEndToEnd(t *testing.T) {
	f := newSearchFixture(t)
	at := searchT0.Add(24 * time.Hour)
	for i, body := range []string{"José said hi", "Lunch at the café", "hello there", "東京タワー is tall", "dinner at eight"} {
		mkMsg(t, f.s, "!wa-dm1", fmt.Sprintf("$m%d", i), "@wa-anna:courier.local", "m.room.message", text(body), at.Add(time.Duration(i)*time.Second))
	}
	for q, want := range map[string][]string{
		"jose": {"$m0"}, "CAFE": {"$m1"}, "Ｈｅｌｌｏ": {"$m2"}, "東京": {"$m3"}, "京タ": {"$m3"},
		"dinn": {"$m4"}, "dinn ": {},
	} {
		require.Equal(t, want, hitIDs(searchAll(t, f.s, MessageQuery{Terms: terms(q), Limit: 10})), q)
	}
}

func TestAllWordsMustMatchAndPhrasesKeepOrder(t *testing.T) {
	f := newSearchFixture(t)
	at := searchT0.Add(24 * time.Hour)
	mkMsg(t, f.s, "!sg-dm1", "$a", me, "m.room.message", text("see you soon"), at)
	mkMsg(t, f.s, "!sg-dm1", "$b", me, "m.room.message", text("soon, see"), at.Add(time.Second))
	mkMsg(t, f.s, "!sg-dm1", "$c", me, "m.room.message", text("see the moon"), at.Add(2*time.Second))
	require.Equal(t, []string{"$b", "$a"}, hitIDs(searchAll(t, f.s, MessageQuery{Terms: terms("see soon"), Limit: 10})))
	require.Equal(t, []string{"$a"}, hitIDs(searchAll(t, f.s, MessageQuery{Terms: terms(`"see you"`), Limit: 10})))
}

func TestPartialMatchesComeAfterFullOnes(t *testing.T) {
	f := newSearchFixture(t)
	at := searchT0.Add(24 * time.Hour)
	// Full and partial matches interleave in time, so only the phases can put the full ones first.
	bodies := []string{"alpha beta", "alpha", "beta gamma", "beta alpha", "alpha only", "alpha and beta", "just beta", "alpha", "beta, then alpha"}
	var full, partial []string
	for i, body := range bodies {
		id := fmt.Sprintf("$p%d", i)
		mkMsg(t, f.s, "!sg-dm2", id, me, "m.room.message", text(body), at.Add(time.Duration(i)*time.Second))
		if strings.Contains(body, "alpha") && strings.Contains(body, "beta") {
			full = append([]string{id}, full...)
		} else {
			partial = append([]string{id}, partial...)
		}
	}
	q := MessageQuery{Terms: terms("alpha beta"), Partial: true, Limit: 3}
	var got []string
	var partialFlags []bool
	pages := 0
	for {
		hits, next, err := f.s.SearchMessages(context.Background(), q)
		require.NoError(t, err)
		require.LessOrEqual(t, len(hits), 3)
		pages++
		for _, h := range hits {
			got = append(got, h.Event.EventID)
			partialFlags = append(partialFlags, h.Partial)
		}
		if next == "" {
			break
		}
		q.After = next
	}
	require.Equal(t, append(slices.Clone(full), partial...), got, "full matches newest first, then partial ones, each once")
	for i, p := range partialFlags {
		require.Equal(t, i >= len(full), p, got[i])
	}
	require.Equal(t, 3, pages)

	// Without Partial, only the full ones; with one word, Partial changes nothing.
	require.Equal(t, full, hitIDs(searchAll(t, f.s, MessageQuery{Terms: terms("alpha beta"), Limit: 3})))
	require.Len(t, searchAll(t, f.s, MessageQuery{Terms: terms("gamma"), Partial: true, Limit: 3}), 1)
}

func TestNewestFirstAndPagesNeverRepeat(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	q := MessageQuery{Terms: terms("note"), Limit: 20}
	hits, next, err := f.s.SearchMessages(ctx, q)
	require.NoError(t, err)
	require.Len(t, hits, 20)
	require.NotEmpty(t, next)
	// A message arriving between pages is newer than the cursor, so later pages never show it.
	mkMsg(t, f.s, "!wa-dm1", "$late", me, "m.room.message", text("note arriving late"), searchT0.Add(48*time.Hour))
	q.After = next
	all := append(hits, searchAll(t, f.s, q)...)
	require.Equal(t, f.newestFirst(func(fixtureMsg) bool { return true }), hitIDs(all))

	// Every hit says what the fixture made it.
	byID := map[string]fixtureMsg{}
	for _, m := range f.msgs {
		byID[m.id] = m
	}
	for _, h := range all {
		m, r := byID[h.Event.EventID], f.rooms[byID[h.Event.EventID].room]
		require.Equal(t, m.room, h.Event.RoomID)
		require.Equal(t, m.sender, h.Event.Sender)
		require.Equal(t, r.name, h.RoomName)
		require.Equal(t, r.network, h.Network)
		require.Equal(t, r.direct, h.IsDirect)
		require.Equal(t, r.place, h.Place, h.Event.EventID)
		require.False(t, h.Partial)
		n := strings.TrimPrefix(m.id, "$n")
		switch m.kind {
		case "image":
			require.Equal(t, "image", h.Kind)
			require.Equal(t, "mxc://courier.test/thumb"+n, h.MediaURI)
		case "video":
			require.Equal(t, "video", h.Kind)
			require.Equal(t, "mxc://courier.test/vid"+n, h.MediaURI)
		case "file":
			require.Equal(t, "file", h.Kind)
			require.Empty(t, h.MediaURI)
		default:
			require.Equal(t, "text", h.Kind)
			require.Empty(t, h.MediaURI)
		}
		require.True(t, strings.HasPrefix(h.Text, "note n"+n), h.Text)
	}
	require.Equal(t, "$late", hitIDs(searchAll(t, f.s, MessageQuery{Terms: terms("note"), Limit: 1}))[0], "a new search sees it")
}

func TestFiltersNarrowMessages(t *testing.T) {
	f := newSearchFixture(t)
	note := terms("note")
	ghostOf := func(room string) string { return f.rooms[room].ghost }
	since, until := f.msgs[50].ts, f.msgs[100].ts
	for _, tc := range []struct {
		name string
		q    MessageQuery
		keep func(m fixtureMsg) bool
	}{
		{"a room", MessageQuery{RoomIDs: []string{"!wa-grp1"}}, func(m fixtureMsg) bool { return m.room == "!wa-grp1" }},
		{"two rooms", MessageQuery{RoomIDs: []string{"!tg-dm2", "!wa-grp1"}}, func(m fixtureMsg) bool { return m.room == "!wa-grp1" || m.room == "!tg-dm2" }},
		{"a network", MessageQuery{Networks: []string{"telegram"}}, func(m fixtureMsg) bool { return f.rooms[m.room].network == "telegram" }},
		{"me", MessageQuery{Sender: "me"}, func(m fixtureMsg) bool { return m.sender == me }},
		{"others", MessageQuery{Sender: "others"}, func(m fixtureMsg) bool { return m.sender != me }},
		{"a person", MessageQuery{Sender: ghostOf("!sg-grp2")}, func(m fixtureMsg) bool { return m.sender == ghostOf("!sg-grp2") }},
		{"dm", MessageQuery{ChatType: "dm"}, func(m fixtureMsg) bool { return f.rooms[m.room].direct }},
		{"group", MessageQuery{ChatType: "group"}, func(m fixtureMsg) bool { return !f.rooms[m.room].direct }},
		{"images", MessageQuery{Kinds: []string{"image"}}, func(m fixtureMsg) bool { return m.kind == "image" }},
		{"not images or videos", MessageQuery{NotKinds: []string{"image", "video"}}, func(m fixtureMsg) bool { return m.kind != "image" && m.kind != "video" }},
		{"links", MessageQuery{Kinds: []string{"link"}}, func(m fixtureMsg) bool { return m.kind == "link" }},
		{"since and until", MessageQuery{Since: since, Until: until}, func(m fixtureMsg) bool { return !m.ts.Before(since) && m.ts.Before(until) }},
		{"no low priority", MessageQuery{ExcludeLowPriority: true}, func(m fixtureMsg) bool { return m.room != "!wa-grp2" }},
		{"not muted", MessageQuery{ExcludeMuted: true}, func(m fixtureMsg) bool { return m.room != "!tg-grp1" && m.room != "!sg-grp1" }},
		{
			"combined",
			MessageQuery{Networks: []string{"whatsapp", "signal"}, Sender: "others", ChatType: "group", NotKinds: []string{"text"}},
			func(m fixtureMsg) bool {
				r := f.rooms[m.room]
				return r.network != "telegram" && m.sender != me && !r.direct && (m.kind == "image" || m.kind == "video" || m.kind == "file")
			},
		},
	} {
		q := tc.q
		q.Terms, q.Limit = note, 7
		want := f.newestFirst(tc.keep)
		require.NotEmpty(t, want, tc.name)
		require.Less(t, len(want), 200, tc.name)
		require.Equal(t, want, hitIDs(searchAll(t, f.s, q)), tc.name)
	}

	// Filters with no text: every image, newest first; a room's messages; mine.
	require.Equal(t, f.newestFirst(func(m fixtureMsg) bool { return m.kind == "image" }),
		hitIDs(searchAll(t, f.s, MessageQuery{Kinds: []string{"image"}, Limit: 9})))
	require.Equal(t, f.newestFirst(func(m fixtureMsg) bool { return m.room == "!sg-dm1" }),
		hitIDs(searchAll(t, f.s, MessageQuery{RoomIDs: []string{"!sg-dm1"}, Limit: 50})))
	require.Equal(t, f.newestFirst(func(m fixtureMsg) bool { return m.sender == me && m.kind == "video" }),
		hitIDs(searchAll(t, f.s, MessageQuery{Sender: "me", Kinds: []string{"video"}, Limit: 50})))

	// Ruling 34: a time period, a chat type or Received alone browses too, newest first (Received + Last week,
	// Direct messages).
	for _, tc := range []struct {
		name string
		q    MessageQuery
		keep func(m fixtureMsg) bool
	}{
		{"received in a period", MessageQuery{Sender: "others", Since: since}, func(m fixtureMsg) bool { return m.sender != me && !m.ts.Before(since) }},
		{"received", MessageQuery{Sender: "others"}, func(m fixtureMsg) bool { return m.sender != me }},
		{"dm", MessageQuery{ChatType: "dm"}, func(m fixtureMsg) bool { return f.rooms[m.room].direct }},
		{"group", MessageQuery{ChatType: "group"}, func(m fixtureMsg) bool { return !f.rooms[m.room].direct }},
		{"since", MessageQuery{Since: since}, func(m fixtureMsg) bool { return !m.ts.Before(since) }},
		{"until", MessageQuery{Until: until}, func(m fixtureMsg) bool { return m.ts.Before(until) }},
	} {
		tc.q.Limit = 50
		want := f.newestFirst(tc.keep)
		require.NotEmpty(t, want, tc.name)
		require.Equal(t, want, hitIDs(searchAll(t, f.s, tc.q)), tc.name)
	}

	// An account mute counts as muted too.
	_, err := f.s.db.Exec(context.Background(), "INSERT INTO account_prefs (network, muted) VALUES ('signal', 1)")
	require.NoError(t, err)
	require.Equal(t, f.newestFirst(func(m fixtureMsg) bool { return m.room != "!tg-grp1" && f.rooms[m.room].network != "signal" }),
		hitIDs(searchAll(t, f.s, MessageQuery{Terms: note, ExcludeMuted: true, Limit: 50})))
}

func TestSearchRefusesWhatItCannotRun(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	for _, q := range []MessageQuery{
		{Limit: 10},
		{Terms: terms("🥺"), Limit: 10},
		{Terms: []searchtext.Term{{Text: "  "}}, Limit: 10},
		// Only what leaves messages out picks nothing to list.
		{NotKinds: []string{"image"}, ExcludeMuted: true, ExcludeLowPriority: true, Partial: true, Limit: 10},
	} {
		_, _, err := f.s.SearchMessages(ctx, q)
		require.ErrorIs(t, err, ErrNoQuery, "%+v", q)
	}
	tooMany := make([]string, 101)
	for i := range tooMany {
		tooMany[i] = fmt.Sprintf("!r%d", i)
	}
	for _, q := range []MessageQuery{
		{Terms: terms("note"), Limit: 51},
		{Terms: terms("note"), Limit: -1},
		{Terms: terms("note"), Kinds: []string{"gif"}},
		{Terms: terms("note"), NotKinds: []string{"Image"}},
		{Terms: terms("note"), Sender: "someone"},
		{Terms: terms("note"), ChatType: "channel"},
		{Terms: terms("note"), RoomIDs: tooMany},
	} {
		_, _, err := f.s.SearchMessages(ctx, q)
		require.ErrorIs(t, err, ErrBadValue, "%+v", q)
	}
	for _, q := range []NameQuery{{Terms: terms("anna"), Limit: 101}, {Terms: terms("anna"), ChatType: "channel"}} {
		_, err := f.s.SearchChats(ctx, q)
		require.ErrorIs(t, err, ErrBadValue, "%+v", q)
		_, err = f.s.SearchPeopleInGroups(ctx, q)
		require.ErrorIs(t, err, ErrBadValue, "%+v", q)
	}
	_, err := f.s.SearchChats(ctx, NameQuery{Terms: terms("…")})
	require.ErrorIs(t, err, ErrNoQuery)
	_, err = f.s.SearchPeopleInGroups(ctx, NameQuery{})
	require.ErrorIs(t, err, ErrNoQuery)
}

func TestEditedMessagesSnippetTheirNewText(t *testing.T) {
	f := newSearchFixture(t)
	at := searchT0.Add(24 * time.Hour)
	mkMsg(t, f.s, "!sg-dm1", "$orig", me, "m.room.message", text("lunch at noon"), at)
	mkMsg(t, f.s, "!sg-dm1", "$edit", me, "m.room.message", editTo("$orig", "lunch at one"), at.Add(time.Minute))
	hits := searchAll(t, f.s, MessageQuery{Terms: terms("lunch"), Limit: 10})
	require.Len(t, hits, 1)
	require.Equal(t, "$orig", hits[0].Event.EventID)
	require.Equal(t, "lunch at one", hits[0].Text)
	require.Empty(t, searchAll(t, f.s, MessageQuery{Terms: terms("noon "), Limit: 10}))
}

// readSeedCorpus is Task 2's corpus of strange queries (searchtext/testdata/queries.txt), one Go-quoted string a line.
func readSeedCorpus(t *testing.T) []string {
	t.Helper()
	file, err := os.Open("../searchtext/testdata/queries.txt")
	require.NoError(t, err)
	defer file.Close()
	var out []string
	sc := bufio.NewScanner(file)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		q, err := strconv.Unquote(sc.Text())
		require.NoError(t, err, sc.Text())
		out = append(out, q)
	}
	require.NoError(t, sc.Err())
	return out
}

func TestStrangeTextNeverFails(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	corpus := readSeedCorpus(t)
	require.Greater(t, len(corpus), 100)
	// The strange strings are in the index too: as messages, a chat's name and a person's name.
	for i, q := range corpus {
		mkMsg(t, f.s, "!sg-grp2", fmt.Sprintf("$odd%d", i), "@sg-gus:courier.local", "m.room.message", text(q), searchT0.Add(72*time.Hour+time.Duration(i)*time.Second))
		if i%10 == 0 {
			require.NoError(t, f.s.UpsertRoom(ctx, Room{ID: fmt.Sprintf("!odd%d", i), Network: "signal", Name: q, CreatedAt: time.Unix(1, 0)}))
			require.NoError(t, f.s.SetMember(ctx, fmt.Sprintf("!odd%d", i), fmt.Sprintf("@odd%d:courier.local", i), json.RawMessage(memberContent(q))))
		}
	}
	ok := func(err error, q string) {
		t.Helper()
		if err != nil {
			require.ErrorIs(t, err, ErrNoQuery, "%q", q)
		}
	}
	for _, q := range corpus {
		ts := terms(q)
		for _, mq := range []MessageQuery{
			{Terms: ts, Limit: 5},
			{Terms: ts, Partial: true, Limit: 5},
			{Terms: ts, Sender: "others", NotKinds: []string{"image"}, ChatType: "group", Limit: 5},
		} {
			hits, next, err := f.s.SearchMessages(ctx, mq)
			ok(err, q)
			if next != "" {
				mq.After = next
				_, _, err = f.s.SearchMessages(ctx, mq)
				require.NoError(t, err, "%q", q)
			}
			_ = hits
		}
		_, err := f.s.SearchChats(ctx, NameQuery{Terms: ts, Limit: 5})
		ok(err, q)
		_, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: ts, Networks: []string{"signal"}, Limit: 5})
		ok(err, q)
	}
}

func TestSearchCursorFromAnotherQueryIsRefused(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	q := MessageQuery{Terms: terms("note"), Networks: []string{"signal", "whatsapp"}, Limit: 5}
	_, next, err := f.s.SearchMessages(ctx, q)
	require.NoError(t, err)
	require.NotEmpty(t, next)

	// The same query, networks in another order and a different page size, takes it.
	_, _, err = f.s.SearchMessages(ctx, MessageQuery{Terms: terms("note"), Networks: []string{"whatsapp", "signal"}, After: next, Limit: 50})
	require.NoError(t, err)

	for _, other := range []MessageQuery{
		{Terms: terms("note ")},
		{Terms: terms("notes"), Networks: []string{"signal", "whatsapp"}},
		{Terms: terms("note"), Networks: []string{"signal"}},
		{Terms: terms("note"), Networks: []string{"signal", "whatsapp"}, Partial: true},
		{Terms: terms("note"), Networks: []string{"signal", "whatsapp"}, Since: searchT0},
		{Terms: terms("note"), Networks: []string{"signal", "whatsapp"}, ExcludeMuted: true},
		{Networks: []string{"signal", "whatsapp"}},
	} {
		other.After, other.Limit = next, 5
		_, _, err := f.s.SearchMessages(ctx, other)
		require.ErrorIs(t, err, ErrBadCursor, "%+v", other)
	}
	m, err := normalizeMessageQuery(q)
	require.NoError(t, err)
	forged := func(body string) string { return base64.RawURLEncoding.EncodeToString([]byte(body)) }
	for _, bad := range []string{
		"x", "!!!", "e30", forged(`{"q":"` + m.hash() + `","p":1,"r":5}`),
		forged(`{"q":"` + m.hash() + `","p":-1}`), forged(`{"q":"` + m.hash() + `","r":"5"}`), forged(`[]`),
	} {
		q.After = bad
		_, _, err := f.s.SearchMessages(ctx, q)
		require.ErrorIs(t, err, ErrBadCursor, bad)
	}
}

func TestAPageEndsBeforeOneMebibyte(t *testing.T) {
	s := open(t)
	chat(t, s, "!big", "whatsapp", true, 1)
	long := strings.Repeat("bulky words fill this message ", 540) // about 16,000 characters, every one indexed
	for i := 0; i < 50; i++ {
		mkMsg(t, s, "!big", fmt.Sprintf("$big%d", i), ghost, "m.room.message", text(fmt.Sprintf("%s %d", long, i)), searchT0.Add(time.Duration(i)*time.Second))
	}
	q := MessageQuery{Terms: terms("bulky"), Limit: 50}
	hits, next, err := s.SearchMessages(context.Background(), q)
	require.NoError(t, err)
	require.Less(t, len(hits), 50, "a page of 50 long messages would pass 1 MiB")
	require.NotEmpty(t, next, "a short page isn't the last")
	size := 0
	for _, h := range hits {
		size += len(h.Text) + len(h.Event.Content)
	}
	require.Less(t, size, 1<<20)
	q.After = next
	all := append(hits, searchAll(t, s, q)...)
	want := []string{}
	for i := 49; i >= 0; i-- {
		want = append(want, fmt.Sprintf("$big%d", i))
	}
	require.Equal(t, want, hitIDs(all))
}

func roomIDsOf(rows []InboxRow) []string {
	out := []string{}
	for _, r := range rows {
		out = append(out, r.ID)
	}
	return out
}

func TestChatsStartingWithTheWordComeFirst(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	require.NoError(t, f.s.UpsertRoom(ctx, Room{ID: "!wa-andes", Network: "whatsapp", Name: "Andes trip", CreatedAt: time.Unix(1, 0)}))
	at := searchT0.Add(24 * time.Hour)
	mkMsg(t, f.s, "!wa-dm1", "$anna", ghost, "m.room.message", text("hi"), at)
	mkMsg(t, f.s, "!wa-andes", "$andes", ghost, "m.room.message", text("hi"), at.Add(time.Minute))
	mkMsg(t, f.s, "!wa-grp1", "$book", ghost, "m.room.message", text("hi"), at.Add(2*time.Minute))

	rows, err := f.s.SearchChats(ctx, NameQuery{Terms: terms("an"), Limit: 10})
	require.NoError(t, err)
	// "Joanna's group" doesn't match: a prefix starts at a word.
	require.Equal(t, []string{"!wa-andes", "!wa-dm1", "!wa-grp1"}, roomIDsOf(rows))
	require.Equal(t, "Anna", rows[1].Name, "whole inbox rows")
	require.Equal(t, "hi", rows[1].Preview)

	rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms("an"), Limit: 2})
	require.NoError(t, err)
	require.Equal(t, []string{"!wa-andes", "!wa-dm1"}, roomIDsOf(rows))
	rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms("an"), ChatType: "group", Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{"!wa-andes", "!wa-grp1"}, roomIDsOf(rows))
	rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms("an"), Networks: []string{"telegram"}, Limit: 10})
	require.NoError(t, err)
	require.Empty(t, rows)
	// Chats in any place are found: archived, hidden, a request.
	for q, want := range map[string]string{"family": "!tg-grp2", "bram": "!tg-dm1", "cleo": "!tg-dm2"} {
		rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms(q), Limit: 10})
		require.NoError(t, err)
		require.Equal(t, []string{want}, roomIDsOf(rows), q)
	}
}

func TestNamesAreSearchedFromTheFirstLetter(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	require.NoError(t, f.s.UpsertRoom(ctx, Room{ID: "!sg-alpha", Network: "signal", Name: "Alpha", CreatedAt: time.Unix(1, 0)}))
	require.NoError(t, f.s.SetMember(ctx, "!sg-alpha", "@sg-ada:courier.local", json.RawMessage(memberContent("Ada"))))
	personIDs := func(hits []PersonHit) []string {
		out := []string{}
		for _, h := range hits {
			out = append(out, h.UserID)
		}
		return out
	}

	rows, err := f.s.SearchChats(ctx, NameQuery{Terms: searchtext.ParseName("a"), Limit: 100})
	require.NoError(t, err)
	require.Contains(t, roomIDsOf(rows), "!sg-alpha")
	people, err := f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: searchtext.ParseName("a"), Limit: 100})
	require.NoError(t, err)
	require.Contains(t, personIDs(people), "@sg-ada:courier.local")

	// Parse's terms (the messages' 2-letter rule) look for the word "a" alone, and a finished word is no prefix.
	for _, ts := range [][]searchtext.Term{terms("a"), searchtext.ParseName("a ")} {
		rows, err = f.s.SearchChats(ctx, NameQuery{Terms: ts, Limit: 100})
		require.NoError(t, err)
		require.NotContains(t, roomIDsOf(rows), "!sg-alpha")
		people, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: ts, Limit: 100})
		require.NoError(t, err)
		require.NotContains(t, personIDs(people), "@sg-ada:courier.local")
	}
}

func TestDirectChatFoundByThePersonsName(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	rows, err := f.s.SearchChats(ctx, NameQuery{Terms: terms("joseph"), Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{"!wa-dm2"}, roomIDsOf(rows), "the DM named by a phone number is found by the person's name")
	require.Equal(t, "+1 555 0100", rows[0].Name)
	require.True(t, rows[0].Archived)
	for _, q := range []NameQuery{
		{Terms: terms("joseph"), ChatType: "group", Limit: 10},
		{Terms: terms("joseph"), Networks: []string{"signal"}, Limit: 10},
	} {
		rows, err = f.s.SearchChats(ctx, q)
		require.NoError(t, err)
		require.Empty(t, rows, "%+v", q)
	}
	rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms("joseph"), ChatType: "dm", Networks: []string{"whatsapp"}, Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{"!wa-dm2"}, roomIDsOf(rows))
	// A group the person is in isn't found by their name.
	require.NoError(t, f.s.SetMember(ctx, "!wa-grp1", "@wa-joseph:courier.local", json.RawMessage(memberContent("Joseph Bloggs"))))
	rows, err = f.s.SearchChats(ctx, NameQuery{Terms: terms("bloggs"), Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{"!wa-dm2"}, roomIDsOf(rows))
}

func TestInGroupsListsOnlyPeopleWithoutADirectChat(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	join := func(room, user, name string) {
		t.Helper()
		require.NoError(t, f.s.SetMember(ctx, room, user, json.RawMessage(memberContent(name))))
	}
	require.NoError(t, f.s.UpsertRoom(ctx, Room{ID: "!wa-dm3", Network: "whatsapp", Name: "Mira Lane", IsDirect: true, CreatedAt: time.Unix(1, 0)}))
	require.NoError(t, f.s.UpsertRoom(ctx, Room{ID: "!wa-dm4", Network: "whatsapp", Name: "Miranda Fox", IsDirect: true, CreatedAt: time.Unix(1, 0)}))
	require.NoError(t, f.s.SetProfile(ctx, "@wa-mira:courier.local", ptr("Mira Stone"), ptr("mxc://courier.test/mira")))
	join("!wa-grp1", "@wa-mira:courier.local", "Mira Stone")
	join("!wa-grp2", "@wa-mira:courier.local", "Mira S.")
	join("!wa-grp1", "@wa-miralane:courier.local", "Mira Lane") // has a DM
	join("!wa-dm3", "@wa-miralane:courier.local", "Mira Lane")
	join("!wa-dm4", "@wa-miranda:courier.local", "Miranda Fox") // only a DM
	require.NoError(t, f.s.SetProfile(ctx, "@wa-miragone:courier.local", ptr("Mira Gone"), nil))
	require.NoError(t, f.s.SetMember(ctx, "!wa-grp1", "@wa-miragone:courier.local", json.RawMessage(`{"membership":"leave","displayname":"Mira Gone"}`)))
	join("!sg-grp2", "@sg-oldmira:courier.local", "Old Mira") // newer group, but the name doesn't begin with the word
	at := searchT0.Add(24 * time.Hour)
	mkMsg(t, f.s, "!wa-grp2", "$g2", ghost, "m.room.message", text("hi"), at)
	mkMsg(t, f.s, "!sg-grp2", "$sg2", ghost, "m.room.message", text("hi"), at.Add(time.Minute))

	hits, err := f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms("mira"), Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []PersonHit{
		{UserID: "@wa-mira:courier.local", Name: "Mira Stone", Network: "whatsapp", AvatarURI: "mxc://courier.test/mira", RoomID: "!wa-grp2", RoomName: "Joanna's group", Groups: 2},
		{UserID: "@sg-oldmira:courier.local", Name: "Old Mira", Network: "signal", RoomID: "!sg-grp2", RoomName: "Choir", Groups: 1},
	}, hits)

	hits, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms("mira"), Networks: []string{"signal"}, Limit: 10})
	require.NoError(t, err)
	require.Len(t, hits, 1)
	require.Equal(t, "@sg-oldmira:courier.local", hits[0].UserID)
	hits, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms("mira"), Limit: 1})
	require.NoError(t, err)
	require.Len(t, hits, 1)
	hits, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms("mira"), ChatType: "dm", Limit: 10})
	require.NoError(t, err)
	require.Empty(t, hits)
	// Everyone in the fixture has a DM with me or is found in a group: the group ghosts only.
	hits, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms("hale"), Limit: 10})
	require.NoError(t, err)
	require.Len(t, hits, 2)
}

func TestLastArchivedSkipsHiddenAndTheOpenChat(t *testing.T) {
	f := newSearchFixture(t)
	ctx := context.Background()
	f.s.SetClock(func() time.Time { return searchT0.Add(2 * time.Hour) })
	_, err := f.s.SetArchived(ctx, []string{"!sg-dm1"}, true)
	require.NoError(t, err)
	_, err = f.s.SetHidden(ctx, []string{"!sg-dm1"}, true)
	require.NoError(t, err)

	row, ok, err := f.s.LastArchived(ctx, "")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "!tg-grp2", row.ID, "the newest archive that isn't hidden")
	require.Equal(t, "Family", row.Name)
	require.True(t, row.Archived)
	row, ok, err = f.s.LastArchived(ctx, "!tg-grp2")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "!wa-dm2", row.ID, "not the open chat")

	_, err = f.s.SetArchived(ctx, []string{"!tg-grp2", "!wa-dm2"}, false)
	require.NoError(t, err)
	_, ok, err = f.s.LastArchived(ctx, "")
	require.NoError(t, err)
	require.False(t, ok)
}

func TestRoomSharedMediaFilesAndLinks(t *testing.T) {
	s, ctx := open(t), context.Background()
	roomID := "!shared:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: roomID, Network: "whatsapp", Name: "Shared Room", CreatedAt: time.Unix(1, 0)}))
	t0 := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)

	mkMsg(t, s, roomID, "$img1", me, "m.room.message", `{"msgtype":"m.image","body":"photo.png","url":"mxc://courier.test/img1"}`, t0.Add(time.Minute))
	mkMsg(t, s, roomID, "$vid1", me, "m.room.message", `{"msgtype":"m.video","body":"clip.mp4","url":"mxc://courier.test/vid1"}`, t0.Add(2*time.Minute))
	mkMsg(t, s, roomID, "$file1", me, "m.room.message", `{"msgtype":"m.file","body":"doc.pdf","url":"mxc://courier.test/file1"}`, t0.Add(3*time.Minute))
	mkMsg(t, s, roomID, "$lnk1", me, "m.room.message", `{"msgtype":"m.text","body":"See https://example.com/spec, and (https://docs.example.org/guide)."}`, t0.Add(4*time.Minute))

	mediaEvs, err := s.RoomSharedMedia(ctx, roomID, 10)
	require.NoError(t, err)
	require.Len(t, mediaEvs, 2)
	require.Equal(t, "$vid1", mediaEvs[0].EventID)
	require.Equal(t, "$img1", mediaEvs[1].EventID)

	fileEvs, err := s.RoomSharedFiles(ctx, roomID, 10)
	require.NoError(t, err)
	require.Len(t, fileEvs, 1)
	require.Equal(t, "$file1", fileEvs[0].EventID)

	links, err := s.RoomSharedLinks(ctx, roomID, 10)
	require.NoError(t, err)
	require.Len(t, links, 2)
	require.Equal(t, "https://example.com/spec", links[0].URL)
	require.Equal(t, "example.com", links[0].Host)
	require.Equal(t, "https://docs.example.org/guide", links[1].URL)
	require.Equal(t, "docs.example.org", links[1].Host)
}

type countingDBLogger struct {
	dbutil.DatabaseLogger
	count int
}

func (l *countingDBLogger) QueryTiming(_ context.Context, method, _ string, _ []any, _ int, _ time.Duration, _ error) {
	if method == "Query" || method == "QueryRow" {
		l.count++
	}
}

func TestRoomSharedLinksCapsAtNewest500Messages(t *testing.T) {
	s, ctx := open(t), context.Background()
	roomID := "!many-links:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: roomID, Network: "whatsapp", Name: "Many Links", CreatedAt: time.Unix(1, 0)}))
	t0 := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)

	for i := 1; i <= 520; i++ {
		body := fmt.Sprintf("Check https://example.com/page-%d", i)
		mkMsg(t, s, roomID, fmt.Sprintf("$m%d", i), me, "m.room.message", text(body), t0.Add(time.Duration(i)*time.Second))
	}
	// Edit the newest message ($m520) so its link changes to edited-520.
	mkMsg(t, s, roomID, "$edit520", me, "m.room.message",
		`{"msgtype":"m.text","body":"* https://example.com/edited-520","m.new_content":{"msgtype":"m.text","body":"https://example.com/edited-520"},"m.relates_to":{"rel_type":"m.replace","event_id":"$m520"}}`,
		t0.Add(600*time.Second))

	ql := &countingDBLogger{DatabaseLogger: dbutil.NoopLogger}
	s.db.Log = ql
	t.Cleanup(func() { s.db.Log = dbutil.NoopLogger })

	links, err := s.RoomSharedLinks(ctx, roomID, 600)
	require.NoError(t, err)
	require.Equal(t, 1, ql.count, "RoomSharedLinks must execute in a single bounded SQL query")
	require.Len(t, links, 500, "RoomSharedLinks must scan at most the newest 500 message events")
	require.Equal(t, "https://example.com/edited-520", links[0].URL, "latest edit text must be used")
	require.Equal(t, "https://example.com/page-21", links[len(links)-1].URL, "messages older than the newest 500 must not be scanned")
}

func TestSearchChatsIndexesBothLocalNameAndNetworkName(t *testing.T) {
	s, ctx := open(t), context.Background()
	roomID := "!override-search:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID: roomID, Network: "signal", Name: "Apollo Crew", IsDirect: false, CreatedAt: time.Unix(1, 0),
	}))
	require.NoError(t, s.SetRoomLocalOverride(ctx, roomID, "Secret Nickname", ""))

	byLocal, err := s.SearchChats(ctx, NameQuery{Terms: terms("secret"), Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{roomID}, roomIDsOf(byLocal), "chat must be found by its local override name")

	byRemote, err := s.SearchChats(ctx, NameQuery{Terms: terms("apollo"), Limit: 10})
	require.NoError(t, err)
	require.Equal(t, []string{roomID}, roomIDsOf(byRemote), "chat must still be found by its network name when local_name is set")
}

func TestViewOnceExcludedFromMediaSearchAndSharedMedia(t *testing.T) {
	s, ctx := open(t), context.Background()
	roomID := "!sig-vo-search:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: roomID, Network: "signal", Name: "Signal Search Room", CreatedAt: time.Unix(1, 0)}))
	t0 := time.Date(2026, 1, 1, 10, 0, 0, 0, time.UTC)

	mkMsg(t, s, roomID, "$img-normal", me, "m.room.message",
		`{"msgtype":"m.image","body":"caption normal","url":"mxc://courier.test/normal"}`,
		t0.Add(time.Minute))
	mkMsg(t, s, roomID, "$img-vo", me, "m.room.message",
		`{"msgtype":"m.image","body":"caption secret","url":"mxc://courier.test/secret","com.beeper.disappearing_timer":{"type":"after_read","timer":300000}}`,
		t0.Add(2*time.Minute))
	mkMsg(t, s, roomID, "$file-vo", me, "m.room.message",
		`{"msgtype":"m.file","body":"doc-secret.pdf","url":"mxc://courier.test/doc-secret","com.beeper.disappearing_timer":{"type":"after_read","timer":300000}}`,
		t0.Add(3*time.Minute))

	// 1. Search for media/files kinds excludes view-once items.
	mediaHits := searchAll(t, s, MessageQuery{RoomIDs: []string{roomID}, Kinds: []string{"image", "video"}, Limit: 10})
	require.Equal(t, []string{"$img-normal"}, hitIDs(mediaHits), "media kind search must exclude view-once photos")
	fileHits := searchAll(t, s, MessageQuery{RoomIDs: []string{roomID}, Kinds: []string{"file"}, Limit: 10})
	require.Empty(t, fileHits, "file kind search must exclude view-once files")

	// 2. Text search matching a view-once caption marks ViewOnce = true and blanks MediaURI.
	textHits := searchAll(t, s, MessageQuery{RoomIDs: []string{roomID}, Terms: terms("secret"), Limit: 10})
	require.NotEmpty(t, textHits)
	for _, h := range textHits {
		require.True(t, h.ViewOnce, "text hit on view-once item must set ViewOnce = true")
		require.Empty(t, h.MediaURI, "text hit on view-once item must blank MediaURI")
	}

	// 3. RoomSharedMedia and RoomSharedFiles exclude view-once items.
	sharedMedia, err := s.RoomSharedMedia(ctx, roomID, 10)
	require.NoError(t, err)
	require.Len(t, sharedMedia, 1, "RoomSharedMedia must exclude view-once media")
	require.Equal(t, "$img-normal", sharedMedia[0].EventID)

	sharedFiles, err := s.RoomSharedFiles(ctx, roomID, 10)
	require.NoError(t, err)
	require.Empty(t, sharedFiles, "RoomSharedFiles must exclude view-once files")
}
