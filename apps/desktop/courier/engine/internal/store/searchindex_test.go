// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store/storetest"
)

// matches returns the IDs of the events whose doc matches a raw FTS5 expression, newest first.
func matches(t *testing.T, s *Store, expr string) []string {
	t.Helper()
	return queryIDs(t, s, `SELECT e.event_id FROM search_messages JOIN events e ON e.doc_id = search_messages.rowid
		WHERE search_messages MATCH $1 ORDER BY search_messages.rowid DESC`, expr)
}

// chatMatches returns the IDs of the chats whose name doc matches expr.
func chatMatches(t *testing.T, s *Store, expr string) []string {
	t.Helper()
	return queryIDs(t, s, `SELECT d.room_id FROM search_chats JOIN chat_docs d ON d.doc_id = search_chats.rowid
		WHERE search_chats MATCH $1 ORDER BY d.room_id`, expr)
}

// peopleMatches returns the user IDs whose person doc matches expr.
func peopleMatches(t *testing.T, s *Store, expr string) []string {
	t.Helper()
	return queryIDs(t, s, `SELECT d.user_id FROM search_people JOIN people_docs d ON d.doc_id = search_people.rowid
		WHERE search_people MATCH $1 ORDER BY d.user_id`, expr)
}

func queryIDs(t *testing.T, s *Store, q string, args ...any) []string {
	t.Helper()
	rows, err := s.db.Query(context.Background(), q, args...)
	require.NoError(t, err)
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var id string
		require.NoError(t, rows.Scan(&id))
		out = append(out, id)
	}
	require.NoError(t, rows.Err())
	return out
}

func count(t *testing.T, s *Store, q string, args ...any) int {
	t.Helper()
	var n int
	require.NoError(t, s.db.QueryRow(context.Background(), q, args...).Scan(&n))
	return n
}

func docID(t *testing.T, s *Store, eventID string) sql.NullInt64 {
	t.Helper()
	var d sql.NullInt64
	require.NoError(t, s.db.QueryRow(context.Background(), "SELECT doc_id FROM events WHERE event_id=$1", eventID).Scan(&d))
	return d
}

func insert(t *testing.T, s *Store, e Event) {
	t.Helper()
	ins, err := s.InsertEvent(context.Background(), e)
	require.NoError(t, err)
	require.True(t, ins)
}

func editTo(target, body string) string {
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": "* " + body,
		"m.new_content": map[string]string{"msgtype": "m.text", "body": body},
		"m.relates_to":  map[string]string{"rel_type": "m.replace", "event_id": target},
	})
	return string(b)
}

func TestMigrationFromMilestone4_1(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile("testdata/m4.sql")
	require.NoError(t, err)
	raw, err := sqlite.Open(path)
	require.NoError(t, err)
	_, err = raw.Exec(ctx, string(fixture))
	require.NoError(t, err)
	var before, maxRowID, events int
	require.NoError(t, raw.QueryRow(ctx, "PRAGMA user_version").Scan(&before))
	require.Equal(t, 3, before, "the fixture is a genuine milestone-4.1 database")
	require.NoError(t, raw.QueryRow(ctx, "SELECT MAX(rowid), count(*) FROM events").Scan(&maxRowID, &events))
	require.GreaterOrEqual(t, events, 20)
	require.NoError(t, raw.Close())

	s, err := Open(path)
	require.NoError(t, err)
	defer s.Close()
	require.GreaterOrEqual(t, userVersion(t, s), 4)
	require.Equal(t, len(migrations), userVersion(t, s))

	require.Equal(t, maxRowID, count(t, s, "SELECT value FROM search_state WHERE key='backfill_until'"))
	require.Equal(t, 0, count(t, s, "SELECT value FROM search_state WHERE key='backfill_after'"))
	// The chats and people on disk wait for the backfill too: 3 rooms, 2 profiles and 5 member rows.
	for key, want := range map[string]int{"chats_until": 3, "profiles_until": 2, "members_until": 5, "chats_after": 0, "profiles_after": 0, "members_after": 0} {
		require.Equal(t, want, count(t, s, "SELECT value FROM search_state WHERE key=$1", key), key)
	}
	// The migration indexes nothing: the backfill does, outside it.
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM events WHERE doc_id IS NOT NULL"))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_messages"))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_chats"))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_people"))

	rows := inboxByID(t, s)
	require.Len(t, rows, 3)
	require.Equal(t, "see https://example.com/seeds", rows["!garden:courier.local"].Preview)
	require.True(t, rows["!trip:courier.local"].Muted)
	require.True(t, rows["!pat:courier.local"].Archived)
	// 4.1 ignored a redaction that arrived before its message; the upgrade repairs that before anything is indexed.
	require.Equal(t, 1, count(t, s, "SELECT redacted FROM events WHERE event_id='$g14'"))
	require.Equal(t, 0, count(t, s, "SELECT redacted FROM events WHERE event_id='$g12'"))

	// The engine keeps working on the upgraded database: a new message is indexed at once.
	insert(t, s, Event{
		RoomID: "!trip:courier.local", EventID: "$t6", Sender: "@ghost3:courier.local",
		Type: "m.room.message", Content: json.RawMessage(text("bring snacks")), TS: time.UnixMilli(190000),
	})
	require.Equal(t, []string{"$t6"}, matches(t, s, `"snacks"`))
}

func TestNewMessagesAreIndexedAtOnce(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$m", ghost, "m.room.message", text("dinner at eight"), time.Unix(10, 0))
	require.Equal(t, []string{"$m"}, matches(t, s, `"dinner"`))
	require.Equal(t, []string{"$m"}, matches(t, s, `"eight"`))

	mkMsg(t, s, "!r", "$react", ghost, "m.reaction", `{"m.relates_to":{"rel_type":"m.annotation","event_id":"$m","key":"dinner"}}`, time.Unix(11, 0))
	mkMsg(t, s, "!r", "$enc", ghost, "m.room.encrypted", `{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"dinner"}`, time.Unix(12, 0))
	key := ""
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$state", Sender: ghost, Type: "m.room.topic", StateKey: &key,
		Content: json.RawMessage(`{"topic":"dinner"}`), TS: time.Unix(13, 0),
	})
	require.NoError(t, err)
	for _, id := range []string{"$react", "$enc", "$state"} {
		require.False(t, docID(t, s, id).Valid, id)
	}
	require.Equal(t, []string{"$m"}, matches(t, s, `"dinner"`))
}

