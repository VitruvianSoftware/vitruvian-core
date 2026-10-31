// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

var (
	_ bridgev2.EditHandlingNetworkAPI        = (*Client)(nil)
	_ bridgev2.RedactionHandlingNetworkAPI   = (*Client)(nil)
	_ bridgev2.ReactionHandlingNetworkAPI    = (*Client)(nil)
	_ bridgev2.ReadReceiptHandlingNetworkAPI = (*Client)(nil)
	_ bridgev2.TypingHandlingNetworkAPI      = (*Client)(nil)
)

const (
	localIDPrefix         = "mautrix-googlechat%"
	maxOutboundTextLength = 4096
)

func generateUUIDv4() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func (c *Client) registerPendingLocalID() string {
	localID := localIDPrefix + generateUUIDv4()
	c.mu.Lock()
	if c.pendingLocalIDs == nil {
		c.pendingLocalIDs = make(map[string]struct{})
	}
	for len(c.pendingLocalIDs) >= maxPendingLocalIDs && len(c.pendingLocalOrder) > 0 {
		oldest := c.pendingLocalOrder[0]
		c.pendingLocalOrder = c.pendingLocalOrder[1:]
		delete(c.pendingLocalIDs, oldest)
	}
	c.pendingLocalIDs[localID] = struct{}{}
	c.pendingLocalOrder = append(c.pendingLocalOrder, localID)
	c.mu.Unlock()
	return localID
}

func (c *Client) clearPendingLocalID(localID string) {
	c.mu.Lock()
	delete(c.pendingLocalIDs, localID)
	c.mu.Unlock()
}

func (c *Client) addPendingToIgnore(msg *bridgev2.MatrixMessage, txnID networkid.TransactionID) {
	if msg != nil && msg.Portal != nil && msg.Portal.Bridge != nil && txnID != "" {
		msg.AddPendingToIgnore(txnID)
	}
}

func (c *Client) removePending(msg *bridgev2.MatrixMessage, localID string, txnID networkid.TransactionID) {
	c.mu.Lock()
	delete(c.pendingLocalIDs, localID)
	c.mu.Unlock()
	if msg != nil && msg.Portal != nil && msg.Portal.Bridge != nil && txnID != "" {
		msg.RemovePending(txnID)
	}
}

func convertOutgoingText(content *event.MessageEventContent, allowMentionAll bool) (plainText string, annotations [][]byte, err error) {
	if content == nil {
		return "", nil, errors.New("Google Chat message content is empty.")
	}
	if utf8.RuneCountInString(content.Body) > maxOutboundTextLength {
		return "", nil, fmt.Errorf("Google Chat messages can't be longer than 4,096 characters.")
	}
	hasHTML := content.Format == event.FormatHTML && content.FormattedBody != ""
	hasPlainRoomMention := allowMentionAll && (strings.Contains(content.Body, "@room") || strings.Contains(content.Body, "@all"))
	if hasHTML || hasPlainRoomMention {
		var formatted string
		if hasHTML {
			formatted = content.FormattedBody
		}
		plainText, annotations, err = HTMLToAnnotations(content.Body, formatted, allowMentionAll)
		if err != nil {
			return "", nil, err
		}
	} else {
		plainText = content.Body
	}
	if utf8.RuneCountInString(plainText) > maxOutboundTextLength {
		return "", nil, fmt.Errorf("Google Chat messages can't be longer than 4,096 characters.")
	}
	return plainText, annotations, nil
}

func unmarshalAnnotations(raw [][]byte) ([]*pb.Annotation, error) {
	if len(raw) == 0 {
		return nil, nil
	}
	out := make([]*pb.Annotation, 0, len(raw))
	for _, b := range raw {
		var ann pb.Annotation
		if err := pb.Unmarshal(b, &ann); err != nil {
			return nil, fmt.Errorf("decode annotation: %w", err)
		}
		out = append(out, &ann)
	}
	return out, nil
}

func buildTopicID(groupID *pb.GroupId, topicID string) *pb.TopicId {
	tid := &pb.TopicId{
		GroupId: groupID,
	}
	if topicID != "" {
		tid.TopicId = pb.String(topicID)
	}
	return tid
}

