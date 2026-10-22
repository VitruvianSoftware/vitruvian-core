// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const (
	ghost2 = "@ghost2:courier.local"
	ghost3 = "@ghost3:courier.local"
)

// pollContent is a poll.start as bridges send it: the question and answers as MSC1767 text.
func pollContent(question string, maxSelections int, answers ...string) string {
	opts := make([]map[string]string, len(answers))
	for i, a := range answers {
		id, text, _ := strings.Cut(a, "=")
		opts[i] = map[string]string{"id": id, "org.matrix.msc1767.text": text}
	}
	b, _ := json.Marshal(map[string]any{
		"org.matrix.msc1767.text": question,
		pollStartType: map[string]any{
			"kind": "org.matrix.msc3381.poll.disclosed", "max_selections": maxSelections,
			"question": map[string]string{"org.matrix.msc1767.text": question}, "answers": opts,
		},
	})
	return string(b)
}

func voteFor(poll string, answers ...string) string {
	if answers == nil {
		answers = []string{}
	}
	b, _ := json.Marshal(map[string]any{
		"m.relates_to":   map[string]string{"rel_type": "m.reference", "event_id": poll},
		pollResponseType: map[string]any{"answers": answers},
	})
	return string(b)
}

func endOf(poll string) string {
	b, _ := json.Marshal(map[string]any{
		"m.relates_to": map[string]string{"rel_type": "m.reference", "event_id": poll},
		pollEndType:    map[string]any{},
	})
	return string(b)
}

func tally(t *testing.T, s *Store, roomID, pollID string) PollTally {
	t.Helper()
	got, err := s.PollTallies(context.Background(), roomID, []string{pollID})
	require.NoError(t, err)
	require.Contains(t, got, pollID)
	return got[pollID]
}

func votes(p PollTally) map[string]int {
	out := map[string]int{}
	for _, o := range p.Options {
		out[o.ID] = o.Votes
	}
	return out
}

func mkVote(t *testing.T, s *Store, id, sender, content string, ts time.Time, status string) {
	t.Helper()
	insert(t, s, Event{
		RoomID: "!r", EventID: id, Sender: sender, Type: pollResponseType, Content: json.RawMessage(content),
		TS: ts, Status: status,
	})
}

func TestTallyCountsEachPersonsNewestVote(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$p", ghost, pollStartType, pollContent("Lunch?", 1, "a=Pizza", "b=Sushi", "c=Tacos"), time.Unix(10, 0))
	mkVote(t, s, "$v1", ghost, voteFor("$p", "a"), time.Unix(11, 0), "")
	mkVote(t, s, "$v2", ghost, voteFor("$p", "b"), time.Unix(12, 0), "") // changed their mind
	mkVote(t, s, "$v3", me, voteFor("$p", "a"), time.Unix(13, 0), "sent")
	mkVote(t, s, "$v4", me, voteFor("$p", "c"), time.Unix(14, 0), "failed") // never reached the network
	mkVote(t, s, "$v5", ghost2, voteFor("$p", "a", "c"), time.Unix(15, 0), "")
	mkVote(t, s, "$v6", ghost3, voteFor("$p", "c"), time.Unix(16, 0), "")
	mkMsg(t, s, "!r", "$x", ghost3, "m.room.redaction", redactionOf("$v6"), time.Unix(17, 0)) // deleted

	p := tally(t, s, "!r", "$p")
	require.Equal(t, "Lunch?", p.Question)
	require.Equal(t, 1, p.MaxSelections)
	require.Equal(t, []PollOption{{ID: "a", Text: "Pizza", Votes: 2}, {ID: "b", Text: "Sushi", Votes: 1}, {ID: "c", Text: "Tacos"}},
		p.Options, "max_selections caps ghost2's two answers at the first")
	require.Equal(t, 3, p.Voters)
	require.Equal(t, []string{"a"}, p.Mine)
	require.False(t, p.Ended)

	// Many answers: each counts.
	mkMsg(t, s, "!r", "$q", ghost, pollStartType, pollContent("When?", 2, "x=Mon", "y=Tue"), time.Unix(20, 0))
	mkVote(t, s, "$w1", ghost, voteFor("$q", "x", "y"), time.Unix(21, 0), "")
	q := tally(t, s, "!r", "$q")
	require.Equal(t, map[string]int{"x": 1, "y": 1}, votes(q))
	require.Equal(t, 1, q.Voters)
	require.Empty(t, q.Mine)

	both, err := s.PollTallies(context.Background(), "!r", []string{"$p", "$q", "$p", "$x", "$nowhere"})
	require.NoError(t, err)
	require.Len(t, both, 2, "only polls, each once")
	other, err := s.PollTallies(context.Background(), "!elsewhere", []string{"$p"})
	require.NoError(t, err)
	require.Empty(t, other, "a poll of another chat")

	// A vote in another chat that names this poll isn't a vote on it.
	mkRoom(t, s, "!elsewhere", time.Unix(1, 0))
	insert(t, s, Event{
		RoomID: "!elsewhere", EventID: "$stray", Sender: ghost3, Type: pollResponseType,
		Content: json.RawMessage(voteFor("$p", "c")), TS: time.Unix(30, 0),
	})
	require.Equal(t, p, tally(t, s, "!r", "$p"))
}

