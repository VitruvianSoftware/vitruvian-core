// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package sqlite opens courier's SQLite files on the cgo driver the bridge stack expects.
package sqlite

import (
	"errors"
	"fmt"
	"io/fs"
	"os"

	"go.mau.fi/util/dbutil"
	_ "go.mau.fi/util/dbutil/litestream" // registers the cgo sqlite3 drivers
)

// PrivateDir creates dir (and any parents) and makes sure only the owner can use it, even if it already existed.
func PrivateDir(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return os.Chmod(dir, 0o700)
}

// Open opens (creating if needed) a SQLite database in WAL mode with a 5 s busy timeout.
// The database and its -wal and -shm files are readable by the owner only: they hold chat history
// and, for the bridge databases, the keys of the linked WhatsApp device.
func Open(path string) (*dbutil.Database, error) {
	// Create the file private up front, so it is never readable by others, even briefly. SQLite gives the
	// -wal and -shm files the same mode as the database file.
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	f.Close()
	uri := fmt.Sprintf("file:%s?_txlock=immediate&_busy_timeout=5000&_journal_mode=WAL&_foreign_keys=on", path)
	db, err := dbutil.NewWithDialect(uri, "sqlite3-fk-wal")
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	// Narrow files made by an earlier run, or by the user, including the sidecars if they exist.
	for _, p := range []string{path, path + "-wal", path + "-shm"} {
		if err = os.Chmod(p, 0o600); err != nil && !errors.Is(err, fs.ErrNotExist) {
			db.Close()
			return nil, fmt.Errorf("secure %s: %w", p, err)
		}
	}
	return db, nil
}
