// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/login"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/search"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/timers"
)

// socketPath is a place for a test's socket. A Unix socket path must be short (104 bytes on macOS), and a test's
// own temporary directory under Bazel is far longer, so it lives in a fresh directory under /tmp.
func socketPath(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "crpc")
	require.NoError(t, err)
	t.Cleanup(func() { os.RemoveAll(dir) })
	return filepath.Join(dir, "s")
}

// serve runs the server on a fresh socket until the test ends, and returns the socket's path.
func serve(t *testing.T, d Deps) string {
	t.Helper()
	path := socketPath(t)
	ln, err := net.Listen("unix", path)
	require.NoError(t, err)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Serve(ctx, ln, d) }()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			require.NoError(t, err, "Serve stops cleanly when its context ends")
		case <-time.After(10 * time.Second):
			t.Error("Serve did not return after its context ended")
		}
	})
	return path
}

// storeOnly is a server with a store and nothing else: enough for the handshake, the inbox and the change feed.
func storeOnly(t *testing.T) (*store.Store, string) {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s, serve(t, Deps{Store: s, Version: "test-1"})
}

// wireError is an error as it comes off the wire.
type wireError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data"`
}

// message is any line the server sends: an answer or a notification.
type message struct {
	ID     json.RawMessage `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
	Result json.RawMessage `json:"result"`
	Error  *wireError      `json:"error"`
	raw    []byte
}

// client is a test's end of a connection. A goroutine reads every line: answers go to whoever is waiting for
// that id, and notifications into notes.
type client struct {
	t     *testing.T
	conn  net.Conn
	mu    sync.Mutex
	next  int
	wait  map[string]chan message
	notes chan message
	gone  chan struct{} // closed when the server closes the connection (or the test does)
}

func dial(t *testing.T, path string) *client {
	t.Helper()
	conn, err := net.Dial("unix", path)
	require.NoError(t, err)
	c := &client{t: t, conn: conn, wait: map[string]chan message{}, notes: make(chan message, 100000), gone: make(chan struct{})}
	t.Cleanup(func() { conn.Close() })
	go c.readLoop()
	return c
}

func (c *client) readLoop() {
	defer close(c.gone)
	r := bufio.NewReaderSize(c.conn, 1<<20)
	for {
		line, err := r.ReadBytes('\n')
		if err != nil {
			return
		}
		var m message
		if err := json.Unmarshal(line, &m); err != nil {
			c.t.Errorf("the server sent a line that is not JSON: %q", line)
			return
		}
		m.raw = line
		if m.Method != "" {
			c.notes <- m
			continue
		}
		c.mu.Lock()
		ch := c.wait[string(m.ID)]
		delete(c.wait, string(m.ID))
		c.mu.Unlock()
		if ch == nil {
			c.t.Errorf("an answer nobody asked for: %s", line)
			continue
		}
		ch <- m
	}
}

// send writes one line and returns the channel its answer arrives on.
func (c *client) send(method string, params any) <-chan message {
	c.t.Helper()
	c.mu.Lock()
	c.next++
	id := fmt.Sprint(c.next)
	ch := make(chan message, 1)
	c.wait[id] = ch
	c.mu.Unlock()
	req := map[string]any{"jsonrpc": "2.0", "id": c.next, "method": method}
	if params != nil {
		req["params"] = params
	}
	b, err := json.Marshal(req)
	require.NoError(c.t, err)
	c.writeLine(b)
	return ch
}

func (c *client) writeLine(b []byte) {
	c.t.Helper()
	_, err := c.conn.Write(append(b, '\n'))
	require.NoError(c.t, err)
}

func (c *client) answer(ch <-chan message) message {
	c.t.Helper()
	select {
	case m := <-ch:
		return m
	case <-c.gone:
		c.t.Fatal("the connection closed before the answer came")
	case <-time.After(10 * time.Second):
		c.t.Fatal("no answer")
	}
	return message{}
}

// call sends a request and waits for its answer.
func (c *client) call(method string, params any) message {
	c.t.Helper()
	return c.answer(c.send(method, params))
}

// ok calls a method that must succeed and decodes its result into out (which may be nil).
func (c *client) ok(method string, params any, out any) {
	c.t.Helper()
	m := c.call(method, params)
	require.Nil(c.t, m.Error, "%s failed: %s", method, m.raw)
	if out != nil {
		require.NoError(c.t, json.Unmarshal(m.Result, out))
	}
}

// fails calls a method that must fail with code, and returns the error.
func (c *client) fails(code int, method string, params any) *wireError {
	c.t.Helper()
	m := c.call(method, params)
	require.NotNil(c.t, m.Error, "%s should have failed with %d: %s", method, code, m.raw)
	require.Equal(c.t, code, m.Error.Code, "%s: %s", method, m.raw)
	return m.Error
}

func (c *client) hello() {
	c.t.Helper()
	c.ok("hello", map[string]any{"protocol": Protocol, "client": "test/1"}, nil)
}

// changed waits for the first changed notification that match accepts.
func (c *client) changed(match func(changed) bool) changed {
	c.t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case m := <-c.notes:
			require.Equal(c.t, "changed", m.Method)
			var ch changed
			require.NoError(c.t, json.Unmarshal(m.Params, &ch))
			if match(ch) {
				return ch
			}
		case <-deadline:
			c.t.Fatal("no matching changed notification")
			return changed{}
		}
	}
}

func TestHelloIsRequiredAndVersioned(t *testing.T) {
	_, path := storeOnly(t)
	c := dial(t, path)

	e := c.fails(-32002, "inbox.list", nil)
	require.Equal(t, "hello first", e.Message)
	c.fails(-32002, "no.such.method", nil)

	e = c.fails(-32001, "hello", map[string]any{"protocol": Protocol + 1, "client": "test/2"})
	require.Equal(t, "protocol mismatch", e.Message)
	require.JSONEq(t, fmt.Sprintf(`{"engine": %d}`, Protocol), string(e.Data))
	c.fails(-32002, "inbox.list", nil) // a failed hello is no hello

	c.fails(-32602, "hello", map[string]any{"client": "test/1"})

	var res struct {
		Protocol int      `json:"protocol"`
		Engine   string   `json:"engine"`
		Networks []string `json:"networks"`
	}
	c.ok("hello", map[string]any{"protocol": Protocol, "client": "test/1"}, &res)
	require.Equal(t, Protocol, res.Protocol)
	require.Equal(t, "test-1", res.Engine)
	require.NotNil(t, res.Networks, "networks is a list, even an empty one")
	c.ok("inbox.list", nil, nil)
	c.ok("hello", map[string]any{"protocol": Protocol, "client": "test/1"}, nil) // again: the same answer

	// The handshake is per connection.
	c2 := dial(t, path)
	c2.fails(-32002, "inbox.list", nil)
}

// A later hello, after one succeeded, changes nothing: the right protocol answers the same, the wrong one is
// -32001, and either way the connection stays greeted with one change feed.
func TestASecondHelloLeavesTheConnectionAsItWas(t *testing.T) {
	s, path := storeOnly(t)
	c := dial(t, path)
	c.hello()
	e := c.fails(CodeProtocolMismatch, "hello", map[string]any{"protocol": Protocol + 1, "client": "test/2"})
	require.JSONEq(t, fmt.Sprintf(`{"engine": %d}`, Protocol), string(e.Data))
	c.ok("inbox.list", nil, nil) // still greeted
	c.hello()

	require.NoError(t, s.SetLoginState(context.Background(), "one", "", json.RawMessage(`{}`)))
	require.NoError(t, s.SetLoginState(context.Background(), "two", "", json.RawMessage(`{}`)))
	require.Equal(t, "one", c.changed(func(changed) bool { return true }).Network)
	require.Equal(t, "two", c.changed(func(changed) bool { return true }).Network, "each change once: one feed")
}

func TestHelloThenARequestRightBehindIt(t *testing.T) {
	_, path := storeOnly(t)
	c := dial(t, path)
	hello := c.send("hello", map[string]any{"protocol": Protocol, "client": "test/1"})
	inbox := c.send("inbox.list", nil) // pipelined: sent before the hello's answer came
	require.Nil(t, c.answer(hello).Error)
	require.Nil(t, c.answer(inbox).Error, "a request sent after hello is answered as after hello")
}

// The first thing a client reads is the answer to its hello, even while the store is busy: a notification never
// gets ahead of it.
func TestHelloAnswerComesBeforeAnyNotification(t *testing.T) {
	s, path := storeOnly(t)
	stop := make(chan struct{})
	busy := make(chan struct{})
	go func() {
		defer close(busy)
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			_ = s.SetLoginState(context.Background(), fmt.Sprintf("n%d", i%8), "", json.RawMessage(`{}`))
		}
	}()
	defer func() { close(stop); <-busy }()
	for range 200 {
		rawHello(t, path) // fails unless the first line is the hello's result
	}
}

// A change made as soon as hello has answered is notified: the connection is subscribed before the answer goes
// out. (It used to subscribe just after, and a change in between was never told; the conformance test's
// notification examples, which change the store right after hello, timed out now and then under load.)
func TestAChangeRightAfterHelloIsNotified(t *testing.T) {
	s, path := storeOnly(t)
	for i := range 300 {
		conn, r := rawHello(t, path)
		room := fmt.Sprintf("!r%d:courier.local", i)
		s.SetTyping(room, "@someone:courier.local", time.Now().Add(time.Minute))
		require.NoError(t, conn.SetReadDeadline(time.Now().Add(5*time.Second)))
		for {
			line, err := r.ReadBytes('\n')
			require.NoError(t, err, "connection %d was never told of the change made right after its hello", i)
			var m message
			require.NoError(t, json.Unmarshal(line, &m))
			var ch changed
			require.NoError(t, json.Unmarshal(m.Params, &ch))
			if ch.Kind == "typing" && ch.RoomID == room {
				break
			}
		}
		conn.Close()
	}
}

func TestOversizeFrameClosesConnection(t *testing.T) {
	_, path := storeOnly(t)

	// A line of exactly MaxFrameBytes is read and answered.
	c := dial(t, path)
	c.hello()
	frame := func(size int) []byte {
		head := `{"jsonrpc":"2.0","id":"big","method":"message.send","params":{"text":"`
		tail := `"}}`
		return []byte(head + strings.Repeat("x", size-len(head)-len(tail)) + tail)
	}
	c.mu.Lock()
	ch := make(chan message, 1)
	c.wait[`"big"`] = ch
	c.mu.Unlock()
	big := frame(MaxFrameBytes)
	require.Len(t, big, MaxFrameBytes)
	c.writeLine(big)
	m := c.answer(ch) // read whole and parsed: it is refused for its missing room_id, not for its size
	require.NotNil(t, m.Error)
	require.Equal(t, CodeInvalidParams, m.Error.Code)
	require.JSONEq(t, `{"reason":"room_id is required"}`, string(m.Error.Data))

	// One byte more closes the connection, without an answer.
	c2 := dial(t, path)
	c2.hello()
	_, err := c2.conn.Write(append(frame(MaxFrameBytes+1), '\n'))
	if err != nil {
		require.True(t, errors.Is(err, net.ErrClosed) || strings.Contains(err.Error(), "broken pipe") ||
			strings.Contains(err.Error(), "reset"), "writing may fail once the server has closed: %v", err)
	}
	select {
	case <-c2.gone:
	case <-time.After(10 * time.Second):
		t.Fatal("the server kept a connection that sent an oversize frame")
	}
	select {
	case m := <-c2.notes:
		t.Fatalf("nothing is sent for an oversize frame, got %s", m.raw)
	default:
	}

	// Without a newline at all: the server stops reading at the limit, not at the end of the line.
	c3 := dial(t, path)
	go func() { _, _ = c3.conn.Write(frame(MaxFrameBytes + 64*1024)) }()
	select {
	case <-c3.gone:
	case <-time.After(10 * time.Second):
		t.Fatal("the server kept reading an oversize frame that never ended")
	}

	// The server itself is fine.
	dial(t, path).hello()
}

func TestBadRequestsAreAnsweredAndTheConnectionGoesOn(t *testing.T) {
	_, path := storeOnly(t)
	c := dial(t, path)
	c.hello()
	for _, tc := range []struct {
		line string
		code int
		id   string
	}{
		{`{"jsonrpc":"2.0","id":7,"method":`, -32700, "null"},
		{`[{"jsonrpc":"2.0","id":7,"method":"inbox.list"}]`, -32600, "null"},
		{`"inbox.list"`, -32600, "null"},
		{`{"id":7,"method":"inbox.list"}`, -32600, "7"},
		{`{"jsonrpc":"1.0","id":"x","method":"inbox.list"}`, -32600, `"x"`},
		{`{"jsonrpc":"2.0","id":7,"method":5}`, -32600, "7"},
		{`{"jsonrpc":"2.0","id":{"a":1},"method":"inbox.list"}`, -32600, "null"},
		{`{"jsonrpc":"2.0","id":7,"method":"inbox.list","params":[1]}`, -32602, "7"},
		{`{"jsonrpc":"2.0","id":7,"method":"room.events","params":{"room_id":5}}`, -32602, "7"},
	} {
		c.mu.Lock()
		ch := make(chan message, 1)
		c.wait[tc.id] = ch
		c.mu.Unlock()
		c.writeLine([]byte(tc.line))
		m := c.answer(ch)
		require.NotNil(t, m.Error, tc.line)
		require.Equal(t, tc.code, m.Error.Code, tc.line)
		require.JSONEq(t, tc.id, string(m.ID), tc.line)
	}
	// A message with no id is a notification: not answered. The next request still is.
	c.writeLine([]byte(`{"jsonrpc":"2.0","method":"inbox.list"}`))
	c.ok("inbox.list", nil, nil)
}

// A key a method doesn't take is refused by name, so a misspelt parameter (replyTo for reply_to) can't be
// silently dropped.
func TestUnknownParametersAreRefusedByName(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	reason := func(e *wireError) string {
		t.Helper()
		var d struct {
			Reason string `json:"reason"`
		}
		require.NoError(t, json.Unmarshal(e.Data, &d))
		return d.Reason
	}
	e := c.fails(CodeInvalidParams, "hello", map[string]any{"protocol": Protocol, "client": "test/1", "clinet": "x"})
	require.Equal(t, "unknown parameter clinet", reason(e))
	c.hello()
	e = c.fails(CodeInvalidParams, "message.send", map[string]any{"room_id": w.room, "text": "hi", "replyTo": w.events[0]})
	require.Equal(t, "unknown parameter replyTo", reason(e))
	select {
	case got := <-w.wa.Sent:
		t.Fatalf("nothing is sent when a parameter is refused, got %+v", got)
	case <-time.After(100 * time.Millisecond):
	}
	e = c.fails(CodeInvalidParams, "inbox.list", map[string]any{"filter": "unread"})
	require.Equal(t, "unknown parameter filter", reason(e), "filters, not filter")
	e = c.fails(CodeInvalidParams, "room.events", map[string]any{"room_id": w.room, "before": map[string]any{"ts": 1, "seq": 1, "id": "x"}})
	require.Equal(t, "unknown parameter before.id", reason(e), "nested keys too")
	c.ok("inbox.list", map[string]any{}, nil)
}

func TestUnknownMethodIsMethodNotFound(t *testing.T) {
	_, path := storeOnly(t)
	c := dial(t, path)
	c.hello()
	e := c.fails(-32601, "room.archive", map[string]any{"room_id": "!r:courier.local"})
	require.Equal(t, "method not found", e.Message)
	require.NotContains(t, e.Message, "room.archive")
	c.ok("inbox.list", nil, nil)
}

func TestChangesReachEveryClient(t *testing.T) {
	s, path := storeOnly(t)
	a, b := dial(t, path), dial(t, path)
	a.hello()
	b.hello()
	quiet := dial(t, path) // never says hello: gets nothing

	require.NoError(t, s.SetLoginState(context.Background(), "whatsapp", "", json.RawMessage(`{"state_event":"CONNECTED"}`)))
	for _, c := range []*client{a, b} {
		got := c.changed(func(ch changed) bool { return true })
		require.Equal(t, changed{Kind: "bridge", Network: "whatsapp"}, got)
	}
	select {
	case m := <-quiet.notes:
		t.Fatalf("a connection that has not said hello is sent nothing, got %s", m.raw)
	case <-time.After(200 * time.Millisecond):
	}
}

// overflowed is what a client that read nothing got once it read again.
type overflowed struct {
	sent, got     int               // changes sent through the store, and changed notifications that arrived for them
	resyncs       []json.RawMessage // the params of each resync that arrived, in order
	lastWasResync bool
	backToBack    int           // resyncs that arrived straight after another resync, with no change between
	resyncAfter   time.Duration // from the end of the burst to the last resync's arrival
}

// requireToldToResync checks what a client that fell behind must be able to rely on. It is told to resync at
// least once, and the last thing it hears is a resync, so it re-reads after everything that was kept. A resync
// never follows another one directly, and a resync carries nothing else. How many resyncs arrive depends on how
// many times the client fell behind during the burst, which depends on scheduling, so the count is not fixed.
func requireToldToResync(t *testing.T, o overflowed) {
	t.Helper()
	require.NotEmpty(t, o.resyncs, "a client that fell behind is told to resync")
	require.True(t, o.lastWasResync, "the last thing it hears is a resync, after everything that was kept")
	require.Zero(t, o.backToBack, "a resync never follows another one directly")
	for _, r := range o.resyncs {
		require.JSONEq(t, `{"kind":"resync"}`, string(r), "a resync carries nothing else")
	}
}

// overflow sends changes through the store while conn, a connection that has said hello, reads nothing, so its
// notifications back up through the socket and the server into the store, which drops them. Then, with nothing
// changing any more, it reads what arrives until the line goes quiet. The changes are bridge changes for networks
// n0, n1, ... in order. If nothing was dropped (a host with unusually large socket buffers), it goes again with a
// bigger burst.
func overflow(t *testing.T, s *store.Store, conn net.Conn, r *bufio.Reader) overflowed {
	t.Helper()
	ctx := context.Background()
	var o overflowed
	for burst := overflowBurst; ; burst *= 4 {
		require.Less(t, burst, 1<<20, "the store never dropped a change for a client that reads nothing")
		for i := 0; i < burst; i++ {
			require.NoError(t, s.SetLoginState(ctx, fmt.Sprintf("n%d", o.sent), "", json.RawMessage(`{}`)))
			o.sent++
		}
		ended := time.Now()
		for {
			require.NoError(t, conn.SetReadDeadline(time.Now().Add(500*time.Millisecond)))
			line, err := r.ReadBytes('\n')
			if err != nil {
				var ne net.Error
				require.True(t, errors.As(err, &ne) && ne.Timeout(), "the connection must stay open: %v", err)
				require.NoError(t, conn.SetReadDeadline(time.Time{}))
				break
			}
			var m message
			require.NoError(t, json.Unmarshal(line, &m))
			require.Equal(t, "changed", m.Method)
			var ch changed
			require.NoError(t, json.Unmarshal(m.Params, &ch))
			wasResync := o.lastWasResync
			o.lastWasResync = ch.Kind == "resync"
			if o.lastWasResync {
				if wasResync {
					o.backToBack++
				}
				o.resyncs = append(o.resyncs, m.Params)
				o.resyncAfter = time.Since(ended)
				continue
			}
			o.got++
		}
		if o.got < o.sent {
			return o
		}
		require.Empty(t, o.resyncs, "nothing was dropped, so there is no resync")
	}
}

// rawHello opens a connection and says hello on it without starting a reader, so the test decides when to read.
func rawHello(t *testing.T, path string) (net.Conn, *bufio.Reader) {
	t.Helper()
	conn, err := net.Dial("unix", path)
	require.NoError(t, err)
	t.Cleanup(func() { conn.Close() })
	_, err = fmt.Fprintf(conn, `{"jsonrpc":"2.0","id":1,"method":"hello","params":{"protocol":%d,"client":"test/1"}}`+"\n", Protocol)
	require.NoError(t, err)
	r := bufio.NewReader(conn)
	line, err := r.ReadBytes('\n')
	require.NoError(t, err)
	require.Contains(t, string(line), `"result"`)
	return conn, r
}

// overflowBurst is comfortably more than fits between the store and a client that reads nothing: the store's
// buffer, the server's queue and both ends of the socket (a few hundred lines with default socket buffers).
const overflowBurst = 4000

func TestSlowClientIsToldToResync(t *testing.T) {
	s, path := storeOnly(t)
	conn, r := rawHello(t, path)
	keepsUp := dial(t, path)
	keepsUp.hello()

	o := overflow(t, s, conn, r)
	require.Greater(t, o.got, store.SubscriberBuffer, "what fitted was delivered, the store's buffer and more")
	require.Less(t, o.got, o.sent, "the client read nothing, so changes must have been dropped")
	t.Logf("%d changes sent, %d reached the client that read nothing", o.sent, o.got)
	requireToldToResync(t, o)

	// Later changes come as they are: the drop was already reported.
	require.NoError(t, s.SetLoginState(context.Background(), "after", "", json.RawMessage(`{}`)))
	require.NoError(t, s.SetLoginState(context.Background(), "later", "", json.RawMessage(`{}`)))
	var kinds []string
	require.NoError(t, conn.SetReadDeadline(time.Now().Add(10*time.Second)))
	for len(kinds) < 2 {
		line, err := r.ReadBytes('\n')
		require.NoError(t, err)
		var m message
		require.NoError(t, json.Unmarshal(line, &m))
		var ch changed
		require.NoError(t, json.Unmarshal(m.Params, &ch))
		kinds = append(kinds, ch.Kind+":"+ch.Network)
	}
	require.Equal(t, []string{"bridge:after", "bridge:later"}, kinds, "no second resync")

	// A client that was reading the whole time never loses a change silently: it gets every change in order, or,
	// if it too fell behind (a starved machine can make any reader fall behind a burst this size), a resync
	// after the changes it did get. It never gets a change out of order and never misses one without a resync.
	next := 0
	for next < o.sent {
		ch := keepsUp.changed(func(changed) bool { return true })
		if ch.Kind == "resync" {
			t.Logf("the reading client also fell behind after %d of %d changes, and was told to resync", next, o.sent)
			return
		}
		require.Equal(t, changed{Kind: "bridge", Network: fmt.Sprintf("n%d", next)}, ch, "changes arrive in order, none skipped without a resync")
		next++
	}
}

// Review Focus 2: a drop is reported even when nothing changes after it, so the inbox can't go stale in a quiet
// moment that follows a burst.
func TestResyncArrivesEvenIfNothingChangesAfterTheDrop(t *testing.T) {
	s, path := storeOnly(t)
	conn, r := rawHello(t, path)
	o := overflow(t, s, conn, r) // nothing changes once the burst ends
	require.Less(t, o.got, o.sent)
	requireToldToResync(t, o)
	require.Less(t, o.resyncAfter, 2*time.Second, "promptly, as soon as the client has read what was kept")
}

// world is an engine on the fake network over a real store, and the server over it. whatsapp is linked and has
// one chat with three messages from a contact; signal is running and not linked; telegram is not started.
type world struct {
	s       *store.Store
	m       *media.Store
	eng     *engine.Engine
	wa, sig *fakenet.Network
	waLogin *bridgev2.UserLogin
	d       *login.Driver
	ent     *switchable // allows everything until a test denies it
	deps    Deps
	path    string
	room    string   // the whatsapp chat
	events  []string // its three messages, oldest first
}

var testNetworks = []NetworkInfo{
	{Name: "whatsapp", DisplayName: "WhatsApp", Flows: []string{fakenet.ScriptFlow}},
	{Name: "signal", DisplayName: "Signal", Flows: []string{fakenet.ScriptFlow}},
	{Name: "telegram", DisplayName: "Telegram", Flows: []string{"qr", "phone"}},
}

func testFlows(name string) ([]string, bool) {
	for _, n := range testNetworks {
		if n.Name == name {
			return n.Flows, true
		}
	}
	return nil, false
}

func newWorld(t *testing.T) *world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	w := &world{s: s, m: m, wa: fakenet.New(), sig: fakenet.New()}
	eng, errs := engine.Start(ctx, dir, s, m, []engine.Spec{
		{Name: "whatsapp", Connector: func() (bridgev2.NetworkConnector, error) { return w.wa, nil }},
		{Name: "signal", Connector: func() (bridgev2.NetworkConnector, error) { return w.sig, nil }},
		// As networks does for Telegram without its app credentials: the engine keeps the reason for the app.
		{Name: "telegram", Connector: func() (bridgev2.NetworkConnector, error) {
			return nil, errors.New("Telegram needs an api_id and api_hash")
		}},
	}, zerolog.Nop())
	require.Len(t, errs, 1)
	require.Error(t, errs["telegram"])
	t.Cleanup(eng.Stop)
	w.eng = eng
	h, ok := eng.Host("whatsapp")
	require.True(t, ok)
	w.waLogin, err = w.wa.Login(ctx, h.Bridge)
	require.NoError(t, err)

	for i, body := range []string{"one", "two", "three"} {
		w.wa.Incoming(w.waLogin, "chat1", "contact", fmt.Sprintf("m%d", i), body)
		require.Eventually(t, func() bool {
			rooms, err := s.ListRooms(ctx)
			if err != nil || len(rooms) != 1 {
				return false
			}
			evs, err := s.Events(ctx, rooms[0].ID, 10)
			if err != nil || len(evs) != i+1 {
				return false
			}
			w.room = rooms[0].ID
			w.events = append(w.events, evs[0].EventID)
			return true
		}, 5*time.Second, 10*time.Millisecond, "the bridge never stored message %d", i)
	}

	// As courier-engine does: account titles and muted_by_name read "WhatsApp", not "whatsapp" (Ruling 5).
	names := map[string]string{}
	for _, n := range testNetworks {
		names[n.Name] = n.DisplayName
	}
	s.SetNetworkNames(names)
	w.d = login.NewDriver(eng, s, testFlows)
	a := actions.New(eng, s, m)
	a.LoginWait = 5 * time.Second
	w.ent = &switchable{}
	w.deps = Deps{
		Store: s, Engine: eng, Actions: a, Login: w.d, Media: m, Search: search.New(s),
		Timers:      timers.New(s, w.ent, timers.RealClock{}, zerolog.Nop()), // not run: a poke just waits
		Entitlement: w.ent,
		Networks:    testNetworks,
		Version:     "0.3.0-test",
	}
	w.path = serve(t, w.deps)
	return w
}

