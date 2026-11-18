// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/jpeg"
	"testing"

	"github.com/stretchr/testify/require"
	"go.mau.fi/mautrix-whatsapp/pkg/msgconv"
	"go.mau.fi/mautrix-whatsapp/pkg/waid"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/types"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/event"
)

func tinyJPEG(t *testing.T) []byte {
	img := image.NewRGBA(image.Rect(0, 0, 4, 3))
	img.Set(1, 1, color.RGBA{R: 200, A: 255})
	var buf bytes.Buffer
	require.NoError(t, jpeg.Encode(&buf, img, nil))
	return buf.Bytes()
}

// convertWhatsAppText runs the real mautrix-whatsapp converter on msg with this connector's ghost intent, stores the
// result the way bridgev2 does, and reads it back.
func convertWhatsAppText(t *testing.T, c *Connector, msg *waE2E.Message) *event.MessageEventContent {
	t.Helper()
	ctx := context.Background()
	roomID, err := c.BotIntent().CreateRoom(ctx, &mautrix.ReqCreateRoom{})
	require.NoError(t, err)
	portal := &bridgev2.Portal{Portal: &database.Portal{MXID: roomID, Metadata: &waid.PortalMetadata{}}}
	intent := c.GhostIntent("15550001111@s.whatsapp.net")
	cm := msgconv.New(nil).ToMatrix(ctx, portal, whatsmeow.NewClient(&store.Device{}, waLog.Noop), intent, msg, msg, &types.MessageInfo{}, false, false, nil)
	require.Len(t, cm.Parts, 1)
	resp, err := intent.SendMessage(ctx, roomID, event.EventMessage, &event.Content{Parsed: cm.Parts[0].Content}, nil)
	require.NoError(t, err)
	got, err := intent.GetEvent(ctx, roomID, resp.EventID)
	require.NoError(t, err)
	return got.Content.AsMessage()
}

func TestWhatsAppLinkPreviewKeepsThumbnail(t *testing.T) {
	c := newTestConnector(t)
	thumb := tinyJPEG(t)
	got := convertWhatsAppText(t, c, &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{
		Text:          proto.String("look https://www.youtube.com/watch?v=abc"),
		MatchedText:   proto.String("https://www.youtube.com/watch?v=abc"),
		Title:         proto.String("A video"),
		JPEGThumbnail: thumb,
	}})
	require.Len(t, got.BeeperLinkPreviews, 1)
	p := got.BeeperLinkPreviews[0]
	require.NotEmpty(t, p.ImageURL, "the inline JPEG thumbnail must come out as og:image")
	data, err := c.BotIntent().DownloadMedia(context.Background(), p.ImageURL, nil)
	require.NoError(t, err)
	require.Equal(t, thumb, data)
}

// A failed download of the hosted thumbnail (here: a client that is not connected) falls back to the inline one.
func TestWhatsAppLinkPreviewFallsBackToInlineThumbnailWhenDownloadFails(t *testing.T) {
	c := newTestConnector(t)
	got := convertWhatsAppText(t, c, &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{
		Text:                proto.String("https://example.com/a"),
		MatchedText:         proto.String("https://example.com/a"),
		Title:               proto.String("A page"),
		ThumbnailDirectPath: proto.String("/v/t62.7118-24/thumb"),
		ThumbnailEncSHA256:  []byte("enc"),
		MediaKey:            []byte("key"),
		JPEGThumbnail:       tinyJPEG(t),
	}})
	require.Len(t, got.BeeperLinkPreviews, 1)
	require.NotEmpty(t, got.BeeperLinkPreviews[0].ImageURL)
}

// With no thumbnail bytes at all the preview is title-only: the shape of the one WhatsApp preview in the user's store.
func TestWhatsAppLinkPreviewWithoutThumbnailBytesHasNoImage(t *testing.T) {
	c := newTestConnector(t)
	got := convertWhatsAppText(t, c, &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{
		Text:        proto.String("https://example.com/a"),
		MatchedText: proto.String("https://example.com/a"),
		Title:       proto.String("A page"),
	}})
	require.Len(t, got.BeeperLinkPreviews, 1)
	require.Empty(t, got.BeeperLinkPreviews[0].ImageURL)
	require.Zero(t, got.BeeperLinkPreviews[0].ImageSize, "the bridge sets the size only when it holds thumbnail bytes")
}

// Plain text with no link yields the empty list, which is where the 154 "linkpreviews":[] events come from: the
// bridge writes it for every plain WhatsApp text, sent by anyone.
func TestWhatsAppPlainTextGetsEmptyPreviewList(t *testing.T) {
	c := newTestConnector(t)
	got := convertWhatsAppText(t, c, &waE2E.Message{Conversation: proto.String("hello")})
	require.NotNil(t, got.BeeperLinkPreviews)
	require.Empty(t, got.BeeperLinkPreviews)
}
