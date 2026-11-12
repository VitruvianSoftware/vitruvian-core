// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/host"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// Real Google Chat ids, as stored by a live Courier: a message that starts a conversation is the head of its own
// topic, so its message_id equals its topic_id ("AbC/AbC"). An in-line thread reply keeps the head's topic_id and
// has its own message_id ("AbC/XyZ"). Flat spaces and DMs give every top-level message its own topic.
const (
	threadsTestOwnGaia  = "112233445566778899001"
	threadsTestPeerGaia = "112233445566778899002"

	threadsTestDM         = "dm_threads"
	threadsTestFlatSpace  = "space_flat"
	threadsTestInlineRoom = "space_inline"
)

type threadsTestEnv struct {
	h      *host.Host
	ul     *bridgev2.UserLogin
	client *Client
	st     *store.Store
	conn   *Connector

	mu              sync.Mutex
	createTopicReqs []*pb.CreateTopicRequest
	createMsgReqs   []*pb.CreateMessageRequest
}

func threadsTestWorld() []byte {
	joined := &pb.GroupReadState{
		MembershipState: pb.MembershipState_MEMBER_JOINED.Enum(),
		JoinedUsers:     []*pb.UserId{pb.HumanUserID(threadsTestOwnGaia), pb.HumanUserID(threadsTestPeerGaia)},
	}
	return pb.MustMarshal(&pb.PaginatedWorldResponse{
		UserRevision: &pb.ReadRevision{Timestamp: pb.Int64(500)},
		WorldItems: []*pb.WorldItemLite{
			{
				// Google marks DMs flat_threads_enabled now: they have in-line threads.
				GroupId:            pb.DMGroupID(threadsTestDM),
				GroupRevision:      &pb.ReadRevision{Timestamp: pb.Int64(90)},
				SortTimestamp:      pb.Int64(1710000001000000),
				ReadState:          joined,
				FlatThreadsEnabled: pb.Bool(true),
			},
			{
				GroupId:       pb.SpaceGroupID(threadsTestFlatSpace),
				GroupRevision: &pb.ReadRevision{Timestamp: pb.Int64(110)},
				SortTimestamp: pb.Int64(1710000002000000),
				ReadState:     &pb.GroupReadState{MembershipState: pb.MembershipState_MEMBER_JOINED.Enum()},
				RoomName:      pb.String("Flat"),
			},
			{
				GroupId:            pb.SpaceGroupID(threadsTestInlineRoom),
				GroupRevision:      &pb.ReadRevision{Timestamp: pb.Int64(115)},
				SortTimestamp:      pb.Int64(1710000002500000),
				ReadState:          &pb.GroupReadState{MembershipState: pb.MembershipState_MEMBER_JOINED.Enum()},
				RoomName:           pb.String("In-line threads"),
				FlatThreadsEnabled: pb.Bool(true),
			},
		},
	})
}

func setupThreadsTestEnv(t *testing.T) *threadsTestEnv {
	t.Helper()
	enableTestLoopback(t)
	ctx := context.Background()
	env := &threadsTestEnv{}
	var seq int64

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			_, _ = w.Write(buildSyntheticSelfUserStatusResponse(threadsTestOwnGaia))
		case "/u/0/api/get_members":
			_, _ = w.Write(buildSyntheticGetMembersResponse(threadsTestOwnGaia, "Ada Lovelace", "ada@example.com", "https://example.invalid/avatar/ada.png"))
		case "/u/0/api/paginated_world":
			_, _ = w.Write(threadsTestWorld())
		case "/u/0/api/create_topic":
			body, _ := io.ReadAll(r.Body)
			var req pb.CreateTopicRequest
			_ = pb.Unmarshal(body, &req)
			env.mu.Lock()
			env.createTopicReqs = append(env.createTopicReqs, &req)
			seq++
			n := seq
			env.mu.Unlock()
			// A new topic's head: message_id == topic_id.
			topic := fmt.Sprintf("NewTopic%03d", n)
			ts := 1710000700000000 + n
			head := buildSyntheticMessageProto(req.GetGroupId(), topic, topic, threadsTestOwnGaia, req.GetTextBody(), ts, "", 0, 0)
			_, _ = w.Write(pb.MustMarshal(&pb.CreateTopicResponse{Topic: &pb.Topic{
				Id: buildTopicID(req.GetGroupId(), topic), SortTime: pb.Int64(ts), CreateTimeUsec: pb.Int64(ts),
				Replies: []*pb.Message{head},
			}}))
		case "/u/0/api/create_message":
			body, _ := io.ReadAll(r.Body)
			var req pb.CreateMessageRequest
			_ = pb.Unmarshal(body, &req)
			env.mu.Lock()
			env.createMsgReqs = append(env.createMsgReqs, &req)
			seq++
			n := seq
			env.mu.Unlock()
			tid := req.GetParentId().GetTopicId()
			topic, msg := tid.GetTopicId(), fmt.Sprintf("NewMsg%03d", n)
			if topic == "" {
				// No topic asked for (a DM's top-level message): Google starts one, headed by this message.
				topic = msg
			}
			_, _ = w.Write(pb.MustMarshal(&pb.CreateMessageResponse{
				Message: buildSyntheticMessageProto(tid.GetGroupId(), topic, msg, threadsTestOwnGaia, req.GetTextBody(), 1710000700000000+n, "", 0, 0),
			}))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })
	conn := &Connector{baseURL: srv.URL}
	h, err := host.Start(ctx, dir, NetworkID, st, &media.Store{Dir: filepath.Join(dir, "media")}, conn, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	user, err := h.Bridge.GetUserByMXID(ctx, "@me:courier.local")
	require.NoError(t, err)
	proc, err := conn.CreateLogin(ctx, user, FlowCookies)
	require.NoError(t, err)
	done, err := proc.(bridgev2.LoginProcessCookies).SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass", "OSID": "synthetic_osid", "SID": "synthetic_sid",
		"HSID": "synthetic_hsid", "SSID": "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := done.CompleteParams.UserLogin
	client := ul.Client.(*Client)
	t.Cleanup(client.Disconnect)
	require.NoError(t, client.syncWorld(ctx))

	env.h, env.ul, env.client, env.st, env.conn = h, ul, client, st, conn
	return env
}

