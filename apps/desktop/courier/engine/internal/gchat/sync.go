// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

const (
	worldSectionPageSize      = 999
	defaultTopicsPageSize     = 30
	defaultRepliesPageSize    = 10
	defaultMessagesPageSize   = 50
	typingNotificationTimeout = 6 * time.Second
	initialChatSyncCap        = 30
)

// MakeDMPortalID encodes a 1:1 DM or Group DM ID into a networkid.PortalID ("dm:" + dmID).
func MakeDMPortalID(dmID string) networkid.PortalID {
	return networkid.PortalID("dm:" + dmID)
}

// MakeSpacePortalID encodes a named Space ID into a networkid.PortalID ("space:" + spaceID).
func MakeSpacePortalID(spaceID string) networkid.PortalID {
	return networkid.PortalID("space:" + spaceID)
}

// ParsePortalID splits a Google Chat PortalID ("dm:<id>" or "space:<id>") into isDM and rawID.
func ParsePortalID(portalID networkid.PortalID) (isDM bool, rawID string, err error) {
	s := string(portalID)
	if strings.HasPrefix(s, "dm:") {
		raw := strings.TrimPrefix(s, "dm:")
		if raw == "" {
			return false, "", fmt.Errorf("empty dm portal id %q", portalID)
		}
		return true, raw, nil
	}
	if strings.HasPrefix(s, "space:") {
		raw := strings.TrimPrefix(s, "space:")
		if raw == "" {
			return false, "", fmt.Errorf("empty space portal id %q", portalID)
		}
		return false, raw, nil
	}
	return false, "", fmt.Errorf("invalid gchat portal id %q", portalID)
}

// MakeMessageID encodes msgParentID and msgID into networkid.MessageID(msgParentID + "/" + msgID).
func MakeMessageID(msgParentID, msgID string) networkid.MessageID {
	if msgParentID == "" {
		return networkid.MessageID(msgID)
	}
	return networkid.MessageID(msgParentID + "/" + msgID)
}

// MakeThreadRootID encodes a topicID into networkid.MessageID(topicID + "/" + topicID).
func MakeThreadRootID(topicID string) networkid.MessageID {
	return networkid.MessageID(topicID + "/" + topicID)
}

// ParseMessageID splits a networkid.MessageID ("topicID/msgID" or "msgID") into topicID and msgID.
func ParseMessageID(id networkid.MessageID) (topicID, msgID string) {
	s := string(id)
	if before, after, ok := strings.Cut(s, "/"); ok {
		return before, after
	}
	return "", s
}

// MakeUserID encodes a Gaia ID into networkid.UserID(gaiaID).
func MakeUserID(gaiaID string) networkid.UserID {
	return networkid.UserID(gaiaID)
}

var _ bridgev2.BackfillingNetworkAPI = (*Client)(nil)

type parsedWorldItem struct {
	isDM               bool
	rawID              string
	hasGroupID         bool
	groupRevision      int64
	sortTimestamp      int64
	hideTimestamp      int64
	blocked            bool
	membershipState    pb.MembershipState
	hasMembershipState bool
	roomName           string
	hasRoomName        bool
	topicThreaded      bool
	flatThreadsEnabled bool
	memberUserIDs      []string
}

func parseWorldItemLiteFromProto(w *pb.WorldItemLite) parsedWorldItem {
	var item parsedWorldItem
	if w == nil {
		return item
	}
	seenMembers := make(map[string]bool)
	addMember := func(uid string) {
		if uid != "" && !seenMembers[uid] {
			seenMembers[uid] = true
			item.memberUserIDs = append(item.memberUserIDs, uid)
		}
	}

	if rawID, isDM, ok := pb.GroupIDToParts(w.GetGroupId()); ok {
		item.isDM = isDM
		item.rawID = rawID
		item.hasGroupID = true
	}
	item.groupRevision = w.GetGroupRevision().GetTimestamp()
	item.sortTimestamp = w.GetSortTimestamp()

	if rs := w.GetReadState(); rs != nil {
		item.hideTimestamp = rs.GetHideTimestamp()
		item.blocked = rs.GetBlocked()
		if rs.MembershipState != nil {
			item.membershipState = rs.GetMembershipState()
			item.hasMembershipState = true
		}
		for _, u := range rs.GetJoinedUsers() {
			addMember(u.GetId())
		}
	}
	if w.RoomName != nil {
		item.roomName = w.GetRoomName()
		item.hasRoomName = true
	}
	if dm := w.GetDmMembers(); dm != nil {
		for _, u := range dm.GetMembers() {
			addMember(u.GetId())
		}
		for _, m := range dm.GetMemberships() {
			addMember(m.GetUserId().GetId())
		}
	}
	if w.GetThreadedGroup() != nil {
		item.topicThreaded = true
	}
	if w.GetFlatThreadsEnabled() {
		item.flatThreadsEnabled = true
	}
	return item
}

func derivePeerUserID(memberIDs []string, ownUserID networkid.UserID) networkid.UserID {
	for _, id := range memberIDs {
		if id != "" && MakeUserID(id) != ownUserID {
			return MakeUserID(id)
		}
	}
	if len(memberIDs) == 1 {
		return MakeUserID(memberIDs[0])
	}
	return ""
}

