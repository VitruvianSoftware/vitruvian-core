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
	"fmt"
	"slices"
	"strings"
	"time"

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

// currentEditSQL lists the live edits of message $1 sent by $2, newest first, through events_edits: not redacted,
// and not failed (an edit the network refused never changed the message). The room is checked in Go so that nothing
// tempts the planner onto events_room_ts instead.
var currentEditSQL = `SELECT room_id, content FROM events
WHERE ` + editTargetSQL("content") + ` = $1 AND type = 'm.room.message' AND ` + isEditSQL("content") + `
  AND sender = $2 AND redacted = 0 AND status <> 'failed'
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

// indexable is the text an index row holds: exactly what queries are matched against. The text is cut at
// MaxIndexRunes of its own characters before it is normalised (Ruling 37): normalising puts a space around each
// character of a script written without spaces, so cutting afterwards would index only half as much Chinese,
// Japanese or Thai as any other text.
func indexable(text string) string {
	return searchtext.Normalize(cutRunes(text, searchtext.MaxIndexRunes))
}

// MessageText is an event's own searchable text (its body, reply fallback cut, at most MaxIndexRunes) and its
// kind. ok is false for anything that isn't indexed. Edits are not applied here.
//
// The kinds are text (also notices, emotes and any other msgtype), image, video, audio, file and sticker. An
// image's or file's body is its caption or its file name, and is indexed like any text. A poll is text: its
// question, then each option on its own line. An action message (com.beeper.action_message: a timer change, a call)
// is not indexed: its body is a bridge's English, not anyone's words (Ruling 40).
func MessageText(typ string, content json.RawMessage) (text, kind string, ok bool) {
	if typ == pollStartType {
		text, ok = pollText(content)
		if !ok {
			return "", "", false
		}
		return cutRunes(text, searchtext.MaxIndexRunes), "text", true
	}
	if typ != "m.room.message" && typ != "m.sticker" {
		return "", "", false
	}
	var c struct {
		Body      string          `json:"body"`
		MsgType   string          `json:"msgtype"`
		RelatesTo json.RawMessage `json:"m.relates_to"`
	}
	if json.Unmarshal(content, &c) != nil || isEdit(content) || isActionMessage(content) {
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
// (looked up through events_edits), else MessageText. A redacted or failed edit doesn't count, so redacting the
// newest edit, or the network refusing it, puts back the one before it.
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
	full, err := s.indexMessage(ctx, e)
	if full {
		zerolog.Ctx(ctx).Warn().Int("per_millisecond", docsPerMillisecond).
			Msg("Search index: a millisecond already holds the most messages it can; one message is not indexed")
	}
	return err
}

// indexMessage is indexEvent for a message that isn't an edit, without the warning: full reports that its
// millisecond had no doc id left, so it was left out. The backfill counts those and warns once per batch.
func (s *Store) indexMessage(ctx context.Context, e Event) (full bool, err error) {
	_, kind, ok := MessageText(e.Type, e.Content)
	if !ok {
		return false, nil
	}
	var stored sql.NullInt64
	var redacted bool
	err = s.db.QueryRow(ctx, "SELECT doc_id, redacted FROM events WHERE event_id=$1", e.EventID).Scan(&stored, &redacted)
	if errors.Is(err, sql.ErrNoRows) || err == nil && (stored.Valid || redacted) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	ts := min(max(e.TS.UnixMilli(), 0), maxDocTS)
	first := ts << 10
	var taken sql.NullInt64
	if err = s.db.QueryRow(ctx, docIDsInMillisecondSQL, first, first|(docsPerMillisecond-1)).Scan(&taken); err != nil {
		return false, err
	}
	docID := first
	if taken.Valid {
		if taken.Int64 == first|(docsPerMillisecond-1) {
			return true, nil
		}
		docID = taken.Int64 + 1
	}
	if _, err = s.db.Exec(ctx, "UPDATE events SET doc_id=$2 WHERE event_id=$1", e.EventID, docID); err != nil {
		return false, err
	}
	return false, s.writeMessageDoc(ctx, e, docID, kind)
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
	var network, localName, remoteName string
	var direct bool
	err := s.db.QueryRow(ctx, `SELECT r.network, COALESCE(p.local_name, ''), r.name, r.is_direct
		FROM rooms r LEFT JOIN room_prefs p ON p.room_id = r.room_id WHERE r.room_id=$1`, r.ID).Scan(&network, &localName, &remoteName, &direct)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	var names []string
	for _, n := range []string{localName, remoteName} {
		if n = indexable(n); len(searchtext.Words(n)) > 0 && !slices.Contains(names, n) {
			names = append(names, n)
		}
	}
	kind := "group"
	if direct {
		kind = "dm"
	}
	return s.writeDoc(ctx, "chat_docs", "room_id", "search_chats", r.ID, strings.Join(names, "\n"),
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

// The backfill indexes what was on disk when migration 4 ran, in the background and in batches. For each table it
// reads there is a range of rowids, after < rowid <= until, with both ends in search_state: until is where that
// table ended when migration 4 ran, and after is how far the backfill has got. Everything written later is indexed
// by the write itself (InsertEvent, UpsertRoom, SetProfile, SetMember), so until never moves and after only moves
// forward, in the same transaction as the docs it stands for: a batch cut off by a quit leaves nothing behind, and
// the next start carries on from after.
//
// The cursors are rowids, and rowids are only stable while the file is. After anything that may renumber them (a
// VACUUM, an export or import, a rekey that rewrites the database), set every *_after to 0 and every *_until to
// its table's highest rowid: the backfill passes over whatever already has its doc, so starting again from zero
// redoes nothing and misses nothing.

// BackfillTimeBudget is how long one backfill batch may take rows for. Once it is spent the batch stops taking
// rows, commits what it has indexed and leaves the rest to the next one, so a live write (a person's own send)
// waits at most about this long, however long the messages are. Every batch takes at least one row.
const BackfillTimeBudget = 50 * time.Millisecond

// backfillRange is one table's part of the backfill. index writes the docs that the rows with rowid in (from, to]
// need, inside the batch's transaction, leaving alone anything that already has its doc. It takes rows while b
// lets it; when it stops early, last is the rowid of the last row it took, else to.
type backfillRange struct {
	table, after, until string
	index               func(s *Store, ctx context.Context, b *backfillBatch, from, to int64) (last int64, stopped bool, err error)
}

// backfillRanges are taken in this order: chats and people first, because they are few and every search shows
// them, then the messages, oldest first.
var backfillRanges = []backfillRange{
	{"rooms", "chats_after", "chats_until", (*Store).backfillChats},
	{"profiles", "profiles_after", "profiles_until", (*Store).backfillProfiles},
	{"members", "members_after", "members_until", (*Store).backfillMembers},
	{"events", "backfill_after", "backfill_until", (*Store).backfillMessages},
}

// backfillBatch is one batch's time budget and what it has to report.
type backfillBatch struct {
	now      func() time.Time
	deadline time.Time
	took     bool // a row has been taken: the first one always is
	full     int  // messages left out because their millisecond had no doc id left
}

// take reports whether the batch may take another row: its first always, then while the budget lasts.
func (b *backfillBatch) take() bool {
	if !b.took {
		b.took = true
		return true
	}
	return b.now().Before(b.deadline)
}

// backfillNextSQL is where a batch of at most $3 rows of a table after the cursor $1 ends (never past $2): how many
// rows there are and the last one's rowid. %s is the table. It walks the rowid b-tree and nothing else.
const backfillNextSQL = `SELECT count(*), COALESCE(MAX(rowid), 0) FROM (
  SELECT rowid FROM %s WHERE rowid > $1 AND rowid <= $2 ORDER BY rowid LIMIT $3)`

// backfillMessagesSQL lists the events of rowid $1 < rowid <= $2 that could need a doc: messages, stickers and polls
// (the types MessageText indexes) that aren't deleted and have none yet. A deleted one is passed over, so a message
// whose redaction arrived first (migration 4's repair marked it) is never indexed.
var backfillMessagesSQL = `SELECT rowid, ` + eventCols + ` FROM events
WHERE rowid > $1 AND rowid <= $2 AND type IN ('m.room.message', 'm.sticker', '` + pollStartType + `') AND redacted = 0 AND doc_id IS NULL
ORDER BY rowid`

// BackfillSearch indexes up to batch things not yet indexed, in one transaction: first chats without a doc, then
// people without one (by their profile, then by their member rows), then events with backfill_after < rowid <=
// backfill_until (skipping redacted ones and those that already have a doc id), moving each range's after past
// what it read. Every row it reads counts toward batch, whether or not it needed a doc, and once
// BackfillTimeBudget is spent it stops taking rows and moves that range's after only to the last row it took; so
// a batch is short in rows and in time. done is true once nothing is left. Messages left out because their
// millisecond had no doc id left are counted in one warning for the batch.
//
// The transaction is BEGIN IMMEDIATE (sqlite.Open's _txlock=immediate), so it holds the write lock before it reads
// anything: a live InsertEvent waits for the batch, or the batch for it, and the two can never pick the same doc id
// in a millisecond. A write that has waited busy_timeout (5 s) fails with SQLITE_BUSY and changes nothing; the
// caller tries again later.
func (s *Store) BackfillSearch(ctx context.Context, batch int) (done bool, err error) {
	batch = max(batch, 1)
	var b *backfillBatch
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		// The budget counts from holding the lock, which is what live writes wait on.
		b = &backfillBatch{now: s.backfillNow}
		b.deadline = b.now().Add(s.backfillBudget)
		done = true
		left := batch
		for _, r := range backfillRanges {
			var after, until int64
			if err := s.db.QueryRow(ctx, `SELECT COALESCE((SELECT value FROM search_state WHERE key=$1), 0),
				COALESCE((SELECT value FROM search_state WHERE key=$2), 0)`, r.after, r.until).Scan(&after, &until); err != nil {
				return err
			}
			if after >= until {
				continue
			}
			if left == 0 {
				done = false
				continue
			}
			var n int
			var to int64
			if err := s.db.QueryRow(ctx, fmt.Sprintf(backfillNextSQL, r.table), after, until, left).Scan(&n, &to); err != nil {
				return err
			}
			if n < left {
				to = until // nothing more of this range is on disk
			} else if to < until {
				done = false
			}
			last, stopped, err := r.index(s, ctx, b, after, to)
			if err != nil {
				return err
			}
			if stopped {
				to, left, done = last, 0, false // out of time: the rest of this range, and the others, wait
			} else {
				left -= n
			}
			if _, err := s.db.Exec(ctx, "UPDATE search_state SET value=$2 WHERE key=$1", r.after, to); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return false, err
	}
	if b.full > 0 {
		zerolog.Ctx(ctx).Warn().Int("messages", b.full).Int("per_millisecond", docsPerMillisecond).
			Msg("Search index: some milliseconds already hold the most messages they can; these messages are not indexed")
	}
	return done, nil
}

// SearchComplete reports whether the backfill is done: backfill_after >= backfill_until, and no chat or person
// waits (every other range's after has reached its until). Until then search finds only part of the history.
func (s *Store) SearchComplete(ctx context.Context) (bool, error) {
	rows, err := s.db.Query(ctx, "SELECT key, value FROM search_state")
	if err != nil {
		return false, err
	}
	defer rows.Close()
	state := map[string]int64{}
	for rows.Next() {
		var key string
		var value int64
		if err := rows.Scan(&key, &value); err != nil {
			return false, err
		}
		state[key] = value
	}
	if err := rows.Err(); err != nil {
		return false, err
	}
	for _, r := range backfillRanges {
		if state[r.after] < state[r.until] {
			return false, nil
		}
	}
	return true, nil
}

// SearchCounts is how many messages, chats and people the search index holds.
func (s *Store) SearchCounts(ctx context.Context) (messages, chats, people int, err error) {
	err = s.db.QueryRow(ctx, `SELECT (SELECT count(*) FROM events WHERE doc_id IS NOT NULL),
		(SELECT count(*) FROM chat_docs), (SELECT count(*) FROM people_docs)`).Scan(&messages, &chats, &people)
	return messages, chats, people, err
}

// keyedRow is a rowid and the key its table's doc is looked up by.
type keyedRow struct {
	rowid int64
	key   string
}

// backfillKeys runs index for each row q lists (rowid, key) for rowid in (from, to] ($1 and $2; more are extra),
// while b lets it. It stops early with the rowid of the last row it took, or returns to when it took them all.
func (s *Store) backfillKeys(ctx context.Context, b *backfillBatch, from, to int64, index func(key string) error,
	q string, extra ...any,
) (int64, bool, error) {
	rows, err := s.db.Query(ctx, q, append([]any{from, to}, extra...)...)
	if err != nil {
		return 0, false, err
	}
	var list []keyedRow
	for rows.Next() {
		var r keyedRow
		if err := rows.Scan(&r.rowid, &r.key); err != nil {
			rows.Close()
			return 0, false, err
		}
		list = append(list, r)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return 0, false, err
	}
	last := from // nothing taken yet
	seen := map[string]bool{}
	for _, r := range list {
		if seen[r.key] {
			last = r.rowid // the same person again: their doc is already written
			continue
		}
		if !b.take() {
			return last, true, nil
		}
		seen[r.key] = true
		if err := index(r.key); err != nil {
			return 0, false, err
		}
		last = r.rowid
	}
	return to, false, nil
}

// backfillChats writes the doc of every chat of rowid in (from, to] that has none. A chat whose name has no words
// still has none afterwards; the cursor moving past it is what says it was seen.
func (s *Store) backfillChats(ctx context.Context, b *backfillBatch, from, to int64) (int64, bool, error) {
	return s.backfillKeys(ctx, b, from, to, func(id string) error { return s.indexChat(ctx, Room{ID: id}) },
		`SELECT rowid, room_id FROM rooms r WHERE rowid > $1 AND rowid <= $2
		AND NOT EXISTS (SELECT 1 FROM chat_docs d WHERE d.room_id = r.room_id) ORDER BY rowid`)
}

// backfillProfiles writes the doc of everyone with a profile of rowid in (from, to] who has none (I am not a
// person). indexPerson gathers all their names, so one visit is enough.
func (s *Store) backfillProfiles(ctx context.Context, b *backfillBatch, from, to int64) (int64, bool, error) {
	return s.backfillKeys(ctx, b, from, to, func(id string) error { return s.indexPerson(ctx, id) },
		`SELECT rowid, user_id FROM profiles p WHERE rowid > $1 AND rowid <= $2 AND user_id <> $3
		AND NOT EXISTS (SELECT 1 FROM people_docs d WHERE d.user_id = p.user_id) ORDER BY rowid`, string(ids.Me))
}

// backfillMembers does the same for everyone with a member row of rowid in (from, to].
func (s *Store) backfillMembers(ctx context.Context, b *backfillBatch, from, to int64) (int64, bool, error) {
	return s.backfillKeys(ctx, b, from, to, func(id string) error { return s.indexPerson(ctx, id) },
		`SELECT rowid, user_id FROM members m WHERE rowid > $1 AND rowid <= $2 AND user_id <> $3
		AND NOT EXISTS (SELECT 1 FROM people_docs d WHERE d.user_id = m.user_id) ORDER BY rowid`, string(ids.Me))
}

// backfillMessages indexes the messages of rowid in (from, to] as InsertEvent does (indexMessage): each gets the
// text it reads as now (CurrentText), so an edit that is already here, or arrived live before the backfill reached
// its message, counts. Edits are passed over: the message an old edit replaces is indexed after the edit was on
// disk, so its doc already has the edit's text.
func (s *Store) backfillMessages(ctx context.Context, b *backfillBatch, from, to int64) (int64, bool, error) {
	rows, err := s.db.Query(ctx, backfillMessagesSQL, from, to)
	if err != nil {
		return 0, false, err
	}
	type row struct {
		rowid int64
		e     Event
	}
	var list []row
	for rows.Next() {
		var r row
		var er eventRow
		if err := rows.Scan(append([]any{&r.rowid}, er.dest()...)...); err != nil {
			rows.Close()
			return 0, false, err
		}
		r.e = er.event()
		list = append(list, r)
	}
	if err := errors.Join(rows.Err(), rows.Close()); err != nil {
		return 0, false, err
	}
	last := from
	for _, r := range list {
		if isEdit(r.e.Content) {
			last = r.rowid
			continue
		}
		if !b.take() {
			return last, true, nil
		}
		full, err := s.indexMessage(ctx, r.e)
		if err != nil {
			return 0, false, err
		}
		if full {
			b.full++
		}
		last = r.rowid
	}
	return to, false, nil
}
