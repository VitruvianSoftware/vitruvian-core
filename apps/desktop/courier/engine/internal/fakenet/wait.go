// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package fakenet

import (
	"bytes"
	"context"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// RoomWith waits until s holds a chat with a message whose content has text in it, and returns that chat: how a
// test finds the chat a message delivered with Incoming (or IncomingShared) made. It looks again on each of s's
// changes rather than on a timer; ctx ending first is its error.
func RoomWith(ctx context.Context, s *store.Store, text string) (store.Room, error) {
	feed := s.Feed() // before the first look, so a change between the look and the wait isn't missed
	defer feed.Close()
	for {
		r, ok, err := roomWith(ctx, s, []byte(text))
		if err != nil || ok {
			return r, err
		}
		select {
		case <-feed.C:
		case <-ctx.Done():
			return store.Room{}, ctx.Err()
		}
	}
}

func roomWith(ctx context.Context, s *store.Store, text []byte) (store.Room, bool, error) {
	rooms, err := s.ListRooms(ctx)
	if err != nil {
		return store.Room{}, false, err
	}
	for _, r := range rooms {
		evs, err := s.Events(ctx, r.ID, 10)
		if err != nil {
			return store.Room{}, false, err
		}
		for _, e := range evs {
			if bytes.Contains(e.Content, text) {
				return r, true, nil
			}
		}
	}
	return store.Room{}, false, nil
}
