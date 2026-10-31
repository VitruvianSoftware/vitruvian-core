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
	"os"
	"path/filepath"
	"reflect"
	"strings"
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
	"maunium.net/go/mautrix/bridgev2/status"
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

			// Blocked DM (field 15 = 1 in GroupReadState): must be skipped
			var blockedDM []byte
			blockedDM = append(blockedDM, encodeBytesField(1, encodeDMGroupID("dm_blocked"))...)
			blockedDM = append(blockedDM, encodeVarintField(3, 1710000009000000)...)
			var blockedRS []byte
			blockedRS = append(blockedRS, encodeVarintField(15, 1)...) // blocked = true
			blockedRS = append(blockedRS, encodeVarintField(16, 2)...) // MEMBER_JOINED
			blockedDM = append(blockedDM, encodeBytesField(4, blockedRS)...)

			// Hidden DM (field 9 > 0 in GroupReadState): must be skipped
			var hiddenDM []byte
			hiddenDM = append(hiddenDM, encodeBytesField(1, encodeDMGroupID("dm_hidden"))...)
			hiddenDM = append(hiddenDM, encodeVarintField(3, 1710000008000000)...)
			var hiddenRS []byte
			hiddenRS = append(hiddenRS, encodeVarintField(9, 1710000000000000)...) // hide_timestamp > 0
			hiddenRS = append(hiddenRS, encodeVarintField(16, 2)...)               // MEMBER_JOINED
			hiddenDM = append(hiddenDM, encodeBytesField(4, hiddenRS)...)

			// Non-joined Space (field 16 = 1 MEMBER_INVITED in GroupReadState): must be skipped
			var invitedSpace []byte
			invitedSpace = append(invitedSpace, encodeBytesField(1, encodeSpaceGroupID("space_invited"))...)
			invitedSpace = append(invitedSpace, encodeVarintField(3, 1710000007000000)...)
			invitedSpace = append(invitedSpace, encodeBytesField(4, encodeVarintField(16, 1))...) // MEMBER_INVITED != 2

			// Old joined space placed FIRST on the wire with low sort_timestamp (100), plus 29 filler joined spaces
			// with higher sort_timestamps so total joined rooms = 31 (> 30 cap).
			var oldSpace []byte
			oldSpace = append(oldSpace, encodeBytesField(1, encodeSpaceGroupID("space_old_31"))...)
			oldSpace = append(oldSpace, encodeVarintField(3, 100)...)
			oldSpace = append(oldSpace, encodeBytesField(4, encodeVarintField(16, 2))...)
			oldSpace = append(oldSpace, encodeStringField(5, "Old Archive")...)

			var worldResp []byte
			worldResp = append(worldResp, encodeBytesField(3, encodeVarintField(1, 500))...) // user_revision = 500
			worldResp = append(worldResp, encodeBytesField(4, blockedDM)...)
			worldResp = append(worldResp, encodeBytesField(4, hiddenDM)...)
			worldResp = append(worldResp, encodeBytesField(4, invitedSpace)...)
			worldResp = append(worldResp, encodeBytesField(4, oldSpace)...)
			for i := 1; i <= 28; i++ {
				var filler []byte
				filler = append(filler, encodeBytesField(1, encodeSpaceGroupID(fmt.Sprintf("space_filler_%02d", i)))...)
				filler = append(filler, encodeVarintField(3, uint64(1710000000000000+i*1000))...)
				filler = append(filler, encodeBytesField(4, encodeVarintField(16, 2))...)
				filler = append(filler, encodeStringField(5, fmt.Sprintf("Filler %02d", i))...)
				worldResp = append(worldResp, encodeBytesField(4, filler)...)
			}
			worldResp = append(worldResp, encodeBytesField(4, dmItem)...)
			worldResp = append(worldResp, encodeBytesField(4, spaceItem)...)

			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(worldResp)
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	// Blocked, hidden, non-joined, and >30th oldest joined room must NOT be created.
	for _, skippedID := range []networkid.PortalID{
		MakeDMPortalID("dm_blocked"),
		MakeDMPortalID("dm_hidden"),
		MakeSpacePortalID("space_invited"),
		MakeSpacePortalID("space_old_31"),
	} {
		p, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{ID: skippedID, Receiver: ul.ID})
		require.NoError(t, err)
		require.Nil(t, p, "expected portal %s to be filtered/capped out", skippedID)
	}

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
	var abortCatchUpUser atomic.Bool
	var worldSyncFallbackCalls atomic.Int64

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		spaceGID := encodeSpaceGroupID("space_xyz")
		switch r.URL.Path {
		case "/u/0/api/catch_up_user":
			gotCatchUpUserFromRev.Store(decodeCatchUpUserFromRevision(body))
			if abortCatchUpUser.Load() {
				var resp []byte
				resp = append(resp, encodeVarintField(2, 3)...) // ABORTED_CUTOFF_EXCEEDED
				w.Header().Set("Content-Type", "application/x-protobuf")
				_, _ = w.Write(resp)
				return
			}
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_cu", "msg_cu_user_1", "112233445566778899002", "Caught up user message", 1710000050000000, "", 0, 0)
			var evtBody []byte
			evtBody = append(evtBody, encodeBytesField(6, encodeBytesField(1, msgBytes))...)
			evtBody = append(evtBody, encodeVarintField(12, 6)...) // MESSAGE_POSTED
			var evt []byte
			evt = append(evt, encodeBytesField(1, spaceGID)...)
			evt = append(evt, encodeVarintField(3, 6)...)
			evt = append(evt, encodeBytesField(4, evtBody)...)
			evt = append(evt, encodeBytesField(6, encodeVarintField(1, 650))...) // user_revision = 650
			var resp []byte
			resp = append(resp, encodeBytesField(1, evt)...)
			resp = append(resp, encodeVarintField(2, 1)...)                        // COMPLETED
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 650))...) // read_revision = 650
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/catch_up_group":
			gotCatchUpGroupFromRev.Store(decodeCatchUpGroupFromRevision(body))
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_cu", "msg_cu_group_1", "112233445566778899002", "Caught up group message", 1710000060000000, "", 0, 0)
			var evtBody []byte
			evtBody = append(evtBody, encodeBytesField(6, encodeBytesField(1, msgBytes))...)
			evtBody = append(evtBody, encodeVarintField(12, 6)...) // MESSAGE_POSTED
			var evt []byte
			evt = append(evt, encodeBytesField(1, spaceGID)...)
			evt = append(evt, encodeVarintField(3, 6)...)
			evt = append(evt, encodeBytesField(4, evtBody)...)
			evt = append(evt, encodeBytesField(7, encodeVarintField(1, 180))...) // group_revision = 180
			var resp []byte
			resp = append(resp, encodeBytesField(1, evt)...)
			resp = append(resp, encodeVarintField(2, 1)...)                        // COMPLETED
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 180))...) // read_revision = 180
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/paginated_world":
			worldSyncFallbackCalls.Add(1)
			var worldResp []byte
			worldResp = append(worldResp, encodeBytesField(3, encodeVarintField(1, 900))...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(worldResp)
		case "/u/0/api/list_topics", "/u/0/api/list_messages":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(nil)
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

	// 1. Reconnect triggers catch_up_user with from_revision = 500, translates & dispatches caught-up events
	require.NoError(t, client.catchUpAfterReconnect(ctx))
	require.Equal(t, int64(500), gotCatchUpUserFromRev.Load())
	require.Equal(t, int64(650), ul.Metadata.(*UserLoginMetadata).UserRevision)
	require.Equal(t, int64(120), spacePortal.Metadata.(*PortalMetadata).GroupRevision, "catch_up_user must not overwrite portal group_revision")

	require.Eventually(t, func() bool {
		msg, err := h.Bridge.DB.Message.GetFirstPartByID(ctx, ul.ID, MakeMessageID("topic_cu", "msg_cu_user_1"))
		return err == nil && msg != nil
	}, 2*time.Second, 20*time.Millisecond, "catch_up_user must translate and dispatch caught-up MESSAGE_POSTED event")

	// 2. Per-portal catch_up_group translates & dispatches group events and advances group_revision to 180
	require.NoError(t, client.catchUpGroup(ctx, spacePortal))
	require.Equal(t, int64(120), gotCatchUpGroupFromRev.Load())
	require.Equal(t, int64(180), spacePortal.Metadata.(*PortalMetadata).GroupRevision)
	require.Equal(t, int64(650), ul.Metadata.(*UserLoginMetadata).UserRevision)

	require.Eventually(t, func() bool {
		msg, err := h.Bridge.DB.Message.GetFirstPartByID(ctx, ul.ID, MakeMessageID("topic_cu", "msg_cu_group_1"))
		return err == nil && msg != nil
	}, 2*time.Second, 20*time.Millisecond, "catch_up_group must translate and dispatch caught-up MESSAGE_POSTED event")

	// 3. ABORTED_CUTOFF_EXCEEDED (status = 3) falls back to syncWorld (paginated_world)
	abortCatchUpUser.Store(true)
	require.NoError(t, client.catchUpAfterReconnect(ctx))
	require.Equal(t, int64(1), worldSyncFallbackCalls.Load(), "ABORTED_CUTOFF_EXCEEDED must fall back to syncWorld")
	require.Equal(t, int64(900), ul.Metadata.(*UserLoginMetadata).UserRevision)
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

func TestEndToEndConnectSyncStreamReconnectCatchUpAndBadCredentials(t *testing.T) {
	enableTestLoopback(t)
	ctx := context.Background()

	var authExpired401 atomic.Bool
	var registerCalls atomic.Int64
	var worldSyncCalls atomic.Int64
	var catchUpUserCalls atomic.Int64
	var e2eCreateTopicCalls atomic.Int64
	var e2eCreateMsgCalls atomic.Int64
	var e2eEditCalls atomic.Int64
	var e2eDeleteCalls atomic.Int64
	var e2eReactionCalls atomic.Int64
	var e2eReadStateCalls atomic.Int64
	var e2eTypingCalls atomic.Int64
	var pollStep atomic.Int64
	trigger401Ch := make(chan struct{})

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if authExpired401.Load() {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticSelfUserStatusResponse("112233445566778899001"))
		case "/u/0/api/get_members":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			))
		case "/u/0/api/paginated_world":
			worldSyncCalls.Add(1)
			var spaceItem []byte
			spaceItem = append(spaceItem, encodeBytesField(1, encodeSpaceGroupID("space_xyz"))...)
			spaceItem = append(spaceItem, encodeBytesField(2, encodeVarintField(1, 120))...)
			spaceItem = append(spaceItem, encodeVarintField(3, 1710000002000000)...)
			spaceItem = append(spaceItem, encodeBytesField(4, encodeVarintField(16, 2))...) // MEMBER_JOINED
			spaceItem = append(spaceItem, encodeStringField(5, "Engineering")...)
			spaceItem = append(spaceItem, encodeBytesField(15, nil)...)

			var worldResp []byte
			worldResp = append(worldResp, encodeBytesField(3, encodeVarintField(1, 500))...) // user_revision = 500
			worldResp = append(worldResp, encodeBytesField(4, spaceItem)...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(worldResp)
		case "/u/0/api/list_topics", "/u/0/api/list_messages":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(nil)
		case "/u/0/webchannel/register":
			n := registerCalls.Add(1)
			gs := fmt.Sprintf("gsession_%d", n)
			w.Header().Set("X-HTTP-Session-Id", gs)
			_, _ = fmt.Fprint(w, gs)
		case "/u/0/webchannel/events_encoded":
			if r.Method == http.MethodPost {
				body, _ := io.ReadAll(r.Body)
				if strings.HasPrefix(string(body), "count=0") {
					sidFrame := fmt.Sprintf(`[[0,["c","sid_%d","",8]]]`, registerCalls.Load())
					framed := fmt.Sprintf("%d\n%s", len([]rune(sidFrame)), sidFrame)
					_, _ = fmt.Fprint(w, framed)
					return
				}
				w.WriteHeader(http.StatusOK)
				return
			}
			// GET long-poll stream
			step := pollStep.Add(1)
			switch step {
			case 1:
				// Case 1: Push live MESSAGE_POSTED event over WebChannel
				eventChunk := `[[1,[[[[["space_xyz"]],null,6,[null,null,null,null,null,[[[[null,null,null,[null,"topic_1",[["space_xyz"]]]],"msg_live_1"],[["112233445566778899002",0]],"1710000200000000",null,null,null,null,null,null,"Live hello from WebChannel"]],null,null,null,null,null,6],null,["550"],["150"]]]]]]`
				framed := fmt.Sprintf("%d\n%s", len([]rune(eventChunk)), eventChunk)
				_, _ = fmt.Fprint(w, framed)
			case 2:
				// Case 2: Drop the stream (400 Unknown SID triggers reconnect with backoff + catch_up_user)
				http.Error(w, "Unknown SID", http.StatusBadRequest)
			default:
				// Wait until Case 3 signals 401
				select {
				case <-r.Context().Done():
					return
				case <-trigger401Ch:
					http.Error(w, "Unauthorized", http.StatusUnauthorized)
				}
			}
		case "/u/0/api/catch_up_user":
			catchUpUserCalls.Add(1)
			spaceGID := encodeSpaceGroupID("space_xyz")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_1", "msg_missed_1", "112233445566778899002", "Missed while stream was down", 1710000300000000, "", 0, 0)
			var evtBody []byte
			evtBody = append(evtBody, encodeBytesField(6, encodeBytesField(1, msgBytes))...)
			evtBody = append(evtBody, encodeVarintField(12, 6)...) // MESSAGE_POSTED
			var evt []byte
			evt = append(evt, encodeBytesField(1, spaceGID)...)
			evt = append(evt, encodeVarintField(3, 6)...)
			evt = append(evt, encodeBytesField(4, evtBody)...)
			// Include the same missed message a second time in bodies (field 8) to prove at-most-once deduplication!
			evt = append(evt, encodeBytesField(8, evtBody)...)
			evt = append(evt, encodeBytesField(6, encodeVarintField(1, 700))...)
			var resp []byte
			resp = append(resp, encodeBytesField(1, evt)...)
			resp = append(resp, encodeVarintField(2, 1)...) // COMPLETED
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 700))...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/create_topic":
			e2eCreateTopicCalls.Add(1)
			spaceGID := encodeSpaceGroupID("space_xyz")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_e2e", "msg_e2e_1", "112233445566778899001", "E2E top", 1710000400000000, "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, "topic_e2e"))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/create_message":
			e2eCreateMsgCalls.Add(1)
			spaceGID := encodeSpaceGroupID("space_xyz")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_e2e", "msg_e2e_2", "112233445566778899001", "E2E reply", 1710000410000000, "msg_e2e_1", 0, 0)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/edit_message":
			e2eEditCalls.Add(1)
			spaceGID := encodeSpaceGroupID("space_xyz")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_e2e", "msg_e2e_1", "112233445566778899001", "E2E edited", 1710000400000000, "", 0, 0)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/delete_message":
			e2eDeleteCalls.Add(1)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeVarintField(4, 1710000420000000))
		case "/u/0/api/update_reaction":
			e2eReactionCalls.Add(1)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, encodeVarintField(1, 710)))
		case "/u/0/api/mark_group_readstate":
			e2eReadStateCalls.Add(1)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 711)))
		case "/u/0/api/set_typing_state":
			e2eTypingCalls.Add(1)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeVarintField(1, 1710000430000000))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	conn := &Connector{
		baseURL:        srv.URL,
		useManualClock: true,
		manualJitter:   0.2,
	}
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

	// Case 1: Connect logs in from cookies, runs initial world sync, opens WebChannel stream,
	// fake server pushes a message event, and bridgev2 remote message event is emitted with the right room, sender, and text.
	require.Eventually(t, func() bool {
		msg, err := h.Bridge.DB.Message.GetFirstPartByID(ctx, ul.ID, MakeMessageID("topic_1", "msg_live_1"))
		return err == nil && msg != nil
	}, 3*time.Second, 20*time.Millisecond, "Connect must sync world, open WebChannel stream, and deliver live message")

	require.Equal(t, int64(1), worldSyncCalls.Load(), "Connect must run initial world sync once")
	recorded := client.recordedRemoteEvents()
	require.Len(t, recorded, 1)
	liveEvt, ok := recorded[0].(*simplevent.PreConvertedMessage)
	require.True(t, ok)
	require.Equal(t, MakeSpacePortalID("space_xyz"), liveEvt.GetPortalKey().ID)
	require.Equal(t, MakeUserID("112233445566778899002"), liveEvt.GetSender().Sender)
	require.Len(t, liveEvt.Data.Parts, 1)
	require.Equal(t, "Live hello from WebChannel", liveEvt.Data.Parts[0].Content.Body)

	// Case 2: Stream dropped on step 2 -> client is waiting in backoff on injected clock; catch_up_user has not run yet.
	require.Eventually(t, func() bool {
		return pollStep.Load() >= 2
	}, 2*time.Second, 20*time.Millisecond)
	require.Equal(t, int64(0), catchUpUserCalls.Load(), "reconnect must wait for injected backoff clock before running catch-up")

	// Advance injected clock past 1050ms backoff (1s + 5% jitter) -> client reconnects, runs catch_up_user, and delivers missed message exactly once.
	client.advanceManualClock(1100 * time.Millisecond)

	require.Eventually(t, func() bool {
		msg, err := h.Bridge.DB.Message.GetFirstPartByID(ctx, ul.ID, MakeMessageID("topic_1", "msg_missed_1"))
		return err == nil && msg != nil
	}, 3*time.Second, 20*time.Millisecond, "reconnect must run catch_up_user and deliver missed message")

	require.Equal(t, int64(1), catchUpUserCalls.Load())
	recordedAfterCatchUp := client.recordedRemoteEvents()
	var missedDeliveries int
	for _, ev := range recordedAfterCatchUp {
		if m, ok := ev.(*simplevent.PreConvertedMessage); ok && m.ID == MakeMessageID("topic_1", "msg_missed_1") {
			missedDeliveries++
			require.Equal(t, MakeSpacePortalID("space_xyz"), m.GetPortalKey().ID)
			require.Equal(t, MakeUserID("112233445566778899002"), m.GetSender().Sender)
			require.Equal(t, "Missed while stream was down", m.Data.Parts[0].Content.Body)
		}
	}
	require.Equal(t, 1, missedDeliveries, "missed message must be delivered exactly once")

	// Case 2b: Outbound actions on the live connected client through the E2E harness.
	e2ePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_xyz"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, e2ePortal)
	e2eTop, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  e2ePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "E2E top"},
		},
	})
	require.NoError(t, err)
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  e2ePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "E2E reply"},
		},
		ThreadRoot: e2eTop.DB,
		ReplyTo:    e2eTop.DB,
	})
	require.NoError(t, err)
	require.NoError(t, client.HandleMatrixEdit(ctx, &bridgev2.MatrixEdit{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  e2ePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "E2E edited"},
		},
		EditTarget: e2eTop.DB,
	}))
	rxnPre, err := client.PreHandleMatrixReaction(ctx, &bridgev2.MatrixReaction{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.ReactionEventContent]{
			Portal:  e2ePortal,
			Content: &event.ReactionEventContent{RelatesTo: event.RelatesTo{Key: "❤️"}},
		},
		TargetMessage: e2eTop.DB,
	})
	require.NoError(t, err)
	dbRxn, err := client.HandleMatrixReaction(ctx, &bridgev2.MatrixReaction{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.ReactionEventContent]{
			Portal:  e2ePortal,
			Content: &event.ReactionEventContent{RelatesTo: event.RelatesTo{Key: "❤️"}},
		},
		TargetMessage: e2eTop.DB,
		PreHandleResp: &rxnPre,
	})
	require.NoError(t, err)
	require.NoError(t, client.HandleMatrixReactionRemove(ctx, &bridgev2.MatrixReactionRemove{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{Portal: e2ePortal},
		TargetReaction: &database.Reaction{
			Room:      e2ePortal.PortalKey,
			MessageID: e2eTop.DB.ID,
			EmojiID:   dbRxn.EmojiID,
			Emoji:     dbRxn.Emoji,
			Metadata:  dbRxn.Metadata,
		},
	}))
	require.NoError(t, client.HandleMatrixMessageRemove(ctx, &bridgev2.MatrixMessageRemove{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{Portal: e2ePortal},
		TargetMessage:   e2eTop.DB,
	}))
	require.NoError(t, client.HandleMatrixReadReceipt(ctx, &bridgev2.MatrixReadReceipt{
		Portal:   e2ePortal,
		ReadUpTo: time.UnixMicro(1710000450000000),
	}))
	require.NoError(t, client.HandleMatrixTyping(ctx, &bridgev2.MatrixTyping{Portal: e2ePortal, IsTyping: true}))
	require.NoError(t, client.HandleMatrixTyping(ctx, &bridgev2.MatrixTyping{Portal: e2ePortal, IsTyping: false}))
	require.Equal(t, int64(1), e2eCreateTopicCalls.Load())
	require.Equal(t, int64(1), e2eCreateMsgCalls.Load())
	require.Equal(t, int64(1), e2eEditCalls.Load())
	require.Equal(t, int64(1), e2eDeleteCalls.Load())
	require.Equal(t, int64(2), e2eReactionCalls.Load())
	require.Equal(t, int64(1), e2eReadStateCalls.Load())
	require.Equal(t, int64(2), e2eTypingCalls.Load())

	// Case 3: Fake server answers 401 -> login transitions to BAD_CREDENTIALS.
	authExpired401.Store(true)
	close(trigger401Ch)

	require.Eventually(t, func() bool {
		return client.lastBridgeState() == status.StateBadCredentials && !client.IsLoggedIn()
	}, 3*time.Second, 20*time.Millisecond, "401 response must transition login to BAD_CREDENTIALS")
}

