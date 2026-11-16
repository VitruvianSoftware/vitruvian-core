// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

const (
	ownGaia    = "112233445566778899001"
	annGaia    = "112233445566778899002"
	bobGaia    = "112233445566778899003"
	githubGaia = "103512937927001688260"
)

func appUserID(gaiaID string) *pb.UserId {
	return &pb.UserId{Id: pb.String(gaiaID), Type: pb.UserType_BOT.Enum()}
}

func appMemberID(gaiaID string) *pb.MemberId {
	return &pb.MemberId{Id: &pb.MemberId_UserId{UserId: appUserID(gaiaID)}}
}

func joinedMembership(m *pb.MemberId) *pb.Membership {
	return &pb.Membership{
		Id:              &pb.MembershipId{MemberId: m},
		MembershipState: pb.MembershipState_MEMBER_JOINED.Enum(),
	}
}

// membersAPI answers get_members with a name for each of the test's people and for the GitHub app, and get_group
// with memberships and (when groupName is not blank) a group name.
func membersAPI(groupName string, memberships ...*pb.Membership) http.HandlerFunc {
	names := map[string]string{annGaia: "Ann", bobGaia: "Bob", githubGaia: "GitHub"}
	return func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/get_group":
			g := &pb.Group{}
			if groupName != "" {
				g.Name = pb.String(groupName)
			}
			_, _ = w.Write(pb.MustMarshal(&pb.GetGroupResponse{Group: g, Memberships: memberships}))
		case "/u/0/api/get_members":
			var req pb.GetMembersRequest
			_ = pb.Unmarshal(body, &req)
			uid := ""
			if len(req.GetMemberIds()) > 0 {
				uid = req.GetMemberIds()[0].GetUserId().GetId()
			}
			if name, ok := names[uid]; ok {
				_, _ = w.Write(buildSyntheticGetMembersResponse(uid, name, "", ""))
				return
			}
			http.NotFound(w, r)
		default:
			http.NotFound(w, r)
		}
	}
}

func memberUserIDs(m bridgev2.ChatMemberMap) []networkid.UserID {
	var out []networkid.UserID
	for id := range m {
		out = append(out, id)
	}
	return out
}

func TestIsAppUser(t *testing.T) {
	require.True(t, isAppUser(appUserID(githubGaia)))
	require.False(t, isAppUser(pb.HumanUserID(annGaia)))
	require.False(t, isAppUser(&pb.UserId{Id: pb.String(annGaia)}), "a UserId with no type is a person")
	require.False(t, isAppUser(nil))
}

func TestMemberRosterKeepsAppsAnyListSaysSo(t *testing.T) {
	var r memberRoster
	r.add(pb.HumanUserID(ownGaia))
	r.add(appUserID(githubGaia))
	// A later list names the same ID without a type: it stays an app, and is listed once.
	r.add(&pb.UserId{Id: pb.String(githubGaia)})
	r.add(pb.HumanUserID(" "))
	r.add(nil)
	require.Equal(t, []string{ownGaia, githubGaia}, r.ids)
	require.Equal(t, []string{githubGaia}, r.appIDs())
}

func TestVisibleMemberIDs(t *testing.T) {
	own := MakeUserID(ownGaia)
	tests := []struct {
		name    string
		members []string
		apps    []string
		want    []string
	}{
		{"no apps", []string{ownGaia, annGaia}, nil, []string{ownGaia, annGaia}},
		{"app dropped", []string{ownGaia, annGaia, bobGaia, githubGaia}, []string{githubGaia}, []string{ownGaia, annGaia, bobGaia}},
		{"one person and an app is a DM with that person", []string{ownGaia, annGaia, githubGaia}, []string{githubGaia}, []string{ownGaia, annGaia}},
		{"only me and an app keeps the app", []string{ownGaia, githubGaia}, []string{githubGaia}, []string{ownGaia, githubGaia}},
		{"only an app keeps the app", []string{githubGaia}, []string{githubGaia}, []string{githubGaia}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, visibleMemberIDs(tc.members, tc.apps, own))
		})
	}
}

