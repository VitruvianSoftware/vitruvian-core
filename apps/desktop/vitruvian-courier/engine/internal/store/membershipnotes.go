// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"maps"
	"slices"
	"strings"
	"unicode/utf8"
)

// Slack tells a person joining or leaving a channel as a message: "<@U123> has joined the channel", with the
// subtype channel_join / channel_leave (group_join / group_leave in a private channel). The bridge keeps the words
// but not the subtype, so for Slack the engine reads the words and stores the message as the membership change it
// is: the timeline shows a centered "Ann joined" line, not a bubble, and it is never unread, never notifies and never
// the chat's preview.
//
// Slack's own note is sent by the person who joined, and says their name. So a message only counts when it is
// exactly "<the sender's name> has joined the channel": "Welcome! Ann has joined the channel." from someone else, a
// quoted line, or a longer message stays a message. MembershipNote is the one rule; slackNoteSQL is its twin for the
// unread count, and TestMembershipNoteSQLAgreesWithGo holds the two to the same verdicts.

// notePhrases is what follows the name, and what it means.
var notePhrases = func() map[string]string {
	m := map[string]string{}
	for _, verb := range []struct{ word, membership string }{{"joined", "join"}, {"left", "leave"}} {
		for _, noun := range []string{"channel", "group", "conversation"} {
			m[" has "+verb.word+" the "+noun] = verb.membership
			m[" has "+verb.word+" the "+noun+"."] = verb.membership
		}
	}
	return m
}()

// noteSpace is what is trimmed from a body and a name: the same four characters in Go and in SQL.
const noteSpace = " \t\n\r"

// maxNoteNameRunes is the longest name a note can carry.
const maxNoteNameRunes = 200

// couldBeMembershipNote is the cheap first look every event gets: a Slack-shaped text message.
func couldBeMembershipNote(typ string, content json.RawMessage) bool {
	return typ == "m.room.message" && strings.Contains(string(content), " has ")
}

// MembershipNote reads content, an m.room.message from network's bridge sent by someone called senderName, as that
// person joining or leaving the chat. membership is "join" or "leave"; ok is false for anything else: another
// network, a sender with no name, a message that says more or less than Slack's note, an edit or a thread reply.
func MembershipNote(network, typ string, content json.RawMessage, senderName string) (membership string, ok bool) {
	if network != "slack" || !couldBeMembershipNote(typ, content) {
		return "", false
	}
	name := strings.Trim(senderName, noteSpace)
	if n := utf8.RuneCountInString(name); n < 1 || n > maxNoteNameRunes {
		return "", false
	}
	var c struct {
		MsgType    string          `json:"msgtype"`
		Body       string          `json:"body"`
		NewContent json.RawMessage `json:"m.new_content"`
		Relates    *struct {
			RelType string `json:"rel_type"`
		} `json:"m.relates_to"`
	}
	if json.Unmarshal(content, &c) != nil || c.NewContent != nil || (c.Relates != nil && c.Relates.RelType != "") {
		return "", false
	}
	switch c.MsgType {
	case "m.text", "m.notice", "":
	default:
		return "", false
	}
	rest, found := strings.CutPrefix(strings.Trim(c.Body, noteSpace), name)
	if !found {
		return "", false
	}
	membership, ok = notePhrases[rest]
	return membership, ok
}

// senderName is the name Slack gave userID: their profile's display name.
func (s *Store) senderName(ctx context.Context, userID string) string {
	var name string
	_ = s.db.QueryRow(ctx, "SELECT display_name FROM profiles WHERE user_id=$1", userID).Scan(&name)
	return name
}

// noteOf is MembershipNote for event e of a chat on network, looking up its sender's name when the event could be one.
func (s *Store) noteOf(ctx context.Context, network string, e Event) (string, bool) {
	if network != "slack" || !couldBeMembershipNote(e.Type, e.Content) {
		return "", false
	}
	return MembershipNote(network, e.Type, e.Content, s.senderName(ctx, e.Sender))
}

// membershipEvent is the membership change a Slack join or leave note stands for: an m.room.member event with the
// note's own event ID, sender and time, so replies and scroll anchors that name it keep working. The person is the
// sender (the note is written by the one who joined); the app names them as it names any member event.
func membershipEvent(e Event, membership string) Event {
	sk := e.Sender
	e.Type, e.StateKey = "m.room.member", &sk
	e.Content, _ = json.Marshal(map[string]any{"membership": membership, "state_key": sk, "target_user_id": sk})
	return e
}

// served is e as the app should see it. A Slack join or leave note that was stored as a text message, before the
// engine stored them as membership events, is turned into the membership event it is, so history already on disk
// shows as the centered membership row too. Every other event comes back as given. The cheap content test comes
// first: only a matching message costs a look at its chat's network.
func (s *Store) served(ctx context.Context, e Event) Event {
	if !couldBeMembershipNote(e.Type, e.Content) {
		return e
	}
	var network string
	if s.db.QueryRow(ctx, "SELECT network FROM rooms WHERE room_id=$1", e.RoomID).Scan(&network) != nil {
		return e
	}
	return s.servedOn(ctx, network, e)
}

// servedOn is served for an event whose chat's network is known.
func (s *Store) servedOn(ctx context.Context, network string, e Event) Event {
	if membership, ok := s.noteOf(ctx, network, e); ok {
		return membershipEvent(e, membership)
	}
	return e
}

// slackNoteSQL is MembershipNote in SQL, for event u (an events alias) of a chat r (a rooms alias): the unread
// count must not count a note that is still stored as text. 1 for a note, else 0 or NULL. The checks run cheapest
// first (the network, the type, the two phrases as plain text), so only a message that says "has joined the" or "has
// left the" costs a JSON read or a look at its sender's name. (MembershipNote's "has joined|left the" phrases are
// all of the shapes in notePhrases.)
func slackNoteSQL(r, u string) string {
	c := u + ".content"
	jc := func(path string) string {
		return `(CASE WHEN json_valid(` + c + `) THEN json_extract(` + c + `, '` + path + `') END)`
	}
	space := `' ' || char(9) || char(10) || char(13)`
	name := `trim(pr.display_name, ` + space + `)`
	body := `trim(` + jc("$.body") + `, ` + space + `)`
	var forms []string
	for _, phrase := range slices.Sorted(maps.Keys(notePhrases)) { // sorted: the same statement every time
		forms = append(forms, name+` || '`+phrase+`'`)
	}
	return `(` + r + `.network = 'slack' AND ` + u + `.type = 'm.room.message' AND (instr(` + c + `, ' has joined the ') > 0 OR instr(` + c + `, ' has left the ') > 0)
       AND COALESCE(` + jc("$.msgtype") + `, '') IN ('', 'm.text', 'm.notice')
       AND (CASE WHEN json_valid(` + c + `) THEN json_type(` + c + `, '$."m.new_content"') END) IS NULL
       AND COALESCE(` + jc(`$."m.relates_to".rel_type`) + `, '') = ''
       AND EXISTS (SELECT 1 FROM profiles pr WHERE pr.user_id = ` + u + `.sender
                   AND length(` + name + `) BETWEEN 1 AND ` + "200" + `
                   AND ` + body + ` IN (` + strings.Join(forms, ", ") + `)))`
}
