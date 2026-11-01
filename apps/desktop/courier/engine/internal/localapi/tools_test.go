// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

type chatOut struct {
	ID            string           `json:"id"`
	AccountID     string           `json:"accountID"`
	Network       string           `json:"network"`
	Title         string           `json:"title"`
	Type          string           `json:"type"`
	UnreadCount   int              `json:"unreadCount"`
	IsArchived    bool             `json:"isArchived"`
	IsMuted       bool             `json:"isMuted"`
	IsPinned      bool             `json:"isPinned"`
	IsLowPriority bool             `json:"isLowPriority"`
	LastActivity  string           `json:"lastActivity"`
	Participants  []participantOut `json:"participants"`
}

type participantOut struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	IsSelf bool   `json:"isSelf"`
}

type messageOut struct {
	ID          string `json:"id"`
	ChatID      string `json:"chatID"`
	AccountID   string `json:"accountID"`
	SenderID    string `json:"senderID"`
	SenderName  string `json:"senderName"`
	IsSender    bool   `json:"isSender"`
	Timestamp   string `json:"timestamp"`
	Text        string `json:"text"`
	Attachments []struct {
		Type string `json:"type"`
	} `json:"attachments"`
}

type messagesPage struct {
	Messages     []messageOut       `json:"messages"`
	Chats        map[string]chatOut `json:"chats"`
	HasMore      bool               `json:"hasMore"`
	OldestCursor *string            `json:"oldestCursor"`
	NewestCursor *string            `json:"newestCursor"`
}

type chatsPage struct {
	Chats        []chatOut `json:"chats"`
	HasMore      bool      `json:"hasMore"`
	OldestCursor *string   `json:"oldestCursor"`
	NewestCursor *string   `json:"newestCursor"`
}

func TestGetAccounts(t *testing.T) {
	w := newWorld(t, 1)
	sess := w.session(t, false)
	var accounts []struct {
		AccountID   string `json:"accountID"`
		Network     string `json:"network"`
		DisplayName string `json:"displayName"`
		Status      string `json:"status"`
	}
	ok(t, sess, "get_accounts", nil, &accounts)
	require.Len(t, accounts, 1)
	require.Equal(t, string(w.waLogin.ID), accounts[0].AccountID)
	require.Equal(t, "WhatsApp", accounts[0].Network)
	require.NotEmpty(t, accounts[0].DisplayName)
	require.NotEmpty(t, accounts[0].Status)
}

func TestSearchFindsChatsAndMessages(t *testing.T) {
	w := newWorld(t, 3)
	sess := w.session(t, false)
	var res struct {
		Chats                   []chatOut    `json:"chats"`
		GroupParticipantMatches []any        `json:"groupParticipantMatches"`
		Messages                []messageOut `json:"messages"`
	}
	ok(t, sess, "search", map[string]any{"query": "message"}, &res)
	require.Len(t, res.Messages, 3)
	require.Equal(t, "message 2", res.Messages[0].Text, "the whole text, newest first")
	require.Equal(t, w.room, res.Messages[0].ChatID)
	require.Equal(t, string(w.waLogin.ID), res.Messages[0].AccountID)
	require.NotNil(t, res.Chats)
	require.NotNil(t, res.GroupParticipantMatches)
	require.Contains(t, fails(t, sess, "search", map[string]any{"query": " "}), "query is required")
}

