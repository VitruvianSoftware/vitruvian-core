// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const joinNote = "Vertex AI Pipelines (bot) has joined the channel"

func mkNetworkRoom(t *testing.T, s *Store, id, network string) {
	t.Helper()
	require.NoError(t, s.UpsertRoom(context.Background(), Room{ID: id, Network: network, Name: id, CreatedAt: time.Unix(1, 0)}))
}

// A note stored as text before the engine stored them as membership events is served as the membership event,
// with its own event ID; the same words in another network's chat stay a message.
func TestStoredSlackNoteIsServedAsMembership(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkNetworkRoom(t, s, "!s", "slack")
	mkNetworkRoom(t, s, "!w", "whatsapp")
	for _, room := range []string{"!s", "!w"} {
		mkMsg(t, s, room, "$hi"+room, ghost, "m.room.message", text("hello"), time.Unix(10, 0))
		mkMsg(t, s, room, "$join"+room, ghost, "m.room.message", text(joinNote), time.Unix(20, 0))
	}
	check := func(evs []Event, room, wantType string) {
		t.Helper()
		byID := map[string]Event{}
		for _, e := range evs {
			byID[e.EventID] = e
		}
		require.Equal(t, wantType, byID["$join"+room].Type)
		require.Equal(t, "m.room.message", byID["$hi"+room].Type)
	}
	page, _, err := s.EventsBefore(ctx, "!s", nil, 10)
	require.NoError(t, err)
	check(page, "!s", "m.room.member")
	for _, e := range page {
		if e.EventID == "$join!s" {
			require.Contains(t, string(e.Content), `"membership":"join"`)
			require.NotNil(t, e.StateKey)
		}
	}
	around, _, _, err := s.EventsAround(ctx, "!s", "$join!s", 10)
	require.NoError(t, err)
	check(around, "!s", "m.room.member")
	page, _, err = s.EventsBefore(ctx, "!w", nil, 10)
	require.NoError(t, err)
	check(page, "!w", "m.room.message")
}

// The inbox does not preview or count a note that is still stored as text.
func TestStoredSlackNoteIsNoPreviewAndNotUnread(t *testing.T) {
	s := open(t)
	mkNetworkRoom(t, s, "!s", "slack")
	mkNetworkRoom(t, s, "!w", "whatsapp")
	for _, room := range []string{"!s", "!w"} {
		mkMsg(t, s, room, "$hi"+room, ghost, "m.room.message", text("hello"), time.Unix(10, 0))
		mkMsg(t, s, room, "$join"+room, ghost, "m.room.message", text(joinNote), time.Unix(20, 0))
	}
	rows := inboxByID(t, s)
	require.Equal(t, "", rows["!s"].Preview)
	require.Equal(t, 1, rows["!s"].Unread, "only the real message is unread")
	require.Equal(t, joinNote, rows["!w"].Preview, "another network's chat is not Slack's wording")
	require.Equal(t, 2, rows["!w"].Unread)
}