func TestMergeAppIDsKeepsOnlyCurrentMembers(t *testing.T) {
	got := mergeAppIDs([]string{"a", "gone"}, []string{"b", "a", " "}, []string{"a", "b", "c"})
	require.Equal(t, []string{"a", "b"}, got)
	require.Empty(t, mergeAppIDs(nil, nil, []string{"a"}))
}

func TestSameNameList(t *testing.T) {
	require.True(t, sameNameList("Ann, Bob, GitHub", "GitHub, Ann, Bob"))
	require.True(t, sameNameList("Ann", "Ann"))
	require.False(t, sameNameList("Ann, Bob", "Ann, Bob, GitHub"))
	require.False(t, sameNameList("Release crew", "Ann, Bob"))
	require.False(t, sameNameList("", ""), "no name is not a composed name")
}

func TestBuildChatMemberListWithAppsLeftOutHasOnlyPeople(t *testing.T) {
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	own := client.ownUserID()
	visible := visibleMemberIDs([]string{ownGaia, annGaia, bobGaia, githubGaia}, []string{githubGaia}, own)
	list := client.buildChatMemberList(own, false, "", visible, true)
	require.True(t, list.IsFull, "a full list is what removes an app already in the room")
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia), MakeUserID(bobGaia)}, memberUserIDs(list.MemberMap))
}

func TestGetChatInfoGroupLeavesAppOutOfMembersAndComposedName(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	))
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_with_app"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	// What an older build stored: the app listed as a member and in the name it composed.
	portal.Name = "Ann, Bob, GitHub"
	portal.NameSet = true
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, bobGaia, githubGaia}}

	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.NotNil(t, info.Name)
	require.Equal(t, "Ann, Bob", *info.Name, "an old composed name is recomposed from the people")
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia), MakeUserID(bobGaia)}, memberUserIDs(info.Members.MemberMap))
	require.True(t, info.Members.IsFull)
	require.Empty(t, info.Members.OtherUserID, "two people besides me is a group")

	meta := portal.Metadata.(*PortalMetadata)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.True(t, meta.AppRosterChecked)
}

func TestGetChatInfoNeverRenamesAChatWithAnExplicitName(t *testing.T) {
	ctx := context.Background()
	t.Run("name from Google Chat", func(t *testing.T) {
		h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(
			"Release Room",
			joinedMembership(pb.UserMemberID(annGaia)),
			joinedMembership(pb.UserMemberID(bobGaia)),
			joinedMembership(appMemberID(githubGaia)),
		))
		portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("named_space"), Receiver: ul.ID})
		require.NoError(t, err)
		portal.Name = "Ann, Bob, GitHub"
		portal.Metadata = &PortalMetadata{MemberUserIDs: []string{annGaia, bobGaia, githubGaia}}

		info, err := client.GetChatInfo(ctx, portal)
		require.NoError(t, err)
		require.Equal(t, "Release Room", *info.Name)
		require.NotContains(t, memberUserIDs(info.Members.MemberMap), MakeUserID(githubGaia))
	})
	t.Run("name someone typed", func(t *testing.T) {
		h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(
			"",
			joinedMembership(pb.UserMemberID(annGaia)),
			joinedMembership(pb.UserMemberID(bobGaia)),
			joinedMembership(appMemberID(githubGaia)),
		))
		portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("typed_space"), Receiver: ul.ID})
		require.NoError(t, err)
		portal.Name = "Release crew"
		portal.NameSet = true
		portal.Metadata = &PortalMetadata{MemberUserIDs: []string{annGaia, bobGaia, githubGaia}}

		info, err := client.GetChatInfo(ctx, portal)
		require.NoError(t, err)
		require.Equal(t, "Release crew", *info.Name)
		require.NotContains(t, memberUserIDs(info.Members.MemberMap), MakeUserID(githubGaia))
	})
}

func TestGetChatInfoDMWithOnePersonAndAnAppIsStillADM(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(appMemberID(githubGaia)),
	))
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("ann_and_app"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	portal.Name = "Ann, GitHub"
	portal.NameSet = true
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, githubGaia}}

	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.Equal(t, database.RoomTypeDM, *info.Type)
	require.Equal(t, MakeUserID(annGaia), info.Members.OtherUserID, "the person is the DM's other user")
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia)}, memberUserIDs(info.Members.MemberMap))
	require.Equal(t, "Ann", *info.Name)
}

