// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package logscrub keeps the engine's log from naming anyone ("never log who").
//
// Every network's bridge logs through the engine's logger, and bridgev2 and the connectors put the people and chats
// they are handling into their log context: a chat's portal_id (for a WhatsApp one-to-one chat, the contact's JID,
// which is their phone number), remote_sender.user_id on every remote event, ghost_id, a WhatsApp sender, pn (a phone
// number), lid, jid, login_id (WhatsApp's is my own number), room and event IDs, and IDs inside error strings and
// formatted messages. A Writer sits between the logger and its output and lets through only what can't name anyone.
//
// It is an allow-list, not a deny-list: a key nobody has looked at is dropped, so a bridge bump that adds one can't
// leak. Of the keys kept, every string is redacted: anything shaped like an identifier (Matrix user, room and event
// IDs, WhatsApp JIDs and LIDs, e-mail addresses, phone numbers, long digit runs, UUIDs, network IDs mixing letters and
// digits, a URL's path) and anything in double quotes becomes a fixed token. What is left is the level, the time, the
// network, the kind of thing and what went wrong: enough to tell what failed, never for whom.
package logscrub

import (
	"bytes"
	"encoding/json"
	"io"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// Tokens put in place of what is taken out.
const (
	ID     = "[id]"     // an identifier
	Quoted = "[quoted]" // text in double quotes: a value, a name or a message, whatever it looked like
	Path   = "[path]"   // a URL's path and query
)

// allowed is every key a line keeps, each one checked in the engine and the pinned bridge sources: its value is a
// fixed word, a number or a network's name, never a person, a chat or a message; and the free-text ones (message,
// error, panic, stack, caller) are redacted like every other string. Each key the engine itself logs is here.
var allowed = map[string]bool{
	// zerolog's own.
	"level":   true,
	"time":    true,
	"message": true,
	"error":   true, // kept, redacted: what went wrong is the reason the line exists (the alternative was dropping it)
	"caller":  true, // file:line, if a logger ever adds it
	// The bridges' fixed words: which network (host.go's "bridge"), which part of a bridge, what it was doing.
	"bridge":          true,
	"network":         true, // the engine's: localmatrix, outbox, typing, start-up
	"component":       true, // "typing updater", "backfill queue", "whatsmeow", the engine's "localmatrix"
	"sublogger":       true, // whatsmeow's module: "Socket", "Send", "Recv", "AppState", "QRChannel"
	"action":          true, // "handle remote event", "create matrix room"
	"subaction":       true, // "implicit read receipt", "thread backfill"
	"event_type":      true, // a Matrix event type: "m.room.message"
	"bridge_evt_type": true, // a bridgev2 remote event type: "RemoteEventMessage"
	"method":          true, // the engine's protocol method ("room.events"), an HTTP method, a connector's step
	"status":          true, // a message status ("fail"), a network's message status enum
	// The engine's own (cmd/courier-engine, rpc, actions, timers, search, store, host, engine).
	"change":           true, // a chat change's kind: "pin", "mute", "read", "accept", "typing"
	"waited":           true, // shutdown's bounded waits
	"retry_in":         true, // search backfill
	"batches":          true,
	"took_ms":          true,
	"messages":         true, // counts
	"chats":            true,
	"people":           true,
	"per_millisecond":  true, // the search index's limit
	"open_connections": true, // a bridge database still busy at Stop
	"panic":            true, // a recovered panic's value, redacted
	"stack":            true, // its goroutine's stack (no values, only pointers), redacted
}

// Limits on what one line can hold, so a huge value (a stack, an error quoting a whole request) can't make a line
// without end. Nothing is held between writes: each Write is scrubbed and passed on whole.
const (
	maxValue = 4 << 10  // bytes of any one string value, after redaction
	maxStack = 32 << 10 // bytes of a stack
	maxText  = 8 << 10  // bytes of a line that isn't JSON
)

// Writer is an io.Writer for a zerolog.Logger: each line written to it is scrubbed and then written to out.
// It is safe for concurrent use, and a line reaches out in one Write.
type Writer struct {
	mu  sync.Mutex
	out io.Writer
}

// New returns a Writer that writes the scrubbed lines to out.
func New(out io.Writer) *Writer { return &Writer{out: out} }

// Write scrubs the lines in p (zerolog writes one JSON object and a newline per call; a last line without a newline
// counts as a line) and writes what is left to out. It always reports all of p written: a write error on out loses
// those lines, and the next line is written as usual. Returning the error would only make zerolog print
// "zerolog: could not write event: <the error>" to os.Stderr itself, a line outside the log's format and this writer.
func (w *Writer) Write(p []byte) (int, error) {
	var buf bytes.Buffer
	for rest := p; len(rest) > 0; {
		line := rest
		if i := bytes.IndexByte(rest, '\n'); i >= 0 {
			line, rest = rest[:i], rest[i+1:]
		} else {
			rest = nil
		}
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		buf.Write(Line(line))
		buf.WriteByte('\n')
	}
	if buf.Len() > 0 {
		w.mu.Lock()
		_, _ = w.out.Write(buf.Bytes())
		w.mu.Unlock()
	}
	return len(p), nil
}

// unreadable stands in for a line that looked like JSON but couldn't be read: what it held can't be checked key by
// key, so none of it is kept.
var unreadable = []byte(`{"level":"warn","message":"a log line that couldn't be read was left out"}`)

// Line returns one log line (without its newline) scrubbed. A JSON object keeps the allowed keys, in their order, each
// string redacted; any other line is redacted as text.
func Line(line []byte) []byte {
	trimmed := bytes.TrimSpace(line)
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return []byte(cut(Redact(string(trimmed)), maxText))
	}
	out, ok := object(trimmed)
	if !ok {
		return unreadable
	}
	return out
}

