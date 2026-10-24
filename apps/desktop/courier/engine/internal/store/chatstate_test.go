// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

// fakeClock is a settable clock for SetClock.
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *fakeClock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) set(t time.Time) {
	c.mu.Lock()
	c.t = t
	c.mu.Unlock()
}

func clockAt(s *Store, t time.Time) *fakeClock {
	c := &fakeClock{t: t}
	s.SetClock(c.now)
	return c
}

// requireNoChange fails if anything is waiting on ch. Every setter publishes before it returns, so there is no
// need to wait.
func requireNoChange(t *testing.T, ch <-chan Change) {
	t.Helper()
	select {
	case c := <-ch:
		t.Fatalf("unexpected change %+v", c)
	default:
	}
}

func TestMigrationFromMilestone3(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile("testdata/m3.sql")
	require.NoError(t, err)
	raw, err := sqlite.Open(path)
	require.NoError(t, err)
	_, err = raw.Exec(ctx, string(fixture))
	require.NoError(t, err)
	var before int
	require.NoError(t, raw.QueryRow(ctx, "PRAGMA user_version").Scan(&before))
	require.Equal(t, 2, before, "the fixture is a genuine milestone-3 database")
	require.NoError(t, raw.Close())

	s, err := Open(path)
	require.NoError(t, err)
	defer s.Close()
	require.GreaterOrEqual(t, userVersion(t, s), 3)
	require.Equal(t, len(migrations), userVersion(t, s))

	rows := inboxByID(t, s)
	require.Len(t, rows, 3)
	quiet := rows["!quiet:courier.local"]
	require.True(t, quiet.Muted, "a milestone-3 mute survives the upgrade")
	require.Equal(t, "second", quiet.Preview)
	require.Equal(t, 1, quiet.Unread)
	require.False(t, quiet.Archived)
	require.True(t, quiet.PinnedAt.IsZero())
	require.Empty(t, quiet.Draft)
	require.Empty(t, quiet.Labels)
	require.Nil(t, quiet.Reminder)
	loud := rows["!loud:courier.local"]
	require.False(t, loud.Muted)
	require.True(t, loud.PreviewMine)
	require.False(t, rows["!new:courier.local"].Request)

	// The new state can be written straight away.
	_, err = s.SetArchived(ctx, []string{"!loud:courier.local"}, true)
	require.NoError(t, err)
	require.True(t, inboxByID(t, s)["!loud:courier.local"].Archived)
	require.True(t, inboxByID(t, s)["!quiet:courier.local"].Muted, "archiving another chat leaves the mute alone")
}

func TestOnlyANewMessageFromOthersUnarchives(t *testing.T) {
	s, ctx := open(t), context.Background()
	archivedAt := time.Unix(1000, 0)
	clockAt(s, archivedAt)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	changed, err := s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, changed)
	// A pending auto-archive, which only a message from someone else cancels.
	_, err = s.db.Exec(ctx, `INSERT INTO auto_archive_rules (rule_id, scope, trigger, duration_ms) VALUES (1, 'all', 'after_reply', 600000)`)
	require.NoError(t, err)
	_, err = s.db.Exec(ctx, `INSERT INTO archive_due (room_id, due_at, rule_id) VALUES ('!r', 5000000, 1)`)
	require.NoError(t, err)
	archiveDue := func() int {
		var n int
		require.NoError(t, s.db.QueryRow(ctx, "SELECT COUNT(*) FROM archive_due WHERE room_id='!r'").Scan(&n))
		return n
	}

	ch, cancel := s.Subscribe()
	defer cancel()
	after := archivedAt.Add(time.Second)
	expectStaysArchived := func(why, eventID, sender, typ, content string, ts time.Time) {
		t.Helper()
		mkMsg(t, s, "!r", eventID, sender, typ, content, ts)
		require.Equal(t, "event", nextChange(t, ch).Kind, why)
		requireNoChange(t, ch)
		require.True(t, inboxByID(t, s)["!r"].Archived, why)
		require.Equal(t, 1, archiveDue(), why)
	}
	expectStaysArchived("my own message, sent from my phone", "$mine", me, "m.room.message", text("mine"), after)
	expectStaysArchived("a backfilled older message", "$old", ghost, "m.room.message", text("old"), archivedAt.Add(-time.Second))
	expectStaysArchived("a reaction", "$re", ghost, "m.reaction", `{"m.relates_to":{"event_id":"$mine","key":"x"}}`, after)
	expectStaysArchived("an edit", "$ed", ghost, "m.room.message",
		`{"msgtype":"m.text","body":"* old","m.relates_to":{"rel_type":"m.replace","event_id":"$old"}}`, after)

	// A new message from someone else brings it back, and cancels the pending auto-archive. (It is a millisecond
	// after my message: one in the same millisecond as the newest isn't newer, so it wouldn't cancel; see
	// TestBackfillDoesNotCancelAutoArchive.)
	mkMsg(t, s, "!r", "$new", ghost, "m.room.message", text("are you there?"), after.Add(time.Millisecond))
	require.Equal(t, Change{Kind: "event", RoomID: "!r", EventID: "$new", Seq: inboxSeq(t, s, "$new")}, nextChange(t, ch))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.False(t, inboxByID(t, s)["!r"].Archived)
	require.Equal(t, 0, archiveDue())

	// It only happens for an event that is actually inserted: the same event arriving again changes nothing.
	_, err = s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	require.Equal(t, "room", nextChange(t, ch).Kind)
	inserted, err := s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$new", Sender: ghost, Type: "m.room.message",
		Content: []byte(text("are you there?")), TS: after.Add(time.Hour),
	})
	require.NoError(t, err)
	require.False(t, inserted)
	require.True(t, inboxByID(t, s)["!r"].Archived)
	requireNoChange(t, ch)
}

