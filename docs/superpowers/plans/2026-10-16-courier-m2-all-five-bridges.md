# Courier Milestone 2: all five bridges in one engine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the engine runs WhatsApp, Telegram, Google Messages, Slack and Signal side by side against one local store. The test CLI can link, watch and reply on any of them.

**Architecture:** milestone 1 proved the glue for one network. This adds:
- an `engine` that runs one bridge host per network over a shared `courier.db`;
- a small registry describing each network (how to build its connector and how to log in);
- a CLI that walks any bridge's login steps generically.

Signal links a Rust library (`libsignal_ffi`), so Task 1 settles how that builds under Bazel before anything depends on it.

**Tech Stack:** Go 1.26; `maunium.net/go/mautrix` v0.31.0 and `go.mau.fi/util` v0.10.1 (unchanged). New bridges, all at their September 2026 releases, all on mautrix v0.31.0 and util v0.10.1:
- `go.mau.fi/mautrix-telegram` v0.2609.0
- `go.mau.fi/mautrix-gmessages` v0.2609.0
- `go.mau.fi/mautrix-slack` v0.2609.1
- `go.mau.fi/mautrix-signal` v0.2609.0

Signal's Rust library is `signalapp/libsignal` at commit `8fc2113bda042fc972a166a24b974b0d34155c6c` (the bridge's submodule). It needs Rust 1.98.1, plus a BoringSSL fork built with CMake and bindgen.

**Spec:** `docs/superpowers/specs/2026-10-15-courier-iteration-1-design.md`, milestone 2 in §7. Milestone 1's plan and its result are the base: `docs/superpowers/plans/2026-10-15-courier-m1-local-store.md`.

## Global Constraints

- Every Global Constraint in the milestone-1 plan still applies: module path, pins, cgo SQLite, `courier.local`, `@me`, data layout, no real accounts in CI, AGPL headers by hand, `bazel run //:gazelle` and `bazel mod tidy` after Go changes, `bazel run //:tidy` before every commit.
- Bridge versions are pinned exactly as listed above. None of them may move mautrix or util off v0.31.0 or v0.10.1. Check `go.mod` after every `go get`.
- Network names are lowercase with no underscore: `whatsapp`, `telegram`, `gmessages`, `slack`, `signal`. They become ghost-ID prefixes, and an underscore would break ghost parsing (milestone-1 deferred finding).
- **Credentials:**
  - Telegram's `api_id` / `api_hash` come only from the environment variables `COURIER_TELEGRAM_API_ID` / `COURIER_TELEGRAM_API_HASH`. They are never committed or logged.
  - The engine refuses to start Telegram without them, with a message saying where to get them.
- The CLI default data dir stays `~/Library/Application Support/Courier-m1`, so milestone-1 links keep working. It is still one process per data dir, enforced by the existing lock.
- A Rust toolchain added for Signal must not change the Rust version the existing `packages/vitruvian-sdk` code builds with (1.75.0).

## Review Focus

1. **A reply sent to one network's room must go to that network's bridge.** Routing by the room's network must never fall back to "the first host". Covered in Task 2 (`TestReplyRoutesToTheRoomsNetwork`).
2. **One bridge failing to start must not take the others down.** For example, Telegram without credentials: the engine starts the rest and reports which failed. Covered in Task 2 (`TestOneNetworkFailingDoesNotStopTheOthers`).
3. **A login step the CLI can't do must cancel cleanly and say what to use instead.** Examples are WebAuthn, or a cookies step without pasted values. Covered in Task 4 (`TestUnsupportedStepCancelsWithAdvice`).
4. **Text typed at a prompt is never echoed for secret fields.** Telegram's 2FA password and Slack tokens use password-type fields. Covered in Task 4 (`TestSecretFieldsAreNotEchoed`).
5. **Linking Google Messages disconnects it in Beeper.** It allows one web session; spec §5. The CLI warns and asks for confirmation first. Covered in Task 4 (`TestGoogleMessagesLinkWarnsFirst`).

---

## File structure

