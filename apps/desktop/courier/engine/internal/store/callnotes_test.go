// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
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
	require.Equal(t, 2, rowOf(t, s, "!r").Unread)

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
	}
}
