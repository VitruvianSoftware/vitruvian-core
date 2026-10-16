package sqlite

import (
	"context"
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
