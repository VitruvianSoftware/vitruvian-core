// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"errors"
	"strconv"
	"strings"
)

// ErrBadValue is the answer for a value the store doesn't accept: a label title, colour or icon out of range, a
// draft too long, a spaces layout that moves or hides the inbox, a setting on a built-in space.
var ErrBadValue = errors.New("that isn't accepted")

// Space is one entry of the spaces bar: a built-in space, an account, or a label.
type Space struct {
	ID, Kind, Title, Network string // Kind: builtin | account | label. Title is "" for a built-in space: the app names those.
	LabelID                  int64
	Color                    int
	Icon                     string
	Hidden, Muted            bool
	ShowInInbox              string // all | dms | none; "" for builtin
	Chats, UnreadChats       int

	// AttentionChats is, for the inbox space only, how many of its unread chats nothing mutes (not the chat
	// itself, its account or a label): the Dock badge and the menu bar's count. 0 for every other space.
	AttentionChats int
}

const (
	kindBuiltin = "builtin"
	kindAccount = "account"
	kindLabel   = "label"

	showAll  = "all"
	showDMs  = "dms"
	showNone = "none"
)

// builtinSpaces are the built-in spaces in their default order. inbox is always first.
var builtinSpaces = []string{"inbox", "reminders", "requests", "low_priority", "send_later", "archive"}

// parseSpace splits a space ID into its kind and its account's network or its label ID. ok is false for anything
// that isn't a well-formed space ID.
func parseSpace(id string) (kind, network string, labelID int64, ok bool) {
	for _, b := range builtinSpaces {
		if id == b {
			return kindBuiltin, "", 0, true
		}
	}
	if n, found := strings.CutPrefix(id, "account:"); found && n != "" {
		return kindAccount, n, 0, true
	}
	if l, found := strings.CutPrefix(id, "label:"); found {
		if v, err := strconv.ParseInt(l, 10, 64); err == nil && v > 0 && strconv.FormatInt(v, 10) == l {
			return kindLabel, "", v, true
		}
	}
	return "", "", 0, false
}

// IsSpaceID reports whether id is a well-formed space ID: a built-in space, account:<network> or label:<id>. It
// doesn't say whether that account or label exists.
func IsSpaceID(id string) bool {
	_, _, _, ok := parseSpace(id)
	return ok
}

// placeSQL is where a chat is, first match wins: hidden, requests, low_priority, archive, otherwise inbox.
// r is the rooms alias and p the LEFT JOINed room_prefs alias.
func placeSQL(r, p string) string {
	return `(CASE WHEN COALESCE(` + p + `.hidden, 0) = 1 THEN 'hidden' WHEN ` + r + `.request = 1 THEN 'requests'
  WHEN COALESCE(` + p + `.low_priority, 0) = 1 THEN 'low_priority' WHEN COALESCE(` + p + `.archived_at, 0) > 0 THEN 'archive' ELSE 'inbox' END)`
}

// showAllowsSQL is whether a Show in Inbox setting (all | dms | none) lets a chat into the inbox space: all
// does, dms only a one-to-one chat, none never.
func showAllowsSQL(setting, isDirect string) string {
	return `(` + setting + ` = 'all' OR (` + setting + ` = 'dms' AND ` + isDirect + ` = 1))`
}

// shownInInboxSQL is whether a chat's account and every one of its labels let it into the inbox space. r is the
// rooms alias and ap the LEFT JOINed account_prefs alias.
func shownInInboxSQL(r, ap string) string {
	return `(` + showAllowsSQL(`COALESCE(`+ap+`.show_in_inbox, 'all')`, r+`.is_direct`) + ` AND NOT EXISTS (
  SELECT 1 FROM room_labels sl JOIN labels sll ON sll.label_id = sl.label_id
  WHERE sl.room_id = ` + r + `.room_id AND NOT ` + showAllowsSQL(`sll.show_in_inbox`, r+`.is_direct`) + `))`
}

// countFacts are the chat facts of spaceCountsSQL's materialized c.
var countFacts = chatFacts{place: "c.place", shown: "c.shown", reminded: "c.reminded", scheduled: "c.scheduled"}

// builtinCountRule is the place rule of built-in space id over c (placeRule), for spaceCountsSQL.
func builtinCountRule(id string) string {
	rule, ok := placeRule(countFacts, id)
	if !ok {
		panic("no place rule for space " + id)
	}
	return rule
}

