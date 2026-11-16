// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

func urlAnnotation(address, title, snippet, domain string, hide bool) *pb.Annotation {
	um := &pb.UrlMetadata{
		Url:     &pb.Url{Url: pb.String(address)},
		Title:   pb.String(title),
		Snippet: pb.String(snippet),
		Domain:  pb.String(domain),
	}
	if hide {
		um.ShouldNotRender = pb.Bool(true)
	}
	return &pb.Annotation{
		Type:     pb.AnnotationType_URL.Enum(),
		Metadata: &pb.Annotation_UrlMetadata{UrlMetadata: um},
	}
}

func TestLinkPreviewsFromMessageCarriesGoogleChatsOwnCard(t *testing.T) {
	msg := &pb.Message{Annotations: []*pb.Annotation{
		urlAnnotation("https://antigravity.google/docs/dynamic-workflows/", "Dynamic workflows", "Run agents in loops", "antigravity.google", false),
	}}
	previews := linkPreviewsFromMessage(msg)
	require.Len(t, previews, 1)
	require.Equal(t, "https://antigravity.google/docs/dynamic-workflows/", previews[0].MatchedURL)
	require.Equal(t, "https://antigravity.google/docs/dynamic-workflows/", previews[0].CanonicalURL)
	require.Equal(t, "Dynamic workflows", previews[0].Title)
	require.Equal(t, "Run agents in loops", previews[0].Description)
	require.Equal(t, "antigravity.google", previews[0].SiteName)
	require.Empty(t, previews[0].ImageURL, "the picture is on Google's servers; carrying it would be a fetch")
}

func TestLinkPreviewsFromMessageSkipsWhatShouldNotBeCards(t *testing.T) {
	msg := &pb.Message{Annotations: []*pb.Annotation{
		urlAnnotation("https://example.org/hidden", "Hidden", "", "example.org", true),
		urlAnnotation("https://example.org/untitled", "  ", "", "example.org", false),
		urlAnnotation("javascript:alert(1)", "Not a web link", "", "", false),
		urlAnnotation("https://example.org/dup", "First", "", "example.org", false),
		urlAnnotation("https://example.org/dup", "Again", "", "example.org", false),
		{Type: pb.AnnotationType_FORMAT_DATA.Enum()},
	}}
	previews := linkPreviewsFromMessage(msg)
	require.Len(t, previews, 1)
	require.Equal(t, "First", previews[0].Title)

	require.Nil(t, linkPreviewsFromMessage(nil))
	require.Nil(t, linkPreviewsFromMessage(&pb.Message{}))
}

func TestLinkPreviewsFromMessageIsCapped(t *testing.T) {
	var anns []*pb.Annotation
	for _, n := range []string{"a", "b", "c", "d", "e"} {
		anns = append(anns, urlAnnotation("https://example.org/"+n, "Page "+n, "", "example.org", false))
	}
	require.Len(t, linkPreviewsFromMessage(&pb.Message{Annotations: anns}), maxInboundLinkPreviews)
}

// The message the app receives carries Google's card: this is the path an inbound message takes.
func TestInboundMessageCarriesGoogleChatsLinkCard(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	spaceGID := pb.SpaceGroupID("space_xyz")

	address := "https://antigravity.google/docs/dynamic-workflows/"
	msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_1", "112233445566778899002", address, 1710000100000000, "", 0, 0)
	msg.Annotations = append(msg.Annotations, urlAnnotation(address, "Dynamic workflows", "Run agents in loops", "antigravity.google", false))

	conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
	require.NoError(t, err)
	require.Len(t, conv.Parts, 1)
	previews := conv.Parts[0].Content.BeeperLinkPreviews
	require.Len(t, previews, 1, "the link arrives with Google's card, so the app can draw it")
	require.Equal(t, "Dynamic workflows", previews[0].Title)
	require.Equal(t, address, previews[0].MatchedURL)

	plain := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_2", "112233445566778899002", "no link", 1710000200000000, "", 0, 0)
	conv, err = client.convertParsedMessage(ctx, parseMessageFromProto(plain))
	require.NoError(t, err)
	require.Empty(t, conv.Parts[0].Content.BeeperLinkPreviews)
}
