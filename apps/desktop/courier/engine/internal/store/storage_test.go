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

// openCleanupStore opens a store with a media store and a fixed clock, with no grace for blobs written just before a
// clean-up (the grace is what keeps a message arriving mid-clean-up; these tests write their blobs just before).
func openCleanupStore(t *testing.T, now time.Time) (*Store, *media.Store) {
	t.Helper()
	dir := t.TempDir()
	s, err := Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	ms := &media.Store{Dir: filepath.Join(dir, "media")}
	s.SetMediaStore(ms)
	s.SetClock(func() time.Time { return now })
	s.SetMediaPutGrace(0)
	return s, ms
}

func insertImage(t *testing.T, s *Store, roomID, eventID, uri string, ts time.Time) {
	t.Helper()
	_, err := s.InsertEvent(context.Background(), Event{
		RoomID:  roomID,
		EventID: eventID,
		Sender:  "@someone:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"photo.jpg","url":"` + uri + `","info":{"mimetype":"image/jpeg"}}`),
		TS:      ts,
		Status:  "sent",
	})
	require.NoError(t, err)
}


// older_than_ms is a duration (the app sends one week as 604800000), so "older than 30 days" is measured back from
// now: a message 40 days old loses its media, one 2 days old keeps it.
func TestCleanupStorageOlderThanIsADurationBackFromNow(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	s, ms := openCleanupStore(t, now)

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!a", Network: "whatsapp", Name: "Room A", CreatedAt: now.Add(-100 * day)}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!b", Network: "signal", Name: "Room B", CreatedAt: now.Add(-100 * day)}))

	_, oldURI, oldPath := putTestBlob(t, ms, 0x21, 1000)
	_, oldThumbURI, oldThumbPath := putTestBlob(t, ms, 0x22, 200)
	_, newURI, newPath := putTestBlob(t, ms, 0x23, 1500)
	_, sharedURI, sharedPath := putTestBlob(t, ms, 0x24, 800)

	old, recent := now.Add(-40*day), now.Add(-2*day)
	_, err := s.InsertEvent(ctx, Event{
		RoomID:  "!a",
		EventID: "$a-old",
		Sender:  "@someone:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"old-photo.jpg","url":"` + oldURI + `","info":{"mimetype":"image/jpeg","thumbnail_url":"` + oldThumbURI + `"}}`),
		TS:      old,
		Status:  "sent",
	})
	require.NoError(t, err)
	insertImage(t, s, "!a", "$a-new", newURI, recent)
	insertImage(t, s, "!a", "$a-shared", sharedURI, old)
	insertImage(t, s, "!b", "$b-shared", sharedURI, old)

	thirtyDays := (30 * day).Milliseconds()

	// 1. Room A, older than 30 days: the old photo and its thumbnail go; the recent one and the blob room B still
	// uses stay.
	report, err := s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: []string{"!a"}, OlderThanMS: thirtyDays})
	require.NoError(t, err)
	require.Equal(t, 2, report.RemovedBlobs)
	require.Equal(t, int64(1000+200), report.FreedBytes)
	require.NoFileExists(t, oldPath)
	require.NoFileExists(t, oldThumbPath)
	require.FileExists(t, newPath, "a 2-day-old photo is not older than 30 days")
	require.FileExists(t, sharedPath, "room B still uses the shared blob")

	cleaned, ok, err := s.GetEvent(ctx, "$a-old")
	require.NoError(t, err)
	require.True(t, ok)
	ExtractEventMedia(&cleaned, ms, false)
	require.Empty(t, cleaned.MediaPath)
	require.Empty(t, cleaned.ThumbnailPath)
	require.Contains(t, string(cleaned.Content), "old-photo.jpg", "the message itself stays")

	// 2. Room B, older than 30 days: nothing uses the shared blob any more, so it goes.
	report, err = s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: []string{"!b"}, OlderThanMS: thirtyDays})
	require.NoError(t, err)
	require.Equal(t, 1, report.RemovedBlobs)
	require.NoFileExists(t, sharedPath)

	// 3. Every chat, older than 1 day: the 2-day-old photo goes too.
	report, err = s.CleanupStorage(ctx, StorageCleanupFilter{OlderThanMS: day.Milliseconds()})
	require.NoError(t, err)
	require.Equal(t, 1, report.RemovedBlobs)
	require.NoFileExists(t, newPath)
}

