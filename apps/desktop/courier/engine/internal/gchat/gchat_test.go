// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func encodeVarint(v uint64) []byte {
	var out []byte
	for v >= 0x80 {
		out = append(out, byte(v)|0x80)
		v >>= 7
	}
	out = append(out, byte(v))
	return out
}

func encodeVarintField(fieldNum int, v uint64) []byte {
	tag := uint64((fieldNum << 3) | 0)
	out := encodeVarint(tag)
	out = append(out, encodeVarint(v)...)
	return out
}

func encodeBytesField(fieldNum int, data []byte) []byte {
	tag := uint64((fieldNum << 3) | 2)
	out := encodeVarint(tag)
	out = append(out, encodeVarint(uint64(len(data)))...)
	out = append(out, data...)
	return out
}

func encodeStringField(fieldNum int, s string) []byte {
	return encodeBytesField(fieldNum, []byte(s))
}

// buildSyntheticSelfUserStatusResponse encodes GetSelfUserStatusResponse { user_status: UserStatus { user_id: UserId { id: gaiaID } } }.
func buildSyntheticSelfUserStatusResponse(gaiaID string) []byte {
	userID := encodeStringField(1, gaiaID)
	userStatus := encodeBytesField(1, userID)
	return encodeBytesField(1, userStatus)
}

// buildSyntheticGetMembersResponse encodes GetMembersResponse { members: [Member { user: User { user_id: UserId { id }, name, avatar_url, email } }] }.
func buildSyntheticGetMembersResponse(gaiaID, name, email, avatarURL string) []byte {
	userID := encodeStringField(1, gaiaID)
	var user []byte
	user = append(user, encodeBytesField(1, userID)...)
	user = append(user, encodeStringField(2, name)...)
	user = append(user, encodeStringField(3, avatarURL)...)
	user = append(user, encodeStringField(4, email)...)
	member := encodeBytesField(1, user)
	return encodeBytesField(1, member)
}

