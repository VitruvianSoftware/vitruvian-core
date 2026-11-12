// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package imessage

import (
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/host"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

const testChatDBSchema = `
CREATE TABLE handle (
	ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
	id TEXT NOT NULL,
	service TEXT NOT NULL DEFAULT 'iMessage'
);

CREATE TABLE chat (
	ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
	guid TEXT NOT NULL,
	chat_identifier TEXT NOT NULL,
	service_name TEXT NOT NULL DEFAULT 'iMessage',
	display_name TEXT DEFAULT '',
	style INTEGER DEFAULT 45
);

CREATE TABLE chat_handle_join (
	chat_id INTEGER NOT NULL,
	handle_id INTEGER NOT NULL
);

CREATE TABLE message (
	ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
	guid TEXT NOT NULL,
	text TEXT,
	attributedBody BLOB,
	handle_id INTEGER DEFAULT 0,
	service TEXT DEFAULT 'iMessage',
	date INTEGER DEFAULT 0,
	date_read INTEGER DEFAULT 0,
	date_delivered INTEGER DEFAULT 0,
	date_edited INTEGER DEFAULT 0,
	is_from_me INTEGER DEFAULT 0,
	is_read INTEGER DEFAULT 0,
	is_delivered INTEGER DEFAULT 0,
	thread_originator_guid TEXT DEFAULT '',
	reply_to_guid TEXT DEFAULT '',
	associated_message_guid TEXT DEFAULT '',
	associated_message_type INTEGER DEFAULT 0,
	associated_message_emoji TEXT DEFAULT ''
);

CREATE TABLE chat_message_join (
	chat_id INTEGER NOT NULL,
	message_id INTEGER NOT NULL,
	message_date INTEGER DEFAULT 0
);

CREATE TABLE attachment (
	ROWID INTEGER PRIMARY KEY AUTOINCREMENT,
	guid TEXT NOT NULL,
	filename TEXT NOT NULL,
	transfer_name TEXT DEFAULT '',
	mime_type TEXT DEFAULT 'application/octet-stream',
	total_bytes INTEGER DEFAULT 0,
	is_sticker INTEGER DEFAULT 0
);

CREATE TABLE message_attachment_join (
	message_id INTEGER NOT NULL,
	attachment_id INTEGER NOT NULL
);
`

func createTestChatDB(t *testing.T, dbPath string) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", "file:"+dbPath+"?_busy_timeout=5000&_journal_mode=WAL")
	require.NoError(t, err)
	t.Cleanup(func() { _ = db.Close() })
	_, err = db.Exec(testChatDBSchema)
	require.NoError(t, err)
	return db
}

type mockSender struct {
	mu        sync.Mutex
	messages  []OutboundMessage
	reactions []OutboundReaction
	db        *sql.DB
}

func (m *mockSender) SendMessage(_ context.Context, msg OutboundMessage) (SendResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.messages = append(m.messages, msg)

	now := time.Now().UTC()
	guid := "out-guid-" + generateUUIDv4()
	if m.db != nil {
		var chatRowID int64
		err := m.db.QueryRow(`SELECT ROWID FROM chat WHERE guid = ? OR chat_identifier = ? LIMIT 1`, msg.ChatGUID, msg.ChatIdentifier).Scan(&chatRowID)
		if err == nil && chatRowID > 0 {
			res, err := m.db.Exec(
				`INSERT INTO message (guid, text, handle_id, service, date, is_from_me, thread_originator_guid) VALUES (?, ?, 0, ?, ?, 1, ?)`,
				guid, msg.Text, msg.Service, TimeToAppleNano(now), msg.ReplyToGUID,
			)
			if err == nil {
				msgRowID, _ := res.LastInsertId()
				_, _ = m.db.Exec(`INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (?, ?, ?)`, chatRowID, msgRowID, TimeToAppleNano(now))
			}
		}
	}
	return SendResult{GUID: guid, Timestamp: now}, nil
}

func (m *mockSender) SendReaction(_ context.Context, react OutboundReaction) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.reactions = append(m.reactions, react)
	return nil
}

func (m *mockSender) SentMessages() []OutboundMessage {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]OutboundMessage(nil), m.messages...)
}

func (m *mockSender) SentReactions() []OutboundReaction {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]OutboundReaction(nil), m.reactions...)
}

