// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package imessage

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
)

const (
	// MaxAttachmentBytes is the 100 MiB attachment limit for iMessage.
	MaxAttachmentBytes = 100 * 1024 * 1024

	// MaxOutboundTextLength is the maximum character count for an outbound iMessage.
	MaxOutboundTextLength = 20000

	localTxnPrefix     = "imessage-local-"
	pendingEchoTTL     = 30 * time.Second
	maxPendingOutbounds = 128
)

var (
	_ bridgev2.ReactionHandlingNetworkAPI    = (*Client)(nil)
	_ bridgev2.ReadReceiptHandlingNetworkAPI = (*Client)(nil)
)

// OutboundMessage describes a message to be sent via Messages.app.
type OutboundMessage struct {
	ChatGUID       string
	ChatIdentifier string
	Service        string
	IsGroup        bool
	Text           string
	AttachmentPath string
	ReplyToGUID    string
}

// OutboundReaction describes a tapback reaction to be sent or removed via Messages.app.
type OutboundReaction struct {
	ChatGUID   string
	TargetGUID string
	Emoji      string
	AssocType  int
	Remove     bool
}

// SendResult is returned by a Sender after delivering an outbound message.
type SendResult struct {
	GUID      string
	Timestamp time.Time
}

// Sender abstracts outbound iMessage delivery so production uses parameterized
// osascript and tests can inspect or simulate outbound messages in chat.db.
type Sender interface {
	SendMessage(ctx context.Context, msg OutboundMessage) (SendResult, error)
	SendReaction(ctx context.Context, react OutboundReaction) error
}

// appleScriptSendToChat uses `on run argv` so the chat GUID, recipient handle,
// message text, and optional attachment path are passed strictly as positional
// arguments and never interpolated into AppleScript source code.
const appleScriptSendToChat = `on run argv
	set chatGUID to item 1 of argv
	set targetHandle to item 2 of argv
	set msgText to item 3 of argv
	set attPath to item 4 of argv
	tell application "Messages"
		set targetChat to missing value
		if chatGUID is not "" then
			try
				set targetChat to chat id chatGUID
			end try
		end if
		if targetChat is not missing value then
			if attPath is not "" then
				set theFile to POSIX file attPath
				send theFile to targetChat
			end if
			if msgText is not "" then
				send msgText to targetChat
			end if
		else if targetHandle is not "" then
			set targetService to 1st account whose service type = iMessage
			set theBuddy to participant targetHandle of targetService
			if attPath is not "" then
				set theFile to POSIX file attPath
				send theFile to theBuddy
			end if
			if msgText is not "" then
				send msgText to theBuddy
			end if
		else
			error "Missing iMessage target chat or handle"
		end if
	end tell
end run`

// OSAScriptSender sends outbound messages via /usr/bin/osascript using
// parameterized `on run argv` arguments.
type OSAScriptSender struct {
	// ExecFunc executes the osascript command; if nil, exec.CommandContext is used.
	ExecFunc func(ctx context.Context, name string, args ...string) ([]byte, error)
}

// NewOSAScriptSender returns a new production OSAScriptSender.
func NewOSAScriptSender() *OSAScriptSender {
	return &OSAScriptSender{}
}

func (s *OSAScriptSender) runOSAScript(ctx context.Context, script string, argv ...string) ([]byte, error) {
	args := make([]string, 0, 3+len(argv))
	args = append(args, "-e", script, "--")
	args = append(args, argv...)
	if s != nil && s.ExecFunc != nil {
		return s.ExecFunc(ctx, "/usr/bin/osascript", args...)
	}
	cmd := exec.CommandContext(ctx, "/usr/bin/osascript", args...)
	return cmd.CombinedOutput()
}