func inboxSeq(t *testing.T, s *Store, eventID string) int64 {
	t.Helper()
	e, ok, err := s.GetEvent(context.Background(), eventID)
	require.NoError(t, err)
	require.True(t, ok)
	return e.Seq
}

func TestLowPriorityAndHiddenIgnoreNewMessages(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!low", time.Unix(1, 0))
	mkRoom(t, s, "!hid", time.Unix(2, 0))
	changed, err := s.SetLowPriority(ctx, []string{"!low"}, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!low"}, changed)
	changed, err = s.SetHidden(ctx, []string{"!hid"}, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!hid"}, changed)

	// Also archived: the message brings it out of the archive, but not out of low priority or hidden.
	mkRoom(t, s, "!both", time.Unix(3, 0))
	_, err = s.SetArchived(ctx, []string{"!both"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!both"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!both"}, true)
	require.NoError(t, err)

	later := time.Now().Add(time.Minute)
	mkMsg(t, s, "!low", "$1", ghost, "m.room.message", text("hello"), later)
	mkMsg(t, s, "!hid", "$2", ghost, "m.room.message", text("hello"), later)
	mkMsg(t, s, "!both", "$3", ghost, "m.room.message", text("hello"), later)
	rows := inboxByID(t, s)
	require.True(t, rows["!low"].LowPriority, "a new message leaves a low-priority chat where it is")
	require.True(t, rows["!hid"].Hidden, "a new message leaves a hidden chat where it is")
	require.False(t, rows["!both"].Archived)
	require.True(t, rows["!both"].LowPriority && rows["!both"].Hidden)

	// Off again.
	changed, err = s.SetLowPriority(ctx, []string{"!low"}, false)
	require.NoError(t, err)
	require.Equal(t, []string{"!low"}, changed)
	require.False(t, inboxByID(t, s)["!low"].LowPriority)
}

func TestPinnedChatsCannotBeArchived(t *testing.T) {
	s, ctx := open(t), context.Background()
	clk := clockAt(s, time.Unix(1000, 0))
	mkRoom(t, s, "!pinned", time.Unix(1, 0))
	mkRoom(t, s, "!plain", time.Unix(2, 0))
	require.NoError(t, s.SetPinned(ctx, "!pinned", true))
	require.Equal(t, time.Unix(1000, 0).UnixMilli(), inboxByID(t, s)["!pinned"].PinnedAt.UnixMilli())

	changed, err := s.SetArchived(ctx, []string{"!pinned"}, true)
	require.ErrorIs(t, err, ErrPinned)
	require.Empty(t, changed)
	require.False(t, inboxByID(t, s)["!pinned"].Archived)

	changed, err = s.SetArchived(ctx, []string{"!pinned", "!plain"}, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!plain"}, changed)
	rows := inboxByID(t, s)
	require.False(t, rows["!pinned"].Archived)
	require.True(t, rows["!plain"].Archived)

	// Pinning an archived chat brings it back.
	clk.set(time.Unix(2000, 0))
	require.NoError(t, s.SetPinned(ctx, "!plain", true))
	rows = inboxByID(t, s)
	require.False(t, rows["!plain"].Archived)
	require.True(t, rows["!plain"].PinnedAt.After(rows["!pinned"].PinnedAt), "pin order is the order of pinning")

	// Unpinning.
	require.NoError(t, s.SetPinned(ctx, "!pinned", false))
	require.True(t, inboxByID(t, s)["!pinned"].PinnedAt.IsZero())
}

func TestPinOrderHoldsWithinOneMillisecond(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, time.Unix(1000, 0)) // the clock never moves: three pins in the same instant
	for _, id := range []string{"!c", "!a", "!b"} {
		mkRoom(t, s, id, time.Unix(1, 0))
		require.NoError(t, s.SetPinned(ctx, id, true))
	}
	rows := inboxByID(t, s)
	require.True(t, rows["!c"].PinnedAt.Before(rows["!a"].PinnedAt))
	require.True(t, rows["!a"].PinnedAt.Before(rows["!b"].PinnedAt))
}

func TestSettersReportOnlyRealChanges(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	_, err := s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	_, err = s.SetMarkedUnread(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetDraft(ctx, "!r", "draft"))
	require.NoError(t, s.SetRequest(ctx, "!r", true))

	ch, cancel := s.Subscribe()
	defer cancel()
	for name, set := range map[string]func([]string, bool) ([]string, error){
		"archived":      func(ids []string, on bool) ([]string, error) { return s.SetArchived(ctx, ids, on) },
		"low priority":  func(ids []string, on bool) ([]string, error) { return s.SetLowPriority(ctx, ids, on) },
		"hidden":        func(ids []string, on bool) ([]string, error) { return s.SetHidden(ctx, ids, on) },
		"marked unread": func(ids []string, on bool) ([]string, error) { return s.SetMarkedUnread(ctx, ids, on) },
	} {
		changed, err := set([]string{"!r", "!r"}, true)
		require.NoError(t, err, name)
		require.Empty(t, changed, "%s again changes nothing", name)
		requireNoChange(t, ch)

		changed, err = set([]string{"!nope"}, true)
		require.ErrorIs(t, err, ErrNotFound, name)
		require.Empty(t, changed, name)
		// A batch with one unknown chat changes none of them.
		changed, err = set([]string{"!r", "!nope"}, false)
		require.ErrorIs(t, err, ErrNotFound, name)
		require.Empty(t, changed, name)
		requireNoChange(t, ch)
	}
	require.NoError(t, s.SetDraft(ctx, "!r", "draft"))
	require.NoError(t, s.SetRequest(ctx, "!r", true))
	require.NoError(t, s.SetPinned(ctx, "!r", false))
	requireNoChange(t, ch)

	row := inboxByID(t, s)["!r"]
	require.True(t, row.Archived && row.LowPriority && row.Hidden && row.MarkedUnread && row.Request)

	require.ErrorIs(t, s.SetPinned(ctx, "!nope", true), ErrNotFound)
	require.ErrorIs(t, s.SetDraft(ctx, "!nope", "x"), ErrNotFound)
	require.ErrorIs(t, s.SetRequest(ctx, "!nope", true), ErrNotFound)
	require.ErrorIs(t, s.ApplyNetworkMute(ctx, "!nope", event.MutedForever), ErrNotFound)
	requireNoChange(t, ch)

	// A real change publishes one room change.
	changed, err := s.SetMarkedUnread(ctx, []string{"!r"}, false)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, changed)
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.NoError(t, s.SetRequest(ctx, "!r", false))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.False(t, inboxByID(t, s)["!r"].Request)
	requireNoChange(t, ch)
}

func TestNetworkTagsMapToPinAndArchive(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))

	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.favourite", true))
	require.False(t, inboxByID(t, s)["!r"].PinnedAt.IsZero())
	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.favourite", false))
	require.True(t, inboxByID(t, s)["!r"].PinnedAt.IsZero())

	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.lowpriority", true))
	row := inboxByID(t, s)["!r"]
	require.True(t, row.Archived, "a network's low priority is Courier's archive")
	require.False(t, row.LowPriority)
	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.lowpriority", false))
	require.False(t, inboxByID(t, s)["!r"].Archived)

	ch, cancel := s.Subscribe()
	defer cancel()
	before := inboxByID(t, s)["!r"]
	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "u.work", true))
	require.Equal(t, before, inboxByID(t, s)["!r"])
	requireNoChange(t, ch)

	// A pinned chat the network calls low priority stays pinned and is not archived.
	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.favourite", true))
	require.NoError(t, s.ApplyNetworkTag(ctx, "!r", "m.lowpriority", true))
	row = inboxByID(t, s)["!r"]
	require.False(t, row.PinnedAt.IsZero())
	require.False(t, row.Archived)
}

