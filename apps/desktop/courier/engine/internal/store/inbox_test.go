// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

const (
	ghost = "@ghost:courier.local"
	me    = "@me:courier.local"
)

func mkRoom(t *testing.T, s *Store, id string, created time.Time) {
	t.Helper()
	require.NoError(t, s.UpsertRoom(context.Background(), Room{ID: id, Network: "whatsapp", Name: id, CreatedAt: created}))
}

func mkMsg(t *testing.T, s *Store, roomID, eventID, sender, typ, content string, ts time.Time) {
	t.Helper()
	_, err := s.InsertEvent(context.Background(), Event{
		RoomID: roomID, EventID: eventID, Sender: sender, Type: typ, Content: json.RawMessage(content), TS: ts,
	})
	require.NoError(t, err)
}

func text(body string) string {
	b, _ := json.Marshal(map[string]string{"msgtype": "m.text", "body": body})
	return string(b)
}

func inboxByID(t *testing.T, s *Store) map[string]InboxRow {
	t.Helper()
	rows, err := s.Inbox(context.Background())
	require.NoError(t, err)
	out := map[string]InboxRow{}
	for _, r := range rows {
		out[r.ID] = r
	}
	return out
}

func TestInboxOrdersByLatestMessage(t *testing.T) {
	s, ctx := open(t), context.Background()
	// Created order is A, B, C, D (D newest). Only A and B have messages; A's is older than B's.
	mkRoom(t, s, "!a", time.Unix(100, 0))
	mkRoom(t, s, "!b", time.Unix(200, 0))
	mkRoom(t, s, "!c", time.Unix(300, 0))
	mkRoom(t, s, "!d", time.Unix(400, 0))
	mkMsg(t, s, "!a", "$a", ghost, "m.room.message", text("a"), time.Unix(1000, 0))
	mkMsg(t, s, "!b", "$b", ghost, "m.room.message", text("b"), time.Unix(2000, 0))

	rows, err := s.Inbox(ctx)
	require.NoError(t, err)
	var ids []string
	for _, r := range rows {
		ids = append(ids, r.ID)
	}
	require.Equal(t, []string{"!b", "!a", "!d", "!c"}, ids, "rooms with messages first (newest first), then the rest by created_at")
	require.Equal(t, time.Unix(2000, 0).UnixMilli(), rows[0].LastTS.UnixMilli())
	require.True(t, rows[2].LastTS.IsZero(), "a room with no message has a zero LastTS")
}

