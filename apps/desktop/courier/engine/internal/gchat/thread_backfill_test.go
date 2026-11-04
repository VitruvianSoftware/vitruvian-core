// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"io"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

// threadBackfillServer answers list_topics the way Google does without the replies page-size fields: one
// message per topic, its head (message_id == topic_id), with the head carrying last_reply_time and
// num_unread_replies when the topic has replies. list_messages on a topic returns its head and replies.
type threadBackfillServer struct {
	mu           sync.Mutex
	listTopics   [][]byte
	listMessages []*pb.ListMessagesRequest
	failTopic    string
}

const (
	tbPeer      = "112233445566778899002"
	tbHeadA     = "DmTopicAAA" // has two replies
	tbHeadB     = "DmTopicBBB" // no replies
	tbHeadC     = "DmTopicCCC" // one old reply, already seen before the anchor
	tbHeadATime = int64(1710000100000000)
	tbReplyA1   = int64(1710000150000000)
	tbReplyA2   = int64(1710000250000000)
	tbHeadBTime = int64(1710000200000000)
	tbHeadCTime = int64(1710000050000000)
	tbReplyC1   = int64(1710000060000000)
)

func (s *threadBackfillServer) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	w.Header().Set("Content-Type", "application/x-protobuf")
	switch r.URL.Path {
	case "/u/0/api/list_topics":
		var req pb.ListTopicsRequest
		_ = pb.Unmarshal(body, &req)
		s.mu.Lock()
		s.listTopics = append(s.listTopics, body)
		s.mu.Unlock()
		gid := req.GetGroupId()
		headA := buildSyntheticMessageProto(gid, tbHeadA, tbHeadA, tbPeer, "Lunch?", tbHeadATime, "", 0, 0)
		headA.LastReplyTime = pb.Int64(tbReplyA2)
		headA.NumUnreadReplies = pb.Int64(2)
		headB := buildSyntheticMessageProto(gid, tbHeadB, tbHeadB, tbPeer, "Unrelated", tbHeadBTime, "", 0, 0)
		headC := buildSyntheticMessageProto(gid, tbHeadC, tbHeadC, tbPeer, "Old thread", tbHeadCTime, "", 0, 0)
		headC.LastReplyTime = pb.Int64(tbReplyC1)
		_, _ = w.Write(pb.MustMarshal(&pb.ListTopicsResponse{Topics: []*pb.Topic{
			{Id: buildTopicID(gid, tbHeadA), SortTime: pb.Int64(tbReplyA2), Replies: []*pb.Message{headA}},
			{Id: buildTopicID(gid, tbHeadB), SortTime: pb.Int64(tbHeadBTime), Replies: []*pb.Message{headB}},
			{Id: buildTopicID(gid, tbHeadC), SortTime: pb.Int64(tbReplyC1), Replies: []*pb.Message{headC}},
		}}))
	case "/u/0/api/list_messages":
		var req pb.ListMessagesRequest
		_ = pb.Unmarshal(body, &req)
		s.mu.Lock()
		s.listMessages = append(s.listMessages, &req)
		fail := s.failTopic
		s.mu.Unlock()
		tid := req.GetParentId().GetTopicId()
		gid, topic := tid.GetGroupId(), tid.GetTopicId()
		if topic == fail {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		var msgs []*pb.Message
		switch topic {
		case tbHeadA:
			msgs = []*pb.Message{
				buildSyntheticMessageProto(gid, tbHeadA, tbHeadA, tbPeer, "Lunch?", tbHeadATime, "", 0, 0),
				buildSyntheticMessageProto(gid, tbHeadA, "DmReplyA1", "112233445566778899001", "noon?", tbReplyA1, "", 0, 0),
				buildSyntheticMessageProto(gid, tbHeadA, "DmReplyA2", tbPeer, "noon works", tbReplyA2, "", 0, 0),
			}
		case tbHeadC:
			msgs = []*pb.Message{
				buildSyntheticMessageProto(gid, tbHeadC, tbHeadC, tbPeer, "Old thread", tbHeadCTime, "", 0, 0),
				buildSyntheticMessageProto(gid, tbHeadC, "DmReplyC1", tbPeer, "old reply", tbReplyC1, "", 0, 0),
			}
		}
		_, _ = w.Write(pb.MustMarshal(&pb.ListMessagesResponse{Messages: msgs}))
	default:
		http.NotFound(w, r)
	}
}

func backfillIDs(resp *bridgev2.FetchMessagesResponse) []networkid.MessageID {
	out := make([]networkid.MessageID, len(resp.Messages))
	for i, m := range resp.Messages {
		out[i] = m.ID
	}
	return out
}

