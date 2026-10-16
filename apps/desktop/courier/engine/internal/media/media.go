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
)

var ErrMissing = errors.New("media file missing")

var hashRE = regexp.MustCompile(`^[0-9a-f]{64}$`)

type Store struct{ Dir string }

func (m *Store) Path(hash string) string { return filepath.Join(m.Dir, hash[:2], hash) }

func (m *Store) Put(data []byte) (string, error) {
	return m.PutStream(func(w io.Writer) error { _, err := w.Write(data); return err })
}

// PutStream writes to a temp file while hashing, then renames into place atomically.
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
	if err = tmp.Close(); err != nil {
		return "", err
	}
	hash := hex.EncodeToString(hasher.Sum(nil))
	if err = os.MkdirAll(filepath.Dir(m.Path(hash)), 0o700); err != nil {
		return "", err
	}
	return hash, os.Rename(tmp.Name(), m.Path(hash))
}

func (m *Store) Read(hash string) ([]byte, error) {
	if !hashRE.MatchString(hash) {
		return nil, fmt.Errorf("invalid media hash %q", hash)
	}
	b, err := os.ReadFile(m.Path(hash))
	if errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("%w: %s", ErrMissing, hash)
	}
	return b, err
}
