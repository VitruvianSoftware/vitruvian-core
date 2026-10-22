// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/datadir"
	"github.com/VitruvianSoftware/courier/engine/internal/networks"
	"github.com/VitruvianSoftware/courier/engine/internal/rpc"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/store/storetest"
)

// These tests run the real binary, the one the app ships. Bazel hands it over as test data (see BUILD); it links
// every network, Signal's Rust library included, which a plain `go build` in a sandbox cannot.

const startTimeout = 60 * time.Second

// binary finds the courier-engine binary in the test's runfiles.
func binary(t *testing.T) string {
	t.Helper()
	rel := os.Getenv("COURIER_ENGINE_BIN")
	if rel == "" {
		t.Fatal("COURIER_ENGINE_BIN is not set: run these tests with bazel test //apps/desktop/courier/engine/cmd/courier-engine:courier-engine_test")
	}
	var tried []string
	for _, root := range []string{os.Getenv("RUNFILES_DIR"), os.Getenv("TEST_SRCDIR")} {
		if root == "" {
			continue
		}
		p := filepath.Join(root, rel)
		tried = append(tried, p)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	t.Fatalf("courier-engine not found in the runfiles; tried %v", tried)
	return ""
}

// shortDir makes a directory under /tmp. A socket path must fit in macOS's 104-byte sun_path, and Bazel's
// TEST_TMPDIR is far too long for that.
func shortDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "ce")
	require.NoError(t, err)
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

// syncBuf is a bytes.Buffer safe to read while a process is still writing to it.
type syncBuf struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuf) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuf) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

type gotReady struct {
	Ready    bool   `json:"ready"`
	Socket   string `json:"socket"`
	Protocol int    `json:"protocol"`
}

type engineProc struct {
	cmd    *exec.Cmd
	stdout *syncBuf
	stderr *syncBuf
	done   chan struct{}
	code   int
}

// cleanEnv is the environment without Telegram's credentials, so a developer's own do not change what is tested.
func cleanEnv() []string {
	var env []string
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "COURIER_TELEGRAM_") {
			env = append(env, kv)
		}
	}
	return env
}

// launch starts the binary with args and does not wait for it to be ready.
func launch(t *testing.T, extra []*os.File, args ...string) *engineProc {
	t.Helper()
	p := &engineProc{stdout: &syncBuf{}, stderr: &syncBuf{}, done: make(chan struct{})}
	p.cmd = exec.Command(binary(t), args...)
	p.cmd.Env = cleanEnv()
	p.cmd.Stdout, p.cmd.Stderr = p.stdout, p.stderr
	p.cmd.ExtraFiles = extra
	require.NoError(t, p.cmd.Start())
	go func() {
		err := p.cmd.Wait()
		p.code = p.cmd.ProcessState.ExitCode()
		_ = err
		close(p.done)
	}()
	t.Cleanup(func() {
		select {
		case <-p.done:
		default:
			_ = p.cmd.Process.Kill()
			<-p.done
		}
	})
	return p
}

// start launches the engine on data and waits for its ready line.
func start(t *testing.T, data string, extra []*os.File, args ...string) (*engineProc, gotReady) {
	t.Helper()
	p := launch(t, extra, append([]string{"--data", data}, args...)...)
	deadline := time.Now().Add(startTimeout)
	for {
		if line, _, ok := strings.Cut(p.stdout.String(), "\n"); ok {
			var r gotReady
			require.NoError(t, json.Unmarshal([]byte(line), &r), "ready line %q", line)
			return p, r
		}
		select {
		case <-p.done:
			t.Fatalf("the engine exited with %d before it was ready; stderr:\n%s", p.code, p.stderr.String())
		case <-time.After(20 * time.Millisecond):
		}
		if time.Now().After(deadline) {
			t.Fatalf("the engine was not ready in %v; stderr:\n%s", startTimeout, p.stderr.String())
		}
	}
}

// exited waits for the process to end and returns its exit code.
func (p *engineProc) exited(t *testing.T, within time.Duration) int {
	t.Helper()
	select {
	case <-p.done:
		return p.code
	case <-time.After(within):
		t.Fatalf("the engine did not exit within %v; stderr:\n%s", within, p.stderr.String())
		return -1
	}
}

