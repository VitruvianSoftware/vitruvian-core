// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package datadir holds what the CLI and the engine binary share about a data directory: one process at a time.
package datadir

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// ErrLocked means another process holds the data directory's lock.
var ErrLocked = errors.New("another Courier engine is using this data directory")

// LockedError is the error Lock returns when another process holds the lock. It matches ErrLocked.
type LockedError struct{ Dir string }

func (e *LockedError) Error() string        { return "another Courier engine is using " + e.Dir }
func (e *LockedError) Is(target error) bool { return target == ErrLocked }

// Lock takes an exclusive advisory lock on <dir>/.lock for as long as the returned release func has not been
// called (or the process lives). Two processes on one data dir would run two live sessions on one linked WhatsApp
// device. It does not wait: a lock held elsewhere is a *LockedError at once.
func Lock(dir string) (release func(), err error) {
	f, err := os.OpenFile(filepath.Join(dir, ".lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, &LockedError{Dir: dir}
		}
		return nil, fmt.Errorf("lock %s: %w", dir, err)
	}
	// Closing the file drops the lock; the OS also drops it if we crash.
	return func() { _ = f.Close() }, nil
}