func TestListMessagesPagesNewestFirst(t *testing.T) {
	w := newWorld(t, 30)
	sess := w.session(t, false)
	var p1 messagesPage
	ok(t, sess, "list_messages", map[string]any{"chatID": w.room}, &p1)
	require.Len(t, p1.Messages, 20, "20 to a page")
	require.True(t, p1.HasMore)
	require.Equal(t, w.events[29], p1.Messages[0].ID, "newest first")
	require.Equal(t, w.events[10], p1.Messages[19].ID)
	require.Equal(t, "message 29", p1.Messages[0].Text)
	require.Equal(t, "whatsapp_contact", p1.Messages[0].SenderName)
	require.False(t, p1.Messages[0].IsSender)
	_, err := time.Parse(time.RFC3339, p1.Messages[0].Timestamp)
	require.NoError(t, err)

	// New messages arrive; the cursor from page 1 still reads the older ones, with no gap and nothing twice
	// (Review Focus 2).
	w.say(t, 5)
	var p2 messagesPage
	ok(t, sess, "list_messages", map[string]any{"chatID": w.room, "cursor": *p1.OldestCursor, "direction": "before"}, &p2)
	require.Len(t, p2.Messages, 10)
	require.False(t, p2.HasMore)
	require.Equal(t, w.events[9], p2.Messages[0].ID)
	require.Equal(t, w.events[0], p2.Messages[9].ID)

	// And newer than page 1: exactly the five new ones.
	var p3 messagesPage
	ok(t, sess, "list_messages", map[string]any{"chatID": w.room, "cursor": *p1.NewestCursor, "direction": "after"}, &p3)
	require.Len(t, p3.Messages, 5)
	require.False(t, p3.HasMore)
	require.Equal(t, w.events[34], p3.Messages[0].ID, "newest first")
	require.Equal(t, w.events[30], p3.Messages[4].ID)

	// A cursor of {t, id} alone (no seq) is read by its message.
	var p4 messagesPage
	ok(t, sess, "list_messages", map[string]any{"chatID": w.room, "cursor": cursorOf(t, w, w.events[10])}, &p4)
	require.Equal(t, w.events[9], p4.Messages[0].ID)
}

// cursorOf is a {t, id} cursor at a stored message, as the plan defines it.
func cursorOf(t *testing.T, w *world, eventID string) string {
	t.Helper()
	e, found, err := w.s.GetEvent(context.Background(), eventID)
	require.NoError(t, err)
	require.True(t, found)
	return encodeCursor(fmt.Sprintf(`{"t":%d,"id":%q}`, e.TS.UnixMilli(), eventID))
}

// Unknown or malformed IDs and cursors are tool errors in plain words, never a crash or a 500 (Review Focus 1).
func TestUnknownIDsAndBadCursorsAreToolErrors(t *testing.T) {
	w := newWorld(t, 1)
	sess := w.session(t, true)
	const nope = "!nope:courier.local"
	for _, c := range []struct {
		tool string
		args map[string]any
		want string
	}{
		{"get_chat", map[string]any{"chatID": nope}, "No chat or message with that ID"},
		{"list_messages", map[string]any{"chatID": nope}, "No chat or message with that ID"},
		{"list_messages", map[string]any{"chatID": w.room, "cursor": "%%%"}, "cursor"},
		{"list_messages", map[string]any{"chatID": w.room, "cursor": encodeCursor(`{"t":1,"id":"$nope"}`)}, "cursor"},
		{"list_messages", map[string]any{"chatID": w.room, "cursor": encodeCursor(`[1,2]`)}, "cursor"},
		{"list_messages", map[string]any{"chatID": w.room, "direction": "sideways"}, "direction"},
		{"search_chats", map[string]any{"cursor": "bm90IGpzb24"}, "cursor"},
		{"search_messages", map[string]any{"query": "message", "cursor": "x"}, "cursor"},
		{"search_messages", map[string]any{"query": "message", "chatIDs": []string{nope}}, "No chat or message with that ID"},
		{"archive_chat", map[string]any{"chatID": nope}, "No chat or message with that ID"},
		{"send_message", map[string]any{"chatID": nope, "text": "hi"}, "No chat or message with that ID"},
		{"send_message", map[string]any{"chatID": w.room, "text": "hi", "replyToMessageID": "$nope"}, "No chat or message with that ID"},
		{"set_chat_reminder", map[string]any{"chatID": nope, "reminder": map[string]any{"remindAtMs": time.Now().Add(time.Hour).UnixMilli()}}, "No chat or message with that ID"},
		{"clear_chat_reminder", map[string]any{"chatID": nope}, "No chat or message with that ID"},
		{"focus_app", map[string]any{"chatID": nope}, "No chat"},
		{"focus_app", map[string]any{"chatID": w.room, "messageID": "$nope"}, "No message"},
		{"get_chat", map[string]any{"chatID": 5}, "wrong type"},
		{"get_chat", map[string]any{"chatID": w.room, "maxParticipantCount": 501}, "maxParticipantCount"},
	} {
		msg := fails(t, sess, c.tool, c.args)
		require.Contains(t, msg, c.want, "%s %v", c.tool, c.args)
	}
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room}, nil) // still serving
}