func TestGetChatInfoDMWithOnlyAnAppKeepsTheApp(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(""))
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("just_the_app"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	portal.OtherUserID = MakeUserID(githubGaia)
	portal.Name = "GitHub"
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, githubGaia}, AppUserIDs: []string{githubGaia}}

	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.Equal(t, MakeUserID(githubGaia), info.Members.OtherUserID)
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(githubGaia)}, memberUserIDs(info.Members.MemberMap))
	require.Equal(t, "GitHub", *info.Name)
}

func TestParseWorldItemSeparatesAppsFromPeople(t *testing.T) {
	item := parseWorldItemLiteFromProto(&pb.WorldItemLite{
		GroupId: pb.DMGroupID("grp"),
		ReadState: &pb.GroupReadState{
			JoinedUsers: []*pb.UserId{pb.HumanUserID(ownGaia), pb.HumanUserID(annGaia), appUserID(githubGaia)},
		},
		DmMembers: &pb.WorldItemLite_DmMembers{
			Members:     []*pb.UserId{pb.HumanUserID(bobGaia)},
			Memberships: []*pb.WorldItemLite_MembershipLite{{UserId: &pb.UserId{Id: pb.String(githubGaia)}}},
		},
	})
	require.Equal(t, []string{ownGaia, annGaia, githubGaia, bobGaia}, item.memberUserIDs)
	require.Equal(t, []string{githubGaia}, item.appUserIDs)
}

func TestSyncWorldLeavesAppsOutOfMembersAndRepairsOldNames(t *testing.T) {
	ctx := context.Background()
	groupAPI := membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/u/0/api/paginated_world" {
			groupAPI(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/x-protobuf")
		_, _ = w.Write(pb.MustMarshal(&pb.PaginatedWorldResponse{
			UserRevision: &pb.ReadRevision{Timestamp: pb.Int64(700)},
			WorldItems: []*pb.WorldItemLite{{
				GroupId:       pb.DMGroupID("grp_world"),
				GroupRevision: &pb.ReadRevision{Timestamp: pb.Int64(10)},
				SortTimestamp: pb.Int64(1710000002000000),
				ReadState: &pb.GroupReadState{
					MembershipState: pb.MembershipState_MEMBER_JOINED.Enum(),
					JoinedUsers:     []*pb.UserId{pb.HumanUserID(ownGaia), pb.HumanUserID(annGaia), pb.HumanUserID(bobGaia), appUserID(githubGaia)},
				},
			}},
		}))
	})

	// The chat as an older build left it: composed name with the app in it.
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_world"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.Name = "Ann, Bob, GitHub"
	portal.NameSet = true
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, bobGaia, githubGaia}}
	require.NoError(t, portal.Save(ctx))

	require.NoError(t, client.syncWorld(ctx))

	resyncs := client.recordedChatResyncs()
	require.Len(t, resyncs, 1)
	members := resyncs[0].ChatInfo.Members
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia), MakeUserID(bobGaia)}, memberUserIDs(members.MemberMap))
	require.True(t, members.IsFull)

	meta := portal.Metadata.(*PortalMetadata)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.True(t, meta.AppRosterChecked, "the chat's roster is read once, and the answer kept")
	require.Equal(t, "Ann, Bob", portal.Name, "the stored composed name is repaired on the same sync")
}

func TestMembershipChangedForAnAppAddsNoMember(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	gid := pb.SpaceGroupID("space_with_app")
	changed := func(m *pb.MemberId) []byte {
		return pb.MustMarshal(&pb.Event{
			GroupId: gid,
			Type:    pb.Event_MEMBERSHIP_CHANGED.Enum(),
			Body: &pb.Event_EventBody{
				Type: &pb.Event_EventBody_MembershipChanged{
					MembershipChanged: &pb.MembershipChangedEvent{
						NewMembership: &pb.Membership{
							Id:              &pb.MembershipId{MemberId: m, GroupId: gid},
							MembershipState: pb.MembershipState_MEMBER_JOINED.Enum(),
						},
					},
				},
				EventType: pb.Event_MEMBERSHIP_CHANGED.Enum(),
			},
		})
	}

	evts, err := client.translateWebChannelEvent(ctx, changed(pb.UserMemberID(annGaia)))
	require.NoError(t, err)
	require.Len(t, evts, 1, "a person joining is a member change")
	_, ok := evts[0].(*simplevent.ChatInfoChange)
	require.True(t, ok)

	evts, err = client.translateWebChannelEvent(ctx, changed(appMemberID(githubGaia)))
	require.NoError(t, err)
	require.Empty(t, evts, "an app joining or leaving is not a member change")
}