func TestAppleEpochConversion(t *testing.T) {
	require.True(t, AppleTimeToTime(0).IsZero())
	require.True(t, AppleTimeToTime(-10).IsZero())

	// Legacy seconds since 2001-01-01 00:00:00 UTC.
	legacySec := int64(100_000_000)
	gotLegacy := AppleTimeToTime(legacySec)
	require.Equal(t, time.Unix(AppleEpochOffsetSeconds+legacySec, 0).UTC(), gotLegacy)

	// Modern nanoseconds since 2001-01-01 00:00:00 UTC.
	ref := time.Date(2026, 11, 5, 1, 15, 30, 123456789, time.UTC)
	appleNano := TimeToAppleNano(ref)
	require.Greater(t, appleNano, appleNanoCutoff)
	roundTrip := AppleTimeToTime(appleNano)
	require.Equal(t, ref, roundTrip)
}

func TestAttributedBodyTypedstreamExtraction(t *testing.T) {
	// Short UTF-8 string (< 128 bytes) with emoji and inline attachment placeholder U+FFFC.
	shortBlob := EncodeAttributedBody("Hello from Sonoma 🚀\uFFFC")
	require.Equal(t, "Hello from Sonoma 🚀", ExtractAttributedBodyText(shortBlob))

	// Long UTF-8 string (>= 128 bytes, encoded with 0x81 + 2-byte little-endian length).
	longText := strings.Repeat("Ventura attributedBody typedstream test — ", 6)
	require.Greater(t, len(longText), 128)
	longBlob := EncodeAttributedBody(longText)
	require.Equal(t, longText, ExtractAttributedBodyText(longBlob))

	require.Equal(t, "", ExtractAttributedBodyText(nil))
	require.Equal(t, "", ExtractAttributedBodyText([]byte("not a typedstream")))
}

func TestTapbackMappingAndGUIDNormalization(t *testing.T) {
	require.Equal(t, "msg-guid-123", NormalizeAssociatedGUID("p:0/msg-guid-123"))
	require.Equal(t, "msg-guid-456", NormalizeAssociatedGUID("bp:msg-guid-456"))
	require.Equal(t, "msg-guid-789", NormalizeAssociatedGUID("msg-guid-789"))

	cases := []struct {
		addCode    int
		removeCode int
		emoji      string
	}{
		{TapbackLove, TapbackRemoveLove, "❤️"},
		{TapbackLike, TapbackRemoveLike, "👍"},
		{TapbackDislike, TapbackRemoveDislike, "👎"},
		{TapbackLaugh, TapbackRemoveLaugh, "😂"},
		{TapbackEmphasize, TapbackRemoveEmphasize, "‼️"},
		{TapbackQuestion, TapbackRemoveQuestion, "❓"},
	}
	for _, tc := range cases {
		em, rem, ok := TapbackFromRow(tc.addCode, "", "")
		require.True(t, ok)
		require.False(t, rem)
		require.Equal(t, tc.emoji, em)

		emRem, remFlag, okRem := TapbackFromRow(tc.removeCode, "", "")
		require.True(t, okRem)
		require.True(t, remFlag)
		require.Equal(t, tc.emoji, emRem)

		gotAddCode, gotCanonical := EmojiToTapbackType(tc.emoji, false)
		require.Equal(t, tc.addCode, gotAddCode)
		require.Equal(t, tc.emoji, gotCanonical)

		gotRemCode, _ := EmojiToTapbackType(tc.emoji, true)
		require.Equal(t, tc.removeCode, gotRemCode)
	}

	// macOS Sequoia+ arbitrary emoji tapback (2006 / 3006).
	em, rem, ok := TapbackFromRow(TapbackCustomEmoji, "🔥", "")
	require.True(t, ok)
	require.False(t, rem)
	require.Equal(t, "🔥", em)

	emFallback, remFallback, okFallback := TapbackFromRow(TapbackRemoveCustomEmoji, "", "Removed a 🎉 from “hello”")
	require.True(t, okFallback)
	require.True(t, remFallback)
	require.Equal(t, "🎉", emFallback)
}