func TestLoginOverTheSocket(t *testing.T) {
	w := newWorld(t)
	w.sig.Script = &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{
		qrStep(), usernameStep(), completeStep(),
	}}
	c := dial(t, w.path)
	c.hello()

	var step login.Step
	c.ok("login.start", map[string]any{"network": "signal", "flow": fakenet.ScriptFlow}, &step)
	require.Equal(t, login.StepDisplayAndWait, step.Type)
	require.Equal(t, "qr", step.Display.Kind)
	id := step.LoginID

	c.fails(-32017, "login.start", map[string]any{"network": "signal"}) // one at a time per network

	c.ok("login.wait", map[string]any{"login_id": id}, &step)
	require.Equal(t, login.StepUserInput, step.Type)
	require.Equal(t, "username", step.Fields[0].ID)

	c.fails(-32014, "login.wait", map[string]any{"login_id": id}) // this step wants input, not the phone

	c.ok("login.submit", map[string]any{"login_id": id, "values": map[string]string{"username": "example-user"}}, &step)
	require.Equal(t, login.StepComplete, step.Type)
	require.Equal(t, "Test Account", step.RemoteName)
	require.Equal(t, []map[string]string{{"username": "example-user"}}, w.sig.Script.Submitted())

	c.fails(-32015, "login.wait", map[string]any{"login_id": id}) // it is over
	c.ok("login.cancel", map[string]any{"login_id": id}, nil)     // harmless
	require.Zero(t, w.sig.Script.Cancelled(), "a completed sign-in is not cancelled")
}

