// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package imessage implements a native macOS bridgev2.NetworkConnector that reads
// ~/Library/Messages/chat.db in read-only mode and sends outbound messages via Messages.app.
package imessage

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	_ "go.mau.fi/util/dbutil/litestream" // registers the cgo sqlite3 driver
)

const (
	// AppleEpochOffsetSeconds is the number of seconds between the Unix epoch
	// (1970-01-01 00:00:00 UTC) and the Apple CoreData/Cocoa reference date
	// (2001-01-01 00:00:00 UTC).
	AppleEpochOffsetSeconds int64 = 978307200

	// appleNanoCutoff distinguishes modern macOS nanosecond timestamps (> 1e12)
	// from legacy second-granularity timestamps.
	appleNanoCutoff int64 = 1_000_000_000_000
)

// Tapback associated_message_type constants used by macOS Messages in chat.db.
const (
	TapbackLove        = 2000
	TapbackLike        = 2001
	TapbackDislike     = 2002
	TapbackLaugh       = 2003
	TapbackEmphasize   = 2004
	TapbackQuestion    = 2005
	TapbackCustomEmoji = 2006

	TapbackRemoveLove        = 3000
	TapbackRemoveLike        = 3001
	TapbackRemoveDislike     = 3002
	TapbackRemoveLaugh       = 3003
	TapbackRemoveEmphasize   = 3004
	TapbackRemoveQuestion    = 3005
	TapbackRemoveCustomEmoji = 3006

	ChatStyleGroup = 43
	ChatStyleDM    = 45
)

// DefaultChatDBPath returns the standard macOS Messages SQLite database path
// (~/Library/Messages/chat.db).
func DefaultChatDBPath() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, "Library", "Messages", "chat.db")
}

// AppleTimeToTime converts a macOS chat.db date value (nanoseconds or seconds
// since 2001-01-01 00:00:00 UTC) into a UTC time.Time. Zero or negative values
// return the zero time.Time.
func AppleTimeToTime(raw int64) time.Time {
	if raw <= 0 {
		return time.Time{}
	}
	if raw > appleNanoCutoff {
		sec := raw / 1_000_000_000
		nsec := raw % 1_000_000_000
		return time.Unix(sec+AppleEpochOffsetSeconds, nsec).UTC()
	}
	return time.Unix(raw+AppleEpochOffsetSeconds, 0).UTC()
}

// TimeToAppleNano converts a time.Time into nanoseconds since 2001-01-01 00:00:00 UTC.
func TimeToAppleNano(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return (t.Unix()-AppleEpochOffsetSeconds)*1_000_000_000 + int64(t.Nanosecond())
}

// ExtractAttributedBodyText extracts the plain UTF-8 string from an Apple
// NSArchiver typedstream NSAttributedString blob stored in message.attributedBody
// on macOS Ventura, Sonoma, and Sequoia when message.text is NULL.
func ExtractAttributedBodyText(blob []byte) string {
	if len(blob) == 0 {
		return ""
	}
	for _, marker := range [][]byte{[]byte("NSMutableString"), []byte("NSString")} {
		idx := bytes.Index(blob, marker)
		if idx < 0 {
			continue
		}
		rest := blob[idx+len(marker):]
		if text, ok := decodeTypedstreamPlusString(rest); ok {
			return cleanExtractedText(text)
		}
	}
	if text, ok := decodeTypedstreamPlusString(blob); ok {
		return cleanExtractedText(text)
	}
	return ""
}

func decodeTypedstreamPlusString(rest []byte) (string, bool) {
	// In Apple's typedstream format, after the NSString class header (typically
	// \x01\x94\x84\x01+ or \x01\x95\x84\x01+ or \x01+), '+' (0x2b) introduces a
	// length-prefixed UTF-8 byte sequence.
	limit := min(len(rest), 64)
	for i := 0; i < limit; i++ {
		if rest[i] != '+' {
			continue
		}
		if i > 0 && rest[i-1] != 0x01 && rest[i-1] != 0x84 {
			continue
		}
		pos := i + 1
		if pos >= len(rest) {
			break
		}
		strLen, hdrBytes, ok := readTypedstreamLength(rest[pos:])
		if !ok || strLen <= 0 {
			continue
		}
		start := pos + hdrBytes
		end := start + strLen
		if end > len(rest) {
			continue
		}
		candidate := rest[start:end]
		if utf8.Valid(candidate) {
			return string(candidate), true
		}
	}
	return "", false
}