// SendMessage sends msg via parameterized osascript.
func (s *OSAScriptSender) SendMessage(ctx context.Context, msg OutboundMessage) (SendResult, error) {
	if strings.TrimSpace(msg.ChatGUID) == "" && strings.TrimSpace(msg.ChatIdentifier) == "" {
		return SendResult{}, errors.New("missing iMessage chat GUID or recipient handle")
	}
	if strings.TrimSpace(msg.Text) == "" && strings.TrimSpace(msg.AttachmentPath) == "" {
		return SendResult{}, errors.New("iMessage content is empty")
	}
	out, err := s.runOSAScript(
		ctx,
		appleScriptSendToChat,
		msg.ChatGUID,
		msg.ChatIdentifier,
		msg.Text,
		msg.AttachmentPath,
	)
	if err != nil {
		trimmed := strings.TrimSpace(string(out))
		if trimmed != "" {
			return SendResult{}, fmt.Errorf("osascript send failed: %s: %w", trimmed, err)
		}
		return SendResult{}, fmt.Errorf("osascript send failed: %w", err)
	}
	return SendResult{Timestamp: time.Now().UTC()}, nil
}

// SendReaction sends or removes a tapback reaction. When backed by OSAScriptSender
// without Accessibility tapback automation configured, it returns a clear error.
func (s *OSAScriptSender) SendReaction(_ context.Context, react OutboundReaction) error {
	if strings.TrimSpace(react.TargetGUID) == "" {
		return errors.New("missing target message GUID for iMessage tapback")
	}
	return errors.New("sending iMessage tapbacks requires Accessibility automation on macOS")
}

type pendingOutboundEcho struct {
	localID   string
	chatGUID  string
	text      string
	createdAt time.Time
}

func generateUUIDv4() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func (c *Client) registerPendingEcho(chatGUID, text string) string {
	localID := localTxnPrefix + generateUUIDv4()
	now := time.Now().UTC()
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.pendingOutbounds) >= maxPendingOutbounds {
		c.pendingOutbounds = c.pendingOutbounds[1:]
	}
	c.pendingOutbounds = append(c.pendingOutbounds, pendingOutboundEcho{
		localID:   localID,
		chatGUID:  chatGUID,
		text:      strings.TrimSpace(text),
		createdAt: now,
	})
	return localID
}

func (c *Client) removePendingEcho(localID string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i, p := range c.pendingOutbounds {
		if p.localID == localID {
			c.pendingOutbounds = append(c.pendingOutbounds[:i], c.pendingOutbounds[i+1:]...)
			return
		}
	}
}

func (c *Client) consumePendingOutboundEchoLocked(chatGUID, text string, now time.Time) bool {
	trimmedText := strings.TrimSpace(text)
	valid := c.pendingOutbounds[:0]
	matched := false
	for _, p := range c.pendingOutbounds {
		if now.Sub(p.createdAt) > pendingEchoTTL {
			continue
		}
		if !matched && p.chatGUID == chatGUID && p.text == trimmedText {
			matched = true
			continue
		}
		valid = append(valid, p)
	}
	c.pendingOutbounds = valid
	return matched
}