func encodeCursor(s string) string {
	return strings.TrimRight(base64URL(s), "=")
}

func TestGetChat(t *testing.T) {
	w := newWorld(t, 2)
	sess := w.session(t, false)
	var chat chatOut
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room}, &chat)
	require.Equal(t, w.room, chat.ID)
	require.Equal(t, "WhatsApp", chat.Network)
	require.Equal(t, string(w.waLogin.ID), chat.AccountID)
	require.Equal(t, 2, chat.UnreadCount)
	require.NotEmpty(t, chat.LastActivity)
	require.NotEmpty(t, chat.Participants)
	require.True(t, slices.ContainsFunc(chat.Participants, func(p participantOut) bool { return p.IsSelf }), "I am one")
	all := len(chat.Participants)
	var none, every, one chatOut
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room, "maxParticipantCount": 0}, &none)
	require.Empty(t, none.Participants)
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room, "maxParticipantCount": -1}, &every)
	require.Len(t, every.Participants, all)
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room, "maxParticipantCount": 1}, &one)
	require.Len(t, one.Participants, 1)
	require.Contains(t, fails(t, sess, "get_chat", map[string]any{"chatID": w.room, "maxParticipantCount": -2}), "maxParticipantCount")
}

func TestSearchChatsFiltersAndPages(t *testing.T) {
	w := newWorld(t, 1)
	ctx := context.Background()
	for i := range 5 {
		id := fmt.Sprintf("!group%d:courier.local", i)
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: id, Network: "whatsapp", Name: fmt.Sprintf("Project group %d", i)}))
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: id, EventID: fmt.Sprintf("$g%d", i), Sender: "@whatsapp_contact:courier.local", Type: "m.room.message",
			Content: []byte(`{"msgtype":"m.text","body":"hello"}`), TS: time.UnixMilli(1_700_000_000_000 + int64(i)*1000), Status: "sent",
		})
		require.NoError(t, err)
	}
	_, err := w.s.SetArchived(ctx, []string{"!group0:courier.local"}, true)
	require.NoError(t, err)
	const dm = "!dm:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: dm, Network: "whatsapp", Name: "A contact", IsDirect: true}))
	planner, plannerName := "@whatsapp_planner:courier.local", "Trip Planner"
	require.NoError(t, w.s.SetProfile(ctx, planner, &plannerName, nil))
	require.NoError(t, w.s.SetMember(ctx, "!group2:courier.local", planner, []byte(`{"membership":"join"}`)))
	sess := w.session(t, false)

	var all chatsPage
	ok(t, sess, "search_chats", nil, &all)
	require.Len(t, all.Chats, 7)
	require.Equal(t, w.room, all.Chats[0].ID, "newest activity first")
	require.Equal(t, dm, all.Chats[6].ID, "no messages: last")
	require.False(t, all.HasMore)

	var groups chatsPage
	ok(t, sess, "search_chats", map[string]any{"type": "group", "query": "project", "inbox": "primary", "limit": 2}, &groups)
	require.Len(t, groups.Chats, 2)
	require.True(t, groups.HasMore)
	require.Equal(t, "!group4:courier.local", groups.Chats[0].ID)
	require.Equal(t, "group", groups.Chats[0].Type)
	var next chatsPage
	ok(t, sess, "search_chats", map[string]any{"type": "group", "query": "project", "inbox": "primary", "limit": 2, "cursor": *groups.OldestCursor}, &next)
	require.Len(t, next.Chats, 2)
	require.Equal(t, "!group2:courier.local", next.Chats[0].ID)
	require.Equal(t, "!group1:courier.local", next.Chats[1].ID)
	ok(t, sess, "search_chats", map[string]any{"type": "group", "query": "project", "inbox": "primary", "limit": 2, "cursor": *next.OldestCursor}, &next)
	require.Empty(t, next.Chats, "group0 is archived, not primary")
	var back chatsPage
	ok(t, sess, "search_chats", map[string]any{"type": "group", "limit": 1, "cursor": *groups.OldestCursor, "direction": "after"}, &back)
	require.Len(t, back.Chats, 1)
	require.Equal(t, "!group4:courier.local", back.Chats[0].ID)

	var archived chatsPage
	ok(t, sess, "search_chats", map[string]any{"inbox": "archive"}, &archived)
	require.Len(t, archived.Chats, 1)
	require.True(t, archived.Chats[0].IsArchived)

	var single chatsPage
	ok(t, sess, "search_chats", map[string]any{"type": "single"}, &single)
	require.Len(t, single.Chats, 1)
	require.Equal(t, dm, single.Chats[0].ID)
	require.Equal(t, "single", single.Chats[0].Type)

	require.NoError(t, w.s.MarkReadLocal(ctx, w.room, w.events[len(w.events)-1], time.Now()))
	var unread chatsPage
	ok(t, sess, "search_chats", map[string]any{"unreadOnly": true}, &unread)
	require.Len(t, unread.Chats, 5, "the five groups; the read chat and the empty DM are not unread")
	for _, c := range unread.Chats {
		require.NotEqual(t, w.room, c.ID)
	}

	var byAccount chatsPage
	ok(t, sess, "search_chats", map[string]any{"accountIDs": []string{"nobody"}}, &byAccount)
	require.Empty(t, byAccount.Chats)

	var recent chatsPage
	ok(t, sess, "search_chats", map[string]any{"lastActivityAfter": time.UnixMilli(1_700_000_002_500).UTC().Format(time.RFC3339), "type": "group"}, &recent)
	require.Len(t, recent.Chats, 3, "the WhatsApp chat (just now), group4 and group3")
	require.Equal(t, w.room, recent.Chats[0].ID)

	var people chatsPage
	ok(t, sess, "search_chats", map[string]any{"scope": "participants", "query": "planner"}, &people)
	require.Len(t, people.Chats, 1, "the planner is a member of one group")
	require.Equal(t, "!group2:courier.local", people.Chats[0].ID)
	var titles chatsPage
	ok(t, sess, "search_chats", map[string]any{"query": "planner"}, &titles)
	require.Empty(t, titles.Chats, "no chat is named for the planner")
}

