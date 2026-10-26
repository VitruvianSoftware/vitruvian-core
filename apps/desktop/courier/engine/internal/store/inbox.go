// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// maxPreviewRunes is how much of a message the inbox row shows.
const maxPreviewRunes = 140

// InboxRow is one chat in the list: the room plus what the list shows beside its name.
type InboxRow struct {
	Room
	LastTS      time.Time // zero when the room has no message yet
	Preview     string    // body of the newest message-like event, at most 140 runes
	PreviewKind string    // "text", "image", "video", "audio", "file", "sticker", "poll", "timer_change", "call", or "" (nothing readable yet)
	PreviewMine bool      // the newest message is mine
	// PreviewStatus is how far the newest message has got when it is mine and has gone (previewStatusSQL): "seen"
	// (someone's read marker is at it or past it), "delivered" (someone's device has it), or "sent". "" otherwise.
	// The row's login is Room.LoginID.
	PreviewStatus   string
	PreviewMediaURI string    // the newest message's image or sticker (its thumbnail when it has one), or ""
	PreviewCall     *CallNote // for a "call" preview, what happened; nil otherwise
	Unread          int       // messages from others newer than the read marker
	UnreadMentions  int       // the unread ones that mention me, by name or the whole room
	Muted           bool      // I muted this chat itself

	// MutedBy says what else mutes this chat: "account" (its account; MutedByName is the network's display name),
	// "label" (a muted label; MutedByName is the title of the first one, by label ID), or "". An account mute wins.
	MutedBy, MutedByName string

	PinnedAt                                     time.Time // zero when not pinned; pin order
	Archived, LowPriority, MarkedUnread, Request bool
	Draft                                        string
	Labels                                       []int64   // by label ID
	Reminder                                     *Reminder // nil when the chat has none
}

// myID is $1 of every statement that needs to tell my messages from other people's.
var myID = string(ids.Me)

// readMarkerJoinsFor brings in room r's two read markers, both mine, with their events (for the seq): rd / rde
// is what I read on another device, as the network reports it (reads), and lr / lre what I read on this one
// (local_reads).
func readMarkerJoinsFor(r, rd, rde, lr, lre string) string {
	return `LEFT JOIN reads ` + rd + ` ON ` + rd + `.room_id = ` + r + `.room_id
LEFT JOIN events ` + rde + ` ON ` + rde + `.event_id = ` + rd + `.event_id AND ` + rde + `.ts = ` + rd + `.ts
LEFT JOIN local_reads ` + lr + ` ON ` + lr + `.room_id = ` + r + `.room_id
LEFT JOIN events ` + lre + ` ON ` + lre + `.event_id = ` + lr + `.event_id AND ` + lre + `.ts = ` + lr + `.ts`
}

var readMarkerJoins = readMarkerJoinsFor("r", "rd", "rde", "lr", "lre")

// unreadSQLFor is the condition on an event u of room r for "unread": a message we can show, from someone else ($1
// is my user ID), not deleted, not an edit, not a note that the disappearing timer changed (a system line, not news:
// Ruling 40), not the record of a call that ended, was declined or dropped (isCallRecordSQL: a call that rang or was
// missed is news), and after both read markers (readMarkerJoinsFor), or at or after the message the chat was marked
// unread from (room_prefs p's unread_from_*). After both is the same as after the later one, and "after the later
// marker, or from the mark on" is the same as after the earlier of the two (unreadBoundFor), so the range scan of
// events_room_ts keeps one lower bound (Ruling C29). "After" compares (ts, seq), so a message in the same
// millisecond as the marker but received later still counts.
func unreadSQLFor(r, p, rd, rde, lr, lre string) string {
	return `u.room_id = ` + r + `.room_id
       AND (u.ts, u.seq) > (` + unreadBoundFor(p, rd, rde, lr, lre) + `)
       AND u.type IN (` + unreadTypes + `) AND u.sender <> $1 AND u.redacted = 0 AND ` + notEditSQL("u.content") + `
       AND (` + isTimerNoteSQL("u.content") + `) IS NOT 1 AND (` + isCallRecordSQL("u.content") + `) IS NOT 1`
}