// syncWorld fetches the user's conversation list via POST /u/0/api/paginated_world,
// filtering out blocked, hidden, and non-joined conversations, sorting by sort_timestamp
// descending, capping at 30 conversations, and storing user_revision on UserLoginMetadata
// separately from each portal's group_revision.
func (c *Client) syncWorld(ctx context.Context) error {
	c.syncMu.Lock()
	defer c.syncMu.Unlock()

	reqBytes, err := pb.Marshal(&pb.PaginatedWorldRequest{
		WorldSectionRequests: []*pb.WorldSectionRequest{
			{PageSize: pb.Int32(worldSectionPageSize)},
		},
		FetchOptions: []pb.PaginatedWorldRequest_FetchOptions{
			pb.PaginatedWorldRequest_EXCLUDE_GROUP_LITE,
			pb.PaginatedWorldRequest_FETCH_SPACE_INTEGRATION_PAYLOADS,
			pb.PaginatedWorldRequest_FETCH_GROUPS_D3_POLICIES,
		},
		FetchFromUserSpaces: pb.Bool(true),
	})
	if err != nil {
		return fmt.Errorf("marshal paginated_world request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "paginated_world", reqBytes)
	if err != nil {
		return fmt.Errorf("paginated_world failed: %w", err)
	}

	var resp pb.PaginatedWorldResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		return fmt.Errorf("decode paginated_world response: %w", err)
	}

	userRev := resp.GetUserRevision().GetTimestamp()
	var items []parsedWorldItem
	for _, sec := range resp.GetWorldSectionResponses() {
		for _, w := range sec.GetWorldItems() {
			items = append(items, parseWorldItemLiteFromProto(w))
		}
	}
	for _, w := range resp.GetWorldItems() {
		items = append(items, parseWorldItemLiteFromProto(w))
	}

	if userRev > 0 {
		if err := c.advanceUserRevision(ctx, userRev); err != nil {
			return err
		}
	}

	// Filter out blocked, hidden, and non-joined conversations, then sort by sort_timestamp descending
	// and apply the 30-room initial sync cap (matching planChatSync in ref/pkg/connector/sync.go:35-51).
	filtered := make([]parsedWorldItem, 0, len(items))
	for _, item := range items {
		if !item.hasGroupID || item.rawID == "" {
			continue
		}
		if item.blocked || item.hideTimestamp > 0 || item.membershipState != pb.MembershipState_MEMBER_JOINED {
			continue
		}
		filtered = append(filtered, item)
	}
	slices.SortStableFunc(filtered, func(a, b parsedWorldItem) int {
		return cmp.Compare(b.sortTimestamp, a.sortTimestamp)
	})
	if len(filtered) > initialChatSyncCap {
		filtered = filtered[:initialChatSyncCap]
	}

	own := c.ownUserID()
	for _, item := range filtered {
		for _, rawUID := range item.memberUserIDs {
			uid := MakeUserID(strings.TrimSpace(rawUID))
			if uid != "" && uid != own {
				c.ensureGhostInitialized(ctx, uid)
			}
		}
	}
	for _, item := range filtered {
		var portalID networkid.PortalID
		if item.isDM {
			portalID = MakeDMPortalID(item.rawID)
		} else {
			portalID = MakeSpacePortalID(item.rawID)
		}
		portal, err := c.UserLogin.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
			ID:       portalID,
			Receiver: c.UserLogin.ID,
		})
		if err != nil {
			return fmt.Errorf("get portal %q: %w", portalID, err)
		}
		if item.isDM {
			portal.RoomType = database.RoomTypeDM
			if peer := derivePeerUserID(item.memberUserIDs, own); peer != "" {
				portal.OtherUserID = peer
			}
		} else {
			portal.RoomType = database.RoomTypeDefault
			if item.hasRoomName {
				portal.Name = item.roomName
				portal.NameSet = true
			}
		}
		c.metaMu.Lock()
		meta, ok := portal.Metadata.(*PortalMetadata)
		if !ok || meta == nil {
			meta = &PortalMetadata{}
			portal.Metadata = meta
		}
		meta.TopicThreaded = item.topicThreaded
		meta.ThreadsEnabled = item.topicThreaded || item.flatThreadsEnabled
		if len(item.memberUserIDs) > 0 {
			meta.MemberUserIDs = slices.Clone(item.memberUserIDs)
		}
		if item.groupRevision > meta.GroupRevision {
			meta.GroupRevision = item.groupRevision
			meta.Revision = item.groupRevision
		}
		saveErr := portal.Save(ctx)
		c.metaMu.Unlock()
		if saveErr != nil {
			return fmt.Errorf("save portal %q: %w", portalID, saveErr)
		}

		roomType := portal.RoomType
		chatInfo := &bridgev2.ChatInfo{
			Type:        &roomType,
			CanBackfill: true,
			Members:     c.buildChatMemberList(own, item.isDM, portal.OtherUserID, item.memberUserIDs, false),
		}
		if item.hasRoomName {
			roomName := item.roomName
			chatInfo.Name = &roomName
		}
		c.queueRemoteEvent(ctx, &simplevent.ChatResync{
			EventMeta: simplevent.EventMeta{
				Type:         bridgev2.RemoteEventChatResync,
				PortalKey:    portal.PortalKey,
				CreatePortal: true,
			},
			ChatInfo:        chatInfo,
			LatestMessageTS: time.UnixMicro(item.sortTimestamp),
		})
	}
	return nil
}

