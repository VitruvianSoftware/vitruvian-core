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
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

// olderHistoryServer is a space with topics 1..total, topic i created (and last active) at olderBase+i seconds.
// list_topics answers like Google: newest first, only topics with a sort time older than the cursor (field 4)
// when one is sent, at most page_size_for_topics of them. ignoreCursor makes it answer as if the cursor were
// not there, to prove the client keeps only what is older than its anchor.
type olderHistoryServer struct {
	mu           sync.Mutex
	total        int
	ignoreCursor bool
	requests     []*pb.ListTopicsRequest
}

const olderBase = int64(1710000000000000)

func olderTime(i int) int64 { return olderBase + int64(i)*1_000_000 }

func olderTopicID(i int) string { return fmt.Sprintf("OldTopic%03d", i) }

func (s *olderHistoryServer) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	w.Header().Set("Content-Type", "application/x-protobuf")
	if r.URL.Path != "/u/0/api/list_topics" {
		http.NotFound(w, r)
		return
	}
	var req pb.ListTopicsRequest
	_ = pb.Unmarshal(body, &req)
	s.mu.Lock()
	s.requests = append(s.requests, &req)
	s.mu.Unlock()
	cursor := req.GetOlderThanSortTime().GetTimestamp()
	gid := req.GetGroupId()
	var topics []*pb.Topic
	for i := s.total; i >= 1 && len(topics) < int(req.GetPageSizeForTopics()); i-- {
		if cursor > 0 && !s.ignoreCursor && olderTime(i) >= cursor {
			continue
		}
		head := buildSyntheticMessageProto(gid, olderTopicID(i), olderTopicID(i), tbPeer, fmt.Sprintf("message %d", i), olderTime(i), "", 0, 0)
		topics = append(topics, &pb.Topic{Id: buildTopicID(gid, olderTopicID(i)), SortTime: pb.Int64(olderTime(i)), Replies: []*pb.Message{head}})
	}
	_, _ = w.Write(pb.MustMarshal(&pb.ListTopicsResponse{Topics: topics}))
}

func olderSetup(t *testing.T, srv *olderHistoryServer) (*Client, *bridgev2.Portal) {
	t.Helper()
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	portal, err := h.Bridge.GetPortalByKey(context.Background(), networkid.PortalKey{ID: MakeSpacePortalID("space_older"), Receiver: ul.ID})
	require.NoError(t, err)
	return client, portal
}

func olderAnchor(i int) *database.Message {
	return &database.Message{ID: MakeMessageID(olderTopicID(i), olderTopicID(i)), Timestamp: time.UnixMicro(olderTime(i))}
}

func TestBackwardBackfillSendsAnchorCursorAndPageSize30(t *testing.T) {
	srv := &olderHistoryServer{total: 100}
	client, portal := olderSetup(t, srv)

	// Count 100 is what the host may ask for; Google answers 500 above 30, so 30 goes out.
	_, err := client.FetchMessages(context.Background(), bridgev2.FetchMessagesParams{Portal: portal, Count: 100, AnchorMessage: olderAnchor(60)})
	require.NoError(t, err)

	srv.mu.Lock()
	defer srv.mu.Unlock()
	require.Len(t, srv.requests, 1)
	req := srv.requests[0]
	require.NotNil(t, req.GetOlderThanSortTime(), "scroll-up carries the field-4 cursor")
	require.Equal(t, olderTime(60), req.GetOlderThanSortTime().GetTimestamp(), "cursor is the anchor's time")
	require.Equal(t, int32(30), req.GetPageSizeForTopics())
	require.Equal(t, int32(1000), req.GetPageSizeForUnreadReplies())
	require.Equal(t, int32(20), req.GetPageSizeForReadReplies())
}

func TestBackwardBackfillReturnsOnlyOlderMessagesAndAdvances(t *testing.T) {
	srv := &olderHistoryServer{total: 100}
	client, portal := olderSetup(t, srv)

	resp, err := client.FetchMessages(context.Background(), bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: olderAnchor(60)})
	require.NoError(t, err)
	require.Len(t, resp.Messages, 30)
	for _, m := range resp.Messages {
		require.Less(t, m.Timestamp.UnixMicro(), olderTime(60), "%s is older than the anchor", m.ID)
	}
	require.Equal(t, MakeThreadRootID(olderTopicID(30)), resp.Messages[0].ID, "oldest first: topics 30..59")
	require.Equal(t, MakeThreadRootID(olderTopicID(59)), resp.Messages[29].ID)
}

func TestBackwardBackfillDropsNewerMessagesGoogleSendsAnyway(t *testing.T) {
	srv := &olderHistoryServer{total: 40, ignoreCursor: true}
	client, portal := olderSetup(t, srv)

	resp, err := client.FetchMessages(context.Background(), bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: olderAnchor(20)})
	require.NoError(t, err)
	ids := backfillIDs(resp)
	require.NotEmpty(t, ids)
	require.False(t, slices.Contains(ids, olderAnchor(20).ID), "the anchor itself is not sent again")
	for _, m := range resp.Messages {
		require.Less(t, m.Timestamp.UnixMicro(), olderTime(20), "%s is older than the anchor", m.ID)
	}
}

func TestBackwardBackfillHasMoreFollowsPageFullness(t *testing.T) {
	srv := &olderHistoryServer{total: 100}
	client, portal := olderSetup(t, srv)
	ctx := context.Background()

	full, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: olderAnchor(60)})
	require.NoError(t, err)
	require.Len(t, full.Messages, 30)
	require.True(t, full.HasMore, "a full page of topics means there may be older ones")

	// The first load stored a cursor (topic 30); these cases are independent walks, so start each without one and
	// the anchor's create time is the cursor.
	portal.Metadata = &PortalMetadata{}
	short, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: olderAnchor(11)})
	require.NoError(t, err)
	require.Len(t, short.Messages, 10, "topics 1..10")
	require.False(t, short.HasMore, "a short page is the start of the space")

	portal.Metadata = &PortalMetadata{}
	none, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: olderAnchor(1)})
	require.NoError(t, err)
	require.Empty(t, none.Messages)
	require.False(t, none.HasMore)
}

func TestInitialAndForwardListTopicsRequestsHaveNoCursor(t *testing.T) {
	srv := &olderHistoryServer{total: 100}
	client, portal := olderSetup(t, srv)
	ctx := context.Background()

	initial, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 50})
	require.NoError(t, err)
	require.False(t, initial.HasMore, "the initial backfill is the newest page, not a paging walk")
	fwd, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Forward: true, Count: 50, AnchorMessage: olderAnchor(90)})
	require.NoError(t, err)
	require.False(t, fwd.HasMore)
	require.Len(t, fwd.Messages, 10, "topics 91..100 are newer than the anchor")

	srv.mu.Lock()
	defer srv.mu.Unlock()
	require.Len(t, srv.requests, 2)
	for _, req := range srv.requests {
		require.Nil(t, req.GetOlderThanSortTime(), "no cursor outside a backwards load")
		require.Equal(t, int32(30), req.GetPageSizeForTopics())
		require.Equal(t, []pb.ListTopicsRequest_FetchOptions{3, 1, 4}, req.GetFetchOptions())
		require.Equal(t, int32(2), req.GetUnknown_11())
	}
}