// object scrubs a JSON object, keeping its allowed keys in their order. ok is false if line is not one JSON object.
func object(line []byte) (_ []byte, ok bool) {
	dec := json.NewDecoder(bytes.NewReader(line))
	dec.UseNumber()
	if tok, err := dec.Token(); err != nil || tok != json.Delim('{') {
		return nil, false
	}
	var out bytes.Buffer
	out.WriteByte('{')
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return nil, false
		}
		key, isKey := tok.(string)
		var raw json.RawMessage
		if err = dec.Decode(&raw); err != nil || !isKey {
			return nil, false
		}
		if !allowed[key] {
			continue
		}
		v, keep := value(key, raw)
		if !keep {
			continue
		}
		if out.Len() > 1 {
			out.WriteByte(',')
		}
		out.Write(encode(key))
		out.WriteByte(':')
		out.Write(v)
	}
	if tok, err := dec.Token(); err != nil || tok != json.Delim('}') {
		return nil, false
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, false // something after the object
	}
	out.WriteByte('}')
	return out.Bytes(), true
}

// counts are the allowed keys whose numbers are the engine's own counts and durations, kept however long they are.
var counts = map[string]bool{
	"waited": true, "retry_in": true, "batches": true, "took_ms": true, "messages": true, "chats": true, "people": true,
	"per_millisecond": true, "open_connections": true,
}

// digits counts the digits in s.
func digits(s string) int {
	n := 0
	for _, r := range s {
		if r >= '0' && r <= '9' {
			n++
		}
	}
	return n
}

// levels are zerolog's level names.
var levels = map[string]bool{
	"trace": true, "debug": true, "info": true, "warn": true, "error": true, "fatal": true, "panic": true,
}

