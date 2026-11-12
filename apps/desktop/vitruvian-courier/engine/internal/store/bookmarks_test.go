// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestBookmarkSetClearAndSearch(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("lunch plans"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("lunch later"), time.Unix(20, 0))

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetBookmarked(ctx, "$a", true))
	a, _ := getEvent(t, s, "$a")
	require.Equal(t, Change{Kind: "status", RoomID: "!r", EventID: "$a", Seq: a.Seq}, nextChange(t, ch))
	require.NoError(t, s.SetBookmarked(ctx, "$a", true), "again keeps it")
	got, err := s.Bookmarked(ctx, []string{"$a", "$b", "$nowhere"})
	require.NoError(t, err)
	require.Equal(t, map[string]bool{"$a": true}, got)

	lunch := MessageQuery{Terms: terms("lunch")}
	require.Equal(t, []string{"$b", "$a"}, hitIDs(searchAll(t, s, lunch)))
	lunch.BookmarkedOnly = true
	require.Equal(t, []string{"$a"}, hitIDs(searchAll(t, s, lunch)), "only the bookmarked match")
	_, _, err = s.SearchMessages(ctx, MessageQuery{BookmarkedOnly: true})
	require.ErrorIs(t, err, ErrNoQuery, "bookmarks alone are RecentBookmarks' job")

	require.NoError(t, s.SetBookmarked(ctx, "$a", false))
	require.Empty(t, hitIDs(searchAll(t, s, lunch)))
	got, err = s.Bookmarked(ctx, []string{"$a", "$b"})
	require.NoError(t, err)
	require.Empty(t, got)

	mkMsg(t, s, "!r", "$x", ghost, "m.room.redaction", redactionOf("$b"), time.Unix(30, 0))
	require.ErrorIs(t, s.SetBookmarked(ctx, "$b", true), ErrNotFound, "a deleted message")
	require.ErrorIs(t, s.SetBookmarked(ctx, "$nowhere", true), ErrNotFound)

	// FTS5 still drives the plan; the bookmark is a primary-key lookup per match.
	m, err := normalizeMessageQuery(lunch)
	require.NoError(t, err)
	query, args := m.sql(0, math.MaxInt64, 21)
	plan := planOf(t, s, query, args...)
	requireWalksTheIndex(t, "bookmarked", plan)
	require.Contains(t, strings.Join(plan, "\n"), "sqlite_autoindex_bookmarks_1 (event_id=?)")
}

func TestRecentBookmarksNewestFirst(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "telegram", Name: "Climbing", CreatedAt: time.Unix(1, 0)}))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$a", Sender: me, Type: "m.room.message", Content: json.RawMessage(text("meet at noon")),
		TS: time.Unix(10, 0), Status: "sent",
	})
	insert(t, s, Event{
		RoomID: "!r", EventID: "$e", Sender: me, Type: "m.room.message", Content: json.RawMessage(editTo("$a", "meet at five")),
		TS: time.Unix(11, 0), Status: "sent",
	})
	mkMsg(t, s, "!g", "$b", ghost, "m.room.message", text("rope list"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", text("tickets"), time.Unix(30, 0))
	mkMsg(t, s, "!r", "$d", ghost, "m.room.message", text("gone soon"), time.Unix(40, 0))
	for i, id := range []string{"$b", "$a", "$c", "$d"} { // bookmarked in this order
		clock.set(t0.Add(time.Duration(i) * time.Minute))
		require.NoError(t, s.SetBookmarked(ctx, id, true))
	}
	mkMsg(t, s, "!r", "$x", ghost, "m.room.redaction", redactionOf("$d"), time.Unix(50, 0))

	hits, err := s.RecentBookmarks(ctx, 0)
	require.NoError(t, err)
	require.Equal(t, []string{"$c", "$a", "$b"}, hitIDs(hits), "newest bookmark first; a deleted message isn't listed")
	require.Equal(t, "meet at five", hits[1].Text, "as it reads now")
	require.Equal(t, "text", hits[1].Kind)
	require.Equal(t, "Climbing", hits[2].RoomName)
	require.Equal(t, "telegram", hits[2].Network)
	require.Equal(t, "inbox", hits[2].Place)

	hits, err = s.RecentBookmarks(ctx, 2)
	require.NoError(t, err)
	require.Equal(t, []string{"$c", "$a"}, hitIDs(hits))
	for _, bad := range []int{-1, 51} {
		_, err = s.RecentBookmarks(ctx, bad)
		require.ErrorIs(t, err, ErrBadValue, bad)
	}
}
