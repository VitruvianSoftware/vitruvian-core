// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"
)

// Slack tells a person joining or leaving a channel as a message: "<@U123> has joined the channel", with the
// subtype channel_join / channel_leave (group_join / group_leave in a private channel). The bridge keeps the words
// but not the subtype, so for Slack the engine reads the words (a person writing exactly that is as good as the
// same event) and stores the message as the membership change it is: the timeline shows a centered "Ann joined"
// line, not a bubble, and it is never unread, never notifies and never the chat's preview.

// slackMembershipRE is Slack's own wording: one line, a name, "has joined|left the channel|group|conversation".
var slackMembershipRE = regexp.MustCompile(`^.{1,200}? has (joined|left) the (?:channel|group|conversation)\.?$`)

// MembershipNote reads content, an m.room.message from network's bridge, as a person joining or leaving the chat.
// membership is "join" or "leave"; ok is false for anything else (and for every network but Slack).
func MembershipNote(network, typ string, content json.RawMessage) (membership string, ok bool) {
	if network != "slack" || typ != "m.room.message" || !strings.Contains(string(content), " has ") {
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
	m := slackMembershipRE.FindStringSubmatch(strings.TrimSpace(c.Body))
	if m == nil {
		return "", false
	}
	if m[1] == "joined" {
		return "join", true
	}
	return "leave", true
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
	membership, ok := MembershipNote("slack", e.Type, e.Content)
	if !ok {
		return e
	}
	var network string
	if s.db.QueryRow(ctx, "SELECT network FROM rooms WHERE room_id=$1", e.RoomID).Scan(&network) != nil || network != "slack" {
		return e
	}
	return membershipEvent(e, membership)
}

// slackNoteSQL is MembershipNote in SQL, for a Slack chat's event u (room alias r): the unread count and the
// preview must not count a note that is still stored as text. 1 for a note, else 0 or NULL.
func slackNoteSQL(r, content string) string {
	body := `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$.body') END)`
	var globs []string
	for _, verb := range []string{"joined", "left"} {
		for _, noun := range []string{"channel", "group", "conversation"} {
			globs = append(globs, body+` GLOB '* has `+verb+` the `+noun+`'`, body+` GLOB '* has `+verb+` the `+noun+`.'`)
		}
	}
	return `(` + r + `.network = 'slack' AND ` + content + ` LIKE '% has %' AND instr(` + body + `, char(10)) = 0
       AND (CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$.msgtype') END) IN ('m.text', 'm.notice')
       AND (CASE WHEN json_valid(` + content + `) THEN json_type(` + content + `, '$."m.new_content"') END) IS NULL
       AND (` + strings.Join(globs, " OR ") + `))`
}
