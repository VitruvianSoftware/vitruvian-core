// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// The call notices the pinned bridges send, each as its bridge makes it (see callnotes.go for the sources).
const (
	waCall        = `{"msgtype":"m.text","body":"Incoming call. Use the WhatsApp app to answer.","com.beeper.action_message":{"type":"call"}}`
	waGroupCall   = `{"msgtype":"m.text","body":"Incoming group call. Use the WhatsApp app to answer.","com.beeper.action_message":{"type":"call","call_type":"group"}}`
	signalRinging = `{"msgtype":"m.text","body":"Incoming call","com.beeper.action_message":{"type":"call"}}`
	signalGroup   = `{"msgtype":"m.notice","body":"Incoming call","com.beeper.action_message":{"type":"call"}}`
	signalEnded   = `{"msgtype":"m.notice","body":"Call ended"}`
	tgRinging     = `{"msgtype":"m.notice","body":"Started a call","com.beeper.action_message":{"type":"call","call_type":"voice"}}`
	tgRingingVid  = `{"msgtype":"m.notice","body":"Started a video call","com.beeper.action_message":{"type":"call","call_type":"video"}}`
	tgChatStarted = `{"msgtype":"m.notice","body":"Started a video chat","com.beeper.action_message":{"type":"call","call_type":"video"}}`
	tgChatEnded   = `{"msgtype":"m.notice","body":"Ended the video chat (1 minute)","com.beeper.action_message":{"type":"call","call_type":"video"}}`
)

// tgRecord is Telegram's record of a one-to-one call (MessageActionPhoneCall): an m.notice with no action message.
func tgRecord(body string) string {
	b, _ := json.Marshal(map[string]string{"msgtype": "m.notice", "body": body})
	return string(b)
}

func callOf(t *testing.T, content json.RawMessage) (CallNote, bool) {
	t.Helper()
	return parseCallNote("m.room.message", content)
}

// Every call notice a pinned bridge sends is read as Courier's call note: what happened and, where the bridge says,
// voice or video. The bridge's English body is never what decides, except for the two notices that have nothing
// else (Signal's "Call ended", Telegram's call record), and those only on their own network, as the bridge's notice.
func TestEveryBridgesCallNoticeIsACallNote(t *testing.T) {
	cases := []struct {
		name, network, content string
		want                   CallNote
	}{
		{"whatsapp", "whatsapp", waCall, CallNote{State: CallRinging}},
		{"whatsapp group", "whatsapp", waGroupCall, CallNote{State: CallRinging}},
		{"signal", "signal", signalRinging, CallNote{State: CallRinging}},
		{"signal group", "signal", signalGroup, CallNote{State: CallRinging}},
		{"signal ended", "signal", signalEnded, CallNote{State: CallEnded}},
		{"telegram voice", "telegram", tgRinging, CallNote{State: CallRinging, Media: CallVoice}},
		{"telegram video", "telegram", tgRingingVid, CallNote{State: CallRinging, Media: CallVideo}},
		{"telegram video chat", "telegram", tgChatStarted, CallNote{State: CallStarted, Media: CallVideo}},
		{"telegram video chat ended", "telegram", tgChatEnded, CallNote{State: CallEnded, Media: CallVideo}},
		{"telegram missed", "telegram", tgRecord("Call missed"), CallNote{State: CallMissed, Media: CallVoice}},
		{"telegram video missed", "telegram", tgRecord("Video call missed"), CallNote{State: CallMissed, Media: CallVideo}},
		{"telegram ended", "telegram", tgRecord("Call ended (5 minutes)"), CallNote{State: CallEnded, Media: CallVoice}},
		{"telegram rejected", "telegram", tgRecord("Video call rejected"), CallNote{State: CallDeclined, Media: CallVideo}},
		{"telegram disconnected", "telegram", tgRecord("Call disconnected (12 seconds)"), CallNote{State: CallDropped, Media: CallVoice}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := AnnotateCallNote(tc.network, "m.room.message", json.RawMessage(tc.content))
			note, ok := callOf(t, got)
			require.True(t, ok, "%s", got)
			require.Equal(t, tc.want, note)
			require.True(t, isActionMessage(got), "a call note is an action message: never indexed")
			var c map[string]any
			require.NoError(t, json.Unmarshal(got, &c))
			var orig map[string]any
			require.NoError(t, json.Unmarshal([]byte(tc.content), &orig))
			for k, v := range orig {
				if k != actionMessageKey {
					require.Equal(t, v, c[k], "the bridge's %s is kept as it was", k)
				}
			}
			require.Equal(t, "call", c[actionMessageKey].(map[string]any)["type"])
			if a, ok := orig[actionMessageKey].(map[string]any); ok {
				require.Equal(t, a, c[actionMessageKey], "the bridge's own action message is kept as it was")
			}
			// Reading it again changes nothing.
			require.JSONEq(t, string(got), string(AnnotateCallNote(tc.network, "m.room.message", got)))
		})
	}
}

