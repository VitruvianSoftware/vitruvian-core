// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"cmp"
	"context"
	"fmt"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

const (
	worldSectionPageSize      = 999
	defaultTopicsPageSize     = 30
	defaultRepliesPageSize    = 10
	defaultMessagesPageSize   = 50
	typingNotificationTimeout = 6 * time.Second
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

// Protobuf wire format helpers.

func protoEncodeVarint(v uint64) []byte {
	var out []byte
	for v >= 0x80 {
		out = append(out, byte(v)|0x80)
		v >>= 7
	}
	out = append(out, byte(v))
	return out
}

func protoEncodeVarintField(fieldNum int, v uint64) []byte {
	tag := uint64((fieldNum << 3) | 0)
	out := protoEncodeVarint(tag)
	out = append(out, protoEncodeVarint(v)...)
	return out
}

func protoEncodeBytesField(fieldNum int, data []byte) []byte {
	tag := uint64((fieldNum << 3) | 2)
	out := protoEncodeVarint(tag)
	out = append(out, protoEncodeVarint(uint64(len(data)))...)
	out = append(out, data...)
	return out
}

func protoEncodeStringField(fieldNum int, s string) []byte {
	return protoEncodeBytesField(fieldNum, []byte(s))
}

func protoDecodeVarint(buf []byte) (val uint64, n int, ok bool) {
	var shift uint
	for i, b := range buf {
		if i >= 10 {
			return 0, 0, false
		}
		val |= uint64(b&0x7F) << shift
		if b < 0x80 {
			return val, i + 1, true
		}
		shift += 7
	}
	return 0, 0, false
}

type protoField struct {
	num      int
	wireType int
	varint   uint64
	bytes    []byte
}

func protoIterFields(buf []byte, fn func(f protoField)) {
	i := 0
	for i < len(buf) {
		tag, n, ok := protoDecodeVarint(buf[i:])
		if !ok {
			return
		}
		i += n
		fieldNum := int(tag >> 3)
		wireType := int(tag & 0x7)
		switch wireType {
		case 0: // varint
			v, vn, vok := protoDecodeVarint(buf[i:])
			if !vok {
				return
			}
			i += vn
			fn(protoField{num: fieldNum, wireType: 0, varint: v})
		case 1: // 64-bit fixed
			if i+8 > len(buf) {
				return
			}
			i += 8
		case 2: // length-delimited
			length, ln, lok := protoDecodeVarint(buf[i:])
			if !lok || uint64(len(buf)-i-ln) < length {
				return
			}
			i += ln
			end := i + int(length)
			fn(protoField{num: fieldNum, wireType: 2, bytes: buf[i:end]})
			i = end
		case 5: // 32-bit fixed
			if i+4 > len(buf) {
				return
			}
			i += 4
		default:
			return
		}
	}
}

func protoEncodeGroupID(isDM bool, rawID string) []byte {
	if isDM {
		// GroupId.dm_id (field 3) -> DmId.dm_id (field 1)
		return protoEncodeBytesField(3, protoEncodeStringField(1, rawID))
	}
	// GroupId.space_id (field 1) -> SpaceId.space_id (field 1)
	return protoEncodeBytesField(1, protoEncodeStringField(1, rawID))
}

func protoDecodeGroupID(buf []byte) (isDM bool, rawID string, ok bool) {
	protoIterFields(buf, func(f protoField) {
		switch f.num {
		case 1: // SpaceId
			protoIterFields(f.bytes, func(sf protoField) {
				if sf.num == 1 && len(sf.bytes) > 0 {
					isDM = false
					rawID = string(sf.bytes)
					ok = true
				}
			})
		case 3: // DmId
			protoIterFields(f.bytes, func(df protoField) {
				if df.num == 1 && len(df.bytes) > 0 {
					isDM = true
					rawID = string(df.bytes)
					ok = true
				}
			})
		}
	})
	return isDM, rawID, ok
}

func protoDecodeRevisionTimestamp(buf []byte) int64 {
	var ts int64
	protoIterFields(buf, func(f protoField) {
		if f.num == 1 && f.wireType == 0 {
			ts = int64(f.varint)
		}
	})
	return ts
}

func protoDecodeUserID(buf []byte) string {
	var uid string
	protoIterFields(buf, func(f protoField) {
		if f.num == 1 && f.wireType == 2 {
			uid = string(f.bytes)
		}
	})
	return uid
}

const (
	initialChatSyncCap               = 30
	membershipStateJoined      int32 = 2
	catchUpStatusAbortedCutoff int32 = 3
	catchUpStatusAbortedCache  int32 = 4
	catchUpStatusAbortedTooOld int32 = 5
)

type parsedWorldItem struct {
	isDM               bool
	rawID              string
	hasGroupID         bool
	groupRevision      int64
	sortTimestamp      int64
	hideTimestamp      int64
	blocked            bool
	membershipState    int32
	hasMembershipState bool
	roomName           string
	hasRoomName        bool
	topicThreaded      bool
	flatThreadsEnabled bool
	memberUserIDs      []string
}

func parseWorldItemLite(buf []byte) parsedWorldItem {
	var item parsedWorldItem
	seenMembers := make(map[string]bool)
	addMember := func(uid string) {
		if uid != "" && !seenMembers[uid] {
			seenMembers[uid] = true
			item.memberUserIDs = append(item.memberUserIDs, uid)
		}
	}

	protoIterFields(buf, func(f protoField) {
		switch f.num {
		case 1: // group_id
			if isDM, rawID, ok := protoDecodeGroupID(f.bytes); ok {
				item.isDM = isDM
				item.rawID = rawID
				item.hasGroupID = true
			}
		case 2: // group_revision
			item.groupRevision = protoDecodeRevisionTimestamp(f.bytes)
		case 3: // sort_timestamp
			if f.wireType == 0 {
				item.sortTimestamp = int64(f.varint)
			}
		case 4: // read_state (GroupReadState)
			protoIterFields(f.bytes, func(rf protoField) {
				switch rf.num {
				case 9: // hide_timestamp
					if rf.wireType == 0 {
						item.hideTimestamp = int64(rf.varint)
					}
				case 15: // blocked
					if rf.wireType == 0 && rf.varint != 0 {
						item.blocked = true
					}
				case 16: // membership_state (MembershipState: 2 = MEMBER_JOINED)
					if rf.wireType == 0 {
						item.membershipState = int32(rf.varint)
						item.hasMembershipState = true
					}
				case 23: // joined_users (UserId)
					if rf.wireType == 2 {
						addMember(protoDecodeUserID(rf.bytes))
					}
				}
			})
		case 5: // room_name
			if f.wireType == 2 {
				item.roomName = string(f.bytes)
				item.hasRoomName = true
			}
		case 6: // dm_members (DmMembers)
			protoIterFields(f.bytes, func(df protoField) {
				switch df.num {
				case 1: // members (UserId)
					addMember(protoDecodeUserID(df.bytes))
				case 2: // memberships (MembershipLite)
					protoIterFields(df.bytes, func(mf protoField) {
						if mf.num == 1 && mf.wireType == 2 {
							addMember(protoDecodeUserID(mf.bytes))
						}
					})
				}
			})
		case 15: // threaded_group (ThreadedGroup)
			if f.wireType == 2 {
				item.topicThreaded = true
			}
		case 27: // flat_threads_enabled
			if f.wireType == 0 && f.varint != 0 {
				item.flatThreadsEnabled = true
			}
		}
	})
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

	// PaginatedWorldRequest:
	// - world_section_requests (field 2): WorldSectionRequest { page_size (field 1) = 999 }
	// - fetch_options (field 4): EXCLUDE_GROUP_LITE (1), INCLUDE_SNIPPET (3), PARTICIPANT_NAMES (4)
	// - fetch_from_user_spaces (field 5): true (1)
	var req []byte
	req = append(req, protoEncodeBytesField(2, protoEncodeVarintField(1, worldSectionPageSize))...)
	req = append(req, protoEncodeVarintField(4, 1)...)
	req = append(req, protoEncodeVarintField(4, 3)...)
	req = append(req, protoEncodeVarintField(4, 4)...)
	req = append(req, protoEncodeVarintField(5, 1)...)

	respBytes, err := c.rpcCall(ctx, "paginated_world", req)
	if err != nil {
		return fmt.Errorf("paginated_world failed: %w", err)
	}

	var userRev int64
	var items []parsedWorldItem
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // world_section_responses
			protoIterFields(f.bytes, func(sf protoField) {
				if sf.num == 2 && sf.wireType == 2 {
					items = append(items, parseWorldItemLite(sf.bytes))
				}
			})
		case 3: // user_revision
			userRev = protoDecodeRevisionTimestamp(f.bytes)
		case 4: // world_items
			if f.wireType == 2 {
				items = append(items, parseWorldItemLite(f.bytes))
			}
		}
	})

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
		if item.blocked || item.hideTimestamp > 0 || item.membershipState != membershipStateJoined {
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
		if item.groupRevision > meta.GroupRevision {
			meta.GroupRevision = item.groupRevision
			meta.Revision = item.groupRevision
		}
		saveErr := portal.Save(ctx)
		c.metaMu.Unlock()
		if saveErr != nil {
			return fmt.Errorf("save portal %q: %w", portalID, saveErr)
		}
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

func parseMessageIDFields(buf []byte) (isDM bool, groupRawID string, hasGroup bool, topicID, msgID string) {
	protoIterFields(buf, func(f protoField) {
		switch f.num {
		case 1: // parent_id (MessageParentId)
			protoIterFields(f.bytes, func(pf protoField) {
				if pf.num == 4 && pf.wireType == 2 { // topic_id (TopicId)
					protoIterFields(pf.bytes, func(tf protoField) {
						switch tf.num {
						case 2: // topic_id string
							if tf.wireType == 2 {
								topicID = string(tf.bytes)
							}
						case 3: // group_id (GroupId)
							if dm, raw, ok := protoDecodeGroupID(tf.bytes); ok {
								isDM = dm
								groupRawID = raw
								hasGroup = true
							}
						}
					})
				}
			})
		case 2: // message_id string
			if f.wireType == 2 {
				msgID = string(f.bytes)
			}
		}
	})
	return isDM, groupRawID, hasGroup, topicID, msgID
}

func parseMessageProto(raw []byte) parsedMessage {
	pm := parsedMessage{rawProto: raw}
	protoIterFields(raw, func(f protoField) {
		switch f.num {
		case 1: // id (MessageId)
			pm.isDM, pm.groupRawID, pm.hasGroupID, pm.topicID, pm.messageID = parseMessageIDFields(f.bytes)
		case 2: // creator (User)
			protoIterFields(f.bytes, func(uf protoField) {
				if uf.num == 1 && uf.wireType == 2 {
					pm.senderGaiaID = protoDecodeUserID(uf.bytes)
				}
			})
		case 3: // create_time
			if f.wireType == 0 {
				pm.createTimeUsec = int64(f.varint)
			}
		case 4: // last_update_time
			if f.wireType == 0 {
				pm.lastUpdateUsec = int64(f.varint)
			}
		case 14: // local_id
			if f.wireType == 2 {
				pm.localID = string(f.bytes)
			}
		case 17: // last_edit_time
			if f.wireType == 0 {
				pm.lastEditUsec = int64(f.varint)
			}
		case 37: // reply_to (ReplyToMessage)
			protoIterFields(f.bytes, func(rf protoField) {
				if rf.num == 1 && rf.wireType == 2 {
					_, _, _, rTopicID, rMsgID := parseMessageIDFields(rf.bytes)
					pm.replyTopicID = rTopicID
					pm.replyMsgID = rMsgID
				}
			})
		}
	})
	return pm
}

func (c *Client) convertParsedMessage(pm parsedMessage) (*bridgev2.ConvertedMessage, error) {
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

	mediaParts, err := c.extractInboundMediaParts(context.Background(), pm)
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
		// ListMessagesRequest:
		// - parent_id (field 1): MessageParentId { topic_id (field 4): TopicId { group_id (field 3): GroupId } }
		// - page_size (field 2): pageSize
		topicIDProto := protoEncodeBytesField(3, protoEncodeGroupID(true, rawID))
		parentIDProto := protoEncodeBytesField(4, topicIDProto)
		var req []byte
		req = append(req, protoEncodeBytesField(1, parentIDProto)...)
		req = append(req, protoEncodeVarintField(2, uint64(pageSize))...)

		respBytes, err := c.rpcCall(ctx, "list_messages", req)
		if err != nil {
			return nil, fmt.Errorf("list_messages failed: %w", err)
		}

		var parsed []parsedMessage
		protoIterFields(respBytes, func(f protoField) {
			if f.num == 1 && f.wireType == 2 {
				parsed = append(parsed, parseMessageProto(f.bytes))
			}
		})
		slices.SortStableFunc(parsed, func(a, b parsedMessage) int {
			return cmp.Compare(a.createTimeUsec, b.createTimeUsec)
		})

		backfillMsgs := make([]*bridgev2.BackfillMessage, 0, len(parsed))
		for _, pm := range parsed {
			if pm.messageID == "" {
				continue
			}
			cm, err := c.convertParsedMessage(pm)
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
	var req []byte
	req = append(req, protoEncodeVarintField(2, uint64(topicsPageSize))...)
	req = append(req, protoEncodeVarintField(3, uint64(defaultRepliesPageSize))...)
	req = append(req, protoEncodeVarintField(6, uint64(defaultRepliesPageSize))...)
	req = append(req, protoEncodeVarintField(7, uint64(defaultRepliesPageSize))...)
	req = append(req, protoEncodeBytesField(8, protoEncodeGroupID(false, rawID))...)

	respBytes, err := c.rpcCall(ctx, "list_topics", req)
	if err != nil {
		return nil, fmt.Errorf("list_topics failed: %w", err)
	}

	var parsed []parsedMessage
	protoIterFields(respBytes, func(f protoField) {
		if f.num == 1 && f.wireType == 2 { // Topic
			var topicFallbackID string
			protoIterFields(f.bytes, func(tf protoField) {
				if tf.num == 1 && tf.wireType == 2 { // TopicId
					protoIterFields(tf.bytes, func(tidf protoField) {
						if tidf.num == 2 && tidf.wireType == 2 {
							topicFallbackID = string(tidf.bytes)
						}
					})
				}
			})
			protoIterFields(f.bytes, func(tf protoField) {
				if tf.num == 7 && tf.wireType == 2 { // replies (Message)
					pm := parseMessageProto(tf.bytes)
					if pm.topicID == "" {
						pm.topicID = topicFallbackID
					}
					parsed = append(parsed, pm)
				}
			})
		}
	})
	slices.SortStableFunc(parsed, func(a, b parsedMessage) int {
		return cmp.Compare(a.createTimeUsec, b.createTimeUsec)
	})

	backfillMsgs := make([]*bridgev2.BackfillMessage, 0, len(parsed))
	for _, pm := range parsed {
		if pm.messageID == "" {
			continue
		}
		cm, err := c.convertParsedMessage(pm)
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

func isCatchUpAborted(status int32) bool {
	return status == catchUpStatusAbortedCutoff ||
		status == catchUpStatusAbortedCache ||
		status == catchUpStatusAbortedTooOld
}

// catchUpAfterReconnect calls POST /u/0/api/catch_up_user with from_revision = UserLoginMetadata.UserRevision,
// translates and dispatches every returned Event, falls back to syncWorld when from_revision == 0 or
// CatchUpResponse.status is ABORTED_*, and advances user_revision without overwriting any portal's group_revision.
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

	// CatchUpUserRequest: range (field 1) -> CatchUpRange { from_revision_timestamp (field 1) = fromRev }
	req := protoEncodeBytesField(1, protoEncodeVarintField(1, uint64(fromRev)))
	respBytes, err := c.rpcCall(ctx, "catch_up_user", req)
	if err != nil {
		return fmt.Errorf("catch_up_user failed: %w", err)
	}

	var respStatus int32
	var eventPayloads [][]byte
	maxUserRev := fromRev
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // events (Event)
			if f.wireType == 2 {
				eventPayloads = append(eventPayloads, f.bytes)
				protoIterFields(f.bytes, func(ef protoField) {
					if ef.num == 6 && ef.wireType == 2 { // user_revision
						if r := protoDecodeRevisionTimestamp(ef.bytes); r > maxUserRev {
							maxUserRev = r
						}
					}
				})
			}
		case 2: // status (CatchUpResponse.ResponseStatus)
			if f.wireType == 0 {
				respStatus = int32(f.varint)
			}
		case 4: // read_revision (if present)
			if f.wireType == 2 {
				if r := protoDecodeRevisionTimestamp(f.bytes); r > maxUserRev {
					maxUserRev = r
				}
			}
		}
	})

	if isCatchUpAborted(respStatus) {
		return c.syncWorld(ctx)
	}

	for _, evtBytes := range eventPayloads {
		remoteEvts, err := c.translateEventProto(ctx, evtBytes, false, false)
		if err != nil {
			return err
		}
		for _, re := range remoteEvts {
			c.queueRemoteEvent(ctx, re)
		}
	}

	if maxUserRev > fromRev {
		return c.advanceUserRevision(ctx, maxUserRev)
	}
	return nil
}

