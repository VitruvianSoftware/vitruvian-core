// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// integrationsWorld is a store, its local API and the socket server over them, with one greeted app connection.
func integrationsWorld(t *testing.T) (*store.Store, *localapi.Server, *client) {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	d := Deps{Store: s, Version: "test-1", Notices: NewNotifier()}
	d.LocalAPI = localapi.New(s, NewDispatcher(d), d.Notices, zerolog.Nop())
	t.Cleanup(d.LocalAPI.Close)
	c := dial(t, serve(t, d))
	c.hello()
	return s, d.LocalAPI, c
}

type apiToken struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	CanSend    bool   `json:"canSend"`
	CreatedMS  int64  `json:"createdMs"`
	LastUsedMS *int64 `json:"lastUsedMs"`
}

func TestIntegrationsTokensRoundTrip(t *testing.T) {
	s, _, c := integrationsWorld(t)
	var created struct {
		Token  apiToken `json:"token"`
		Secret string   `json:"secret"`
	}
	c.ok("integrations.createToken", map[string]any{"name": "  Claude Code\n", "canSend": true}, &created)
	require.Equal(t, "Claude Code", created.Token.Name)
	require.True(t, created.Token.CanSend)
	require.True(t, strings.HasPrefix(created.Secret, store.TokenPrefix))
	require.Nil(t, created.Token.LastUsedMS)
	got, err := s.LookupAPIToken(context.Background(), created.Secret)
	require.NoError(t, err, "the secret handed out is the one that works")
	require.Equal(t, created.Token.ID, got.ID)

	var second struct {
		Token apiToken `json:"token"`
	}
	c.ok("integrations.createToken", map[string]any{"name": ""}, &second)
	require.Equal(t, store.UnnamedClient, second.Token.Name)
	require.False(t, second.Token.CanSend, "off unless asked for")

	var list []apiToken
	c.ok("integrations.tokens", nil, &list)
	require.Len(t, list, 2)
	require.Equal(t, created.Token.ID, list[0].ID)
	require.NotNil(t, list[0].LastUsedMS, "the lookup above was a use")
	raw := c.call("integrations.tokens", nil).raw
	require.NotContains(t, string(raw), created.Secret, "no secret in a listing")
	require.NotContains(t, string(raw), "hash")

	c.ok("integrations.setCanSend", map[string]any{"id": second.Token.ID, "canSend": true}, nil)
	c.ok("integrations.revokeToken", map[string]any{"id": created.Token.ID}, nil)
	_, err = s.LookupAPIToken(context.Background(), created.Secret)
	require.ErrorIs(t, err, store.ErrNotFound)
	c.ok("integrations.tokens", nil, &list)
	require.Len(t, list, 1)
	require.Equal(t, second.Token.ID, list[0].ID)
	require.True(t, list[0].CanSend)

	c.fails(CodeNotFound, "integrations.revokeToken", map[string]any{"id": created.Token.ID})
	c.fails(CodeNotFound, "integrations.setCanSend", map[string]any{"id": created.Token.ID, "canSend": false})
	c.fails(CodeInvalidParams, "integrations.createToken", map[string]any{})
	c.fails(CodeInvalidParams, "integrations.setCanSend", map[string]any{"id": second.Token.ID})
}

// freePort is a loopback port nothing listens on just now.
func freePort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port
}

type integrationsStatusJSON struct {
	Enabled   bool   `json:"enabled"`
	Port      int    `json:"port"`
	Remote    bool   `json:"remote"`
	Listening bool   `json:"listening"`
	Error     string `json:"error"`
}

func TestIntegrationsUpdateAppliesAndSaves(t *testing.T) {
	s, api, c := integrationsWorld(t)
	var st integrationsStatusJSON
	c.ok("integrations.status", nil, &st)
	require.Equal(t, integrationsStatusJSON{Port: store.DefaultLocalAPIPort}, st, "off until turned on")

	port := freePort(t)
	c.ok("integrations.update", map[string]any{"enabled": true, "port": port}, &st)
	require.Equal(t, integrationsStatusJSON{Enabled: true, Port: port, Listening: true}, st)
	require.NotNil(t, api.Addr())
	set, err := s.LocalAPI(context.Background())
	require.NoError(t, err)
	require.Equal(t, store.LocalAPISettings{Enabled: true, Port: port}, set, "saved")

	c.ok("integrations.update", map[string]any{"remote": true}, &st)
	require.True(t, st.Remote)
	require.True(t, st.Listening, st.Error)
	require.True(t, api.Addr().(*net.TCPAddr).IP.IsUnspecified(), "every address, at once")
	c.ok("integrations.update", map[string]any{"remote": false}, &st)
	require.True(t, api.Addr().(*net.TCPAddr).IP.IsLoopback())

	c.fails(CodeInvalidParams, "integrations.update", map[string]any{"port": 80})
	c.fails(CodeInvalidParams, "integrations.update", map[string]any{"port": 70000})

	// A port another app holds: off, with the reason; the engine answers on.
	taken, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer taken.Close()
	busy := taken.Addr().(*net.TCPAddr).Port
	c.ok("integrations.update", map[string]any{"port": busy}, &st)
	require.False(t, st.Listening)
	require.Equal(t, fmt.Sprintf("Port %d is in use by another app", busy), st.Error)
	c.ok("integrations.status", nil, &st)
	require.Equal(t, busy, st.Port)

	c.ok("integrations.update", map[string]any{"enabled": false}, &st)
	require.False(t, st.Enabled)
	require.Nil(t, api.Addr())
}

