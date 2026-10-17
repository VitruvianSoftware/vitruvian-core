// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"time"

	"go.mau.fi/util/dbutil"
)

// Rule is an auto-archive rule.
//   - Scope: "all", "account:<network>" or "label:<id>". An older_than rule's scope is the space it sweeps ("all" is
//     the inbox); after_reply and after_read rules are the General setting, scope "all".
//   - Trigger: "after_reply" (Duration after a message of mine), "after_read" (Duration after I read the chat), or
//     "older_than" (the chat's newest message is older than Duration).
//   - ChatType: "all", or "read" (only chats with nothing unread and not marked unread). "" is "all".
//   - Duration: one of the exact values ruleDurations allows for the trigger.
type Rule struct {
	ID                       int64
	Scope, Trigger, ChatType string
	Duration                 time.Duration
	Enabled                  bool
}

const (
	trigAfterReply = "after_reply"
	trigAfterRead  = "after_read"
	trigOlderThan  = "older_than"

	chatTypeAll  = "all"
	chatTypeRead = "read"

	scopeAll = "all"
)

// ruleDurations are the delays each trigger accepts, exactly. The app's default for the General setting is 10
// minutes (inventory 02 §1.2).
var ruleDurations = func() map[string][]time.Duration {
	const day = 24 * time.Hour
	after := []time.Duration{
		0, time.Minute, 5 * time.Minute, 10 * time.Minute, 30 * time.Minute,
		time.Hour, 4 * time.Hour, day, 7 * day,
	}
	return map[string][]time.Duration{
		trigAfterReply: after,
		trigAfterRead:  after,
		trigOlderThan:  {3 * day, 7 * day, 14 * day, 28 * day, 90 * day, 365 * day},
	}
}()

// checkRule puts r in canonical form and checks its shape. Anything out of shape is ErrBadValue.
func checkRule(r *Rule) error {
	if r.ChatType == "" {
		r.ChatType = chatTypeAll
	}
	if r.ChatType != chatTypeAll && r.ChatType != chatTypeRead {
		return ErrBadValue
	}
	durations, ok := ruleDurations[r.Trigger]
	if !ok || !slices.Contains(durations, r.Duration) {
		return ErrBadValue
	}
	if r.Scope == scopeAll {
		return nil
	}
	if r.Trigger != trigOlderThan {
		return ErrBadValue // the General setting applies to every chat
	}
	if kind, _, _, ok := parseSpace(r.Scope); !ok || (kind != kindAccount && kind != kindLabel) {
		return ErrBadValue
	}
	return nil
}

// ruleSpace is the space an older_than rule's scope sweeps.
func ruleSpace(scope string) string {
	if scope == scopeAll {
		return "inbox"
	}
	return scope
}

// SetRule saves r and returns it as stored; ID 0 makes a new rule. It is ErrBadValue when r is out of shape
// (checkRule), when it would make a second enabled after_reply or after_read rule, or a second older_than rule for
// the same space. An unknown rule ID or label is ErrNotFound.
//
// Archives a rule has already scheduled follow it: a new delay moves them by the difference (they still count
// from the same reply or read), and turning the rule off or changing its trigger drops them.
func (s *Store) SetRule(ctx context.Context, r Rule) (Rule, error) {
	if err := checkRule(&r); err != nil {
		return Rule{}, err
	}
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		if kind, _, labelID, _ := parseSpace(r.Scope); kind == kindLabel {
			var one int
			err := s.db.QueryRow(ctx, "SELECT 1 FROM labels WHERE label_id=$1", labelID).Scan(&one)
			if errors.Is(err, sql.ErrNoRows) {
				return ErrNotFound
			}
			if err != nil {
				return err
			}
		}
		var old Rule
		if r.ID != 0 {
			var err error
			if old, err = scanRule(s.db.QueryRow(ctx, "SELECT "+ruleCols+" FROM auto_archive_rules WHERE rule_id=$1", r.ID)); errors.Is(err, sql.ErrNoRows) {
				return ErrNotFound
			} else if err != nil {
				return err
			}
		}
		var clash int
		switch {
		case r.Trigger == trigOlderThan:
			if err := s.db.QueryRow(ctx, "SELECT COUNT(*) FROM auto_archive_rules WHERE trigger=$1 AND scope=$2 AND rule_id<>$3",
				trigOlderThan, r.Scope, r.ID).Scan(&clash); err != nil {
				return err
			}
		case r.Enabled:
			if err := s.db.QueryRow(ctx, "SELECT COUNT(*) FROM auto_archive_rules WHERE enabled=1 AND trigger IN ($1,$2) AND rule_id<>$3",
				trigAfterReply, trigAfterRead, r.ID).Scan(&clash); err != nil {
				return err
			}
		}
		if clash > 0 {
			return ErrBadValue
		}
		if r.ID == 0 {
			return s.db.QueryRow(ctx, `INSERT INTO auto_archive_rules (scope, trigger, chat_type, duration_ms, enabled)
				VALUES ($1,$2,$3,$4,$5) RETURNING rule_id`, r.Scope, r.Trigger, r.ChatType, r.Duration.Milliseconds(), b2i(r.Enabled)).Scan(&r.ID)
		}
		if _, err := s.db.Exec(ctx, `UPDATE auto_archive_rules SET scope=$2, trigger=$3, chat_type=$4, duration_ms=$5, enabled=$6
			WHERE rule_id=$1`, r.ID, r.Scope, r.Trigger, r.ChatType, r.Duration.Milliseconds(), b2i(r.Enabled)); err != nil {
			return err
		}
		var err error
		switch {
		case !r.Enabled || r.Trigger != old.Trigger:
			_, err = s.db.Exec(ctx, "DELETE FROM archive_due WHERE rule_id=$1", r.ID)
		case r.Duration != old.Duration:
			_, err = s.db.Exec(ctx, "UPDATE archive_due SET due_at = due_at + $2 WHERE rule_id=$1", r.ID, (r.Duration - old.Duration).Milliseconds())
		}
		return err
	})
	if err != nil {
		return Rule{}, err
	}
	return r, nil
}

