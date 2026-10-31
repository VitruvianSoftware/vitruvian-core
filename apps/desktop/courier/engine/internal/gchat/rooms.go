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

func protoEncodeUserID(gaiaID string) []byte {
	var out []byte
	out = append(out, protoEncodeStringField(1, gaiaID)...)
	out = append(out, protoEncodeVarintField(2, 0)...) // UserType.HUMAN = 0
	return out
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

	// CreateDmRequest (googlechat.proto:1217-1228):
	// - members (field 1): repeated UserId { id (field 1): gaiaID, type (field 2): HUMAN (0) }
	// - invitees (field 7): repeated InviteeInfo { email (field 2): email }
	var req []byte
	if targetEmail != "" {
		invitee := protoEncodeStringField(2, targetEmail)
		req = append(req, protoEncodeBytesField(7, invitee)...)
	} else {
		req = append(req, protoEncodeBytesField(1, protoEncodeUserID(targetGaiaID))...)
	}

	respBytes, err := c.rpcCall(ctx, "create_dm", req)
	if err != nil {
		return nil, fmt.Errorf("Could not start Google Chat direct message: %w", err)
	}

	// CreateDmResponse (googlechat.proto:1230-1236):
	// - dm (field 1): Group { group_id (field 1): GroupId, name (field 4): string, group_read_state (field 12): GroupReadState }
	// - memberships (field 4): repeated Membership { id (field 1): MembershipId { member_id (field 1): MemberId { user_id (field 1): UserId } } }
	var dmID string
	var dmName string
	var memberGaiaIDs []string
	var groupRev int64

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

	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // dm (Group)
			protoIterFields(f.bytes, func(gf protoField) {
				switch gf.num {
				case 1: // group_id (GroupId)
					if _, rawID, ok := protoDecodeGroupID(gf.bytes); ok && rawID != "" {
						dmID = rawID
					}
				case 4: // name
					if gf.wireType == 2 {
						dmName = string(gf.bytes)
					}
				case 12: // group_read_state (GroupReadState)
					protoIterFields(gf.bytes, func(rsf protoField) {
						if rsf.num == 23 && rsf.wireType == 2 { // joined_users (repeated UserId)
							addMember(protoDecodeUserID(rsf.bytes))
						}
					})
				case 18: // group_revision (RevisionTimestamp)
					groupRev = protoDecodeRevisionTimestamp(gf.bytes)
				}
			})
		case 4: // memberships (repeated Membership)
			protoIterFields(f.bytes, func(mf protoField) {
				if mf.num == 1 && mf.wireType == 2 { // id (MembershipId)
					protoIterFields(mf.bytes, func(midf protoField) {
						if midf.num == 1 && midf.wireType == 2 { // member_id (MemberId)
							protoIterFields(midf.bytes, func(uidf protoField) {
								if uidf.num == 1 && uidf.wireType == 2 { // user_id (UserId)
									addMember(protoDecodeUserID(uidf.bytes))
								}
							})
						}
					})
				}
			})
		}
	})

	if dmID == "" {
		return nil, errors.New("Google Chat did not return a direct message ID.")
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
			portal.NameSet = true
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

// HandleMatrixRoomName renames a Google Chat Space via update_group (UpdateMask_NAME = 1).
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

	// UpdateGroupRequest (googlechat.proto:2444-2459):
	// - space_id (field 1): SpaceId { space_id (field 1): rawGroupID }
	// - name (field 2): newName
	// - update_masks (field 4): UpdateMask_NAME (1)
	var req []byte
	req = append(req, protoEncodeBytesField(1, protoEncodeStringField(1, rawGroupID))...)
	req = append(req, protoEncodeStringField(2, msg.Content.Name)...)
	req = append(req, protoEncodeVarintField(4, 1)...)

	respBytes, err := c.rpcCall(ctx, "update_group", req)
	if err != nil {
		return false, fmt.Errorf("Could not rename Google Chat space: %w", err)
	}
	msg.Portal.Name = msg.Content.Name
	msg.Portal.NameSet = true
	c.advanceRevisionFromUpdateGroup(ctx, msg.Portal, respBytes)
	return true, nil
}

// HandleMatrixRoomTopic updates a Google Chat Space description via update_group (UpdateMask_SPACE_DETAILS = 4),
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

	// Step 1: Fetch existing Group via get_group (googlechat.proto:2149-2167) to preserve GroupDetails.guidelines.
	var getReq []byte
	getReq = append(getReq, protoEncodeBytesField(1, protoEncodeGroupID(false, rawGroupID))...)
	getReq = append(getReq, protoEncodeVarintField(4, 0)...) // FetchOptions_MEMBERS = 0
	getReq = append(getReq, protoEncodeVarintField(4, 5)...) // FetchOptions_INCLUDE_DYNAMIC_GROUP_NAME = 5
	getReq = append(getReq, protoEncodeVarintField(5, 1)...) // include_invite_dms = true

	getResp, err := c.rpcCall(ctx, "get_group", getReq)
	if err != nil {
		return false, fmt.Errorf("Could not read current space details before changing topic: %w", err)
	}

	var existingGuidelines string
	protoIterFields(getResp, func(f protoField) {
		if f.num == 1 && f.wireType == 2 { // group (Group)
			protoIterFields(f.bytes, func(gf protoField) {
				if gf.num == 37 && gf.wireType == 2 { // group_details (GroupDetails, googlechat.proto:980)
					protoIterFields(gf.bytes, func(df protoField) {
						if df.num == 2 && df.wireType == 2 { // guidelines (field 2, googlechat.proto:942)
							existingGuidelines = string(df.bytes)
						}
					})
				}
			})
		}
	})

	// Step 2: UpdateGroupRequest (googlechat.proto:2444-2459) with UpdateMask_SPACE_DETAILS (4) and preserved guidelines.
	var details []byte
	details = append(details, protoEncodeStringField(1, msg.Content.Topic)...)
	if existingGuidelines != "" {
		details = append(details, protoEncodeStringField(2, existingGuidelines)...)
	}

	var updReq []byte
	updReq = append(updReq, protoEncodeBytesField(1, protoEncodeStringField(1, rawGroupID))...)
	updReq = append(updReq, protoEncodeVarintField(4, 4)...) // UpdateMask_SPACE_DETAILS = 4
	updReq = append(updReq, protoEncodeBytesField(7, details)...)

	respBytes, err := c.rpcCall(ctx, "update_group", updReq)
	if err != nil {
		return false, fmt.Errorf("Could not update Google Chat space topic: %w", err)
	}
	msg.Portal.Topic = msg.Content.Topic
	msg.Portal.TopicSet = true
	c.advanceRevisionFromUpdateGroup(ctx, msg.Portal, respBytes)
	return true, nil
}