func (c *Client) advanceUserRevision(ctx context.Context, rev int64) error {
	if rev <= 0 || c.UserLogin == nil {
		return nil
	}
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata)
	if !ok || meta == nil {
		return nil
	}
	if rev <= meta.UserRevision {
		return nil
	}
	meta.UserRevision = rev
	return c.UserLogin.Save(ctx)
}

func (c *Client) advancePortalGroupRevision(ctx context.Context, portalKey networkid.PortalKey, rev int64) error {
	if rev <= 0 || c.UserLogin == nil || c.UserLogin.Bridge == nil {
		return nil
	}
	portal, err := c.UserLogin.Bridge.GetExistingPortalByKey(ctx, portalKey)
	if err != nil || portal == nil {
		return err
	}
	c.metaMu.Lock()
	defer c.metaMu.Unlock()
	meta, ok := portal.Metadata.(*PortalMetadata)
	if !ok || meta == nil {
		meta = &PortalMetadata{}
		portal.Metadata = meta
	}
	if rev <= meta.GroupRevision {
		return nil
	}
	meta.GroupRevision = rev
	meta.Revision = rev
	return portal.Save(ctx)
}

type parsedMessage struct {
	rawProto       []byte
	isDM           bool
	groupRawID     string
	hasGroupID     bool
	topicID        string
	messageID      string
	senderGaiaID   string
	createTimeUsec int64
	lastEditUsec   int64
	lastUpdateUsec int64
	localID        string
	replyTopicID   string
	replyMsgID     string
}

func extractMessageIDParts(mid *pb.MessageId) (isDM bool, groupRawID string, hasGroup bool, topicID, msgID string) {
	if mid == nil {
		return false, "", false, "", ""
	}
	msgID = mid.GetMessageId()
	if tid := mid.GetParentId().GetTopicId(); tid != nil {
		topicID = tid.GetTopicId()
		if raw, dm, ok := pb.GroupIDToParts(tid.GetGroupId()); ok {
			isDM = dm
			groupRawID = raw
			hasGroup = true
		}
	}
	return isDM, groupRawID, hasGroup, topicID, msgID
}

func parseMessageFromProto(m *pb.Message) parsedMessage {
	if m == nil {
		return parsedMessage{}
	}
	raw, _ := pb.Marshal(m)
	pm := parsedMessage{
		rawProto:       raw,
		senderGaiaID:   m.GetCreator().GetUserId().GetId(),
		createTimeUsec: m.GetCreateTime(),
		lastUpdateUsec: m.GetLastUpdateTime(),
		localID:        m.GetLocalId(),
		lastEditUsec:   m.GetLastEditTime(),
	}
	pm.isDM, pm.groupRawID, pm.hasGroupID, pm.topicID, pm.messageID = extractMessageIDParts(m.GetId())
	if rmid := m.GetReplyTo().GetId(); rmid != nil {
		_, _, _, pm.replyTopicID, pm.replyMsgID = extractMessageIDParts(rmid)
	}
	return pm
}

func parseMessageProto(raw []byte) parsedMessage {
	var m pb.Message
	if err := pb.Unmarshal(raw, &m); err != nil {
		return parsedMessage{rawProto: raw}
	}
	pm := parseMessageFromProto(&m)
	pm.rawProto = raw
	return pm
}

func (c *Client) convertParsedMessage(ctx context.Context, pm parsedMessage) (*bridgev2.ConvertedMessage, error) {
	conv, err := AnnotationsToHTML(pm.rawProto)
	if err != nil {
		return nil, err
	}
	content := &event.MessageEventContent{
		MsgType: event.MsgText,
		Body:    conv.Body,
	}
	if conv.FormattedBody != "" {
		content.Format = event.FormatHTML
		content.FormattedBody = conv.FormattedBody
	}
	if conv.MentionAll || len(conv.Mentions) > 0 {
		mentions := &event.Mentions{Room: conv.MentionAll}
		for _, gaiaID := range conv.Mentions {
			mentions.UserIDs = append(mentions.UserIDs, id.UserID(fmt.Sprintf("@gchat_%s:courier.local", gaiaID)))
		}
		content.Mentions = mentions
	}

	mediaParts, err := c.extractInboundMediaParts(ctx, pm)
	if err != nil {
		return nil, err
	}
	var parts []*bridgev2.ConvertedMessagePart
	if conv.Body != "" || len(mediaParts) == 0 {
		parts = append(parts, &bridgev2.ConvertedMessagePart{
			ID:      networkid.PartID(""),
			Type:    event.EventMessage,
			Content: content,
			DBMetadata: &MessageMetadata{
				TopicID:          pm.topicID,
				CreateTimeMicros: pm.createTimeUsec,
				LastEditTime:     pm.lastEditUsec,
			},
		})
	}
	parts = append(parts, mediaParts...)

	cm := &bridgev2.ConvertedMessage{
		Parts: parts,
	}
	if pm.topicID != "" {
		threadRoot := MakeThreadRootID(pm.topicID)
		cm.ThreadRoot = &threadRoot
	}
	if pm.replyMsgID != "" {
		replyTopic := pm.replyTopicID
		if replyTopic == "" {
			replyTopic = pm.topicID
		}
		cm.ReplyTo = &networkid.MessageOptionalPartID{
			MessageID: MakeMessageID(replyTopic, pm.replyMsgID),
		}
	}
	return cm, nil
}