func TestMembershipChangedForAnAppKnownFromTheStoredRosterAddsNoMember(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_known_app"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{annGaia, githubGaia}, AppUserIDs: []string{githubGaia}}
	require.NoError(t, portal.Save(ctx))

	gid := pb.SpaceGroupID("space_known_app")
	// This event does not carry the member's type (an older payload shape).
	evts, err := client.translateWebChannelEvent(ctx, pb.MustMarshal(&pb.Event{
		GroupId: gid,
		Type:    pb.Event_MEMBERSHIP_CHANGED.Enum(),
		Body: &pb.Event_EventBody{
			Type: &pb.Event_EventBody_MembershipChanged{
				MembershipChanged: &pb.MembershipChangedEvent{
					NewMembership: &pb.Membership{
						Id: &pb.MembershipId{
							MemberId: &pb.MemberId{Id: &pb.MemberId_UserId{UserId: &pb.UserId{Id: pb.String(githubGaia)}}},
							GroupId:  gid,
						},
						MembershipState: pb.MembershipState_MEMBER_NOT_A_MEMBER.Enum(),
					},
				},
			},
			EventType: pb.Event_MEMBERSHIP_CHANGED.Enum(),
		},
	}))
	require.NoError(t, err)
	require.Empty(t, evts)
}

func TestMessageFromAnAppStillArrivesWithItsOwnSender(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	gid := pb.SpaceGroupID("space_app_says")
	msg := buildSyntheticMessageProto(gid, "topic_1", "msg_1", githubGaia, "Build passed", 1710000000000000, "", 0, 0)
	msg.Creator.UserId = appUserID(githubGaia)
	msg.Creator.Name = pb.String("GitHub")

	evts, err := client.translateWebChannelEvent(ctx, pb.MustMarshal(&pb.Event{
		GroupId: gid,
		Type:    pb.Event_MESSAGE_POSTED.Enum(),
		Body: &pb.Event_EventBody{
			Type:      &pb.Event_EventBody_MessagePosted{MessagePosted: &pb.MessageEvent{Message: msg}},
			EventType: pb.Event_MESSAGE_POSTED.Enum(),
		},
	}))
	require.NoError(t, err)
	require.Len(t, evts, 1, "an app's message is not dropped")
	require.Equal(t, bridgev2.RemoteEventMessage, evts[0].GetType())
	require.Equal(t, MakeUserID(githubGaia), evts[0].GetSender().Sender, "the message keeps the app as its sender")
}

func TestPortalMetadataDecodesOldStoredJSON(t *testing.T) {
	raw := fmt.Sprintf(
		`{"revision":5,"group_revision":5,"member_user_ids":[%q,%q,%q]}`,
		ownGaia, annGaia, githubGaia,
	)
	var meta PortalMetadata
	require.NoError(t, json.Unmarshal([]byte(raw), &meta))
	require.Equal(t, int64(5), meta.Revision)
	require.Equal(t, int64(5), meta.GroupRevision)
	require.Equal(t, []string{ownGaia, annGaia, githubGaia}, meta.MemberUserIDs)
	require.Empty(t, meta.AppUserIDs)
	require.False(t, meta.AppRosterChecked)

	encoded, err := json.Marshal(&meta)
	require.NoError(t, err)
	require.NotContains(t, string(encoded), "app_user_ids")
	require.NotContains(t, string(encoded), "app_roster_checked")
}

func TestRepairRetriedWhenGetGroupFails(t *testing.T) {
	ctx := context.Background()
	fallback := membersAPI("")
	var getGroupHits atomic.Int32
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/u/0/api/get_group" {
			getGroupHits.Add(1)
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		fallback(w, r)
	})
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_get_group_fail"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	portal.Metadata = &PortalMetadata{
		MemberUserIDs:    []string{ownGaia, annGaia, bobGaia, githubGaia},
		AppRosterChecked: false,
	}

	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.NotNil(t, info)
	require.Equal(t, int32(1), getGroupHits.Load())

	meta := portal.Metadata.(*PortalMetadata)
	require.False(t, meta.AppRosterChecked)
	require.True(t, client.needsAppRosterCheck(portal, client.ownUserID()))
}

