// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"

	"go.mau.fi/util/dbutil"
)

// maxSeq stands in for "this marker has no known event, so there is no seq to tie-break on": comparing against it
// makes (ts, seq) comparisons fall back to ts alone.
const maxSeq = "9223372036854775807"

// notEditSQL is the SQL half of the one rule "an edit is not a new message": an event whose content has
// m.relates_to.rel_type = m.replace never moves last_ts, the preview or the unread count. content is the column
// expression to test. (CASE keeps json_extract away from content that is not valid JSON.) The Go half is isEdit.
func notEditSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".rel_type') END) IS NOT 'm.replace'`
}

// markerSeq is the seq of the event a read marker points at, so unread can be counted by (ts, seq). marker is the
// alias of the reads / local_reads row and ev the alias of its event (joined on event_id and ts). With no marker
// the answer is 0; with a marker whose event is unknown it is maxSeq (compare on ts alone).
func markerSeq(marker, ev string) string {
	return `CASE WHEN ` + marker + `.room_id IS NULL THEN 0 WHEN ` + ev + `.event_id IS NULL THEN ` + maxSeq + ` ELSE ` + ev + `.seq END`
}

// laterMarker is the (ts, seq) of the later of two read markers, as two SQL expressions: a and b are the aliases
// of the marker rows, aEv and bEv of their events (see markerSeq). A missing marker is (0, 0).
func laterMarker(a, aEv, b, bEv string) string {
	aTS, aSeq := `COALESCE(`+a+`.ts, 0)`, markerSeq(a, aEv)
	bTS, bSeq := `COALESCE(`+b+`.ts, 0)`, markerSeq(b, bEv)
	aWins := `(` + aTS + `, ` + aSeq + `) >= (` + bTS + `, ` + bSeq + `)`
	return `CASE WHEN ` + aWins + ` THEN ` + aTS + ` ELSE ` + bTS + ` END, CASE WHEN ` + aWins + ` THEN ` + aSeq + ` ELSE ` + bSeq + ` END`
}

// messageLikeTypesV1 is messageLikeTypes as migrations 1, 2 and 4 shipped with it, before polls arrived as polls.
// Those migrations are built from it, so their SQL stays as it shipped (TestShippedMigrationsAreUnchanged). Never
// change it: what counts as a message now is messageLikeTypes.
const messageLikeTypesV1 = `'m.room.message','m.sticker','m.room.encrypted'`

// messageLikeTypes decides which events set a room's last_ts and last_event_id: the things a person would call
// "the latest message". An encrypted placeholder counts, because the message exists even if we cannot read it,
// and so does a poll (its start: votes and the end are not messages). Reactions, redactions, state events and
// edits (see notEditSQL) never count. (Go twin: isMessageLike.)
const messageLikeTypes = messageLikeTypesV1 + `,'` + pollStartType + `'`

// unreadTypes is the narrower set that counts as unread: only messages we can show, polls included.
const unreadTypes = `'m.room.message','m.sticker','` + pollStartType + `'`

// lastEventSQL builds the statement that points every room at its newest event of types (latest ts, then latest
// seq) that isn't an edit. filter is extra SQL that the event e must also satisfy.
func lastEventSQL(types, filter string) string {
	pick := `FROM events e WHERE e.room_id = rooms.room_id AND e.type IN (` + types + `) AND ` + notEditSQL("e.content") + filter + `
                      ORDER BY e.ts DESC, e.seq DESC LIMIT 1`
	return `UPDATE rooms SET
  last_ts = COALESCE((SELECT e.ts ` + pick + `), 0),
  last_event_id = COALESCE((SELECT e.event_id ` + pick + `), '')`
}

// backfillLastEventV1SQL is migration 1's statement, frozen as it shipped: it runs before migration 2's redacted
// column exists, so it cannot use backfillLastEventSQL.
var backfillLastEventV1SQL = lastEventSQL(messageLikeTypesV1, "")

// backfillLastEventV2SQL is backfillLastEventSQL as migrations 2 and 4 shipped with it (messageLikeTypesV1), frozen
// so their SQL stays as it shipped.
var backfillLastEventV2SQL = lastEventSQL(messageLikeTypesV1, " AND e.redacted = 0")

// backfillLastEventSQL points every room at its newest message-like event that has not been deleted (redacted).
// It is the single definition of "newest" that InsertEvent keeps up to date afterwards: deleting or redacting a
// chat's last message runs it for that chat.
var backfillLastEventSQL = lastEventSQL(messageLikeTypes, " AND e.redacted = 0")

