// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/gchat/pb"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/host"
)

type funcMediaDownloader func(ctx context.Context, req mediaDownloadRequest) ([]byte, error)

func (f funcMediaDownloader) downloadMedia(ctx context.Context, req mediaDownloadRequest) ([]byte, error) {
	return f(ctx, req)
}

type spyMatrixAPI struct {
	bridgev2.MatrixAPI
	mu          sync.Mutex
	uploadCalls int
	lastRoomID  id.RoomID
	lastCtx     context.Context
	uploadFn    func(ctx context.Context, roomID id.RoomID, data []byte, fileName, mimeType string) (id.ContentURIString, *event.EncryptedFileInfo, error)
}

func (s *spyMatrixAPI) UploadMedia(ctx context.Context, roomID id.RoomID, data []byte, fileName, mimeType string) (id.ContentURIString, *event.EncryptedFileInfo, error) {
	s.mu.Lock()
	s.uploadCalls++
	s.lastRoomID = roomID
	s.lastCtx = ctx
	fn := s.uploadFn
	s.mu.Unlock()
	if fn != nil {
		return fn(ctx, roomID, data, fileName, mimeType)
	}
	return s.MatrixAPI.UploadMedia(ctx, roomID, data, fileName, mimeType)
}

func createTestSpacePortal(t *testing.T, ctx context.Context, h *host.Host, ul *bridgev2.UserLogin, spaceID string) id.RoomID {
	t.Helper()
	portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
		ID:       MakeSpacePortalID(spaceID),
		Receiver: ul.ID,
	})
	require.NoError(t, err)
	require.NotNil(t, portal)
	require.NoError(t, portal.CreateMatrixRoom(ctx, ul, nil))
	require.NotEmpty(t, portal.MXID)
	return portal.MXID
}

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
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, req mediaDownloadRequest) ([]byte, error) {
		downloadCalls++
		downloadedURL = req.URL
		return pngBytes, nil
	})

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
	previews := client.linkPreviewsFromMessage(ctx, id.RoomID("!room:courier.local"), msg)
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
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
		downloadCalls++
		return pngBytes, nil
	})

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
	previews := client.linkPreviewsFromMessage(ctx, id.RoomID("!room:courier.local"), &pb.Message{Annotations: anns})
	require.Len(t, previews, maxInboundLinkPreviews)
	require.Equal(t, maxInboundLinkPreviews, downloadCalls, "cards beyond maxInboundLinkPreviews must not trigger image downloads")
}

// The message the app receives carries Google's card: this is the path an inbound message takes.
func TestInboundMessageCarriesGoogleChatsLinkCard(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	createTestSpacePortal(t, ctx, h, ul, "space_xyz")
	spaceGID := pb.SpaceGroupID("space_xyz")
	pngBytes := solidPNG(10, 8)
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
		return pngBytes, nil
	})

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
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	createTestSpacePortal(t, ctx, h, ul, "space_xyz")
	spaceGID := pb.SpaceGroupID("space_xyz")

	var downloadCalls int
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
		downloadCalls++
		return nil, errors.New("simulated download error")
	})

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
			h, ul, client := setupLoggedInGChatTestEnv(t, nil)
			createTestSpacePortal(t, ctx, h, ul, "space_xyz")
			spaceGID := pb.SpaceGroupID("space_xyz")

			var downloadCalls int
			client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
				downloadCalls++
				return solidPNG(4, 4), nil
			})

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
			h, ul, client := setupLoggedInGChatTestEnv(t, nil)
			createTestSpacePortal(t, ctx, h, ul, "space_xyz")
			spaceGID := pb.SpaceGroupID("space_xyz")

			client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
				return tc.payload, nil
			})

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
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	createTestSpacePortal(t, ctx, h, ul, "space_xyz")
	spaceGID := pb.SpaceGroupID("space_xyz")

	unblock := make(chan struct{})
	t.Cleanup(func() { close(unblock) })

	// Simulate a blocking CGO download that ignores ctx cancellation.
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
		select {
		case <-unblock:
		case <-time.After(1500 * time.Millisecond):
		}
		return solidPNG(4, 4), nil
	})

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

