// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/localapi"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/rpc"
	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// recorder is a Publisher that keeps what the local API tells the app.
type recorder struct {
	mu     sync.Mutex
	sent   []published
	nobody bool // no app connected: Publish reaches no one
}

type published struct {
	method string
	params any
}

func (r *recorder) Publish(method string, params any) int {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.nobody {
		return 0
	}
	r.sent = append(r.sent, published{method, params})
	return 1
}

func (r *recorder) Listeners() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.nobody {
		return 0
	}
	return 1
}

func (r *recorder) setNobody(v bool) {
	r.mu.Lock()
	r.nobody = v
	r.mu.Unlock()
}

func (r *recorder) all() []published {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]published(nil), r.sent...)
}

// world is an engine on the fake network with one WhatsApp chat holding n messages from a contact, and the local
// API over it, listening on 127.0.0.1 on a free port.
type world struct {
	s       *store.Store
	wa      *fakenet.Network
	waLogin *bridgev2.UserLogin
	api     *localapi.Server
	pub     *recorder
	room    string
	events  []string // the chat's messages, oldest first
	url     string   // the MCP endpoint
	dbPath  string   // courier.db (storeOnly)
}

// storeOnly is a store and the local API over it, with no networks: enough for the HTTP guards.
func storeOnly(t *testing.T) *world {
	t.Helper()
	return storeOnlyLog(t, zerolog.Nop())
}

func storeOnlyLog(t *testing.T, log zerolog.Logger) *world {
	t.Helper()
	path := filepath.Join(t.TempDir(), "courier.db")
	s, err := store.Open(path)
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	w := &world{s: s, pub: &recorder{}, dbPath: path}
	w.api = localapi.New(s, rpc.NewDispatcher(rpc.Deps{Store: s, Search: search.New(s)}), w.pub, log)
	w.listen(t, localapi.Config{Enabled: true})
	return w
}

func (w *world) listen(t *testing.T, cfg localapi.Config) localapi.Status {
	t.Helper()
	st := w.api.Apply(context.Background(), cfg)
	t.Cleanup(w.api.Close)
	if st.Listening {
		w.url = fmt.Sprintf("http://127.0.0.1:%d%s", st.Port, localapi.MCPPath)
	}
	return st
}

func newWorld(t *testing.T, n int) *world {
	t.Helper()
	return newWorldLog(t, n, zerolog.Nop())
}

// newWorldLogging is newWorld with three messages whose local API logs every line to out.
func newWorldLogging(t *testing.T, out io.Writer) *world {
	t.Helper()
	return newWorldLog(t, 3, zerolog.New(out).Level(zerolog.DebugLevel))
}

func newWorldLog(t *testing.T, n int, log zerolog.Logger) *world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	s.SetMediaStore(m)
	w := &world{s: s, wa: fakenet.New(), pub: &recorder{}}
	eng, errs := engine.Start(ctx, dir, s, m, []engine.Spec{
		{Name: "whatsapp", Connector: func() (bridgev2.NetworkConnector, error) { return w.wa, nil }},
	}, zerolog.Nop())
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	h, ok := eng.Host("whatsapp")
	require.True(t, ok)
	w.waLogin, err = w.wa.Login(ctx, h.Bridge)
	require.NoError(t, err)
	// The account's state, as its bridge reports it (the fake network sends none of its own).
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", string(w.waLogin.ID), json.RawMessage(fmt.Sprintf(
		`{"state_event":"CONNECTED","remote_id":%q,"remote_name":"Test Account","timestamp":1760600000}`, w.waLogin.ID,
	))))
	w.say(t, n)
	s.SetNetworkNames(map[string]string{"whatsapp": "WhatsApp"})
	deps := rpc.Deps{
		Store: s, Engine: eng, Actions: actions.New(eng, s, m), Media: m, Search: search.New(s),
		Networks: []rpc.NetworkInfo{{Name: "whatsapp", DisplayName: "WhatsApp", Flows: []string{fakenet.ScriptFlow}}},
		Version:  "0.5.0-test", DataDir: dir,
	}
	w.api = localapi.New(s, rpc.NewDispatcher(deps), w.pub, log)
	st := w.listen(t, localapi.Config{Enabled: true})
	require.True(t, st.Listening, st.Error)
	return w
}