```
apps/desktop/courier/engine/
  internal/networks/networks.go       registry: name, display name, connector factory, login flows, configure hook
  internal/networks/networks_test.go
  internal/engine/engine.go           runs one host per network over a shared store; routes rooms
  internal/engine/engine_test.go
  internal/host/host.go               (modify) optional Configure hook after example config is decoded
  internal/host/offline_test.go       (rename of whatsapp_offline_test.go) offline start for every pure-Go network
  cmd/courier-engine-cli/main.go      (modify) --network, --flow, engine-based run, generic login, routed send
  cmd/courier-engine-cli/login.go     generic step walker (QR, emoji/code, user input, cookies paste)
  cmd/courier-engine-cli/login_test.go
third_party/libsignal/                Task 1 output (Option A: Bazel build; Option B: pinned prebuilt archive)
apps/desktop/courier/engine/docs/m2-libsignal.md   Task 1 decision record
apps/desktop/courier/engine/docs/m2-result.md      Task 7 by-hand result
```

---

### Task 1: Decide and build `libsignal_ffi` under Bazel (spike, time-boxed)

This is the riskiest build step, so it goes first. Everything else in this plan works without it; Signal waits on it.

**Files:**
- Create: `third_party/libsignal/BUILD`, `third_party/libsignal/README.md`, `apps/desktop/courier/engine/docs/m2-libsignal.md`
- Modify: `MODULE.bazel` (only as the chosen option requires)

**Interfaces:**
- Produces: a `cc_library` target `//third_party/libsignal:signal_ffi` that provides `libsignal_ffi.a` for both darwin arm64 and darwin x86_64. It must be linkable from cgo through `-lsignal_ffi`, which is the flag `go.mau.fi/mautrix-signal/pkg/libsignalgo/cflags.go` uses. The header is already in that Go package (`libsignal-ffi.h`).

**Option A (preferred): build it hermetically in Bazel.**
- Add a second rules_rust toolchain at 1.98.1, used only for this crate. `rust.toolchain(versions = ["1.75.0", "1.98.1"])` registers both; select 1.98.1 with a target-level toolchain setting so the SDK stays on 1.75.0.
- Fetch `signalapp/libsignal` at the pinned commit with `git_repository` or `http_archive` and a sha256.
- Generate its crate graph from its own `Cargo.lock`, using a separate `crate.from_cargo(name = "libsignal_crates", ...)`.
- Build `rust/bridge/ffi` as a `rust_static_library`.
- `boring-sys` needs BoringSSL compiled with CMake. Feed it a BoringSSL tree built by `rules_foreign_cc`'s `cmake()` rule (already a dependency), via `BORING_BSSL_SOURCE_PATH` / `BORING_BSSL_ASSUME_PATCHED`. bindgen comes from `rules_rust`'s bindgen toolchain.

**Option B (fallback): a pinned prebuilt archive.**
- Add `.github/workflows/build-libsignal-ffi.yaml`, run by hand (`workflow_dispatch`), on a free macOS runner, since the repo is public:
  - check out libsignal at the pinned commit;
  - run `cargo build -p libsignal-ffi --release` for both `aarch64-apple-darwin` and `x86_64-apple-darwin`;
  - combine them with `lipo` into one universal `libsignal_ffi.a`;
  - publish it as a release asset named `libsignal-ffi-<commit>-universal.tar.gz` with its sha256.
- Consume it with `http_archive` plus that sha256 in `MODULE.bazel`, and wrap it as `cc_library(srcs = ["libsignal_ffi.a"], linkstatic = True)`.
- This is reproducible and checksum-pinned, but not built from source in the Bazel graph. Record that trade-off in the decision doc.

**Decision rule:** use Option A if `bazel build //third_party/libsignal:signal_ffi` succeeds cleanly for both CPU types within one working day of effort. Otherwise use Option B. Option B publishes a release asset to this repo, an additive change, but say so plainly in the decision doc and the PR.

- [ ] **Step 1: Try Option A**, keeping a log of each blocker in `docs/m2-libsignal.md`.
- [ ] **Step 2: Prove linkability.** Write a throwaway cgo test that calls one `libsignalgo` function, for example generating an identity key pair. It must build and run under `bazel test` against `//third_party/libsignal:signal_ffi`. Keep that test as `internal/networks/signal_link_test.go`; it becomes the permanent guard.
- [ ] **Step 3: Decide.** If Option A is not green at the time box, switch to Option B and repeat Step 2.
- [ ] **Step 4: Write the decision** in `docs/m2-libsignal.md`: the option chosen, why, time spent, what failed, and what it costs to revisit.
- [ ] **Step 5: Commit**, with a conventional message and the AGPL or third-party licence headers as appropriate. libsignal itself is AGPL-3.0, which is compatible.

