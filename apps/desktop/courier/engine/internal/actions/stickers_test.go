// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

func TestImportAndListStickers(t *testing.T) {
	ctx := context.Background()

	// Build a valid PNG sticker on disk.
	var pngBuf bytes.Buffer
	img := image.NewNRGBA(image.Rect(0, 0, 32, 32))
	img.Set(1, 1, color.NRGBA{R: 100, G: 200, B: 50, A: 255})
	require.NoError(t, png.Encode(&pngBuf, img))

	tmpDir := t.TempDir()
	pngPath := filepath.Join(tmpDir, "party_parrot.png")
	require.NoError(t, os.WriteFile(pngPath, pngBuf.Bytes(), 0o600))
	gifBytes := []byte("GIF89a\x08\x00\x08\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x08\x00\x08\x00\x00\x02\x02D\x01\x00;")
	gifPath := filepath.Join(tmpDir, "wave.gif")
	require.NoError(t, os.WriteFile(gifPath, gifBytes, 0o600))
	badPath := filepath.Join(tmpDir, "malware.exe")
	require.NoError(t, os.WriteFile(badPath, []byte("MZ\x90\x00"), 0o600))

	n := fakenet.New()
	w := startWorldOn(t, "telegram", n, true, zerolog.Nop())
	room, _ := w.chat(t, "chat-1", "m-1")

	// Pre-populate a media blob in w.m to represent what a bridge's DownloadImagePack uploads via MatrixAPI.UploadMedia.
	bridgeHash, err := w.m.Put(pngBuf.Bytes())
	require.NoError(t, err)
	bridgeURI := ids.ContentURI(bridgeHash)

	// Configure the fake network implementing bridgev2.StickerImportingNetworkAPI
	// with both a Telegram-style sticker pack (BridgedSticker + ImagePackUsageSticker)
	// and a Slack-style custom emoji pack (ImagePackUsageEmoji = "emoticon").
	tgPackURL := "https://t.me/addstickers/CatPack"
	slackPackURL := "https://workspace.slack.com/"
	tgMeta := event.ImagePackMetadata{
		DisplayName: "Cat Pack",
		Usage:       []event.ImagePackUsage{event.ImagePackUsageSticker},
		BridgedPack: &event.BridgedStickerPack{
			Network: "telegram",
			URL:     tgPackURL,
		},
	}
	slackMeta := event.ImagePackMetadata{
		DisplayName: "Workspace Emoji",
		Usage:       []event.ImagePackUsage{event.ImagePackUsageEmoji},
		BridgedPack: &event.BridgedStickerPack{
			Network: "slack",
			URL:     slackPackURL,
		},
	}
	n.ImagePacks = []*event.ImagePackMetadata{&tgMeta, &slackMeta}
	n.DownloadedPacks = map[string]*bridgev2.ImportedImagePack{
		tgPackURL: {
			Shortcode: "CatPack",
			Content: &event.ImagePackEventContent{
				Metadata: tgMeta,
				Images: map[string]*event.ImagePackImage{
					"happy_cat": {
						URL:  bridgeURI,
						Body: "😺",
						Info: &event.FileInfo{
							MimeType: "image/png",
							Width:    32,
							Height:   32,
							BridgedSticker: &event.BridgedSticker{
								Network: "telegram",
								PackURL: tgPackURL,
								ID:      "doc-9001",
								Emoji:   "😺",
							},
						},
					},
				},
			},
		},
		slackPackURL: {
			Shortcode: "workspace-emoji",
			Content: &event.ImagePackEventContent{
				Metadata: slackMeta,
				Images: map[string]*event.ImagePackImage{
					"shipit": {
						URL:  bridgeURI,
						Body: ":shipit:",
						Info: &event.FileInfo{
							MimeType: "image/png",
							Width:    32,
							Height:   32,
						},
					},
				},
			},
		},
	}

	// 1. ImportSticker rejects unsupported file extensions/MIME types.
	_, err = w.a.ImportSticker(ctx, ImportStickerReq{
		Path: badPath,
		Name: "Bad",
	})
	require.ErrorIs(t, err, ErrBadValue)

	// 2. ImportSticker imports a valid .png with surrounding colons on Shortcode,
	// writes to media.Store, persists to <dataDir>/media/stickers.json, and defaults Usage to ["emoticon", "sticker"].
	imported, err := w.a.ImportSticker(ctx, ImportStickerReq{
		Path:      pngPath,
		Shortcode: ":party_parrot:",
		Name:      "Party Parrot",
		Emoji:     "🦜",
	})
	require.NoError(t, err)
	require.Equal(t, "imported", imported.PackID)
	require.Equal(t, "party_parrot", imported.Shortcode)
	require.Equal(t, "Party Parrot", imported.Name)
	require.Equal(t, "🦜", imported.Emoji)
	require.True(t, strings.HasPrefix(imported.MediaURL, "courier://media/"))
	require.Equal(t, "image/png", imported.MimeType)
	require.Equal(t, 32, imported.Width)
	require.Equal(t, 32, imported.Height)
	require.Equal(t, []string{"emoticon", "sticker"}, imported.Usage)

	// Verify <dataDir>/media/stickers.json was written on disk.
	stickersJSONPath := filepath.Join(w.dir, "media", "stickers.json")
	_, err = os.Stat(stickersJSONPath)
	require.NoError(t, err)

	// 3. Send a sticker and a GIF in the room so recent stickers and recent GIFs are populated in SQLite.
	_, err = w.a.SendSticker(ctx, SendStickerReq{
		RoomID:   room,
		MediaURL: imported.MediaURL,
		Name:     "Sent Parrot",
		Emoji:    "🦜",
	})
	require.NoError(t, err)
	recv(t, w.n.Files, "sent sticker")

	_, err = w.a.SendGIF(ctx, SendGIFReq{
		RoomID:  room,
		Path:    gifPath,
		Caption: "Wave",
	})
	require.NoError(t, err)
	recv(t, w.n.Files, "sent gif")

	// 4. ListStickers combines recent, imported, bridge packs, and recent_gifs.
	listed, err := w.a.ListStickers(ctx, true)
	require.NoError(t, err)
	require.Len(t, listed.RecentGIFs, 1)
	require.Equal(t, "Wave", listed.RecentGIFs[0].Name)
	require.Equal(t, "image/gif", listed.RecentGIFs[0].MimeType)

	packBySource := map[string][]StickerPack{}
	for _, p := range listed.Packs {
		packBySource[p.Source] = append(packBySource[p.Source], p)
	}
	require.Len(t, packBySource["recent"], 1)
	require.Len(t, packBySource["recent"][0].Items, 1)
	require.Equal(t, "Sent Parrot", packBySource["recent"][0].Items[0].Name)

	require.Len(t, packBySource["imported"], 1)
	require.Len(t, packBySource["imported"][0].Items, 1)
	require.Equal(t, "party_parrot", packBySource["imported"][0].Items[0].Shortcode)

	require.Len(t, packBySource["bridge"], 2)
	var tgPack, slackPack StickerPack
	for _, p := range packBySource["bridge"] {
		switch p.Title {
		case "Cat Pack":
			tgPack = p
		case "Workspace Emoji":
			slackPack = p
		}
	}
	require.Len(t, tgPack.Items, 1)
	require.Equal(t, "telegram", tgPack.Network)
	require.NotNil(t, tgPack.Items[0].BridgedSticker)
	require.Equal(t, "doc-9001", tgPack.Items[0].BridgedSticker.ID)
	require.Equal(t, []string{"sticker"}, tgPack.Items[0].Usage)

	require.Len(t, slackPack.Items, 1)
	require.Equal(t, "shipit", slackPack.Items[0].Shortcode)
	require.Equal(t, []string{"emoticon"}, slackPack.Items[0].Usage)
}