func TestInboxPreviewAndUnread(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$1", ghost, "m.room.message", text("one"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$2", ghost, "m.room.message", text("two"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$3", ghost, "m.room.message", text("three"), time.Unix(30, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$1", time.Unix(10, 0)))

	row := inboxByID(t, s)["!r"]
	require.Equal(t, 2, row.Unread)
	require.Equal(t, "three", row.Preview)
	require.Equal(t, "text", row.PreviewKind)
	require.False(t, row.PreviewMine)

	// A reaction and a redaction (of that reaction) are newer, but never the preview, never unread, and don't move
	// the sort time. (A redaction of a message: TestRedactingTheLastMessageFixesTheChatRow.)
	mkMsg(t, s, "!r", "$re", ghost, "m.reaction", `{"m.relates_to":{"event_id":"$3","key":"x"}}`, time.Unix(40, 0))
	mkMsg(t, s, "!r", "$rd", ghost, "m.room.redaction", `{"redacts":"$re"}`, time.Unix(50, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "three", row.Preview)
	require.Equal(t, 2, row.Unread)
	require.Equal(t, time.Unix(30, 0).UnixMilli(), row.LastTS.UnixMilli())

	// An image from someone else: kind "image", counted as unread.
	mkMsg(t, s, "!r", "$img", ghost, "m.room.message", `{"msgtype":"m.image","body":"pic.jpg"}`, time.Unix(60, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "image", row.PreviewKind)
	require.Equal(t, "pic.jpg", row.Preview)
	require.Equal(t, 3, row.Unread)

	// A sticker.
	mkMsg(t, s, "!r", "$st", ghost, "m.sticker", `{"body":"waving"}`, time.Unix(65, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "sticker", row.PreviewKind)
	require.Equal(t, 4, row.Unread)

	// My own message: not counted, and it is the preview.
	mkMsg(t, s, "!r", "$mine", me, "m.room.message", text("sent by me"), time.Unix(70, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, 4, row.Unread, "my own messages are never unread")
	require.True(t, row.PreviewMine)
	require.Equal(t, "sent by me", row.Preview)
}

func TestInboxPreviewKindsAndTruncation(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for i, tc := range []struct{ msgtype, kind string }{
		{"m.text", "text"},
		{"m.notice", "text"},
		{"m.emote", "text"},
		{"m.image", "image"},
		{"m.video", "video"},
		{"m.audio", "audio"},
		{"m.file", "file"},
		{"m.location", "text"},
		{"", "text"},
	} {
		body, _ := json.Marshal(map[string]string{"msgtype": tc.msgtype, "body": "b"})
		mkMsg(t, s, "!r", fmt.Sprintf("$%d", i), ghost, "m.room.message", string(body), time.Unix(int64(10+i), 0))
		require.Equal(t, tc.kind, inboxByID(t, s)["!r"].PreviewKind, "msgtype %q", tc.msgtype)
	}
	long := strings.Repeat("é", 200) // multi-byte: the cut is by rune, not byte
	mkMsg(t, s, "!r", "$long", ghost, "m.room.message", text(long), time.Unix(100, 0))
	got := inboxByID(t, s)["!r"].Preview
	require.Equal(t, 140, len([]rune(got)))
	require.Equal(t, strings.Repeat("é", 140), got)
}

func TestInboxOutOfOrderBackfillKeepsNewest(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$new", ghost, "m.room.message", text("newest"), time.Unix(500, 0))
	mkMsg(t, s, "!r", "$old", ghost, "m.room.message", text("backfilled older"), time.Unix(100, 0))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "newest", row.Preview, "a backfilled older message must not replace the preview")
	require.Equal(t, time.Unix(500, 0).UnixMilli(), row.LastTS.UnixMilli())
}

// The bug this guards: a read receipt moved the marker to the time of the receipt, so a receipt that came in
// after newer messages marked those read too. The marker is the message's own place, and only moves forward.
func TestMyReadOnAnotherDeviceClearsUpToThatMessageOnly(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$mine", me, "m.room.message", text("are you coming?"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$r1", ghost, "m.room.message", text("yes"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$r2", ghost, "m.room.message", text("on my way"), time.Unix(30, 0))
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread)

	// A receipt for my own message, reported later than both replies: they stay unread.
	require.NoError(t, s.SetRead(ctx, "!r", "$mine", time.Unix(40, 0)))
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread, "the receipt's time must not mark newer messages read")

	// I read the first reply on my phone: only it clears.
	require.NoError(t, s.SetRead(ctx, "!r", "$r1", time.Unix(50, 0)))
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread)
	// A late receipt for an older message does not move the marker back.
	require.NoError(t, s.SetRead(ctx, "!r", "$mine", time.Unix(60, 0)))
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread)

	// The marker is the later of the two: an older local read must not bring messages back...
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$mine", time.Unix(10, 0)))
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread)
	// ...and a newer local read wins over the network one.
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$r2", time.Unix(30, 0)))
	require.Equal(t, 0, inboxByID(t, s)["!r"].Unread)
}

func TestSetReadPublishesOnlyWhenItMoves(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$1", ghost, "m.room.message", text("a"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$2", ghost, "m.room.message", text("b"), time.Unix(20, 0))
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetRead(ctx, "!r", "$2", time.Unix(99, 0)))
	require.Equal(t, Change{Kind: "read", RoomID: "!r", EventID: "$2"}, nextChange(t, ch))
	require.NoError(t, s.SetRead(ctx, "!r", "$1", time.Unix(99, 0)))
	select {
	case c := <-ch:
		t.Fatalf("an older read published %+v", c)
	case <-time.After(50 * time.Millisecond):
	}
}

func TestMarkReadLocalPublishesReadChange(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$1", time.Unix(10, 0)))
	require.Equal(t, Change{Kind: "read", RoomID: "!r", EventID: "$1"}, nextChange(t, ch))
}

func TestMutedIsKeptAndPublished(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	require.False(t, inboxByID(t, s)["!r"].Muted)

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetMuted(ctx, "!r", true))
	require.Equal(t, Change{Kind: "room", RoomID: "!r"}, nextChange(t, ch))
	require.True(t, inboxByID(t, s)["!r"].Muted)

	// A bridge refreshing the room's name must not unmute it.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r", Network: "whatsapp", Name: "renamed"}))
	require.True(t, inboxByID(t, s)["!r"].Muted)

	require.NoError(t, s.SetMuted(ctx, "!r", false))
	require.False(t, inboxByID(t, s)["!r"].Muted)
}

func TestEventsBeforePagesWithoutGapsOrRepeats(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	var all []string
	for i := 0; i < 120; i++ {
		id := fmt.Sprintf("$%03d", i)
		all = append(all, id)
		// Three events share each timestamp, so only seq can order them.
		mkMsg(t, s, "!r", id, ghost, "m.room.message", text(id), time.Unix(int64(1000+i/3), 0))
	}

	var got []string
	var sizes []int
	var cur *Cursor
	for page := 0; page < 10; page++ {
		evs, next, err := s.EventsBefore(ctx, "!r", cur, 50)
		require.NoError(t, err)
		sizes = append(sizes, len(evs))
		for _, e := range evs {
			require.NotZero(t, e.Seq, "events carry their seq")
			got = append(got, e.EventID)
		}
		if next == nil {
			break
		}
		cur = next
	}
	require.Equal(t, []int{50, 50, 20}, sizes)
	require.Len(t, got, 120)
	require.ElementsMatch(t, all, got, "the pages' union is exactly the 120 events")
	for i := range got {
		require.Equal(t, all[119-i], got[i], "newest first; equal timestamps broken by seq (arrival order, newest first)")
	}
}

