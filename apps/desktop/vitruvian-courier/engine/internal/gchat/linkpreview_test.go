// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/color"
	"image/png"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
)

func solidPNG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: 40, G: 120, B: 200, A: 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func urlAnnotationWithImage(address, title, snippet, domain, imageURL, mimeType string, hide bool) *pb.Annotation {
	um := &pb.UrlMetadata{
		Url:     &pb.Url{Url: pb.String(address)},
		Title:   pb.String(title),
		Snippet: pb.String(snippet),
		Domain:  pb.String(domain),
	}
	if imageURL != "" {
		um.ImageUrl = pb.String(imageURL)
	}
	if mimeType != "" {
		um.MimeType = pb.String(mimeType)
	}
	if hide {
		um.ShouldNotRender = pb.Bool(true)
	}
	return &pb.Annotation{
		Type:     pb.AnnotationType_URL.Enum(),
		Metadata: &pb.Annotation_UrlMetadata{UrlMetadata: um},
	}
}

func urlAnnotation(address, title, snippet, domain string, hide bool) *pb.Annotation {
	return urlAnnotationWithImage(address, title, snippet, domain, "", "", hide)
}

func TestLinkPreviewsFromMessageCarriesGoogleChatsOwnCard(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	pngBytes := solidPNG(16, 12)
	const wantImageURL = "https://lh3.googleusercontent.com/proxy/usatoday-thumb"

	var downloadCalls int
	var downloadedURL string
	client.linkPreviewImageDownloader = func(_ context.Context, imageURL string) ([]byte, error) {
		downloadCalls++
		downloadedURL = imageURL
		return pngBytes, nil
	}

	msg := &pb.Message{Annotations: []*pb.Annotation{
		urlAnnotationWithImage(
			"https://antigravity.google/docs/dynamic-workflows/",
			"Dynamic workflows",
			"Run agents in loops",
			"antigravity.google",
			wantImageURL,
			"image/png",
			false,
		),
	}}
	previews := client.linkPreviewsFromMessage(ctx, "", msg)
	require.Len(t, previews, 1)
	require.Equal(t, 1, downloadCalls)
	require.Equal(t, wantImageURL, downloadedURL)
	require.Equal(t, "https://antigravity.google/docs/dynamic-workflows/", previews[0].MatchedURL)
	require.Equal(t, "https://antigravity.google/docs/dynamic-workflows/", previews[0].CanonicalURL)
	require.Equal(t, "Dynamic workflows", previews[0].Title)
	require.Equal(t, "Run agents in loops", previews[0].Description)
	require.Equal(t, "antigravity.google", previews[0].SiteName)
	require.True(t, strings.HasPrefix(string(previews[0].ImageURL), "mxc://"), "preview picture should be stored in the local media store")
	require.Equal(t, event.IntOrString(16), previews[0].ImageWidth)
	require.Equal(t, event.IntOrString(12), previews[0].ImageHeight)
	require.Equal(t, event.IntOrString(len(pngBytes)), previews[0].ImageSize)
	require.NotEmpty(t, previews[0].ImageBlurhash)
	require.Equal(t, "image/png", previews[0].ImageType)

	stored, err := client.UserLogin.Bridge.Bot.DownloadMedia(ctx, previews[0].ImageURL, nil)
	require.NoError(t, err)
	require.Equal(t, pngBytes, stored)
}

func TestLinkPreviewsFromMessageSkipsWhatShouldNotBeCards(t *testing.T) {
	ctx := context.Background()
	msg := &pb.Message{Annotations: []*pb.Annotation{
		urlAnnotation("https://example.org/hidden", "Hidden", "", "example.org", true),
		urlAnnotation("https://example.org/untitled", "  ", "", "example.org", false),
		urlAnnotation("javascript:alert(1)", "Not a web link", "", "", false),
		urlAnnotation("https://example.org/dup", "First", "", "example.org", false),
		urlAnnotation("https://example.org/dup", "Again", "", "example.org", false),
		{Type: pb.AnnotationType_FORMAT_DATA.Enum()},
	}}
	previews := (*Client)(nil).linkPreviewsFromMessage(ctx, "", msg)
	require.Len(t, previews, 1)
	require.Equal(t, "First", previews[0].Title)

	require.Nil(t, (*Client)(nil).linkPreviewsFromMessage(ctx, "", nil))
	require.Nil(t, (*Client)(nil).linkPreviewsFromMessage(ctx, "", &pb.Message{}))
}

