// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"bytes"
	"encoding/json"
	"regexp"
	"slices"
	"strings"
)

// A call note is a bridge's notice of a call. The app says it in Courier's words, from what the engine reads here;
// the engine never shows or indexes the bridge's English body (as timer notes, Ruling 40). What the pinned bridges
// send (each a ghost's message, mine only when the network says I made the call):
//   - WhatsApp: m.text "Incoming call. Use the WhatsApp app to answer.", action {type: call}, call_type "" or
//     "group" (mautrix-whatsapp handlewhatsapp.go:583-635). Ringing; never voice or video.
//   - Signal: m.text (m.notice in a group) "Incoming call", action {type: call} (mautrix-signal handlesignal.go:98-109);
//     then, when it is over, m.notice "Call ended" with no action message (handlesignal.go:110-112).
//   - Telegram: m.notice "Started a call" / "Started a video call", action {type: call, call_type: voice|video}
//     (mautrix-telegram handletelegram.go:1610-1660); afterwards the call's record, m.notice "Call " or "Video call "
//     + missed|disconnected|ended|rejected [+ " (duration)"], with no action message, sent as the caller: me when I
//     called (handletelegram.go:471-508, 729-753); a group's video chat, m.notice "Started a video chat" / "Ended the
//     video chat (duration)", action {type: call, call_type: video} (handletelegram.go:513-540).
//   - Google Messages and Slack send nothing that tells a call by its shape; bridgev2 sends no call notice itself.
//
// So the engine reads each notice once, as it arrives (AnnotateCallNote, from localmatrix), and writes what it read
// into the content beside the bridge's: com.beeper.action_message {type: call} where the bridge left it out (so the
// two notices with none are action messages like the rest, never indexed), and callKey, what happened. From then on
// one rule says what a call note is: an action message of type call (parseCallNote; the app's CallNote.of). Migration
// 6 does the same, in SQL (annotateCallNoteSQL), to the notices already on disk.

// callActionType is the action message type of a call note.
const callActionType = "call"

// callKey is Courier's reading of a call note, in its content: {state, media} (CallNote).
const callKey = "fi.courier.call"

// CallState is what happened with a call, as Courier says it.
type CallState string

const (
	CallRinging  CallState = "ringing"  // it rang (someone called)
	CallStarted  CallState = "started"  // a group's call started
	CallMissed   CallState = "missed"   // no one answered
	CallEnded    CallState = "ended"    // it was answered, and is over (Signal: it is over, answered or not)
	CallDeclined CallState = "declined" // it was turned down
	CallDropped  CallState = "dropped"  // the connection was lost
)

// CallMedia is a call's kind: voice, video, or "" when the bridge doesn't say.
type CallMedia string

const (
	CallVoice CallMedia = "voice"
	CallVideo CallMedia = "video"
)

// CallNote is a call notice as Courier reads it.
type CallNote struct {
	State CallState `json:"state"`
	Media CallMedia `json:"media"`
}

func knownState(s CallState) bool {
	switch s {
	case CallRinging, CallStarted, CallMissed, CallEnded, CallDeclined, CallDropped:
		return true
	}
	return false
}

func knownMedia(m CallMedia) bool { return m == CallVoice || m == CallVideo }

// Telegram's own words, which decide only for its notices that have nothing else.
const (
	tgChatStartedBody = "Started a video chat"
	tgChatEndedPrefix = "Ended the video chat ("
	signalEndedBody   = "Call ended"
)

// tgRecordOutcomes is Telegram's call record's reason word, and what Courier calls it (handletelegram.go:478-489).
var tgRecordOutcomes = []struct {
	word  string
	state CallState
}{{"missed", CallMissed}, {"disconnected", CallDropped}, {"ended", CallEnded}, {"rejected", CallDeclined}}

// tgRecordRE is Telegram's call record: "Call " or "Video call ", the reason, and " (duration)" when it lasted.
var tgRecordRE = regexp.MustCompile(`(?s)^(Video call|Call) (missed|disconnected|ended|rejected)(?: \(.*\))?$`)

// AnnotateCallNote reads content, a message from network's bridge, as a call note: when it is one, it is returned
// with Courier's reading added (see above); anything else, and a note already read, comes back exactly as given.
// (SQL twin: annotateCallNoteSQL.)
func AnnotateCallNote(network, typ string, content json.RawMessage) json.RawMessage {
	if typ != "m.room.message" || !bytes.Contains(content, []byte("all")) {
		return content
	}
	var c map[string]json.RawMessage
	if json.Unmarshal(content, &c) != nil || c == nil {
		return content
	}
	if _, read := c[callKey]; read {
		return content
	}
	var shape struct {
		MsgType string `json:"msgtype"`
		Body    string `json:"body"`
	}
	_ = json.Unmarshal(content, &shape)
	note, action, ok := readCallNotice(network, shape.MsgType, shape.Body, c[actionMessageKey])
	if !ok {
		return content
	}
	if action != nil {
		c[actionMessageKey] = action
	}
	c[callKey], _ = json.Marshal(note)
	out, err := json.Marshal(c)
	if err != nil {
		return content
	}
	return out
}

