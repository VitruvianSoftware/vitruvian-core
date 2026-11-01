// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

type RoomStorageUsage struct {
	RoomID     string `json:"room_id"`
	Name       string `json:"name"`
	Network    string `json:"network"`
	MediaBytes int64  `json:"media_bytes"`
	ItemCount  int    `json:"item_count"`
}

type StorageUsage struct {
	TotalBytes           int64              `json:"total_bytes"`
	DatabaseBytes        int64              `json:"database_bytes"`
	PhotosAndVideosBytes int64              `json:"photos_and_videos_bytes"`
	AudioBytes           int64              `json:"audio_bytes"`
	FilesBytes           int64              `json:"files_bytes"`
	StickersBytes        int64              `json:"stickers_bytes"`
	OtherMediaBytes      int64              `json:"other_media_bytes"`
	Rooms                []RoomStorageUsage `json:"rooms"`
}

type StorageCleanupFilter struct {
	RoomIDs         []string `json:"room_ids,omitempty"`
	OlderThanMS     int64    `json:"older_than_ms,omitempty"`
	IncludeStickers bool     `json:"include_stickers,omitempty"`
}

type StorageCleanupReport struct {
	FreedBytes   int64 `json:"freed_bytes"`
	RemovedBlobs int   `json:"removed_blobs"`
}

