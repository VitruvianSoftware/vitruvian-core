// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"bytes"
	"image"
	"image/color"
	"image/gif"
	"image/png"
	"io"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEncodeBlurHashAndInspectImage(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 64, 48))
	for y := 0; y < 48; y++ {
		for x := 0; x < 64; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 3), G: uint8(y * 4), B: 120, A: 255})
		}
	}
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))

	meta, err := InspectImage(bytes.NewReader(pngBuf.Bytes()))
	require.NoError(t, err)
	require.Equal(t, 64, meta.Width)
	require.Equal(t, 48, meta.Height)
	require.NotEmpty(t, meta.BlurHash)
	require.GreaterOrEqual(t, len(meta.BlurHash), 6)
	require.False(t, meta.IsAnimated)

	// Multi-frame GIF sets IsAnimated = true.
	pal := color.Palette{color.Black, color.White}
	f1 := image.NewPaletted(image.Rect(0, 0, 16, 16), pal)
	f2 := image.NewPaletted(image.Rect(0, 0, 16, 16), pal)
	var gifBuf bytes.Buffer
	require.NoError(t, gif.EncodeAll(&gifBuf, &gif.GIF{
		Image: []*image.Paletted{f1, f2},
		Delay: []int{10, 10},
	}))
	gifMeta, err := InspectImage(bytes.NewReader(gifBuf.Bytes()))
	require.NoError(t, err)
	require.Equal(t, 16, gifMeta.Width)
	require.Equal(t, 16, gifMeta.Height)
	require.True(t, gifMeta.IsAnimated)
	require.NotEmpty(t, gifMeta.BlurHash)
}

func TestInspectImageTruncatedFailsCleanly(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))
	truncated := pngBuf.Bytes()[:len(pngBuf.Bytes())/2]

	_, err := InspectImage(bytes.NewReader(truncated))
	require.Error(t, err, "a truncated PNG must fail inspection cleanly")

	pal := color.Palette{color.Black, color.White}
	f1 := image.NewPaletted(image.Rect(0, 0, 16, 16), pal)
	var gifBuf bytes.Buffer
	require.NoError(t, gif.EncodeAll(&gifBuf, &gif.GIF{
		Image: []*image.Paletted{f1},
		Delay: []int{10},
	}))
	truncatedGIF := gifBuf.Bytes()[:len(gifBuf.Bytes())/2]
	_, err = InspectImage(bytes.NewReader(truncatedGIF))
	require.Error(t, err, "a truncated GIF must fail inspection cleanly")
}

func TestInspectImageZeroByteFailsCleanly(t *testing.T) {
	_, err := InspectImage(bytes.NewReader(nil))
	require.Error(t, err, "a zero-byte file must fail inspection cleanly")
}

type endlessZeroReader struct{}

func (endlessZeroReader) Read(p []byte) (int, error) {
	clear(p)
	return len(p), nil
}

func TestInspectImageOverSizeLimitFailsCleanly(t *testing.T) {
	_, err := InspectImage(io.LimitReader(endlessZeroReader{}, MaxInspectBytes+1024))
	require.Error(t, err, "a stream exceeding MaxInspectBytes must fail inspection cleanly")
}
