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

// gapTopic is a topic as Google keeps it: a head created at createSec, and a sort time (last activity) of
// sortSec, which is the last reply's time when replySec is set and the head's time otherwise.
type gapTopic struct {
	id                 string
	createSec, sortSec int64
	replySec           int64
}

// gapServer answers list_topics the way Google does: topics newest-sort-time first, only topics whose sort time
// is older than the field-4 cursor, at most page_size_for_topics of them. list_messages answers empty.
type gapServer struct {
	mu       sync.Mutex
	topics   []gapTopic
	requests []*pb.ListTopicsRequest
}

func gapMicros(sec int64) int64 { return olderBase + sec*1_000_000 }

func (s *gapServer) handle(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	w.Header().Set("Content-Type", "application/x-protobuf")
	switch r.URL.Path {
	case "/u/0/api/list_topics":
		var req pb.ListTopicsRequest
		_ = pb.Unmarshal(body, &req)
		s.mu.Lock()
		s.requests = append(s.requests, &req)
		s.mu.Unlock()
		cursor := req.GetOlderThanSortTime().GetTimestamp()
		gid := req.GetGroupId()
		sorted := slices.Clone(s.topics)
		slices.SortFunc(sorted, func(a, b gapTopic) int { return int(b.sortSec - a.sortSec) })
		var out []*pb.Topic
		for _, t := range sorted {
			if len(out) >= int(req.GetPageSizeForTopics()) {
				break
			}
			if cursor > 0 && gapMicros(t.sortSec) >= cursor {
				continue
			}
			msgs := []*pb.Message{buildSyntheticMessageProto(gid, t.id, t.id, tbPeer, "head "+t.id, gapMicros(t.createSec), "", 0, 0)}
			if t.replySec > 0 {
				msgs = append(msgs, buildSyntheticMessageProto(gid, t.id, t.id+"_reply", tbPeer, "reply "+t.id, gapMicros(t.replySec), "", 0, 0))
			}
			out = append(out, &pb.Topic{Id: buildTopicID(gid, t.id), SortTime: pb.Int64(gapMicros(t.sortSec)), Replies: msgs})
		}
		_, _ = w.Write(pb.MustMarshal(&pb.ListTopicsResponse{Topics: out}))
	case "/u/0/api/list_messages":
		_, _ = w.Write(pb.MustMarshal(&pb.ListMessagesResponse{}))
	default:
		http.NotFound(w, r)
	}
}

// gapTopics: 29 topics created and last active at 3001..3029 s; P30 created at 2000 s with a reply at 2600 s, so
// the 30 newest by sort time are P1..P30 and P30's head (2000 s) is the oldest message of the newest page. T was
// created at 1500 s but had a reply at 2300 s: its sort time is newer than the anchor's create time (2000 s) and
// older than P30's sort time (2600 s), so it sits outside the newest page. Z is an ordinary older topic at 1000 s.
func gapTopics() []gapTopic {
	var ts []gapTopic
	for i := int64(1); i <= 29; i++ {
		ts = append(ts, gapTopic{id: fmt.Sprintf("P%02d", i), createSec: 3000 + i, sortSec: 3000 + i})
	}
	ts = append(
		ts,
		gapTopic{id: "P30", createSec: 2000, sortSec: 2600, replySec: 2600},
		gapTopic{id: "T", createSec: 1500, sortSec: 2300, replySec: 2300},
		gapTopic{id: "Z", createSec: 1000, sortSec: 1000},
	)
	return ts
}

// TestBackwardBackfillCursorGapLosesTopicWithLaterReply models the cursor gap: backwards paging sends the
// anchor's create time, but Google filters on sort time, so topic T (head older than the anchor, last reply newer
// than it) is never listed by any backwards page. A full walk from the newest page must still deliver T's head.
// Expected to FAIL on the current code; see the driver report for the reproduction.
func TestBackwardBackfillCursorGapLosesTopicWithLaterReply(t *testing.T) {
	srv := &gapServer{topics: gapTopics()}
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	ctx := context.Background()
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_gap"), Receiver: ul.ID})
	require.NoError(t, err)

	delivered := make(map[networkid.MessageID]int)
	record := func(msgs []*bridgev2.BackfillMessage) *database.Message {
		var oldest *database.Message
		for _, m := range msgs {
			delivered[m.ID]++
			if oldest == nil || m.Timestamp.Before(oldest.Timestamp) {
				oldest = &database.Message{ID: m.ID, Timestamp: m.Timestamp}
			}
		}
		return oldest
	}

	initial, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30})
	require.NoError(t, err)
	require.Len(t, initial.Messages, 31, "newest page is P1..P30 heads plus P30 reply")
	anchor := record(initial.Messages)
	require.NotNil(t, anchor)
	require.Equal(t, MakeThreadRootID("P30"), anchor.ID, "P30's head is the oldest message loaded so far")

	for step := 0; step < 10; step++ {
		resp, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30, AnchorMessage: anchor})
		require.NoError(t, err)
		if oldest := record(resp.Messages); oldest != nil {
			anchor = oldest
		}
		if !resp.HasMore {
			break
		}
	}

	srv.mu.Lock()
	require.Len(t, srv.requests, 2, "one initial page and one backwards page")
	require.Equal(t, gapMicros(2600), srv.requests[1].GetOlderThanSortTime().GetTimestamp(), "the cursor is the oldest sort time returned (P30's), not the anchor's create time (2000 s)")
	srv.mu.Unlock()
	require.Contains(t, delivered, MakeThreadRootID("Z"), "the ordinary older topic is reached")
	require.Equal(t, 1, delivered[MakeThreadRootID("T")], "topic T (head 1500 s, last reply 2300 s) head arrives exactly once")
	require.Equal(t, 1, delivered[MakeMessageID("T", "T_reply")], "and so does its reply")
	for id, n := range delivered {
		require.Equal(t, 1, n, "%s delivered once", id)
	}
}

// The cursor is kept in the portal's metadata: a portal read back from the database after a restart (nothing
// in memory) still pages from the oldest sort time seen, so T is found.
func TestBackwardBackfillCursorSurvivesRestart(t *testing.T) {
	srv := &gapServer{topics: gapTopics()}
	h, ul, client := setupLoggedInGChatTestEnv(t, srv.handle)
	ctx := context.Background()
	key := networkid.PortalKey{ID: MakeSpacePortalID("space_gap"), Receiver: ul.ID}
	portal, err := h.Bridge.GetPortalByKey(ctx, key)
	require.NoError(t, err)

	initial, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Count: 30})
	require.NoError(t, err)
	require.Len(t, initial.Messages, 31)

	row, err := h.Bridge.DB.Portal.GetByKey(ctx, key)
	require.NoError(t, err)
	stored, ok := row.Metadata.(*PortalMetadata)
	require.True(t, ok, "metadata read back from the database")
	require.Equal(t, gapMicros(2600), stored.OldestTopicSortTime, "the minimum sort time of the initial page was saved")

	// A fresh portal object built from the stored row, as after a restart.
	restarted := &bridgev2.Portal{Portal: row, Bridge: h.Bridge}
	anchor := &database.Message{ID: MakeThreadRootID("P30"), Timestamp: time.UnixMicro(gapMicros(2000))}
	page, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: restarted, Count: 30, AnchorMessage: anchor})
	require.NoError(t, err)
	require.Contains(t, backfillIDs(page), MakeThreadRootID("T"))

	srv.mu.Lock()
	defer srv.mu.Unlock()
	require.Equal(t, gapMicros(2600), srv.requests[1].GetOlderThanSortTime().GetTimestamp())
}