func TestVotesForUnknownOptionsDontCount(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$p", ghost, pollStartType, pollContent("Lunch?", 1, "a=Pizza", "b=Sushi"), time.Unix(10, 0))
	mkVote(t, s, "$v1", ghost, voteFor("$p", "zzz"), time.Unix(11, 0), "")
	mkVote(t, s, "$v2", ghost2, voteFor("$p", "zzz", "b"), time.Unix(12, 0), "")
	mkVote(t, s, "$v3", ghost3, voteFor("$p", "a"), time.Unix(13, 0), "")
	mkVote(t, s, "$v4", ghost3, voteFor("$p"), time.Unix(14, 0), "") // took their vote back
	mkVote(t, s, "$v5", me, `{"m.relates_to":{"event_id":"$p"},"org.matrix.msc3381.poll.response":"garbage"}`, time.Unix(15, 0), "sent")

	p := tally(t, s, "!r", "$p")
	require.Equal(t, map[string]int{"a": 0, "b": 1}, votes(p), "the unknown option is skipped, not counted against the cap")
	require.Equal(t, 1, p.Voters)
	require.Empty(t, p.Mine)
}

func TestPollEndedOnlyByItsSender(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$p", ghost, pollStartType, pollContent("Lunch?", 1, "a=Pizza"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$e1", ghost2, pollEndType, endOf("$p"), time.Unix(11, 0))
	require.False(t, tally(t, s, "!r", "$p").Ended, "someone else can't end it")
	mkMsg(t, s, "!r", "$e2", ghost, pollEndType, endOf("$p"), time.Unix(12, 0))
	require.True(t, tally(t, s, "!r", "$p").Ended)

	// My end that the network refused doesn't end my poll.
	insert(t, s, Event{
		RoomID: "!r", EventID: "$mine", Sender: me, Type: pollStartType,
		Content: json.RawMessage(pollContent("Dinner?", 1, "a=Yes")), TS: time.Unix(20, 0), Status: "sent",
	})
	insert(t, s, Event{
		RoomID: "!r", EventID: "$e3", Sender: me, Type: pollEndType, Content: json.RawMessage(endOf("$mine")),
		TS: time.Unix(21, 0), Status: "failed",
	})
	require.False(t, tally(t, s, "!r", "$mine").Ended)
}

func TestPollTextIsSearchable(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	content := pollContent("Where shall we climb?", 1, "a=Boulder gym", "b=Crag outside")
	mkMsg(t, s, "!r", "$p", ghost, pollStartType, content, time.Unix(10, 0))

	text, kind, ok := MessageText(pollStartType, json.RawMessage(content))
	require.True(t, ok)
	require.Equal(t, "text", kind)
	require.Equal(t, "Where shall we climb?\nBoulder gym\nCrag outside", text)
	require.Equal(t, []string{"$p"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("climb")})), "the question")
	require.Equal(t, []string{"$p"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("crag"), Kinds: []string{"text"}})), "an option")

	// A vote or an end is never a hit, and a poll on disk before 4.3 is indexed by the backfill.
	mkVote(t, s, "$v", ghost, voteFor("$p", "a"), time.Unix(11, 0), "")
	require.Equal(t, []string{"$p"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("climb")})))
	_, _, ok = MessageText(pollResponseType, json.RawMessage(voteFor("$p", "a")))
	require.False(t, ok)
	_, err := s.db.Exec(context.Background(), `UPDATE events SET doc_id = NULL WHERE event_id = '$p';
		DELETE FROM search_messages; UPDATE search_state SET value = 0 WHERE key = 'backfill_after';
		UPDATE search_state SET value = (SELECT MAX(rowid) FROM events) WHERE key = 'backfill_until'`)
	require.NoError(t, err)
	require.Empty(t, matches(t, s, `"climb"`))
	backfillAll(t, s, 100)
	require.Equal(t, []string{"$p"}, matches(t, s, `"climb"`))
}

func TestTallyLookupUsesItsIndex(t *testing.T) {
	s := open(t)
	plan := strings.Join(planOf(t, s, pollRefsSQL, `["$p"]`), "\n")
	t.Log(plan)
	require.Contains(t, plan, "USING INDEX events_refs")
	require.NotRegexp(t, `(?m)^SCAN events\b`, plan)
}