// readCallNotice says whether a message of network's bridge (its msgtype, body and action message, if it has one)
// is a call notice, and what it says. action is the action message to add, for a notice that came with none.
func readCallNotice(network, msgType, body string, rawAction json.RawMessage) (note CallNote, action json.RawMessage, ok bool) {
	if rawAction != nil {
		var a map[string]json.RawMessage
		if json.Unmarshal(rawAction, &a) != nil || a == nil {
			return CallNote{}, nil, false // an action message that isn't one: not the bridge's notice
		}
		var typ, callType string
		_ = json.Unmarshal(a["type"], &typ)
		if typ != callActionType {
			return CallNote{}, nil, false
		}
		_ = json.Unmarshal(a["call_type"], &callType)
		note = CallNote{State: CallRinging}
		if m := CallMedia(callType); knownMedia(m) {
			note.Media = m
		}
		if network == "telegram" {
			switch {
			case body == tgChatStartedBody:
				note.State = CallStarted
			case strings.HasPrefix(body, tgChatEndedPrefix) && strings.HasSuffix(body, ")"):
				note.State = CallEnded
			}
		}
		return note, nil, true
	}
	if msgType != "m.notice" {
		return CallNote{}, nil, false
	}
	switch network {
	case "signal":
		if body == signalEndedBody {
			return CallNote{State: CallEnded}, json.RawMessage(`{"type":"call"}`), true
		}
	case "telegram":
		if m := tgRecordRE.FindStringSubmatch(body); m != nil {
			note.Media = CallVoice
			if m[1] == "Video call" {
				note.Media = CallVideo
			}
			for _, o := range tgRecordOutcomes {
				if o.word == m[2] {
					note.State = o.state
				}
			}
			return note, json.RawMessage(`{"type":"call"}`), true
		}
	}
	return CallNote{}, nil, false
}

// sqlString is s as an SQL string literal.
func sqlString(s string) string { return `'` + strings.ReplaceAll(s, `'`, `''`) + `'` }

// annotateCallNoteSQL is AnnotateCallNote in SQL, for migration 6: the content of an m.room.message with Courier's
// reading added when it is a call notice, else the content as it is. network and content are SQL expressions.
func annotateCallNoteSQL(network, content string) string {
	valid := `json_valid(` + content + `)`
	field := func(path string) string {
		return `(CASE WHEN ` + valid + ` THEN json_extract(` + content + `, '$.` + path + `') END)`
	}
	action := `(CASE WHEN ` + valid + ` THEN json_type(` + content + `, '$."` + actionMessageKey + `"') END)`
	actionType := field(`"` + actionMessageKey + `".type`)
	callType := field(`"` + actionMessageKey + `".call_type`)
	read := `(CASE WHEN ` + valid + ` THEN json_type(` + content + `, '$."` + callKey + `"') END)`
	body, msgType := field("body"), field("msgtype")
	note := func(state, media string) string {
		return `json_object('state', ` + state + `, 'media', ` + media + `)`
	}
	withNote := func(n string) string {
		return `json_set(` + content + `, '$."` + callKey + `"', json(` + n + `))`
	}
	withActionAndNote := func(n string) string {
		return `json_set(` + content + `, '$."` + actionMessageKey + `"', json('{"type":"call"}'), '$."` + callKey + `"', json(` + n + `))`
	}
	media := `(CASE WHEN ` + callType + ` IN ('voice', 'video') THEN ` + callType + ` ELSE '' END)`
	actionState := `(CASE WHEN ` + network + ` = 'telegram' AND ` + body + ` = ` + sqlString(tgChatStartedBody) + ` THEN 'started'
  WHEN ` + network + ` = 'telegram' AND ` + body + ` GLOB ` + sqlString(globEscape(tgChatEndedPrefix)+"*)") + ` THEN 'ended'
  ELSE 'ringing' END)`
	var record strings.Builder
	for _, prefix := range []struct{ words, media string }{{"Call", "voice"}, {"Video call", "video"}} {
		for _, o := range tgRecordOutcomes {
			words := prefix.words + " " + o.word
			record.WriteString(`
  WHEN ` + network + ` = 'telegram' AND ` + msgType + ` = 'm.notice' AND ` + action + ` IS NULL AND (` + body + ` = ` + sqlString(words) +
				` OR ` + body + ` GLOB ` + sqlString(globEscape(words+" (")+"*)") + `) THEN ` +
				withActionAndNote(note(sqlString(string(o.state)), sqlString(prefix.media))))
		}
	}
	return `(CASE WHEN NOT ` + valid + ` OR ` + read + ` IS NOT NULL THEN ` + content + `
  WHEN ` + action + ` = 'object' THEN (CASE WHEN ` + actionType + ` = 'call' THEN ` + withNote(note(actionState, media)) + ` ELSE ` + content + ` END)
  WHEN ` + network + ` = 'signal' AND ` + msgType + ` = 'm.notice' AND ` + action + ` IS NULL AND ` + body + ` = ` + sqlString(signalEndedBody) + `
    THEN ` + withActionAndNote(note("'ended'", "''")) + record.String() + `
  ELSE ` + content + ` END)`
}