const ruleCols = "rule_id, scope, trigger, chat_type, duration_ms, enabled"

func scanRule(row dbutil.Scannable) (Rule, error) {
	var r Rule
	var ms int64
	var enabled int
	err := row.Scan(&r.ID, &r.Scope, &r.Trigger, &r.ChatType, &ms, &enabled)
	r.Duration, r.Enabled = time.Duration(ms)*time.Millisecond, enabled == 1
	return r, err
}

// Rules lists every auto-archive rule, oldest first.
func (s *Store) Rules(ctx context.Context) ([]Rule, error) {
	rows, err := s.db.Query(ctx, "SELECT "+ruleCols+" FROM auto_archive_rules ORDER BY rule_id")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Rule
	for rows.Next() {
		r, err := scanRule(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// DeleteRule deletes a rule, and the archives it had scheduled. An unknown ID is ErrNotFound.
func (s *Store) DeleteRule(ctx context.Context, id int64) error {
	res, err := s.db.Exec(ctx, "DELETE FROM auto_archive_rules WHERE rule_id=$1", id) // archive_due cascades
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// scheduleArchive is what a reply (trigAfterReply) or a read (trigAfterRead) at from (Unix ms) does when an
// enabled rule has that trigger: it schedules the chat's archive at from + the rule's delay, replacing one already
// pending. It runs inside the caller's transaction (InsertEvent, advanceMarker). A pinned chat is scheduled too;
// ArchiveDue leaves it alone.
func (s *Store) scheduleArchive(ctx context.Context, roomID, trigger string, from int64) error {
	_, err := s.db.Exec(ctx, `INSERT INTO archive_due (room_id, due_at, rule_id)
		SELECT $1, $2 + duration_ms, rule_id FROM auto_archive_rules WHERE enabled = 1 AND trigger = $3 ORDER BY rule_id LIMIT 1
		ON CONFLICT(room_id) DO UPDATE SET due_at=excluded.due_at, rule_id=excluded.rule_id`, roomID, from, trigger)
	return err
}

// ArchiveMatch picks chats to archive in one go.
type ArchiveMatch struct {
	Space     string        // "" is "inbox"; inbox, account:<n> or label:<id>. Only the chats in its inbox place count.
	ReadOnly  bool          // only chats with nothing unread and not marked unread
	OlderThan time.Duration // only chats whose newest message (or, with none, whose creation) is older; 0 is any age
	DryRun    bool          // say which, change nothing
}

// ArchiveMatching archives the chats m picks, all in one transaction, and returns them by room ID; with DryRun it
// only returns them. It looks only at the chats in the space's inbox place: what the space lists when no place
// filter is on. A pinned chat is never picked. A space that has no inbox place (the built-in spaces other than
// inbox), an unknown space or a negative OlderThan is ErrBadValue. Each chat archived changes ("room").
func (s *Store) ArchiveMatching(ctx context.Context, m ArchiveMatch) ([]string, error) {
	query, args, err := s.matchSQL(m)
	if err != nil {
		return nil, err
	}
	if m.DryRun {
		return s.roomIDs(ctx, query, args...)
	}
	var picked []string
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		if picked, err = s.roomIDs(ctx, query, args...); err != nil {
			return err
		}
		return s.archiveRooms(ctx, picked, s.now().UnixMilli())
	})
	if err != nil {
		return nil, err
	}
	for _, id := range picked {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return picked, nil
}

// matchSQL is the statement that lists the room IDs m picks, in room ID order. Values travel as arguments only.
func (s *Store) matchSQL(m ArchiveMatch) (string, []any, error) {
	if m.OlderThan < 0 {
		return "", nil, ErrBadValue
	}
	space := m.Space
	if space == "" {
		space = "inbox"
	}
	kind, network, labelID, ok := parseSpace(space)
	if !ok || (kind == kindBuiltin && space != "inbox") {
		return "", nil, ErrBadValue
	}
	var args sqlArgs
	if m.ReadOnly {
		args = sqlArgs{myID} // $1 of unreadChatSQL
	}
	where := []string{`COALESCE(p.pinned_at, 0) = 0`}
	switch kind {
	case kindBuiltin:
		rule, _ := placeRule(pageFacts, "inbox")
		where = append(where, rule)
	case kindAccount:
		where = append(where, scopedPlaceRule(pageFacts), `r.network = `+args.add(network))
	case kindLabel:
		where = append(where, scopedPlaceRule(pageFacts),
			`EXISTS (SELECT 1 FROM room_labels ql WHERE ql.room_id = r.room_id AND ql.label_id = `+args.add(labelID)+`)`)
	}
	joins := ""
	if m.ReadOnly {
		where = append(where, `NOT `+unreadChatSQL)
		joins = "\n  " + readMarkerJoins
	}
	if m.OlderThan > 0 {
		cutoff := s.now().Add(-m.OlderThan).UnixMilli()
		where = append(where, `(CASE WHEN r.last_ts > 0 THEN r.last_ts ELSE r.created_at END) < `+args.add(cutoff))
	}
	query := `SELECT r.room_id FROM rooms r
  LEFT JOIN room_prefs p ON p.room_id = r.room_id
  LEFT JOIN account_prefs ap ON ap.network = r.network` + joins + `
  WHERE ` + strings.Join(where, `
    AND `) + `
  ORDER BY r.room_id`
	return query, args, nil
}

// roomIDs runs a statement that selects room IDs.
func (s *Store) roomIDs(ctx context.Context, query string, args ...any) ([]string, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// archiveRooms archives the chats in ids at now (Unix ms) and drops their pending auto-archives, inside the
// caller's transaction. The caller has picked chats that aren't pinned or archived.
func (s *Store) archiveRooms(ctx context.Context, ids []string, now int64) error {
	if len(ids) == 0 {
		return nil
	}
	list, _ := json.Marshal(ids)
	if _, err := s.db.Exec(ctx, `INSERT INTO room_prefs (room_id, archived_at) SELECT value, $2 FROM json_each($1) WHERE true
		ON CONFLICT(room_id) DO UPDATE SET archived_at=excluded.archived_at`, string(list), now); err != nil {
		return err
	}
	_, err := s.db.Exec(ctx, "DELETE FROM archive_due WHERE room_id IN (SELECT value FROM json_each($1))", string(list))
	return err
}

// archiveDueSQL lists the pending auto-archives due by $2 (Unix ms; $1 is my user ID), each with whether to carry
// it out: its rule is still enabled, the chat isn't pinned and is in the inbox place, and, for a rule for read
// chats, it has nothing unread and isn't marked unread.
var archiveDueSQL = `SELECT d.room_id, (ru.enabled = 1 AND COALESCE(p.pinned_at, 0) = 0 AND ` + scopedPlaceRule(pageFacts) + `
    AND (ru.chat_type = 'all' OR NOT ` + unreadChatSQL + `)) AS take
  FROM archive_due d
  JOIN auto_archive_rules ru ON ru.rule_id = d.rule_id
  JOIN rooms r ON r.room_id = d.room_id
  LEFT JOIN room_prefs p ON p.room_id = r.room_id
  ` + readMarkerJoins + `
  WHERE d.due_at <= $2
  ORDER BY d.room_id`

// ArchiveDue carries out the pending auto-archives (after a reply or a read) that are due by now, and returns the
// chats it archived. A pending archive it doesn't carry out (the chat was pinned, moved out of the inbox, or has
// something unread under a rule for read chats) is dropped all the same, so nothing stays due for ever. Each
// chat archived changes ("room").
func (s *Store) ArchiveDue(ctx context.Context) ([]string, error) {
	now := s.now().UnixMilli()
	var archived []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		archived = nil
		rows, err := s.db.Query(ctx, archiveDueSQL, myID, now)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id string
			var take bool
			if err := rows.Scan(&id, &take); err != nil {
				rows.Close()
				return err
			}
			if take {
				archived = append(archived, id)
			}
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if _, err := s.db.Exec(ctx, "DELETE FROM archive_due WHERE due_at <= $1", now); err != nil {
			return err
		}
		return s.archiveRooms(ctx, archived, now)
	})
	if err != nil {
		return nil, err
	}
	for _, id := range archived {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return archived, nil
}

// SweepOlderThan runs every enabled older_than rule over its space (ArchiveMatching, for read chats only when the
// rule says so), and returns the chats archived, rule by rule.
func (s *Store) SweepOlderThan(ctx context.Context) ([]string, error) {
	rules, err := s.Rules(ctx)
	if err != nil {
		return nil, err
	}
	var archived []string
	var errs []error
	for _, r := range rules {
		if !r.Enabled || r.Trigger != trigOlderThan {
			continue
		}
		ids, err := s.ArchiveMatching(ctx, ArchiveMatch{Space: ruleSpace(r.Scope), ReadOnly: r.ChatType == chatTypeRead, OlderThan: r.Duration})
		if err != nil {
			errs = append(errs, err)
			continue
		}
		archived = append(archived, ids...)
	}
	return archived, errors.Join(errs...)
}
