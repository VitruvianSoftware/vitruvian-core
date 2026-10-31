// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/gchat/pb"
)

const (
	// MaxMediaBytes is the 200 MiB attachment size limit enforced for Google Chat uploads and downloads.
	MaxMediaBytes = 200 * 1024 * 1024
)

func encodeUploadMetadataAnnotation(uploadMetaProto []byte) ([]byte, error) {
	var meta pb.UploadMetadata
	if err := pb.Unmarshal(uploadMetaProto, &meta); err != nil {
		return nil, fmt.Errorf("decode upload metadata: %w", err)
	}
	return pb.Marshal(&pb.Annotation{
		Type:           pb.AnnotationType_UPLOAD_METADATA.Enum(),
		StartIndex:     pb.Int32(0),
		Length:         pb.Int32(0),
		ChipRenderType: pb.Annotation_RENDER.Enum(),
		Metadata: &pb.Annotation_UploadMetadata{
			UploadMetadata: &meta,
		},
	})
}

func (c *Client) uploadMedia(_ context.Context, rawGroupID, filename, contentType string, data []byte) ([]byte, error) {
	if len(data) == 0 {
		return nil, errors.New("Attachment is empty.")
	}
	if len(data) > MaxMediaBytes {
		return nil, errors.New("Attachments on Google Chat can't be larger than 200 MB.")
	}
	ffi, err := c.ensureFFIClient()
	if err != nil {
		return nil, err
	}
	return ffi.UploadMedia(rawGroupID, filename, contentType, data)
}

func (c *Client) downloadAttachment(_ context.Context, attachmentToken, contentType string) ([]byte, error) {
	ffi, err := c.ensureFFIClient()
	if err != nil {
		return nil, err
	}
	data, err := ffi.DownloadMedia("attachment", attachmentToken, contentType, "", false)
	if err != nil {
		return nil, err
	}
	if len(data) > MaxMediaBytes {
		return nil, errors.New("Attachments on Google Chat can't be larger than 200 MB.")
	}
	return data, nil
}

func (c *Client) downloadAvatar(_ context.Context, avatarURL string) ([]byte, error) {
	ffi, err := c.ensureFFIClient()
	if err != nil {
		return nil, err
	}
	return ffi.DownloadMedia("avatar", "", "", avatarURL, false)
}

