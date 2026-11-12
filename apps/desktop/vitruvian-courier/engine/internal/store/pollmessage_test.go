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

// sqlTypes reads a quoted SQL list ('a','b') back into its values.
func sqlTypes(list string) []string {
	var out []string
	for _, v := range strings.Split(list, ",") {
		out = append(out, strings.Trim(strings.TrimSpace(v), "'"))
	}
	return out
}

// The Go and SQL halves of "what counts as a message" agree: isMessageLike and messageLikeTypes, with polls (their
// start) in and their votes and end out. What counts as unread is a part of it, and the shipped set (V1) is what it
// was.
func TestMessageSetsAgree(t *testing.T) {
	sqlSet := sqlTypes(messageLikeTypes)
	for _, typ := range []string{
		"m.room.message", "m.sticker", "m.room.encrypted", pollStartType, pollResponseType, pollEndType,
		"m.reaction", "m.room.redaction", "m.room.name", "m.room.member", "com.beeper.disappearing_timer", "",
	} {
		require.Equal(t, strings.Contains(","+strings.Join(sqlSet, ",")+",", ","+typ+","), isMessageLike(typ, json.RawMessage(`{}`)),
			"Go and SQL disagree on %q", typ)
	}
	require.Contains(t, sqlSet, pollStartType)
	require.NotContains(t, sqlSet, pollResponseType)
	require.NotContains(t, sqlSet, pollEndType)
	for _, typ := range sqlTypes(unreadTypes) {
		require.Contains(t, sqlSet, typ, "an unread type is a message type")
	}
	require.Contains(t, sqlTypes(unreadTypes), pollStartType)
	require.Equal(t, []string{"m.room.message", "m.sticker", "m.room.encrypted"}, sqlTypes(messageLikeTypesV1))
	require.False(t, isMessageLike(pollStartType, json.RawMessage(editTo("$p", "x"))), "an edit of a poll is no new message")
}

// A poll from someone else is a message: it moves its chat to the top, counts as unread and is the preview (its
// question). Votes and the end don't, and deleting the poll points the chat back at the message before it.
func TestAPollIsANewMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	t1 := time.Unix(1000, 0)
	mkRoom(t, s, "!p", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	mkMsg(t, s, "!p", "$before", ghost, "m.room.message", text("hello"), t1)
	mkMsg(t, s, "!other", "$o", ghost, "m.room.message", text("newer"), t1.Add(time.Minute))
	rows, err := s.Inbox(ctx)
	require.NoError(t, err)
	require.Equal(t, "!other", rows[0].ID)

	mkMsg(t, s, "!p", "$poll", ghost2, pollStartType, pollContent("Lunch on Friday?", 1, "a=yes", "b=no"), t1.Add(2*time.Minute))
	rows, err = s.Inbox(ctx)
	require.NoError(t, err)
	require.Equal(t, "!p", rows[0].ID, "the poll moved its chat to the top")
	p := rows[0]
	require.Equal(t, t1.Add(2*time.Minute).UnixMilli(), p.LastTS.UnixMilli())
	require.Equal(t, "Lunch on Friday?", p.Preview)
	require.Equal(t, "poll", p.PreviewKind)
	require.Equal(t, 2, p.Unread, "the message and the poll")

	// A vote and the end are not messages.
	mkMsg(t, s, "!p", "$vote", ghost, pollResponseType, voteFor("$poll", "a"), t1.Add(3*time.Minute))
	mkMsg(t, s, "!p", "$end", ghost2, pollEndType, endOf("$poll"), t1.Add(4*time.Minute))
	p = inboxByID(t, s)["!p"]
	require.Equal(t, t1.Add(2*time.Minute).UnixMilli(), p.LastTS.UnixMilli())
	require.Equal(t, "poll", p.PreviewKind)
	require.Equal(t, 2, p.Unread)

	// Deleted, the poll is neither the preview nor unread.
	mkMsg(t, s, "!p", "$del", ghost2, "m.room.redaction", redactionOf("$poll"), t1.Add(5*time.Minute))
	p = inboxByID(t, s)["!p"]
	require.Equal(t, "hello", p.Preview)
	require.Equal(t, "text", p.PreviewKind)
	require.Equal(t, 1, p.Unread)
}

func TestAPollPreviewIsItsQuestionCut(t *testing.T) {
	preview, kind, media := previewOf(pollStartType, pollContent(strings.Repeat("é", maxPreviewRunes+10), 1, "a=x"))
	require.Equal(t, "poll", kind)
	require.Empty(t, media)
	require.Equal(t, strings.Repeat("é", maxPreviewRunes), preview)
	preview, kind, _ = previewOf(pollStartType, `not json`)
	require.Equal(t, "", preview, "an unreadable poll previews as empty")
	require.Equal(t, "poll", kind)
}

// A poll from someone else brings an archived chat back, as any new message from them does.
func TestAPollUnarchivesItsChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	archivedAt := time.Unix(1000, 0)
	clockAt(s, archivedAt)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	_, err := s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	mkMsg(t, s, "!r", "$poll", ghost, pollStartType, pollContent("Dinner?", 1, "a=yes"), archivedAt.Add(time.Second))
	require.False(t, inboxByID(t, s)["!r"].Archived, "their poll brought the chat back")
}

// A poll from someone else after a message was scheduled "if no reply" is their reply: the message is canceled.
// Their vote isn't.
func TestAPollCancelsIfNoReply(t *testing.T) {
	s := open(t)
	clock := clockAt(s, t0)
	for _, r := range []string{"!poll", "!vote"} {
		mkRoom(t, s, r, time.Unix(1, 0))
		mkMsg(t, s, r, "$mine"+r, me, pollStartType, pollContent("Lunch?", 1, "a=yes"), t0.Add(-time.Minute))
	}
	schedule(t, s, "!poll", "$p", "ping", t0.Add(time.Hour), condIfNoReply)
	schedule(t, s, "!vote", "$v", "ping", t0.Add(time.Hour), condIfNoReply)
	mkMsg(t, s, "!poll", "$theirs", ghost, pollStartType, pollContent("Or dinner?", 1, "a=yes"), t0.Add(time.Minute))
	mkMsg(t, s, "!vote", "$vote", ghost, pollResponseType, voteFor("$mine!vote", "a"), t0.Add(time.Minute))
	clock.set(t0.Add(time.Hour))
	require.Equal(t, []string{"$v"}, claimDue(t, s))
	require.Equal(t, stateCanceled, scheduledStates(t, s, "!poll")["$p"])
}

// My own poll after I set an "if no reply" reminder counts as my reply: the reminder doesn't fire.
func TestMyPollIsAReplyForReminders(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), condIfNoReply))
	mkMsg(t, s, "!r", "$poll", me, pollStartType, pollContent("Lunch?", 1, "a=yes"), t0.Add(time.Minute))
	clock.set(t0.Add(time.Hour))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Empty(t, fired)
	require.Nil(t, rowOf(t, s, "!r").Reminder, "I replied with a poll: the reminder is gone")
}