func buildMessageParentID(groupID *pb.GroupId, topicID string) *pb.MessageParentId {
	return &pb.MessageParentId{
		Parent: &pb.MessageParentId_TopicId{
			TopicId: buildTopicID(groupID, topicID),
		},
	}
}

func buildMessageID(groupID *pb.GroupId, topicID, msgID string) *pb.MessageId {
	return &pb.MessageId{
		ParentId:  buildMessageParentID(groupID, topicID),
		MessageId: pb.String(msgID),
	}
}

func resolveMessageTopicAndID(dbMsg *database.Message) (topicID, msgID string, createTimeMicros int64) {
	if dbMsg == nil {
		return "", "", 0
	}
	topicID, msgID = ParseMessageID(dbMsg.ID)
	if meta, ok := dbMsg.Metadata.(*MessageMetadata); ok && meta != nil {
		if meta.TopicID != "" {
			topicID = meta.TopicID
		}
		createTimeMicros = meta.CreateTimeMicros
	}
	return topicID, msgID, createTimeMicros
}

func buildSendReplyTarget(groupID *pb.GroupId, replyTo *database.Message, fallbackTopicID string) *pb.SendReplyTarget {
	if replyTo == nil {
		return nil
	}
	rTopicID, rMsgID, createTimeMicros := resolveMessageTopicAndID(replyTo)
	if createTimeMicros <= 0 || rMsgID == "" {
		// Never send SendReplyTarget with zero create_time (research §3.5).
		return nil
	}
	if rTopicID == "" {
		rTopicID = fallbackTopicID
	}
	if rTopicID == "" {
		rTopicID = rMsgID
	}
	return &pb.SendReplyTarget{
		Id:         buildMessageID(groupID, rTopicID, rMsgID),
		CreateTime: pb.Int64(createTimeMicros),
	}
}

// HandleMatrixMessage sends an outbound message to Google Chat via create_topic or create_message.
func (c *Client) HandleMatrixMessage(ctx context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	if msg == nil || msg.Portal == nil {
		return nil, errors.New("missing portal for Google Chat message")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return nil, err
	}
	plainText, annotations, err := c.prepareOutgoingMessageContent(ctx, msg, isDM, rawGroupID)
	if err != nil {
		return nil, err
	}

	var isThreaded bool
	c.metaMu.Lock()
	if meta, ok := msg.Portal.Metadata.(*PortalMetadata); ok && meta != nil {
		isThreaded = meta.TopicThreaded || meta.ThreadsEnabled
	}
	c.metaMu.Unlock()

	groupID := pb.PartsToGroupID(rawGroupID, isDM)
	localID := c.registerPendingLocalID()
	txnID := networkid.TransactionID(localID)
	c.addPendingToIgnore(msg, txnID)

	var topicID string
	if msg.ThreadRoot != nil {
		tTopic, tMsg, _ := resolveMessageTopicAndID(msg.ThreadRoot)
		if tTopic != "" {
			topicID = tTopic
		} else {
			topicID = tMsg
		}
	} else if msg.ReplyTo != nil && (isDM || isThreaded) {
		rTopic, rMsg, _ := resolveMessageTopicAndID(msg.ReplyTo)
		if rTopic != "" {
			topicID = rTopic
		} else {
			topicID = rMsg
		}
	}

	// Top-level message in a Space (including a quote-reply in an unthreaded Space) creates a new Topic via POST /u/0/api/create_topic.
	// Thread replies in a Space or messages in a DM call POST /u/0/api/create_message.
	if !isDM && topicID == "" {
		return c.sendCreateTopic(ctx, msg, groupID, plainText, annotations, localID, txnID)
	}
	return c.sendCreateMessage(ctx, msg, groupID, topicID, plainText, annotations, localID, txnID)
}

