// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// pageIDs is the room IDs of rows, in order.
func pageIDs(rows []InboxRow) []string {
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		out = append(out, r.ID)
	}
	return out
}

// allPages reads q to its last page and returns every room ID, in order.
func allPages(t *testing.T, s *Store, q InboxQuery) []string {
	t.Helper()
	var out []string
	for i := 0; ; i++ {
		require.Less(t, i, 10000, "paging never ends")
		rows, next, err := s.InboxPage(context.Background(), q)
		require.NoError(t, err)
		out = append(out, pageIDs(rows)...)
		if next == "" {
			return out
		}
		q.After = next
	}
}

// chat makes a room with one message from someone else at ts seconds.
func chat(t *testing.T, s *Store, id, network string, direct bool, ts int64) {
	t.Helper()
	require.NoError(t, s.UpsertRoom(context.Background(), Room{ID: id, Network: network, Name: id, IsDirect: direct, CreatedAt: time.Unix(1, 0)}))
	mkMsg(t, s, id, "$"+id, ghost, "m.room.message", text("hello"), time.Unix(ts, 0))
}

func remind(t *testing.T, s *Store, roomID string, dueAt, firedAt int64) {
	t.Helper()
	_, err := s.db.Exec(context.Background(), `INSERT INTO reminders (room_id, due_at, condition, set_at, fired_at) VALUES ($1,$2,'always',1,$3)`,
		roomID, dueAt, firedAt)
	require.NoError(t, err)
}