// FetchMessages implements bridgev2.BackfillingNetworkAPI.
// For Space portals ("space:<id>") it performs a single-page POST /u/0/api/list_topics
// (page_size_for_topics = 30, page_size_for_replies = 10); for DM portals ("dm:<id>")
// it performs a single-page POST /u/0/api/list_messages (page_size = 50).
// History sync is strictly read-only (MarkRead: false, HasMore: false).
func (c *Client) FetchMessages(ctx context.Context, fetchParams bridgev2.FetchMessagesParams) (*bridgev2.FetchMessagesResponse, error) {
	if fetchParams.Portal == nil {
		return nil, fmt.Errorf("FetchMessages called with nil portal")
	}
	isDM, rawID, err := ParsePortalID(fetchParams.Portal.ID)
	if err != nil {
		return nil, err
	}

	if isDM {
		pageSize := defaultMessagesPageSize
		if fetchParams.Count > 0 {
			pageSize = fetchParams.Count
		}
		reqBytes, err := pb.Marshal(&pb.ListMessagesRequest{
			ParentId: buildMessageParentID(pb.DMGroupID(rawID), ""),
			PageSize: pb.Int32(int32(pageSize)),
		})
		if err != nil {
			return nil, fmt.Errorf("marshal list_messages request: %w", err)
		}

		respBytes, err := c.rpcCall(ctx, "list_messages", reqBytes)
		if err != nil {
			return nil, fmt.Errorf("list_messages failed: %w", err)
		}

		var resp pb.ListMessagesResponse
		if err := pb.Unmarshal(respBytes, &resp); err != nil {
			return nil, fmt.Errorf("decode list_messages response: %w", err)
		}

		parsed := make([]parsedMessage, 0, len(resp.GetMessages()))
		for _, m := range resp.GetMessages() {
			parsed = append(parsed, parseMessageFromProto(m))
		}
		slices.SortStableFunc(parsed, func(a, b parsedMessage) int {
			return cmp.Compare(a.createTimeUsec, b.createTimeUsec)
		})

		backfillMsgs := make([]*bridgev2.BackfillMessage, 0, len(parsed))
		for _, pm := range parsed {
			if pm.messageID == "" {
				continue
			}
			cm, err := c.convertParsedMessage(ctx, pm)
			if err != nil {
				return nil, err
			}
			senderID := MakeUserID(pm.senderGaiaID)
			backfillMsgs = append(backfillMsgs, &bridgev2.BackfillMessage{
				ConvertedMessage: cm,
				Sender: bridgev2.EventSender{
					Sender:   senderID,
					IsFromMe: c.IsThisUser(ctx, senderID),
				},
				ID:          MakeMessageID(pm.topicID, pm.messageID),
				Timestamp:   time.UnixMicro(pm.createTimeUsec),
				StreamOrder: pm.createTimeUsec,
			})
		}
		return &bridgev2.FetchMessagesResponse{
			Messages: backfillMsgs,
			HasMore:  false,
			MarkRead: false,
		}, nil
	}

	// Space portal: POST /u/0/api/list_topics
	topicsPageSize := defaultTopicsPageSize
	if fetchParams.Count > 0 {
		topicsPageSize = fetchParams.Count
	}
	reqBytes, err := pb.Marshal(&pb.ListTopicsRequest{
		GroupId:                  pb.SpaceGroupID(rawID),
		PageSizeForTopics:        pb.Int32(int32(topicsPageSize)),
		PageSizeForReplies:       pb.Int32(defaultRepliesPageSize),
		PageSizeForUnreadReplies: pb.Int32(defaultRepliesPageSize),
		PageSizeForReadReplies:   pb.Int32(defaultRepliesPageSize),
	})
	if err != nil {
		return nil, fmt.Errorf("marshal list_topics request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "list_topics", reqBytes)
	if err != nil {
		return nil, fmt.Errorf("list_topics failed: %w", err)
	}

	var resp pb.ListTopicsResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		return nil, fmt.Errorf("decode list_topics response: %w", err)
	}

	var parsed []parsedMessage
	for _, topic := range resp.GetTopics() {
		topicFallbackID := topic.GetId().GetTopicId()
		for _, reply := range topic.GetReplies() {
			pm := parseMessageFromProto(reply)
			if pm.topicID == "" {
				pm.topicID = topicFallbackID
			}
			parsed = append(parsed, pm)
		}
	}
	slices.SortStableFunc(parsed, func(a, b parsedMessage) int {
		return cmp.Compare(a.createTimeUsec, b.createTimeUsec)
	})

	backfillMsgs := make([]*bridgev2.BackfillMessage, 0, len(parsed))
	for _, pm := range parsed {
		if pm.messageID == "" {
			continue
		}
		cm, err := c.convertParsedMessage(ctx, pm)
		if err != nil {
			return nil, err
		}
		senderID := MakeUserID(pm.senderGaiaID)
		backfillMsgs = append(backfillMsgs, &bridgev2.BackfillMessage{
			ConvertedMessage: cm,
			Sender: bridgev2.EventSender{
				Sender:   senderID,
				IsFromMe: c.IsThisUser(ctx, senderID),
			},
			ID:          MakeMessageID(pm.topicID, pm.messageID),
			Timestamp:   time.UnixMicro(pm.createTimeUsec),
			StreamOrder: pm.createTimeUsec,
		})
	}
	return &bridgev2.FetchMessagesResponse{
		Messages: backfillMsgs,
		HasMore:  false,
		MarkRead: false,
	}, nil
}

func isCatchUpAborted(status pb.CatchUpResponse_ResponseStatus) bool {
	return status == pb.CatchUpResponse_ABORTED_CUTOFF_EXCEEDED ||
		status == pb.CatchUpResponse_ABORTED_CACHE_INVALIDATION ||
		status == pb.CatchUpResponse_ABORTED_FROM_REVISION_TOO_OLD
}

const catchUpMaxPages = 100

// catchUpAfterReconnect calls POST /u/0/api/catch_up_user with from_revision = UserLoginMetadata.UserRevision,
// follows PAGINATED responses up to catchUpMaxPages, translates and dispatches every returned Event,
// falls back to syncWorld when from_revision == 0 or CatchUpResponse.status is ABORTED_*, and advances
// user_revision only after all pages are processed without overwriting any portal's group_revision.
func (c *Client) catchUpAfterReconnect(ctx context.Context) error {
	var fromRev int64
	if c.UserLogin != nil {
		c.metaMu.Lock()
		if meta, ok := c.UserLogin.Metadata.(*UserLoginMetadata); ok && meta != nil {
			fromRev = meta.UserRevision
		}
		c.metaMu.Unlock()
	}
	if fromRev <= 0 {
		return c.syncWorld(ctx)
	}

	maxUserRev := fromRev
	for page := 0; page < catchUpMaxPages; page++ {
		pageStartRev := maxUserRev
		reqBytes, err := pb.Marshal(&pb.CatchUpUserRequest{
			Range: &pb.CatchUpRange{
				FromRevisionTimestamp: pb.Int64(pageStartRev),
			},
		})
		if err != nil {
			return fmt.Errorf("marshal catch_up_user request: %w", err)
		}
		respBytes, err := c.rpcCall(ctx, "catch_up_user", reqBytes)
		if err != nil {
			return fmt.Errorf("catch_up_user failed: %w", err)
		}

		var resp pb.CatchUpResponse
		if err := pb.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("decode catch_up_user response: %w", err)
		}

		if isCatchUpAborted(resp.GetStatus()) {
			return c.syncWorld(ctx)
		}

		if r := resp.GetReadRevision().GetTimestamp(); r > maxUserRev {
			maxUserRev = r
		}

		for _, evt := range resp.GetEvents() {
			if r := evt.GetUserRevision().GetTimestamp(); r > maxUserRev {
				maxUserRev = r
			}
			remoteEvts, err := c.translateEvent(ctx, evt, false, false)
			if err != nil {
				return err
			}
			for _, re := range remoteEvts {
				c.queueRemoteEvent(ctx, re)
			}
		}

		if resp.GetStatus() != pb.CatchUpResponse_PAGINATED || maxUserRev <= pageStartRev {
			break
		}
	}

	if maxUserRev > fromRev {
		return c.advanceUserRevision(ctx, maxUserRev)
	}
	return nil
}