func (c *Client) sendCreateTopic(
	ctx context.Context,
	msg *bridgev2.MatrixMessage,
	groupID *pb.GroupId,
	plainText string,
	annotations [][]byte,
	localID string,
	txnID networkid.TransactionID,
) (*bridgev2.MatrixMessageResponse, error) {
	anns, err := unmarshalAnnotations(annotations)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, err
	}

	reqBytes, err := pb.Marshal(&pb.CreateTopicRequest{
		GroupId:     groupID,
		TextBody:    pb.String(plainText),
		Annotations: anns,
		LocalId:     pb.String(localID),
		RetentionSettings: &pb.RetentionSettings{
			State: pb.RetentionSettings_PERMANENT.Enum(),
		},
		HistoryV2: pb.Bool(true),
		MessageInfo: &pb.MessageInfo{
			AcceptFormatAnnotations: pb.Bool(true),
			ReplyTo:                 buildSendReplyTarget(groupID, msg.ReplyTo, ""),
		},
	})
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("marshal create_topic request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "create_topic", reqBytes)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("create_topic failed: %w", err)
	}

	var resp pb.CreateTopicResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("decode create_topic response: %w", err)
	}

	topicID := resp.GetTopic().GetId().GetTopicId()
	var pm parsedMessage
	if replies := resp.GetTopic().GetReplies(); len(replies) > 0 {
		pm = parseMessageFromProto(replies[0])
	}
	groupRev := resp.GetGroupRevision().GetTimestamp()
	if topicID == "" {
		topicID = pm.topicID
	}
	msgID := pm.messageID
	if msgID == "" {
		msgID = topicID
	}
	if topicID == "" || msgID == "" {
		c.removePending(msg, localID, txnID)
		return nil, errors.New("create_topic returned empty topic_id or message_id")
	}
	createUsec := pm.createTimeUsec
	if createUsec <= 0 {
		createUsec = time.Now().UnixMicro()
	}
	if groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}

	dbID := MakeMessageID(topicID, msgID)
	c.markDispatched(msg.Portal.ID, dbID)
	c.clearPendingLocalID(localID)

	dbMsg := &database.Message{
		ID:        dbID,
		SenderID:  c.ownUserID(),
		Timestamp: time.UnixMicro(createUsec),
		Metadata: &MessageMetadata{
			TopicID:          topicID,
			CreateTimeMicros: createUsec,
		},
	}
	c.metaMu.Lock()
	isThreaded := false
	if meta, ok := msg.Portal.Metadata.(*PortalMetadata); ok && meta != nil {
		isThreaded = meta.TopicThreaded || meta.ThreadsEnabled
	}
	c.metaMu.Unlock()
	if isThreaded && topicID != "" {
		dbMsg.ThreadRoot = MakeThreadRootID(topicID)
	}
	if msg.ReplyTo != nil {
		dbMsg.ReplyTo = networkid.MessageOptionalPartID{
			MessageID: msg.ReplyTo.ID,
			PartID:    &msg.ReplyTo.PartID,
		}
	}

	return &bridgev2.MatrixMessageResponse{
		DB:            dbMsg,
		StreamOrder:   createUsec,
		RemovePending: txnID,
	}, nil
}

func (c *Client) sendCreateMessage(
	ctx context.Context,
	msg *bridgev2.MatrixMessage,
	groupID *pb.GroupId,
	topicID string,
	plainText string,
	annotations [][]byte,
	localID string,
	txnID networkid.TransactionID,
) (*bridgev2.MatrixMessageResponse, error) {
	anns, err := unmarshalAnnotations(annotations)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, err
	}

	reqBytes, err := pb.Marshal(&pb.CreateMessageRequest{
		ParentId:    buildMessageParentID(groupID, topicID),
		TextBody:    pb.String(plainText),
		Annotations: anns,
		LocalId:     pb.String(localID),
		MessageInfo: &pb.MessageInfo{
			AcceptFormatAnnotations: pb.Bool(true),
			ReplyTo:                 buildSendReplyTarget(groupID, msg.ReplyTo, topicID),
		},
	})
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("marshal create_message request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "create_message", reqBytes)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("create_message failed: %w", err)
	}

	var resp pb.CreateMessageResponse
	if err := pb.Unmarshal(respBytes, &resp); err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("decode create_message response: %w", err)
	}

	var pm parsedMessage
	if resp.GetMessage() != nil {
		pm = parseMessageFromProto(resp.GetMessage())
	}
	groupRev := resp.GetGroupRevision().GetTimestamp()
	if pm.topicID != "" {
		topicID = pm.topicID
	}
	msgID := pm.messageID
	if msgID == "" {
		c.removePending(msg, localID, txnID)
		return nil, errors.New("create_message returned empty message_id")
	}
	createUsec := pm.createTimeUsec
	if createUsec <= 0 {
		createUsec = time.Now().UnixMicro()
	}
	if groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}

	dbID := MakeMessageID(topicID, msgID)
	c.markDispatched(msg.Portal.ID, dbID)
	c.clearPendingLocalID(localID)

	dbMsg := &database.Message{
		ID:        dbID,
		SenderID:  c.ownUserID(),
		Timestamp: time.UnixMicro(createUsec),
		Metadata: &MessageMetadata{
			TopicID:          topicID,
			CreateTimeMicros: createUsec,
		},
	}
	c.metaMu.Lock()
	isThreaded := false
	if meta, ok := msg.Portal.Metadata.(*PortalMetadata); ok && meta != nil {
		isThreaded = meta.TopicThreaded || meta.ThreadsEnabled
	}
	c.metaMu.Unlock()
	if isThreaded && topicID != "" {
		dbMsg.ThreadRoot = MakeThreadRootID(topicID)
	}
	if msg.ReplyTo != nil {
		dbMsg.ReplyTo = networkid.MessageOptionalPartID{
			MessageID: msg.ReplyTo.ID,
			PartID:    &msg.ReplyTo.PartID,
		}
	}

	return &bridgev2.MatrixMessageResponse{
		DB:            dbMsg,
		StreamOrder:   createUsec,
		RemovePending: txnID,
	}, nil
}