func TestDocIDsFollowTime(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	// Backfill delivers history out of order: the index still yields newest first.
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", text("hello three"), time.UnixMilli(3000))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("hello one"), time.UnixMilli(1000))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("hello two"), time.UnixMilli(2000))
	require.Equal(t, []string{"$c", "$b", "$a"}, matches(t, s, `"hello"`))
	require.Equal(t, int64(3000<<10), docID(t, s, "$c").Int64)

	for i, id := range []string{"$s0", "$s1", "$s2"} {
		mkMsg(t, s, "!r", id, ghost, "m.room.message", text("same millisecond"), time.UnixMilli(5000))
		require.Equal(t, int64(5000<<10|i), docID(t, s, id).Int64, id)
	}

	mkMsg(t, s, "!r", "$neg", ghost, "m.room.message", text("before the epoch"), time.UnixMilli(-5000))
	require.True(t, docID(t, s, "$neg").Valid)
	require.Equal(t, int64(0), docID(t, s, "$neg").Int64, "a negative ts counts as 0")
	require.Equal(t, []string{"$neg"}, matches(t, s, `"epoch"`))

	// With every one of a millisecond's 1,024 doc ids taken, the next message there isn't indexed.
	_, err := s.db.Exec(ctx, `WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 1023)
		INSERT INTO events (event_id, room_id, sender, type, content, ts, seq, doc_id)
		SELECT '$full' || i, '!r', $1, 'm.room.message', '{}', 7000, 1000 + i, (7000 << 10) | i FROM n`, ghost)
	require.NoError(t, err)
	mkMsg(t, s, "!r", "$over", ghost, "m.room.message", text("one too many"), time.UnixMilli(7000))
	require.False(t, docID(t, s, "$over").Valid)
	require.Empty(t, matches(t, s, `"many"`))
}

func TestReplyFallbackIsNotIndexed(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	body := "> <@a> where are you\n\nhome soon"
	reply, _ := json.Marshal(map[string]any{
		"msgtype": "m.text", "body": body,
		"m.relates_to": map[string]any{"m.in_reply_to": map[string]string{"event_id": "$q"}},
	})
	mkMsg(t, s, "!r", "$reply", ghost, "m.room.message", string(reply), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$quote", ghost, "m.room.message", text(body), time.Unix(11, 0))
	require.Equal(t, []string{"$quote", "$reply"}, matches(t, s, `"home"`))
	require.Equal(t, []string{"$quote"}, matches(t, s, `"where"`), "a reply isn't found by the words it quotes")

	got, kind, ok := MessageText("m.room.message", reply)
	require.True(t, ok)
	require.Equal(t, "home soon", got)
	require.Equal(t, "text", kind)
}

func TestMessageText(t *testing.T) {
	for _, c := range []struct {
		typ, content, text, kind string
		ok                       bool
	}{
		{"m.room.message", `{"msgtype":"m.text","body":"hi"}`, "hi", "text", true},
		{"m.room.message", `{"msgtype":"m.notice","body":"hi"}`, "hi", "text", true},
		{"m.room.message", `{"msgtype":"m.emote","body":"hi"}`, "hi", "text", true},
		{"m.room.message", `{"msgtype":"m.image","body":"cat.jpg"}`, "cat.jpg", "image", true},
		{"m.room.message", `{"msgtype":"m.video","body":"v"}`, "v", "video", true},
		{"m.room.message", `{"msgtype":"m.audio","body":"a"}`, "a", "audio", true},
		{"m.room.message", `{"msgtype":"m.file","body":"f.pdf"}`, "f.pdf", "file", true},
		{"m.room.message", `{"msgtype":"m.location","body":"here"}`, "here", "text", true},
		{"m.sticker", `{"body":"waving"}`, "waving", "sticker", true},
		{"m.room.message", editTo("$x", "new"), "", "", false},
		{"m.room.encrypted", `{"body":"x"}`, "", "", false},
		{"m.reaction", `{"body":"x"}`, "", "", false},
		{"m.room.message", `not json`, "", "", false},
	} {
		text, kind, ok := MessageText(c.typ, json.RawMessage(c.content))
		require.Equal(t, c.ok, ok, c.content)
		require.Equal(t, c.text, text, c.content)
		require.Equal(t, c.kind, kind, c.content)
	}
	long := strings.Repeat("é", searchtext.MaxIndexRunes+10)
	text, _, ok := MessageText("m.room.message", json.RawMessage(fmt.Sprintf(`{"msgtype":"m.text","body":%q}`, long)))
	require.True(t, ok)
	require.Equal(t, searchtext.MaxIndexRunes, len([]rune(text)))
}

func TestEditReplacesTheIndexedText(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$o", ghost, "m.room.message", text("meet at noon"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$e", ghost, "m.room.message", editTo("$o", "meet at five"), time.Unix(20, 0))
	require.Empty(t, matches(t, s, `"noon"`))
	require.Equal(t, []string{"$o"}, matches(t, s, `"five"`), "the original is found, not the edit")
	require.False(t, docID(t, s, "$e").Valid, "an edit has no doc of its own")

	// An edit from someone else changes nothing.
	mkMsg(t, s, "!r", "$x", "@other:courier.local", "m.room.message", editTo("$o", "meet at six"), time.Unix(30, 0))
	require.Empty(t, matches(t, s, `"six"`))
	require.Equal(t, []string{"$o"}, matches(t, s, `"five"`))
}

func TestEditBeforeItsMessageStillWins(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$e", ghost, "m.room.message", editTo("$o", "meet at five"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$o", ghost, "m.room.message", text("meet at noon"), time.Unix(10, 0))
	require.Equal(t, []string{"$o"}, matches(t, s, `"five"`))
	require.Empty(t, matches(t, s, `"noon"`))

	// Of two edits the later ts wins, whichever arrives first, and wherever the original falls among them.
	orders := [][]string{{"o", "e1", "e2"}, {"o", "e2", "e1"}, {"e1", "o", "e2"}, {"e2", "o", "e1"}, {"e1", "e2", "o"}, {"e2", "e1", "o"}}
	for i, order := range orders {
		room := fmt.Sprintf("!r%d", i)
		mkRoom(t, s, room, time.Unix(1, 0))
		orig := fmt.Sprintf("$o%d", i)
		for _, which := range order {
			switch which {
			case "o":
				mkMsg(t, s, room, orig, ghost, "m.room.message", text("first word"), time.Unix(10, 0))
			case "e1":
				mkMsg(t, s, room, fmt.Sprintf("$e1-%d", i), ghost, "m.room.message", editTo(orig, "second word"), time.Unix(20, 0))
			case "e2":
				mkMsg(t, s, room, fmt.Sprintf("$e2-%d", i), ghost, "m.room.message", editTo(orig, "third word"), time.Unix(30, 0))
			}
		}
		scope := fmt.Sprintf(`{scope}: %q AND `, RoomScope(room))
		require.Equal(t, []string{orig}, matches(t, s, scope+`"third"`), order)
		require.Empty(t, matches(t, s, scope+`"second"`), order)
		require.Empty(t, matches(t, s, scope+`"first"`), order)
	}
}