func TestClosingTheConnectionCancelsItsSignIn(t *testing.T) {
	w := newWorld(t)
	script := &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{qrStep(), completeStep()}, Hold: make(chan struct{})}
	w.sig.Script = script
	c := dial(t, w.path)
	c.hello()
	var step login.Step
	c.ok("login.start", map[string]any{"network": "signal", "flow": fakenet.ScriptFlow}, &step)
	c.send("login.wait", map[string]any{"login_id": step.LoginID})
	time.Sleep(50 * time.Millisecond) // let the wait block on the phone
	c.conn.Close()
	require.Eventually(t, func() bool { return script.Cancelled() == 1 }, 5*time.Second, 10*time.Millisecond,
		"closing the connection cancels the login.wait in flight, and so the sign-in")
}

func TestRequestsDoNotWaitForEachOther(t *testing.T) {
	w := newWorld(t)
	script := &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{qrStep(), completeStep()}, Hold: make(chan struct{})}
	w.sig.Script = script
	c := dial(t, w.path)
	c.hello()
	var step login.Step
	c.ok("login.start", map[string]any{"network": "signal", "flow": fakenet.ScriptFlow}, &step)
	waiting := c.send("login.wait", map[string]any{"login_id": step.LoginID})
	c.ok("inbox.list", nil, nil) // answered while the wait is still blocked
	select {
	case m := <-waiting:
		t.Fatalf("the wait should still be blocked: %s", m.raw)
	default:
	}
	close(script.Hold)
	m := c.answer(waiting)
	require.Nil(t, m.Error, "%s", m.raw)
}

