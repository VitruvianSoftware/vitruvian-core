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
	"time"

	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
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

// DefaultMediaPutGrace is how long before a storage clean-up a blob must have been written for the clean-up to
// delete it. A message that arrives during a clean-up writes its file first and its row a moment later, possibly
// after the clean-up's transaction; the grace keeps that file.
const DefaultMediaPutGrace = time.Minute

// SetMediaPutGrace sets the grace (DefaultMediaPutGrace). Tests that write blobs just before a clean-up set 0.
func (s *Store) SetMediaPutGrace(d time.Duration) {
	s.cfgMu.Lock()
	s.mediaPutGrace = d
	s.cfgMu.Unlock()
}

type StorageCleanupReport struct {
	FreedBytes   int64 `json:"freed_bytes"`
	RemovedBlobs int   `json:"removed_blobs"`
}

// The sticker catalog (media/stickers.json) as package actions writes it (stickersCatalogFile, StickerPack and
// StickerItem in actions/stickers.go); only the fields the storage pages need, with the same JSON names. actions
// imports store, so store can't use those types directly; TestStorageCleanupReadsTheStickerCatalogTheActionsWrite
// keeps the two in step.
type storageCatalogItem struct {
	MediaURL string `json:"media_url"`
}

type storageCatalogPack struct {
	Items []storageCatalogItem `json:"items"`
}

type storageCatalogFile struct {
	Imported            []storageCatalogItem `json:"imported"`
	BridgePacks         []storageCatalogPack `json:"bridge_packs"`
	BridgePacksSyncedAt int64                `json:"bridge_packs_synced_at"` // Unix ms
}

