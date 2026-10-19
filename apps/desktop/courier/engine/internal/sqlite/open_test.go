// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package sqlite

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
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

// The search index needs FTS5 compiled into the driver (the go_deps patch for
// github.com/mattn/go-sqlite3 in MODULE.bazel) and SQLite 3.43.0 or later for
// contentless_delete.
func TestFTS5IsCompiledIn(t *testing.T) {
	ctx := context.Background()
	db, err := Open(filepath.Join(t.TempDir(), "x.db"))
	require.NoError(t, err)
	defer db.Close()

	rows, err := db.Query(ctx, "PRAGMA compile_options")
	require.NoError(t, err)
	var options []string
	for rows.Next() {
		var o string
		require.NoError(t, rows.Scan(&o))
		options = append(options, o)
	}
	require.NoError(t, rows.Err())
	require.NoError(t, rows.Close())
	// assert, not require: a driver without FTS5 also shows "no such module: fts5" below.
	assert.Contains(t, options, "ENABLE_FTS5")

	var version string
	require.NoError(t, db.QueryRow(ctx, "SELECT sqlite_version()").Scan(&version))
	var major, minor, patch int
	_, err = fmt.Sscanf(version, "%d.%d.%d", &major, &minor, &patch)
	require.NoError(t, err, version)
	assert.GreaterOrEqual(t, major*1_000_000+minor*1_000+patch, 3_043_000,
		"contentless_delete needs SQLite 3.43.0, have %s", version)

	_, err = db.Exec(ctx, `CREATE VIRTUAL TABLE t USING fts5(x, content='', contentless_delete=1, `+
		`tokenize="unicode61 remove_diacritics 2 categories 'L* N* Co M*'")`)
	require.NoError(t, err)
	_, err = db.Exec(ctx, "INSERT INTO t(rowid, x) VALUES (7, 'hello world')")
	require.NoError(t, err)
	matches := func() int {
		var n int
		require.NoError(t, db.QueryRow(ctx, "SELECT count(*) FROM t WHERE t MATCH 'hello'").Scan(&n))
		return n
	}
	require.Equal(t, 1, matches())
	_, err = db.Exec(ctx, "DELETE FROM t WHERE rowid = 7")
	require.NoError(t, err)
	require.Equal(t, 0, matches())
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