func TestErrorsNeverEchoWhatWasSent(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()
	const secret = "do-not-echo-7a1c"
	check := func(e *wireError) {
		t.Helper()
		require.NotContains(t, e.Message, secret)
		require.NotContains(t, string(e.Data), secret)
	}
	check(c.fails(-32014, "login.start", map[string]any{"network": secret}))
	check(c.fails(-32014, "login.start", map[string]any{"network": "signal", "flow": secret}))
	check(c.fails(-32602, "message.sendFile", map[string]any{"room_id": w.room, "path": "/nonexistent/" + secret + ".png"}))
	check(c.fails(-32602, "message.sendFile", map[string]any{"room_id": w.room, "path": secret + ".png"}))
	check(c.fails(-32020, "room.events", map[string]any{"room_id": "!" + secret + ":courier.local"}))
	check(c.fails(-32020, "message.send", map[string]any{"room_id": w.room, "text": "hi", "reply_to": "$" + secret}))
	check(c.fails(-32015, "login.submit", map[string]any{"login_id": secret, "values": map[string]string{}}))

	w.sig.Script = &fakenet.ScriptedLogin{Steps: []*bridgev2.LoginStep{codeStep()}}
	var step login.Step
	c.ok("login.start", map[string]any{"network": "signal", "flow": fakenet.ScriptFlow}, &step)
	check(c.fails(-32014, "login.submit", map[string]any{"login_id": step.LoginID, "values": map[string]string{"code": secret}}))
}