func TestLinkPreviewEmptyRoomIDSkipsUploadAndKeepsCard(t *testing.T) {
	t.Run("portal_missing", func(t *testing.T) {
		ctx := context.Background()
		_, _, client := setupLoggedInGChatTestEnv(t, nil)
		spy := &spyMatrixAPI{MatrixAPI: client.UserLogin.Bridge.Bot}
		client.UserLogin.Bridge.Bot = spy

		var downloadCalls int
		client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
			downloadCalls++
			return solidPNG(8, 8), nil
		})

		spaceGID := pb.SpaceGroupID("space_missing")
		address := "https://example.com/empty-room"
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_empty_room", "112233445566778899002", address, 1710000700000000, "", 0, 0)
		msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
			address,
			"Headline",
			"Summary",
			"example.com",
			"https://lh3.googleusercontent.com/proxy/pic.png",
			"image/png",
			false,
		))

		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		require.NoError(t, err)
		require.Zero(t, downloadCalls)
		require.Zero(t, spy.uploadCalls)
		require.Len(t, conv.Parts, 1)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 1)
		require.Equal(t, "Headline", previews[0].Title)
		require.Equal(t, "Summary", previews[0].Description)
		require.Equal(t, "example.com", previews[0].SiteName)
		require.Empty(t, previews[0].ImageURL)
	})

	t.Run("portal_without_mxid", func(t *testing.T) {
		ctx := context.Background()
		h, ul, client := setupLoggedInGChatTestEnv(t, nil)
		portal, err := h.Bridge.GetPortalByKey(ctx, networkid.PortalKey{
			ID:       MakeSpacePortalID("space_uncreated"),
			Receiver: ul.ID,
		})
		require.NoError(t, err)
		require.Empty(t, portal.MXID)

		spy := &spyMatrixAPI{MatrixAPI: client.UserLogin.Bridge.Bot}
		client.UserLogin.Bridge.Bot = spy

		var downloadCalls int
		client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
			downloadCalls++
			return solidPNG(8, 8), nil
		})

		spaceGID := pb.SpaceGroupID("space_uncreated")
		address := "https://example.com/no-mxid"
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_no_mxid", "112233445566778899002", address, 1710000710000000, "", 0, 0)
		msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
			address,
			"Headline 2",
			"Summary 2",
			"example.com",
			"https://lh3.googleusercontent.com/proxy/pic2.png",
			"image/png",
			false,
		))

		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		require.NoError(t, err)
		require.Zero(t, downloadCalls)
		require.Zero(t, spy.uploadCalls)
		require.Len(t, conv.Parts, 1)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 1)
		require.Equal(t, "Headline 2", previews[0].Title)
		require.Empty(t, previews[0].ImageURL)
	})
}

func TestLinkPreviewLogNeverLeaksURLOrError(t *testing.T) {
	const imageURL = "https://lh3.googleusercontent.com/proxy/secret-path?token=SECRET_PREVIEW_TOKEN_98765"
	cases := []struct {
		name       string
		wantReason string
		setup      func(t *testing.T, client *Client)
	}{
		{
			name:       "download",
			wantReason: "download",
			setup: func(_ *testing.T, client *Client) {
				client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
					return nil, fmt.Errorf("Get %q: connection reset", imageURL)
				})
			},
		},
		{
			name:       "too_big",
			wantReason: "too_big",
			setup: func(_ *testing.T, client *Client) {
				payload := append(solidPNG(8, 8), bytes.Repeat([]byte{0}, maxLinkPreviewImageBytes)...)
				client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
					return payload, nil
				})
			},
		},
		{
			name:       "not_image",
			wantReason: "not_image",
			setup: func(_ *testing.T, client *Client) {
				client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
					return []byte("<html>nope</html>"), nil
				})
			},
		},
		{
			name:       "upload",
			wantReason: "upload",
			setup: func(_ *testing.T, client *Client) {
				client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
					return solidPNG(8, 8), nil
				})
				client.UserLogin.Bridge.Bot = &spyMatrixAPI{
					MatrixAPI: client.UserLogin.Bridge.Bot,
					uploadFn: func(_ context.Context, _ id.RoomID, _ []byte, _, _ string) (id.ContentURIString, *event.EncryptedFileInfo, error) {
						return "", nil, fmt.Errorf("upload failed for %s", imageURL)
					},
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var logBuf bytes.Buffer
			ctx := zerolog.New(&logBuf).WithContext(context.Background())
			h, ul, client := setupLoggedInGChatTestEnv(t, nil)
			createTestSpacePortal(t, ctx, h, ul, "space_xyz")
			tc.setup(t, client)

			spaceGID := pb.SpaceGroupID("space_xyz")
			address := "https://example.com/" + tc.name
			msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_log_"+tc.name, "112233445566778899002", address, 1710000800000000, "", 0, 0)
			msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
				address,
				"Title",
				"Snippet",
				"example.com",
				imageURL,
				"image/png",
				false,
			))

			conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
			require.NoError(t, err)
			require.Len(t, conv.Parts, 1)
			require.Len(t, conv.Parts[0].Content.BeeperLinkPreviews, 1)
			require.Empty(t, conv.Parts[0].Content.BeeperLinkPreviews[0].ImageURL)

			logged := logBuf.String()
			require.NotContains(t, logged, "SECRET_PREVIEW_TOKEN_98765")
			require.NotContains(t, logged, "/proxy/secret-path")
			require.NotContains(t, logged, "connection reset")
			require.NotContains(t, logged, "upload failed")
			require.Contains(t, logged, `"host":"lh3.googleusercontent.com"`)
			require.Contains(t, logged, fmt.Sprintf(`"reason":%q`, tc.wantReason))
		})
	}
}