func buildSendTestPaginatedWorldResponse() []byte {
	var dmItem []byte
	dmItem = append(dmItem, encodeBytesField(1, encodeDMGroupID("dm_alpha"))...)
	dmItem = append(dmItem, encodeBytesField(2, encodeVarintField(1, 90))...)
	dmItem = append(dmItem, encodeVarintField(3, 1710000001000000)...)
	var dmRS []byte
	dmRS = append(dmRS, encodeVarintField(16, 2)...) // MEMBER_JOINED
	dmRS = append(dmRS, encodeBytesField(23, encodeStringField(1, "112233445566778899001"))...)
	dmRS = append(dmRS, encodeBytesField(23, encodeStringField(1, "112233445566778899002"))...)
	dmItem = append(dmItem, encodeBytesField(4, dmRS)...)

	var unthreadedSpace []byte
	unthreadedSpace = append(unthreadedSpace, encodeBytesField(1, encodeSpaceGroupID("space_unthreaded"))...)
	unthreadedSpace = append(unthreadedSpace, encodeBytesField(2, encodeVarintField(1, 110))...)
	unthreadedSpace = append(unthreadedSpace, encodeVarintField(3, 1710000002000000)...)
	unthreadedSpace = append(unthreadedSpace, encodeBytesField(4, encodeVarintField(16, 2))...)
	unthreadedSpace = append(unthreadedSpace, encodeStringField(5, "Unthreaded General")...)

	var flatThreadsSpace []byte
	flatThreadsSpace = append(flatThreadsSpace, encodeBytesField(1, encodeSpaceGroupID("space_flat_threads"))...)
	flatThreadsSpace = append(flatThreadsSpace, encodeBytesField(2, encodeVarintField(1, 115))...)
	flatThreadsSpace = append(flatThreadsSpace, encodeVarintField(3, 1710000002500000)...)
	flatThreadsSpace = append(flatThreadsSpace, encodeBytesField(4, encodeVarintField(16, 2))...)
	flatThreadsSpace = append(flatThreadsSpace, encodeStringField(5, "Flat Threads Eng")...)
	flatThreadsSpace = append(flatThreadsSpace, encodeVarintField(27, 1)...) // flat_threads_enabled = true

	var threadedSpace []byte
	threadedSpace = append(threadedSpace, encodeBytesField(1, encodeSpaceGroupID("space_threaded"))...)
	threadedSpace = append(threadedSpace, encodeBytesField(2, encodeVarintField(1, 120))...)
	threadedSpace = append(threadedSpace, encodeVarintField(3, 1710000003000000)...)
	threadedSpace = append(threadedSpace, encodeBytesField(4, encodeVarintField(16, 2))...)
	threadedSpace = append(threadedSpace, encodeStringField(5, "Threaded Eng")...)
	threadedSpace = append(threadedSpace, encodeBytesField(15, nil)...) // threaded_group = ThreadedGroup{}

	var worldResp []byte
	worldResp = append(worldResp, encodeBytesField(3, encodeVarintField(1, 500))...)
	worldResp = append(worldResp, encodeBytesField(4, dmItem)...)
	worldResp = append(worldResp, encodeBytesField(4, unthreadedSpace)...)
	worldResp = append(worldResp, encodeBytesField(4, flatThreadsSpace)...)
	worldResp = append(worldResp, encodeBytesField(4, threadedSpace)...)
	return worldResp
}

func TestSendNewTopicInThreadedSpaceAndCreateMessageInThreadOrDM(t *testing.T) {
	enableTestLoopback(t)
	ctx := context.Background()

	var (
		mu              sync.Mutex
		createTopicReqs [][]byte
		createMsgReqs   [][]byte
	)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticSelfUserStatusResponse("112233445566778899001"))
		case "/u/0/api/get_members":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			))
		case "/u/0/api/paginated_world":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_topic":
			body, _ := io.ReadAll(r.Body)
			mu.Lock()
			idx := len(createTopicReqs) + 1
			createTopicReqs = append(createTopicReqs, body)
			mu.Unlock()

			spaceGID := encodeSpaceGroupID("space_threaded")
			topicIDStr := fmt.Sprintf("topic_new_%d", idx)
			msgIDStr := fmt.Sprintf("msg_new_%d", idx)
			msgBytes := encodeSyntheticMessage(spaceGID, topicIDStr, msgIDStr, "112233445566778899001", "Hello 🚀", 1710000500000000+int64(idx), "", 0, 0)
			var topicIDProto []byte
			topicIDProto = append(topicIDProto, encodeStringField(2, topicIDStr)...)
			topicIDProto = append(topicIDProto, encodeBytesField(3, spaceGID)...)
			var topicProto []byte
			topicProto = append(topicProto, encodeBytesField(1, topicIDProto)...)
			topicProto = append(topicProto, encodeVarintField(2, uint64(1710000500000000+idx))...)
			topicProto = append(topicProto, encodeBytesField(7, msgBytes)...)
			topicProto = append(topicProto, encodeVarintField(15, uint64(1710000500000000+idx))...)
			resp := encodeBytesField(1, topicProto)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/create_message":
			body, _ := io.ReadAll(r.Body)
			mu.Lock()
			idx := len(createMsgReqs) + 1
			createMsgReqs = append(createMsgReqs, body)
			mu.Unlock()

			spaceGID := encodeSpaceGroupID("space_threaded")
			msgIDStr := fmt.Sprintf("msg_reply_%d", idx)
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_new_1", msgIDStr, "112233445566778899001", "Reply body", 1710000600000000+int64(idx), "", 0, 0)
			resp := encodeBytesField(1, msgBytes)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
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
	doneStep, err := proc.(bridgev2.LoginProcessCookies).SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
		"OSID":    "synthetic_osid",
		"SID":     "synthetic_sid",
		"HSID":    "synthetic_hsid",
		"SSID":    "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := doneStep.CompleteParams.UserLogin
	client := ul.Client.(*Client)
	t.Cleanup(client.Disconnect)

	// Build portals by running the real syncWorld path against paginated_world on the fake server.
	require.NoError(t, client.syncWorld(ctx))

	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)

	flatThreadsPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_flat_threads"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, flatThreadsPortal)
	require.Equal(t, event.CapLevelFullySupported, client.GetCapabilities(ctx, flatThreadsPortal).Thread, "synced flat_threads_enabled space must advertise Thread capability")

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)

	// 1. Top-level message in synced threaded space -> POST /u/0/api/create_topic
	topResp, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType:       event.MsgText,
				Body:          "Hello 🚀",
				Format:        event.FormatHTML,
				FormattedBody: "<b>Hello</b> 🚀",
			},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, topResp)
	require.NotNil(t, topResp.DB)
	require.Equal(t, MakeMessageID("topic_new_1", "msg_new_1"), topResp.DB.ID)
	require.Equal(t, MakeThreadRootID("topic_new_1"), topResp.DB.ThreadRoot)

	// 1b. Top-level message and thread reply in synced flat_threads_enabled space (TopicThreaded == false, ThreadsEnabled == true)
	flatTopResp, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: flatThreadsPortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Flat thread starter",
			},
		},
	})
	require.NoError(t, err)
	require.Equal(t, MakeThreadRootID("topic_new_2"), flatTopResp.DB.ThreadRoot, "flat_threads_enabled space must set ThreadRoot on created topic")

	mu.Lock()
	require.Len(t, createTopicReqs, 2)
	topicReqBytes := createTopicReqs[0]
	mu.Unlock()

	topicFields := parseProtoFields(topicReqBytes)
	require.Equal(t, "Hello 🚀", firstFieldString(topicFields, 2), "CreateTopicRequest.text_body")
	require.NotEmpty(t, topicFields[3], "CreateTopicRequest.annotations must carry BOLD annotation")
	localID := firstFieldString(topicFields, 4)
	require.True(t, strings.HasPrefix(localID, "mautrix-googlechat%"), "local_id must have mautrix-googlechat%% prefix, got %q", localID)
	groupIDFields := parseProtoFields(firstFieldBytes(topicFields, 5))
	spaceIDFields := parseProtoFields(firstFieldBytes(groupIDFields, 1))
	require.Equal(t, "space_threaded", firstFieldString(spaceIDFields, 1))
	retentionFields := parseProtoFields(firstFieldBytes(topicFields, 6))
	require.Equal(t, uint64(1), firstFieldVarint(retentionFields, 1), "retention_settings.state must be DEFAULT_AWAKE (1)")
	require.Equal(t, uint64(1), firstFieldVarint(topicFields, 8), "history_v2 must be true")
	msgInfoFields := parseProtoFields(firstFieldBytes(topicFields, 9))
	require.Equal(t, uint64(1), firstFieldVarint(msgInfoFields, 1), "accept_format_annotations must be true")

	// Echo deduplication: incoming WebChannel MESSAGE_POSTED carrying the same local_id must be ignored.
	beforeEvents := len(client.recordedRemoteEvents())
	echoMsg := encodeSyntheticMessage(encodeSpaceGroupID("space_threaded"), "topic_new_1", "msg_new_1", "112233445566778899001", "Hello 🚀", 1710000500000001, "", 0, 0)
	echoMsg = append(echoMsg, encodeStringField(14, localID)...)
	var echoBody []byte
	echoBody = append(echoBody, encodeBytesField(6, encodeBytesField(1, echoMsg))...)
	echoBody = append(echoBody, encodeVarintField(12, 6)...)
	var echoEvt []byte
	echoEvt = append(echoEvt, encodeBytesField(1, encodeSpaceGroupID("space_threaded"))...)
	echoEvt = append(echoEvt, encodeVarintField(3, 6)...)
	echoEvt = append(echoEvt, encodeBytesField(4, echoBody)...)
	client.processStreamNotification(ctx, streamNotification{kind: 1, payload: echoEvt})
	require.Len(t, client.recordedRemoteEvents(), beforeEvents, "outbound local_id echo must be deduplicated")

	// 2. Thread reply + quote-reply with valid microsecond create_time -> POST /u/0/api/create_message
	threadRootDB := &database.Message{
		ID:       MakeThreadRootID("topic_new_1"),
		Metadata: &MessageMetadata{TopicID: "topic_new_1", CreateTimeMicros: 1710000500000000},
	}
	replyTargetDB := &database.Message{
		ID:        MakeMessageID("topic_new_1", "msg_new_1"),
		Timestamp: time.UnixMicro(1710000500000000),
		Metadata:  &MessageMetadata{TopicID: "topic_new_1", CreateTimeMicros: 1710000500000000},
	}
	replyResp, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Reply body",
			},
		},
		ThreadRoot: threadRootDB,
		ReplyTo:    replyTargetDB,
	})
	require.NoError(t, err)
	require.NotNil(t, replyResp)

	mu.Lock()
	require.Len(t, createMsgReqs, 1)
	createMsgBytes := createMsgReqs[0]
	mu.Unlock()

	cmFields := parseProtoFields(createMsgBytes)
	parentFields := parseProtoFields(firstFieldBytes(cmFields, 1))
	topicIDFields := parseProtoFields(firstFieldBytes(parentFields, 4))
	require.Equal(t, "topic_new_1", firstFieldString(topicIDFields, 2), "MessageParentId.topic_id.topic_id")
	require.Equal(t, "Reply body", firstFieldString(cmFields, 2), "CreateMessageRequest.text_body")
	require.True(t, strings.HasPrefix(firstFieldString(cmFields, 4), "mautrix-googlechat%"))
	cmInfoFields := parseProtoFields(firstFieldBytes(cmFields, 7))
	replyTargetBytes := firstFieldBytes(cmInfoFields, 3)
	require.NotEmpty(t, replyTargetBytes, "SendReplyTarget must be populated when create_time > 0")
	rtFields := parseProtoFields(replyTargetBytes)
	require.Equal(t, uint64(1710000500000000), firstFieldVarint(rtFields, 2), "SendReplyTarget.create_time must be microsecond timestamp")
	rtMsgIDFields := parseProtoFields(firstFieldBytes(rtFields, 1))
	require.Equal(t, "msg_new_1", firstFieldString(rtMsgIDFields, 2), "SendReplyTarget.id.message_id")

	// 3. Quote-reply with zero create_time must NEVER send SendReplyTarget (create_time == 0 omitted).
	zeroReplyTargetDB := &database.Message{
		ID:       MakeMessageID("topic_new_1", "msg_zero"),
		Metadata: &MessageMetadata{TopicID: "topic_new_1", CreateTimeMicros: 0},
	}
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Reply without timestamp",
			},
		},
		ThreadRoot: threadRootDB,
		ReplyTo:    zeroReplyTargetDB,
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, createMsgReqs, 2)
	zeroReqFields := parseProtoFields(createMsgReqs[1])
	mu.Unlock()
	zeroInfoFields := parseProtoFields(firstFieldBytes(zeroReqFields, 7))
	require.Empty(t, firstFieldBytes(zeroInfoFields, 3), "SendReplyTarget must not be sent when target create_time is 0")

	// 4. Message in synced DM -> POST /u/0/api/create_message
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Hello DM",
			},
		},
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, createMsgReqs, 3)
	dmReqFields := parseProtoFields(createMsgReqs[2])
	mu.Unlock()
	dmParentFields := parseProtoFields(firstFieldBytes(dmReqFields, 1))
	dmTopicFields := parseProtoFields(firstFieldBytes(dmParentFields, 4))
	dmGIDFields := parseProtoFields(firstFieldBytes(dmTopicFields, 3))
	dmIDFields := parseProtoFields(firstFieldBytes(dmGIDFields, 3))
	require.Equal(t, "dm_alpha", firstFieldString(dmIDFields, 1))

	// 5. Text exceeding 4,096 characters is refused with a plain message.
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    strings.Repeat("x", 4097),
			},
		},
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "4,096")
}

