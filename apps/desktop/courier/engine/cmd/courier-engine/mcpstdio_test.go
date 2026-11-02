// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/rpc"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// localAPI is a local API listening on a free loopback port, over an empty store.
func localAPI(t *testing.T) (*store.Store, int) {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	api := localapi.New(s, rpc.NewDispatcher(rpc.Deps{Store: s}), rpc.NewNotifier(), zerolog.Nop())
	st := api.Apply(context.Background(), localapi.Config{Enabled: true})
	require.True(t, st.Listening, st.Error)
	t.Cleanup(api.Close)
	return s, st.Port
}

type stdioRun struct {
	toServer   *io.PipeWriter // the client's writes: mcp-stdio's stdin
	fromServer *io.PipeReader // mcp-stdio's stdout
	stderr     *syncBuf
	code       chan int
}

// startStdio runs mcp-stdio in-process with env as its environment.
func startStdio(t *testing.T, env map[string]string, args ...string) *stdioRun {
	t.Helper()
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	r := &stdioRun{toServer: inW, fromServer: outR, stderr: &syncBuf{}, code: make(chan int, 1)}
	go func() {
		code := runMCPStdio(args, inR, outW, r.stderr, func(k string) string { return env[k] })
		outW.Close()
		r.code <- code
	}()
	t.Cleanup(func() { inW.Close(); outR.Close() })
	return r
}

func (r *stdioRun) exit(t *testing.T) int {
	t.Helper()
	select {
	case c := <-r.code:
		return c
	case <-time.After(10 * time.Second):
		t.Fatal("mcp-stdio did not exit")
		return -1
	}
}

func TestMCPStdioForwardsToolsList(t *testing.T) {
	s, port := localAPI(t)
	_, secret, err := s.CreateAPIToken(context.Background(), "stdio client", false)
	require.NoError(t, err)
	r := startStdio(t, map[string]string{"COURIER_TOKEN": secret}, "--port", fmt.Sprint(port))

	ctx := context.Background()
	c := mcp.NewClient(&mcp.Implementation{Name: "stdio-test", Version: "1"}, nil)
	sess, err := c.Connect(ctx, &mcp.IOTransport{Reader: r.fromServer, Writer: r.toServer}, nil)
	require.NoError(t, err)
	res, err := sess.ListTools(ctx, nil)
	require.NoError(t, err)
	var names []string
	for _, tool := range res.Tools {
		names = append(names, tool.Name)
	}
	require.ElementsMatch(t, []string{
		"get_accounts", "search", "search_chats", "search_messages", "get_chat", "list_messages", "send_message",
		"archive_chat", "set_chat_reminder", "clear_chat_reminder", "focus_app", "search_docs",
	}, names, "the local API's tools, forwarded")

	got, err := sess.CallTool(ctx, &mcp.CallToolParams{Name: "search_docs", Arguments: map[string]any{"query": "x", "language": "go"}})
	require.NoError(t, err)
	require.False(t, got.IsError)
	require.Equal(t, localapi.SearchDocsText, got.Content[0].(*mcp.TextContent).Text)

	got, err = sess.CallTool(ctx, &mcp.CallToolParams{Name: "send_message", Arguments: map[string]any{"chatID": "!r:courier.local", "text": "hi"}})
	require.NoError(t, err)
	require.True(t, got.IsError, "a tool error comes through as one")
	require.Contains(t, got.Content[0].(*mcp.TextContent).Text, "isn't allowed to send")

	require.NoError(t, sess.Close())
	r.toServer.Close()
	require.Equal(t, 0, r.exit(t), "stdin ended: a clean exit")
	require.Empty(t, r.stderr.String())
}

func TestMCPStdioWithoutTokenExplains(t *testing.T) {
	r := startStdio(t, nil)
	require.Equal(t, exitFailed, r.exit(t))
	line := r.stderr.String()
	require.Equal(t, 1, strings.Count(line, "\n"), "one line")
	require.Contains(t, line, "COURIER_TOKEN isn't set")
}

func TestMCPStdioExplainsWhenCourierIsntListening(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close() // nothing listens there now
	r := startStdio(t, map[string]string{"COURIER_TOKEN": store.TokenPrefix + "x"}, "--port", fmt.Sprint(port))
	require.Equal(t, exitFailed, r.exit(t))
	require.Equal(t, stdioNotRunning+"\n", r.stderr.String())
}

func TestMCPStdioExplainsARefusedToken(t *testing.T) {
	_, port := localAPI(t)
	secret := store.TokenPrefix + "not-a-real-token"
	r := startStdio(t, map[string]string{"COURIER_TOKEN": secret}, "--port", fmt.Sprint(port))
	require.Equal(t, exitFailed, r.exit(t))
	require.Equal(t, stdioBadToken+"\n", r.stderr.String())
	require.NotContains(t, r.stderr.String(), secret, "the token is never written out")
}

func TestMCPStdioBadArgumentsAreUsage(t *testing.T) {
	for _, args := range [][]string{{"--port", "0"}, {"--port", "x"}, {"extra"}, {"--nope"}} {
		var stderr bytes.Buffer
		code := runMCPStdio(args, io.NopCloser(strings.NewReader("")), nopCloser{io.Discard}, &stderr, func(string) string { return "t" })
		require.Equal(t, exitUsage, code, "%v", args)
		require.Contains(t, stderr.String(), "usage: courier-engine mcp-stdio")
	}
}
