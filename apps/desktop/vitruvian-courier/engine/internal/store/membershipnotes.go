// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"maps"
	"slices"
	"strconv"
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
// quoted line, or a longer message stays a message. The one exception is my own note: the app's own user has no
// profile name, so my note counts when it is a plain name (no sentence punctuation) and nothing else.
//
// A sender renamed since the note was stored no longer matches, so the old note stays an ordinary message; it is
// still never unread once the chat's read marker is past it. MembershipNote is the one rule; slackNoteSQL is its twin for the
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

// The members of a note's content that decide whether it is one. SQLite's json_extract, which the unread count
// uses, reads exact-case keys and the first of a repeated key; an event that makes the two readings differ (a key
// repeated, a key in another case, a relation that is not an object) is never a note, on either side.
var noteKeys = []string{"body", "msgtype", "m.relates_to", "m.new_content"}

// asciiFold lowercases ASCII only, as SQLite's lower() does.
func asciiFold(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= 'A' && r <= 'Z' {
			return r + 'a' - 'A'
		}
		return r
	}, s)
}

// jsonMembers lists the members of raw, a single JSON object, in order, repeated keys kept. ok is false for
// anything else.
func jsonMembers(raw []byte) (keys []string, vals []json.RawMessage, ok bool) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	if t, err := dec.Token(); err != nil || t != json.Delim('{') {
		return nil, nil, false
	}
	for dec.More() {
		t, err := dec.Token()
		key, isKey := t.(string)
		if err != nil || !isKey {
			return nil, nil, false
		}
		var v json.RawMessage
		if dec.Decode(&v) != nil {
			return nil, nil, false
		}
		keys, vals = append(keys, key), append(vals, v)
	}
	if t, err := dec.Token(); err != nil || t != json.Delim('}') {
		return nil, nil, false
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, nil, false
	}
	return keys, vals, true
}

// noteMember is the first member called key (exact case) of an object's members.
func noteMember(keys []string, vals []json.RawMessage, key string) (json.RawMessage, bool) {
	if i := slices.Index(keys, key); i >= 0 {
		return vals[i], true
	}
	return nil, false
}

// noteShape reads content as the parts of a Slack note that are not the name: its body. ok is false for an event
// that is not a plain text message of the kind a note is (an edit, a thread reply, another message type), or that
// reads differently in SQL (see noteKeys).
func noteShape(content json.RawMessage) (body string, ok bool) {
	keys, vals, ok := jsonMembers(content)
	if !ok {
		return "", false
	}
	for _, k := range keys {
		for _, want := range noteKeys {
			if k != want && asciiFold(k) == want {
				return "", false // a key in another case
			}
		}
	}
	for _, want := range noteKeys {
		n := 0
		for _, k := range keys {
			if k == want {
				n++
			}
		}
		if n > 1 {
			return "", false // a repeated key
		}
	}
	if _, edit := noteMember(keys, vals, "m.new_content"); edit {
		return "", false
	}
	if raw, found := noteMember(keys, vals, "msgtype"); found && string(raw) != "null" {
		var mt string
		if json.Unmarshal(raw, &mt) != nil || (mt != "" && mt != "m.text" && mt != "m.notice") {
			return "", false
		}
	}
	if raw, found := noteMember(keys, vals, "m.relates_to"); found {
		rk, rv, isObj := jsonMembers(raw)
		if !isObj {
			return "", false // a relation that is not an object
		}
		if rt, has := noteMember(rk, rv, "rel_type"); has && string(rt) != "null" && string(rt) != `""` {
			return "", false // a thread reply, a replacement, a reaction...
		}
	}
	raw, found := noteMember(keys, vals, "body")
	if !found || json.Unmarshal(raw, &body) != nil {
		return "", false
	}
	return body, true
}

// plainNoteName is the name part of my own note: one line, no sentence punctuation, nothing to trim.
func plainNoteName(name string) bool {
	n := utf8.RuneCountInString(name)
	return n >= 1 && n <= maxNoteNameRunes && name == strings.Trim(name, noteSpace) &&
		!strings.ContainsAny(name, ".!?:;,>\n\r")
}