func TestRedactedMessageLeavesTheIndex(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$m", ghost, "m.room.message", text("secret plan"), time.Unix(10, 0))
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$r1", Sender: me, Type: "m.room.redaction",
		Content: json.RawMessage(redactionOf("$m")), TS: time.Unix(20, 0), Status: "failed",
	})
	require.NoError(t, err)
	require.Equal(t, []string{"$m"}, matches(t, s, `"secret"`), "a failed redaction removes nothing")
	require.True(t, docID(t, s, "$m").Valid)

	mkMsg(t, s, "!r", "$r2", ghost, "m.room.redaction", redactionOf("$m"), time.Unix(30, 0))
	require.Empty(t, matches(t, s, `"secret"`))
	require.False(t, docID(t, s, "$m").Valid)
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_messages"))

	// An edit arriving after the deletion doesn't bring it back.
	mkMsg(t, s, "!r", "$e", ghost, "m.room.message", editTo("$m", "secret plan b"), time.Unix(40, 0))
	require.Empty(t, matches(t, s, `"secret"`))
}

func TestRedactionBeforeItsMessageKeepsItOut(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$old", ghost, "m.room.message", text("earlier words"), time.Unix(5, 0))
	// The redaction arrives first, then the message it deletes.
	mkMsg(t, s, "!r", "$red", ghost, "m.room.redaction", redactionOf("$m"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$m", ghost, "m.room.message", text("secret plan"), time.Unix(10, 0))
	require.Empty(t, matches(t, s, `"secret"`))
	require.False(t, docID(t, s, "$m").Valid)
	require.Equal(t, 1, count(t, s, "SELECT redacted FROM events WHERE event_id='$m'"), "deleted, as an in-order redaction leaves it")
	row := inboxByID(t, s)["!r"]
	require.Equal(t, "earlier words", row.Preview, "a deleted message isn't the chat's latest")
	require.Equal(t, 1, row.Unread, "nor unread")

	// The same for an edit: its redaction arrives before it, so the original keeps its own text.
	mkMsg(t, s, "!r", "$o", ghost, "m.room.message", text("apple"), time.Unix(30, 0))
	mkMsg(t, s, "!r", "$red2", ghost, "m.room.redaction", redactionOf("$e"), time.Unix(50, 0))
	mkMsg(t, s, "!r", "$e", ghost, "m.room.message", editTo("$o", "banana"), time.Unix(40, 0))
	require.Equal(t, []string{"$o"}, matches(t, s, `"apple"`))
	require.Empty(t, matches(t, s, `"banana"`))
	o, _, err := s.GetEvent(ctx, "$o")
	require.NoError(t, err)
	got, err := s.CurrentText(ctx, o)
	require.NoError(t, err)
	require.Equal(t, "apple", got)

	// A failed redaction that arrived first deletes nothing, and nor does one from another chat.
	mkRoom(t, s, "!other", time.Unix(1, 0))
	_, err = s.InsertEvent(ctx, Event{
		RoomID: "!r", EventID: "$redf", Sender: me, Type: "m.room.redaction",
		Content: json.RawMessage(redactionOf("$k")), TS: time.Unix(70, 0), Status: "failed",
	})
	require.NoError(t, err)
	mkMsg(t, s, "!other", "$redx", ghost, "m.room.redaction", redactionOf("$k"), time.Unix(70, 0))
	mkMsg(t, s, "!r", "$k", ghost, "m.room.message", text("kept words"), time.Unix(60, 0))
	require.Equal(t, []string{"$k"}, matches(t, s, `"kept"`))
}

// Ruling 36: a message whose deletion arrived before it is deleted from the start, so it never brings an archived
// chat back and never cancels a pending auto-archive, as a message from someone else otherwise does.
func TestADeletedMessageArrivingLateLeavesTheArchiveAlone(t *testing.T) {
	s, ctx := open(t), context.Background()
	t0 := time.UnixMilli(1_000_000_000)
	clockAt(s, t0)
	mkRule(t, s, "all", "after_reply", "all", 10*time.Minute)
	chatAt(t, s, "!arch", "whatsapp", t0.Add(-time.Hour))
	_, err := s.SetArchived(ctx, []string{"!arch"}, true)
	require.NoError(t, err)
	chatAt(t, s, "!due", "whatsapp", t0.Add(-time.Hour))
	mkMsg(t, s, "!due", "$mine", me, "m.room.message", text("ok"), t0)
	due := t0.Add(10 * time.Minute)
	require.Equal(t, due, dueAt(t, s, "!due"))

	for _, id := range []string{"!arch", "!due"} {
		mkMsg(t, s, id, "$red"+id, ghost, "m.room.redaction", redactionOf("$gone"+id), t0.Add(2*time.Minute))
		mkMsg(t, s, id, "$gone"+id, ghost, "m.room.message", text("deleted words"), t0.Add(time.Minute))
	}
	require.True(t, rowOf(t, s, "!arch").Archived, "a deleted message doesn't bring the chat back")
	require.Equal(t, due, dueAt(t, s, "!due"), "nor cancel the pending auto-archive")
	require.Equal(t, "hello", rowOf(t, s, "!arch").Preview, "nor is it the chat's latest")

	// A message that isn't deleted still does both.
	mkMsg(t, s, "!arch", "$back1", ghost, "m.room.message", text("still here"), t0.Add(3*time.Minute))
	mkMsg(t, s, "!due", "$back2", ghost, "m.room.message", text("still here"), t0.Add(3*time.Minute))
	require.False(t, rowOf(t, s, "!arch").Archived)
	require.True(t, dueAt(t, s, "!due").IsZero())
}

func TestRedactingAnEditPutsBackTheOneBefore(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$o", ghost, "m.room.message", text("apple"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", editTo("$o", "banana"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$c", ghost, "m.room.message", editTo("$o", "cherry"), time.Unix(30, 0))
	require.Equal(t, []string{"$o"}, matches(t, s, `"cherry"`))

	mkMsg(t, s, "!r", "$red", ghost, "m.room.redaction", redactionOf("$c"), time.Unix(40, 0))
	require.Empty(t, matches(t, s, `"cherry"`))
	require.Equal(t, []string{"$o"}, matches(t, s, `"banana"`))

	mkMsg(t, s, "!r", "$red2", ghost, "m.room.redaction", redactionOf("$b"), time.Unix(50, 0))
	require.Equal(t, []string{"$o"}, matches(t, s, `"apple"`))
	require.Empty(t, matches(t, s, `"banana"`))
}

func TestDiscardingAFailedEditPutsBackTheText(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$o", me, "m.room.message", text("apple"), time.Unix(10, 0))
	insert(t, s, Event{
		RoomID: "!r", EventID: "$e", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(editTo("$o", "banana")), TS: time.Unix(20, 0), Status: "failed",
	})
	// Since 4.3 a failed edit never counts (currentEditSQL), so the old text is already back before the discard.
	require.Empty(t, matches(t, s, `"banana"`))
	require.NoError(t, s.DeleteEvent(ctx, "$e"))
	require.Equal(t, []string{"$o"}, matches(t, s, `"apple"`))
	require.Empty(t, matches(t, s, `"banana"`))
}

func TestDeletingAChatLeavesNoText(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!r", Network: "whatsapp", Name: "Book club"}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!keep", Network: "whatsapp", Name: "Book swap"}))
	mkMsg(t, s, "!r", "$1", ghost, "m.room.message", text("chapter one"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$2", ghost, "m.room.message", text("chapter two"), time.Unix(20, 0))
	mkMsg(t, s, "!keep", "$3", ghost, "m.room.message", text("chapter three"), time.Unix(30, 0))
	require.NoError(t, s.SetMember(ctx, "!r", "@reader:courier.local", json.RawMessage(`{"membership":"join","displayname":"Avid Reader"}`)))
	require.Equal(t, []string{"@reader:courier.local"}, peopleMatches(t, s, `"avid"`))
	scope := fmt.Sprintf(`{scope}: %q`, RoomScope("!r"))
	require.Equal(t, 2, count(t, s, "SELECT count(*) FROM search_messages WHERE search_messages MATCH $1", scope))

	require.NoError(t, s.DeleteRoom(ctx, "!r"))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_messages WHERE search_messages MATCH $1", scope))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_messages"))
	require.Equal(t, []string{"!keep"}, chatMatches(t, s, `"book"`))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_chats"))
	require.Empty(t, peopleMatches(t, s, `"avid"`), "a name only that chat knew goes with it")
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_people"))

	// A failed send that is discarded leaves the index too.
	insert(t, s, Event{
		RoomID: "!keep", EventID: "$f", Sender: me, Type: "m.room.message",
		Content: json.RawMessage(text("typo here")), TS: time.Unix(40, 0), Status: "failed",
	})
	require.Equal(t, []string{"$f"}, matches(t, s, `"typo"`))
	require.NoError(t, s.DeleteEvent(ctx, "$f"))
	require.Empty(t, matches(t, s, `"typo"`))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_messages"))
}

