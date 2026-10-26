// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// StickerItem is one sticker, custom emoji, or recent GIF entry in the local catalog.
type StickerItem struct {
	ID             string             `json:"id"`
	PackID         string             `json:"pack_id"`
	Shortcode      string             `json:"shortcode,omitempty"`
	Name           string             `json:"name"`
	Emoji          string             `json:"emoji,omitempty"`
	MediaURL       string             `json:"media_url"`
	MimeType       string             `json:"mime_type"`
	Width          int                `json:"width,omitempty"`
	Height         int                `json:"height,omitempty"`
	Usage          []string           `json:"usage"` // ["sticker"], ["emoticon"], or both
	BridgedSticker *BridgedStickerRef `json:"bridged_sticker,omitempty"`
}

// StickerPack groups stickers or custom emoji by origin ("recent", "imported", or "bridge").
type StickerPack struct {
	ID      string        `json:"id"`
	Title   string        `json:"title"`
	Source  string        `json:"source"` // "recent" | "imported" | "bridge"
	Network string        `json:"network,omitempty"`
	Items   []StickerItem `json:"items"`
}

// ListStickersResult is the response payload for stickers.list.
type ListStickersResult struct {
	Packs      []StickerPack `json:"packs"`
	RecentGIFs []StickerItem `json:"recent_gifs"`
}

// ImportStickerReq configures a local image file to import as a user sticker and/or custom emoji.
type ImportStickerReq struct {
	Path      string   `json:"path"`
	Shortcode string   `json:"shortcode,omitempty"`
	Name      string   `json:"name,omitempty"`
	Emoji     string   `json:"emoji,omitempty"`
	Usage     []string `json:"usage,omitempty"` // defaults to ["sticker"] or ["emoticon","sticker"] if Shortcode != ""
}

type stickersCatalogFile struct {
	Imported    []StickerItem `json:"imported"`
	BridgePacks []StickerPack `json:"bridge_packs,omitempty"`
}

var allowedStickerExts = map[string]bool{
	".png":  true,
	".webp": true,
	".gif":  true,
	".apng": true,
	".jpg":  true,
	".jpeg": true,
}

var allowedStickerMIMEs = map[string]bool{
	"image/png":  true,
	"image/webp": true,
	"image/gif":  true,
	"image/apng": true,
	"image/jpeg": true,
}

func normalizeMediaURL(raw string) string {
	if hash, ok := ids.ParseContentURI(id.ContentURIString(raw)); ok {
		return "courier://media/" + hash
	}
	return raw
}

func (a *Actions) stickersCatalogPath() string {
	if a.m == nil || a.m.Dir == "" {
		return ""
	}
	return filepath.Join(a.m.Dir, "stickers.json")
}

func (a *Actions) loadStickersCatalog() (stickersCatalogFile, error) {
	p := a.stickersCatalogPath()
	if p == "" {
		return stickersCatalogFile{}, nil
	}
	data, err := os.ReadFile(p)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return stickersCatalogFile{}, nil
		}
		return stickersCatalogFile{}, err
	}
	var cat stickersCatalogFile
	if err := json.Unmarshal(data, &cat); err == nil {
		return cat, nil
	}
	var items []StickerItem
	if err := json.Unmarshal(data, &items); err != nil {
		return stickersCatalogFile{}, err
	}
	return stickersCatalogFile{Imported: items}, nil
}

func (a *Actions) saveStickersCatalog(cat stickersCatalogFile) error {
	p := a.stickersCatalogPath()
	if p == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return err
	}
	if cat.Imported == nil {
		cat.Imported = []StickerItem{}
	}
	data, err := json.MarshalIndent(cat, "", "  ")
	if err != nil {
		return err
	}
	tmp := p + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// ImportSticker validates a local sticker/custom-emoji image, copies it into media.Store,