func TestSendEditUnsendReactionReceiptAndTyping(t *testing.T) {
	enableTestLoopback(t)
	ctx := context.Background()

	var (
		mu            sync.Mutex
		editReqs      [][]byte
		deleteReqs    [][]byte
		reactionReqs  [][]byte
		readStateReqs [][]byte
		typingReqs    [][]byte
	)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_synthetic_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			_, _ = w.Write(buildSyntheticSelfUserStatusResponse("112233445566778899001"))
		case "/u/0/api/get_members":
			_, _ = w.Write(buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			))
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/edit_message":
			mu.Lock()
			editReqs = append(editReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_1", "msg_1", "112233445566778899001", "Edited text", 1710000500000000, "", 0, 0)
			msgBytes = append(msgBytes, encodeVarintField(17, 1710000550000000)...)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/delete_message":
			mu.Lock()
			deleteReqs = append(deleteReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeVarintField(4, 1710000560000000))
		case "/u/0/api/update_reaction":
			mu.Lock()
			reactionReqs = append(reactionReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(1, encodeVarintField(1, 600)))
		case "/u/0/api/mark_group_readstate":
			mu.Lock()
			readStateReqs = append(readStateReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 601)))
		case "/u/0/api/set_typing_state":
			mu.Lock()
			typingReqs = append(typingReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeVarintField(1, 1710000570000000))
		case "/u/0/uploads", "/uploads":
			w.Header().Set("x-goog-upload-url", fmt.Sprintf("http://%s/u/0/upload_put", r.Host))
			w.WriteHeader(http.StatusOK)
		case "/u/0/upload_put":
			upMeta := encodeUploadMetadataProto("cap_tok", "cap.bin", "application/octet-stream")
			wrapped := encodeBytesField(1, upMeta)
			w.Header().Set("Content-Type", "text/plain")
			_, _ = fmt.Fprint(w, base64.StdEncoding.EncodeToString(wrapped))
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
	doneStep, err := proc.(bridgev2.LoginProcessCookies).SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
		"OSID":    "synthetic_osid",
		"SID":     "synthetic_sid",
		"HSID":    "synthetic_hsid",
		"SSID":    "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := doneStep.CompleteParams.UserLogin
	client := ul.Client.(*Client)
	t.Cleanup(client.Disconnect)

	// Build portals via real syncWorld against paginated_world.
	require.NoError(t, client.syncWorld(ctx))

	portal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, portal)

	unthreadedSpace, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_unthreaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, unthreadedSpace)

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)

	targetMsg := &database.Message{
		ID:       MakeMessageID("topic_1", "msg_1"),
		Metadata: &MessageMetadata{TopicID: "topic_1", CreateTimeMicros: 1710000500000000},
	}

	// 1. Edit message -> POST /u/0/api/edit_message
	err = client.HandleMatrixEdit(ctx, &bridgev2.MatrixEdit{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: portal,
			Content: &event.MessageEventContent{
				MsgType:       event.MsgText,
				Body:          "Edited text",
				Format:        event.FormatHTML,
				FormattedBody: "<i>Edited</i> text",
			},
		},
		EditTarget: targetMsg,
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, editReqs, 1)
	editFields := parseProtoFields(editReqs[0])
	mu.Unlock()
	editMsgIDFields := parseProtoFields(firstFieldBytes(editFields, 1))
	require.Equal(t, "msg_1", firstFieldString(editMsgIDFields, 2))
	require.Equal(t, "Edited text", firstFieldString(editFields, 2))
	require.NotEmpty(t, editFields[3], "EditMessageRequest.annotations must be populated")

	// 2. Delete message -> POST /u/0/api/delete_message
	err = client.HandleMatrixMessageRemove(ctx, &bridgev2.MatrixMessageRemove{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{
			Portal: portal,
		},
		TargetMessage: targetMsg,
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, deleteReqs, 1)
	delFields := parseProtoFields(deleteReqs[0])
	mu.Unlock()
	delMsgIDFields := parseProtoFields(firstFieldBytes(delFields, 1))
	require.Equal(t, "msg_1", firstFieldString(delMsgIDFields, 2))

	// 3. Reaction add & remove -> POST /u/0/api/update_reaction (strips U+FE0F)
	rxnInput := &bridgev2.MatrixReaction{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.ReactionEventContent]{
			Portal: portal,
			Content: &event.ReactionEventContent{
				RelatesTo: event.RelatesTo{Key: "❤️"}, // \u2764\uFE0F
			},
		},
		TargetMessage: targetMsg,
	}
	preResp, err := client.PreHandleMatrixReaction(ctx, rxnInput)
	require.NoError(t, err)
	require.Equal(t, networkid.EmojiID("❤"), preResp.EmojiID, "U+FE0F must be stripped from EmojiID")
	require.Equal(t, "❤", preResp.Emoji)
	rxnInput.PreHandleResp = &preResp

	dbRxn, err := client.HandleMatrixReaction(ctx, rxnInput)
	require.NoError(t, err)
	require.NotNil(t, dbRxn)

	err = client.HandleMatrixReactionRemove(ctx, &bridgev2.MatrixReactionRemove{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{
			Portal: portal,
		},
		TargetReaction: &database.Reaction{
			Room:      portal.PortalKey,
			MessageID: targetMsg.ID,
			EmojiID:   preResp.EmojiID,
			Emoji:     "❤️",
		},
	})
	require.NoError(t, err)

	mu.Lock()
	require.Len(t, reactionReqs, 2)
	addRxnFields := parseProtoFields(reactionReqs[0])
	remRxnFields := parseProtoFields(reactionReqs[1])
	mu.Unlock()

	addEmojiFields := parseProtoFields(firstFieldBytes(addRxnFields, 2))
	require.Equal(t, "❤", firstFieldString(addEmojiFields, 1), "UpdateReactionRequest ADD must strip U+FE0F")
	require.Equal(t, uint64(1), firstFieldVarint(addRxnFields, 3), "UpdateReactionRequest.type must be ADD (1)")

	remEmojiFields := parseProtoFields(firstFieldBytes(remRxnFields, 2))
	require.Equal(t, "❤", firstFieldString(remEmojiFields, 1), "UpdateReactionRequest REMOVE must strip U+FE0F")
	require.Equal(t, uint64(2), firstFieldVarint(remRxnFields, 3), "UpdateReactionRequest.type must be REMOVE (2)")

	// 4. Read receipt -> POST /u/0/api/mark_group_readstate with microsecond timestamp
	readTime := time.UnixMicro(1710000599123456)
	err = client.HandleMatrixReadReceipt(ctx, &bridgev2.MatrixReadReceipt{
		Portal:   portal,
		ReadUpTo: readTime,
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, readStateReqs, 1)
	rsFields := parseProtoFields(readStateReqs[0])
	mu.Unlock()
	require.Equal(t, uint64(1710000599123456), firstFieldVarint(rsFields, 2), "MarkGroupReadstateRequest.last_read_time must be in microseconds")

	// 5. Typing start & stop -> POST /u/0/api/set_typing_state
	err = client.HandleMatrixTyping(ctx, &bridgev2.MatrixTyping{
		Portal:   portal,
		IsTyping: true,
	})
	require.NoError(t, err)
	err = client.HandleMatrixTyping(ctx, &bridgev2.MatrixTyping{
		Portal:   portal,
		IsTyping: false,
	})
	require.NoError(t, err)
	mu.Lock()
	require.Len(t, typingReqs, 2)
	typingStartFields := parseProtoFields(typingReqs[0])
	typingStopFields := parseProtoFields(typingReqs[1])
	mu.Unlock()
	require.Equal(t, uint64(1), firstFieldVarint(typingStartFields, 1), "SetTypingStateRequest.state TYPING (1)")
	require.Equal(t, uint64(2), firstFieldVarint(typingStopFields, 1), "SetTypingStateRequest.state STOPPED (2)")

	require.Equal(t, event.CapLevelUnsupported, client.GetCapabilities(ctx, dmPortal).Thread)
	require.Equal(t, event.CapLevelUnsupported, client.GetCapabilities(ctx, dmPortal).Formatting[event.FmtAtRoomMention])
	require.Equal(t, event.CapLevelUnsupported, client.GetCapabilities(ctx, unthreadedSpace).Thread)
	require.Equal(t, event.CapLevelFullySupported, client.GetCapabilities(ctx, unthreadedSpace).Formatting[event.FmtAtRoomMention])
	require.Equal(t, event.CapLevelFullySupported, client.GetCapabilities(ctx, portal).Thread)
	require.Equal(t, event.CapLevelFullySupported, client.GetCapabilities(ctx, portal).Formatting[event.FmtAtRoomMention])
}

func hasMentionAllAnnotation(annSlices []protoField) bool {
	for _, f := range annSlices {
		af := parseProtoFields(f.bytes)
		if firstFieldVarint(af, 1) != 6 { // AnnotationType.USER_MENTION = 6 (googlechat.proto:1778)
			continue
		}
		um := parseProtoFields(firstFieldBytes(af, 5)) // user_mention_metadata = field 5
		if firstFieldVarint(um, 2) == 4 {              // UserMentionMetadata.type (field 2) == MENTION_ALL (4)
			return true
		}
	}
	return false
}

func TestOutboundMentionsAtRoomAndAtAllInSpaceAndDM(t *testing.T) {
	ctx := context.Background()
	var (
		mu              sync.Mutex
		createTopicReqs [][]byte
		createMsgReqs   [][]byte
		editReqs        [][]byte
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_topic":
			mu.Lock()
			createTopicReqs = append(createTopicReqs, body)
			idx := len(createTopicReqs)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			tid := fmt.Sprintf("topic_m_%d", idx)
			mid := fmt.Sprintf("msg_m_%d", idx)
			msgBytes := encodeSyntheticMessage(spaceGID, tid, mid, "112233445566778899001", "ok", 1710000500000000+int64(idx), "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, tid))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/create_message":
			mu.Lock()
			createMsgReqs = append(createMsgReqs, body)
			idx := len(createMsgReqs)
			mu.Unlock()
			dmGID := encodeDMGroupID("dm_alpha")
			msgBytes := encodeSyntheticMessage(dmGID, "dm_t", fmt.Sprintf("dm_m_%d", idx), "112233445566778899001", "ok", 1710000500000000+int64(idx), "", 0, 0)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/edit_message":
			mu.Lock()
			editReqs = append(editReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_m_1", "msg_m_1", "112233445566778899001", "ok", 1710000500000000, "", 0, 0)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)
	require.NoError(t, spacePortal.CreateMatrixRoom(ctx, ul, nil))

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)
	require.NoError(t, dmPortal.CreateMatrixRoom(ctx, ul, nil))

	// 1. Plain-text @room and @all in a Space -> rewritten to @all with USER_MENTION (MENTION_ALL = 4) annotations
	plainSpaceResp, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Heads up @room and @all",
			},
		},
	})
	require.NoError(t, err)

	// 2. HTML @room in a Space -> rewritten to @all with USER_MENTION (MENTION_ALL = 4) annotation
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType:       event.MsgText,
				Body:          "Alert @room",
				Format:        event.FormatHTML,
				FormattedBody: "<b>Alert</b> @room",
			},
		},
	})
	require.NoError(t, err)

	// 3. Edit with plain-text @room in a Space -> rewritten to @all with USER_MENTION (MENTION_ALL = 4) annotation
	require.NoError(t, client.HandleMatrixEdit(ctx, &bridgev2.MatrixEdit{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Edited @room notice",
			},
		},
		EditTarget: plainSpaceResp.DB,
	}))

	// 4. Plain-text and HTML @room / @all in a DM -> left as plain text, NO MENTION_ALL annotation
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType: event.MsgText,
				Body:    "Hello @room and @all in DM",
			},
		},
	})
	require.NoError(t, err)
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType:       event.MsgText,
				Body:          "Hello @room and @all in DM",
				Format:        event.FormatHTML,
				FormattedBody: "<b>Hello</b> @room and @all in DM",
			},
		},
	})
	require.NoError(t, err)

	mu.Lock()
	defer mu.Unlock()
	require.Len(t, createTopicReqs, 2)
	require.Len(t, editReqs, 1)
	require.Len(t, createMsgReqs, 2)

	plainSpaceFields := parseProtoFields(createTopicReqs[0])
	require.Equal(t, "Heads up @all and @all", firstFieldString(plainSpaceFields, 2), "plain-text @room in Space must rewrite to @all")
	require.True(t, hasMentionAllAnnotation(plainSpaceFields[3]), "plain-text @room/@all in Space must emit MENTION_ALL annotation")

	htmlSpaceFields := parseProtoFields(createTopicReqs[1])
	require.Equal(t, "Alert @all", firstFieldString(htmlSpaceFields, 2), "HTML @room in Space must rewrite to @all")
	require.True(t, hasMentionAllAnnotation(htmlSpaceFields[3]), "HTML @room in Space must emit MENTION_ALL annotation")

	editSpaceFields := parseProtoFields(editReqs[0])
	require.Equal(t, "Edited @all notice", firstFieldString(editSpaceFields, 2), "Edit @room in Space must rewrite to @all")
	require.True(t, hasMentionAllAnnotation(editSpaceFields[3]), "Edit @room in Space must emit MENTION_ALL annotation")

	plainDMFields := parseProtoFields(createMsgReqs[0])
	require.Equal(t, "Hello @room and @all in DM", firstFieldString(plainDMFields, 2), "DM must not rewrite @room")
	require.False(t, hasMentionAllAnnotation(plainDMFields[3]), "DM plain text must not emit MENTION_ALL")

	htmlDMFields := parseProtoFields(createMsgReqs[1])
	require.Equal(t, "Hello @room and @all in DM", firstFieldString(htmlDMFields, 2), "DM HTML must not rewrite @room")
	require.False(t, hasMentionAllAnnotation(htmlDMFields[3]), "DM HTML must not emit MENTION_ALL")
}