func (env *threadsTestEnv) portal(t *testing.T, id networkid.PortalID) *bridgev2.Portal {
	t.Helper()
	p, err := env.h.Bridge.GetExistingPortalByKey(context.Background(), networkid.PortalKey{ID: id, Receiver: env.ul.ID})
	require.NoError(t, err)
	require.NotNil(t, p)
	return p
}

// post delivers a real-shaped MESSAGE_POSTED event and waits until bridgev2 has stored it.
func (env *threadsTestEnv) post(t *testing.T, gid *pb.GroupId, topic, msg, text string, ts int64) *database.Message {
	t.Helper()
	ctx := context.Background()
	m := buildSyntheticMessageProto(gid, topic, msg, threadsTestPeerGaia, text, ts, "", 0, 0)
	env.client.processStreamNotification(ctx, streamNotification{kind: EventKindEventProto, payload: pb.MustMarshal(&pb.Event{
		GroupId: gid,
		Type:    pb.Event_MESSAGE_POSTED.Enum(),
		Body: &pb.Event_EventBody{
			EventType: pb.Event_MESSAGE_POSTED.Enum(),
			Type:      &pb.Event_EventBody_MessagePosted{MessagePosted: &pb.MessageEvent{Message: m}},
		},
	})})
	var stored *database.Message
	require.Eventually(t, func() bool {
		got, err := env.h.Bridge.DB.Message.GetFirstPartByID(ctx, env.ul.ID, MakeMessageID(topic, msg))
		stored = got
		return err == nil && got != nil
	}, 3*time.Second, 20*time.Millisecond, "message %s/%s must be stored", topic, msg)
	return stored
}

func eventIDs(evts []store.Event) []string {
	out := make([]string, 0, len(evts))
	for _, e := range evts {
		if e.Type == "m.room.message" {
			out = append(out, e.EventID)
		}
	}
	return out
}

func relType(t *testing.T, evts []store.Event, eventID string) string {
	t.Helper()
	for _, e := range evts {
		if e.EventID == eventID {
			var c struct {
				RelatesTo struct {
					RelType string `json:"rel_type"`
				} `json:"m.relates_to"`
			}
			require.NoError(t, json.Unmarshal(e.Content, &c))
			return c.RelatesTo.RelType
		}
	}
	t.Fatalf("event %s not found", eventID)
	return ""
}