// Words that only look like a call notice stay what they are: a person's message, another network's notice, a
// notice of a shape the bridge never sends, or something that isn't a message.
func TestOnlyABridgesOwnCallNoticeIsACallNote(t *testing.T) {
	cases := []struct{ name, network, typ, content string }{
		{"typed on signal", "signal", "m.room.message", text("Call ended")},
		{"signal's words on telegram", "telegram", "m.room.message", tgRecord("Call ended, see you")},
		{"telegram's words on signal", "signal", "m.room.message", tgRecord("Call missed")},
		{"telegram's words typed", "telegram", "m.room.message", text("Call missed")},
		{"telegram's words on whatsapp", "whatsapp", "m.room.message", tgRecord("Call ended")},
		{"a longer notice", "telegram", "m.room.message", tgRecord("Call missed twice")},
		{"an unknown reason", "telegram", "m.room.message", tgRecord("Call paused")},
		{"slack", "slack", "m.room.message", tgRecord("Call ended")},
		{"a sticker", "signal", "m.sticker", signalEnded},
		{"a timer note", "signal", "m.room.message", bridgeNote(day, "after_send", "")},
		{"not json", "signal", "m.room.message", `{"msgtype":`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := AnnotateCallNote(tc.network, tc.typ, json.RawMessage(tc.content))
			require.Equal(t, tc.content, string(got), "left exactly as the bridge sent it")
			_, ok := parseCallNote(tc.typ, got)
			require.False(t, ok)
		})
	}
}

// An action message of type call that Courier didn't annotate (one stored before this engine) is still a call note:
// the action message alone says so, ringing, with voice or video only when its call_type says.
func TestACallActionMessageAloneIsACallNote(t *testing.T) {
	note, ok := callOf(t, json.RawMessage(tgRingingVid))
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallRinging, Media: CallVideo}, note)
	note, ok = callOf(t, json.RawMessage(waGroupCall))
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallRinging}, note, "call_type group is no media")
	note, ok = callOf(t, json.RawMessage(`{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call"},"fi.courier.call":{"state":"exploded","media":"hologram"}}`))
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallRinging}, note, "what this engine doesn't know reads as the plainest note")
	note, ok = callOf(t, json.RawMessage(`{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call","call_type":"voice"},"fi.courier.call":"missed"}`))
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallRinging, Media: CallVoice}, note, "a reading that isn't one is no reading")
}

// A call note is the chat's newest message like any other, and its preview is Courier's: kind "call", no text (the
// bridge's English), and what happened beside it.
func TestACallNotePreviewsAsACall(t *testing.T) {
	s := open(t)
	chatAt(t, s, "!r", "telegram", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$call", ghost, "m.room.message",
		string(AnnotateCallNote("telegram", "m.room.message", json.RawMessage(tgRecord("Video call missed")))), t0)
	r := rowOf(t, s, "!r")
	require.Equal(t, "call", r.PreviewKind)
	require.Empty(t, r.Preview, "never the bridge's English")
	require.Equal(t, &CallNote{State: CallMissed, Media: CallVideo}, r.PreviewCall)
	require.False(t, r.PreviewMine)

	mkMsg(t, s, "!r", "$msg", ghost, "m.room.message", text("sorry, call me back"), t0.Add(time.Minute))
	r = rowOf(t, s, "!r")
	require.Equal(t, "text", r.PreviewKind)
	require.Nil(t, r.PreviewCall)
}

