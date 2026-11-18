// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// historyBatch is a bridgev2 backfill batch of messages from sender at the given seconds, oldest first, with the
// event IDs the bridge would have made.
func historyBatch(c *Connector, room id.RoomID, sender id.UserID, prefix string, secs ...int64) ([]*event.Event, []*bridgev2.MatrixSendExtra) {
	var evs []*event.Event
	var extras []*bridgev2.MatrixSendExtra
	for _, s := range secs {
		evs = append(evs, &event.Event{
			ID: id.EventID(fmt.Sprintf("$%s%d", prefix, s)), RoomID: room, Sender: sender, Type: event.EventMessage,
			Timestamp: time.Unix(s, 0).UnixMilli(),
			Content:   *textContent(fmt.Sprintf("%s message %d", prefix, s)),
		})
		extras = append(extras, &bridgev2.MatrixSendExtra{})
	}
	return evs, extras
}

// bodiesOldestFirst is the bodies of the chat's messages in timeline order.
func bodiesOldestFirst(t *testing.T, c *Connector, room id.RoomID) []string {
	t.Helper()
	evs, err := c.store.Events(context.Background(), string(room), 1000)
	require.NoError(t, err)
	var out []string
	for i := len(evs) - 1; i >= 0; i-- {
		if evs[i].Type == "m.room.message" {
			out = append(out, string(evs[i].Content))
		}
	}
	return out
}

// chatWithMessages is a chat with a friend who wrote at each of secs, through the ordinary live path.
func chatWithMessages(t *testing.T, c *Connector, secs ...int64) (id.RoomID, *Intent) {
	t.Helper()
	ctx := context.Background()
	friend := c.GhostIntent("friend").(*Intent)
	room, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	for _, s := range secs {
		_, err = friend.SendMessage(ctx, room, event.EventMessage, textContent(fmt.Sprintf("live message %d", s)),
			&bridgev2.MatrixSendExtra{Timestamp: time.Unix(s, 0)})
		require.NoError(t, err)
	}
	return room, friend
}

func TestConnectorReportsBatchSending(t *testing.T) {
	require.True(t, newTestConnector(t).GetCapabilities().BatchSending,
		"bridgev2 runs its backwards backfill queue only when this is true")
}

// The point of BatchSend: older history lands before what the chat already has, by time, and the chat's preview
// and its unread count don't move.
func TestBatchSendPlacesHistoryBeforeTheFirstMessage(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	room, friend := chatWithMessages(t, c, 1000, 2000, 3000)
	before := rowOf(t, c, room)
	require.Equal(t, 3, before.Unread)

	evs, extras := historyBatch(c, room, friend.mxid, "old", 100, 200, 300)
	resp, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
	require.NoError(t, err)
	require.Len(t, resp.EventIDs, 3)

	got := bodiesOldestFirst(t, c, room)
	require.Len(t, got, 6)
	for i, want := range []string{"old message 100", "old message 200", "old message 300", "live message 1000", "live message 2000", "live message 3000"} {
		require.Contains(t, got[i], want, "message %d of the timeline", i)
	}
	after := rowOf(t, c, room)
	require.Equal(t, before.Preview, after.Preview, "the chat's preview stays its newest message")
	require.Equal(t, before.LastTS, after.LastTS, "history does not move the chat up the inbox")
	require.Equal(t, 3, after.Unread, "a year of history is not a year of unread")
}

// A second run of the same page, or one that overlaps a page already stored, adds nothing.
func TestBatchSendIsIdempotent(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	room, friend := chatWithMessages(t, c, 1000)
	evs, extras := historyBatch(c, room, friend.mxid, "old", 100, 200, 300)
	for range 2 {
		_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
		require.NoError(t, err)
	}
	overlap, overlapExtras := historyBatch(c, room, friend.mxid, "old", 200, 300, 400)
	_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: overlap}, overlapExtras)
	require.NoError(t, err)
	require.Len(t, bodiesOldestFirst(t, c, room), 1+4, "the live message and the four distinct old ones")
}

// History never counts as unread, whether the chat was read or not: with a read marker already past it, and with no
// marker at all (a chat nobody has read), where only the chat's own newer messages stay unread.
func TestBatchSendHistoryRaisesNoUnread(t *testing.T) {
	t.Run("chat read up to its newest message", func(t *testing.T) {
		c, ctx := newTestConnector(t), context.Background()
		room, friend := chatWithMessages(t, c, 1000, 2000)
		me, _, _ := c.NewUserIntent(ctx, ids.Me, "")
		require.NoError(t, me.MarkRead(ctx, room, id.EventID(string(mustLastEventID(t, c, room))), time.Unix(2000, 0)))
		require.Equal(t, 0, unreadOf(t, c, room))
		evs, extras := historyBatch(c, room, friend.mxid, "old", 100, 200)
		_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
		require.NoError(t, err)
		require.Equal(t, 0, unreadOf(t, c, room))
	})
	t.Run("chat never read", func(t *testing.T) {
		c, ctx := newTestConnector(t), context.Background()
		room, friend := chatWithMessages(t, c, 1000, 2000)
		require.Equal(t, 2, unreadOf(t, c, room))
		evs, extras := historyBatch(c, room, friend.mxid, "old", 100, 200, 300)
		_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
		require.NoError(t, err)
		require.Equal(t, 2, unreadOf(t, c, room), "the two messages that were unread, and none of the history")
		// and the next, older page changes nothing either
		evs, extras = historyBatch(c, room, friend.mxid, "older", 10, 20)
		_, err = c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
		require.NoError(t, err)
		require.Equal(t, 2, unreadOf(t, c, room))
	})
}

