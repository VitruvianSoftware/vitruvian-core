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

// MaxInspectPixels is the most pixels (width times height) InspectImage decodes: 50 megapixels, a big camera photo.
// Decoding allocates every pixel, so a few hundred bytes of PNG header claiming 20000 x 20000 would take hundreds of
// megabytes; the size is read from the header first and refused above this.
const MaxInspectPixels int64 = 50_000_000

// MaxInspectDimension is the longest side InspectImage decodes, in pixels: no picture is a strip this long.
const MaxInspectDimension = 30000

// MaxLinkPreviewPixels is the most pixels a link card's picture may claim: 16 megapixels. Pages and chat networks size
// these pictures for a card (a typical one is about 1200 x 630), so a bigger one is refused before it is decoded rather
// than spending the hundreds of megabytes a picture near MaxInspectPixels takes.
const MaxLinkPreviewPixels int64 = 16_000_000

// ErrImageTooLarge means a picture's header claims more pixels than InspectImage decodes.
var ErrImageTooLarge = errors.New("image is too large to decode")

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

	// The size comes from the header alone, before anything is allocated for the pixels.
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return Metadata{}, err
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > MaxInspectDimension || cfg.Height > MaxInspectDimension ||
		int64(cfg.Width)*int64(cfg.Height) > MaxInspectPixels {
		return Metadata{}, fmt.Errorf("%w: %d x %d", ErrImageTooLarge, cfg.Width, cfg.Height)
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

// InspectLinkPreviewImage is InspectImage for a link card's picture: it refuses one whose header claims more than
// MaxLinkPreviewPixels, before anything is allocated for the pixels.
func InspectLinkPreviewImage(data []byte) (Metadata, error) {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return Metadata{}, err
	}
	if int64(cfg.Width)*int64(cfg.Height) > MaxLinkPreviewPixels {
		return Metadata{}, fmt.Errorf("%w: %d x %d", ErrImageTooLarge, cfg.Width, cfg.Height)
	}
	return InspectImage(bytes.NewReader(data))
}
