// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const (
	joinNote = "Vertex AI Pipelines (bot) has joined the channel"
	botName  = "Vertex AI Pipelines (bot)"
)

// nameGhost gives ghost the display name Slack gave it.
func nameGhost(t *testing.T, s *Store, name string) {
	t.Helper()
	require.NoError(t, s.UpsertProfile(context.Background(), Profile{UserID: ghost, DisplayName: name}))
}

func mkNetworkRoom(t *testing.T, s *Store, id, network string) {
	t.Helper()
	require.NoError(t, s.UpsertRoom(context.Background(), Room{ID: id, Network: network, Name: id, CreatedAt: time.Unix(1, 0)}))
}

// A note stored as text before the engine stored them as membership events is served as the membership event,
// with its own event ID; the same words in another network's chat stay a message.
func TestStoredSlackNoteIsServedAsMembership(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, botName)
	mkNetworkRoom(t, s, "!s", "slack")
	mkNetworkRoom(t, s, "!w", "whatsapp")
	for _, room := range []string{"!s", "!w"} {
		mkMsg(t, s, room, "$hi"+room, ghost, "m.room.message", text("hello"), time.Unix(10, 0))
		mkMsg(t, s, room, "$join"+room, ghost, "m.room.message", text(joinNote), time.Unix(20, 0))
	}
	check := func(evs []Event, room, wantType string) {
		t.Helper()
		byID := map[string]Event{}
		for _, e := range evs {
			byID[e.EventID] = e
		}
		require.Equal(t, wantType, byID["$join"+room].Type)
		require.Equal(t, "m.room.message", byID["$hi"+room].Type)
	}
	page, _, err := s.EventsBefore(ctx, "!s", nil, 10)
	require.NoError(t, err)
	check(page, "!s", "m.room.member")
	for _, e := range page {
		if e.EventID == "$join!s" {
			require.Contains(t, string(e.Content), `"membership":"join"`)
			require.NotNil(t, e.StateKey)
		}
	}
	around, _, _, err := s.EventsAround(ctx, "!s", "$join!s", 10)
	require.NoError(t, err)
	check(around, "!s", "m.room.member")
	page, _, err = s.EventsBefore(ctx, "!w", nil, 10)
	require.NoError(t, err)
	check(page, "!w", "m.room.message")
}

// The inbox does not preview or count a note that is still stored as text.
func TestStoredSlackNoteIsNoPreviewAndNotUnread(t *testing.T) {
	s := open(t)
	nameGhost(t, s, botName)
	mkNetworkRoom(t, s, "!s", "slack")
	mkNetworkRoom(t, s, "!w", "whatsapp")
	for _, room := range []string{"!s", "!w"} {
		mkMsg(t, s, room, "$hi"+room, ghost, "m.room.message", text("hello"), time.Unix(10, 0))
		mkMsg(t, s, room, "$join"+room, ghost, "m.room.message", text(joinNote), time.Unix(20, 0))
	}
	rows := inboxByID(t, s)
	require.Equal(t, "", rows["!s"].Preview)
	require.Equal(t, 1, rows["!s"].Unread, "only the real message is unread")
	require.Equal(t, joinNote, rows["!w"].Preview, "another network's chat is not Slack's wording")
	require.Equal(t, 2, rows["!w"].Unread)
}

func msgWith(msgtype, body string, extra map[string]any) string {
	return msgContent(msgtype, body, extra)
}