// pair POSTs a pairing request and returns its answer on the channel.
type pairResult struct {
	status int
	body   string
	header http.Header
}

func pair(t *testing.T, port int, clientName string) <-chan pairResult {
	t.Helper()
	return pairCtx(t, context.Background(), port, clientName)
}

// pairCtx is pair with a context: cancelling it hangs the client up.
func pairCtx(t *testing.T, ctx context.Context, port int, clientName string) <-chan pairResult {
	t.Helper()
	out := make(chan pairResult, 1)
	go func() {
		b, _ := json.Marshal(map[string]string{"clientName": clientName})
		req, _ := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("http://127.0.0.1:%d%s", port, localapi.PairPath), strings.NewReader(string(b)))
		req.Header.Set("Content-Type", "application/json")
		resp, err := (&http.Client{Transport: &http.Transport{DisableKeepAlives: true}}).Do(req)
		if err != nil {
			out <- pairResult{status: -1, body: err.Error()}
			return
		}
		defer resp.Body.Close()
		body, _ := io.ReadAll(resp.Body)
		out <- pairResult{status: resp.StatusCode, body: string(body), header: resp.Header}
	}()
	return out
}

func waitPair(t *testing.T, ch <-chan pairResult) pairResult {
	t.Helper()
	select {
	case r := <-ch:
		return r
	case <-time.After(10 * time.Second):
		t.Fatal("the pairing request got no answer")
		return pairResult{}
	}
}

// pairRequestNotice waits for the app to be asked, and returns the request.
func pairRequestNotice(t *testing.T, c *client) localapi.PairRequest {
	t.Helper()
	var req localapi.PairRequest
	require.NoError(t, json.Unmarshal(c.notice(localapi.NoticePairRequest), &req))
	return req
}

// pairEndedNotice waits for the app to be told a request is over, and returns its ID.
func pairEndedNotice(t *testing.T, c *client) string {
	t.Helper()
	var ended localapi.PairEnded
	require.NoError(t, json.Unmarshal(c.notice(localapi.NoticePairEnded), &ended))
	return ended.RequestID
}

func pairingWorld(t *testing.T, cooldown time.Duration) (*store.Store, *localapi.Server, *client, int) {
	t.Helper()
	s, api, c := integrationsWorld(t)
	api.SetPairCooldown(cooldown)
	st := api.Apply(context.Background(), localapi.Config{Enabled: true})
	require.True(t, st.Listening, st.Error)
	return s, api, c, st.Port
}

func TestPairingAllowDenyTimeoutAndOneAtATime(t *testing.T) {
	s, api, c, port := pairingWorld(t, time.Millisecond)

	// Allow and Send Messages: the client gets a working token named as it asked, cleaned.
	res := pair(t, port, "Claude\u202e Desktop\n")
	req := pairRequestNotice(t, c)
	require.Equal(t, "Claude Desktop", req.ClientName)

	// Another while that one waits: 429.
	second := waitPair(t, pair(t, port, "Second"))
	require.Equal(t, http.StatusTooManyRequests, second.status)

	c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": true, "canSend": true}, nil)
	got := waitPair(t, res)
	require.Equal(t, http.StatusOK, got.status, got.body)
	require.Equal(t, req.RequestID, pairEndedNotice(t, c), "the app hears it is over")
	var body struct {
		Token string `json:"token"`
	}
	require.NoError(t, json.Unmarshal([]byte(got.body), &body))
	tok, err := s.LookupAPIToken(context.Background(), body.Token)
	require.NoError(t, err)
	require.Equal(t, "Claude Desktop", tok.Name)
	require.True(t, tok.CanSend)
	c.fails(CodeNotFound, "integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": true})

	// Don't Allow: 403, no token, and the app hears it is over.
	res = pair(t, port, "Denied client")
	req = pairRequestNotice(t, c)
	c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": false}, nil)
	got = waitPair(t, res)
	require.Equal(t, http.StatusForbidden, got.status)
	require.JSONEq(t, `{"error":"denied"}`, got.body)
	require.Equal(t, req.RequestID, pairEndedNotice(t, c))

	// No answer in time: 403, the app hears it is over, and the request is gone.
	time.Sleep(20 * time.Millisecond) // past the (shortened) cooldown
	api.SetPairTimeout(100 * time.Millisecond)
	res = pair(t, port, "Slow")
	req = pairRequestNotice(t, c)
	got = waitPair(t, res)
	require.Equal(t, http.StatusForbidden, got.status)
	require.Equal(t, req.RequestID, pairEndedNotice(t, c))
	c.fails(CodeNotFound, "integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": true})

	toks, err := s.ListAPITokens(context.Background())
	require.NoError(t, err)
	require.Len(t, toks, 1, "only the allowed client got a token")

	// The guards apply: a browser can't ask, nor can a Host other than loopback with Remote Access off.
	for _, h := range []map[string]string{{"Origin": "https://evil.example"}, {"Host": "evil.example"}} {
		r, err := http.NewRequest(http.MethodPost, fmt.Sprintf("http://127.0.0.1:%d%s", port, localapi.PairPath), strings.NewReader(`{"clientName":"x"}`))
		require.NoError(t, err)
		for k, v := range h {
			if k == "Host" {
				r.Host = v
			} else {
				r.Header.Set(k, v)
			}
		}
		resp, err := http.DefaultClient.Do(r)
		require.NoError(t, err)
		resp.Body.Close()
		require.Equal(t, http.StatusForbidden, resp.StatusCode, "%v", h)
	}
}