func TestChatAndPeopleDocsFollowTheirNames(t *testing.T) {
	s, ctx := open(t), context.Background()
	name := func(n string) *string { return &n }
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Hiking group"}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!d", Network: "telegram", Name: "Dana Example", IsDirect: true}))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `"hiking"`))
	require.Equal(t, []string{"!d"}, chatMatches(t, s, `{scope}: "dm"`))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `{scope}: "group"`))
	require.Equal(t, []string{"!d"}, chatMatches(t, s, `{scope}: "ntelegram"`))
	require.Equal(t, []string{"!d", "!g"}, chatMatches(t, s, `{scope}: "all"`))

	// Renaming, then clearing the name.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Climbing group"}))
	require.Empty(t, chatMatches(t, s, `"hiking"`))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `"climbing"`))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: ""}))
	require.Empty(t, chatMatches(t, s, `"climbing"`))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM chat_docs WHERE room_id='!g'"))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_chats"))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Hiking group"}))

	// A ghost's profile name changes.
	g1 := "@ghost1:courier.local"
	require.NoError(t, s.SetProfile(ctx, g1, name("Robin Example"), nil))
	require.Equal(t, []string{g1}, peopleMatches(t, s, `"robin"`))
	require.NoError(t, s.SetProfile(ctx, g1, name("Robyn Example"), nil))
	require.Empty(t, peopleMatches(t, s, `"robin"`))
	require.Equal(t, []string{g1}, peopleMatches(t, s, `"robyn"`))
	require.NoError(t, s.SetProfile(ctx, g1, nil, name("mxc://courier.local/avatar")), "an avatar change keeps the name")
	require.Equal(t, []string{g1}, peopleMatches(t, s, `"robyn"`))

	// A member name only one group knows, and the networks of the chats they're in.
	require.NoError(t, s.SetMember(ctx, "!g", g1, json.RawMessage(`{"membership":"join","displayname":"Rob from the trail"}`)))
	require.NoError(t, s.SetMember(ctx, "!d", g1, json.RawMessage(`{"membership":"join"}`)))
	require.Equal(t, []string{g1}, peopleMatches(t, s, `"trail"`))
	require.Equal(t, []string{g1}, peopleMatches(t, s, `{scope}: "nwhatsapp" AND {scope}: "ntelegram"`))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_people"), "one doc per person")

	// The member leaves the group.
	require.NoError(t, s.DeleteMember(ctx, "!g", g1))
	require.Empty(t, peopleMatches(t, s, `"trail"`))
	require.Empty(t, peopleMatches(t, s, `{scope}: "nwhatsapp"`))
	require.Equal(t, []string{g1}, peopleMatches(t, s, `"robyn" AND {scope}: "ntelegram"`))

	// A membership that says they left is not being in the chat.
	g2 := "@ghost2:courier.local"
	require.NoError(t, s.SetMember(ctx, "!g", g2, json.RawMessage(`{"membership":"join","displayname":"Sam Sample"}`)))
	require.Equal(t, []string{g2}, peopleMatches(t, s, `"sam"`))
	require.NoError(t, s.SetMember(ctx, "!g", g2, json.RawMessage(`{"membership":"leave","displayname":"Sam Sample"}`)))
	require.Empty(t, peopleMatches(t, s, `"sam"`))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM people_docs WHERE user_id=$1", g2), "no names left removes the doc")

	// No names left at all.
	require.NoError(t, s.DeleteMember(ctx, "!d", g1))
	require.NoError(t, s.SetProfile(ctx, g1, name(""), nil))
	require.Empty(t, peopleMatches(t, s, `{scope}: "all"`))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM people_docs"))

	// I am never a person.
	require.NoError(t, s.SetProfile(ctx, me, name("Myself Example"), nil))
	require.NoError(t, s.SetMember(ctx, "!g", me, json.RawMessage(`{"membership":"join","displayname":"Myself Example"}`)))
	require.Empty(t, peopleMatches(t, s, `"myself"`))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM search_people"))
}

