// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// mentioning is a thread reply in root's thread that mentions me.
func mentioning(root, body string) string {
	return `{"msgtype":"m.text","body":"` + body + `","m.mentions":{"user_ids":["` + me + `"]},` +
		`"m.relates_to":{"rel_type":"m.thread","event_id":"` + root + `","is_falling_back":true}}`
}

func summaryOf(t *testing.T, s *Store, roomID, rootID string) ThreadSummary {
	t.Helper()
	got, err := s.ThreadSummaries(context.Background(), roomID, []string{rootID})
	require.NoError(t, err)
	return got[rootID]
}

// threadChat is a chat with a root $a, read on this device up to $main, and two replies in $a's thread after that:
// $a1 from someone else and $a2, which mentions me.
func threadChat(t *testing.T, s *Store) {
	t.Helper()
	ctx := context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("root"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$a1", ghost, "m.room.message", threadReply("$a", "one", false), time.Unix(20, 0))
	mkMsg(t, s, "!r", "$a2", ghost, "m.room.message", mentioning("$a", "two"), time.Unix(21, 0))
	mkMsg(t, s, "!r", "$main", ghost, "m.room.message", text("in the chat"), time.Unix(30, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$main", time.Unix(30, 0)))
}

// Reading the chat on this device reads its main timeline, not its threads: their replies stay unread, in the
// thread's summary and in the chat's unread count, until the thread pane shows them.
func TestReadingTheChatLeavesItsThreadsUnread(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)

	require.Equal(t, ThreadSummary{Replies: 2, LastTS: time.Unix(21, 0), LastSenders: []string{"ghost"}, Unread: 2,
		UnreadMentionsMe: true}, summaryOf(t, s, "!r", "$a"))
	row := inboxByID(t, s)["!r"]
	require.Equal(t, 2, row.Unread, "the chat counts its unread thread replies")
	require.Equal(t, 1, row.UnreadMentions)

	changes, stop := s.Subscribe()
	defer stop()
	moved, err := s.MarkThreadRead(ctx, "!r", "$a")
	require.NoError(t, err)
	require.True(t, moved)
	require.Equal(t, Change{Kind: "read", RoomID: "!r"}, <-changes)
	sum := summaryOf(t, s, "!r", "$a")
	require.Zero(t, sum.Unread)
	require.False(t, sum.UnreadMentionsMe)
	row = inboxByID(t, s)["!r"]
	require.Zero(t, row.Unread)
	require.Zero(t, row.UnreadMentions)

	moved, err = s.MarkThreadRead(ctx, "!r", "$a")
	require.NoError(t, err)
	require.False(t, moved, "read up to its newest reply already")

	mkMsg(t, s, "!r", "$a3", ghost, "m.room.message", threadReply("$a", "three", false), time.Unix(40, 0))
	require.Equal(t, 1, summaryOf(t, s, "!r", "$a").Unread, "a newer reply is unread again")
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread)
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$a3", time.Unix(40, 0)))
	require.Equal(t, 1, inboxByID(t, s)["!r"].Unread, "the chat's own marker doesn't read it, wherever it is")
}

// A thread's marker reads that thread only.
func TestMarkingOneThreadReadLeavesTheOthers(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("another root"), time.Unix(11, 0))
	mkMsg(t, s, "!r", "$b1", ghost, "m.room.message", threadReply("$b", "b one", false), time.Unix(22, 0))

	_, err := s.MarkThreadRead(ctx, "!r", "$b")
	require.NoError(t, err)
	require.Equal(t, 2, summaryOf(t, s, "!r", "$a").Unread)
	require.Zero(t, summaryOf(t, s, "!r", "$b").Unread)
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread)

	moved, err := s.MarkThreadRead(ctx, "!r", "$nothing")
	require.NoError(t, err)
	require.False(t, moved, "a thread with no reply has nothing to read")
}

// Mark as Read from the inbox reads every thread of the chat.
func TestMarkThreadsReadReadsEveryThread(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)
	moved, err := s.MarkThreadsRead(ctx, "!r")
	require.NoError(t, err)
	require.True(t, moved)
	require.Zero(t, summaryOf(t, s, "!r", "$a").Unread)
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
	moved, err = s.MarkThreadsRead(ctx, "!r")
	require.NoError(t, err)
	require.False(t, moved)
}

// What I read on another device, the network says, reads the threads up to there too; the network telling me back
// the receipt this device sent (a marker at this device's own) reads none.
func TestAReadFromAnotherDeviceReadsThreadsButNotItsOwnEcho(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)
	require.NoError(t, s.SetRead(ctx, "!r", "$main", time.Unix(30, 0)))
	require.Equal(t, 2, summaryOf(t, s, "!r", "$a").Unread, "the receipt this device sent, told back")

	mkMsg(t, s, "!r", "$later", ghost, "m.room.message", text("later"), time.Unix(50, 0))
	require.NoError(t, s.SetRead(ctx, "!r", "$later", time.Unix(50, 0)))
	require.Zero(t, summaryOf(t, s, "!r", "$a").Unread)
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
}

