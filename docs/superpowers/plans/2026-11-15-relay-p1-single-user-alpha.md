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
moves out of the Slack MCP into a shared crate both use.

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
  (Claude is the done-when).
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
  and not built. Ping every **20 s**, **3** missed pings = offline. Frames
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
- **Repo rules:** every git, gh, cluster and Pulumi operation through the Bazel
  targets in `AGENTS.md`. Commits via `bazel run //tools/git:commit -- --agent
  <you>`. Raw `cargo` is blocked; re-lock with `bazel run //tools/crates:lock
  -- --dir <path>`.

## Review Focus

1. **The Mac sleeps or drops off Wi-Fi mid-call.** The AI app should get
   "Your computer disconnected" within a second or two, not wait for the
   deadline. Test in Task 3 (`pending_call_fails_when_device_drops`).
2. **Nobody is at the Mac when an "ask first" call arrives.** The prompt must
   time out as **Deny**, never Allow. Test in Task 6
   (`prompt_timeout_denies`).
3. **`desktop-commander` crashes mid-command.** The call returns an error, the
   command it started is killed with it, and the next call starts a fresh
   process. Test in Task 7 (`crash_kills_group_and_restarts`).
4. **A command prints far more than 4 MiB.** The result is cut to fit with a
   note saying so, and the WebSocket stays up. Test in Task 7
   (`oversized_result_is_truncated_with_note`).
5. **The relay resends a call after a reconnect.** The command must not run
   twice. Test in Task 8 (`repeated_call_id_runs_once`).

---

## File Structure

```
packages/rust/vitruvian-mcp-auth/         shared token checking (from slack-mcp auth.rs)
  Cargo.toml, BUILD, src/lib.rs, src/verifier.rs, src/prm.rs
apps/suites/vitruvian-relay/
  Cargo.toml, Cargo.lock                   workspace: relay, connector, mcp-auth
  protocol/  src/lib.rs                    frame types shared by relay and connector
  relay/     src/{main,config,registry,mcp,http,devices}.rs, Dockerfile, deploy/chart/
  connector/ src/{main,auth,keys,rules,prompt,bridge,link}.rs, package.json (desktop-commander pin)
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
- Create: `packages/rust/vitruvian-mcp-auth/{Cargo.toml,BUILD,src/lib.rs,src/verifier.rs,src/prm.rs}`
- Create: `apps/suites/vitruvian-relay/Cargo.toml` (workspace; member list grows in later tasks), `Cargo.lock`
- Modify: `MODULE.bazel` (add hub `vitruvian_relay_crates`; keep the spike hub until Task 10)
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

The checks are exactly slack-mcp's `auth.rs`: RS256 only, modulus ≥ 2048
bits, JWKS `{issuer}/oauth/v2/keys` cached 600 s with a 30 s refetch
cooldown, `iss` exact, `exp`/`nbf` 30 s skew, `aud` contains `project_id`,
`sub` in the allow-list, any `azp` rejected, `client_id` in
`allowed_client_ids`. Use `serde_json` instead of slack-mcp's own `JsonValue`.

- [ ] **Step 1: Write the failing tests** — port slack-mcp's verifier tests,
  plus `accepts_any_listed_client_id` (two ids, a token for each verifies) and
  `rejects_unlisted_client_id` (`AuthError` code `"invalid_client"`), and
  `prm_lists_project_audience_scope` (scopes `openid`, `offline_access`,
  `urn:zitadel:iam:org:project:id:<id>:aud`).
- [ ] **Step 2:** `bazel test //packages/rust/vitruvian-mcp-auth:unit_tests` → FAIL (crate missing).
- [ ] **Step 3: Implement** the crate; add the hub, re-lock with
  `bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay`, then `bazel run //:gazelle`.
- [ ] **Step 4:** the same test → PASS; `bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay --check` → clean.
- [ ] **Step 5: Commit** `feat(relay): shared MCP token checking crate`.

