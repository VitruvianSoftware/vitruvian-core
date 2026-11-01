// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/media"
)

func putTestBlob(t *testing.T, ms *media.Store, tag byte, size int) (hash, uri, path string) {
	t.Helper()
	buf := bytes.Repeat([]byte{tag}, size)
	if len(buf) >= 4 {
		buf[0] = tag
		buf[1] = byte(size >> 8)
		buf[2] = byte(size)
	}
	var err error
	hash, err = ms.Put(buf)
	require.NoError(t, err)
	path, err = ms.Path(hash)
	require.NoError(t, err)
	return hash, "mxc://courier.local/" + hash, path
}

func TestStorageUsageCategorizesMediaStickersDatabaseAndPerRoomTotals(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "courier.db")
	s, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })

	ms := &media.Store{Dir: filepath.Join(dir, "media")}
	s.SetMediaStore(ms)

	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID:        "!wa1",
		Network:   "whatsapp",
		Name:      "Design Team",
		CreatedAt: time.Unix(100, 0),
	}))
	require.NoError(t, s.UpsertRoom(ctx, Room{
		ID:        "!sig1",
		Network:   "signal",
		Name:      "Alice",
		CreatedAt: time.Unix(100, 0),
	}))

	_, imgURI, _ := putTestBlob(t, ms, 0x11, 1024)
	_, thumbURI, _ := putTestBlob(t, ms, 0x12, 256)
	_, vidURI, _ := putTestBlob(t, ms, 0x13, 4096)
	_, audURI, _ := putTestBlob(t, ms, 0x14, 512)
	_, fileURI, _ := putTestBlob(t, ms, 0x15, 2048)
	_, stkURI, _ := putTestBlob(t, ms, 0x16, 768)
	_, _, _ = putTestBlob(t, ms, 0x17, 300) // orphan blob in media.Store.Dir

	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$img1",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"photo.jpg","url":"` + imgURI + `","info":{"mimetype":"image/jpeg","thumbnail_url":"` + thumbURI + `"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)

	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$vid1",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.video","body":"clip.mp4","url":"` + vidURI + `","info":{"mimetype":"video/mp4"}}`),
		TS:      time.UnixMilli(2000),
		Status:  "sent",
	})
	require.NoError(t, err)

	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!sig1",
		EventID: "$aud1",
		Sender:  "@bob:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.audio","body":"voice.ogg","url":"` + audURI + `","org.matrix.msc3245.voice":{}}`),
		TS:      time.UnixMilli(3000),
		Status:  "sent",
	})
	require.NoError(t, err)

	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!sig1",
		EventID: "$file1",
		Sender:  "@bob:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.file","body":"spec.pdf","url":"` + fileURI + `","info":{"mimetype":"application/pdf"}}`),
		TS:      time.UnixMilli(4000),
		Status:  "sent",
	})
	require.NoError(t, err)

	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!sig1",
		EventID: "$stk1",
		Sender:  "@bob:courier.local",
		Type:    "m.sticker",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"Wave","url":"` + stkURI + `","info":{"mimetype":"image/webp"}}`),
		TS:      time.UnixMilli(5000),
		Status:  "sent",
	})
	require.NoError(t, err)

	usage, err := s.StorageUsage(ctx, dbPath)
	require.NoError(t, err)

	require.Greater(t, usage.DatabaseBytes, int64(0))
	require.Equal(t, int64(1024+256+4096), usage.PhotosAndVideosBytes)
	require.Equal(t, int64(512), usage.AudioBytes)
	require.Equal(t, int64(2048), usage.FilesBytes)
	require.Equal(t, int64(768), usage.StickersBytes)
	require.Equal(t, int64(300), usage.OtherMediaBytes)
	require.Equal(
		t,
		usage.DatabaseBytes+usage.PhotosAndVideosBytes+usage.AudioBytes+usage.FilesBytes+usage.StickersBytes+usage.OtherMediaBytes,
		usage.TotalBytes,
	)

	require.Len(t, usage.Rooms, 2)
	require.Equal(t, RoomStorageUsage{
		RoomID:     "!wa1",
		Name:       "Design Team",
		Network:    "whatsapp",
		MediaBytes: 1024 + 256 + 4096,
		ItemCount:  2,
	}, usage.Rooms[0])
	require.Equal(t, RoomStorageUsage{
		RoomID:     "!sig1",
		Name:       "Alice",
		Network:    "signal",
		MediaBytes: 512 + 2048 + 768,
		ItemCount:  3,
	}, usage.Rooms[1])
}