func TestEventsBeforeExactMultipleHasNoTrailingCursor(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for i := 0; i < 100; i++ {
		mkMsg(t, s, "!r", fmt.Sprintf("$%d", i), ghost, "m.room.message", text("x"), time.Unix(int64(i), 0))
	}
	evs, next, err := s.EventsBefore(ctx, "!r", nil, 50)
	require.NoError(t, err)
	require.Len(t, evs, 50)
	require.NotNil(t, next)
	evs, next, err = s.EventsBefore(ctx, "!r", next, 50)
	require.NoError(t, err)
	require.Len(t, evs, 50)
	require.Nil(t, next, "exactly the last page: no cursor to an empty page")
}

func TestChangesCarrySeq(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	ch, cancel := s.Subscribe()
	defer cancel()
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$a", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("x")), TS: time.Unix(5, 0), Status: "pending",
	})
	require.NoError(t, err)
	c := nextChange(t, ch)
	require.Equal(t, "event", c.Kind)
	require.NotZero(t, c.Seq)
	require.NoError(t, s.SetStatus(ctx, "$a", "sent", ""))
	st := nextChange(t, ch)
	require.Equal(t, Change{Kind: "status", RoomID: "!r", EventID: "$a", Seq: c.Seq}, st, "a status change carries the event's seq")
}

func TestPendingSurvivesReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "courier.db")
	ctx := context.Background()
	s, err := Open(path)
	require.NoError(t, err)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	pending := Event{
		RoomID: "!r", EventID: "$p", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("on its way")), TS: time.Unix(5, 0), Status: "pending",
	}
	_, err = s.InsertEvent(ctx, pending)
	require.NoError(t, err)
	require.NoError(t, s.Close())

	s, err = Open(path)
	require.NoError(t, err)
	defer s.Close()
	evs, err := s.Events(ctx, "!r", 10)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	require.Equal(t, "pending", evs[0].Status)

	// Re-delivering the same event after a restart neither duplicates it nor resets its state.
	require.NoError(t, s.SetStatus(ctx, "$p", "failed", "offline"))
	ins, err := s.InsertEvent(ctx, pending)
	require.NoError(t, err)
	require.False(t, ins)
	evs, err = s.Events(ctx, "!r", 10)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	require.Equal(t, "failed", evs[0].Status)
	row := inboxByID(t, s)["!r"]
	require.True(t, row.PreviewMine)
	require.Equal(t, "on its way", row.Preview)

	// New events after the reopen get a seq above the old ones.
	_, err = s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$q", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("later")), TS: time.Unix(5, 0),
	})
	require.NoError(t, err)
	evs, err = s.Events(ctx, "!r", 10)
	require.NoError(t, err)
	require.Equal(t, "$q", evs[0].EventID)
	require.Greater(t, evs[0].Seq, evs[1].Seq)
}

func userVersion(t *testing.T, s *Store) int {
	t.Helper()
	var v int
	require.NoError(t, s.db.QueryRow(context.Background(), "PRAGMA user_version").Scan(&v))
	return v
}

func TestMigrationFromMilestone2(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile("testdata/m2.sql")
	require.NoError(t, err)
	raw, err := sqlite.Open(path)
	require.NoError(t, err)
	_, err = raw.Exec(ctx, string(fixture))
	require.NoError(t, err)
	var before int
	require.NoError(t, raw.QueryRow(ctx, "PRAGMA user_version").Scan(&before))
	require.Equal(t, 0, before, "the fixture is a genuine pre-migration database")
	require.NoError(t, raw.Close())

	s, err := Open(path)
	require.NoError(t, err)
	defer s.Close()
	require.Equal(t, len(migrations), userVersion(t, s))

	rows := inboxByID(t, s)
	require.Len(t, rows, 3)
	old := rows["!old:courier.local"]
	require.Equal(t, time.UnixMilli(20000).UnixMilli(), old.LastTS.UnixMilli(), "last_ts is backfilled from events, ignoring the newer edit")
	require.Equal(t, "second old", old.Preview)
	require.Equal(t, 2, old.Unread, "never read: both messages are unread; the edit is not a third")
	busy := rows["!busy:courier.local"]
	require.Equal(t, time.UnixMilli(70000).UnixMilli(), busy.LastTS.UnixMilli(), "the reaction at 50000 does not count")
	require.Equal(t, "still sending", busy.Preview)
	require.True(t, busy.PreviewMine)
	require.Equal(t, 1, busy.Unread, "only the image is newer than the network read marker")
	require.True(t, rows["!empty:courier.local"].LastTS.IsZero())

	evs, err := s.Events(ctx, "!busy:courier.local", 1)
	require.NoError(t, err)
	require.Equal(t, "pending", evs[0].Status, "pending messages survive the upgrade")
	require.NoError(t, s.Close())

	// Opening again is a no-op.
	s2, err := Open(path)
	require.NoError(t, err)
	defer s2.Close()
	require.Equal(t, len(migrations), userVersion(t, s2))
	require.Len(t, inboxByID(t, s2), 3)
}