func TestOSAScriptSenderParameterizesArguments(t *testing.T) {
	var capturedName string
	var capturedArgs []string
	sender := &OSAScriptSender{
		ExecFunc: func(_ context.Context, name string, args ...string) ([]byte, error) {
			capturedName = name
			capturedArgs = append([]string(nil), args...)
			return nil, nil
		},
	}

	trickyText := `hello "world" & do shell script "echo pwned"`
	_, err := sender.SendMessage(context.Background(), OutboundMessage{
		ChatGUID:       "iMessage;-;+15551234567",
		ChatIdentifier: "+15551234567",
		Service:        "iMessage",
		Text:           trickyText,
		AttachmentPath: "/tmp/photo.png",
	})
	require.NoError(t, err)
	require.Equal(t, "/usr/bin/osascript", capturedName)
	require.Len(t, capturedArgs, 7)
	require.Equal(t, "-e", capturedArgs[0])
	// Script must use `on run argv` and never contain the user text or handle inline.
	require.Contains(t, capturedArgs[1], "on run argv")
	require.NotContains(t, capturedArgs[1], trickyText)
	require.NotContains(t, capturedArgs[1], "+15551234567")
	require.Equal(t, "--", capturedArgs[2])
	require.Equal(t, "iMessage;-;+15551234567", capturedArgs[3])
	require.Equal(t, "+15551234567", capturedArgs[4])
	require.Equal(t, trickyText, capturedArgs[5])
	require.Equal(t, "/tmp/photo.png", capturedArgs[6])
}

