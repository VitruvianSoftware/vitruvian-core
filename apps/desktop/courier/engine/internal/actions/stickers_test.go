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

	// 1b. ImportSticker rejects a file with a valid extension (.png) whose bytes do not decode as an image,
	// and leaves nothing in media.Store.
	badPNGPath := filepath.Join(tmpDir, "bad.png")
	require.NoError(t, os.WriteFile(badPNGPath, []byte{0x01, 0x02, 0x03, 0x04}, 0o600))
	blobsBeforeBadPNG := countMediaBlobs(t, w.m.Dir)
	_, err = w.a.ImportSticker(ctx, ImportStickerReq{
		Path: badPNGPath,
		Name: "Corrupt PNG",
	})
	require.ErrorIs(t, err, ErrBadValue)
	require.Equal(t, blobsBeforeBadPNG, countMediaBlobs(t, w.m.Dir), "refused corrupt image must not write to media.Store")

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

func TestListStickersDoesNotSyncBridgePacksUnlessRefreshRequested(t *testing.T) {
	ctx := context.Background()

	var pngBuf bytes.Buffer
	img := image.NewNRGBA(image.Rect(0, 0, 16, 16))
	img.Set(1, 1, color.NRGBA{R: 50, G: 100, B: 200, A: 255})
	require.NoError(t, png.Encode(&pngBuf, img))

	n := fakenet.New()
	w := startWorldOn(t, "telegram", n, true, zerolog.Nop())
	_, _ = w.chat(t, "chat-1", "m-1")

	bridgeHash, err := w.m.Put(pngBuf.Bytes())
	require.NoError(t, err)
	bridgeURI := ids.ContentURI(bridgeHash)

	tgPackURL := "https://t.me/addstickers/CatPack"
	tgMeta := event.ImagePackMetadata{
		DisplayName: "Cat Pack",
		Usage:       []event.ImagePackUsage{event.ImagePackUsageSticker},
		BridgedPack: &event.BridgedStickerPack{
			Network: "telegram",
			URL:     tgPackURL,
		},
	}
	n.ImagePacks = []*event.ImagePackMetadata{&tgMeta}
	n.DownloadedPacks = map[string]*bridgev2.ImportedImagePack{
		tgPackURL: {
			Shortcode: "CatPack",
			Content: &event.ImagePackEventContent{
				Metadata: tgMeta,
				Images: map[string]*event.ImagePackImage{
					"happy_cat": {
						URL:  bridgeURI,
						Body: "😺",
					},
				},
			},
		},
	}

	// Non-refresh stickers.list (e.g. on chat open) with an empty cache must NEVER call ListImagePacks or DownloadImagePack.
	initial, err := w.a.ListStickers(ctx, false)
	require.NoError(t, err)
	require.Zero(t, n.ListImagePacksCalls.Load(), "non-refresh stickers.list must not call ListImagePacks")
	require.Zero(t, n.DownloadImagePackCalls.Load(), "non-refresh stickers.list must not call DownloadImagePack")
	for _, p := range initial.Packs {
		require.NotEqual(t, "bridge", p.Source, "non-refresh stickers.list on empty cache must not fetch bridge packs")
	}

	// Explicit refresh=true ("Sync Packs") calls ListImagePacks + DownloadImagePack and caches the result.
	refreshed, err := w.a.ListStickers(ctx, true)
	require.NoError(t, err)
	require.EqualValues(t, 1, n.ListImagePacksCalls.Load())
	require.EqualValues(t, 1, n.DownloadImagePackCalls.Load())
	var bridgePacks []StickerPack
	for _, p := range refreshed.Packs {
		if p.Source == "bridge" {
			bridgePacks = append(bridgePacks, p)
		}
	}
	require.Len(t, bridgePacks, 1)
	require.Equal(t, "Cat Pack", bridgePacks[0].Title)

	// Subsequent non-refresh stickers.list serves the cached pack without calling the bridge again.
	cached, err := w.a.ListStickers(ctx, false)
	require.NoError(t, err)
	require.EqualValues(t, 1, n.ListImagePacksCalls.Load())
	require.EqualValues(t, 1, n.DownloadImagePackCalls.Load())
	var cachedBridgePacks []StickerPack
	for _, p := range cached.Packs {
		if p.Source == "bridge" {
			cachedBridgePacks = append(cachedBridgePacks, p)
		}
	}
	require.Len(t, cachedBridgePacks, 1)

	// When refresh=true returns an empty pack list, the empty result is still persisted with a timestamp.
	n.ImagePacks = nil
	n.DownloadedPacks = nil
	emptyRefreshed, err := w.a.ListStickers(ctx, true)
	require.NoError(t, err)
	for _, p := range emptyRefreshed.Packs {
		require.NotEqual(t, "bridge", p.Source)
	}
	rawCat, err := os.ReadFile(filepath.Join(w.dir, "media", "stickers.json"))
	require.NoError(t, err)
	require.Contains(t, string(rawCat), `"bridge_packs_synced_at"`, "refresh=true must persist sync timestamp even when bridge packs are empty")
}

