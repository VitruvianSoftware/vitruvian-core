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

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
)

// maxInboundLinkPreviews caps how many link cards one message carries.
const maxInboundLinkPreviews = 3

type uploadedPreviewImage struct {
	uri      id.ContentURIString
	size     int
	width    int
	height   int
	blurHash string
	mimeType string
}

func (u *uploadedPreviewImage) applyTo(preview *event.BeeperLinkPreview) {
	preview.ImageURL = u.uri
	preview.ImageSize = event.IntOrString(u.size)
	preview.ImageWidth = event.IntOrString(u.width)
	preview.ImageHeight = event.IntOrString(u.height)
	preview.ImageBlurhash = u.blurHash
	if u.mimeType != "" {
		preview.ImageType = u.mimeType
	}
}

// logLinkPreviewImageSkipped logs only the image host and a fixed reason word
// ("download", "too_big", "not_image", or "upload") — never the URL or error text.
func logLinkPreviewImageSkipped(ctx context.Context, imageURL, reason string) {
	host := ""
	if u, err := url.Parse(imageURL); err == nil {
		host = u.Hostname()
	}
	zerolog.Ctx(ctx).Info().Str("host", host).Str("reason", reason).
		Msg("Google Chat: link card picture not carried")
}

// linkPreviewsFromMessage turns the link cards Google Chat's own servers attached to a message (its URL
// annotations' url_metadata: title, snippet, domain, and picture) into the Matrix link previews the app draws as a card.
//
// Google fetched the page, not this Mac, so nothing here is a request to the linked site. A link Google had no
// title for, or told clients not to render, gets none. When url_metadata carries an https:// image_url, the picture
// is fetched from Google's servers through the Google Chat client (never from the linked site), bounded by the media
// slot, a single shared timeout across all pictures and upload for the message, and a 2 MiB limit, verified as a real
// image, and stored in the local media store as an mxc:// URI. Any failure, or missing portal room ID, leaves the card
// without a picture and never fails or stalls message delivery.
func (c *Client) linkPreviewsFromMessage(ctx context.Context, roomID id.RoomID, msg *pb.Message) []*event.BeeperLinkPreview {
	if msg == nil {
		return nil
	}
	var (
		previews []*event.BeeperLinkPreview
		seen     = map[string]bool{}
		imgCtx   context.Context
		imgCache map[string]*uploadedPreviewImage
	)
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
		if c != nil && roomID != "" && isHTTPSImageURL(um.GetImageUrl()) {
			if imgCtx == nil {
				var imgCancel context.CancelFunc
				imgCtx, imgCancel = context.WithTimeout(ctx, linkPreviewImageTimeout)
				defer imgCancel()
				imgCache = make(map[string]*uploadedPreviewImage)
			}
			c.populateLinkPreviewImage(imgCtx, roomID, um, p, imgCache)
		}
		previews = append(previews, p)
		if len(previews) == maxInboundLinkPreviews {
			break
		}
	}
	return previews
}

func (c *Client) populateLinkPreviewImage(
	ctx context.Context,
	roomID id.RoomID,
	um *pb.UrlMetadata,
	preview *event.BeeperLinkPreview,
	imgCache map[string]*uploadedPreviewImage,
) {
	if c == nil || roomID == "" || um == nil || preview == nil {
		return
	}
	imageURL := strings.TrimSpace(um.GetImageUrl())
	if !isHTTPSImageURL(imageURL) {
		return
	}
	if c.UserLogin == nil || c.UserLogin.Bridge == nil || c.UserLogin.Bridge.Bot == nil {
		return
	}
	if imgCache != nil {
		if cached, seen := imgCache[imageURL]; seen {
			if cached != nil {
				cached.applyTo(preview)
			}
			return
		}
		// Mark attempted so a failed URL is not retried for another card in the same message.
		imgCache[imageURL] = nil
	}
	data, err := c.downloadLinkPreviewImage(ctx, imageURL)
	if err != nil {
		if isLinkPreviewTooBigError(err) {
			logLinkPreviewImageSkipped(ctx, imageURL, "too_big")
		} else {
			logLinkPreviewImageSkipped(ctx, imageURL, "download")
		}
		return
	}
	if len(data) > maxLinkPreviewImageBytes {
		logLinkPreviewImageSkipped(ctx, imageURL, "too_big")
		return
	}
	if len(data) == 0 {
		logLinkPreviewImageSkipped(ctx, imageURL, "download")
		return
	}
	meta, err := media.InspectImage(bytes.NewReader(data))
	if err != nil {
		logLinkPreviewImageSkipped(ctx, imageURL, "not_image")
		return
	}
	if ctx.Err() != nil {
		logLinkPreviewImageSkipped(ctx, imageURL, "download")
		return
	}
	mimeType := previewImageMIMEType(data, um.GetMimeType())
	mxcURI, _, err := c.UserLogin.Bridge.Bot.UploadMedia(ctx, roomID, data, "link-preview", mimeType)
	if err != nil || mxcURI == "" {
		logLinkPreviewImageSkipped(ctx, imageURL, "upload")
		return
	}
	uploaded := &uploadedPreviewImage{
		uri:      mxcURI,
		size:     len(data),
		width:    meta.Width,
		height:   meta.Height,
		blurHash: meta.BlurHash,
		mimeType: mimeType,
	}
	if imgCache != nil {
		imgCache[imageURL] = uploaded
	}
	uploaded.applyTo(preview)
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