func TestLinkPreviewSharedDeadlineAcrossCardsAndUpload(t *testing.T) {
	t.Run("three_slow_pictures_share_one_deadline", func(t *testing.T) {
		prevTimeout := linkPreviewImageTimeout
		linkPreviewImageTimeout = 150 * time.Millisecond
		t.Cleanup(func() { linkPreviewImageTimeout = prevTimeout })

		ctx := context.Background()
		h, ul, client := setupLoggedInGChatTestEnv(t, nil)
		createTestSpacePortal(t, ctx, h, ul, "space_xyz")

		var downloadCalls int
		client.mediaFFI = funcMediaDownloader(func(dlCtx context.Context, _ mediaDownloadRequest) ([]byte, error) {
			downloadCalls++
			<-dlCtx.Done()
			return nil, dlCtx.Err()
		})

		spaceGID := pb.SpaceGroupID("space_xyz")
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_3slow", "112233445566778899002", "three slow links", 1710000900000000, "", 0, 0)
		for _, suffix := range []string{"1", "2", "3"} {
			addr := "https://example.com/slow/" + suffix
			msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
				addr,
				"Slow "+suffix,
				"Snippet",
				"example.com",
				"https://lh3.googleusercontent.com/proxy/slow-"+suffix+".png",
				"image/png",
				false,
			))
		}

		start := time.Now()
		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		elapsed := time.Since(start)

		require.NoError(t, err)
		require.Less(t, elapsed, 2*linkPreviewImageTimeout, "3 slow pictures must share one deadline")
		require.Equal(t, 1, downloadCalls, "once shared deadline expires, remaining cards must not start downloads")
		require.Len(t, conv.Parts, 1)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 3)
		for _, p := range previews {
			require.Empty(t, p.ImageURL)
		}
	})

	t.Run("upload_receives_shared_deadline", func(t *testing.T) {
		prevTimeout := linkPreviewImageTimeout
		linkPreviewImageTimeout = 150 * time.Millisecond
		t.Cleanup(func() { linkPreviewImageTimeout = prevTimeout })

		var logBuf bytes.Buffer
		ctx := zerolog.New(&logBuf).WithContext(context.Background())
		h, ul, client := setupLoggedInGChatTestEnv(t, nil)
		createTestSpacePortal(t, ctx, h, ul, "space_xyz")

		client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
			return solidPNG(8, 8), nil
		})

		var hasDeadline bool
		spy := &spyMatrixAPI{
			MatrixAPI: client.UserLogin.Bridge.Bot,
			uploadFn: func(uploadCtx context.Context, _ id.RoomID, _ []byte, _, _ string) (id.ContentURIString, *event.EncryptedFileInfo, error) {
				_, hasDeadline = uploadCtx.Deadline()
				select {
				case <-uploadCtx.Done():
					return "", nil, uploadCtx.Err()
				case <-time.After(500 * time.Millisecond):
					return "", nil, errors.New("upload context had no deadline")
				}
			},
		}
		client.UserLogin.Bridge.Bot = spy

		spaceGID := pb.SpaceGroupID("space_xyz")
		address := "https://example.com/slow-upload"
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_slow_upload", "112233445566778899002", address, 1710000910000000, "", 0, 0)
		msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
			address,
			"Slow upload",
			"Snippet",
			"example.com",
			"https://lh3.googleusercontent.com/proxy/slow-upload.png",
			"image/png",
			false,
		))

		start := time.Now()
		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		elapsed := time.Since(start)

		require.NoError(t, err)
		require.True(t, hasDeadline, "UploadMedia must receive the shared deadline context")
		require.Less(t, elapsed, 2*linkPreviewImageTimeout)
		require.Len(t, conv.Parts, 1)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 1)
		require.Empty(t, previews[0].ImageURL)
		require.Contains(t, logBuf.String(), `"reason":"upload"`)
	})
}

