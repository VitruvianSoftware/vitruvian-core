// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

// bridgeNote is a bridge's timer-change note as bridgev2's DisappearingMessageNotice makes it (portal.go:4982–5068):
// an m.notice with the bridge's English body and com.beeper.action_message. extra is more of the action message
// (`,"backfill":true`), or "".
func bridgeNote(timer time.Duration, typ, extra string) string {
	body := "Set the disappearing message timer to " + timer.String()
	if timer == 0 {
		body = "Turned off disappearing messages"
	}
	return fmt.Sprintf(`{"msgtype":"m.notice","body":%q,"m.mentions":{},"com.beeper.action_message":{"type":"disappearing_timer","timer":%d,"timer_type":%q,"implicit":false%s}}`,
		body, timer.Milliseconds(), typ, extra)
}

// timerNotes is the IDs of roomID's timer-change notes, oldest first.
func timerNotes(t *testing.T, s *Store, roomID string) []string {
	t.Helper()
	evs, err := s.Events(context.Background(), roomID, 1000)
	require.NoError(t, err)
	var out []string
	for i := len(evs) - 1; i >= 0; i-- {
		if _, ok := parseTimerNote(evs[i].Type, evs[i].Content); ok {
			out = append(out, evs[i].EventID)
		}
	}
	return out
}

func insertTimerNote(t *testing.T, s *Store, roomID, id, typ string, timer time.Duration, ts time.Time, afterSeq int64) bool {
	t.Helper()
	inserted, err := s.InsertTimerNote(context.Background(), roomID, id, typ, timer, ts, afterSeq)
	require.NoError(t, err)
	return inserted
}

// Ruling 40: a timer changed here leaves a note in the bridge's shape, mine, with no words of the bridge's.
func TestTimerNoteHasTheBridgesShape(t *testing.T) {
	s := open(t)
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ch, cancel := s.Subscribe()
	defer cancel()
	require.True(t, insertTimerNote(t, s, "!r", "$note", "after_send", 7*day, t0, s.LastSeq()))
	require.Equal(t, Change{Kind: "event", RoomID: "!r", EventID: "$note", Seq: s.LastSeq()}, nextChange(t, ch))

	e, ok := getEvent(t, s, "$note")
	require.True(t, ok)
	require.Equal(t, me, e.Sender)
	require.Equal(t, "m.room.message", e.Type)
	require.Equal(t, "sent", e.Status, "it never waits on a network: there is none to wait on")
	require.Equal(t, t0.UnixMilli(), e.TS.UnixMilli())
	require.JSONEq(t, `{"msgtype":"m.notice","body":"","m.mentions":{},"fi.courier.local":true,
		"com.beeper.action_message":{"type":"disappearing_timer","timer":604800000,"timer_type":"after_send","implicit":false}}`,
		string(e.Content))
	require.True(t, e.ExpiresAt.IsZero(), "the note itself doesn't disappear")

	require.True(t, insertTimerNote(t, s, "!r", "$off", "", 0, t0.Add(time.Minute), s.LastSeq()))
	off, _ := getEvent(t, s, "$off")
	require.JSONEq(t, `{"msgtype":"m.notice","body":"","m.mentions":{},"fi.courier.local":true,
		"com.beeper.action_message":{"type":"disappearing_timer","timer":0,"timer_type":"","implicit":false}}`, string(off.Content))
	require.Equal(t, []string{"$note", "$off"}, timerNotes(t, s, "!r"))
}