// TestInboundTopicHeadsStayInTimelineAndDMRepliesLandInThread covers the four real shapes end to end, from the
// WebChannel event through bridgev2 into Courier's store: a DM's top-level message, an in-line DM thread reply, a
// reply in an in-line-threaded space and a flat space's messages.
func TestInboundTopicHeadsStayInTimelineAndDMRepliesLandInThread(t *testing.T) {
	ctx := context.Background()
	env := setupThreadsTestEnv(t)

	// 1. DM top-level message, then 2. an in-line DM thread reply to it.
	dmGID := pb.DMGroupID(threadsTestDM)
	dmHead := env.post(t, dmGID, "DmTopicAAA", "DmTopicAAA", "Lunch?", 1710000100000000)
	dmReply := env.post(t, dmGID, "DmTopicAAA", "DmReplyBBB", "Sure, noon", 1710000101000000)
	dmNext := env.post(t, dmGID, "DmTopicCCC", "DmTopicCCC", "Another top-level", 1710000102000000)

	require.Empty(t, dmHead.ThreadRoot, "a DM's top-level message is its topic's head, never a reply in its own thread")
	require.Empty(t, dmNext.ThreadRoot)
	require.Equal(t, MakeThreadRootID("DmTopicAAA"), dmReply.ThreadRoot, "an in-line DM reply belongs to its head's thread")

	dmRoom := env.portal(t, MakeDMPortalID(threadsTestDM)).MXID.String()
	main, _, err := env.st.EventsBefore(ctx, dmRoom, nil, 50)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{dmHead.MXID.String(), dmNext.MXID.String()}, eventIDs(main), "main DM timeline: both top-level messages, not the thread reply")
	require.Empty(t, relType(t, main, dmHead.MXID.String()))

	replies, _, err := env.st.ThreadEventsBefore(ctx, dmRoom, dmHead.MXID.String(), nil, 50)
	require.NoError(t, err)
	require.Contains(t, eventIDs(replies), dmReply.MXID.String(), "the thread pane shows the DM reply")
	require.Equal(t, "m.thread", relType(t, replies, dmReply.MXID.String()))
	sums, err := env.st.ThreadSummaries(ctx, dmRoom, []string{dmHead.MXID.String()})
	require.NoError(t, err)
	require.Equal(t, 1, sums[dmHead.MXID.String()].Replies, "the DM head shows a one-reply summary")

	// 3. A reply in an in-line-threaded space.
	inGID := pb.SpaceGroupID(threadsTestInlineRoom)
	inHead := env.post(t, inGID, "SpTopicDDD", "SpTopicDDD", "Deploy at 5", 1710000200000000)
	inReply := env.post(t, inGID, "SpTopicDDD", "SpReplyEEE", "ack", 1710000201000000)
	require.Empty(t, inHead.ThreadRoot)
	require.Equal(t, MakeThreadRootID("SpTopicDDD"), inReply.ThreadRoot)
	inRoom := env.portal(t, MakeSpacePortalID(threadsTestInlineRoom)).MXID.String()
	inMain, _, err := env.st.EventsBefore(ctx, inRoom, nil, 50)
	require.NoError(t, err)
	require.Equal(t, []string{inHead.MXID.String()}, eventIDs(inMain))
	inReplies, _, err := env.st.ThreadEventsBefore(ctx, inRoom, inHead.MXID.String(), nil, 50)
	require.NoError(t, err)
	require.Contains(t, eventIDs(inReplies), inReply.MXID.String())

	// 4. A flat space: every message heads its own topic, so all stay in the timeline.
	flatGID := pb.SpaceGroupID(threadsTestFlatSpace)
	flat1 := env.post(t, flatGID, "FlTopicFFF", "FlTopicFFF", "one", 1710000300000000)
	flat2 := env.post(t, flatGID, "FlTopicGGG", "FlTopicGGG", "two", 1710000301000000)
	require.Empty(t, flat1.ThreadRoot)
	require.Empty(t, flat2.ThreadRoot)
	flatRoom := env.portal(t, MakeSpacePortalID(threadsTestFlatSpace)).MXID.String()
	flatMain, _, err := env.st.EventsBefore(ctx, flatRoom, nil, 50)
	require.NoError(t, err)
	require.ElementsMatch(t, []string{flat1.MXID.String(), flat2.MXID.String()}, eventIDs(flatMain))
	require.Empty(t, relType(t, flatMain, flat1.MXID.String()))
	require.Empty(t, relType(t, flatMain, flat2.MXID.String()))
}

