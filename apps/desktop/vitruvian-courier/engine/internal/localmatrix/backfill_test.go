// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// startBackfilling is startBridged with the backfill settings host.Start gives a network: a first backfill of
// initial messages and the backwards queue on, a page at a time, with no wait between pages. The fake network's
// history is set by the caller, before the chat is made.
func startBackfilling(t *testing.T, n *fakenet.Network, initial, pageSize int) (*Connector, *bridgev2.Bridge, *bridgev2.UserLogin) {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	c := New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!fake",
		Permissions:   bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		Backfill: bridgeconfig.BackfillConfig{
			Enabled:            true,
			MaxInitialMessages: initial,
			MaxCatchupMessages: 500,
			Queue:              bridgeconfig.BackfillQueueConfig{Enabled: true, BatchSize: pageSize, BatchDelay: 0, MaxBatches: -1},
		},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.Nop(), cfg, c, n,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	t.Cleanup(br.Stop)
	login, err := n.Login(ctx, br)
	require.NoError(t, err)
	return c, br, login
}

// A chat whose network has 40 older messages: its first backfill takes the newest 10, the queue pages back through
// the rest 7 at a time until the network has no more, and the timeline reads in order, once each, with the chat's
// unread count and preview exactly as they were after the first backfill.
func TestBackwardsBackfillQueuePagesBackThroughHistory(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	base := time.Now().Add(-100 * time.Hour).Truncate(time.Second)
	var history []fakenet.HistoryMessage
	for i := range 40 {
		history = append(history, fakenet.HistoryMessage{
			ID: fmt.Sprintf("h%02d", i), Sender: "alice", Body: fmt.Sprintf("history %02d", i), At: base.Add(time.Duration(i) * time.Hour / 2),
		})
	}
	n.SetHistory("chat", history)
	c, br, login := startBackfilling(t, n, 10, 7)

	n.Incoming(login, "chat", "alice", "live", "live message")
	var room id.RoomID
	require.Eventually(t, func() bool {
		rooms, _ := c.store.ListRooms(ctx)
		for _, r := range rooms {
			evs, _ := c.store.Events(ctx, r.ID, 100)
			for _, e := range evs {
				if strings.Contains(string(e.Content), "live message") {
					room = id.RoomID(r.ID)
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 20*time.Millisecond)
	require.Eventually(t, func() bool { return len(bodiesOldestFirst(t, c, room)) == 10+1 }, 5*time.Second, 20*time.Millisecond,
		"the first backfill is the newest 10 messages, then the one that arrived")
	unreadBefore, previewBefore := unreadOf(t, c, room), rowOf(t, c, room).Preview
	require.Equal(t, "live message", previewBefore)

	// The room's backfill task starts a minute after the room is made; bring it forward and wake the queue, as the
	// minute passing would.
	portalKey := networkid.PortalKey{ID: "chat", Receiver: login.ID}
	_, err := br.DB.Exec(ctx, `UPDATE backfill_task SET next_dispatch_min_ts = 0 WHERE portal_id = $1`, portalKey.ID)
	require.NoError(t, err)
	br.WakeupBackfillQueue()

	require.Eventually(t, func() bool { return len(bodiesOldestFirst(t, c, room)) == 40+1 }, 15*time.Second, 20*time.Millisecond,
		"the queue fetches older pages until the network has no more")
	got := bodiesOldestFirst(t, c, room)
	for i := range 40 {
		require.Contains(t, got[i], fmt.Sprintf("history %02d", i), "timeline position %d", i)
	}
	require.Contains(t, got[40], "live message", "the newest message stays newest")
	require.Equal(t, unreadBefore, unreadOf(t, c, room), "history is not unread")
	require.Equal(t, previewBefore, rowOf(t, c, room).Preview, "nor does it change the preview")

	var done bool
	require.Eventually(t, func() bool {
		task, err := br.DB.BackfillTask.GetNextForPortal(ctx, portalKey, true)
		done = err == nil && task != nil && task.IsDone
		return done
	}, 5*time.Second, 20*time.Millisecond, "the task is finished once the network has no more")

	for _, f := range n.Fetches() {
		if !f.Forward {
			require.LessOrEqual(t, f.Count, 7, "a page is the configured size")
		}
	}
	// A restart of the queue does not fetch again: a finished task is not dispatched.
	fetched := len(n.Fetches())
	br.WakeupBackfillQueue()
	time.Sleep(200 * time.Millisecond)
	require.Equal(t, fetched, len(n.Fetches()))
}
