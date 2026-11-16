---
status: planned
date: 2026-11-15
---

# Relay P1: single-user alpha Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** James runs a command on his Mac from Claude on his phone, and the "ask
first" prompt appears on the Mac.

**Architecture:** Two new Rust programs. The **relay** runs on the homelab. It
serves MCP to AI apps at `/mcp/d/<device-id>`, holds one WebSocket per computer
at `/connect`, and passes calls down it. The **connector** (`vrelay`) runs on
the Mac. It signs in with the device flow, dials the relay, checks every call
against a local rules file (asking first when the rules say so), and runs it
through an unmodified, pinned `desktop-commander` over stdio. Token checking
moves out of the Slack MCP into a shared crate the relay uses; moving the Slack
MCP itself onto it is a follow-up (Task 1).

**Tech Stack:** Rust 1.98.1 (rules_rust 0.68.1, per-app crate hub via
`crate.from_cargo`), hyper 1 + tokio, tokio-tungstenite 0.24, ring 0.17 (RS256
and Ed25519), serde_json, `desktop-commander` 0.3.1 via rules_js, Helm chart
plus Argo CD, Zitadel (`zitadel-apps-relay` stack).

**Spec:** [`docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md`](../specs/2026-11-07-vitruvian-relay-design.md)
(§4 protocol, §5 components, §6 sign-in, §7 security, §8 alpha hosting, §10 P1
row). P0 evidence: [`2026-11-09-relay-p0-spikes.md`](2026-11-09-relay-p0-spikes.md).
The spike code (`apps/suites/vitruvian-relay/spike`) is the starting point for
PRM, the `/connect` loop and the device flow; copy what fits, then the spike
is retired in the last task.

## Global Constraints

- **Scope (§10 P1):** homelab only, one user, one device, bridging only
  `desktop-commander`, local rules file, no billing, no Postgres, no dashboard.
