// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// The network's read position is the one the network reported (SetRead): a read made on this Mac is no part of it.
func TestNetworkReadMarkersAreTheNetworksAndNeverTheLocalOnes(t *testing.T) {
	s, ctx := open(t), context.Background()
	const a, b, c = "!a:courier.local", "!b:courier.local", "!c:courier.local"
	for _, id := range []string{a, b, c} {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: id, Network: "whatsapp"}))
	}
	_, err := s.InsertEvents(ctx, []Event{
		historyEvent(a, "$a1", 10, "a1"), historyEvent(a, "$a2", 20, "a2"),
		historyEvent(b, "$b1", 10, "b1"), historyEvent(b, "$b2", 20, "b2"),
	})
	require.NoError(t, err)

	require.NoError(t, s.SetRead(ctx, a, "$a1", time.Unix(10, 0)))          // the network says I read a1 elsewhere
	require.NoError(t, s.MarkReadLocal(ctx, b, "$b2", time.Unix(20, 0)))    // I read b here
	require.NoError(t, s.SetRead(ctx, c, "$never-stored", time.Unix(5, 0))) // a marker whose message isn't stored

	got, err := s.NetworkReadMarkers(ctx, []string{a, b, c, "!nowhere:courier.local"})
	require.NoError(t, err)
	e, ok, err := s.GetEvent(ctx, "$a1")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, Cursor{TS: time.Unix(10, 0), Seq: e.Seq}, got[a], "what the network reported, at its message's (ts, seq)")
	require.NotContains(t, got, b, "a read made on this Mac is not the network's")
	require.Equal(t, int64(1<<63-1), got[c].Seq, "a message that isn't stored compares on ts alone")
	require.NotContains(t, got, "!nowhere:courier.local")

	empty, err := s.NetworkReadMarkers(ctx, nil)
	require.NoError(t, err)
	require.Empty(t, empty)
}
