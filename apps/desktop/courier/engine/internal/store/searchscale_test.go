// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// The scale fixture (Review Focus 4): 10,000 chats and 100,000 messages, 10 to a chat, of 3 to 18 words drawn
// Zipf-distributed from a list of 30,000 synthetic words with a fixed seed, so the common words are very common
// and the rare ones rare, as in real text. Everything is written in one transaction, through the indexer itself.

const (
	scaleChats    = 10_000
	scaleMessages = 100_000
	scaleWords    = 30_000
)

type scaleFixture struct {
	s               *Store
	words           []string // most common first
	bytes           int64    // the database's size: page_count × page_size
	textBytes       int64    // bytes of the indexed message text
	firstTS, lastTS time.Time
}

// syntheticWords is n distinct lowercase words of 2 to 10 letters.
func syntheticWords(r *rand.Rand, n int) []string {
	seen := map[string]bool{}
	out := make([]string, 0, n)
	for len(out) < n {
		b := make([]byte, 2+r.Intn(9))
		for i := range b {
			b[i] = byte('a' + r.Intn(26))
		}
		if w := string(b); !seen[w] {
			seen[w] = true
			out = append(out, w)
		}
	}
	return out
}

func dbBytes(t *testing.T, ctx context.Context, s *Store) int64 {
	t.Helper()
	var pages, size int64
	require.NoError(t, s.db.QueryRow(ctx, "PRAGMA page_count").Scan(&pages))
	require.NoError(t, s.db.QueryRow(ctx, "PRAGMA page_size").Scan(&size))
	return pages * size
}

// scaleSpacing is how far apart the fixture's messages are: a chat history's messages are seconds to minutes apart,
// and that, through the doc ids that encode time, is what the index's size depends on.
const scaleSpacing = 7 * time.Second

var (
	scaleOnce   sync.Once
	scaleShared *scaleFixture
)

// sharedScaleFixture is the indexed scale fixture, written once for every test that reads it. It lives in its own
// directory under the test's temporary directory, which Bazel removes, and stays open until the test binary ends.
func sharedScaleFixture(t *testing.T) *scaleFixture {
	t.Helper()
	scaleOnce.Do(func() {
		dir, err := os.MkdirTemp(os.Getenv("TEST_TMPDIR"), "scale")
		require.NoError(t, err)
		s, err := Open(filepath.Join(dir, "courier.db"))
		require.NoError(t, err)
		scaleShared = newScaleFixture(t, s, scaleSpacing, true)
	})
	require.NotNil(t, scaleShared, "the scale fixture failed to build")
	return scaleShared
}