func (c *Client) advanceRevisionFromUpdateGroup(ctx context.Context, portal *bridgev2.Portal, respBytes []byte) {
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		if f.num == 2 && f.wireType == 2 { // group_revision (WriteRevision)
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if groupRev > 0 && portal != nil {
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

	// GroupNotificationSettingsUpdate.Type (googlechat.proto:2482-2490):
	// - NOTIFICATION_LEVEL_OR_MUTE_STATE_CHANGED = 4 (for DMs)
	// - MUTE_STATE_CHANGE = 5 (for Spaces)
	settingType := uint64(5)
	if isDM {
		settingType = 4
	}
	// Mute.State (googlechat.proto:2492-2498):
	// - UNMUTED = 1
	// - MUTED = 2
	muteState := uint64(1)
	if msg.Content.IsMuted() {
		muteState = 2
	}

	var update []byte
	update = append(update, protoEncodeVarintField(2, settingType)...)
	update = append(update, protoEncodeBytesField(3, protoEncodeVarintField(1, muteState))...)

	var req []byte
	req = append(req, protoEncodeBytesField(1, protoEncodeGroupID(isDM, rawGroupID))...)
	req = append(req, protoEncodeBytesField(2, update)...)

	if _, err := c.rpcCall(ctx, "update_group_notification_settings", req); err != nil {
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
		// CreateMembershipRequest (googlechat.proto:2386-2394):
		// - member_ids (field 2): MemberId { user_id (field 1): UserId }
		// - membership_state (field 3): MEMBER_INVITED (1)
		// - group_id (field 4): GroupId
		// - invitee_member_infos (field 8): InviteeMemberInfo { invitee_info (field 1): InviteeInfo { user_id (field 1): UserId } }
		userIDProto := protoEncodeUserID(targetGaia)
		memberIDProto := protoEncodeBytesField(1, userIDProto)
		inviteeMemberInfoProto := protoEncodeBytesField(1, protoEncodeBytesField(1, userIDProto))

		var req []byte
		req = append(req, protoEncodeBytesField(2, memberIDProto)...)
		req = append(req, protoEncodeVarintField(3, 1)...) // MembershipState_MEMBER_INVITED = 1
		req = append(req, protoEncodeBytesField(4, protoEncodeGroupID(false, rawGroupID))...)
		req = append(req, protoEncodeBytesField(8, inviteeMemberInfoProto)...)

		if _, err := c.rpcCall(ctx, "create_membership", req); err != nil {
			return nil, fmt.Errorf("Could not invite member to Google Chat space: %w", err)
		}
		return &bridgev2.MatrixMembershipResult{}, nil

	case bridgev2.AcceptInvite, bridgev2.Join:
		if isDM {
			return &bridgev2.MatrixMembershipResult{}, nil
		}
		memberIDProto := protoEncodeBytesField(1, protoEncodeUserID(targetGaia))
		var req []byte
		req = append(req, protoEncodeBytesField(2, memberIDProto)...)
		req = append(req, protoEncodeBytesField(4, protoEncodeGroupID(false, rawGroupID))...)

		if _, err := c.rpcCall(ctx, "create_membership", req); err != nil {
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
	// RemoveMembershipsRequest (googlechat.proto:2349-2355):
	// - member_ids (field 1): repeated MemberId { user_id (field 1): UserId }
	// - group_id (field 2): GroupId
	// - membership_state (field 3): MembershipState_MEMBER_INVITED (1)
	memberIDProto := protoEncodeBytesField(1, protoEncodeUserID(gaiaID))
	var req []byte
	req = append(req, protoEncodeBytesField(1, memberIDProto)...)
	req = append(req, protoEncodeBytesField(2, protoEncodeGroupID(false, rawSpaceID))...)
	req = append(req, protoEncodeVarintField(3, 1)...)
	_, err := c.rpcCall(ctx, "remove_memberships", req)
	return err
}

func (c *Client) hideGroup(ctx context.Context, isDM bool, rawGroupID string) error {
	// HideGroupRequest (googlechat.proto:2368-2372):
	// - id (field 1): GroupId
	// - hide (field 2): bool (true = 1)
	var req []byte
	req = append(req, protoEncodeBytesField(1, protoEncodeGroupID(isDM, rawGroupID))...)
	req = append(req, protoEncodeVarintField(2, 1)...)
	_, err := c.rpcCall(ctx, "hide_group", req)
	return err
}