// limit is clamped to 1–200: 10000 lists 200.
func TestLimitIsClamped(t *testing.T) {
	w := storeOnly(t)
	ctx := context.Background()
	for i := range 205 {
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: fmt.Sprintf("!c%03d:courier.local", i), Network: "whatsapp", Name: "Chat"}))
	}
	_, secret := w.token(t, false)
	sess := w.connect(t, secret)
	var page chatsPage
	ok(t, sess, "search_chats", map[string]any{"limit": 10000}, &page)
	require.Len(t, page.Chats, 200)
	require.True(t, page.HasMore)
	ok(t, sess, "search_chats", map[string]any{"limit": 0}, &page)
	require.Len(t, page.Chats, 1)
}

func TestSearchMessages(t *testing.T) {
	w := newWorld(t, 25)
	sess := w.session(t, false)
	var p1 messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message"}, &p1)
	require.Len(t, p1.Messages, 20, "20 by default")
	require.True(t, p1.HasMore)
	require.Equal(t, w.events[24], p1.Messages[0].ID)
	require.Contains(t, p1.Chats, w.room, "the chats the messages are in")
	var p2 messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "cursor": *p1.OldestCursor}, &p2)
	require.Len(t, p2.Messages, 5)
	require.False(t, p2.HasMore)
	require.Equal(t, w.events[4], p2.Messages[0].ID)

	var mine messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "sender": "me"}, &mine)
	require.Empty(t, mine.Messages)
	var theirs messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "sender": p1.Messages[0].SenderID, "limit": 3}, &theirs)
	require.Len(t, theirs.Messages, 3)
	var other messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "sender": "@someone_else:courier.local"}, &other)
	require.Empty(t, other.Messages)
	var singles messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "chatType": "single"}, &singles)
	require.Empty(t, singles.Messages, "the chat is a group")
	var groups messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "chatType": "group", "limit": 1}, &groups)
	require.Len(t, groups.Messages, 1)
	var images messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "mediaTypes": []string{"image"}}, &images)
	require.Empty(t, images.Messages)
	var later messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "dateAfter": time.Now().Add(time.Hour).UTC().Format(time.RFC3339)}, &later)
	require.Empty(t, later.Messages)
	var newer messagesPage
	ok(t, sess, "search_messages", map[string]any{"query": "message", "cursor": *p2.NewestCursor, "direction": "after", "limit": 3}, &newer)
	require.Len(t, newer.Messages, 3)
	require.Equal(t, w.events[7], newer.Messages[0].ID)
	require.Equal(t, w.events[5], newer.Messages[2].ID)
	require.Contains(t, fails(t, sess, "search_messages", map[string]any{}), "query is required")
}