func readTypedstreamLength(b []byte) (length int, consumed int, ok bool) {
	if len(b) == 0 {
		return 0, 0, false
	}
	first := b[0]
	switch {
	case first < 0x80:
		return int(first), 1, true
	case first == 0x81:
		if len(b) < 3 {
			return 0, 0, false
		}
		return int(binary.LittleEndian.Uint16(b[1:3])), 3, true
	case first == 0x82:
		if len(b) < 5 {
			return 0, 0, false
		}
		return int(binary.LittleEndian.Uint32(b[1:5])), 5, true
	default:
		return 0, 0, false
	}
}

func cleanExtractedText(s string) string {
	// Strip the Unicode Object Replacement Character (U+FFFC) inserted by Messages
	// for inline attachments and trim any trailing NUL bytes.
	s = strings.ReplaceAll(s, "\uFFFC", "")
	s = strings.TrimRight(s, "\x00")
	return s
}

// EncodeAttributedBody encodes plain UTF-8 text into a valid Apple typedstream
// NSAttributedString binary blob matching macOS Ventura/Sonoma/Sequoia chat.db rows.
func EncodeAttributedBody(text string) []byte {
	var buf bytes.Buffer
	buf.Write([]byte("\x04\x0bstreamtyped\x81\xe8\x03\x84\x01@\x84\x84\x84\x12NSAttributedString\x00\x84\x84\x08NSObject\x00\x85\x92\x84\x84\x84\x08NSString\x01\x94\x84\x01+"))
	raw := []byte(text)
	switch {
	case len(raw) < 0x80:
		buf.WriteByte(byte(len(raw)))
	case len(raw) <= 0xFFFF:
		buf.WriteByte(0x81)
		var lenBuf [2]byte
		binary.LittleEndian.PutUint16(lenBuf[:], uint16(len(raw)))
		buf.Write(lenBuf[:])
	default:
		buf.WriteByte(0x82)
		var lenBuf [4]byte
		binary.LittleEndian.PutUint32(lenBuf[:], uint32(len(raw)))
		buf.Write(lenBuf[:])
	}
	buf.Write(raw)
	buf.Write([]byte("\x86\x84\x02iI\x01\x92\x84\x84\x84\x0cNSDictionary\x00\x94\x84\x01i\x00\x86\x86"))
	return buf.Bytes()
}

// NormalizeAssociatedGUID strips the "p:<part>/" or "bp:" prefix macOS Messages
// prepends to associated_message_guid and thread_originator_guid values in chat.db.
func NormalizeAssociatedGUID(raw string) string {
	s := strings.TrimSpace(raw)
	if strings.HasPrefix(s, "p:") {
		if _, after, ok := strings.Cut(s, "/"); ok && after != "" {
			s = after
		}
	}
	s = strings.TrimPrefix(s, "bp:")
	return strings.TrimSpace(s)
}

// IsTapbackType reports whether assocType is an iMessage tapback addition (2000-2006)
// or removal (3000-3006).
func IsTapbackType(assocType int) bool {
	return (assocType >= TapbackLove && assocType <= TapbackCustomEmoji) ||
		(assocType >= TapbackRemoveLove && assocType <= TapbackRemoveCustomEmoji)
}

