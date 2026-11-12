// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// rowOf is roomID's inbox row, wherever the chat is.
func rowOf(t *testing.T, s *Store, roomID string) InboxRow {
	t.Helper()
	rows, _, err := s.InboxPage(context.Background(), InboxQuery{RoomIDs: []string{roomID}})
	require.NoError(t, err)
	require.Len(t, rows, 1, roomID)
	return rows[0]
}

func TestReminderFiresAtDueTimeAndBringsTheChatBack(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	_, err := s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	due := t0.Add(time.Hour)

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, due, "always"))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch), "the row shows the reminder")
	rem := rowOf(t, s, "!r").Reminder
	require.NotNil(t, rem)
	require.Equal(t, Reminder{RoomID: "!r", Condition: "always", DueAt: due, SetAt: t0}, *rem)

	next, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, due, next)

	clock.set(due.Add(-time.Millisecond))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Empty(t, fired, "not due yet")
	requireNoChange(t, ch)

	clock.set(due)
	fired, err = s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, fired)
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, Change{Kind: "reminder", RoomID: "!r"}, nextChange(t, ch))
	requireNoChange(t, ch)

	row := rowOf(t, s, "!r")
	require.False(t, row.Archived, "it came back from the archive")
	require.True(t, row.MarkedUnread)
	require.NotNil(t, row.Reminder, "a fired reminder stays as the row's badge")
	require.Equal(t, due, row.Reminder.FiredAt)
	_, ok, err = s.NextDue(ctx)
	require.NoError(t, err)
	require.False(t, ok, "a fired reminder is not due again")

	// Reading the chat ends a fired reminder; it is gone from the row.
	require.NoError(t, s.ClearFiredReminder(ctx, "!r"))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Nil(t, rowOf(t, s, "!r").Reminder)
	require.NoError(t, s.ClearFiredReminder(ctx, "!r"), "nothing left to clear is not an error")
	requireNoChange(t, ch)
}

func TestClearFiredReminderLeavesAPendingOne(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), "always"))
	require.NoError(t, s.ClearFiredReminder(ctx, "!r"))
	require.NotNil(t, rowOf(t, s, "!r").Reminder, "opening a chat does not cancel a reminder still to come")
}

func TestClearRemindersNamedOrAll(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	for _, id := range []string{"!a", "!b", "!c"} {
		chat(t, s, id, "whatsapp", true, 900_000)
	}
	require.NoError(t, s.SetReminder(ctx, []string{"!a", "!b", "!c"}, t0.Add(time.Hour), "if_no_reply"))

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.ClearReminders(ctx, []string{"!a"}))
	require.Equal(t, Change{Kind: "room", RoomID: "!a"}, nextChange(t, ch))
	requireNoChange(t, ch)
	require.Nil(t, rowOf(t, s, "!a").Reminder)
	require.NotNil(t, rowOf(t, s, "!b").Reminder)

	require.NoError(t, s.ClearReminders(ctx, []string{}), "an empty list clears nothing")
	requireNoChange(t, ch)
	require.NotNil(t, rowOf(t, s, "!b").Reminder)

	require.NoError(t, s.ClearReminders(ctx, nil), "nil clears every reminder")
	got := []string{nextChange(t, ch).RoomID, nextChange(t, ch).RoomID}
	require.ElementsMatch(t, []string{"!b", "!c"}, got)
	requireNoChange(t, ch)
	_, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.False(t, ok)
}