Moving the Slack MCP onto this crate is **not** in P1: it builds from its own
hub, and one crate from two hubs is two crates. Record it as a follow-up issue
in this task's PR.

### Task 2: Protocol frames

**Files:**
- Create: `apps/suites/vitruvian-relay/protocol/{Cargo.toml,BUILD,src/lib.rs}`

**Interfaces:**
- Produces (serde, `#[serde(tag = "type", rename_all = "snake_case")]`):
  - `enum ToRelay { Hello(Hello), Result(CallResult), ToolsChanged { tools: Vec<ToolDef> }, Pong { n: u64 } }`
  - `enum ToConnector { Welcome { device_id: String }, Reject { reason: String }, Call(Call), Cancel { call_id: String }, Ping { n: u64 } }`
  - `struct Hello { device_id: String, connector_version: String, protocol: u32, ts: u64, sig: String, tools: Vec<ToolDef> }`
  - `struct Call { call_id: String, tool: String, arguments: serde_json::Value, deadline_ms: u64 }`
  - `struct CallResult { call_id: String, content: serde_json::Value, is_error: bool, truncated: bool }`
  - `struct ToolDef { name: String, description: String, input_schema: serde_json::Value }`
  - `const PROTOCOL: u32 = 1; const MAX_FRAME_BYTES: usize = 4 * 1024 * 1024; const PING_SECS: u64 = 20; const MAX_MISSED_PINGS: u32 = 3;`
  - `fn hello_message(device_id: &str, ts: u64, token_sha256_hex: &str) -> String` → `"vrelay-hello-v1\n{device_id}\n{ts}\n{token_sha256_hex}"` (the bytes the device key signs; binding the token hash stops replay with another token)
  - `fn encode(&impl Serialize) -> Result<String, FrameError>` (refuses over `MAX_FRAME_BYTES`), `fn decode_to_relay(&str)`, `fn decode_to_connector(&str)`