---

### Task 2: An engine that runs several networks over one store

**Files:**
- Create: `internal/engine/engine.go`, `internal/engine/engine_test.go`
- Modify: `internal/host/host.go` (add `Option` / `WithConfigure`)

**Interfaces:**
- Consumes: `host.Start`, `store`, `media`, `fakenet` (tests).
- Produces:

```go
// package host
type Option func(*options)
func WithConfigure(f func(networkConfig any) error) Option // runs after the example config is decoded, before Start
func Start(ctx context.Context, dataDir, network string, s *store.Store, m *media.Store,
	nc bridgev2.NetworkConnector, log zerolog.Logger, opts ...Option) (*Host, error)

// package engine
type Spec struct {
	Name      string
	Connector func() (bridgev2.NetworkConnector, error)
	Configure func(networkConfig any) error // may be nil
}
type Engine struct{ /* unexported */ }
func Start(ctx context.Context, dataDir string, s *store.Store, m *media.Store, specs []Spec, log zerolog.Logger) (*Engine, map[string]error)
func (e *Engine) Host(name string) (*host.Host, bool)
func (e *Engine) HostForRoom(ctx context.Context, roomID string) (*host.Host, error) // by rooms.network; error if unknown room or network not running
func (e *Engine) Names() []string                                                  // running networks, sorted
func (e *Engine) Stop()
```

`Start` starts every spec it can. A spec whose connector factory, configure hook or `host.Start` fails is left out, and its error is returned in the map under its name. Started hosts keep running. `Stop` stops the hosts in reverse start order.

- [ ] **Step 1: Write the failing tests**

`internal/engine/engine_test.go`:

```go
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package engine

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func startTwo(t *testing.T) (*Engine, *store.Store, map[string]*fakenet.Network) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	nets := map[string]*fakenet.Network{"fakea": fakenet.New(), "fakeb": fakenet.New()}
	var specs []Spec
	for name, n := range nets {
		n := n
		specs = append(specs, Spec{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }})
	}
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, specs, zerolog.New(zerolog.NewTestWriter(t)))
	require.Empty(t, errs)
	t.Cleanup(e.Stop)
	for name, n := range nets {
		h, ok := e.Host(name)
		require.True(t, ok)
		_, err := n.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	return e, s, nets
}

func roomWith(t *testing.T, s *store.Store, network, body string) string {
	var roomID string
	require.Eventually(t, func() bool {
		rooms, err := s.ListRooms(context.Background())
		require.NoError(t, err)
		for _, r := range rooms {
			if r.Network != network {
				continue
			}
			evs, err := s.Events(context.Background(), r.ID, 10)
			require.NoError(t, err)
			for _, e := range evs {
				if json.Valid(e.Content) && string(e.Content) != "" && containsBody(e.Content, body) {
					roomID = r.ID
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 50*time.Millisecond)
	return roomID
}

func containsBody(raw json.RawMessage, body string) bool {
	var c struct{ Body string `json:"body"` }
	return json.Unmarshal(raw, &c) == nil && c.Body == body
}

func TestReplyRoutesToTheRoomsNetwork(t *testing.T) {
	e, s, nets := startTwo(t)
	ctx := context.Background()
	for name, n := range nets {
		hh, _ := e.Host(name)
		me, err := hh.Me(ctx)
		require.NoError(t, err)
		n.Incoming(me.GetUserLogins()[0], "chat1", "alice", "m1", "hi from "+name)
	}
	roomB := roomWith(t, s, "fakeb", "hi from fakeb")
	h, err := e.HostForRoom(ctx, roomB)
	require.NoError(t, err)
	require.Equal(t, "fakeb", h.Network)

	reply := &event.Event{Type: event.EventMessage, RoomID: id.RoomID(roomB), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "to b"}}}
	h.Bridge.QueueMatrixEvent(ctx, reply)
	select {
	case got := <-nets["fakeb"].Sent:
		require.Equal(t, "to b", got.Body)
	case <-time.After(5 * time.Second):
		t.Fatal("reply never reached fakeb")
	}
	select {
	case got := <-nets["fakea"].Sent:
		t.Fatalf("reply leaked to fakea: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestHostForUnknownRoomErrors(t *testing.T) {
	e, _, _ := startTwo(t)
	_, err := e.HostForRoom(context.Background(), "!nope:courier.local")
	require.Error(t, err)
}

func TestOneNetworkFailingDoesNotStopTheOthers(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	good := fakenet.New()
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{
		{Name: "fakegood", Connector: func() (bridgev2.NetworkConnector, error) { return good, nil }},
		{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("no credentials") }},
	}, zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Equal(t, []string{"fakegood"}, e.Names())
	require.ErrorContains(t, errs["fakebad"], "no credentials")
}
```