var unreadSQL = unreadSQLFor("r", "p", "rd", "rde", "lr", "lre")

// unreadBoundFor is the (ts, seq) after which room r's messages are unread, as two SQL expressions: the later of its
// two read markers (readMarkerJoinsFor), or, when the chat is marked unread from a message (room_prefs p,
// unread_from_ts > 0) that is not after that marker, just before that message: (from_ts, from_seq - 1), so that
// "(ts, seq) > bound" takes the message itself in. A seq is an integer, so nothing falls between the two.
func unreadBoundFor(p, rd, rde, lr, lre string) string {
	mTS, mSeq := laterMarker(rd, rde, lr, lre)
	from := `(COALESCE(` + p + `.unread_from_ts, 0) > 0 AND (` + p + `.unread_from_ts, ` + p + `.unread_from_seq - 1) < (` + mTS + `, ` + mSeq + `))`
	return `CASE WHEN ` + from + ` THEN ` + p + `.unread_from_ts ELSE ` + mTS + ` END, CASE WHEN ` + from + ` THEN ` + p + `.unread_from_seq - 1 ELSE ` + mSeq + ` END`
}

func unreadBound() string {
	return unreadBoundFor("p", "rd", "rde", "lr", "lre")
}

// mentionsMeSQL is the condition on an event u for "it mentions me": m.mentions.user_ids holds my user ID ($1),
// or m.mentions.room is true.
const mentionsMeSQL = `((CASE WHEN json_valid(u.content) THEN json_extract(u.content, '$."m.mentions".room') END) IS 1
       OR EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(u.content) THEN u.content ELSE '{}' END, '$."m.mentions".user_ids')
                  WHERE value = $1))`

// mutedLabelSQL is the title of room r's first muted label, by label ID, or "".
const mutedLabelSQL = `COALESCE((SELECT ml.title FROM room_labels mrl JOIN labels ml ON ml.label_id = mrl.label_id
     WHERE mrl.room_id = r.room_id AND ml.muted = 1 ORDER BY mrl.label_id LIMIT 1), '')`

// mutedBySQL is what else mutes room r: 'account' (its account_prefs ap), 'label' (a muted label), or the empty string.
const mutedBySQL = `(CASE WHEN COALESCE(ap.muted, 0) = 1 THEN 'account' WHEN ` + mutedLabelSQL + ` <> '' THEN 'label' ELSE '' END)`

// sentStatusSQL is true for a message ev of mine that has gone: the network took it ("sent"), or it came from another
// device of mine and was stored without a status of its own ("").
const sentStatusSQL = `ev.status IN ('sent', '')`

// isNoteSQL is true for content that is a note (a timer change or a call, isNote): a system line, not a message
// anyone reads. content is the column expression.
func isNoteSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."` + actionMessageKey + `".type') END) IN ('` +
		timerActionType + `', '` + callActionType + `')`
}

// previewStatusSQL is InboxRow.PreviewStatus for room r's newest message ev ($1 is my user ID): for my message that
// has gone (not a note: isNoteSQL), "seen" when someone else's read marker (receipts, by the room prefix of its primary key) is at it or past
// it by (ts, seq), else "delivered" when a deliveries row names it (its primary key's prefix), else "sent"; "" for
// anything else.
var previewStatusSQL = `(CASE WHEN ev.sender = $1 AND ` + sentStatusSQL + ` AND (` + isNoteSQL("ev.content") + `) IS NOT 1 THEN
    CASE WHEN EXISTS (SELECT 1 FROM receipts rc JOIN events re ON re.event_id = rc.event_id
                      WHERE rc.room_id = r.room_id AND rc.user_id <> $1 AND (re.ts, re.seq) >= (ev.ts, ev.seq)) THEN 'seen'
         WHEN EXISTS (SELECT 1 FROM deliveries dv WHERE dv.event_id = ev.event_id) THEN 'delivered'
         ELSE 'sent' END
  ELSE '' END)`

