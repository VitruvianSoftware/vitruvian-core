// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/color"
	"image/gif"
	"image/png"
	"io"
	"runtime"
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

// pngChunk is one PNG chunk: length, type, data, CRC.
func pngChunk(kind string, data []byte) []byte {
	out := binary.BigEndian.AppendUint32(nil, uint32(len(data)))
	out = append(out, kind...)
	out = append(out, data...)
	return binary.BigEndian.AppendUint32(out, crc32.ChecksumIEEE(append([]byte(kind), data...)))
}

// grayPNGClaiming is a grayscale PNG whose header says width x height. With rows, its pixels are really there (all
// zero, so it compresses to a few kilobytes); without, it has the header and no pixel data at all.
func grayPNGClaiming(t *testing.T, width, height uint32, rows bool) []byte {
	t.Helper()
	ihdr := binary.BigEndian.AppendUint32(nil, width)
	ihdr = binary.BigEndian.AppendUint32(ihdr, height)
	ihdr = append(ihdr, 8, 0, 0, 0, 0) // 8 bits, grayscale, no interlace
	out := append([]byte("\x89PNG\r\n\x1a\n"), pngChunk("IHDR", ihdr)...)
	if rows {
		var z bytes.Buffer
		zw := zlib.NewWriter(&z)
		row := make([]byte, int(width)+1) // filter byte 0, then zero pixels
		for y := uint32(0); y < height; y++ {
			_, err := zw.Write(row)
			require.NoError(t, err)
		}
		require.NoError(t, zw.Close())
		out = append(out, pngChunk("IDAT", z.Bytes())...)
	}
	return append(out, pngChunk("IEND", nil)...)
}

// A picture that claims a huge size is refused from its header, before the pixels are allocated: a 389 KB PNG that
// says 20000 x 20000 once took 383 MiB to decode.
func TestInspectImageRefusesAPictureThatClaimsTooManyPixels(t *testing.T) {
	for _, tc := range []struct {
		name string
		data []byte
	}{
		{"20000 x 20000 header only", grayPNGClaiming(t, 20000, 20000, false)},
		{"an absurd strip, 1 x 40000", grayPNGClaiming(t, 1, 40000, false)},
		{"a gif that claims 60000 x 60000", []byte("GIF89a\x60\xea\x60\xea\x80\x00\x00\x00\x00\x00\xff\xff\xff;")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := InspectImage(bytes.NewReader(tc.data))
			require.ErrorIs(t, err, ErrImageTooLarge)
		})
	}

	// 56 megapixels that are really there: refused, and nothing like 56 MB is allocated to find that out.
	big := grayPNGClaiming(t, 8000, 7000, true)
	require.Less(t, len(big), 2*1024*1024, "a small file that decodes to a big picture: the bomb")
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	_, err := InspectImage(bytes.NewReader(big))
	runtime.ReadMemStats(&after)
	require.ErrorIs(t, err, ErrImageTooLarge)
	require.Less(t, after.TotalAlloc-before.TotalAlloc, uint64(20<<20), "no pixel buffer was allocated")

	// A picture just under the limit still decodes.
	ok := grayPNGClaiming(t, 2000, 1500, true)
	meta, err := InspectImage(bytes.NewReader(ok))
	require.NoError(t, err)
	require.Equal(t, 2000, meta.Width)
	require.Equal(t, 1500, meta.Height)
}