The `fakenet.Sent` value already carries `PortalID` and `Body`, as in milestone 1's fix round. If `fakenet.Network.Incoming` takes the login argument differently, follow its real signature.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop/courier/engine && go test ./internal/engine/`
Expected: FAIL with `undefined: Start`.

- [ ] **Step 3: Implement**

Add to `internal/host/host.go`:

```go
// Option adjusts how Start prepares a bridge.
type Option func(*options)

type options struct{ configure func(any) error }

// WithConfigure runs after the connector's example config is decoded and before the bridge starts,
// so a network can fill in values the example cannot hold (Telegram's API credentials).
func WithConfigure(f func(networkConfig any) error) Option {
	return func(o *options) { o.configure = f }
}
```

Give `Start` a trailing `opts ...Option`. Apply them, and after the example config is decoded into `data` call `o.configure(data)` when it is set. Return its error wrapped with the network name, before opening the database.

`internal/engine/engine.go`:

```go
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package engine runs one bridge host per chat network over courier's single local store.
package engine

import (
	"context"
	"fmt"
	"sort"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Spec says how to build and configure one network's bridge.
type Spec struct {
	Name      string
	Connector func() (bridgev2.NetworkConnector, error)
	Configure func(networkConfig any) error
}

type Engine struct {
	store *store.Store
	hosts map[string]*host.Host
	order []string
}

// Start starts every network it can. Networks that fail are left out and reported by name.
func Start(ctx context.Context, dataDir string, s *store.Store, m *media.Store, specs []Spec, log zerolog.Logger) (*Engine, map[string]error) {
	e := &Engine{store: s, hosts: map[string]*host.Host{}}
	errs := map[string]error{}
	for _, spec := range specs {
		nc, err := spec.Connector()
		if err != nil {
			errs[spec.Name] = err
			continue
		}
		var opts []host.Option
		if spec.Configure != nil {
			opts = append(opts, host.WithConfigure(spec.Configure))
		}
		h, err := host.Start(ctx, dataDir, spec.Name, s, m, nc, log, opts...)
		if err != nil {
			errs[spec.Name] = err
			continue
		}
		e.hosts[spec.Name] = h
		e.order = append(e.order, spec.Name)
	}
	return e, errs
}

func (e *Engine) Host(name string) (*host.Host, bool) {
	h, ok := e.hosts[name]
	return h, ok
}

// HostForRoom finds the bridge a room belongs to, by the network recorded on its row.
func (e *Engine) HostForRoom(ctx context.Context, roomID string) (*host.Host, error) {
	room, ok, err := e.store.GetRoom(ctx, roomID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("no chat with id %s", roomID)
	}
	h, ok := e.hosts[room.Network]
	if !ok {
		return nil, fmt.Errorf("chat %s is on %s, which is not running", roomID, room.Network)
	}
	return h, nil
}

func (e *Engine) Names() []string {
	names := append([]string(nil), e.order...)
	sort.Strings(names)
	return names
}

// Stop stops the hosts in reverse start order.
func (e *Engine) Stop() {
	for i := len(e.order) - 1; i >= 0; i-- {
		e.hosts[e.order[i]].Stop()
	}
}
```

