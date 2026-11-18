// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"slices"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

// TestBackwardBackfillExactFullFinalPageStopsAfterOneEmptyCall verifies Probe 2:
// when 60 topics lie before the first anchor (an exact multiple of the 30-topic page size),
// backwards paging returns 30 (HasMore=true), 30 (HasMore=true), then 0 (HasMore=false)
// and stops cleanly after that single empty call with no duplicate message IDs.
func TestBackwardBackfillExactFullFinalPageStopsAfterOneEmptyCall(t *testing.T) {
	srv := &olderHistoryServer{total: 61}
	client, portal := olderSetup(t, srv)
	ctx := context.Background()

	var pageCounts []int
	var pageHasMore []bool
	seen := make(map[networkid.MessageID]struct{})
	anchor := olderAnchor(61)

	for hasMore := true; hasMore; {
		resp, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
			Portal:        portal,
			Count:         30,
			AnchorMessage: anchor,
		})
		require.NoError(t, err)
		pageCounts = append(pageCounts, len(resp.Messages))
		pageHasMore = append(pageHasMore, resp.HasMore)
		for _, m := range resp.Messages {
			_, dup := seen[m.ID]
			require.False(t, dup, "duplicate message id %s", m.ID)
			seen[m.ID] = struct{}{}
			if m.Timestamp.Before(anchor.Timestamp) {
				anchor = &database.Message{ID: m.ID, Timestamp: m.Timestamp}
			}
		}
		hasMore = resp.HasMore
	}

	require.Equal(t, []int{30, 30, 0}, pageCounts)
	require.Equal(t, []bool{true, true, false}, pageHasMore)
	require.Len(t, seen, 60)
	for i := 1; i <= 60; i++ {
		require.Contains(t, seen, MakeThreadRootID(olderTopicID(i)))
	}

	srv.mu.Lock()
	defer srv.mu.Unlock()
	require.Len(t, srv.requests, 3, "walk stops after one empty call with no call after HasMore=false")
	require.Equal(t, olderTime(61), srv.requests[0].GetOlderThanSortTime().GetTimestamp())
	require.Equal(t, olderTime(31), srv.requests[1].GetOlderThanSortTime().GetTimestamp())
	require.Equal(t, olderTime(1), srv.requests[2].GetOlderThanSortTime().GetTimestamp())
}

type pagedThreadServer struct {
	mu                sync.Mutex
	total             int
	threadedTopics    map[int]int // topic index -> number of replies
	listTopicsReqs    []*pb.ListTopicsRequest
	listMessagesCalls []string
}

func (s *pagedThreadServer) topicMessages(gid *pb.GroupId, i int) (head *pb.Message, replies []*pb.Message, sortTime int64) {
	topicID := olderTopicID(i)
	created := olderTime(i)
	sortTime = created
	head = buildSyntheticMessageProto(gid, topicID, topicID, tbPeer, fmt.Sprintf("head %d", i), created, "", 0, 0)
	nReplies := s.threadedTopics[i]
	for r := 1; r <= nReplies; r++ {
		rt := created + int64(r)*100_000
		sortTime = rt
		replyID := fmt.Sprintf("%s_reply_%d", topicID, r)
		replies = append(replies, buildSyntheticMessageProto(gid, topicID, replyID, tbPeer, fmt.Sprintf("reply %d.%d", i, r), rt, "", 0, 0))
	}
	if nReplies > 0 {
		head.LastReplyTime = pb.Int64(sortTime)
	}
	return head, replies, sortTime
}

func (s *pagedThreadServer) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	w.Header().Set("Content-Type", "application/x-protobuf")
	switch r.URL.Path {
	case "/u/0/api/list_topics":
		var req pb.ListTopicsRequest
		_ = pb.Unmarshal(body, &req)
		s.mu.Lock()
		s.listTopicsReqs = append(s.listTopicsReqs, &req)
		s.mu.Unlock()

		cursor := req.GetOlderThanSortTime().GetTimestamp()
		gid := req.GetGroupId()
		var topics []*pb.Topic
		for i := s.total; i >= 1 && len(topics) < int(req.GetPageSizeForTopics()); i-- {
			head, replies, sortTime := s.topicMessages(gid, i)
			if cursor > 0 && sortTime >= cursor {
				continue
			}
			inline := append([]*pb.Message{head}, replies...)
			topics = append(topics, &pb.Topic{
				Id:       buildTopicID(gid, olderTopicID(i)),
				SortTime: pb.Int64(sortTime),
				Replies:  inline,
			})
		}
		_, _ = w.Write(pb.MustMarshal(&pb.ListTopicsResponse{Topics: topics}))
	case "/u/0/api/list_messages":
		var req pb.ListMessagesRequest
		_ = pb.Unmarshal(body, &req)
		tid := req.GetParentId().GetTopicId()
		gid, topicID := tid.GetGroupId(), tid.GetTopicId()
		s.mu.Lock()
		s.listMessagesCalls = append(s.listMessagesCalls, topicID)
		s.mu.Unlock()

		var msgs []*pb.Message
		for i := 1; i <= s.total; i++ {
			if olderTopicID(i) == topicID {
				head, replies, _ := s.topicMessages(gid, i)
				msgs = append([]*pb.Message{head}, replies...)
				break
			}
		}
		_, _ = w.Write(pb.MustMarshal(&pb.ListMessagesResponse{Messages: msgs}))
	default:
		http.NotFound(w, r)
	}
}

