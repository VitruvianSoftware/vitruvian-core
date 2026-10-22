// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// A timer-change note says a chat's disappearing timer changed. A bridge writes one (bridgev2's
// DisappearingMessageNotice, portal.go:4982–5068; WhatsApp's wa-misc.go:238 and Signal's from-signal.go:211 the
// same) as an m.notice whose body is the bridge's English and whose com.beeper.action_message is
// {type: "disappearing_timer", timer (ms), timer_type, implicit}. The app draws the note from the action message in
// Courier's words; the engine never shows or indexes the body (Ruling 40).
//
// A change made in Courier gets no note from the bridge: WhatsApp, Signal and Telegram all store the new setting on
// the portal when they take it (e.g. mautrix-whatsapp handlematrix.go:397), so the network's echo equals it and is
// dropped (DontBridge, wa-misc.go:218/244), and bridgev2's room-meta handler (portal.go:1818–1858) sends none. So
// the engine writes the note itself (InsertTimerNote): the same shape, mine, with an empty body and localKey set,
// never handed to a bridge.

// actionMessageKey is the content key of a bridge's action message: a note of something done, not a person writing.
const actionMessageKey = "com.beeper.action_message"

// timerActionType is the action message type of a timer-change note.
const timerActionType = "disappearing_timer"

// localKey marks a note the engine wrote for a change made here: never sent, so no network or bridge has it.
const localKey = "fi.courier.local"

// timerEchoWindow is how soon after my note a bridge's note of the same setting must arrive to be the network
// echoing my change rather than a change of its own.
// Inferred: no pinned bridge passes such an echo on (see above), so this only guards a bridge that would; an echo
// comes back within seconds, and minutes leave room for a slow network. A later note of the same setting is kept: a
// change can come and go with no note between (bridgev2 sends none when a chat's info is synced with
// ExcludeChangesFromTimeline, portal.go:5182–5190).
const timerEchoWindow = 5 * time.Minute

