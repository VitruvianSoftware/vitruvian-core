// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"image"
	"image/color"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEncodeBlurHashDownsamplesAndFormats4x3(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 128, 96))
	for y := 0; y < 96; y++ {
		for x := 0; x < 128; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 2), G: uint8(y * 2), B: 140, A: 255})
		}
	}
	hash := EncodeBlurHash(img)
	require.NotEmpty(t, hash)
	// 4x3 components: 1 (size flag) + 1 (max AC) + 4 (DC) + 11*2 (AC) = 28 chars.
	require.Len(t, hash, 28)
	require.Equal(t, byte('L'), hash[0], "4x3 components encode size flag (4-1) + (3-1)*9 = 21 ('L' in base83)")
}
