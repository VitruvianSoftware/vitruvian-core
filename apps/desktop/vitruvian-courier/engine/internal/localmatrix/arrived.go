// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

// Read on arrival: a message of mine that reaches Vitruvian Courier already read by the other person.
//
// Some bridges only send a read receipt when they see a message's state change: mautrix-gmessages (v0.2609.0)
// queues one in MessageEvent.HandleExisting, when an update of a message it already has moves it to
// OUTGOING_DISPLAYED. A message it first meets already displayed (a backfill, or one the phone read before this Mac
// heard of it: the usual case when another Google Messages web client, such as Beeper, was the active session) is
// stored with that state in its part's metadata and no receipt ever goes out, so the chat says "Delivered" or "Sent"
// for a message the phone shows as read. The state is there, though: bridgev2 hands every part's metadata to
// SendMessage (MatrixSendExtra.MessageMeta) and keeps it in the bridge's message table. This file reads it in both
// places and turns it into the receipt the bridge didn't send: the other person of a one-to-one chat read it.
//
// The receipt carries no time (the state doesn't say when), so the app shows "Seen" without one.

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
)

// readStatusByNetwork is, for each network whose bridge keeps a message's state in its part metadata's "type",
// the state that means the other side has read it. Google Messages: gmproto.MessageStatusType_OUTGOING_DISPLAYED.
var readStatusByNetwork = map[string]int{"gmessages": 11}

// arrivedRead reports whether a message part's bridge metadata (any value: the bridge's own type, or its stored
// JSON) says the other side of the chat has read it, on a network that keeps that there (readStatusByNetwork).
func arrivedRead(network string, metadata any) bool {
	want, ok := readStatusByNetwork[network]
	if !ok || metadata == nil {
		return false
	}
	var raw []byte
	switch m := metadata.(type) {
	case string:
		raw = []byte(m)
	case []byte:
		raw = m
	default:
		var err error
		if raw, err = json.Marshal(m); err != nil {
			return false
		}
	}
	var meta struct {
		Type int `json:"type"`
	}
	return json.Unmarshal(raw, &meta) == nil && meta.Type == want
}

// isMine reports whether this intent is me: my own (double-puppet) intent, or my own network user's ghost.
func (in *Intent) isMine(ctx context.Context) bool {
	if in.mxid == ids.Me {
		return true
	}
	ghost, ok := ids.ParseGhostMXID(in.c.network, in.mxid)
	return ok && in.c.isMe(ctx, ghost)
}

// readOnArrival records the read a message of mine (eventID in roomID) arrived with, when roomID is a one-to-one
// chat: the other person read it. Best effort: a chat that isn't one-to-one, or whose other person isn't known,
// records nothing, and a failure is only logged (the message itself is stored).
func (c *Connector) readOnArrival(ctx context.Context, roomID, eventID string) {
	reader, err := c.directReader(ctx, roomID)
	if err == nil && reader != "" {
		err = c.store.SetReceipt(ctx, roomID, reader, eventID, time.Time{})
	}
	if err != nil {
		c.log.Warn().Err(err).Str("network", c.network).Msg("failed to store the read a message arrived with")
	}
}

// directReader is the other person of the one-to-one chat roomID: its only member who is a ghost of this network
// and not me. "" for a chat that isn't one-to-one, or that lists no such member or more than one.
func (c *Connector) directReader(ctx context.Context, roomID string) (string, error) {
	room, ok, err := c.store.GetRoom(ctx, roomID)
	if err != nil || !ok || !room.IsDirect {
		return "", err
	}
	members, err := c.store.Members(ctx, roomID)
	if err != nil {
		return "", err
	}
	reader := ""
	for userID, content := range members {
		ghost, isGhost := ids.ParseGhostMXID(c.network, id.UserID(userID))
		if !isGhost || c.isMe(ctx, ghost) || !joined(content) {
			continue
		}
		if reader != "" {
			return "", nil // more than one: not a one-to-one chat after all
		}
		reader = userID
	}
	return reader, nil
}

// joined reports whether member content is a joined member's (no membership counts as joined).
func joined(content json.RawMessage) bool {
	var m struct {
		Membership string `json:"membership"`
	}
	_ = json.Unmarshal(content, &m)
	return m.Membership == "" || m.Membership == "join"
}

// arrivedReadsSQL is, for every one-to-one chat of the bridge ($1), each part of a message of mine ($2) whose state
// the bridge kept: the chat's room, its other person, the part's event ID, its time and its metadata. The LIKE only
// narrows the read (arrivedRead decides), so it holds whatever the bridge's JSON spacing.
const arrivedReadsSQL = `SELECT COALESCE(p.mxid, ''), COALESCE(p.other_user_id, ''), m.mxid, m.timestamp, m.metadata
FROM message m
JOIN portal p ON p.bridge_id = m.bridge_id AND p.id = m.room_id AND p.receiver = m.room_receiver
WHERE m.bridge_id = $1 AND m.sender_mxid = $2 AND p.room_type = 'dm' AND m.metadata LIKE '%"type"%'`

// reconcileArrivedReads catches up on the reads earlier messages arrived with (arrivedRead) from the bridge's own
// message table, as the bridge starts: messages bridged before Vitruvian Courier read their state, and any whose
// state the bridge updated without a receipt. Per one-to-one chat it takes the newest such message of mine, and the
// store keeps a receipt only for a message it has and only moving forward (SetReceipt), so running it again changes
// nothing. A network that keeps no state there (readStatusByNetwork) is passed over. Best effort: a failure is
// logged and the bridge starts anyway.
func (c *Connector) reconcileArrivedReads(ctx context.Context) {
	if _, ok := readStatusByNetwork[c.network]; !ok || c.br == nil || c.br.DB == nil {
		return
	}
	if err := c.doReconcileArrivedReads(ctx); err != nil {
		c.log.Warn().Err(err).Str("network", c.network).Msg("failed to catch up on the reads messages arrived with")
	}
}

func (c *Connector) doReconcileArrivedReads(ctx context.Context) error {
	rows, err := c.br.DB.Query(ctx, arrivedReadsSQL, c.br.ID, ids.Me)
	if err != nil {
		return err
	}
	type newest struct {
		reader, eventID string
		ts              int64
	}
	latest := map[string]newest{} // by room
	for rows.Next() {
		var roomID, other, eventID, metadata string
		var ts int64
		if err := rows.Scan(&roomID, &other, &eventID, &ts, &metadata); err != nil {
			rows.Close()
			return err
		}
		if roomID == "" || other == "" || strings.HasPrefix(eventID, "$fake::") || !arrivedRead(c.network, metadata) {
			continue // no room yet, no other person, a part the bridge never sent (a fake MXID), or not read
		}
		if cur, ok := latest[roomID]; !ok || ts > cur.ts {
			latest[roomID] = newest{reader: string(ids.GhostMXID(c.network, networkid.UserID(other))), eventID: eventID, ts: ts}
		}
	}
	if err := rows.Close(); err != nil {
		return err
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for roomID, n := range latest {
		if err := c.store.SetReceipt(ctx, roomID, n.reader, n.eventID, time.Time{}); err != nil {
			return err
		}
	}
	return nil
}
