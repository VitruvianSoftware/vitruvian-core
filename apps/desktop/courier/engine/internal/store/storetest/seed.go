// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package storetest puts history into a courier.db the way a milestone-4.1 database holds it: on disk, and not in
// the search index, so the backfill has it to do. The store's, the search package's and the engine's tests share it.
// It writes through raw SQL, never through the store, because the store indexes everything it writes.
package storetest

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

// SeedRoom, SeedPerson and SeedSender are what SeedUnindexed adds besides the messages.
const (
	SeedRoom   = "!seed:courier.local"
	SeedPerson = "@seedperson:courier.local"
	SeedSender = "@seedsender:courier.local"
)

// SeedEventID is the event ID of seeded message i (1-based), and SeedWord the one word only its body holds.
func SeedEventID(i int) string { return fmt.Sprintf("$seed%d", i) }

// SeedWord is the word only seeded message i holds: "w" and its number, one token to the tokenizer.
func SeedWord(i int) string { return fmt.Sprintf("w%d", i) }

// SeedTS is the ts (ms) of seeded message i: three messages to a millisecond, so doc ids share milliseconds.
func SeedTS(i int) int64 { return 1_000_000 + int64(i/3) }

// SeedUnindexed adds to the courier.db at path, which must be closed and at the current schema, a chat named
// "Seed chat", a person named "Seed Person" who is in it, and n text messages, "seed message w1" to "seed message
// wN", none of them indexed; and it moves every backfill range's end past them, as migration 4 sets the ends for
// what is on disk when it runs. The messages are from SeedSender and get rowids after every event already there.
func SeedUnindexed(t testing.TB, path string, n int) {
	t.Helper()
	ctx := context.Background()
	db, err := sqlite.Open(path)
	require.NoError(t, err)
	defer db.Close()
	for _, q := range []string{
		`INSERT INTO rooms (room_id, network, name, created_at) VALUES ('` + SeedRoom + `', 'whatsapp', 'Seed chat', 1000)`,
		`INSERT INTO profiles (user_id, display_name) VALUES ('` + SeedPerson + `', 'Seed Person')`,
		`INSERT INTO members (room_id, user_id, content) VALUES ('` + SeedRoom + `', '` + SeedPerson + `', '{"membership":"join"}')`,
		fmt.Sprintf(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < %d)
			INSERT INTO events (event_id, room_id, sender, type, content, ts, seq)
			SELECT '$seed' || i, '%s', '%s', 'm.room.message',
				json_object('msgtype', 'm.text', 'body', 'seed message w' || i), 1000000 + i / 3,
				(SELECT COALESCE(MAX(seq), 0) FROM events) + i
			FROM n`, n, SeedRoom, SeedSender),
		`UPDATE search_state SET value = (SELECT COALESCE(MAX(rowid), 0) FROM events) WHERE key = 'backfill_until'`,
		`UPDATE search_state SET value = (SELECT COALESCE(MAX(rowid), 0) FROM rooms) WHERE key = 'chats_until'`,
		`UPDATE search_state SET value = (SELECT COALESCE(MAX(rowid), 0) FROM profiles) WHERE key = 'profiles_until'`,
		`UPDATE search_state SET value = (SELECT COALESCE(MAX(rowid), 0) FROM members) WHERE key = 'members_until'`,
	} {
		_, err = db.Exec(ctx, q)
		require.NoError(t, err)
	}
}

// Indexed is how many messages of the courier.db at path have a search doc. The store may be open meanwhile.
func Indexed(t testing.TB, path string) int {
	t.Helper()
	db, err := sqlite.Open(path)
	require.NoError(t, err)
	defer db.Close()
	var n int
	require.NoError(t, db.QueryRow(context.Background(), "SELECT count(*) FROM events WHERE doc_id IS NOT NULL").Scan(&n))
	return n
}
