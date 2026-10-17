// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const day = 24 * time.Hour

func mkRule(t *testing.T, s *Store, scope, trigger, chatType string, d time.Duration) Rule {
	t.Helper()
	r, err := s.SetRule(context.Background(), Rule{Scope: scope, Trigger: trigger, ChatType: chatType, Duration: d, Enabled: true})
	require.NoError(t, err)
	require.NotZero(t, r.ID)
	return r
}

// dueAt is roomID's pending auto-archive time, or the zero time when there is none.
func dueAt(t *testing.T, s *Store, roomID string) time.Time {
	t.Helper()
	var ms int64
	require.NoError(t, s.db.QueryRow(context.Background(), "SELECT COALESCE((SELECT due_at FROM archive_due WHERE room_id=$1), 0)", roomID).Scan(&ms))
	return msTime(ms)
}

// chatAt makes a chat on network whose one message, from someone else, is at ts.
func chatAt(t *testing.T, s *Store, id, network string, ts time.Time) {
	t.Helper()
	require.NoError(t, s.UpsertRoom(context.Background(), Room{ID: id, Network: network, Name: id, IsDirect: true, CreatedAt: time.Unix(1, 0)}))
	mkMsg(t, s, id, "$"+id, ghost, "m.room.message", text("hello"), ts)
}

func TestAfterReplyArchivesAfterTheDelayUnlessTheyWriteBack(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!a", "whatsapp", t0.Add(-time.Hour))
	chatAt(t, s, "!b", "whatsapp", t0.Add(-time.Hour))

	mkMsg(t, s, "!a", "$ra", me, "m.room.message", text("ok"), t0)
	mkMsg(t, s, "!b", "$rb", me, "m.room.message", text("ok"), t0)
	require.Equal(t, t0.Add(10*time.Minute), dueAt(t, s, "!a"), "my reply schedules the archive at its time + the delay")
	next, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, t0.Add(10*time.Minute), next)

	mkMsg(t, s, "!b", "$back", ghost, "m.room.message", text("wait"), t0.Add(5*time.Minute))
	require.True(t, dueAt(t, s, "!b").IsZero(), "they wrote back: no archive")

	clock.set(t0.Add(10*time.Minute - time.Millisecond))
	archived, err := s.ArchiveDue(ctx)
	require.NoError(t, err)
	require.Empty(t, archived)

	ch, cancel := s.Subscribe()
	defer cancel()
	clock.set(t0.Add(10 * time.Minute))
	archived, err = s.ArchiveDue(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!a"}, archived)
	require.Equal(t, Change{Kind: "room", RoomID: "!a"}, nextChange(t, ch))
	requireNoChange(t, ch)
	require.True(t, rowOf(t, s, "!a").Archived)
	require.False(t, rowOf(t, s, "!b").Archived)
	_, ok, err = s.NextDue(ctx)
	require.NoError(t, err)
	require.False(t, ok, "nothing is left pending")
}

func TestAMessageOfMineBackfilledOrEditedSchedulesNothing(t *testing.T) {
	s := open(t)
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!r", "whatsapp", t0)
	mkMsg(t, s, "!r", "$old", me, "m.room.message", text("old"), t0.Add(-time.Hour))
	require.True(t, dueAt(t, s, "!r").IsZero(), "a backfilled older reply of mine is not my latest word")
	mkMsg(t, s, "!r", "$ed", me, "m.room.message",
		`{"msgtype":"m.text","body":"* old","m.relates_to":{"rel_type":"m.replace","event_id":"$old"}}`, t0.Add(time.Minute))
	require.True(t, dueAt(t, s, "!r").IsZero(), "an edit is not a reply")
}

func TestNoRuleSchedulesNothing(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	r := mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	r.Enabled = false
	_, err := s.SetRule(ctx, r)
	require.NoError(t, err)
	chatAt(t, s, "!r", "whatsapp", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$me", me, "m.room.message", text("ok"), t0)
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$!r", t0.Add(-time.Hour)))
	require.True(t, dueAt(t, s, "!r").IsZero(), "a disabled rule does nothing")
}

func TestAfterReadArchivesAfterTheDelay(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	mkRule(t, s, "all", "after_read", "all", time.Hour)
	chatAt(t, s, "!here", "whatsapp", t0.Add(-day))
	chatAt(t, s, "!phone", "whatsapp", t0.Add(-day))

	require.NoError(t, s.MarkReadLocal(ctx, "!here", "$!here", t0.Add(-day)))
	require.NoError(t, s.SetRead(ctx, "!phone", "$!phone", t0.Add(-day)), "a read on my phone counts too")
	require.Equal(t, t0.Add(time.Hour), dueAt(t, s, "!here"), "now + the delay")
	require.Equal(t, t0.Add(time.Hour), dueAt(t, s, "!phone"))

	clock.set(t0.Add(30 * time.Minute))
	require.NoError(t, s.MarkReadLocal(ctx, "!here", "$!here", t0.Add(-day)))
	require.Equal(t, t0.Add(time.Hour), dueAt(t, s, "!here"), "a marker that doesn't move schedules nothing new")

	clock.set(t0.Add(time.Hour))
	archived, err := s.ArchiveDue(ctx)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"!here", "!phone"}, archived)
	require.True(t, rowOf(t, s, "!here").Archived)
	require.True(t, rowOf(t, s, "!phone").Archived)
}