func TestOutboundMessageAndEditEchoDeduplication(t *testing.T) {
	ctx := context.Background()
	var failCreateTopic atomic.Bool
	var inFlightEchoDispatched atomic.Bool

	var clientRef atomic.Pointer[Client]

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_topic":
			if failCreateTopic.Load() {
				http.Error(w, "Server Error", http.StatusInternalServerError)
				return
			}
			reqFields := parseProtoFields(body)
			localID := firstFieldString(reqFields, 4)
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_dedup", "msg_dedup_1", "112233445566778899001", "Dedup test", 1710000500000000, "", 0, 0)
			msgBytes = append(msgBytes, encodeStringField(14, localID)...)

			// Deliver the WebChannel MESSAGE_POSTED echo WHILE create_topic is still in flight!
			if c := clientRef.Load(); c != nil {
				var echoBody []byte
				echoBody = append(echoBody, encodeBytesField(6, encodeBytesField(1, msgBytes))...)
				echoBody = append(echoBody, encodeVarintField(12, 6)...)
				var echoEvt []byte
				echoEvt = append(echoEvt, encodeBytesField(1, spaceGID)...)
				echoEvt = append(echoEvt, encodeVarintField(3, 6)...)
				echoEvt = append(echoEvt, encodeBytesField(4, echoBody)...)
				c.processStreamNotification(ctx, streamNotification{kind: 1, payload: echoEvt})
				inFlightEchoDispatched.Store(true)
			}

			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, "topic_dedup"))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/edit_message":
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_dedup", "msg_dedup_1", "112233445566778899001", "Dedup edited", 1710000500000000, "", 0, 0)
			msgBytes = append(msgBytes, encodeVarintField(17, 1710000550000000)...) // last_edit_time
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		default:
			http.NotFound(w, r)
		}
	})
	clientRef.Store(client)

	require.NoError(t, client.syncWorld(ctx))
	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)

	// 1. Send message while server delivers in-flight echo -> must be registered in bridgev2 pending map before RPC and deduplicated
	beforeCount := len(client.recordedRemoteEvents())
	resp, err := client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  spacePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Dedup test"},
		},
	})
	require.NoError(t, err)
	require.True(t, inFlightEchoDispatched.Load())
	require.NotEmpty(t, resp.RemovePending, "MatrixMessageResponse.RemovePending must carry txnID")
	require.Len(t, client.recordedRemoteEvents(), beforeCount, "outbound MESSAGE_POSTED echo must be suppressed so only one message exists")

	// Also verify bridgev2 portal's outgoingMessages map has txnID registered via msg.AddPendingToIgnore(txnID):
	outgoingMap := reflect.ValueOf(spacePortal).Elem().FieldByName("outgoingMessages")
	require.True(t, outgoingMap.MapIndex(reflect.ValueOf(resp.RemovePending)).IsValid(),
		"msg.AddPendingToIgnore(txnID) must register txnID in portal.outgoingMessages before sending")

	// 2. Failed send must clean up pendingLocalIDs and portal pending map
	failCreateTopic.Store(true)
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  spacePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Should fail"},
		},
	})
	require.Error(t, err)
	client.mu.Lock()
	pendingCount := len(client.pendingLocalIDs)
	client.mu.Unlock()
	require.Zero(t, pendingCount, "failed send must remove local_id from pendingLocalIDs")
	require.Equal(t, 1, outgoingMap.Len(), "failed send must call msg.RemovePending(txnID) so portal.outgoingMessages does not leak")

	// 3. Edit message via HandleMatrixEdit -> sets LastEditTime = 1710000550000000; subsequent MESSAGE_UPDATED echo with <= LastEditTime returns ErrIgnoringRemoteEvent
	require.NoError(t, client.HandleMatrixEdit(ctx, &bridgev2.MatrixEdit{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  spacePortal,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Dedup edited"},
		},
		EditTarget: resp.DB,
	}))
	require.Equal(t, int64(1710000550000000), resp.DB.Metadata.(*MessageMetadata).LastEditTime)

	spaceGID := encodeSpaceGroupID("space_threaded")
	editedEcho := encodeSyntheticMessage(spaceGID, "topic_dedup", "msg_dedup_1", "112233445566778899001", "Dedup edited", 1710000500000000, "", 0, 0)
	editedEcho = append(editedEcho, encodeVarintField(17, 1710000550000000)...)
	var editBody []byte
	editBody = append(editBody, encodeBytesField(6, encodeBytesField(1, editedEcho))...)
	editBody = append(editBody, encodeVarintField(12, 7)...) // MESSAGE_UPDATED
	var editEvtBytes []byte
	editEvtBytes = append(editEvtBytes, encodeBytesField(1, spaceGID)...)
	editEvtBytes = append(editEvtBytes, encodeVarintField(3, 7)...)
	editEvtBytes = append(editEvtBytes, encodeBytesField(4, editBody)...)

	remoteEvts, err := client.translateWebChannelEvent(ctx, editEvtBytes)
	require.NoError(t, err)
	require.Len(t, remoteEvts, 1)
	remoteEdit, ok := remoteEvts[0].(bridgev2.RemoteEdit)
	require.True(t, ok)

	_, convErr := remoteEdit.ConvertEdit(ctx, spacePortal, nil, []*database.Message{resp.DB})
	require.ErrorIs(t, convErr, bridgev2.ErrIgnoringRemoteEvent, "ConvertEdit must return ErrIgnoringRemoteEvent for outbound edit echo with same last_edit_time")

	// Newer edit from remote (1710000560000000 > 1710000550000000) is NOT ignored
	newerEditMsg := encodeSyntheticMessage(spaceGID, "topic_dedup", "msg_dedup_1", "112233445566778899001", "Newer edit", 1710000500000000, "", 0, 0)
	newerEditMsg = append(newerEditMsg, encodeVarintField(17, 1710000560000000)...)
	var newerBody []byte
	newerBody = append(newerBody, encodeBytesField(6, encodeBytesField(1, newerEditMsg))...)
	newerBody = append(newerBody, encodeVarintField(12, 7)...)
	var newerEvtBytes []byte
	newerEvtBytes = append(newerEvtBytes, encodeBytesField(1, spaceGID)...)
	newerEvtBytes = append(newerEvtBytes, encodeVarintField(3, 7)...)
	newerEvtBytes = append(newerEvtBytes, encodeBytesField(4, newerBody)...)

	newerRemoteEvts, err := client.translateWebChannelEvent(ctx, newerEvtBytes)
	require.NoError(t, err)
	require.Len(t, newerRemoteEvts, 1)
	convEdit, convErr := newerRemoteEvts[0].(bridgev2.RemoteEdit).ConvertEdit(ctx, spacePortal, nil, []*database.Message{resp.DB})
	require.NoError(t, convErr)
	require.NotNil(t, convEdit)
	require.Equal(t, int64(1710000560000000), resp.DB.Metadata.(*MessageMetadata).LastEditTime)
}

func TestQuoteReplyUsesStoredMicrosecondCreateTimeAndTopicIDFallback(t *testing.T) {
	ctx := context.Background()
	var (
		mu              sync.Mutex
		createTopicReqs [][]byte
		createMsgReqs   [][]byte
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_topic":
			mu.Lock()
			createTopicReqs = append(createTopicReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_unthreaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_qt_1", "msg_qt_1", "112233445566778899001", "Quote in unthreaded space", 1710000510000000, "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, "topic_qt_1"))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/create_message":
			mu.Lock()
			createMsgReqs = append(createMsgReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "msg_root_single", "msg_qt_2", "112233445566778899001", "Quote in threaded space", 1710000520000000, "", 0, 0)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))
	unthreadedSpace, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_unthreaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	threadedSpace, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)

	// Target message with single-segment ID ("msg_root_single", no "/" separator), empty TopicID in metadata,
	// millisecond-truncated Timestamp, and exact microsecond CreateTimeMicros = 1710000500123456.
	singleSegTarget := &database.Message{
		ID:        networkid.MessageID("msg_root_single"),
		Timestamp: time.UnixMilli(1710000500123), // 1710000500123000 us if misused
		Metadata:  &MessageMetadata{TopicID: "", CreateTimeMicros: 1710000500123456},
	}

	// 1. Quote-reply in unthreaded space -> calls create_topic with SendReplyTarget carrying exact CreateTimeMicros and non-empty topic_id fallback ("msg_root_single")
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  unthreadedSpace,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Quote in unthreaded space"},
		},
		ReplyTo: singleSegTarget,
	})
	require.NoError(t, err)

	// 2. Quote-reply in threaded space -> calls create_message with SendReplyTarget carrying exact CreateTimeMicros and non-empty topic_id fallback ("msg_root_single")
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal:  threadedSpace,
			Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Quote in threaded space"},
		},
		ReplyTo: singleSegTarget,
	})
	require.NoError(t, err)

	mu.Lock()
	defer mu.Unlock()
	require.Len(t, createTopicReqs, 1, "quote-reply in unthreaded space must use create_topic")
	require.Len(t, createMsgReqs, 1, "quote-reply in threaded space must use create_message")

	ctFields := parseProtoFields(createTopicReqs[0])
	ctMsgInfo := parseProtoFields(firstFieldBytes(ctFields, 9))
	ctReplyTarget := parseProtoFields(firstFieldBytes(ctMsgInfo, 3))
	require.Equal(t, uint64(1710000500123456), firstFieldVarint(ctReplyTarget, 2), "create_topic SendReplyTarget must use stored microsecond CreateTimeMicros")
	ctReplyMsgID := parseProtoFields(firstFieldBytes(ctReplyTarget, 1))
	ctReplyParent := parseProtoFields(firstFieldBytes(ctReplyMsgID, 1))
	ctReplyTopic := parseProtoFields(firstFieldBytes(ctReplyParent, 4))
	require.Equal(t, "msg_root_single", firstFieldString(ctReplyTopic, 2), "create_topic SendReplyTarget topic_id must fall back to target message ID, never empty")

	cmFields := parseProtoFields(createMsgReqs[0])
	cmMsgInfo := parseProtoFields(firstFieldBytes(cmFields, 7))
	cmReplyTarget := parseProtoFields(firstFieldBytes(cmMsgInfo, 3))
	require.Equal(t, uint64(1710000500123456), firstFieldVarint(cmReplyTarget, 2), "create_message SendReplyTarget must use stored microsecond CreateTimeMicros")
	cmReplyMsgID := parseProtoFields(firstFieldBytes(cmReplyTarget, 1))
	cmReplyParent := parseProtoFields(firstFieldBytes(cmReplyMsgID, 1))
	cmReplyTopic := parseProtoFields(firstFieldBytes(cmReplyParent, 4))
	require.Equal(t, "msg_root_single", firstFieldString(cmReplyTopic, 2), "create_message SendReplyTarget topic_id must never be empty")
}

func TestPortalMetadataConcurrentStreamAndSendRace(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_topic":
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_race", "msg_race", "112233445566778899001", "Race", 1710000500000000, "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, "topic_race"))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			var resp []byte
			resp = append(resp, encodeBytesField(1, topic)...)
			resp = append(resp, encodeBytesField(2, encodeVarintField(1, 300))...)
			_, _ = w.Write(resp)
		case "/u/0/api/catch_up_group":
			var resp []byte
			resp = append(resp, encodeVarintField(2, 1)...)
			resp = append(resp, encodeBytesField(4, encodeVarintField(1, 350))...)
			_, _ = w.Write(resp)
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))
	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)

	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		rev := int64(200 + i)
		wg.Add(4)
		go func(r int64) {
			defer wg.Done()
			_ = client.advancePortalGroupRevision(ctx, spacePortal.PortalKey, r)
		}(rev)
		go func() {
			defer wg.Done()
			_ = client.GetCapabilities(ctx, spacePortal)
		}()
		go func() {
			defer wg.Done()
			_ = client.catchUpGroup(ctx, spacePortal)
		}()
		go func() {
			defer wg.Done()
			_, _ = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
				MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
					Portal:  spacePortal,
					Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Race"},
				},
			})
		}()
	}
	wg.Wait()
}