Add a host test, `TestConfigureRunsAfterExampleDefaults`. It uses the existing config-example test connector, makes `WithConfigure` change one decoded field, and asserts that both the example default and the override hold after `Start`.

- [ ] **Step 4: Run the tests**

Run: `go test -race ./internal/engine/ ./internal/host/`
Expected: PASS.

- [ ] **Step 5: Commit**

Run `bazel run //:gazelle && bazel run //:tidy`, then commit with `feat(courier): an engine that runs several networks over one store`.

---

### Task 3: Telegram, Google Messages and Slack, with a network registry

**Files:**
- Create: `internal/networks/networks.go`, `internal/networks/networks_test.go`
- Rename: `internal/host/whatsapp_offline_test.go` becomes `internal/host/offline_test.go`. It moves to `internal/networks/offline_test.go` if the import direction requires it, since networks imports host, not the reverse.
- Modify: `go.mod`. Add the three bridges at their pinned versions.

**Interfaces:**
- Produces:

```go
package networks
type Network struct {
	Name        string   // "whatsapp", "telegram", "gmessages", "slack", "signal"
	DisplayName string   // "WhatsApp", ...
	Flows       []string // login flow IDs this CLI offers, preferred first
	Spec        func() (engine.Spec, error)
}
func All() []Network // in the order above; Signal only once Task 5 lands
func Get(name string) (Network, bool)
```

Flows, verified from each bridge's source at its pinned version:

| Network | Flows (preferred first) | Notes |
|---|---|---|
| whatsapp | `qr` | |
| telegram | `qr`, `phone` | Needs `COURIER_TELEGRAM_API_ID` and `COURIER_TELEGRAM_API_HASH`. Its `Spec` returns an error naming https://my.telegram.org when they're missing. Configure merges `api_id: <id>` and `api_hash: <hash>` YAML into the decoded config. |
| gmessages | `qr`, `google` | `google` needs a cookies step plus an emoji match on the phone |
| slack | `email`, `token`, `app` | `email` needs an emailed code (plus a captcha cookies step if Slack demands one). `token` needs pasted browser cookies. `app` needs bot tokens. |

- [ ] **Step 1: Write the failing tests**

`internal/networks/networks_test.go`:

```go
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRegistryNamesAreSafeGhostPrefixes(t *testing.T) {
	for _, n := range All() {
		require.Regexp(t, `^[a-z]+$`, n.Name, "network names become ghost-ID prefixes and must not contain '_'")
		require.NotEmpty(t, n.Flows)
	}
	for _, name := range []string{"whatsapp", "telegram", "gmessages", "slack"} {
		_, ok := Get(name)
		require.True(t, ok, name)
	}
}

func TestTelegramWithoutCredentialsSaysWhereToGetThem(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "")
	tg, _ := Get("telegram")
	_, err := tg.Spec()
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "my.telegram.org"), err.Error())
}

func TestTelegramCredentialsReachTheConnectorConfig(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "424242")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")
	tg, _ := Get("telegram")
	spec, err := tg.Spec()
	require.NoError(t, err)
	nc, err := spec.Connector()
	require.NoError(t, err)
	_, data, _ := nc.GetConfig()
	require.NoError(t, spec.Configure(data))
	require.Contains(t, fmtConfig(t, data), "424242")
}
```

`fmtConfig` marshals `data` to YAML (yaml.v3) and returns the string. Write it in the test file.