// catchUpGroup calls POST /u/0/api/catch_up_group for a single portal with from_revision = PortalMetadata.GroupRevision,
// follows PAGINATED responses up to catchUpMaxPages, translates and dispatches every returned Event,
// falls back to syncWorld when from_revision == 0 or CatchUpResponse.status is ABORTED_*, and advances
// only that portal's group_revision after all pages are processed.
func (c *Client) catchUpGroup(ctx context.Context, portal *bridgev2.Portal) error {
	if portal == nil {
		return fmt.Errorf("catchUpGroup called with nil portal")
	}
	isDM, rawID, err := ParsePortalID(portal.ID)
	if err != nil {
		return err
	}
	var fromRev int64
	c.metaMu.Lock()
	if meta, ok := portal.Metadata.(*PortalMetadata); ok && meta != nil {
		fromRev = meta.GroupRevision
	}
	c.metaMu.Unlock()
	if fromRev <= 0 {
		return c.syncWorld(ctx)
	}

	groupID := pb.PartsToGroupID(rawID, isDM)
	maxGroupRev := fromRev
	for page := 0; page < catchUpMaxPages; page++ {
		pageStartRev := maxGroupRev
		reqBytes, err := pb.Marshal(&pb.CatchUpGroupRequest{
			GroupId: groupID,
			Range: &pb.CatchUpRange{
				FromRevisionTimestamp: pb.Int64(pageStartRev),
			},
		})
		if err != nil {
			return fmt.Errorf("marshal catch_up_group request: %w", err)
		}

		respBytes, err := c.rpcCall(ctx, "catch_up_group", reqBytes)
		if err != nil {
			return fmt.Errorf("catch_up_group failed: %w", err)
		}

		var resp pb.CatchUpResponse
		if err := pb.Unmarshal(respBytes, &resp); err != nil {
			return fmt.Errorf("decode catch_up_group response: %w", err)
		}

		if isCatchUpAborted(resp.GetStatus()) {
			return c.syncWorld(ctx)
		}

		if r := resp.GetReadRevision().GetTimestamp(); r > maxGroupRev {
			maxGroupRev = r
		}

		for _, evt := range resp.GetEvents() {
			if r := evt.GetGroupRevision().GetTimestamp(); r > maxGroupRev {
				maxGroupRev = r
			}
			if evt.GetGroupId() == nil {
				evt.GroupId = groupID
			}
			remoteEvts, err := c.translateEvent(ctx, evt, false, false)
			if err != nil {
				return err
			}
			for _, re := range remoteEvts {
				c.queueRemoteEvent(ctx, re)
			}
		}

		if resp.GetStatus() != pb.CatchUpResponse_PAGINATED || maxGroupRev <= pageStartRev {
			break
		}
	}

	if maxGroupRev > fromRev {
		c.metaMu.Lock()
		meta, ok := portal.Metadata.(*PortalMetadata)
		if !ok || meta == nil {
			meta = &PortalMetadata{}
			portal.Metadata = meta
		}
		if maxGroupRev > meta.GroupRevision {
			meta.GroupRevision = maxGroupRev
			meta.Revision = maxGroupRev
		}
		saveErr := portal.Save(ctx)
		c.metaMu.Unlock()
		return saveErr
	}
	return nil
}