func (c *Client) markDispatched(portalID networkid.PortalID, msgID networkid.MessageID) {
	if msgID == "" {
		return
	}
	dedupKey := string(portalID) + "|" + string(msgID)
	c.mu.Lock()
	c.recordDispatchedLocked(dedupKey)
	c.mu.Unlock()
}

// HandleMatrixEdit edits an existing message on Google Chat via POST /u/0/api/edit_message.
func (c *Client) HandleMatrixEdit(ctx context.Context, msg *bridgev2.MatrixEdit) error {
	if msg == nil || msg.Portal == nil || msg.EditTarget == nil {
		return errors.New("missing edit target for Google Chat edit")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return err
	}
	plainText, annotations, err := convertOutgoingText(msg.Content, !isDM)
	if err != nil {
		return err
	}
	topicID, msgID, _ := resolveMessageTopicAndID(msg.EditTarget)
	if msgID == "" {
		return errors.New("empty Google Chat message ID for edit")
	}
	groupID := pb.PartsToGroupID(rawGroupID, isDM)
	anns, err := unmarshalAnnotations(annotations)
	if err != nil {
		return err
	}

	reqBytes, err := pb.Marshal(&pb.EditMessageRequest{
		MessageId:   buildMessageID(groupID, topicID, msgID),
		TextBody:    pb.String(plainText),
		Annotations: anns,
		MessageInfo: &pb.MessageInfo{
			AcceptFormatAnnotations: pb.Bool(true),
		},
	})
	if err != nil {
		return fmt.Errorf("marshal edit_message request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "edit_message", reqBytes)
	if err != nil {
		return fmt.Errorf("edit_message failed: %w", err)
	}

	var resp pb.EditMessageResponse
	_ = pb.Unmarshal(respBytes, &resp)
	var pm parsedMessage
	if resp.GetMessage() != nil {
		pm = parseMessageFromProto(resp.GetMessage())
	}
	groupRev := resp.GetGroupRevision().GetTimestamp()
	editTS := pm.lastEditUsec
	if editTS <= 0 {
		editTS = pm.lastUpdateUsec
	}
	if editTS <= 0 {
		editTS = time.Now().UnixMicro()
	}
	meta, ok := msg.EditTarget.Metadata.(*MessageMetadata)
	if !ok || meta == nil {
		meta = &MessageMetadata{TopicID: topicID}
		msg.EditTarget.Metadata = meta
	}
	meta.LastEditTime = editTS
	if msg.Portal.Bridge != nil && msg.Portal.Bridge.DB != nil && msg.EditTarget.RowID != 0 {
		_ = msg.Portal.Bridge.DB.Message.Update(ctx, msg.EditTarget)
	}
	if groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}
	return nil
}

// HandleMatrixMessageRemove deletes a message on Google Chat via POST /u/0/api/delete_message.
func (c *Client) HandleMatrixMessageRemove(ctx context.Context, msg *bridgev2.MatrixMessageRemove) error {
	if msg == nil || msg.Portal == nil || msg.TargetMessage == nil {
		return errors.New("missing target message for Google Chat delete")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return err
	}
	topicID, msgID, _ := resolveMessageTopicAndID(msg.TargetMessage)
	if msgID == "" {
		return errors.New("empty Google Chat message ID for delete")
	}
	groupID := pb.PartsToGroupID(rawGroupID, isDM)

	reqBytes, err := pb.Marshal(&pb.DeleteMessageRequest{
		MessageId: buildMessageID(groupID, topicID, msgID),
	})
	if err != nil {
		return fmt.Errorf("marshal delete_message request: %w", err)
	}
	respBytes, err := c.rpcCall(ctx, "delete_message", reqBytes)
	if err != nil {
		return fmt.Errorf("delete_message failed: %w", err)
	}

	var resp pb.DeleteMessageResponse
	_ = pb.Unmarshal(respBytes, &resp)
	if groupRev := resp.GetGroupRevision().GetTimestamp(); groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}
	return nil
}