// rpcClient is a minimal line-JSON client.
type rpcClient struct {
	t  *testing.T
	c  net.Conn
	r  *bufio.Reader
	id int
}

func dial(t *testing.T, socket string) *rpcClient {
	t.Helper()
	c, err := net.DialTimeout("unix", socket, 5*time.Second)
	require.NoError(t, err)
	t.Cleanup(func() { c.Close() })
	return &rpcClient{t: t, c: c, r: bufio.NewReader(c)}
}

// call sends one request and returns its result, skipping notifications.
func (c *rpcClient) call(method string, params any) json.RawMessage {
	c.t.Helper()
	c.id++
	req := map[string]any{"jsonrpc": "2.0", "id": c.id, "method": method}
	if params != nil {
		req["params"] = params
	}
	b, err := json.Marshal(req)
	require.NoError(c.t, err)
	require.NoError(c.t, c.c.SetDeadline(time.Now().Add(30*time.Second)))
	_, err = c.c.Write(append(b, '\n'))
	require.NoError(c.t, err)
	for {
		line, err := c.r.ReadBytes('\n')
		require.NoError(c.t, err)
		var resp struct {
			ID     *int            `json:"id"`
			Result json.RawMessage `json:"result"`
			Error  json.RawMessage `json:"error"`
		}
		require.NoError(c.t, json.Unmarshal(line, &resp))
		if resp.ID == nil || *resp.ID != c.id {
			continue
		}
		require.Empty(c.t, resp.Error, "%s failed: %s", method, resp.Error)
		return resp.Result
	}
}

func (c *rpcClient) hello() struct {
	Protocol int      `json:"protocol"`
	Engine   string   `json:"engine"`
	Networks []string `json:"networks"`
} {
	c.t.Helper()
	var res struct {
		Protocol int      `json:"protocol"`
		Engine   string   `json:"engine"`
		Networks []string `json:"networks"`
	}
	require.NoError(c.t, json.Unmarshal(c.call("hello", map[string]any{"protocol": rpc.Protocol, "client": "test/1"}), &res))
	return res
}

func TestServesHelloOnTheSocket(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	p, ready := start(t, data, nil)

	require.Equal(t, gotReady{Ready: true, Socket: filepath.Join(data, "engine.sock"), Protocol: rpc.Protocol}, ready)
	require.True(t, filepath.IsAbs(ready.Socket))

	c := dial(t, ready.Socket)
	res := c.hello()
	require.Equal(t, rpc.Protocol, res.Protocol)
	want := os.Getenv("COURIER_ENGINE_VERSION")
	require.NotEmpty(t, want, "COURIER_ENGINE_VERSION is not set: BUILD passes the version the binary is stamped with")
	require.Equal(t, want, res.Engine, "hello reports the version the build stamped (app/version.bzl), the app's own")
	require.Contains(t, res.Networks, "whatsapp")
	require.Contains(t, res.Networks, "telegram")
	require.Contains(t, res.Networks, "slack")
	require.Contains(t, res.Networks, "gmessages")

	// Without Telegram's app credentials Telegram does not start, and the app is told why.
	var accounts struct {
		Accounts []struct {
			Network    string `json:"network"`
			State      string `json:"state"`
			NotStarted string `json:"not_started"`
		} `json:"accounts"`
	}
	require.NoError(t, json.Unmarshal(c.call("accounts.list", nil), &accounts))
	byName := map[string]string{}
	for _, a := range accounts.Accounts {
		byName[a.Network] = a.State
		if a.Network == "telegram" {
			require.Contains(t, a.NotStarted, "my.telegram.org")
		} else {
			require.Empty(t, a.NotStarted, a.Network)
		}
	}
	require.Equal(t, "NOT_STARTED", byName["telegram"])
	require.Equal(t, "UNCONFIGURED", byName["whatsapp"])

	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second))

	// Nothing but the ready line ever goes to stdout; stderr is JSON lines.
	require.Equal(t, 1, strings.Count(p.stdout.String(), "\n"), "stdout: %q", p.stdout.String())
	require.True(t, strings.HasSuffix(p.stdout.String(), "\n"))
	for _, line := range strings.Split(strings.TrimSpace(p.stderr.String()), "\n") {
		if line != "" {
			require.True(t, json.Valid([]byte(line)), "stderr line is not JSON: %q", line)
		}
	}
}

