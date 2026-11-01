// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package media stores attachment bytes by SHA-256 so the same file is kept once.
package media

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sync"
	"time"
)

var ErrMissing = errors.New("media file missing")

// ErrInvalidHash means a name is not a 64-character lower-case SHA-256 hex string.
var ErrInvalidHash = errors.New("invalid media hash")

var hashRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

// DefaultMaxMemoryBytes is the default 100 MiB cap on whole-file in-memory reads via Read when Store.MaxMemoryBytes is 0.
const DefaultMaxMemoryBytes int64 = 100 * 1024 * 1024

type Store struct {
	Dir string
	// MaxMemoryBytes bounds whole-file in-memory reads via Read (defaults to DefaultMaxMemoryBytes when 0).
	// Streaming writes (PutStream) and file-backed downloads (DownloadMediaToFile) are unaffected.
	MaxMemoryBytes int64

	putMu sync.Mutex           // guards putAt, and makes a write and DeleteUnlessPutSince one step each
	putAt map[string]time.Time // when each blob was last written, for the last putMemory
}

// putMemory is how long Store remembers that a blob was written, for DeleteUnlessPutSince.
const putMemory = time.Hour

// Path returns where a blob lives on disk. Anything that is not a real hash is
// refused, so a hostile name can neither panic nor escape Dir.
func (m *Store) Path(hash string) (string, error) {
	if !hashRE.MatchString(hash) {
		return "", fmt.Errorf("%w: %q", ErrInvalidHash, hash)
	}
	return filepath.Join(m.Dir, hash[:2], hash), nil
}

func (m *Store) Put(data []byte) (string, error) {
	return m.PutStream(func(w io.Writer) error { _, err := w.Write(data); return err })
}

// PutStream writes to a temp file while hashing, then renames into place.
// The data is synced before the rename so a crash cannot leave an empty file
// under its final hash name. On any failure it returns "" and leaves no temp file.
func (m *Store) PutStream(write func(io.Writer) error) (string, error) {
	if err := os.MkdirAll(m.Dir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(m.Dir, ".upload-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	hasher := sha256.New()
	if err = write(io.MultiWriter(tmp, hasher)); err != nil {
		tmp.Close()
		return "", err
	}
	if err = tmp.Sync(); err != nil {
		tmp.Close()
		return "", err
	}
	if err = tmp.Close(); err != nil {
		return "", err
	}
	hash := hex.EncodeToString(hasher.Sum(nil))
	final, err := m.Path(hash)
	if err != nil {
		return "", err
	}
	if err = os.MkdirAll(filepath.Dir(final), 0o700); err != nil {
		return "", err
	}
	m.putMu.Lock()
	defer m.putMu.Unlock()
	if err = os.Rename(tmp.Name(), final); err != nil {
		return "", err
	}
	now := time.Now()
	if m.putAt == nil {
		m.putAt = map[string]time.Time{}
	}
	for h, at := range m.putAt {
		if now.Sub(at) > putMemory {
			delete(m.putAt, h)
		}
	}
	m.putAt[hash] = now
	return hash, nil
}

func (m *Store) Read(hash string) ([]byte, error) {
	p, err := m.Path(hash)
	if err != nil {
		return nil, err
	}
	limit := m.MaxMemoryBytes
	if limit <= 0 {
		limit = DefaultMaxMemoryBytes
	}
	fi, err := os.Stat(p)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("%w: %s", ErrMissing, hash)
	}
	if err != nil {
		return nil, err
	}
	if fi.Size() > limit {
		return nil, fmt.Errorf("media read exceeds in-memory limit (%d > %d)", fi.Size(), limit)
	}
	b, err := os.ReadFile(p)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("%w: %s", ErrMissing, hash)
	}
	return b, err
}

// Delete removes the blob for hash from disk, ignoring fs.ErrNotExist if it is already gone.
// DeleteUnlessPutSince deletes a blob unless it was written at or after since, and says whether it deleted it. A
// write of the same blob waits for it, so a file written during a clean-up is never lost to it: either the write
// comes after the delete and puts the file back, or it came first and the delete leaves the file.
func (m *Store) DeleteUnlessPutSince(hash string, since time.Time) (bool, error) {
	if m == nil {
		return false, nil
	}
	m.putMu.Lock()
	defer m.putMu.Unlock()
	if at, ok := m.putAt[hash]; ok && !at.Before(since) {
		return false, nil
	}
	if err := m.Delete(hash); err != nil {
		return false, err
	}
	return true, nil
}

func (m *Store) Delete(hash string) error {
	if m == nil {
		return nil
	}
	p, err := m.Path(hash)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}
