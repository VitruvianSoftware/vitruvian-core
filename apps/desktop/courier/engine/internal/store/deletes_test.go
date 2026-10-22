// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// listedBookmarks is every bookmark a list shows, newest first (listedBookmarksSQL).
func listedBookmarks(t *testing.T, s *Store) []string {
	t.Helper()
	return queryIDs(t, s, listedBookmarksSQL)
}

func bookmark(t *testing.T, s *Store, roomID, eventID string, at time.Time) {
	t.Helper()
	_, err := s.db.Exec(context.Background(), "INSERT INTO bookmarks (event_id, room_id, created_at) VALUES ($1, $2, $3)",
		eventID, roomID, at.UnixMilli())
	require.NoError(t, err)
}

func redacted(t *testing.T, s *Store, eventID string) bool {
	t.Helper()
	return count(t, s, "SELECT redacted FROM events WHERE event_id=$1", eventID) == 1
}

// changesUntil reads ch until it has seen want, failing if it doesn't come.
func changesUntil(t *testing.T, ch <-chan Change, want Change) {
	t.Helper()
	for {
		if c := nextChange(t, ch); c == want {
			return
		}
	}
}

// myUnsend is my redaction of target, pending: what Unsend stores before the network answers.
func myUnsend(t *testing.T, s *Store, roomID, id, target string, ts time.Time) {
	t.Helper()
	insert(t, s, Event{
		RoomID: roomID, EventID: id, Sender: me, Type: "m.room.redaction",
		Content: json.RawMessage(redactionOf(target)), TS: ts, Status: "pending",
	})
}

func TestMigrationFromMilestone4_2(t *testing.T) {
	s, _ := openFixture(t, "m5.sql")
	ctx := context.Background()
	require.GreaterOrEqual(t, userVersion(t, s), 5)
	require.Equal(t, len(migrations), userVersion(t, s))

	// The after_send messages on disk get their time: ts + timer. after_read, a plain message and a deleted one don't.
	past, ok, err := s.GetEvent(ctx, "$a8")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, past.TS.Add(24*time.Hour).UnixMilli(), past.ExpiresAt.UnixMilli())
	future, _, err := s.GetEvent(ctx, "$a9")
	require.NoError(t, err)
	require.Equal(t, future.TS.Add(90*24*time.Hour).UnixMilli(), future.ExpiresAt.UnixMilli())
	for _, id := range []string{"$a10", "$a2", "$a6", "$s1"} {
		e, _, err := s.GetEvent(ctx, id)
		require.NoError(t, err)
		require.True(t, e.ExpiresAt.IsZero(), id)
		require.False(t, e.DeletedForMe, id)
	}
	require.Equal(t, 2, count(t, s, "SELECT count(*) FROM events WHERE expires_at IS NOT NULL"))

	// The new tables are there and empty.
	for _, table := range []string{"outbox", "bookmarks"} {
		require.Equal(t, 0, count(t, s, "SELECT count(*) FROM "+table), table)
	}
	// The thread index holds the two replies that stay in the thread, not the one broadcast to the channel.
	require.Equal(t, 2, count(t, s, `SELECT count(*) FROM events INDEXED BY events_threads WHERE room_id = '!team:courier.local'
		AND type IN ('m.room.message', 'm.sticker') AND `+isThreadReplySQL("content")+` AND `+threadRootSQL("content")+` = '$s1'`))
	// The reference index holds the poll's two votes.
	require.Equal(t, 2, count(t, s, `SELECT count(*) FROM events INDEXED BY events_refs
		WHERE type IN ('org.matrix.msc3381.poll.response', 'org.matrix.msc3381.poll.end') AND `+editTargetSQL("content")+` = '$a11'`))

	rows := inboxByID(t, s)
	require.Len(t, rows, 2)
	require.Equal(t, "$a10", lastEventID(t, s, "!pat:courier.local"))
	require.Equal(t, "standup moved", rows["!team:courier.local"].Preview)

	backfillAll(t, s, 2000)
	find := func(q string) []string {
		return hitIDs(searchAll(t, s, MessageQuery{Terms: terms(q)}))
	}
	require.Equal(t, []string{"$a2"}, find("five"), "a sent edit counts")
	require.Empty(t, find("noon"))
	require.Equal(t, []string{"$a4"}, find("soon"), "a failed edit doesn't")
	require.Empty(t, find("later"))
	require.Empty(t, find("wrong"), "a deleted message isn't found")
	require.Equal(t, []string{"$s2"}, find("looks good"))
}

