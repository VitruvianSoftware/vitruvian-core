// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPruneLinkPreviewImagesDropsExpiredRowsThenKeepsTheNewest(t *testing.T) {
	ctx := context.Background()
	s, err := Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	put := func(name, state string, at int64) {
		require.NoError(t, s.SetSetting(ctx, LinkPreviewImageKeyPrefix+name, fmt.Sprintf(`{"state":%q,"at":%d}`, state, at)))
	}
	has := func(name string) bool {
		_, ok, err := s.Setting(ctx, LinkPreviewImageKeyPrefix+name)
		require.NoError(t, err)
		return ok
	}
	// An unrelated setting (the local API's) is never touched.
	require.NoError(t, s.SetSetting(ctx, "local_api_enabled", "1"))

	put("none-old", "none", 100)
	put("none-new", "none", 900)
	put("unknown-old", "unknown", 100)
	put("unknown-new", "unknown", 900)
	put("found-old", "found", 100) // a found picture does not expire
	require.NoError(t, s.SetSetting(ctx, LinkPreviewImageKeyPrefix+"garbage", `not json`))

	removed, err := s.PruneLinkPreviewImages(ctx, 500, 500, 100)
	require.NoError(t, err)
	require.EqualValues(t, 3, removed)
	require.False(t, has("none-old"))
	require.False(t, has("unknown-old"))
	require.False(t, has("garbage"))
	require.True(t, has("none-new"))
	require.True(t, has("unknown-new"))
	require.True(t, has("found-old"))

	// The cap keeps the newest rows.
	removed, err = s.PruneLinkPreviewImages(ctx, 0, 0, 2)
	require.NoError(t, err)
	require.EqualValues(t, 1, removed)
	require.False(t, has("found-old"), "the oldest goes first")
	require.True(t, has("none-new"))
	require.True(t, has("unknown-new"))

	_, ok, err := s.Setting(ctx, "local_api_enabled")
	require.NoError(t, err)
	require.True(t, ok, "settings that are not pictures are left alone")
}
