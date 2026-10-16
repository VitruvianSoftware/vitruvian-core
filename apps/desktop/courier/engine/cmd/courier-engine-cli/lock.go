// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// lockDataDir takes an exclusive advisory lock on <dir>/.lock for as long as the
// returned release func has not been called (or the process lives). Two processes
// on one data dir would run two live sessions on one linked WhatsApp device.
func lockDataDir(dir string) (release func(), err error) {
	f, err := os.OpenFile(filepath.Join(dir, ".lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, fmt.Errorf("another courier-engine-cli is already running on %s", dir)
		}
		return nil, fmt.Errorf("lock %s: %w", dir, err)
	}
	// Closing the file drops the lock; the OS also drops it if we crash.
	return func() { _ = f.Close() }, nil
}