// Ruling 37b: a chat's doc is re-written only when what it holds changes (its name, or whether it is a DM), not on
// every UpsertRoom of a chat a network sends again unchanged.
func TestUpsertRoomRewritesTheChatDocOnlyWhenItChanges(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Hiking group"}))
	// The stored name moves without its doc (as no write ever leaves it). An UpsertRoom with that same name
	// changes nothing the doc holds, so the doc is left alone: it still has the old words.
	_, err := s.db.Exec(ctx, "UPDATE rooms SET name = 'Climbing group' WHERE room_id = '!g'")
	require.NoError(t, err)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Climbing group", Topic: "a new topic"}))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `"hiking"`), "the same name: the doc is untouched")
	require.Empty(t, chatMatches(t, s, `"climbing"`))

	// A new name, or a chat that becomes a DM, re-writes it.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Running group"}))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `"running"`))
	require.Empty(t, chatMatches(t, s, `"hiking"`))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!g", Network: "whatsapp", Name: "Running group", IsDirect: true}))
	require.Equal(t, []string{"!g"}, chatMatches(t, s, `{scope}: "dm"`))
	require.Empty(t, chatMatches(t, s, `{scope}: "group"`))
}

// Ruling 37a: a long message is cut at MaxIndexRunes of its own text, before normalising. A script written without
// spaces gets a space around each character when normalised, so cutting after would keep only half as much of it.
func TestLongTextWithoutSpacesIsIndexedAsFarAsAnyOther(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	body := strings.Repeat("東", 12000) + "京都" + strings.Repeat("東", 3000)
	mkMsg(t, s, "!r", "$long", ghost, "m.room.message", text(body), time.Unix(10, 0))
	require.Equal(t, []string{"$long"}, matches(t, s, searchtext.MatchAll("body", searchtext.Parse("京都"))),
		"a word near character 12,000 is found")
	past := strings.Repeat("東", searchtext.MaxIndexRunes) + "大阪"
	mkMsg(t, s, "!r", "$past", ghost, "m.room.message", text(past), time.Unix(20, 0))
	require.Empty(t, matches(t, s, searchtext.MatchAll("body", searchtext.Parse("大阪"))), "past the limit is not")
}

func TestScopeTokens(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa", Network: "whatsapp", Name: "Family"}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tg", Network: "telegram", Name: "Work", IsDirect: true}))
	mkMsg(t, s, "!wa", "$img", me, "m.room.message",
		`{"msgtype":"m.image","body":"look at https://example.com/beach","url":"mxc://courier.local/beach"}`, time.Unix(10, 0))
	mkMsg(t, s, "!wa", "$txt", ghost, "m.room.message", text("lovely beach"), time.Unix(20, 0))
	mkMsg(t, s, "!tg", "$stk", ghost, "m.sticker", `{"body":"beach ball","url":"mxc://courier.local/ball"}`, time.Unix(30, 0))
	mkMsg(t, s, "!tg", "$vid", ghost, "m.room.message", `{"msgtype":"m.video","body":"beach.mp4"}`, time.Unix(40, 0))
	mkMsg(t, s, "!tg", "$aud", ghost, "m.room.message", `{"msgtype":"m.audio","body":"beach audio"}`, time.Unix(50, 0))
	mkMsg(t, s, "!tg", "$fil", ghost, "m.room.message", `{"msgtype":"m.file","body":"beach.pdf"}`, time.Unix(60, 0))

	require.Equal(t, []string{"$img"}, matches(t, s, `{scope}: "me" AND {scope}: "kimage" AND {scope}: "klink" AND {scope}: "nwhatsapp"`))
	require.Equal(t, []string{"$fil", "$aud", "$vid", "$stk", "$txt", "$img"}, matches(t, s, `{scope}: "all"`))
	require.Equal(t, []string{"$txt"}, matches(t, s, `{scope}: "ktext"`))
	require.Equal(t, []string{"$stk"}, matches(t, s, `{scope}: "ksticker"`))
	require.Equal(t, []string{"$vid"}, matches(t, s, `{scope}: "kvideo"`))
	require.Equal(t, []string{"$aud"}, matches(t, s, `{scope}: "kaudio"`))
	require.Equal(t, []string{"$fil"}, matches(t, s, `{scope}: "kfile"`))
	require.Equal(t, []string{"$img"}, matches(t, s, `{scope}: "klink"`))
	require.Equal(t, []string{"$txt", "$img"}, matches(t, s, fmt.Sprintf(`{scope}: %q`, RoomScope("!wa"))))
	require.Equal(t, []string{"$img"}, matches(t, s, fmt.Sprintf(`{scope}: %q`, SenderScope(me))))
	require.Equal(t, []string{"$fil", "$aud", "$vid", "$stk", "$txt"}, matches(t, s, fmt.Sprintf(`{scope}: %q`, SenderScope(ghost))))
	require.Empty(t, matches(t, s, `{body}: "me" OR {body}: "kimage" OR {body}: "nwhatsapp"`), "scope tokens stay out of the text")
	require.Equal(t, "nwhatsapp", NetworkScope("WhatsApp"))
	require.Regexp(t, `^r[0-9a-f]{16}$`, RoomScope("!wa"))
	require.Regexp(t, `^s[0-9a-f]{16}$`, SenderScope(me))

	// An edit that adds a link makes it a link message.
	mkMsg(t, s, "!wa", "$e", ghost, "m.room.message", editTo("$txt", "lovely beach http://example.com"), time.Unix(70, 0))
	require.Equal(t, []string{"$txt", "$img"}, matches(t, s, `{scope}: "klink"`))
}

func TestIndexedTextIsNormalised(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$jp", ghost, "m.room.message", text("東京タワーで会いましょう"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$fw", ghost, "m.room.message", text("Ｈｅｌｌｏ José"), time.Unix(20, 0))
	require.Equal(t, []string{"$jp"}, matches(t, s, searchtext.MatchAll("body", searchtext.Parse("京タ "))))
	require.Equal(t, []string{"$fw"}, matches(t, s, searchtext.MatchAll("body", searchtext.Parse("hello jose "))))
}