func mustLastEventID(t *testing.T, c *Connector, room id.RoomID) id.EventID {
	t.Helper()
	e, ok, err := c.store.LastMessage(context.Background(), string(room))
	require.NoError(t, err)
	require.True(t, ok)
	return id.EventID(e.EventID)
}

// A forward batch is a chat's first messages, or what came while Vitruvian Courier was closed. It is read when
// bridgev2 says so (MarkReadBy) and unread otherwise, as bridgev2's one-by-one backfill was.
func TestBatchSendForwardReadsAsBridgev2Says(t *testing.T) {
	for _, tc := range []struct {
		name     string
		markRead bool
		unread   int
	}{{"read on the network", true, 0}, {"unread on the network", false, 3}} {
		t.Run(tc.name, func(t *testing.T) {
			c, ctx := newTestConnector(t), context.Background()
			friend := c.GhostIntent("friend").(*Intent)
			room, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
			require.NoError(t, err)
			evs, extras := historyBatch(c, room, friend.mxid, "first", 100, 200, 300)
			req := &mautrix.ReqBeeperBatchSend{Forward: true, Events: evs}
			if tc.markRead {
				req.MarkReadBy = ids.Me
			}
			_, err = c.BatchSend(ctx, room, req, extras)
			require.NoError(t, err)
			require.Equal(t, tc.unread, unreadOf(t, c, room))
			require.Equal(t, "first message 300", rowOf(t, c, room).Preview)
		})
	}
}

// ForwardIfNoMessages on an empty chat is a forward batch (the first one a chat gets); on one with messages it is
// older history.
func TestBatchSendForwardIfNoMessages(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	friend := c.GhostIntent("friend").(*Intent)
	room, err := friend.CreateRoom(ctx, &mautrix.ReqCreateRoom{Invite: []id.UserID{ids.Me}})
	require.NoError(t, err)
	evs, extras := historyBatch(c, room, friend.mxid, "first", 100, 200)
	_, err = c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{ForwardIfNoMessages: true, Events: evs}, extras)
	require.NoError(t, err)
	require.Equal(t, 2, unreadOf(t, c, room), "an empty chat's first batch is its start: unread as the network has it")

	evs, extras = historyBatch(c, room, friend.mxid, "older", 10, 20)
	_, err = c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{ForwardIfNoMessages: true, Events: evs}, extras)
	require.NoError(t, err)
	require.Equal(t, 2, unreadOf(t, c, room), "in a chat with messages it is older history")
}

// Batch-inserted events are in the search index, like sent ones.
func TestBatchSendEventsAreSearchable(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	room, friend := chatWithMessages(t, c, 1000)
	evs, extras := historyBatch(c, room, friend.mxid, "zanzibar", 100)
	_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
	require.NoError(t, err)
	hits, _, err := c.store.SearchMessages(ctx, store.MessageQuery{Terms: searchtext.Parse("zanzibar")})
	require.NoError(t, err)
	require.Len(t, hits, 1)
	require.Equal(t, "$zanzibar100", hits[0].Event.EventID)
}

// A page of history for the same chat, written as the legacy one-by-one path writes a message, comes out the same.
func TestBatchSendStoresWhatSendMessageStores(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	room, friend := chatWithMessages(t, c)
	evs, extras := historyBatch(c, room, friend.mxid, "a", 100)
	_, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{Events: evs}, extras)
	require.NoError(t, err)
	_, err = friend.SendMessage(ctx, room, event.EventMessage, textContent("a message 200"), &bridgev2.MatrixSendExtra{Timestamp: time.Unix(200, 0)})
	require.NoError(t, err)
	stored, err := c.store.Events(ctx, string(room), 10)
	require.NoError(t, err)
	require.Len(t, stored, 2)
	for _, e := range stored {
		require.Equal(t, string(friend.mxid), e.Sender)
		require.Equal(t, "m.room.message", e.Type)
		require.Equal(t, "sent", e.Status)
	}
}

func TestBatchSendEmptyIsANoOp(t *testing.T) {
	c, ctx := newTestConnector(t), context.Background()
	room, _ := chatWithMessages(t, c, 1000)
	resp, err := c.BatchSend(ctx, room, &mautrix.ReqBeeperBatchSend{}, nil)
	require.NoError(t, err)
	require.Empty(t, resp.EventIDs)
}