// globEscape makes s match itself in a GLOB pattern.
func globEscape(s string) string {
	r := strings.NewReplacer("*", "[*]", "?", "[?]", "[", "[[]")
	return r.Replace(s)
}

// parseCallNote reads a call note: an m.room.message whose action message is of type call. What happened is
// Courier's reading (callKey); a note without one (stored before this engine read call notices) rang, voice or video
// as its call_type says. A state or media this engine doesn't know reads as ringing, no media. ok is false for
// anything else. (The app's twin: CallNote.of.)
func parseCallNote(typ string, content json.RawMessage) (CallNote, bool) {
	// Every chat's newest is asked when the inbox is read: most never mention the type, and need no parse.
	if typ != "m.room.message" || !bytes.Contains(content, []byte(`"call"`)) {
		return CallNote{}, false
	}
	var c struct {
		Action *struct {
			Type     string `json:"type"`
			CallType string `json:"call_type"`
		} `json:"com.beeper.action_message"`
		Note json.RawMessage `json:"fi.courier.call"`
	}
	if json.Unmarshal(content, &c) != nil || c.Action == nil || c.Action.Type != callActionType {
		return CallNote{}, false
	}
	// Courier's reading, when it is an object: each field a string this engine knows, or the plainest.
	var read map[string]json.RawMessage
	if json.Unmarshal(c.Note, &read) != nil || read == nil {
		note := CallNote{State: CallRinging}
		if m := CallMedia(c.Action.CallType); knownMedia(m) {
			note.Media = m
		}
		return note, true
	}
	var state, media string
	_ = json.Unmarshal(read["state"], &state)
	_ = json.Unmarshal(read["media"], &media)
	note := CallNote{State: CallState(state), Media: CallMedia(media)}
	if !knownState(note.State) {
		note.State = CallRinging
	}
	if !knownMedia(note.Media) {
		note.Media = ""
	}
	return note, true
}

// The call states that are a record of a call, not news: it ended, was declined or dropped. A call that rang (or a
// group's call that started) and one that was missed are news: they count unread, notify, bring an archived chat
// back and cancel a scheduled message "if no reply", as a message does. A call I made never counts, as nothing of
// mine does. (The app's twin: CallNote.isNews.)
var callRecordStates = []CallState{CallEnded, CallDeclined, CallDropped}

// isCallRecord reports whether e is a call note that is a record, not news (callRecordStates). (SQL twin:
// isCallRecordSQL.)
func isCallRecord(e Event) bool {
	note, ok := parseCallNote(e.Type, e.Content)
	return ok && slices.Contains(callRecordStates, note.State)
}

// isCallRecordSQL is true for content that is a call note that is a record, not news: its action message is of type
// call and Courier's reading says ended, declined or dropped. content is the column expression. (Go twin:
// isCallRecord; a state this engine doesn't know reads as ringing there, and is not one of these here.)
func isCallRecordSQL(content string) string {
	states := make([]string, len(callRecordStates))
	for i, st := range callRecordStates {
		states[i] = sqlString(string(st))
	}
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."` + actionMessageKey + `".type') = '` +
		callActionType + `' AND json_extract(` + content + `, '$."` + callKey + `".state') IN (` + strings.Join(states, ", ") + `) END)`
}

// isCallNewsSQL is true for content that is a call note that is news: a call note (its action message is of type
// call) that isn't a record (isCallRecordSQL). content is the column expression.
func isCallNewsSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."` + actionMessageKey + `".type') = '` +
		callActionType + `' AND (` + isCallRecordSQL(content) + `) IS NOT 1 END)`
}

// isCallNote reports whether e is a call note.
func isCallNote(e Event) bool {
	_, ok := parseCallNote(e.Type, e.Content)
	return ok
}

// IsCallNote reports whether e is a bridge's call note: a note of a call, no words of anyone's to edit, unsend or
// forward.
func IsCallNote(e Event) bool { return isCallNote(e) }