// TestDMThreadCapabilityAndReplyInThreadSendsToTopic: a DM with in-line threads offers "Reply in thread", the
// reply goes to the head's topic, and a plain quote-reply stays a top-level message rather than a thread reply.
func TestDMThreadCapabilityAndReplyInThreadSendsToTopic(t *testing.T) {
	ctx := context.Background()
	env := setupThreadsTestEnv(t)

	dmPortal := env.portal(t, MakeDMPortalID(threadsTestDM))
	flatPortal := env.portal(t, MakeSpacePortalID(threadsTestFlatSpace))
	inlinePortal := env.portal(t, MakeSpacePortalID(threadsTestInlineRoom))
	require.Equal(t, event.CapLevelFullySupported, env.client.GetCapabilities(ctx, dmPortal).Thread, "DMs with in-line threads must offer Reply in thread")
	require.Equal(t, event.CapLevelFullySupported, env.client.GetCapabilities(ctx, inlinePortal).Thread)
	require.Equal(t, event.CapLevelUnsupported, env.client.GetCapabilities(ctx, flatPortal).Thread, "a flat space stays flat")

	dmHead := env.post(t, pb.DMGroupID(threadsTestDM), "DmTopicAAA", "DmTopicAAA", "Lunch?", 1710000100000000)

	// Reply in thread in the DM.
	resp, err := env.client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal, Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "noon works"},
		},
		ThreadRoot: dmHead,
	})
	require.NoError(t, err)
	env.mu.Lock()
	require.Len(t, env.createMsgReqs, 1)
	threadReq := env.createMsgReqs[0]
	env.mu.Unlock()
	require.Equal(t, "DmTopicAAA", threadReq.GetParentId().GetTopicId().GetTopicId(), "the DM thread reply must go to the head's topic")
	require.Equal(t, threadsTestDM, threadReq.GetParentId().GetTopicId().GetGroupId().GetDmId().GetDmId())
	require.Equal(t, MakeThreadRootID("DmTopicAAA"), resp.DB.ThreadRoot, "the sent DM thread reply is stored in its thread")

	// A plain top-level DM message is a head, not a thread reply.
	resp, err = env.client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal, Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "top-level"},
		},
	})
	require.NoError(t, err)
	env.mu.Lock()
	require.Len(t, env.createMsgReqs, 2)
	require.Empty(t, env.createMsgReqs[1].GetParentId().GetTopicId().GetTopicId())
	env.mu.Unlock()
	require.Empty(t, resp.DB.ThreadRoot, "a top-level DM message must not be stored as a reply in its own thread")

	// A quote-reply in the DM (no thread) must not be filed into the quoted message's thread on Google's side.
	resp, err = env.client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal, Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "quoting you"},
		},
		ReplyTo: dmHead,
	})
	require.NoError(t, err)
	env.mu.Lock()
	require.Len(t, env.createMsgReqs, 3)
	quoteReq := env.createMsgReqs[2]
	env.mu.Unlock()
	require.Empty(t, quoteReq.GetParentId().GetTopicId().GetTopicId(), "a DM quote-reply is a new top-level message")
	require.Equal(t, "DmTopicAAA", quoteReq.GetMessageInfo().GetReplyTo().GetId().GetMessageId(), "and still quotes the message")
	require.Empty(t, resp.DB.ThreadRoot)

	// A quote-reply in an in-line-threaded space starts a new topic too.
	inHead := env.post(t, pb.SpaceGroupID(threadsTestInlineRoom), "SpTopicDDD", "SpTopicDDD", "Deploy at 5", 1710000200000000)
	resp, err = env.client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: inlinePortal, Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "re: deploy"},
		},
		ReplyTo: inHead,
	})
	require.NoError(t, err)
	env.mu.Lock()
	require.Len(t, env.createTopicReqs, 1, "a quote-reply in an in-line-threaded space creates a topic")
	require.Equal(t, "SpTopicDDD", env.createTopicReqs[0].GetMessageInfo().GetReplyTo().GetId().GetMessageId())
	require.Len(t, env.createMsgReqs, 3)
	env.mu.Unlock()
	require.Empty(t, resp.DB.ThreadRoot, "a new topic's head is not a thread reply")
}

// TestConnectorStartClearsSelfThreadRoots repairs heads stored by earlier versions as replies in their own thread,
// which would otherwise turn every quote-reply to them into a thread reply once a chat offers threads.
func TestConnectorStartClearsSelfThreadRoots(t *testing.T) {
	ctx := context.Background()
	env := setupThreadsTestEnv(t)
	dmPortal := env.portal(t, MakeDMPortalID(threadsTestDM))

	insert := func(msgID, root networkid.MessageID, mxid string) {
		require.NoError(t, env.h.Bridge.DB.Message.Insert(ctx, &database.Message{
			ID: msgID, Room: dmPortal.PortalKey, MXID: id.EventID("$" + mxid + ":courier.local"), SenderID: MakeUserID(threadsTestPeerGaia),
			Timestamp: time.UnixMicro(1710000000000000), ThreadRoot: root, Metadata: &MessageMetadata{TopicID: "T"},
		}))
	}
	insert(MakeThreadRootID("OldHead"), MakeThreadRootID("OldHead"), "oldhead")
	insert(MakeMessageID("OldHead", "OldReply"), MakeThreadRootID("OldHead"), "oldreply")

	require.NoError(t, env.conn.Start(ctx))

	head, err := env.h.Bridge.DB.Message.GetFirstPartByID(ctx, env.ul.ID, MakeThreadRootID("OldHead"))
	require.NoError(t, err)
	require.Empty(t, head.ThreadRoot, "a stored head must no longer point at itself")
	reply, err := env.h.Bridge.DB.Message.GetFirstPartByID(ctx, env.ul.ID, MakeMessageID("OldHead", "OldReply"))
	require.NoError(t, err)
	require.Equal(t, MakeThreadRootID("OldHead"), reply.ThreadRoot, "real thread replies keep their thread")
}
