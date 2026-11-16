// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

// ChannelRoom is a chat room the store holds, found by the bridge chat its bridge info names.
type ChannelRoom struct {
	RoomID string
	// ChannelID is the bridge chat (portal) the room's bridge info says it is for.
	ChannelID string
	Name      string
	// LastTS is the time of the room's newest message, Unix milliseconds (0: none).
	LastTS int64
	// Tombstoned says the room carries a tombstone (a bridge merged it into another room).
	Tombstoned bool
	// Replacement is the room the tombstone points to ("" when there is none, or no tombstone).
	Replacement string
}

const channelRoomsSelect = `SELECT r.room_id, COALESCE(json_extract(b.content, '$.channel.id'), ''), r.name, r.last_ts,
		EXISTS(SELECT 1 FROM state t WHERE t.room_id = r.room_id AND t.type = 'm.room.tombstone'),
		COALESCE((SELECT json_extract(t.content, '$.replacement_room') FROM state t
			WHERE t.room_id = r.room_id AND t.type = 'm.room.tombstone' AND json_valid(t.content)), '')
		FROM rooms r JOIN state b ON b.room_id = r.room_id AND b.type = 'm.bridge'
		WHERE r.network = $1 AND json_valid(b.content)`

// RoomsForChannel lists the rooms of network whose bridge info (m.bridge) says they are the chat channelID of the
// login receiver, newest message first. A bridge puts that in every room it makes (channel.id and
// channel."fi.mau.receiver"), so it names the portal a room was made for even after the portal's own row is gone.
func (s *Store) RoomsForChannel(ctx context.Context, network, channelID, receiver string) ([]ChannelRoom, error) {
	return s.channelRooms(ctx, channelRoomsSelect+`
		AND json_extract(b.content, '$.channel.id') = $2
		AND COALESCE(json_extract(b.content, '$.channel."fi.mau.receiver"'), '') = $3
		ORDER BY r.last_ts DESC, r.created_at DESC`, network, channelID, receiver)
}

// ChannelRooms lists every room of network that has bridge info, of any login when receiver is "" and of that login
// otherwise, newest message first.
func (s *Store) ChannelRooms(ctx context.Context, network, receiver string) ([]ChannelRoom, error) {
	return s.channelRooms(ctx, channelRoomsSelect+`
		AND ($2 = '' OR COALESCE(json_extract(b.content, '$.channel."fi.mau.receiver"'), '') = $2)
		ORDER BY r.last_ts DESC, r.created_at DESC`, network, receiver)
}

func (s *Store) channelRooms(ctx context.Context, query string, args ...any) ([]ChannelRoom, error) {
	rows, err := s.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ChannelRoom
	for rows.Next() {
		var r ChannelRoom
		if err := rows.Scan(&r.RoomID, &r.ChannelID, &r.Name, &r.LastTS, &r.Tombstoned, &r.Replacement); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// RoomLastTS is the time of a room's newest message, Unix milliseconds: 0 when it has none or isn't there.
func (s *Store) RoomLastTS(ctx context.Context, roomID string) (int64, error) {
	var ts int64
	err := s.db.QueryRow(ctx, "SELECT last_ts FROM rooms WHERE room_id = $1", roomID).Scan(&ts)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return ts, err
}

// TombstoneReplacement reports whether a room carries a tombstone, and the room it points to ("" if none).
func (s *Store) TombstoneReplacement(ctx context.Context, roomID string) (tombstoned bool, replacement string, err error) {
	var raw string
	err = s.db.QueryRow(ctx, "SELECT content FROM state WHERE room_id = $1 AND type = 'm.room.tombstone'", roomID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}
	var c struct {
		Replacement string `json:"replacement_room"`
	}
	_ = json.Unmarshal([]byte(raw), &c)
	return true, c.Replacement, nil
}

// ClearTombstone takes the tombstone off a room (it is the chat's room again) and reports whether it had one. The
// app reads the chat again.
func (s *Store) ClearTombstone(ctx context.Context, roomID string) (bool, error) {
	res, err := s.db.Exec(ctx, "DELETE FROM state WHERE room_id = $1 AND type = 'm.room.tombstone'", roomID)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	if n > 0 {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return n > 0, nil
}

// RoomIsTombstoned reports whether a room carries a tombstone.
func (s *Store) RoomIsTombstoned(ctx context.Context, roomID string) (bool, error) {
	var one int
	err := s.db.QueryRow(ctx, "SELECT 1 FROM state WHERE room_id = $1 AND type = 'm.room.tombstone'", roomID).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}