// PreHandleMatrixReaction strips U+FE0F from the reaction emoji before sending to Google Chat.
func (c *Client) PreHandleMatrixReaction(_ context.Context, msg *bridgev2.MatrixReaction) (bridgev2.MatrixReactionPreResponse, error) {
	if msg == nil || msg.Content == nil {
		return bridgev2.MatrixReactionPreResponse{}, errors.New("missing reaction content")
	}
	cleaned := strings.ReplaceAll(msg.Content.RelatesTo.Key, "\uFE0F", "")
	if cleaned == "" {
		return bridgev2.MatrixReactionPreResponse{}, errors.New("empty reaction emoji")
	}
	return bridgev2.MatrixReactionPreResponse{
		SenderID:     c.ownUserID(),
		EmojiID:      networkid.EmojiID(cleaned),
		Emoji:        cleaned,
		MaxReactions: -1,
	}, nil
}

// HandleMatrixReaction adds a reaction on Google Chat via POST /u/0/api/update_reaction (ReactionAction = ADD).
func (c *Client) HandleMatrixReaction(ctx context.Context, msg *bridgev2.MatrixReaction) (*database.Reaction, error) {
	if msg == nil || msg.Portal == nil || msg.TargetMessage == nil {
		return nil, errors.New("missing target message for Google Chat reaction")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return nil, err
	}
	topicID, msgID, _ := resolveMessageTopicAndID(msg.TargetMessage)
	if msgID == "" {
		return nil, errors.New("empty Google Chat message ID for reaction")
	}
	var emoji string
	if msg.PreHandleResp != nil && msg.PreHandleResp.Emoji != "" {
		emoji = strings.ReplaceAll(msg.PreHandleResp.Emoji, "\uFE0F", "")
	} else if msg.Content != nil {
		emoji = strings.ReplaceAll(msg.Content.RelatesTo.Key, "\uFE0F", "")
	}
	if emoji == "" {
		return nil, errors.New("empty reaction emoji")
	}

	groupID := pb.PartsToGroupID(rawGroupID, isDM)
	reqBytes, err := pb.Marshal(&pb.UpdateReactionRequest{
		MessageId: buildMessageID(groupID, topicID, msgID),
		Emoji: &pb.Emoji{
			Content: &pb.Emoji_Unicode{Unicode: emoji},
		},
		Type: pb.UpdateReactionRequest_ADD.Enum(),
	})
	if err != nil {
		return nil, fmt.Errorf("marshal update_reaction request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "update_reaction", reqBytes)
	if err != nil {
		return nil, fmt.Errorf("update_reaction (ADD) failed: %w", err)
	}
	var resp pb.UpdateReactionResponse
	_ = pb.Unmarshal(respBytes, &resp)
	if groupRev := resp.GetGroupRevision().GetTimestamp(); groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}

	return &database.Reaction{
		EmojiID: networkid.EmojiID(emoji),
		Emoji:   emoji,
		Metadata: &ReactionMetadata{
			TopicID: topicID,
		},
	}, nil
}

// HandleMatrixReactionRemove removes a reaction on Google Chat via POST /u/0/api/update_reaction (ReactionAction = REMOVE).
func (c *Client) HandleMatrixReactionRemove(ctx context.Context, msg *bridgev2.MatrixReactionRemove) error {
	if msg == nil || msg.Portal == nil || msg.TargetReaction == nil {
		return errors.New("missing target reaction for Google Chat reaction removal")
	}
	isDM, rawGroupID, err := ParsePortalID(msg.Portal.ID)
	if err != nil {
		return err
	}
	topicID, msgID := ParseMessageID(msg.TargetReaction.MessageID)
	if rMeta, ok := msg.TargetReaction.Metadata.(*ReactionMetadata); ok && rMeta != nil && rMeta.TopicID != "" {
		topicID = rMeta.TopicID
	}
	if msgID == "" {
		return errors.New("empty Google Chat message ID for reaction removal")
	}
	emoji := strings.ReplaceAll(string(msg.TargetReaction.EmojiID), "\uFE0F", "")
	if emoji == "" {
		emoji = strings.ReplaceAll(msg.TargetReaction.Emoji, "\uFE0F", "")
	}
	if emoji == "" {
		return errors.New("empty emoji for reaction removal")
	}

	groupID := pb.PartsToGroupID(rawGroupID, isDM)
	reqBytes, err := pb.Marshal(&pb.UpdateReactionRequest{
		MessageId: buildMessageID(groupID, topicID, msgID),
		Emoji: &pb.Emoji{
			Content: &pb.Emoji_Unicode{Unicode: emoji},
		},
		Type: pb.UpdateReactionRequest_REMOVE.Enum(),
	})
	if err != nil {
		return fmt.Errorf("marshal update_reaction request: %w", err)
	}

	respBytes, err := c.rpcCall(ctx, "update_reaction", reqBytes)
	if err != nil {
		return fmt.Errorf("update_reaction (REMOVE) failed: %w", err)
	}
	var resp pb.UpdateReactionResponse
	_ = pb.Unmarshal(respBytes, &resp)
	if groupRev := resp.GetGroupRevision().GetTimestamp(); groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}
	return nil
}