func TestNetworkMuteUntil(t *testing.T) {
	s, ctx := open(t), context.Background()
	now := time.Date(2026, 10, 17, 12, 0, 0, 0, time.UTC)
	clockAt(s, now)
	mkRoom(t, s, "!r", time.Unix(1, 0))

	require.NoError(t, s.ApplyNetworkMute(ctx, "!r", event.MutedForever))
	require.True(t, inboxByID(t, s)["!r"].Muted)
	require.NoError(t, s.ApplyNetworkMute(ctx, "!r", bridgev2.Unmuted))
	require.False(t, inboxByID(t, s)["!r"].Muted)
	require.NoError(t, s.ApplyNetworkMute(ctx, "!r", now.Add(time.Hour)))
	require.True(t, inboxByID(t, s)["!r"].Muted)
	require.NoError(t, s.ApplyNetworkMute(ctx, "!r", now.Add(-time.Minute)))
	require.False(t, inboxByID(t, s)["!r"].Muted, "a mute that already ran out is no mute")
	require.NoError(t, s.ApplyNetworkMute(ctx, "!r", time.Time{}))
	require.False(t, inboxByID(t, s)["!r"].Muted)
}

func TestDraftIsKeptAndCleared(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.SetDraft(ctx, "!r", "half a thought"))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, "half a thought", inboxByID(t, s)["!r"].Draft)

	// A bridge refreshing the room keeps the draft.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r", Network: "whatsapp", Name: "renamed"}))
	require.Equal(t, "room", nextChange(t, ch).Kind)
	require.Equal(t, "half a thought", inboxByID(t, s)["!r"].Draft)

	// The limit is in characters, not bytes.
	longest := strings.Repeat("é", maxDraftChars)
	require.NoError(t, s.SetDraft(ctx, "!r", longest))
	require.Equal(t, "room", nextChange(t, ch).Kind)
	require.ErrorIs(t, s.SetDraft(ctx, "!r", longest+"x"), ErrBadValue)
	require.Equal(t, longest, inboxByID(t, s)["!r"].Draft, "a refused draft leaves the old one")
	requireNoChange(t, ch)

	require.NoError(t, s.SetDraft(ctx, "!r", ""))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Empty(t, inboxByID(t, s)["!r"].Draft)
}