// Someone else's call is news: it counts unread, as a message does. My own call (Telegram's record of a call I made,
// which the bridge sends as me) is not.
func TestSomeoneElsesCallIsUnreadMineIsNot(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	chatAt(t, s, "!r", "signal", t0.Add(-time.Hour))
	require.NoError(t, s.SetRead(ctx, "!r", "$!r", t0.Add(-time.Hour)))
	mkMsg(t, s, "!r", "$ring", ghost, "m.room.message", string(AnnotateCallNote("signal", "m.room.message", json.RawMessage(signalRinging))), t0)
	mkMsg(t, s, "!r", "$end", ghost, "m.room.message", string(AnnotateCallNote("signal", "m.room.message", json.RawMessage(signalEnded))), t0.Add(time.Minute))
	require.Equal(t, 1, rowOf(t, s, "!r").Unread, "the ring is news; that it ended is not")

	chatAt(t, s, "!t", "telegram", t0.Add(-time.Hour))
	require.NoError(t, s.SetRead(ctx, "!t", "$!t", t0.Add(-time.Hour)))
	mkMsg(t, s, "!t", "$mine", me, "m.room.message", string(AnnotateCallNote("telegram", "m.room.message", json.RawMessage(tgRecord("Call missed")))), t0)
	r := rowOf(t, s, "!t")
	require.Zero(t, r.Unread, "a call I made is not news to me")
	require.Equal(t, "call", r.PreviewKind)
	require.True(t, r.PreviewMine)
}

// A call note is the bridge's English: search never finds it by those words.
func TestACallNoteIsNotSearchable(t *testing.T) {
	s := open(t)
	chatAt(t, s, "!r", "signal", t0.Add(-time.Hour))
	mkMsg(t, s, "!r", "$end", ghost, "m.room.message", string(AnnotateCallNote("signal", "m.room.message", json.RawMessage(signalEnded))), t0)
	mkMsg(t, s, "!r", "$typed", ghost, "m.room.message", text("Call ended early"), t0.Add(time.Minute))
	require.Equal(t, []string{"$typed"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("ended")})))
}