// Sending is a separate permission, off by default.
func TestSendMessageNeedsPermission(t *testing.T) {
	w := newWorld(t, 1)
	tok, secret := w.token(t, false)
	sess := w.connect(t, secret)
	msg := fails(t, sess, "send_message", map[string]any{"chatID": w.room, "text": "hello"})
	require.Contains(t, msg, "isn't allowed to send messages")
	select {
	case s := <-w.wa.Sent:
		t.Fatalf("nothing should have been sent, got %q", s.Body)
	default:
	}

	// Allowed from the next request on.
	require.NoError(t, w.s.SetAPITokenCanSend(context.Background(), tok.ID, true))
	var sent struct {
		MessageID string `json:"messageID"`
		ChatID    string `json:"chatID"`
		Deeplink  string `json:"deeplink"`
	}
	ok(t, sess, "send_message", map[string]any{"chatID": w.room, "text": "**hello** there", "replyToMessageID": w.events[0]}, &sent)
	require.Equal(t, w.room, sent.ChatID)
	require.Equal(t, "courier://chat/"+w.room, sent.Deeplink)
	require.NotEmpty(t, sent.MessageID)
	got := <-w.wa.Sent
	require.Equal(t, "hello there", got.Body, "Markdown goes as formatting, not as asterisks")
	_, found, err := w.s.GetEvent(context.Background(), sent.MessageID)
	require.NoError(t, err)
	require.True(t, found)

	require.Contains(t, fails(t, sess, "send_message", map[string]any{"chatID": w.room}), "text is required")
	require.Contains(t, fails(t, sess, "send_message", map[string]any{"chatID": w.room, "text": "  "}), "text is required")
}

func TestArchiveChat(t *testing.T) {
	w := newWorld(t, 1)
	sess := w.session(t, false)
	ok(t, sess, "archive_chat", map[string]any{"chatID": w.room}, nil)
	var chat chatOut
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room}, &chat)
	require.True(t, chat.IsArchived, "archived defaults to true")
	ok(t, sess, "archive_chat", map[string]any{"chatID": w.room, "archived": false}, nil)
	ok(t, sess, "get_chat", map[string]any{"chatID": w.room}, &chat)
	require.False(t, chat.IsArchived)
	err := w.s.SetPinned(context.Background(), w.room, true)
	require.NoError(t, err)
	require.Contains(t, fails(t, sess, "archive_chat", map[string]any{"chatID": w.room}), "pinned")
}

