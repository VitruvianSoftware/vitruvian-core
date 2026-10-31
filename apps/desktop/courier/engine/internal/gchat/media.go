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
)

const (
	// MaxMediaBytes is the 200 MiB attachment size limit enforced for Google Chat uploads and downloads.
	MaxMediaBytes = 200 * 1024 * 1024

	annotationTypeUploadMetadata = 13
	chipRenderTypeRender         = 1
)

type parsedUploadMetadata struct {
	attachmentToken string
	contentName     string
	contentType     string
	localID         string
	clonedDriveID   string
}

func parseUploadMetadataProto(buf []byte) parsedUploadMetadata {
	var out parsedUploadMetadata
	protoIterFields(buf, func(f protoField) {
		if f.wireType != 2 {
			return
		}
		switch f.num {
		case 1:
			out.attachmentToken = string(f.bytes)
		case 3:
			out.contentName = string(f.bytes)
		case 4:
			out.contentType = string(f.bytes)
		case 6:
			out.localID = string(f.bytes)
		case 9:
			out.clonedDriveID = string(f.bytes)
		}
	})
	return out
}

func encodeUploadMetadataAnnotation(uploadMetaProto []byte) []byte {
	var ann []byte
	ann = append(ann, protoEncodeVarintField(1, annotationTypeUploadMetadata)...)
	ann = append(ann, protoEncodeVarintField(2, 0)...)
	ann = append(ann, protoEncodeVarintField(3, 0)...)
	ann = append(ann, protoEncodeBytesField(10, uploadMetaProto)...)
	ann = append(ann, protoEncodeVarintField(20, chipRenderTypeRender)...)
	return ann
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

func (c *Client) downloadAttachment(_ context.Context, attachmentToken string) ([]byte, error) {
	ffi, err := c.ensureFFIClient()
	if err != nil {
		return nil, err
	}
	data, err := ffi.DownloadMedia("attachment", attachmentToken, "", false)
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
	return ffi.DownloadMedia("avatar", "", avatarURL, false)
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

	annotations = append(annotations, encodeUploadMetadataAnnotation(uploadMetaProto))
	return plainText, annotations, nil
}

func extractMessageUploadMetadataList(rawMessageProto []byte) []parsedUploadMetadata {
	var uploads []parsedUploadMetadata
	protoIterFields(rawMessageProto, func(f protoField) {
		if f.num != 11 || f.wireType != 2 { // annotations (repeated Annotation, field 11 of Message)
			return
		}
		var annType uint64
		var uploadBytes []byte
		protoIterFields(f.bytes, func(af protoField) {
			switch af.num {
			case 1:
				if af.wireType == 0 {
					annType = af.varint
				}
			case 10: // upload_metadata (UploadMetadata)
				if af.wireType == 2 {
					uploadBytes = af.bytes
				}
			}
		})
		if (annType == annotationTypeUploadMetadata || len(uploadBytes) > 0) && len(uploadBytes) > 0 {
			up := parseUploadMetadataProto(uploadBytes)
			if up.attachmentToken != "" || up.clonedDriveID != "" {
				uploads = append(uploads, up)
			}
		}
	})
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
		if up.attachmentToken == "" && up.clonedDriveID != "" {
			driveLink := fmt.Sprintf("https://drive.google.com/file/d/%s/view", up.clonedDriveID)
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

		data, err := c.downloadAttachment(ctx, up.attachmentToken)
		if err != nil {
			return nil, fmt.Errorf("download attachment %d: %w", idx, err)
		}
		if len(data) == 0 || len(data) > MaxMediaBytes {
			return nil, fmt.Errorf("invalid attachment %d size (%d bytes)", idx, len(data))
		}

		mimeType := strings.TrimSpace(up.contentType)
		if mimeType == "" {
			mimeType = http.DetectContentType(data)
		}
		filename := strings.TrimSpace(up.contentName)
		if filename == "" {
			filename = fmt.Sprintf("attachment_%04d", idx)
		}

		var mxcURI id.ContentURIString
		if c != nil && c.UserLogin != nil && c.UserLogin.Bridge != nil && c.UserLogin.Bridge.Bot != nil {
			uploadedURI, _, upErr := c.UserLogin.Bridge.Bot.UploadMedia(ctx, roomID, data, filename, mimeType)
			if upErr != nil {
				return nil, fmt.Errorf("store attachment %d in media store: %w", idx, upErr)
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
