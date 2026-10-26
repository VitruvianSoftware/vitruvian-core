// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
)

func TestStickersImportAndListOverRPC(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	w.can(t, everything())

	tmpDir := t.TempDir()
	pngPath := filepath.Join(tmpDir, "party.png")
	pngData := []byte{
		0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
		0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
		0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
		0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
		0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
		0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
		0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
		0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
		0x42, 0x60, 0x82,
	}
	require.NoError(t, os.WriteFile(pngPath, pngData, 0o600))

	var imported actions.StickerItem
	c.ok("stickers.import", map[string]any{
		"path":      pngPath,
		"shortcode": ":party:",
		"name":      "Party",
		"emoji":     "🎉",
	}, &imported)
	require.Equal(t, "imported", imported.PackID)
	require.Equal(t, "party", imported.Shortcode)
	require.Equal(t, "Party", imported.Name)
	require.True(t, strings.HasPrefix(imported.MediaURL, "courier://media/"))
	require.Equal(t, []string{"emoticon", "sticker"}, imported.Usage)

	var listed actions.ListStickersResult
	c.ok("stickers.list", map[string]any{
		"refresh_bridge_packs": false,
	}, &listed)
	require.NotEmpty(t, listed.Packs)

	var foundImported bool
	for _, p := range listed.Packs {
		if p.Source == "imported" && len(p.Items) == 1 && p.Items[0].Shortcode == "party" {
			foundImported = true
		}
	}
	require.True(t, foundImported)
}