func TestGChatCookieLoginFlowCreatesUserLogin(t *testing.T) {
	enableTestLoopback(t)

	var lastCookieHeader atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lastCookieHeader.Store(r.Header.Get("Cookie"))
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			payload := buildSyntheticSelfUserStatusResponse("112233445566778899001")
			w.Header().Set("Content-Type", "text/plain")
			w.Header().Set("X-Goog-Safety-Encoding", "base64")
			_, _ = w.Write([]byte(base64.StdEncoding.EncodeToString(payload)))
		case "/u/0/api/get_members":
			payload := buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(payload)
		default:
			http.NotFound(w, r)
		}
	}))
	defer srv.Close()

	ctx := context.Background()
	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	conn := &Connector{
		baseURL: srv.URL,
	}
	h, err := host.Start(ctx, dir, NetworkID, st, &media.Store{Dir: filepath.Join(dir, "media")}, conn, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	flows := conn.GetLoginFlows()
	require.Len(t, flows, 1)
	require.Equal(t, FlowCookies, flows[0].ID)

	user, err := h.Bridge.GetUserByMXID(ctx, "@me:courier.local")
	require.NoError(t, err)

	proc, err := conn.CreateLogin(ctx, user, FlowCookies)
	require.NoError(t, err)

	step, err := proc.Start(ctx)
	require.NoError(t, err)
	require.Equal(t, bridgev2.LoginStepTypeCookies, step.Type)
	require.Equal(t, "fi.mau.gchat.login.cookies", step.StepID)
	require.NotNil(t, step.CookiesParams)
	require.Equal(t, "https://chat.google.com/", step.CookiesParams.URL)
	require.Equal(t, `^https://chat\.google\.com/`, step.CookiesParams.WaitForURLPattern)

	domainsByField := make(map[string]string)
	requiredByField := make(map[string]bool)
	for _, f := range step.CookiesParams.Fields {
		requiredByField[f.ID] = f.Required
		if len(f.Sources) > 0 {
			domainsByField[f.ID] = f.Sources[0].CookieDomain
		}
	}
	require.True(t, requiredByField["COMPASS"])
	require.Equal(t, "chat.google.com", domainsByField["COMPASS"])
	require.True(t, requiredByField["OSID"])
	require.Equal(t, "chat.google.com", domainsByField["OSID"])
	require.True(t, requiredByField["SID"])
	require.Equal(t, "google.com", domainsByField["SID"])
	require.True(t, requiredByField["HSID"])
	require.Equal(t, "google.com", domainsByField["HSID"])
	require.True(t, requiredByField["SSID"])
	require.Equal(t, "google.com", domainsByField["SSID"])

	cookieLogin, ok := proc.(bridgev2.LoginProcessCookies)
	require.True(t, ok)

	_, err = cookieLogin.SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
	})
	require.Error(t, err, "missing required cookies must be refused before storing")
	loginsBefore, err := h.Bridge.DB.UserLogin.GetAllForUser(ctx, user.MXID)
	require.NoError(t, err)
	require.Empty(t, loginsBefore, "refused cookie submission must leave nothing on disk")

	doneStep, err := cookieLogin.SubmitCookies(ctx, map[string]string{
		"COMPASS":    "dynamite-ui=synthetic_compass+plus%2Bpct/slash=eq",
		"OSID":       "synthetic_osid+plus%2Bpct/slash=eq",
		"SID":        "synthetic_sid+plus%2Bpct/slash=eq",
		"HSID":       "synthetic_hsid",
		"SSID":       "synthetic_ssid",
		"user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15",
	})
	require.NoError(t, err)
	require.Equal(t, bridgev2.LoginStepTypeComplete, doneStep.Type)
	require.NotNil(t, doneStep.CompleteParams)
	require.Equal(t, networkid.UserLoginID("112233445566778899001"), doneStep.CompleteParams.UserLoginID)
	require.NotNil(t, doneStep.CompleteParams.UserLogin)
	require.Equal(t, "Ada Lovelace (ada@example.com)", doneStep.CompleteParams.UserLogin.RemoteName)
	meta, ok := doneStep.CompleteParams.UserLogin.Metadata.(*UserLoginMetadata)
	require.True(t, ok)
	require.Equal(t, "dynamite-ui=synthetic_compass+plus%2Bpct/slash=eq", meta.Cookies["COMPASS"])
	require.Equal(t, "synthetic_osid+plus%2Bpct/slash=eq", meta.Cookies["OSID"])
	require.Equal(t, "synthetic_sid+plus%2Bpct/slash=eq", meta.Cookies["SID"])

	gotCookieHdr, _ := lastCookieHeader.Load().(string)
	require.Contains(t, gotCookieHdr, "COMPASS=dynamite-ui=synthetic_compass+plus%2Bpct/slash=eq")
	require.Contains(t, gotCookieHdr, "OSID=synthetic_osid+plus%2Bpct/slash=eq")
	require.Contains(t, gotCookieHdr, "SID=synthetic_sid+plus%2Bpct/slash=eq")
}

func encodeDMGroupID(dmID string) []byte {
	return encodeBytesField(3, encodeStringField(1, dmID))
}

func encodeSpaceGroupID(spaceID string) []byte {
	return encodeBytesField(1, encodeStringField(1, spaceID))
}

func encodeTopicID(groupIDBytes []byte, topicID string) []byte {
	var out []byte
	out = append(out, encodeStringField(2, topicID)...)
	out = append(out, encodeBytesField(3, groupIDBytes)...)
	return out
}

func encodeMessageID(groupIDBytes []byte, topicID, msgID string) []byte {
	parent := encodeBytesField(4, encodeTopicID(groupIDBytes, topicID))
	var out []byte
	out = append(out, encodeBytesField(1, parent)...)
	out = append(out, encodeStringField(2, msgID)...)
	return out
}

