// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package store is courier.db: the single source of truth that stands in for a Matrix server.
package store

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

//go:embed schema.sql
var schema string

type Room struct {
	ID, Network, Name, Topic, AvatarURI string
	IsDirect                            bool
	CreatedAt                           time.Time
}

type Event struct {
	RoomID, EventID, Sender, Type string
	StateKey                      *string
	Content                       json.RawMessage
	TS                            time.Time
	Status, StatusReason          string
}

type Change struct{ Kind, RoomID, EventID string }

type Store struct {
	db   *dbutil.Database
	seq  int64
	mu   sync.Mutex // guards seq and subs
	subs map[chan Change]struct{}
}

func Open(path string) (*Store, error) {
	db, err := sqlite.Open(path)
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec(context.Background(), schema); err != nil {
		db.Close()
		return nil, err
	}
	s := &Store{db: db, subs: map[chan Change]struct{}{}}
	if err = db.QueryRow(context.Background(), "SELECT COALESCE(MAX(seq),0) FROM events").Scan(&s.seq); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) publish(c Change) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for ch := range s.subs {
		select {
		case ch <- c:
		default: // slow subscriber: drop; it re-reads state on its next query
		}
	}
}

// Subscribe returns a buffered change feed and a cancel function.
func (s *Store) Subscribe() (<-chan Change, func()) {
	ch := make(chan Change, 256)
	s.mu.Lock()
	s.subs[ch] = struct{}{}
	s.mu.Unlock()
	return ch, func() {
		s.mu.Lock()
		delete(s.subs, ch)
		s.mu.Unlock()
	}
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

func (s *Store) UpsertRoom(ctx context.Context, r Room) error {
	if r.CreatedAt.IsZero() {
		r.CreatedAt = time.Now()
	}
	_, err := s.db.Exec(ctx, `INSERT INTO rooms (room_id, network, name, topic, avatar_uri, is_direct, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT(room_id) DO UPDATE SET name=excluded.name, topic=excluded.topic, avatar_uri=excluded.avatar_uri, is_direct=excluded.is_direct`,
		r.ID, r.Network, r.Name, r.Topic, r.AvatarURI, b2i(r.IsDirect), r.CreatedAt.UnixMilli())
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: r.ID})
	}
	return err
}

func scanRoom(row dbutil.Scannable) (Room, error) {
	var r Room
	var direct int
	var created int64
	err := row.Scan(&r.ID, &r.Network, &r.Name, &r.Topic, &r.AvatarURI, &direct, &created)
	r.IsDirect, r.CreatedAt = direct == 1, time.UnixMilli(created)
	return r, err
}

const roomCols = "room_id, network, name, topic, avatar_uri, is_direct, created_at"