// inboxColsSQL is the columns of an inbox row (scanInboxRow), for a room r with inboxJoinsSQL.
var inboxColsSQL = `r.room_id, r.network,
  COALESCE(NULLIF(p.local_name, ''), r.name), r.name, COALESCE(p.local_name, ''),
  r.topic,
  COALESCE(NULLIF(p.local_avatar_uri, ''), r.avatar_uri), COALESCE(p.local_avatar_uri, ''),
  COALESCE(p.spam_reported_at, 0),
  COALESCE((SELECT mcr.merge_id FROM merged_chat_rooms mcr WHERE mcr.room_id = r.room_id LIMIT 1), ''),
  r.is_direct, r.created_at, r.login_id,
  r.last_ts,
  COALESCE(ev.sender, ''), COALESCE(ev.type, ''), COALESCE(ev.content, ''), ` + previewStatusSQL + `,
  COALESCE(p.muted, 0),
  (SELECT COUNT(*) FROM events u WHERE ` + unreadSQL + `),
  (SELECT COUNT(*) FROM events u WHERE ` + unreadSQL + ` AND ` + mentionsMeSQL + `),
  ` + mutedBySQL + `, CASE WHEN COALESCE(ap.muted, 0) = 1 THEN '' ELSE ` + mutedLabelSQL + ` END,
  COALESCE(p.pinned_at, 0), COALESCE(p.archived_at, 0), COALESCE(p.low_priority, 0), COALESCE(p.hidden, 0),
  COALESCE(p.marked_unread, 0), r.request, COALESCE(p.draft, ''),
  COALESCE((SELECT group_concat(rl.label_id) FROM room_labels rl WHERE rl.room_id = r.room_id), ''),
  rm.room_id IS NOT NULL, COALESCE(rm.condition, ''), COALESCE(rm.due_at, 0), COALESCE(rm.set_at, 0), COALESCE(rm.fired_at, 0)`

// inboxJoinsSQL brings in what inboxColsSQL reads beside the room r.
var inboxJoinsSQL = `LEFT JOIN events ev ON ev.event_id = r.last_event_id
LEFT JOIN room_prefs p ON p.room_id = r.room_id
LEFT JOIN account_prefs ap ON ap.network = r.network
LEFT JOIN reminders rm ON rm.room_id = r.room_id
` + readMarkerJoins

// inboxSQL is the whole inbox in one statement. $1 is my user ID. Every part is an index lookup:
//   - rooms come out of rooms_last_ts already in display order (no sort);
//   - the preview event is a primary-key lookup on rooms.last_event_id;
//   - the unread and unread-mention counts are range scans of events_room_ts (room_id, ts, seq) from the read
//     marker onward (unreadSQL), so they only touch messages that are actually newer than the marker;
//   - prefs, account prefs, the reminder, labels and muted labels are primary-key lookups.
//
// primaryMergeRoomSQL is true when r is either not in a merged chat or is the single representative member room
// of its merged chat (the member room with the newest last_ts, tie-broken by created_at DESC and room_id ASC).
const primaryMergeRoomSQL = `NOT EXISTS (
  SELECT 1 FROM merged_chat_rooms mcr1
  JOIN merged_chat_rooms mcr2 ON mcr2.merge_id = mcr1.merge_id AND mcr2.room_id <> mcr1.room_id
  JOIN rooms r2 ON r2.room_id = mcr2.room_id
  WHERE mcr1.room_id = r.room_id
    AND (r2.last_ts > r.last_ts
         OR (r2.last_ts = r.last_ts AND (r2.created_at > r.created_at
             OR (r2.created_at = r.created_at AND r2.room_id < r.room_id))))
)`