// newScaleFixture writes the scale fixture into s, messages spacing apart, in one transaction. With index, every chat,
// person and message is indexed as the store's own writes do it (indexChat, indexPerson, and indexEvent right after
// each message's row); without, the same rows are written and nothing is indexed, which is the size the index is
// measured against.
func newScaleFixture(t *testing.T, s *Store, spacing time.Duration, index bool) *scaleFixture {
	t.Helper()
	ctx := context.Background()
	r := rand.New(rand.NewSource(42))
	f := &scaleFixture{s: s, words: syntheticWords(r, scaleWords)}
	zipf := rand.NewZipf(r, 1.07, 2, scaleWords-1)
	sentence := func(min, max int) string {
		n := min + r.Intn(max-min+1)
		parts := make([]string, n)
		for i := range parts {
			parts[i] = f.words[zipf.Uint64()]
		}
		return strings.Join(parts, " ")
	}
	networks := []string{"whatsapp", "telegram", "signal"}
	f.firstTS = time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)
	f.lastTS = f.firstTS.Add(time.Duration(scaleMessages-1) * spacing)
	start := time.Now()
	require.NoError(t, s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		for c := 0; c < scaleChats; c++ {
			id, ghost := fmt.Sprintf("!s%d", c), fmt.Sprintf("@s%d:courier.local", c)
			if _, err := s.db.Exec(ctx, "INSERT INTO rooms (room_id, network, name, is_direct, created_at) VALUES ($1,$2,$3,$4,1)",
				id, networks[c%3], sentence(1, 3), c%2); err != nil {
				return err
			}
			for _, m := range []struct{ user, name string }{{ghost, sentence(2, 2)}, {me, "Me"}} {
				if _, err := s.db.Exec(ctx, "INSERT INTO members (room_id, user_id, content) VALUES ($1,$2,$3)",
					id, m.user, memberContent(m.name)); err != nil {
					return err
				}
			}
			if !index {
				continue
			}
			if err := s.indexChat(ctx, Room{ID: id}); err != nil {
				return err
			}
			if err := s.indexPerson(ctx, ghost); err != nil {
				return err
			}
		}
		for j := 0; j < scaleMessages; j++ {
			c := j % scaleChats
			sender := fmt.Sprintf("@s%d:courier.local", c)
			if j%3 == 0 {
				sender = me
			}
			body := sentence(3, 18)
			content := map[string]any{"msgtype": "m.text", "body": body}
			if j%10 == 0 {
				content = map[string]any{"msgtype": "m.image", "body": body, "url": fmt.Sprintf("mxc://courier.test/i%d", j)}
			}
			b, _ := json.Marshal(content)
			e := Event{
				RoomID: fmt.Sprintf("!s%d", c), EventID: fmt.Sprintf("$s%d", j), Sender: sender, Type: "m.room.message",
				Content: b, TS: f.firstTS.Add(time.Duration(j) * spacing), Seq: int64(j + 1),
			}
			if _, err := s.db.Exec(ctx, `INSERT INTO events (event_id, room_id, sender, type, content, ts, seq) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
				e.EventID, e.RoomID, e.Sender, e.Type, string(e.Content), e.TS.UnixMilli(), e.Seq); err != nil {
				return err
			}
			f.textBytes += int64(len(indexable(body)))
			if !index {
				continue
			}
			if err := s.indexEvent(ctx, e); err != nil {
				return err
			}
		}
		_, err := s.db.Exec(ctx, backfillLastEventSQL)
		return err
	}))
	f.bytes = dbBytes(t, ctx, s)
	t.Logf("scale fixture: %d chats, %d messages %s apart, indexed: %t, written in %s", scaleChats, scaleMessages, spacing, index, time.Since(start))
	if index {
		require.Equal(t, scaleMessages, count(t, s, "SELECT count(*) FROM events WHERE doc_id IS NOT NULL"))
		require.Equal(t, scaleChats, count(t, s, "SELECT count(*) FROM chat_docs"))
	}
	return f
}

// requireWalksTheIndex is TestSearchPlansWalkTheIndex's check of one message query's plan.
func requireWalksTheIndex(t *testing.T, name string, plan []string) {
	t.Helper()
	joined := strings.Join(plan, "\n")
	t.Logf("%s:\n  %s", name, strings.ReplaceAll(joined, "\n", "\n  "))
	require.Regexp(t, `(?m)^SCAN f VIRTUAL TABLE INDEX `, joined, "%s: FTS5 drives the query", name)
	require.Contains(t, joined, "SEARCH e USING INDEX events_doc (doc_id=?)", name)
	require.Regexp(t, `(?m)^SEARCH r USING INDEX sqlite_autoindex_rooms_1 \(room_id=\?\)`, joined, name)
	requireNoScans(t, name, plan)
}

func requireNoScans(t *testing.T, name string, plan []string) {
	t.Helper()
	for _, line := range plan {
		require.NotContains(t, line, "TEMP B-TREE", "%s: a sort", name)
		for _, bad := range []string{"SCAN e", "SCAN r", "SCAN events", "SCAN rooms"} {
			require.False(t, line == bad || strings.HasPrefix(line, bad+" "), "%s: %q in the plan", name, line)
		}
	}
}

func TestSearchPlansWalkTheIndex(t *testing.T) {
	f := sharedScaleFixture(t)
	ctx := context.Background()
	common, rare := f.words[0], f.words[5000]
	mid := f.firstTS.Add(f.lastTS.Sub(f.firstTS) / 2)
	cases := []struct {
		name  string
		q     MessageQuery
		phase int
		page2 bool
	}{
		{"text only", MessageQuery{Terms: terms(common + " ")}, 0, false},
		{"a rare word, typed", MessageQuery{Terms: terms(rare[:2])}, 0, false},
		{"text and a room", MessageQuery{Terms: terms(common + " "), RoomIDs: []string{"!s7", "!s8"}}, 0, false},
		{"text and dm", MessageQuery{Terms: terms(common + " "), ChatType: "dm"}, 0, false},
		{"text and a network", MessageQuery{Terms: terms(common + " "), Networks: []string{"telegram"}}, 0, false},
		{"kinds only", MessageQuery{Kinds: []string{"image"}}, 0, false},
		// Ruling 34: filters alone browse the scope column, bounded by the doc-id range and the limit.
		{"filters only: received, last week", MessageQuery{Sender: "others", Since: mid.Add(-7 * 24 * time.Hour)}, 0, false},
		{"filters only: dm", MessageQuery{ChatType: "dm"}, 0, false},
		{"partial, phase 1", MessageQuery{Terms: terms(common + " " + rare), Partial: true}, 1, false},
		{"a second page", MessageQuery{Terms: terms(common + " ")}, 0, true},
		{"since and until", MessageQuery{Terms: terms(common + " "), Since: mid.Add(-24 * time.Hour), Until: mid}, 0, false},
		{"excluding low priority and muted", MessageQuery{Terms: terms(common + " "), ExcludeLowPriority: true, ExcludeMuted: true, Sender: "others"}, 0, false},
	}
	for _, tc := range cases {
		tc.q.Limit = 20
		m, err := normalizeMessageQuery(tc.q)
		require.NoError(t, err, tc.name)
		upper := m.top()
		if tc.page2 {
			upper = mid.UnixMilli() << 10
		}
		query, args := m.sql(tc.phase, upper, tc.q.Limit+1)
		requireWalksTheIndex(t, tc.name, planOf(t, f.s, query, args...))

		// The loose ceiling, for something gross; the plan is what proves it scales.
		start := time.Now()
		hits, _, err := f.s.SearchMessages(ctx, tc.q)
		took := time.Since(start)
		require.NoError(t, err, tc.name)
		require.NotEmpty(t, hits, tc.name)
		t.Logf("%s: first page of %d in %s", tc.name, len(hits), took)
		require.Less(t, took, 2*time.Second, tc.name)
	}

	// Chats and In groups never scan rooms.
	nq, err := normalizeNameQuery(NameQuery{Terms: terms(common[:2]), Limit: 100})
	require.NoError(t, err)
	for name, q := range map[string]string{"chats": chatMatchSQL, "dms by person": personDMSQL, "in groups": peopleInGroupsSQL} {
		plan := planOf(t, f.s, q, nq.match("dm"))
		t.Logf("%s:\n  %s", name, strings.Join(plan, "\n  "))
		require.Regexp(t, `(?m)^SCAN f VIRTUAL TABLE INDEX `, strings.Join(plan, "\n"), name)
		requireNoScans(t, name, plan)
	}
	query, args, err := buildInboxPage(InboxQuery{RoomIDs: []string{"!s1", "!s2"}, Limit: 100}, nil)
	require.NoError(t, err)
	plan := planOf(t, f.s, query, args...)
	t.Logf("chats' rows:\n  %s", strings.Join(plan, "\n  "))
	for _, line := range plan {
		require.NotEqual(t, "SCAN r", line, "the chats' inbox rows are looked up, not scanned")
	}
	for _, q := range []string{common[:2], common, rare} {
		start := time.Now()
		_, err := f.s.SearchChats(ctx, NameQuery{Terms: terms(q), Limit: 5})
		require.NoError(t, err)
		_, err = f.s.SearchPeopleInGroups(ctx, NameQuery{Terms: terms(q), Limit: 5})
		require.NoError(t, err)
		took := time.Since(start)
		t.Logf("chats and in groups for a %d-letter word: %s", len(q), took)
		require.Less(t, took, 2*time.Second)
	}
}

// The real check measures the message index itself, as the Global Constraint words it ("the message index stays
// within 2× the text it holds"): the bytes the FTS5 table search_messages keeps in its shadow tables (Ruling 15).
// The whole database also grows by the doc ids, events_doc, chat and people docs and freed pages; that is logged.
func TestIndexStaysWithinTwiceTheText(t *testing.T) {
	ctx := context.Background()
	f := sharedScaleFixture(t)
	raw := newScaleFixture(t, open(t), scaleSpacing, false)
	require.Equal(t, raw.textBytes, f.textBytes)
	require.Greater(t, f.textBytes, int64(5<<20), "the fixture is the size the budget was measured at")
	// What the table holds: its segment blocks, its segment index (the term and two integers a row) and the column
	// sizes of every doc (and its rowid), at 8 bytes an integer.
	var data, idx, docsize int64
	require.NoError(t, f.s.db.QueryRow(ctx, `SELECT (SELECT COALESCE(SUM(length(block)), 0) FROM search_messages_data),
		(SELECT COALESCE(SUM(length(term) + 16), 0) FROM search_messages_idx),
		(SELECT COALESCE(SUM(length(sz) + 8), 0) FROM search_messages_docsize)`).Scan(&data, &idx, &docsize))
	table := data + idx + docsize
	ratio := float64(table) / float64(f.textBytes)
	t.Logf("indexed %d bytes of message text; the message index holds %d bytes (%.2f×); the whole database grew %d bytes (%.2f×)",
		f.textBytes, table, ratio, f.bytes-raw.bytes, float64(f.bytes-raw.bytes)/float64(f.textBytes))
	require.LessOrEqual(t, ratio, 2.0)
}