func encodeSyntheticMessage(groupIDBytes []byte, topicID, msgID, senderGaiaID, text string, createTimeMicros int64, replyToMsgID string, boldStart, boldLen int) []byte {
	var msg []byte
	msg = append(msg, encodeBytesField(1, encodeMessageID(groupIDBytes, topicID, msgID))...)
	creator := encodeBytesField(1, encodeStringField(1, senderGaiaID))
	creator = append(creator, encodeStringField(2, "Grace Hopper")...)
	msg = append(msg, encodeBytesField(2, creator)...)
	msg = append(msg, encodeVarintField(3, uint64(createTimeMicros))...)
	msg = append(msg, encodeStringField(10, text)...)
	if boldLen > 0 {
		var ann []byte
		ann = append(ann, encodeVarintField(1, 8)...) // FORMAT_DATA
		ann = append(ann, encodeVarintField(2, uint64(boldStart))...)
		ann = append(ann, encodeVarintField(3, uint64(boldLen))...)
		fmtMeta := encodeVarintField(1, 1) // BOLD
		ann = append(ann, encodeBytesField(8, fmtMeta)...)
		msg = append(msg, encodeBytesField(11, ann)...)
	}
	if replyToMsgID != "" {
		replyTarget := encodeBytesField(1, encodeMessageID(groupIDBytes, topicID, replyToMsgID))
		replyTarget = append(replyTarget, encodeVarintField(2, uint64(createTimeMicros-1000))...)
		msg = append(msg, encodeBytesField(37, replyTarget)...)
	}
	return msg
}

func setupLoggedInGChatTestEnv(t *testing.T, apiHandler http.HandlerFunc) (*host.Host, *bridgev2.UserLogin, *Client) {
	t.Helper()
	enableTestLoopback(t)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			payload := buildSyntheticSelfUserStatusResponse("112233445566778899001")
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(payload)
		case "/u/0/api/get_members":
			payload := buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(payload)
		default:
			if apiHandler != nil {
				apiHandler(w, r)
				return
			}
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	ctx := context.Background()
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
	cookieLogin := proc.(bridgev2.LoginProcessCookies)
	doneStep, err := cookieLogin.SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
		"OSID":    "synthetic_osid",
		"SID":     "synthetic_sid",
		"HSID":    "synthetic_hsid",
		"SSID":    "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := doneStep.CompleteParams.UserLogin
	client, ok := ul.Client.(*Client)
	require.True(t, ok)
	return h, ul, client
}

func TestPaginatedWorldSyncsDMsAndSpacesWithThreadedMetadata(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			// Build 1 DM (dm_abc, peer 112233445566778899002) and 1 Space (space_xyz, name "Engineering", topic_threaded=true, group_revision=120)
			var dmItem []byte
			dmItem = append(dmItem, encodeBytesField(1, encodeDMGroupID("dm_abc"))...)
			dmItem = append(dmItem, encodeBytesField(2, encodeVarintField(1, 90))...)
			dmItem = append(dmItem, encodeVarintField(3, 1710000001000000)...)
			var dmReadState []byte
			dmReadState = append(dmReadState, encodeVarintField(16, 2)...) // MEMBER_JOINED
			dmReadState = append(dmReadState, encodeBytesField(23, encodeStringField(1, "112233445566778899001"))...)
			dmReadState = append(dmReadState, encodeBytesField(23, encodeStringField(1, "112233445566778899002"))...)
			dmItem = append(dmItem, encodeBytesField(4, dmReadState)...)
			var dmMembers []byte
			dmMembers = append(dmMembers, encodeBytesField(1, encodeStringField(1, "112233445566778899001"))...)
			dmMembers = append(dmMembers, encodeBytesField(1, encodeStringField(1, "112233445566778899002"))...)
			var membershipLite []byte
			membershipLite = append(membershipLite, encodeBytesField(1, encodeStringField(1, "112233445566778899002"))...)
			membershipLite = append(membershipLite, encodeVarintField(2, 2)...)
			dmMembers = append(dmMembers, encodeBytesField(2, membershipLite)...)
			dmItem = append(dmItem, encodeBytesField(6, dmMembers)...)

			var spaceItem []byte
			spaceItem = append(spaceItem, encodeBytesField(1, encodeSpaceGroupID("space_xyz"))...)
			spaceItem = append(spaceItem, encodeBytesField(2, encodeVarintField(1, 120))...)
			spaceItem = append(spaceItem, encodeVarintField(3, 1710000002000000)...)
			spaceReadState := encodeVarintField(16, 2) // MEMBER_JOINED
			spaceItem = append(spaceItem, encodeBytesField(4, spaceReadState)...)
			spaceItem = append(spaceItem, encodeStringField(5, "Engineering")...)
			spaceItem = append(spaceItem, encodeBytesField(15, nil)...) // threaded_group = ThreadedGroup{}

			var worldResp []byte
			worldResp = append(worldResp, encodeBytesField(3, encodeVarintField(1, 500))...) // user_revision = 500
			worldResp = append(worldResp, encodeBytesField(4, dmItem)...)
			worldResp = append(worldResp, encodeBytesField(4, spaceItem)...)

			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(worldResp)
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_abc"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)
	require.Equal(t, database.RoomTypeDM, dmPortal.RoomType)
	require.Equal(t, MakeUserID("112233445566778899002"), dmPortal.OtherUserID)

	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_xyz"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)
	require.Equal(t, database.RoomTypeDefault, spacePortal.RoomType)
	require.Equal(t, "Engineering", spacePortal.Name)

	spaceMeta, ok := spacePortal.Metadata.(*PortalMetadata)
	require.True(t, ok)
	require.True(t, spaceMeta.TopicThreaded)
	require.Equal(t, int64(120), spaceMeta.GroupRevision)

	loginMeta, ok := ul.Metadata.(*UserLoginMetadata)
	require.True(t, ok)
	require.Equal(t, int64(500), loginMeta.UserRevision)
}