// hasActionMessageSQL is true for content that carries an action message (any type). content is the column
// expression. (Go twin: isActionMessage.)
func hasActionMessageSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_type(` + content + `, '$."` + actionMessageKey + `"') END) = 'object'`
}

// isTimerNoteSQL is true for content that is a timer-change note. content is the column expression. (Go twin:
// parseTimerNote.)
func isTimerNoteSQL(content string) string {
	return `(CASE WHEN json_valid(` + content + `) THEN json_extract(` + content + `, '$."` + actionMessageKey + `".type') END) = '` + timerActionType + `'`
}

// lastTimerNoteSQL is room $1's timer-change note that arrived last (by seq). Its WHERE is events_timer_notes', so
// the planner reads that partial index (TestLastTimerNoteUsesItsIndex).
var lastTimerNoteSQL = `SELECT content, ts, seq FROM events
WHERE room_id = $1 AND type = 'm.room.message' AND ` + isTimerNoteSQL("content") + `
ORDER BY seq DESC LIMIT 1`

// isActionMessage reports whether content carries an action message: a note a bridge (or the engine) wrote of
// something done, in the bridge's words. It is never indexed. (SQL twin: hasActionMessageSQL.)
func isActionMessage(content json.RawMessage) bool {
	// Every message is asked when it is indexed: most never mention the key, and need no parse.
	if !bytes.Contains(content, []byte(actionMessageKey)) {
		return false
	}
	var c map[string]json.RawMessage
	if json.Unmarshal(content, &c) != nil {
		return false
	}
	var action map[string]json.RawMessage
	return json.Unmarshal(c[actionMessageKey], &action) == nil && action != nil
}

// timerSetting is a disappearing timer as a note states it, normalised as bridgev2 does: no timer is type "".
type timerSetting struct {
	Type    string
	TimerMS int64
}

func normalTimer(typ string, timerMS int64) timerSetting {
	if timerMS <= 0 || typ == "" {
		return timerSetting{}
	}
	return timerSetting{Type: typ, TimerMS: timerMS}
}

// timerNote is what a timer-change note says, and where it came from.
type timerNote struct {
	Setting  timerSetting
	Local    bool // written here for a change made here (localKey)
	Backfill bool // a bridge's note of history (its action message's backfill)
}

// parseTimerNote reads a timer-change note: an m.room.message whose action message is of type
// disappearing_timer. ok is false for anything else.
func parseTimerNote(typ string, content json.RawMessage) (timerNote, bool) {
	// Every event is asked when it arrives, and every chat's newest when the inbox is read: most never mention the
	// type, and need no parse.
	if typ != "m.room.message" || !bytes.Contains(content, []byte(timerActionType)) {
		return timerNote{}, false
	}
	var c struct {
		Action *struct {
			Type      string  `json:"type"`
			Timer     float64 `json:"timer"`
			TimerType string  `json:"timer_type"`
			Backfill  bool    `json:"backfill"`
		} `json:"com.beeper.action_message"`
		Local bool `json:"fi.courier.local"`
	}
	if json.Unmarshal(content, &c) != nil || c.Action == nil || c.Action.Type != timerActionType {
		return timerNote{}, false
	}
	return timerNote{
		Setting: normalTimer(c.Action.TimerType, int64(c.Action.Timer)), Local: c.Local, Backfill: c.Action.Backfill,
	}, true
}

// isTimerNote reports whether e is a timer-change note, a bridge's or mine.
func isTimerNote(e Event) bool {
	_, ok := parseTimerNote(e.Type, e.Content)
	return ok
}

// TimerNoteContent is the content of the note for a timer change made here: the bridge's shape (an m.notice with
// com.beeper.action_message, implicit false), an empty body (the app words it), and localKey. typ "" (or timer 0)
// is the timer turned off.
func TimerNoteContent(typ string, timer time.Duration) json.RawMessage {
	set := normalTimer(typ, timer.Milliseconds())
	b, _ := json.Marshal(map[string]any{
		"msgtype": "m.notice", "body": "", "m.mentions": map[string]any{},
		actionMessageKey: map[string]any{"type": timerActionType, "timer": set.TimerMS, "timer_type": set.Type, "implicit": false},
		localKey:         true,
	})
	return b
}

// LastSeq is the arrival order last handed out: an event that arrives after this call has a higher seq.
func (s *Store) LastSeq() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.seq
}

// lastTimerNote is roomID's timer-change note that arrived last. ok is false when it has none.
func (s *Store) lastTimerNote(ctx context.Context, roomID string) (note timerNote, ts time.Time, seq int64, ok bool, err error) {
	var content string
	var tsMS int64
	err = s.db.QueryRow(ctx, lastTimerNoteSQL, roomID).Scan(&content, &tsMS, &seq)
	if errors.Is(err, sql.ErrNoRows) {
		return timerNote{}, time.Time{}, 0, false, nil
	}
	if err != nil {
		return timerNote{}, time.Time{}, 0, false, err
	}
	note, ok = parseTimerNote("m.room.message", json.RawMessage(content))
	return note, time.UnixMilli(tsMS), seq, ok, nil
}

// echoesLocalNote reports whether e, a bridge's timer-change note arriving now, is the network echoing the change
// my last note says I made here: the chat's last note is mine (local), of the same setting, and e came within
// timerEchoWindow of it. For a live note that is its arrival (the store's clock, the clock my note's time came
// from); for a backfilled one it is the note's own time, either side of mine, since a backfill arrives whenever the
// bridge gets to it and carries the time of the change. It runs inside InsertEvent's transaction.
func (s *Store) echoesLocalNote(ctx context.Context, e Event) (bool, error) {
	note, ok := parseTimerNote(e.Type, e.Content)
	if !ok || note.Local {
		return false, nil
	}
	last, ts, _, found, err := s.lastTimerNote(ctx, e.RoomID)
	if err != nil || !found || !last.Local || last.Setting != note.Setting {
		return false, err
	}
	since := s.now().Sub(ts)
	if note.Backfill {
		since = e.TS.Sub(ts).Abs()
	}
	return since <= timerEchoWindow, nil
}

// InsertTimerNote stores the note that I changed roomID's disappearing timer here: eventID at ts, mine, sent (there
// is no network to wait on: it is never handed to a bridge), with TimerNoteContent. It is the chat's newest thing,
// so the inbox previews it as a timer change; but it isn't unread or searchable, isn't my reply for auto-archive
// and isn't "I replied" for a reminder.
//
// afterSeq is LastSeq from before the change was sent. When a bridge's note of the same setting arrived since, the
// network has already told of this change, so nothing is stored and inserted is false (Ruling 40: one note).
func (s *Store) InsertTimerNote(ctx context.Context, roomID, eventID, typ string, timer time.Duration, ts time.Time, afterSeq int64) (inserted bool, err error) {
	e := Event{
		RoomID: roomID, EventID: eventID, Sender: string(ids.Me), Type: "m.room.message",
		Content: TimerNoteContent(typ, timer), TS: ts, Status: "sent",
	}
	seq := s.nextSeq()
	var cameBack bool
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		last, _, lastSeq, found, err := s.lastTimerNote(ctx, roomID)
		if err != nil {
			return err
		}
		if found && !last.Local && lastSeq > afterSeq && last.Setting == normalTimer(typ, timer.Milliseconds()) {
			inserted = false
			return nil
		}
		inserted, cameBack, err = s.insertEvent(ctx, e, seq)
		return err
	})
	if err != nil {
		return false, err
	}
	s.publishInserted(e, seq, inserted, cameBack)
	return inserted, nil
}