func (c *Client) prepareOutgoingMessageContent(
	ctx context.Context,
	msg *bridgev2.MatrixMessage,
	isDM bool,
	rawGroupID string,
) (plainText string, annotations [][]byte, err error) {
	if msg == nil || msg.Content == nil {
		return "", nil, errors.New("Google Chat message content is empty.")
	}

	switch msg.Content.MsgType {
	case event.MsgText, event.MsgNotice, event.MsgEmote, "":
		return convertOutgoingText(msg.Content, !isDM)
	case event.MsgImage, event.MsgVideo, event.MsgAudio, event.CapMsgVoice, event.MsgFile, event.CapMsgGIF:
		// Validated below.
	default:
		return "", nil, errors.New("Google Chat doesn't support this attachment type.")
	}

	// Validate advertised size limit BEFORE reading from Matrix media store or calling Scotty.
	if msg.Content.Info != nil && msg.Content.Info.Size > MaxMediaBytes {
		return "", nil, errors.New("Attachments on Google Chat can't be larger than 200 MB.")
	}

	capType := msg.Content.GetCapMsgType()
	if capType == "" {
		capType = msg.Content.MsgType
	}
	mimeType := ""
	if msg.Content.Info != nil {
		mimeType = strings.TrimSpace(msg.Content.Info.MimeType)
	}
	lowerMime := strings.ToLower(mimeType)
	switch capType {
	case event.MsgImage:
		if mimeType == "" {
			mimeType = "image/png"
		} else if !strings.HasPrefix(lowerMime, "image/") {
			return "", nil, errors.New("Google Chat image attachments require an image MIME type.")
		}
	case event.CapMsgGIF:
		if mimeType == "" {
			mimeType = "image/gif"
		} else if lowerMime != "image/gif" && !strings.HasPrefix(lowerMime, "image/") {
			return "", nil, errors.New("Google Chat GIF attachments require an image/gif MIME type.")
		}
	case event.MsgVideo:
		if mimeType == "" {
			mimeType = "video/mp4"
		} else if !strings.HasPrefix(lowerMime, "video/") {
			return "", nil, errors.New("Google Chat video attachments require a video MIME type.")
		}
	case event.MsgAudio, event.CapMsgVoice:
		if mimeType == "" {
			mimeType = "audio/ogg"
		} else if !strings.HasPrefix(lowerMime, "audio/") {
			return "", nil, errors.New("Google Chat audio attachments require an audio MIME type.")
		}
	case event.MsgFile:
		if mimeType == "" {
			mimeType = "application/octet-stream"
		}
	default:
		return "", nil, errors.New("Google Chat doesn't support this attachment type.")
	}

	if caption := msg.Content.GetCaption(); caption != "" {
		capContent := &event.MessageEventContent{
			MsgType:       event.MsgText,
			Body:          caption,
			Format:        msg.Content.Format,
			FormattedBody: msg.Content.GetFormattedCaption(),
		}
		plainText, annotations, err = convertOutgoingText(capContent, !isDM)
		if err != nil {
			return "", nil, err
		}
	}

	mxcURI := msg.Content.URL
	if mxcURI == "" && msg.Content.File != nil {
		mxcURI = msg.Content.File.URL
	}
	if mxcURI == "" || msg.Portal == nil || msg.Portal.Bridge == nil || msg.Portal.Bridge.Bot == nil {
		return "", nil, errors.New("Missing attachment file for Google Chat upload.")
	}

	data, err := msg.Portal.Bridge.Bot.DownloadMedia(ctx, mxcURI, msg.Content.File)
	if err != nil {
		return "", nil, fmt.Errorf("read attachment for Google Chat upload: %w", err)
	}
	if len(data) == 0 {
		return "", nil, errors.New("Attachment is empty.")
	}
	if len(data) > MaxMediaBytes {
		return "", nil, errors.New("Attachments on Google Chat can't be larger than 200 MB.")
	}

	filename := strings.TrimSpace(msg.Content.GetFileName())
	if filename == "" {
		filename = "attachment.bin"
	}

	uploadMetaProto, err := c.uploadMedia(ctx, rawGroupID, filename, mimeType, data)
	if err != nil {
		return "", nil, fmt.Errorf("upload attachment to Google Chat: %w", err)
	}

	annBytes, err := encodeUploadMetadataAnnotation(uploadMetaProto)
	if err != nil {
		return "", nil, err
	}
	annotations = append(annotations, annBytes)
	return plainText, annotations, nil
}

func eventHasAttachmentDownload(eventProto []byte) bool {
	var evt pb.Event
	if err := pb.Unmarshal(eventProto, &evt); err != nil {
		return false
	}
	checkBody := func(b *pb.Event_EventBody) bool {
		if b == nil {
			return false
		}
		mp := b.GetMessagePosted()
		if mp == nil || mp.GetMessage() == nil {
			return false
		}
		msg := mp.GetMessage()
		for _, ann := range msg.GetAnnotations() {
			if ann.GetUploadMetadata().GetAttachmentToken() != "" {
				return true
			}
		}
		for _, att := range msg.GetAttachments() {
			if att.GetUploadMetadata().GetAttachmentToken() != "" {
				return true
			}
		}
		return false
	}
	if checkBody(evt.GetBody()) {
		return true
	}
	for _, b := range evt.GetBodies() {
		if checkBody(b) {
			return true
		}
	}
	return false
}

func extractMessageUploadMetadataList(rawMessageProto []byte) []*pb.UploadMetadata {
	var msg pb.Message
	if err := pb.Unmarshal(rawMessageProto, &msg); err != nil {
		return nil
	}
	var uploads []*pb.UploadMetadata
	for _, ann := range msg.GetAnnotations() {
		up := ann.GetUploadMetadata()
		if up == nil {
			continue
		}
		if up.GetAttachmentToken() != "" || up.GetClonedDriveId() != "" {
			uploads = append(uploads, up)
		}
	}
	for _, att := range msg.GetAttachments() {
		up := att.GetUploadMetadata()
		if up == nil {
			continue
		}
		if up.GetAttachmentToken() != "" || up.GetClonedDriveId() != "" {
			uploads = append(uploads, up)
		}
	}
	return uploads
}

func (c *Client) resolvePortalMXID(ctx context.Context, pm parsedMessage) id.RoomID {
	if c == nil || c.UserLogin == nil || c.UserLogin.Bridge == nil || !pm.hasGroupID {
		return ""
	}
	pk := c.portalKeyFromGroup(pm.isDM, pm.groupRawID)
	if portal, err := c.UserLogin.Bridge.GetExistingPortalByKey(ctx, pk); err == nil && portal != nil {
		return portal.MXID
	}
	return ""
}

