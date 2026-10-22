// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// Version is one version of a message: its text, its HTML if it has any, and when it was written.
type Version struct {
	Body, FormattedBody string
	TS                  time.Time
}

// liveEditsSQL lists the live edits of message $1 sent by $2, oldest first, through events_edits: currentEditSQL's
// rule (not deleted, not failed) in the other order. The room is checked in Go, as CurrentText does.
var liveEditsSQL = `SELECT room_id, content, ts FROM events
WHERE ` + editTargetSQL("content") + ` = $1 AND type = 'm.room.message' AND ` + isEditSQL("content") + `
  AND sender = $2 AND redacted = 0 AND status <> 'failed'
ORDER BY ts, seq`

// textOf reads a message's body and formatted_body (only an org.matrix.custom.html one counts). A reply loses its
// fallback: the quoted lines of the body, and the mx-reply block of the HTML.
func textOf(content json.RawMessage) (body, formatted string) {
	var c struct {
		Body          string          `json:"body"`
		Format        string          `json:"format"`
		FormattedBody string          `json:"formatted_body"`
		RelatesTo     json.RawMessage `json:"m.relates_to"`
	}
	_ = json.Unmarshal(content, &c) // content that can't be read has no text
	if c.Format == "org.matrix.custom.html" {
		formatted = c.FormattedBody
	}
	body = c.Body
	if isReply(c.RelatesTo) {
		body = cutReplyFallback(body)
		if _, after, found := strings.Cut(formatted, "</mx-reply>"); found && strings.HasPrefix(formatted, "<mx-reply>") {
			formatted = after
		}
	}
	return body, formatted
}

// EditHistory is message eventID as it was first sent, then each of its live edits by its own sender (not deleted,
// not refused by the network), oldest first. An unknown or deleted message is ErrNotFound; one never edited has just
// its original.
func (s *Store) EditHistory(ctx context.Context, eventID string) ([]Version, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1 AND redacted = 0", eventID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	body, formatted := textOf(e.Content)
	out := []Version{{Body: body, FormattedBody: formatted, TS: e.TS}}
	rows, err := s.db.Query(ctx, liveEditsSQL, eventID, e.Sender)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var roomID, content string
		var ts int64
		if err := rows.Scan(&roomID, &content, &ts); err != nil {
			return nil, err
		}
		var c struct {
			NewContent json.RawMessage `json:"m.new_content"`
		}
		if roomID != e.RoomID || json.Unmarshal([]byte(content), &c) != nil || len(c.NewContent) == 0 {
			continue
		}
		body, formatted := textOf(c.NewContent)
		out = append(out, Version{Body: body, FormattedBody: formatted, TS: time.UnixMilli(ts)})
	}
	return out, rows.Err()
}