- [ ] **Step 1: Tests** `round_trips_every_frame`, `rejects_unknown_type`,
  `encode_refuses_oversized_frame`, `hello_message_is_stable` (exact string above).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/protocol:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): connector/relay protocol frames`.

### Task 3: Relay core — device registry and call routing

**Files:**
- Create: `apps/suites/vitruvian-relay/relay/src/{registry.rs,devices.rs}`, `BUILD`, `Cargo.toml`

**Interfaces:**
- Consumes: Task 2 frames.
- Produces:
  - `struct DeviceRecord { device_id: String, owner_sub: String, public_key_ed25519: [u8; 32] }`
  - `trait DeviceStore: Send + Sync { fn get(&self, id: &str) -> Option<DeviceRecord>; fn put(&self, rec: DeviceRecord) -> io::Result<()>; }`
  - `struct FileDeviceStore` (JSON file, atomic rename on write; `/data/devices.json` in the pod) — P2 replaces it with Postgres behind the same trait.
  - `struct Registry` with `connect(&self, device_id, tools, tx: mpsc::Sender<ToConnector>) -> ConnectionId`, `disconnect(&self, device_id, ConnectionId)`, `tools(&self, device_id) -> Option<Vec<ToolDef>>`, `async fn call(&self, device_id, Call) -> Result<CallResult, CallError>`, `complete(&self, CallResult)`
  - `enum CallError { Offline, Disconnected, Deadline, NotOwner }` with `user_message()`: `"Your computer is offline."`, `"Your computer disconnected; try again."`, `"The command took too long."`, `"Not your device."`

`call` registers a oneshot under `call_id`, sends the frame, and waits for
`complete`, the deadline, or the device's disconnect, whichever comes first.
`disconnect` fails every pending call for that connection with
`Disconnected` at once (P0 requirement). A newer connection for the same
device replaces the old one (its pending calls fail `Disconnected`).

- [ ] **Step 1: Tests** `call_returns_device_result`,
  `pending_call_fails_when_device_drops` (disconnect mid-call → `Disconnected`
  in under 100 ms), `call_to_offline_device_fails_fast`,
  `deadline_expiry_sends_cancel`, `reconnect_replaces_old_connection`,
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
  - `struct Settings` from env: `PORT` (3000), `PUBLIC_URL`, `ISSUER`, `PROJECT_ID`, `MCP_CLIENT_IDS` (CSV), `CONNECTOR_CLIENT_ID`, `ALLOWED_SUBJECTS` (CSV), `DATA_DIR` (`/data`). Same validation as the spike's `Settings::from_lookup`.
  - Routes:
    - `POST /mcp/d/{device_id}` — MCP over Streamable HTTP (JSON responses; SSE not needed in P1). Bearer verified with the MCP client ids; caller `sub` must equal the device's `owner_sub`, else 404 (don't reveal the device).
    - `GET /.well-known/oauth-protected-resource/mcp/d/{device_id}` and the bare `/.well-known/oauth-protected-resource` — PRM with `resource` = that device's URL.
    - `POST /devices` — bearer verified with `CONNECTOR_CLIENT_ID`; body `{ "public_key": "<base64 32 bytes>" }`; creates a record owned by the caller, returns `{ "device_id": "<uuid v4>", "mcp_url": "…" }`. P1 allows one device per subject: a second call for the same subject replaces the key and keeps the id.
    - `GET /connect` — WebSocket. Bearer verified with `CONNECTOR_CLIENT_ID`. First frame must be `hello` within 10 s: device exists, owned by the caller, `|now − ts| ≤ 60 s`, Ed25519 `sig` over `hello_message(device_id, ts, sha256(bearer))` verifies, `protocol == 1`. Otherwise `reject` with the reason and close. Then `welcome`, `Registry::connect`, ping every 20 s, disconnect after 3 missed pongs.
  - `mcp::handle(req, device_id, caller, registry) -> Option<Value>`: `initialize` (protocol versions as the spike's `PROTOCOL_VERSIONS`), `ping`, `server/discover` (name `vitruvian-relay`, version, the device URL), `tools/list` (the device's tools; empty list plus no error if offline), `tools/call` (→ `Registry::call`; `CallError` becomes an MCP tool result with `isError: true` and `user_message()`), and `notifications/tools/list_changed` sent when `tools_changed` arrives (P1: only on the next request, no SSE).
  - Logging: one line per call — device id, tool, argument bytes, result bytes, duration, outcome. Never arguments or output (§7.2).

- [ ] **Step 1: Tests** (hyper test client against an in-process server, with a
  test JWKS like slack-mcp's tests): `mcp_requires_token_with_www_authenticate`,
  `mcp_rejects_other_users_device_as_404`, `server_discover_is_answered`,
  `tools_list_reflects_hello_tools`, `connect_rejects_bad_signature`,
  `connect_rejects_stale_ts`, `connect_rejects_token_for_another_client`,
  `register_device_returns_mcp_url`, `logs_never_contain_arguments`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay:unit_tests` → FAIL.
- [ ] **Step 3: Implement** with hyper 1 + tokio-tungstenite, copying the spike's `main.rs` routing shape.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): MCP, PRM, device registration and /connect`.