// HandleMatrixMessage sends an outbound text or media message via the configured Sender.
func (c *Client) HandleMatrixMessage(ctx context.Context, msg *bridgev2.MatrixMessage) (*bridgev2.MatrixMessageResponse, error) {
	if msg == nil || msg.Portal == nil || msg.Content == nil {
		return nil, errors.New("missing portal or content for iMessage")
	}
	chatGUID := string(msg.Portal.ID)
	if strings.TrimSpace(chatGUID) == "" {
		return nil, errors.New("empty iMessage portal ID")
	}

	var chatIdentifier, service string
	var isGroup bool
	c.metaMu.Lock()
	if meta, ok := msg.Portal.Metadata.(*PortalMetadata); ok && meta != nil {
		chatIdentifier = meta.ChatIdentifier
		service = meta.ServiceName
		isGroup = meta.Style == ChatStyleGroup || len(meta.Participants) > 1
	}
	c.metaMu.Unlock()
	if service == "" {
		service = "iMessage"
	}
	if chatIdentifier == "" {
		_, chatIdentifier, isGroup = ParseChatGUID(chatGUID)
	}

	var plainText, attachmentPath, cleanupDir string
	defer func() {
		if cleanupDir != "" {
			_ = os.RemoveAll(cleanupDir)
		}
	}()

	switch msg.Content.MsgType {
	case event.MsgText, event.MsgNotice, event.MsgEmote, "":
		plainText = msg.Content.Body
		if utf8.RuneCountInString(plainText) > MaxOutboundTextLength {
			return nil, fmt.Errorf("iMessage text cannot exceed %d characters", MaxOutboundTextLength)
		}
		if strings.TrimSpace(plainText) == "" {
			return nil, errors.New("iMessage text is empty")
		}
	case event.MsgImage, event.MsgVideo, event.MsgAudio, event.CapMsgVoice, event.MsgFile, event.CapMsgGIF:
		if msg.Content.Info != nil && msg.Content.Info.Size > MaxAttachmentBytes {
			return nil, errors.New("Attachments on iMessage can't be larger than 100 MB.")
		}
		mxcURI := msg.Content.URL
		if mxcURI == "" && msg.Content.File != nil {
			mxcURI = msg.Content.File.URL
		}
		if mxcURI == "" || msg.Portal.Bridge == nil || msg.Portal.Bridge.Bot == nil {
			return nil, errors.New("Missing attachment file for iMessage send.")
		}
		data, err := msg.Portal.Bridge.Bot.DownloadMedia(ctx, mxcURI, msg.Content.File)
		if err != nil {
			return nil, fmt.Errorf("download attachment for iMessage: %w", err)
		}
		if len(data) == 0 {
			return nil, errors.New("Attachment is empty.")
		}
		if len(data) > MaxAttachmentBytes {
			return nil, errors.New("Attachments on iMessage can't be larger than 100 MB.")
		}
		tmpDir, err := os.MkdirTemp("", "courier-imessage-att-*")
		if err != nil {
			return nil, fmt.Errorf("create temp attachment dir: %w", err)
		}
		cleanupDir = tmpDir
		fileName := filepath.Base(strings.TrimSpace(msg.Content.GetFileName()))
		if fileName == "" || fileName == "." || fileName == "/" {
			fileName = "attachment.bin"
		}
		attachmentPath = filepath.Join(tmpDir, fileName)
		if err := os.WriteFile(attachmentPath, data, 0o600); err != nil {
			return nil, fmt.Errorf("stage attachment file: %w", err)
		}
		if caption := msg.Content.GetCaption(); caption != "" {
			plainText = caption
		}
	default:
		return nil, errors.New("iMessage doesn't support this message type.")
	}

	var replyToGUID string
	if msg.ReplyTo != nil {
		replyToGUID = string(msg.ReplyTo.ID)
		if mMeta, ok := msg.ReplyTo.Metadata.(*MessageMetadata); ok && mMeta != nil && mMeta.GUID != "" {
			replyToGUID = mMeta.GUID
		}
	}

	localID := c.registerPendingEcho(chatGUID, plainText)
	txnID := networkid.TransactionID(localID)
	if msg.Portal.Bridge != nil {
		msg.AddPendingToIgnore(txnID)
	}

	sender := c.sender()
	res, err := sender.SendMessage(ctx, OutboundMessage{
		ChatGUID:       chatGUID,
		ChatIdentifier: chatIdentifier,
		Service:        service,
		IsGroup:        isGroup,
		Text:           plainText,
		AttachmentPath: attachmentPath,
		ReplyToGUID:    replyToGUID,
	})
	if err != nil {
		c.removePendingEcho(localID)
		if msg.Portal.Bridge != nil {
			msg.RemovePending(txnID)
		}
		return nil, err
	}

	msgGUID := strings.TrimSpace(res.GUID)
	if msgGUID != "" {
		// When the Sender returns the exact message GUID (or inserts into chat.db),
		// mark the GUID dispatched and clear the text-based pending echo.
		c.markDispatched(msg.Portal.ID, networkid.MessageID(msgGUID))
		c.removePendingEcho(localID)
	} else {
		msgGUID = localID
		c.markDispatched(msg.Portal.ID, networkid.MessageID(msgGUID))
	}

	ts := res.Timestamp
	if ts.IsZero() {
		ts = time.Now().UTC()
	}

	dbMsg := &database.Message{
		ID:        networkid.MessageID(msgGUID),
		SenderID:  SelfUserID,
		Timestamp: ts,
		Metadata: &MessageMetadata{
			GUID:    msgGUID,
			Service: service,
		},
	}
	if msg.ReplyTo != nil {
		dbMsg.ReplyTo = networkid.MessageOptionalPartID{
			MessageID: msg.ReplyTo.ID,
			PartID:    &msg.ReplyTo.PartID,
		}
	}

	return &bridgev2.MatrixMessageResponse{
		DB:            dbMsg,
		StreamOrder:   ts.UnixMicro(),
		RemovePending: txnID,
	}, nil
}