func TestBackfillUsesListTopicsForSpacesAndListMessagesForDMs(t *testing.T) {
	ctx := context.Background()
	var mu sync.Mutex
	var listTopicsReqs [][]byte
	var listMessagesReqs [][]byte

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		switch r.URL.Path {
		case "/u/0/api/list_topics":
			mu.Lock()
			listTopicsReqs = append(listTopicsReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_xyz")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_1", "msg_1", "112233445566778899002", "Space topic head", 1710000010000000, "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, "topic_1"))...)
			topic = append(topic, encodeVarintField(2, 1710000010000000)...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			resp := encodeBytesField(1, topic)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/list_messages":
			mu.Lock()
			listMessagesReqs = append(listMessagesReqs, body)
			mu.Unlock()
			dmGID := encodeDMGroupID("dm_abc")
			msgBytes := encodeSyntheticMessage(dmGID, "dm_topic_1", "dm_msg_1", "112233445566778899002", "Hello in DM", 1710000020000000, "", 0, 0)
			resp := encodeBytesField(1, msgBytes)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		default:
			http.NotFound(w, r)
		}
	})

	spacePortal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_xyz"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	spacePortal.Metadata = &PortalMetadata{TopicThreaded: true, GroupRevision: 120}

	spaceBackfill, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
		Portal: spacePortal,
		Count:  30,
	})
	require.NoError(t, err)
	require.False(t, spaceBackfill.HasMore)
	require.False(t, spaceBackfill.MarkRead)
	require.Len(t, spaceBackfill.Messages, 1)
	require.Equal(t, MakeMessageID("topic_1", "msg_1"), spaceBackfill.Messages[0].ID)

	dmPortal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_abc"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	dmPortal.RoomType = database.RoomTypeDM

	dmBackfill, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
		Portal: dmPortal,
		Count:  50,
	})
	require.NoError(t, err)
	require.False(t, dmBackfill.HasMore)
	require.False(t, dmBackfill.MarkRead)
	require.Len(t, dmBackfill.Messages, 1)
	require.Equal(t, MakeMessageID("dm_topic_1", "dm_msg_1"), dmBackfill.Messages[0].ID)

	mu.Lock()
	defer mu.Unlock()
	require.Len(t, listTopicsReqs, 1, "space backfill must do a single list_topics request")
	require.Len(t, listMessagesReqs, 1, "DM backfill must do a single list_messages request")
	require.Equal(t, int64(30), decodeListTopicsPageSizeForTopics(listTopicsReqs[0]))
	require.Equal(t, int64(10), decodeListTopicsPageSizeForReplies(listTopicsReqs[0]))
	require.Equal(t, int64(50), decodeListMessagesPageSize(listMessagesReqs[0]))
}