// everyPlace is a fixture with a chat in every place, and the label "Work" on !grp and !arch.
func everyPlace(t *testing.T, s *Store) (work Label) {
	t.Helper()
	ctx := context.Background()
	chat(t, s, "!dm", "whatsapp", true, 10)
	chat(t, s, "!grp", "whatsapp", false, 11)
	chat(t, s, "!tg", "telegram", true, 12)
	chat(t, s, "!arch", "whatsapp", false, 13)
	chat(t, s, "!fired", "whatsapp", false, 14)
	chat(t, s, "!low", "whatsapp", false, 15)
	chat(t, s, "!hid", "whatsapp", true, 16)
	chat(t, s, "!req", "whatsapp", true, 17)
	_, err := s.SetArchived(ctx, []string{"!arch", "!fired"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!low"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!hid"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetRequest(ctx, "!req", true))
	remind(t, s, "!tg", 100, 0)
	remind(t, s, "!fired", 50, 60)
	remind(t, s, "!hid", 100, 0)
	work = mkLabel(t, s, "Work")
	_, err = s.SetLabel(ctx, []string{"!grp", "!arch"}, work.ID, true)
	require.NoError(t, err)
	return work
}

func TestEachSpaceShowsItsChats(t *testing.T) {
	s := open(t)
	work := everyPlace(t, s)
	for _, tc := range []struct {
		space string
		want  []string
	}{
		{"", []string{"!dm", "!grp", "!tg"}},
		{"inbox", []string{"!dm", "!grp", "!tg"}},
		{"account:whatsapp", []string{"!dm", "!grp"}},
		{"account:telegram", []string{"!tg"}},
		{"account:signal", nil},
		{labelSpaceID(work.ID), []string{"!grp"}},
		{"reminders", []string{"!tg", "!fired"}}, // a fired reminder still counts; a hidden chat's doesn't
		{"requests", []string{"!req"}},
		{"low_priority", []string{"!low"}},
		{"archive", []string{"!arch", "!fired"}},
		{"send_later", nil},
	} {
		t.Run(tc.space, func(t *testing.T) {
			require.ElementsMatch(t, tc.want, allPages(t, s, InboxQuery{Space: tc.space}))
		})
	}

	ctx := context.Background()
	for _, q := range []InboxQuery{
		{Space: "hidden"},
		{Space: "label:x"},
		{Space: "account:"},
		{Space: "Inbox"},
		{Filters: []string{"all"}},
		{Filters: []string{"Unread"}},
		{Sort: "newer"},
		{Limit: -1},
		{Limit: 501},
	} {
		_, _, err := s.InboxPage(ctx, q)
		require.ErrorIs(t, err, ErrBadValue, "%+v", q)
	}
}

// Ruling 9: a space's count in the spaces bar is the number of chats its pages list, and its unread count the
// number its Unread filter lists.
func TestSpaceCountsMatchTheirPages(t *testing.T) {
	s, ctx := open(t), context.Background()
	work := everyPlace(t, s)
	home := mkLabel(t, s, "Home")
	_, err := s.SetLabel(ctx, []string{"!dm", "!tg", "!low"}, home.ID, true)
	require.NoError(t, err)
	require.NoError(t, s.MarkReadLocal(ctx, "!grp", "$!grp", time.Unix(11, 0)))
	_, err = s.SetMarkedUnread(ctx, []string{"!grp"}, true)
	require.NoError(t, err)
	require.NoError(t, s.MarkReadLocal(ctx, "!tg", "$!tg", time.Unix(12, 0)))

	check := func() {
		t.Helper()
		spaces, err := s.Spaces(ctx, []string{"whatsapp", "telegram"})
		require.NoError(t, err)
		require.Len(t, spaces, 6+2+2)
		for _, sp := range spaces {
			require.Len(t, allPages(t, s, InboxQuery{Space: sp.ID}), sp.Chats, sp.ID)
			require.Len(t, allPages(t, s, InboxQuery{Space: sp.ID, Filters: []string{"unread"}}), sp.UnreadChats, sp.ID)
		}
	}
	check()
	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", nil, ptr("dms")))
	require.NoError(t, s.UpdateSpace(ctx, labelSpaceID(home.ID), nil, ptr("none")))
	check()
	require.NoError(t, s.UpdateSpace(ctx, labelSpaceID(work.ID), nil, ptr("dms")))
	check()
}

func TestShowInInboxPerAccountAndLabel(t *testing.T) {
	s, ctx := open(t), context.Background()
	chat(t, s, "!dm", "whatsapp", true, 10)
	chat(t, s, "!grp", "whatsapp", false, 11)
	chat(t, s, "!tg", "telegram", false, 12)
	chat(t, s, "!tgdm", "telegram", true, 13)
	family := mkLabel(t, s, "Family")
	_, err := s.SetLabel(ctx, []string{"!tgdm"}, family.ID, true)
	require.NoError(t, err)
	inbox := func() []string { return allPages(t, s, InboxQuery{Space: "inbox"}) }
	require.ElementsMatch(t, []string{"!dm", "!grp", "!tg", "!tgdm"}, inbox())

	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", nil, ptr("dms")))
	require.ElementsMatch(t, []string{"!dm", "!tg", "!tgdm"}, inbox(), "WhatsApp at dms drops its group")
	require.ElementsMatch(t, []string{"!dm", "!grp"}, allPages(t, s, InboxQuery{Space: "account:whatsapp"}), "but not from its own space")

	require.NoError(t, s.UpdateSpace(ctx, labelSpaceID(family.ID), nil, ptr("none")))
	require.ElementsMatch(t, []string{"!dm", "!tg"}, inbox(), "a label at none drops its chats")
	require.ElementsMatch(t, []string{"!tgdm"}, allPages(t, s, InboxQuery{Space: labelSpaceID(family.ID)}))
	require.ElementsMatch(t, []string{"!tg", "!tgdm"}, allPages(t, s, InboxQuery{Space: "account:telegram"}))

	require.NoError(t, s.UpdateSpace(ctx, "account:telegram", nil, ptr("none")))
	require.ElementsMatch(t, []string{"!dm"}, inbox())
}

func TestFiltersCombineWithinAndAcrossGroups(t *testing.T) {
	s, ctx := open(t), context.Background()
	chat(t, s, "!dmUnread", "x", true, 10)
	chat(t, s, "!dmRead", "x", true, 11)
	chat(t, s, "!grpUnread", "x", false, 12)
	chat(t, s, "!grpRead", "y", false, 13)
	chat(t, s, "!xArch", "x", true, 14)
	chat(t, s, "!xHid", "x", false, 15)
	chat(t, s, "!xLow", "x", false, 16)
	chat(t, s, "!yArch", "y", false, 17)
	require.NoError(t, s.MarkReadLocal(ctx, "!dmRead", "$!dmRead", time.Unix(11, 0)))
	require.NoError(t, s.MarkReadLocal(ctx, "!grpRead", "$!grpRead", time.Unix(13, 0)))
	_, err := s.SetArchived(ctx, []string{"!xArch", "!yArch"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!xHid"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!xLow"}, true)
	require.NoError(t, err)

	q := func(space string, filters ...string) []string {
		return allPages(t, s, InboxQuery{Space: space, Filters: filters})
	}
	everything := []string{"!dmUnread", "!dmRead", "!grpUnread", "!grpRead"}
	require.ElementsMatch(t, everything, q("inbox"))
	require.ElementsMatch(t, everything, q("inbox", "dms", "groups"), "dms+groups is everything")
	require.ElementsMatch(t, []string{"!dmUnread", "!dmRead"}, q("inbox", "dms"))
	require.ElementsMatch(t, []string{"!dmUnread"}, q("inbox", "unread", "dms"), "unread+dms is unread DMs")
	require.ElementsMatch(t, []string{"!dmUnread"}, q("inbox", "dms", "unread", "dms"), "a repeated filter changes nothing")
	require.ElementsMatch(t, []string{"!xArch", "!xHid"}, q("account:x", "archived", "hidden"), "x's archived and hidden chats")
	require.ElementsMatch(t, []string{"!xArch", "!yArch"}, q("inbox", "archived"), "a place filter replaces the inbox's place")
	require.ElementsMatch(t, []string{"!xArch"}, q("account:x", "archived", "dms"))
	require.Empty(t, q("inbox", "send_later"))
	require.ElementsMatch(t, []string{"!xArch"}, q("archive", "dms"))

	// Marked unread counts as unread.
	_, err = s.SetMarkedUnread(ctx, []string{"!grpRead"}, true)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!dmUnread", "!grpUnread", "!grpRead"}, q("inbox", "unread"))

	// Drafts, and muted: by the chat itself, its account or a label.
	require.NoError(t, s.SetDraft(ctx, "!dmRead", "half a thought"))
	require.ElementsMatch(t, []string{"!dmRead"}, q("inbox", "drafts"))
	require.Empty(t, q("inbox", "drafts", "groups"))
	require.Empty(t, q("inbox", "muted"))
	require.NoError(t, s.SetMuted(ctx, "!dmUnread", true))
	require.NoError(t, s.UpdateSpace(ctx, "account:y", ptr(true), nil))
	quiet := mkLabel(t, s, "Quiet")
	_, err = s.SetLabel(ctx, []string{"!grpUnread"}, quiet.ID, true)
	require.NoError(t, err)
	require.NoError(t, s.UpdateSpace(ctx, labelSpaceID(quiet.ID), ptr(true), nil))
	require.ElementsMatch(t, []string{"!dmUnread", "!grpUnread", "!grpRead"}, q("inbox", "muted"))
}

func TestUnansweredNoReplyAndUnknown(t *testing.T) {
	s, ctx := open(t), context.Background()
	room := func(id, name string, direct bool) {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: id, Network: "whatsapp", Name: name, IsDirect: direct, CreatedAt: time.Unix(1, 0)}))
	}
	room("!theirs", "Theirs", false)
	mkMsg(t, s, "!theirs", "$t1", me, "m.room.message", text("mine first"), time.Unix(10, 0))
	mkMsg(t, s, "!theirs", "$t2", ghost, "m.room.message", text("theirs last"), time.Unix(11, 0))
	room("!mine", "Mine", false)
	mkMsg(t, s, "!mine", "$m1", ghost, "m.room.message", text("theirs first"), time.Unix(10, 0))
	mkMsg(t, s, "!mine", "$m2", me, "m.room.message", text("mine last"), time.Unix(11, 0))
	mkMsg(t, s, "!mine", "$m3", ghost, "m.reaction", `{"m.relates_to":{"rel_type":"m.annotation","event_id":"$m2","key":"x"}}`, time.Unix(12, 0))
	room("!empty", "Empty", false)

	room("!noName", "", true)
	room("!digits", "0000000", true)
	room("!plusDigits", "+00 (000) 000-0000", true)
	room("!short", "+00000", true)
	room("!letters", "00000x00", true)
	room("!named", "Someone", true)
	room("!groupDigits", "0000000", false)
	room("!groupNoName", "", false)

	q := func(filters ...string) []string { return allPages(t, s, InboxQuery{Filters: filters}) }
	require.ElementsMatch(t, []string{"!theirs"}, q("unanswered"), "a reaction isn't the newest message")
	require.ElementsMatch(t, []string{"!mine"}, q("no_reply"))
	require.ElementsMatch(t, []string{"!theirs", "!mine"}, q("unanswered", "no_reply"))
	require.ElementsMatch(t, []string{"!noName", "!digits", "!plusDigits"}, q("unknown"))
	require.ElementsMatch(t, []string{"!noName", "!digits", "!plusDigits"}, q("unknown", "dms"))
	require.Empty(t, q("unknown", "groups"))
}