// spaceCountsSQL counts each space's chats and unread chats in one statement ($1 is my user ID). Every room is
// read once (the materialized c); unread is unreadChatSQL, an EXISTS on events_room_ts from the read marker on, so
// it stops at the first unread message. Each space's rule is InboxPage's own (placeRule, scopedPlaceRule), so a
// space's count is the number of chats its pages list:
//   - inbox: place inbox, and the account and every label allow it (Show in Inbox);
//   - reminders: has a reminder (set or fired), any place but hidden;
//   - send_later: has a scheduled message (waiting, canceled or missed), any place but hidden;
//   - requests, low_priority, archive: that place;
//   - account:<n>: network n, place inbox, whatever Show in Inbox says;
//   - label:<id>: has that label, place inbox.
//
// The inbox's row also counts its unread chats that nothing mutes (mutedChatSQL): the Dock badge (Ruling 36). It
// is the same rule as the inbox's pages with one more condition, so the badge never depends on the space or
// filters the app is showing. Every other row says 0.
// Inferred (inventory 01 §18): a low-priority, hidden or archived chat is out of the inbox, and a request is not
// yet a conversation, so none of them asks for attention.
var spaceCountsSQL = `WITH c AS MATERIALIZED (
  SELECT r.room_id, r.network, ` + pageFacts.place + ` AS place, ` + pageFacts.shown + ` AS shown,
    ` + unreadChatSQL + ` AS unread, ` + mutedChatSQL + ` AS muted,
    EXISTS (SELECT 1 FROM reminders m WHERE m.room_id = r.room_id) AS reminded, ` + scheduledSQL("r") + ` AS scheduled
  FROM rooms r
  LEFT JOIN room_prefs p ON p.room_id = r.room_id
  LEFT JOIN account_prefs ap ON ap.network = r.network
  ` + readMarkerJoins + `
)
SELECT 'inbox', COUNT(*), COALESCE(SUM(c.unread), 0), COALESCE(SUM(c.unread AND NOT c.muted), 0) FROM c WHERE ` + builtinCountRule("inbox") + `
UNION ALL SELECT 'reminders', COUNT(*), COALESCE(SUM(c.unread), 0), 0 FROM c WHERE ` + builtinCountRule("reminders") + `
UNION ALL SELECT 'requests', COUNT(*), COALESCE(SUM(c.unread), 0), 0 FROM c WHERE ` + builtinCountRule("requests") + `
UNION ALL SELECT 'low_priority', COUNT(*), COALESCE(SUM(c.unread), 0), 0 FROM c WHERE ` + builtinCountRule("low_priority") + `
UNION ALL SELECT 'send_later', COUNT(*), COALESCE(SUM(c.unread), 0), 0 FROM c WHERE ` + builtinCountRule("send_later") + `
UNION ALL SELECT 'archive', COUNT(*), COALESCE(SUM(c.unread), 0), 0 FROM c WHERE ` + builtinCountRule("archive") + `
UNION ALL SELECT 'account:' || c.network, COUNT(*), SUM(c.unread), 0 FROM c WHERE ` + scopedPlaceRule(countFacts) + ` GROUP BY c.network
UNION ALL SELECT 'label:' || rl.label_id, COUNT(*), SUM(c.unread), 0 FROM c JOIN room_labels rl ON rl.room_id = c.room_id
  WHERE ` + scopedPlaceRule(countFacts) + ` GROUP BY rl.label_id`

// spaceCounts returns [chats, unread chats, attention chats] by space ID. A space with no chats is missing.
func (s *Store) spaceCounts(ctx context.Context) (map[string][3]int, error) {
	rows, err := s.db.Query(ctx, spaceCountsSQL, myID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string][3]int{}
	for rows.Next() {
		var id string
		var chats, unread, attention int
		if err := rows.Scan(&id, &chats, &unread, &attention); err != nil {
			return nil, err
		}
		out[id] = [3]int{chats, unread, attention}
	}
	return out, rows.Err()
}