func TestCatchUpUserAdvancesUserRevisionWithoutOverwritingGroupRevision(t *testing.T) {
	ctx := context.Background()
	var gotCatchUpUserFromRev atomic.Int64
	var gotCatchUpGroupFromRev atomic.Int64

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		switch r.URL.Path {
		case "/u/0/api/catch_up_user":
			gotCatchUpUserFromRev.Store(decodeCatchUpUserFromRevision(body))
			var evt []byte
			evt = append(evt, encodeVarintField(3, 40)...)                       // USER_NO_OP
			evt = append(evt, encodeBytesField(6, encodeVarintField(1, 650))...) // user_revision = 650
			var resp []byte
			resp = append(resp, encodeBytesField(1, evt)...)
			resp = append(resp, encodeVarintField(2, 1)...)                        // COMPLETED
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 650))...) // read_revision = 650
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/catch_up_group":
			gotCatchUpGroupFromRev.Store(decodeCatchUpGroupFromRevision(body))
			var evt []byte
			evt = append(evt, encodeBytesField(1, encodeSpaceGroupID("space_xyz"))...)
			evt = append(evt, encodeVarintField(3, 38)...)                       // GROUP_NO_OP
			evt = append(evt, encodeBytesField(7, encodeVarintField(1, 180))...) // group_revision = 180
			var resp []byte
			resp = append(resp, encodeBytesField(1, evt)...)
			resp = append(resp, encodeVarintField(2, 1)...)                        // COMPLETED
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 180))...) // read_revision = 180
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		default:
			http.NotFound(w, r)
		}
	})

	loginMeta := ul.Metadata.(*UserLoginMetadata)
	loginMeta.UserRevision = 500
	require.NoError(t, ul.Save(ctx))

	spacePortal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_xyz"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	spacePortal.Metadata = &PortalMetadata{TopicThreaded: true, GroupRevision: 120}
	require.NoError(t, spacePortal.Save(ctx))

	// 1. Reconnect triggers catch_up_user with from_revision = 500
	require.NoError(t, client.catchUpAfterReconnect(ctx))
	require.Equal(t, int64(500), gotCatchUpUserFromRev.Load())
	require.Equal(t, int64(650), ul.Metadata.(*UserLoginMetadata).UserRevision)
	require.Equal(t, int64(120), spacePortal.Metadata.(*PortalMetadata).GroupRevision, "catch_up_user must not overwrite portal group_revision")

	// 2. Per-portal catch_up_group advances group_revision to 180 without touching user_revision
	require.NoError(t, client.catchUpGroup(ctx, spacePortal))
	require.Equal(t, int64(120), gotCatchUpGroupFromRev.Load())
	require.Equal(t, int64(180), spacePortal.Metadata.(*PortalMetadata).GroupRevision)
	require.Equal(t, int64(650), ul.Metadata.(*UserLoginMetadata).UserRevision)
}