func TestPinnedComeFirstInPinOrder(t *testing.T) {
	s, ctx := open(t), context.Background()
	clk := clockAt(s, time.Unix(1000, 0))
	for i, id := range []string{"!a", "!b", "!c", "!d", "!e"} {
		chat(t, s, id, "whatsapp", true, int64(10+i))
	}
	require.NoError(t, s.SetPinned(ctx, "!c", true))
	clk.set(time.Unix(1001, 0))
	require.NoError(t, s.SetPinned(ctx, "!a", true))

	require.Equal(t, []string{"!c", "!a", "!e", "!d", "!b"}, allPages(t, s, InboxQuery{}))
	require.Equal(t, []string{"!c", "!a", "!b", "!d", "!e"}, allPages(t, s, InboxQuery{Sort: "oldest"}))
	require.Equal(t, []string{"!c", "!a", "!e", "!d", "!b"}, allPages(t, s, InboxQuery{Limit: 1}), "the same order a row at a time")
	rows, _, err := s.InboxPage(ctx, InboxQuery{Limit: 1})
	require.NoError(t, err)
	require.Equal(t, time.Unix(1000, 0), rows[0].PinnedAt, "the row carries the inbox columns")
}

func TestSortsByReminderTime(t *testing.T) {
	s, ctx := open(t), context.Background()
	for i, id := range []string{"!none1", "!due30", "!due10", "!none2", "!due20", "!tie20"} {
		chat(t, s, id, "whatsapp", true, int64(10+i))
	}
	remind(t, s, "!due30", 30, 0)
	remind(t, s, "!due10", 10, 0)
	remind(t, s, "!due20", 20, 0)
	remind(t, s, "!tie20", 20, 25)
	require.Equal(t, []string{"!due10", "!due20", "!tie20", "!due30", "!none1", "!none2"},
		allPages(t, s, InboxQuery{Sort: "least_time_remaining"}))
	require.Equal(t, []string{"!due30", "!due20", "!tie20", "!due10", "!none1", "!none2"},
		allPages(t, s, InboxQuery{Sort: "most_time_remaining"}))
	require.Equal(t, []string{"!due30", "!due20", "!tie20", "!due10", "!none1", "!none2"},
		allPages(t, s, InboxQuery{Sort: "most_time_remaining", Limit: 2}), "the same order in pages")

	// Pinned still come first.
	require.NoError(t, s.SetPinned(ctx, "!none2", true))
	require.Equal(t, []string{"!none2", "!due10", "!due20", "!tie20", "!due30", "!none1"},
		allPages(t, s, InboxQuery{Sort: "least_time_remaining"}))
}