// persists it to <dataDir>/media/stickers.json, and returns the resulting StickerItem.
func (a *Actions) ImportSticker(_ context.Context, req ImportStickerReq) (StickerItem, error) {
	if strings.TrimSpace(req.Path) == "" {
		return StickerItem{}, ErrBadValue
	}
	ext := strings.ToLower(filepath.Ext(req.Path))
	if !allowedStickerExts[ext] {
		return StickerItem{}, ErrBadValue
	}

	hash, info, _, err := a.resolveMediaSource(req.Path, "", "", "", MaxFileBytes)
	if err != nil {
		return StickerItem{}, err
	}
	mimeType := info.MimeType
	if ext == ".apng" && mimeType == "image/png" {
		mimeType = "image/apng"
	}
	if !allowedStickerMIMEs[mimeType] {
		return StickerItem{}, ErrBadValue
	}

	shortcode := strings.TrimSpace(strings.Trim(req.Shortcode, ":"))
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = shortcode
	}
	if name == "" {
		name = strings.TrimSuffix(filepath.Base(req.Path), filepath.Ext(req.Path))
	}
	if name == "" {
		name = "Sticker"
	}

	var usage []string
	if len(req.Usage) > 0 {
		usage = make([]string, 0, len(req.Usage))
		for _, u := range req.Usage {
			if u != string(event.ImagePackUsageSticker) && u != string(event.ImagePackUsageEmoji) {
				return StickerItem{}, ErrBadValue
			}
			if !slices.Contains(usage, u) {
				usage = append(usage, u)
			}
		}
	} else if shortcode != "" {
		usage = []string{string(event.ImagePackUsageEmoji), string(event.ImagePackUsageSticker)}
	} else {
		usage = []string{string(event.ImagePackUsageSticker)}
	}

	itemID := "imported:" + hash
	if shortcode != "" {
		itemID = "imported:" + shortcode
	}
	item := StickerItem{
		ID:        itemID,
		PackID:    "imported",
		Shortcode: shortcode,
		Name:      name,
		Emoji:     strings.TrimSpace(req.Emoji),
		MediaURL:  "courier://media/" + hash,
		MimeType:  mimeType,
		Width:     info.Width,
		Height:    info.Height,
		Usage:     usage,
	}

	a.mu.Lock()
	defer a.mu.Unlock()
	cat, err := a.loadStickersCatalog()
	if err != nil {
		return StickerItem{}, err
	}
	replaced := false
	for i := range cat.Imported {
		if cat.Imported[i].ID == item.ID || (shortcode != "" && cat.Imported[i].Shortcode == shortcode) {
			cat.Imported[i] = item
			replaced = true
			break
		}
	}
	if !replaced {
		cat.Imported = append(cat.Imported, item)
	}
	if err := a.saveStickersCatalog(cat); err != nil {
		return StickerItem{}, err
	}
	return item, nil
}

// ListStickers returns the combined sticker/emoji catalog (recent, imported, and bridge packs) plus recent GIFs.
func (a *Actions) ListStickers(ctx context.Context, refreshBridgePacks bool) (ListStickersResult, error) {
	recentRows, err := a.s.ListRecentStickers(ctx, store.MaxRecentMediaLimit)
	if err != nil {
		return ListStickersResult{}, err
	}
	recentItems := make([]StickerItem, 0, len(recentRows))
	for _, r := range recentRows {
		name := strings.TrimSpace(r.Body)
		if name == "" {
			name = "Sticker"
		}
		var bs *BridgedStickerRef
		if r.BridgedStickerID != "" || r.BridgedPackURL != "" || r.BridgedNetwork != "" {
			bs = &BridgedStickerRef{
				Network: r.BridgedNetwork,
				PackURL: r.BridgedPackURL,
				ID:      r.BridgedStickerID,
			}
		}
		recentItems = append(recentItems, StickerItem{
			ID:             "recent:" + r.EventID,
			PackID:         "recent",
			Name:           name,
			Emoji:          r.BridgedEmoji,
			MediaURL:       normalizeMediaURL(r.URL),
			MimeType:       r.MimeType,
			Width:          r.Width,
			Height:         r.Height,
			Usage:          []string{string(event.ImagePackUsageSticker)},
			BridgedSticker: bs,
		})
	}

	a.mu.Lock()
	cat, err := a.loadStickersCatalog()
	a.mu.Unlock()
	if err != nil {
		return ListStickersResult{}, err
	}

	bridgePacks := cat.BridgePacks
	if refreshBridgePacks || len(bridgePacks) == 0 {
		fetched := a.fetchBridgeStickerPacks(ctx)
		if len(fetched) > 0 || refreshBridgePacks {
			bridgePacks = fetched
			a.mu.Lock()
			if latest, lerr := a.loadStickersCatalog(); lerr == nil {
				latest.BridgePacks = bridgePacks
				_ = a.saveStickersCatalog(latest)
			}
			a.mu.Unlock()
		}
	}

	importedItems := cat.Imported
	if importedItems == nil {
		importedItems = []StickerItem{}
	}

	packs := make([]StickerPack, 0, 2+len(bridgePacks))
	packs = append(
		packs,
		StickerPack{
			ID:     "recent",
			Title:  "Recent",
			Source: "recent",
			Items:  recentItems,
		},
		StickerPack{
			ID:     "imported",
			Title:  "Imported",
			Source: "imported",
			Items:  importedItems,
		},
	)
	packs = append(packs, bridgePacks...)

	gifRows, err := a.s.ListRecentGIFs(ctx, store.MaxRecentMediaLimit)
	if err != nil {
		return ListStickersResult{}, err
	}
	recentGIFs := make([]StickerItem, 0, len(gifRows))
	for _, g := range gifRows {
		name := strings.TrimSpace(g.Body)
		if name == "" {
			name = "GIF"
		}
		recentGIFs = append(recentGIFs, StickerItem{
			ID:       "gif:" + g.EventID,
			PackID:   "recent_gifs",
			Name:     name,
			MediaURL: normalizeMediaURL(g.URL),
			MimeType: g.MimeType,
			Width:    g.Width,
			Height:   g.Height,
			Usage:    []string{string(event.ImagePackUsageSticker)},
		})
	}

	return ListStickersResult{
		Packs:      packs,
		RecentGIFs: recentGIFs,
	}, nil
}