func TestLinkPreviewDeduplicatesImageURLWithinMessage(t *testing.T) {
	t.Run("reuses_uploaded_image", func(t *testing.T) {
		ctx := context.Background()
		h, ul, client := setupLoggedInGChatTestEnv(t, nil)
		createTestSpacePortal(t, ctx, h, ul, "space_xyz")
		spy := &spyMatrixAPI{MatrixAPI: client.UserLogin.Bridge.Bot}
		client.UserLogin.Bridge.Bot = spy

		var downloadCalls int
		pngBytes := solidPNG(12, 10)
		client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
			downloadCalls++
			return pngBytes, nil
		})

		const sharedImage = "https://lh3.googleusercontent.com/proxy/shared.png"
		spaceGID := pb.SpaceGroupID("space_xyz")
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_dedup_ok", "112233445566778899002", "two cards", 1710000920000000, "", 0, 0)
		msg.Annotations = append(
			msg.Annotations,
			urlAnnotationWithImage("https://example.com/a", "Card A", "Desc A", "example.com", sharedImage, "image/png", false),
			urlAnnotationWithImage("https://example.com/b", "Card B", "Desc B", "example.com", sharedImage, "image/png", false),
		)

		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		require.NoError(t, err)
		require.Equal(t, 1, downloadCalls)
		require.Equal(t, 1, spy.uploadCalls)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 2)
		require.True(t, strings.HasPrefix(string(previews[0].ImageURL), "mxc://"))
		require.Equal(t, previews[0].ImageURL, previews[1].ImageURL)
		require.Equal(t, previews[0].ImageWidth, previews[1].ImageWidth)
		require.Equal(t, previews[0].ImageHeight, previews[1].ImageHeight)
		require.Equal(t, previews[0].ImageSize, previews[1].ImageSize)
		require.Equal(t, previews[0].ImageBlurhash, previews[1].ImageBlurhash)
		require.Equal(t, previews[0].ImageType, previews[1].ImageType)
	})

	t.Run("does_not_retry_failed_image", func(t *testing.T) {
		ctx := context.Background()
		h, ul, client := setupLoggedInGChatTestEnv(t, nil)
		createTestSpacePortal(t, ctx, h, ul, "space_xyz")
		spy := &spyMatrixAPI{MatrixAPI: client.UserLogin.Bridge.Bot}
		client.UserLogin.Bridge.Bot = spy

		var downloadCalls int
		client.mediaFFI = funcMediaDownloader(func(_ context.Context, _ mediaDownloadRequest) ([]byte, error) {
			downloadCalls++
			return nil, errors.New("boom")
		})

		const sharedImage = "https://lh3.googleusercontent.com/proxy/fail-shared.png"
		spaceGID := pb.SpaceGroupID("space_xyz")
		msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_dedup_fail", "112233445566778899002", "two cards", 1710000930000000, "", 0, 0)
		msg.Annotations = append(
			msg.Annotations,
			urlAnnotationWithImage("https://example.com/a", "Card A", "Desc A", "example.com", sharedImage, "image/png", false),
			urlAnnotationWithImage("https://example.com/b", "Card B", "Desc B", "example.com", sharedImage, "image/png", false),
		)

		conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
		require.NoError(t, err)
		require.Equal(t, 1, downloadCalls)
		require.Equal(t, 0, spy.uploadCalls)
		previews := conv.Parts[0].Content.BeeperLinkPreviews
		require.Len(t, previews, 2)
		require.Empty(t, previews[0].ImageURL)
		require.Empty(t, previews[1].ImageURL)
	})
}

