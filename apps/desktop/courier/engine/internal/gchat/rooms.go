// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

var (
	_ bridgev2.IdentifierResolvingNetworkAPI = (*Client)(nil)
	_ bridgev2.GhostDMCreatingNetworkAPI     = (*Client)(nil)
	_ bridgev2.RoomNameHandlingNetworkAPI    = (*Client)(nil)
	_ bridgev2.RoomTopicHandlingNetworkAPI   = (*Client)(nil)
	_ bridgev2.MuteHandlingNetworkAPI        = (*Client)(nil)
	_ bridgev2.MembershipHandlingNetworkAPI  = (*Client)(nil)
	_ bridgev2.DeleteChatHandlingNetworkAPI  = (*Client)(nil)
)

const (
	notificationSettingTypeDM    int32 = 4
	notificationSettingTypeSpace int32 = 5
)

// ParseUserID returns the raw Gaia ID from a networkid.UserID (stripping an optional "gchat_" or "user_" prefix).
func ParseUserID(id networkid.UserID) string {
	s := strings.TrimSpace(string(id))
	s = strings.TrimPrefix(s, "gchat_")
	s = strings.TrimPrefix(s, "user_")
	return s
}

// ParseUserLoginID returns the raw Gaia ID from a networkid.UserLoginID.
func ParseUserLoginID(id networkid.UserLoginID) string {
	return strings.TrimSpace(string(id))
}

// ResolveIdentifier resolves a Google Chat user by Gaia ID or email address and optionally creates or fetches a DM.
func (c *Client) ResolveIdentifier(ctx context.Context, identifier string, startChat bool) (*bridgev2.ResolveIdentifierResponse, error) {
	identifier = strings.TrimSpace(identifier)
	if identifier == "" {
		return nil, errors.New("Google Chat needs an email address or user ID.")
	}

	isEmail := strings.Contains(identifier, "@")
	if !isEmail {
		identifier = ParseUserID(networkid.UserID(identifier))
	}

	if !startChat {
		if isEmail {
			return nil, errors.New("Enter a Google Chat user ID to look up a contact without starting a chat.")
		}
		userID := MakeUserID(identifier)
		var ghost *bridgev2.Ghost
		if c.UserLogin != nil && c.UserLogin.Bridge != nil {
			ghost, _ = c.UserLogin.Bridge.GetGhostByID(ctx, userID)
		}
		var userInfo *bridgev2.UserInfo
		if ghost != nil {
			userInfo, _ = c.GetUserInfo(ctx, ghost)
		}
		return &bridgev2.ResolveIdentifierResponse{
			Ghost:    ghost,
			UserID:   userID,
			UserInfo: userInfo,
		}, nil
	}

	var gaiaID, email string
	if isEmail {
		email = identifier
	} else {
		gaiaID = identifier
	}
	return c.createDM(ctx, gaiaID, email)
}

// CreateChatWithGhost starts or opens a direct message with an existing Google Chat ghost.
func (c *Client) CreateChatWithGhost(ctx context.Context, ghost *bridgev2.Ghost) (*bridgev2.CreateChatResponse, error) {
	if ghost == nil {
		return nil, errors.New("missing contact for direct message")
	}
	gaiaID := ParseUserID(ghost.ID)
	if gaiaID == "" {
		return nil, errors.New("missing Google Chat user ID for contact")
	}
	res, err := c.createDM(ctx, gaiaID, "")
	if err != nil {
		return nil, err
	}
	return res.Chat, nil
}

