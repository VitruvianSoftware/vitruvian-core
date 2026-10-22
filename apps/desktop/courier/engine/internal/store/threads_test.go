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

// threadReply is a reply in root's thread; broadcast also sends it to the channel.
func threadReply(root, body string, broadcast bool) string {
	c := map[string]any{
		"msgtype": "m.text", "body": body,
		"m.relates_to": map[string]any{
			"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
			"m.in_reply_to": map[string]string{"event_id": root},
		},
	}
	if broadcast {
		c["com.beeper.broadcast_outside_thread"] = true
	}
	b, _ := json.Marshal(c)
	return string(b)
}

func TestMainTimelineLeavesOutThreadReplies(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$root", ghost, "m.room.message", text("root"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$t1", ghost, "m.room.message", threadReply("$root", "in the thread", false), time.Unix(11, 0))
	mkMsg(t, s, "!r", "$t2", ghost, "m.room.message", threadReply("$root", "also in the channel", true), time.Unix(12, 0))
	mkMsg(t, s, "!r", "$t3", ghost, "m.sticker", threadReply("$root", "a sticker in the thread", false), time.Unix(13, 0))
	mkMsg(t, s, "!r", "$junk", ghost, "m.room.message", `not json`, time.Unix(14, 0))
	mkMsg(t, s, "!r", "$plain", ghost, "m.room.message", text("plain"), time.Unix(15, 0))
	main := []string{"$plain", "$junk", "$t2", "$root"}

	evs, before, err := s.EventsBefore(ctx, "!r", nil, 10)
	require.NoError(t, err)
	require.Nil(t, before)
	require.Equal(t, main, idsOf(evs))

	evs, older, newer, err := s.EventsAround(ctx, "!r", "$t2", 10)
	require.NoError(t, err)
	require.Nil(t, older)
	require.Nil(t, newer)
	require.Equal(t, main, idsOf(evs))

	root, ok := getEvent(t, s, "$root")
	require.True(t, ok)
	evs, _, err = s.EventsAfter(ctx, "!r", Cursor{TS: root.TS, Seq: root.Seq}, 10)
	require.NoError(t, err)
	require.Equal(t, main[:3], idsOf(evs))
}

func TestThreadPagesReadOneThread(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("a"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("b"), time.Unix(10, 0))
	for i, id := range []string{"$a1", "$a2", "$a3"} {
		mkMsg(t, s, "!r", id, ghost, "m.room.message", threadReply("$a", id, false), time.Unix(int64(20+i), 0))
	}
	mkMsg(t, s, "!r", "$b1", ghost, "m.room.message", threadReply("$b", "b1", false), time.Unix(21, 0))
	mkMsg(t, s, "!other", "$o1", ghost, "m.room.message", threadReply("$a", "elsewhere", false), time.Unix(22, 0))
	mkMsg(t, s, "!r", "$react", ghost, "m.reaction", `{"m.relates_to":{"rel_type":"m.annotation","event_id":"$a1","key":"👍"}}`, time.Unix(30, 0))

	page, before, err := s.ThreadEventsBefore(ctx, "!r", "$a", nil, 2)
	require.NoError(t, err)
	require.Equal(t, []string{"$a3", "$a2"}, idsOf(page))
	require.NotNil(t, before)
	page, before, err = s.ThreadEventsBefore(ctx, "!r", "$a", before, 2)
	require.NoError(t, err)
	require.Equal(t, []string{"$a1"}, idsOf(page))
	require.Nil(t, before)

	page, _, err = s.ThreadEventsBefore(ctx, "!r", "$b", nil, 0)
	require.NoError(t, err)
	require.Equal(t, []string{"$b1"}, idsOf(page))
	page, _, err = s.ThreadEventsBefore(ctx, "!r", "$nothing", nil, 10)
	require.NoError(t, err)
	require.Empty(t, page)
}

func TestThreadSummaryCountsAndNames(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	const ana, ben, cat, dee = "@ana:courier.local", "@ben:courier.local", "@cat:courier.local", "@dee:courier.local"
	require.NoError(t, s.SetMember(ctx, "!r", ana, json.RawMessage(`{"membership":"join","displayname":"Ana"}`)))
	require.NoError(t, s.SetMember(ctx, "!r", cat, json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.SetProfile(ctx, ben, ptr("Ben"), nil))
	require.NoError(t, s.SetProfile(ctx, cat, ptr("Cat"), nil))
	mkMsg(t, s, "!r", "$root", ghost, "m.room.message", text("root"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$quiet", ghost, "m.room.message", text("no replies"), time.Unix(10, 0))
	for i, r := range []struct{ id, sender string }{{"$1", ana}, {"$2", ben}, {"$3", ana}, {"$4", cat}, {"$5", dee}, {"$6", ana}} {
		mkMsg(t, s, "!r", r.id, r.sender, "m.room.message", threadReply("$root", r.id, false), time.Unix(int64(20+i), 0))
	}
	mkMsg(t, s, "!r", "$7", ben, "m.room.message", threadReply("$root", "deleted", false), time.Unix(30, 0))
	mkMsg(t, s, "!r", "$x", ben, "m.room.redaction", redactionOf("$7"), time.Unix(31, 0))

	got, err := s.ThreadSummaries(ctx, "!r", []string{"$root", "$quiet", "$root"})
	require.NoError(t, err)
	require.Equal(t, map[string]ThreadSummary{
		"$root": {Replies: 6, LastTS: time.Unix(25, 0), LastSenders: []string{"Ana", "dee", "Cat"}},
	}, got, "a deleted reply doesn't count; names come from the chat, then the profile, then the ID")
}

func TestThreadLookupUsesItsIndex(t *testing.T) {
	s := open(t)
	for name, plan := range map[string][]string{
		"page":    planOf(t, s, threadEventsBeforeSQL, "!r", "$root", int64(math.MaxInt64), int64(math.MaxInt64), 51),
		"summary": planOf(t, s, threadSummariesSQL, "!r", `["$root"]`),
	} {
		joined := strings.Join(plan, "\n")
		t.Logf("%s:\n%s", name, joined)
		require.Contains(t, joined, "USING INDEX events_threads", name)
		require.NotRegexp(t, `(?m)^SCAN events\b`, joined, name)
	}
	requireIndexed(t, planOf(t, s, threadEventsBeforeSQL, "!r", "$root", int64(math.MaxInt64), int64(math.MaxInt64), 51))
}