func TestLinkPreviewsFromMessageIsCapped(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	pngBytes := solidPNG(8, 6)
	var downloadCalls int
	client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
		downloadCalls++
		return pngBytes, nil
	}

	var anns []*pb.Annotation
	for _, n := range []string{"a", "b", "c", "d", "e"} {
		anns = append(anns, urlAnnotationWithImage(
			"https://example.org/"+n,
			"Page "+n,
			"",
			"example.org",
			"https://lh3.googleusercontent.com/proxy/"+n+".png",
			"image/png",
			false,
		))
	}
	previews := client.linkPreviewsFromMessage(ctx, "", &pb.Message{Annotations: anns})
	require.Len(t, previews, maxInboundLinkPreviews)
	require.Equal(t, maxInboundLinkPreviews, downloadCalls, "cards beyond maxInboundLinkPreviews must not trigger image downloads")
}

// The message the app receives carries Google's card: this is the path an inbound message takes.
func TestInboundMessageCarriesGoogleChatsLinkCard(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	spaceGID := pb.SpaceGroupID("space_xyz")
	pngBytes := solidPNG(10, 8)
	client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
		return pngBytes, nil
	}

	address := "https://antigravity.google/docs/dynamic-workflows/"
	msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_1", "112233445566778899002", address, 1710000100000000, "", 0, 0)
	msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
		address,
		"Dynamic workflows",
		"Run agents in loops",
		"antigravity.google",
		"https://lh3.googleusercontent.com/proxy/dynamic-workflows.png",
		"image/png",
		false,
	))

	conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
	require.NoError(t, err)
	require.Len(t, conv.Parts, 1)
	previews := conv.Parts[0].Content.BeeperLinkPreviews
	require.Len(t, previews, 1, "the link arrives with Google's card, so the app can draw it")
	require.Equal(t, "Dynamic workflows", previews[0].Title)
	require.Equal(t, address, previews[0].MatchedURL)
	require.True(t, strings.HasPrefix(string(previews[0].ImageURL), "mxc://"))
	require.Equal(t, event.IntOrString(10), previews[0].ImageWidth)
	require.Equal(t, event.IntOrString(8), previews[0].ImageHeight)
	require.Equal(t, event.IntOrString(len(pngBytes)), previews[0].ImageSize)
	require.NotEmpty(t, previews[0].ImageBlurhash)
	require.Equal(t, "image/png", previews[0].ImageType)

	plain := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_2", "112233445566778899002", "no link", 1710000200000000, "", 0, 0)
	conv, err = client.convertParsedMessage(ctx, parseMessageFromProto(plain))
	require.NoError(t, err)
	require.Empty(t, conv.Parts[0].Content.BeeperLinkPreviews)
}

func TestLinkPreviewDownloadFailureKeepsCardWithoutImage(t *testing.T) {
	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	spaceGID := pb.SpaceGroupID("space_xyz")

	var downloadCalls int
	client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
		downloadCalls++
		return nil, errors.New("simulated download error")
	}

	address := "https://www.usatoday.com/story/news/example/"
	msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_err", "112233445566778899002", address, 1710000300000000, "", 0, 0)
	msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
		address,
		"Headline",
		"Summary",
		"usatoday.com",
		"https://lh3.googleusercontent.com/proxy/usatoday.jpg",
		"image/jpeg",
		false,
	))

	conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
	require.NoError(t, err)
	require.Equal(t, 1, downloadCalls)
	require.Len(t, conv.Parts, 1)
	previews := conv.Parts[0].Content.BeeperLinkPreviews
	require.Len(t, previews, 1)
	require.Equal(t, "Headline", previews[0].Title)
	require.Equal(t, "Summary", previews[0].Description)
	require.Equal(t, "usatoday.com", previews[0].SiteName)
	require.Empty(t, previews[0].ImageURL)
	require.Zero(t, previews[0].ImageSize)
	require.Zero(t, previews[0].ImageWidth)
	require.Zero(t, previews[0].ImageHeight)
	require.Empty(t, previews[0].ImageBlurhash)
	require.Empty(t, previews[0].ImageType)
}