func TestAdvertisedCapabilitiesAllHaveWorkingHandlers(t *testing.T) {
	ctx := context.Background()
	var (
		mu              sync.Mutex
		createTopicReqs [][]byte
		createMsgReqs   [][]byte
		editReqs        [][]byte
		deleteReqs      [][]byte
		reactionReqs    [][]byte
		readStateReqs   [][]byte
		typingReqs      [][]byte
		createDMReqs    [][]byte
		getGroupReqs    [][]byte
		updateGroupReqs [][]byte
		createMemReqs   [][]byte
		removeMemReqs   [][]byte
		hideGroupReqs   [][]byte
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/create_dm":
			mu.Lock()
			createDMReqs = append(createDMReqs, body)
			mu.Unlock()
			var dmGroup []byte
			dmGroup = append(dmGroup, encodeBytesField(1, encodeDMGroupID("dm_cap_created"))...)
			var mem []byte
			var memID []byte
			memID = append(memID, encodeBytesField(1, encodeBytesField(1, encodeStringField(1, "112233445566778899002")))...)
			mem = append(mem, encodeBytesField(1, memID)...)
			var resp []byte
			resp = append(resp, encodeBytesField(1, dmGroup)...)
			resp = append(resp, encodeBytesField(4, mem)...)
			_, _ = w.Write(resp)
		case "/u/0/api/get_group":
			mu.Lock()
			getGroupReqs = append(getGroupReqs, body)
			mu.Unlock()
			var details []byte
			details = append(details, encodeStringField(1, "Old description")...)
			details = append(details, encodeStringField(2, "Keep guidelines intact")...)
			var grp []byte
			grp = append(grp, encodeBytesField(1, encodeSpaceGroupID("space_threaded"))...)
			grp = append(grp, encodeStringField(4, "Threaded Eng")...)
			grp = append(grp, encodeBytesField(37, details)...)
			_, _ = w.Write(encodeBytesField(1, grp))
		case "/u/0/api/update_group":
			mu.Lock()
			updateGroupReqs = append(updateGroupReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 610)))
		case "/u/0/api/create_membership":
			mu.Lock()
			createMemReqs = append(createMemReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 611)))
		case "/u/0/api/remove_memberships":
			mu.Lock()
			removeMemReqs = append(removeMemReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(3, encodeVarintField(1, 612)))
		case "/u/0/api/hide_group":
			mu.Lock()
			hideGroupReqs = append(hideGroupReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 613)))
		case "/u/0/api/create_topic":
			mu.Lock()
			createTopicReqs = append(createTopicReqs, body)
			idx := len(createTopicReqs)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			tid := fmt.Sprintf("topic_cap_%d", idx)
			mid := fmt.Sprintf("msg_cap_%d", idx)
			msgBytes := encodeSyntheticMessage(spaceGID, tid, mid, "112233445566778899001", "cap", 1710000500000000+int64(idx), "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, tid))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/create_message":
			mu.Lock()
			createMsgReqs = append(createMsgReqs, body)
			idx := len(createMsgReqs)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_cap_1", fmt.Sprintf("msg_reply_cap_%d", idx), "112233445566778899001", "cap reply", 1710000600000000+int64(idx), "", 0, 0)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/edit_message":
			mu.Lock()
			editReqs = append(editReqs, body)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			msgBytes := encodeSyntheticMessage(spaceGID, "topic_cap_1", "msg_cap_1", "112233445566778899001", "edited", 1710000500000000, "", 0, 0)
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/delete_message":
			mu.Lock()
			deleteReqs = append(deleteReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeVarintField(4, 1710000560000000))
		case "/u/0/api/update_reaction":
			mu.Lock()
			reactionReqs = append(reactionReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(1, encodeVarintField(1, 600)))
		case "/u/0/api/mark_group_readstate":
			mu.Lock()
			readStateReqs = append(readStateReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 601)))
		case "/u/0/api/set_typing_state":
			mu.Lock()
			typingReqs = append(typingReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeVarintField(1, 1710000570000000))
		case "/u/0/uploads", "/uploads":
			w.Header().Set("x-goog-upload-url", fmt.Sprintf("http://%s/u/0/upload_put", r.Host))
			w.WriteHeader(http.StatusOK)
		case "/u/0/upload_put":
			upMeta := encodeUploadMetadataProto("cap_tok", "cap.bin", "application/octet-stream")
			wrapped := encodeBytesField(1, upMeta)
			w.Header().Set("Content-Type", "text/plain")
			_, _ = fmt.Fprint(w, base64.StdEncoding.EncodeToString(wrapped))
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))
	threadedSpace, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, threadedSpace)

	var api bridgev2.NetworkAPI = client

	// 1. Walk NetworkGeneralCapabilities: ResolveIdentifier (CreateDM + LookupEmail) is advertised and wired; GroupCreation stays empty (Owner Decision spec §13).
	genCaps := client.Main.GetCapabilities()
	require.NotNil(t, genCaps)
	require.True(t, genCaps.Provisioning.ResolveIdentifier.CreateDM, "ResolveIdentifier.CreateDM must be advertised")
	require.True(t, genCaps.Provisioning.ResolveIdentifier.LookupEmail, "ResolveIdentifier.LookupEmail must be advertised")
	require.Empty(t, genCaps.Provisioning.GroupCreation, "GroupCreation must remain hidden per spec §13")
	if genCaps.Provisioning.ResolveIdentifier.CreateDM || genCaps.Provisioning.ResolveIdentifier.LookupEmail || genCaps.Provisioning.ResolveIdentifier.LookupPhone || genCaps.Provisioning.ResolveIdentifier.LookupUsername {
		resAPI, ok := api.(bridgev2.IdentifierResolvingNetworkAPI)
		require.True(t, ok, "ResolveIdentifier advertised without IdentifierResolvingNetworkAPI")
		mu.Lock()
		beforeDM := len(createDMReqs)
		mu.Unlock()
		dmResp, err := resAPI.ResolveIdentifier(ctx, "bob@example.com", true)
		require.NoError(t, err)
		require.NotNil(t, dmResp)
		require.NotNil(t, dmResp.Chat)
		mu.Lock()
		require.Equal(t, beforeDM+1, len(createDMReqs), "ResolveIdentifier(startChat=true) must reach create_dm on fake server")
		mu.Unlock()
	}

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)

	// 2. Walk every capability in RoomFeatures on the synced threaded space and DM and invoke its handler against the fake server.
	caps := client.GetCapabilities(ctx, threadedSpace)
	require.NotNil(t, caps)
	dmCaps := client.GetCapabilities(ctx, dmPortal)
	require.NotNil(t, dmCaps)

	// Unimplemented capabilities must NOT be advertised.
	require.False(t, caps.Poll.Partial(), "Poll must not be advertised without PollHandlingNetworkAPI")
	require.Nil(t, caps.DisappearingTimer, "DisappearingTimer must not be advertised without DisappearTimerChangingNetworkAPI")
	require.False(t, caps.LocationMessage.Partial(), "LocationMessage must not be advertised without location handler")
	require.False(t, caps.DeleteChat, "DeleteChat must be false on Spaces (hide_group only hides DMs)")
	require.True(t, dmCaps.DeleteChat, "DeleteChat must be true on DMs (hide_group)")

	// Walk State capabilities on Space (m.room.name and m.room.topic)
	require.NotEmpty(t, caps.State, "State capabilities must be advertised on Spaces")
	if nameCap, ok := caps.State[event.StateRoomName.Type]; ok && nameCap.Level.Partial() {
		nameAPI, ok := api.(bridgev2.RoomNameHandlingNetworkAPI)
		require.True(t, ok, "StateRoomName advertised without RoomNameHandlingNetworkAPI")
		mu.Lock()
		beforeUpd := len(updateGroupReqs)
		mu.Unlock()
		changed, err := nameAPI.HandleMatrixRoomName(ctx, &bridgev2.MatrixRoomName{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.RoomNameEventContent]{
				Portal:  threadedSpace,
				Content: &event.RoomNameEventContent{Name: "Cap Space Name"},
			},
		})
		require.NoError(t, err)
		require.True(t, changed)
		mu.Lock()
		require.Equal(t, beforeUpd+1, len(updateGroupReqs), "StateRoomName must reach update_group on fake server")
		mu.Unlock()
	}
	if topicCap, ok := caps.State[event.StateTopic.Type]; ok && topicCap.Level.Partial() {
		topicAPI, ok := api.(bridgev2.RoomTopicHandlingNetworkAPI)
		require.True(t, ok, "StateTopic advertised without RoomTopicHandlingNetworkAPI")
		mu.Lock()
		beforeGet := len(getGroupReqs)
		beforeUpd := len(updateGroupReqs)
		mu.Unlock()
		changed, err := topicAPI.HandleMatrixRoomTopic(ctx, &bridgev2.MatrixRoomTopic{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.TopicEventContent]{
				Portal:  threadedSpace,
				Content: &event.TopicEventContent{Topic: "Cap Space Topic"},
			},
		})
		require.NoError(t, err)
		require.True(t, changed)
		mu.Lock()
		require.Equal(t, beforeGet+1, len(getGroupReqs), "StateTopic must call get_group first")
		require.Equal(t, beforeUpd+1, len(updateGroupReqs), "StateTopic must reach update_group on fake server")
		mu.Unlock()
	}

	// Walk MemberActions on Space (Invite, Kick, Leave)
	require.NotEmpty(t, caps.MemberActions, "MemberActions must be advertised on Spaces")
	memAPI, ok := api.(bridgev2.MembershipHandlingNetworkAPI)
	require.True(t, ok, "MemberActions advertised without MembershipHandlingNetworkAPI")
	targetGhost, err := h.Bridge.GetGhostByID(ctx, MakeUserID("112233445566778899002"))
	require.NoError(t, err)
	if caps.MemberActions[event.MemberActionInvite].Partial() {
		mu.Lock()
		before := len(createMemReqs)
		mu.Unlock()
		_, err := memAPI.HandleMatrixMembership(ctx, &bridgev2.MatrixMembershipChange{
			MatrixRoomMeta: bridgev2.MatrixRoomMeta[*event.MemberEventContent]{
				MatrixEventBase: bridgev2.MatrixEventBase[*event.MemberEventContent]{
					Portal:  threadedSpace,
					Content: &event.MemberEventContent{Membership: event.MembershipInvite},
				},
			},
			Target: targetGhost,
			Type:   bridgev2.Invite,
		})
		require.NoError(t, err)
		mu.Lock()
		require.Equal(t, before+1, len(createMemReqs), "MemberActionInvite must reach create_membership on fake server")
		mu.Unlock()
	}
	if caps.MemberActions[event.MemberActionKick].Partial() {
		mu.Lock()
		before := len(removeMemReqs)
		mu.Unlock()
		_, err := memAPI.HandleMatrixMembership(ctx, &bridgev2.MatrixMembershipChange{
			MatrixRoomMeta: bridgev2.MatrixRoomMeta[*event.MemberEventContent]{
				MatrixEventBase: bridgev2.MatrixEventBase[*event.MemberEventContent]{
					Portal:  threadedSpace,
					Content: &event.MemberEventContent{Membership: event.MembershipLeave},
				},
			},
			Target: targetGhost,
			Type:   bridgev2.Kick,
		})
		require.NoError(t, err)
		mu.Lock()
		require.Equal(t, before+1, len(removeMemReqs), "MemberActionKick must reach remove_memberships on fake server")
		mu.Unlock()
	}
	if caps.MemberActions[event.MemberActionLeave].Partial() {
		mu.Lock()
		before := len(removeMemReqs)
		mu.Unlock()
		_, err := memAPI.HandleMatrixMembership(ctx, &bridgev2.MatrixMembershipChange{
			MatrixRoomMeta: bridgev2.MatrixRoomMeta[*event.MemberEventContent]{
				MatrixEventBase: bridgev2.MatrixEventBase[*event.MemberEventContent]{
					Portal:  threadedSpace,
					Content: &event.MemberEventContent{Membership: event.MembershipLeave},
				},
			},
			Target: ul,
			Type:   bridgev2.Leave,
		})
		require.NoError(t, err)
		mu.Lock()
		require.Equal(t, before+1, len(removeMemReqs), "MemberActionLeave must reach remove_memberships on fake server")
		mu.Unlock()
	}

	// Walk DeleteChat on DM
	if dmCaps.DeleteChat {
		delChatAPI, ok := api.(bridgev2.DeleteChatHandlingNetworkAPI)
		require.True(t, ok, "DeleteChat advertised without DeleteChatHandlingNetworkAPI")
		mu.Lock()
		before := len(hideGroupReqs)
		mu.Unlock()
		require.NoError(t, delChatAPI.HandleMatrixDeleteChat(ctx, &bridgev2.MatrixDeleteChat{
			Portal:  dmPortal,
			Content: &event.BeeperChatDeleteEventContent{},
		}))
		mu.Lock()
		require.Equal(t, before+1, len(hideGroupReqs), "DeleteChat on DM must reach hide_group on fake server")
		mu.Unlock()
	}

	// Walk every advertised Formatting capability and verify it reaches the fake server via HandleMatrixMessage.
	formattingSamples := map[event.FormattingFeature]string{
		event.FmtBold:                "<b>bold</b>",
		event.FmtItalic:              "<i>italic</i>",
		event.FmtStrikethrough:       "<s>strike</s>",
		event.FmtUnderline:           "<u>underline</u>",
		event.FmtInlineCode:          "<code>code</code>",
		event.FmtCodeBlock:           "<pre><code>block</code></pre>",
		event.FmtTextForegroundColor: `<span data-mx-color="#ff00aa">color</span>`,
		event.FmtUnorderedList:       "<ul><li>item</li></ul>",
		event.FmtOrderedList:         "<ol><li>step</li></ol>",
		event.FmtBlockquote:          "<blockquote>quote</blockquote>",
		event.FmtInlineLink:          `<a href="https://example.com">link</a>`,
		event.FmtUserLink:            `<a href="https://matrix.to/#/@gchat_112233445566778899002:courier.local">Alice</a>`,
		event.FmtAtRoomMention:       "Hello @room",
		event.FmtHeaders:             "<h1>Header</h1>",
	}
	var lastMsg *database.Message
	for fmtFeat, level := range caps.Formatting {
		if !level.Partial() {
			continue
		}
		sampleHTML, ok := formattingSamples[fmtFeat]
		require.True(t, ok, "missing test sample for advertised formatting feature %v", fmtFeat)
		mu.Lock()
		beforeTopics := len(createTopicReqs)
		mu.Unlock()
		resp, err := api.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
				Portal: threadedSpace,
				Content: &event.MessageEventContent{
					MsgType:       event.MsgText,
					Body:          sampleHTML,
					Format:        event.FormatHTML,
					FormattedBody: sampleHTML,
				},
			},
		})
		require.NoError(t, err, "formatting feature %v failed", fmtFeat)
		require.NotNil(t, resp.DB)
		lastMsg = resp.DB
		mu.Lock()
		afterTopics := len(createTopicReqs)
		lastTopicReq := createTopicReqs[len(createTopicReqs)-1]
		mu.Unlock()
		require.Equal(t, beforeTopics+1, afterTopics, "formatting feature %v must reach fake server", fmtFeat)
		if fmtFeat == event.FmtAtRoomMention {
			fields := parseProtoFields(lastTopicReq)
			require.Equal(t, "Hello @all", firstFieldString(fields, 2), "FmtAtRoomMention must rewrite @room to @all on wire")
			require.True(t, hasMentionAllAnnotation(fields[3]), "FmtAtRoomMention must emit MENTION_ALL annotation on wire")
		}
	}
	require.NotNil(t, lastMsg)

	// Walk every advertised File capability -> verify MaxSize and caption support reach the fake server via HandleMatrixMessage.
	capMediaURI, _, err := threadedSpace.Bridge.Bot.UploadMedia(ctx, threadedSpace.MXID, []byte("cap-media"), "cap.bin", "application/octet-stream")
	require.NoError(t, err)
	for msgType, fileCaps := range caps.File {
		if fileCaps == nil {
			continue
		}
		require.Equal(t, int64(200*1024*1024), fileCaps.MaxSize, "file capability %v must enforce 200 MiB MaxSize", msgType)
		mu.Lock()
		beforeTopics := len(createTopicReqs)
		mu.Unlock()
		resp, err := api.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
				Portal: threadedSpace,
				Content: &event.MessageEventContent{
					MsgType:  msgType,
					Body:     fmt.Sprintf("file-%s", msgType),
					FileName: fmt.Sprintf("file-%s.bin", msgType),
					URL:      capMediaURI,
				},
			},
		})
		require.NoError(t, err, "file capability %v failed", msgType)
		require.NotNil(t, resp.DB)
		mu.Lock()
		require.Equal(t, beforeTopics+1, len(createTopicReqs), "file capability %v must reach fake server", msgType)
		mu.Unlock()
	}

	// Walk Thread capability -> reaches /u/0/api/create_message
	if caps.Thread.Partial() {
		mu.Lock()
		beforeMsgs := len(createMsgReqs)
		mu.Unlock()
		_, err := api.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
				Portal:  threadedSpace,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Thread walk"},
			},
			ThreadRoot: lastMsg,
		})
		require.NoError(t, err)
		mu.Lock()
		require.Equal(t, beforeMsgs+1, len(createMsgReqs), "Thread capability must reach create_message on fake server")
		mu.Unlock()
	}

	// Walk Reply capability -> reaches fake server with SendReplyTarget
	if caps.Reply.Partial() {
		mu.Lock()
		beforeMsgs := len(createMsgReqs)
		mu.Unlock()
		_, err := api.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
				Portal:  threadedSpace,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Reply walk"},
			},
			ThreadRoot: lastMsg,
			ReplyTo:    lastMsg,
		})
		require.NoError(t, err)
		mu.Lock()
		require.Equal(t, beforeMsgs+1, len(createMsgReqs), "Reply capability must reach create_message on fake server")
		lastCreateMsg := parseProtoFields(createMsgReqs[len(createMsgReqs)-1])
		mu.Unlock()
		msgInfo := parseProtoFields(firstFieldBytes(lastCreateMsg, 7))
		require.NotEmpty(t, firstFieldBytes(msgInfo, 3), "Reply capability must populate SendReplyTarget on fake server")
	}

	// Walk Edit capability -> reaches /u/0/api/edit_message
	if caps.Edit.Partial() {
		editAPI, ok := api.(bridgev2.EditHandlingNetworkAPI)
		require.True(t, ok, "Edit advertised without EditHandlingNetworkAPI")
		mu.Lock()
		before := len(editReqs)
		mu.Unlock()
		require.NoError(t, editAPI.HandleMatrixEdit(ctx, &bridgev2.MatrixEdit{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
				Portal:  threadedSpace,
				Content: &event.MessageEventContent{MsgType: event.MsgText, Body: "Edit walk"},
			},
			EditTarget: lastMsg,
		}))
		mu.Lock()
		require.Equal(t, before+1, len(editReqs), "Edit capability must reach edit_message on fake server")
		mu.Unlock()
	}

	// Walk Reaction capability -> reaches /u/0/api/update_reaction (ADD and REMOVE)
	if caps.Reaction.Partial() {
		rxnAPI, ok := api.(bridgev2.ReactionHandlingNetworkAPI)
		require.True(t, ok, "Reaction advertised without ReactionHandlingNetworkAPI")
		mu.Lock()
		before := len(reactionReqs)
		mu.Unlock()
		rxnEvt := &bridgev2.MatrixReaction{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.ReactionEventContent]{
				Portal:  threadedSpace,
				Content: &event.ReactionEventContent{RelatesTo: event.RelatesTo{Key: "👍"}},
			},
			TargetMessage: lastMsg,
		}
		pre, err := rxnAPI.PreHandleMatrixReaction(ctx, rxnEvt)
		require.NoError(t, err)
		rxnEvt.PreHandleResp = &pre
		dbRxn, err := rxnAPI.HandleMatrixReaction(ctx, rxnEvt)
		require.NoError(t, err)
		require.NoError(t, rxnAPI.HandleMatrixReactionRemove(ctx, &bridgev2.MatrixReactionRemove{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{Portal: threadedSpace},
			TargetReaction: &database.Reaction{
				Room:      threadedSpace.PortalKey,
				MessageID: lastMsg.ID,
				EmojiID:   dbRxn.EmojiID,
				Emoji:     dbRxn.Emoji,
				Metadata:  dbRxn.Metadata,
			},
		}))
		mu.Lock()
		require.Equal(t, before+2, len(reactionReqs), "Reaction capability must reach update_reaction (ADD and REMOVE) on fake server")
		mu.Unlock()
	}

	// Walk Delete capability -> reaches /u/0/api/delete_message
	if caps.Delete.Partial() {
		delAPI, ok := api.(bridgev2.RedactionHandlingNetworkAPI)
		require.True(t, ok, "Delete advertised without RedactionHandlingNetworkAPI")
		mu.Lock()
		before := len(deleteReqs)
		mu.Unlock()
		require.NoError(t, delAPI.HandleMatrixMessageRemove(ctx, &bridgev2.MatrixMessageRemove{
			MatrixEventBase: bridgev2.MatrixEventBase[*event.RedactionEventContent]{Portal: threadedSpace},
			TargetMessage:   lastMsg,
		}))
		mu.Lock()
		require.Equal(t, before+1, len(deleteReqs), "Delete capability must reach delete_message on fake server")
		mu.Unlock()
	}

	// Walk ReadReceipts capability -> reaches /u/0/api/mark_group_readstate
	if caps.ReadReceipts {
		rrAPI, ok := api.(bridgev2.ReadReceiptHandlingNetworkAPI)
		require.True(t, ok, "ReadReceipts advertised without ReadReceiptHandlingNetworkAPI")
		mu.Lock()
		before := len(readStateReqs)
		mu.Unlock()
		require.NoError(t, rrAPI.HandleMatrixReadReceipt(ctx, &bridgev2.MatrixReadReceipt{
			Portal:   threadedSpace,
			ReadUpTo: time.UnixMicro(1710000700000000),
		}))
		mu.Lock()
		require.Equal(t, before+1, len(readStateReqs), "ReadReceipts capability must reach mark_group_readstate on fake server")
		mu.Unlock()
	}

	// Walk TypingNotifications capability -> reaches /u/0/api/set_typing_state
	if caps.TypingNotifications {
		typAPI, ok := api.(bridgev2.TypingHandlingNetworkAPI)
		require.True(t, ok, "TypingNotifications advertised without TypingHandlingNetworkAPI")
		mu.Lock()
		before := len(typingReqs)
		mu.Unlock()
		require.NoError(t, typAPI.HandleMatrixTyping(ctx, &bridgev2.MatrixTyping{
			Portal:   threadedSpace,
			IsTyping: true,
			Type:     bridgev2.TypingTypeText,
		}))
		mu.Lock()
		require.Equal(t, before+1, len(typingReqs), "TypingNotifications capability must reach set_typing_state on fake server")
		mu.Unlock()
	}
}