// normalizeEmojiForDisplay ensures bare heart "\u2764" (without U+FE0F) is normalized
// to "❤️" ("\u2764\uFE0F") for Courier display while keeping EmojiID stripped of U+FE0F.
func normalizeEmojiForDisplay(raw string) (bareEmoji string, displayEmoji string) {
	bare := strings.ReplaceAll(raw, "\uFE0F", "")
	if bare == "\u2764" {
		return bare, "\u2764\uFE0F"
	}
	return bare, raw
}

// translateWebChannelEvent splits a Google Chat Event (singular body + repeated bodies)
// and translates each EventBody into the corresponding bridgev2.RemoteEvent.
func (c *Client) translateWebChannelEvent(ctx context.Context, eventProto []byte) ([]bridgev2.RemoteEvent, error) {
	return c.translateEventProto(ctx, eventProto, true, true)
}

func (c *Client) translateEventProto(
	ctx context.Context,
	eventProto []byte,
	advanceUserRev bool,
	advanceGroupRev bool,
) ([]bridgev2.RemoteEvent, error) {
	var evt pb.Event
	if err := pb.Unmarshal(eventProto, &evt); err != nil {
		return nil, fmt.Errorf("decode event protobuf: %w", err)
	}
	return c.translateEvent(ctx, &evt, advanceUserRev, advanceGroupRev)
}

func (c *Client) translateEvent(
	ctx context.Context,
	evt *pb.Event,
	advanceUserRev bool,
	advanceGroupRev bool,
) ([]bridgev2.RemoteEvent, error) {
	if evt == nil {
		return nil, nil
	}
	outerRawGroupID, outerIsDM, hasOuterGroupID := pb.GroupIDToParts(evt.GetGroupId())
	outerEventType := evt.GetType()
	userRev := evt.GetUserRevision().GetTimestamp()
	groupRev := evt.GetGroupRevision().GetTimestamp()

	var bodies []*pb.Event_EventBody
	if evt.GetBody() != nil {
		bodies = append(bodies, evt.GetBody())
	}
	bodies = append(bodies, evt.GetBodies()...)

	var out []bridgev2.RemoteEvent
	for _, body := range bodies {
		evts, err := c.translateSingleEventBody(ctx, outerIsDM, outerRawGroupID, hasOuterGroupID, outerEventType, body)
		if err != nil {
			return nil, err
		}
		out = append(out, evts...)
	}

	if advanceUserRev && userRev > 0 {
		_ = c.advanceUserRevision(ctx, userRev)
	}
	if advanceGroupRev && groupRev > 0 && hasOuterGroupID {
		var pid networkid.PortalID
		if outerIsDM {
			pid = MakeDMPortalID(outerRawGroupID)
		} else {
			pid = MakeSpacePortalID(outerRawGroupID)
		}
		_ = c.advancePortalGroupRevision(ctx, networkid.PortalKey{ID: pid, Receiver: c.UserLogin.ID}, groupRev)
	}

	return out, nil
}

func (c *Client) portalKeyFromGroup(isDM bool, rawGroupID string) networkid.PortalKey {
	var pid networkid.PortalID
	if isDM {
		pid = MakeDMPortalID(rawGroupID)
	} else {
		pid = MakeSpacePortalID(rawGroupID)
	}
	var receiver networkid.UserLoginID
	if c.UserLogin != nil {
		receiver = c.UserLogin.ID
	}
	return networkid.PortalKey{ID: pid, Receiver: receiver}
}