func TestFreshDatabaseIsAtLatestVersion(t *testing.T) {
	require.Equal(t, len(migrations), userVersion(t, open(t)))
}

func TestNewerDatabaseIsRefused(t *testing.T) {
	path := filepath.Join(t.TempDir(), "courier.db")
	s, err := Open(path)
	require.NoError(t, err)
	_, err = s.db.Exec(context.Background(), "PRAGMA user_version = 99")
	require.NoError(t, err)
	require.NoError(t, s.Close())
	_, err = Open(path)
	require.ErrorContains(t, err, "newer")
}

// seedBig fills s with rooms inbox rooms (perRoom messages each) plus one room, "!long", with longN messages
// (none when longN is 0).
// It writes the rows directly, in one transaction, so the test stays quick; last_ts comes from the migration's
// own backfill statement.
func seedBig(t *testing.T, s *Store, rooms, perRoom, longN int) {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		seq := 0
		add := func(room string, i int, sender string) error {
			seq++
			_, err := s.db.Exec(ctx, `INSERT INTO events (event_id, room_id, sender, type, content, ts, seq) VALUES ($1,$2,$3,'m.room.message',$4,$5,$6)`,
				fmt.Sprintf("$%s-%d", room, i), room, sender, `{"msgtype":"m.text","body":"hello"}`, int64(1_000_000+i/2), seq)
			return err
		}
		for r := 0; r < rooms; r++ {
			id := fmt.Sprintf("!r%d", r)
			if _, err := s.db.Exec(ctx, "INSERT INTO rooms (room_id, network, name, created_at) VALUES ($1,'whatsapp',$1,$2)", id, int64(r)); err != nil {
				return err
			}
			for i := 0; i < perRoom; i++ {
				sender := ghost
				if i%3 == 0 {
					sender = me
				}
				if err := add(id, r+i, sender); err != nil {
					return err
				}
			}
		}
		if longN == 0 {
			_, err := s.db.Exec(ctx, backfillLastEventSQL)
			return err
		}
		if _, err := s.db.Exec(ctx, "INSERT INTO rooms (room_id, network, name, created_at) VALUES ('!long','whatsapp','long',0)"); err != nil {
			return err
		}
		for i := 0; i < longN; i++ {
			if err := add("!long", i, ghost); err != nil {
				return err
			}
		}
		_, err := s.db.Exec(ctx, backfillLastEventSQL)
		return err
	}))
}

// planOf returns the lines of EXPLAIN QUERY PLAN for q.
func planOf(t *testing.T, s *Store, q string, args ...any) []string {
	t.Helper()
	rows, err := s.db.Query(context.Background(), "EXPLAIN QUERY PLAN "+q, args...)
	require.NoError(t, err)
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id, parent, unused int
		var detail string
		require.NoError(t, rows.Scan(&id, &parent, &unused, &detail))
		out = append(out, detail)
	}
	require.NoError(t, rows.Err())
	return out
}

func requireIndexed(t *testing.T, plan []string) {
	t.Helper()
	t.Log("plan:\n  " + strings.Join(plan, "\n  "))
	for _, line := range plan {
		// A rowid lookup ("USING INTEGER PRIMARY KEY") is the table's own b-tree: as good as an index.
		if (strings.HasPrefix(line, "SCAN") || strings.HasPrefix(line, "SEARCH")) && !strings.Contains(line, "INTEGER PRIMARY KEY") {
			require.Contains(t, line, "INDEX", "a full table scan: %s", line)
		}
		require.NotContains(t, line, "TEMP B-TREE", "the query sorts in a temp table: %s", line)
	}
}