func TestAppRemovalFromTheRoomIsNotATimelineEvent(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	))
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_silent"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, bobGaia, githubGaia}}

	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.True(t, info.Members.IsFull, "a full list is what takes the app out of the room")
	require.True(t, info.Members.ExcludeChangesFromTimeline, "the app's removal must not post a 'left' line in the chat")

	// A chat with no app keeps real-time member changes visible.
	h2, ul2, client2 := setupLoggedInGChatTestEnv(t, membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
	))
	other, err := h2.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_no_app"), Receiver: ul2.ID})
	require.NoError(t, err)
	other.RoomType = database.RoomTypeDM
	other.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, bobGaia}}
	plain, err := client2.GetChatInfo(ctx, other)
	require.NoError(t, err)
	require.False(t, plain.Members.ExcludeChangesFromTimeline)
}

func TestSyncWorldResyncOfAChatWithAnAppIsSilent(t *testing.T) {
	ctx := context.Background()
	groupAPI := membersAPI("")
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/u/0/api/paginated_world" {
			groupAPI(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/x-protobuf")
		_, _ = w.Write(pb.MustMarshal(&pb.PaginatedWorldResponse{
			UserRevision: &pb.ReadRevision{Timestamp: pb.Int64(700)},
			WorldItems: []*pb.WorldItemLite{{
				GroupId:       pb.DMGroupID("grp_world_silent"),
				GroupRevision: &pb.ReadRevision{Timestamp: pb.Int64(10)},
				SortTimestamp: pb.Int64(1710000002000000),
				ReadState: &pb.GroupReadState{
					MembershipState: pb.MembershipState_MEMBER_JOINED.Enum(),
					JoinedUsers:     []*pb.UserId{pb.HumanUserID(ownGaia), pb.HumanUserID(annGaia), pb.HumanUserID(bobGaia), appUserID(githubGaia)},
				},
			}},
		}))
	})
	_, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_world_silent"), Receiver: ul.ID})
	require.NoError(t, err)

	require.NoError(t, client.syncWorld(ctx))
	resyncs := client.recordedChatResyncs()
	require.Len(t, resyncs, 1)
	require.True(t, resyncs[0].ChatInfo.Members.ExcludeChangesFromTimeline)
}

func typingEvent(gid *pb.GroupId, u *pb.UserId) []byte {
	return pb.MustMarshal(&pb.Event{
		GroupId: gid,
		Type:    pb.Event_TYPING_STATE_CHANGED.Enum(),
		Body: &pb.Event_EventBody{
			Type: &pb.Event_EventBody_TypingStateChanged{
				TypingStateChanged: &pb.TypingStateChangedEvent{
					State:              pb.TypingState_TYPING.Enum(),
					UserId:             u,
					Context:            &pb.TypingContext{Context: &pb.TypingContext_GroupId{GroupId: gid}},
					StartTimestampUsec: pb.Int64(1710000125000000),
				},
			},
			EventType: pb.Event_TYPING_STATE_CHANGED.Enum(),
		},
	})
}

func TestAnAppIsNeverShownTyping(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_typing"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{annGaia, githubGaia}, AppUserIDs: []string{githubGaia}}
	require.NoError(t, portal.Save(ctx))
	gid := pb.SpaceGroupID("space_typing")

	evts, err := client.translateWebChannelEvent(ctx, typingEvent(gid, pb.HumanUserID(annGaia)))
	require.NoError(t, err)
	require.Len(t, evts, 1, "a person typing is shown")

	evts, err = client.translateWebChannelEvent(ctx, typingEvent(gid, appUserID(githubGaia)))
	require.NoError(t, err)
	require.Empty(t, evts, "an app typing, by its own type, is not shown")

	evts, err = client.translateWebChannelEvent(ctx, typingEvent(gid, &pb.UserId{Id: pb.String(githubGaia)}))
	require.NoError(t, err)
	require.Empty(t, evts, "an app typing, known from the chat's roster, is not shown")
}