// Spaces lists the spaces bar in layout order: the saved layout's order, then any space it doesn't name (a new
// label, an account linked since) at the end, visible, in the default order. The default order is the built-in
// spaces, then an account per entry of networks (the linked networks, in the app's order), then labels oldest
// first. A saved space that no longer exists (an unlinked account, a deleted label) is left out.
func (s *Store) Spaces(ctx context.Context, networks []string) ([]Space, error) {
	labels, err := s.Labels(ctx)
	if err != nil {
		return nil, err
	}
	accounts, err := s.accountPrefs(ctx)
	if err != nil {
		return nil, err
	}
	counts, err := s.spaceCounts(ctx)
	if err != nil {
		return nil, err
	}

	var all []Space
	for _, id := range builtinSpaces {
		all = append(all, Space{ID: id, Kind: kindBuiltin})
	}
	for _, n := range distinct(networks) {
		a, ok := accounts[n]
		if !ok {
			a = accountPref{showInInbox: showAll}
		}
		all = append(all, Space{
			ID: "account:" + n, Kind: kindAccount, Title: s.networkName(n), Network: n,
			Muted: a.muted, ShowInInbox: a.showInInbox,
		})
	}
	for _, l := range labels {
		all = append(all, Space{
			ID: labelSpaceID(l.ID), Kind: kindLabel, Title: l.Title, LabelID: l.ID, Color: l.Color,
			Icon: l.Icon, Muted: l.Muted, ShowInInbox: l.ShowInInbox,
		})
	}
	for i := range all {
		c := counts[all[i].ID]
		all[i].Chats, all[i].UnreadChats, all[i].AttentionChats = c[0], c[1], c[2]
	}

	byID := make(map[string]int, len(all))
	for i, sp := range all {
		byID[sp.ID] = i
	}
	rows, err := s.db.Query(ctx, "SELECT space_id, hidden FROM space_layout ORDER BY position")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Space, 0, len(all))
	placed := make(map[string]bool, len(all))
	for rows.Next() {
		var id string
		var hidden int
		if err := rows.Scan(&id, &hidden); err != nil {
			return nil, err
		}
		i, ok := byID[id]
		if !ok || placed[id] {
			continue
		}
		sp := all[i]
		sp.Hidden = hidden == 1
		out = append(out, sp)
		placed[id] = true
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for _, sp := range all {
		if !placed[sp.ID] {
			out = append(out, sp)
		}
	}
	return out, nil
}

type accountPref struct {
	muted       bool
	showInInbox string
}

func (s *Store) accountPrefs(ctx context.Context) (map[string]accountPref, error) {
	rows, err := s.db.Query(ctx, "SELECT network, muted, show_in_inbox FROM account_prefs")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]accountPref{}
	for rows.Next() {
		var n string
		var a accountPref
		var muted int
		if err := rows.Scan(&n, &muted, &a.showInInbox); err != nil {
			return nil, err
		}
		a.muted = muted == 1
		out[n] = a
	}
	return out, rows.Err()
}

// SetSpaceLayout saves the order of the spaces bar and which spaces are hidden. order must start with inbox, name
// each space once, and hold every space in hidden; inbox can't be hidden. Anything else is ErrBadValue. A space
// the layout doesn't name goes at the end, visible (see Spaces).
func (s *Store) SetSpaceLayout(ctx context.Context, order, hidden []string) error {
	if len(order) == 0 || order[0] != "inbox" {
		return ErrBadValue
	}
	inOrder := make(map[string]bool, len(order))
	for _, id := range order {
		if _, _, _, ok := parseSpace(id); !ok || inOrder[id] {
			return ErrBadValue
		}
		inOrder[id] = true
	}
	isHidden := make(map[string]bool, len(hidden))
	for _, id := range hidden {
		if id == "inbox" || !inOrder[id] {
			return ErrBadValue
		}
		isHidden[id] = true
	}
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		if _, err := s.db.Exec(ctx, "DELETE FROM space_layout"); err != nil {
			return err
		}
		for i, id := range order {
			if _, err := s.db.Exec(ctx, "INSERT INTO space_layout (space_id, position, hidden) VALUES ($1,$2,$3)",
				id, i, b2i(isHidden[id])); err != nil {
				return err
			}
		}
		return nil
	})
	if err == nil {
		s.publish(Change{Kind: "spaces"})
	}
	return err
}

// UpdateSpace changes an account's or a label's space settings: whether its chats are muted, and what it lets
// into the inbox space (all | dms | none). nil leaves a setting as it is. A built-in space has no settings
// (ErrBadValue); an unknown label is ErrNotFound.
func (s *Store) UpdateSpace(ctx context.Context, spaceID string, muted *bool, showInInbox *string) error {
	kind, network, labelID, ok := parseSpace(spaceID)
	if !ok || kind == kindBuiltin {
		return ErrBadValue
	}
	if showInInbox != nil && *showInInbox != showAll && *showInInbox != showDMs && *showInInbox != showNone {
		return ErrBadValue
	}
	var mutedInt *int
	if muted != nil {
		v := b2i(*muted)
		mutedInt = &v
	}
	switch kind {
	case kindAccount:
		if _, err := s.db.Exec(ctx, `INSERT INTO account_prefs (network, muted, show_in_inbox) VALUES ($1, COALESCE($2, 0), COALESCE($3, 'all'))
			ON CONFLICT(network) DO UPDATE SET muted=COALESCE($2, muted), show_in_inbox=COALESCE($3, show_in_inbox)`,
			network, mutedInt, showInInbox); err != nil {
			return err
		}
	case kindLabel:
		res, err := s.db.Exec(ctx, `UPDATE labels SET muted=COALESCE($2, muted), show_in_inbox=COALESCE($3, show_in_inbox) WHERE label_id=$1`,
			labelID, mutedInt, showInInbox)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
	}
	s.publish(Change{Kind: "spaces"})
	return nil
}