func (c *Client) createDM(ctx context.Context, targetGaiaID, targetEmail string) (*bridgev2.ResolveIdentifierResponse, error) {
	if c.UserLogin == nil {
		return nil, errors.New("not logged in")
	}

	reqProto := &pb.CreateDmRequest{}
	if targetEmail != "" {
		reqProto.Invitees = []*pb.InviteeInfo{
			{Email: pb.String(targetEmail)},
		}
	} else {
		reqProto.Members = []*pb.UserId{
			pb.HumanUserID(targetGaiaID),
		}
	}

	reqBytes, err := pb.Marshal(reqProto)
	if err != nil {
		return nil, fmt.Errorf("marshal create_dm request: %w", err)
	}
	respBytes, err := c.rpcCall(ctx, "create_dm", reqBytes)
	if err != nil {
		return nil, fmt.Errorf("Could not start Google Chat direct message: %w", err)
	}

	var resp pb.CreateDmResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		return nil, fmt.Errorf("decode create_dm response: %w", err)
	}

	var dmID string
	if rawID, _, ok := pb.GroupIDToParts(resp.GetDm().GetGroupId()); ok && rawID != "" {
		dmID = rawID
	}
	if dmID == "" {
		return nil, errors.New("Google Chat did not return a direct message ID.")
	}

	dmName := resp.GetDm().GetName()
	groupRev := resp.GetGroupRevision().GetTimestamp()
	if groupRev == 0 {
		groupRev = resp.GetDm().GetRevisionTime()
	}

	var memberGaiaIDs []string
	addMember := func(id string) {
		if id == "" {
			return
		}
		for _, existing := range memberGaiaIDs {
			if existing == id {
				return
			}
		}
		memberGaiaIDs = append(memberGaiaIDs, id)
	}
	for _, u := range resp.GetDm().GetGroupReadState().GetJoinedUsers() {
		addMember(u.GetId())
	}
	for _, m := range resp.GetMemberships() {
		addMember(m.GetId().GetMemberId().GetUserId().GetId())
	}

	ownGaia := ParseUserLoginID(c.UserLogin.ID)
	otherGaia := targetGaiaID
	for _, m := range memberGaiaIDs {
		if m != "" && m != ownGaia {
			otherGaia = m
			break
		}
	}
	if otherGaia == "" && len(memberGaiaIDs) > 0 {
		otherGaia = memberGaiaIDs[0]
	}

	otherUserID := MakeUserID(otherGaia)
	var ghost *bridgev2.Ghost
	var userInfo *bridgev2.UserInfo
	if otherGaia != "" && c.UserLogin.Bridge != nil {
		ghost, _ = c.UserLogin.Bridge.GetGhostByID(ctx, otherUserID)
		if ghost != nil {
			userInfo, _ = c.GetUserInfo(ctx, ghost)
		}
	}

	portalKey := networkid.PortalKey{
		ID:       MakeDMPortalID(dmID),
		Receiver: c.UserLogin.ID,
	}
	var portal *bridgev2.Portal
	if c.UserLogin.Bridge != nil {
		portal, _ = c.UserLogin.Bridge.GetPortalByKey(ctx, portalKey)
	}
	if portal != nil {
		portal.RoomType = database.RoomTypeDM
		if otherUserID != "" {
			portal.OtherUserID = otherUserID
		}
		if dmName != "" {
			portal.Name = dmName
			portal.NameSet = portal.MXID != ""
		}
		c.metaMu.Lock()
		meta, ok := portal.Metadata.(*PortalMetadata)
		if !ok || meta == nil {
			meta = &PortalMetadata{}
		}
		if groupRev > meta.GroupRevision {
			meta.GroupRevision = groupRev
			meta.Revision = groupRev
		}
		portal.Metadata = meta
		c.metaMu.Unlock()
	}

	roomType := database.RoomTypeDM
	memberMap := make(bridgev2.ChatMemberMap)
	level := 50
	memberMap[""] = bridgev2.ChatMember{
		EventSender: bridgev2.EventSender{
			IsFromMe:    true,
			SenderLogin: c.UserLogin.ID,
			Sender:      c.ownUserID(),
		},
		Membership: "join",
		PowerLevel: &level,
	}
	if otherGaia != "" {
		memberMap[otherUserID] = bridgev2.ChatMember{
			EventSender: bridgev2.EventSender{Sender: otherUserID},
			Membership:  "join",
			PowerLevel:  &level,
			UserInfo:    userInfo,
		}
	}

	chatInfo := &bridgev2.ChatInfo{
		Type: &roomType,
		Members: &bridgev2.ChatMemberList{
			IsFull:           true,
			OtherUserID:      otherUserID,
			CheckAllLogins:   true,
			TotalMemberCount: len(memberMap),
			MemberMap:        memberMap,
			PowerLevels: &bridgev2.PowerLevelOverrides{
				Invite:       &level,
				Kick:         &level,
				StateDefault: &level,
			},
		},
	}
	if dmName != "" {
		chatInfo.Name = &dmName
	} else if userInfo != nil && userInfo.Name != nil && *userInfo.Name != "" {
		n := *userInfo.Name
		chatInfo.Name = &n
	}

	return &bridgev2.ResolveIdentifierResponse{
		Ghost:    ghost,
		UserID:   otherUserID,
		UserInfo: userInfo,
		Chat: &bridgev2.CreateChatResponse{
			PortalKey:  portalKey,
			Portal:     portal,
			PortalInfo: chatInfo,
		},
	}, nil
}