func TestLinkPreviewSkipsNonHTTPSAndEmptyImageURL(t *testing.T) {
	cases := []struct {
		name     string
		imageURL string
	}{
		{name: "empty", imageURL: ""},
		{name: "whitespace", imageURL: "   "},
		{name: "http", imageURL: "http://lh3.googleusercontent.com/pic.png"},
		{name: "javascript", imageURL: "javascript:alert(1)"},
		{name: "userinfo", imageURL: "https://user:pass@lh3.googleusercontent.com/pic.png"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			_, _, client := setupLoggedInGChatTestEnv(t, nil)
			spaceGID := pb.SpaceGroupID("space_xyz")

			var downloadCalls int
			client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
				downloadCalls++
				return solidPNG(4, 4), nil
			}

			address := "https://example.com/" + tc.name
			msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_"+tc.name, "112233445566778899002", address, 1710000400000000, "", 0, 0)
			msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
				address,
				"Title "+tc.name,
				"Snippet",
				"example.com",
				tc.imageURL,
				"image/png",
				false,
			))

			conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
			require.NoError(t, err)
			require.Zero(t, downloadCalls, "non-https or empty image_url must never call downloader")
			require.Len(t, conv.Parts, 1)
			previews := conv.Parts[0].Content.BeeperLinkPreviews
			require.Len(t, previews, 1)
			require.Empty(t, previews[0].ImageURL)
		})
	}
}

func TestLinkPreviewRejectsOversizedAndNonImage(t *testing.T) {
	cases := []struct {
		name    string
		payload []byte
	}{
		{
			name:    "over_2mib",
			payload: append(solidPNG(16, 12), bytes.Repeat([]byte{0}, maxLinkPreviewImageBytes)...),
		},
		{
			name:    "not_an_image",
			payload: []byte("<html><body>402 Payment Required</body></html>"),
		},
		{
			name:    "empty_body",
			payload: nil,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			_, _, client := setupLoggedInGChatTestEnv(t, nil)
			spaceGID := pb.SpaceGroupID("space_xyz")

			client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
				return tc.payload, nil
			}

			address := "https://example.com/" + tc.name
			msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_"+tc.name, "112233445566778899002", address, 1710000500000000, "", 0, 0)
			msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
				address,
				"Title "+tc.name,
				"Snippet",
				"example.com",
				"https://lh3.googleusercontent.com/proxy/"+tc.name+".png",
				"image/png",
				false,
			))

			conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
			require.NoError(t, err)
			require.Len(t, conv.Parts, 1)
			previews := conv.Parts[0].Content.BeeperLinkPreviews
			require.Len(t, previews, 1)
			require.Empty(t, previews[0].ImageURL)
			require.Zero(t, previews[0].ImageSize)
			require.Zero(t, previews[0].ImageWidth)
			require.Zero(t, previews[0].ImageHeight)
		})
	}
}

func TestLinkPreviewTimeoutDoesNotStallConversion(t *testing.T) {
	prevTimeout := linkPreviewImageTimeout
	linkPreviewImageTimeout = 50 * time.Millisecond
	t.Cleanup(func() { linkPreviewImageTimeout = prevTimeout })

	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	spaceGID := pb.SpaceGroupID("space_xyz")

	unblock := make(chan struct{})
	t.Cleanup(func() { close(unblock) })

	// Simulate a blocking CGO download that ignores ctx cancellation.
	client.linkPreviewImageDownloader = func(_ context.Context, _ string) ([]byte, error) {
		select {
		case <-unblock:
		case <-time.After(1500 * time.Millisecond):
		}
		return solidPNG(4, 4), nil
	}

	address := "https://example.com/slow"
	msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_slow", "112233445566778899002", address, 1710000600000000, "", 0, 0)
	msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
		address,
		"Slow article",
		"Snippet",
		"example.com",
		"https://lh3.googleusercontent.com/proxy/slow.png",
		"image/png",
		false,
	))

	start := time.Now()
	conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
	elapsed := time.Since(start)

	require.NoError(t, err)
	require.Less(t, elapsed, time.Second, "message conversion must not wait past linkPreviewImageTimeout")
	require.Len(t, conv.Parts, 1)
	previews := conv.Parts[0].Content.BeeperLinkPreviews
	require.Len(t, previews, 1)
	require.Empty(t, previews[0].ImageURL)
}