func TestAfterSendMessagesGetAnExpiry(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ts := time.UnixMilli(1_790_000_000_000)
	for id, content := range map[string]string{
		"$send": `{"msgtype":"m.text","body":"a","com.beeper.disappearing_timer":{"type":"after_send","timer":86400000}}`,
		"$read": `{"msgtype":"m.text","body":"b","com.beeper.disappearing_timer":{"type":"after_read","timer":30000}}`,
		"$zero": `{"msgtype":"m.text","body":"c","com.beeper.disappearing_timer":{"type":"after_send","timer":0}}`,
		"$text": `{"msgtype":"m.text","body":"d","com.beeper.disappearing_timer":{"type":"after_send","timer":"86400000"}}`,
		"$none": text("e"),
		"$junk": `not json com.beeper.disappearing_timer`,
	} {
		mkMsg(t, s, "!r", id, ghost, "m.room.message", content, ts)
	}
	e, _, err := s.GetEvent(ctx, "$send")
	require.NoError(t, err)
	require.Equal(t, ts.Add(24*time.Hour).UnixMilli(), e.ExpiresAt.UnixMilli())
	for _, id := range []string{"$read", "$zero", "$text", "$none", "$junk"} {
		e, _, err := s.GetEvent(ctx, id)
		require.NoError(t, err)
		require.True(t, e.ExpiresAt.IsZero(), id)
	}
	// The SQL of migration 5 gives what InsertEvent gives: the two agree on every row.
	require.Equal(t, 0, count(t, s, `SELECT count(*) FROM events WHERE expires_at IS NOT
		(CASE WHEN content LIKE '%com.beeper.disappearing_timer%' AND `+afterSendTimerSQL("content")+` > 0
		 THEN ts + `+afterSendTimerSQL("content")+` END)`))
}

func TestFailedEditPutsBackTheTextAndTheIndex(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$m", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("meet at noon")), TS: time.Unix(10, 0), Status: "sent",
	})
	insert(t, s, Event{
		RoomID: "!r", EventID: "$e", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(editTo("$m", "meet at five")), TS: time.Unix(20, 0), Status: "pending",
	})
	msg, _, err := s.GetEvent(ctx, "$m")
	require.NoError(t, err)
	require.Equal(t, []string{"$m"}, matches(t, s, `"five"`))
	require.Empty(t, matches(t, s, `"noon"`))

	// The network refuses the edit: the old text is back, in the chat and in search.
	require.NoError(t, s.SetStatus(ctx, "$e", "failed", "refused"))
	require.Equal(t, []string{"$m"}, matches(t, s, `"noon"`))
	require.Empty(t, matches(t, s, `"five"`))
	got, err := s.CurrentText(ctx, msg)
	require.NoError(t, err)
	require.Equal(t, "meet at noon", got)

	// Retry: the edit counts again while it is pending.
	require.NoError(t, s.SetStatus(ctx, "$e", "pending", ""))
	require.Equal(t, []string{"$m"}, matches(t, s, `"five"`))
	require.Empty(t, matches(t, s, `"noon"`))
	got, err = s.CurrentText(ctx, msg)
	require.NoError(t, err)
	require.Equal(t, "meet at five", got)

	// A newer edit that fails leaves the older one standing.
	insert(t, s, Event{
		RoomID: "!r", EventID: "$e2", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(editTo("$m", "meet at six")), TS: time.Unix(30, 0), Status: "pending",
	})
	require.Equal(t, []string{"$m"}, matches(t, s, `"six"`))
	require.NoError(t, s.SetStatus(ctx, "$e2", "failed", ""))
	require.Equal(t, []string{"$m"}, matches(t, s, `"five"`))
	require.Empty(t, matches(t, s, `"six"`))

	require.ErrorIs(t, s.SetStatus(ctx, "$never", "failed", ""), sql.ErrNoRows)
}

func TestFailedUnsendBringsTheMessageBack(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("hello there")), TS: time.Unix(20, 0), Status: "sent",
	})
	myUnsend(t, s, "!r", "$x", "$b", time.Unix(30, 0))
	require.True(t, redacted(t, s, "$b"))
	require.Empty(t, matches(t, s, `"there"`))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.False(t, redacted(t, s, "$b"), "back in the chat")
	require.Equal(t, []string{"$b"}, matches(t, s, `"there"`), "back in search")
	require.Equal(t, "$b", lastEventID(t, s, "!r"), "back as the chat's latest")
	require.Equal(t, "hello there", inboxByID(t, s)["!r"].Preview)
	changesUntil(t, ch, Change{Kind: "room", RoomID: "!r"})

	// A refused unsend of an older message leaves the chat's latest alone.
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", text("newest"), time.Unix(40, 0))
	myUnsend(t, s, "!r", "$y", "$b", time.Unix(50, 0))
	require.NoError(t, s.SetStatus(ctx, "$y", "failed", ""))
	require.Equal(t, "$c", lastEventID(t, s, "!r"))
	require.Equal(t, []string{"$b"}, matches(t, s, `"there"`))
}