// TestBackwardBackfillDeliversOlderTopicThreadRepliesOnceAcrossPages verifies Probe 3:
// during a multi-page backwards walk where both list_topics and list_messages return a topic's replies,
// replies on older pages still load via fetchTopicReplies and every head and reply is delivered once.
func TestBackwardBackfillDeliversOlderTopicThreadRepliesOnceAcrossPages(t *testing.T) {
	srv := &pagedThreadServer{
		total: 50,
		threadedTopics: map[int]int{
			45: 2, // first backwards page (topics 20..49)
			35: 1, // first backwards page
			15: 2, // second/older backwards page (topics 1..19)
			5:  2, // second/older backwards page
		},
	}
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	ctx := context.Background()
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_paged_threads"), Receiver: ul.ID})
	require.NoError(t, err)

	counts := make(map[networkid.MessageID]int)
	anchor := olderAnchor(50)
	pages := 0
	for hasMore := true; hasMore; {
		resp, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
			Portal:        portal,
			Count:         30,
			AnchorMessage: anchor,
		})
		require.NoError(t, err)
		pages++
		for _, m := range resp.Messages {
			counts[m.ID]++
			topicID, msgID := ParseMessageID(m.ID)
			if topicID == msgID {
				require.Nil(t, m.ThreadRoot, "head %s has nil ThreadRoot", m.ID)
			} else {
				require.NotNil(t, m.ThreadRoot, "reply %s has ThreadRoot", m.ID)
				require.Equal(t, MakeThreadRootID(topicID), *m.ThreadRoot)
			}
			if m.Timestamp.Before(anchor.Timestamp) {
				anchor = &database.Message{ID: m.ID, Timestamp: m.Timestamp}
			}
		}
		hasMore = resp.HasMore
	}

	require.Equal(t, 2, pages, "49 older topics span two backwards pages (30 + 19)")
	for i := 1; i <= 49; i++ {
		topicID := olderTopicID(i)
		require.Equal(t, 1, counts[MakeThreadRootID(topicID)], "head %s delivered once", topicID)
		for r := 1; r <= srv.threadedTopics[i]; r++ {
			replyID := MakeMessageID(topicID, fmt.Sprintf("%s_reply_%d", topicID, r))
			require.Equal(t, 1, counts[replyID], "reply %s delivered once", replyID)
		}
	}

	srv.mu.Lock()
	defer srv.mu.Unlock()
	for _, idx := range []int{45, 35, 15, 5} {
		require.True(t, slices.Contains(srv.listMessagesCalls, olderTopicID(idx)),
			"fetchTopicReplies called for threaded topic %d", idx)
	}
}

// TestDMInitialBackfillCapsAt30AndBackwardWalkReachesRemainingTopics verifies Probe 4:
// a 45-topic DM requests page size 30 on initial backfill (Count=50 -> 30 returned, HasMore=false),
// and a subsequent backwards walk from the oldest delivered message fetches the remaining 15 topics.
func TestDMInitialBackfillCapsAt30AndBackwardWalkReachesRemainingTopics(t *testing.T) {
	srv := &olderHistoryServer{total: 45}
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	ctx := context.Background()

	dmPortal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("dm_45"), Receiver: ul.ID})
	require.NoError(t, err)
	dmPortal.RoomType = database.RoomTypeDM

	initial, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
		Portal: dmPortal,
		Count:  50,
	})
	require.NoError(t, err)
	require.Len(t, initial.Messages, 30, "initial DM backfill returns newest 30 topics (16..45)")
	require.False(t, initial.HasMore, "initial backfill reports HasMore=false")
	require.Equal(t, MakeThreadRootID(olderTopicID(16)), initial.Messages[0].ID)
	require.Equal(t, MakeThreadRootID(olderTopicID(45)), initial.Messages[29].ID)

	seen := make(map[networkid.MessageID]int)
	for _, m := range initial.Messages {
		seen[m.ID]++
	}

	anchor := &database.Message{
		ID:        initial.Messages[0].ID,
		Timestamp: initial.Messages[0].Timestamp,
	}
	var olderDelivered int
	for hasMore := true; hasMore; {
		page, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
			Portal:        dmPortal,
			Count:         50,
			AnchorMessage: anchor,
		})
		require.NoError(t, err)
		olderDelivered += len(page.Messages)
		for _, m := range page.Messages {
			seen[m.ID]++
			if m.Timestamp.Before(anchor.Timestamp) {
				anchor = &database.Message{ID: m.ID, Timestamp: m.Timestamp}
			}
		}
		hasMore = page.HasMore
	}

	require.Equal(t, 15, olderDelivered, "remaining 15 older DM topics (1..15) are reachable via backwards walk")
	require.Len(t, seen, 45)
	for i := 1; i <= 45; i++ {
		require.Equal(t, 1, seen[MakeThreadRootID(olderTopicID(i))], "DM topic %d delivered once", i)
	}

	srv.mu.Lock()
	defer srv.mu.Unlock()
	require.Len(t, srv.requests, 2)
	require.Equal(t, "dm_45", srv.requests[0].GetGroupId().GetDmId().GetDmId())
	require.Equal(t, int32(30), srv.requests[0].GetPageSizeForTopics(), "initial DM backfill requests page size 30 despite Count=50")
	require.Nil(t, srv.requests[0].GetOlderThanSortTime())
	require.Equal(t, int32(30), srv.requests[1].GetPageSizeForTopics())
	require.Equal(t, olderTime(16), srv.requests[1].GetOlderThanSortTime().GetTimestamp())
}