// value is an allowed key's value as it is kept: a number or a boolean as it was, a string redacted (a level and a
// time only if they are one). Anything else (null, an object, an array: none of the allowed keys holds one) is dropped.
func value(key string, raw json.RawMessage) (_ []byte, keep bool) {
	switch raw[0] {
	case '"':
		var s string
		if json.Unmarshal(raw, &s) != nil {
			return nil, false
		}
		switch key {
		case "level":
			return raw, levels[s]
		case "time":
			_, err := time.Parse(time.RFC3339Nano, s)
			return raw, err == nil
		case "stack":
			return encode(cut(Redact(s), maxStack)), true
		}
		return encode(cut(Redact(s), maxValue)), true
	case 't', 'f':
		return raw, true // a boolean: Decode has checked it
	case '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
		// A number, which Decode has checked. One long enough to be an ID (a phone number, a Telegram user ID) under a
		// key that is not one of the engine's counts or durations is taken out.
		if !counts[key] && digits(string(raw)) >= 6 {
			return encode(ID), true
		}
		return raw, true
	}
	return nil, false
}

// encode is s as a JSON string, with <, > and & left as they are (as zerolog leaves them).
func encode(s string) []byte {
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(s) // a string always encodes
	return bytes.TrimSuffix(b.Bytes(), []byte("\n"))
}

// cut shortens s to at most n bytes, on a character boundary, marking the cut.
func cut(s string, n int) string {
	if len(s) <= n {
		return s
	}
	const mark = "…[cut]"
	i := n - len(mark)
	for i > 0 && !utf8.RuneStart(s[i]) {
		i--
	}
	return s[:i] + mark
}

var (
	// quotedRE is text in double quotes. Go's %q and most errors quote the value they are about.
	quotedRE = regexp.MustCompile(`"[^"\n]*"`)
	// urlRE is a URL; its scheme and host are kept, and the rest (paths and queries carry IDs) is not.
	urlRE = regexp.MustCompile(`\b([a-zA-Z][a-zA-Z0-9+.-]*)://([^/\s"'<>?#]*)([^\s"'<>]*)`)
	// rules are the shapes of identifiers, applied in order to a string after quotes and URLs; a rule with a check
	// replaces only the matches it accepts.
	rules = []rule{
		// A Matrix user, room, alias or community, with its server: @whatsapp_15551234567:courier.local, !abc:courier.local.
		{re: regexp.MustCompile(`[@!#+][^\s:"'<>,;()\[\]{}@]+:[A-Za-z0-9.-]*[A-Za-z0-9](?::\d+)?`)},
		// A Matrix event ID: $ and an opaque string, with a server in old room versions.
		{re: regexp.MustCompile(`\$[A-Za-z0-9+/_=-]{6,}(?::[A-Za-z0-9.-]*[A-Za-z0-9])?`)},
		// An address: an e-mail, a WhatsApp JID (15551234567@s.whatsapp.net, 15551234567:12@s.whatsapp.net, groups
		// @g.us) or LID (123456789012345@lid).
		{re: regexp.MustCompile(`[A-Za-z0-9._%+=:-]*[A-Za-z0-9_%+=-]@[A-Za-z0-9.-]*[A-Za-z0-9]`)},
		// A bare handle: a Telegram username, a Matrix localpart.
		{re: regexp.MustCompile(`@[A-Za-z0-9._=-]*[A-Za-z0-9_=]`)},
		// A UUID: a Signal ACI or PNI.
		{re: regexp.MustCompile(`[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`)},
		// A Slack team and user (or channel) pair, as the bridge makes a ghost's or a portal's ID of them
		// (slackid.MakeUserID lower-cases it), and a Slack ID alone: a letter for its kind and 8 to 10 more.
		{re: regexp.MustCompile(`\b[TtEe][A-Za-z0-9]{8,10}-[UuWwCcDdGgBb][A-Za-z0-9]{8,10}\b`), is: isSlackID},
		{re: regexp.MustCompile(`\b[UuWwTtCcDdGgBbEe][A-Za-z0-9]{8,10}\b`), is: isSlackID},
		// An international phone number, however it is written: +15551234567, +1 555-123-4567, +44 (20) 7946 0958.
		{re: regexp.MustCompile(`\+\d(?:[ ().-]{0,2}\d){5,14}`)},
		// A North American number written for people: (555) 123-4567, 555-123-4567, 555.123.4567.
		{re: regexp.MustCompile(`\(?\b\d{3}\)?[ .-]\d{3}[ .-]\d{4}\b`)},
		// A run of six digits or more: a phone number without its +, a Telegram user or chat ID, a WhatsApp LID.
		{re: regexp.MustCompile(`\d{6,}`)},
	}
	// tokenRE is a word that may be a network's opaque ID, kept or not by isID.
	tokenRE = regexp.MustCompile(`[A-Za-z0-9_+=]{8,}`)
)