func TestFetchBridgeStickerPacksSkipsPackWithoutURL(t *testing.T) {
	ctx := context.Background()

	n := fakenet.New()
	w := startWorldOn(t, "telegram", n, true, zerolog.Nop())
	_, _ = w.chat(t, "chat-1", "m-1")

	noURLMeta := event.ImagePackMetadata{
		DisplayName: "Cute Cats",
		Usage:       []event.ImagePackUsage{event.ImagePackUsageSticker},
		BridgedPack: &event.BridgedStickerPack{
			Network: "telegram",
			URL:     "",
		},
	}
	n.ImagePacks = []*event.ImagePackMetadata{&noURLMeta}
	n.DownloadedPacks = map[string]*bridgev2.ImportedImagePack{
		"Cute Cats": {
			Shortcode: "CuteCats",
			Content: &event.ImagePackEventContent{
				Metadata: noURLMeta,
				Images: map[string]*event.ImagePackImage{
					"cat1": {URL: "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"},
				},
			},
		},
	}

	res, err := w.a.ListStickers(ctx, true)
	require.NoError(t, err)
	require.EqualValues(t, 1, n.ListImagePacksCalls.Load())
	require.Zero(t, n.DownloadImagePackCalls.Load(), "pack without BridgedPack.URL must be skipped instead of passing DisplayName to DownloadImagePack")
	for _, p := range res.Packs {
		require.NotEqual(t, "bridge", p.Source)
	}
}

func TestImportStickerRemovesBlobWhenCatalogSaveFails(t *testing.T) {
	ctx := context.Background()

	var pngBuf bytes.Buffer
	img := image.NewNRGBA(image.Rect(0, 0, 16, 16))
	img.Set(2, 2, color.NRGBA{R: 200, G: 50, B: 50, A: 255})
	require.NoError(t, png.Encode(&pngBuf, img))

	tmpDir := t.TempDir()
	pngPath := filepath.Join(tmpDir, "orphan.png")
	require.NoError(t, os.WriteFile(pngPath, pngBuf.Bytes(), 0o600))

	n := fakenet.New()
	w := startWorldOn(t, "telegram", n, true, zerolog.Nop())

	// Make saveStickersCatalog fail by placing a non-empty directory at <mediaDir>/stickers.json.tmp.
	require.NoError(t, os.MkdirAll(filepath.Join(w.m.Dir, "stickers.json.tmp", "blocker"), 0o700))

	blobsBefore := countMediaBlobs(t, w.m.Dir)
	_, err := w.a.ImportSticker(ctx, ImportStickerReq{
		Path: pngPath,
		Name: "Orphan Check",
	})
	require.Error(t, err)
	require.Equal(t, blobsBefore, countMediaBlobs(t, w.m.Dir), "ImportSticker must remove the newly written blob when saving stickers.json fails")
}