func TestInboxAndPagingAreIndexed(t *testing.T) {
	s, ctx := open(t), context.Background()
	seedBig(t, s, 2000, 5, 10000)

	// The primary check: both queries run on indexes, never a table scan or a sort.
	inboxPlan := planOf(t, s, inboxSQL, me)
	requireIndexed(t, inboxPlan)
	require.True(t, strings.Contains(strings.Join(inboxPlan, "\n"), "events_room_ts"), "the unread count uses events_room_ts")
	require.Contains(t, strings.Join(inboxPlan, "\n"), "events_room_ts (room_id=? AND (ts,seq)>(?,?))",
		"the unread count is a range from the marker on, not a scan of the whole chat")
	require.True(t, strings.Contains(strings.Join(inboxPlan, "\n"), "rooms_last_ts"), "the inbox order uses rooms_last_ts")
	pagePlan := planOf(t, s, eventsBeforeSQL, "!long", int64(1_005_000), int64(5000), 51)
	requireIndexed(t, pagePlan)
	require.Contains(t, strings.Join(pagePlan, "\n"), "events_room_ts")

	// The secondary check: wall-clock, with room for a busy machine. (Measured: about 7 ms, and about 25 ms under
	// -race, against 1 s.) The plan above is what proves the queries scale; this only catches something gross.
	const bound = time.Second
	start := time.Now()
	rows, err := s.Inbox(ctx)
	took := time.Since(start)
	t.Logf("inbox of %d rooms: %s", len(rows), took)
	require.NoError(t, err)
	require.Len(t, rows, 2001)
	require.Less(t, took, bound, "a 2,000-room inbox must return quickly")

	// Paging deep into a 10,000-message chat is just as quick as the first page.
	start = time.Now()
	evs, next, err := s.EventsBefore(ctx, "!long", nil, 50)
	for i := 0; i < 150 && err == nil && next != nil; i++ {
		evs, next, err = s.EventsBefore(ctx, "!long", next, 50)
	}
	took = time.Since(start)
	t.Logf("200 pages of the long chat: %s", took)
	require.NoError(t, err)
	require.Len(t, evs, 50)
	require.Less(t, took, bound*2, "200 pages of a 10,000-message chat")
}

func lastEventID(t *testing.T, s *Store, roomID string) string {
	t.Helper()
	var id string
	require.NoError(t, s.db.QueryRow(context.Background(), "SELECT last_event_id FROM rooms WHERE room_id=$1", roomID).Scan(&id))
	return id
}

const editOf = `{"msgtype":"m.text","body":"* edited","m.relates_to":{"rel_type":"m.replace","event_id":"$orig"}}`

func TestEditsDoNotBumpAChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(2, 0))
	mkMsg(t, s, "!r", "$orig", ghost, "m.room.message", text("original"), time.Unix(10, 0))
	mkMsg(t, s, "!other", "$o", ghost, "m.room.message", text("o"), time.Unix(20, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$orig", time.Unix(10, 0)))

	mkMsg(t, s, "!r", "$edit", ghost, "m.room.message", editOf, time.Unix(30, 0))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "original", row.Preview, "an edit is not the preview")
	require.Equal(t, time.Unix(10, 0).UnixMilli(), row.LastTS.UnixMilli(), "an edit does not move the sort time")
	require.Equal(t, 0, row.Unread, "an edit is not unread")
	require.Equal(t, "$orig", lastEventID(t, s, "!r"))
	rows, err := s.Inbox(ctx)
	require.NoError(t, err)
	require.Equal(t, "!other", rows[0].ID, "the edited chat does not jump to the top")

	// The edit is still stored: it is history, just not news.
	evs, err := s.Events(ctx, "!r", 10)
	require.NoError(t, err)
	require.Len(t, evs, 2)

	// Content that is not JSON, or has no relation, is an ordinary message.
	mkMsg(t, s, "!r", "$odd", ghost, "m.room.message", `not json`, time.Unix(40, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, 1, row.Unread)
	require.Equal(t, "$odd", lastEventID(t, s, "!r"))
}

func TestUnreadTieBreaksBySeq(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	same := time.Unix(10, 0)
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("a"), same)
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("b"), same) // same millisecond, arrived later
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$a", same))
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread, "$b is in the marker's millisecond but arrived after it")

	// The same through the network marker.
	require.NoError(t, s.SetRead(ctx, "!r", "$b", same))
	require.Equal(t, 0, inboxByID(t, s)["!r"].Unread)
	mkRoom(t, s, "!n", time.Unix(2, 0))
	mkMsg(t, s, "!n", "$x", ghost, "m.room.message", text("x"), same)
	mkMsg(t, s, "!n", "$y", ghost, "m.room.message", text("y"), same)
	require.NoError(t, s.SetRead(ctx, "!n", "$x", same))
	require.Equal(t, 1, inboxByID(t, s)["!n"].Unread)

	// A marker whose event we do not have falls back to ts alone.
	mkRoom(t, s, "!u", time.Unix(3, 0))
	mkMsg(t, s, "!u", "$p", ghost, "m.room.message", text("p"), same)
	mkMsg(t, s, "!u", "$q", ghost, "m.room.message", text("q"), time.Unix(20, 0))
	require.NoError(t, s.SetRead(ctx, "!u", "$unknown", same))
	require.Equal(t, 1, inboxByID(t, s)["!u"].Unread)
}