func (c *Client) translateSingleEventBody(
	ctx context.Context,
	outerIsDM bool,
	outerRawGroupID string,
	hasOuterGroupID bool,
	outerEventType pb.Event_EventType,
	body *pb.Event_EventBody,
) ([]bridgev2.RemoteEvent, error) {
	if body == nil {
		return nil, nil
	}
	bodyEventType := outerEventType
	if body.EventType != nil && body.GetEventType() != pb.Event_UNKNOWN {
		bodyEventType = body.GetEventType()
	}

	var out []bridgev2.RemoteEvent

	// 1 & 2: MESSAGE_POSTED or MESSAGE_UPDATED
	if msgPosted := body.GetMessagePosted(); msgPosted != nil && msgPosted.GetMessage() != nil {
		pm := parseMessageFromProto(msgPosted.GetMessage())
		isDM, rawGroupID, ok := outerIsDM, outerRawGroupID, hasOuterGroupID
		if !ok && pm.hasGroupID {
			isDM, rawGroupID, ok = pm.isDM, pm.groupRawID, true
		}
		if ok && pm.messageID != "" {
			portalKey := c.portalKeyFromGroup(isDM, rawGroupID)
			senderID := MakeUserID(pm.senderGaiaID)
			sender := bridgev2.EventSender{
				Sender:   senderID,
				IsFromMe: c.IsThisUser(ctx, senderID),
			}
			targetID := MakeMessageID(pm.topicID, pm.messageID)
			if bodyEventType == pb.Event_MESSAGE_UPDATED {
				editTS := pm.lastEditUsec
				if editTS == 0 {
					editTS = pm.lastUpdateUsec
				}
				if editTS == 0 {
					editTS = pm.createTimeUsec
				}
				pmCopy := pm
				out = append(out, &simplevent.Message[parsedMessage]{
					EventMeta: simplevent.EventMeta{
						Type:        bridgev2.RemoteEventEdit,
						PortalKey:   portalKey,
						Sender:      sender,
						Timestamp:   time.UnixMicro(editTS),
						StreamOrder: editTS,
					},
					ID:            targetID,
					TargetMessage: targetID,
					Data:          pmCopy,
					ConvertEditFunc: func(editCtx context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, existing []*database.Message, data parsedMessage) (*bridgev2.ConvertedEdit, error) {
						if len(existing) > 0 && existing[0] != nil {
							meta, ok := existing[0].Metadata.(*MessageMetadata)
							if !ok || meta == nil {
								meta = &MessageMetadata{}
								existing[0].Metadata = meta
							}
							if meta.LastEditTime > 0 && editTS <= meta.LastEditTime {
								return nil, bridgev2.ErrIgnoringRemoteEvent
							}
							meta.LastEditTime = editTS
						}
						cm, err := c.convertParsedMessage(editCtx, data)
						if err != nil {
							return nil, err
						}
						var editedParts []*bridgev2.ConvertedEditPart
						if len(existing) > 0 && len(cm.Parts) > 0 {
							if partMeta, ok := cm.Parts[0].DBMetadata.(*MessageMetadata); ok && partMeta != nil {
								partMeta.LastEditTime = editTS
							}
							editedParts = append(editedParts, cm.Parts[0].ToEditPart(existing[0]))
						}
						return &bridgev2.ConvertedEdit{ModifiedParts: editedParts}, nil
					},
				})
			} else {
				pmCopy := pm
				var convOnce sync.Once
				var convMsg *bridgev2.ConvertedMessage
				var convErr error
				out = append(out, &simplevent.Message[parsedMessage]{
					EventMeta: simplevent.EventMeta{
						Type:         bridgev2.RemoteEventMessage,
						PortalKey:    portalKey,
						CreatePortal: true,
						Sender:       sender,
						Timestamp:    time.UnixMicro(pm.createTimeUsec),
						StreamOrder:  pm.createTimeUsec,
					},
					ID:            targetID,
					TransactionID: networkid.TransactionID(pm.localID),
					Data:          pmCopy,
					ConvertMessageFunc: func(convCtx context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data parsedMessage) (*bridgev2.ConvertedMessage, error) {
						convOnce.Do(func() {
							convMsg, convErr = c.convertParsedMessage(convCtx, data)
						})
						return convMsg, convErr
					},
				})
			}
		}
	}

	// 3: MESSAGE_DELETED
	if msgDeleted := body.GetMessageDeleted(); msgDeleted != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		dm, rg, hg, topicID, msgID := extractMessageIDParts(msgDeleted.GetMessageId())
		if !hasGroup && hg {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		if hasGroup && msgID != "" {
			out = append(out, &simplevent.MessageRemove{
				EventMeta: simplevent.EventMeta{
					Type:      bridgev2.RemoteEventMessageRemove,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Timestamp: time.UnixMicro(msgDeleted.GetTimestamp()),
				},
				TargetMessage: MakeMessageID(topicID, msgID),
			})
		}
	}

	// 4: MESSAGE_REACTED
	if msgReaction := body.GetMessageReaction(); msgReaction != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		dm, rg, hg, topicID, msgID := extractMessageIDParts(msgReaction.GetMessageId())
		if !hasGroup && hg {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		actionType := msgReaction.GetType()
		if hasGroup && msgID != "" && (actionType == pb.MessageReactionEvent_ADD || actionType == pb.MessageReactionEvent_REMOVE) {
			evtType := bridgev2.RemoteEventReaction
			if actionType == pb.MessageReactionEvent_REMOVE {
				evtType = bridgev2.RemoteEventReactionRemove
			}
			bareEmoji, displayEmoji := normalizeEmojiForDisplay(msgReaction.GetEmoji().GetUnicode())
			senderID := MakeUserID(msgReaction.GetUserId().GetId())
			out = append(out, &simplevent.Reaction{
				EventMeta: simplevent.EventMeta{
					Type:      evtType,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Sender: bridgev2.EventSender{
						Sender:   senderID,
						IsFromMe: c.IsThisUser(ctx, senderID),
					},
					Timestamp: time.UnixMicro(msgReaction.GetTimestamp()),
				},
				TargetMessage: MakeMessageID(topicID, msgID),
				EmojiID:       networkid.EmojiID(bareEmoji),
				Emoji:         displayEmoji,
			})
		}
	}

	// 5a: GROUP_READ_STATE_UPDATED
	if grs := body.GetGroupReadStateUpdatedEvent(); grs != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		if rg, dm, ok := pb.GroupIDToParts(grs.GetGroupId()); ok {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		mostRecentReadTime := grs.GetMostRecentReadTime()
		if hasGroup && mostRecentReadTime > 0 {
			ownID := c.ownUserID()
			readTime := time.UnixMicro(mostRecentReadTime)
			out = append(out, &simplevent.Receipt{
				EventMeta: simplevent.EventMeta{
					Type:      bridgev2.RemoteEventReadReceipt,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Sender: bridgev2.EventSender{
						Sender:   ownID,
						IsFromMe: true,
					},
					Timestamp: readTime,
				},
				ReadUpTo: readTime,
			})
		}
	}

	// 5b: READ_RECEIPT_CHANGED
	if rrc := body.GetReadReceiptChanged(); rrc != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		if rg, dm, ok := pb.GroupIDToParts(rrc.GetGroupId()); ok {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		for _, rr := range rrc.GetReadReceiptSet().GetReadReceipts() {
			readTimeMicros := rr.GetReadTimeMicros()
			readerGaiaID := rr.GetUser().GetUserId().GetId()
			if hasGroup && readerGaiaID != "" && readTimeMicros > 0 {
				senderID := MakeUserID(readerGaiaID)
				rt := time.UnixMicro(readTimeMicros)
				out = append(out, &simplevent.Receipt{
					EventMeta: simplevent.EventMeta{
						Type:      bridgev2.RemoteEventReadReceipt,
						PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
						Sender: bridgev2.EventSender{
							Sender:   senderID,
							IsFromMe: c.IsThisUser(ctx, senderID),
						},
						Timestamp: rt,
					},
					ReadUpTo: rt,
				})
			}
		}
	}

	// 6: TYPING_STATE_CHANGED
	if tsc := body.GetTypingStateChanged(); tsc != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		if rg, dm, ok := pb.GroupIDToParts(tsc.GetContext().GetGroupId()); ok {
			isDM, rawGroupID, hasGroup = dm, rg, true
		} else if rg, dm, ok := pb.GroupIDToParts(tsc.GetContext().GetTopicId().GetGroupId()); ok {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		typerGaiaID := tsc.GetUserId().GetId()
		if hasGroup && typerGaiaID != "" {
			var timeout time.Duration
			if tsc.GetState() == pb.TypingState_TYPING {
				timeout = typingNotificationTimeout
			}
			senderID := MakeUserID(typerGaiaID)
			out = append(out, &simplevent.Typing{
				EventMeta: simplevent.EventMeta{
					Type:      bridgev2.RemoteEventTyping,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Sender: bridgev2.EventSender{
						Sender:   senderID,
						IsFromMe: c.IsThisUser(ctx, senderID),
					},
					Timestamp: time.UnixMicro(tsc.GetStartTimestampUsec()),
				},
				Timeout: timeout,
			})
		}
	}

	// 7: MEMBERSHIP_CHANGED
	if mc := body.GetMembershipChanged(); mc != nil && mc.GetNewMembership() != nil {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		nm := mc.GetNewMembership()
		memberGaiaID := nm.GetId().GetMemberId().GetUserId().GetId()
		if rg, dm, ok := pb.GroupIDToParts(nm.GetId().GetGroupId()); ok {
			isDM, rawGroupID, hasGroup = dm, rg, true
		}
		if hasGroup && memberGaiaID != "" {
			evMembership := event.MembershipJoin
			switch nm.GetMembershipState() {
			case pb.MembershipState_MEMBER_INVITED:
				evMembership = event.MembershipInvite
			case pb.MembershipState_MEMBER_NOT_A_MEMBER:
				evMembership = event.MembershipLeave
			}
			uid := MakeUserID(memberGaiaID)
			memberMap := bridgev2.ChatMemberMap{
				uid: {
					EventSender: bridgev2.EventSender{
						Sender:   uid,
						IsFromMe: c.IsThisUser(ctx, uid),
					},
					Membership: evMembership,
				},
			}
			out = append(out, &simplevent.ChatInfoChange{
				EventMeta: simplevent.EventMeta{
					Type:         bridgev2.RemoteEventChatInfoChange,
					PortalKey:    c.portalKeyFromGroup(isDM, rawGroupID),
					CreatePortal: true,
				},
				ChatInfoChange: &bridgev2.ChatInfoChange{
					MemberChanges: &bridgev2.ChatMemberList{
						MemberMap: memberMap,
					},
				},
			})
		}
	}

	return out, nil
}