// TapbackFromRow resolves an iMessage associated_message_type (and optional
// associated_message_emoji / fallback text) into a canonical Unicode emoji and
// whether the row removes an existing tapback.
func TapbackFromRow(assocType int, assocEmoji, fallbackText string) (emoji string, isRemove bool, ok bool) {
	if !IsTapbackType(assocType) {
		return "", false, false
	}
	baseType := assocType
	if assocType >= TapbackRemoveLove {
		isRemove = true
		baseType = assocType - 1000
	}
	switch baseType {
	case TapbackLove:
		return "❤️", isRemove, true
	case TapbackLike:
		return "👍", isRemove, true
	case TapbackDislike:
		return "👎", isRemove, true
	case TapbackLaugh:
		return "😂", isRemove, true
	case TapbackEmphasize:
		return "‼️", isRemove, true
	case TapbackQuestion:
		return "❓", isRemove, true
	case TapbackCustomEmoji:
		em := strings.TrimSpace(assocEmoji)
		if em == "" {
			em = extractEmojiFromTapbackSummary(fallbackText)
		}
		if em == "" {
			return "", false, false
		}
		return em, isRemove, true
	default:
		return "", false, false
	}
}

func extractEmojiFromTapbackSummary(summary string) string {
	s := strings.TrimSpace(summary)
	for _, prefix := range []string{"Reacted ", "Removed a ", "Removed "} {
		if after, ok := strings.CutPrefix(s, prefix); ok {
			for _, sep := range []string{" to ", " from "} {
				if before, _, found := strings.Cut(after, sep); found {
					return strings.TrimSpace(before)
				}
			}
		}
	}
	return ""
}

// EmojiToTapbackType maps an emoji reaction into the macOS chat.db
// associated_message_type code (2000-2006 for add, 3000-3006 for remove) and
// canonical emoji string.
func EmojiToTapbackType(emoji string, remove bool) (assocType int, canonicalEmoji string) {
	trimmed := strings.TrimSpace(emoji)
	stripped := strings.ReplaceAll(trimmed, "\uFE0F", "")
	switch stripped {
	case "❤", "♥":
		assocType, canonicalEmoji = TapbackLove, "❤️"
	case "👍":
		assocType, canonicalEmoji = TapbackLike, "👍"
	case "👎":
		assocType, canonicalEmoji = TapbackDislike, "👎"
	case "😂", "😆":
		assocType, canonicalEmoji = TapbackLaugh, "😂"
	case "‼", "❗":
		assocType, canonicalEmoji = TapbackEmphasize, "‼️"
	case "❓", "?":
		assocType, canonicalEmoji = TapbackQuestion, "❓"
	default:
		assocType, canonicalEmoji = TapbackCustomEmoji, trimmed
	}
	if remove {
		assocType += 1000
	}
	return assocType, canonicalEmoji
}

// ExpandAttachmentPath expands a leading "~/" in a chat.db attachment.filename
// using homeDir (falling back to os.UserHomeDir when homeDir is empty).
func ExpandAttachmentPath(rawPath, homeDir string) string {
	p := strings.TrimSpace(rawPath)
	if p == "" {
		return ""
	}
	if strings.HasPrefix(p, "~/") {
		if homeDir == "" {
			homeDir, _ = os.UserHomeDir()
		}
		if homeDir != "" {
			return filepath.Join(homeDir, strings.TrimPrefix(p, "~/"))
		}
	}
	return p
}

// ChatRecord represents one conversation row from chat.db along with its participant handles.
type ChatRecord struct {
	RowID          int64
	GUID           string
	ChatIdentifier string
	ServiceName    string
	DisplayName    string
	Style          int
	Participants   []string
	LastMessageTS  time.Time
}

// IsDM reports whether the chat is a 1:1 direct message conversation.
func (c ChatRecord) IsDM() bool {
	if c.Style == ChatStyleDM {
		return true
	}
	if c.Style == ChatStyleGroup {
		return false
	}
	if strings.Contains(c.GUID, ";-;") {
		return true
	}
	if strings.Contains(c.GUID, ";+;") {
		return false
	}
	return len(c.Participants) <= 1
}

// HandleRecord represents one contact handle (phone number or email) in chat.db.
type HandleRecord struct {
	RowID   int64
	ID      string
	Service string
}

// AttachmentRecord represents one attachment joined to a message in chat.db.
type AttachmentRecord struct {
	RowID        int64
	GUID         string
	Filename     string
	TransferName string
	MimeType     string
	TotalBytes   int64
	IsSticker    bool
}