The offline test, renamed and extended:
- `TestEveryNetworkStartsOfflineTwice` loops over `All()`. For Telegram it sets dummy credentials with `t.Setenv`.
- For each network it runs `host.Start` twice on one temp dir with no login and no network, and asserts both succeed.
- Before relying on this, read each connector's `Start` in the module cache and confirm it does no network I/O without a login, as the milestone-1 review confirmed for WhatsApp. If one does, skip that network in the test, name it, and give the reason in a comment.

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./internal/networks/`
Expected: FAIL with `undefined: All`.

- [ ] **Step 3: Implement `networks.go`**

Each `Spec` returns an `engine.Spec`. Its `Connector` returns a fresh `&connector.XConnector{}` from that bridge's `pkg/connector` package; check the exact type names (`TelegramConnector`, `GMConnector`, `SlackConnector`) in the module cache before writing them. Telegram's `Configure` is:

```go
func(data any) error {
	extra := fmt.Sprintf("api_id: %s\napi_hash: %s\n", id, hash)
	return yaml.Unmarshal([]byte(extra), data) // merges onto the decoded example; other fields keep their defaults
}
```

`id` must parse as a positive integer, and `hash` must be 32 hex characters. Otherwise `Spec` returns an error that doesn't echo the values.

- [ ] **Step 4: Run the tests**

Run: `go test -race ./internal/networks/ ./internal/host/`, then `bazel run //:gazelle && bazel mod tidy && bazel test //apps/desktop/courier/engine/...`.
Expected: PASS. For any new Bazel build problem in a bridge's dependencies, add a scoped `go_deps.gazelle_override` or `go_deps.module_override` in `MODULE.bazel`, with a comment naming the module, following milestone 1's whatsmeow and webp precedent.

- [ ] **Step 5: Commit**

Commit with `feat(courier): Telegram, Google Messages and Slack bridges in the engine`.

---

### Task 4: The CLI drives any network's login and routes replies

**Files:**
- Create: `cmd/courier-engine-cli/login.go`, `cmd/courier-engine-cli/login_test.go`
- Modify: `cmd/courier-engine-cli/main.go`

**Interfaces:**
- Consumes: `engine.Start`, `networks.All` / `Get`.
- Produces:
  - Usage: `courier-engine-cli [--data DIR] [--network NAME] [--flow ID] link|chats|tail|send <room-id> <text>`. `--network` is required for `link` (no default, so a QR is never shown for the wrong app). `chats`, `tail` and `send` run every network.
  - `type prompter interface { Line(label string) (string, error); Secret(label string) (string, error); Confirm(question string) (bool, error) }`, with a terminal implementation and a scripted one for tests.
  - `func walkLogin(ctx context.Context, proc bridgev2.LoginProcess, p prompter, out io.Writer) error` replaces `runLogin`.

Behaviour of `walkLogin`:
- **`display_and_wait`:** a QR code is drawn with qrterminal. An emoji or code is printed in large text with "Tap/enter this on your phone". Then it waits.
- **`user_input`:** each field is prompted by its `Name` and `Description`. Fields of type password or token use `Secret`, which never echoes. Values are checked against the field's `Pattern`, if there is one, and the user is re-prompted up to 3 times.
- **`cookies`:**
  - print the URL;
  - tell the user to sign in there in their browser and copy each named cookie or value (field `ID` and its source hints);
  - read each with `Secret`;
  - submit.
  - If the user enters nothing for a required field, cancel with "use the Courier app for this sign-in (milestone 3)".
- **`webauthn`, or any unknown step:** cancel, then return an error naming the step and the alternative.
- Cancel on every path except `complete`, as today.

`link` additions:
- Uses `--flow`, or the network's first flow.
- Refuses when that network already has a login: "already linked to <Network>".
- For `gmessages`, first asks `Confirm("Google Messages allows one web session. Linking here disconnects it in Beeper. Continue?")`.

`send` changes:
- Resolves the host with `engine.HostForRoom`.
- `waitForLogin` fails fast with "<network> isn't linked — run link --network <network> first" when the network has no logins, instead of waiting 30 s (milestone-1 parked finding).
- The bridge-command prefix check uses `"!" + network` for the room's network.

- [ ] **Step 1: Write the failing tests**

`login_test.go` uses a scripted `prompter` and fake `LoginProcess` types implementing `LoginProcessDisplayAndWait`, `LoginProcessUserInput` and `LoginProcessCookies`. Each returns canned steps and records what was submitted and whether `Cancel` ran. Required tests:
- `TestUserInputStepPromptsEachFieldAndSubmits`: two fields, phone then code, submitted with exactly the scripted values.
- `TestSecretFieldsAreNotEchoed`: a password-type field is read through `Secret`, and its value never appears in `out`.
- `TestPatternMismatchRepromptsThenGivesUp`: bad, bad, bad → error, and `Cancel` ran.
- `TestCookiesStepPrintsURLAndSubmitsPastedValues`
- `TestUnsupportedStepCancelsWithAdvice`: webauthn → error mentions the passkey, and `Cancel` ran.
- `TestEmojiDisplayIsShownThenWaits`
- `TestGoogleMessagesLinkWarnsFirst`: declining the confirm → no `CreateLogin` call, and no error.
- `TestSendToUnlinkedNetworkFailsFast`: under 1 s, nothing stored or queued.
- `TestBridgePrefixPerNetwork`: `!telegram logout` is refused for a Telegram room; `!whatsapp` is allowed there.
- `TestLinkRequiresNetwork`: `parseArgs([]string{"link"})` → error naming `--network`.