// redactionTargetSQL is the event a redaction deletes: content.redacts. content is the column expression.
func redactionTargetSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$.redacts') END)`
}

// editTargetSQL is the message an edit replaces: content.m.relates_to.event_id. content is the column expression.
func editTargetSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".event_id') END)`
}

// isEditSQL is true for content that replaces an earlier message: the opposite of notEditSQL. (Go twin: isEdit.)
func isEditSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".rel_type') END) = 'm.replace'`
}

// threadRootSQL is the message a thread reply belongs to: content.m.relates_to.event_id, read with inThreadSQL.
// content is the column expression.
func threadRootSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".event_id') END)`
}

// inThreadSQL is true for content that is a reply in a thread: m.relates_to.rel_type is m.thread, whether or not it
// was also sent to the channel. The thread pane and its summary read these, through events_threads. content is the
// column expression.
func inThreadSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".rel_type') = 'm.thread' END)`
}

// isThreadReplySQL is true for content that is a reply which stays in its thread: in a thread (inThreadSQL) and
// com.beeper.broadcast_outside_thread is not true (a reply also sent to the channel is a message there too). Only the
// main timeline uses it (mainTimelineSQL). content is the column expression.
func isThreadReplySQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."m.relates_to".rel_type') = 'm.thread'
  AND json_extract(` + content + `, '$."com.beeper.broadcast_outside_thread"') IS NOT 1 END)`
}

// afterSendTimerSQL is how long, in ms, an after_send disappearing timer keeps a message:
// content.com.beeper.disappearing_timer.timer when its type is after_send and the timer is a number, else NULL.
// content is the column expression. (Go twin: afterSendExpiry.)
func afterSendTimerSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `)
  AND json_extract(` + content + `, '$."com.beeper.disappearing_timer".type') = 'after_send'
  AND json_type(` + content + `, '$."com.beeper.disappearing_timer".timer') IN ('integer', 'real')
  THEN CAST(json_extract(` + content + `, '$."com.beeper.disappearing_timer".timer') AS INTEGER) END)`
}

// repairRedactedSQL is migration 2's repair, run again by migration 4: it marks deleted every message whose
// redaction arrived before it did, which InsertEvent ignored until migration 4, and points each chat whose latest
// message that was back at the newest one left. Migration 2's own copy stays as it shipped, and this one is frozen
// as migration 4 shipped it (backfillLastEventV2SQL).
var repairRedactedSQL = `UPDATE events SET redacted = 1 WHERE redacted = 0 AND (room_id, event_id) IN (
  SELECT r.room_id, ` + redactionTargetSQL("r.content") + ` FROM events r WHERE r.type = 'm.room.redaction' AND r.status <> 'failed');
` + backfillLastEventV2SQL + ` WHERE last_event_id IN (SELECT event_id FROM events WHERE redacted = 1)`

// searchTokenizer is every search table's tokenizer: case and accents fold, and combining marks stay inside
// words. searchtext prepares text and queries for exactly this one.
const searchTokenizer = `tokenize="unicode61 remove_diacritics 2 categories 'L* N* Co M*'"`

// migrations are applied in order. migrations[i] upgrades a database at PRAGMA user_version = i to i+1.
// schema.sql is the version-0 baseline (the milestone-2 shape) and is never edited: every later change to the
// shape of courier.db is a new entry here, so that databases already on a user's disk keep opening.
var migrations = []string{
	// 1: what an inbox needs (milestone 3).
	`ALTER TABLE rooms ADD COLUMN last_ts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE rooms ADD COLUMN last_event_id TEXT NOT NULL DEFAULT '';