func TestMessagesOverTheSocket(t *testing.T) {
	w := newWorld(t)
	c := dial(t, w.path)
	c.hello()

	var page struct {
		Events []struct {
			EventID    string `json:"event_id"`
			Mine       bool   `json:"mine"`
			SenderName string `json:"sender_name"`
			TS         int64  `json:"ts"`
		} `json:"events"`
		Before *struct {
			TS  int64 `json:"ts"`
			Seq int64 `json:"seq"`
		} `json:"before"`
	}
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 2}, &page)
	require.Len(t, page.Events, 2)
	require.Equal(t, w.events[2], page.Events[0].EventID, "newest first")
	require.NotNil(t, page.Before)
	require.Greater(t, page.Events[0].TS, int64(1_000_000_000_000), "times are Unix milliseconds")
	require.Equal(t, "whatsapp_contact", page.Events[0].SenderName, "no profile name: the localpart")
	c.ok("room.events", map[string]any{"room_id": w.room, "before": page.Before, "limit": 2}, &page)
	require.Len(t, page.Events, 1)
	require.Equal(t, w.events[0], page.Events[0].EventID)
	require.Nil(t, page.Before)
	c.fails(-32602, "room.events", map[string]any{"room_id": w.room, "limit": 101})
	c.fails(-32602, "room.events", map[string]any{"room_id": w.room, "limit": 0})

	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": w.room, "text": "hello there", "reply_to": w.events[2]}, &sent)
	got := <-w.wa.Sent
	require.Equal(t, "hello there", got.Body)
	c.changed(func(ch changed) bool { return ch.Kind == "event" && ch.EventID == sent.EventID })
	c.fails(-32011, "message.send", map[string]any{"room_id": w.room, "text": "!whatsapp help"})
	c.fails(-32602, "message.send", map[string]any{"room_id": w.room, "text": "  "})

	var inbox struct {
		Rooms []struct {
			RoomID      string `json:"room_id"`
			Unread      int    `json:"unread"`
			Muted       bool   `json:"muted"`
			PreviewMine bool   `json:"preview_mine"`
		} `json:"rooms"`
	}
	c.ok("room.setMuted", map[string]any{"room_id": w.room, "muted": true}, nil)
	c.ok("room.markRead", map[string]any{"room_id": w.room}, nil)
	c.ok("inbox.list", nil, &inbox)
	require.Len(t, inbox.Rooms, 1)
	require.True(t, inbox.Rooms[0].Muted)
	require.Zero(t, inbox.Rooms[0].Unread)

	var accounts struct {
		Accounts []struct {
			Network    string `json:"network"`
			State      string `json:"state"`
			NotStarted string `json:"not_started"`
		} `json:"accounts"`
	}
	c.ok("accounts.list", nil, &accounts)
	require.Len(t, accounts.Accounts, 3)
	require.Equal(t, "telegram", accounts.Accounts[2].Network)
	require.Equal(t, "NOT_STARTED", accounts.Accounts[2].State)
	require.Equal(t, "Telegram needs an api_id and api_hash", accounts.Accounts[2].NotStarted)

	// A chat on a network with no account.
	require.NoError(t, w.s.UpsertRoom(context.Background(), store.Room{ID: "!unlinked:courier.local", Network: "signal"}))
	c.fails(-32010, "message.send", map[string]any{"room_id": "!unlinked:courier.local", "text": "hi"})
}