// catchUpGroup calls POST /u/0/api/catch_up_group for a single portal with from_revision = PortalMetadata.GroupRevision,
// translates and dispatches every returned Event, falls back to syncWorld when from_revision == 0 or
// CatchUpResponse.status is ABORTED_*, and advances only that portal's group_revision.
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

	groupIDProto := protoEncodeGroupID(isDM, rawID)
	// CatchUpGroupRequest:
	// - group_id (field 1): GroupId
	// - range (field 2): CatchUpRange { from_revision_timestamp (field 1) = fromRev }
	var req []byte
	req = append(req, protoEncodeBytesField(1, groupIDProto)...)
	req = append(req, protoEncodeBytesField(2, protoEncodeVarintField(1, uint64(fromRev)))...)

	respBytes, err := c.rpcCall(ctx, "catch_up_group", req)
	if err != nil {
		return fmt.Errorf("catch_up_group failed: %w", err)
	}

	var respStatus int32
	var eventPayloads [][]byte
	maxGroupRev := fromRev
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // events (Event)
			if f.wireType == 2 {
				eventPayloads = append(eventPayloads, f.bytes)
				protoIterFields(f.bytes, func(ef protoField) {
					if ef.num == 7 && ef.wireType == 2 { // group_revision
						if r := protoDecodeRevisionTimestamp(ef.bytes); r > maxGroupRev {
							maxGroupRev = r
						}
					}
				})
			}
		case 2: // status (CatchUpResponse.ResponseStatus)
			if f.wireType == 0 {
				respStatus = int32(f.varint)
			}
		case 4: // read_revision (if present)
			if f.wireType == 2 {
				if r := protoDecodeRevisionTimestamp(f.bytes); r > maxGroupRev {
					maxGroupRev = r
				}
			}
		}
	})

	if isCatchUpAborted(respStatus) {
		return c.syncWorld(ctx)
	}

	for _, evtBytes := range eventPayloads {
		var hasGroup bool
		protoIterFields(evtBytes, func(ef protoField) {
			if ef.num == 1 && ef.wireType == 2 {
				hasGroup = true
			}
		})
		if !hasGroup {
			withGroup := make([]byte, 0, len(groupIDProto)+4+len(evtBytes))
			withGroup = append(withGroup, protoEncodeBytesField(1, groupIDProto)...)
			withGroup = append(withGroup, evtBytes...)
			evtBytes = withGroup
		}
		remoteEvts, err := c.translateEventProto(ctx, evtBytes, false, false)
		if err != nil {
			return err
		}
		for _, re := range remoteEvts {
			c.queueRemoteEvent(ctx, re)
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

// translateWebChannelEvent splits a Google Chat Event (singular body field 4 + repeated bodies field 8)
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
	var outerIsDM bool
	var outerRawGroupID string
	var hasOuterGroupID bool
	var outerEventType uint64
	var userRev int64
	var groupRev int64
	var bodySlices [][]byte

	protoIterFields(eventProto, func(f protoField) {
		switch f.num {
		case 1: // group_id
			if isDM, raw, ok := protoDecodeGroupID(f.bytes); ok {
				outerIsDM = isDM
				outerRawGroupID = raw
				hasOuterGroupID = true
			}
		case 3: // type (EventType)
			if f.wireType == 0 {
				outerEventType = f.varint
			}
		case 4: // singular body (EventBody)
			if f.wireType == 2 {
				bodySlices = append([][]byte{f.bytes}, bodySlices...)
			}
		case 6: // user_revision
			if f.wireType == 2 {
				userRev = protoDecodeRevisionTimestamp(f.bytes)
			}
		case 7: // group_revision
			if f.wireType == 2 {
				groupRev = protoDecodeRevisionTimestamp(f.bytes)
			}
		case 8: // repeated bodies (EventBody)
			if f.wireType == 2 {
				bodySlices = append(bodySlices, f.bytes)
			}
		}
	})

	var out []bridgev2.RemoteEvent
	for _, bodyBytes := range bodySlices {
		evts, err := c.translateSingleEventBody(ctx, outerIsDM, outerRawGroupID, hasOuterGroupID, outerEventType, bodyBytes)
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
	outerEventType uint64,
	bodyBytes []byte,
) ([]bridgev2.RemoteEvent, error) {
	bodyEventType := outerEventType
	var msgPostedBytes []byte
	var membershipChangedBytes []byte
	var msgDeletedBytes []byte
	var msgReactionBytes []byte
	var typingChangedBytes []byte
	var readReceiptChangedBytes []byte
	var groupReadStateUpdatedBytes []byte

	protoIterFields(bodyBytes, func(f protoField) {
		switch f.num {
		case 6: // message_posted (MessageEvent)
			msgPostedBytes = f.bytes
		case 12: // event_type (EventType)
			if f.wireType == 0 && f.varint != 0 {
				bodyEventType = f.varint
			}
		case 14: // membership_changed (MembershipChangedEvent)
			membershipChangedBytes = f.bytes
		case 18: // message_deleted (MessageDeletedEvent)
			msgDeletedBytes = f.bytes
		case 22: // message_reaction (MessageReactionEvent)
			msgReactionBytes = f.bytes
		case 26: // typing_state_changed (TypingStateChangedEvent)
			typingChangedBytes = f.bytes
		case 33: // read_receipt_changed (ReadReceiptChangedEvent)
			readReceiptChangedBytes = f.bytes
		case 65: // group_read_state_updated_event (GroupReadStateUpdatedEvent)
			groupReadStateUpdatedBytes = f.bytes
		}
	})

	var out []bridgev2.RemoteEvent

	// 1 & 2: MESSAGE_POSTED (6) or MESSAGE_UPDATED (7)
	if len(msgPostedBytes) > 0 {
		var rawMsg []byte
		protoIterFields(msgPostedBytes, func(f protoField) {
			if f.num == 1 && f.wireType == 2 {
				rawMsg = f.bytes
			}
		})
		if len(rawMsg) > 0 {
			pm := parseMessageProto(rawMsg)
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
				if bodyEventType == 7 { // MESSAGE_UPDATED (edit)
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
						ConvertEditFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, existing []*database.Message, data parsedMessage) (*bridgev2.ConvertedEdit, error) {
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
							cm, err := c.convertParsedMessage(data)
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
					cm, err := c.convertParsedMessage(pm)
					if err != nil {
						return nil, err
					}
					out = append(out, &simplevent.PreConvertedMessage{
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
						Data:          cm,
					})
				}
			}
		}
	}

	// 3: MESSAGE_DELETED (field 18)
	if len(msgDeletedBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		var topicID, msgID string
		var ts int64
		protoIterFields(msgDeletedBytes, func(f protoField) {
			switch f.num {
			case 1: // message_id (MessageId)
				dm, rg, hg, tid, mid := parseMessageIDFields(f.bytes)
				topicID, msgID = tid, mid
				if !hasGroup && hg {
					isDM, rawGroupID, hasGroup = dm, rg, true
				}
			case 2: // timestamp
				if f.wireType == 0 {
					ts = int64(f.varint)
				}
			}
		})
		if hasGroup && msgID != "" {
			out = append(out, &simplevent.MessageRemove{
				EventMeta: simplevent.EventMeta{
					Type:      bridgev2.RemoteEventMessageRemove,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Timestamp: time.UnixMicro(ts),
				},
				TargetMessage: MakeMessageID(topicID, msgID),
			})
		}
	}

	// 4: MESSAGE_REACTED (field 22)
	if len(msgReactionBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		var topicID, msgID, unicodeEmoji, reactorGaiaID string
		var ts int64
		var actionType uint64
		protoIterFields(msgReactionBytes, func(f protoField) {
			switch f.num {
			case 1: // message_id (MessageId)
				dm, rg, hg, tid, mid := parseMessageIDFields(f.bytes)
				topicID, msgID = tid, mid
				if !hasGroup && hg {
					isDM, rawGroupID, hasGroup = dm, rg, true
				}
			case 2: // emoji (Emoji)
				protoIterFields(f.bytes, func(ef protoField) {
					if ef.num == 1 && ef.wireType == 2 {
						unicodeEmoji = string(ef.bytes)
					}
				})
			case 3: // user_id (UserId)
				reactorGaiaID = protoDecodeUserID(f.bytes)
			case 4: // timestamp
				if f.wireType == 0 {
					ts = int64(f.varint)
				}
			case 5: // type (ADD=1, REMOVE=2)
				if f.wireType == 0 {
					actionType = f.varint
				}
			}
		})
		if hasGroup && msgID != "" && (actionType == 1 || actionType == 2) {
			evtType := bridgev2.RemoteEventReaction
			if actionType == 2 {
				evtType = bridgev2.RemoteEventReactionRemove
			}
			bareEmoji, displayEmoji := normalizeEmojiForDisplay(unicodeEmoji)
			senderID := MakeUserID(reactorGaiaID)
			out = append(out, &simplevent.Reaction{
				EventMeta: simplevent.EventMeta{
					Type:      evtType,
					PortalKey: c.portalKeyFromGroup(isDM, rawGroupID),
					Sender: bridgev2.EventSender{
						Sender:   senderID,
						IsFromMe: c.IsThisUser(ctx, senderID),
					},
					Timestamp: time.UnixMicro(ts),
				},
				TargetMessage: MakeMessageID(topicID, msgID),
				EmojiID:       networkid.EmojiID(bareEmoji),
				Emoji:         displayEmoji,
			})
		}
	}

	// 5a: GROUP_READ_STATE_UPDATED (field 65)
	if len(groupReadStateUpdatedBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		var mostRecentReadTime int64
		protoIterFields(groupReadStateUpdatedBytes, func(f protoField) {
			switch f.num {
			case 1: // group_id
				if dm, rg, ok := protoDecodeGroupID(f.bytes); ok {
					isDM, rawGroupID, hasGroup = dm, rg, true
				}
			case 3: // most_recent_read_time
				if f.wireType == 0 {
					mostRecentReadTime = int64(f.varint)
				}
			}
		})
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

	// 5b: READ_RECEIPT_CHANGED (field 33)
	if len(readReceiptChangedBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		protoIterFields(readReceiptChangedBytes, func(f protoField) {
			switch f.num {
			case 1: // group_id
				if dm, rg, ok := protoDecodeGroupID(f.bytes); ok {
					isDM, rawGroupID, hasGroup = dm, rg, true
				}
			case 2: // read_receipt_set
				protoIterFields(f.bytes, func(sf protoField) {
					if sf.num == 2 && sf.wireType == 2 { // read_receipts (ReadReceipt)
						var readTimeMicros int64
						var readerGaiaID string
						protoIterFields(sf.bytes, func(rf protoField) {
							switch rf.num {
							case 2:
								if rf.wireType == 0 {
									readTimeMicros = int64(rf.varint)
								}
							case 3: // user (User)
								protoIterFields(rf.bytes, func(uf protoField) {
									if uf.num == 1 && uf.wireType == 2 {
										readerGaiaID = protoDecodeUserID(uf.bytes)
									}
								})
							}
						})
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
				})
			}
		})
	}

	// 6: TYPING_STATE_CHANGED (field 26)
	if len(typingChangedBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		var state uint64
		var typerGaiaID string
		var startUsec int64
		protoIterFields(typingChangedBytes, func(f protoField) {
			switch f.num {
			case 1: // state (TYPING=1, STOPPED=2)
				if f.wireType == 0 {
					state = f.varint
				}
			case 2: // user_id
				typerGaiaID = protoDecodeUserID(f.bytes)
			case 3: // context (TypingContext)
				protoIterFields(f.bytes, func(cf protoField) {
					switch cf.num {
					case 1: // group_id
						if dm, rg, ok := protoDecodeGroupID(cf.bytes); ok {
							isDM, rawGroupID, hasGroup = dm, rg, true
						}
					case 2: // topic_id
						protoIterFields(cf.bytes, func(tf protoField) {
							if tf.num == 3 && tf.wireType == 2 {
								if dm, rg, ok := protoDecodeGroupID(tf.bytes); ok {
									isDM, rawGroupID, hasGroup = dm, rg, true
								}
							}
						})
					}
				})
			case 4: // start_timestamp_usec
				if f.wireType == 0 {
					startUsec = int64(f.varint)
				}
			}
		})
		if hasGroup && typerGaiaID != "" {
			var timeout time.Duration
			if state == 1 { // TYPING
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
					Timestamp: time.UnixMicro(startUsec),
				},
				Timeout: timeout,
			})
		}
	}

	// 7: MEMBERSHIP_CHANGED (field 14)
	if len(membershipChangedBytes) > 0 {
		isDM, rawGroupID, hasGroup := outerIsDM, outerRawGroupID, hasOuterGroupID
		var memberGaiaID string
		var membershipState uint64
		protoIterFields(membershipChangedBytes, func(f protoField) {
			if f.num == 1 && f.wireType == 2 { // new_membership (Membership)
				protoIterFields(f.bytes, func(mf protoField) {
					switch mf.num {
					case 1: // id (MembershipId)
						protoIterFields(mf.bytes, func(idf protoField) {
							switch idf.num {
							case 1: // member_id (MemberId)
								protoIterFields(idf.bytes, func(midf protoField) {
									if midf.num == 1 && midf.wireType == 2 {
										memberGaiaID = protoDecodeUserID(midf.bytes)
									}
								})
							case 2: // group_id (GroupId)
								if dm, rg, ok := protoDecodeGroupID(idf.bytes); ok {
									isDM, rawGroupID, hasGroup = dm, rg, true
								}
							}
						})
					case 3: // membership_state (MEMBER_INVITED=1, MEMBER_JOINED=2, MEMBER_NOT_A_MEMBER=3)
						if mf.wireType == 0 {
							membershipState = mf.varint
						}
					}
				})
			}
		})
		if hasGroup && memberGaiaID != "" {
			evMembership := event.MembershipJoin
			switch membershipState {
			case 1:
				evMembership = event.MembershipInvite
			case 3:
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

// Test request inspection helpers.

func decodeListTopicsPageSizeForTopics(req []byte) int64 {
	var v int64
	protoIterFields(req, func(f protoField) {
		if f.num == 2 && f.wireType == 0 {
			v = int64(f.varint)
		}
	})
	return v
}

func decodeListTopicsPageSizeForReplies(req []byte) int64 {
	var v int64
	protoIterFields(req, func(f protoField) {
		if f.num == 3 && f.wireType == 0 {
			v = int64(f.varint)
		}
	})
	return v
}

func decodeListMessagesPageSize(req []byte) int64 {
	var v int64
	protoIterFields(req, func(f protoField) {
		if f.num == 2 && f.wireType == 0 {
			v = int64(f.varint)
		}
	})
	return v
}

func decodeCatchUpUserFromRevision(req []byte) int64 {
	var v int64
	protoIterFields(req, func(f protoField) {
		if f.num == 1 && f.wireType == 2 { // range (CatchUpRange)
			protoIterFields(f.bytes, func(rf protoField) {
				if rf.num == 1 && rf.wireType == 0 {
					v = int64(rf.varint)
				}
			})
		}
	})
	return v
}

func decodeCatchUpGroupFromRevision(req []byte) int64 {
	var v int64
	protoIterFields(req, func(f protoField) {
		if f.num == 2 && f.wireType == 2 { // range (CatchUpRange)
			protoIterFields(f.bytes, func(rf protoField) {
				if rf.num == 1 && rf.wireType == 0 {
					v = int64(rf.varint)
				}
			})
		}
	})
	return v
}
