// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package media

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPutReadIsContentAddressed(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	h1, err := m.Put([]byte("hello"))
	require.NoError(t, err)
	h2, err := m.PutStream(func(w io.Writer) error { _, err := w.Write([]byte("hello")); return err })
	require.NoError(t, err)
	require.Equal(t, h1, h2)
	got, err := m.Read(h1)
	require.NoError(t, err)
	require.Equal(t, "hello", string(got))
}

func TestOpenMissingMediaErrors(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	_, err := m.Read("0000000000000000000000000000000000000000000000000000000000000000")
	require.ErrorIs(t, err, ErrMissing)
	_, err = m.Read("../../etc/passwd")
	require.ErrorIs(t, err, ErrInvalidHash, "non-hash names must be rejected, not read")
}

func TestPathRejectsNonHashes(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	for _, bad := range []string{"", "a", "../../etc/passwd"} {
		require.NotPanics(t, func() {
			_, err := m.Path(bad)
			require.ErrorIs(t, err, ErrInvalidHash, "input %q", bad)
		})
	}
}

func TestPathStaysInsideDir(t *testing.T) {
	m := &Store{Dir: t.TempDir()}
	h := hex.EncodeToString(make([]byte, 32))
	p, err := m.Path(h)
	require.NoError(t, err)
	require.Equal(t, filepath.Join(m.Dir, h[:2], h), p)
}

func TestPutStreamFailureLeavesNothing(t *testing.T) {
	dir := t.TempDir()
	m := &Store{Dir: dir}
	boom := errors.New("boom")
	hash, err := m.PutStream(func(w io.Writer) error {
		_, _ = w.Write([]byte("partial"))
		return boom
	})
	require.ErrorIs(t, err, boom)
	require.Empty(t, hash)
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	require.Empty(t, entries, "no temp file or partial blob may remain")
}

func TestPutStreamRenameFailureReturnsEmptyHash(t *testing.T) {
	dir := t.TempDir()
	m := &Store{Dir: dir}
	sum := sha256.Sum256([]byte("hello"))
	h := hex.EncodeToString(sum[:])
	// Occupy the final name with a non-empty directory so the rename must fail.
	blocker := filepath.Join(dir, h[:2], h)
	require.NoError(t, os.MkdirAll(blocker, 0o700))
	require.NoError(t, os.WriteFile(filepath.Join(blocker, "x"), []byte("x"), 0o600))

	hash, err := m.PutStream(func(w io.Writer) error { _, err := w.Write([]byte("hello")); return err })
	require.Error(t, err)
	require.Empty(t, hash, "a failed write must not report a hash")
}

func TestReadEnforcesDefaultMaxMemoryBytes(t *testing.T) {
	dir := t.TempDir()
	m := &Store{Dir: dir}
	h := hex.EncodeToString(make([]byte, 32))
	p, err := m.Path(h)
	require.NoError(t, err)
	require.NoError(t, os.MkdirAll(filepath.Dir(p), 0o700))
	f, err := os.Create(p)
	require.NoError(t, err)
	require.NoError(t, f.Truncate(100*1024*1024+1))
	require.NoError(t, f.Close())

	_, err = m.Read(h)
	require.ErrorContains(t, err, "exceeds in-memory limit")
}