func TestUnreadMentionsCountOnlyUnreadMentionsOfMe(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mention := func(users ...string) string {
		q := make([]string, len(users))
		for i, u := range users {
			q[i] = `"` + u + `"`
		}
		return `{"msgtype":"m.text","body":"hey","m.mentions":{"user_ids":[` + strings.Join(q, ",") + `]}}`
	}
	// Before the read marker (and the marker itself): not counted.
	mkMsg(t, s, "!r", "$old", ghost, "m.room.message", mention(me), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$mark", ghost, "m.room.message", mention(me), time.Unix(20, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$mark", time.Unix(20, 0)))
	// After it.
	mkMsg(t, s, "!r", "$me", ghost, "m.room.message", mention("@someone:courier.local", me), time.Unix(30, 0))
	mkMsg(t, s, "!r", "$room", ghost, "m.room.message", `{"msgtype":"m.text","body":"all","m.mentions":{"room":true}}`, time.Unix(40, 0))
	mkMsg(t, s, "!r", "$other", ghost, "m.room.message", mention("@someone:courier.local"), time.Unix(50, 0))
	mkMsg(t, s, "!r", "$plain", ghost, "m.room.message", text("no mention"), time.Unix(60, 0))
	mkMsg(t, s, "!r", "$bad", ghost, "m.room.message", `not json`, time.Unix(70, 0))
	mkMsg(t, s, "!r", "$self", me, "m.room.message", mention(me), time.Unix(80, 0))

	row := inboxByID(t, s)["!r"]
	require.Equal(t, 2, row.UnreadMentions, "a mention of me and a room mention, both after the marker")
	require.Equal(t, 5, row.Unread)

	// Reading up to $me leaves only the room mention.
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$me", time.Unix(30, 0)))
	require.Equal(t, 1, inboxByID(t, s)["!r"].UnreadMentions)
}

