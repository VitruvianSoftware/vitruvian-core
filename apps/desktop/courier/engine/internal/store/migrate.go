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

// messageLikeTypes decides which events set a room's last_ts and last_event_id: the things a person would call
// "the latest message". An encrypted placeholder counts, because the message exists even if we cannot read it.
// Reactions, redactions, state events and edits (see notEditSQL) never count.
const messageLikeTypes = `'m.room.message','m.sticker','m.room.encrypted'`

// unreadTypes is the narrower set that counts as unread: only messages we can show.
const unreadTypes = `'m.room.message','m.sticker'`

// backfillLastEventSQL points every room at its newest message-like event. Migration 1 runs it once; it is also
// the single definition of "newest" (latest ts, then latest seq) that InsertEvent keeps up to date afterwards.
var backfillLastEventSQL = `UPDATE rooms SET
  last_ts = COALESCE((SELECT e.ts FROM events e WHERE e.room_id = rooms.room_id AND e.type IN (` + messageLikeTypes + `) AND ` + notEditSQL("e.content") + `
                      ORDER BY e.ts DESC, e.seq DESC LIMIT 1), 0),
  last_event_id = COALESCE((SELECT e.event_id FROM events e WHERE e.room_id = rooms.room_id AND e.type IN (` + messageLikeTypes + `) AND ` + notEditSQL("e.content") + `
                      ORDER BY e.ts DESC, e.seq DESC LIMIT 1), '')`

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
` + backfillLastEventSQL + `;`,
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