func TestRetriedUnsendDeletesAgain(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("hello there")), TS: time.Unix(20, 0), Status: "sent",
	})
	myUnsend(t, s, "!r", "$x", "$b", time.Unix(30, 0))
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.False(t, redacted(t, s, "$b"))

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetStatus(ctx, "$x", "pending", ""))
	require.True(t, redacted(t, s, "$b"))
	require.Empty(t, matches(t, s, `"there"`))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
	changesUntil(t, ch, Change{Kind: "room", RoomID: "!r"})

	// It goes through this time: still deleted.
	require.NoError(t, s.SetStatus(ctx, "$x", "sent", ""))
	require.True(t, redacted(t, s, "$b"))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
}

func TestFailedUnsendLeavesAMessageDeletedForMe(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("hello there")), TS: time.Unix(20, 0), Status: "sent",
	})
	myUnsend(t, s, "!r", "$x", "$b", time.Unix(30, 0))
	require.NoError(t, s.SetDeletedForMe(ctx, "$b"))
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.True(t, redacted(t, s, "$b"), "deleted for me stays deleted")
	require.Empty(t, matches(t, s, `"there"`))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
}

func TestFailedUnsendLeavesAnotherRedaction(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("hello there")), TS: time.Unix(20, 0), Status: "sent",
	})
	myUnsend(t, s, "!r", "$x", "$b", time.Unix(30, 0))
	// The network deleted it too (from my phone, say): that redaction stands.
	mkMsg(t, s, "!r", "$net", me, "m.room.redaction", redactionOf("$b"), time.Unix(31, 0))
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.True(t, redacted(t, s, "$b"))
	require.Empty(t, matches(t, s, `"there"`))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))

	// A failed redaction of a message nobody else deleted, from someone who isn't me, changes nothing: only my
	// unsends are mine to put back.
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", text("theirs"), time.Unix(40, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$y", Sender: ghost, Type: "m.room.redaction",
		Content: json.RawMessage(redactionOf("$c")), TS: time.Unix(50, 0),
	})
	require.NoError(t, s.SetStatus(ctx, "$y", "failed", ""))
	require.True(t, redacted(t, s, "$c"))
}

func TestRefusedUnsendKeepsTheBookmark(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("hello there")), TS: time.Unix(20, 0), Status: "sent",
	})
	bookmark(t, s, "!r", "$b", time.Unix(25, 0))
	require.Equal(t, []string{"$b"}, listedBookmarks(t, s))

	myUnsend(t, s, "!r", "$x", "$b", time.Unix(30, 0))
	require.Empty(t, listedBookmarks(t, s), "a deleted message isn't listed")
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM bookmarks"), "but its bookmark stays")

	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.Equal(t, []string{"$b"}, listedBookmarks(t, s), "a refused unsend gives the bookmark back")

	// Forgetting the message forgets its bookmark.
	require.NoError(t, s.DeleteEvent(ctx, "$b"))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM bookmarks"))
}

func TestDeletedForMeLeavesEverywhere(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("second thought"), time.Unix(20, 0))
	bookmark(t, s, "!r", "$b", time.Unix(21, 0))
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread)
	require.Equal(t, []string{"$b"}, matches(t, s, `"thought"`))

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetDeletedForMe(ctx, "$b"))
	require.Equal(t, Change{Kind: "status", RoomID: "!r", EventID: "$b", Seq: 2}, nextChange(t, ch))

	evs, err := s.Events(ctx, "!r", 10)
	require.NoError(t, err)
	require.Equal(t, []string{"$b", "$a"}, idsOf(evs))
	require.True(t, evs[0].DeletedForMe, "the rpc layer leaves it out")
	require.False(t, evs[1].DeletedForMe)
	require.False(t, docID(t, s, "$b").Valid)
	require.Empty(t, matches(t, s, `"thought"`))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, 1, row.Unread)
	require.Equal(t, "first", row.Preview)
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
	require.Empty(t, listedBookmarks(t, s))

	require.ErrorIs(t, s.SetDeletedForMe(ctx, "$never"), ErrNotFound)
}