// Ruling 40: my note is the chat's newest thing, so the inbox previews it, but as a timer change and never in the
// bridge's words; it isn't unread, isn't my reply for auto-archive, isn't "I replied" for a reminder, doesn't cancel
// a scheduled message set "if no reply", and isn't searchable.
func TestTimerNoteIsNotAMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!r", "whatsapp", t0.Add(-time.Hour))
	require.NoError(t, s.SetReminder(ctx, []string{"!r"}, t0.Add(time.Hour), "if_no_reply"))
	schedule(t, s, "!r", "$later", "ping", t0.Add(time.Hour), condIfNoReply)
	require.NoError(t, s.SetRead(ctx, "!r", "$!r", t0.Add(-time.Hour)))
	before := rowOf(t, s, "!r")
	require.Zero(t, before.Unread)

	require.True(t, insertTimerNote(t, s, "!r", "$note", "after_send", day, t0.Add(time.Minute), s.LastSeq()))

	row := rowOf(t, s, "!r")
	require.Equal(t, "$note", lastEventID(t, s, "!r"), "it is the newest thing in the chat")
	require.Equal(t, "timer_change", row.PreviewKind)
	require.Empty(t, row.Preview, "no words of the bridge's or of a language")
	require.True(t, row.PreviewMine)
	require.Zero(t, row.Unread, "not unread")
	require.True(t, dueAt(t, s, "!r").IsZero(), "not my reply: auto-archive isn't scheduled")
	require.Zero(t, count(t, s, "SELECT count(*) FROM events WHERE event_id = '$note' AND doc_id IS NOT NULL"), "not indexed")

	clock.set(t0.Add(time.Hour))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Equal(t, []string{"!r"}, fired, "not \"I replied\": the reminder fires")
	require.Equal(t, []string{"$later"}, claimDue(t, s), "and a scheduled message set \"if no reply\" goes")
}

// A bridge's note of a change made on the phone or by someone else: still a timer change in the preview, and none
// of its English is searchable. No other action message (a call) is searchable either.
func TestBridgeActionMessagesAreNotSearchedOrPreviewedInItsWords(t *testing.T) {
	s := open(t)
	clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$plain", ghost, "m.room.message", text("a timer for the oven"), t0)
	mkMsg(t, s, "!r", "$call", ghost, "m.room.message",
		`{"msgtype":"m.notice","body":"Started a video call","com.beeper.action_message":{"type":"call","call_type":"video"}}`, t0.Add(time.Second))
	mkMsg(t, s, "!r", "$note", ghost, "m.room.message", bridgeNote(day, "after_send", ""), t0.Add(2*time.Second))

	row := rowOf(t, s, "!r")
	require.Equal(t, "timer_change", row.PreviewKind)
	require.Empty(t, row.Preview)
	require.False(t, row.PreviewMine)

	find := func(q string) []string { return hitIDs(searchAll(t, s, MessageQuery{Terms: terms(q)})) }
	require.Equal(t, []string{"$plain"}, find("timer"), "only the person's words")
	require.Empty(t, find("disappearing"))
	require.Empty(t, find("video call"))
	require.Zero(t, count(t, s, "SELECT count(*) FROM events WHERE event_id IN ('$call', '$note') AND doc_id IS NOT NULL"))
}