- **Not in P1** (spec items deferred to P2 or later): the tenant isolation test
  in CI (§7.4), per-user and per-device rate limits (§7.7), revoking a device
  from a dashboard (§6), the connector settings screen and one-click pause UI
  (the rules file's `paused` flag stands in), Gemini and ChatGPT as P1 targets
  (Claude is the done-when), a notification per call (§7.3, "can post"),
  bridging other stdio servers (§5; `desktop-commander` only), folder limits
  for file tools (§7.1; `desktop-commander`'s own setting, which remote callers
  can't change because its config tools are hidden, stays at its default), pushing
  `tools/list_changed` over SSE (the next request picks it up), notarisation
  (P3's installers; P1 is a local Developer ID-signed install), and **Postgres**:
  spec §8 puts the alpha on CNPG, but one user and one device need only a device
  record, so P1 keeps it in a file behind a `DeviceStore` trait that P2 swaps
  for Postgres.
- **One sign-in is P1-required** (§10 builds in the spike B fix), but it needs
  James's decision. `pulumi-zitadel` v0.2.0, the newest on the Go module proxy when checked on 2026-11-15, has no
  per-app login-version field, so there is no IaC switch for the relay alone.
  The instance already serves Login V2 (`/ui/v2/login`, routed in
  `gitops/argocd/platform/zitadel/applicationset.yaml`); a guess, not yet
  checked, is that spike B's second sign-in comes from the device-approval page
  using the older screen, which might need a Zitadel upgrade. Task 10 records what was checked and asks
  James; P1 does not silently ship two sign-ins.
- **`desktop-commander`'s own log** (`~/.claude-server-commander/claude_tool_call.log`)
  records full arguments outside the connector's log. Changing `HOME` would
  change it for the user's commands too (spike D), so the connector leaves the
  file where it is and sets that folder to mode `0700` at start.
- **Relay URL per device:** `https://relay.ipv1337.dev/mcp/d/<device-id>`. One
  device in P1, but the URL shape is the final one (§4).
- **Authorise on client id and subject, never audience alone** (§6). Zitadel
  puts the client id in `client_id`; `azp` is absent.
- **The relay keeps no content** (§7.2): arguments and outputs only in memory
  while a call is in flight. Logs record tool name, size, duration, outcome.
- **The computer has the last word** (§7.1): rules live in a file on the Mac;
  no frame from the relay can change them. Default: terminal commands and any
  write ask first, reads don't. `set_config_value` and any other tool that
  changes `desktop-commander`'s own settings is hidden from remote callers.
- **Protocol (§4):** JSON frames `hello`, `welcome`/`reject`, `call`,
  `result`, `cancel`, `tools_changed`, `ping`/`pong`. `progress` is reserved
  and not built. Ping every **20 s**, **3** missed pings = offline. **While a device has a call in flight**, the relay pings it every **2 s** and treats **3** missed pings (about 6 s) as a drop, so a silent network loss fails the call in seconds, not a minute (a P1 refinement of §4, recorded in the spec by this plan's PR). Frames
  capped at **4 MiB**; bigger output is truncated with a note. Repeated call
  ids ignored for **10 minutes**. Reconnect backoff **1 s doubling to 60 s,
  with jitter**.
- **`desktop-commander` (§5, spike D):** exactly **0.3.1**, integrity
  `sha512-cx7KTscLF951adHmDLVCDIVTqJ/Bg1LtdRILZoo5wa/UMeyOfMAuOJOEBulNMKBKb5Xd3nHDQnB9aXroN9Fw5A==`;
  needs Node **22.12+**; started in its own process group and stopped by
  group; env `DESKTOP_COMMANDER_DISABLE_TELEMETRY=1` and `DC_FLAG_URL`
  pointed at a closed local port; its `notifications/message` are logs, not
  replies; it never needs `progress`.
- **P0 requirements (§4, §10):** a call in flight when its device drops gets an
  immediate error, not a hang; the connector refreshes its token on reconnect
  and retries a failed refresh; the relay answers `server/discover`.
- **Hosting (§8):** relay pod on the always-on pools only (the same
  allow-list affinity as the spike, #4916), one replica.
- **License headers** on every new source and config file (`addlicense`; CI's `license-check` fails without them).
- **CI coverage:** every new package's `BUILD` declares a `pipeline_unit` (as the spike's does: `load("//tools/pipeline:defs.bzl", "pipeline_unit")`, `persona = "backend"`, `runner = "ubuntu-26.04"`, `tier = "L1"`, `test_targets = [":unit_tests"]`), or its tests never run on PRs or in the merge queue. After adding or removing one, regenerate the presubmit workflow with `bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml` (tidy-check fails if it's stale). Each hand-written `BUILD` starts with `# gazelle:ignore`, as the spike's does.
- **Repo rules:** every git, gh, cluster and Pulumi operation through the Bazel
  targets in `AGENTS.md`. Commits via `bazel run //tools/git:commit -- --agent
  <you>`. Raw `cargo` is blocked; re-lock with `bazel run //tools/crates:lock
  -- --dir <path>`.

## Review Focus

1. **The Mac sleeps or drops off Wi-Fi mid-call.** A closed connection fails
   the call at once. A silent loss (Wi-Fi off sends nothing) is caught by the
   fast in-call pings within about 6 s. Either way the AI app gets "Your
   computer disconnected; try again." instead of waiting for the deadline.
   Tests in Task 3 (`pending_call_fails_when_device_drops`) and Task 4
   (`silent_drop_mid_call_fails_within_seconds`).
2. **Nobody is at the Mac when an "ask first" call arrives.** The prompt must
   time out as **Deny**, never Allow. Test in Task 6
   (`prompt_timeout_denies`).
3. **`desktop-commander` crashes mid-command.** The call returns an error, the
   command it started is killed with it, and the next call starts a fresh
   process. Test in Task 7 (`crash_kills_group_and_restarts`).
4. **A command prints far more than 4 MiB.** The result is cut to fit with a
   note saying so, and the WebSocket stays up. Test in Task 7
   (`oversized_result_is_truncated_with_note`).
5. **Two calls arrive at once** (two chats, or Claude running tools in
   parallel). Each result must go back to the call that asked for it, never
   swapped. Test in Task 3 (`concurrent_calls_get_their_own_results`).

---

## File Structure

```
packages/rust/vitruvian-mcp-auth/         shared token checking (from slack-mcp auth.rs)
  Cargo.toml, BUILD, src/lib.rs, src/verifier.rs, src/prm.rs
apps/suites/vitruvian-relay/
  BUILD, Cargo.toml, Cargo.lock            workspace: protocol, relay, connector, connector/scripts;
                                           vitruvian-mcp-auth joins as a path dependency
                                           (`../../../../packages/rust/vitruvian-mcp-auth`
                                           from relay/Cargo.toml; it sits outside this
                                           root, as the spike's slack-mcp one does)
  protocol/  src/lib.rs                    frame types shared by relay and connector
  relay/     src/{main,config,registry,mcp,http,devices}.rs, Dockerfile, deploy/chart/
  connector/ src/{main,config,auth,keys,rules,prompt,bridge,link}.rs, dc/ (desktop-commander pin, own pnpm workspace)
gitops/argocd/applications/relay.yaml, gitops/argocd/platform/relay/values.yaml
infrastructure/pulumi/platform/zitadel-apps-relay/  (redirect for relay host, login V2)
```

One crate hub, `@vitruvian_relay_crates`, built from
`apps/suites/vitruvian-relay/Cargo.toml`, replaces `@vitruvian_relay_spike_crates`.

---

### Task 1: Shared token checking crate

Pull the verifier out of the Slack MCP so the relay doesn't copy it (§5), and
let one verifier accept several client ids.

**Files:**
- Create: `packages/rust/vitruvian-mcp-auth/{Cargo.toml,BUILD,src/lib.rs,src/verifier.rs,src/prm.rs}`. Its BUILD takes its crates from `@vitruvian_relay_crates` and sets `package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])`; the Slack MCP is added to that list when it moves over. Its `Cargo.toml` has its own empty `[workspace]` table, as slack-mcp's does, so cargo doesn't treat it as an unlisted member of the repo-root workspace when the relay path-depends on it
- Create: `apps/suites/vitruvian-relay/{BUILD,Cargo.toml,Cargo.lock}` (the BUILD makes the folder a package, so `MODULE.bazel` can name `//apps/suites/vitruvian-relay:Cargo.toml` and `:Cargo.lock`, as it names the spike's). The hub only contains crates that some workspace member depends on, so Task 1 also creates the `relay` member as a stub (`relay/Cargo.toml` path-depending on `vitruvian-mcp-auth`, and an empty `relay/src/main.rs`); that puts the shared crate's dependencies in the lock and the hub. Later tasks fill in the relay and add the other members
- Modify: `MODULE.bazel`: add hub `vitruvian_relay_crates`, and add it to the `repositories` list of the `ring` `crate.annotation` (every hub that builds ring is listed there, the spike's included). Keep the spike hub until the spike is retired (Task 10), which removes it from both places.
- Test: `packages/rust/vitruvian-mcp-auth/src/verifier.rs` (`#[cfg(test)]`)

**Interfaces:**
- Produces:
  - `pub struct VerifierConfig { issuer: String, project_id: String, allowed_client_ids: Vec<String>, allowed_subjects: Vec<String>, jwks_uri: Option<String>, user_agent: String }`
  - `pub fn verifier(cfg: VerifierConfig) -> Result<Verifier, String>` (refuses empty client or subject lists)
  - `impl Verifier { pub fn verify(&self, bearer: &str) -> Result<Caller, AuthError> }`
  - `pub struct Caller { pub subject: String, pub client_id: String }`
  - `pub enum AuthError` with `status() -> u16`, `code() -> &'static str`
  - `pub fn extract_bearer(header: Option<&str>) -> Option<&str>`
  - `pub fn protected_resource_metadata(resource: &str, issuer: &str, project_id: &str) -> serde_json::Value`
  - `pub fn www_authenticate(resource_metadata_url: &str, err: Option<&AuthError>) -> String`

The token checks are the same as slack-mcp's `auth.rs` (the helper signatures differ, as listed above): RS256 only, modulus ≥ 2048
bits, JWKS `{issuer}/oauth/v2/keys` cached 600 s with a 30 s refetch
cooldown, `iss` exact, `exp`/`nbf` 30 s skew, `aud` contains `project_id`,
`sub` in the allow-list, any `azp` rejected, `client_id` in
`allowed_client_ids`. Use `serde_json` instead of slack-mcp's own `JsonValue`. The JWKS fetch uses slack-mcp's TLS stack: rustls 0.23 on ring, rustls-native-certs 0.8, and ureq without its `native-certs` feature, so the unmaintained rustls-pemfile (RUSTSEC-2025-0134) never enters the lock and osv-scan stays green.

- [ ] **Step 1: Write the failing tests** — port slack-mcp's verifier tests,
  plus `accepts_any_listed_client_id` (two ids, a token for each verifies) and
  `rejects_unlisted_client_id` (`AuthError` code `"insufficient_scope"`, as
  slack-mcp's `ClientNotAllowed` maps it), and
  `prm_lists_project_audience_scope` (scopes `openid`, `offline_access`,
  `urn:zitadel:iam:org:project:id:<id>:aud`).
- [ ] **Step 2:** `bazel test //packages/rust/vitruvian-mcp-auth:unit_tests` → FAIL (crate missing).
- [ ] **Step 3: Implement** the crate; add the hub, re-lock with
  `bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay`, then `bazel run //:gazelle` and confirm it changes nothing under `apps/suites/vitruvian-relay` or `packages/rust/vitruvian-mcp-auth` (the spike's BUILD is hand-written). `apps/suites` is already excluded in the root `BUILD` file; if gazelle touches `packages/rust/vitruvian-mcp-auth`, add a `# gazelle:exclude packages/rust/vitruvian-mcp-auth` line there, in the same form as the existing ones.
- [ ] **Step 4:** the same test → PASS; `bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay --check` → clean; the crate's `pipeline_unit` is declared and `bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml --check` passes after regenerating.
- [ ] **Step 5: Commit** `feat(relay): shared MCP token checking crate`.

Moving the Slack MCP onto this crate is **not** in P1: it builds from its own
hub, and one crate from two hubs is two crates. Record it as a follow-up issue
in this task's PR.

### Task 2: Protocol frames

**Files:**
- Create: `apps/suites/vitruvian-relay/protocol/{Cargo.toml,BUILD,src/lib.rs}` (BUILD with `:unit_tests` and a `pipeline_unit`)

**Interfaces:**
- Produces (serde, `#[serde(tag = "type", rename_all = "snake_case")]`):
  - `enum ToRelay { Hello(Hello), Result(CallResult), ToolsChanged { tools: Vec<ToolDef> }, Ping { n: u64 }, Pong { n: u64 } }`
  - `enum ToConnector { Welcome { device_id: String }, Reject { reason: String }, Call(Call), Cancel { call_id: String }, Ping { n: u64 }, Pong { n: u64 } }`
  - Ping and pong go both ways (§4): each side pings every 20 s and treats 3 unanswered pings as a dead link.
  - `struct Hello { device_id: String, connector_version: String, protocol: u32, ts: u64, sig: String, tools: Vec<ToolDef> }`
  - `struct Call { call_id: String, tool: String, arguments: serde_json::Value, deadline_ms: u64 }` — `deadline_ms` is a duration from when the frame is sent, not a clock time (the two machines' clocks may differ). The relay's budget for a `tools/call` is **180 s**, covering a 60 s "ask first" prompt plus the command
  - `struct CallResult { call_id: String, content: serde_json::Value, is_error: bool, truncated: bool }`
  - `struct ToolDef { name: String, description: String, #[serde(rename = "inputSchema")] input_schema: serde_json::Value }` — the MCP wire name, so a `desktop-commander` tool passes through unchanged
  - `const PROTOCOL: u32 = 1; const MAX_FRAME_BYTES: usize = 4 * 1024 * 1024; const PING_SECS: u64 = 20; const IN_CALL_PING_SECS: u64 = 2; const MAX_MISSED_PINGS: u32 = 3;`
  - `fn hello_message(device_id: &str, ts: u64, token_sha256_hex: &str) -> String` → `"vrelay-hello-v1\n{device_id}\n{ts}\n{token_sha256_hex}"` (the bytes the device key signs; binding the token hash stops replay with another token)
  - `fn encode(&impl Serialize) -> Result<String, FrameError>` (refuses over `MAX_FRAME_BYTES`), `fn decode_to_relay(&str)`, `fn decode_to_connector(&str)` (both refuse input over `MAX_FRAME_BYTES`). Both ends also set tokio-tungstenite's `max_message_size` and `max_frame_size` to `MAX_FRAME_BYTES`; its defaults are far larger

- [ ] **Step 1: Tests** `round_trips_every_frame`, `rejects_unknown_type`,
  `encode_refuses_oversized_frame` (asserts on the encoded byte length, not the
  input length), `decode_refuses_oversized_frame`, `tool_def_uses_input_schema_wire_name`
  (decodes `{"name":…,"description":…,"inputSchema":{…}}`), `hello_message_is_stable` (exact string above).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/protocol:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): connector/relay protocol frames`.

### Task 3: Relay core — device registry and call routing

**Files:**
- Create: `apps/suites/vitruvian-relay/relay/src/{registry.rs,devices.rs}`, `BUILD` (`:unit_tests` and a `pipeline_unit`), `Cargo.toml`

**Interfaces:**
- Consumes: Task 2 frames.
- Produces:
  - `struct DeviceRecord { device_id: String, owner_sub: String, public_key_ed25519: [u8; 32] }`
  - `trait DeviceStore: Send + Sync { fn get(&self, id: &str) -> Option<DeviceRecord>; fn put(&self, rec: DeviceRecord) -> io::Result<()>; }`
  - `struct FileDeviceStore` (JSON file, atomic rename on write; `/data/devices.json` in the pod) — P2 replaces it with Postgres behind the same trait.
  - `struct Registry` with `connect(&self, device_id, tools, tx: mpsc::Sender<ToConnector>) -> ConnectionId`, `disconnect(&self, device_id, ConnectionId)`, `update_tools(&self, device_id, tools: Vec<ToolDef>)`, `tools(&self, device_id) -> Option<Vec<ToolDef>>`, `async fn call(&self, device_id, Call) -> Result<CallResult, CallError>`, `complete(&self, CallResult)`, `kick(&self, device_id)` (close the live connection, failing its pending calls)
  - `enum CallError { Offline, Disconnected, Deadline }` with `user_message()`: `"Your computer is offline."`, `"Your computer disconnected; try again."`, `"The command took too long."` (ownership is checked before the registry, in Task 4)

`call` registers a oneshot under `call_id`, sends the frame, and waits for
`complete`, the deadline, or the device's disconnect, whichever comes first.
`disconnect` fails every pending call for that connection with
`Disconnected` at once (P0 requirement). A newer connection for the same
device replaces the old one (its pending calls fail `Disconnected`).

- [ ] **Step 1: Tests** `call_returns_device_result`,
  `concurrent_calls_get_their_own_results` (two calls in flight, results
  completed in reverse order, each caller gets its own),
  `pending_call_fails_when_device_drops` (disconnect mid-call → `Disconnected`
  in under 100 ms), `call_to_offline_device_fails_fast`,
  `deadline_expiry_sends_cancel`, `reconnect_replaces_old_connection`,
  `update_tools_changes_the_list`, `kick_fails_pending_calls`,
  `file_store_round_trips_and_survives_restart`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): device registry and call routing`.

### Task 4: Relay HTTP — MCP, PRM, `/connect`, device registration

**Files:**
- Create: `apps/suites/vitruvian-relay/relay/src/{main.rs,config.rs,http.rs,mcp.rs}`

**Interfaces:**
- Consumes: Task 1 `verifier`, `protected_resource_metadata`, `www_authenticate`; Task 3 `Registry`, `DeviceStore`.
- Produces:
  - `vitruvian-relay --version` prints the version and exits 0 (the image workflow runs it to check the image).
  - `struct Settings` from env: `PORT` (3000), `PUBLIC_URL`, `ISSUER`, `PROJECT_ID`, `MCP_CLIENT_IDS` (CSV), `CONNECTOR_CLIENT_ID`, `ALLOWED_SUBJECTS` (CSV), `DATA_DIR` (`/data`). Same validation as the spike's `Settings::from_lookup`.
  - Routes:
    - `GET /healthz` → 200 `ok` (the chart's probes use it, as the spike's do; not routed publicly).
    - `GET` and `DELETE /mcp/d/{device_id}` → 405 (no SSE stream or session delete in P1), as the spike does.
    - `POST /mcp/d/{device_id}` — MCP over Streamable HTTP (JSON responses; SSE not needed in P1). Bearer verified with the MCP client ids; caller `sub` must equal the device's `owner_sub`, else 404 (don't reveal the device).
    - `GET /.well-known/oauth-protected-resource/mcp/d/{device_id}` — PRM with `resource` = that device's URL. The bare `/.well-known/oauth-protected-resource` returns the same metadata with `resource` = `PUBLIC_URL` (the relay itself), for clients that look there first.
    - `POST /devices` — bearer verified with `CONNECTOR_CLIENT_ID`; body `{ "public_key": "<base64 32 bytes>" }`; creates a record owned by the caller, returns `{ "device_id": "<uuid v4>", "mcp_url": "…" }`. P1 allows one device per subject: a second call for the same subject replaces the key, keeps the id, and calls `Registry::kick` so a session signed with the old key ends at once.
    - `GET /connect` — WebSocket. Bearer verified with `CONNECTOR_CLIENT_ID`. First frame must be `hello` within 10 s: device exists, owned by the caller, `|now − ts| ≤ 60 s`, Ed25519 `sig` over `hello_message(device_id, ts, sha256(bearer))` verifies, `protocol == 1`. Otherwise `reject` with the reason and close. Then `welcome`, `Registry::connect`, ping every 20 s (every 2 s while the device has a call in flight), answer the connector's pings, disconnect after 3 missed pongs.
  - `mcp::handle(req, device_id, caller, registry) -> Option<Value>`: `initialize` (protocol versions as the spike's `PROTOCOL_VERSIONS`; capabilities `tools: { listChanged: false }`, because P1 answers in JSON only and has no stream to push a change on), `ping`, `server/discover` (returns the same `serverInfo` — name `vitruvian-relay`, version — `capabilities` and supported protocol versions as `initialize`, without starting a session), `tools/list` (the device's current tools; empty list and no error if offline), `tools/call` (→ `Registry::call` with a 180 s budget; `CallError` becomes an MCP tool result with `isError: true` and `user_message()`). Sessions: `initialize` returns an `Mcp-Session-Id` header (a random 128-bit id), and every later request carries it; a request with a missing id gets 400, and one with an unknown id gets 404, which tells the AI app to start a new session (MCP's rule for an ended session). Sessions live in memory, so after a relay restart every client gets 404 once and re-initializes. `initialize` and `server/discover` need no session. Cancelling: the relay keeps a map from (session id, JSON-RPC `id`) to `call_id`, so one chat can never cancel another's call. An MCP `notifications/cancelled` with that `requestId`, or the HTTP request being dropped before the result is ready, sends `cancel { call_id }` to the device (Task 8 dismisses a pending prompt on it). A `tools_changed` frame calls `Registry::update_tools`; AI apps see the new list on their next `tools/list`.
  - Logging: one line per call — device id, caller client id, tool, argument bytes, result bytes, duration, outcome. Never arguments or output (§7.2).

- [ ] **Step 1: Tests** (hyper test client against an in-process server, with a
  test JWKS like slack-mcp's tests): `mcp_requires_token_with_www_authenticate`,
  `mcp_rejects_other_users_device_as_404`, `server_discover_is_answered`,
  `tools_list_reflects_hello_tools`, `connect_rejects_bad_signature`,
  `connect_rejects_stale_ts`, `connect_rejects_token_for_another_client`,
  `register_device_returns_mcp_url`, `reregister_kicks_old_session`,
  `notifications_cancelled_sends_cancel`, `dropped_request_sends_cancel`,
  `healthz_ok`, `unknown_session_gets_404`, `get_and_delete_get_405`,
  `cancel_only_affects_own_session` (two sessions using the same JSON-RPC id;
  cancelling in one leaves the other's call running),
  `silent_drop_mid_call_fails_within_seconds` (a fake connector that stops
  answering pings mid-call, with an injected clock: the call fails
  `Disconnected` after about 6 s),
  `bare_prm_names_the_relay`, `logs_never_contain_arguments_outputs_or_tokens`
  (a call with a marker string in its arguments and its result, and a known
  bearer: none of the three appears in the captured log).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay:unit_tests` → FAIL.
- [ ] **Step 3: Implement** with hyper 1 + tokio-tungstenite, copying the spike's `main.rs` routing shape.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): MCP, PRM, device registration and /connect`.

### Task 5: Connector sign-in, device key and token refresh

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/{main.rs,auth.rs,keys.rs}`, `BUILD` (a `rust_binary` named `vrelay`, so `bazel run //apps/suites/vitruvian-relay/connector:vrelay -- <command>`, plus `:unit_tests` and a `pipeline_unit`), `Cargo.toml`

**Interfaces:**
- Produces:
  - Commands: `vrelay login`, `vrelay status`, `vrelay logout` (`run` and `install` come in Tasks 8–9). `vrelay status` prints signed in or out, the device id and MCP URL, and the link state, which `vrelay run` writes to `status.json` in the state dir: `connected` (welcome received and a pong within the last 60 s), `connecting` (with the next retry time), `waiting for sign-in`, or `stopped` (no `vrelay run` process, or `status.json` older than 60 s).
  - State dir: `~/Library/Application Support/vrelay/` (`$VRELAY_HOME` overrides, for tests), mode `0700`; files `token.json` (holds the refresh token, mode `0600`), `device.json` (`{device_id, mcp_url}`), `device.key` (Ed25519 seed, mode `0600`).
  - `auth::login(issuer, client_id, project_id) -> Result<Tokens>` — the spike's device flow (as built it takes the `Config`, which holds all three: `auth::login(&cfg) -> Result<Tokens>`, ruling R10's pattern; noted at the final review): `parse_device_start` and `parse_token_response` from `client.rs`, the polling loop from `client_main.rs`; scope `openid offline_access urn:zitadel:iam:org:project:id:<id>:aud`.
  - `auth::fresh_token(&mut Tokens) -> Result<String>` — refresh when within 300 s of expiry; on failure retry once after 1 s, then report "sign in again" (P0: one refresh failed on a reset and worked a second later).
  - `keys::load_or_create(dir) -> Result<Ed25519KeyPair>`, `keys::sign_hello(&key, device_id, ts, token) -> String` (base64 of the signature over Task 2's `hello_message`, with `sha256(token)` hex).
  - `login` ends by calling `POST /devices`, saving `device.json`, and printing the MCP URL plus the client id to paste into Claude.
  - HTTPS (device flow, token refresh, `POST /devices`): a `rustls` client config built the way slack-mcp's `tls::client_config()` builds one (rustls 0.23 on ring, rustls-native-certs 0.8), defined here in `connector/src/config.rs` and reused by Task 8's WebSocket. That avoids rustls-native-certs 0.7 and its unmaintained rustls-pemfile, as slack-mcp's comment notes.
  - Defaults, as constants in `connector/src/config.rs`: issuer `https://auth.ipv1337.dev`, relay `https://relay.ipv1337.dev`, connector client id `398912442404505402` and project id `398912441632687930` (the `zitadel-apps-relay` outputs `connectorClientId` and `projectId`, as the spike's `client.rs` hard-codes them). Each can be overridden by a `VRELAY_*` env var. Task 10's PR B adds the test `defaults_match_relay_stack` (the constants against `gitops/argocd/platform/relay/values.yaml`, which only exists from then), so a re-created client can't leave the connector pointing at the old one.

- [ ] **Step 1: Tests** `key_file_is_0600_and_reused`, `token_file_is_0600`, `sign_hello_verifies_with_public_key`,
  `fresh_token_refreshes_near_expiry`, `fresh_token_retries_once_then_asks_to_sign_in`
  (fake token endpoint failing once, then failing twice), `status_reports_signed_out`,
  `status_reports_stopped_when_status_file_is_stale`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): vrelay login, device key and token refresh`.

### Task 6: Local rules and the "ask first" prompt

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/{rules.rs,prompt.rs}`

**Interfaces:**
- Produces:
  - Rules file `rules.toml` in the state dir, created with defaults on first run:
    ```toml
    paused = false
    hidden = ["set_config_value", "get_config"]   # never exposed remotely
    config_allow = []    # settings tools to expose anyway; any other tool whose
                         # name contains "config" is hidden
    # While paused, no tools are visible and every call is refused.
    # Run without asking: reads only. Every other tool, including any tool a
    # future desktop-commander adds, asks first.
    no_prompt = ["read_file", "read_multiple_files", "list_directory",
                 "get_file_info", "start_search", "get_more_search_results",
                 "stop_search", "list_searches"]
    ```
  - `rules::load(dir) -> Result<Rules>`; `Rules::visible(&self, tools: &[ToolDef]) -> Vec<ToolDef>`; `Rules::decide(&self, tool: &str) -> Decision` with `enum Decision { Run, AskFirst, Refuse(&'static str) }`: `Refuse` for hidden tools or when paused, `Run` only for `no_prompt` tools, `AskFirst` for everything else (an unknown tool asks; it never runs silently). The tool names in `hidden`, `no_prompt` and the prompt summaries are provisional: they come from desktop-commander's source, not from the pinned 0.3.1 package's own `tools/list`. Task 7 step 5 checks them against the real list and corrects them here, with this task's tests, before Task 8.
  - `prompt::ask(tool: &str, summary: &str, timeout: Duration) -> PromptHandle`; `PromptHandle::wait(self) -> Answer` and `PromptHandle::dismiss(self)` (kills the dialog), with `enum Answer { Allow, Deny }`.
    The dialog is a fixed script, `osascript -e 'on run argv' -e 'display dialog (item 1 of argv) buttons {"Deny","Allow"} default button "Deny" giving up after (item 2 of argv as integer)' -e 'end run' -- <summary> <secs>`: the summary travels as an argument and is never put inside the script, so quotes and backslashes can't break out. `summary` is the tool name plus its key arguments, each cut to 200 characters with control characters removed: `start_process` → `command`; `interact_with_process` → `pid` and `input`; `write_file` → `path`; `edit_block` → `file_path`; `move_file` → `source` and `destination`; `create_directory` → `path`; `kill_process` / `force_terminate` → `pid`; `write_pdf` → `outputPath`. Any other tool shows its arguments as compact JSON. (Names are checked against the pinned package in Task 7.) Timeout, a non-zero exit or anything but "Allow" → `Deny`. Default timeout **60 s**.
  - The rules file is read at start and on `SIGHUP`; nothing received from the relay changes it.

- [ ] **Step 1: Tests** `reads_run_without_asking`,
  `unknown_tool_asks_first`, `hidden_tools_never_visible_or_callable`,
  `paused_refuses_everything`, `config_tools_are_hidden` (any tool whose name
  contains `config` is hidden unless named in the rules file's
  `config_allow = []` list, empty by default, so a renamed or new settings
  tool can't slip through), `paused_shows_no_tools` (while paused,
  `visible()` is empty and the connector sends `tools_changed`), `prompt_timeout_denies` (fake `osascript` on
  `PATH` that reports `gave up:true`), `prompt_failure_denies` (fake exits 1),
  `summary_shows_key_arguments` (one case per tool above),
  `prompt_passes_summary_as_argument` (fake records argv: a summary with `"`,
  `\` and a newline arrives intact as one argument, and the script text never
  contains it).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): local rules and ask-first prompt`.

### Task 7: Bridge to `desktop-commander`

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/bridge.rs`
- Create: `apps/suites/vitruvian-relay/connector/dc/{pnpm-workspace.yaml,package.json,pnpm-lock.yaml}` (the only `package.json`; it pins `@wonderwhy-er/desktop-commander` to exactly `0.3.1`) and a separate `npm_translate_lock` repository (`@vrelay_npm`) in `MODULE.bazel`. The folder's own `pnpm-workspace.yaml` makes it a workspace root, so pnpm stops there instead of joining the repo-root workspace; add its `pnpm-lock.yaml` to the ignore list in `tools/license/BUILD`, next to the root one. That keeps `desktop-commander`'s dependency tree in its own lock and can't move the main workspace's versions (spike D's re-lock changed unrelated Backstage entries; a second set of versions in the shared lock would break the One Version Rule, while a separate hub is the sanctioned way to diverge). `//tools/pnpm:lock` always runs from the repo root, so this task adds a `--dir` option to it (as `//tools/crates:lock` has, with a test) and locks with `bazel run //tools/pnpm:lock -- --dir apps/suites/vitruvian-relay/connector/dc`. `BUILD` uses that repository's `desktop-commander` binary as a runfile. `pnpm-workspace.yaml` is not changed

**Interfaces:**
- Produces:
  - `struct BridgeCommand { node: PathBuf, entry: PathBuf }` — where `node` and `desktop-commander`'s `dist/index.js` are. `BridgeCommand::locate()` reads `~/.local/share/vrelay/bridge.json` (`{"node": "...", "entry": "..."}`, written by the installer in Task 9); under `bazel run` it uses the runfiles path of the pinned package and the `node` on `PATH`.
  - `struct Bridge`, `Bridge::start(cmd: &BridgeCommand) -> Result<Bridge>`; `async fn tools(&self) -> Vec<ToolDef>`; `async fn call(&self, tool: &str, args: Value, deadline: Instant) -> BridgeOutput`; `fn stop(self)`.
  - `struct BridgeOutput { content: Value, is_error: bool, truncated: bool }` — Task 8 wraps it with the `call_id` into a `CallResult`.
  - Start: `Command::process_group(0)`, env `DESKTOP_COMMANDER_DISABLE_TELEMETRY=1`, `DC_FLAG_URL=http://127.0.0.1:9/`, stdin/stdout piped, stderr to the connector log. Check `node --version` ≥ 22.12 first and fail with how to install it.
  - JSON-RPC client over stdout lines: `initialize`, `tools/list`, `tools/call`. Lines with a `method` and no `id` (e.g. `notifications/message`) go to the log.
  - Truncation is measured on the **encoded `result` frame**, not the raw output (JSON escaping can grow it): if `protocol::encode` would exceed `MAX_FRAME_BYTES`, cut the text content and append `"[output truncated by vrelay: N bytes omitted]"`, set `truncated: true`, and re-encode until it fits.
  - At start, set `~/.claude-server-commander` to mode `0700` (its call log holds full arguments).
  - `vrelay tools`: start the bridge, print each tool name with what the rules decide for it (`run`, `ask first`, `hidden`), then stop. `vrelay tools --raw` prints `desktop-commander`'s own `tools/list` result as JSON instead, unfiltered.
  - Stop: close stdin, wait 2 s, then `killpg(SIGTERM)`, wait 2 s, then `killpg(SIGKILL)`. If the process exits on its own, kill the group too, fail pending calls, and restart on the next call.

- [ ] **Step 1: Tests** against a tiny fake MCP server script (a `sh_binary`
  that answers initialize/tools/list/tools/call and can spawn `sleep 30`):
  `lists_tools`, `notifications_are_logged_not_returned`,
  `crash_kills_group_and_restarts` (kill the fake mid-call: call errors, the
  `sleep 30` child is gone, next call works), `stop_kills_children`,
  `oversized_result_is_truncated_with_note` (output full of `"` and `\n`, so
  escaping doubles it: the encoded frame is ≤ 4 MiB), `old_node_is_refused`,
  `dc_config_dir_is_0700`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS. Then check the locks: the root `pnpm-lock.yaml` is unchanged, and the
  connector's own lock passes its `--check`. npm, checked 2026-11-15: `dist-tags.latest` is **0.3.3**,
  and 0.3.1's integrity matches the pin above exactly. P1 stays on 0.3.1, the
  version spike D tested; 0.3.3 is a later reviewed bump (re-run spike D's
  checks against it first).
- [ ] **Step 5:** One manual check with the real package:
  `bazel run //apps/suites/vitruvian-relay/connector:vrelay -- tools` lists its
  tools (spike D saw 25) minus the hidden ones. Compare the names with Task 6's
  `hidden` and `no_prompt` lists, and the argument names Task 6's prompt
  summary reads with each tool's `inputSchema` properties; fix any that differ.
  Save the output of `bazel run //apps/suites/vitruvian-relay/connector:vrelay -- tools --raw`
  as `connector/testdata/dc-0.3.1-tools.json`
  (listed in `:unit_tests`' `data` and read through runfiles)
  and add the test `summary_keys_exist_in_pinned_schemas` (every key the
  summary reads exists in the saved schema for that tool).
- [ ] **Step 6: Commit** `feat(relay): run desktop-commander safely over stdio`.

### Task 8: `vrelay run` — the link to the relay

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/link.rs`; modify `main.rs`

**Interfaces:**
- Consumes: Tasks 2, 5, 6, 7.
- Produces:
  - TLS for `wss://`: tokio-tungstenite 0.24 (as the spike uses) with Task 5's `rustls` client config, passed as `Connector::Rustls`. Its `__rustls-tls` feature exposes `Connector::Rustls` without its own root-store crates; it looks like an internal feature name, so after locking confirm `rustls-pemfile`, `rustls-native-certs` 0.7 and `aws-lc-rs` are absent from `Cargo.lock` and osv-scan passes.
  - `vrelay run`: start the bridge, connect to `wss://<relay>/connect` with a fresh token, send `hello` with `Rules::visible(bridge.tools())`, then loop.
  - On `call`: dedupe by `call_id` for 10 minutes. A repeat re-sends the stored result or, if still running, nothing. Started ids are also appended to `seen_calls.jsonl` in the state dir (id and time only, pruned after 10 minutes), so after a LaunchAgent restart a resent id is refused with "This call already started before vrelay restarted; not run again." rather than run twice. This is the spec's repeated-id rule (§4), kept as a safeguard: the P1 relay never resends a call (Task 3 fails it instead), and an id repeated after the 10-minute window runs again. The real duplicate risk, an AI app's own retry, arrives with a new id and is spec §11 question 14. `Rules::decide` → `Run` / `AskFirst` (prompt) / `Refuse`, then `Bridge::call`, then `result`. A denied prompt returns `is_error: true`, "Denied on the computer."
  - On `cancel`: if the call is still waiting at its "ask first" prompt, dismiss the dialog and never run it. If it is already running, drop the result (the command itself is not killed in P1; the local log notes it).
  - Ping the relay every 20 s and answer its pings. 3 unanswered pings either way → reconnect. The link loop never waits on a call: prompts and bridge calls run in their own tasks, so pongs keep flowing while an "ask first" dialog is open (the relay pings every 2 s during a call).
  - When the link drops, dismiss every open prompt and refuse those calls locally, so a later "Allow" can't run a command the relay has already failed.
  - Reconnect after any drop: attempt `n` starts at 0, delay = `max(1, random(0..=min(60, 2^n)))` seconds (full jitter with a 1 s floor, so the first retry is 1 s and none is ever 0 s or over 60 s). Reset `n` after 60 s connected. Refresh the token before each attempt (`auth::fresh_token`).
  - `vrelay run` keeps Task 5's `status.json` current (written atomically every 20 s and on every change): `connecting` with the next retry time, `connected` after `welcome` (refreshed on each pong), `waiting for sign-in` with no token.
  - With no token yet (installed before `vrelay login`), `run` waits, checking for `token.json` every 10 s, instead of exiting; launchd's `KeepAlive` would otherwise restart it in a loop.
  - Local log of every call with full arguments at `~/Library/Logs/vrelay/calls.log` (§7.3, user-only `0600`). Each line records the decision too: `ran`, `denied`, `timed out` (prompt gave up), `cancelled at prompt`, `refused` (hidden or paused), or `link dropped at prompt`.
  - On `SIGHUP`: reload rules and send `tools_changed`.

- [ ] **Step 1: Tests** with an in-process fake relay (tokio-tungstenite server):
  `sends_hello_with_visible_tools_only`, `repeated_call_id_runs_once`,
  `ask_first_denied_returns_error`, `repeated_call_id_after_restart_is_refused`,
  `concurrent_calls_are_answered_by_id` (two calls in flight, the fake
  bridge finishes them in reverse order, each `result` carries its own
  `call_id`),
  `cancel_during_prompt_never_runs` (cancel arrives while the fake dialog is
  open: dialog dismissed, bridge never called, even if the fake then answers
  Allow), `pongs_flow_while_prompt_open` (a fake prompt held open for 30 s
  while the fake relay pings every 2 s: no ping missed),
  `link_drop_dismisses_open_prompts` (the link drops while the fake dialog is
  open: dialog dismissed, call refused locally, even if the fake then answers
  Allow), `reconnects_with_jittered_backoff`
  (inject clock/rng; every delay within `[1, min(60, 2^n)]`), `waits_for_token_instead_of_exiting`, `status_file_tracks_link_state`
  (connecting → connected after welcome → connecting after a drop, and
  waiting for sign-in with no token), `refreshes_token_before_reconnect`,
  `missed_pings_trigger_reconnect`, `call_log_is_0600_and_has_arguments`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): vrelay run links the Mac to the relay`.

### Task 9: Install as a LaunchAgent (signed)

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/scripts/{Cargo.toml,BUILD (`:unit_tests` and a `pipeline_unit`),src/lib.rs,src/main.rs,com.vitruvian.vrelay.plist}` (it is a workspace member, so it needs its own `Cargo.toml`)

Follow `apps/mobile/vitruvian-remote/macagent/scripts` (`render_plist`,
`launchctl bootout` / `bootstrap gui/<uid>` / `enable`).

**Interfaces:**
- Produces: `bazel run //apps/suites/vitruvian-relay/connector/scripts:install` (its `data` is `//apps/suites/vitruvian-relay/connector:vrelay`, the `@vrelay_npm` `desktop-commander` package, and the plist template) — copies `vrelay` and the pinned `desktop-commander` package to `~/.local/share/vrelay/` and writes `~/.local/share/vrelay/bridge.json` with the absolute `node` path and `desktop-commander/dist/index.js` path (Task 7's `BridgeCommand::locate`), signs the binary with the Developer ID identity (identifier `dev.vitruvian.vrelay`), as the Mac apps are signed (see `developer_id_identity` in `apps/desktop/vitruvian-atrium/build.sh`, lines 69–74). The macagent pattern this follows signs with its own identity and falls back to unsigned; vrelay doesn't fall back. If `security find-identity -p codesigning` doesn't list it, the install **fails** with how to get it, unless `--unsigned` is passed explicitly. Resolves the absolute path of `node` (≥ 22.12) at install time and writes it into the plist's `EnvironmentVariables` `PATH` (its folder, then `/usr/bin:/bin`), because launchd starts agents with a minimal `PATH` that usually lacks Homebrew or mise. Writes the plist from the template at `connector/scripts/com.vitruvian.vrelay.plist`, with label `com.vitruvian.vrelay`, `KeepAlive` true and log `~/Library/Logs/vrelay/vrelay.log`, creates `~/Library/Logs/vrelay/` (mode `0700`) first because launchd won't create it and the agent then never starts, and loads it. `//apps/suites/vitruvian-relay/connector/scripts:uninstall` reverses it.

- [ ] **Step 1: Tests** `render_plist_fills_paths_and_args`, `plist_path_includes_node_dir`, `install_fails_without_identity`, `install_creates_log_dir`, `unsigned_flag_skips_signing_with_warning`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector/scripts:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): install vrelay as a signed LaunchAgent`.

### Task 10: Deploy the relay, Zitadel changes, retire the spike

**Files:**
This task ships as **two PRs** (step 2 says why). **PR A:** the Dockerfile, chart, chart-render values file and image workflow. **PR B:** the AppProject, the Argo CD Application and the gitops values file.

- Create: `gitops/argocd/projects/relay-project.yaml` and `gitops/argocd/applications/relay.yaml` (PR B) (from `relay-spike-project.yaml`, with its destination namespace changed to `relay` and `PersistentVolumeClaim` added to `namespaceResourceWhitelist`, or Argo CD refuses the volume), `tools/ci/chart-render/vitruvian-relay.values.yaml` (from the spike's; CI finds it by chart name, so the chart is named `vitruvian-relay` in `Chart.yaml`), `apps/suites/vitruvian-relay/relay/Dockerfile`. The build context is the workspace root, `apps/suites/vitruvian-relay` (from the repo root: `docker buildx build -f apps/suites/vitruvian-relay/relay/Dockerfile --build-context mcpauth=packages/rust/vitruvian-mcp-auth … apps/suites/vitruvian-relay`), because the relay is a member of that workspace. The shared crate comes in as a named build context, `mcpauth=packages/rust/vitruvian-mcp-auth` (the spike does the same with `slackmcp`), copied to `/src/packages/rust/vitruvian-mcp-auth` (its `Cargo.toml` and `src/` only: it has no `Cargo.lock` of its own, because the relay workspace's lock covers it); the workspace is copied to `/src/apps/suites/vitruvian-relay`, so the relay's `../../../../packages/rust/vitruvian-mcp-auth` path dependency (declared in `relay/Cargo.toml`, four levels up from `apps/suites/vitruvian-relay/relay`) resolves. `WORKDIR /src/apps/suites/vitruvian-relay`, then `cargo build --release --locked -p vitruvian-relay`. The image workflow passes `--build-context mcpauth=…` everywhere the spike's passes `slackmcp`, its `paths:` filter lists `apps/suites/vitruvian-relay/**` and `packages/rust/vitruvian-mcp-auth/**`, it runs `vitruvian-relay --version` in its verify step, and it pushes to `ghcr.io/vitruviansoftware/vitruvian-relay`, the chart's `image.repository`, `relay/deploy/chart/` (Service, HTTPRoute, DNSEndpoint for `relay.ipv1337.dev`, NetworkPolicy and the `affinity` value copied from the spike's chart, with `_helpers.tpl`'s `vitruvian-relay-spike.*` template names renamed to `vitruvian-relay.*`, with the HTTPRoute also passing `/devices` (match type `Exact`), which the spike's route lacks, and `/mcp/d/` as a `PathPrefix`; the affinity *rule* itself comes from `gitops/argocd/platform/relay-spike/values.yaml`; new: a 1 GiB PVC mounted at `/data` for the device file, with `storageClassName: nfs`, and `fsGroup: 10001` in the pod's securityContext, because the pod runs as UID 10001 and the NFS volume starts root-owned (likely, not yet confirmed: step 2 checks a real write). The default `local-path` class would pin the volume, and so the pod, to one node, defeating the three-node allow list), `gitops/argocd/applications/relay.yaml`, `gitops/argocd/platform/relay/values.yaml` (with the #4916 allow-list affinity; `MCP_CLIENT_IDS` = the `claudeClientId` and `geminiClientId` outputs), image build workflow mirroring `vitruvian-relay-spike-image`
- One sign-in (P1-required, James decides). Check, and write down in this
  plan: which login screen the device-approval page (`/oauth/v2/device`)
  uses, whether this Zitadel version's Login V2 serves it, and whether any
  `pulumi-zitadel` release newer than v0.2.0 adds a per-app login version.
  Then **stop and ask James**, with the options found: upgrade Zitadel, change
  an instance-wide setting (it affects every app, and an upstream issue, zitadel/zitadel#12148, reports a Login V2 problem with OTP second factors; check its status before choosing this), or
  accept two sign-ins for P1 and record it.
- Optional for P1 (unlike the one sign-in above): Gemini's callback is tied to
  the server URL (spike A), so the new relay URL needs a new callback in
  `geminiRedirectUris` before Gemini can use it. Note it in the stack README if
  not done.
- Delete (in a separate PR, after Task 11 passes), also removing `vitruvian_relay_spike_crates` from the `ring` annotation, regenerating `.github/workflows/presubmit.yaml` (it lists `vitruvian-relay-spike-service`), and `tools/ci/chart-render/vitruvian-relay-spike.values.yaml`: `apps/suites/vitruvian-relay/spike/`, `gitops/argocd/applications/relay-spike.yaml`, `gitops/argocd/platform/relay-spike/`, `gitops/argocd/projects/relay-spike-project.yaml`, `.github/workflows/vitruvian-relay-spike-image.yaml`, the spike hub in `MODULE.bazel`, and the slack-mcp visibility exception for the spike.

- [ ] **Step 1:** Set the chart defaults that the spike's chart pins to itself: `hostname: relay.ipv1337.dev` (the DNS record and `PUBLIC_URL` both read it) and `image.repository: ghcr.io/vitruviansoftware/vitruvian-relay`. Render check in PR A, with the CI values file (the gitops values come in PR B): `bazel run //tools/gitops:helm -- template t apps/suites/vitruvian-relay/relay/deploy/chart -f tools/ci/chart-render/vitruvian-relay.values.yaml` → a Deployment with the PVC, `fsGroup` and env.
- [ ] **Step 2:** Ship in two PRs, because the chart pins its image by digest and the digest exists only after the image workflow's first push-to-`main` run. **PR A:** relay code, Dockerfile, chart, chart-render values and image workflow, with no Argo CD app yet. After it merges, read the pushed digest from that run's output. **PR B:** the AppProject, `gitops/argocd/applications/relay.yaml` and `gitops/argocd/platform/relay/values.yaml`, which sets every value the chart requires: `image.digest` (that digest), `oidc.projectId`, `oidc.mcpClientIds`, `oidc.connectorClientId` and `oidc.allowedSubjects` (the `zitadel-apps-relay` outputs and James's subject, as the spike's values file does), plus the affinity. `tunnel.id` keeps the chart default copied from the spike. `gitops/argocd/applications/relay.yaml` names `project: relay-project` and keeps the spike app's `syncOptions` (`CreateNamespace=true`, `ServerSideApply=true`), or the first sync fails on the missing `relay` namespace. PR B also adds the connector test `defaults_match_relay_stack` (Task 5's constants against this values file, read through runfiles). PR B renders with `bazel run //tools/gitops:helm -- template t apps/suites/vitruvian-relay/relay/deploy/chart -f gitops/argocd/platform/relay/values.yaml` before it opens (later bumps are by hand, as the spike's are: the plan adds no image-updater config). Merge PR B; confirm the Argo CD app is Synced and Healthy (the PVC is accepted), then confirm with `bazel run //tools/gitops:get -- pods -n relay -o wide` that the pod is Running on `fedora`, `nuc9i5` or `nuc9i9`, that a test device registration wrote `/data/devices.json` (relay log line on startup and after `POST /devices`), and that `https://relay.ipv1337.dev/.well-known/oauth-protected-resource` serves PRM.
- [ ] **Step 3:** If James chose a change in the `zitadel-apps-relay` stack: preview then apply `zitadel-apps-relay-apply.yaml`. `workflow-run` works only as wren, so run it without `--agent`: `bazel run //tools/agent-app -- workflow-run zitadel-apps-relay-apply.yaml -f action=preview`, read it, then `-f action=up`. Expect only in-place updates.
- [ ] **Step 4:** After Task 11 passes, retire the spike (the Delete list above) in its own PR.
- [ ] **Step 5: Commit** `feat(relay): deploy the relay to the homelab`.

### Task 11: Done-when — Claude on the phone runs a command on the Mac

Manual, with James.

- [ ] **Step 1:** `vrelay login` first (`bazel run //apps/suites/vitruvian-relay/connector:vrelay -- login`; one sign-in or two, per James's Task 10 decision). It prints the MCP URL. Then `bazel run //apps/suites/vitruvian-relay/connector/scripts:install`, and `vrelay status` shows connected.
- [ ] **Step 2:** James adds that URL in Claude (web) as a custom connector with the `relay-claude` client id (`398912442404439866`, the `claudeClientId` output) and signs in.
- [ ] **Step 3:** From the **Claude phone app**: "list the files in my Downloads folder" runs without a prompt (a read). Relay log shows `tools/call` from client `398912442404439866`, no arguments.
- [ ] **Step 4:** From the phone: "run `uname -a`". The "Allow?" dialog appears on the Mac; Allow → the output comes back to the phone. Repeat and Deny → Claude shows "Denied on the computer."
- [ ] **Step 5:** Leave a "run" request's dialog unanswered for 60 s: Claude
  shows "Denied on the computer." Then send one and stop it from the phone while
  the dialog is open: the dialog should close and nothing run (`calls.log`
  says `cancelled at prompt`). Nothing yet shows whether Claude sends
  `notifications/cancelled` or drops the request when the user stops; if it
  does neither, record that here (the dialog then times out as Deny) and raise
  it as a P2 item.
- [ ] **Step 6:** Turn the Mac's Wi-Fi off mid-command: the phone gets "Your computer disconnected; try again." within about 6 s. Wi-Fi on: `vrelay status` shows connected within about a minute.
- [ ] **Step 7:** Record the result in this plan (yes or no, with log lines), set `status: completed`, and update spec §10's P1 row.