func TestChatReminders(t *testing.T) {
	w := newWorld(t, 1)
	sess := w.session(t, false)
	ctx := context.Background()
	at := time.Now().Add(time.Hour).UnixMilli()
	ok(t, sess, "set_chat_reminder", map[string]any{"chatID": w.room, "reminder": map[string]any{"remindAtMs": at, "dismissOnIncomingMessage": true}}, nil)
	rows, _, err := w.s.InboxPage(ctx, store.InboxQuery{RoomIDs: []string{w.room}})
	require.NoError(t, err)
	require.NotNil(t, rows[0].Reminder)
	require.Equal(t, at, rows[0].Reminder.DueAt.UnixMilli())
	require.Equal(t, "if_no_reply", rows[0].Reminder.Condition)

	require.Contains(t, fails(t, sess, "set_chat_reminder", map[string]any{"chatID": w.room, "reminder": map[string]any{"remindAtMs": time.Now().Add(-time.Minute).UnixMilli()}}), "in the past")
	require.Contains(t, fails(t, sess, "set_chat_reminder", map[string]any{"chatID": w.room, "reminder": map[string]any{}}), "remindAtMs is required")

	ok(t, sess, "clear_chat_reminder", map[string]any{"chatID": w.room}, nil)
	rows, _, err = w.s.InboxPage(ctx, store.InboxQuery{RoomIDs: []string{w.room}})
	require.NoError(t, err)
	require.Nil(t, rows[0].Reminder)
	ok(t, sess, "clear_chat_reminder", map[string]any{"chatID": w.room}, nil) // none: no error
}

// focus_app tells the app what to open; a bad attachment is refused before the app hears anything, so it never
// opens a half-filled composer (Review Focus 4).
func TestFocusApp(t *testing.T) {
	w := newWorld(t, 2)
	sess := w.session(t, false)
	dir := t.TempDir()
	file := filepath.Join(dir, "notes.txt")
	require.NoError(t, os.WriteFile(file, []byte("x"), 0o600))
	locked := filepath.Join(dir, "locked.txt")
	require.NoError(t, os.WriteFile(locked, []byte("x"), 0o000))

	for _, c := range []struct {
		path, want string
	}{
		{filepath.Join(dir, "missing.txt"), "doesn't name a file"},
		{dir, "not a folder"},
		{locked, "can't read"},
		{"notes.txt", "absolute path"},
	} {
		msg := fails(t, sess, "focus_app", map[string]any{"chatID": w.room, "draftText": "hi", "draftAttachmentPath": c.path})
		require.Contains(t, msg, c.want, c.path)
	}
	require.Contains(t, fails(t, sess, "focus_app", map[string]any{"draftText": "hi"}), "need a chatID")
	require.Empty(t, w.pub.all(), "nothing reached the app")

	ok(t, sess, "focus_app", map[string]any{"chatID": w.room, "messageID": w.events[0], "draftText": "hi", "draftAttachmentPath": file}, nil)
	ok(t, sess, "focus_app", map[string]any{"messageID": w.events[1]}, nil)
	ok(t, sess, "focus_app", nil, nil)
	sent := w.pub.all()
	require.Len(t, sent, 3)
	require.Equal(t, "app.focus", sent[0].method)
	require.Equal(t, localapi.FocusParams{ChatID: w.room, MessageID: w.events[0], DraftText: "hi", DraftAttachmentPath: file}, sent[0].params)
	require.Equal(t, localapi.FocusParams{ChatID: w.room, MessageID: w.events[1]}, sent[1].params, "a message's chat is found for it")
	require.Equal(t, localapi.FocusParams{}, sent[2].params)

	w.pub.nobody = true
	require.Contains(t, fails(t, sess, "focus_app", nil), "isn't open")
}

func TestSearchDocsIsAStub(t *testing.T) {
	w := storeOnly(t)
	_, secret := w.token(t, false)
	sess := w.connect(t, secret)
	text, isErr := call(t, sess, "search_docs", map[string]any{"query": "send", "language": "python"})
	require.False(t, isErr)
	require.Equal(t, "Courier has no documentation search. Each tool's description is its documentation.", text)
}