func TestPathsAreAbsoluteAndOnlyForFilesThatExist(t *testing.T) {
	w := newWorld(t)
	ctx := context.Background()
	c := dial(t, w.path)
	c.hello()

	avatar, err := w.m.Put([]byte("a picture"))
	require.NoError(t, err)
	r, ok, err := w.s.GetRoom(ctx, w.room)
	require.NoError(t, err)
	require.True(t, ok)
	r.AvatarURI = string(ids.ContentURI(avatar))
	require.NoError(t, w.s.UpsertRoom(ctx, r))
	missing := strings.Repeat("ab", 32) // a well-formed hash the media store does not have
	name := "Contact"
	gone := string(ids.ContentURI(missing))
	require.NoError(t, w.s.SetProfile(ctx, "@whatsapp_contact:courier.local", &name, &gone))

	var inbox struct {
		Rooms []struct {
			AvatarPath string `json:"avatar_path"`
		} `json:"rooms"`
	}
	c.ok("inbox.list", nil, &inbox)
	want, err := w.m.Path(avatar)
	require.NoError(t, err)
	require.True(t, filepath.IsAbs(inbox.Rooms[0].AvatarPath))
	require.Equal(t, want, inbox.Rooms[0].AvatarPath)

	file := filepath.Join(t.TempDir(), "notes.txt")
	require.NoError(t, os.WriteFile(file, []byte("some notes"), 0o600))
	var sent struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.sendFile", map[string]any{"room_id": w.room, "path": file}, &sent)
	<-w.wa.Files

	var page struct {
		Events []struct {
			EventID          string `json:"event_id"`
			SenderName       string `json:"sender_name"`
			SenderAvatarPath string `json:"sender_avatar_path"`
			MediaPath        string `json:"media_path"`
			Mine             bool   `json:"mine"`
		} `json:"events"`
	}
	c.ok("room.events", map[string]any{"room_id": w.room}, &page)
	require.Len(t, page.Events, 4)
	mine := page.Events[0]
	require.Equal(t, sent.EventID, mine.EventID)
	require.True(t, mine.Mine)
	require.True(t, filepath.IsAbs(mine.MediaPath))
	b, err := os.ReadFile(mine.MediaPath)
	require.NoError(t, err)
	require.Equal(t, "some notes", string(b), "media_path is the file that was sent")
	theirs := page.Events[1]
	require.False(t, theirs.Mine)
	require.Equal(t, "Contact", theirs.SenderName, "the profile's name")
	require.Empty(t, theirs.SenderAvatarPath, "a picture the engine does not have is no path")
	require.Empty(t, theirs.MediaPath, "a text message has no media")
}

// The store's status column defaults to "": an event stored without one is one the network has, so the wire
// says sent, never an empty status.
func TestAnEventStoredWithoutAStatusIsSent(t *testing.T) {
	w := newWorld(t)
	_, err := w.s.InsertEvent(context.Background(), store.Event{
		RoomID: w.room, EventID: "$nostatus", Sender: "@whatsapp_contact:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"x"}`), TS: time.Now(),
	})
	require.NoError(t, err)
	c := dial(t, w.path)
	c.hello()
	var page struct {
		Events []struct {
			EventID string `json:"event_id"`
			Status  string `json:"status"`
		} `json:"events"`
	}
	c.ok("room.events", map[string]any{"room_id": w.room, "limit": 1}, &page)
	require.Equal(t, "$nostatus", page.Events[0].EventID)
	require.Equal(t, "sent", page.Events[0].Status)
}

// syncBuffer is a log destination tests can read while the server writes to it.
type syncBuffer struct {
	mu sync.Mutex
	b  strings.Builder
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.String()
}

// Only the engine's own failures are logged, with the method and the error, never the params. An error that maps
// to a code of its own is the caller's business and is not logged: its text can carry a network, a flow or a path.
func TestOnlyInternalErrorsAreLoggedAndNeverTheParams(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	var logs syncBuffer
	path := serve(t, Deps{Store: s, Version: "test-1", Log: zerolog.New(&logs)})
	c := dial(t, path)
	c.hello()
	const secret = "do-not-log-5e2b"

	c.fails(CodeNotFound, "room.events", map[string]any{"room_id": "!" + secret + ":courier.local"})
	c.fails(CodeInvalidParams, "room.events", map[string]any{"room_id": "!r:courier.local", "limit": 1000})
	require.Empty(t, logs.String(), "errors with a code of their own are not logged")

	c.fails(CodeInternal, "login.cancel", map[string]any{"login_id": secret}) // no login driver: an internal error
	require.Eventually(t, func() bool { return strings.Contains(logs.String(), "login.cancel") }, 5*time.Second, 10*time.Millisecond)
	line := logs.String()
	require.Contains(t, line, `"level":"error"`)
	require.Contains(t, line, errMissing.Error(), "the real cause is in the log")
	require.NotContains(t, line, secret, "params are never logged")
}

func TestAPanicIsAnInternalErrorAndIsLoggedWithItsStack(t *testing.T) {
	var logs syncBuffer
	d := &Deps{Log: zerolog.New(&logs)}
	res, err := run(context.Background(), d, "test.panic", func(context.Context, *Deps, json.RawMessage) (any, error) {
		panic("boom")
	}, nil)
	require.Nil(t, res)
	require.Equal(t, CodeInternal, toError(err).Code)
	out := logs.String()
	require.Contains(t, out, `"level":"error"`)
	require.Contains(t, out, "test.panic")
	require.Contains(t, out, "boom")
	require.Contains(t, out, "goroutine", "the stack is logged")
}

func TestNotificationsMapEveryStoreChange(t *testing.T) {
	for kind, want := range map[string]struct {
		c  changed
		ok bool
	}{
		"room":     {changed{Kind: "room", RoomID: "!r"}, true},
		"member":   {changed{Kind: "room", RoomID: "!r"}, true},
		"profile":  {changed{Kind: "room"}, true},
		"event":    {changed{Kind: "event", RoomID: "!r", EventID: "$e"}, true},
		"status":   {changed{Kind: "status", RoomID: "!r", EventID: "$e"}, true},
		"read":     {changed{Kind: "read", RoomID: "!r", EventID: "$e"}, true},
		"bridge":   {changed{Kind: "bridge", Network: "!r"}, true},
		"spaces":   {changed{Kind: "spaces"}, true},
		"typing":   {changed{Kind: "typing", RoomID: "!r"}, true},
		"reminder": {changed{Kind: "reminder", RoomID: "!r"}, true},
		// Ruling 7: a chat's scheduled messages changed (scheduled, changed, sent, canceled, missed or deleted).
		"scheduled": {changed{Kind: "scheduled", RoomID: "!r"}, true},
		// Protocol 5: a read receipt or a delivery arrived for a message in the chat.
		"receipt": {changed{Kind: "receipt", RoomID: "!r"}, true},
		"resync":  {changed{Kind: "resync"}, true},
		"unknown": {changed{Kind: "resync"}, true}, // a kind this code doesn't know: re-read everything rather than miss it
	} {
		roomID, eventID := "!r", ""
		if kind == "event" || kind == "status" || kind == "read" {
			eventID = "$e"
		}
		if kind == "profile" || kind == "resync" || kind == "unknown" || kind == "spaces" {
			roomID = ""
		}
		got := notification(store.Change{Kind: kind, RoomID: roomID, EventID: eventID})
		require.Equal(t, want.c, got, kind)
	}
}

func qrStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeDisplayAndWait, StepID: "fi.mau.signal.qr",
		Instructions:         "Scan the QR code with the app on your phone.",
		DisplayAndWaitParams: &bridgev2.LoginDisplayAndWaitParams{Type: bridgev2.LoginDisplayTypeQR, Data: "sgnl://linkdevice?uuid=example"},
	}
}

func usernameStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeUserInput, StepID: "fi.mau.signal.input", Instructions: "Enter your details.",
		UserInputParams: &bridgev2.LoginUserInputParams{Fields: []bridgev2.LoginInputDataField{
			{Type: bridgev2.LoginInputFieldTypeUsername, ID: "username", Name: "Username", Description: "The name you sign in with"},
		}},
	}
}

func codeStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeUserInput, StepID: "fi.mau.signal.code", Instructions: "Enter the code.",
		UserInputParams: &bridgev2.LoginUserInputParams{Fields: []bridgev2.LoginInputDataField{
			{Type: bridgev2.LoginInputFieldType2FACode, ID: "code", Name: "Code", Description: "The code the app shows", Pattern: "^[0-9]{6}$"},
		}},
	}
}

func completeStep() *bridgev2.LoginStep {
	return &bridgev2.LoginStep{
		Type: bridgev2.LoginStepTypeComplete, StepID: "fi.mau.signal.complete",
		CompleteParams: &bridgev2.LoginCompleteParams{
			UserLoginID: "signal-login",
			UserLogin:   &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: "signal-login", RemoteName: "Test Account"}},
		},
	}
}

// slowNet is a fake network whose bridge start-up waits for release, as a slow bridge's does.
type slowNet struct {
	*fakenet.Network
	entered, release chan struct{}
}

func (n *slowNet) Start(ctx context.Context) error {
	close(n.entered)
	<-n.release
	return n.Network.Start(ctx)
}

// A network the engine hasn't started yet is STARTING: no reason, no error, so the app shows no banner. Once it is up
// it says what its bridge says (UNCONFIGURED: nothing linked yet), and once an account is linked and connected, the
// account's own state, not the UNCONFIGURED from before.
func TestAccountsSayStarting(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })

	n := &slowNet{Network: fakenet.New(), entered: make(chan struct{}), release: make(chan struct{})}
	specs := []engine.Spec{{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	path := serve(t, Deps{Store: s, Engine: eng, Networks: []NetworkInfo{{Name: "fake", DisplayName: "Fake", Flows: []string{"qr"}}}})
	c := dial(t, path)
	c.hello()

	type wireAccount struct {
		Network    string `json:"network"`
		State      string `json:"state"`
		Error      string `json:"error"`
		RemoteName string `json:"remote_name"`
		NotStarted string `json:"not_started"`
	}
	accounts := func() []wireAccount {
		var res struct {
			Accounts []wireAccount `json:"accounts"`
		}
		c.ok("accounts.list", nil, &res)
		return res.Accounts
	}
	require.Equal(t, []wireAccount{{Network: "fake", State: "STARTING"}}, accounts(), "before the engine reaches it")

	done := make(chan struct{})
	go func() {
		defer close(done)
		eng.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, specs, zerolog.Nop())
	}()
	<-n.entered
	require.Equal(t, []wireAccount{{Network: "fake", State: "STARTING"}}, accounts(), "while its bridge starts")

	close(n.release)
	<-done
	c.changed(func(ch changed) bool { return ch.Kind == "bridge" && ch.Network == "fake" })
	require.Equal(t, []wireAccount{{Network: "fake", State: "UNCONFIGURED"}}, accounts(), "running, nothing linked")

	h, ok := eng.Host("fake")
	require.True(t, ok)
	login, err := n.Login(ctx, h.Bridge)
	require.NoError(t, err)
	// As the bridge says it, in the same second as its UNCONFIGURED, say: the login's state wins a tie.
	require.NoError(t, s.SetLoginState(ctx, "fake", string(login.ID), json.RawMessage(fmt.Sprintf(
		`{"state_event":"CONNECTED","remote_id":%q,"remote_name":"Me","timestamp":%d}`, login.ID, time.Now().Unix(),
	))))
	require.Equal(t, []wireAccount{{Network: "fake", State: "CONNECTED", RemoteName: "Me"}}, accounts())
}

// The bridge's own state (login ID "") is the account's only while no login has spoken since it: it is UNCONFIGURED
// from before linking, and again when a start finds the login gone.
func TestAccountStateIsTheLoginsOverTheBridgesOwn(t *testing.T) {
	ctx := context.Background()
	state := func(event, remoteID string, ts int64) json.RawMessage {
		return json.RawMessage(fmt.Sprintf(`{"state_event":%q,"remote_id":%q,"timestamp":%d}`, event, remoteID, ts))
	}
	for name, c := range map[string]struct {
		own, login json.RawMessage // nil: none
		want       string
	}{
		"nothing linked":                  {own: state("UNCONFIGURED", "", 100), want: "UNCONFIGURED"},
		"linked since":                    {own: state("UNCONFIGURED", "", 100), login: state("CONNECTED", "L1", 200), want: "CONNECTED"},
		"a tie goes to the login":         {own: state("UNCONFIGURED", "", 200), login: state("CONNECTED", "L1", 200), want: "CONNECTED"},
		"only a login":                    {login: state("TRANSIENT_DISCONNECT", "L1", 200), want: "TRANSIENT_DISCONNECT"},
		"the login gone at a later start": {own: state("UNCONFIGURED", "", 300), login: state("LOGGED_OUT", "L1", 200), want: "UNCONFIGURED"},
		"no time on either":               {own: json.RawMessage(`{"state_event":"UNCONFIGURED"}`), login: json.RawMessage(`{"state_event":"CONNECTED"}`), want: "CONNECTED"},
	} {
		t.Run(name, func(t *testing.T) {
			s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
			require.NoError(t, err)
			defer s.Close()
			// The login's row is written first, so the newest row is the bridge's own in every case.
			if c.login != nil {
				require.NoError(t, s.SetLoginState(ctx, "fake", "L1", c.login))
			}
			if c.own != nil {
				require.NoError(t, s.SetLoginState(ctx, "fake", "", c.own))
			}
			raw, ok, err := accountState(ctx, s, "fake", nil)
			require.NoError(t, err)
			require.True(t, ok)
			var st struct {
				StateEvent string `json:"state_event"`
			}
			require.NoError(t, json.Unmarshal(raw, &st))
			require.Equal(t, c.want, st.StateEvent)
		})
	}
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	_, ok, err := accountState(ctx, s, "fake", nil)
	require.NoError(t, err)
	require.False(t, ok, "no state at all")
}