// After a clean-up rewrites messages, the change feed says so, so a chat that is open re-reads them.
func TestCleanupStorageTellsSubscribersToReRead(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	s, ms := openCleanupStore(t, now)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!a", Network: "whatsapp", Name: "Room A", CreatedAt: now.Add(-10 * day)}))
	_, uri, _ := putTestBlob(t, ms, 0x41, 300)
	insertImage(t, s, "!a", "$a-1", uri, now.Add(-5*day))

	changes, stop := s.Subscribe()
	defer stop()
	_, err := s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: []string{"!a"}})
	require.NoError(t, err)

	var kinds []string
	for {
		select {
		case c := <-changes:
			kinds = append(kinds, c.Kind)
			continue
		default:
		}
		break
	}
	require.Contains(t, kinds, ChangeResync)
}

// A message waiting to be sent later still needs its attachment: cleaning the chat that also showed it keeps the file.
func TestCleanupStorageKeepsBlobsOfScheduledMessages(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	s, ms := openCleanupStore(t, now)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!a", Network: "whatsapp", Name: "Room A", CreatedAt: now.Add(-10 * day)}))
	_, uri, path := putTestBlob(t, ms, 0x51, 400)
	insertImage(t, s, "!a", "$a-1", uri, now.Add(-5*day))
	_, err := s.Schedule(ctx, Scheduled{
		RoomID:  "!a",
		EventID: "$later-1",
		Type:    "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.image","body":"photo.jpg","url":"` + uri + `"}`),
		DueAt:   now.Add(day),
	})
	require.NoError(t, err)

	report, err := s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: []string{"!a"}})
	require.NoError(t, err)
	require.Zero(t, report.RemovedBlobs)
	require.FileExists(t, path, "the scheduled message still sends this file")
}

// A message that arrives during a clean-up with the same file (the same content hash) keeps its file: the blob was
// written after the clean-up started, so the clean-up leaves it.
func TestCleanupStorageKeepsABlobWrittenDuringTheCleanup(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	s, ms := openCleanupStore(t, now)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!a", Network: "whatsapp", Name: "Room A", CreatedAt: now.Add(-10 * day)}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!b", Network: "signal", Name: "Room B", CreatedAt: now.Add(-10 * day)}))
	data := bytes.Repeat([]byte{0x61}, 500)
	hash, err := ms.Put(data)
	require.NoError(t, err)
	uri := "mxc://courier.local/" + hash
	path, err := ms.Path(hash)
	require.NoError(t, err)
	insertImage(t, s, "!a", "$a-1", uri, now.Add(-5*day))

	// The same file arrives in room B after the clean-up has decided what nothing uses, before it deletes.
	s.storageCleanupBeforeDelete = func() {
		_, err := ms.Put(data)
		require.NoError(t, err)
	}
	_, err = s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: []string{"!a"}})
	require.NoError(t, err)
	s.storageCleanupBeforeDelete = nil
	insertImage(t, s, "!b", "$b-1", uri, now)

	require.FileExists(t, path, "the message that arrived during the clean-up keeps its file")
}

// An unknown chat, or a merged chat's ID (the app sends the chats inside it), is ErrNotFound, and nothing changes.
func TestCleanupStorageUnknownOrMergedChatIsNotFound(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 6, 1, 12, 0, 0, 0, time.UTC)
	s, ms := openCleanupStore(t, now)
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!a", Network: "whatsapp", Name: "Room A", CreatedAt: now.Add(-10 * day)}))
	_, uri, path := putTestBlob(t, ms, 0x71, 300)
	insertImage(t, s, "!a", "$a-1", uri, now.Add(-5*day))

	for _, ids := range [][]string{{"!nope"}, {newMergeID()}, {"!a", "!nope"}} {
		_, err := s.CleanupStorage(ctx, StorageCleanupFilter{RoomIDs: ids})
		require.ErrorIs(t, err, ErrNotFound, "%v", ids)
	}
	require.FileExists(t, path, "a refused clean-up deletes nothing")
	ev, ok, err := s.GetEvent(ctx, "$a-1")
	require.NoError(t, err)
	require.True(t, ok)
	require.NotContains(t, string(ev.Content), "media_removed")
}

func TestCleanupStoragePreservesRemoteURLsAndMarksRemovedMediaOnEvents(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "courier.db")
	s, err := Open(dbPath)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })

	ms := &media.Store{Dir: filepath.Join(dir, "media")}
	s.SetMediaStore(ms)
	s.SetMediaPutGrace(0)

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!wa1", Network: "whatsapp", Name: "WhatsApp Room", CreatedAt: time.Unix(10, 0)}))

	_, localImgURI, localImgPath := putTestBlob(t, ms, 0x31, 1024)
	_, localOGURI, localOGPath := putTestBlob(t, ms, 0x32, 512)

	// Event 1: image message with local url, remote thumbnail_url, and two link previews (one remote https og:image, one local blob og:image).
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$ev-mixed",
		Sender:  "@alice:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{
			"msgtype":"m.image",
			"body":"Look at https://example.com",
			"url":"` + localImgURI + `",
			"info":{"mimetype":"image/jpeg","thumbnail_url":"https://example.com/remote-thumb.png"},
			"com.beeper.linkpreviews":[
				{"matched_url":"https://example.com","og:title":"Example","og:image":"https://example.com/a.png"},
				{"matched_url":"https://example.org","og:title":"Org","og:image":"` + localOGURI + `"}
			]
		}`),
		TS:     time.UnixMilli(1000),
		Status: "sent",
	})
	require.NoError(t, err)

	// Event 2: text message with only a remote https og:image in link preview.
	_, err = s.InsertEvent(ctx, Event{
		RoomID:  "!wa1",
		EventID: "$ev-remote-only",
		Sender:  "@bob:courier.local",
		Type:    "m.room.message",
		Content: json.RawMessage(`{
			"msgtype":"m.text",
			"body":"Check https://example.com",
			"com.beeper.linkpreviews":[
				{"matched_url":"https://example.com","og:title":"Example","og:image":"https://example.com/a.png"}
			]
		}`),
		TS:     time.UnixMilli(1500),
		Status: "sent",
	})
	require.NoError(t, err)

	report, err := s.CleanupStorage(ctx, StorageCleanupFilter{
		RoomIDs: []string{"!wa1"},
	})
	require.NoError(t, err)
	require.Equal(t, 2, report.RemovedBlobs)
	require.Equal(t, int64(1024+512), report.FreedBytes)

	_, err = os.Stat(localImgPath)
	require.ErrorIs(t, err, os.ErrNotExist)
	_, err = os.Stat(localOGPath)
	require.ErrorIs(t, err, os.ErrNotExist)

	// Verify $ev-mixed: local url and local og:image blanked, remote thumbnail_url and remote og:image preserved,
	// and "com.courier.media_removed": true added while keeping body and msgtype.
	mixedEv, ok, err := s.GetEvent(ctx, "$ev-mixed")
	require.NoError(t, err)
	require.True(t, ok)
	var mixedContent map[string]any
	require.NoError(t, json.Unmarshal(mixedEv.Content, &mixedContent))
	require.Equal(t, "m.image", mixedContent["msgtype"])
	require.Equal(t, "Look at https://example.com", mixedContent["body"])
	require.Equal(t, "", mixedContent["url"])
	require.Equal(t, true, mixedContent["com.courier.media_removed"])

	mixedInfo, ok := mixedContent["info"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, "https://example.com/remote-thumb.png", mixedInfo["thumbnail_url"])

	mixedPreviews, ok := mixedContent["com.beeper.linkpreviews"].([]any)
	require.True(t, ok)
	require.Len(t, mixedPreviews, 2)
	lp0 := mixedPreviews[0].(map[string]any)
	lp1 := mixedPreviews[1].(map[string]any)
	require.Equal(t, "https://example.com/a.png", lp0["og:image"], "remote https og:image must be preserved")
	require.Equal(t, "", lp1["og:image"], "local blob og:image must be blanked")

	// Verify $ev-remote-only: completely untouched, keeps og:image and does not get com.courier.media_removed.
	remoteEv, ok, err := s.GetEvent(ctx, "$ev-remote-only")
	require.NoError(t, err)
	require.True(t, ok)
	var remoteContent map[string]any
	require.NoError(t, json.Unmarshal(remoteEv.Content, &remoteContent))
	_, hasRemovedFlag := remoteContent["com.courier.media_removed"]
	require.False(t, hasRemovedFlag)
	remotePreviews := remoteContent["com.beeper.linkpreviews"].([]any)
	require.Equal(t, "https://example.com/a.png", remotePreviews[0].(map[string]any)["og:image"])

	// Also verify clearEventMediaFields directly on an event with only remote URLs returns changed == false.
	unchangedRaw, changed := clearEventMediaFields(string(remoteEv.Content))
	require.False(t, changed)
	require.Equal(t, string(remoteEv.Content), unchangedRaw)
}
