// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"errors"
)

// ChannelRoom is a chat room the store holds, found by the bridge chat its bridge info names.
type ChannelRoom struct {
	RoomID string
	Name   string
	// LastTS is the time of the room's newest message, Unix milliseconds.
	LastTS int64
	// Tombstoned says the room carries a tombstone (a bridge merged it into another room).
	Tombstoned bool
}

// RoomsForChannel lists the rooms of network whose bridge info (m.bridge) says they are the chat channelID of the
// login receiver, newest message first. A bridge puts that in every room it makes (channel.id and
// channel."fi.mau.receiver"), so it names the portal a room was made for even after the portal's own row is gone.
func (s *Store) RoomsForChannel(ctx context.Context, network, channelID, receiver string) ([]ChannelRoom, error) {
	rows, err := s.db.Query(ctx, `SELECT r.room_id, r.name, r.last_ts,
		EXISTS(SELECT 1 FROM state t WHERE t.room_id = r.room_id AND t.type = 'm.room.tombstone')
		FROM rooms r JOIN state b ON b.room_id = r.room_id AND b.type = 'm.bridge'
		WHERE r.network = $1 AND json_valid(b.content)
		  AND json_extract(b.content, '$.channel.id') = $2
		  AND COALESCE(json_extract(b.content, '$.channel."fi.mau.receiver"'), '') = $3
		ORDER BY r.last_ts DESC, r.created_at DESC`, network, channelID, receiver)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ChannelRoom
	for rows.Next() {
		var r ChannelRoom
		if err := rows.Scan(&r.RoomID, &r.Name, &r.LastTS, &r.Tombstoned); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
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