Keep every existing milestone-1 CLI test passing, adjusted only where `runLogin` was renamed.

- [ ] **Step 2: Run them to verify they fail**

Run: `go test ./cmd/courier-engine-cli/`
Expected: FAIL with undefined symbols.

- [ ] **Step 3: Implement** `login.go`, with the terminal prompter using `golang.org/x/term` for `Secret`, and the `main.go` changes. Run the engine via `engine.Start` with `networks.All()` specs. Print one line per network that failed to start, for example "telegram: not started — set COURIER_TELEGRAM_API_ID…", and carry on with the rest.

- [ ] **Step 4: Run the tests and build**

Run: `go test -race ./... && go build ./cmd/courier-engine-cli && bazel test //apps/desktop/courier/engine/... && bazel run //:tidy && bazel run //tools/license:check`
Expected: PASS, and a clean tree after tidy.

- [ ] **Step 5: Commit**

Commit with `feat(courier): the test CLI links and replies on any network`.

---

### Task 5: Signal in the engine

Depends on Task 1.

**Files:**
- Modify: `internal/networks/networks.go` (add `signal`), `go.mod` (`go.mau.fi/mautrix-signal v0.2609.0`), `MODULE.bazel` (a `go_deps.module_override` or `gazelle_override` that adds `//third_party/libsignal:signal_ffi` as a cdep of `go.mau.fi/mautrix-signal/pkg/libsignalgo`)
- Test: the offline test now includes `signal`; `signal_link_test.go` from Task 1 stays.

- [ ] **Step 1:** Add `signal` to the registry, with flows `qr`, and extend the offline test.
- [ ] **Step 2:** Run `go test` and `bazel test`, and show the libsignal link working in both. `go test` outside Bazel needs `CGO_LDFLAGS=-L<dir of libsignal_ffi.a>`. Document that in the engine README section of `docs/m2-libsignal.md`.
- [ ] **Step 3:** Commit `feat(courier): Signal bridge in the engine`.

---

### Task 6: Final check of the branch

- [ ] Run the full engine suite under `-race`, plus `bazel test //apps/desktop/courier/engine/...`, `bazel run //:tidy` (clean), `bazel run //tools/license:check` and `verify`, and an osv-scanner pass over the engine's `go.mod` (zero advisories, or fix them as in milestone 1).
- [ ] Confirm `go.mod` still pins mautrix v0.31.0 and util v0.10.1.

---

### Task 7: By-hand check on James's accounts (needs James)

**Files:** create `apps/desktop/courier/engine/docs/m2-result.md`

Before starting, register a Telegram API app at https://my.telegram.org → API development tools, using James's own Telegram account. Store `api_id` and `api_hash` in Bitwarden, then export them as `COURIER_TELEGRAM_API_ID` / `COURIER_TELEGRAM_API_HASH` in the shell. Never commit them.

For each network, run `link --network <name>` as an extra device beside Beeper, then `tail`, receive a test message, Ctrl-C, `send` a reply to a willing tester, and restart. Beeper keeps running throughout.

| Network | Link with | Watch for |
|---|---|---|
| signal | QR from Signal → Settings → Linked devices | |
| telegram | QR (Telegram → Settings → Devices → Link Desktop Device) | Sessions list shows the new device |
| slack | `--flow email`: your Abrial work email, then the emailed code | Workspace admins may block third-party clients |
| gmessages | Last, and only if ready: it disconnects Beeper's Google Messages | |

Record pass or fail for each step, per network, in `m2-result.md`, with no phone numbers, names or message text. Note anything the CLI couldn't handle.
