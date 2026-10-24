// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"slices"
	"strings"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// MergedChat is a virtual chat combining two or more 1:1 rooms across networks into one timeline.
type MergedChat struct {
	MergeID    string   `json:"merge_id"`
	Name       string   `json:"name"`
	AvatarURI  string   `json:"avatar_uri"`
	LastRoomID string   `json:"last_room_id"`
	RoomIDs    []string `json:"room_ids"`
	Networks   []string `json:"networks"`
	CreatedTS  int64    `json:"created_ts"`
}

// MergeSuggestion proposes merging two or more unmerged 1:1 rooms that appear to be with the same person.
type MergeSuggestion struct {
	DisplayName string   `json:"display_name"`
	Reason      string   `json:"reason"` // "identifier" or "display_name"
	RoomIDs     []string `json:"room_ids"`
	Networks    []string `json:"networks"`
}

func newMergeID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("merge:%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func dedupRoomIDs(roomIDs []string) ([]string, error) {
	out := make([]string, 0, len(roomIDs))
	seen := make(map[string]struct{}, len(roomIDs))
	for _, id := range roomIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			return nil, ErrBadValue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	if len(out) < 2 {
		return nil, ErrBadValue
	}
	return out, nil
}

type memberRoomMeta struct {
	roomID    string
	network   string
	name      string
	avatarURI string
	lastTS    int64
}

func (s *Store) loadMemberRoomMeta(ctx context.Context, roomIDs []string) ([]memberRoomMeta, error) {
	metas := make([]memberRoomMeta, 0, len(roomIDs))
	for _, roomID := range roomIDs {
		var m memberRoomMeta
		m.roomID = roomID
		err := s.db.QueryRow(
			ctx, `
			SELECT r.network,
			       COALESCE(NULLIF(p.local_name, ''), r.name),
			       COALESCE(NULLIF(p.local_avatar_uri, ''), r.avatar_uri),
			       r.last_ts
			FROM rooms r
			LEFT JOIN room_prefs p ON p.room_id = r.room_id
			WHERE r.room_id = $1`, roomID,
		).Scan(&m.network, &m.name, &m.avatarURI, &m.lastTS)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		metas = append(metas, m)
	}
	return metas, nil
}

// CreateMergedChat creates a merged chat combining roomIDs (at least 2 rooms) and sets last_room_id to the member
// room with the highest last_ts.
func (s *Store) CreateMergedChat(ctx context.Context, name string, roomIDs []string) (MergedChat, error) {
	cleanIDs, err := dedupRoomIDs(roomIDs)
	if err != nil {
		return MergedChat{}, err
	}
	name = strings.TrimSpace(name)
	mergeID := newMergeID()
	createdTS := s.now().UnixMilli()

	var mc MergedChat
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		metas, err := s.loadMemberRoomMeta(ctx, cleanIDs)
		if err != nil {
			return err
		}
		lastRoomID := metas[0].roomID
		bestTS := metas[0].lastTS
		avatarURI := ""
		networks := make([]string, 0, len(metas))
		for _, m := range metas {
			networks = append(networks, m.network)
			if m.lastTS > bestTS {
				bestTS = m.lastTS
				lastRoomID = m.roomID
			}
			if avatarURI == "" && m.avatarURI != "" {
				avatarURI = m.avatarURI
			}
		}
		if name == "" {
			name = metas[0].name
		}
		if _, err := s.db.Exec(
			ctx, `
			INSERT INTO merged_chats (merge_id, name, avatar_uri, last_room_id, created_ts)
			VALUES ($1, $2, $3, $4, $5)`,
			mergeID, name, avatarURI, lastRoomID, createdTS,
		); err != nil {
			return err
		}
		for i, id := range cleanIDs {
			if _, err := s.db.Exec(ctx, `DELETE FROM merged_chat_rooms WHERE room_id = $1`, id); err != nil {
				return err
			}
			if _, err := s.db.Exec(
				ctx, `
				INSERT INTO merged_chat_rooms (merge_id, room_id, position)
				VALUES ($1, $2, $3)`,
				mergeID, id, i,
			); err != nil {
				return err
			}
		}
		mc = MergedChat{
			MergeID:    mergeID,
			Name:       name,
			AvatarURI:  avatarURI,
			LastRoomID: lastRoomID,
			RoomIDs:    cleanIDs,
			Networks:   networks,
			CreatedTS:  createdTS,
		}
		return nil
	})
	if err != nil {
		return MergedChat{}, err
	}
	for _, id := range cleanIDs {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return mc, nil
}