// EffectiveFileName returns the display filename for the attachment.
func (a AttachmentRecord) EffectiveFileName() string {
	if name := strings.TrimSpace(a.TransferName); name != "" {
		return filepath.Base(name)
	}
	if name := strings.TrimSpace(a.Filename); name != "" {
		return filepath.Base(name)
	}
	return "attachment"
}

// MessageRecord represents one row from the message table in chat.db.
type MessageRecord struct {
	RowID                 int64
	GUID                  string
	ChatGUID              string
	ChatIdentifier        string
	ChatStyle             int
	Service               string
	SenderHandle          string
	IsFromMe              bool
	Text                  string
	Date                  time.Time
	DateRead              time.Time
	DateDelivered         time.Time
	DateEdited            time.Time
	IsRead                bool
	IsDelivered           bool
	ReplyToGUID           string
	AssociatedMessageGUID string
	AssociatedMessageType int
	AssociatedEmoji       string
	Attachments           []AttachmentRecord
}

// ChatDB provides read-only queries against a macOS Messages chat.db SQLite file.
type ChatDB struct {
	path string
	db   *sql.DB

	msgCols map[string]bool
	attCols map[string]bool
}

// OpenChatDB opens the SQLite database at path in read-only mode and inspects its schema.
func OpenChatDB(ctx context.Context, path string) (*ChatDB, error) {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return nil, errors.New("iMessage chat.db path is empty")
	}
	info, err := os.Stat(trimmed)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, fmt.Errorf("Messages database not found at %s: open Messages.app on this Mac first (%w)", trimmed, err)
		}
		if errors.Is(err, os.ErrPermission) {
			return nil, fmt.Errorf("Full Disk Access is required to read %s (%w)", trimmed, err)
		}
		return nil, fmt.Errorf("stat %s: %w", trimmed, err)
	}
	if info.IsDir() {
		return nil, fmt.Errorf("Messages database path %s is a directory", trimmed)
	}
	f, err := os.Open(trimmed)
	if err != nil {
		if errors.Is(err, os.ErrPermission) {
			return nil, fmt.Errorf("Full Disk Access is required to read %s (%w)", trimmed, err)
		}
		return nil, fmt.Errorf("open %s: %w", trimmed, err)
	}
	_ = f.Close()

	uri := fmt.Sprintf("file:%s?mode=ro&_busy_timeout=5000&_query_only=1", trimmed)
	db, err := sql.Open("sqlite3", uri)
	if err != nil {
		return nil, fmt.Errorf("open sqlite %s: %w", trimmed, err)
	}
	reader := &ChatDB{
		path: trimmed,
		db:   db,
	}
	if err := reader.inspectSchema(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return reader, nil
}

// Close closes the underlying read-only SQLite connection pool.
func (r *ChatDB) Close() error {
	if r == nil || r.db == nil {
		return nil
	}
	return r.db.Close()
}

func (r *ChatDB) inspectSchema(ctx context.Context) error {
	msgCols, err := r.tableColumns(ctx, "message")
	if err != nil {
		return fmt.Errorf("inspect message table in %s: %w", r.path, err)
	}
	if len(msgCols) == 0 {
		return fmt.Errorf("%s does not contain a valid Messages 'message' table", r.path)
	}
	attCols, err := r.tableColumns(ctx, "attachment")
	if err != nil {
		return fmt.Errorf("inspect attachment table in %s: %w", r.path, err)
	}
	r.msgCols = msgCols
	r.attCols = attCols
	return nil
}

func (r *ChatDB) tableColumns(ctx context.Context, table string) (map[string]bool, error) {
	rows, err := r.db.QueryContext(ctx, fmt.Sprintf("PRAGMA table_info(%s)", table))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := make(map[string]bool)
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull int
		var dflt sql.NullString
		var pk int
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols[strings.ToLower(name)] = true
	}
	return cols, rows.Err()
}