func TestSocketAndDirArePrivate(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	require.NoError(t, os.Mkdir(data, 0o755)) // an earlier run, or the user, left it open
	_, ready := start(t, data, nil)

	di, err := os.Stat(data)
	require.NoError(t, err)
	require.Equal(t, os.FileMode(0o700), di.Mode().Perm())
	si, err := os.Stat(ready.Socket)
	require.NoError(t, err)
	require.NotZero(t, si.Mode()&os.ModeSocket)
	require.Equal(t, os.FileMode(0o600), si.Mode().Perm())
}

func TestSecondEngineOnSameDirExits3(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	first, ready := start(t, data, nil)

	second := launch(t, nil, "--data", data)
	require.Equal(t, 3, second.exited(t, startTimeout))
	require.Contains(t, second.stderr.String(), "another Courier engine is using "+data)
	require.Empty(t, second.stdout.String(), "a refused engine says nothing on stdout")

	// The refused engine must not have removed the first one's socket: it still answers.
	require.Equal(t, rpc.Protocol, dial(t, ready.Socket).hello().Protocol)
	select {
	case <-first.done:
		t.Fatal("the first engine stopped")
	default:
	}
}

func TestStaleSocketIsReplaced(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	require.NoError(t, os.Mkdir(data, 0o700))
	sock := filepath.Join(data, "engine.sock")
	// What a crashed engine leaves: a socket file nobody listens on.
	ln, err := net.Listen("unix", sock)
	require.NoError(t, err)
	ln.(*net.UnixListener).SetUnlinkOnClose(false)
	require.NoError(t, ln.Close())
	_, err = os.Stat(sock)
	require.NoError(t, err, "the stale socket must be there to begin with")

	_, ready := start(t, data, nil)
	require.Equal(t, sock, ready.Socket)
	require.Equal(t, rpc.Protocol, dial(t, sock).hello().Protocol)
}

func TestSIGTERMStopsCleanly(t *testing.T) {
	for _, sig := range []syscall.Signal{syscall.SIGTERM, syscall.SIGINT} {
		t.Run(sig.String(), func(t *testing.T) {
			data := filepath.Join(shortDir(t), "data")
			p, ready := start(t, data, nil)
			c := dial(t, ready.Socket) // a client still connected must not hold the engine up
			c.hello()

			require.NoError(t, p.cmd.Process.Signal(sig))
			require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())

			_, err := os.Stat(ready.Socket)
			require.ErrorIs(t, err, os.ErrNotExist, "the socket is removed")
			release, err := datadir.Lock(data)
			require.NoError(t, err, "the lock is free")
			release()
		})
	}
}

func TestParentPipeClosedStopsEngine(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	r, w, err := os.Pipe()
	require.NoError(t, err)
	defer w.Close()
	p, ready := start(t, data, []*os.File{r}, "--parent-fd", "3") // ExtraFiles[0] is fd 3 in the child
	require.NoError(t, r.Close())                                 // the app is the only reader's writer; the test keeps w

	select {
	case <-p.done:
		t.Fatal("the engine stopped while its parent was still there")
	case <-time.After(300 * time.Millisecond):
	}
	require.Equal(t, rpc.Protocol, dial(t, ready.Socket).hello().Protocol)

	require.NoError(t, w.Close()) // the app crashed
	require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())
	_, err = os.Stat(ready.Socket)
	require.ErrorIs(t, err, os.ErrNotExist)
	release, err := datadir.Lock(data)
	require.NoError(t, err)
	release()
}

