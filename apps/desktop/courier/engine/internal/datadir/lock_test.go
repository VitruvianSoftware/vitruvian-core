// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package datadir

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestLockIsExclusive(t *testing.T) {
	dir := t.TempDir()
	release, err := Lock(dir)
	require.NoError(t, err)

	_, err = Lock(dir)
	require.Error(t, err, "a second instance on the same data dir must be refused")
	require.ErrorIs(t, err, ErrLocked)
	require.EqualError(t, err, "another Courier engine is using "+dir)

	release()
	release2, err := Lock(dir)
	require.NoError(t, err, "the lock must be free again once the first instance exits")
	release2()
}

func TestLockIsPerDirectory(t *testing.T) {
	a, err := Lock(t.TempDir())
	require.NoError(t, err)
	defer a()
	b, err := Lock(t.TempDir())
	require.NoError(t, err, "different data dirs do not conflict")
	b()
}

func TestLockOnMissingDirIsNotReportedAsHeld(t *testing.T) {
	_, err := Lock(t.TempDir() + "/nope")
	require.Error(t, err)
	require.NotErrorIs(t, err, ErrLocked)
}