func TestReminderSkippedWhenIReplied(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!quiet", "whatsapp", true, 900_000)
	chat(t, s, "!replied", "whatsapp", true, 900_000)
	chat(t, s, "!always", "whatsapp", true, 900_000)
	chat(t, s, "!failed", "whatsapp", true, 900_000)
	due := t0.Add(time.Hour)
	require.NoError(t, s.SetReminder(ctx, []string{"!quiet", "!replied", "!failed"}, due, "if_no_reply"))
	require.NoError(t, s.SetReminder(ctx, []string{"!always"}, due, "always"))
	// My messages before I set the reminder don't count; one after it does, unless it failed to send. A reaction
	// isn't a reply.
	mkMsg(t, s, "!quiet", "$before", me, "m.room.message", text("earlier"), t0.Add(-time.Minute))
	mkMsg(t, s, "!quiet", "$react", me, "m.reaction", `{"m.relates_to":{"event_id":"$!quiet","key":"x"}}`, t0.Add(time.Minute))
	mkMsg(t, s, "!replied", "$reply", me, "m.room.message", text("on it"), t0.Add(time.Minute))
	mkMsg(t, s, "!always", "$reply2", me, "m.room.message", text("on it"), t0.Add(time.Minute))
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!failed", EventID: "$fail", Sender: me, Type: "m.room.message",
		Content: []byte(text("never went")), TS: t0.Add(time.Minute), Status: "failed",
	})
	require.NoError(t, err)

	ch, cancel := s.Subscribe()
	defer cancel()
	clock.set(due)
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!quiet", "!always", "!failed"}, fired)

	replied := rowOf(t, s, "!replied")
	require.Nil(t, replied.Reminder, "I replied: the reminder is gone")
	require.False(t, replied.MarkedUnread, "and nothing else happened")
	for range 7 { // !replied's room change, and a room and a reminder change for each of the three that fired
		c := nextChange(t, ch)
		require.NotEqual(t, Change{Kind: "reminder", RoomID: "!replied"}, c)
	}
	requireNoChange(t, ch)
	require.NotNil(t, rowOf(t, s, "!always").Reminder, "always fires anyway")
	require.True(t, rowOf(t, s, "!always").MarkedUnread)
}

// "if_no_incoming" (the local API's dismissOnIncomingMessage) is dropped by a message from someone else since it
// was set, and by nothing of mine: my own message, their reaction or their edit of an older message is no new
// message coming in.
func TestReminderSkippedWhenSomethingCameIn(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	for _, id := range []string{"!quiet", "!incoming", "!noreply"} {
		chat(t, s, id, "whatsapp", true, 900_000)
	}
	due := t0.Add(time.Hour)
	require.NoError(t, s.SetReminder(ctx, []string{"!quiet", "!incoming"}, due, "if_no_incoming"))
	require.NoError(t, s.SetReminder(ctx, []string{"!noreply"}, due, "if_no_reply"))
	mkMsg(t, s, "!quiet", "$before", ghost, "m.room.message", text("earlier"), t0.Add(-time.Minute))
	mkMsg(t, s, "!quiet", "$mine", me, "m.room.message", text("on it"), t0.Add(time.Minute))
	mkMsg(t, s, "!quiet", "$react", ghost, "m.reaction", `{"m.relates_to":{"event_id":"$before","key":"x"}}`, t0.Add(time.Minute))
	mkMsg(t, s, "!quiet", "$edit", ghost, "m.room.message", editTo("$before", "earlier still"), t0.Add(2*time.Minute))
	mkMsg(t, s, "!incoming", "$theirs", ghost, "m.room.message", text("news"), t0.Add(time.Minute))
	mkMsg(t, s, "!noreply", "$theirs2", ghost, "m.room.message", text("news"), t0.Add(time.Minute))

	clock.set(due)
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!quiet", "!noreply"}, fired, "their message doesn't cancel if_no_reply")
	incoming := rowOf(t, s, "!incoming")
	require.Nil(t, incoming.Reminder, "a message came in: the reminder is gone")
	require.False(t, incoming.MarkedUnread, "and nothing else happened")
	require.Equal(t, "if_no_incoming", rowOf(t, s, "!quiet").Reminder.Condition)
	require.ErrorIs(t, s.SetReminder(ctx, []string{"!quiet"}, due.Add(time.Hour), "if_unknown"), ErrBadValue)
}

// Review Focus 2: a reminder that came due while Courier was quit fires once at the next chance: not zero times,
// not twice.
func TestOverdueReminderFiresOnceAfterRestart(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	t0 := time.UnixMilli(1_000_000_000)
	due := t0.Add(time.Hour)

	s, err := Open(path)
	require.NoError(t, err)
	clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, due, "always"))
	require.NoError(t, s.Close())

	// Courier was quit through the due time; it opens a day later.
	s, err = Open(path)
	require.NoError(t, err)
	clockAt(s, due.Add(24*time.Hour))
	next, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, due, next, "the overdue reminder is due at once")
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, fired, "it fires on the first chance")
	fired, err = s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Empty(t, fired, "and only once")
	require.NoError(t, s.Close())

	s, err = Open(path)
	require.NoError(t, err)
	defer s.Close()
	clockAt(s, due.Add(48*time.Hour))
	fired, err = s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Empty(t, fired, "not again after another restart")
	_, ok, err = s.NextDue(ctx)
	require.NoError(t, err)
	require.False(t, ok)
	row := rowOf(t, s, "!r")
	require.NotNil(t, row.Reminder)
	require.Equal(t, due.Add(24*time.Hour), row.Reminder.FiredAt, "it fired when the engine next ran")
}