// A reply also sent to the channel is a message of the main timeline: the chat's marker reads it, and its thread
// never counts it as unread.
func TestABroadcastReplyIsReadWithTheChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("root"), time.Unix(10, 0))
	mkMsg(t, s, "!r", "$a1", ghost, "m.room.message", threadReply("$a", "both", true), time.Unix(20, 0))
	require.Equal(t, 2, inboxByID(t, s)["!r"].Unread)
	require.Zero(t, summaryOf(t, s, "!r", "$a").Unread)
	require.NoError(t, s.MarkReadLocal(ctx, "!r", "$a1", time.Unix(20, 0)))
	require.Zero(t, inboxByID(t, s)["!r"].Unread)
}

// My own replies are never unread, and the floor follows the chat up past threads that are read, never past one
// that isn't.
func TestTheThreadFloorNeverPassesAnUnreadReply(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)
	mkMsg(t, s, "!r", "$mine", me, "m.room.message", threadReply("$a", "mine", false), time.Unix(31, 0))
	floor, err := s.threadFloor(ctx, "!r")
	require.NoError(t, err)
	a1, _ := getEvent(t, s, "$a1")
	require.Equal(t, position{a1.TS.UnixMilli(), a1.Seq - 1}, floor, "just before the oldest unread reply")
	require.Equal(t, 2, summaryOf(t, s, "!r", "$a").Unread)

	_, err = s.MarkThreadRead(ctx, "!r", "$a")
	require.NoError(t, err)
	floor, err = s.threadFloor(ctx, "!r")
	require.NoError(t, err)
	newest, _, err := s.newestEvent(ctx, "!r")
	require.NoError(t, err)
	require.Equal(t, newest, floor, "every thread is read: the floor is at the newest event")
	var markers int
	require.NoError(t, s.db.QueryRow(ctx, `SELECT COUNT(*) FROM thread_reads`).Scan(&markers))
	require.Zero(t, markers, "the floor covers the thread's marker")
}

// Migration 12 starts every chat's floor at the later of its read markers: nothing read before comes back unread.
func TestMigration12KeepsWhatWasReadRead(t *testing.T) {
	s, _ := openFixtureWith(t, "m10.sql", `
INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id, request) VALUES
  ('!t:courier.local', 'whatsapp', 'T', 0, 1000, 0, '', 0);
INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted) VALUES
  ('$t', '!t:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+text("root")+`', 10000, '', '', 901, 0),
  ('$t1', '!t:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+threadReply("$t", "old", false)+`', 20000, '', '', 902, 0),
  ('$t2', '!t:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+text("read")+`', 30000, '', '', 903, 0),
  ('$t3', '!t:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '`+threadReply("$t", "new", false)+`', 40000, '', '', 904, 0);
INSERT INTO local_reads (room_id, event_id, ts) VALUES ('!t:courier.local', '$t2', 30000);`)
	require.Equal(t, SchemaVersion, userVersion(t, s))
	require.Equal(t, 1, summaryOf(t, s, "!t:courier.local", "$t").Unread, "only the reply after the marker")
	require.Equal(t, 1, inboxByID(t, s)["!t:courier.local"].Unread)
}

// The inbox row says when its newest message is a reply that stays in its thread, and only then.
func TestInboxRowSaysItsPreviewIsInAThread(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!r", time.Unix(1, 0))
	mkMsg(t, s, "!r", "$a", ghost, "m.room.message", text("root"), time.Unix(10, 0))
	require.False(t, inboxByID(t, s)["!r"].PreviewInThread)
	mkMsg(t, s, "!r", "$a1", ghost, "m.room.message", threadReply("$a", "in the thread", false), time.Unix(20, 0))
	row := inboxByID(t, s)["!r"]
	require.True(t, row.PreviewInThread)
	require.Equal(t, "in the thread", row.Preview)
	mkMsg(t, s, "!r", "$a2", ghost, "m.room.message", threadReply("$a", "both", true), time.Unix(30, 0))
	require.False(t, inboxByID(t, s)["!r"].PreviewInThread, "also sent to the channel: it is in the chat too")
}

// The open chat's banner lists its threads with unread replies, the oldest unread first, each at its oldest unread
// reply; a read thread leaves the list.
func TestUnreadThreadsListsEachThreadAtItsOldestUnreadReply(t *testing.T) {
	s, ctx := open(t), context.Background()
	threadChat(t, s)
	mkMsg(t, s, "!r", "$b", ghost, "m.room.message", text("another root"), time.Unix(11, 0))
	mkMsg(t, s, "!r", "$b1", ghost, "m.room.message", threadReply("$b", "b one", false), time.Unix(35, 0))
	mkMsg(t, s, "!r", "$a3", ghost, "m.room.message", threadReply("$a", "three", false), time.Unix(36, 0))

	got, err := s.UnreadThreads(ctx, "!r")
	require.NoError(t, err)
	require.Equal(t, []UnreadThread{
		{RootID: "$a", Unread: 3, MentionsMe: true, FirstUnreadID: "$a1", FirstUnreadTS: time.Unix(20, 0)},
		{RootID: "$b", Unread: 1, FirstUnreadID: "$b1", FirstUnreadTS: time.Unix(35, 0)},
	}, got)

	_, err = s.MarkThreadRead(ctx, "!r", "$a")
	require.NoError(t, err)
	got, err = s.UnreadThreads(ctx, "!r")
	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, "$b", got[0].RootID)
}