func parseProtoFields(buf []byte) map[int][]protoField {
	res := make(map[int][]protoField)
	protoIterFields(buf, func(f protoField) {
		res[f.num] = append(res[f.num], f)
	})
	return res
}

func firstFieldBytes(fields map[int][]protoField, num int) []byte {
	if fs := fields[num]; len(fs) > 0 {
		return fs[0].bytes
	}
	return nil
}

func firstFieldString(fields map[int][]protoField, num int) string {
	return string(firstFieldBytes(fields, num))
}

func firstFieldVarint(fields map[int][]protoField, num int) uint64 {
	if fs := fields[num]; len(fs) > 0 {
		return fs[0].varint
	}
	return 0
}

func encodeUploadMetadataProto(token, contentName, contentType string) []byte {
	var out []byte
	out = append(out, encodeStringField(1, token)...)
	out = append(out, encodeStringField(3, contentName)...)
	out = append(out, encodeStringField(4, contentType)...)
	return out
}

func encodeUploadMetadataAnnotationProto(startIdx, length int32, token, contentName, contentType string) []byte {
	var ann []byte
	ann = append(ann, encodeVarintField(1, 13)...) // AnnotationType.UPLOAD_METADATA = 13
	ann = append(ann, encodeVarintField(2, uint64(startIdx))...)
	ann = append(ann, encodeVarintField(3, uint64(length))...)
	ann = append(ann, encodeBytesField(10, encodeUploadMetadataProto(token, contentName, contentType))...)
	ann = append(ann, encodeVarintField(20, 1)...) // ChipRenderType.RENDER = 1
	return ann
}

func TestMultiAttachmentInboundUsesZeroPaddedPartIDsAndOutboundUploadsViaScotty(t *testing.T) {
	enableTestLoopback(t)
	ctx := context.Background()

	var (
		mu              sync.Mutex
		uploadStartReqs []string
		uploadPutBodies [][]byte
		createTopicReqs [][]byte
		createMsgReqs   [][]byte
		cdnGotCookie    atomic.Bool
		cdnGotXSRF      atomic.Bool
	)

	attBytes0 := []byte("\x89PNG\r\n\x1a\ninbound-image-zero")
	attBytes1 := []byte("%PDF-1.4\ninbound-pdf-one")

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_media_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticSelfUserStatusResponse("112233445566778899001"))
		case "/u/0/api/get_members":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSyntheticGetMembersResponse(
				"112233445566778899001",
				"Ada Lovelace",
				"ada@example.com",
				"https://example.invalid/avatar/ada.png",
			))
		case "/u/0/api/paginated_world":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/uploads", "/uploads":
			mu.Lock()
			idx := len(uploadStartReqs) + 1
			uploadStartReqs = append(uploadStartReqs, fmt.Sprintf("%s?%s|%s|%s", r.URL.Path, r.URL.RawQuery, r.Header.Get("X-Goog-Upload-Command"), string(body)))
			mu.Unlock()
			w.Header().Set("x-goog-upload-url", fmt.Sprintf("http://%s/u/0/upload_put?id=%d", r.Host, idx))
			w.WriteHeader(http.StatusOK)
		case "/u/0/upload_put":
			mu.Lock()
			uploadPutBodies = append(uploadPutBodies, body)
			idx := len(uploadPutBodies)
			mu.Unlock()
			upMeta := encodeUploadMetadataProto(fmt.Sprintf("out_tok_%d", idx), fmt.Sprintf("file_%d.bin", idx), "application/octet-stream")
			wrapped := encodeBytesField(1, upMeta)
			w.Header().Set("Content-Type", "text/plain")
			_, _ = fmt.Fprint(w, base64.StdEncoding.EncodeToString(wrapped))
		case "/u/0/api/create_topic":
			mu.Lock()
			createTopicReqs = append(createTopicReqs, body)
			idx := len(createTopicReqs)
			mu.Unlock()
			spaceGID := encodeSpaceGroupID("space_threaded")
			tid := fmt.Sprintf("topic_med_%d", idx)
			mid := fmt.Sprintf("msg_med_%d", idx)
			msgBytes := encodeSyntheticMessage(spaceGID, tid, mid, "112233445566778899001", "uploaded", 1710000800000000+int64(idx), "", 0, 0)
			var topic []byte
			topic = append(topic, encodeBytesField(1, encodeTopicID(spaceGID, tid))...)
			topic = append(topic, encodeBytesField(7, msgBytes)...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, topic))
		case "/u/0/api/create_message":
			mu.Lock()
			createMsgReqs = append(createMsgReqs, body)
			idx := len(createMsgReqs)
			mu.Unlock()
			dmGID := encodeDMGroupID("dm_alpha")
			msgBytes := encodeSyntheticMessage(dmGID, "dm_med_t", fmt.Sprintf("dm_med_m_%d", idx), "112233445566778899001", "uploaded", 1710000850000000+int64(idx), "", 0, 0)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(encodeBytesField(1, msgBytes))
		case "/u/0/api/get_attachment_url", "/api/get_attachment_url":
			tok := r.URL.Query().Get("attachment_token")
			port := r.Host[strings.LastIndex(r.Host, ":")+1:]
			http.Redirect(w, r, fmt.Sprintf("http://lh3.googleusercontent.com:%s/cdn/%s", port, tok), http.StatusFound)
		case "/cdn/in_tok_0":
			if r.Header.Get("Cookie") != "" {
				cdnGotCookie.Store(true)
			}
			if r.Header.Get("x-framework-xsrf-token") != "" {
				cdnGotXSRF.Store(true)
			}
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write(attBytes0)
		case "/cdn/in_tok_1":
			if r.Header.Get("Cookie") != "" {
				cdnGotCookie.Store(true)
			}
			if r.Header.Get("x-framework-xsrf-token") != "" {
				cdnGotXSRF.Store(true)
			}
			w.Header().Set("Content-Type", "application/pdf")
			_, _ = w.Write(attBytes1)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	mediaStore := &media.Store{Dir: filepath.Join(dir, "media")}
	conn := &Connector{baseURL: srv.URL}
	h, err := host.Start(ctx, dir, NetworkID, st, mediaStore, conn, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	user, err := h.Bridge.GetUserByMXID(ctx, "@me:courier.local")
	require.NoError(t, err)
	proc, err := conn.CreateLogin(ctx, user, FlowCookies)
	require.NoError(t, err)
	doneStep, err := proc.(bridgev2.LoginProcessCookies).SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
		"OSID":    "synthetic_osid",
		"SID":     "synthetic_sid",
		"HSID":    "synthetic_hsid",
		"SSID":    "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := doneStep.CompleteParams.UserLogin
	client := ul.Client.(*Client)
	t.Cleanup(client.Disconnect)

	// Build portals via the real syncWorld path.
	require.NoError(t, client.syncWorld(ctx))
	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)
	require.NoError(t, spacePortal.CreateMatrixRoom(ctx, ul, nil))

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)
	require.NoError(t, dmPortal.CreateMatrixRoom(ctx, ul, nil))

	countBlobs := func() int {
		var n int
		_ = filepath.WalkDir(mediaStore.Dir, func(_ string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() {
				n++
			}
			return nil
		})
		return n
	}

	// 0. Validate before storing/uploading: refused media (oversized > 200 MiB or unsupported type) leaves zero new blobs in mediaStore and sends nothing to /u/0/uploads.
	blobsBeforeRefusal := countBlobs()
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType:  event.MsgFile,
				Body:     "huge.bin",
				FileName: "huge.bin",
				URL:      "mxc://courier.local/nonexistent",
				Info:     &event.FileInfo{MimeType: "application/octet-stream", Size: 200*1024*1024 + 1},
			},
		},
	})
	require.Error(t, err, "media exceeding 200 MiB must be refused before reading or uploading")
	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType: event.CapMsgSticker,
				Body:    "sticker.webp",
				URL:     "mxc://courier.local/nonexistent",
				Info:    &event.FileInfo{MimeType: "image/webp", Size: 128},
			},
		},
	})
	require.Error(t, err, "unsupported sticker message type must be refused")
	require.Equal(t, blobsBeforeRefusal, countBlobs(), "refused media must leave zero new blobs in media.Store")
	mu.Lock()
	require.Empty(t, uploadStartReqs, "refused media must not send any request to /u/0/uploads")
	mu.Unlock()

	// 1. Outbound image, file, and voice note via HandleMatrixMessage on real synced portals -> Scotty 2-step upload + UPLOAD_METADATA annotation.
	imgBytes := []byte("\x89PNG\r\n\x1a\noutbound-image-bytes")
	imgURI, _, err := spacePortal.Bridge.Bot.UploadMedia(ctx, spacePortal.MXID, imgBytes, "screen.png", "image/png")
	require.NoError(t, err)

	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: spacePortal,
			Content: &event.MessageEventContent{
				MsgType:  event.MsgImage,
				Body:     "Look at this screenshot",
				FileName: "screen.png",
				URL:      imgURI,
				Info:     &event.FileInfo{MimeType: "image/png", Size: len(imgBytes)},
			},
		},
	})
	require.NoError(t, err)

	docBytes := []byte("outbound-file-bytes")
	docURI, _, err := dmPortal.Bridge.Bot.UploadMedia(ctx, dmPortal.MXID, docBytes, "notes.txt", "text/plain")
	require.NoError(t, err)

	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType:  event.MsgFile,
				Body:     "notes.txt",
				FileName: "notes.txt",
				URL:      docURI,
				Info:     &event.FileInfo{MimeType: "text/plain", Size: len(docBytes)},
			},
		},
	})
	require.NoError(t, err)

	voiceBytes := []byte("OggS\x00\x02outbound-voice-note")
	voiceURI, _, err := dmPortal.Bridge.Bot.UploadMedia(ctx, dmPortal.MXID, voiceBytes, "voice.ogg", "audio/ogg")
	require.NoError(t, err)

	_, err = client.HandleMatrixMessage(ctx, &bridgev2.MatrixMessage{
		MatrixEventBase: bridgev2.MatrixEventBase[*event.MessageEventContent]{
			Portal: dmPortal,
			Content: &event.MessageEventContent{
				MsgType:      event.MsgAudio,
				Body:         "voice.ogg",
				FileName:     "voice.ogg",
				URL:          voiceURI,
				Info:         &event.FileInfo{MimeType: "audio/ogg", Size: len(voiceBytes), Duration: 3000},
				MSC3245Voice: &event.MSC3245Voice{},
			},
		},
	})
	require.NoError(t, err)

	mu.Lock()
	require.Len(t, uploadStartReqs, 3, "image, file, and voice note must each initiate a Scotty upload")
	require.Len(t, uploadPutBodies, 3, "image, file, and voice note must each PUT bytes to x-goog-upload-url")
	require.Equal(t, imgBytes, uploadPutBodies[0])
	require.Equal(t, docBytes, uploadPutBodies[1])
	require.Equal(t, voiceBytes, uploadPutBodies[2])
	require.Len(t, createTopicReqs, 1)
	require.Len(t, createMsgReqs, 2)
	topicFields := parseProtoFields(createTopicReqs[0])
	mu.Unlock()

	require.Equal(t, "Look at this screenshot", firstFieldString(topicFields, 2), "caption must be preserved in text_body")
	var foundUploadAnn bool
	for _, annField := range topicFields[3] {
		af := parseProtoFields(annField.bytes)
		if firstFieldVarint(af, 1) == 13 { // UPLOAD_METADATA = 13
			foundUploadAnn = true
			require.Equal(t, uint64(1), firstFieldVarint(af, 20), "ChipRenderType must be RENDER (1)")
			um := parseProtoFields(firstFieldBytes(af, 10))
			require.Equal(t, "out_tok_1", firstFieldString(um, 1))
		}
	}
	require.True(t, foundUploadAnn, "outbound media message must attach UPLOAD_METADATA annotation")

	// 2. Inbound message with 2 UploadMetadata annotations -> downloads both attachments via get_attachment_url + redirect,
	// strips cookies on CDN hop, stores in media.Store, and emits zero-padded PartIDs "att_0000" and "att_0001".
	spaceGID := encodeSpaceGroupID("space_threaded")
	inMsg := encodeSyntheticMessage(spaceGID, "topic_in_med", "msg_in_med_1", "112233445566778899002", "Here are two files", 1710000900000000, "", 0, 0)
	inMsg = append(inMsg, encodeBytesField(11, encodeUploadMetadataAnnotationProto(0, 0, "in_tok_0", "chart.png", "image/png"))...)
	inMsg = append(inMsg, encodeBytesField(11, encodeUploadMetadataAnnotationProto(0, 0, "in_tok_1", "report.pdf", "application/pdf"))...)

	var evtBody []byte
	evtBody = append(evtBody, encodeBytesField(6, encodeBytesField(1, inMsg))...)
	evtBody = append(evtBody, encodeVarintField(12, 6)...) // MESSAGE_POSTED
	var evt []byte
	evt = append(evt, encodeBytesField(1, spaceGID)...)
	evt = append(evt, encodeVarintField(3, 6)...)
	evt = append(evt, encodeBytesField(4, evtBody)...)

	beforeRecorded := len(client.recordedRemoteEvents())
	client.processStreamNotification(ctx, streamNotification{kind: EventKindEventProto, payload: evt})
	afterRecorded := client.recordedRemoteEvents()
	require.Len(t, afterRecorded, beforeRecorded+1)

	preConv, ok := afterRecorded[len(afterRecorded)-1].(*simplevent.PreConvertedMessage)
	require.True(t, ok)
	require.Len(t, preConv.Data.Parts, 3, "text part + 2 attachment parts")
	require.Equal(t, networkid.PartID(""), preConv.Data.Parts[0].ID)
	require.Equal(t, "Here are two files", preConv.Data.Parts[0].Content.Body)

	require.Equal(t, networkid.PartID("att_0000"), preConv.Data.Parts[1].ID)
	require.Equal(t, event.MsgImage, preConv.Data.Parts[1].Content.MsgType)
	require.Equal(t, "chart.png", preConv.Data.Parts[1].Content.FileName)
	require.NotEmpty(t, preConv.Data.Parts[1].Content.URL)
	gotBytes0, err := spacePortal.Bridge.Bot.DownloadMedia(ctx, preConv.Data.Parts[1].Content.URL, nil)
	require.NoError(t, err)
	require.Equal(t, attBytes0, gotBytes0)

	require.Equal(t, networkid.PartID("att_0001"), preConv.Data.Parts[2].ID)
	require.Equal(t, event.MsgFile, preConv.Data.Parts[2].Content.MsgType)
	require.Equal(t, "report.pdf", preConv.Data.Parts[2].Content.FileName)
	require.NotEmpty(t, preConv.Data.Parts[2].Content.URL)
	gotBytes1, err := spacePortal.Bridge.Bot.DownloadMedia(ctx, preConv.Data.Parts[2].Content.URL, nil)
	require.NoError(t, err)
	require.Equal(t, attBytes1, gotBytes1)

	require.False(t, cdnGotCookie.Load(), "CDN redirect hop must never receive Google cookies")
	require.False(t, cdnGotXSRF.Load(), "CDN redirect hop must never receive XSRF header")
}