func (a *Actions) fetchBridgeStickerPacks(ctx context.Context) []StickerPack {
	if a.eng == nil {
		return nil
	}
	var out []StickerPack
	for _, netName := range a.eng.Names() {
		h, ok := a.eng.Host(netName)
		if !ok || h == nil {
			continue
		}
		for _, l := range myLogins(h) {
			if l == nil || l.Client == nil || !l.Client.IsLoggedIn() {
				continue
			}
			importer, ok := l.Client.(bridgev2.StickerImportingNetworkAPI)
			if !ok {
				continue
			}
			metas, err := importer.ListImagePacks(ctx)
			if err != nil {
				continue
			}
			for _, meta := range metas {
				if meta == nil {
					continue
				}
				packURL := meta.DisplayName
				if meta.BridgedPack != nil && meta.BridgedPack.URL != "" {
					packURL = meta.BridgedPack.URL
				}
				dl, err := importer.DownloadImagePack(ctx, packURL)
				if err != nil || dl == nil || dl.Content == nil {
					continue
				}
				pack := convertBridgeImagePack(netName, dl)
				if len(pack.Items) > 0 {
					out = append(out, pack)
				}
			}
		}
	}
	return out
}

func convertBridgeImagePack(defaultNetwork string, dl *bridgev2.ImportedImagePack) StickerPack {
	meta := dl.Content.Metadata
	network := defaultNetwork
	packKey := dl.Shortcode
	if meta.BridgedPack != nil {
		if meta.BridgedPack.Network != "" {
			network = meta.BridgedPack.Network
		}
		if packKey == "" {
			packKey = meta.BridgedPack.URL
		}
	}
	if packKey == "" {
		packKey = meta.DisplayName
	}
	packID := "bridge:" + network + ":" + packKey
	title := strings.TrimSpace(meta.DisplayName)
	if title == "" {
		title = packKey
	}

	usage := make([]string, 0, len(meta.Usage))
	for _, u := range meta.Usage {
		if u != "" && !slices.Contains(usage, string(u)) {
			usage = append(usage, string(u))
		}
	}
	if len(usage) == 0 {
		usage = []string{string(event.ImagePackUsageSticker)}
	}
	isEmojiPack := slices.Contains(usage, string(event.ImagePackUsageEmoji))

	keys := make([]string, 0, len(dl.Content.Images))
	for k := range dl.Content.Images {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	items := make([]StickerItem, 0, len(keys))
	for _, k := range keys {
		img := dl.Content.Images[k]
		if img == nil || img.URL == "" {
			continue
		}
		item := StickerItem{
			ID:       packID + ":" + k,
			PackID:   packID,
			Name:     k,
			MediaURL: normalizeMediaURL(string(img.URL)),
			MimeType: "image/png",
			Usage:    append([]string(nil), usage...),
		}
		if isEmojiPack {
			item.Shortcode = strings.Trim(k, ":")
		}
		if strings.TrimSpace(img.Body) != "" {
			body := strings.TrimSpace(img.Body)
			if !isEmojiPack && !strings.HasPrefix(body, ":") {
				item.Emoji = body
			}
		}
		if img.Info != nil {
			if img.Info.MimeType != "" {
				item.MimeType = img.Info.MimeType
			}
			item.Width = img.Info.Width
			item.Height = img.Info.Height
			if img.Info.BridgedSticker != nil {
				bsNet := img.Info.BridgedSticker.Network
				if bsNet == "" {
					bsNet = network
				}
				item.BridgedSticker = &BridgedStickerRef{
					Network: bsNet,
					PackURL: img.Info.BridgedSticker.PackURL,
					ID:      img.Info.BridgedSticker.ID,
				}
				if item.Emoji == "" && img.Info.BridgedSticker.Emoji != "" {
					item.Emoji = img.Info.BridgedSticker.Emoji
				}
			}
		}
		items = append(items, item)
	}

	return StickerPack{
		ID:      packID,
		Title:   title,
		Source:  "bridge",
		Network: network,
		Items:   items,
	}
}