func TestMarkReadLocalOnlyMovesForward(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for i := 1; i <= 4; i++ {
		mkMsg(t, s, "!r", fmt.Sprintf("$%d", i), ghost, "m.room.message", text("m"), time.Unix(int64(i*10), 0))
	}
	// Two more in one millisecond.
	mkMsg(t, s, "!r", "$5a", ghost, "m.room.message", text("m"), time.Unix(50, 0))
	mkMsg(t, s, "!r", "$5b", ghost, "m.room.message", text("m"), time.Unix(50, 0))

	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$3", time.Unix(30, 0))) // no network read exists
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread)
	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$1", time.Unix(10, 0)))
	require.Equal(t, 3, inboxByID(t, s)["!r"].Unread, "an older mark never moves the marker back")
	select {
	case c := <-ch:
		t.Fatalf("a mark that moved nothing published %+v", c)
	case <-time.After(50 * time.Millisecond):
	}

	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$5b", time.Unix(50, 0)))
	require.Equal(t, 0, inboxByID(t, s)["!r"].Unread)
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$5a", time.Unix(50, 0))) // same ms, lower seq: not later
	require.Equal(t, 0, inboxByID(t, s)["!r"].Unread)
	require.Equal(t, Change{Kind: "read", RoomID: "!r", EventID: "$5b"}, nextChange(t, ch))
}

func TestEncryptedPlaceholderBecomesLastEvent(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$m", ghost, "m.room.message", text("readable"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$enc", ghost, "m.room.encrypted", `{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"x"}`, time.Unix(20, 0))
	require.Equal(t, "$enc", lastEventID(t, s, "!r"))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, time.Unix(20, 0).UnixMilli(), row.LastTS.UnixMilli())
	require.Equal(t, "", row.Preview)
	require.Equal(t, "", row.PreviewKind)
	require.Equal(t, 1, row.Unread, "only the readable message is counted as unread")
}

func TestFailedMigrationRollsBack(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile("testdata/m2.sql")
	require.NoError(t, err)
	db, err := sqlite.Open(path)
	require.NoError(t, err)
	defer db.Close()
	_, err = db.Exec(ctx, string(fixture))
	require.NoError(t, err)

	// Migration 1 succeeds, then a second step fails: the whole thing must roll back, including migration 1.
	err = migrateWith(ctx, db, []string{migrations[0], "ALTER TABLE no_such_table ADD COLUMN x INTEGER"})
	require.ErrorContains(t, err, "migration 2")
	var v int
	require.NoError(t, db.QueryRow(ctx, "PRAGMA user_version").Scan(&v))
	require.Equal(t, 0, v, "user_version is unchanged")
	_, err = db.Exec(ctx, "SELECT last_ts FROM rooms")
	require.Error(t, err, "migration 1's columns were rolled back with it")
	_, err = db.Exec(ctx, "SELECT * FROM room_prefs")
	require.Error(t, err, "migration 1's tables were rolled back with it")

	// The real migration still applies cleanly afterwards.
	require.NoError(t, migrate(ctx, db))
	require.NoError(t, db.QueryRow(ctx, "PRAGMA user_version").Scan(&v))
	require.Equal(t, len(migrations), v)
}

func TestDeleteEventForgetsItAndFixesTheChatRow(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$old", ghost, "m.room.message", text("older"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$mine", me, "m.room.message", text("mine"), time.Unix(20, 0))
	require.Equal(t, "$mine", lastEventID(t, s, "!r"))
	ch, cancel := s.Subscribe()
	defer cancel()

	require.NoError(t, s.DeleteEvent(ctx, "$mine"))

	_, ok, err := s.GetEvent(ctx, "$mine")
	require.NoError(t, err)
	require.False(t, ok, "the event is gone")
	require.Equal(t, "$old", lastEventID(t, s, "!r"), "the chat points at the newest message that is left")
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "older", row.Preview)
	require.Equal(t, time.Unix(10, 0).UnixMilli(), row.LastTS.UnixMilli(), "the chat sorts by the message that is left")
	c := nextChange(t, ch)
	require.Equal(t, "status", c.Kind)
	require.Equal(t, "!r", c.RoomID)
	require.Equal(t, "$mine", c.EventID)

	// Deleting the last message of a chat leaves it with no message, and an unknown event is not an error.
	require.NoError(t, s.DeleteEvent(ctx, "$old"))
	require.Equal(t, "", lastEventID(t, s, "!r"))
	require.True(t, inboxByID(t, s)["!r"].LastTS.IsZero())
	require.NoError(t, s.DeleteEvent(ctx, "$never-existed"))
}

func TestDeleteEventOfAnOlderMessageLeavesTheChatRowAlone(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("a"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("b"), time.Unix(20, 0))
	require.NoError(t, s.DeleteEvent(ctx, "$a"))
	require.Equal(t, "$b", lastEventID(t, s, "!r"))
	require.Equal(t, "b", inboxByID(t, s)["!r"].Preview)
}

