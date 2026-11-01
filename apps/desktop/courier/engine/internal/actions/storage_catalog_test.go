// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func storageTestPNG(t *testing.T, r uint8) []byte {
	t.Helper()
	var buf bytes.Buffer
	img := image.NewNRGBA(image.Rect(0, 0, 16, 16))
	img.Set(1, 1, color.NRGBA{R: r, G: 100, B: 200, A: 255})
	require.NoError(t, png.Encode(&buf, img))
	return buf.Bytes()
}

// The storage clean-up reads the sticker catalog exactly as ImportSticker and a pack sync write it: an imported
// sticker is never deleted, and a synced pack's sticker goes only when stickers are included and the pack was synced
// before the cut-off.
func TestStorageCleanupReadsTheStickerCatalogTheActionsWrite(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	w := startWorldOn(t, "telegram", n, true, zerolog.Nop())
	w.s.SetMediaStore(w.m)
	w.s.SetMediaPutGrace(0)
	room, _ := w.chat(t, "chat-1", "m-1")

	// An imported sticker, written by ImportSticker.
	stickerPath := filepath.Join(t.TempDir(), "sample.png")
	require.NoError(t, os.WriteFile(stickerPath, storageTestPNG(t, 10), 0o600))
	item, err := w.a.ImportSticker(ctx, ImportStickerReq{Path: stickerPath, Name: "Sample"})
	require.NoError(t, err)
	importedHash := strings.TrimPrefix(item.MediaURL, "courier://media/")
	importedFile, err := w.m.Path(importedHash)
	require.NoError(t, err)

	// A synced pack sticker, written by ListStickers(refresh).
	bridgeHash, err := w.m.Put(storageTestPNG(t, 20))
	require.NoError(t, err)
	bridgeFile, err := w.m.Path(bridgeHash)
	require.NoError(t, err)
	packURL := "https://example.invalid/addstickers/SamplePack"
	meta := event.ImagePackMetadata{
		DisplayName: "Sample Pack",
		Usage:       []event.ImagePackUsage{event.ImagePackUsageSticker},
		BridgedPack: &event.BridgedStickerPack{Network: "telegram", URL: packURL},
	}
	n.ImagePacks = []*event.ImagePackMetadata{&meta}
	n.DownloadedPacks = map[string]*bridgev2.ImportedImagePack{
		packURL: {Shortcode: "SamplePack", Content: &event.ImagePackEventContent{
			Metadata: meta,
			Images:   map[string]*event.ImagePackImage{"one": {URL: ids.ContentURI(bridgeHash), Body: "x"}},
		}},
	}
	_, err = w.a.ListStickers(ctx, true)
	require.NoError(t, err)

	// The chat once showed the imported sticker.
	_, err = w.s.InsertEvent(ctx, store.Event{
		RoomID: room, EventID: "$sticker-1", Sender: "@someone:courier.local", Type: "m.sticker",
		Content: json.RawMessage(`{"body":"Sample","url":"` + string(ids.ContentURI(importedHash)) + `","info":{"mimetype":"image/png"}}`),
		TS:      time.Now().Add(-48 * time.Hour), Status: "sent",
	})
	require.NoError(t, err)

	// Without stickers, neither sticker goes.
	_, err = w.s.CleanupStorage(ctx, store.StorageCleanupFilter{})
	require.NoError(t, err)
	require.FileExists(t, importedFile)
	require.FileExists(t, bridgeFile)

	// With stickers but only older than 30 days: the pack was synced just now, so its sticker stays.
	_, err = w.s.CleanupStorage(ctx, store.StorageCleanupFilter{
		IncludeStickers: true, OlderThanMS: (30 * 24 * time.Hour).Milliseconds(),
	})
	require.NoError(t, err)
	require.FileExists(t, bridgeFile, "a pack synced just now is not older than 30 days")

	// With stickers and no age: the synced pack's sticker goes, the imported one stays.
	report, err := w.s.CleanupStorage(ctx, store.StorageCleanupFilter{IncludeStickers: true})
	require.NoError(t, err)
	require.Equal(t, 1, report.RemovedBlobs)
	require.NoFileExists(t, bridgeFile, "a synced pack sticker is cache")
	require.FileExists(t, importedFile, "an imported sticker is never deleted")
}