// Migration 6 reads the call notices already on disk as this engine now reads a new one: the two with no action
// message become call notes, the video chat that ended says so, and none of them stays in the search index.
func TestMigrationReadsStoredCallNotices(t *testing.T) {
	s, _ := openFixtureWith(t, "m5.sql", `
INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id, request) VALUES
  ('!sig:courier.local', 'signal', 'Sig', 1, 1790000000000, 0, '', 0),
  ('!tg:courier.local', 'telegram', 'Tg', 1, 1790000000000, 0, '', 0);
INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted, doc_id) VALUES
  ('$c1', '!sig:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+signalEnded+`', 1790812900000, '', '', 101, 0, 1),
  ('$c2', '!tg:courier.local', '@me:courier.local', 'm.room.message', NULL, '`+tgRecord("Video call missed")+`', 1790812901000, '', '', 102, 0, 2),
  ('$c3', '!tg:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+tgChatEnded+`', 1790812902000, '', '', 103, 0, NULL),
  ('$c4', '!tg:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+text("Call ended")+`', 1790812903000, '', '', 104, 0, 3),
  ('$c5', '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+tgRecord("Call ended")+`', 1790812904000, '', '', 105, 0, 4);
INSERT INTO search_messages (rowid, body, scope) VALUES (1, 'call ended', 'all'), (2, 'video call missed', 'all'),
  (3, 'call ended', 'all'), (4, 'call ended', 'all');
UPDATE search_state SET value = (SELECT MAX(rowid) FROM events) WHERE key IN ('backfill_until', 'backfill_after');`)
	read := func(id string) (CallNote, bool) {
		e, ok := getEvent(t, s, id)
		require.True(t, ok, id)
		return parseCallNote(e.Type, e.Content)
	}
	note, ok := read("$c1")
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallEnded}, note)
	note, ok = read("$c2")
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallMissed, Media: CallVideo}, note)
	note, ok = read("$c3")
	require.True(t, ok)
	require.Equal(t, CallNote{State: CallEnded, Media: CallVideo}, note)
	_, ok = read("$c4")
	require.False(t, ok, "a person's words stay theirs")
	_, ok = read("$c5")
	require.False(t, ok, "Telegram's words on another network stay a message")

	require.Equal(t, []string{"$c5", "$c4"}, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("ended")})))
	require.Empty(t, hitIDs(searchAll(t, s, MessageQuery{Terms: terms("missed")})))
}

// The SQL that annotates stored notices and the Go that annotates new ones read the same notices the same way.
func TestCallNoteSQLAndGoAgree(t *testing.T) {
	s, ctx := open(t), context.Background()
	contents := []struct{ network, content string }{
		{"signal", signalEnded},
		{"signal", signalRinging},
		{"signal", text("Call ended")},
		{"whatsapp", signalEnded},
		{"telegram", tgChatStarted},
		{"telegram", tgChatEnded},
		{"telegram", tgRingingVid},
		{"telegram", text("Call missed")},
		{"whatsapp", waGroupCall},
		{"slack", tgRecord("Call missed")},
		// Already read: an odd reading, a reading that isn't one, a reading on another action message.
		{"signal", `{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call"},"fi.courier.call":{"state":"exploded"}}`},
		{"signal", `{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call"},"fi.courier.call":"ended"}`},
		{"signal", `{"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"x"},"fi.courier.call":{"state":"ended"}}`},
	}
	for _, r := range []string{"Call", "Video call"} {
		for _, o := range []string{"missed", "ended", "rejected", "disconnected", "paused"} {
			contents = append(contents, struct{ network, content string }{"telegram", tgRecord(r + " " + o)},
				struct{ network, content string }{"telegram", tgRecord(r + " " + o + " (1 hour)")},
				struct{ network, content string }{"telegram", tgRecord(r + " " + o + " (")})
		}
	}
	for _, c := range contents {
		var got string
		require.NoError(t, s.db.QueryRow(ctx, `SELECT `+annotateCallNoteSQL("$1", "$2")+``, c.network, c.content).Scan(&got))
		want := AnnotateCallNote(c.network, "m.room.message", json.RawMessage(c.content))
		wantNote, wantOK := parseCallNote("m.room.message", want)
		gotNote, gotOK := parseCallNote("m.room.message", json.RawMessage(got))
		require.Equal(t, wantOK, gotOK, "%s %s: SQL %s", c.network, c.content, got)
		require.Equal(t, wantNote, gotNote, "%s %s", c.network, c.content)
		require.Equal(t, isActionMessage(want), isActionMessage(json.RawMessage(got)), "%s %s", c.network, c.content)
		var record bool
		require.NoError(t, s.db.QueryRow(ctx, `SELECT (`+isCallRecordSQL("$1")+`) IS 1`, string(want)).Scan(&record))
		require.Equal(t, isCallRecord(Event{Type: "m.room.message", Content: want}), record, "%s %s", c.network, c.content)
	}
}

// read is network's bridge's notice as the engine stores it.
func read(network, content string) string {
	return string(AnnotateCallNote(network, "m.room.message", json.RawMessage(content)))
}

// Only a call that is news counts unread: one that rang (or a group's call that started) and one that was missed.
// The record that a call ended, was declined or dropped is not news; and a call I made never is.
func TestOnlyACallThatIsNewsIsUnread(t *testing.T) {
	cases := []struct {
		name, network string
		notices       []struct{ sender, content string }
		unread        int
	}{
		{"signal: rang, then ended", "signal", []struct{ sender, content string }{
			{ghost, signalRinging}, {ghost, signalEnded},
		}, 1},
		{"signal: ended, after a call I made", "signal", []struct{ sender, content string }{
			{ghost, signalEnded},
		}, 0},
		{"telegram: answered", "telegram", []struct{ sender, content string }{
			{ghost, tgRinging}, {ghost, tgRecord("Call ended (5 minutes)")},
		}, 1},
		{"telegram: missed", "telegram", []struct{ sender, content string }{
			{ghost, tgRinging}, {ghost, tgRecord("Call missed")},
		}, 2},
		{"telegram: declined and dropped", "telegram", []struct{ sender, content string }{
			{ghost, tgRecord("Video call rejected")}, {ghost, tgRecord("Call disconnected")},
		}, 0},
		{"telegram: a group's video chat", "telegram", []struct{ sender, content string }{
			{ghost, tgChatStarted}, {ghost, tgChatEnded},
		}, 1},
		{"telegram: a call I made, missed", "telegram", []struct{ sender, content string }{
			{me, tgRecord("Call missed")},
		}, 0},
		{"whatsapp: rang", "whatsapp", []struct{ sender, content string }{{ghost, waCall}}, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s, ctx := open(t), context.Background()
			clockAt(s, t0)
			chatAt(t, s, "!r", tc.network, t0.Add(-time.Hour))
			require.NoError(t, s.SetRead(ctx, "!r", "$!r", t0.Add(-time.Hour)))
			for i, n := range tc.notices {
				mkMsg(t, s, "!r", fmt.Sprintf("$n%d", i), n.sender, "m.room.message", read(tc.network, n.content),
					t0.Add(time.Duration(i)*time.Minute))
			}
			r := rowOf(t, s, "!r")
			require.Equal(t, tc.unread, r.Unread)
			require.Equal(t, "call", r.PreviewKind, "the newest is still the chat's latest, news or not")
		})
	}
}