// Ruling 8: only a message from someone else that is newer than the chat's newest message cancels a pending
// auto-archive.
func TestBackfillDoesNotCancelAutoArchive(t *testing.T) {
	s := open(t)
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!r", "whatsapp", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$me", me, "m.room.message", text("ok"), t0)
	want := t0.Add(10 * time.Minute)

	mkMsg(t, s, "!r", "$older", ghost, "m.room.message", text("from yesterday"), t0.Add(-30*time.Minute))
	require.Equal(t, want, dueAt(t, s, "!r"), "a backfilled older message")
	mkMsg(t, s, "!r", "$same", ghost, "m.room.message", text("same moment"), t0)
	require.Equal(t, want, dueAt(t, s, "!r"), "one at the same time as the newest is not newer")
	mkMsg(t, s, "!r", "$react", ghost, "m.reaction", `{"m.relates_to":{"event_id":"$me","key":"x"}}`, t0.Add(time.Minute))
	require.Equal(t, want, dueAt(t, s, "!r"), "a reaction")

	mkMsg(t, s, "!r", "$new", ghost, "m.room.message", text("new"), t0.Add(time.Millisecond))
	require.True(t, dueAt(t, s, "!r").IsZero(), "a newer message cancels it")
}

func TestOlderThanRuleArchivesOnlyItsSpace(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(10_000_000_000)
	clockAt(s, t0)
	old, recent := t0.Add(-8*day), t0.Add(-day)
	chatAt(t, s, "!wa", "whatsapp", old)
	chatAt(t, s, "!work", "whatsapp", old)
	chatAt(t, s, "!tg", "telegram", old)
	chatAt(t, s, "!tgnew", "telegram", recent)
	chatAt(t, s, "!tglow", "telegram", old)
	chatAt(t, s, "!tgreq", "telegram", old)
	chatAt(t, s, "!tghid", "telegram", old)
	_, err := s.SetLowPriority(ctx, []string{"!tglow"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!tghid"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetRequest(ctx, "!tgreq", true))
	work := mkLabel(t, s, "Work")
	_, err = s.SetLabel(ctx, []string{"!work"}, work.ID, true)
	require.NoError(t, err)

	mkRule(t, s, "account:telegram", "older_than", "all", 7*day)
	archived, err := s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!tg"}, archived, "only the old chat in that account's inbox place")

	mkRule(t, s, "label:"+strconv.FormatInt(work.ID, 10), "older_than", "all", 7*day)
	archived, err = s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!work"}, archived)
	require.False(t, rowOf(t, s, "!wa").Archived)

	disabled := mkRule(t, s, "all", "older_than", "all", 7*day)
	disabled.Enabled = false
	_, err = s.SetRule(ctx, disabled)
	require.NoError(t, err)
	archived, err = s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Empty(t, archived, "a disabled rule sweeps nothing")

	disabled.Enabled = true
	_, err = s.SetRule(ctx, disabled)
	require.NoError(t, err)
	archived, err = s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!wa"}, archived, "scope all is the inbox")
	for _, id := range []string{"!tgnew", "!tglow", "!tgreq", "!tghid"} {
		require.False(t, rowOf(t, s, id).Archived, id)
	}
}

func TestReadOnlySkipsUnreadAndMarkedUnread(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(10_000_000_000)
	clockAt(s, t0)
	for _, id := range []string{"!read", "!unread", "!marked", "!mine"} {
		chatAt(t, s, id, "whatsapp", t0.Add(-day))
	}
	require.NoError(t, s.MarkReadLocal(ctx, "!read", "$!read", t0.Add(-day)))
	require.NoError(t, s.MarkReadLocal(ctx, "!marked", "$!marked", t0.Add(-day)))
	_, err := s.SetMarkedUnread(ctx, []string{"!marked"}, true)
	require.NoError(t, err)
	require.NoError(t, s.MarkReadLocal(ctx, "!mine", "$!mine", t0.Add(-day)))
	mkMsg(t, s, "!mine", "$mine", me, "m.room.message", text("bye"), t0.Add(-time.Hour))

	got, err := s.ArchiveMatching(ctx, ArchiveMatch{ReadOnly: true, DryRun: true})
	require.NoError(t, err)
	require.Equal(t, []string{"!mine", "!read"}, got)

	// A rule for read chats only is the same thing.
	mkRule(t, s, "all", "older_than", "read", 3*day)
	clockAt(s, t0.Add(4*day))
	archived, err := s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!mine", "!read"}, archived)
	require.False(t, rowOf(t, s, "!unread").Archived)
	require.False(t, rowOf(t, s, "!marked").Archived)
}

func TestRulesNeverArchivePinned(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(10_000_000_000)
	clock := clockAt(s, t0)
	chatAt(t, s, "!pin", "whatsapp", t0.Add(-30*day))
	chatAt(t, s, "!other", "whatsapp", t0.Add(-30*day))
	require.NoError(t, s.SetPinned(ctx, "!pin", true))

	got, err := s.ArchiveMatching(ctx, ArchiveMatch{})
	require.NoError(t, err)
	require.Equal(t, []string{"!other"}, got, "archive everything leaves the pin")
	_, err = s.SetArchived(ctx, []string{"!other"}, false)
	require.NoError(t, err)

	mkRule(t, s, "all", "older_than", "all", 7*day)
	archived, err := s.SweepOlderThan(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!other"}, archived)

	mkRule(t, s, "all", "after_reply", "all", 0)
	mkMsg(t, s, "!pin", "$me", me, "m.room.message", text("ok"), t0)
	require.Equal(t, t0, dueAt(t, s, "!pin"), "0 min: due at once")
	clock.set(t0.Add(time.Second))
	archived, err = s.ArchiveDue(ctx)
	require.NoError(t, err)
	require.Empty(t, archived)
	require.False(t, rowOf(t, s, "!pin").Archived)
	_, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.False(t, ok, "the pinned chat's pending archive is dropped, not retried forever")
}

func TestArchiveMatchingDryRunChangesNothing(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(10_000_000_000)
	clockAt(s, t0)
	chatAt(t, s, "!old", "whatsapp", t0.Add(-10*day))
	chatAt(t, s, "!new", "whatsapp", t0.Add(-time.Hour))
	chatAt(t, s, "!tg", "telegram", t0.Add(-10*day))

	ch, cancel := s.Subscribe()
	defer cancel()
	m := ArchiveMatch{Space: "account:whatsapp", OlderThan: 7 * day, DryRun: true}
	got, err := s.ArchiveMatching(ctx, m)
	require.NoError(t, err)
	require.Equal(t, []string{"!old"}, got)
	requireNoChange(t, ch)
	require.False(t, rowOf(t, s, "!old").Archived)

	m.DryRun = false
	got, err = s.ArchiveMatching(ctx, m)
	require.NoError(t, err)
	require.Equal(t, []string{"!old"}, got)
	require.Equal(t, Change{Kind: "room", RoomID: "!old"}, nextChange(t, ch))
	requireNoChange(t, ch)
	require.True(t, rowOf(t, s, "!old").Archived)

	got, err = s.ArchiveMatching(ctx, ArchiveMatch{DryRun: true})
	require.NoError(t, err)
	require.Equal(t, []string{"!new", "!tg"}, got, `"" is the inbox; OlderThan 0 is any age; the archived one is left out`)

	_, err = s.ArchiveMatching(ctx, ArchiveMatch{Space: "archive"})
	require.ErrorIs(t, err, ErrBadValue, "a space without an inbox place")
	_, err = s.ArchiveMatching(ctx, ArchiveMatch{Space: "nowhere"})
	require.ErrorIs(t, err, ErrBadValue)
	_, err = s.ArchiveMatching(ctx, ArchiveMatch{OlderThan: -time.Hour})
	require.ErrorIs(t, err, ErrBadValue)
}

func TestRuleDurationsAreExact(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, time.UnixMilli(10_000_000_000))
	minute := time.Minute
	afterOK := []time.Duration{0, minute, 5 * minute, 10 * minute, 30 * minute, time.Hour, 4 * time.Hour, day, 7 * day}
	olderOK := []time.Duration{3 * day, 7 * day, 14 * day, 28 * day, 90 * day, 365 * day}
	for _, trig := range []string{"after_reply", "after_read"} {
		for _, d := range afterOK {
			_, err := s.SetRule(ctx, Rule{Scope: "all", Trigger: trig, ChatType: "all", Duration: d})
			require.NoError(t, err, "%s %v", trig, d)
		}
		for _, d := range []time.Duration{2 * minute, 3 * day, -minute, 10*minute + time.Millisecond} {
			_, err := s.SetRule(ctx, Rule{Scope: "all", Trigger: trig, ChatType: "all", Duration: d})
			require.ErrorIs(t, err, ErrBadValue, "%s %v", trig, d)
		}
	}
	for i, d := range olderOK {
		_, err := s.SetRule(ctx, Rule{Scope: "account:n" + strconv.Itoa(i), Trigger: "older_than", ChatType: "all", Duration: d, Enabled: true})
		require.NoError(t, err, "older_than %v", d)
	}
	for _, d := range []time.Duration{0, 10 * minute, 2 * day, 7*day + time.Second} {
		_, err := s.SetRule(ctx, Rule{Scope: "account:x", Trigger: "older_than", ChatType: "all", Duration: d})
		require.ErrorIs(t, err, ErrBadValue, "older_than %v", d)
	}
}

func TestRuleShapes(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, time.UnixMilli(10_000_000_000))
	bad := map[string]Rule{
		"unknown scope":          {Scope: "space:x", Trigger: "older_than", Duration: 7 * day},
		"empty account":          {Scope: "account:", Trigger: "older_than", Duration: 7 * day},
		"unknown trigger":        {Scope: "all", Trigger: "after_lunch", Duration: 10 * time.Minute},
		"unknown chat type":      {Scope: "all", Trigger: "older_than", ChatType: "dms", Duration: 7 * day},
		"after_reply on a space": {Scope: "account:whatsapp", Trigger: "after_reply", Duration: 10 * time.Minute},
		"after_read on a label":  {Scope: "label:1", Trigger: "after_read", Duration: 10 * time.Minute},
	}
	for name, r := range bad {
		_, err := s.SetRule(ctx, r)
		require.ErrorIs(t, err, ErrBadValue, name)
	}
	_, err := s.SetRule(ctx, Rule{Scope: "label:99", Trigger: "older_than", Duration: 7 * day})
	require.ErrorIs(t, err, ErrNotFound, "a label that doesn't exist")
	_, err = s.SetRule(ctx, Rule{ID: 42, Scope: "all", Trigger: "older_than", Duration: 7 * day})
	require.ErrorIs(t, err, ErrNotFound, "a rule that doesn't exist")
	require.ErrorIs(t, s.DeleteRule(ctx, 42), ErrNotFound)

	// The General setting: one enabled after_reply or after_read rule at most.
	general := mkRule(t, s, "all", "after_reply", "", 10*time.Minute)
	require.Equal(t, "all", general.ChatType, `"" is all`)
	_, err = s.SetRule(ctx, Rule{Scope: "all", Trigger: "after_read", Duration: time.Hour, Enabled: true})
	require.ErrorIs(t, err, ErrBadValue, "a second enabled General rule")
	general.Trigger, general.Duration = "after_read", time.Hour
	general, err = s.SetRule(ctx, general)
	require.NoError(t, err, "changing the one there is is fine")

	// One older_than rule per space.
	inbox := mkRule(t, s, "all", "older_than", "all", 7*day)
	_, err = s.SetRule(ctx, Rule{Scope: "all", Trigger: "older_than", Duration: 14 * day})
	require.ErrorIs(t, err, ErrBadValue, "a second rule for the same space")
	tg := mkRule(t, s, "account:telegram", "older_than", "read", 14*day)

	rules, err := s.Rules(ctx)
	require.NoError(t, err)
	require.Equal(t, []Rule{general, inbox, tg}, rules)
	require.NoError(t, s.DeleteRule(ctx, inbox.ID))
	rules, err = s.Rules(ctx)
	require.NoError(t, err)
	require.Equal(t, []Rule{general, tg}, rules)
}

func TestChangingARuleMovesItsPendingArchives(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	r := mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!r", "whatsapp", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$me", me, "m.room.message", text("ok"), t0)
	require.Equal(t, t0.Add(10*time.Minute), dueAt(t, s, "!r"))

	r.Duration = 30 * time.Minute
	r, err := s.SetRule(ctx, r)
	require.NoError(t, err)
	require.Equal(t, t0.Add(30*time.Minute), dueAt(t, s, "!r"), "a new delay counts from the same reply")

	r.Enabled = false
	r, err = s.SetRule(ctx, r)
	require.NoError(t, err)
	require.True(t, dueAt(t, s, "!r").IsZero(), "turning the rule off drops what it scheduled")

	r.Enabled = true
	_, err = s.SetRule(ctx, r)
	require.NoError(t, err)
	mkMsg(t, s, "!r", "$me2", me, "m.room.message", text("ok"), t0.Add(time.Minute))
	require.False(t, dueAt(t, s, "!r").IsZero())
	require.NoError(t, s.DeleteRule(ctx, r.ID))
	require.True(t, dueAt(t, s, "!r").IsZero(), "deleting the rule drops what it scheduled")
}

func TestReminderFiringDropsAPendingAutoArchive(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clock := clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", time.Hour)
	chatAt(t, s, "!r", "whatsapp", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$me", me, "m.room.message", text("ok"), t0)
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Minute), "always"))
	clock.set(t0.Add(time.Minute))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, fired)
	require.True(t, dueAt(t, s, "!r").IsZero(), "the chat the reminder brought back isn't archived again behind my back")
}