### Task 5: Connector sign-in, device key and token refresh

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/{main.rs,auth.rs,keys.rs}`, `BUILD`, `Cargo.toml`

**Interfaces:**
- Produces:
  - Commands: `vrelay login`, `vrelay status`, `vrelay logout` (`run` and `install` come in Tasks 8–9).
  - State dir: `~/Library/Application Support/vrelay/` (`$VRELAY_HOME` overrides, for tests), mode `0700`; files `token.json`, `device.json` (`{device_id, mcp_url}`), `device.key` (Ed25519 seed, mode `0600`).
  - `auth::login(issuer, client_id, project_id) -> Result<Tokens>` — the spike's device flow (`client.rs`), scope `openid offline_access urn:zitadel:iam:org:project:id:<id>:aud`.
  - `auth::fresh_token(&mut Tokens) -> Result<String>` — refresh when within 300 s of expiry; on failure retry once after 1 s, then report "sign in again" (P0: one refresh failed on a reset and worked a second later).
  - `keys::load_or_create(dir) -> Result<Ed25519KeyPair>`, `keys::sign_hello(&key, device_id, ts, token) -> String` (base64 of the signature over Task 2's `hello_message`, with `sha256(token)` hex).
  - `login` ends by calling `POST /devices`, saving `device.json`, and printing the MCP URL plus the client id to paste into Claude.
  - Defaults: issuer `https://auth.ipv1337.dev`, relay `https://relay.ipv1337.dev`, connector client id and project id from the `zitadel-apps-relay` outputs (overridable by `VRELAY_*` env vars).