// storageStickers is what the catalog says about blobs: the imported stickers' (never deleted), the synced packs'
// (cache), and when the packs were synced (Unix ms; 0 = unknown).
type storageStickers struct {
	imported, bridge map[string]bool
	syncedAtMS       int64
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

func loadStickerCatalog(ms *media.Store) storageStickers {
	out := storageStickers{imported: map[string]bool{}, bridge: map[string]bool{}}
	if ms == nil || ms.Dir == "" {
		return out
	}
	raw, err := os.ReadFile(filepath.Join(ms.Dir, "stickers.json"))
	if err != nil {
		return out
	}
	var cat storageCatalogFile
	if json.Unmarshal(raw, &cat) != nil {
		// The oldest catalog was a bare list of imported stickers (actions.loadStickersCatalog reads it the same way).
		var items []storageCatalogItem
		if json.Unmarshal(raw, &items) != nil {
			return out
		}
		cat = storageCatalogFile{Imported: items}
	}
	for _, item := range cat.Imported {
		if h, ok := parseStorageMediaHash(item.MediaURL); ok {
			out.imported[h] = true
		}
	}
	for _, pack := range cat.BridgePacks {
		for _, item := range pack.Items {
			if h, ok := parseStorageMediaHash(item.MediaURL); ok && !out.imported[h] {
				out.bridge[h] = true
			}
		}
	}
	out.syncedAtMS = cat.BridgePacksSyncedAt
	return out
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
		stickers := loadStickerCatalog(ms)
		for _, hashes := range []map[string]bool{stickers.imported, stickers.bridge} {
			for h := range hashes {
				if _, exists := blobSizes[h]; exists {
					blobCategory[h] = "sticker"
				}
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
	if u, ok := m["url"].(string); ok {
		if _, isLocal := parseStorageMediaHash(u); isLocal {
			m["url"] = ""
			changed = true
		}
	}
	if info, ok := m["info"].(map[string]any); ok {
		if tu, ok := info["thumbnail_url"].(string); ok {
			if _, isLocal := parseStorageMediaHash(tu); isLocal {
				info["thumbnail_url"] = ""
				changed = true
			}
		}
	}
	if lps, ok := m["com.beeper.linkpreviews"].([]any); ok {
		for _, item := range lps {
			if lp, ok := item.(map[string]any); ok {
				if img, ok := lp["og:image"].(string); ok {
					if _, isLocal := parseStorageMediaHash(img); isLocal {
						lp["og:image"] = ""
						changed = true
					}
				}
			}
		}
	}
	if !changed {
		return rawContent, false
	}
	m["com.courier.media_removed"] = true
	encoded, err := json.Marshal(m)
	if err != nil {
		return rawContent, false
	}
	return string(encoded), true
}

// CleanupStorage deletes local media references on matching events (keeping message rows and text intact,
// leaving remote URLs untouched, and stamping com.courier.media_removed = true) and deletes the blob files nothing
// else uses. filter.OlderThanMS is a duration: only messages older than that, back from now, lose their media. A blob
// stays while another message, a message waiting to be sent later, or an imported sticker uses it, and so does one
// written within the media put grace before the clean-up (a message arriving during it). Synced pack stickers go
// only with IncludeStickers. A room ID that isn't a chat (a merged chat's ID included) is ErrNotFound, and nothing
// changes. Reading, rewriting and checking what is still used happen in one write transaction, and the files are
// deleted inside it, so no message can start using a blob between the check and the delete. When messages were
// rewritten the change feed gets a ChangeResync, so open chats re-read them.
func (s *Store) CleanupStorage(ctx context.Context, filter StorageCleanupFilter) (StorageCleanupReport, error) {
	var report StorageCleanupReport
	ms := s.getMediaStore()
	stickers := loadStickerCatalog(ms)
	s.cfgMu.RLock()
	grace, beforeDelete := s.mediaPutGrace, s.storageCleanupBeforeDelete
	s.cfgMu.RUnlock()
	putSince := time.Now().Add(-grace)

	roomAllowed := map[string]bool{}
	for _, r := range filter.RoomIDs {
		if r != "" {
			roomAllowed[r] = true
		}
	}
	var cutoffMS int64 // messages at or after it keep their media; 0 = no age limit
	if filter.OlderThanMS > 0 {
		cutoffMS = s.now().UnixMilli() - filter.OlderThanMS
	}

	rewrote := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		report, rewrote = StorageCleanupReport{}, false
		for r := range roomAllowed {
			ok, err := s.roomExists(ctx, r)
			if err != nil {
				return err
			}
			if !ok {
				return ErrNotFound
			}
		}

		rows, err := s.db.Query(ctx, `
			SELECT event_id, room_id, type, content, ts
			FROM events
			WHERE redacted = 0 AND deleted_for_me = 0
		`)
		if err != nil {
			return err
		}
		type eventUpdate struct{ eventID, newContent string }
		var updates []eventUpdate
		candidateHashes := map[string]bool{}
		for rows.Next() {
			var eventID, roomID, evtType, rawContent string
			var ts int64
			if err := rows.Scan(&eventID, &roomID, &evtType, &rawContent, &ts); err != nil {
				rows.Close()
				return err
			}
			if len(roomAllowed) > 0 && !roomAllowed[roomID] {
				continue
			}
			if cutoffMS != 0 && ts >= cutoffMS {
				continue
			}
			cat, hashes := parseEventStorageMedia(evtType, rawContent)
			if len(hashes) == 0 || cat == "sticker" && !filter.IncludeStickers {
				continue
			}
			for _, h := range hashes {
				candidateHashes[h] = true
			}
			if updatedContent, ok := clearEventMediaFields(rawContent); ok {
				updates = append(updates, eventUpdate{eventID: eventID, newContent: updatedContent})
			}
		}
		if err := rows.Close(); err != nil {
			return err
		}
		for _, u := range updates {
			if _, err := s.db.Exec(ctx, `UPDATE events SET content = $1 WHERE event_id = $2`, u.newContent, u.eventID); err != nil {
				return err
			}
		}
		rewrote = len(updates) > 0

		if filter.IncludeStickers && len(roomAllowed) == 0 &&
			(cutoffMS == 0 || stickers.syncedAtMS == 0 || stickers.syncedAtMS < cutoffMS) {
			for h := range stickers.bridge {
				candidateHashes[h] = true
			}
		}
		if ms == nil || ms.Dir == "" || len(candidateHashes) == 0 {
			return nil
		}

		// What is still used: imported stickers, synced pack stickers unless they are being cleaned, every message
		// left, and every message waiting to be sent later (or canceled or missed, which can be set to wait again).
		stillReferenced := map[string]bool{}
		for h := range stickers.imported {
			stillReferenced[h] = true
		}
		if !filter.IncludeStickers {
			for h := range stickers.bridge {
				stillReferenced[h] = true
			}
		}
		for _, query := range []string{
			`SELECT type, content FROM events WHERE redacted = 0 AND deleted_for_me = 0`,
			`SELECT type, content FROM outbox WHERE kind = '` + outboxLater + `'`,
		} {
			remRows, err := s.db.Query(ctx, query)
			if err != nil {
				return err
			}
			for remRows.Next() {
				var evtType, rawContent string
				if err := remRows.Scan(&evtType, &rawContent); err != nil {
					remRows.Close()
					return err
				}
				_, hashes := parseEventStorageMedia(evtType, rawContent)
				for _, h := range hashes {
					stillReferenced[h] = true
				}
			}
			if err := remRows.Close(); err != nil {
				return err
			}
		}

		if beforeDelete != nil {
			beforeDelete()
		}
		sortedCandidates := make([]string, 0, len(candidateHashes))
		for h := range candidateHashes {
			if !stillReferenced[h] {
				sortedCandidates = append(sortedCandidates, h)
			}
		}
		slices.Sort(sortedCandidates)
		for _, h := range sortedCandidates {
			path, err := ms.Path(h)
			if err != nil {
				continue
			}
			info, err := os.Stat(path)
			if err != nil || info.IsDir() {
				continue
			}
			if deleted, err := ms.DeleteUnlessPutSince(h, putSince); err == nil && deleted {
				report.FreedBytes += info.Size()
				report.RemovedBlobs++
			}
		}
		return nil
	})
	if err != nil {
		return StorageCleanupReport{}, err
	}
	if rewrote {
		s.publish(Change{Kind: ChangeResync})
	}
	return report, nil
}