// A client that asks and hangs up can't put up prompt after prompt: its request keeps the slot until the person
// answers or the time is up, the app is told to take the prompt down, and an Allow for it makes no token.
func TestPairingDisconnectThenRetryIs429(t *testing.T) {
	s, _, c, port := pairingWorld(t, time.Hour)
	ctx, hangUp := context.WithCancel(context.Background())
	res := pairCtx(t, ctx, port, "Flooder")
	req := pairRequestNotice(t, c)
	hangUp()
	require.Equal(t, -1, waitPair(t, res).status)
	require.Equal(t, req.RequestID, pairEndedNotice(t, c), "the prompt comes down")

	for range 3 {
		again := waitPair(t, pair(t, port, "Flooder"))
		require.Equal(t, http.StatusTooManyRequests, again.status, "the slot is still taken")
	}

	// The person answers the request whose client left: no token, and the cooldown starts.
	c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": true, "canSend": true}, nil)
	require.Eventually(t, func() bool {
		r := waitPair(t, pair(t, port, "Flooder"))
		return r.status == http.StatusTooManyRequests && r.header.Get("Retry-After") != ""
	}, 5*time.Second, 20*time.Millisecond, "in the cooldown now, which says when to retry")
	toks, err := s.ListAPITokens(context.Background())
	require.NoError(t, err)
	require.Empty(t, toks, "nobody to give a token to: none made")
	select {
	case m := <-c.notes:
		require.NotEqual(t, localapi.NoticePairRequest, m.Method, "no new prompt went up")
	default:
	}
}

// After each request that ends without an Allow, new requests wait longer; an Allow resets it.
func TestPairingCooldownGrows(t *testing.T) {
	const base = 300 * time.Millisecond
	_, _, c, port := pairingWorld(t, base)
	deny := func() {
		t.Helper()
		res := pair(t, port, "Client")
		req := pairRequestNotice(t, c)
		c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": false}, nil)
		require.Equal(t, http.StatusForbidden, waitPair(t, res).status)
		pairEndedNotice(t, c)
	}
	refused := func() bool {
		t.Helper()
		return waitPair(t, pair(t, port, "Client")).status == http.StatusTooManyRequests
	}

	deny()
	require.True(t, refused(), "in the first cooldown")
	time.Sleep(base + 100*time.Millisecond)
	deny() // the first cooldown is over: asked again, and denied again
	time.Sleep(base + 100*time.Millisecond)
	require.True(t, refused(), "the second cooldown is twice as long")
	time.Sleep(base + 100*time.Millisecond)

	// An Allow resets it: the next request is asked at once.
	res := pair(t, port, "Client")
	req := pairRequestNotice(t, c)
	c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": true}, nil)
	require.Equal(t, http.StatusOK, waitPair(t, res).status)
	pairEndedNotice(t, c)
	res = pair(t, port, "Client")
	req = pairRequestNotice(t, c)
	c.ok("integrations.answerPairing", map[string]any{"requestID": req.RequestID, "allow": false}, nil)
	waitPair(t, res)
}

// With no app connected there is no one to ask: refused at once.
func TestPairingWithNoAppIsRefused(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	api := localapi.New(s, NewDispatcher(Deps{Store: s}), NewNotifier(), zerolog.Nop())
	t.Cleanup(api.Close)
	st := api.Apply(context.Background(), localapi.Config{Enabled: true})
	require.True(t, st.Listening, st.Error)
	got := waitPair(t, pair(t, st.Port, "Nobody home"))
	require.Equal(t, http.StatusForbidden, got.status)
}