// UpdateMergedChat updates an existing merged chat's name, member rooms, and active last_room_id.
func (s *Store) UpdateMergedChat(ctx context.Context, mergeID, name string, roomIDs []string, lastRoomID string) (MergedChat, error) {
	mergeID = strings.TrimSpace(mergeID)
	if mergeID == "" {
		return MergedChat{}, ErrBadValue
	}
	cleanIDs, err := dedupRoomIDs(roomIDs)
	if err != nil {
		return MergedChat{}, err
	}
	if lastRoomID != "" && !slices.Contains(cleanIDs, lastRoomID) {
		return MergedChat{}, ErrBadValue
	}
	name = strings.TrimSpace(name)

	var mc MergedChat
	var notifyRooms []string
	err = s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var curName, curAvatar, curLastRoom string
		var createdTS int64
		err := s.db.QueryRow(
			ctx, `
			SELECT name, avatar_uri, last_room_id, created_ts
			FROM merged_chats WHERE merge_id = $1`, mergeID,
		).Scan(&curName, &curAvatar, &curLastRoom, &createdTS)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return err
		}

		oldRooms, err := s.mergedRoomIDs(ctx, mergeID)
		if err != nil {
			return err
		}
		metas, err := s.loadMemberRoomMeta(ctx, cleanIDs)
		if err != nil {
			return err
		}

		highestRoomID := metas[0].roomID
		bestTS := metas[0].lastTS
		avatarURI := curAvatar
		networks := make([]string, 0, len(metas))
		for _, m := range metas {
			networks = append(networks, m.network)
			if m.lastTS > bestTS {
				bestTS = m.lastTS
				highestRoomID = m.roomID
			}
			if avatarURI == "" && m.avatarURI != "" {
				avatarURI = m.avatarURI
			}
		}

		chosenLast := lastRoomID
		if chosenLast == "" {
			if slices.Contains(cleanIDs, curLastRoom) {
				chosenLast = curLastRoom
			} else {
				chosenLast = highestRoomID
			}
		}
		chosenName := name
		if chosenName == "" {
			chosenName = curName
		}

		if _, err := s.db.Exec(
			ctx, `
			UPDATE merged_chats
			SET name = $2, avatar_uri = $3, last_room_id = $4
			WHERE merge_id = $1`,
			mergeID, chosenName, avatarURI, chosenLast,
		); err != nil {
			return err
		}
		if _, err := s.db.Exec(ctx, `DELETE FROM merged_chat_rooms WHERE merge_id = $1`, mergeID); err != nil {
			return err
		}
		for i, id := range cleanIDs {
			if _, err := s.db.Exec(ctx, `DELETE FROM merged_chat_rooms WHERE room_id = $1`, id); err != nil {
				return err
			}
			if _, err := s.db.Exec(
				ctx, `
				INSERT INTO merged_chat_rooms (merge_id, room_id, position)
				VALUES ($1, $2, $3)`,
				mergeID, id, i,
			); err != nil {
				return err
			}
		}

		notifyRooms = slices.Clone(oldRooms)
		for _, id := range cleanIDs {
			if !slices.Contains(notifyRooms, id) {
				notifyRooms = append(notifyRooms, id)
			}
		}
		mc = MergedChat{
			MergeID:    mergeID,
			Name:       chosenName,
			AvatarURI:  avatarURI,
			LastRoomID: chosenLast,
			RoomIDs:    cleanIDs,
			Networks:   networks,
			CreatedTS:  createdTS,
		}
		return nil
	})
	if err != nil {
		return MergedChat{}, err
	}
	for _, id := range notifyRooms {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return mc, nil
}

