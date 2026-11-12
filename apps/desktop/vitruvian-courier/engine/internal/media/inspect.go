// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"

	_ "golang.org/x/image/webp"
)

// MaxInspectBytes bounds how many bytes InspectImage reads from a stream so
// an oversized or corrupt file fails that one inspection rather than the engine.
const MaxInspectBytes int64 = 32 * 1024 * 1024

type Metadata struct {
	Width      int
	Height     int
	BlurHash   string
	IsAnimated bool
}

// InspectImage decodes dimensions and computes a 4x3 BlurHash for JPEG, PNG, GIF (detecting multi-frame GIFs), and WebP.
func InspectImage(r io.Reader) (Metadata, error) {
	if r == nil {
		return Metadata{}, errors.New("nil image reader")
	}
	data, err := io.ReadAll(io.LimitReader(r, MaxInspectBytes+1))
	if err != nil {
		return Metadata{}, err
	}
	if len(data) == 0 {
		return Metadata{}, errors.New("empty image")
	}
	if int64(len(data)) > MaxInspectBytes {
		return Metadata{}, fmt.Errorf("image exceeds maximum inspection size (%d bytes)", MaxInspectBytes)
	}

	if bytes.HasPrefix(data, []byte("GIF87a")) || bytes.HasPrefix(data, []byte("GIF89a")) {
		g, err := gif.DecodeAll(bytes.NewReader(data))
		if err != nil {
			return Metadata{}, err
		}
		if len(g.Image) == 0 {
			return Metadata{}, errors.New("gif contains no frames")
		}
		first := g.Image[0]
		w, h := g.Config.Width, g.Config.Height
		if w <= 0 || h <= 0 {
			w, h = first.Bounds().Dx(), first.Bounds().Dy()
		}
		return Metadata{
			Width:      w,
			Height:     h,
			BlurHash:   EncodeBlurHash(first),
			IsAnimated: len(g.Image) > 1,
		}, nil
	}

	img, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return Metadata{}, err
	}
	b := img.Bounds()
	isAnimated := false
	if format == "webp" && len(data) >= 21 && string(data[12:16]) == "VP8X" && data[20]&0x02 != 0 {
		isAnimated = true
	}
	return Metadata{
		Width:      b.Dx(),
		Height:     b.Dy(),
		BlurHash:   EncodeBlurHash(img),
		IsAnimated: isAnimated,
	}, nil
}