// say has the contact send k more messages into the chat, and waits until they are all stored.
func (w *world) say(t *testing.T, k int) {
	t.Helper()
	ctx := context.Background()
	start := len(w.events)
	for i := range k {
		w.wa.Incoming(w.waLogin, "chat1", "contact", fmt.Sprintf("m%d", start+i), fmt.Sprintf("message %d", start+i))
		// One at a time, so each has its own place in the history.
		require.Eventually(t, func() bool {
			rooms, err := w.s.ListRooms(ctx)
			if err != nil || len(rooms) == 0 {
				return false
			}
			w.room = rooms[0].ID
			evs, err := w.s.Events(ctx, w.room, 1000)
			return err == nil && len(evs) == start+i+1
		}, 5*time.Second, 5*time.Millisecond, "the bridge never stored message %d", start+i)
	}
	evs, err := w.s.Events(ctx, w.room, 1000)
	require.NoError(t, err)
	w.events = w.events[:0]
	for i := len(evs) - 1; i >= 0; i-- { // Events is newest first
		w.events = append(w.events, evs[i].EventID)
	}
}

// token makes a token and returns its secret.
func (w *world) token(t *testing.T, canSend bool) (store.APIToken, string) {
	t.Helper()
	tok, secret, err := w.s.CreateAPIToken(context.Background(), "Test client", canSend)
	require.NoError(t, err)
	return tok, secret
}

// bearer adds a token to every request.
type bearer struct {
	secret string
	base   http.RoundTripper
}

func (b bearer) RoundTrip(r *http.Request) (*http.Response, error) {
	r = r.Clone(r.Context())
	r.Header.Set("Authorization", "Bearer "+b.secret)
	return b.base.RoundTrip(r)
}

// connect is an MCP client session over HTTP with the token secret.
func (w *world) connect(t *testing.T, secret string) *mcp.ClientSession {
	t.Helper()
	c := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "1"}, nil)
	tr := &mcp.StreamableClientTransport{Endpoint: w.url, HTTPClient: &http.Client{Transport: bearer{secret, http.DefaultTransport}}, MaxRetries: -1, DisableStandaloneSSE: true}
	sess, err := c.Connect(context.Background(), tr, nil)
	require.NoError(t, err)
	t.Cleanup(func() { sess.Close() })
	return sess
}

// session is a session whose token may send when canSend.
func (w *world) session(t *testing.T, canSend bool) *mcp.ClientSession {
	t.Helper()
	_, secret := w.token(t, canSend)
	return w.connect(t, secret)
}

// call calls a tool and returns its text and whether it is a tool error.
func call(t *testing.T, sess *mcp.ClientSession, name string, args map[string]any) (string, bool) {
	t.Helper()
	res, err := sess.CallTool(context.Background(), &mcp.CallToolParams{Name: name, Arguments: args})
	require.NoError(t, err, name)
	require.Len(t, res.Content, 1, name)
	text, ok := res.Content[0].(*mcp.TextContent)
	require.True(t, ok, name)
	return text.Text, res.IsError
}

// ok calls a tool that must succeed and reads its JSON into out.
func ok(t *testing.T, sess *mcp.ClientSession, name string, args map[string]any, out any) {
	t.Helper()
	text, isErr := call(t, sess, name, args)
	require.False(t, isErr, "%s failed: %s", name, text)
	if out != nil {
		require.NoError(t, json.Unmarshal([]byte(text), out), text)
	}
}

// fails calls a tool that must fail and returns its message.
func fails(t *testing.T, sess *mcp.ClientSession, name string, args map[string]any) string {
	t.Helper()
	text, isErr := call(t, sess, name, args)
	require.True(t, isErr, "%s should have failed, got %s", name, text)
	return text
}

func toolCall(name string, args map[string]any) *mcp.CallToolParams {
	return &mcp.CallToolParams{Name: name, Arguments: args}
}

func base64URL(s string) string { return base64.RawURLEncoding.EncodeToString([]byte(s)) }