// HandleMatrixReadReceipt marks a conversation read up to receipt.ReadUpTo via POST /u/0/api/mark_group_readstate.
func (c *Client) HandleMatrixReadReceipt(ctx context.Context, receipt *bridgev2.MatrixReadReceipt) error {
	if receipt == nil || receipt.Portal == nil {
		return nil
	}
	if !receipt.ReadUpTo.After(receipt.LastRead) {
		return nil
	}
	lastReadMicros := receipt.ReadUpTo.UnixMicro()
	if lastReadMicros <= 0 {
		return nil
	}
	isDM, rawGroupID, err := ParsePortalID(receipt.Portal.ID)
	if err != nil {
		return err
	}
	groupID := pb.PartsToGroupID(rawGroupID, isDM)

	reqBytes, err := pb.Marshal(&pb.MarkGroupReadstateRequest{
		Id:           groupID,
		LastReadTime: pb.Int64(lastReadMicros),
	})
	if err != nil {
		return fmt.Errorf("marshal mark_group_readstate request: %w", err)
	}

	_, err = c.rpcCall(ctx, "mark_group_readstate", reqBytes)
	if err != nil {
		return fmt.Errorf("mark_group_readstate failed: %w", err)
	}
	return nil
}

// HandleMatrixTyping sends typing state via POST /u/0/api/set_typing_state.
func (c *Client) HandleMatrixTyping(ctx context.Context, typing *bridgev2.MatrixTyping) error {
	if typing == nil || typing.Portal == nil {
		return nil
	}
	if typing.Type != bridgev2.TypingTypeText {
		return nil
	}
	isDM, rawGroupID, err := ParsePortalID(typing.Portal.ID)
	if err != nil {
		return err
	}
	groupID := pb.PartsToGroupID(rawGroupID, isDM)

	state := pb.TypingState_STOPPED
	if typing.IsTyping {
		state = pb.TypingState_TYPING
	}
	reqBytes, err := pb.Marshal(&pb.SetTypingStateRequest{
		State: state.Enum(),
		Context: &pb.TypingContext{
			Context: &pb.TypingContext_GroupId{GroupId: groupID},
		},
	})
	if err != nil {
		return fmt.Errorf("marshal set_typing_state request: %w", err)
	}

	_, err = c.rpcCall(ctx, "set_typing_state", reqBytes)
	if err != nil {
		return fmt.Errorf("set_typing_state failed: %w", err)
	}
	return nil
}