func (s *Store) GetRoom(ctx context.Context, roomID string) (Room, bool, error) {
	r, err := scanRoom(s.db.QueryRow(ctx, "SELECT "+roomCols+" FROM rooms WHERE room_id=$1", roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return Room{}, false, nil
	}
	return r, err == nil, err
}

func (s *Store) ListRooms(ctx context.Context) ([]Room, error) {
	rows, err := s.db.Query(ctx, "SELECT "+roomCols+" FROM rooms ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Room
	for rows.Next() {
		r, err := scanRoom(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) DeleteRoom(ctx context.Context, roomID string) error {
	_, err := s.db.Exec(ctx, "DELETE FROM rooms WHERE room_id=$1", roomID)
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}

func (s *Store) SetMember(ctx context.Context, roomID, userID string, content json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO members (room_id, user_id, content) VALUES ($1,$2,$3)
		ON CONFLICT(room_id, user_id) DO UPDATE SET content=excluded.content`, roomID, userID, string(content))
	if err == nil {
		s.publish(Change{Kind: "member", RoomID: roomID})
	}
	return err
}

func (s *Store) Members(ctx context.Context, roomID string) (map[string]json.RawMessage, error) {
	rows, err := s.db.Query(ctx, "SELECT user_id, content FROM members WHERE room_id=$1", roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]json.RawMessage{}
	for rows.Next() {
		var u, c string
		if err := rows.Scan(&u, &c); err != nil {
			return nil, err
		}
		out[u] = json.RawMessage(c)
	}
	return out, rows.Err()
}

func (s *Store) DeleteMember(ctx context.Context, roomID, userID string) error {
	_, err := s.db.Exec(ctx, "DELETE FROM members WHERE room_id=$1 AND user_id=$2", roomID, userID)
	if err == nil {
		s.publish(Change{Kind: "member", RoomID: roomID})
	}
	return err
}

// SetProfile records a user's global display name and avatar. A nil argument leaves that field unchanged;
// a pointer to an empty string clears it.
func (s *Store) SetProfile(ctx context.Context, userID string, displayName, avatarURI *string) error {
	_, err := s.db.Exec(ctx, `INSERT INTO profiles (user_id, display_name, avatar_uri) VALUES ($1, COALESCE($2,''), COALESCE($3,''))
		ON CONFLICT(user_id) DO UPDATE SET display_name=COALESCE($2, display_name), avatar_uri=COALESCE($3, avatar_uri)`,
		userID, displayName, avatarURI)
	if err == nil {
		s.publish(Change{Kind: "profile"})
	}
	return err
}

func (s *Store) GetProfile(ctx context.Context, userID string) (displayName, avatarURI string, ok bool, err error) {
	err = s.db.QueryRow(ctx, "SELECT display_name, avatar_uri FROM profiles WHERE user_id=$1", userID).Scan(&displayName, &avatarURI)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", false, nil
	}
	return displayName, avatarURI, err == nil, err
}

func (s *Store) SetState(ctx context.Context, roomID, evType, stateKey string, content json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO state (room_id, type, state_key, content) VALUES ($1,$2,$3,$4)
		ON CONFLICT(room_id, type, state_key) DO UPDATE SET content=excluded.content`, roomID, evType, stateKey, string(content))
	return err
}

func (s *Store) GetState(ctx context.Context, roomID, evType, stateKey string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT content FROM state WHERE room_id=$1 AND type=$2 AND state_key=$3", roomID, evType, stateKey).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}

func (s *Store) InsertEvent(ctx context.Context, e Event) (bool, error) {
	s.mu.Lock()
	s.seq++
	seq := s.seq
	s.mu.Unlock()
	res, err := s.db.Exec(ctx, `INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(event_id) DO NOTHING`,
		e.EventID, e.RoomID, e.Sender, e.Type, e.StateKey, string(e.Content), e.TS.UnixMilli(), e.Status, e.StatusReason, seq)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	if n == 1 {
		s.publish(Change{Kind: "event", RoomID: e.RoomID, EventID: e.EventID})
	}
	return n == 1, nil
}

const eventCols = "room_id, event_id, sender, type, state_key, content, ts, status, status_reason"

func scanEvent(row dbutil.Scannable) (Event, error) {
	var e Event
	var c string
	var ts int64
	err := row.Scan(&e.RoomID, &e.EventID, &e.Sender, &e.Type, &e.StateKey, &c, &ts, &e.Status, &e.StatusReason)
	e.Content, e.TS = json.RawMessage(c), time.UnixMilli(ts)
	return e, err
}

func (s *Store) GetEvent(ctx context.Context, eventID string) (Event, bool, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1", eventID))
	if errors.Is(err, sql.ErrNoRows) {
		return Event{}, false, nil
	}
	return e, err == nil, err
}

func (s *Store) Events(ctx context.Context, roomID string, limit int) ([]Event, error) {
	rows, err := s.db.Query(ctx, "SELECT "+eventCols+" FROM events WHERE room_id=$1 ORDER BY ts DESC, seq DESC LIMIT $2", roomID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) SetStatus(ctx context.Context, eventID, status, reason string) error {
	var roomID string
	err := s.db.QueryRow(ctx, "UPDATE events SET status=$2, status_reason=$3 WHERE event_id=$1 RETURNING room_id", eventID, status, reason).Scan(&roomID)
	if err == nil {
		s.publish(Change{Kind: "status", RoomID: roomID, EventID: eventID})
	}
	return err
}

func (s *Store) SetRead(ctx context.Context, roomID, eventID string, ts time.Time) error {
	_, err := s.db.Exec(ctx, `INSERT INTO reads (room_id, event_id, ts) VALUES ($1,$2,$3)
		ON CONFLICT(room_id) DO UPDATE SET event_id=excluded.event_id, ts=excluded.ts`, roomID, eventID, ts.UnixMilli())
	if err == nil {
		s.publish(Change{Kind: "read", RoomID: roomID, EventID: eventID})
	}
	return err
}

func (s *Store) SetBridgeState(ctx context.Context, network string, state json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT INTO bridge_state (network, state) VALUES ($1,$2)
		ON CONFLICT(network) DO UPDATE SET state=excluded.state`, network, string(state))
	if err == nil {
		s.publish(Change{Kind: "bridge", RoomID: network})
	}
	return err
}

func (s *Store) BridgeState(ctx context.Context, network string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT state FROM bridge_state WHERE network=$1", network).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}