func TestIMessageConnectorEndToEndSyncTapbacksRepliesAttachmentsAndSend(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	fakeHome := filepath.Join(dir, "home")
	attDir := filepath.Join(fakeHome, "Library", "Messages", "Attachments", "01")
	require.NoError(t, os.MkdirAll(attDir, 0o700))

	pngBytes := []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde")
	attFilePath := filepath.Join(attDir, "diagram.png")
	require.NoError(t, os.WriteFile(attFilePath, pngBytes, 0o600))

	chatDBPath := filepath.Join(dir, "chat.db")
	rawDB := createTestChatDB(t, chatDBPath)

	// Seed handles: Alice (+15551234567) and Bob (bob@example.com).
	_, err := rawDB.Exec(`
		INSERT INTO handle (ROWID, id, service) VALUES
			(1, '+15551234567', 'iMessage'),
			(2, 'bob@example.com', 'iMessage');
	`)
	require.NoError(t, err)

	// Seed 1:1 DM with Alice and Group Chat with Alice + Bob.
	_, err = rawDB.Exec(`
		INSERT INTO chat (ROWID, guid, chat_identifier, service_name, display_name, style) VALUES
			(1, 'iMessage;-;+15551234567', '+15551234567', 'iMessage', '', 45),
			(2, 'iMessage;+;chat987654', 'chat987654', 'iMessage', 'Weekend Trip', 43);
		INSERT INTO chat_handle_join (chat_id, handle_id) VALUES
			(1, 1),
			(2, 1),
			(2, 2);
	`)
	require.NoError(t, err)

	baseTime := time.Date(2026, 11, 5, 0, 10, 0, 0, time.UTC)
	t1 := TimeToAppleNano(baseTime)
	t2 := TimeToAppleNano(baseTime.Add(1 * time.Minute))
	t3 := TimeToAppleNano(baseTime.Add(2 * time.Minute))
	t4 := TimeToAppleNano(baseTime.Add(3 * time.Minute))
	t5 := TimeToAppleNano(baseTime.Add(4 * time.Minute))

	attrBlob := EncodeAttributedBody("Message stored only in attributedBody")

	// Seed messages:
	// 1. Plain text from Alice in DM.
	// 2. attributedBody-only message from Alice in DM (text is NULL).
	// 3. Reply from Bob in Group Chat replying to message 1 (or group message).
	// 4. Message with PNG attachment in DM.
	// 5. Heart tapback (2000) from Alice on message 1 (`p:0/msg-dm-1`).
	_, err = rawDB.Exec(`
		INSERT INTO message (
			ROWID, guid, text, attributedBody, handle_id, service, date, is_from_me, is_read,
			thread_originator_guid, associated_message_guid, associated_message_type
		) VALUES
			(1, 'msg-dm-1', 'Hello from Alice plain text', NULL, 1, 'iMessage', ?, 0, 0, '', '', 0),
			(2, 'msg-dm-2', NULL, ?, 1, 'iMessage', ?, 0, 0, 'p:0/msg-dm-1', '', 0),
			(3, 'msg-grp-1', 'Packing list ready', NULL, 2, 'iMessage', ?, 0, 0, '', '', 0),
			(4, 'msg-dm-att-1', 'See attached diagram', NULL, 1, 'iMessage', ?, 0, 0, '', '', 0),
			(5, 'msg-tapback-1', 'Loved “Hello from Alice plain text”', NULL, 1, 'iMessage', ?, 0, 0, '', 'p:0/msg-dm-1', 2000);

		INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES
			(1, 1, ?),
			(1, 2, ?),
			(2, 3, ?),
			(1, 4, ?),
			(1, 5, ?);

		INSERT INTO attachment (ROWID, guid, filename, transfer_name, mime_type, total_bytes) VALUES
			(1, 'att-1', '~/Library/Messages/Attachments/01/diagram.png', 'diagram.png', 'image/png', ?);

		INSERT INTO message_attachment_join (message_id, attachment_id) VALUES
			(4, 1);
	`, t1, attrBlob, t2, t3, t4, t5, t1, t2, t3, t4, t5, len(pngBytes))
	require.NoError(t, err)

	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	sender := &mockSender{db: rawDB}
	conn := &Connector{
		ChatDBPath:   chatDBPath,
		HomeDir:      fakeHome,
		Sender:       sender,
		PollInterval: 50 * time.Millisecond,
	}

	h, err := host.Start(ctx, dir, NetworkID, st, &media.Store{Dir: filepath.Join(dir, "media")}, conn, zerolog.New(zerolog.NewTestWriter(t)))
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	flows := conn.GetLoginFlows()
	require.Len(t, flows, 1)
	require.Equal(t, FlowLocal, flows[0].ID)

	user, err := h.Me(ctx)
	require.NoError(t, err)

	proc, err := conn.CreateLogin(ctx, user, FlowLocal)
	require.NoError(t, err)
	step, err := proc.Start(ctx)
	require.NoError(t, err)
	require.Equal(t, bridgev2.LoginStepTypeComplete, step.Type)
	require.NotNil(t, step.CompleteParams)
	require.Equal(t, DefaultLoginID, step.CompleteParams.UserLoginID)

	login := step.CompleteParams.UserLogin
	require.NotNil(t, login)
	require.True(t, login.Client.IsLoggedIn())

	// Wait for both the DM room and Group room to be populated in Vitruvian Courier's store.
	var dmRoomID, grpRoomID string
	require.Eventually(t, func() bool {
		rooms, err := st.ListRooms(ctx)
		if err != nil {
			return false
		}
		for _, r := range rooms {
			evs, err := st.Events(ctx, r.ID, 50)
			if err != nil {
				return false
			}
			for _, e := range evs {
				if strings.Contains(string(e.Content), "Message stored only in attributedBody") {
					dmRoomID = r.ID
				}
				if strings.Contains(string(e.Content), "Packing list ready") {
					grpRoomID = r.ID
				}
			}
		}
		return dmRoomID != "" && grpRoomID != ""
	}, 5*time.Second, 25*time.Millisecond, "initial DM and group messages never arrived in courier.db")

	// Verify DM events: plain text, attributedBody text, attachment, and ❤️ tapback reaction.
	dmEvents, err := st.Events(ctx, dmRoomID, 50)
	require.NoError(t, err)

	var foundPlain, foundAttrBody, foundImage, foundHeartReaction bool
	var heartReactionEventID string
	for _, e := range dmEvents {
		switch e.Type {
		case event.EventMessage.Type:
			body := string(e.Content)
			if strings.Contains(body, "Hello from Alice plain text") {
				foundPlain = true
				require.Equal(t, string(ids.GhostMXID(NetworkID, "+15551234567")), e.Sender)
			}
			if strings.Contains(body, "Message stored only in attributedBody") {
				foundAttrBody = true
				// Message 2 was a reply to msg-dm-1; verify m.relates_to.m.in_reply_to is populated.
				require.Contains(t, body, "m.in_reply_to")
			}
			if strings.Contains(body, "m.image") && strings.Contains(body, "diagram.png") {
				foundImage = true
				require.Contains(t, body, "mxc://courier.local/")
			}
		case event.EventReaction.Type:
			if strings.Contains(string(e.Content), "❤️") {
				foundHeartReaction = true
				heartReactionEventID = e.EventID
			}
		}
	}
	require.True(t, foundPlain, "plain text message missing")
	require.True(t, foundAttrBody, "attributedBody message or reply relation missing")
	require.True(t, foundImage, "image attachment message missing")
	require.True(t, foundHeartReaction, "heart tapback reaction missing")
	require.NotEmpty(t, heartReactionEventID)

	// Incremental sync: insert a new message (ROWID 6) and a tapback removal (ROWID 7, type 3000) into chat.db.
	t6 := TimeToAppleNano(baseTime.Add(5 * time.Minute))
	t7 := TimeToAppleNano(baseTime.Add(6 * time.Minute))
	_, err = rawDB.Exec(`
		INSERT INTO message (
			ROWID, guid, text, attributedBody, handle_id, service, date, is_from_me,
			associated_message_guid, associated_message_type
		) VALUES
			(6, 'msg-dm-live-6', NULL, ?, 1, 'iMessage', ?, 0, '', 0),
			(7, 'msg-tapback-rem-7', 'Removed a heart from “Hello from Alice plain text”', NULL, 1, 'iMessage', ?, 0, 'p:0/msg-dm-1', 3000);
		INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES
			(1, 6, ?),
			(1, 7, ?);
	`, EncodeAttributedBody("Incremental message from Alice"), t6, t7, t6, t7)
	require.NoError(t, err)

	imClient, ok := login.Client.(*Client)
	require.True(t, ok)
	require.NoError(t, imClient.SyncNow(ctx))

	require.Eventually(t, func() bool {
		evs, err := st.Events(ctx, dmRoomID, 50)
		if err != nil {
			return false
		}
		hasIncremental := false
		hasHeartRedaction := false
		for _, e := range evs {
			if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "Incremental message from Alice") {
				hasIncremental = true
			}
			if e.Type == event.EventRedaction.Type && strings.Contains(string(e.Content), heartReactionEventID) {
				hasHeartRedaction = true
			}
		}
		return hasIncremental && hasHeartRedaction
	}, 5*time.Second, 25*time.Millisecond, "incremental message or tapback removal did not take effect")

	// Outbound send via Matrix event -> Sender -> chat.db echo deduplication.
	outEvt := &event.Event{
		Type:      event.EventMessage,
		RoomID:    id.RoomID(dmRoomID),
		Sender:    ids.Me,
		ID:        ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(),
		Content: event.Content{
			Parsed: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Outbound reply from Vitruvian Courier",
			},
		},
	}
	rawContent, err := json.Marshal(&outEvt.Content)
	require.NoError(t, err)
	_, err = st.InsertEvent(ctx, store.Event{
		RoomID:  dmRoomID,
		EventID: string(outEvt.ID),
		Sender:  string(ids.Me),
		Type:    event.EventMessage.Type,
		Content: rawContent,
		TS:      time.Now(),
		Status:  "pending",
	})
	require.NoError(t, err)

	res := h.Bridge.QueueMatrixEvent(ctx, outEvt)
	require.True(t, res.Success, "outbound Matrix event failed: %+v", res)

	sent := sender.SentMessages()
	require.Len(t, sent, 1)
	require.Equal(t, "iMessage;-;+15551234567", sent[0].ChatGUID)
	require.Equal(t, "+15551234567", sent[0].ChatIdentifier)
	require.Equal(t, "Outbound reply from Vitruvian Courier", sent[0].Text)

	// Force another sync cycle after the mockSender inserted the outbound row into chat.db;
	// verify echo deduplication prevents a duplicate copy of "Outbound reply from Vitruvian Courier".
	require.NoError(t, imClient.SyncNow(ctx))

	evsAfterSend, err := st.Events(ctx, dmRoomID, 50)
	require.NoError(t, err)
	outboundCount := 0
	for _, e := range evsAfterSend {
		if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "Outbound reply from Vitruvian Courier") {
			outboundCount++
		}
	}
	require.Equal(t, 1, outboundCount, "outbound message must not be duplicated when echoed in chat.db")

	// Verify ResolveIdentifier (starting a new DM by phone/email) and SearchUsers.
	resolved, err := imClient.ResolveIdentifier(ctx, "carol@example.com", true)
	require.NoError(t, err)
	require.NotNil(t, resolved)
	require.NotNil(t, resolved.Chat)
	require.Equal(t, "iMessage;-;carol@example.com", string(resolved.Chat.PortalKey.ID))

	matches, err := imClient.SearchUsers(ctx, "bob@example.com")
	require.NoError(t, err)
	require.Len(t, matches, 1)
	require.Equal(t, "bob@example.com", string(matches[0].UserID))
}

func TestIMessageLoginFailsWhenChatDBMissing(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	conn := &Connector{
		ChatDBPath: filepath.Join(dir, "nonexistent-chat.db"),
	}
	h, err := host.Start(ctx, dir, NetworkID, st, &media.Store{Dir: filepath.Join(dir, "media")}, conn, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	user, err := h.Me(ctx)
	require.NoError(t, err)
	proc, err := conn.CreateLogin(ctx, user, FlowLocal)
	require.NoError(t, err)
	_, err = proc.Start(ctx)
	require.Error(t, err)
	require.Contains(t, err.Error(), "Messages database not found")
}