// Review Focus 5: a refused unsend never brings back a message whose disappearing timer has run out, so it can't
// outstay its timer that way.
func TestFailedUnsendLeavesAMessagePastItsTimer(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	sent := time.UnixMilli(1_790_000_000_000)
	clock := clockAt(s, sent)
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), sent.Add(-time.Minute))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$b", Sender: me, Type: "m.room.message", TS: sent, Status: "sent",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"brief thought","com.beeper.disappearing_timer":{"type":"after_send","timer":3600000}}`),
	})
	myUnsend(t, s, "!r", "$x", "$b", sent.Add(time.Second))

	// Refused while its time is still to come: it is back.
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.False(t, redacted(t, s, "$b"))
	require.NoError(t, s.SetStatus(ctx, "$x", "pending", ""))

	// Refused once its time has passed: it stays gone, everywhere.
	clock.set(sent.Add(time.Hour))
	require.NoError(t, s.SetStatus(ctx, "$x", "failed", "refused"))
	require.True(t, redacted(t, s, "$b"))
	require.Empty(t, matches(t, s, `"thought"`))
	require.Equal(t, "$a", lastEventID(t, s, "!r"))
}

// disappearing is an after_send disappearing message's content: body, gone timer after it is sent.
func disappearing(body string, timer time.Duration) string {
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": body,
		"com.beeper.disappearing_timer": map[string]any{"type": "after_send", "timer": timer.Milliseconds()},
	})
	return string(b)
}

// Review Focus 5: once its time has passed, a disappearing message is gone from the chat, the inbox preview and
// search when ExpireDue runs, whatever the bridge's own loop is doing. One whose time is still to come stays, and an
// after_read one is never touched (the network decides when it was read).
func TestExpiredMessagesLeaveEverywhere(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), t0.Add(-3*time.Minute))
	mkMsg(t, s, "!r", "$later", ghost, "m.room.message", disappearing("tomorrow's plan", 24*time.Hour), t0.Add(-2*time.Minute))
	mkMsg(t, s, "!r", "$read", ghost, "m.room.message",
		`{"msgtype":"m.text","body":"read receipt timer","com.beeper.disappearing_timer":{"type":"after_read","timer":30000}}`, t0.Add(-time.Minute))
	mkMsg(t, s, "!r", "$gone", ghost, "m.room.message", disappearing("secret meeting", time.Hour), t0)
	mkMsg(t, s, "!other", "$o", ghost, "m.room.message", text("unrelated"), t0)
	require.Equal(t, "secret meeting", inboxByID(t, s)["!r"].Preview)
	require.Equal(t, 4, inboxByID(t, s)["!r"].Unread)
	require.Equal(t, []string{"$gone"}, matches(t, s, `"secret"`))

	rooms, err := s.ExpireDue(ctx)
	require.NoError(t, err)
	require.Empty(t, rooms, "nothing is due yet")

	ch, cancel := s.Subscribe()
	defer cancel()
	clock.set(t0.Add(time.Hour)) // the Mac slept through it
	rooms, err = s.ExpireDue(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, rooms)
	changesUntil(t, ch, Change{Kind: "room", RoomID: "!r"})

	require.True(t, redacted(t, s, "$gone"), "out of the timeline")
	require.Empty(t, matches(t, s, `"secret"`), "out of search")
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "read receipt timer", row.Preview, "out of the preview")
	require.Equal(t, 3, row.Unread)
	require.False(t, redacted(t, s, "$later"), "its time is still to come")
	require.False(t, redacted(t, s, "$read"), "after_read is never touched")
	require.Equal(t, []string{"$later"}, matches(t, s, `"plan"`))

	rooms, err = s.ExpireDue(ctx)
	require.NoError(t, err)
	require.Empty(t, rooms, "once")
	at, ok, err := s.NextDue(ctx)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, t0.Add(-2*time.Minute+24*time.Hour).UnixMilli(), at.UnixMilli())

	// An expired edit gives its message back the text before it.
	insert(t, s, Event{
		RoomID: "!r", EventID: "$m", Sender: me, Type: "m.room.message", TS: t0.Add(2 * time.Hour),
		Content: json.RawMessage(text("meet at noon")), Status: "sent",
	})
	var edit map[string]any
	require.NoError(t, json.Unmarshal([]byte(editTo("$m", "meet at five")), &edit))
	edit["com.beeper.disappearing_timer"] = map[string]any{"type": "after_send", "timer": 1000}
	b, _ := json.Marshal(edit)
	insert(t, s, Event{RoomID: "!r", EventID: "$e", Sender: me, Type: "m.room.message", TS: t0.Add(2 * time.Hour), Content: b, Status: "sent"})
	require.Equal(t, []string{"$m"}, matches(t, s, `"five"`))
	clock.set(t0.Add(2*time.Hour + time.Second))
	rooms, err = s.ExpireDue(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, rooms)
	require.Equal(t, []string{"$m"}, matches(t, s, `"noon"`))
	require.Empty(t, matches(t, s, `"five"`))
}

func TestExpireDueUsesItsIndex(t *testing.T) {
	s := open(t)
	plan := planOf(t, s, expireDueSQL, int64(1))
	require.Contains(t, strings.Join(plan, "\n"), "events_expiry")
}