func TestAnAppIsNeverShownReadingAChat(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_reads"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{annGaia, bobGaia, githubGaia}, AppUserIDs: []string{githubGaia}}
	require.NoError(t, portal.Save(ctx))

	receipt := func(u *pb.UserId) *pb.ReadReceipt {
		return &pb.ReadReceipt{ReadTimeMicros: pb.Int64(1710000200000000), User: &pb.User{UserId: u}}
	}
	evts := client.readReceiptEvents(ctx, false, "space_reads", &pb.ReadReceiptSet{ReadReceipts: []*pb.ReadReceipt{
		receipt(pb.HumanUserID(annGaia)),
		receipt(appUserID(githubGaia)),
		receipt(&pb.UserId{Id: pb.String(githubGaia)}),
		receipt(appUserID("100000000000000000009")), // an app the chat's roster does not name yet
		receipt(pb.HumanUserID(bobGaia)),
	}})
	var readers []networkid.UserID
	for _, e := range evts {
		readers = append(readers, e.GetSender().Sender)
	}
	require.Equal(t, []networkid.UserID{MakeUserID(annGaia), MakeUserID(bobGaia)}, readers)
}

func TestCreateDMKeepsWhichMembersAreApps(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/create_dm":
			_, _ = w.Write(pb.MustMarshal(&pb.CreateDmResponse{
				Dm:            &pb.Group{GroupId: pb.DMGroupID("dm_created_app")},
				GroupRevision: &pb.WriteRevision{Timestamp: pb.Int64(1710000500000000)},
				Memberships: []*pb.Membership{
					joinedMembership(pb.UserMemberID(ownGaia)),
					joinedMembership(appMemberID(githubGaia)),
					joinedMembership(pb.UserMemberID(annGaia)),
				},
			}))
		case "/u/0/api/get_members":
			_, _ = w.Write(buildSyntheticGetMembersResponse(annGaia, "Ann", "", ""))
		default:
			http.NotFound(w, r)
		}
	})

	res, err := client.createDM(ctx, annGaia, "")
	require.NoError(t, err)
	require.Equal(t, MakeUserID(annGaia), res.UserID, "the DM's peer is the person, not the app")
	members := res.Chat.PortalInfo.Members
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia)}, memberUserIDs(members.MemberMap))
	require.True(t, members.ExcludeChangesFromTimeline)

	meta := res.Chat.Portal.Metadata.(*PortalMetadata)
	require.ElementsMatch(t, []string{ownGaia, githubGaia, annGaia}, meta.MemberUserIDs)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.True(t, meta.AppRosterChecked, "create_dm already carried each member's type: no second read")
	require.False(t, client.needsAppRosterCheck(res.Chat.Portal, client.ownUserID()))
}

func TestAGoogleGivenNameIsRememberedAcrossFailedReads(t *testing.T) {
	ctx := context.Background()
	fallback := membersAPI(
		"Ann, Bob, GitHub",
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	var failGetGroup atomic.Bool
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/u/0/api/get_group" && failGetGroup.Load() {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		fallback(w, r)
	})
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeDMPortalID("grp_google_name"), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDM
	portal.Name = "Ann, Bob, GitHub"
	portal.NameSet = true
	portal.Metadata = &PortalMetadata{MemberUserIDs: []string{ownGaia, annGaia, bobGaia, githubGaia}}

	// Google gives the chat a name that happens to list the app: it is Google's, so it stays, and is remembered.
	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.Equal(t, "Ann, Bob, GitHub", *info.Name)
	require.True(t, portal.Metadata.(*PortalMetadata).NameFromGoogle)

	// A later read that fails must not let the same name be taken for one this client composed.
	failGetGroup.Store(true)
	info, err = client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.Equal(t, "Ann, Bob, GitHub", *info.Name)
	require.NotContains(t, memberUserIDs(info.Members.MemberMap), MakeUserID(githubGaia), "the app is still left out of the members")
}