type storageCatalogEntry struct {
	ID        string `json:"id"`
	PackID    string `json:"pack_id"`
	Name      string `json:"name"`
	Shortcode string `json:"shortcode,omitempty"`
	Emoji     string `json:"emoji,omitempty"`
	MediaURL  string `json:"media_url"`
	MimeType  string `json:"mime_type"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	Usage     any    `json:"usage,omitempty"`
	AddedTS   int64  `json:"added_ts"`
}

type storageCatalogPack struct {
	ID       string                `json:"id"`
	Name     string                `json:"name"`
	Network  string                `json:"network"`
	Stickers []storageCatalogEntry `json:"stickers"`
}

type storageCatalogFile struct {
	Imported    []storageCatalogEntry `json:"imported"`
	BridgePacks []storageCatalogPack  `json:"bridge_packs"`
}

func isHex64(s string) bool {
	if len(s) != 64 {
		return false
	}
	for i := range len(s) {
		c := s[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

func parseStorageMediaHash(uri string) (string, bool) {
	uri = strings.TrimSpace(uri)
	if uri == "" {
		return "", false
	}
	if hash, ok := ids.ParseContentURI(id.ContentURIString(uri)); ok {
		return hash, true
	}
	if rest, ok := strings.CutPrefix(uri, "courier://media/"); ok && isHex64(rest) {
		return rest, true
	}
	if isHex64(uri) {
		return uri, true
	}
	return "", false
}

func parseEventStorageMedia(evtType string, rawContent string) (category string, hashes []string) {
	var c struct {
		MsgType string `json:"msgtype"`
		URL     string `json:"url"`
		Info    *struct {
			ThumbnailURL string `json:"thumbnail_url"`
		} `json:"info"`
		LinkPreviews []struct {
			OGImage string `json:"og:image"`
		} `json:"com.beeper.linkpreviews"`
	}
	if json.Unmarshal([]byte(rawContent), &c) != nil {
		return "", nil
	}
	switch {
	case evtType == "m.sticker" || c.MsgType == "m.sticker":
		category = "sticker"
	case evtType == "m.room.message":
		switch c.MsgType {
		case "m.image", "m.video":
			category = "photos_and_videos"
		case "m.audio":
			category = "audio"
		case "m.file":
			category = "files"
		default:
			category = "other"
		}
	default:
		category = "other"
	}

	addURI := func(u string) {
		if h, ok := parseStorageMediaHash(u); ok && !slices.Contains(hashes, h) {
			hashes = append(hashes, h)
		}
	}
	addURI(c.URL)
	if c.Info != nil {
		addURI(c.Info.ThumbnailURL)
	}
	for _, lp := range c.LinkPreviews {
		addURI(lp.OGImage)
	}
	return category, hashes
}

func loadStickerCatalogHashes(mediaDir string) (userHashes map[string]bool, bridgeHashes map[string]int64) {
	userHashes = map[string]bool{}
	bridgeHashes = map[string]int64{}
	if mediaDir == "" {
		return userHashes, bridgeHashes
	}
	raw, err := os.ReadFile(filepath.Join(mediaDir, "stickers.json"))
	if err != nil {
		return userHashes, bridgeHashes
	}
	var cat storageCatalogFile
	if json.Unmarshal(raw, &cat) != nil {
		return userHashes, bridgeHashes
	}
	for _, item := range cat.Imported {
		if h, ok := parseStorageMediaHash(item.MediaURL); ok {
			userHashes[h] = true
		}
	}
	for _, pack := range cat.BridgePacks {
		for _, item := range pack.Stickers {
			h, ok := parseStorageMediaHash(item.MediaURL)
			if !ok {
				continue
			}
			if item.PackID == "user" || item.PackID == "imported" || pack.ID == "user" || pack.ID == "imported" {
				userHashes[h] = true
			} else {
				bridgeHashes[h] = item.AddedTS
			}
		}
	}
	return userHashes, bridgeHashes
}

// StorageUsage walks events, stickers, the media blob store, and the SQLite database files to compute
// Courier's storage breakdown by category and per room.
func (s *Store) StorageUsage(ctx context.Context, dbPath string) (StorageUsage, error) {
	if dbPath == "" {
		dbPath = s.dbPath
	}
	out := StorageUsage{
		Rooms: []RoomStorageUsage{},
	}
	if dbPath != "" {
		for _, suffix := range []string{"", "-wal", "-shm"} {
			if info, err := os.Stat(dbPath + suffix); err == nil && !info.IsDir() {
				out.DatabaseBytes += info.Size()
			}
		}
	}

	ms := s.getMediaStore()
	blobSizes := map[string]int64{}
	var unhashedMediaBytes int64
	if ms != nil && ms.Dir != "" {
		_ = filepath.WalkDir(ms.Dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			name := d.Name()
			if name == "stickers.json" || strings.HasPrefix(name, ".tmp-") {
				return nil
			}
			info, statErr := d.Info()
			if statErr != nil {
				return nil
			}
			if isHex64(name) {
				blobSizes[name] = info.Size()
			} else {
				unhashedMediaBytes += info.Size()
			}
			return nil
		})
	}

	blobCategory := map[string]string{}
	if ms != nil && ms.Dir != "" {
		userHashes, bridgeHashes := loadStickerCatalogHashes(ms.Dir)
		for h := range userHashes {
			if _, exists := blobSizes[h]; exists {
				blobCategory[h] = "sticker"
			}
		}
		for h := range bridgeHashes {
			if _, exists := blobSizes[h]; exists {
				blobCategory[h] = "sticker"
			}
		}
	}

	roomMap := map[string]*RoomStorageUsage{}
	roomSeenHashes := map[string]map[string]bool{}
	roomRows, err := s.db.Query(ctx, `
		SELECT r.room_id, COALESCE(NULLIF(p.local_name, ''), r.name), r.network
		FROM rooms r
		LEFT JOIN room_prefs p ON p.room_id = r.room_id
		WHERE r.is_space = 0
	`)
	if err != nil {
		return out, err
	}
	for roomRows.Next() {
		var roomID, name, network string
		if err := roomRows.Scan(&roomID, &name, &network); err != nil {
			roomRows.Close()
			return out, err
		}
		roomMap[roomID] = &RoomStorageUsage{
			RoomID:  roomID,
			Name:    name,
			Network: network,
		}
		roomSeenHashes[roomID] = map[string]bool{}
	}
	if err := roomRows.Close(); err != nil {
		return out, err
	}

	evRows, err := s.db.Query(ctx, `
		SELECT room_id, type, content
		FROM events
		WHERE redacted = 0 AND deleted_for_me = 0
		ORDER BY ts ASC, seq ASC
	`)
	if err != nil {
		return out, err
	}
	for evRows.Next() {
		var roomID, evtType, rawContent string
		if err := evRows.Scan(&roomID, &evtType, &rawContent); err != nil {
			evRows.Close()
			return out, err
		}
		cat, hashes := parseEventStorageMedia(evtType, rawContent)
		if len(hashes) == 0 {
			continue
		}
		hasOnDiskBlob := false
		for _, h := range hashes {
			size, ok := blobSizes[h]
			if !ok {
				continue
			}
			hasOnDiskBlob = true
			if blobCategory[h] == "" {
				blobCategory[h] = cat
			}
			if rm := roomMap[roomID]; rm != nil {
				if !roomSeenHashes[roomID][h] {
					roomSeenHashes[roomID][h] = true
					rm.MediaBytes += size
				}
			}
		}
		if hasOnDiskBlob {
			if rm := roomMap[roomID]; rm != nil {
				rm.ItemCount++
			}
		}
	}
	if err := evRows.Close(); err != nil {
		return out, err
	}

	for h, size := range blobSizes {
		switch blobCategory[h] {
		case "photos_and_videos":
			out.PhotosAndVideosBytes += size
		case "audio":
			out.AudioBytes += size
		case "files":
			out.FilesBytes += size
		case "sticker":
			out.StickersBytes += size
		default:
			out.OtherMediaBytes += size
		}
	}
	out.OtherMediaBytes += unhashedMediaBytes
	out.TotalBytes = out.DatabaseBytes +
		out.PhotosAndVideosBytes +
		out.AudioBytes +
		out.FilesBytes +
		out.StickersBytes +
		out.OtherMediaBytes

	for _, rm := range roomMap {
		out.Rooms = append(out.Rooms, *rm)
	}
	slices.SortFunc(out.Rooms, func(a, b RoomStorageUsage) int {
		if a.MediaBytes != b.MediaBytes {
			if a.MediaBytes > b.MediaBytes {
				return -1
			}
			return 1
		}
		return strings.Compare(a.RoomID, b.RoomID)
	})
	return out, nil
}

func clearEventMediaFields(rawContent string) (string, bool) {
	var m map[string]any
	if json.Unmarshal([]byte(rawContent), &m) != nil {
		return rawContent, false
	}
	changed := false
	if u, ok := m["url"].(string); ok && u != "" {
		m["url"] = ""
		changed = true
	}
	if info, ok := m["info"].(map[string]any); ok {
		if tu, ok := info["thumbnail_url"].(string); ok && tu != "" {
			info["thumbnail_url"] = ""
			changed = true
		}
	}
	if lps, ok := m["com.beeper.linkpreviews"].([]any); ok {
		for _, item := range lps {
			if lp, ok := item.(map[string]any); ok {
				if img, ok := lp["og:image"].(string); ok && img != "" {
					lp["og:image"] = ""
					changed = true
				}
			}
		}
	}
	if !changed {
		return rawContent, false
	}
	encoded, err := json.Marshal(m)
	if err != nil {
		return rawContent, false
	}
	return string(encoded), true
}

// CleanupStorage clears media_path and thumbnail_path references on matching events (keeping message rows
// and text intact) and deletes unreferenced blob files from media.Store while preserving blobs still
// referenced by other events or user-imported stickers (pack_id = 'user').
func (s *Store) CleanupStorage(ctx context.Context, filter StorageCleanupFilter) (StorageCleanupReport, error) {
	var report StorageCleanupReport
	ms := s.getMediaStore()

	var userStickerHashes map[string]bool
	var bridgeStickerHashes map[string]int64
	if ms != nil && ms.Dir != "" {
		userStickerHashes, bridgeStickerHashes = loadStickerCatalogHashes(ms.Dir)
	} else {
		userStickerHashes = map[string]bool{}
		bridgeStickerHashes = map[string]int64{}
	}

	roomAllowed := map[string]bool{}
	for _, r := range filter.RoomIDs {
		if r != "" {
			roomAllowed[r] = true
		}
	}

	rows, err := s.db.Query(ctx, `
		SELECT event_id, room_id, type, content, ts
		FROM events
		WHERE redacted = 0 AND deleted_for_me = 0
	`)
	if err != nil {
		return report, err
	}

	type eventUpdate struct {
		eventID    string
		newContent string
	}
	var updates []eventUpdate
	candidateHashes := map[string]bool{}

	for rows.Next() {
		var eventID, roomID, evtType, rawContent string
		var ts int64
		if err := rows.Scan(&eventID, &roomID, &evtType, &rawContent, &ts); err != nil {
			rows.Close()
			return report, err
		}
		if len(roomAllowed) > 0 && !roomAllowed[roomID] {
			continue
		}
		if filter.OlderThanMS > 0 && ts >= filter.OlderThanMS {
			continue
		}
		cat, hashes := parseEventStorageMedia(evtType, rawContent)
		if len(hashes) == 0 {
			continue
		}
		if cat == "sticker" && !filter.IncludeStickers {
			continue
		}
		for _, h := range hashes {
			candidateHashes[h] = true
		}
		if updatedContent, ok := clearEventMediaFields(rawContent); ok {
			updates = append(updates, eventUpdate{
				eventID:    eventID,
				newContent: updatedContent,
			})
		}
	}
	if err := rows.Close(); err != nil {
		return report, err
	}

	for _, u := range updates {
		if _, err := s.db.Exec(ctx, `UPDATE events SET content = ? WHERE event_id = ?`, u.newContent, u.eventID); err != nil {
			return report, err
		}
	}

	if filter.IncludeStickers && len(roomAllowed) == 0 {
		for h, addedTS := range bridgeStickerHashes {
			if filter.OlderThanMS <= 0 || addedTS == 0 || addedTS < filter.OlderThanMS {
				candidateHashes[h] = true
			}
		}
	}

	if ms == nil || ms.Dir == "" || len(candidateHashes) == 0 {
		return report, nil
	}

	// Scan remaining events to find any hashes still referenced.
	stillReferenced := map[string]bool{}
	for h := range userStickerHashes {
		stillReferenced[h] = true
	}
	if !filter.IncludeStickers {
		for h := range bridgeStickerHashes {
			stillReferenced[h] = true
		}
	}

	remRows, err := s.db.Query(ctx, `
		SELECT type, content
		FROM events
		WHERE redacted = 0 AND deleted_for_me = 0
	`)
	if err != nil {
		return report, err
	}
	for remRows.Next() {
		var evtType, rawContent string
		if err := remRows.Scan(&evtType, &rawContent); err != nil {
			remRows.Close()
			return report, err
		}
		_, hashes := parseEventStorageMedia(evtType, rawContent)
		for _, h := range hashes {
			stillReferenced[h] = true
		}
	}
	if err := remRows.Close(); err != nil {
		return report, err
	}

	sortedCandidates := make([]string, 0, len(candidateHashes))
	for h := range candidateHashes {
		sortedCandidates = append(sortedCandidates, h)
	}
	slices.Sort(sortedCandidates)

	for _, h := range sortedCandidates {
		if stillReferenced[h] {
			continue
		}
		path, err := ms.Path(h)
		if err != nil {
			continue
		}
		info, err := os.Stat(path)
		if err != nil || info.IsDir() {
			continue
		}
		size := info.Size()
		if err := ms.Delete(h); err == nil {
			report.FreedBytes += size
			report.RemovedBlobs++
		}
	}

	return report, nil
}
