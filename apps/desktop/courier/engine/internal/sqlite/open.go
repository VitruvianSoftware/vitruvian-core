// Package sqlite opens courier's SQLite files on the cgo driver the bridge stack expects.
package sqlite

import (
	"fmt"

	"go.mau.fi/util/dbutil"
	_ "go.mau.fi/util/dbutil/litestream" // registers the cgo sqlite3 drivers
)

// Open opens (creating if needed) a SQLite database in WAL mode with a 5 s busy timeout.
func Open(path string) (*dbutil.Database, error) {
	uri := fmt.Sprintf("file:%s?_txlock=immediate&_busy_timeout=5000&_journal_mode=WAL&_foreign_keys=on", path)
	db, err := dbutil.NewWithDialect(uri, "sqlite3-fk-wal")
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	return db, nil
}
