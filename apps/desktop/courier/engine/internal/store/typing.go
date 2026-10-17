// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"sort"
	"time"
)

// typingEntry is one person typing in one chat, until a time. Typing lives only in memory: it means nothing
// after a restart.
type typingEntry struct {
	until time.Time
	stop  func() bool // stops the expiry timer
}

// SetTyping records that userID is typing in roomID until the given time. A zero or past until means they
// stopped. Each (room, user) has one expiry timer, replaced when the typing is renewed. A "typing" change is
// published when the list of who is typing in roomID changes: someone starts, stops, or runs out. A renewal
// says nothing new.
func (s *Store) SetTyping(roomID, userID string, until time.Time) {
	now := s.now()
	s.typingMu.Lock()
	room := s.typing[roomID]
	old := room[userID]
	if old != nil {
		old.stop()
	}
	changed := false
	if until.IsZero() || !until.After(now) {
		if old != nil {
			delete(room, userID)
			if len(room) == 0 {
				delete(s.typing, roomID)
			}
			changed = true
		}
	} else {
		if room == nil {
			room = map[string]*typingEntry{}
			s.typing[roomID] = room
		}
		e := &typingEntry{until: until}
		e.stop = s.afterFunc(until.Sub(now), func() { s.typingExpired(roomID, userID, e) })
		room[userID] = e
		changed = old == nil || !old.until.After(now) // a renewal of typing that had already run out is a start
	}
	s.typingMu.Unlock()
	if changed {
		s.publish(Change{Kind: "typing", RoomID: roomID})
	}
}

// typingExpired is e's timer firing. It does nothing if e has since been renewed or stopped.
func (s *Store) typingExpired(roomID, userID string, e *typingEntry) {
	s.typingMu.Lock()
	room := s.typing[roomID]
	if room[userID] != e {
		s.typingMu.Unlock()
		return
	}
	delete(room, userID)
	if len(room) == 0 {
		delete(s.typing, roomID)
	}
	s.typingMu.Unlock()
	s.publish(Change{Kind: "typing", RoomID: roomID})
}

// TypingIn lists the user IDs still typing in roomID, sorted. Someone whose time has passed is not listed, even
// if their timer hasn't run yet.
func (s *Store) TypingIn(roomID string) []string {
	now := s.now()
	s.typingMu.Lock()
	defer s.typingMu.Unlock()
	var out []string
	for u, e := range s.typing[roomID] {
		if e.until.After(now) {
			out = append(out, u)
		}
	}
	sort.Strings(out)
	return out
}
