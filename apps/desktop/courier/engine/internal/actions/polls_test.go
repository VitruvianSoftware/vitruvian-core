// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
)

func TestCreatePollValidates(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures()) // 2 to 12 options of at most 100 characters
	twelve := make([]string, 12)
	for i := range twelve {
		twelve[i] = strings.Repeat("o", i+1)
	}
	before := w.eventCount(t, room)
	for _, tc := range []struct {
		name     string
		question string
		options  []string
	}{
		{"a blank question", "   ", []string{"a", "b"}},
		{"a question of 301 characters", strings.Repeat("q", 301), []string{"a", "b"}},
		{"one option", "Q?", []string{"a"}},
		{"thirteen options", "Q?", append(twelve, "more")},
		{"a blank option", "Q?", []string{"a", "  "}},
		{"an option of 101 characters", "Q?", []string{"a", strings.Repeat("é", 101)}},
		{"two the same but for case", "Q?", []string{"Pizza", " pizza "}},
	} {
		_, err := w.a.CreatePoll(ctx, room, tc.question, tc.options, false)
		require.ErrorIs(t, err, ErrBadValue, tc.name)
	}
	require.Equal(t, before, w.eventCount(t, room))
	require.Empty(t, w.n.Polls)

	// 300 characters, 12 options, 100 characters each: just fits.
	_, err := w.a.CreatePoll(ctx, room, strings.Repeat("q", 300), append(twelve[:11], strings.Repeat("é", 100)), true)
	require.NoError(t, err)
	require.Equal(t, 12, recv(t, w.n.Polls, "the biggest poll").MaxSelections)

	id, err := w.a.CreatePoll(ctx, room, "  Lunch?  ", []string{" Pizza", "Sushi "}, false)
	require.NoError(t, err)
	require.Equal(t, fakenet.Poll{
		PortalID: "alice", Question: "Lunch?", Options: []string{"Pizza", "Sushi"}, MaxSelections: 1,
	}, recv(t, w.n.Polls, "the poll"))
	e := w.waitStatus(t, id, "sent")
	require.Equal(t, map[string]any{
		"kind": "org.matrix.msc3381.poll.disclosed", "max_selections": float64(1),
		"question": map[string]any{"org.matrix.msc1767.text": "Lunch?"},
		"answers": []any{
			map[string]any{"id": "1", "org.matrix.msc1767.text": "Pizza"},
			map[string]any{"id": "2", "org.matrix.msc1767.text": "Sushi"},
		},
	}, content(t, e)["org.matrix.msc3381.poll.start"])

	// A chat whose network has no polls.
	w2, room2 := startFeatureWorld(t, googleMessagesFeatures())
	_, err = w2.a.CreatePoll(ctx, room2, "Lunch?", []string{"Pizza", "Sushi"}, false)
	require.ErrorIs(t, err, ErrNotSupported)
	require.Empty(t, w2.n.Polls)
}

func TestVoteAndRetract(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	theirs := w.firstID(t, room)
	poll, err := w.a.CreatePoll(ctx, room, "Lunch?", []string{"Pizza", "Sushi", "Salad"}, false)
	require.NoError(t, err)
	recv(t, w.n.Polls, "the poll")
	w.waitStatus(t, poll, "sent")
	mine := func() []string {
		t.Helper()
		tallies, err := w.s.PollTallies(ctx, room, []string{poll})
		require.NoError(t, err)
		return tallies[poll].Mine
	}

	vote, err := w.a.Vote(ctx, poll, []string{"2"})
	require.NoError(t, err)
	require.Equal(t, fakenet.Vote{PortalID: "alice", PollID: "out-" + poll, Answers: []string{"2"}}, recv(t, w.n.Votes, "the vote"))
	w.waitStatus(t, vote, "sent")
	require.Equal(t, []string{"2"}, mine())

	// None takes the vote back.
	retract, err := w.a.Vote(ctx, poll, nil)
	require.NoError(t, err)
	require.Equal(t, []string{}, recv(t, w.n.Votes, "the retraction").Answers)
	w.waitStatus(t, retract, "sent")
	require.Empty(t, mine())

	before := w.eventCount(t, room)
	for name, ids := range map[string][]string{
		"an option it hasn't": {"4"},
		"two of a one-answer": {"1", "2"},
		"one twice":           {"1", "1"},
	} {
		_, err = w.a.Vote(ctx, poll, ids)
		require.ErrorIs(t, err, ErrBadValue, name)
	}
	_, err = w.a.Vote(ctx, theirs, []string{"1"})
	require.ErrorIs(t, err, ErrNotSupported, "not a poll")
	require.Equal(t, before, w.eventCount(t, room))
	require.Empty(t, w.n.Votes)

	// A poll of many answers takes up to all of them, each once.
	multi, err := w.a.CreatePoll(ctx, room, "Which days?", []string{"Mon", "Tue"}, true)
	require.NoError(t, err)
	recv(t, w.n.Polls, "the poll")
	w.waitStatus(t, multi, "sent")
	_, err = w.a.Vote(ctx, multi, []string{"2", "1"})
	require.NoError(t, err)
	require.Equal(t, []string{"2", "1"}, recv(t, w.n.Votes, "the vote").Answers)
}