func TestBadArgumentsAreUsageErrors(t *testing.T) {
	data := filepath.Join(shortDir(t), "data")
	for name, args := range map[string][]string{
		"no data":            {},
		"empty data":         {"--data", ""},
		"unknown flag":       {"--data", data, "--nope"},
		"extra argument":     {"--data", data, "extra"},
		"fd not a number":    {"--data", data, "--parent-fd", "abc"},
		"fd negative":        {"--data", data, "--parent-fd", "-1"},
		"fd not open":        {"--data", data, "--parent-fd", "99"},
		"fd is stdout":       {"--data", data, "--parent-fd", "1"},
		"fd is stderr":       {"--data", data, "--parent-fd", "2"},
		"data and fd absent": {"--parent-fd", "3"},
	} {
		t.Run(name, func(t *testing.T) {
			p := launch(t, nil, args...)
			require.Equal(t, 2, p.exited(t, 30*time.Second), "stderr:\n%s", p.stderr.String())
			require.Contains(t, p.stderr.String(), "usage: courier-engine --data DIR")
			require.Empty(t, p.stdout.String())
		})
	}
	_, err := os.Stat(data)
	require.ErrorIs(t, err, os.ErrNotExist, "a usage error touches nothing")
}

func TestTooLongSocketPathFailsWithTheLimit(t *testing.T) {
	data := filepath.Join(shortDir(t), strings.Repeat("d", 100))
	p := launch(t, nil, "--data", data)
	require.Equal(t, 1, p.exited(t, 30*time.Second))
	require.Contains(t, p.stderr.String(), "104")
	require.Contains(t, p.stderr.String(), "engine.sock")
	require.Empty(t, p.stdout.String())
	_, err := os.Stat(data)
	require.ErrorIs(t, err, os.ErrNotExist, "it fails before it creates anything")
}

func TestWaitBoundedGivesUpAtTheBound(t *testing.T) {
	done := make(chan struct{})
	start := time.Now()
	require.False(t, waitBounded(done, 50*time.Millisecond))
	require.Less(t, time.Since(start), 5*time.Second)
	close(done)
	require.True(t, waitBounded(done, time.Hour))
}

// A message still pending when the last engine stopped is one it never heard back about: on the next start it is
// failed with "may have been sent", before any client can see it, and not sent again.
func TestPendingFromAnEarlierRunBecomesMayHaveBeenSent(t *testing.T) {
	ctx := context.Background()
	data := filepath.Join(shortDir(t), "data")
	require.NoError(t, os.Mkdir(data, 0o700))
	s, err := store.Open(filepath.Join(data, "courier.db"))
	require.NoError(t, err)
	require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: "!r:courier.local", Network: "whatsapp", Name: "Test chat"}))
	_, err = s.InsertEvent(ctx, store.Event{
		RoomID: "!r:courier.local", EventID: "$p", Sender: "@me:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"cut off"}`), TS: time.Unix(5, 0), Status: "pending",
	})
	require.NoError(t, err)
	require.NoError(t, s.Close())

	p, _ := start(t, data, nil)
	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second))

	s, err = store.Open(filepath.Join(data, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	e, ok, err := s.GetEvent(ctx, "$p")
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "failed", e.Status)
	require.Equal(t, store.ReasonMayHaveBeenSent, e.StatusReason)
}

// Ruling 5: the store is handed each network's display name, so account spaces and muted_by_name read "WhatsApp".
func TestTheStoreIsGivenEachNetworksDisplayName(t *testing.T) {
	all := networks.All()
	names := displayNames(all)
	require.Len(t, names, len(all))
	for _, n := range all {
		require.Equal(t, n.DisplayName, names[n.Name])
		require.NotEmpty(t, names[n.Name], n.Name)
	}
	require.Equal(t, "WhatsApp", names["whatsapp"])
	require.Equal(t, "Google Messages", names["gmessages"])
}

