// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
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
