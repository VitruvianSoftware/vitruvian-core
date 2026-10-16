package media

import (
	"io"
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
	require.Error(t, err, "non-hash names must be rejected, not read")
}