func TestReminderMustBeInTheFuture(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	for name, due := range map[string]time.Time{
		"in the past":           t0.Add(-time.Minute),
		"now":                   t0,
		"more than 5 years out": t0.AddDate(5, 0, 0).Add(time.Millisecond),
	} {
		require.ErrorIs(t, s.SetReminder(ctx, []string{"!r"}, due, "always"), ErrBadValue, name)
	}
	require.ErrorIs(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), "sometimes"), ErrBadValue, "an unknown condition")
	require.ErrorIs(t, s.SetReminder(ctx, []string{"!r", "!nope"}, t0.Add(time.Hour), "always"), ErrNotFound)
	require.Nil(t, rowOf(t, s, "!r").Reminder, "a refused call sets nothing, for any chat")

	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.AddDate(5, 0, 0), "always"), "exactly 5 years is fine")
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Millisecond), "if_no_reply"), "it replaces")
	rem := rowOf(t, s, "!r").Reminder
	require.Equal(t, Reminder{RoomID: "!r", Condition: "if_no_reply", DueAt: t0.Add(time.Millisecond), SetAt: t0}, *rem)
}

func TestSettingAReminderAgainResetsAFiredOne(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Minute), "always"))
	clock.set(t0.Add(time.Minute))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Len(t, fired, 1)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), "always"))
	rem := rowOf(t, s, "!r").Reminder
	require.True(t, rem.FiredAt.IsZero(), "a new reminder has not fired")
	next, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, t0.Add(time.Hour), next)
}

// Ruling 38b: a reminder brings the chat all the way back to the inbox, as its help text says: out of the archive
// and out of Low priority. A hidden chat stays hidden: hiding it was a stronger choice than a reminder undoes.
func TestAFiredReminderBringsALowPriorityChatBackButNotAHiddenOne(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!low", "whatsapp", true, 10)
	chat(t, s, "!hid", "whatsapp", true, 11)
	_, err := s.SetLowPriority(ctx, []string{"!low"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!hid"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetReminder(ctx, []string{"!low", "!hid"}, t0.Add(time.Minute), "always"))

	clock.set(t0.Add(time.Minute))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!low", "!hid"}, fired)
	low := rowOf(t, s, "!low")
	require.False(t, low.LowPriority, "back from Low priority")
	require.True(t, low.MarkedUnread)
	require.Contains(t, allPages(t, s, InboxQuery{Space: "inbox"}), "!low", "in the inbox again")
	require.True(t, rowOf(t, s, "!hid").Hidden, "a hidden chat stays hidden")
	require.NotContains(t, allPages(t, s, InboxQuery{Space: "inbox"}), "!hid")
}

// NextDueAfter skips what is already due by after, in every part: an overdue reminder left waiting doesn't hide a
// held message due later, and NextDue still reports the overdue one.
func TestNextDueAfterSkipsWhatIsAlreadyDue(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	chat(t, s, "!r", "whatsapp", true, 900_000)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Minute), "always"))
	clock.set(t0.Add(2 * time.Minute)) // the reminder is overdue
	now := clock.now()
	require.NoError(t, s.Hold(ctx, Event{
		RoomID: "!r", EventID: "$h", Sender: me, Type: "m.room.message", Content: json.RawMessage(text("held")), TS: now,
	}, now.Add(750*time.Millisecond)))

	next, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, t0.Add(time.Minute), next, "NextDue counts the overdue reminder")
	next, ok, err = s.NextDueAfter(ctx, now)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, now.Add(750*time.Millisecond), next, "NextDueAfter doesn't")
	_, ok, err = s.NextDueAfter(ctx, now.Add(750*time.Millisecond))
	require.NoError(t, err)
	require.False(t, ok, "nothing after the hold")
}