func TestCurrentText(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$o", ghost, "m.room.message", text("apple"), time.Unix(10, 0))
	e, _, err := s.GetEvent(ctx, "$o")
	require.NoError(t, err)
	got, err := s.CurrentText(ctx, e)
	require.NoError(t, err)
	require.Equal(t, "apple", got)
	mkMsg(t, s, "!r", "$e", ghost, "m.room.message", editTo("$o", "banana"), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$bad", ghost, "m.room.message", `{"msgtype":"m.text","body":"* x","m.relates_to":{"rel_type":"m.replace","event_id":"$o"}}`, time.Unix(30, 0))
	got, err = s.CurrentText(ctx, e)
	require.NoError(t, err)
	require.Equal(t, "banana", got, "an edit with no new content is passed over")
}

func TestEditLookupUsesItsIndex(t *testing.T) {
	s, ctx := open(t), context.Background()
	rows, err := s.db.Query(ctx, "EXPLAIN QUERY PLAN "+currentEditSQL, "$o", ghost)
	require.NoError(t, err)
	defer rows.Close()
	var plan []string
	for rows.Next() {
		var id, parent, notused int
		var detail string
		require.NoError(t, rows.Scan(&id, &parent, &notused, &detail))
		plan = append(plan, detail)
	}
	require.NoError(t, rows.Err())
	require.Contains(t, strings.Join(plan, "\n"), "USING INDEX events_edits", plan)

	rows2, err := s.db.Query(ctx, "EXPLAIN QUERY PLAN "+docIDsInMillisecondSQL, 1<<10, 1<<10|1023)
	require.NoError(t, err)
	defer rows2.Close()
	plan = nil
	for rows2.Next() {
		var id, parent, notused int
		var detail string
		require.NoError(t, rows2.Scan(&id, &parent, &notused, &detail))
		plan = append(plan, detail)
	}
	require.Contains(t, strings.Join(plan, "\n"), "events_doc", plan)

	rows3, err := s.db.Query(ctx, "EXPLAIN QUERY PLAN "+earlierRedactionSQL, "$m", "!r")
	require.NoError(t, err)
	defer rows3.Close()
	plan = nil
	for rows3.Next() {
		var id, parent, notused int
		var detail string
		require.NoError(t, rows3.Scan(&id, &parent, &notused, &detail))
		plan = append(plan, detail)
	}
	require.Contains(t, strings.Join(plan, "\n"), "USING INDEX events_redacts", plan)
}

// openFixture loads testdata/name, a database as an earlier milestone left it, at a new path and opens it with the
// store, which migrates it.
func openFixture(t *testing.T, name string) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "courier.db")
	fixture, err := os.ReadFile(filepath.Join("testdata", name))
	require.NoError(t, err)
	raw, err := sqlite.Open(path)
	require.NoError(t, err)
	_, err = raw.Exec(context.Background(), string(fixture))
	require.NoError(t, err)
	require.NoError(t, raw.Close())
	s, err := Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s, path
}

// openSeeded is a store whose database held n messages, a chat and a person before migration 4 (see storetest).
func openSeeded(t *testing.T, n int) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "courier.db")
	s, err := Open(path)
	require.NoError(t, err)
	require.NoError(t, s.Close())
	storetest.SeedUnindexed(t, path, n)
	s, err = Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s, path
}

// backfillAll runs BackfillSearch until it is done and returns how many batches that took.
func backfillAll(t *testing.T, s *Store, batch int) int {
	t.Helper()
	for calls := 1; calls <= 1_000_000; calls++ {
		done, err := s.BackfillSearch(context.Background(), batch)
		require.NoError(t, err)
		if done {
			return calls
		}
	}
	t.Fatal("the backfill never finished")
	return 0
}

func searchComplete(t *testing.T, s *Store) bool {
	t.Helper()
	complete, err := s.SearchComplete(context.Background())
	require.NoError(t, err)
	return complete
}

func stateValue(t *testing.T, s *Store, key string) int {
	t.Helper()
	return count(t, s, "SELECT value FROM search_state WHERE key=$1", key)
}

func TestBackfillIndexesTheMilestone4_1Database(t *testing.T) {
	s, _ := openFixture(t, "m4.sql")
	require.False(t, searchComplete(t, s), "nothing on disk is indexed yet")
	backfillAll(t, s, 2000)
	require.True(t, searchComplete(t, s))

	// Every message a person can read is found by a word of its text: replies by their own words, a file by its
	// name, a failed send that wasn't discarded too.
	for word, want := range map[string]string{
		"tomatoes": "$g2", "raised": "$g3", "looks": "$g4", "waving": "$g11", "seeds": "$g12", "saturday": "$p1",
		"lunch": "$p2", "directions": "$p3", "train": "$t1", "platform": "$t2", "voice": "$t3", "waves": "$t4", "there": "$t5",
	} {
		require.Equal(t, []string{want}, matches(t, s, fmt.Sprintf("%q", word)), word)
	}
	// The edited message by its edit, not its old words; the edit itself has no doc.
	require.Equal(t, []string{"$g5"}, matches(t, s, `"five"`))
	require.Empty(t, matches(t, s, `"noon"`))
	// The Japanese message by two of its characters.
	require.Equal(t, []string{"$p4"}, matches(t, s, searchtext.MatchAll("body", searchtext.Parse("京タ "))))
	// Not the deleted ones (one deleted in order, one whose deletion arrived first), the encrypted one, a reaction
	// or state.
	for _, word := range []string{"wrong", "mistake", "megolm", "aaaa", "garden"} {
		require.Empty(t, matches(t, s, fmt.Sprintf("%q", word)), word)
	}
	for _, id := range []string{"$g1", "$g6", "$g7", "$g8", "$g9", "$g10", "$g13", "$g14"} {
		require.False(t, docID(t, s, id).Valid, id)
	}
	require.Equal(t, 15, count(t, s, "SELECT count(*) FROM search_messages"))
	require.Equal(t, int64(200000<<10), docID(t, s, "$g12").Int64, "a doc id encodes its message's time")

	// Ruling 11: the chats' names and the people on disk are indexed too; I am not a person.
	require.Equal(t, []string{"!garden:courier.local"}, chatMatches(t, s, `"garden"`))
	require.Equal(t, []string{"!trip:courier.local"}, chatMatches(t, s, `"planning"`))
	require.Equal(t, []string{"!pat:courier.local"}, chatMatches(t, s, `"pat"`))
	require.Equal(t, 3, count(t, s, "SELECT count(*) FROM search_chats"))
	require.Equal(t, []string{"@ghost1:courier.local"}, peopleMatches(t, s, `"garden"`), "by the name a chat knows them by")
	require.Equal(t, []string{"@ghost2:courier.local"}, peopleMatches(t, s, `"robin"`))
	require.Equal(t, []string{"@ghost3:courier.local"}, peopleMatches(t, s, `"lee"`))
	require.Equal(t, 3, count(t, s, "SELECT count(*) FROM search_people"))

	// Task 10's by-hand check opens this database in the app: bazel test --test_env=COURIER_KEEP_DB=1 leaves it in
	// the test's outputs.
	if os.Getenv("COURIER_KEEP_DB") == "1" {
		out := os.Getenv("TEST_UNDECLARED_OUTPUTS_DIR")
		require.NotEmpty(t, out, "COURIER_KEEP_DB needs bazel test, which sets TEST_UNDECLARED_OUTPUTS_DIR")
		_, err := s.db.Exec(context.Background(), "VACUUM INTO $1", filepath.Join(out, "courier.db"))
		require.NoError(t, err)
	}
}