// rule is one shape of identifier; is, if set, accepts or refuses each match.
type rule struct {
	re *regexp.Regexp
	is func(string) bool
}

// isSlackID accepts a Slack-ID-shaped match that has a digit and is in one case (Slack's IDs are upper case, and the
// bridge lower-cases the ones it makes a ghost's ID of). Without a digit it is a word: a bridge state (CONNECTED,
// CONNECTING) or a hyphenated pair. Slack IDs without any digit (USLACKBOT, Slack's own bot) are left: they are rare
// and name no person.
func isSlackID(m string) bool {
	return digits(m) > 0 && (strings.ToUpper(m) == m || strings.ToLower(m) == m)
}

// isID reports whether a word looks like an opaque ID rather than a word: letters and at least two digits (a Slack ID
// U0123ABCD, a WhatsApp message ID 3EB0C431D5A8, a hex pointer), or sixteen characters or more with a digit (a
// base64 or hex key). English words, Go identifiers and network names have no digits, or one ("bridgev2").
func isID(w string) bool {
	digits, letters := 0, 0
	for _, r := range w {
		switch {
		case r >= '0' && r <= '9':
			digits++
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z':
			letters++
		}
	}
	return letters > 0 && (digits >= 2 || (len(w) >= 16 && digits >= 1))
}

// Redact returns s with everything that could name someone replaced by a fixed token: text in double quotes becomes
// [quoted] (a quoted URL keeps its scheme and host), a URL's path [path], and every identifier-shaped string [id].
// What is left are the words around them: "Failed to get ghost [id]: [quoted] not found".
func Redact(s string) string {
	s = quotedRE.ReplaceAllStringFunc(s, func(q string) string {
		inner := q[1 : len(q)-1]
		if loc := urlRE.FindStringIndex(inner); loc != nil && loc[0] == 0 && loc[1] == len(inner) {
			return `"` + url(inner) + `"`
		}
		return Quoted
	})
	s = urlRE.ReplaceAllStringFunc(s, url)
	for _, r := range rules {
		if r.is == nil {
			s = r.re.ReplaceAllLiteralString(s, ID)
			continue
		}
		s = r.re.ReplaceAllStringFunc(s, func(m string) string {
			if r.is(m) {
				return ID
			}
			return m
		})
	}
	return tokenRE.ReplaceAllStringFunc(s, func(w string) string {
		if isID(w) {
			return ID
		}
		return w
	})
}

// url keeps a URL's scheme and the last two labels of its host (the service: "https://*.whatsapp.net", never a
// workspace's or a user's own subdomain), and puts [path] for anything after them.
func url(u string) string {
	m := urlRE.FindStringSubmatch(u)
	if m == nil {
		return u
	}
	scheme, host, rest := m[1], m[2], m[3]
	if i := strings.LastIndexByte(host, '@'); i >= 0 {
		host = host[i+1:] // user info: never kept
	}
	if i := strings.IndexByte(host, ':'); i >= 0 && !strings.Contains(host[i+1:], ":") {
		host = host[:i] // a port
	}
	if labels := strings.Split(host, "."); len(labels) > 2 && !isIP(host) {
		host = "*." + strings.Join(labels[len(labels)-2:], ".")
	}
	out := scheme + "://" + host
	if rest != "" && rest != "/" {
		out += "/" + Path
	}
	return out
}

// isIP reports whether host is a dotted IPv4 address.
func isIP(host string) bool {
	for _, r := range host {
		if r != '.' && (r < '0' || r > '9') {
			return false
		}
	}
	return true
}