func TestSyncWorldRemembersAGoogleGivenRoomName(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-protobuf")
		switch r.URL.Path {
		case "/u/0/api/paginated_world":
			_, _ = w.Write(pb.MustMarshal(&pb.PaginatedWorldResponse{
				UserRevision: &pb.ReadRevision{Timestamp: pb.Int64(700)},
				WorldItems: []*pb.WorldItemLite{{
					GroupId:       pb.SpaceGroupID("space_named_world"),
					GroupRevision: &pb.ReadRevision{Timestamp: pb.Int64(10)},
					SortTimestamp: pb.Int64(1710000002000000),
					ReadState:     &pb.GroupReadState{MembershipState: pb.MembershipState_MEMBER_JOINED.Enum()},
					RoomName:      pb.String("Ann, Bob, GitHub"),
				}},
			}))
		default:
			_, _ = w.Write(pb.MustMarshal(&pb.GetGroupResponse{}))
		}
	})
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID("space_named_world"), Receiver: ul.ID})
	require.NoError(t, err)

	require.NoError(t, client.syncWorld(ctx))
	require.True(t, portal.Metadata.(*PortalMetadata).NameFromGoogle)
}

// spaceWorldAPI answers paginated_world with one joined space that lists no members (as Google does for a space)
// and serves everything else, get_group included, from groupAPI.
func spaceWorldAPI(spaceID, roomName string, groupAPI http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/u/0/api/paginated_world" {
			groupAPI(w, r)
			return
		}
		item := &pb.WorldItemLite{
			GroupId:       pb.SpaceGroupID(spaceID),
			GroupRevision: &pb.ReadRevision{Timestamp: pb.Int64(10)},
			SortTimestamp: pb.Int64(1710000002000000),
			ReadState:     &pb.GroupReadState{MembershipState: pb.MembershipState_MEMBER_JOINED.Enum()},
		}
		if roomName != "" {
			item.RoomName = pb.String(roomName)
		}
		w.Header().Set("Content-Type", "application/x-protobuf")
		_, _ = w.Write(pb.MustMarshal(&pb.PaginatedWorldResponse{
			UserRevision: &pb.ReadRevision{Timestamp: pb.Int64(700)},
			WorldItems:   []*pb.WorldItemLite{item},
		}))
	}
}

// spacePortalWithName is a space portal as an older build left it: no member list, no app roster, and (the
// interesting part) whatever name it had composed or been given.
func spacePortalWithName(t *testing.T, ctx context.Context, bridge *bridgev2.Bridge, ul *bridgev2.UserLogin, spaceID, name string) *bridgev2.Portal {
	t.Helper()
	portal, err := bridge.GetPortalByKey(ctx, networkid.PortalKey{ID: MakeSpacePortalID(spaceID), Receiver: ul.ID})
	require.NoError(t, err)
	portal.RoomType = database.RoomTypeDefault
	portal.Name = name
	portal.NameSet = true
	portal.Metadata = &PortalMetadata{Revision: 5, GroupRevision: 5, ThreadsEnabled: true}
	require.NoError(t, portal.Save(ctx))
	return portal
}

func TestSyncWorldLeavesAppsOutOfAnUnnamedSpaceAndRepairsItsName(t *testing.T) {
	ctx := context.Background()
	groupAPI := membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_unnamed", "", groupAPI))
	portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_unnamed", "Ann, Bob, GitHub")

	require.NoError(t, client.syncWorld(ctx))

	meta := portal.Metadata.(*PortalMetadata)
	require.ElementsMatch(t, []string{ownGaia, annGaia, bobGaia, githubGaia}, meta.MemberUserIDs)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.True(t, meta.AppRosterChecked, "the space's roster is read once, and the answer kept")
	require.False(t, meta.NameFromGoogle)
	require.Equal(t, "Ann, Bob", portal.Name, "the composed name that listed the app is recomposed from the people")
	require.False(t, client.needsAppRosterCheck(portal, client.ownUserID()), "read once, not again")

	// The same read, seen as the chat info it hands the room: people only, and the app leaves silently.
	portal.Metadata = &PortalMetadata{Revision: 5, GroupRevision: 5, ThreadsEnabled: true}
	info, err := client.GetChatInfo(ctx, portal)
	require.NoError(t, err)
	require.ElementsMatch(t, []networkid.UserID{"", MakeUserID(annGaia), MakeUserID(bobGaia)}, memberUserIDs(info.Members.MemberMap))
	require.True(t, info.Members.IsFull)
	require.True(t, info.Members.ExcludeChangesFromTimeline, "the app's removal must not post a 'left' line")
}