var inboxSQL = `SELECT ` + inboxColsSQL + `
FROM rooms r
` + inboxJoinsSQL + `
WHERE ` + primaryMergeRoomSQL + `
ORDER BY r.last_ts DESC, r.created_at DESC`

// Inbox lists every room, newest message first; rooms without a message follow, newest created first.
func (s *Store) Inbox(ctx context.Context) ([]InboxRow, error) {
	rows, err := s.db.Query(ctx, inboxSQL, myID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []InboxRow
	for rows.Next() {
		r, err := s.scanInboxRow(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := s.enrichMergedInboxRows(ctx, out); err != nil {
		return nil, err
	}
	return out, nil
}

// enrichMergedInboxRows populates merged chat display name, avatar, newest preview, and summed unread counts for
// any InboxRow belonging to a merged chat.
func (s *Store) enrichMergedInboxRows(ctx context.Context, rows []InboxRow) error {
	var mergeIDs []string
	for _, r := range rows {
		if r.MergeID != "" && !slices.Contains(mergeIDs, r.MergeID) {
			mergeIDs = append(mergeIDs, r.MergeID)
		}
	}
	if len(mergeIDs) == 0 {
		return nil
	}
	type mergeAgg struct {
		name      string
		avatarURI string
		bestRow   InboxRow
		hasBest   bool
		unread    int
		mentions  int
		marked    bool
	}
	aggs := make(map[string]*mergeAgg, len(mergeIDs))
	for _, mid := range mergeIDs {
		var name, avatarURI string
		err := s.db.QueryRow(ctx, `SELECT name, avatar_uri FROM merged_chats WHERE merge_id = $1`, mid).Scan(&name, &avatarURI)
		if errors.Is(err, sql.ErrNoRows) {
			continue
		}
		if err != nil {
			return err
		}
		aggs[mid] = &mergeAgg{name: name, avatarURI: avatarURI}
		mRows, err := s.db.Query(ctx, `SELECT `+inboxColsSQL+`
			FROM merged_chat_rooms mcr
			JOIN rooms r ON r.room_id = mcr.room_id
			`+inboxJoinsSQL+`
			WHERE mcr.merge_id = $2
			ORDER BY r.last_ts DESC, r.created_at DESC, r.room_id ASC`, myID, mid)
		if err != nil {
			return err
		}
		for mRows.Next() {
			mr, scanErr := s.scanInboxRow(mRows)
			if scanErr != nil {
				mRows.Close()
				return scanErr
			}
			agg := aggs[mid]
			if !agg.hasBest {
				agg.bestRow = mr
				agg.hasBest = true
			}
			agg.unread += mr.Unread
			agg.mentions += mr.UnreadMentions
			agg.marked = agg.marked || mr.MarkedUnread
		}
		if err := errors.Join(mRows.Err(), mRows.Close()); err != nil {
			return err
		}
	}
	for i := range rows {
		mid := rows[i].MergeID
		agg, ok := aggs[mid]
		if !ok || !agg.hasBest {
			continue
		}
		if agg.name != "" {
			rows[i].Name = agg.name
		}
		if agg.avatarURI != "" {
			rows[i].AvatarURI = agg.avatarURI
		}
		rows[i].Unread = agg.unread
		rows[i].UnreadMentions = agg.mentions
		rows[i].MarkedUnread = agg.marked
	}
	return nil
}

// scanInboxRow reads one row of inboxSQL's columns.
func (s *Store) scanInboxRow(row dbutil.Scannable) (InboxRow, error) {
	var r InboxRow
	var direct, muted, low, hidden, markedUnread, request int
	var created, lastTS, pinnedAt, archivedAt int64
	var sender, typ, content, labels string
	var hasReminder bool
	var rem Reminder
	var dueAt, setAt, firedAt int64
	if err := row.Scan(&r.ID, &r.Network, &r.Name, &r.RemoteName, &r.LocalName, &r.Topic,
		&r.AvatarURI, &r.LocalAvatarURI, &r.SpamReportedAt, &r.MergeID,
		&direct, &created, &r.LoginID,
		&lastTS, &sender, &typ, &content, &r.PreviewStatus, &muted, &r.Unread, &r.UnreadMentions, &r.MutedBy, &r.MutedByName,
		&pinnedAt, &archivedAt, &low, &hidden, &markedUnread, &request, &r.Draft, &labels,
		&hasReminder, &rem.Condition, &dueAt, &setAt, &firedAt); err != nil {
		return InboxRow{}, err
	}
	r.IsDirect, r.CreatedAt, r.Muted = direct == 1, time.UnixMilli(created), muted == 1
	r.LastTS = msTime(lastTS)
	r.PreviewMine = sender == myID
	r.Preview, r.PreviewKind, r.PreviewMediaURI = previewOf(typ, content)
	if r.PreviewMediaURI != "" && strings.Contains(content, "after_read") && s.isContentViewOnce(context.Background(), r.ID, r.Network, r.PreviewKind, json.RawMessage(content)) {
		r.PreviewMediaURI = ""
	}
	if r.PreviewKind == "call" {
		note, _ := parseCallNote(typ, json.RawMessage(content))
		r.PreviewCall = &note
	}
	if r.MutedBy == "account" {
		r.MutedByName = s.networkName(r.Network)
	}
	r.PinnedAt, r.Archived = msTime(pinnedAt), archivedAt != 0
	r.LowPriority, r.Hidden, r.MarkedUnread, r.Request = low == 1, hidden == 1, markedUnread == 1, request == 1
	if labels != "" {
		for _, f := range strings.Split(labels, ",") {
			id, err := strconv.ParseInt(f, 10, 64)
			if err != nil {
				return InboxRow{}, err
			}
			r.Labels = append(r.Labels, id)
		}
		slices.Sort(r.Labels)
	}
	if hasReminder {
		rem.RoomID, rem.DueAt, rem.SetAt, rem.FiredAt = r.ID, msTime(dueAt), msTime(setAt), msTime(firedAt)
		r.Reminder = &rem
	}
	return r, nil
}

// previewOf turns the newest message's type and content into the inbox's one-line preview, its kind and, for an
// image or a sticker, the media to show beside it (the thumbnail when there is one). An encrypted placeholder
// has nothing readable, so it previews as empty text with no kind. A poll previews as its question. A note that the
// disappearing timer changed (a bridge's or mine) is "timer_change" with no text, and a bridge's call notice is
// "call" with no text (InboxRow.PreviewCall says what happened): their body is the bridge's English, and the app
// words them (Ruling 40).
func previewOf(typ, content string) (preview, kind, mediaURI string) {
	if _, ok := parseTimerNote(typ, json.RawMessage(content)); ok {
		return "", "timer_change", ""
	}
	if _, ok := parseCallNote(typ, json.RawMessage(content)); ok {
		return "", "call", ""
	}
	switch typ {
	case "":
		return "", "", ""
	case "m.room.encrypted":
		return "", "", ""
	case "m.sticker":
		kind = "sticker"
	case pollStartType:
		// A poll has no body to speak of: its question is the preview.
		question := ""
		if p, ok := parsePoll(json.RawMessage(content)); ok {
			question = p.Start.Question.String()
		}
		if r := []rune(question); len(r) > maxPreviewRunes {
			question = string(r[:maxPreviewRunes])
		}
		return question, "poll", ""
	default:
		kind = "text"
	}
	var c struct {
		Body    string `json:"body"`
		MsgType string `json:"msgtype"`
		URL     string `json:"url"`
		Info    struct {
			ThumbnailURL string `json:"thumbnail_url"`
		} `json:"info"`
	}
	_ = json.Unmarshal([]byte(content), &c) // malformed content just previews as empty
	if typ == "m.room.message" {
		switch c.MsgType {
		case "m.image":
			kind = "image"
		case "m.video":
			kind = "video"
		case "m.audio":
			kind = "audio"
		case "m.file":
			kind = "file"
		}
	}
	if kind == "image" || kind == "sticker" {
		mediaURI = c.Info.ThumbnailURL
		if mediaURI == "" {
			mediaURI = c.URL
		}
	}
	if r := []rune(c.Body); len(r) > maxPreviewRunes {
		c.Body = string(r[:maxPreviewRunes])
	}
	return c.Body, kind, mediaURI
}

// Cursor marks a position in a chat's history: the oldest event of the page you already have.
type Cursor struct {
	TS  time.Time
	Seq int64
}

// eventsBeforeSQL pages newest-first through events_room_ts. $1 room, $2 and $3 the cursor's ts (ms) and seq,
// $4 the number of rows wanted. Ordering by (ts, seq) matches the index, so deep pages cost no more than the first.
// It is the main timeline: a reply that stays in its thread is left out (mainTimelineSQL).
var eventsBeforeSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id = $1 AND (ts, seq) < ($2, $3) AND ` + mainTimelineSQL + `
ORDER BY ts DESC, seq DESC LIMIT $4`

// mainTimelineSQL is whether an event is in its chat's main timeline: everything but a reply that stays in its
// thread (isThreadReplySQL), which the thread pane reads (ThreadEventsBefore). A thread's root, and a reply also
// sent to the channel, stay.
var mainTimelineSQL = isThreadReplySQL("content") + ` IS NOT 1`

// EventsBefore returns up to limit events of the main timeline (no thread replies) older than before, newest first
// (nil before means the newest page).
// The returned cursor is for the next, older page; it is nil when there is no older event.
func (s *Store) EventsBefore(ctx context.Context, roomID string, before *Cursor, limit int) ([]Event, *Cursor, error) {
	if limit <= 0 {
		limit = 50
	}
	ts, seq := int64(math.MaxInt64), int64(math.MaxInt64)
	if before != nil {
		ts, seq = before.TS.UnixMilli(), before.Seq
	}
	rows, err := s.db.Query(ctx, eventsBeforeSQL, roomID, ts, seq, limit+1) // one extra row says whether an older page exists
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}
	if len(out) <= limit {
		return out, nil, nil
	}
	out = out[:limit]
	last := out[limit-1]
	return out, &Cursor{TS: last.TS, Seq: last.Seq}, nil
}

// MarkReadLocal records that the user read roomID up to eventID (whose time is ts) on this device. It is kept
// apart from SetRead, which is the network's own report; the unread count uses whichever is later. The local
// marker only moves forward: an older (ts, seq) than the one already kept is ignored, and publishes nothing.
func (s *Store) MarkReadLocal(ctx context.Context, roomID, eventID string, ts time.Time) error {
	_, err := s.AdvanceReadLocal(ctx, roomID, eventID, ts)
	return err
}

// AdvanceReadLocal is MarkReadLocal that also says whether the marker moved. It does not move when the chat was
// already read up to that event or beyond it.
func (s *Store) AdvanceReadLocal(ctx context.Context, roomID, eventID string, ts time.Time) (bool, error) {
	return s.advanceMarker(ctx, "local_reads", roomID, eventID, ts)
}

// advanceMarker moves table's read marker for roomID (reads or local_reads) to eventID, if that is later than
// where it is. The marker keeps the event's own time, so its (ts, seq) is exactly that event's. An event we do
// not have is kept at fallbackTS and compares on ts alone. It reports whether the marker moved, and publishes a
// "read" change when it did. A marker that moves to a message received after Courier first saw the chat is a read:
// with an enabled after_read rule it schedules the chat's archive (scheduleArchive), in the same transaction.
func (s *Store) advanceMarker(ctx context.Context, table, roomID, eventID string, fallbackTS time.Time) (bool, error) {
	return s.advanceMarkerThen(ctx, table, roomID, eventID, fallbackTS, nil)
}

// advanceMarkerThen is advanceMarker that also runs then, when it isn't nil and the marker moved, in the same
// transaction, with the (ts, seq) the marker moved to.
func (s *Store) advanceMarkerThen(ctx context.Context, table, roomID, eventID string, fallbackTS time.Time,
	then func(ctx context.Context, ts, seq int64) error,
) (bool, error) {
	moved := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		newTS, newSeq := fallbackTS.UnixMilli(), int64(math.MaxInt64) // an event we do not have yet: compare on ts alone
		err := s.db.QueryRow(ctx, "SELECT ts, seq FROM events WHERE event_id=$1 AND room_id=$2", eventID, roomID).Scan(&newTS, &newSeq)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var curTS, curSeq int64
		err = s.db.QueryRow(ctx, `SELECT m.ts, `+markerSeq("m", "e")+` FROM `+table+` m
			LEFT JOIN events e ON e.event_id = m.event_id AND e.ts = m.ts WHERE m.room_id=$1`, roomID).Scan(&curTS, &curSeq)
		switch {
		case err == nil:
			if newTS < curTS || (newTS == curTS && newSeq <= curSeq) {
				return nil // not later than what we have
			}
		case !errors.Is(err, sql.ErrNoRows):
			return err
		}
		if _, err = s.db.Exec(ctx, `INSERT INTO `+table+` (room_id, event_id, ts) VALUES ($1,$2,$3)
			ON CONFLICT(room_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`, roomID, eventID, newTS); err != nil {
			return err
		}
		moved = true
		if then != nil {
			if err = then(ctx, newTS, newSeq); err != nil {
				return err
			}
		}
		// I read the chat: with an enabled after_read rule it is archived that long from now. Only a read of a
		// message Courier received live counts, one after it first saw the chat (rooms.created_at is set when the
		// store first inserts the room and never changes). The markers an account brings in on its first sync are
		// older reads from the phone; scheduling on them would archive every chat already read there.
		var firstSeen int64
		if err = s.db.QueryRow(ctx, "SELECT COALESCE((SELECT created_at FROM rooms WHERE room_id=$1), 0)", roomID).Scan(&firstSeen); err != nil {
			return err
		}
		if firstSeen == 0 || newTS <= firstSeen {
			return nil
		}
		return s.scheduleArchive(ctx, roomID, trigAfterRead, s.now().UnixMilli())
	})
	if err == nil && moved {
		s.publish(Change{Kind: "read", RoomID: roomID, EventID: eventID})
	}
	return moved && err == nil, err
}

// LastMessage returns the chat's newest message-like event: the one its inbox row previews (rooms.last_event_id),
// so a reaction, an edit or a state event never counts. ok is false for a chat with no message yet.
func (s *Store) LastMessage(ctx context.Context, roomID string) (Event, bool, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id = (SELECT last_event_id FROM rooms WHERE room_id=$1)", roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return Event{}, false, nil
	}
	return e, err == nil, err
}

// FindReaction returns the ID of sender's reaction with key to target in roomID, if there is one that has not
// failed (pending or sent). A failed reaction does not count, so it can be sent again.
func (s *Store) FindReaction(ctx context.Context, roomID, sender, target, key string) (string, bool, error) {
	var id string
	err := s.db.QueryRow(ctx, `SELECT event_id FROM events
		WHERE room_id=$1 AND sender=$2 AND type='m.reaction' AND status <> 'failed'
		  AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END) = $3
		  AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".key') END) = $4
		ORDER BY ts, seq LIMIT 1`, roomID, sender, target, key).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return id, err == nil, err
}

// SetMuted sets whether the user muted roomID. It survives the bridge refreshing the room.
func (s *Store) SetMuted(ctx context.Context, roomID string, muted bool) error {
	_, err := s.db.Exec(ctx, `INSERT INTO room_prefs (room_id, muted) VALUES ($1,$2)
		ON CONFLICT(room_id) DO UPDATE SET muted=excluded.muted`, roomID, b2i(muted))
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}