// Review Focus 4: a big history on disk doesn't hold the engine up. It is ready, and answers, while the backfill is
// still indexing behind it; the backfill finishes, says so without any text, and the engine still stops cleanly.
func TestEngineServesWhileTheBackfillRuns(t *testing.T) {
	ctx := context.Background()
	data := filepath.Join(shortDir(t), "data")
	require.NoError(t, os.Mkdir(data, 0o700))
	db := filepath.Join(data, "courier.db")
	s, err := store.Open(db)
	require.NoError(t, err)
	require.NoError(t, s.Close())
	// Enough history for several batches, and few enough that a race-instrumented build on a busy CI runner indexes
	// it well inside backfillTimeout: 50,000 took over a minute there.
	const history = 6_000
	storetest.SeedUnindexed(t, db, history)

	// The test's own look at the database is open before the engine starts, so the first reading can be taken the
	// moment the ready line is out.
	s, err = store.Open(db)
	require.NoError(t, err)
	defer s.Close()
	searchComplete := func() bool {
		done, err := s.SearchComplete(ctx)
		require.NoError(t, err)
		return done
	}
	p, ready := start(t, data, nil)
	// 6,000 messages are at least 3 batches, each followed by a rest of at least BackfillPause, so the backfill, which
	// starts only after the ready line, cannot have finished yet.
	require.False(t, searchComplete(), "the engine was ready before the history on disk was indexed")
	c := dial(t, ready.Socket)
	require.Equal(t, rpc.Protocol, c.hello().Protocol, "and answers while it indexes")

	// A loose ceiling, never a speed check: it only stops a hung backfill from hanging the test.
	const backfillTimeout = 3 * time.Minute
	deadline := time.Now().Add(backfillTimeout)
	for !strings.Contains(p.stderr.String(), "search backfill done") {
		if time.Now().After(deadline) {
			t.Fatalf("the backfill did not finish in %v; stderr:\n%s", backfillTimeout, p.stderr.String())
		}
		time.Sleep(20 * time.Millisecond)
	}
	require.True(t, searchComplete())

	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())
	for _, line := range strings.Split(strings.TrimSpace(p.stderr.String()), "\n") {
		require.True(t, json.Valid([]byte(line)), "stderr line is not JSON: %q", line)
	}
	require.NotContains(t, p.stderr.String(), "seed", "counts and durations only, never text or names")
	require.Equal(t, history, storetest.Indexed(t, db))
}

// The engine starts the outbox and the disappearing timers: a held message whose window ended while Courier was
// closed (less than an hour ago) is handed to its network at start, and a message past its timer is gone. The
// network here has no account, so the hand-off ends failed "not connected", which proves it was attempted; nothing
// was sent.
func TestEngineStartsTheOutbox(t *testing.T) {
	ctx := context.Background()
	data := filepath.Join(shortDir(t), "data")
	require.NoError(t, os.Mkdir(data, 0o700))
	db := filepath.Join(data, "courier.db")
	s, err := store.Open(db)
	require.NoError(t, err)
	defer s.Close()
	const room = "!r:courier.local"
	require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: room, Network: "whatsapp", Name: "Test chat"}))
	now := time.Now()
	require.NoError(t, s.Hold(ctx, store.Event{
		RoomID: room, EventID: "$held", Sender: "@me:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"held"}`), TS: now.Add(-15 * time.Second),
	}, now.Add(-10*time.Second)))
	_, err = s.InsertEvent(ctx, store.Event{
		RoomID: room, EventID: "$gone", Sender: "@whatsapp_x:courier.local", Type: "m.room.message",
		Content: json.RawMessage(`{"msgtype":"m.text","body":"brief","com.beeper.disappearing_timer":{"type":"after_send","timer":1000}}`),
		TS:      now.Add(-time.Hour),
	})
	require.NoError(t, err)

	p, _ := start(t, data, nil)
	// A loose ceiling, never a speed check: it only stops a broken loop from hanging the test.
	deadline := time.Now().Add(startTimeout)
	for {
		e, ok, err := s.GetEvent(ctx, "$held")
		require.NoError(t, err)
		require.True(t, ok)
		if e.Status == "failed" {
			require.Equal(t, actions.ReasonNotConnected, e.StatusReason, "handed off, and refused for want of an account")
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the held message was never handed off (status %q); stderr:\n%s", e.Status, p.stderr.String())
		}
		time.Sleep(20 * time.Millisecond)
	}
	gone, err := s.Redacted(ctx, "$gone")
	require.NoError(t, err)
	require.True(t, gone, "the message past its timer is gone")

	require.NoError(t, p.cmd.Process.Signal(syscall.SIGTERM))
	require.Equal(t, 0, p.exited(t, 60*time.Second), "stderr:\n%s", p.stderr.String())
	require.NotContains(t, p.stderr.String(), "held", "no message text in the log")
	require.NotContains(t, p.stderr.String(), "Test chat", "no names in the log")
}