func TestInboxRowCarriesReminderAndPreviewMedia(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!s", time.Unix(2, 0))
	mkMsg(t, s, "!r", "$img", ghost, "m.room.message",
		`{"msgtype":"m.image","body":"pic.jpg","url":"mxc://courier.local/full","info":{"thumbnail_url":"mxc://courier.local/thumb"}}`, time.Unix(10, 0))
	mkMsg(t, s, "!s", "$st", ghost, "m.sticker", `{"body":"wave","url":"mxc://courier.local/sticker"}`, time.Unix(10, 0))
	_, err := s.db.Exec(ctx, `INSERT INTO reminders (room_id, due_at, condition, set_at, fired_at) VALUES ('!r', 9000, 'if_no_reply', 5000, 0)`)
	require.NoError(t, err)

	rows := inboxByID(t, s)
	require.Equal(t, "mxc://courier.local/thumb", rows["!r"].PreviewMediaURI, "an image previews its thumbnail")
	require.Equal(t, "mxc://courier.local/sticker", rows["!s"].PreviewMediaURI, "a sticker without a thumbnail previews itself")
	require.Equal(t, &Reminder{RoomID: "!r", Condition: "if_no_reply", DueAt: time.UnixMilli(9000), SetAt: time.UnixMilli(5000)}, rows["!r"].Reminder)
	require.Nil(t, rows["!s"].Reminder)

	mkMsg(t, s, "!s", "$txt", ghost, "m.room.message", text("words"), time.Unix(20, 0))
	require.Empty(t, inboxByID(t, s)["!s"].PreviewMediaURI)
}

// fakeTimers stands in for time.AfterFunc, so a test can fire a typing expiry when its clock says so.
type fakeTimers struct {
	mu      sync.Mutex
	pending []*fakeTimer
}

type fakeTimer struct {
	d       time.Duration
	f       func()
	stopped bool
}

func (ft *fakeTimers) afterFunc(d time.Duration, f func()) func() bool {
	ft.mu.Lock()
	defer ft.mu.Unlock()
	tm := &fakeTimer{d: d, f: f}
	ft.pending = append(ft.pending, tm)
	return func() bool {
		ft.mu.Lock()
		defer ft.mu.Unlock()
		was := !tm.stopped
		tm.stopped = true
		return was
	}
}

// fireAll runs every timer that has not been stopped, as time.AfterFunc would once its time came.
func (ft *fakeTimers) fireAll() {
	ft.mu.Lock()
	var due []*fakeTimer
	for _, tm := range ft.pending {
		if !tm.stopped {
			tm.stopped = true
			due = append(due, tm)
		}
	}
	ft.pending = nil
	ft.mu.Unlock()
	for _, tm := range due {
		tm.f()
	}
}

