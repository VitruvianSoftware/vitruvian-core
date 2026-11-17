// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"strings"

	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

// maxInboundLinkPreviews caps how many link cards one message carries.
const maxInboundLinkPreviews = 3

// linkPreviewsFromMessage turns the link cards Google Chat's own servers attached to a message (its URL
// annotations' url_metadata: title, snippet, domain) into the Matrix link previews the app draws as a card.
//
// Google fetched the page, not this Mac, so nothing here is a request to the linked site. A link Google had no
// title for, or told clients not to render, gets none. The picture is not carried: it lives on Google's servers and
// would be a fetch.
func linkPreviewsFromMessage(msg *pb.Message) []*event.BeeperLinkPreview {
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
		previews = append(previews, &event.BeeperLinkPreview{
			MatchedURL: address,
			LinkPreview: event.LinkPreview{
				CanonicalURL: address,
				Title:        title,
				Description:  strings.TrimSpace(um.GetSnippet()),
				SiteName:     strings.TrimSpace(um.GetDomain()),
			},
		})
		if len(previews) == maxInboundLinkPreviews {
			break
		}
	}
	return previews
}