// Review Focus 4: quitting halfway resumes where it stopped, and nothing is indexed twice.
func TestBackfillResumesAndIndexesEachMessageOnce(t *testing.T) {
	const n = 5000
	ctx := context.Background()
	s, path := openSeeded(t, n)
	for range 2 {
		done, err := s.BackfillSearch(ctx, 1000)
		require.NoError(t, err)
		require.False(t, done)
	}
	after := stateValue(t, s, "backfill_after")
	require.Greater(t, after, 0)
	require.Less(t, after, n)
	// Everything up to the cursor is indexed and nothing past it, so a stop here loses and repeats nothing.
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM events WHERE rowid <= $1 AND doc_id IS NULL", after))
	require.Equal(t, 0, count(t, s, "SELECT count(*) FROM events WHERE rowid > $1 AND doc_id IS NOT NULL", after))
	require.False(t, searchComplete(t, s))

	// Quit and start again.
	require.NoError(t, s.Close())
	s, err := Open(path)
	require.NoError(t, err)
	defer s.Close()
	require.Equal(t, after, stateValue(t, s, "backfill_after"), "the cursor survives a restart")
	require.GreaterOrEqual(t, backfillAll(t, s, 1000), 3)
	require.True(t, searchComplete(t, s))

	require.Equal(t, n, count(t, s, "SELECT count(*) FROM events WHERE doc_id IS NOT NULL"))
	require.Equal(t, n, count(t, s, "SELECT count(DISTINCT doc_id) FROM events"))
	require.Len(t, matches(t, s, `{scope}: "all"`), n)
	for i := 1; i <= n; i += 97 {
		require.Equal(t, []string{storetest.SeedEventID(i)}, matches(t, s, fmt.Sprintf("%q", storetest.SeedWord(i))), i)
	}
	// Three messages to a millisecond: the doc ids still follow time, and order within it.
	require.Equal(t, storetest.SeedTS(4)<<10|1, docID(t, s, storetest.SeedEventID(4)).Int64)
	require.Equal(t, []string{storetest.SeedRoom}, chatMatches(t, s, `"seed"`))
	require.Equal(t, []string{storetest.SeedPerson}, peopleMatches(t, s, `"seed"`))

	// A third run finds nothing to do and changes nothing.
	sum := count(t, s, "SELECT SUM(doc_id) % 1000000007 FROM events")
	done, err := s.BackfillSearch(ctx, 1000)
	require.NoError(t, err)
	require.True(t, done)
	require.Equal(t, sum, count(t, s, "SELECT SUM(doc_id) % 1000000007 FROM events"))
	require.Len(t, matches(t, s, `{scope}: "all"`), n)
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_chats"))
	require.Equal(t, 1, count(t, s, "SELECT count(*) FROM search_people"))
}

// What happens live between two batches is never undone or doubled by the backfill.
func TestNewMessagesDuringBackfillAreNotIndexedTwice(t *testing.T) {
	ctx := context.Background()
	s, _ := openSeeded(t, 100)
	until := stateValue(t, s, "backfill_until")
	done, err := s.BackfillSearch(ctx, 20)
	require.NoError(t, err)
	require.False(t, done)
	for _, i := range []int{70, 80, 90, 99} {
		require.False(t, docID(t, s, storetest.SeedEventID(i)).Valid, "not reached yet")
	}

	// A new message lands inside the backfill's range (it takes the rowid of a deleted one) and in the same
	// millisecond as messages the backfill hasn't reached.
	require.NoError(t, s.DeleteEvent(ctx, storetest.SeedEventID(100)))
	insert(t, s, Event{
		RoomID: storetest.SeedRoom, EventID: "$live", Sender: ghost, Type: "m.room.message",
		Content: json.RawMessage(text("arrived meanwhile")), TS: time.UnixMilli(storetest.SeedTS(90)),
	})
	require.LessOrEqual(t, count(t, s, "SELECT rowid FROM events WHERE event_id='$live'"), until)
	live := docID(t, s, "$live")
	require.True(t, live.Valid, "indexed by InsertEvent at once")
	require.Equal(t, []string{"$live"}, matches(t, s, `"meanwhile"`))
	// An edit and a deletion of messages the backfill hasn't reached yet.
	insert(t, s, Event{
		RoomID: storetest.SeedRoom, EventID: "$edit", Sender: storetest.SeedSender, Type: "m.room.message",
		Content: json.RawMessage(editTo(storetest.SeedEventID(80), "changed later")), TS: time.UnixMilli(2_000_000),
	})
	insert(t, s, Event{
		RoomID: storetest.SeedRoom, EventID: "$red", Sender: storetest.SeedSender, Type: "m.room.redaction",
		Content: json.RawMessage(redactionOf(storetest.SeedEventID(70))), TS: time.UnixMilli(2_000_001),
	})

	backfillAll(t, s, 20)
	require.True(t, searchComplete(t, s))
	require.Equal(t, live, docID(t, s, "$live"), "the backfill left the live doc alone")
	require.Equal(t, []string{"$live"}, matches(t, s, `"meanwhile"`))
	require.Equal(t, []string{storetest.SeedEventID(80)}, matches(t, s, `"changed"`), "indexed with the edit that came first")
	require.Empty(t, matches(t, s, fmt.Sprintf("%q", storetest.SeedWord(80))))
	require.Empty(t, matches(t, s, fmt.Sprintf("%q", storetest.SeedWord(70))), "deleted before the backfill reached it")
	require.False(t, docID(t, s, storetest.SeedEventID(70)).Valid)
	require.Equal(t, 99, count(t, s, "SELECT count(*) FROM search_messages"), "98 old messages and the new one")
	require.Equal(t, 99, count(t, s, "SELECT count(DISTINCT doc_id) FROM events"))
	for _, id := range []string{storetest.SeedEventID(90), storetest.SeedEventID(91), storetest.SeedEventID(92)} {
		require.Equal(t, storetest.SeedTS(90), docID(t, s, id).Int64>>10, "in its own millisecond, beside $live")
	}
}