func TestRoomIDsFindAChatInAnyPlace(t *testing.T) {
	s, ctx := open(t), context.Background()
	everyPlace(t, s)
	require.ElementsMatch(t, []string{"!hid", "!dm", "!arch"},
		allPages(t, s, InboxQuery{RoomIDs: []string{"!hid", "!dm", "!arch", "!nosuch", "!hid"}}))
	require.ElementsMatch(t, []string{"!hid"},
		allPages(t, s, InboxQuery{Space: "archive", Filters: []string{"groups"}, RoomIDs: []string{"!hid"}}), "Space and Filters are ignored")
	// Still checked, even though ignored: a malformed query is refused whatever it holds.
	_, _, err := s.InboxPage(ctx, InboxQuery{Space: "nope", RoomIDs: []string{"!hid"}})
	require.ErrorIs(t, err, ErrBadValue)
	rows, _, err := s.InboxPage(ctx, InboxQuery{RoomIDs: []string{"!hid"}})
	require.NoError(t, err)
	require.True(t, rows[0].Hidden)
	require.NotNil(t, rows[0].Reminder)
}

func TestPagesNeverRepeatOrSkip(t *testing.T) {
	s, ctx := open(t), context.Background()
	seedBig(t, s, 1234, 2, 0) // many chats share a last_ts, so room_id breaks most ties
	for _, id := range []string{"!r7", "!r700", "!r1200"} {
		require.NoError(t, s.SetPinned(ctx, id, true))
	}
	for i := 0; i < 1234; i += 3 {
		remind(t, s, fmt.Sprintf("!r%d", i), int64(1+i%10), 0) // ties in due_at too
	}

	for _, sort := range []string{"newest", "oldest", "least_time_remaining", "most_time_remaining"} {
		t.Run(sort, func(t *testing.T) {
			got := allPages(t, s, InboxQuery{Sort: sort, Limit: 100})
			require.Len(t, got, 1234)
			seen := map[string]bool{}
			for _, id := range got {
				require.False(t, seen[id], "%s twice", id)
				seen[id] = true
			}
		})
	}

	// A chat already shown, and one not yet shown, get a new message between pages 3 and 4. Each appears at most
	// once; every chat that didn't move appears exactly once.
	q := InboxQuery{Limit: 100}
	count := map[string]int{}
	moved := map[string]bool{}
	for page := 1; ; page++ {
		rows, next, err := s.InboxPage(ctx, q)
		require.NoError(t, err)
		require.LessOrEqual(t, len(rows), 100)
		for _, r := range rows {
			count[r.ID]++
		}
		if page == 3 {
			last := rows[len(rows)-1].ID
			require.Equal(t, 1, count[last])
			mkMsg(t, s, last, "$bump-seen", ghost, "m.room.message", text("again"), time.Unix(5_000, 0))
			moved[last] = true
			for i := 1233; i >= 0; i-- {
				if id := fmt.Sprintf("!r%d", i); count[id] == 0 {
					mkMsg(t, s, id, "$bump-unseen", ghost, "m.room.message", text("again"), time.Unix(5_000, 0))
					moved[id] = true
					break
				}
			}
			require.Len(t, moved, 2)
		}
		if next == "" {
			break
		}
		q.After = next
	}
	for i := 0; i < 1234; i++ {
		id := fmt.Sprintf("!r%d", i)
		if moved[id] {
			require.LessOrEqual(t, count[id], 1, id)
		} else {
			require.Equal(t, 1, count[id], id)
		}
	}
}