func TestTypingExpires(t *testing.T) {
	s := open(t)
	now := time.Unix(1000, 0)
	clk := clockAt(s, now)
	timers := &fakeTimers{}
	s.afterFunc = timers.afterFunc

	ch, cancel := s.Subscribe()
	defer cancel()
	s.SetTyping("!r", "@b:courier.local", now.Add(5*time.Second))
	s.SetTyping("!r", "@a:courier.local", now.Add(5*time.Second))
	require.Equal(t, Change{Kind: "typing", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, Change{Kind: "typing", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, []string{"@a:courier.local", "@b:courier.local"}, s.TypingIn("!r"))
	require.Empty(t, s.TypingIn("!other"))
	timers.mu.Lock()
	require.Len(t, timers.pending, 2)
	require.Equal(t, 5*time.Second, timers.pending[0].d)
	timers.mu.Unlock()

	// Renewing replaces the timer and says nothing new.
	s.SetTyping("!r", "@a:courier.local", now.Add(10*time.Second))
	requireNoChange(t, ch)

	// @b stops by hand.
	s.SetTyping("!r", "@b:courier.local", time.Time{})
	require.Equal(t, Change{Kind: "typing", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, []string{"@a:courier.local"}, s.TypingIn("!r"))

	// Once the clock passes @a's time it is gone, even before its timer runs.
	clk.set(now.Add(11 * time.Second))
	require.Empty(t, s.TypingIn("!r"))
	timers.fireAll()
	require.Equal(t, Change{Kind: "typing", RoomID: "!r"}, nextChange(t, ch), "one change at expiry")
	requireNoChange(t, ch)
	require.Empty(t, s.TypingIn("!r"))

	// Typing that has already ended is a stop, and stopping someone who isn't typing says nothing.
	s.SetTyping("!r", "@a:courier.local", now)
	requireNoChange(t, ch)
}

func TestTypingWithRealTimers(t *testing.T) {
	s := open(t)
	ch, cancel := s.Subscribe()
	defer cancel()
	s.SetTyping("!r", "@a:courier.local", time.Now().Add(30*time.Millisecond))
	require.Equal(t, "typing", nextChange(t, ch).Kind)
	require.Equal(t, Change{Kind: "typing", RoomID: "!r"}, nextChange(t, ch), "the expiry is published")
	require.Empty(t, s.TypingIn("!r"))
}

// Mark as Unread from a message: the chat's unread count runs from that message on (my own messages never count),
// whatever the read markers say, until the chat is read (SetMarkedUnread false). The unread filter and the space
// counts follow it.
func TestUnreadFromCountsFromThatMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for i := 1; i <= 6; i++ {
		sender := ghost
		if i == 4 {
			sender = me
		}
		mkMsg(t, s, "!r", fmt.Sprintf("$%d", i), sender, "m.room.message", text("m"), t0.Add(time.Duration(i)*time.Second))
	}
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$6", t0.Add(6*time.Second)))
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.SetUnreadFrom(ctx, "!r", "$3"))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread, "$3, $5 and $6; my $4 doesn't count")
	require.Equal(t, []string{"!r"}, allPages(t, s, InboxQuery{Filters: []string{"unread"}}))
	require.Equal(t, 1, spacesByID(t, s)["inbox"].UnreadChats)

	// This Mac's read marker moving past it doesn't clear it. (My read on another device does: Ruling 6,
	// TestMyReadElsewhereClearsTheUnreadFromMarkOnly.)
	mkMsg(t, s, "!r", "$7", ghost, "m.room.message", text("m"), t0.Add(7*time.Second))
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$7", t0.Add(7*time.Second)))
	require.Equal(t, 4, inboxByID(t, s)["!r"].Unread)

	// Reading the chat clears it (and the chat mark with it, in one write).
	drain(ch)
	changed, err := s.SetMarkedUnread(ctx, []string{"!r"}, false)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, changed)
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
	require.Empty(t, allPages(t, s, InboxQuery{Filters: []string{"unread"}}))
	changed, err = s.SetMarkedUnread(ctx, []string{"!r"}, false)
	require.NoError(t, err)
	require.Empty(t, changed, "nothing left to clear")

	// Marking the chat unread leaves the mark from a message alone; reading clears both.
	require.NoError(t, s.SetUnreadFrom(ctx, "!r", "$5"))
	_, err = s.SetMarkedUnread(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread)
	_, err = s.SetMarkedUnread(ctx, []string{"!r"}, false)
	require.NoError(t, err)
	row := inboxByID(t, s)["!r"]
	require.Zero(t, row.Unread)
	require.False(t, row.MarkedUnread)
}

// Ruling 6: my read on another device (SetRead) that reaches the message the chat is marked unread from clears that
// mark, and says so with a "room" change; one short of it doesn't. The chat's marked-unread flag is the phone's to
// clear (ApplyNetworkUnread), which leaves the mark from a message alone.
func TestMyReadElsewhereClearsTheUnreadFromMarkOnly(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for i := 1; i <= 4; i++ {
		mkMsg(t, s, "!r", fmt.Sprintf("$%d", i), ghost, "m.room.message", text("m"), t0.Add(time.Duration(i)*time.Second))
	}
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$4", t0.Add(4*time.Second)))
	require.NoError(t, s.SetUnreadFrom(ctx, "!r", "$2"))
	_, err := s.SetMarkedUnread(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread)
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.ApplyNetworkUnread(ctx, "!r", false))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	row := inboxByID(t, s)["!r"]
	require.False(t, row.MarkedUnread, "the phone clears its flag")
	require.Equal(t, 3, row.Unread, "and leaves the mark made here")

	require.NoError(t, s.SetRead(ctx, "!r", "$1", t0.Add(10*time.Second)))
	require.Equal(t, Change{Kind: "read", RoomID: "!r", EventID: "$1"}, nextChange(t, ch))
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread, "a read short of the mark leaves it")

	require.NoError(t, s.SetRead(ctx, "!r", "$2", t0.Add(11*time.Second)))
	require.Equal(t, Change{Kind: "read", RoomID: "!r", EventID: "$2"}, nextChange(t, ch))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch), "the mark's clearing is a room change")
	require.Zero(t, inboxByID(t, s)["!r"].Unread, "a read that reaches it clears it")
	require.Error(t, s.ApplyNetworkUnread(ctx, "!unknown", true), "an unknown chat")
}

