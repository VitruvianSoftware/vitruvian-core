// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"bytes"
	"compress/lzw"
	"encoding/binary"
	"runtime"
	"testing"

	"github.com/stretchr/testify/require"
)

// gifWithFrame is a GIF whose screen says screenW x screenH and whose one frame says frameW x frameH, filled with zeros.
func gifWithFrame(t *testing.T, screenW, screenH, frameW, frameH int) []byte {
	t.Helper()
	out := []byte("GIF89a")
	out = binary.LittleEndian.AppendUint16(out, uint16(screenW))
	out = binary.LittleEndian.AppendUint16(out, uint16(screenH))
	out = append(out, 0x80, 0, 0, 0, 0, 0, 0xff, 0xff, 0xff) // two-colour table
	out = append(out, 0x2c, 0, 0, 0, 0)
	out = binary.LittleEndian.AppendUint16(out, uint16(frameW))
	out = binary.LittleEndian.AppendUint16(out, uint16(frameH))
	out = append(out, 0, 8) // no local table; LZW minimum code size 8
	var z bytes.Buffer
	zw := lzw.NewWriter(&z, lzw.LSB, 8)
	row := make([]byte, frameW)
	for y := 0; y < frameH; y++ {
		_, err := zw.Write(row)
		require.NoError(t, err)
	}
	require.NoError(t, zw.Close())
	for data := z.Bytes(); len(data) > 0; {
		n := min(len(data), 255)
		out = append(out, byte(n))
		out = append(out, data[:n]...)
		data = data[n:]
	}
	return append(out, 0, ';')
}

// A GIF's screen can say 1 x 1 while its frame says 20000 x 20000: the header check must not be the screen's alone.
func TestInspectImageRefusesAGIFFrameBiggerThanItsScreen(t *testing.T) {
	bomb := gifWithFrame(t, 1, 1, 20000, 20000)
	require.Less(t, len(bomb), 2*1024*1024, "a small file: the bomb")
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	_, err := InspectImage(bytes.NewReader(bomb))
	runtime.ReadMemStats(&after)
	t.Logf("%d bytes on the wire; %d MiB allocated; err=%v", len(bomb), (after.TotalAlloc-before.TotalAlloc)>>20, err)
	require.Error(t, err)
	require.Less(t, after.TotalAlloc-before.TotalAlloc, uint64(50<<20), "no frame buffer of hundreds of MB")
}