func TestInboundAttachmentFailureAndHTMLBecomePlaceholdersWithoutAbortingBatchAndExtractsField15AndAvatar(t *testing.T) {
	enableTestLoopback(t)
	ctx := context.Background()

	field15Bytes := []byte("\x89PNG\r\n\x1a\nfield15-attachment-png")
	avatarBytes := []byte("\x89PNG\r\n\x1a\nada-avatar-png")

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/u/0/mole/world":
			w.Header().Set("Content-Type", "text/html")
			_, _ = fmt.Fprint(w, `<!DOCTYPE html><html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_batch_token:1710000000000"};</script></html>`)
		case "/u/0/api/get_self_user_status":
			payload := buildSyntheticSelfUserStatusResponse("112233445566778899001")
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(payload)
		case "/u/0/api/get_members":
			port := r.Host[strings.LastIndex(r.Host, ":")+1:]
			payload := buildSyntheticGetMembersResponse(
				"112233445566778899002",
				"Grace Example",
				"grace@example.invalid",
				fmt.Sprintf("http://lh3.googleusercontent.com:%s/a/grace_avatar.png", port),
			)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(payload)
		case "/u/0/api/paginated_world":
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/list_topics":
			spaceGID := encodeSpaceGroupID("space_threaded")
			// Message 1: text + failed attachment (att_0000) + text/html attachment (att_0001) + Message.attachments field 15 (att_0002)
			msg1 := encodeSyntheticMessage(spaceGID, "topic_b1", "msg_b1", "112233445566778899002", "First message in batch", 1710000910000000, "", 0, 0)
			msg1 = append(msg1, encodeBytesField(11, encodeUploadMetadataAnnotationProto(0, 0, "tok_fail_500", "broken.bin", "application/octet-stream"))...)
			msg1 = append(msg1, encodeBytesField(11, encodeUploadMetadataAnnotationProto(0, 0, "tok_html_page", "login.html", "application/octet-stream"))...)
			// Message.attachments (field 15) -> Attachment { upload_metadata (field 14): UploadMetadata }
			attField15 := encodeBytesField(14, encodeUploadMetadataProto("tok_field15_ok", "inline_card.png", "image/png"))
			msg1 = append(msg1, encodeBytesField(15, attField15)...)

			var topic1 []byte
			topic1 = append(topic1, encodeBytesField(1, encodeTopicID(spaceGID, "topic_b1"))...)
			topic1 = append(topic1, encodeBytesField(7, msg1)...)

			// Message 2 in the same backfill batch must still arrive!
			msg2 := encodeSyntheticMessage(spaceGID, "topic_b2", "msg_b2", "112233445566778899002", "Second message in batch", 1710000920000000, "", 0, 0)
			var topic2 []byte
			topic2 = append(topic2, encodeBytesField(1, encodeTopicID(spaceGID, "topic_b2"))...)
			topic2 = append(topic2, encodeBytesField(7, msg2)...)

			var resp []byte
			resp = append(resp, encodeBytesField(1, topic1)...)
			resp = append(resp, encodeBytesField(1, topic2)...)
			w.Header().Set("Content-Type", "application/x-protobuf")
			_, _ = w.Write(resp)
		case "/u/0/api/get_attachment_url", "/api/get_attachment_url":
			tok := r.URL.Query().Get("attachment_token")
			port := r.Host[strings.LastIndex(r.Host, ":")+1:]
			http.Redirect(w, r, fmt.Sprintf("http://lh3.googleusercontent.com:%s/cdn/%s", port, tok), http.StatusFound)
		case "/cdn/tok_fail_500":
			w.WriteHeader(http.StatusInternalServerError)
		case "/cdn/tok_html_page":
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write([]byte("<!DOCTYPE html><html><body>Google Sign-In Error</body></html>"))
		case "/cdn/tok_field15_ok":
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write(field15Bytes)
		case "/a/grace_avatar.png":
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write(avatarBytes)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	dir := t.TempDir()
	st, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { _ = st.Close() })

	mediaStore := &media.Store{Dir: filepath.Join(dir, "media")}
	conn := &Connector{baseURL: srv.URL}
	h, err := host.Start(ctx, dir, NetworkID, st, mediaStore, conn, zerolog.Nop())
	require.NoError(t, err)
	t.Cleanup(h.Stop)

	user, err := h.Bridge.GetUserByMXID(ctx, "@me:courier.local")
	require.NoError(t, err)
	proc, err := conn.CreateLogin(ctx, user, FlowCookies)
	require.NoError(t, err)
	doneStep, err := proc.(bridgev2.LoginProcessCookies).SubmitCookies(ctx, map[string]string{
		"COMPASS": "dynamite-ui=synthetic_compass",
		"OSID":    "synthetic_osid",
		"SID":     "synthetic_sid",
		"HSID":    "synthetic_hsid",
		"SSID":    "synthetic_ssid",
	})
	require.NoError(t, err)
	ul := doneStep.CompleteParams.UserLogin
	client := ul.Client.(*Client)
	t.Cleanup(client.Disconnect)

	require.NoError(t, client.syncWorld(ctx))
	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)

	// 1. Backfill batch with failed + text/html + field-15 attachments must not abort Message 1 or Message 2.
	fetchResp, err := client.FetchMessages(ctx, bridgev2.FetchMessagesParams{
		Portal: spacePortal,
		Count:  10,
	})
	require.NoError(t, err, "per-attachment failures or text/html responses must not abort FetchMessages batch")
	require.Len(t, fetchResp.Messages, 2, "both messages in the backfill batch must arrive")

	m1Parts := fetchResp.Messages[0].ConvertedMessage.Parts
	require.Len(t, m1Parts, 4, "text part + 2 placeholder parts (att_0000, att_0001) + 1 valid field-15 attachment (att_0002)")
	require.Equal(t, networkid.PartID(""), m1Parts[0].ID)
	require.Equal(t, "First message in batch", m1Parts[0].Content.Body)

	require.Equal(t, networkid.PartID("att_0000"), m1Parts[1].ID)
	require.Equal(t, event.MsgNotice, m1Parts[1].Content.MsgType, "failed attachment must become a MsgNotice placeholder")
	require.Empty(t, m1Parts[1].Content.URL, "failed attachment placeholder must not store a media blob")

	require.Equal(t, networkid.PartID("att_0001"), m1Parts[2].ID)
	require.Equal(t, event.MsgNotice, m1Parts[2].Content.MsgType, "text/html attachment must become a MsgNotice placeholder")
	require.Empty(t, m1Parts[2].Content.URL, "text/html attachment must not store a media blob")

	require.Equal(t, networkid.PartID("att_0002"), m1Parts[3].ID)
	require.Equal(t, event.MsgImage, m1Parts[3].Content.MsgType)
	require.Equal(t, "inline_card.png", m1Parts[3].Content.FileName)
	require.NotEmpty(t, m1Parts[3].Content.URL)
	gotField15, err := spacePortal.Bridge.Bot.DownloadMedia(ctx, m1Parts[3].Content.URL, nil)
	require.NoError(t, err)
	require.Equal(t, field15Bytes, gotField15)

	require.Equal(t, "Second message in batch", fetchResp.Messages[1].ConvertedMessage.Parts[0].Content.Body)

	// 2. GetUserInfo wires downloadAvatar for ghost profile avatars.
	ghost, err := h.Bridge.GetGhostByID(ctx, MakeUserID("112233445566778899002"))
	require.NoError(t, err)
	uinfo, err := client.GetUserInfo(ctx, ghost)
	require.NoError(t, err)
	require.NotNil(t, uinfo.Avatar, "GetUserInfo must populate Avatar when get_members returns avatar_url")
	require.NotNil(t, uinfo.Avatar.Get)
	gotAvatar, err := uinfo.Avatar.Get(ctx)
	require.NoError(t, err)
	require.Equal(t, avatarBytes, gotAvatar)

	// 3. Verify catch-up / WebChannel event batch also converts failed/text-html attachments into placeholders without aborting the batch.
	var evt []byte
	spaceGID := encodeSpaceGroupID("space_threaded")
	evt = append(evt, encodeBytesField(1, spaceGID)...)
	evt = append(evt, encodeVarintField(3, 6)...) // MESSAGE_POSTED

	liveMsg1 := encodeSyntheticMessage(spaceGID, "topic_b1", "msg_live_1", "112233445566778899002", "Live msg with broken attachment", 1710000930000000, "", 0, 0)
	liveMsg1 = append(liveMsg1, encodeBytesField(11, encodeUploadMetadataAnnotationProto(0, 0, "tok_fail_500", "live_broken.bin", "application/octet-stream"))...)
	var body1 []byte
	body1 = append(body1, encodeBytesField(6, encodeBytesField(1, liveMsg1))...)
	body1 = append(body1, encodeVarintField(12, 6)...)

	liveMsg2 := encodeSyntheticMessage(spaceGID, "topic_b1", "msg_live_2", "112233445566778899002", "Live msg after broken attachment", 1710000940000000, "", 0, 0)
	var body2 []byte
	body2 = append(body2, encodeBytesField(6, encodeBytesField(1, liveMsg2))...)
	body2 = append(body2, encodeVarintField(12, 6)...)

	evt = append(evt, encodeBytesField(4, body1)...)
	evt = append(evt, encodeBytesField(8, body2)...)

	remoteEvts, err := client.translateWebChannelEvent(ctx, evt)
	require.NoError(t, err, "event translation must not abort when an attachment fails")
	require.Len(t, remoteEvts, 2, "both event bodies in the batch must be translated")
	preConv0, ok := remoteEvts[0].(*simplevent.PreConvertedMessage)
	require.True(t, ok)
	require.Len(t, preConv0.Data.Parts, 2)
	require.Equal(t, networkid.PartID("att_0000"), preConv0.Data.Parts[1].ID)
	require.Equal(t, event.MsgNotice, preConv0.Data.Parts[1].Content.MsgType)
}

func TestResolveIdentifierAndCreateDMByGaiaIDOrEmail(t *testing.T) {
	ctx := context.Background()
	var (
		mu             sync.Mutex
		createDMReqs   [][]byte
		getMembersReqs [][]byte
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/get_members":
			mu.Lock()
			getMembersReqs = append(getMembersReqs, body)
			mu.Unlock()
			if strings.Contains(string(body), "112233445566778899001") {
				_, _ = w.Write(buildSyntheticGetMembersResponse(
					"112233445566778899001",
					"Ada Lovelace",
					"ada@example.com",
					"https://example.invalid/avatar/ada.png",
				))
				return
			}
			_, _ = w.Write(buildSyntheticGetMembersResponse(
				"112233445566778899002",
				"Bob Example",
				"bob@example.com",
				"https://example.invalid/avatar/bob.png",
			))
		case "/u/0/api/create_dm":
			mu.Lock()
			createDMReqs = append(createDMReqs, body)
			idx := len(createDMReqs)
			mu.Unlock()

			dmID := fmt.Sprintf("dm_created_%d", idx)
			var dmGroup []byte
			dmGroup = append(dmGroup, encodeBytesField(1, encodeDMGroupID(dmID))...)

			var memSelf, memOther []byte
			memSelf = append(memSelf, encodeBytesField(1, encodeBytesField(1, encodeBytesField(1, encodeStringField(1, "112233445566778899001"))))...)
			memOther = append(memOther, encodeBytesField(1, encodeBytesField(1, encodeBytesField(1, encodeStringField(1, "112233445566778899002"))))...)

			var resp []byte
			resp = append(resp, encodeBytesField(1, dmGroup)...)
			resp = append(resp, encodeBytesField(4, memSelf)...)
			resp = append(resp, encodeBytesField(4, memOther)...)
			_, _ = w.Write(resp)
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	var api bridgev2.NetworkAPI = client
	resAPI, ok := api.(bridgev2.IdentifierResolvingNetworkAPI)
	require.True(t, ok, "Client must implement IdentifierResolvingNetworkAPI")
	ghostDMAPI, ok := api.(bridgev2.GhostDMCreatingNetworkAPI)
	require.True(t, ok, "Client must implement GhostDMCreatingNetworkAPI")

	// 1. Start a DM by email -> POST /u/0/api/create_dm with Invitees (field 7 -> InviteeInfo { email (field 2): "bob@example.com" })
	emailResp, err := resAPI.ResolveIdentifier(ctx, "bob@example.com", true)
	require.NoError(t, err)
	require.NotNil(t, emailResp)
	require.Equal(t, MakeUserID("112233445566778899002"), emailResp.UserID)
	require.NotNil(t, emailResp.Chat)
	require.Equal(t, MakeDMPortalID("dm_created_1"), emailResp.Chat.PortalKey.ID)
	require.Equal(t, ul.ID, emailResp.Chat.PortalKey.Receiver)
	require.NotNil(t, emailResp.Chat.PortalInfo)
	require.Equal(t, database.RoomTypeDM, *emailResp.Chat.PortalInfo.Type)

	mu.Lock()
	require.Len(t, createDMReqs, 1)
	emailDMFields := parseProtoFields(createDMReqs[0])
	mu.Unlock()
	inviteeFields := parseProtoFields(firstFieldBytes(emailDMFields, 7)) // CreateDmRequest.invitees = 7
	require.Equal(t, "bob@example.com", firstFieldString(inviteeFields, 2), "CreateDmRequest.invitees[0].email must match target email")
	require.Empty(t, emailDMFields[1], "email create_dm must use invitees (field 7), not members (field 1)")

	// 2. Start a DM by Gaia ID -> POST /u/0/api/create_dm with Members (field 1 -> UserId { id (field 1): "112233445566778899002", type (field 2): 0 })
	gaiaResp, err := resAPI.ResolveIdentifier(ctx, "112233445566778899002", true)
	require.NoError(t, err)
	require.NotNil(t, gaiaResp)
	require.Equal(t, MakeUserID("112233445566778899002"), gaiaResp.UserID)
	require.NotNil(t, gaiaResp.Chat)
	require.Equal(t, MakeDMPortalID("dm_created_2"), gaiaResp.Chat.PortalKey.ID)

	mu.Lock()
	require.Len(t, createDMReqs, 2)
	gaiaDMFields := parseProtoFields(createDMReqs[1])
	mu.Unlock()
	memberUserFields := parseProtoFields(firstFieldBytes(gaiaDMFields, 1)) // CreateDmRequest.members = 1
	require.Equal(t, "112233445566778899002", firstFieldString(memberUserFields, 1), "CreateDmRequest.members[0].id must match Gaia ID")
	require.Empty(t, gaiaDMFields[7], "Gaia ID create_dm must use members (field 1), not invitees (field 7)")

	// 3. CreateChatWithGhost (Reply Privately) -> POST /u/0/api/create_dm with Members
	ghost, err := h.Bridge.GetGhostByID(ctx, MakeUserID("112233445566778899002"))
	require.NoError(t, err)
	ghostChatResp, err := ghostDMAPI.CreateChatWithGhost(ctx, ghost)
	require.NoError(t, err)
	require.NotNil(t, ghostChatResp)
	require.Equal(t, MakeDMPortalID("dm_created_3"), ghostChatResp.PortalKey.ID)

	// 4. ResolveIdentifier with startChat=false by Gaia ID -> looks up user via get_members without calling create_dm
	mu.Lock()
	beforeDMCount := len(createDMReqs)
	mu.Unlock()
	lookupResp, err := resAPI.ResolveIdentifier(ctx, "112233445566778899002", false)
	require.NoError(t, err)
	require.NotNil(t, lookupResp)
	require.Equal(t, MakeUserID("112233445566778899002"), lookupResp.UserID)
	require.Nil(t, lookupResp.Chat)
	mu.Lock()
	require.Len(t, createDMReqs, beforeDMCount, "ResolveIdentifier(startChat=false) must not call create_dm")
	mu.Unlock()
}

func TestSetChatNameAndSetChatTopicPreservesSpaceGuidelines(t *testing.T) {
	ctx := context.Background()
	var (
		mu              sync.Mutex
		getGroupReqs    [][]byte
		updateGroupReqs [][]byte
		failGetGroup    atomic.Bool
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/get_group":
			mu.Lock()
			getGroupReqs = append(getGroupReqs, body)
			mu.Unlock()
			if failGetGroup.Load() {
				http.Error(w, "upstream get_group failure", http.StatusInternalServerError)
				return
			}
			var details []byte
			details = append(details, encodeStringField(1, "Initial space description")...)
			details = append(details, encodeStringField(2, "Be respectful and keep threads focused.")...)
			var grp []byte
			grp = append(grp, encodeBytesField(1, encodeSpaceGroupID("space_threaded"))...)
			grp = append(grp, encodeStringField(4, "Threaded Eng")...)
			grp = append(grp, encodeBytesField(37, details)...) // Group.group_details = 37
			_, _ = w.Write(encodeBytesField(1, grp))
		case "/u/0/api/update_group":
			mu.Lock()
			updateGroupReqs = append(updateGroupReqs, body)
			idx := len(updateGroupReqs)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, uint64(800+idx)))) // UpdateGroupResponse.group_revision = 2
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)
	require.NoError(t, spacePortal.CreateMatrixRoom(ctx, ul, nil))

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)
	require.NoError(t, dmPortal.CreateMatrixRoom(ctx, ul, nil))

	// 1. End-to-end rename Space through bridgev2 QueueMatrixEvent on synced portal -> POST /u/0/api/update_group
	emptyKey := ""
	nameRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$rename_space_1",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateRoomName,
		StateKey:  &emptyKey,
		Timestamp: 1710000800001,
		Content: event.Content{
			Parsed: &event.RoomNameEventContent{Name: "Core Platform Space"},
		},
	})
	require.True(t, nameRes.Success, "QueueMatrixEvent(StateRoomName) must succeed: %v", nameRes.Error)

	mu.Lock()
	require.Len(t, updateGroupReqs, 1)
	renameFields := parseProtoFields(updateGroupReqs[0])
	mu.Unlock()
	spaceIDFields := parseProtoFields(firstFieldBytes(renameFields, 1)) // UpdateGroupRequest.space_id = 1
	require.Equal(t, "space_threaded", firstFieldString(spaceIDFields, 1))
	require.Equal(t, "Core Platform Space", firstFieldString(renameFields, 2), "UpdateGroupRequest.name = 2")
	require.Equal(t, uint64(1), firstFieldVarint(renameFields, 4), "UpdateGroupRequest.update_masks = UpdateMask_NAME (1)")

	// 2. End-to-end change Space topic through bridgev2 QueueMatrixEvent -> calls get_group first, preserves guidelines, then calls update_group
	topicRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$topic_space_1",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateTopic,
		StateKey:  &emptyKey,
		Timestamp: 1710000800002,
		Content: event.Content{
			Parsed: &event.TopicEventContent{Topic: "Updated platform description"},
		},
	})
	require.True(t, topicRes.Success, "QueueMatrixEvent(StateTopic) must succeed: %v", topicRes.Error)

	mu.Lock()
	require.Len(t, getGroupReqs, 1, "changing topic must fetch existing group via get_group first")
	require.Len(t, updateGroupReqs, 2)
	getGrpFields := parseProtoFields(getGroupReqs[0])
	topicUpdFields := parseProtoFields(updateGroupReqs[1])
	mu.Unlock()

	getGrpID := parseProtoFields(firstFieldBytes(getGrpFields, 1))
	getSpaceID := parseProtoFields(firstFieldBytes(getGrpID, 1))
	require.Equal(t, "space_threaded", firstFieldString(getSpaceID, 1))

	updSpaceID := parseProtoFields(firstFieldBytes(topicUpdFields, 1))
	require.Equal(t, "space_threaded", firstFieldString(updSpaceID, 1))
	require.Equal(t, uint64(4), firstFieldVarint(topicUpdFields, 4), "UpdateGroupRequest.update_masks = UpdateMask_SPACE_DETAILS (4)")
	detailsFields := parseProtoFields(firstFieldBytes(topicUpdFields, 7)) // UpdateGroupRequest.space_details = 7
	require.Equal(t, "Updated platform description", firstFieldString(detailsFields, 1), "GroupDetails.description = 1")
	require.Equal(t, "Be respectful and keep threads focused.", firstFieldString(detailsFields, 2), "GroupDetails.guidelines = 2 must be preserved from get_group")

	// 3. If get_group fails, topic change must be refused and update_group must NOT be called (never wipe guidelines)
	failGetGroup.Store(true)
	failedTopicRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$topic_space_fail",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateTopic,
		StateKey:  &emptyKey,
		Timestamp: 1710000800003,
		Content: event.Content{
			Parsed: &event.TopicEventContent{Topic: "Would overwrite guidelines if allowed"},
		},
	})
	require.False(t, failedTopicRes.Success, "StateTopic must fail when get_group fails")
	require.Error(t, failedTopicRes.Error)
	mu.Lock()
	require.Len(t, updateGroupReqs, 2, "update_group must NOT be called when get_group fails")
	mu.Unlock()

	// 4. Renaming or changing topic on a DM is refused
	dmNameRes := dmPortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$rename_dm",
		RoomID:    dmPortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateRoomName,
		StateKey:  &emptyKey,
		Timestamp: 1710000800004,
		Content: event.Content{
			Parsed: &event.RoomNameEventContent{Name: "Not a space"},
		},
	})
	require.False(t, dmNameRes.Success, "renaming a DM must fail")
}

