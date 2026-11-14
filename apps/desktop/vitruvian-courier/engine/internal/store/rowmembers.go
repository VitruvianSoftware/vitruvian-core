// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"cmp"
	"context"
	"encoding/json"
	"slices"
	"strconv"
	"strings"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
)

// MaxRowMembers is the most members MemberPreviews gives a chat: enough for a group's stacked picture.
const MaxRowMembers = 3

// rowMemberScanLimit is how many of a chat's member rows MemberPreviews reads besides its recent speakers, so a
// channel of thousands costs no more than a small group.
const rowMemberScanLimit = 64

// rowSpeakerWindow is how many of a chat's newest messages MemberPreviews reads for who spoke recently.
const rowSpeakerWindow = 30

// RowMember is someone in a chat, for the inbox row's picture of a group that has none of its own.
type RowMember struct {
	UserID    string
	Name      string // their name in the chat, else their profile's, else their ID's localpart
	AvatarURI string // their picture (in the chat, else their profile's), or ""
}

// memberPreviewsSQL reads, for each chat in $1 (a JSON array of room IDs), its candidates for the row's picture: the
// members who sent one of its rowSpeakerWindow newest messages (with when they last did), and its first
// rowMemberScanLimit member rows. Every part is an index range: events_room_ts from the newest message back, the
// members primary key, and profiles by primary key. One statement for the whole page, never one per chat.
var memberPreviewsSQL = `WITH rq(room_id) AS (SELECT DISTINCT value FROM json_each($1)),
spk AS (
  SELECT x.room_id, x.sender, MAX(x.ts) AS ts FROM rq JOIN events x ON x.event_id IN (
    SELECT y.event_id FROM events y
    WHERE y.room_id = rq.room_id AND y.type IN (` + unreadTypes + `) AND y.redacted = 0
    ORDER BY y.ts DESC, y.seq DESC LIMIT ` + strconv.Itoa(rowSpeakerWindow) + `)
  GROUP BY x.room_id, x.sender
),
cand AS (
  SELECT m.room_id, m.user_id, m.content FROM rq JOIN members m ON m.rowid IN (
    SELECT mm.rowid FROM members mm WHERE mm.room_id = rq.room_id LIMIT ` + strconv.Itoa(rowMemberScanLimit) + `)
  UNION
  SELECT m.room_id, m.user_id, m.content FROM spk JOIN members m ON m.room_id = spk.room_id AND m.user_id = spk.sender
)
SELECT c.room_id, r.network, c.user_id, c.content, COALESCE(p.display_name, ''), COALESCE(p.avatar_uri, ''),
  COALESCE(p.is_bot, 0), COALESCE(spk.ts, 0)
FROM cand c
JOIN rooms r ON r.room_id = c.room_id
LEFT JOIN profiles p ON p.user_id = c.user_id
LEFT JOIN spk ON spk.room_id = c.room_id AND spk.sender = c.user_id`

// MemberPreviews is, for each chat in roomIDs, up to MaxRowMembers of its joined members other than me: who spoke
// most recently first, then those with a picture, then by name. The network's bridge bot, a bot profile and my own
// ghosts on the network (the login's own user) are left out. It is one query for all of them (memberPreviewsSQL) and
// one of my logins; a chat with nobody else has no entry.
func (s *Store) MemberPreviews(ctx context.Context, roomIDs []string) (map[string][]RowMember, error) {
	out := map[string][]RowMember{}
	if len(roomIDs) == 0 {
		return out, nil
	}
	list, err := json.Marshal(roomIDs)
	if err != nil {
		return nil, err
	}
	selfGhosts, err := s.selfGhostIDs(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, memberPreviewsSQL, string(list))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	type candidate struct {
		RowMember
		spoke int64
	}
	byRoom := map[string][]candidate{}
	for rows.Next() {
		var roomID, network, userID, content, profName, profAvatar string
		var isBot int
		var spoke int64
		if err := rows.Scan(&roomID, &network, &userID, &content, &profName, &profAvatar, &isBot, &spoke); err != nil {
			return nil, err
		}
		var mc struct {
			Membership  string `json:"membership"`
			DisplayName string `json:"displayname"`
			AvatarURL   string `json:"avatar_url"`
		}
		_ = json.Unmarshal([]byte(content), &mc)
		switch {
		case cmp.Or(mc.Membership, "join") != "join",
			userID == string(ids.Me),
			userID == "@"+network+"bot:"+ids.ServerName,
			isBot != 0,
			selfGhosts[userID]:
			continue
		}
		byRoom[roomID] = append(byRoom[roomID], candidate{
			RowMember: RowMember{
				UserID:    userID,
				Name:      cmp.Or(mc.DisplayName, profName, userLocalpart(userID)),
				AvatarURI: cmp.Or(mc.AvatarURL, profAvatar),
			},
			spoke: spoke,
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for roomID, cands := range byRoom {
		slices.SortFunc(cands, func(a, b candidate) int {
			if c := cmp.Compare(b.spoke, a.spoke); c != 0 {
				return c
			}
			if c := boolCompare(b.AvatarURI != "", a.AvatarURI != ""); c != 0 {
				return c
			}
			if c := cmp.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name)); c != 0 {
				return c
			}
			return cmp.Compare(a.UserID, b.UserID)
		})
		n := min(len(cands), MaxRowMembers)
		members := make([]RowMember, 0, n)
		for _, c := range cands[:n] {
			members = append(members, c.RowMember)
		}
		out[roomID] = members
	}
	return out, nil
}

// boolCompare orders false before true.
func boolCompare(a, b bool) int {
	switch {
	case a == b:
		return 0
	case !a:
		return -1
	default:
		return 1
	}
}

// selfGhostIDs is the ghost IDs my own logins have on their networks (from each login's remote ID, as RoomMembers
// works them out: resolveSelfProfile), so a picture of a group never shows me.
func (s *Store) selfGhostIDs(ctx context.Context) (map[string]bool, error) {
	rows, err := s.db.Query(ctx, `SELECT network, login_id, state FROM login_state WHERE login_id <> ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var network, loginID, state string
		if err := rows.Scan(&network, &loginID, &state); err != nil {
			return nil, err
		}
		var st struct {
			RemoteID string `json:"remote_id"`
		}
		_ = json.Unmarshal([]byte(state), &st)
		remoteID := cmp.Or(st.RemoteID, loginID)
		out[string(id.NewUserID(network+"_"+id.EncodeUserLocalpart(remoteID), ids.ServerName))] = true
		out[string(id.NewUserID(network+"_"+id.EncodeUserLocalpart(strings.ToLower(remoteID)), ids.ServerName))] = true
	}
	return out, rows.Err()
}