// An account's state outlives it: one the bridge has deleted (signed out from the network's side, say) leaves its
// LOGGED_OUT row. The network's account shows the accounts the bridge has, never one that is gone.
func TestAccountStateIgnoresALoginThatIsGone(t *testing.T) {
	ctx := context.Background()
	state := func(event, remoteID string, ts int64) json.RawMessage {
		return json.RawMessage(fmt.Sprintf(`{"state_event":%q,"remote_id":%q,"timestamp":%d}`, event, remoteID, ts))
	}
	live := func(id string) bool { return id == "L2" }
	for name, c := range map[string]struct {
		rows map[string]json.RawMessage
		want string // "" is no state at all
	}{
		"the account there, not the one gone": {
			rows: map[string]json.RawMessage{"L1": state("LOGGED_OUT", "L1", 300), "L2": state("CONNECTED", "L2", 200)},
			want: "CONNECTED",
		},
		"the bridge's own once no live login has spoken": {
			rows: map[string]json.RawMessage{"": state("UNCONFIGURED", "", 100), "L1": state("LOGGED_OUT", "L1", 300)},
			want: "UNCONFIGURED",
		},
		"nothing when only a gone login has a state": {
			rows: map[string]json.RawMessage{"L1": state("CONNECTED", "L1", 300)},
		},
	} {
		t.Run(name, func(t *testing.T) {
			s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
			require.NoError(t, err)
			defer s.Close()
			for id, raw := range c.rows {
				require.NoError(t, s.SetLoginState(ctx, "fake", id, raw))
			}
			raw, ok, err := accountState(ctx, s, "fake", live)
			require.NoError(t, err)
			require.Equal(t, c.want != "", ok)
			if ok {
				var st struct {
					StateEvent string `json:"state_event"`
				}
				require.NoError(t, json.Unmarshal(raw, &st))
				require.Equal(t, c.want, st.StateEvent)
			}
		})
	}
}

// An account's space doesn't vanish at launch while its network starts: a network still starting whose account was
// linked (it has a login's state from an earlier run) keeps its space, and one with no account has none. When the
// network's bridge is up the app is told spaces changed, so the bar reads them again.
func TestALinkedNetworksSpaceStaysWhileItStarts(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	s.SetNetworkNames(map[string]string{"fake": "Fake", "other": "Other"})
	require.NoError(t, s.SetLoginState(ctx, "fake", "fake-login", json.RawMessage(`{"state_event":"CONNECTED","remote_id":"fake-login"}`)))
	require.NoError(t, s.SetLoginState(ctx, "other", "", json.RawMessage(`{"state_event":"UNCONFIGURED"}`)))

	n := &slowNet{Network: fakenet.New(), entered: make(chan struct{}), release: make(chan struct{})}
	other := &slowNet{Network: fakenet.New(), entered: make(chan struct{}), release: make(chan struct{})}
	specs := []engine.Spec{
		{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }},
		{Name: "other", Connector: func() (bridgev2.NetworkConnector, error) { return other, nil }},
	}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	path := serve(t, Deps{Store: s, Engine: eng, Networks: []NetworkInfo{{Name: "fake", DisplayName: "Fake"}, {Name: "other", DisplayName: "Other"}}})
	c := dial(t, path)
	c.hello()
	spaceIDs := func() []string {
		var r struct {
			Spaces []struct {
				SpaceID string `json:"space_id"`
			} `json:"spaces"`
		}
		c.ok("spaces.list", nil, &r)
		var out []string
		for _, sp := range r.Spaces {
			out = append(out, sp.SpaceID)
		}
		return out
	}
	got := spaceIDs()
	require.Contains(t, got, "account:fake", "linked, and starting")
	require.NotContains(t, got, "account:other", "starting, with no account")

	done := make(chan struct{})
	go func() {
		defer close(done)
		eng.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, specs, zerolog.Nop())
	}()
	<-n.entered
	close(n.release)
	<-other.entered
	c.changed(func(ch changed) bool { return ch.Kind == "spaces" }) // fake's bridge is up
	close(other.release)
	<-done
}

// Marking a chat read on a network that is still starting reads it here: the network can't be told yet, and the
// receipt is best effort anyway.
func TestMarkReadWhileStartingIsDone(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	const room = "!r:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: room, Network: "fake", Name: "Test chat"}))
	n := &slowNet{Network: fakenet.New(), entered: make(chan struct{}), release: make(chan struct{})}
	specs := []engine.Spec{{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	path := serve(t, Deps{Store: s, Engine: eng, Actions: actions.New(eng, s, m), Networks: []NetworkInfo{{Name: "fake", DisplayName: "Fake"}}})
	c := dial(t, path)
	c.hello()
	c.ok("room.markRead", map[string]any{"room_id": room}, nil)
}

// Ruling C6: a new message in a chat whose network is still starting is stored waiting and answered at once
// (message.send, message.sendFile; message.retry passes the same check), not refused as not running. Everything
// else that goes out through the network (a reaction, say) is still -32016 until it runs.
func TestSendWhileStartingAnswersWaiting(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	const room = "!r:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: room, Network: "fake", Name: "Test chat"}))
	_, err = s.InsertEvent(ctx, store.Event{
		RoomID: room, EventID: "$theirs", Sender: "@fake_alice:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"hi"}`), TS: time.Now(),
	})
	require.NoError(t, err)
	// Expected, and never started during the test: STARTING throughout.
	specs := []engine.Spec{{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return fakenet.New(), nil }}}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	path := serve(t, Deps{Store: s, Engine: eng, Actions: actions.New(eng, s, m), Media: m, Networks: []NetworkInfo{{Name: "fake", DisplayName: "Fake"}}})
	c := dial(t, path)
	c.hello()

	var res struct {
		EventID string `json:"event_id"`
	}
	c.ok("message.send", map[string]any{"room_id": room, "text": "while starting"}, &res)
	e, ok, err := s.GetEvent(ctx, res.EventID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, store.StatusWaiting, e.Status)
	c.ok("message.sendFile", map[string]any{"room_id": room, "path": aFile(t)}, &res)
	e, _, err = s.GetEvent(ctx, res.EventID)
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, e.Status)
	c.fails(CodeNotFailed, "message.retry", map[string]any{"event_id": res.EventID}) // reaches the action: not failed
	c.fails(CodeNotRunning, "message.react", map[string]any{"room_id": room, "event_id": "$theirs", "key": "👍"})
}

// Ruling 3: a linked network that fails to start keeps its space (its chats are still there; its account says
// NOT_STARTED with the reason), and the app is told spaces changed when it fails.
func TestALinkedNetworkThatFailsToStartKeepsItsSpace(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	s.SetNetworkNames(map[string]string{"fake": "Fake", "other": "Other"})
	require.NoError(t, s.SetLoginState(ctx, "fake", "fake-login", json.RawMessage(`{"state_event":"CONNECTED","remote_id":"fake-login"}`)))
	specs := []engine.Spec{
		{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("it can't start") }},
		{Name: "other", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("nor this") }},
	}
	eng := engine.New(s)
	t.Cleanup(eng.Stop)
	eng.Expect(specs)
	path := serve(t, Deps{Store: s, Engine: eng, Networks: []NetworkInfo{{Name: "fake", DisplayName: "Fake"}, {Name: "other", DisplayName: "Other"}}})
	c := dial(t, path)
	c.hello()
	eng.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, specs, zerolog.Nop())
	c.changed(func(ch changed) bool { return ch.Kind == "spaces" })
	require.Equal(t, "it can't start", eng.Status("fake").NotStarted)
	var r struct {
		Spaces []struct {
			SpaceID string `json:"space_id"`
		} `json:"spaces"`
	}
	c.ok("spaces.list", nil, &r)
	var got []string
	for _, sp := range r.Spaces {
		got = append(got, sp.SpaceID)
	}
	require.Contains(t, got, "account:fake", "linked: its chats are still there")
	require.NotContains(t, got, "account:other", "never linked")
}