// MembershipNote reads content, an m.room.message from network's bridge sent by sender, whose name is senderName,
// as that person joining or leaving the chat. membership is "join" or "leave"; ok is false for anything else:
// another network, a sender with no name (but me), a message that says more or less than Slack's note, an edit or
// a thread reply.
func MembershipNote(network, typ string, content json.RawMessage, sender, senderName string) (membership string, ok bool) {
	if network != "slack" || !couldBeMembershipNote(typ, content) {
		return "", false
	}
	body, ok := noteShape(content)
	if !ok {
		return "", false
	}
	body = strings.Trim(body, noteSpace)
	name := strings.Trim(senderName, noteSpace)
	if name == "" && sender == myID {
		for phrase, membership := range notePhrases {
			if who, found := strings.CutSuffix(body, phrase); found && plainNoteName(who) {
				return membership, true
			}
		}
		return "", false
	}
	if n := utf8.RuneCountInString(name); n < 1 || n > maxNoteNameRunes {
		return "", false
	}
	rest, found := strings.CutPrefix(body, name)
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
	return MembershipNote(network, e.Type, e.Content, e.Sender, s.senderName(ctx, e.Sender))
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

// served is e as the app should see it: see serveAll.
func (s *Store) served(ctx context.Context, e Event) Event {
	if !couldBeMembershipNote(e.Type, e.Content) {
		return e
	}
	return s.serveAll(ctx, []Event{e})[0]
}

// serveAll is evs as the app should see them. A Slack join or leave note that was stored as a text message, before
// the engine stored them as membership events, is turned into the membership event it is, so history already on disk
// shows as the centered membership row too. Every other event comes back as given. The cheap content test comes
// first: only a matching message costs a look at its chat's network and its sender's name, each looked up once per
// call. Call it with no rows open: it queries.
func (s *Store) serveAll(ctx context.Context, evs []Event) []Event {
	var networks, names map[string]string
	for i, e := range evs {
		if !couldBeMembershipNote(e.Type, e.Content) {
			continue
		}
		if networks == nil {
			networks, names = map[string]string{}, map[string]string{}
		}
		network, seen := networks[e.RoomID]
		if !seen {
			_ = s.db.QueryRow(ctx, "SELECT network FROM rooms WHERE room_id=$1", e.RoomID).Scan(&network)
			networks[e.RoomID] = network
		}
		if network != "slack" {
			continue
		}
		name, seen := names[e.Sender]
		if !seen {
			name = s.senderName(ctx, e.Sender)
			names[e.Sender] = name
		}
		if membership, ok := MembershipNote(network, e.Type, e.Content, e.Sender, name); ok {
			evs[i] = membershipEvent(e, membership)
		}
	}
	return evs
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
// left the" costs a JSON read or a look at its sender's name.
func slackNoteSQL(r, u string) string {
	c := u + ".content"
	jc := func(path string) string {
		return `(CASE WHEN json_valid(` + c + `) THEN json_extract(` + c + `, '` + path + `') END)`
	}
	space := `' ' || char(9) || char(10) || char(13)`
	members := `json_each(CASE WHEN json_valid(` + c + `) THEN ` + c + ` ELSE '{}' END)`
	var keyList []string
	for _, k := range noteKeys {
		keyList = append(keyList, "'"+k+"'")
	}
	keys := strings.Join(keyList, ", ")
	var once []string // each key at most once (no GROUP BY: the inbox must stay free of temp tables)
	for _, k := range keyList {
		once = append(once, `(SELECT count(*) FROM `+members+` WHERE key = `+k+`) <= 1`)
	}
	body := `trim(` + jc("$.body") + `, ` + space + `)`
	name := `trim(pr.display_name, ` + space + `)`
	var forms, mine []string
	for _, phrase := range slices.Sorted(maps.Keys(notePhrases)) { // sorted: the same statement every time
		forms = append(forms, name+` || '`+phrase+`'`)
		n := utf8.RuneCountInString(phrase)
		who := `substr(` + body + `, 1, length(` + body + `) - ` + itoa(n) + `)`
		mine = append(mine, `(substr(`+body+`, -`+itoa(n)+`) = '`+phrase+`' AND length(`+who+`) BETWEEN 1 AND 200
         AND `+who+` = trim(`+who+`, `+space+`) AND `+who+` NOT GLOB '*[.!?:;,>]*'
         AND instr(`+who+`, char(10)) = 0 AND instr(`+who+`, char(13)) = 0)`)
	}
	return `(` + r + `.network = 'slack' AND ` + u + `.type = 'm.room.message'
       AND (instr(` + c + `, ' has joined the ') > 0 OR instr(` + c + `, ' has left the ') > 0)
       AND json_valid(` + c + `)
       AND ` + strings.Join(once, "\n       AND ") + `
       AND NOT EXISTS (SELECT 1 FROM ` + members + ` WHERE lower(key) IN (` + keys + `) AND key NOT IN (` + keys + `))
       AND COALESCE(` + jc("$.msgtype") + `, '') IN ('', 'm.text', 'm.notice')
       AND (CASE WHEN json_valid(` + c + `) THEN json_type(` + c + `, '$."m.new_content"') END) IS NULL
       AND COALESCE(CASE WHEN json_valid(` + c + `) THEN json_type(` + c + `, '$."m.relates_to"') END, 'object') = 'object'
       AND COALESCE(` + jc(`$."m.relates_to".rel_type`) + `, '') = ''
       AND (EXISTS (SELECT 1 FROM profiles pr WHERE pr.user_id = ` + u + `.sender
                    AND length(` + name + `) BETWEEN 1 AND 200
                    AND ` + body + ` IN (` + strings.Join(forms, ", ") + `))
            OR (` + u + `.sender = '` + myID + `'
                AND NOT EXISTS (SELECT 1 FROM profiles pr WHERE pr.user_id = ` + u + `.sender AND ` + name + ` <> '')
                AND (` + strings.Join(mine, " OR ") + `))))`
}

func itoa(n int) string { return strconv.Itoa(n) }
