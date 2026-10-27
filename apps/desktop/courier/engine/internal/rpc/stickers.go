// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"path/filepath"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
)

func stickersList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RefreshBridgePacks bool `json:"refresh_bridge_packs"`
	}
	if len(raw) > 0 && string(raw) != "null" {
		if err := decode(raw, &p); err != nil {
			return nil, err
		}
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return d.Actions.ListStickers(ctx, p.RefreshBridgePacks)
}

func stickersImport(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Path      *string  `json:"path"`
		Shortcode string   `json:"shortcode"`
		Name      string   `json:"name"`
		Emoji     string   `json:"emoji"`
		Usage     []string `json:"usage"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("path", p.Path); err != nil {
		return nil, err
	}
	if !filepath.IsAbs(*p.Path) {
		return nil, invalidParams("path must be an absolute path")
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	item, err := d.Actions.ImportSticker(ctx, actions.ImportStickerReq{
		Path:      *p.Path,
		Shortcode: p.Shortcode,
		Name:      p.Name,
		Emoji:     p.Emoji,
		Usage:     p.Usage,
	})
	if errors.Is(err, fs.ErrNotExist) || errors.Is(err, fs.ErrPermission) {
		return nil, invalidParams("path is not a file that can be read")
	}
	if err != nil {
		return nil, err
	}
	return item, nil
}