// A million messages on disk: each batch walks the events table by rowid, never all of it.
func TestBackfillWalksByRowid(t *testing.T) {
	s, ctx := open(t), context.Background()
	for name, q := range map[string]struct {
		sql  string
		args []any
	}{
		"next":     {fmt.Sprintf(backfillNextSQL, "events"), []any{0, 1000, 2000}},
		"messages": {backfillMessagesSQL, []any{0, 1000}},
	} {
		rows, err := s.db.Query(ctx, "EXPLAIN QUERY PLAN "+q.sql, q.args...)
		require.NoError(t, err)
		var plan []string
		for rows.Next() {
			var id, parent, notused int
			var detail string
			require.NoError(t, rows.Scan(&id, &parent, &notused, &detail))
			plan = append(plan, detail)
		}
		require.NoError(t, rows.Err())
		require.NoError(t, rows.Close())
		require.Contains(t, strings.Join(plan, "\n"), "INTEGER PRIMARY KEY (rowid>? AND rowid<?)", name, plan)
	}
}

// The backfill and live writes run at the same time, in the same milliseconds: each batch holds the write lock
// before it reads which doc ids are taken, so neither ever fails and no doc id is taken twice.
func TestBackfillAndLiveWritesTakeTurns(t *testing.T) {
	const n = 600
	ctx := context.Background()
	s, _ := openSeeded(t, n)
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		for {
			done, err := s.BackfillSearch(ctx, 7)
			if err != nil || done {
				errs <- err
				return
			}
		}
	}()
	go func() {
		defer wg.Done()
		for i := 1; i <= n; i++ {
			if _, err := s.InsertEvent(ctx, Event{
				RoomID: storetest.SeedRoom, EventID: fmt.Sprintf("$live%d", i), Sender: ghost, Type: "m.room.message",
				Content: json.RawMessage(text("live one")), TS: time.UnixMilli(storetest.SeedTS(i)),
			}); err != nil {
				errs <- err
				return
			}
		}
		errs <- nil
	}()
	wg.Wait()
	close(errs)
	for err := range errs {
		require.NoError(t, err)
	}
	require.True(t, searchComplete(t, s))
	require.Equal(t, 2*n, count(t, s, "SELECT count(DISTINCT doc_id) FROM events"))
	require.Equal(t, 2*n, count(t, s, "SELECT count(*) FROM search_messages"))
	require.Len(t, matches(t, s, `"live"`), n)
}

// Ruling 14: a batch over long messages runs out of time before it runs out of rows. It commits what it indexed,
// and the next batch starts right after the last message it took, so each is indexed once. The clock is the
// test's: every look at it is 10 ms later, so a 50 ms budget lets a batch take a handful of rows.
func TestBackfillBatchStopsWhenItsTimeIsSpent(t *testing.T) {
	const n = 200
	ctx := context.Background()
	s, _ := openSeeded(t, n)
	_, err := s.db.Exec(ctx, `UPDATE events SET content = json_object('msgtype', 'm.text',
		'body', 'seed message w' || substr(event_id, 6) || ' ' || $1) WHERE event_id LIKE '$seed%'`,
		strings.Repeat("long ", searchtext.MaxIndexRunes/5))
	require.NoError(t, err)
	var clock time.Time
	s.backfillNow = func() time.Time {
		clock = clock.Add(10 * time.Millisecond)
		return clock
	}
	s.backfillBudget = 50 * time.Millisecond

	batches := 0
	for after := 0; ; batches++ {
		done, err := s.BackfillSearch(ctx, 2000)
		require.NoError(t, err)
		next := stateValue(t, s, "backfill_after")
		indexed := count(t, s, "SELECT count(*) FROM events WHERE doc_id IS NOT NULL")
		// The cursor is the last message indexed: everything up to it has its doc, nothing after it does.
		require.Equal(t, next, indexed)
		require.Equal(t, indexed, count(t, s, "SELECT count(*) FROM events WHERE rowid <= $1 AND doc_id IS NOT NULL", next))
		if done {
			require.Equal(t, n, next)
			break
		}
		require.Greater(t, next, after, "every batch indexes at least one message")
		require.LessOrEqual(t, next-after, 5, "and stops once its 50 ms are spent, far short of 2,000 rows")
		after = next
	}
	require.Greater(t, batches, 10)
	require.True(t, searchComplete(t, s))
	require.Equal(t, n, count(t, s, "SELECT count(DISTINCT doc_id) FROM events"))
	require.Equal(t, n, count(t, s, "SELECT count(*) FROM search_messages"))
	for i := 1; i <= n; i += 13 {
		require.Equal(t, []string{storetest.SeedEventID(i)}, matches(t, s, fmt.Sprintf("%q", storetest.SeedWord(i))), i)
	}
}

// Messages whose millisecond has no doc id left are reported once per batch, with how many, not once each.
func TestBackfillWarnsOncePerBatchForFullMilliseconds(t *testing.T) {
	ctx := context.Background()
	s, _ := openSeeded(t, 30)
	s.backfillNow = func() time.Time { return time.Time{} } // never out of time: one batch
	// Seeds 3-5 and 6-8 share two milliseconds; fill both (with rows past the backfill's range).
	for _, ms := range []int64{storetest.SeedTS(3), storetest.SeedTS(6)} {
		_, err := s.db.Exec(ctx, `WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 1023)
			INSERT INTO events (event_id, room_id, sender, type, content, ts, seq, doc_id)
			SELECT '$full' || $2 || '-' || i, $1, $3, 'm.room.message', '{}', $2, 100000 + $2 * 2000 + i, ($2 << 10) | i FROM n`,
			storetest.SeedRoom, ms, ghost)
		require.NoError(t, err)
	}
	var lb strings.Builder
	log := zerolog.New(&lb).Level(zerolog.InfoLevel)
	done, err := s.BackfillSearch(log.WithContext(ctx), 2000)
	require.NoError(t, err)
	require.True(t, done)
	lines := strings.Split(strings.TrimSpace(lb.String()), "\n")
	require.Len(t, lines, 1, lb.String())
	var warning struct {
		Level    string `json:"level"`
		Messages int    `json:"messages"`
	}
	require.NoError(t, json.Unmarshal([]byte(lines[0]), &warning))
	require.Equal(t, "warn", warning.Level)
	require.Equal(t, 6, warning.Messages)
	require.Equal(t, 24, count(t, s, "SELECT count(*) FROM search_messages"))
}