func TestMuteSyncAndMembershipAndHideGroup(t *testing.T) {
	ctx := context.Background()
	var (
		mu            sync.Mutex
		notifReqs     [][]byte
		createMemReqs [][]byte
		removeMemReqs [][]byte
		hideGroupReqs [][]byte
	)

	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(buildSendTestPaginatedWorldResponse())
		case "/u/0/api/update_group_notification_settings":
			mu.Lock()
			notifReqs = append(notifReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 901)))
		case "/u/0/api/create_membership":
			mu.Lock()
			createMemReqs = append(createMemReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 902)))
		case "/u/0/api/remove_memberships":
			mu.Lock()
			removeMemReqs = append(removeMemReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(3, encodeVarintField(1, 903)))
		case "/u/0/api/hide_group":
			mu.Lock()
			hideGroupReqs = append(hideGroupReqs, body)
			mu.Unlock()
			_, _ = w.Write(encodeBytesField(2, encodeVarintField(1, 904)))
		default:
			http.NotFound(w, r)
		}
	})

	require.NoError(t, client.syncWorld(ctx))

	spacePortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_threaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, spacePortal)
	require.NoError(t, spacePortal.CreateMatrixRoom(ctx, ul, nil))

	unthreadedSpace, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID("space_unthreaded"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, unthreadedSpace)
	require.NoError(t, unthreadedSpace.CreateMatrixRoom(ctx, ul, nil))

	dmPortal, err := h.Bridge.GetExistingPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeDMPortalID("dm_alpha"),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, dmPortal)
	require.NoError(t, dmPortal.CreateMatrixRoom(ctx, ul, nil))

	// 1. Permanent mute on Space -> POST /u/0/api/update_group_notification_settings (setting_type = 5, mute.state = 2)
	muteSpaceRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$mute_space",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.AccountDataBeeperMute,
		Timestamp: 1710000800010,
		Content: event.Content{
			Parsed: &event.BeeperMuteEventContent{MutedUntil: -1},
		},
	})
	require.True(t, muteSpaceRes.Success, "permanent mute on Space must succeed: %v", muteSpaceRes.Error)

	// 2. Unmute on Space -> POST /u/0/api/update_group_notification_settings (setting_type = 5, mute.state = 1)
	unmuteSpaceRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$unmute_space",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.AccountDataBeeperMute,
		Timestamp: 1710000800011,
		Content: event.Content{
			Parsed: &event.BeeperMuteEventContent{MutedUntil: 0},
		},
	})
	require.True(t, unmuteSpaceRes.Success, "unmute on Space must succeed: %v", unmuteSpaceRes.Error)

	// 3. Permanent mute on DM -> POST /u/0/api/update_group_notification_settings (setting_type = 4, mute.state = 2)
	muteDMRes := dmPortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$mute_dm",
		RoomID:    dmPortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.AccountDataBeeperMute,
		Timestamp: 1710000800012,
		Content: event.Content{
			Parsed: &event.BeeperMuteEventContent{MutedUntil: -1},
		},
	})
	require.True(t, muteDMRes.Success, "permanent mute on DM must succeed: %v", muteDMRes.Error)

	// 4. Timed mute (MutedUntil > 0) is refused with a plain-English message and sends no request
	timedMuteRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$timed_mute",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.AccountDataBeeperMute,
		Timestamp: 1710000800013,
		Content: event.Content{
			Parsed: &event.BeeperMuteEventContent{MutedUntil: 4102444800000},
		},
	})
	require.False(t, timedMuteRes.Success, "timed mute must be refused")
	require.Error(t, timedMuteRes.Error)
	require.Contains(t, timedMuteRes.Error.Error(), "permanent mute")

	mu.Lock()
	require.Len(t, notifReqs, 3, "only the 3 permanent mute/unmute events may reach fake server")
	muteSpaceFields := parseProtoFields(notifReqs[0])
	unmuteSpaceFields := parseProtoFields(notifReqs[1])
	muteDMFields := parseProtoFields(notifReqs[2])
	mu.Unlock()

	muteSpaceUpd := parseProtoFields(firstFieldBytes(muteSpaceFields, 2))
	require.Equal(t, uint64(5), firstFieldVarint(muteSpaceUpd, 2), "Space setting_type = MUTE_STATE_CHANGE (5)")
	require.Equal(t, uint64(2), firstFieldVarint(parseProtoFields(firstFieldBytes(muteSpaceUpd, 3)), 1), "Mute.state = MUTED (2)")

	unmuteSpaceUpd := parseProtoFields(firstFieldBytes(unmuteSpaceFields, 2))
	require.Equal(t, uint64(5), firstFieldVarint(unmuteSpaceUpd, 2))
	require.Equal(t, uint64(1), firstFieldVarint(parseProtoFields(firstFieldBytes(unmuteSpaceUpd, 3)), 1), "Mute.state = UNMUTED (1)")

	muteDMUpd := parseProtoFields(firstFieldBytes(muteDMFields, 2))
	require.Equal(t, uint64(4), firstFieldVarint(muteDMUpd, 2), "DM setting_type = NOTIFICATION_LEVEL_OR_MUTE_STATE_CHANGED (4)")
	require.Equal(t, uint64(2), firstFieldVarint(parseProtoFields(firstFieldBytes(muteDMUpd, 3)), 1), "Mute.state = MUTED (2)")

	// 5. Invite user to Space -> POST /u/0/api/create_membership
	_, err = h.Bridge.GetGhostByID(ctx, MakeUserID("112233445566778899002"))
	require.NoError(t, err)
	ghostMXID := "@gchat_112233445566778899002:courier.local"
	inviteRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$invite_bob",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &ghostMXID,
		Timestamp: 1710000800014,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipInvite},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipLeave)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
			},
		},
	})
	require.True(t, inviteRes.Success, "inviting member to Space must succeed: %v", inviteRes.Error)

	// 6. Accept invite to Space -> POST /u/0/api/create_membership with own MemberId
	meMXID := "@me:courier.local"
	acceptRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$accept_space",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &meMXID,
		Timestamp: 1710000800015,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipInvite)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipInvite},
			},
		},
	})
	require.True(t, acceptRes.Success, "accepting invite to Space must succeed: %v", acceptRes.Error)

	mu.Lock()
	require.Len(t, createMemReqs, 2)
	inviteFields := parseProtoFields(createMemReqs[0])
	acceptFields := parseProtoFields(createMemReqs[1])
	mu.Unlock()

	inviteGrp := parseProtoFields(firstFieldBytes(inviteFields, 4)) // CreateMembershipRequest.group_id = 4
	require.Equal(t, "space_threaded", firstFieldString(parseProtoFields(firstFieldBytes(inviteGrp, 1)), 1))
	inviteeInfo := parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(inviteFields, 8)), 1)) // invitee_member_infos (8) -> invitee_info (1)
	require.Equal(t, "112233445566778899002", firstFieldString(parseProtoFields(firstFieldBytes(inviteeInfo, 1)), 1))

	acceptMemID := parseProtoFields(firstFieldBytes(acceptFields, 2)) // CreateMembershipRequest.member_ids = 2
	require.Equal(t, "112233445566778899001", firstFieldString(parseProtoFields(firstFieldBytes(acceptMemID, 1)), 1))

	// 7. Kick member from Space -> POST /u/0/api/remove_memberships
	kickRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$kick_bob",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &ghostMXID,
		Timestamp: 1710000800016,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipJoin)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
			},
		},
	})
	require.True(t, kickRes.Success, "kicking member from Space must succeed: %v", kickRes.Error)

	// 8. Decline invite to Space -> POST /u/0/api/remove_memberships with own MemberId
	declineRes := unthreadedSpace.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$decline_space",
		RoomID:    unthreadedSpace.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &meMXID,
		Timestamp: 1710000800017,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipInvite)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipInvite},
			},
		},
	})
	require.True(t, declineRes.Success, "declining invite to Space must succeed: %v", declineRes.Error)

	// 9. Leave Space -> POST /u/0/api/remove_memberships with own MemberId
	leaveRes := spacePortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$leave_space",
		RoomID:    spacePortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &meMXID,
		Timestamp: 1710000800018,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipJoin)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
			},
		},
	})
	require.True(t, leaveRes.Success, "leaving Space must succeed: %v", leaveRes.Error)

	mu.Lock()
	require.Len(t, removeMemReqs, 3, "kick, decline invite, and leave Space must each call remove_memberships")
	kickFields := parseProtoFields(removeMemReqs[0])
	declineFields := parseProtoFields(removeMemReqs[1])
	leaveFields := parseProtoFields(removeMemReqs[2])
	mu.Unlock()

	require.Equal(t, "112233445566778899002", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(kickFields, 1)), 1)), 1))
	require.Equal(t, "space_threaded", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(kickFields, 2)), 1)), 1))

	require.Equal(t, "112233445566778899001", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(declineFields, 1)), 1)), 1))
	require.Equal(t, "space_unthreaded", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(declineFields, 2)), 1)), 1))

	require.Equal(t, "112233445566778899001", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(leaveFields, 1)), 1)), 1))
	require.Equal(t, "space_threaded", firstFieldString(parseProtoFields(firstFieldBytes(parseProtoFields(firstFieldBytes(leaveFields, 2)), 1)), 1))

	// 10. Hide DM: leaving a DM via StateMember (Leave) or deleting a DM via BeeperDeleteChat calls hide_group with hide=true; DeleteForEveryone=true is refused
	leaveDMRes := dmPortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$leave_dm",
		RoomID:    dmPortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.StateMember,
		StateKey:  &meMXID,
		Timestamp: 1710000800019,
		Content: event.Content{
			Parsed: &event.MemberEventContent{Membership: event.MembershipLeave},
		},
		Unsigned: event.Unsigned{
			PrevContent: &event.Content{
				Raw:    map[string]any{"membership": string(event.MembershipJoin)},
				Parsed: &event.MemberEventContent{Membership: event.MembershipJoin},
			},
		},
	})
	require.True(t, leaveDMRes.Success, "leaving DM must call hide_group: %v", leaveDMRes.Error)

	delEveryoneRes := dmPortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$delete_dm_everyone",
		RoomID:    dmPortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.BeeperDeleteChat,
		Timestamp: 1710000800020,
		Content: event.Content{
			Parsed: &event.BeeperChatDeleteEventContent{DeleteForEveryone: true},
		},
	})
	require.False(t, delEveryoneRes.Success, "DeleteForEveryone on DM must be refused")

	delDMRes := dmPortal.Bridge.QueueMatrixEvent(ctx, &event.Event{
		ID:        "$delete_dm",
		RoomID:    dmPortal.MXID,
		Sender:    "@me:courier.local",
		Type:      event.BeeperDeleteChat,
		Timestamp: 1710000800021,
		Content: event.Content{
			Parsed: &event.BeeperChatDeleteEventContent{DeleteForEveryone: false},
		},
	})
	require.True(t, delDMRes.Success, "deleting/hiding DM must succeed: %v", delDMRes.Error)

	mu.Lock()
	require.Len(t, hideGroupReqs, 2, "both leaving DM and deleting DM must call hide_group")
	hideFields := parseProtoFields(hideGroupReqs[1])
	mu.Unlock()
	hideGrpID := parseProtoFields(firstFieldBytes(hideFields, 1)) // HideGroupRequest.id = 1
	require.Equal(t, "dm_alpha", firstFieldString(parseProtoFields(firstFieldBytes(hideGrpID, 3)), 1))
	require.Equal(t, uint64(1), firstFieldVarint(hideFields, 2), "HideGroupRequest.hide = true (1)")
}