// noteCases are shared by the Go rule and its SQL twin.
var noteCases = []struct {
	name, network, typ, content, sender string
	want                                string // "join", "leave" or "" (not a note)
	asMe                                bool   // sent by the app's own user, who has no profile name
}{
	{"joined", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", nil), "Ann Lee", "join", false},
	{"left", "slack", "m.room.message", msgWith("m.notice", "Ann Lee has left the channel", nil), "Ann Lee", "leave", false},
	{"private channel", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the group", nil), "Ann Lee", "join", false},
	{"conversation", "slack", "m.room.message", msgWith("m.text", "Ann Lee has left the conversation", nil), "Ann Lee", "leave", false},
	{"trailing period", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel.", nil), "Ann Lee", "join", false},
	{"no msgtype", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel"}`, "Ann Lee", "join", false},
	{"body padded", "slack", "m.room.message", msgWith("m.text", "  Ann Lee has joined the channel\n", nil), "Ann Lee", "join", false},
	{"name padded", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", nil), " Ann Lee ", "join", false},
	{"non-latin name", "slack", "m.room.message", msgWith("m.text", "Анна Ли has joined the channel", nil), "Анна Ли", "join", false},
	{"bot name with brackets", "slack", "m.room.message", msgWith("m.text", joinNote, nil), botName, "join", false},
	{"someone else welcomes", "slack", "m.room.message", msgWith("m.text", "Welcome! Ann Lee has joined the channel.", nil), "Bob", "", false},
	{"mid-sentence from the joiner", "slack", "m.room.message", msgWith("m.text", "Hi all, Ann Lee has joined the channel", nil), "Ann Lee", "", false},
	{"quoted line", "slack", "m.room.message", msgWith("m.text", "> Ann Lee has joined the channel", nil), "Ann Lee", "", false},
	{"about someone else", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", nil), "Bob", "", false},
	{"longer message", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel and says hi", nil), "Ann Lee", "", false},
	{"two lines", "slack", "m.room.message", msgWith("m.text", "hi\nAnn Lee has joined the channel", nil), "Ann Lee", "", false},
	{"inner double space", "slack", "m.room.message", msgWith("m.text", "Ann  Lee has joined the channel", nil), "Ann Lee", "", false},
	{"no sender name", "slack", "m.room.message", msgWith("m.text", " has joined the channel", nil), "", "", false},
	{"name too long", "slack", "m.room.message", msgWith("m.text", strings.Repeat("a", 201)+" has joined the channel", nil), strings.Repeat("a", 201), "", false},
	{"name at the limit", "slack", "m.room.message", msgWith("m.text", strings.Repeat("é", 200)+" has joined the channel", nil), strings.Repeat("é", 200), "join", false},
	{"other network", "whatsapp", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", nil), "Ann Lee", "", false},
	{"image", "slack", "m.room.message", msgWith("m.image", "Ann Lee has joined the channel", nil), "Ann Lee", "", false},
	{"an edit", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", map[string]any{"m.new_content": map[string]any{"body": "x"}}), "Ann Lee", "", false},
	{"a null new_content", "slack", "m.room.message", `{"msgtype":"m.text","body":"Ann Lee has joined the channel","m.new_content":null}`, "Ann Lee", "", false},
	{"thread reply", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", map[string]any{"m.relates_to": map[string]any{"rel_type": "m.thread", "event_id": "$r"}}), "Ann Lee", "", false},
	{"relates_to without rel_type", "slack", "m.room.message", msgWith("m.text", "Ann Lee has joined the channel", map[string]any{"m.relates_to": map[string]any{"event_id": "$r"}}), "Ann Lee", "join", false},
	{"not a message", "slack", "m.sticker", msgWith("m.text", "Ann Lee has joined the channel", nil), "Ann Lee", "", false},
	{"not json", "slack", "m.room.message", `not json has`, "Ann Lee", "", false},
	// Keys that SQLite's json_extract and Go's decoder would read differently are never notes.
	{"a repeated body", "slack", "m.room.message", `{"msgtype":"m.text","body":"Ann Lee has joined the channel","body":"hello"}`, "Ann Lee", "", false},
	{"a repeated body, the note last", "slack", "m.room.message", `{"msgtype":"m.text","body":"hello","body":"Ann Lee has joined the channel"}`, "Ann Lee", "", false},
	{"a body key in another case", "slack", "m.room.message", `{"Body":"Ann Lee has joined the channel","msgtype":"m.text"}`, "Ann Lee", "", false},
	{"a note and another-case body", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","BODY":"hello"}`, "Ann Lee", "", false},
	{"a msgtype key in another case", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","MsgType":"m.image"}`, "Ann Lee", "", false},
	{"a relation key in another case", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","M.Relates_To":{"rel_type":"m.thread"}}`, "Ann Lee", "", false},
	{"a relation that is a string", "slack", "m.room.message", `{"msgtype":"m.text","body":"Ann Lee has joined the channel","m.relates_to":"x"}`, "Ann Lee", "", false},
	{"a relation that is null", "slack", "m.room.message", `{"msgtype":"m.text","body":"Ann Lee has joined the channel","m.relates_to":null}`, "Ann Lee", "", false},
	{"a relation with a null rel_type", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","m.relates_to":{"rel_type":null}}`, "Ann Lee", "join", false},
	{"a repeated rel_type, empty first", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","m.relates_to":{"rel_type":"","rel_type":"m.thread"}}`, "Ann Lee", "join", false},
	{"a repeated rel_type, thread first", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","m.relates_to":{"rel_type":"m.thread","rel_type":""}}`, "Ann Lee", "", false},
	{"a repeated other key", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel","format":"a","format":"b"}`, "Ann Lee", "join", false},
	{"a non-string body", "slack", "m.room.message", `{"body":5}`, "Ann Lee", "", false},
	{"a non-string msgtype", "slack", "m.room.message", `{"msgtype":5,"body":"Ann Lee has joined the channel"}`, "Ann Lee", "", false},
	{"trailing data", "slack", "m.room.message", `{"body":"Ann Lee has joined the channel"} x`, "Ann Lee", "", false},
	// My own note: the app's user has no profile name, so a plain name will do.
	{"my own join", "slack", "m.room.message", msgWith("m.text", "James has joined the channel", nil), "", "join", true},
	{"my own leave in a group", "slack", "m.room.message", msgWith("m.text", "James Nguyen has left the group", nil), "", "leave", true},
	{"my own welcome", "slack", "m.room.message", msgWith("m.text", "Welcome! Ann has joined the channel.", nil), "", "", true},
	{"my own quoted line", "slack", "m.room.message", msgWith("m.text", "> Ann has joined the channel", nil), "", "", true},
	{"my own sentence", "slack", "m.room.message", msgWith("m.text", "Hi all, Ann has joined the channel", nil), "", "", true},
	{"my own two lines", "slack", "m.room.message", msgWith("m.text", "hi\nAnn has joined the channel", nil), "", "", true},
	{"my own, name with a full stop", "slack", "m.room.message", msgWith("m.text", "J. Smith has joined the channel", nil), "", "", true},
	{"my own, a thread reply", "slack", "m.room.message", msgWith("m.text", "James has joined the channel", map[string]any{"m.relates_to": map[string]any{"rel_type": "m.thread", "event_id": "$r"}}), "", "", true},
	{"my own, no name", "slack", "m.room.message", msgWith("m.text", " has joined the channel", nil), "", "", true},
	{"my own, in another network", "whatsapp", "m.room.message", msgWith("m.text", "James has joined the channel", nil), "", "", true},
}

// noteSender is who sent a case: the app's own user, or someone.
func noteSender(asMe bool, other string) string {
	if asMe {
		return myID
	}
	return other
}

func TestMembershipNote(t *testing.T) {
	for _, tc := range noteCases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := MembershipNote(tc.network, tc.typ, json.RawMessage(tc.content), noteSender(tc.asMe, "@u:courier.local"), tc.sender)
			require.Equal(t, tc.want != "", ok)
			require.Equal(t, tc.want, got)
		})
	}
}

// slackNoteSQL says what MembershipNote says, for every case.
func TestMembershipNoteSQLAgreesWithGo(t *testing.T) {
	s, ctx := open(t), context.Background()
	for i, tc := range noteCases {
		room, user := "!r"+strings.Repeat("x", i), "@u"+strings.Repeat("x", i)+":courier.local"
		mkNetworkRoom(t, s, room, tc.network)
		user = noteSender(tc.asMe, user)
		if tc.sender != "" || !tc.asMe {
			require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: user, DisplayName: tc.sender}))
		}
		mkMsg(t, s, room, "$e"+room, user, tc.typ, tc.content, time.Unix(10, 0))
		var sqlVerdict int
		require.NoError(t, s.db.QueryRow(ctx, `SELECT COALESCE(`+slackNoteSQL("r", "u")+`, 0) FROM events u JOIN rooms r ON r.room_id = u.room_id WHERE u.event_id = $1`,
			"$e"+room).Scan(&sqlVerdict), tc.name)
		_, goVerdict := MembershipNote(tc.network, tc.typ, json.RawMessage(tc.content), user, tc.sender)
		require.Equal(t, goVerdict, sqlVerdict == 1, "%s: Go and SQL disagree", tc.name)
		require.Equal(t, tc.want != "", sqlVerdict == 1, tc.name)
	}
}

func TestSlackNoteFromSomeoneElseStaysAMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, "Bob")
	mkNetworkRoom(t, s, "!s", "slack")
	mkMsg(t, s, "!s", "$w", ghost, "m.room.message", text("Welcome! Ann Lee has joined the channel."), time.Unix(10, 0))
	e, ok, err := s.GetEvent(ctx, "$w")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "m.room.message", e.Type)
	row := inboxByID(t, s)["!s"]
	require.Equal(t, "Welcome! Ann Lee has joined the channel.", row.Preview)
	require.Equal(t, 1, row.Unread)
}

// Every way the app reads one event serves a stored note as the membership event.
func TestStoredSlackNoteIsServedOnEveryReadPath(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, botName)
	mkNetworkRoom(t, s, "!s", "slack")
	mkMsg(t, s, "!s", "$j", ghost, "m.room.message", text(joinNote), time.Unix(10, 0))

	e, _, err := s.GetEvent(ctx, "$j")
	require.NoError(t, err)
	require.Equal(t, "m.room.member", e.Type, "GetEvent")
	evs, err := s.Events(ctx, "!s", 10)
	require.NoError(t, err)
	require.Equal(t, "m.room.member", evs[0].Type, "Events")
	last, _, err := s.LastMessage(ctx, "!s")
	require.NoError(t, err)
	require.Equal(t, "m.room.member", last.Type, "LastMessage")
	versions, err := s.EditHistory(ctx, "$j")
	require.NoError(t, err)
	require.Len(t, versions, 1, "EditHistory still answers for it")
	require.NoError(t, s.SetBookmarked(ctx, "$j", true))
	hits, err := s.RecentBookmarks(ctx, 5)
	require.NoError(t, err)
	require.Len(t, hits, 1)
	require.Equal(t, "m.room.member", hits[0].Event.Type, "RecentBookmarks")
}

// A note still stored as text is never a search hit; the same words from someone else, or in another network, are.
func TestSearchLeavesOutStoredSlackNotes(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, botName)
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: me, DisplayName: "Zed"}))
	mkNetworkRoom(t, s, "!s", "slack")
	mkNetworkRoom(t, s, "!w", "whatsapp")
	mkMsg(t, s, "!s", "$note", ghost, "m.room.message", text(joinNote), time.Unix(10, 0))
	mkMsg(t, s, "!s", "$talk", me, "m.room.message", text("Welcome! "+joinNote+"."), time.Unix(20, 0))
	mkMsg(t, s, "!w", "$wa", ghost, "m.room.message", text(joinNote), time.Unix(30, 0))
	hits, _, err := s.SearchMessages(ctx, MessageQuery{Terms: terms("joined")})
	require.NoError(t, err)
	var ids []string
	for _, h := range hits {
		ids = append(ids, h.Event.EventID)
	}
	require.ElementsMatch(t, []string{"$talk", "$wa"}, ids)
}

// A sender renamed since the note was stored no longer matches it: the old note stays an ordinary message, but it
// is not unread once the chat's read marker is past it.
func TestRenamedSenderLeavesAnOldNoteAMessageButNotUnread(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, botName)
	mkNetworkRoom(t, s, "!s", "slack")
	mkMsg(t, s, "!s", "$old", ghost, "m.room.message", text(joinNote), time.Unix(10, 0))
	mkMsg(t, s, "!s", "$hi", ghost, "m.room.message", text("hello"), time.Unix(20, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!s", "$hi", time.Unix(20, 0)))
	nameGhost(t, s, "Pipelines")
	e, _, err := s.GetEvent(ctx, "$old")
	require.NoError(t, err)
	require.Equal(t, "m.room.message", e.Type, "no longer matches: an ordinary message")
	require.Equal(t, 0, inboxByID(t, s)["!s"].Unread, "read, so not unread")
	mkMsg(t, s, "!s", "$new", ghost, "m.room.message", text(joinNote), time.Unix(30, 0))
	require.Equal(t, 1, inboxByID(t, s)["!s"].Unread, "a newer one from the renamed sender is an ordinary unread message")
}

// The shape of a real note from this Mac's store (read-only, copied by hand): Slack's text message from the person's
// own ghost, whose profile name is the one in the body.
func TestRealSlackNoteShape(t *testing.T) {
	s, ctx := open(t), context.Background()
	const user = "@slack_t08jv4qgt71-u0b1ktkqunm:courier.local"
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: user, DisplayName: "Vertex AI Pipelines (bot)"}))
	mkNetworkRoom(t, s, "!ds", "slack")
	mkMsg(t, s, "!ds", "$real", user, "m.room.message", `{"msgtype":"m.text","body":"Vertex AI Pipelines (bot) has joined the channel"}`, time.Unix(10, 0))
	e, _, err := s.GetEvent(ctx, "$real")
	require.NoError(t, err)
	require.Equal(t, "m.room.member", e.Type)
	// Mine: sent as the app's own user, which has no profile row at all.
	mkMsg(t, s, "!ds", "$mine", myID, "m.room.message", `{"msgtype":"m.text","body":"James has joined the channel"}`, time.Unix(20, 0))
	e, _, err = s.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	require.Equal(t, "m.room.member", e.Type)
}

// Reading a page of events looks senders up after its rows are closed, once per sender.
func TestServingAPageOfNotes(t *testing.T) {
	s, ctx := open(t), context.Background()
	nameGhost(t, s, botName)
	mkNetworkRoom(t, s, "!s", "slack")
	for i := 0; i < 20; i++ {
		mkMsg(t, s, "!s", fmt.Sprintf("$n%d", i), ghost, "m.room.message", text(joinNote), time.Unix(int64(10+i), 0))
	}
	evs, _, err := s.EventsBefore(ctx, "!s", nil, 50)
	require.NoError(t, err)
	require.Len(t, evs, 20)
	for _, e := range evs {
		require.Equal(t, "m.room.member", e.Type)
	}
}