func TestLastMessageIgnoresReactionsAndEdits(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	_, ok, err := s.LastMessage(ctx, "!r")
	require.NoError(t, err)
	require.False(t, ok, "a chat with no message has none")

	mkMsg(t, s, "!r", "$m", ghost, "m.room.message", text("hi"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$react", me, "m.reaction", `{"m.relates_to":{"rel_type":"m.annotation","event_id":"$m","key":"x"}}`, time.Unix(20, 0))
	mkMsg(t, s, "!r", "$edit", ghost, "m.room.message", editOf, time.Unix(30, 0))
	e, ok, err := s.LastMessage(ctx, "!r")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "$m", e.EventID)
	require.Equal(t, time.Unix(10, 0).UnixMilli(), e.TS.UnixMilli())
}

func TestAdvanceReadLocalSaysWhetherItMoved(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("a"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("b"), time.Unix(20, 0))

	moved, err := s.AdvanceReadLocal(ctx, "!r", "$b", time.Unix(20, 0))
	require.NoError(t, err)
	require.True(t, moved)
	moved, err = s.AdvanceReadLocal(ctx, "!r", "$b", time.Unix(20, 0))
	require.NoError(t, err)
	require.False(t, moved, "already there")
	moved, err = s.AdvanceReadLocal(ctx, "!r", "$a", time.Unix(10, 0))
	require.NoError(t, err)
	require.False(t, moved, "never backwards")
}

func TestFindReactionIgnoresFailedAndOtherPeople(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	react := func(id, sender, target, key, status string) {
		t.Helper()
		content := `{"m.relates_to":{"rel_type":"m.annotation","event_id":"` + target + `","key":"` + key + `"}}`
		_, err := s.InsertEvent(ctx, Event{
			RoomID: "!r", EventID: id, Sender: sender, Type: "m.reaction",
			Content: json.RawMessage(content), TS: time.Unix(10, 0), Status: status,
		})
		require.NoError(t, err)
	}
	_, ok, err := s.FindReaction(ctx, "!r", me, "$m", "👍")
	require.NoError(t, err)
	require.False(t, ok)

	react("$failed", me, "$m", "👍", "failed")
	react("$theirs", ghost, "$m", "👍", "sent")
	react("$otherkey", me, "$m", "❤️", "sent")
	react("$othertarget", me, "$n", "👍", "sent")
	_, ok, err = s.FindReaction(ctx, "!r", me, "$m", "👍")
	require.NoError(t, err)
	require.False(t, ok, "failed, someone else's, another key and another target do not count")

	react("$pending", me, "$m", "👍", "pending")
	id, ok, err := s.FindReaction(ctx, "!r", me, "$m", "👍")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "$pending", id)
}

func redactionOf(target string) string {
	b, _ := json.Marshal(map[string]string{"redacts": target})
	return string(b)
}

func TestRedactingTheLastMessageFixesTheChatRow(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("first"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("oops, wrong chat"), time.Unix(20, 0))
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread)

	mkMsg(t, s, "!r", "$x", ghost, "m.room.redaction", redactionOf("$b"), time.Unix(30, 0))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "$a", lastEventID(t, s, "!r"), "the chat points at the newest message that is left")
	require.Equal(t, "first", row.Preview, "a deleted message is not the preview")
	require.Equal(t, time.Unix(10, 0).UnixMilli(), row.LastTS.UnixMilli())
	require.Equal(t, 1, row.Unread, "a deleted message is not unread")

	// Deleting an older message leaves the row's message alone but still takes it off the unread count.
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", text("third"), time.Unix(40, 0))
	mkMsg(t, s, "!r", "$y", ghost, "m.room.redaction", redactionOf("$a"), time.Unix(50, 0))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "third", row.Preview)
	require.Equal(t, 1, row.Unread)

	// A redaction of something we do not have, or of a reaction, changes nothing.
	mkMsg(t, s, "!r", "$z", ghost, "m.room.redaction", redactionOf("$never-seen"), time.Unix(60, 0))
	mkMsg(t, s, "!r", "$w", ghost, "m.room.redaction", `not json`, time.Unix(61, 0))
	require.Equal(t, "third", inboxByID(t, s)["!r"].Preview)
}

func TestMigration2MarksEarlierRedactions(t *testing.T) {
	ctx := context.Background()
	db, err := sqlite.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	defer db.Close()
	_, err = db.Exec(ctx, schema)
	require.NoError(t, err)
	require.NoError(t, migrateWith(ctx, db, migrations[:1]))
	_, err = db.Exec(ctx, `INSERT INTO rooms (room_id, network, created_at) VALUES ('!r','whatsapp',1);
INSERT INTO events (event_id, room_id, sender, type, content, ts, status, seq) VALUES
  ('$a','!r','`+ghost+`','m.room.message','{"msgtype":"m.text","body":"kept"}',10,'',1),
  ('$b','!r','`+ghost+`','m.room.message','{"msgtype":"m.text","body":"deleted"}',20,'',2),
  ('$x','!r','`+ghost+`','m.room.redaction','{"redacts":"$b"}',30,'sent',3);
UPDATE rooms SET last_ts=20, last_event_id='$b';`)
	require.NoError(t, err)

	require.NoError(t, migrate(ctx, db))
	s := &Store{db: db, subs: map[chan Change]*subscriber{}}
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "kept", row.Preview)
	require.Equal(t, 1, row.Unread)
}