func TestCursorFromAnotherQueryIsRefused(t *testing.T) {
	s, ctx := open(t), context.Background()
	for i := 0; i < 5; i++ {
		chat(t, s, fmt.Sprintf("!c%d", i), "whatsapp", i%2 == 0, int64(10+i))
	}
	_, next, err := s.InboxPage(ctx, InboxQuery{Filters: []string{"dms", "unread"}, Limit: 1})
	require.NoError(t, err)
	require.NotEmpty(t, next)

	// The same query, filters in another order and a different page size, takes it.
	rows, _, err := s.InboxPage(ctx, InboxQuery{Space: "inbox", Filters: []string{"unread", "dms"}, After: next, Limit: 5})
	require.NoError(t, err)
	require.Len(t, rows, 2)

	for _, q := range []InboxQuery{
		{Filters: []string{"dms"}},
		{Filters: []string{"dms", "unread"}, Sort: "oldest"},
		{Space: "archive", Filters: []string{"dms", "unread"}},
		{RoomIDs: []string{"!c0", "!c2"}},
	} {
		q.After = next
		_, _, err := s.InboxPage(ctx, q)
		require.ErrorIs(t, err, ErrBadCursor, "%+v", q)
	}
	pq, err := normalize(InboxQuery{})
	require.NoError(t, err)
	wrongKey := func(k string) string {
		return base64.RawURLEncoding.EncodeToString([]byte(`{"q":"` + pq.hash() + `","k":` + k + `}`))
	}
	for _, bad := range []string{"x", "!!!", "e30", "eyJxIjoiIiwiayI6W119", wrongKey(`["a",1,2,"!c0"]`), wrongKey(`[1,2,3]`), wrongKey(`[1,2,3,4]`)} {
		_, _, err := s.InboxPage(ctx, InboxQuery{After: bad})
		require.ErrorIs(t, err, ErrBadCursor, bad)
	}
}