- [ ] **Step 1: Tests** `key_file_is_0600_and_reused`, `sign_hello_verifies_with_public_key`,
  `fresh_token_refreshes_near_expiry`, `fresh_token_retries_once_then_asks_to_sign_in`
  (fake token endpoint failing once, then failing twice), `status_reports_signed_out`.
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
    ask_first = ["start_process", "interact_with_process", "write_file",
                 "edit_block", "move_file", "create_directory", "kill_process",
                 "force_terminate", "write_pdf"]
    allowed_paths = []        # empty = desktop-commander's own default
    ```
  - `rules::load(dir) -> Result<Rules>`; `Rules::visible(&self, tools: &[ToolDef]) -> Vec<ToolDef>`; `Rules::decide(&self, tool: &str) -> Decision` with `enum Decision { Run, AskFirst, Refuse(&'static str) }` (`Refuse` for hidden tools or when paused).
  - `prompt::ask(tool: &str, summary: &str, timeout: Duration) -> Answer` with `enum Answer { Allow, Deny }`, via `osascript -e 'display dialog … buttons {"Deny","Allow"} default button "Deny" giving up after <secs>'`. Timeout → `Deny`. `summary` is the tool name plus the first 200 characters of the command or path, with control characters removed and quotes escaped for AppleScript. Default timeout **60 s**.
  - The rules file is read at start and on `SIGHUP`; nothing received from the relay changes it.

- [ ] **Step 1: Tests** `defaults_ask_first_for_terminal_and_writes`,
  `hidden_tools_never_visible_or_callable`, `paused_refuses_everything`,
  `prompt_timeout_denies` (fake `osascript` on `PATH` that reports `gave up:true`),
  `prompt_escapes_quotes_and_controls` (a command containing `"` and a newline
  produces a valid script).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): local rules and ask-first prompt`.

### Task 7: Bridge to `desktop-commander`

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/bridge.rs`, `apps/suites/vitruvian-relay/connector/package.json` (pins `@wonderwhy-er/desktop-commander` `0.3.1`)
- Modify: `pnpm-lock.yaml` via `bazel run //tools/pnpm:lock`; `BUILD` (rules_js `desktop_commander` binary as a runfile)

**Interfaces:**
- Produces:
  - `struct Bridge`, `Bridge::start(cmd: &BridgeCommand) -> Result<Bridge>`; `async fn tools(&self) -> Vec<ToolDef>`; `async fn call(&self, tool, args, deadline) -> CallResult`; `fn stop(self)`.
  - Start: `Command::process_group(0)`, env `DESKTOP_COMMANDER_DISABLE_TELEMETRY=1`, `DC_FLAG_URL=http://127.0.0.1:9/`, stdin/stdout piped, stderr to the connector log. Check `node --version` ≥ 22.12 first and fail with how to install it.
  - JSON-RPC client over stdout lines: `initialize`, `tools/list`, `tools/call`. Lines with a `method` and no `id` (e.g. `notifications/message`) go to the log.
  - Results over `MAX_FRAME_BYTES − 64 KiB` are cut, with `"[output truncated by vrelay: N bytes omitted]"` appended and `truncated: true`.
  - Stop: close stdin, wait 2 s, then `killpg(SIGTERM)`, wait 2 s, then `killpg(SIGKILL)`. If the process exits on its own, kill the group too, fail pending calls, and restart on the next call.

- [ ] **Step 1: Tests** against a tiny fake MCP server script (a `sh_binary`
  that answers initialize/tools/list/tools/call and can spawn `sleep 30`):
  `lists_tools`, `notifications_are_logged_not_returned`,
  `crash_kills_group_and_restarts` (kill the fake mid-call: call errors, the
  `sleep 30` child is gone, next call works), `stop_kills_children`,
  `oversized_result_is_truncated_with_note`, `old_node_is_refused`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS. Then one manual check with the real package:
  `bazel run //apps/suites/vitruvian-relay/connector:vrelay -- tools` lists 25
  tools minus the hidden ones.
- [ ] **Step 5: Commit** `feat(relay): run desktop-commander safely over stdio`.

### Task 8: `vrelay run` — the link to the relay

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/src/link.rs`; modify `main.rs`

**Interfaces:**
- Consumes: Tasks 2, 5, 6, 7.
- Produces:
  - `vrelay run`: start the bridge, connect to `wss://<relay>/connect` with a fresh token, send `hello` with `Rules::visible(bridge.tools())`, then loop.
  - On `call`: dedupe by `call_id` (remember ids for 10 minutes; a repeat re-sends the stored result or, if still running, nothing), `Rules::decide` → `Run` / `AskFirst` (prompt) / `Refuse`, then `Bridge::call`, then `result`. A denied prompt returns `is_error: true`, "Denied on the computer."
  - On `cancel`: drop the waiting result (the command itself is not killed in P1; note it).
  - Answer `ping` with `pong`. If no `ping` for 3 × 20 s, reconnect.
  - Reconnect after any drop: backoff `min(60, 2^attempt)` s with full jitter (random 0..delay), reset after 60 s connected; refresh the token before each attempt (`auth::fresh_token`).
  - Local log of every call with full arguments at `~/Library/Logs/vrelay/calls.log` (§7.3, user-only `0600`).
  - On `SIGHUP`: reload rules and send `tools_changed`.

- [ ] **Step 1: Tests** with an in-process fake relay (tokio-tungstenite server):
  `sends_hello_with_visible_tools_only`, `repeated_call_id_runs_once`,
  `ask_first_denied_returns_error`, `reconnects_with_jittered_backoff`
  (inject clock/rng; delays within `[0, min(60, 2^n)]`), `refreshes_token_before_reconnect`,
  `missed_pings_trigger_reconnect`, `call_log_is_0600_and_has_arguments`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): vrelay run links the Mac to the relay`.

### Task 9: Install as a LaunchAgent (signed)

**Files:**
- Create: `apps/suites/vitruvian-relay/connector/scripts/{BUILD,src/lib.rs,src/main.rs}`, `com.vitruvian.vrelay.plist`

Follow `apps/mobile/vitruvian-remote/macagent/scripts` (`render_plist`,
`launchctl bootout` / `bootstrap gui/<uid>` / `enable`).

**Interfaces:**
- Produces: `bazel run //apps/suites/vitruvian-relay/connector:install` — copies `vrelay` and the pinned `desktop-commander` runfiles to `~/.local/share/vrelay/`, signs the binary with the Developer ID identity when `security find-identity -p codesigning` lists it (identifier `dev.vitruvian.vrelay`), writes the plist (label `com.vitruvian.vrelay`, `KeepAlive` true, log `~/Library/Logs/vrelay/vrelay.log`), and loads it. `:uninstall` reverses it.

