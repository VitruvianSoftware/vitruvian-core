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
	c.pendingLocalIDs[localID] = struct{}{}
	c.mu.Unlock()
	return localID
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
	if len(content.Body) > maxOutboundTextLength || utf8.RuneCountInString(content.Body) > maxOutboundTextLength {
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
	if len(plainText) > maxOutboundTextLength || utf8.RuneCountInString(plainText) > maxOutboundTextLength {
		return "", nil, fmt.Errorf("Google Chat messages can't be longer than 4,096 characters.")
	}
	return plainText, annotations, nil
}

func encodeTopicIDProto(groupIDProto []byte, topicID string) []byte {
	var out []byte
	if topicID != "" {
		out = append(out, protoEncodeStringField(2, topicID)...)
	}
	out = append(out, protoEncodeBytesField(3, groupIDProto)...)
	return out
}

func encodeMessageParentIDProto(groupIDProto []byte, topicID string) []byte {
	return protoEncodeBytesField(4, encodeTopicIDProto(groupIDProto, topicID))
}

func encodeMessageIDProto(groupIDProto []byte, topicID, msgID string) []byte {
	var out []byte
	out = append(out, protoEncodeBytesField(1, encodeMessageParentIDProto(groupIDProto, topicID))...)
	out = append(out, protoEncodeStringField(2, msgID)...)
	return out
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

func buildSendReplyTargetProto(groupIDProto []byte, replyTo *database.Message, fallbackTopicID string) []byte {
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
	var out []byte
	out = append(out, protoEncodeBytesField(1, encodeMessageIDProto(groupIDProto, rTopicID, rMsgID))...)
	out = append(out, protoEncodeVarintField(2, uint64(createTimeMicros))...)
	return out
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

	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)
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
		return c.sendCreateTopic(ctx, msg, groupIDProto, plainText, annotations, localID, txnID)
	}
	return c.sendCreateMessage(ctx, msg, groupIDProto, topicID, plainText, annotations, localID, txnID)
}

