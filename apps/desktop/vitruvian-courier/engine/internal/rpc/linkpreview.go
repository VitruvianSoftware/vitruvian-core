// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/actions"
)

// linkPreviewImageResult is linkPreview.image's answer: the picture saved on this Mac, or nothing when the page has none.
type linkPreviewImageResult struct {
	ImagePath   string `json:"image_path,omitempty"`
	ImageWidth  int    `json:"image_width,omitempty"`
	ImageHeight int    `json:"image_height,omitempty"`
	Blurhash    string `json:"blurhash,omitempty"`
}

func linkPreviewImage(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		URL *string `json:"url"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("url", p.URL); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	img, err := d.Actions.PreviewImageForURL(ctx, *p.URL)
	if errors.Is(err, actions.ErrBadPreviewURL) {
		return nil, invalidParams("url must be an https address")
	}
	if err != nil {
		return nil, err
	}
	return linkPreviewImageResult{
		ImagePath: img.ImagePath, ImageWidth: img.ImageWidth,
		ImageHeight: img.ImageHeight, Blurhash: img.BlurHash,
	}, nil
}