// Ruling 40: a network that echoes a change made here, through a bridge that passes the echo on, never makes a
// second note: the echo is skipped, whichever arrives first. A note that isn't that echo is kept.
func TestEchoOfATimerChangeMadeHereIsNoSecondNote(t *testing.T) {
	s := open(t)
	clock := clockAt(s, t0)
	mkRoom(t, s, "!r", time.Unix(1, 0))

	// Mine first, then the echo of the same change (its time is the network's, a little off ours).
	require.True(t, insertTimerNote(t, s, "!r", "$mine", "after_send", day, t0, s.LastSeq()))
	clock.set(t0.Add(time.Minute))
	inserted, err := s.InsertEvent(context.Background(), Event{
		RoomID: "!r", EventID: "$echo", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(bridgeNote(day, "after_send", "")), TS: t0.Add(-2 * time.Second), Status: "sent",
	})
	require.NoError(t, err)
	require.False(t, inserted, "the echo is the same change")
	require.Equal(t, []string{"$mine"}, timerNotes(t, s, "!r"))

	// History of the same setting from long ago (a backfill) is a note of its own.
	mkMsg(t, s, "!r", "$history", ghost, "m.room.message", bridgeNote(day, "after_send", `,"backfill":true`), t0.Add(-30*day))
	// Another setting is a new change; so is the first one again after it.
	mkMsg(t, s, "!r", "$week", ghost, "m.room.message", bridgeNote(7*day, "after_send", ""), t0.Add(2*time.Minute))
	mkMsg(t, s, "!r", "$back", ghost, "m.room.message", bridgeNote(day, "after_send", ""), t0.Add(3*time.Minute))
	require.Equal(t, []string{"$history", "$mine", "$week", "$back"}, timerNotes(t, s, "!r"))

	// A note of the same setting long after mine is no echo: a change came and went with no note between.
	clock.set(t0.Add(time.Hour))
	require.True(t, insertTimerNote(t, s, "!r", "$mine2", "after_send", 90*day, t0.Add(time.Hour), s.LastSeq()))
	clock.set(t0.Add(time.Hour + timerEchoWindow + time.Millisecond))
	mkMsg(t, s, "!r", "$late", ghost, "m.room.message", bridgeNote(90*day, "after_send", ""), t0.Add(time.Hour+timerEchoWindow))
	require.Equal(t, []string{"$history", "$mine", "$week", "$back", "$mine2", "$late"}, timerNotes(t, s, "!r"))

	// The echo first, while the change was on its way: my note is the one skipped.
	afterSeq := s.LastSeq()
	mkMsg(t, s, "!r", "$echo2", me, "m.room.message", bridgeNote(0, "", ""), t0.Add(2*time.Hour))
	require.False(t, insertTimerNote(t, s, "!r", "$mine3", "", 0, t0.Add(2*time.Hour), afterSeq), "the network already said so")
	_, ok := getEvent(t, s, "$mine3")
	require.False(t, ok)
	// A note of that setting that was already here before the change was sent says nothing about it.
	require.True(t, insertTimerNote(t, s, "!r", "$mine4", "", 0, t0.Add(3*time.Hour), s.LastSeq()))
}

// Migration 5 takes out of the index what 4.2 indexed of an action message: the bridge's English.
func TestMigrationTakesActionMessagesOutOfTheIndex(t *testing.T) {
	s, _ := openFixtureWith(t, "m5.sql", `
INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted, doc_id) VALUES
  ('$n1', '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL,
   '`+bridgeNote(day, "after_send", "")+`', 1790812900000, '', '', 101, 0, 1),
  ('$n2', '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL,
   '{"msgtype":"m.text","body":"Incoming call","com.beeper.action_message":{"type":"call"}}', 1790812901000, '', '', 102, 0, 2),
  ('$n3', '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL,
   '{"msgtype":"m.text","body":"call me about the timer"}', 1790812902000, '', '', 103, 0, 3);
INSERT INTO search_messages (rowid, body, scope) VALUES (1, 'set the disappearing message timer to 24h0m0s', 'all'),
  (2, 'incoming call', 'all'), (3, 'call me about the timer', 'all');
UPDATE search_state SET value = (SELECT MAX(rowid) FROM events) WHERE key IN ('backfill_until', 'backfill_after');`)
	find := func(q string) []string { return hitIDs(searchAll(t, s, MessageQuery{Terms: terms(q)})) }
	require.Equal(t, []string{"$n3"}, find("timer"))
	require.Equal(t, []string{"$n3"}, find("call"))
	require.Empty(t, find("disappearing"))
	require.Zero(t, count(t, s, "SELECT count(*) FROM events WHERE event_id IN ('$n1', '$n2') AND doc_id IS NOT NULL"))
}

// openFixtureWith is openFixture with extra SQL run on the fixture before the store opens (and migrates) it.
func openFixtureWith(t *testing.T, name, extra string) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile(filepath.Join("testdata", name))
	require.NoError(t, err)
	raw, err := sqlite.Open(path)
	require.NoError(t, err)
	_, err = raw.Exec(context.Background(), string(fixture)+extra)
	require.NoError(t, err)
	require.NoError(t, raw.Close())
	s, err := Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s, path
}
