package main

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseArgs(t *testing.T) {
	a, err := parseArgs([]string{"--data", "/tmp/x", "send", "!r:courier.local", "hello", "there"})
	require.NoError(t, err)
	require.Equal(t, args{data: "/tmp/x", cmd: "send", room: "!r:courier.local", text: "hello there"}, a)
	_, err = parseArgs([]string{"send", "!r:courier.local"})
	require.Error(t, err, "send without text must be rejected")
	_, err = parseArgs([]string{"bogus"})
	require.Error(t, err)
}

func TestParseArgsRejectsBlankSend(t *testing.T) {
	_, err := parseArgs([]string{"send", "!r:courier.local", "   "})
	require.Error(t, err, "a whitespace-only message must not be sent")
}