- [ ] **Step 1: Tests** `render_plist_fills_paths_and_args`, `install_skips_signing_without_identity`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector/scripts:unit_tests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** → PASS.
- [ ] **Step 5: Commit** `feat(relay): install vrelay as a signed LaunchAgent`.

### Task 10: Deploy the relay, Zitadel changes, retire the spike

**Files:**
- Create: `apps/suites/vitruvian-relay/relay/Dockerfile`, `relay/deploy/chart/` (from the spike's chart: Deployment with a 1 GiB PVC at `/data`, Service, HTTPRoute, DNSEndpoint for `relay.ipv1337.dev`, NetworkPolicy), `gitops/argocd/applications/relay.yaml`, `gitops/argocd/platform/relay/values.yaml` (with the #4916 allow-list affinity; `MCP_CLIENT_IDS` = the `claudeClientId` and `geminiClientId` outputs), image build workflow mirroring `vitruvian-relay-spike-image`
- Modify: `infrastructure/pulumi/platform/zitadel-apps-relay/` — no client changes needed (the clients are not tied to a host), but set the clients to Zitadel Login V2 if the pinned provider exposes it, so device approval and AI-app sign-in share one session (P0 spike B signed in twice). If the provider has no such field, record that in the stack README and leave it for P2. Gemini's callback is tied to the server URL (spike A), so the new relay URL needs a new callback in `geminiRedirectUris` before Gemini can use it; optional for P1, noted in the stack README if not done.
- Delete (after the relay is live): `apps/suites/vitruvian-relay/spike/`, `gitops/argocd/applications/relay-spike.yaml`, `gitops/argocd/platform/relay-spike/`, the spike hub in `MODULE.bazel`, and the slack-mcp visibility exception for the spike.

- [ ] **Step 1:** Render check: `bazel run //tools/gitops:helm -- template t apps/suites/vitruvian-relay/relay/deploy/chart -f gitops/argocd/platform/relay/values.yaml` → Deployment with the affinity, PVC, env from values.
- [ ] **Step 2:** Merge; confirm with `bazel run //tools/gitops:get -- pods -n relay -o wide` that the pod is Running on `fedora`, `nuc9i5` or `nuc9i9`, and that `https://relay.ipv1337.dev/.well-known/oauth-protected-resource` serves PRM.
- [ ] **Step 3:** If Login V2 was set: preview then apply `zitadel-apps-relay-apply.yaml` (`bazel run //tools/agent-app -- workflow-run zitadel-apps-relay-apply.yaml -f action=preview`, read it, then `-f action=up`). Expect only in-place updates.
- [ ] **Step 4:** Retire the spike in a separate PR once Task 11 passes.
- [ ] **Step 5: Commit** `feat(relay): deploy the relay to the homelab`.

### Task 11: Done-when — Claude on the phone runs a command on the Mac

Manual, with James.

- [ ] **Step 1:** `bazel run //apps/suites/vitruvian-relay/connector:install`, then `vrelay login` (one sign-in if Login V2 landed). It prints the MCP URL.
- [ ] **Step 2:** James adds that URL in Claude (web) as a custom connector with the `relay-claude` client id and signs in.
- [ ] **Step 3:** From the **Claude phone app**: "list the files in my Downloads folder" runs without a prompt (a read). Relay log shows `tools/call` from client `398912442404439866`, no arguments.
- [ ] **Step 4:** From the phone: "run `uname -a`". The "Allow?" dialog appears on the Mac; Allow → the output comes back to the phone. Repeat and Deny → Claude shows "Denied on the computer."
- [ ] **Step 5:** Turn the Mac's Wi-Fi off mid-command: the phone gets "Your computer disconnected; try again." quickly. Wi-Fi on: `vrelay status` shows connected within about a minute.
- [ ] **Step 6:** Record the result in this plan (yes or no, with log lines), set `status: completed`, and update spec §10's P1 row.