func TestCleanupStorageByAgeAndRoomPreservesEventsAndSharedOrUserStickerBlobs(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "courier.db")
	s, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })

	ms := &media.Store{Dir: filepath.Join(dir, "media")}
	s.SetMediaStore(ms)

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa1", Network: "whatsapp", Name: "WhatsApp Room", CreatedAt: time.Unix(10, 0)}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!sig1", Network: "signal", Name: "Signal Room", CreatedAt: time.Unix(10, 0)}))

	_, waOldURI, waOldPath := putTestBlob(t, ms, 0x21, 1000)
	_, waOldThumbURI, waOldThumbPath := putTestBlob(t, ms, 0x22, 200)
	_, waNewURI, waNewPath := putTestBlob(t, ms, 0x23, 1500)
	_, sharedURI, sharedPath := putTestBlob(t, ms, 0x24, 800)
	userStkHash, userStkURI, userStkPath := putTestBlob(t, ms, 0x25, 600)
	bridgeStkHash, bridgeStkURI, bridgeStkPath := putTestBlob(t, ms, 0x26, 900)

	// Write stickers.json with a user-imported sticker (pack_id = "user") and a cached bridge sticker (pack_id = "telegram-cats").
	stickersJSON := `{
		"imported": [
			{"id":"usr-1","pack_id":"user","name":"Custom Parrot","shortcode":":parrot:","media_url":"courier://media/` + userStkHash + `","mime_type":"image/png","width":128,"height":128,"added_ts":1000}
		],
		"bridge_packs": [
			{"id":"telegram-cats","name":"Cats","network":"telegram","stickers":[
				{"id":"cat-1","pack_id":"telegram-cats","name":"Happy Cat","media_url":"courier://media/` + bridgeStkHash + `","mime_type":"image/webp","width":256,"height":256,"added_ts":1000}
			]}
		]
	}`
	require.NoError(t, os.WriteFile(filepath.Join(ms.Dir, "stickers.json"), []byte(stickersJSON), 0o600))

	// Old media event in !wa1 (ts = 1000) with unique main + thumbnail blobs.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$wa-old",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"old-photo.jpg","url":"` + waOldURI + `","info":{"mimetype":"image/jpeg","thumbnail_url":"` + waOldThumbURI + `"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)

	// New media event in !wa1 (ts = 9000).
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$wa-new",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"new-photo.jpg","url":"` + waNewURI + `","info":{"mimetype":"image/jpeg"}}`),
		TS:      time.UnixMilli(9000),
		Status:  "sent",
	})
	require.NoError(t, err)

	// Old media event in !wa1 sharing a blob with !sig1.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$wa-shared",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"shared.jpg","url":"` + sharedURI + `","info":{"mimetype":"image/jpeg"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!sig1",
		EventID: "$sig-shared",
		Sender:  "@bob:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"shared.jpg","url":"` + sharedURI + `","info":{"mimetype":"image/jpeg"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)

	// Old event in !wa1 referencing the user-imported sticker blob.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$wa-user-stk",
		Sender:  "@alice:courier.local",
		Type:    "m.sticker",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"Custom Parrot","url":"` + userStkURI + `","info":{"mimetype":"image/png"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)

	// Old bridge sticker event in !sig1.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!sig1",
		EventID: "$sig-bridge-stk",
		Sender:  "@bob:courier.local",
		Type:    "m.sticker",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"Happy Cat","url":"` + bridgeStkURI + `","info":{"mimetype":"image/webp"}}`),
		TS:      time.UnixMilli(1000),
		Status:  "sent",
	})
	require.NoError(t, err)

	// 1. Clean !wa1 older than 5000ms without stickers.
	report, err := s.CleanupStorage(ctx, StorageCleanupFilter{
		RoomIDs:         []string{"!wa1"},
		OlderThanMS:     5000,
		IncludeStickers: false,
	})
	require.NoError(t, err)
	require.Equal(t, 2, report.RemovedBlobs)
	require.Equal(t, int64(1000+200), report.FreedBytes)

	// Unshared old blobs in !wa1 are removed from disk.
	_, err = os.Stat(waOldPath)
	require.ErrorIs(t, err, os.ErrNotExist)
	_, err = os.Stat(waOldThumbPath)
	require.ErrorIs(t, err, os.ErrNotExist)

	// $wa-old remains in SQLite with body intact, while media_path and thumbnail_path become "".
	cleanedEv, ok, err := s.GetEvent(ctx, "$wa-old")
	require.NoError(t, err)
	require.True(t, ok)
	ExtractEventMedia(&cleanedEv, ms, false)
	require.Empty(t, cleanedEv.MediaPath)
	require.Empty(t, cleanedEv.ThumbnailPath)
	require.Contains(t, string(cleanedEv.Content), "old-photo.jpg")

	// $wa-shared in !wa1 also has its media_path cleared, but sharedPath stays on disk because !sig1 still references it.
	waSharedEv, ok, err := s.GetEvent(ctx, "$wa-shared")
	require.NoError(t, err)
	require.True(t, ok)
	ExtractEventMedia(&waSharedEv, ms, false)
	require.Empty(t, waSharedEv.MediaPath)
	_, err = os.Stat(sharedPath)
	require.NoError(t, err, "blob shared with !sig1 must remain on disk")

	// User-imported sticker blob and newer !wa1 blob and bridge sticker blob remain on disk.
	_, err = os.Stat(userStkPath)
	require.NoError(t, err, "user-imported sticker blob must never be removed")
	_, err = os.Stat(waNewPath)
	require.NoError(t, err, "newer blob in !wa1 must remain on disk")
	_, err = os.Stat(bridgeStkPath)
	require.NoError(t, err, "bridge sticker blob must remain when IncludeStickers is false")

	// 2. Clean !sig1 older than 5000ms with IncludeStickers: false -> sharedPath is now unreferenced and removed, bridge sticker stays.
	report2, err := s.CleanupStorage(ctx, StorageCleanupFilter{
		RoomIDs:         []string{"!sig1"},
		OlderThanMS:     5000,
		IncludeStickers: false,
	})
	require.NoError(t, err)
	require.Equal(t, 1, report2.RemovedBlobs)
	require.Equal(t, int64(800), report2.FreedBytes)
	_, err = os.Stat(sharedPath)
	require.ErrorIs(t, err, os.ErrNotExist, "shared blob must be removed once !sig1 no longer references it")
	_, err = os.Stat(bridgeStkPath)
	require.NoError(t, err, "bridge sticker blob must remain when IncludeStickers is false")

	// 3. Clean with IncludeStickers: true -> cached bridge sticker is removed while user-imported sticker (pack_id = 'user') is preserved.
	report3, err := s.CleanupStorage(ctx, StorageCleanupFilter{
		OlderThanMS:     5000,
		IncludeStickers: true,
	})
	require.NoError(t, err)
	require.Equal(t, 1, report3.RemovedBlobs)
	require.Equal(t, int64(900), report3.FreedBytes)
	_, err = os.Stat(bridgeStkPath)
	require.ErrorIs(t, err, os.ErrNotExist, "cached bridge sticker blob must be removed when IncludeStickers is true")
	_, err = os.Stat(userStkPath)
	require.NoError(t, err, "user-imported sticker (pack_id = 'user') must still be preserved when IncludeStickers is true")
}