func TestSyncWorldNeverRenamesANamedSpace(t *testing.T) {
	ctx := context.Background()
	people := []*pb.Membership{
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	}
	t.Run("name from Google Chat's world list", func(t *testing.T) {
		// The name happens to list the app, but Google gave it: it stays.
		h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_named_world", "Ann, Bob, GitHub", membersAPI("Ann, Bob, GitHub", people...)))
		portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_named_world", "Ann, Bob, GitHub")
		require.NoError(t, client.syncWorld(ctx))
		meta := portal.Metadata.(*PortalMetadata)
		require.Equal(t, "Ann, Bob, GitHub", portal.Name)
		require.True(t, meta.NameFromGoogle)
		require.Equal(t, []string{githubGaia}, meta.AppUserIDs, "the app is still left out of the members")
		require.True(t, meta.AppRosterChecked)
	})
	t.Run("name from get_group", func(t *testing.T) {
		h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_named_group", "", membersAPI("Release Room", people...)))
		portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_named_group", "Ann, Bob, GitHub")
		require.NoError(t, client.syncWorld(ctx))
		meta := portal.Metadata.(*PortalMetadata)
		require.Equal(t, "Release Room", portal.Name)
		require.True(t, meta.NameFromGoogle)
		require.True(t, meta.AppRosterChecked)
	})
}

func TestSyncWorldLeavesAnUnnamedSpaceWithADifferentStoredNameAlone(t *testing.T) {
	ctx := context.Background()
	groupAPI := membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_typed", "", groupAPI))
	// Google gives the space no name, but this one is not the list of everyone's names: someone typed it.
	portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_typed", "Release crew")

	require.NoError(t, client.syncWorld(ctx))

	meta := portal.Metadata.(*PortalMetadata)
	require.Equal(t, "Release crew", portal.Name)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs, "the app is still told apart")
	require.True(t, meta.AppRosterChecked)
}

func TestSyncWorldRetriesASpaceRepairWhenGetGroupFails(t *testing.T) {
	ctx := context.Background()
	fallback := membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	var failGetGroup atomic.Bool
	failGetGroup.Store(true)
	h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_retry", "", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/u/0/api/get_group" && failGetGroup.Load() {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		fallback(w, r)
	}))
	portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_retry", "Ann, Bob, GitHub")

	require.NoError(t, client.syncWorld(ctx))
	meta := portal.Metadata.(*PortalMetadata)
	require.False(t, meta.AppRosterChecked, "a failed read is not an answer")
	require.True(t, client.needsAppRosterCheck(portal, client.ownUserID()))
	require.Equal(t, "Ann, Bob, GitHub", portal.Name, "nothing is changed on a guess")

	failGetGroup.Store(false)
	require.NoError(t, client.syncWorld(ctx))
	meta = portal.Metadata.(*PortalMetadata)
	require.True(t, meta.AppRosterChecked)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.Equal(t, "Ann, Bob", portal.Name)
}

func TestSyncWorldKeepsAGoogleGivenSpaceNameWhenGetGroupOmitsIt(t *testing.T) {
	ctx := context.Background()
	groupAPI := membersAPI(
		"",
		joinedMembership(pb.UserMemberID(ownGaia)),
		joinedMembership(pb.UserMemberID(annGaia)),
		joinedMembership(pb.UserMemberID(bobGaia)),
		joinedMembership(appMemberID(githubGaia)),
	)
	h, ul, client := setupLoggedInGChatTestEnv(t, spaceWorldAPI("space_world_named", "Ann, Bob, GitHub", groupAPI))
	portal := spacePortalWithName(t, ctx, h.Bridge, ul, "space_world_named", "Ann, Bob, GitHub")

	require.NoError(t, client.syncWorld(ctx))

	meta := portal.Metadata.(*PortalMetadata)
	require.Equal(t, "Ann, Bob, GitHub", portal.Name)
	require.True(t, meta.NameFromGoogle)
	require.Equal(t, []string{githubGaia}, meta.AppUserIDs)
	require.True(t, meta.AppRosterChecked)
}
