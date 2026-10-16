// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"

	"go.mau.fi/util/dbutil"
)

// messageLikeTypes decides which events set a room's last_ts and last_event_id: the things a person would call
// "the latest message". An encrypted placeholder counts, because the message exists even if we cannot read it.
// Reactions, redactions and state events never count.
const messageLikeTypes = `'m.room.message','m.sticker','m.room.encrypted'`

// unreadTypes is the narrower set that counts as unread: only messages we can show.
const unreadTypes = `'m.room.message','m.sticker'`

// backfillLastEventSQL points every room at its newest message-like event. Migration 1 runs it once; it is also
// the single definition of "newest" (latest ts, then latest seq) that InsertEvent keeps up to date afterwards.
const backfillLastEventSQL = `UPDATE rooms SET
  last_ts = COALESCE((SELECT e.ts FROM events e WHERE e.room_id = rooms.room_id AND e.type IN (` + messageLikeTypes + `)
                      ORDER BY e.ts DESC, e.seq DESC LIMIT 1), 0),
  last_event_id = COALESCE((SELECT e.event_id FROM events e WHERE e.room_id = rooms.room_id AND e.type IN (` + messageLikeTypes + `)
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

// migrate brings db up to the latest version, all in one transaction: either every pending migration applies
// or none does. A database from a newer engine is refused rather than guessed at.
func migrate(ctx context.Context, db *dbutil.Database) error {
	var v int
	if err := db.QueryRow(ctx, "PRAGMA user_version").Scan(&v); err != nil {
		return fmt.Errorf("read schema version: %w", err)
	}
	if v > len(migrations) {
		return fmt.Errorf("courier.db is at schema version %d, newer than this engine understands (%d): update Courier", v, len(migrations))
	}
	if v == len(migrations) {
		return nil
	}
	return db.DoTxn(ctx, nil, func(ctx context.Context) error {
		for i := v; i < len(migrations); i++ {
			if _, err := db.Exec(ctx, migrations[i]); err != nil {
				return fmt.Errorf("migration %d: %w", i+1, err)
			}
		}
		_, err := db.Exec(ctx, fmt.Sprintf("PRAGMA user_version = %d", len(migrations)))
		return err
	})
}