// Test request inspection helpers using generated protobuf types.

func decodeListTopicsPageSizeForTopics(req []byte) int64 {
	var r pb.ListTopicsRequest
	if err := pb.Unmarshal(req, &r); err != nil {
		return 0
	}
	return int64(r.GetPageSizeForTopics())
}

func decodeListTopicsPageSizeForReplies(req []byte) int64 {
	var r pb.ListTopicsRequest
	if err := pb.Unmarshal(req, &r); err != nil {
		return 0
	}
	return int64(r.GetPageSizeForReplies())
}

func decodeListMessagesPageSize(req []byte) int64 {
	var r pb.ListMessagesRequest
	if err := pb.Unmarshal(req, &r); err != nil {
		return 0
	}
	return int64(r.GetPageSize())
}

func decodeCatchUpUserFromRevision(req []byte) int64 {
	var r pb.CatchUpUserRequest
	if err := pb.Unmarshal(req, &r); err != nil {
		return 0
	}
	return r.GetRange().GetFromRevisionTimestamp()
}

func decodeCatchUpGroupFromRevision(req []byte) int64 {
	var r pb.CatchUpGroupRequest
	if err := pb.Unmarshal(req, &r); err != nil {
		return 0
	}
	return r.GetRange().GetFromRevisionTimestamp()
}