func TestLinkPreviewProductionPathCallsFFIExternalEnabled(t *testing.T) {
	ctx := context.Background()
	h, ul, client := setupLoggedInGChatTestEnv(t, nil)
	wantRoomID := createTestSpacePortal(t, ctx, h, ul, "space_xyz")
	spy := &spyMatrixAPI{MatrixAPI: client.UserLogin.Bridge.Bot}
	client.UserLogin.Bridge.Bot = spy

	const wantImageURL = "https://lh3.googleusercontent.com/proxy/prod-path.png"
	pngBytes := solidPNG(14, 10)
	var calls int
	var gotReq mediaDownloadRequest
	client.mediaFFI = funcMediaDownloader(func(_ context.Context, req mediaDownloadRequest) ([]byte, error) {
		calls++
		gotReq = req
		return pngBytes, nil
	})

	spaceGID := pb.SpaceGroupID("space_xyz")
	address := "https://example.com/prod-path"
	msg := buildSyntheticMessageProto(spaceGID, "topic_1", "msg_prod", "112233445566778899002", address, 1710000940000000, "", 0, 0)
	msg.Annotations = append(msg.Annotations, urlAnnotationWithImage(
		address,
		"Prod path",
		"Snippet",
		"example.com",
		wantImageURL,
		"image/png",
		false,
	))

	conv, err := client.convertParsedMessage(ctx, parseMessageFromProto(msg))
	require.NoError(t, err)
	require.Equal(t, 1, calls)
	require.Equal(t, "external", gotReq.Kind)
	require.True(t, gotReq.ExternalEnabled)
	require.Equal(t, wantImageURL, gotReq.URL)
	require.Equal(t, maxLinkPreviewImageBytes, gotReq.MaxBytes)
	require.Greater(t, gotReq.TimeoutMS, int64(0))
	require.LessOrEqual(t, gotReq.TimeoutMS, linkPreviewImageTimeout.Milliseconds())
	require.Equal(t, 1, spy.uploadCalls)
	require.Equal(t, wantRoomID, spy.lastRoomID)
	require.True(t, strings.HasPrefix(string(conv.Parts[0].Content.BeeperLinkPreviews[0].ImageURL), "mxc://"))
}

func TestLinkPreviewReleasesMediaSlotAfterHungDownload(t *testing.T) {
	prevTimeout := linkPreviewImageTimeout
	linkPreviewImageTimeout = 150 * time.Millisecond
	t.Cleanup(func() { linkPreviewImageTimeout = prevTimeout })

	ctx := context.Background()
	_, _, client := setupLoggedInGChatTestEnv(t, nil)
	client.mu.Lock()
	client.mediaSem = make(chan struct{}, 1)
	client.mu.Unlock()

	okBytes := solidPNG(8, 8)
	releaseHung := make(chan struct{})
	var releaseOnce sync.Once
	closeHung := func() { releaseOnce.Do(func() { close(releaseHung) }) }

	imgSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/hung.png":
			w.Header().Set("Content-Type", "image/png")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte{0x89, 'P', 'N', 'G'})
			if fl, ok := w.(http.Flusher); ok {
				fl.Flush()
			}
			select {
			case <-releaseHung:
			case <-r.Context().Done():
			}
		case "/ok.png":
			w.Header().Set("Content-Type", "image/png")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(okBytes)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(imgSrv.Close)
	t.Cleanup(closeHung)

	_, err := client.downloadLinkPreviewImage(ctx, imgSrv.URL+"/hung.png")
	require.Error(t, err, "hung download must fail after timeout")

	got, err := client.downloadLinkPreviewImage(ctx, imgSrv.URL+"/ok.png")
	require.NoError(t, err, "media slot must be released so the following download succeeds")
	require.Equal(t, okBytes, got)
}