func TestPagesAt10000ChatsAreQuickAndIndexed(t *testing.T) {
	s, ctx := open(t), context.Background()
	seedBig(t, s, 10000, 3, 0)
	q := InboxQuery{Space: "inbox", Filters: []string{"unread"}}

	query, args, err := buildInboxPage(q, nil)
	require.NoError(t, err)
	plan := planOf(t, s, query, args...)
	t.Log("plan:\n  " + strings.Join(plan, "\n  "))
	// The real check: no page reads every message. Rooms are scanned (choosing a page has to look at each chat),
	// and so is the page itself (pg, at most Limit rows) and, for a page row's mention count, the JSON of one
	// message (json_each); everything else, events above all, is an index or primary-key lookup.
	for _, line := range plan {
		if strings.HasPrefix(line, "SCAN ") && !strings.HasPrefix(line, "SCAN json_each VIRTUAL TABLE") {
			require.Contains(t, []string{"SCAN r", "SCAN pg"}, line, "only rooms and the page are scanned")
		}
	}
	require.Contains(t, strings.Join(plan, "\n"), "SEARCH u USING INDEX events_room_ts")

	// The loose ceiling, for something gross; the plan above is what proves it scales.
	start := time.Now()
	rows, next, err := s.InboxPage(ctx, q)
	took := time.Since(start)
	t.Logf("first page of 10,000 chats, Unread filter: %s", took)
	require.NoError(t, err)
	require.Len(t, rows, 200)
	require.NotEmpty(t, next)
	require.Less(t, took, time.Second)

	start = time.Now()
	rows, _, err = s.InboxPage(ctx, InboxQuery{Space: "inbox", Filters: []string{"unread"}, After: next, Limit: 500})
	t.Logf("second page (500 rows): %s", time.Since(start))
	require.NoError(t, err)
	require.Len(t, rows, 500)
}
