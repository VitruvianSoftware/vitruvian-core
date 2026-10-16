// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLockDataDirIsExclusive(t *testing.T) {
	dir := t.TempDir()
	release, err := lockDataDir(dir)
	require.NoError(t, err)

	_, err = lockDataDir(dir)
	require.Error(t, err, "a second instance on the same data dir must be refused")
	require.Contains(t, err.Error(), "another courier-engine-cli is already running on "+dir)

	release()
	release2, err := lockDataDir(dir)
	require.NoError(t, err, "the lock must be free again once the first instance exits")
	release2()
}

func TestLockDataDirIsPerDirectory(t *testing.T) {
	a, err := lockDataDir(t.TempDir())
	require.NoError(t, err)
	defer a()
	b, err := lockDataDir(t.TempDir())
	require.NoError(t, err, "different data dirs do not conflict")
	b()
}