func TestLiveWebChannelEventsMapMessagesReactionsEditsUnsendsReceiptsAndTyping(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)

	spaceGID := encodeSpaceGroupID("space_xyz")

	// 1. MESSAGE_POSTED (with TopicId, SendReplyTarget quote reply, and Annotations)
	postedMsg := encodeSyntheticMessage(spaceGID, "topic_77", "msg_100", "112233445566778899002", "Hello bold world", 1710000100000000, "msg_99", 6, 4)
	var body1 []byte
	body1 = append(body1, encodeBytesField(6, encodeBytesField(1, postedMsg))...)
	body1 = append(body1, encodeVarintField(12, 6)...) // MESSAGE_POSTED

	// 2. MESSAGE_UPDATED (edit)
	editedMsg := encodeSyntheticMessage(spaceGID, "topic_77", "msg_100", "112233445566778899002", "Hello edited world", 1710000100000000, "", 6, 6)
	editedMsg = append(editedMsg, encodeVarintField(17, 1710000105000000)...) // last_edit_time
	var body2 []byte
	body2 = append(body2, encodeBytesField(6, encodeBytesField(1, editedMsg))...)
	body2 = append(body2, encodeVarintField(12, 7)...) // MESSAGE_UPDATED

	// 3. MESSAGE_DELETED (unsend)
	var delEvt []byte
	delEvt = append(delEvt, encodeBytesField(1, encodeMessageID(spaceGID, "topic_77", "msg_100"))...)
	delEvt = append(delEvt, encodeVarintField(2, 1710000110000000)...)
	var body3 []byte
	body3 = append(body3, encodeBytesField(18, delEvt)...)
	body3 = append(body3, encodeVarintField(12, 8)...) // MESSAGE_DELETED

	// 4a. REACTION_CREATED (ADD = 1) with bare "❤" (U+2764 without U+FE0F)
	var reactAdd []byte
	reactAdd = append(reactAdd, encodeBytesField(1, encodeMessageID(spaceGID, "topic_77", "msg_100"))...)
	reactAdd = append(reactAdd, encodeBytesField(2, encodeStringField(1, "\u2764"))...)
	reactAdd = append(reactAdd, encodeBytesField(3, encodeStringField(1, "112233445566778899002"))...)
	reactAdd = append(reactAdd, encodeVarintField(4, 1710000115000000)...)
	reactAdd = append(reactAdd, encodeVarintField(5, 1)...) // ADD
	var body4a []byte
	body4a = append(body4a, encodeBytesField(22, reactAdd)...)
	body4a = append(body4a, encodeVarintField(12, 24)...) // MESSAGE_REACTED

	// 4b. REACTION_DELETED (REMOVE = 2)
	var reactRem []byte
	reactRem = append(reactRem, encodeBytesField(1, encodeMessageID(spaceGID, "topic_77", "msg_100"))...)
	reactRem = append(reactRem, encodeBytesField(2, encodeStringField(1, "\u2764"))...)
	reactRem = append(reactRem, encodeBytesField(3, encodeStringField(1, "112233445566778899002"))...)
	reactRem = append(reactRem, encodeVarintField(4, 1710000116000000)...)
	reactRem = append(reactRem, encodeVarintField(5, 2)...) // REMOVE
	var body4b []byte
	body4b = append(body4b, encodeBytesField(22, reactRem)...)
	body4b = append(body4b, encodeVarintField(12, 24)...) // MESSAGE_REACTED

	// 5. GROUP_READ_STATE_UPDATED (field 65, event_type = 83)
	var readStateUpdated []byte
	readStateUpdated = append(readStateUpdated, encodeBytesField(1, spaceGID)...)
	readStateUpdated = append(readStateUpdated, encodeVarintField(3, 1710000120000000)...) // most_recent_read_time
	var body5 []byte
	body5 = append(body5, encodeBytesField(65, readStateUpdated)...)
	body5 = append(body5, encodeVarintField(12, 83)...) // GROUP_READ_STATE_UPDATED

	// 6. TYPING_STATE_CHANGED (STATE_TYPING = 1 -> 6s typing notification)
	var typingEvt []byte
	typingEvt = append(typingEvt, encodeVarintField(1, 1)...) // TYPING
	typingEvt = append(typingEvt, encodeBytesField(2, encodeStringField(1, "112233445566778899002"))...)
	typingEvt = append(typingEvt, encodeBytesField(3, encodeBytesField(1, spaceGID))...) // context.group_id
	typingEvt = append(typingEvt, encodeVarintField(4, 1710000125000000)...)
	var body6 []byte
	body6 = append(body6, encodeBytesField(26, typingEvt)...)
	body6 = append(body6, encodeVarintField(12, 29)...) // TYPING_STATE_CHANGED

	// 7. MEMBERSHIP_CHANGED (field 14, event_type = 15)
	var memID []byte
	memID = append(memID, encodeBytesField(1, encodeBytesField(1, encodeStringField(1, "112233445566778899003")))...)
	memID = append(memID, encodeBytesField(2, spaceGID)...)
	var membership []byte
	membership = append(membership, encodeBytesField(1, memID)...)
	membership = append(membership, encodeVarintField(3, 2)...) // MEMBER_JOINED
	var memChanged []byte
	memChanged = append(memChanged, encodeBytesField(1, membership)...)
	var body7 []byte
	body7 = append(body7, encodeBytesField(14, memChanged)...)
	body7 = append(body7, encodeVarintField(12, 15)...) // MEMBERSHIP_CHANGED

	var evt []byte
	evt = append(evt, encodeBytesField(1, spaceGID)...)
	evt = append(evt, encodeVarintField(3, 6)...)
	evt = append(evt, encodeBytesField(4, body1)...)
	evt = append(evt, encodeBytesField(8, body2)...)
	evt = append(evt, encodeBytesField(8, body3)...)
	evt = append(evt, encodeBytesField(8, body4a)...)
	evt = append(evt, encodeBytesField(8, body4b)...)
	evt = append(evt, encodeBytesField(8, body5)...)
	evt = append(evt, encodeBytesField(8, body6)...)
	evt = append(evt, encodeBytesField(8, body7)...)

	remoteEvts, err := client.translateWebChannelEvent(ctx, evt)
	require.NoError(t, err)
	require.Len(t, remoteEvts, 8)

	// 1. MESSAGE_POSTED
	msgEvt, ok := remoteEvts[0].(*simplevent.PreConvertedMessage)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventMessage, msgEvt.GetType())
	require.Equal(t, MakeSpacePortalID("space_xyz"), msgEvt.GetPortalKey().ID)
	require.Equal(t, MakeMessageID("topic_77", "msg_100"), msgEvt.ID)
	require.NotNil(t, msgEvt.Data.ThreadRoot)
	require.Equal(t, MakeThreadRootID("topic_77"), *msgEvt.Data.ThreadRoot)
	require.NotNil(t, msgEvt.Data.ReplyTo)
	require.Equal(t, MakeMessageID("topic_77", "msg_99"), msgEvt.Data.ReplyTo.MessageID)
	require.Len(t, msgEvt.Data.Parts, 1)
	require.Equal(t, "Hello <strong>bold</strong> world", msgEvt.Data.Parts[0].Content.FormattedBody)

	// 2. MESSAGE_UPDATED
	editEvt, ok := remoteEvts[1].(bridgev2.RemoteEdit)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventEdit, editEvt.GetType())
	require.Equal(t, MakeMessageID("topic_77", "msg_100"), editEvt.GetTargetMessage())

	// 3. MESSAGE_DELETED
	delRemoteEvt, ok := remoteEvts[2].(*simplevent.MessageRemove)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventMessageRemove, delRemoteEvt.GetType())
	require.Equal(t, MakeMessageID("topic_77", "msg_100"), delRemoteEvt.TargetMessage)

	// 4a. REACTION_CREATED -> "❤️" normalized with U+FE0F
	reactAddEvt, ok := remoteEvts[3].(*simplevent.Reaction)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventReaction, reactAddEvt.GetType())
	require.Equal(t, MakeMessageID("topic_77", "msg_100"), reactAddEvt.TargetMessage)
	require.Equal(t, "❤️", reactAddEvt.Emoji)
	require.Equal(t, networkid.EmojiID("\u2764"), reactAddEvt.EmojiID)

	// 4b. REACTION_DELETED
	reactRemEvt, ok := remoteEvts[4].(*simplevent.Reaction)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventReactionRemove, reactRemEvt.GetType())
	require.Equal(t, MakeMessageID("topic_77", "msg_100"), reactRemEvt.TargetMessage)

	// 5. GROUP_READ_STATE_UPDATED
	receiptEvt, ok := remoteEvts[5].(*simplevent.Receipt)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventReadReceipt, receiptEvt.GetType())
	require.Equal(t, time.UnixMicro(1710000120000000), receiptEvt.ReadUpTo)

	// 6. TYPING_STATE_CHANGED
	typingRemoteEvt, ok := remoteEvts[6].(*simplevent.Typing)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventTyping, typingRemoteEvt.GetType())
	require.Equal(t, 6*time.Second, typingRemoteEvt.Timeout)

	// 7. MEMBERSHIP_CHANGED
	memRemoteEvt, ok := remoteEvts[7].(*simplevent.ChatInfoChange)
	require.True(t, ok)
	require.Equal(t, bridgev2.RemoteEventChatInfoChange, memRemoteEvt.GetType())
	require.NotNil(t, memRemoteEvt.ChatInfoChange)
	require.NotNil(t, memRemoteEvt.ChatInfoChange.MemberChanges)
	_, hasNewMember := memRemoteEvt.ChatInfoChange.MemberChanges.MemberMap[MakeUserID("112233445566778899003")]
	require.True(t, hasNewMember)
	_ = event.MembershipJoin
}