// DeleteMergedChat removes a merged chat while leaving all of its underlying rooms intact.
func (s *Store) DeleteMergedChat(ctx context.Context, mergeID string) error {
	var oldRooms []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		oldRooms, err = s.mergedRoomIDs(ctx, mergeID)
		if err != nil {
			return err
		}
		res, err := s.db.Exec(ctx, `DELETE FROM merged_chats WHERE merge_id = $1`, mergeID)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, id := range oldRooms {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return nil
}

func (s *Store) mergedRoomIDs(ctx context.Context, mergeID string) ([]string, error) {
	rows, err := s.db.Query(ctx, `
		SELECT room_id FROM merged_chat_rooms
		WHERE merge_id = $1
		ORDER BY position ASC, room_id ASC`, mergeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// ListMergedChats returns all merged chats with their ordered member room IDs and networks.
func (s *Store) ListMergedChats(ctx context.Context) ([]MergedChat, error) {
	rows, err := s.db.Query(ctx, `
		SELECT merge_id, name, avatar_uri, last_room_id, created_ts
		FROM merged_chats
		ORDER BY created_ts ASC, merge_id ASC`)
	if err != nil {
		return nil, err
	}
	var out []MergedChat
	for rows.Next() {
		var mc MergedChat
		if err := rows.Scan(&mc.MergeID, &mc.Name, &mc.AvatarURI, &mc.LastRoomID, &mc.CreatedTS); err != nil {
			rows.Close()
			return nil, err
		}
		mc.RoomIDs = []string{}
		mc.Networks = []string{}
		out = append(out, mc)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		mrows, err := s.db.Query(ctx, `
			SELECT mcr.room_id, r.network
			FROM merged_chat_rooms mcr
			JOIN rooms r ON r.room_id = mcr.room_id
			WHERE mcr.merge_id = $1
			ORDER BY mcr.position ASC, mcr.room_id ASC`, out[i].MergeID)
		if err != nil {
			return nil, err
		}
		for mrows.Next() {
			var rid, net string
			if err := mrows.Scan(&rid, &net); err != nil {
				mrows.Close()
				return nil, err
			}
			out[i].RoomIDs = append(out[i].RoomIDs, rid)
			out[i].Networks = append(out[i].Networks, net)
		}
		if err := mrows.Close(); err != nil {
			return nil, err
		}
		if err := mrows.Err(); err != nil {
			return nil, err
		}
	}
	if out == nil {
		out = []MergedChat{}
	}
	return out, nil
}

// SuggestMergedChats finds unmerged, non-hidden 1:1 DM rooms across different networks whose other participant shares
// a normalized identifier (reason: "identifier") or an exact case-insensitive display name that is neither empty nor
// just a phone number (reason: "display_name").
func (s *Store) SuggestMergedChats(ctx context.Context) ([]MergeSuggestion, error) {
	type roomCandidate struct {
		roomID      string
		network     string
		displayName string
		identifiers []string
	}

	rows, err := s.db.Query(ctx, `
		SELECT r.room_id, r.network, COALESCE(NULLIF(rp.local_name, ''), r.name)
		FROM rooms r
		LEFT JOIN room_prefs rp ON rp.room_id = r.room_id
		WHERE r.is_direct = 1
		  AND COALESCE(rp.hidden, 0) = 0
		  AND NOT EXISTS (SELECT 1 FROM merged_chat_rooms mcr WHERE mcr.room_id = r.room_id)
		ORDER BY r.created_at ASC, r.room_id ASC`)
	if err != nil {
		return nil, err
	}
	var cands []roomCandidate
	for rows.Next() {
		var c roomCandidate
		if err := rows.Scan(&c.roomID, &c.network, &c.displayName); err != nil {
			rows.Close()
			return nil, err
		}
		cands = append(cands, c)
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	for i := range cands {
		pRows, err := s.db.Query(ctx, `
			SELECT COALESCE(p.display_name, ''), COALESCE(p.identifiers_json, '[]'), m.content
			FROM members m
			LEFT JOIN profiles p ON p.user_id = m.user_id
			WHERE m.room_id = $1 AND m.user_id <> $2
			ORDER BY m.user_id ASC`, cands[i].roomID, string(ids.Me))
		if err != nil {
			return nil, err
		}
		var chosenName string
		var normIDs []string
		for pRows.Next() {
			var pName, idsJSON, memberContent string
			if err := pRows.Scan(&pName, &idsJSON, &memberContent); err != nil {
				pRows.Close()
				return nil, err
			}
			if chosenName == "" {
				if strings.TrimSpace(pName) != "" {
					chosenName = strings.TrimSpace(pName)
				} else {
					var mc struct {
						Displayname string `json:"displayname"`
					}
					if json.Unmarshal([]byte(memberContent), &mc) == nil && strings.TrimSpace(mc.Displayname) != "" {
						chosenName = strings.TrimSpace(mc.Displayname)
					}
				}
			}
			var rawIDs []string
			if idsJSON != "" && idsJSON != "[]" {
				_ = json.Unmarshal([]byte(idsJSON), &rawIDs)
			}
			for _, raw := range rawIDs {
				if norm := normalizeMergeIdentifier(raw); norm != "" && !slices.Contains(normIDs, norm) {
					normIDs = append(normIDs, norm)
				}
			}
		}
		if err := pRows.Close(); err != nil {
			return nil, err
		}
		if err := pRows.Err(); err != nil {
			return nil, err
		}
		if chosenName != "" {
			cands[i].displayName = chosenName
		} else {
			cands[i].displayName = strings.TrimSpace(cands[i].displayName)
		}
		cands[i].identifiers = normIDs
	}

	suggestedRoom := make(map[string]bool, len(cands))
	var out []MergeSuggestion

	// Pass 1: match by normalized identifier (phone E.164 / email).
	var idOrder []string
	byID := make(map[string][]roomCandidate)
	for _, c := range cands {
		for _, id := range c.identifiers {
			if _, exists := byID[id]; !exists {
				idOrder = append(idOrder, id)
			}
			byID[id] = append(byID[id], c)
		}
	}
	for _, id := range idOrder {
		group := byID[id]
		var picked []roomCandidate
		seenNet := make(map[string]bool)
		for _, c := range group {
			if suggestedRoom[c.roomID] || seenNet[c.network] {
				continue
			}
			seenNet[c.network] = true
			picked = append(picked, c)
		}
		if len(picked) < 2 {
			continue
		}
		roomIDs := make([]string, 0, len(picked))
		networks := make([]string, 0, len(picked))
		displayName := ""
		for _, c := range picked {
			suggestedRoom[c.roomID] = true
			roomIDs = append(roomIDs, c.roomID)
			networks = append(networks, c.network)
			if displayName == "" && c.displayName != "" {
				displayName = c.displayName
			}
		}
		out = append(out, MergeSuggestion{
			DisplayName: displayName,
			Reason:      "identifier",
			RoomIDs:     roomIDs,
			Networks:    networks,
		})
	}

	// Pass 2: match by exact case-insensitive display name (never empty and never just a phone number).
	var nameOrder []string
	byName := make(map[string][]roomCandidate)
	for _, c := range cands {
		if suggestedRoom[c.roomID] {
			continue
		}
		name := strings.TrimSpace(c.displayName)
		if name == "" || isPhoneNumberDisplayName(name) {
			continue
		}
		key := strings.ToLower(name)
		if _, exists := byName[key]; !exists {
			nameOrder = append(nameOrder, key)
		}
		byName[key] = append(byName[key], c)
	}
	for _, key := range nameOrder {
		group := byName[key]
		var picked []roomCandidate
		seenNet := make(map[string]bool)
		for _, c := range group {
			if suggestedRoom[c.roomID] || seenNet[c.network] {
				continue
			}
			seenNet[c.network] = true
			picked = append(picked, c)
		}
		if len(picked) < 2 {
			continue
		}
		roomIDs := make([]string, 0, len(picked))
		networks := make([]string, 0, len(picked))
		displayName := picked[0].displayName
		for _, c := range picked {
			suggestedRoom[c.roomID] = true
			roomIDs = append(roomIDs, c.roomID)
			networks = append(networks, c.network)
			if displayName == strings.ToLower(displayName) && c.displayName != strings.ToLower(c.displayName) {
				displayName = c.displayName
			}
		}
		out = append(out, MergeSuggestion{
			DisplayName: displayName,
			Reason:      "display_name",
			RoomIDs:     roomIDs,
			Networks:    networks,
		})
	}

	if out == nil {
		out = []MergeSuggestion{}
	}
	return out, nil
}

// normalizeMergeIdentifier normalizes phone ("tel:...") to full E.164 digits ("tel:+<digits>") and email ("mailto:...")
// to lowercase so identifiers from different bridges match reliably.
func normalizeMergeIdentifier(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" {
		return ""
	}
	lower := strings.ToLower(s)
	if strings.HasPrefix(lower, "tel:") || strings.HasPrefix(lower, "+") {
		var b strings.Builder
		for _, r := range s {
			if r >= '0' && r <= '9' {
				b.WriteRune(r)
			}
		}
		if b.Len() == 0 {
			return ""
		}
		return "tel:+" + b.String()
	}
	if after, ok := strings.CutPrefix(lower, "mailto:"); ok {
		after = strings.TrimSpace(after)
		if after == "" {
			return ""
		}
		return "mailto:" + after
	}
	if strings.Contains(lower, "@") && !strings.Contains(lower, ":") {
		return "mailto:" + lower
	}
	return lower
}

// isPhoneNumberDisplayName reports whether name consists solely of a phone number (digits and phone punctuation).
func isPhoneNumberDisplayName(name string) bool {
	s := strings.TrimSpace(name)
	if after, ok := strings.CutPrefix(strings.ToLower(s), "tel:"); ok {
		s = strings.TrimSpace(after)
	}
	s = strings.TrimPrefix(s, "+")
	if s == "" {
		return false
	}
	digits := 0
	for _, r := range s {
		switch {
		case r >= '0' && r <= '9':
			digits++
		case r == ' ' || r == '(' || r == ')' || r == '-' || r == '.' || r == '\u00a0' || r == '\u202f':
		default:
			return false
		}
	}
	return digits > 0
}

var mergedEventsBeforeSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id IN (SELECT room_id FROM merged_chat_rooms WHERE merge_id = $1)
  AND (ts, seq) < ($2, $3) AND ` + mainTimelineSQL + `
ORDER BY ts DESC, seq DESC LIMIT $4`

var mergedEventsAfterSQL = `SELECT ` + eventCols + ` FROM events
WHERE room_id IN (SELECT room_id FROM merged_chat_rooms WHERE merge_id = $1)
  AND (ts, seq) > ($2, $3) AND ` + mainTimelineSQL + `
ORDER BY ts ASC, seq ASC LIMIT $4`

const mergedEventAtRoomSQL = `SELECT ` + eventCols + ` FROM events
WHERE event_id = $1 AND room_id = $2
  AND room_id IN (SELECT room_id FROM merged_chat_rooms WHERE merge_id = $3)`

const mergedEventAtAnyRoomSQL = `SELECT ` + eventCols + ` FROM events
WHERE event_id = $1
  AND room_id IN (SELECT room_id FROM merged_chat_rooms WHERE merge_id = $2)`

// MergedEventsBefore returns up to limit main-timeline events across all rooms in mergeID older than before, ordered
// oldest-to-newest by (ts, seq), and whether more older events exist.
func (s *Store) MergedEventsBefore(ctx context.Context, mergeID string, before *Cursor, limit int) ([]Event, bool, error) {
	if limit <= 0 {
		limit = 50
	}
	ts, seq := int64(math.MaxInt64), int64(math.MaxInt64)
	if before != nil {
		ts, seq = before.TS.UnixMilli(), before.Seq
	}
	evs, err := s.queryEvents(ctx, mergedEventsBeforeSQL, mergeID, ts, seq, limit+1)
	if err != nil {
		return nil, false, err
	}
	hasMore := len(evs) > limit
	evs = evs[:min(len(evs), limit)]
	slices.Reverse(evs)
	if evs == nil {
		evs = []Event{}
	}
	return evs, hasMore, nil
}

// MergedEventsAfter returns up to limit main-timeline events across all rooms in mergeID newer than after, ordered
// oldest-to-newest by (ts, seq), and whether more newer events exist.
func (s *Store) MergedEventsAfter(ctx context.Context, mergeID string, after *Cursor, limit int) ([]Event, bool, error) {
	if limit <= 0 {
		limit = 50
	}
	ts, seq := int64(math.MinInt64), int64(math.MinInt64)
	if after != nil {
		ts, seq = after.TS.UnixMilli(), after.Seq
	}
	evs, err := s.queryEvents(ctx, mergedEventsAfterSQL, mergeID, ts, seq, limit+1)
	if err != nil {
		return nil, false, err
	}
	hasMore := len(evs) > limit
	evs = evs[:min(len(evs), limit)]
	if evs == nil {
		evs = []Event{}
	}
	return evs, hasMore, nil
}

// MergedEventsAround returns up to limit main-timeline events across all rooms in mergeID centred on eventID, ordered
// oldest-to-newest by (ts, seq), along with moreOlder and moreNewer flags.
func (s *Store) MergedEventsAround(ctx context.Context, mergeID, roomID, eventID string, limit int) ([]Event, bool, bool, error) {
	if limit <= 0 {
		limit = 50
	}
	var centre Event
	var err error
	if roomID != "" {
		centre, err = scanEvent(s.db.QueryRow(ctx, mergedEventAtRoomSQL, eventID, roomID, mergeID))
	} else {
		centre, err = scanEvent(s.db.QueryRow(ctx, mergedEventAtAnyRoomSQL, eventID, mergeID))
	}
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, false, ErrNotFound
	}
	if err != nil {
		return nil, false, false, err
	}
	at := centre.TS.UnixMilli()

	older, err := s.queryEvents(ctx, mergedEventsBeforeSQL, mergeID, at, centre.Seq, limit)
	if err != nil {
		return nil, false, false, err
	}
	newer, err := s.queryEvents(ctx, mergedEventsAfterSQL, mergeID, at, centre.Seq, limit)
	if err != nil {
		return nil, false, false, err
	}
	nOlder := min(len(older), (limit-1)/2)
	nNewer := min(len(newer), limit-1-nOlder)
	nOlder = min(len(older), limit-1-nNewer)
	moreOlder, moreNewer := len(older) > nOlder, len(newer) > nNewer
	older, newer = older[:nOlder], newer[:nNewer]

	slices.Reverse(older)
	evs := make([]Event, 0, len(older)+1+len(newer))
	evs = append(append(append(evs, older...), centre), newer...)
	return evs, moreOlder, moreNewer, nil
}