func TestBackfillFetchesThreadRepliesOfTopicsThatHaveThem(t *testing.T) {
	ctx := context.Background()
	srv := &threadBackfillServer{}
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	dmPortal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("dm_threads"), Receiver: ul.ID})
	require.NoError(t, err)
	dmPortal.RoomType = database.RoomTypeDM

	// Initial backfill: heads plus the replies of A and C, oldest first; B has no replies and costs no call.
	resp, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: dmPortal, Count: 50})
	require.NoError(t, err)
	require.Equal(t, []networkid.MessageID{
		MakeThreadRootID(tbHeadC),
		MakeMessageID(tbHeadC, "DmReplyC1"),
		MakeThreadRootID(tbHeadA),
		MakeMessageID(tbHeadA, "DmReplyA1"),
		MakeThreadRootID(tbHeadB),
		MakeMessageID(tbHeadA, "DmReplyA2"),
	}, backfillIDs(resp), "heads and their replies, each once, oldest first")
	require.True(t, resp.AggressiveDeduplication, "a resync must skip what is already stored")
	for _, m := range resp.Messages {
		topic, msg := ParseMessageID(m.ID)
		if topic == msg {
			require.Nil(t, m.ThreadRoot, "head %s is not a thread reply", m.ID)
		} else {
			require.NotNil(t, m.ThreadRoot)
			require.Equal(t, MakeThreadRootID(topic), *m.ThreadRoot, "reply %s lands in its head's thread", m.ID)
		}
	}

	srv.mu.Lock()
	require.Len(t, srv.listMessages, 2, "only the topics with replies are listed")
	require.Equal(t, tbHeadA, srv.listMessages[0].GetParentId().GetTopicId().GetTopicId(), "newest reply activity first")
	require.Equal(t, "dm_threads", srv.listMessages[0].GetParentId().GetTopicId().GetGroupId().GetDmId().GetDmId())
	require.Equal(t, int32(repliesPageSize), srv.listMessages[0].GetPageSize())
	require.Equal(t, tbHeadC, srv.listMessages[1].GetParentId().GetTopicId().GetTopicId())
	require.Equal(t, pb.MustMarshal(&pb.ListTopicsRequest{
		GroupId:           pb.DMGroupID("dm_threads"),
		PageSizeForTopics: pb.Int32(50),
	}), listTopicsBodyWithoutHeader(t, srv.listTopics[0]), "list_topics still carries no replies page-size fields")
	srv.listMessages = nil
	srv.mu.Unlock()

	// Forward backfill after being offline: the last stored message is A1. A2 (sent while away) comes back; C's
	// replies are no newer than the anchor, so C is not listed again.
	fwd, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
		Portal: dmPortal, Forward: true, Count: 50,
		AnchorMessage: &database.Message{ID: MakeMessageID(tbHeadA, "DmReplyA1"), Timestamp: time.UnixMicro(tbReplyA1)},
	})
	require.NoError(t, err)
	require.Equal(t, []networkid.MessageID{
		MakeThreadRootID(tbHeadB),
		MakeMessageID(tbHeadA, "DmReplyA2"),
	}, backfillIDs(fwd), "the missed thread reply comes back on resync")
	require.True(t, fwd.AggressiveDeduplication)
	srv.mu.Lock()
	require.Len(t, srv.listMessages, 1)
	require.Equal(t, tbHeadA, srv.listMessages[0].GetParentId().GetTopicId().GetTopicId())
	srv.listMessages = nil
	srv.failTopic = tbHeadA
	srv.mu.Unlock()

	// A topic whose list_messages fails costs only its own replies.
	partial, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: dmPortal, Count: 50})
	require.NoError(t, err)
	require.Equal(t, []networkid.MessageID{
		MakeThreadRootID(tbHeadC),
		MakeMessageID(tbHeadC, "DmReplyC1"),
		MakeThreadRootID(tbHeadA),
		MakeThreadRootID(tbHeadB),
	}, backfillIDs(partial))
}

func TestTopicsWithRepliesIsBoundedAndNewestFirst(t *testing.T) {
	gid := pb.SpaceGroupID("space_busy")
	var topics []*pb.Topic
	for i := range maxReplyTopicsPerFetch + 5 {
		id := "Topic" + string(rune('A'+i))
		created := int64(1710000000000000 + i*1000)
		head := buildSyntheticMessageProto(gid, id, id, tbPeer, "x", created, "", 0, 0)
		head.LastReplyTime = pb.Int64(created + 500)
		topics = append(topics, &pb.Topic{Id: buildTopicID(gid, id), SortTime: pb.Int64(created + 500), Replies: []*pb.Message{head}})
	}
	quiet := buildSyntheticMessageProto(gid, "Quiet", "Quiet", tbPeer, "x", 1710000900000000, "", 0, 0)
	topics = append(topics, &pb.Topic{Id: buildTopicID(gid, "Quiet"), SortTime: pb.Int64(1710000900000000), Replies: []*pb.Message{quiet}})
	flagged := buildSyntheticMessageProto(gid, "Flagged", "Flagged", tbPeer, "x", 1710000000000000, "", 0, 0)
	topics = append(topics, &pb.Topic{Id: buildTopicID(gid, "Flagged"), Replies: []*pb.Message{flagged}, ContainsMoreUnreadReplies: pb.Bool(true)})

	got := topicsWithReplies(topics, false, 0)
	require.Len(t, got, maxReplyTopicsPerFetch)
	require.Equal(t, "Topic"+string(rune('A'+maxReplyTopicsPerFetch+4)), got[0], "newest reply first")
	require.NotContains(t, got, "Quiet", "a topic with no reply signal costs no call")

	// A topic flagged with unread replies but no time is fetched even when a forward anchor is set.
	fwd := topicsWithReplies(topics, true, 1710000999000000)
	require.Equal(t, []string{"Flagged"}, fwd)
}