CREATE TABLE room_prefs (
  room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE,
  muted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE local_reads (
  room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  ts INTEGER NOT NULL
);
CREATE INDEX rooms_last_ts ON rooms(last_ts DESC, created_at DESC);
` + backfillLastEventV1SQL + `;`,
	// 2: a deleted (redacted) message is neither a chat's latest message nor unread.
	`ALTER TABLE events ADD COLUMN redacted INTEGER NOT NULL DEFAULT 0;
UPDATE events SET redacted = 1 WHERE (room_id, event_id) IN (
  SELECT r.room_id, ` + redactionTargetSQL("r.content") + ` FROM events r WHERE r.type = 'm.room.redaction' AND r.status <> 'failed');
` + backfillLastEventV2SQL + `;`,
	// 3: how chats are organised (milestone 4.1): pins, archive, low priority, hidden, marked unread, drafts,
	// message requests, labels, per-account settings, the spaces layout, reminders and auto-archive.
	`ALTER TABLE rooms ADD COLUMN request INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN pinned_at INTEGER NOT NULL DEFAULT 0;     -- 0 = not pinned; pin order is pinned_at
ALTER TABLE room_prefs ADD COLUMN archived_at INTEGER NOT NULL DEFAULT 0;   -- 0 = not archived
ALTER TABLE room_prefs ADD COLUMN low_priority INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN marked_unread INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN draft TEXT NOT NULL DEFAULT '';
CREATE INDEX room_prefs_place ON room_prefs(hidden, low_priority, archived_at);
CREATE TABLE labels (label_id INTEGER PRIMARY KEY, title TEXT NOT NULL, color INTEGER NOT NULL, icon TEXT NOT NULL,
  muted INTEGER NOT NULL DEFAULT 0, show_in_inbox TEXT NOT NULL DEFAULT 'all', created_at INTEGER NOT NULL);
CREATE TABLE room_labels (room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
  label_id INTEGER NOT NULL REFERENCES labels(label_id) ON DELETE CASCADE, PRIMARY KEY (room_id, label_id));
CREATE INDEX room_labels_label ON room_labels(label_id);
CREATE TABLE account_prefs (network TEXT PRIMARY KEY, muted INTEGER NOT NULL DEFAULT 0, show_in_inbox TEXT NOT NULL DEFAULT 'all');
CREATE TABLE space_layout (space_id TEXT PRIMARY KEY, position INTEGER NOT NULL, hidden INTEGER NOT NULL DEFAULT 0);
CREATE TABLE reminders (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, due_at INTEGER NOT NULL,
  condition TEXT NOT NULL, set_at INTEGER NOT NULL, fired_at INTEGER NOT NULL DEFAULT 0);
CREATE INDEX reminders_due ON reminders(fired_at, due_at);
CREATE TABLE auto_archive_rules (rule_id INTEGER PRIMARY KEY, scope TEXT NOT NULL, trigger TEXT NOT NULL,
  chat_type TEXT NOT NULL DEFAULT 'all', duration_ms INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1);
CREATE TABLE archive_due (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, due_at INTEGER NOT NULL,
  rule_id INTEGER NOT NULL REFERENCES auto_archive_rules(rule_id) ON DELETE CASCADE);`,
	// 4: search (milestone 4.2): contentless FTS5 indexes of messages, chat names and people's names. The
	// migration indexes nothing itself: text goes through searchtext.Normalize, which is Go, and the backfill
	// (BackfillSearch) indexes in the background every room, profile, member row and event that is on disk now:
	// each table's rows with after < rowid <= until, its two ends in search_state (chats_*, profiles_*, members_*,
	// and backfill_* for events). What is written after it is indexed by the write itself. A message's doc id
	// encodes its time (see indexEvent), so newest first is rowid order.
	`ALTER TABLE events ADD COLUMN doc_id INTEGER;            -- the message's row in search_messages; NULL = not indexed
CREATE UNIQUE INDEX events_doc ON events(doc_id) WHERE doc_id IS NOT NULL;
CREATE INDEX events_edits ON events(` + editTargetSQL("content") + `, ts) WHERE type = 'm.room.message' AND ` + isEditSQL("content") + `;
CREATE INDEX members_user ON members(user_id);            -- a person's chats and names, for their doc
CREATE INDEX events_redacts ON events(` + redactionTargetSQL("content") + `) WHERE type = 'm.room.redaction';
` + repairRedactedSQL + `;
CREATE VIRTUAL TABLE search_messages USING fts5(body, scope, content='', contentless_delete=1, ` + searchTokenizer + `);
CREATE TABLE chat_docs (doc_id INTEGER PRIMARY KEY, room_id TEXT NOT NULL UNIQUE REFERENCES rooms(room_id) ON DELETE CASCADE);
CREATE VIRTUAL TABLE search_chats USING fts5(name, scope, content='', contentless_delete=1, ` + searchTokenizer + `);
CREATE TABLE people_docs (doc_id INTEGER PRIMARY KEY, user_id TEXT NOT NULL UNIQUE);
CREATE VIRTUAL TABLE search_people USING fts5(name, scope, content='', contentless_delete=1, ` + searchTokenizer + `);
CREATE TABLE search_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
INSERT INTO search_state VALUES ('backfill_until', (SELECT COALESCE(MAX(rowid), 0) FROM events)), ('backfill_after', 0),
  ('chats_until', (SELECT COALESCE(MAX(rowid), 0) FROM rooms)), ('chats_after', 0),
  ('profiles_until', (SELECT COALESCE(MAX(rowid), 0) FROM profiles)), ('profiles_after', 0),
  ('members_until', (SELECT COALESCE(MAX(rowid), 0) FROM members)), ('members_after', 0);
CREATE TRIGGER events_unindex AFTER DELETE ON events WHEN old.doc_id IS NOT NULL
  BEGIN DELETE FROM search_messages WHERE rowid = old.doc_id; END;
CREATE TRIGGER events_unindex_redacted AFTER UPDATE OF redacted ON events WHEN new.redacted = 1 AND old.doc_id IS NOT NULL
  BEGIN DELETE FROM search_messages WHERE rowid = old.doc_id; UPDATE events SET doc_id = NULL WHERE event_id = new.event_id; END;
CREATE TRIGGER chat_docs_unindex AFTER DELETE ON chat_docs BEGIN DELETE FROM search_chats WHERE rowid = old.doc_id; END;
CREATE TRIGGER people_docs_unindex AFTER DELETE ON people_docs BEGIN DELETE FROM search_people WHERE rowid = old.doc_id; END;`,
	// 5: message actions (milestone 4.3): Delete for Me, disappearing expiry, the indexes poll votes and threads are
	// read through, the outbox (messages held for undo send, and scheduled ones) and bookmarks. No failed edit or
	// unsend can be on disk yet (4.2 sent neither), so nothing in the search index needs repairing.
	`ALTER TABLE events ADD COLUMN deleted_for_me INTEGER NOT NULL DEFAULT 0; -- set with redacted = 1: gone here, no placeholder
ALTER TABLE events ADD COLUMN expires_at INTEGER;                         -- after_send disappearing: ts + timer; NULL = never
CREATE INDEX events_expiry ON events(expires_at) WHERE expires_at IS NOT NULL AND redacted = 0;
CREATE INDEX events_refs ON events(` + editTargetSQL("content") + `, ts)
  WHERE type IN ('org.matrix.msc3381.poll.response', 'org.matrix.msc3381.poll.end');
CREATE INDEX events_threads ON events(room_id, ` + threadRootSQL("content") + `, ts DESC, seq DESC)
  WHERE type IN ('m.room.message', 'm.sticker') AND ` + inThreadSQL("content") + `;
CREATE TABLE outbox (outbox_id INTEGER PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
  kind TEXT NOT NULL,                    -- undo | later
  event_id TEXT NOT NULL UNIQUE,         -- undo: the queued events row; later: the ID it will be sent as
  type TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',   -- later only
  due_at INTEGER NOT NULL, set_at INTEGER NOT NULL,
  condition TEXT NOT NULL DEFAULT 'always',                          -- later: if_no_reply | always
  state TEXT NOT NULL DEFAULT 'waiting');                            -- waiting | canceled | missed
CREATE INDEX outbox_due ON outbox(state, due_at);
CREATE INDEX outbox_room ON outbox(room_id, kind);
CREATE TABLE bookmarks (event_id TEXT PRIMARY KEY REFERENCES events(event_id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, created_at INTEGER NOT NULL);
CREATE INDEX bookmarks_new ON bookmarks(created_at DESC);
UPDATE events SET expires_at = ts + ` + afterSendTimerSQL("content") + `
  WHERE content LIKE '%com.beeper.disappearing_timer%' AND ` + afterSendTimerSQL("content") + ` > 0 AND redacted = 0;`,
}

// migrate brings db up to the latest version.
func migrate(ctx context.Context, db *dbutil.Database) error { return migrateWith(ctx, db, migrations) }

// migrateWith applies the pending part of list in one transaction, version check included: either every pending
// migration applies and user_version moves, or nothing changes. A database from a newer engine is refused
// rather than guessed at.
func migrateWith(ctx context.Context, db *dbutil.Database, list []string) error {
	return db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var v int
		if err := db.QueryRow(ctx, "PRAGMA user_version").Scan(&v); err != nil {
			return fmt.Errorf("read schema version: %w", err)
		}
		if v > len(list) {
			return fmt.Errorf("courier.db is at schema version %d, newer than this engine understands (%d): update Courier", v, len(list))
		}
		if v == len(list) {
			return nil
		}
		for i := v; i < len(list); i++ {
			if _, err := db.Exec(ctx, list[i]); err != nil {
				return fmt.Errorf("migration %d: %w", i+1, err)
			}
		}
		_, err := db.Exec(ctx, fmt.Sprintf("PRAGMA user_version = %d", len(list)))
		return err
	})
}
