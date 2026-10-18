// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"

	"github.com/rs/zerolog"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
)

// The search index (migration 4) is three contentless FTS5 tables. Each row holds the normalised text a person
// would search for and a scope column of filter tokens; the text itself stays in events, rooms, profiles and
// members, which is where snippets are cut from. Every write that changes searchable text re-writes its doc in the
// same transaction, and the triggers of migration 4 take a doc out when what it came from is deleted or redacted.
// Nothing here logs text, names or queries: counts only.

// docsPerMillisecond is how many messages one millisecond can hold in the index: a message's doc id is
// ts_ms << 10 | n with n in 0..1023.
const docsPerMillisecond = 1 << 10

// maxDocTS is the latest ts (ms) whose doc ids still fit in an int64.
const maxDocTS = int64(1)<<53 - 1

// docIDsInMillisecondSQL finds the highest doc id taken in one millisecond's range ($1..$2), through events_doc.
const docIDsInMillisecondSQL = `SELECT MAX(doc_id) FROM events WHERE doc_id BETWEEN $1 AND $2`

// currentEditSQL lists the live edits of message $1 sent by $2, newest first, through events_edits. The room is
// checked in Go so that nothing tempts the planner onto events_room_ts instead.
var currentEditSQL = `SELECT room_id, content FROM events
WHERE ` + editTargetSQL("content") + ` = $1 AND type = 'm.room.message' AND ` + isEditSQL("content") + `
  AND sender = $2 AND redacted = 0
ORDER BY ts DESC, seq DESC`

// earlierRedactionSQL marks event $1 of chat $2 deleted when a redaction of it arrived before it did, through
// events_redacts. It is the in-order redaction's flag, set late: the timeline hides the text by the redaction
// event either way, and nothing else of the row changes.
var earlierRedactionSQL = `UPDATE events SET redacted = 1 WHERE event_id = $1 AND EXISTS (
  SELECT 1 FROM events r WHERE r.type = 'm.room.redaction' AND r.status <> 'failed' AND r.room_id = $2
    AND ` + redactionTargetSQL("r.content") + ` = $1)`

// scopeHash is the 16 hex digits that stand for an ID in a scope token: plain lowercase ASCII, so the tokenizer
// keeps it whole, and the same length whatever the ID.
func scopeHash(prefix, id string) string {
	sum := sha256.Sum256([]byte(id))
	return prefix + hex.EncodeToString(sum[:8])
}

// RoomScope is the scope token of the messages of a chat.
func RoomScope(roomID string) string { return scopeHash("r", roomID) }

// SenderScope is the scope token of the messages someone sent.
func SenderScope(userID string) string { return scopeHash("s", userID) }

