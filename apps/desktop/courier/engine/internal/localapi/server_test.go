// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi_test

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
)

// initialize is an MCP initialize request, the first thing a client sends.
const initialize = `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}`

// post sends body to the MCP endpoint with the headers given (Host is set on the request itself) and returns the
// status and body.
func post(t *testing.T, url, body string, headers map[string]string) (int, string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, url, strings.NewReader(body))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/event-stream")
	for k, v := range headers {
		if k == "Host" {
			req.Host = v
			continue
		}
		req.Header.Set(k, v)
	}
	// A new connection each time: switching Remote Access closes the listener's connections, and a kept-alive one
	// from before would be gone.
	resp, err := (&http.Client{Transport: &http.Transport{DisableKeepAlives: true}}).Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	for k := range resp.Header {
		require.False(t, strings.HasPrefix(strings.ToLower(k), "access-control-"), "no CORS header, ever: %s", k)
	}
	return resp.StatusCode, string(b)
}

func TestAuthIsRequired(t *testing.T) {
	w := storeOnly(t)
	_, secret := w.token(t, false)

	code, body := post(t, w.url, initialize, nil)
	require.Equal(t, http.StatusUnauthorized, code, "no Authorization header")
	require.JSONEq(t, `{"error":"unauthorized"}`, body)

	for _, auth := range []string{"Bearer courier_wrong", "Bearer " + secret + "x", "Basic " + secret, secret, "Bearer "} {
		code, body = post(t, w.url, initialize, map[string]string{"Authorization": auth})
		require.Equal(t, http.StatusUnauthorized, code, "a wrong token")
		require.JSONEq(t, `{"error":"unauthorized"}`, body)
	}

	code, _ = post(t, w.url, initialize, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusOK, code, "the right token")
}

// A token revoked while its client is connected is refused on the very next request (Review Focus 5).
func TestRevokedMidSessionIsRefusedNextCall(t *testing.T) {
	w := storeOnly(t)
	tok, secret := w.token(t, false)
	sess := w.connect(t, secret)
	ok(t, sess, "search_docs", map[string]any{"query": "x", "language": "go"}, nil)

	require.NoError(t, w.s.RevokeAPIToken(context.Background(), tok.ID))
	_, err := sess.CallTool(context.Background(), toolCall("search_docs", map[string]any{"query": "x", "language": "go"}))
	require.Error(t, err, "revoked: the next call is refused")
	require.Contains(t, err.Error(), "Unauthorized")

	code, body := post(t, w.url, initialize, map[string]string{"Authorization": "Bearer " + secret})
	require.Equal(t, http.StatusUnauthorized, code)
	require.JSONEq(t, `{"error":"unauthorized"}`, body)
}

func TestHostOriginAndBodyGuards(t *testing.T) {
	w := storeOnly(t)
	_, secret := w.token(t, false)
	port := w.api.Status().Port
	auth := "Bearer " + secret

	for _, host := range []string{"evil.example", "evil.example:" + fmt.Sprint(port), "127.0.0.1:1", "10.0.0.2:" + fmt.Sprint(port)} {
		code, body := post(t, w.url, initialize, map[string]string{"Authorization": auth, "Host": host})
		require.Equal(t, http.StatusForbidden, code, "Host %s", host)
		require.JSONEq(t, `{"error":"forbidden"}`, body)
	}
	for _, host := range []string{"127.0.0.1:" + fmt.Sprint(port), "localhost:" + fmt.Sprint(port), "[::1]:" + fmt.Sprint(port)} {
		code, _ := post(t, w.url, initialize, map[string]string{"Authorization": auth, "Host": host})
		require.Equal(t, http.StatusOK, code, "Host %s", host)
	}

	for _, origin := range []string{"https://evil.example", "http://127.0.0.1:" + fmt.Sprint(port), "null", ""} {
		code, body := post(t, w.url, initialize, map[string]string{"Authorization": auth, "Origin": origin})
		require.Equal(t, http.StatusForbidden, code, "Origin %q", origin)
		require.JSONEq(t, `{"error":"forbidden"}`, body)
	}

	big := `{"jsonrpc":"2.0","id":1,"method":"ping","params":{"pad":"` + strings.Repeat("x", localapi.MaxBodyBytes) + `"}}`
	code, _ := post(t, w.url, big, map[string]string{"Authorization": auth})
	require.Equal(t, http.StatusRequestEntityTooLarge, code)

	// Without a Content-Length, the limit holds while the body is read.
	req, err := http.NewRequest(http.MethodPost, w.url, io.MultiReader(strings.NewReader(big)))
	require.NoError(t, err)
	req.ContentLength = -1
	req.Header.Set("Authorization", auth)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json, text/event-stream")
	resp, err := http.DefaultClient.Do(req)
	require.NoError(t, err)
	resp.Body.Close()
	require.Equal(t, http.StatusRequestEntityTooLarge, resp.StatusCode)

	// Only the MCP path is served.
	code, _ = post(t, strings.Replace(w.url, localapi.MCPPath, "/v1/chats", 1), initialize, map[string]string{"Authorization": auth})
	require.Equal(t, http.StatusNotFound, code)
}

