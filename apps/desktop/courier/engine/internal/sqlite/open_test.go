// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package sqlite

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOpenCreatesWALDatabase(t *testing.T) {
	db, err := Open(filepath.Join(t.TempDir(), "x.db"))
	require.NoError(t, err)
	defer db.Close()
	var mode string
	require.NoError(t, db.QueryRow(context.Background(), "PRAGMA journal_mode").Scan(&mode))
	require.Equal(t, "wal", mode)
	var timeout int
	require.NoError(t, db.QueryRow(context.Background(), "PRAGMA busy_timeout").Scan(&timeout))
	require.Equal(t, 5000, timeout)
	var fk int
	require.NoError(t, db.QueryRow(context.Background(), "PRAGMA foreign_keys").Scan(&fk))
	require.Equal(t, 1, fk)
}

func mode(t *testing.T, path string) os.FileMode {
	t.Helper()
	fi, err := os.Stat(path)
	require.NoError(t, err)
	return fi.Mode().Perm()
}

func TestOpenCreatesPrivateFiles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "x.db")
	db, err := Open(path)
	require.NoError(t, err)
	defer db.Close()
	_, err = db.Exec(context.Background(), "CREATE TABLE t (a)")
	require.NoError(t, err)
	for _, f := range []string{path, path + "-wal", path + "-shm"} {
		require.FileExists(t, f)
		require.Equal(t, os.FileMode(0o600), mode(t, f), f)
	}
}

func TestOpenNarrowsAnExistingWideDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "x.db")
	db, err := Open(path)
	require.NoError(t, err)
	defer db.Close()
	_, err = db.Exec(context.Background(), "CREATE TABLE t (a)")
	require.NoError(t, err)
	// An earlier version (or the user) left the files world-readable; the -wal and -shm exist while the db is open.
	for _, f := range []string{path, path + "-wal", path + "-shm"} {
		require.NoError(t, os.Chmod(f, 0o644))
	}
	db2, err := Open(path)
	require.NoError(t, err)
	defer db2.Close()
	for _, f := range []string{path, path + "-wal", path + "-shm"} {
		require.Equal(t, os.FileMode(0o600), mode(t, f), f)
	}
}

func TestPrivateDirTightensAnExistingDir(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "data")
	require.NoError(t, os.Mkdir(dir, 0o755))
	require.NoError(t, os.Chmod(dir, 0o755))
	require.NoError(t, PrivateDir(dir))
	require.Equal(t, os.FileMode(0o700), mode(t, dir))
	// A missing dir is created private, parents included.
	nested := filepath.Join(dir, "a", "b")
	require.NoError(t, PrivateDir(nested))
	require.Equal(t, os.FileMode(0o700), mode(t, nested))
}