// CheckAccess verifies that chat.db can execute read queries against the message and chat tables.
func (r *ChatDB) CheckAccess(ctx context.Context) error {
	var count int64
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM chat`).Scan(&count); err != nil {
		return fmt.Errorf("query chat table: %w", err)
	}
	return nil
}

// MaxMessageRowID returns the highest message.ROWID currently present in chat.db (0 if empty).
func (r *ChatDB) MaxMessageRowID(ctx context.Context) (int64, error) {
	var maxID sql.NullInt64
	if err := r.db.QueryRowContext(ctx, `SELECT MAX(ROWID) FROM message`).Scan(&maxID); err != nil {
		return 0, err
	}
	return maxID.Int64, nil
}

// ListChats returns up to limit conversations ordered by most recent message activity.
func (r *ChatDB) ListChats(ctx context.Context, limit int) ([]ChatRecord, error) {
	if limit <= 0 {
		limit = 50
	}
	query := `
		SELECT
			c.ROWID,
			COALESCE(c.guid, ''),
			COALESCE(c.chat_identifier, ''),
			COALESCE(c.service_name, 'iMessage'),
			COALESCE(c.display_name, ''),
			COALESCE(c.style, 0),
			COALESCE(MAX(m.date), 0) AS last_date
		FROM chat c
		LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
		LEFT JOIN message m ON m.ROWID = cmj.message_id
		GROUP BY c.ROWID
		ORDER BY last_date DESC, c.ROWID DESC
		LIMIT ?
	`
	rows, err := r.db.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("list chats: %w", err)
	}
	defer rows.Close()

	var chats []ChatRecord
	var chatIDs []int64
	idxByRowID := make(map[int64]int)
	for rows.Next() {
		var rec ChatRecord
		var rawLastDate int64
		if err := rows.Scan(
			&rec.RowID,
			&rec.GUID,
			&rec.ChatIdentifier,
			&rec.ServiceName,
			&rec.DisplayName,
			&rec.Style,
			&rawLastDate,
		); err != nil {
			return nil, fmt.Errorf("scan chat: %w", err)
		}
		if rec.GUID == "" && rec.ChatIdentifier != "" {
			rec.GUID = rec.ServiceName + ";-;" + rec.ChatIdentifier
		}
		rec.LastMessageTS = AppleTimeToTime(rawLastDate)
		idxByRowID[rec.RowID] = len(chats)
		chatIDs = append(chatIDs, rec.RowID)
		chats = append(chats, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(chats) == 0 {
		return nil, nil
	}

	participantsByChat, err := r.loadChatParticipants(ctx, chatIDs)
	if err != nil {
		return nil, err
	}
	for chatRowID, handles := range participantsByChat {
		if idx, ok := idxByRowID[chatRowID]; ok {
			chats[idx].Participants = handles
		}
	}
	for i := range chats {
		if len(chats[i].Participants) == 0 && chats[i].IsDM() && chats[i].ChatIdentifier != "" {
			chats[i].Participants = []string{chats[i].ChatIdentifier}
		}
	}
	return chats, nil
}

// GetChatByGUID looks up a single chat by its GUID or chat_identifier.
func (r *ChatDB) GetChatByGUID(ctx context.Context, guidOrIdentifier string) (*ChatRecord, error) {
	target := strings.TrimSpace(guidOrIdentifier)
	if target == "" {
		return nil, nil
	}
	query := `
		SELECT
			c.ROWID,
			COALESCE(c.guid, ''),
			COALESCE(c.chat_identifier, ''),
			COALESCE(c.service_name, 'iMessage'),
			COALESCE(c.display_name, ''),
			COALESCE(c.style, 0),
			COALESCE((SELECT MAX(m.date) FROM chat_message_join cmj JOIN message m ON m.ROWID = cmj.message_id WHERE cmj.chat_id = c.ROWID), 0)
		FROM chat c
		WHERE c.guid = ? OR c.chat_identifier = ?
		ORDER BY c.ROWID DESC
		LIMIT 1
	`
	var rec ChatRecord
	var rawLastDate int64
	err := r.db.QueryRowContext(ctx, query, target, target).Scan(
		&rec.RowID,
		&rec.GUID,
		&rec.ChatIdentifier,
		&rec.ServiceName,
		&rec.DisplayName,
		&rec.Style,
		&rawLastDate,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get chat %q: %w", target, err)
	}
	if rec.GUID == "" && rec.ChatIdentifier != "" {
		rec.GUID = rec.ServiceName + ";-;" + rec.ChatIdentifier
	}
	rec.LastMessageTS = AppleTimeToTime(rawLastDate)
	parts, err := r.loadChatParticipants(ctx, []int64{rec.RowID})
	if err != nil {
		return nil, err
	}
	rec.Participants = parts[rec.RowID]
	if len(rec.Participants) == 0 && rec.IsDM() && rec.ChatIdentifier != "" {
		rec.Participants = []string{rec.ChatIdentifier}
	}
	return &rec, nil
}

func (r *ChatDB) loadChatParticipants(ctx context.Context, chatRowIDs []int64) (map[int64][]string, error) {
	out := make(map[int64][]string, len(chatRowIDs))
	if len(chatRowIDs) == 0 {
		return out, nil
	}
	placeholders := make([]string, len(chatRowIDs))
	args := make([]any, len(chatRowIDs))
	for i, id := range chatRowIDs {
		placeholders[i] = "?"
		args[i] = id
	}
	query := fmt.Sprintf(`
		SELECT chj.chat_id, COALESCE(h.id, '')
		FROM chat_handle_join chj
		JOIN handle h ON h.ROWID = chj.handle_id
		WHERE chj.chat_id IN (%s)
		ORDER BY chj.chat_id ASC, h.ROWID ASC
	`, strings.Join(placeholders, ","))
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query chat participants: %w", err)
	}
	defer rows.Close()

	seen := make(map[int64]map[string]bool, len(chatRowIDs))
	for rows.Next() {
		var chatID int64
		var handleID string
		if err := rows.Scan(&chatID, &handleID); err != nil {
			return nil, err
		}
		handleID = strings.TrimSpace(handleID)
		if handleID == "" {
			continue
		}
		if seen[chatID] == nil {
			seen[chatID] = make(map[string]bool)
		}
		if !seen[chatID][handleID] {
			seen[chatID][handleID] = true
			out[chatID] = append(out[chatID], handleID)
		}
	}
	return out, rows.Err()
}

// ListHandles returns all unique handles from the handle table.
func (r *ChatDB) ListHandles(ctx context.Context) ([]HandleRecord, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT MIN(ROWID), COALESCE(id, ''), COALESCE(service, 'iMessage')
		FROM handle
		WHERE COALESCE(id, '') != ''
		GROUP BY id
		ORDER BY MIN(ROWID) ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("list handles: %w", err)
	}
	defer rows.Close()

	var out []HandleRecord
	for rows.Next() {
		var h HandleRecord
		if err := rows.Scan(&h.RowID, &h.ID, &h.Service); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

func (r *ChatDB) messageSelectColumns() string {
	colOrDefault := func(col, fallback string) string {
		if r.msgCols[strings.ToLower(col)] {
			return fmt.Sprintf("COALESCE(m.%s, %s)", col, fallback)
		}
		return fallback
	}
	var replyExpr string
	switch {
	case r.msgCols["thread_originator_guid"] && r.msgCols["reply_to_guid"]:
		replyExpr = "COALESCE(NULLIF(m.thread_originator_guid, ''), NULLIF(m.reply_to_guid, ''), '')"
	case r.msgCols["thread_originator_guid"]:
		replyExpr = "COALESCE(m.thread_originator_guid, '')"
	case r.msgCols["reply_to_guid"]:
		replyExpr = "COALESCE(m.reply_to_guid, '')"
	default:
		replyExpr = "''"
	}

	var attrBodyExpr string
	if r.msgCols["attributedbody"] {
		attrBodyExpr = "m.attributedBody"
	} else {
		attrBodyExpr = "NULL"
	}

	return strings.Join([]string{
		"m.ROWID",
		colOrDefault("guid", "''"),
		"COALESCE(c.guid, '')",
		"COALESCE(c.chat_identifier, '')",
		"COALESCE(c.style, 0)",
		colOrDefault("service", "COALESCE(c.service_name, 'iMessage')"),
		"COALESCE(h.id, '')",
		colOrDefault("is_from_me", "0"),
		colOrDefault("text", "''"),
		attrBodyExpr,
		colOrDefault("date", "0"),
		colOrDefault("date_read", "0"),
		colOrDefault("date_delivered", "0"),
		colOrDefault("date_edited", "0"),
		colOrDefault("is_read", "0"),
		colOrDefault("is_delivered", "0"),
		replyExpr,
		colOrDefault("associated_message_guid", "''"),
		colOrDefault("associated_message_type", "0"),
		colOrDefault("associated_message_emoji", "''"),
	}, ", ")
}

// FetchMessagesAfterRowID fetches message rows across all chats with m.ROWID > afterRowID,
// ordered ascending by m.ROWID.
func (r *ChatDB) FetchMessagesAfterRowID(ctx context.Context, afterRowID int64, limit int) ([]MessageRecord, error) {
	if limit <= 0 {
		limit = 200
	}
	query := fmt.Sprintf(`
		SELECT %s
		FROM message m
		JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
		JOIN chat c ON c.ROWID = cmj.chat_id
		LEFT JOIN handle h ON h.ROWID = m.handle_id
		WHERE m.ROWID > ?
		ORDER BY m.ROWID ASC
		LIMIT ?
	`, r.messageSelectColumns())

	rows, err := r.db.QueryContext(ctx, query, afterRowID, limit)
	if err != nil {
		return nil, fmt.Errorf("fetch messages after rowid %d: %w", afterRowID, err)
	}
	defer rows.Close()
	return r.scanMessagesAndAttachments(ctx, rows)
}

// FetchMessagesForChat fetches messages belonging to chatGUID, ordered ascending by ROWID.
func (r *ChatDB) FetchMessagesForChat(ctx context.Context, chatGUID string, limit int) ([]MessageRecord, error) {
	if limit <= 0 {
		limit = 100
	}
	// Fetch the newest `limit` rows in descending order, then reverse to ascending order.
	query := fmt.Sprintf(`
		SELECT %s
		FROM message m
		JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
		JOIN chat c ON c.ROWID = cmj.chat_id
		LEFT JOIN handle h ON h.ROWID = m.handle_id
		WHERE c.guid = ? OR c.chat_identifier = ?
		ORDER BY m.ROWID DESC
		LIMIT ?
	`, r.messageSelectColumns())

	rows, err := r.db.QueryContext(ctx, query, chatGUID, chatGUID, limit)
	if err != nil {
		return nil, fmt.Errorf("fetch messages for chat %q: %w", chatGUID, err)
	}
	defer rows.Close()
	msgs, err := r.scanMessagesAndAttachments(ctx, rows)
	if err != nil {
		return nil, err
	}
	sort.Slice(msgs, func(i, j int) bool {
		return msgs[i].RowID < msgs[j].RowID
	})
	return msgs, nil
}

func (r *ChatDB) scanMessagesAndAttachments(ctx context.Context, rows *sql.Rows) ([]MessageRecord, error) {
	var msgs []MessageRecord
	var msgRowIDs []int64
	idxByRowID := make(map[int64][]int)

	for rows.Next() {
		var rec MessageRecord
		var isFromMe, isRead, isDelivered int
		var attrBody []byte
		var rawDate, rawDateRead, rawDateDelivered, rawDateEdited int64
		var rawReplyGUID, rawAssocGUID string

		if err := rows.Scan(
			&rec.RowID,
			&rec.GUID,
			&rec.ChatGUID,
			&rec.ChatIdentifier,
			&rec.ChatStyle,
			&rec.Service,
			&rec.SenderHandle,
			&isFromMe,
			&rec.Text,
			&attrBody,
			&rawDate,
			&rawDateRead,
			&rawDateDelivered,
			&rawDateEdited,
			&isRead,
			&isDelivered,
			&rawReplyGUID,
			&rawAssocGUID,
			&rec.AssociatedMessageType,
			&rec.AssociatedEmoji,
		); err != nil {
			return nil, fmt.Errorf("scan message row: %w", err)
		}

		if rec.ChatGUID == "" && rec.ChatIdentifier != "" {
			rec.ChatGUID = rec.Service + ";-;" + rec.ChatIdentifier
		}
		rec.IsFromMe = isFromMe != 0
		rec.IsRead = isRead != 0 || rawDateRead > 0
		rec.IsDelivered = isDelivered != 0 || rawDateDelivered > 0
		rec.Date = AppleTimeToTime(rawDate)
		rec.DateRead = AppleTimeToTime(rawDateRead)
		rec.DateDelivered = AppleTimeToTime(rawDateDelivered)
		rec.DateEdited = AppleTimeToTime(rawDateEdited)

		if strings.TrimSpace(rec.Text) == "" && len(attrBody) > 0 {
			rec.Text = ExtractAttributedBodyText(attrBody)
		} else {
			rec.Text = cleanExtractedText(rec.Text)
		}

		rec.ReplyToGUID = NormalizeAssociatedGUID(rawReplyGUID)
		rec.AssociatedMessageGUID = NormalizeAssociatedGUID(rawAssocGUID)

		if _, seen := idxByRowID[rec.RowID]; !seen {
			msgRowIDs = append(msgRowIDs, rec.RowID)
		}
		idxByRowID[rec.RowID] = append(idxByRowID[rec.RowID], len(msgs))
		msgs = append(msgs, rec)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(msgs) == 0 {
		return nil, nil
	}

	attsByMsg, err := r.loadMessageAttachments(ctx, msgRowIDs)
	if err != nil {
		return nil, err
	}
	for msgRowID, atts := range attsByMsg {
		for _, idx := range idxByRowID[msgRowID] {
			msgs[idx].Attachments = atts
		}
	}
	return msgs, nil
}

func (r *ChatDB) loadMessageAttachments(ctx context.Context, msgRowIDs []int64) (map[int64][]AttachmentRecord, error) {
	out := make(map[int64][]AttachmentRecord)
	if len(msgRowIDs) == 0 || len(r.attCols) == 0 {
		return out, nil
	}
	placeholders := make([]string, len(msgRowIDs))
	args := make([]any, len(msgRowIDs))
	for i, id := range msgRowIDs {
		placeholders[i] = "?"
		args[i] = id
	}
	colOrDefault := func(col, fallback string) string {
		if r.attCols[strings.ToLower(col)] {
			return fmt.Sprintf("COALESCE(a.%s, %s)", col, fallback)
		}
		return fallback
	}
	query := fmt.Sprintf(
		`
		SELECT
			maj.message_id,
			a.ROWID,
			%s,
			%s,
			%s,
			%s,
			%s,
			%s
		FROM message_attachment_join maj
		JOIN attachment a ON a.ROWID = maj.attachment_id
		WHERE maj.message_id IN (%s)
		ORDER BY maj.message_id ASC, a.ROWID ASC
	`,
		colOrDefault("guid", "''"),
		colOrDefault("filename", "''"),
		colOrDefault("transfer_name", "''"),
		colOrDefault("mime_type", "'application/octet-stream'"),
		colOrDefault("total_bytes", "0"),
		colOrDefault("is_sticker", "0"),
		strings.Join(placeholders, ","),
	)

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("load message attachments: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var msgID int64
		var att AttachmentRecord
		var isSticker int
		if err := rows.Scan(
			&msgID,
			&att.RowID,
			&att.GUID,
			&att.Filename,
			&att.TransferName,
			&att.MimeType,
			&att.TotalBytes,
			&isSticker,
		); err != nil {
			return nil, err
		}
		att.IsSticker = isSticker != 0
		out[msgID] = append(out[msgID], att)
	}
	return out, rows.Err()
}