func (c *Client) sendCreateTopic(
	ctx context.Context,
	msg *bridgev2.MatrixMessage,
	groupIDProto []byte,
	plainText string,
	annotations [][]byte,
	localID string,
	txnID networkid.TransactionID,
) (*bridgev2.MatrixMessageResponse, error) {
	// CreateTopicRequest (googlechat.proto:1503):
	// - text_body (field 2): plainText
	// - annotations (field 3): repeated Annotation
	// - local_id (field 4): "mautrix-googlechat%<uuid>"
	// - group_id (field 5): GroupId
	// - retention_settings (field 6): RetentionSettings { state (field 1) = DEFAULT_AWAKE / PERMANENT (1) }
	// - history_v2 (field 8): true (1)
	// - message_info (field 9): MessageInfo { accept_format_annotations (field 1) = true (1), reply_to (field 3): SendReplyTarget }
	var msgInfo []byte
	msgInfo = append(msgInfo, protoEncodeVarintField(1, 1)...)
	if replyTargetProto := buildSendReplyTargetProto(groupIDProto, msg.ReplyTo, ""); len(replyTargetProto) > 0 {
		msgInfo = append(msgInfo, protoEncodeBytesField(3, replyTargetProto)...)
	}

	var req []byte
	req = append(req, protoEncodeStringField(2, plainText)...)
	for _, ann := range annotations {
		req = append(req, protoEncodeBytesField(3, ann)...)
	}
	req = append(req, protoEncodeStringField(4, localID)...)
	req = append(req, protoEncodeBytesField(5, groupIDProto)...)
	req = append(req, protoEncodeBytesField(6, protoEncodeVarintField(1, 1))...)
	req = append(req, protoEncodeVarintField(8, 1)...)
	req = append(req, protoEncodeBytesField(9, msgInfo)...)

	respBytes, err := c.rpcCall(ctx, "create_topic", req)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("create_topic failed: %w", err)
	}

	// CreateTopicResponse (googlechat.proto:1514):
	// - topic (field 1): Topic { id (field 1): TopicId, replies (field 7): repeated Message }
	// - group_revision (field 2): RevisionTimestamp
	var topicID string
	var pm parsedMessage
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // topic (Topic)
			protoIterFields(f.bytes, func(tf protoField) {
				switch tf.num {
				case 1: // id (TopicId)
					protoIterFields(tf.bytes, func(tidf protoField) {
						if tidf.num == 2 && tidf.wireType == 2 {
							topicID = string(tidf.bytes)
						}
					})
				case 7: // replies (Message)
					if pm.messageID == "" {
						pm = parseMessageProto(tf.bytes)
					}
				}
			})
		case 2: // group_revision
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if topicID == "" {
		topicID = pm.topicID
	}
	msgID := pm.messageID
	if msgID == "" {
		msgID = topicID
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
	groupIDProto []byte,
	topicID string,
	plainText string,
	annotations [][]byte,
	localID string,
	txnID networkid.TransactionID,
) (*bridgev2.MatrixMessageResponse, error) {
	// CreateMessageRequest (googlechat.proto:1525):
	// - parent_id (field 1): MessageParentId { topic_id (field 4): TopicId }
	// - text_body (field 2): plainText
	// - annotations (field 3): repeated Annotation
	// - local_id (field 4): "mautrix-googlechat%<uuid>"
	// - message_info (field 7): MessageInfo { accept_format_annotations (field 1) = true (1), reply_to (field 3): SendReplyTarget }
	var msgInfo []byte
	msgInfo = append(msgInfo, protoEncodeVarintField(1, 1)...)
	if replyTargetProto := buildSendReplyTargetProto(groupIDProto, msg.ReplyTo, topicID); len(replyTargetProto) > 0 {
		msgInfo = append(msgInfo, protoEncodeBytesField(3, replyTargetProto)...)
	}

	var req []byte
	req = append(req, protoEncodeBytesField(1, encodeMessageParentIDProto(groupIDProto, topicID))...)
	req = append(req, protoEncodeStringField(2, plainText)...)
	for _, ann := range annotations {
		req = append(req, protoEncodeBytesField(3, ann)...)
	}
	req = append(req, protoEncodeStringField(4, localID)...)
	req = append(req, protoEncodeBytesField(7, msgInfo)...)

	respBytes, err := c.rpcCall(ctx, "create_message", req)
	if err != nil {
		c.removePending(msg, localID, txnID)
		return nil, fmt.Errorf("create_message failed: %w", err)
	}

	// CreateMessageResponse (googlechat.proto:1535):
	// - message (field 1): Message
	// - group_revision (field 3): RevisionTimestamp
	var pm parsedMessage
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1: // message
			pm = parseMessageProto(f.bytes)
		case 3: // group_revision
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if pm.topicID != "" {
		topicID = pm.topicID
	}
	msgID := pm.messageID
	createUsec := pm.createTimeUsec
	if createUsec <= 0 {
		createUsec = time.Now().UnixMicro()
	}
	if groupRev > 0 {
		_ = c.advancePortalGroupRevision(ctx, msg.Portal.PortalKey, groupRev)
	}

	dbID := MakeMessageID(topicID, msgID)
	c.markDispatched(msg.Portal.ID, dbID)

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
	if c.dispatchedMsgIDs == nil {
		c.dispatchedMsgIDs = make(map[string]struct{})
	}
	c.dispatchedMsgIDs[dedupKey] = struct{}{}
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
	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)

	// EditMessageRequest (googlechat.proto:1541):
	// - id (field 1): MessageId
	// - text_body (field 2): plainText
	// - annotations (field 3): repeated Annotation
	// - message_info (field 5): MessageInfo { accept_format_annotations (field 1) = true (1) }
	var req []byte
	req = append(req, protoEncodeBytesField(1, encodeMessageIDProto(groupIDProto, topicID, msgID))...)
	req = append(req, protoEncodeStringField(2, plainText)...)
	for _, ann := range annotations {
		req = append(req, protoEncodeBytesField(3, ann)...)
	}
	req = append(req, protoEncodeBytesField(5, protoEncodeVarintField(1, 1))...)

	respBytes, err := c.rpcCall(ctx, "edit_message", req)
	if err != nil {
		return fmt.Errorf("edit_message failed: %w", err)
	}

	// EditMessageResponse (googlechat.proto:1549):
	// - message (field 1): Message
	// - group_revision (field 3): RevisionTimestamp
	var pm parsedMessage
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		switch f.num {
		case 1:
			pm = parseMessageProto(f.bytes)
		case 3:
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
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
	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)

	// DeleteMessageRequest (googlechat.proto:1555):
	// - id (field 1): MessageId
	req := protoEncodeBytesField(1, encodeMessageIDProto(groupIDProto, topicID, msgID))
	respBytes, err := c.rpcCall(ctx, "delete_message", req)
	if err != nil {
		return fmt.Errorf("delete_message failed: %w", err)
	}

	// DeleteMessageResponse (googlechat.proto:1559):
	// - group_revision (field 3): RevisionTimestamp
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		if f.num == 3 && f.wireType == 2 {
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if groupRev > 0 {
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

// HandleMatrixReaction adds a reaction on Google Chat via POST /u/0/api/update_reaction (ReactionAction = ADD (1)).
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

	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)
	// UpdateReactionRequest (googlechat.proto:1564):
	// - message_id (field 1): MessageId
	// - emoji (field 2): Emoji { unicode (field 1) = emoji }
	// - type (field 3): ReactionAction ADD (1)
	var req []byte
	req = append(req, protoEncodeBytesField(1, encodeMessageIDProto(groupIDProto, topicID, msgID))...)
	req = append(req, protoEncodeBytesField(2, protoEncodeStringField(1, emoji))...)
	req = append(req, protoEncodeVarintField(3, 1)...)

	respBytes, err := c.rpcCall(ctx, "update_reaction", req)
	if err != nil {
		return nil, fmt.Errorf("update_reaction (ADD) failed: %w", err)
	}
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		if f.num == 1 && f.wireType == 2 {
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if groupRev > 0 {
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

// HandleMatrixReactionRemove removes a reaction on Google Chat via POST /u/0/api/update_reaction (ReactionAction = REMOVE (2)).
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

	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)
	var req []byte
	req = append(req, protoEncodeBytesField(1, encodeMessageIDProto(groupIDProto, topicID, msgID))...)
	req = append(req, protoEncodeBytesField(2, protoEncodeStringField(1, emoji))...)
	req = append(req, protoEncodeVarintField(3, 2)...)

	respBytes, err := c.rpcCall(ctx, "update_reaction", req)
	if err != nil {
		return fmt.Errorf("update_reaction (REMOVE) failed: %w", err)
	}
	var groupRev int64
	protoIterFields(respBytes, func(f protoField) {
		if f.num == 1 && f.wireType == 2 {
			groupRev = protoDecodeRevisionTimestamp(f.bytes)
		}
	})
	if groupRev > 0 {
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
	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)

	// MarkGroupReadstateRequest (googlechat.proto:1580):
	// - id (field 1): GroupId
	// - last_read_time (field 2): int64 microsecond timestamp
	var req []byte
	req = append(req, protoEncodeBytesField(1, groupIDProto)...)
	req = append(req, protoEncodeVarintField(2, uint64(lastReadMicros))...)

	_, err = c.rpcCall(ctx, "mark_group_readstate", req)
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
	groupIDProto := protoEncodeGroupID(isDM, rawGroupID)

	// SetTypingStateRequest (googlechat.proto:1591):
	// - state (field 1): TypingState TYPING (1) or STOPPED (2)
	// - context (field 2): TypingContext { group_id (field 1): GroupId }
	var state uint64 = 2
	if typing.IsTyping {
		state = 1
	}
	var req []byte
	req = append(req, protoEncodeVarintField(1, state)...)
	req = append(req, protoEncodeBytesField(2, protoEncodeBytesField(1, groupIDProto))...)

	_, err = c.rpcCall(ctx, "set_typing_state", req)
	if err != nil {
		return fmt.Errorf("set_typing_state failed: %w", err)
	}
	return nil
}
