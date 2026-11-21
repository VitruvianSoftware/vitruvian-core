// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"bytes"
	"context"
	"mime"
	"net/http"
	"net/url"
	"strings"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
)

// maxInboundLinkPreviews caps how many link cards one message carries.
const maxInboundLinkPreviews = 3

// linkPreviewsFromMessage turns the link cards Google Chat's own servers attached to a message (its URL
// annotations' url_metadata: title, snippet, domain, and picture) into the Matrix link previews the app draws as a card.
//
// Google fetched the page, not this Mac, so nothing here is a request to the linked site. A link Google had no
// title for, or told clients not to render, gets none. When url_metadata carries an https:// image_url, the picture
// is fetched from Google's servers through the Google Chat client (never from the linked site), bounded by the media
// slot, timeout, and 2 MiB limit, verified as a real image, and stored in the local media store as an mxc:// URI. Any
// failure leaves the card without a picture and never fails or stalls message delivery.
func (c *Client) linkPreviewsFromMessage(ctx context.Context, roomID id.RoomID, msg *pb.Message) []*event.BeeperLinkPreview {
	if msg == nil {
		return nil
	}
	var previews []*event.BeeperLinkPreview
	seen := map[string]bool{}
	for _, ann := range msg.GetAnnotations() {
		um := ann.GetUrlMetadata()
		if um == nil || um.GetShouldNotRender() {
			continue
		}
		title := strings.TrimSpace(um.GetTitle())
		address := strings.TrimSpace(um.GetUrl().GetUrl())
		if title == "" || address == "" || seen[address] {
			continue
		}
		lower := strings.ToLower(address)
		if !strings.HasPrefix(lower, "https://") && !strings.HasPrefix(lower, "http://") {
			continue
		}
		seen[address] = true
		p := &event.BeeperLinkPreview{
			MatchedURL: address,
			LinkPreview: event.LinkPreview{
				CanonicalURL: address,
				Title:        title,
				Description:  strings.TrimSpace(um.GetSnippet()),
				SiteName:     strings.TrimSpace(um.GetDomain()),
			},
		}
		if c != nil {
			c.populateLinkPreviewImage(ctx, roomID, um, p)
		}
		previews = append(previews, p)
		if len(previews) == maxInboundLinkPreviews {
			break
		}
	}
	return previews
}

func (c *Client) populateLinkPreviewImage(ctx context.Context, roomID id.RoomID, um *pb.UrlMetadata, preview *event.BeeperLinkPreview) {
	if c == nil || um == nil || preview == nil {
		return
	}
	imageURL := strings.TrimSpace(um.GetImageUrl())
	if !isHTTPSImageURL(imageURL) {
		return
	}
	if c.UserLogin == nil || c.UserLogin.Bridge == nil || c.UserLogin.Bridge.Bot == nil {
		return
	}
	data, err := c.downloadLinkPreviewImage(ctx, imageURL)
	if err != nil || len(data) == 0 || len(data) > maxLinkPreviewImageBytes {
		return
	}
	meta, err := media.InspectImage(bytes.NewReader(data))
	if err != nil {
		return
	}
	mimeType := previewImageMIMEType(data, um.GetMimeType())
	mxcURI, _, err := c.UserLogin.Bridge.Bot.UploadMedia(ctx, roomID, data, "link-preview", mimeType)
	if err != nil || mxcURI == "" {
		return
	}
	preview.ImageURL = mxcURI
	preview.ImageSize = event.IntOrString(len(data))
	preview.ImageWidth = event.IntOrString(meta.Width)
	preview.ImageHeight = event.IntOrString(meta.Height)
	preview.ImageBlurhash = meta.BlurHash
	if mimeType != "" {
		preview.ImageType = mimeType
	}
}

func isHTTPSImageURL(rawURL string) bool {
	u, err := url.Parse(strings.TrimSpace(rawURL))
	return err == nil && strings.EqualFold(u.Scheme, "https") && u.Hostname() != "" && u.User == nil
}

func previewImageMIMEType(data []byte, metaMIME string) string {
	if ct := baseMIMEType(http.DetectContentType(data)); strings.HasPrefix(ct, "image/") {
		return ct
	}
	if ct := baseMIMEType(metaMIME); strings.HasPrefix(ct, "image/") {
		return ct
	}
	return ""
}

func baseMIMEType(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return ""
	}
	base, _, err := mime.ParseMediaType(v)
	if err != nil {
		return ""
	}
	return strings.ToLower(base)
}

func messageHasLinkPreviewImage(msg *pb.Message) bool {
	if msg == nil {
		return false
	}
	for _, ann := range msg.GetAnnotations() {
		um := ann.GetUrlMetadata()
		if um != nil && !um.GetShouldNotRender() && strings.TrimSpace(um.GetImageUrl()) != "" {
			return true
		}
	}
	return false
}