// HandleMatrixRoomName renames a Google Chat Space via update_group.
func (c *Client) HandleMatrixRoomName(ctx context.Context, msg *bridgev2.MatrixRoomName) (bool, error) {
	if msg == nil || msg.Portal == nil || msg.Content == nil {
		return false, errors.New("missing room name event")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return false, err
	}
	if isDM {
		return false, errors.New("Google Chat direct messages cannot be renamed.")
	}

	reqBytes, err := pb.Marshal(&pb.UpdateGroupRequest{
		SpaceId:     &pb.SpaceId{SpaceId: pb.String(rawGroupID)},
		Name:        pb.String(msg.Content.Name),
		UpdateMasks: []pb.UpdateGroupRequest_UpdateMask{pb.UpdateGroupRequest_NAME},
	})
	if err != nil {
		return false, fmt.Errorf("marshal update_group request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "update_group", reqBytes)
	if err != nil {
		return false, fmt.Errorf("Could not rename Google Chat space: %w", err)
	}
	msg.Portal.Name = msg.Content.Name
	msg.Portal.NameSet = true
	c.advanceRevisionFromUpdateGroup(ctx, msg.Portal, respBytes)
	return true, nil
}

// HandleMatrixRoomTopic updates a Google Chat Space description via update_group (UpdateMask_SPACE_DETAILS),
// first reading the current Space via get_group so existing guidelines are preserved and never wiped.
func (c *Client) HandleMatrixRoomTopic(ctx context.Context, msg *bridgev2.MatrixRoomTopic) (bool, error) {
	if msg == nil || msg.Portal == nil || msg.Content == nil {
		return false, errors.New("missing room topic event")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return false, err
	}
	if isDM {
		return false, errors.New("Google Chat direct messages do not have a topic.")
	}

	getReqBytes, err := pb.Marshal(&pb.GetGroupRequest{
		GroupId: pb.SpaceGroupID(rawGroupID),
		FetchOptions: []pb.GetGroupRequest_FetchOptions{
			pb.GetGroupRequest_MEMBERS,
			pb.GetGroupRequest_INCLUDE_DYNAMIC_GROUP_NAME,
		},
		IncludeInviteDms: pb.Bool(true),
	})
	if err != nil {
		return false, fmt.Errorf("marshal get_group request: %w", err)
	}

	getRespBytes, err := c.rpcCall(ctx, "get_group", getReqBytes)
	if err != nil {
		return false, fmt.Errorf("Could not read current space details before changing topic: %w", err)
	}

	var getResp pb.GetGroupResponse
	if err := pb.Unmarshal(getRespBytes, &getResp); err != nil {
		return false, fmt.Errorf("decode get_group response: %w", err)
	}

	details := &pb.GroupDetails{
		Description: pb.String(msg.Content.Topic),
	}
	if existingGuidelines := getResp.GetGroup().GetGroupDetails().GetGuidelines(); existingGuidelines != "" {
		details.Guidelines = pb.String(existingGuidelines)
	}

	updReqBytes, err := pb.Marshal(&pb.UpdateGroupRequest{
		SpaceId:      &pb.SpaceId{SpaceId: pb.String(rawGroupID)},
		UpdateMasks:  []pb.UpdateGroupRequest_UpdateMask{pb.UpdateGroupRequest_SPACE_DETAILS},
		SpaceDetails: details,
	})
	if err != nil {
		return false, fmt.Errorf("marshal update_group request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "update_group", updReqBytes)
	if err != nil {
		return false, fmt.Errorf("Could not update Google Chat space topic: %w", err)
	}
	msg.Portal.Topic = msg.Content.Topic
	msg.Portal.TopicSet = true
	c.advanceRevisionFromUpdateGroup(ctx, msg.Portal, respBytes)
	return true, nil
}

func (c *Client) advanceRevisionFromUpdateGroup(ctx context.Context, portal *bridgev2.Portal, respBytes []byte) {
	var resp pb.UpdateGroupResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		return
	}
	if groupRev := resp.GetGroupRevision().GetTimestamp(); groupRev > 0 && portal != nil {
		_ = c.advancePortalGroupRevision(ctx, portal.PortalKey, groupRev)
	}
}

// HandleMute syncs permanent mute or unmute state to Google Chat via update_group_notification_settings.
// Timed mutes (MutedUntil > 0) are refused with a plain-English error.
func (c *Client) HandleMute(ctx context.Context, msg *bridgev2.MatrixMute) error {
	if msg == nil || msg.Portal == nil || msg.Content == nil {
		return errors.New("missing mute event")
	}
	if msg.Content.MutedUntil > 0 {
		return errors.New("Google Chat only supports permanent mute or unmute.")
	}

	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return err
	}

	settingType := notificationSettingTypeSpace
	if isDM {
		settingType = notificationSettingTypeDM
	}
	muteState := pb.GroupNotificationSettingsUpdate_Mute_UNMUTED
	if msg.Content.IsMuted() {
		muteState = pb.GroupNotificationSettingsUpdate_Mute_MUTED
	}

	reqBytes, err := pb.Marshal(&pb.UpdateGroupNotificationSettingsRequest{
		GroupId: pb.PartsToGroupID(rawGroupID, isDM),
		Update: &pb.GroupNotificationSettingsUpdate{
			SettingType: pb.Int32(settingType),
			Mute: &pb.GroupNotificationSettingsUpdate_Mute{
				State: muteState.Enum(),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("marshal update_group_notification_settings request: %w", err)
	}

	if _, err := c.rpcCall(ctx, "update_group_notification_settings", reqBytes); err != nil {
		return fmt.Errorf("Could not update Google Chat mute setting: %w", err)
	}
	return nil
}

// HandleMatrixMembership handles Space member invitations, invite accept/decline, kicking members, and leaving Spaces or DMs.
func (c *Client) HandleMatrixMembership(ctx context.Context, msg *bridgev2.MatrixMembershipChange) (*bridgev2.MatrixMembershipResult, error) {
	if msg == nil || msg.Portal == nil {
		return nil, errors.New("missing membership event")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return nil, err
	}

	var targetGaia string
	switch t := msg.Target.(type) {
	case *bridgev2.Ghost:
		if t != nil {
			targetGaia = ParseUserID(t.ID)
		}
	case *bridgev2.UserLogin:
		if t != nil {
			targetGaia = ParseUserLoginID(t.ID)
		}
	}
	if targetGaia == "" && msg.Type.IsSelf && c.UserLogin != nil {
		targetGaia = ParseUserLoginID(c.UserLogin.ID)
	}
	if targetGaia == "" {
		return nil, errors.New("missing Google Chat user ID for membership change")
	}

	switch msg.Type {
	case bridgev2.Invite:
		if isDM {
			return nil, errors.New("Cannot invite additional members to a Google Chat direct message.")
		}
		reqBytes, err := pb.Marshal(&pb.CreateMembershipRequest{
			MemberIds:       []*pb.MemberId{pb.UserMemberID(targetGaia)},
			MembershipState: pb.MembershipState_MEMBER_INVITED.Enum(),
			GroupId:         pb.SpaceGroupID(rawGroupID),
			InviteeMemberInfos: []*pb.InviteeMemberInfo{
				{
					Id: &pb.InviteeMemberInfo_InviteeInfo{
						InviteeInfo: &pb.InviteeInfo{
							UserId: pb.HumanUserID(targetGaia),
						},
					},
				},
			},
		})
		if err != nil {
			return nil, fmt.Errorf("marshal create_membership request: %w", err)
		}

		if _, err := c.rpcCall(ctx, "create_membership", reqBytes); err != nil {
			return nil, fmt.Errorf("Could not invite member to Google Chat space: %w", err)
		}
		return &bridgev2.MatrixMembershipResult{}, nil

	case bridgev2.AcceptInvite, bridgev2.Join:
		if isDM {
			return &bridgev2.MatrixMembershipResult{}, nil
		}
		reqBytes, err := pb.Marshal(&pb.CreateMembershipRequest{
			MemberIds: []*pb.MemberId{pb.UserMemberID(targetGaia)},
			GroupId:   pb.SpaceGroupID(rawGroupID),
		})
		if err != nil {
			return nil, fmt.Errorf("marshal create_membership request: %w", err)
		}

		if _, err := c.rpcCall(ctx, "create_membership", reqBytes); err != nil {
			return nil, fmt.Errorf("Could not join Google Chat space: %w", err)
		}
		return &bridgev2.MatrixMembershipResult{}, nil

	case bridgev2.Kick, bridgev2.RevokeInvite, bridgev2.BanInvited, bridgev2.BanJoined, bridgev2.BanLeft:
		if isDM {
			return nil, errors.New("Cannot remove members from a Google Chat direct message.")
		}
		if err := c.removeMembership(ctx, rawGroupID, targetGaia); err != nil {
			return nil, fmt.Errorf("Could not remove member from Google Chat space: %w", err)
		}
		return &bridgev2.MatrixMembershipResult{}, nil

	case bridgev2.Leave, bridgev2.RejectInvite:
		if isDM {
			if err := c.hideGroup(ctx, true, rawGroupID); err != nil {
				return nil, fmt.Errorf("Could not hide Google Chat direct message: %w", err)
			}
			return &bridgev2.MatrixMembershipResult{}, nil
		}
		if err := c.removeMembership(ctx, rawGroupID, targetGaia); err != nil {
			return nil, fmt.Errorf("Could not leave Google Chat space: %w", err)
		}
		return &bridgev2.MatrixMembershipResult{}, nil

	default:
		return nil, fmt.Errorf("Unsupported Google Chat membership change (%s -> %s).", msg.Type.From, msg.Type.To)
	}
}

// HandleMatrixDeleteChat hides a Google Chat DM via hide_group (or leaves a Space via remove_memberships).
func (c *Client) HandleMatrixDeleteChat(ctx context.Context, msg *bridgev2.MatrixDeleteChat) error {
	if msg == nil || msg.Portal == nil {
		return errors.New("missing delete chat event")
	}
	if msg.Content != nil && msg.Content.DeleteForEveryone {
		return errors.New("Google Chat cannot delete a conversation for everyone.")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return err
	}
	if isDM {
		return c.hideGroup(ctx, true, rawGroupID)
	}
	if c.UserLogin == nil {
		return errors.New("not logged in")
	}
	return c.removeMembership(ctx, rawGroupID, ParseUserLoginID(c.UserLogin.ID))
}

func (c *Client) removeMembership(ctx context.Context, rawSpaceID, gaiaID string) error {
	reqBytes, err := pb.Marshal(&pb.RemoveMembershipsRequest{
		MemberIds:       []*pb.MemberId{pb.UserMemberID(gaiaID)},
		GroupId:         pb.SpaceGroupID(rawSpaceID),
		MembershipState: pb.MembershipState_MEMBER_INVITED.Enum(),
	})
	if err != nil {
		return fmt.Errorf("marshal remove_memberships request: %w", err)
	}
	_, err = c.rpcCall(ctx, "remove_memberships", reqBytes)
	return err
}

func (c *Client) hideGroup(ctx context.Context, isDM bool, rawGroupID string) error {
	reqBytes, err := pb.Marshal(&pb.HideGroupRequest{
		Id:   pb.PartsToGroupID(rawGroupID, isDM),
		Hide: pb.Bool(true),
	})
	if err != nil {
		return fmt.Errorf("marshal hide_group request: %w", err)
	}
	_, err = c.rpcCall(ctx, "hide_group", reqBytes)
	return err
}