func TestListensOnLoopbackByDefault(t *testing.T) {
	w := storeOnly(t)
	st := w.api.Status()
	require.True(t, st.Listening)
	require.False(t, st.Remote)
	addr := w.api.Addr().(*net.TCPAddr)
	require.True(t, addr.IP.Equal(net.IPv4(127, 0, 0, 1)), "bound to %s", addr)
}

// With Remote Access on, it listens on every address and takes any Host (the token is the guard); turned off
// again, it is back on 127.0.0.1 with the Host guard, without a restart.
func TestRemoteAccessListensOnAllAddresses(t *testing.T) {
	w := storeOnly(t)
	_, secret := w.token(t, false)
	auth := "Bearer " + secret
	ctx := context.Background()

	st := w.api.Apply(ctx, localapi.Config{Enabled: true, Port: 0, Remote: true})
	require.True(t, st.Listening, st.Error)
	require.True(t, st.Remote)
	addr := w.api.Addr().(*net.TCPAddr)
	require.True(t, addr.IP.IsUnspecified(), "bound to %s", addr)
	url := fmt.Sprintf("http://127.0.0.1:%d%s", st.Port, localapi.MCPPath)
	code, _ := post(t, url, initialize, map[string]string{"Authorization": auth, "Host": "my-mac.local:" + fmt.Sprint(st.Port)})
	require.Equal(t, http.StatusOK, code, "any Host, with a token")
	code, _ = post(t, url, initialize, map[string]string{"Host": "my-mac.local"})
	require.Equal(t, http.StatusUnauthorized, code, "still no way in without a token")
	code, _ = post(t, url, initialize, map[string]string{"Authorization": auth, "Origin": "https://evil.example"})
	require.Equal(t, http.StatusForbidden, code, "and never from a browser")

	st = w.api.Apply(ctx, localapi.Config{Enabled: true, Port: st.Port, Remote: false})
	require.True(t, st.Listening, st.Error)
	require.False(t, st.Remote)
	addr = w.api.Addr().(*net.TCPAddr)
	require.True(t, addr.IP.Equal(net.IPv4(127, 0, 0, 1)), "back on loopback: %s", addr)
	url = fmt.Sprintf("http://127.0.0.1:%d%s", st.Port, localapi.MCPPath)
	code, _ = post(t, url, initialize, map[string]string{"Authorization": auth, "Host": "my-mac.local:" + fmt.Sprint(st.Port)})
	require.Equal(t, http.StatusForbidden, code, "the Host guard is back")

	st = w.api.Apply(ctx, localapi.Config{Enabled: false, Port: st.Port})
	require.False(t, st.Listening)
	require.Nil(t, w.api.Addr())
	_, err := http.Post(url, "application/json", strings.NewReader(initialize))
	require.Error(t, err, "off: nothing listens")
}

// A port another app holds leaves the local API off with a plain reason; the engine goes on (Review Focus 3).
func TestPortInUseLeavesItOff(t *testing.T) {
	w := storeOnly(t)
	taken, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer taken.Close()
	port := taken.Addr().(*net.TCPAddr).Port

	st := w.api.Apply(context.Background(), localapi.Config{Enabled: true, Port: port})
	require.False(t, st.Listening)
	require.True(t, st.Enabled)
	require.Equal(t, port, st.Port)
	require.Equal(t, fmt.Sprintf("Port %d is in use by another app", port), st.Error)
	require.Equal(t, st, w.api.Status())

	// Freed, the same settings applied again listen.
	taken.Close()
	st = w.api.Apply(context.Background(), localapi.Config{Enabled: true, Port: port})
	require.True(t, st.Listening, st.Error)
	require.Empty(t, st.Error)
	code, _ := post(t, fmt.Sprintf("http://127.0.0.1:%d%s", port, localapi.MCPPath), initialize, nil)
	require.Equal(t, http.StatusUnauthorized, code)
}

// Nothing the local API writes to its log names a token or what a message said.
func TestLogsCarryNoTokensOrText(t *testing.T) {
	var buf bytes.Buffer
	w := newWorldLogging(t, &buf)
	_, secret := w.token(t, true)
	sess := w.connect(t, secret)
	ok(t, sess, "list_messages", map[string]any{"chatID": w.room}, nil)
	ok(t, sess, "send_message", map[string]any{"chatID": w.room, "text": "a very private sentence"}, nil)
	ok(t, sess, "search_messages", map[string]any{"query": "message"}, nil)
	out := buf.String()
	require.Contains(t, out, `"tool":"send_message"`, "a call is logged by its tool's name")
	for _, secretish := range []string{secret, "private", "message 0", w.room} {
		require.NotContains(t, out, secretish)
	}
}