func msgTypeForMime(mimeType string) event.MessageType {
	lower := strings.ToLower(strings.TrimSpace(mimeType))
	switch {
	case strings.HasPrefix(lower, "image/"):
		return event.MsgImage
	case strings.HasPrefix(lower, "video/"):
		return event.MsgVideo
	case strings.HasPrefix(lower, "audio/"):
		return event.MsgAudio
	default:
		return event.MsgFile
	}
}

func (c *Client) extractInboundMediaParts(ctx context.Context, pm parsedMessage) ([]*bridgev2.ConvertedMessagePart, error) {
	uploads := extractMessageUploadMetadataList(pm.rawProto)
	if len(uploads) == 0 {
		return nil, nil
	}

	roomID := c.resolvePortalMXID(ctx, pm)
	parts := make([]*bridgev2.ConvertedMessagePart, 0, len(uploads))
	for idx, up := range uploads {
		partID := networkid.PartID(fmt.Sprintf("att_%04d", idx))
		token := up.GetAttachmentToken()
		driveID := up.GetClonedDriveId()
		if token == "" && driveID != "" {
			driveLink := fmt.Sprintf("https://drive.google.com/file/d/%s/view", driveID)
			parts = append(parts, &bridgev2.ConvertedMessagePart{
				ID:   partID,
				Type: event.EventMessage,
				Content: &event.MessageEventContent{
					MsgType: event.MsgText,
					Body:    driveLink,
				},
				DBMetadata: &MessageMetadata{
					TopicID:          pm.topicID,
					CreateTimeMicros: pm.createTimeUsec,
					LastEditTime:     pm.lastEditUsec,
				},
			})
			continue
		}

		filename := strings.TrimSpace(up.GetContentName())
		if filename == "" {
			filename = fmt.Sprintf("attachment_%04d", idx)
		}

		placeholderPart := func() *bridgev2.ConvertedMessagePart {
			return &bridgev2.ConvertedMessagePart{
				ID:   partID,
				Type: event.EventMessage,
				Content: &event.MessageEventContent{
					MsgType: event.MsgNotice,
					Body:    fmt.Sprintf("Attachment unavailable (%s)", filename),
				},
				DBMetadata: &MessageMetadata{
					TopicID:          pm.topicID,
					CreateTimeMicros: pm.createTimeUsec,
					LastEditTime:     pm.lastEditUsec,
				},
			}
		}

		data, err := c.downloadAttachment(ctx, token, up.GetContentType())
		if err != nil || len(data) == 0 || len(data) > MaxMediaBytes {
			parts = append(parts, placeholderPart())
			continue
		}

		snifferMime := http.DetectContentType(data)
		if strings.HasPrefix(strings.ToLower(snifferMime), "text/html") {
			parts = append(parts, placeholderPart())
			continue
		}
		mimeType := strings.TrimSpace(up.GetContentType())
		if mimeType == "" {
			mimeType = snifferMime
		}
		if strings.HasPrefix(strings.ToLower(mimeType), "text/html") {
			parts = append(parts, placeholderPart())
			continue
		}

		var mxcURI id.ContentURIString
		if c != nil && c.UserLogin != nil && c.UserLogin.Bridge != nil && c.UserLogin.Bridge.Bot != nil {
			uploadedURI, _, upErr := c.UserLogin.Bridge.Bot.UploadMedia(ctx, roomID, data, filename, mimeType)
			if upErr != nil {
				parts = append(parts, placeholderPart())
				continue
			}
			mxcURI = uploadedURI
		}

		parts = append(parts, &bridgev2.ConvertedMessagePart{
			ID:   partID,
			Type: event.EventMessage,
			Content: &event.MessageEventContent{
				MsgType:  msgTypeForMime(mimeType),
				Body:     filename,
				FileName: filename,
				URL:      mxcURI,
				Info: &event.FileInfo{
					MimeType: mimeType,
					Size:     len(data),
				},
			},
			DBMetadata: &MessageMetadata{
				TopicID:          pm.topicID,
				CreateTimeMicros: pm.createTimeUsec,
				LastEditTime:     pm.lastEditUsec,
			},
		})
	}
	return parts, nil
}