// NetworkScope is the scope token of a network's messages, chats and people: n and the network's name in
// lowercase ASCII letters and digits only, so the tokenizer never splits it.
func NetworkScope(network string) string {
	var b strings.Builder
	b.WriteByte('n')
	for _, r := range strings.ToLower(network) {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// cutRunes is s cut to at most n runes.
func cutRunes(s string, n int) string {
	if len(s) <= n { // a string of at most n bytes has at most n runes
		return s
	}
	i := 0
	for pos := range s {
		if i == n {
			return s[:pos]
		}
		i++
	}
	return s
}

// indexable is the text an index row holds: exactly what queries are matched against.
func indexable(text string) string {
	return cutRunes(searchtext.Normalize(text), searchtext.MaxIndexRunes)
}

// MessageText is an event's own searchable text (its body, reply fallback cut, at most MaxIndexRunes) and its
// kind. ok is false for anything that isn't indexed. Edits are not applied here.
//
// The kinds are text (also notices, emotes and any other msgtype), image, video, audio, file and sticker. An
// image's or file's body is its caption or its file name, and is indexed like any text.
func MessageText(typ string, content json.RawMessage) (text, kind string, ok bool) {
	if typ != "m.room.message" && typ != "m.sticker" {
		return "", "", false
	}
	var c struct {
		Body      string          `json:"body"`
		MsgType   string          `json:"msgtype"`
		RelatesTo json.RawMessage `json:"m.relates_to"`
	}
	if json.Unmarshal(content, &c) != nil || isEdit(content) {
		return "", "", false
	}
	kind = "text"
	if typ == "m.sticker" {
		kind = "sticker"
	} else {
		switch c.MsgType {
		case "m.image":
			kind = "image"
		case "m.video":
			kind = "video"
		case "m.audio":
			kind = "audio"
		case "m.file":
			kind = "file"
		}
	}
	text = c.Body
	if isReply(c.RelatesTo) {
		text = cutReplyFallback(text)
	}
	return cutRunes(text, searchtext.MaxIndexRunes), kind, true
}

// isReply reports whether m.relates_to carries m.in_reply_to.
func isReply(relatesTo json.RawMessage) bool {
	var r struct {
		InReplyTo json.RawMessage `json:"m.in_reply_to"`
	}
	return json.Unmarshal(relatesTo, &r) == nil && len(r.InReplyTo) > 0 && string(r.InReplyTo) != "null"
}

// cutReplyFallback removes the Matrix reply fallback from a reply's body: the leading "> " lines that quote the
// message replied to, and the blank line after them. Quoted lines that no blank line follows are left alone,
// because then they aren't a fallback but something the person wrote.
func cutReplyFallback(body string) string {
	rest := body
	quoted := false
	for {
		line, after, found := strings.Cut(rest, "\n")
		if !found || !(strings.HasPrefix(line, "> ") || line == ">") {
			if quoted && found && line == "" {
				return after
			}
			return body
		}
		quoted, rest = true, after
	}
}

// newContentBody is the text an edit gives its message: m.new_content.body. ok is false when the edit carries no
// new body.
func newContentBody(content json.RawMessage) (string, bool) {
	var c struct {
		NewContent *struct {
			Body *string `json:"body"`
		} `json:"m.new_content"`
	}
	if json.Unmarshal(content, &c) != nil || c.NewContent == nil || c.NewContent.Body == nil {
		return "", false
	}
	return cutRunes(*c.NewContent.Body, searchtext.MaxIndexRunes), true
}

// CurrentText is the text as it reads now: the m.new_content.body of the newest edit from the same sender
// (looked up through events_edits), else MessageText. A redacted edit no longer counts, so redacting the newest
// edit puts back the one before it.
func (s *Store) CurrentText(ctx context.Context, e Event) (string, error) {
	rows, err := s.db.Query(ctx, currentEditSQL, e.EventID, e.Sender)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	for rows.Next() {
		var roomID, content string
		if err := rows.Scan(&roomID, &content); err != nil {
			return "", err
		}
		if roomID != e.RoomID {
			continue
		}
		if body, ok := newContentBody(json.RawMessage(content)); ok {
			return body, nil
		}
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	text, _, _ := MessageText(e.Type, e.Content)
	return text, nil
}

// messageScope is the scope column of a message's doc: everything search can filter messages on.
func messageScope(e Event, network, kind, text string) string {
	tokens := []string{"all", RoomScope(e.RoomID), SenderScope(e.Sender)}
	if e.Sender == string(ids.Me) {
		tokens = append(tokens, "me")
	}
	tokens = append(tokens, NetworkScope(network), "k"+kind)
	if lower := strings.ToLower(text); strings.Contains(lower, "http://") || strings.Contains(lower, "https://") {
		tokens = append(tokens, "klink")
	}
	return strings.Join(tokens, " ")
}

// roomNetwork is the network a chat is on.
func (s *Store) roomNetwork(ctx context.Context, roomID string) (string, error) {
	var network string
	err := s.db.QueryRow(ctx, "SELECT network FROM rooms WHERE room_id=$1", roomID).Scan(&network)
	return network, err
}

// writeMessageDoc (re-)writes the doc of message e under docID, with its current text.
func (s *Store) writeMessageDoc(ctx context.Context, e Event, docID int64, kind string) error {
	text, err := s.CurrentText(ctx, e)
	if err != nil {
		return err
	}
	network, err := s.roomNetwork(ctx, e.RoomID)
	if err != nil {
		return err
	}
	if _, err = s.db.Exec(ctx, "DELETE FROM search_messages WHERE rowid=$1", docID); err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, "INSERT INTO search_messages (rowid, body, scope) VALUES ($1, $2, $3)",
		docID, indexable(text), messageScope(e, network, kind, text))
	return err
}

// indexEvent indexes e, inside InsertEvent's transaction (or the backfill's). A message gets a doc with the text
// it reads as now, so an edit that arrived before it already counts; an edit re-indexes the message it replaces;
// anything else, and a message that is redacted or already indexed, is left as it is.
//
// The doc id is ts_ms << 10 | n, with n the first value above those already taken in that millisecond: doc-id
// order is time order, so FTS5 yields the newest match first without sorting. A negative ts counts as 0. A
// millisecond with all 1,024 doc ids taken leaves the message out of the index, with a warning.
func (s *Store) indexEvent(ctx context.Context, e Event) error {
	if isEdit(e.Content) {
		return s.applyEdit(ctx, e)
	}
	_, kind, ok := MessageText(e.Type, e.Content)
	if !ok {
		return nil
	}
	var stored sql.NullInt64
	var redacted bool
	err := s.db.QueryRow(ctx, "SELECT doc_id, redacted FROM events WHERE event_id=$1", e.EventID).Scan(&stored, &redacted)
	if errors.Is(err, sql.ErrNoRows) || err == nil && (stored.Valid || redacted) {
		return nil
	}
	if err != nil {
		return err
	}
	ts := min(max(e.TS.UnixMilli(), 0), maxDocTS)
	first := ts << 10
	var taken sql.NullInt64
	if err = s.db.QueryRow(ctx, docIDsInMillisecondSQL, first, first|(docsPerMillisecond-1)).Scan(&taken); err != nil {
		return err
	}
	docID := first
	if taken.Valid {
		if taken.Int64 == first|(docsPerMillisecond-1) {
			zerolog.Ctx(ctx).Warn().Int("per_millisecond", docsPerMillisecond).
				Msg("Search index: a millisecond already holds the most messages it can; one message is not indexed")
			return nil
		}
		docID = taken.Int64 + 1
	}
	if _, err = s.db.Exec(ctx, "UPDATE events SET doc_id=$2 WHERE event_id=$1", e.EventID, docID); err != nil {
		return err
	}
	return s.writeMessageDoc(ctx, e, docID, kind)
}

// applyEdit re-indexes the edit's target, if indexed, with the text its newest live edit from the same sender
// gives it. It runs when an edit arrives (an older edit arriving late leaves the newer one's text, because
// CurrentText always picks the newest) and when an edit is redacted or discarded (the one before it comes back).
// A target that isn't indexed (not here yet, redacted, or waiting for the backfill) takes its edits into account
// when it is indexed.
func (s *Store) applyEdit(ctx context.Context, edit Event) error {
	var rel struct {
		RelatesTo struct {
			EventID string `json:"event_id"`
		} `json:"m.relates_to"`
	}
	if json.Unmarshal(edit.Content, &rel) != nil || rel.RelatesTo.EventID == "" {
		return nil
	}
	var docID int64
	err := s.db.QueryRow(ctx, "SELECT doc_id FROM events WHERE event_id=$1 AND doc_id IS NOT NULL", rel.RelatesTo.EventID).Scan(&docID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	target, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1", rel.RelatesTo.EventID))
	if err != nil {
		return err
	}
	if target.Sender != edit.Sender || target.RoomID != edit.RoomID {
		return nil // only the sender's own edits count
	}
	_, kind, ok := MessageText(target.Type, target.Content)
	if !ok {
		return nil
	}
	return s.writeMessageDoc(ctx, target, docID, kind)
}

// writeDoc (re-)writes the one doc a chat or a person has: docs is chat_docs or people_docs, keyCol its key
// column, fts the FTS5 table. An empty name removes the doc (and, through the table's trigger, its row).
func (s *Store) writeDoc(ctx context.Context, docs, keyCol, fts, key, name, scope string) error {
	if len(searchtext.Words(name)) == 0 {
		_, err := s.db.Exec(ctx, "DELETE FROM "+docs+" WHERE "+keyCol+"=$1", key)
		return err
	}
	if _, err := s.db.Exec(ctx, "INSERT INTO "+docs+" ("+keyCol+") VALUES ($1) ON CONFLICT("+keyCol+") DO NOTHING", key); err != nil {
		return err
	}
	var docID int64
	if err := s.db.QueryRow(ctx, "SELECT doc_id FROM "+docs+" WHERE "+keyCol+"=$1", key).Scan(&docID); err != nil {
		return err
	}
	if _, err := s.db.Exec(ctx, "DELETE FROM "+fts+" WHERE rowid=$1", docID); err != nil {
		return err
	}
	_, err := s.db.Exec(ctx, "INSERT INTO "+fts+" (rowid, name, scope) VALUES ($1, $2, $3)", docID, name, scope)
	return err
}

// indexChat re-writes r's doc from what the store now holds for it (UpsertRoom keeps a chat's network, so the
// stored row is the truth): its name, and the scope tokens all, its network, and dm or group.
func (s *Store) indexChat(ctx context.Context, r Room) error {
	var network, name string
	var direct bool
	err := s.db.QueryRow(ctx, "SELECT network, name, is_direct FROM rooms WHERE room_id=$1", r.ID).Scan(&network, &name, &direct)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	kind := "group"
	if direct {
		kind = "dm"
	}
	return s.writeDoc(ctx, "chat_docs", "room_id", "search_chats", r.ID, indexable(name),
		strings.Join([]string{"all", NetworkScope(network), kind}, " "))
}

// indexPerson re-writes userID's doc: their profile display name and every distinct name a chat they're in knows
// them by, with the scope tokens all and the network of each of those chats. A member row whose membership is
// leave or ban isn't being in that chat. I (@me) am never a person, and someone with no names left has no doc.
func (s *Store) indexPerson(ctx context.Context, userID string) error {
	if userID == string(ids.Me) {
		_, err := s.db.Exec(ctx, "DELETE FROM people_docs WHERE user_id=$1", userID)
		return err
	}
	var names []string
	seenName := map[string]bool{}
	addName := func(n string) {
		if n = indexable(n); len(searchtext.Words(n)) > 0 && !seenName[n] {
			seenName[n] = true
			names = append(names, n)
		}
	}
	var profileName string
	err := s.db.QueryRow(ctx, "SELECT display_name FROM profiles WHERE user_id=$1", userID).Scan(&profileName)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	addName(profileName)

	scope := []string{"all"}
	seenNetwork := map[string]bool{}
	rows, err := s.db.Query(ctx, `SELECT r.network, m.content FROM members m JOIN rooms r ON r.room_id = m.room_id
		WHERE m.user_id = $1 ORDER BY r.network, m.room_id`, userID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var network, content string
		if err := rows.Scan(&network, &content); err != nil {
			return err
		}
		var m struct {
			Membership  string `json:"membership"`
			DisplayName string `json:"displayname"`
		}
		_ = json.Unmarshal([]byte(content), &m) // a member row we can't read still says they're in the chat
		if m.Membership == "leave" || m.Membership == "ban" {
			continue
		}
		addName(m.DisplayName)
		if n := NetworkScope(network); !seenNetwork[n] {
			seenNetwork[n] = true
			scope = append(scope, n)
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	rows.Close()
	return s.writeDoc(ctx, "people_docs", "user_id", "search_people", userID,
		cutRunes(strings.Join(names, " "), searchtext.MaxIndexRunes), strings.Join(scope, " "))
}