// A call that is news brings an archived chat back, as a message does; the record that it ended doesn't.
func TestOnlyACallThatIsNewsUnarchives(t *testing.T) {
	s, ctx := open(t), context.Background()
	clockAt(s, t0)
	chatAt(t, s, "!r", "signal", t0.Add(-time.Hour))
	_, err := s.SetArchived(ctx, []string{"!r"}, true)
	require.NoError(t, err)
	mkMsg(t, s, "!r", "$end", ghost, "m.room.message", read("signal", signalEnded), t0.Add(time.Minute))
	require.True(t, rowOf(t, s, "!r").Archived, "a call that ended is no news")
	mkMsg(t, s, "!r", "$ring", ghost, "m.room.message", read("signal", signalRinging), t0.Add(2*time.Minute))
	require.False(t, rowOf(t, s, "!r").Archived, "a call that rings is")
}

// "If no reply": someone else's call cancels a scheduled message only when it is news (it rang, or was missed), even
// as a notice; the record that it ended doesn't. A call I make is my reply: a reminder "if no reply" doesn't fire.
func TestACallIsAReplyOnlyWhenItIsNews(t *testing.T) {
	s, ctx := open(t), context.Background()
	clock := clockAt(s, t0)
	for _, r := range []string{"!ended", "!missed", "!rang"} {
		chatAt(t, s, r, "telegram", t0.Add(-time.Hour))
	}
	schedule(t, s, "!ended", "$e", "ping", t0.Add(time.Hour), condIfNoReply)
	schedule(t, s, "!missed", "$m", "ping", t0.Add(time.Hour), condIfNoReply)
	schedule(t, s, "!rang", "$g", "ping", t0.Add(time.Hour), condIfNoReply)
	mkMsg(t, s, "!ended", "$c1", ghost, "m.room.message", read("telegram", tgRecord("Call ended (1 minute)")), t0.Add(time.Minute))
	mkMsg(t, s, "!missed", "$c2", ghost, "m.room.message", read("telegram", tgRecord("Video call missed")), t0.Add(time.Minute))
	mkMsg(t, s, "!rang", "$c3", ghost, "m.room.message", read("telegram", tgRinging), t0.Add(time.Minute))

	chatAt(t, s, "!called", "telegram", t0.Add(-time.Hour))
	require.NoError(t, s.SetReminder(ctx, []string{"!called"}, t0.Add(time.Hour), condIfNoReply))
	mkMsg(t, s, "!called", "$c4", me, "m.room.message", read("telegram", tgRecord("Call missed")), t0.Add(time.Minute))

	clock.set(t0.Add(time.Hour))
	require.Equal(t, []string{"$e"}, claimDue(t, s))
	require.Equal(t, map[string]string{"$m": stateCanceled, "$g": stateCanceled}, scheduledStates(t, s, ""))
	fired, err := s.FireDueReminders(ctx)
	require.NoError(t, err)
	require.Empty(t, fired, "calling them back is replying")
}

// liveMigration6SQL is migration 6 as the live helpers build it today: every stored call notice read by
// annotateCallNoteSQL with its chat's network, and the newly marked ones out of the search index.
func liveMigration6SQL() string {
	network := `(SELECT network FROM rooms WHERE rooms.room_id = events.room_id)`
	marked := `content LIKE '%` + callKey + `%' AND ` + hasActionMessageSQL("content")
	return `UPDATE events SET content = ` + annotateCallNoteSQL(network, "content") + `
  WHERE type = 'm.room.message' AND content LIKE '%call%';
DELETE FROM search_messages WHERE rowid IN (SELECT doc_id FROM events WHERE doc_id IS NOT NULL AND ` + marked + `);
UPDATE events SET doc_id = NULL WHERE doc_id IS NOT NULL AND ` + marked + `;`
}

// Migration 6 is frozen as text, so a bridge that rewords its notices later changes annotateCallNoteSQL (what the
// engine reads from then on), never a migration already on someone's disk. Today the two are the same.
func TestMigration6IsTheLiveHelperToday(t *testing.T) {
	require.Equal(t, liveMigration6SQL(), migrations[5])
}