func TestFailInterruptedSends(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	for id, status := range map[string]string{"$pending": "pending", "$sent": "sent", "$failed": "failed", "$theirs": ""} {
		_, err := s.InsertEvent(ctx, Event{
			RoomID: "!r", EventID: id, Sender: me, Type: "m.room.message", Content: json.RawMessage(text(id)),
			TS: time.Unix(5, 0), Status: status, StatusReason: map[bool]string{true: "offline"}[status == "failed"],
		})
		require.NoError(t, err)
	}
	n, err := s.FailInterruptedSends(ctx)
	require.NoError(t, err)
	require.EqualValues(t, 1, n)
	want := map[string][2]string{
		"$pending": {"failed", ReasonMayHaveBeenSent}, "$sent": {"sent", ""}, "$failed": {"failed", "offline"}, "$theirs": {"", ""},
	}
	for id, w := range want {
		e, ok, err := s.GetEvent(ctx, id)
		require.NoError(t, err)
		require.True(t, ok)
		require.Equal(t, w, [2]string{e.Status, e.StatusReason}, id)
	}
	require.Equal(t, "may have been sent", ReasonMayHaveBeenSent, "the app matches this exact text")
}

// The row's status ticks follow the receipts of its newest message when that message is mine and has gone: sent,
// then delivered, then seen. A receipt for an older message doesn't make the newest seen. Nothing for a message of
// mine that hasn't gone, nor for someone else's.
func TestPreviewStatusFollowsReceipts(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!dm", time.Unix(1, 0))
	status := func() string { t.Helper(); return inboxByID(t, s)["!dm"].PreviewStatus }
	mySent(t, s, "!dm", "$old", t0)
	insert(t, s, Event{
		RoomID: "!dm", EventID: "$m", Sender: me, Type: "m.room.message", Content: []byte(text("hi")),
		TS: t0.Add(time.Second), Status: "pending",
	})
	require.Equal(t, "", status(), "not gone yet")
	require.NoError(t, s.SetStatus(ctx, "$m", "sent", ""))
	require.Equal(t, "sent", status())
	require.NoError(t, s.SetReceipt(ctx, "!dm", ana, "$old", t0.Add(time.Minute)))
	require.Equal(t, "sent", status(), "a receipt for an older message")
	require.NoError(t, s.SetDelivered(ctx, "!dm", ana, "$m", t0.Add(time.Minute)))
	require.Equal(t, "delivered", status())
	require.NoError(t, s.SetReceipt(ctx, "!dm", ana, "$m", t0.Add(2*time.Minute)))
	require.Equal(t, "seen", status())
	mkMsg(t, s, "!dm", "$reply", ana, "m.room.message", text("hello"), t0.Add(3*time.Minute))
	require.Equal(t, "", status(), "someone else's newest message")

	// A message of mine sent from another device (no status of its own) has gone too.
	mkMsg(t, s, "!dm", "$phone", me, "m.room.message", text("from my phone"), t0.Add(4*time.Minute))
	require.Equal(t, "sent", status())
}

func TestInboxAndInboxPageApplyLocalOverrides(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID: "!r1:courier.local", Network: "whatsapp", Name: "Original Name",
		AvatarURI: "mxc://courier.local/orig", IsDirect: true, CreatedAt: time.Unix(1, 0),
	}))
	require.NoError(t, s.SetRoomLocalOverride(ctx, "!r1:courier.local", "Custom Name", "mxc://courier.local/custom"))

	r, ok, err := s.GetRoom(ctx, "!r1:courier.local")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Original Name", r.Name)
	require.Equal(t, "Custom Name", r.LocalName)
	require.Equal(t, "mxc://courier.local/orig", r.AvatarURI)
	require.Equal(t, "mxc://courier.local/custom", r.LocalAvatarURI)

	row := inboxByID(t, s)["!r1:courier.local"]
	require.Equal(t, "Custom Name", row.Name)
	require.Equal(t, "Original Name", row.RemoteName)
	require.Equal(t, "Custom Name", row.LocalName)
	require.Equal(t, "mxc://courier.local/custom", row.AvatarURI)
	require.Equal(t, "mxc://courier.local/custom", row.LocalAvatarURI)

	page, _, err := s.InboxPage(ctx, InboxQuery{})
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, "Custom Name", page[0].Name)
	require.Equal(t, "Original Name", page[0].RemoteName)
	require.Equal(t, "Custom Name", page[0].LocalName)
	require.Equal(t, "mxc://courier.local/custom", page[0].AvatarURI)
	require.Equal(t, "mxc://courier.local/custom", page[0].LocalAvatarURI)
}