// PreHandleMatrixReaction normalizes the reaction emoji for iMessage tapbacks.
func (c *Client) PreHandleMatrixReaction(_ context.Context, msg *bridgev2.MatrixReaction) (bridgev2.MatrixReactionPreResponse, error) {
	if msg == nil || msg.Content == nil {
		return bridgev2.MatrixReactionPreResponse{}, errors.New("missing reaction content")
	}
	raw := strings.TrimSpace(msg.Content.RelatesTo.Key)
	if raw == "" {
		return bridgev2.MatrixReactionPreResponse{}, errors.New("empty reaction emoji")
	}
	_, canonical := EmojiToTapbackType(raw, false)
	return bridgev2.MatrixReactionPreResponse{
		SenderID:     SelfUserID,
		EmojiID:      networkid.EmojiID(canonical),
		Emoji:        canonical,
		MaxReactions: 1,
	}, nil
}

// HandleMatrixReaction sends an outbound tapback via the configured Sender.
func (c *Client) HandleMatrixReaction(ctx context.Context, msg *bridgev2.MatrixReaction) (*database.Reaction, error) {
	if msg == nil || msg.Portal == nil || msg.TargetMessage == nil {
		return nil, errors.New("missing target message for iMessage reaction")
	}
	rawEmoji := ""
	if msg.PreHandleResp != nil && msg.PreHandleResp.Emoji != "" {
		rawEmoji = msg.PreHandleResp.Emoji
	} else if msg.Content != nil {
		rawEmoji = msg.Content.RelatesTo.Key
	}
	if strings.TrimSpace(rawEmoji) == "" {
		return nil, errors.New("empty iMessage reaction emoji")
	}
	assocType, canonical := EmojiToTapbackType(rawEmoji, false)
	targetGUID := string(msg.TargetMessage.ID)
	if mMeta, ok := msg.TargetMessage.Metadata.(*MessageMetadata); ok && mMeta != nil && mMeta.GUID != "" {
		targetGUID = mMeta.GUID
	}

	if err := c.sender().SendReaction(ctx, OutboundReaction{
		ChatGUID:   string(msg.Portal.ID),
		TargetGUID: targetGUID,
		Emoji:      canonical,
		AssocType:  assocType,
		Remove:     false,
	}); err != nil {
		return nil, err
	}

	return &database.Reaction{
		EmojiID: networkid.EmojiID(canonical),
		Emoji:   canonical,
		Metadata: &ReactionMetadata{
			GUID:           targetGUID,
			AssociatedType: assocType,
		},
	}, nil
}

// HandleMatrixReactionRemove removes an outbound tapback via the configured Sender.
func (c *Client) HandleMatrixReactionRemove(ctx context.Context, msg *bridgev2.MatrixReactionRemove) error {
	if msg == nil || msg.Portal == nil || msg.TargetReaction == nil {
		return errors.New("missing target reaction for iMessage reaction removal")
	}
	rawEmoji := string(msg.TargetReaction.EmojiID)
	if rawEmoji == "" {
		rawEmoji = msg.TargetReaction.Emoji
	}
	assocType, canonical := EmojiToTapbackType(rawEmoji, true)
	targetGUID := string(msg.TargetReaction.MessageID)
	if rMeta, ok := msg.TargetReaction.Metadata.(*ReactionMetadata); ok && rMeta != nil && rMeta.GUID != "" {
		targetGUID = rMeta.GUID
	}

	return c.sender().SendReaction(ctx, OutboundReaction{
		ChatGUID:   string(msg.Portal.ID),
		TargetGUID: targetGUID,
		Emoji:      canonical,
		AssocType:  assocType,
		Remove:     true,
	})
}

// HandleMatrixReadReceipt accepts local read receipts gracefully (chat.db is opened read-only).
func (c *Client) HandleMatrixReadReceipt(_ context.Context, _ *bridgev2.MatrixReadReceipt) error {
	return nil
}