// SetUnreadFrom takes a message of this chat: an unknown one, or one of another chat, is ErrNotFound, and a note (a
// timer change, a call) is ErrNote (Ruling P2: Mark as Unread is refused on notes).
func TestUnreadFromNeedsAMessageOfTheChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	mkMsg(t, s, "!other", "$elsewhere", ghost, "m.room.message", text("m"), t0)
	require.ErrorIs(t, s.SetUnreadFrom(ctx, "!r", "$nope"), ErrNotFound)
	require.ErrorIs(t, s.SetUnreadFrom(ctx, "!r", "$elsewhere"), ErrNotFound)
	require.ErrorIs(t, s.SetUnreadFrom(ctx, "!unknown", "$elsewhere"), ErrNotFound)
	require.True(t, insertTimerNote(t, s, "!r", "$timer", "after_send", time.Hour, t0, s.LastSeq()))
	require.ErrorIs(t, s.SetUnreadFrom(ctx, "!r", "$timer"), ErrNote)
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
}

// drain empties ch of what is already waiting.
func drain(ch <-chan Change) {
	for {
		select {
		case <-ch:
		default:
			return
		}
	}
}

// mkChat is a chat of network with login loginID ("" is shared), direct or not, whose newest message (from user, who
// is a member) is at last.
func mkChat(t *testing.T, s *Store, id, network, loginID string, direct bool, user string, last time.Time) {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: id, Network: network, Name: id, IsDirect: direct, CreatedAt: time.Unix(1, 0)}))
	require.NoError(t, s.SetRoomLogin(ctx, id, loginID))
	require.NoError(t, s.SetMember(ctx, id, user, []byte(`{"membership":"join"}`)))
	mkMsg(t, s, id, "$last"+id, user, "m.room.message", text("m"), last)
}

// Reply Privately finds the one-to-one chat with a person on the same network: the login's own chat first, then one
// shared by every login, newest first; never another login's chat, a group or another network's.
func TestDirectRoomWithPrefersTheLoginsOwnChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkChat(t, s, "!dmA", "whatsapp", "A", true, ghost, t0)
	mkChat(t, s, "!dmAnewer", "whatsapp", "A", true, ghost, t0.Add(time.Minute))
	mkChat(t, s, "!dmShared", "whatsapp", "", true, ghost, t0.Add(2*time.Minute))
	mkChat(t, s, "!dmB", "whatsapp", "B", true, ghost, t0.Add(3*time.Minute))
	mkChat(t, s, "!groupA", "whatsapp", "A", false, ghost, t0.Add(4*time.Minute))
	mkChat(t, s, "!dmSignal", "signal", "A", true, ghost, t0.Add(5*time.Minute))
	find := func(network, loginID, user string) (string, bool) {
		t.Helper()
		id, ok, err := s.DirectRoomWith(ctx, network, loginID, user)
		require.NoError(t, err)
		return id, ok
	}
	id, ok := find("whatsapp", "A", ghost)
	require.True(t, ok)
	require.Equal(t, "!dmAnewer", id, "the login's own chat, the newest of them")
	id, _ = find("whatsapp", "B", ghost)
	require.Equal(t, "!dmB", id)
	id, _ = find("whatsapp", "C", ghost)
	require.Equal(t, "!dmShared", id, "no chat of its own: the shared one")
	id, _ = find("signal", "A", ghost)
	require.Equal(t, "!dmSignal", id)
	_, ok = find("whatsapp", "A", "@nobody:courier.local")
	require.False(t, ok)
	_, ok = find("telegram", "A", ghost)
	require.False(t, ok)
}
