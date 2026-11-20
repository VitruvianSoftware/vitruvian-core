---
status: planned
date: 2026-11-20
---

# Relay P2: multi-user Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second invited person signs in, connects their own computer and
runs a command on it from Claude, and the tenant-isolation test in CI fails
when the ownership check is deliberately broken.

**Architecture:** Four parts, shipped as separate PRs in this order.

- **A. Reliability** changes both ends and moves the protocol to version 2:
  - A receipt handshake: no call starts until the relay confirms it is still waiting.
  - Results survive a dropped link of up to 10 s.
  - An approval dialog can outlive Claude's 15 s client timeout. The relay answers "waiting for approval" with a request id, and Claude collects the result through a relay tool, `check_request`; a retry of the same request rejoins the open dialog.
  - The Mac stays awake while the connector runs.
  - Secrets move to the Keychain, and file tools get folder limits.
- **B. Multi-user** moves the relay onto Postgres (CNPG).
  - Several devices per person, invite-only access through a Zitadel customer organisation and project grant, a per-person activity log, and rate limits.
  - A server-rendered dashboard, a CI isolation test with a canary that must fail.
  - The move to `relay.vitruviansoftware.dev`.
- **C. Local** adds a small menu bar app, the "local settings screen". It drives the connector only through new `vrelay settings` and `vrelay log` commands.
- **D. Done-when** covers the live checks with James: Gemini and ChatGPT, then the second user.

**Tech Stack:**
- Rust 1.98.1 (rules_rust 0.68.1, the `@vitruvian_relay_crates` hub).
- hyper 1, tokio, tokio-tungstenite 0.24.
- `tokio-postgres` 0.7, `deadpool-postgres` 0.14 and `tokio-postgres-rustls` 0.13.
- `security-framework` 3, `toml_edit` 0.22.
- CNPG and rules_itest (`//tools/testinfra` hermetic Postgres).
- SwiftUI `MenuBarExtra` (macOS 14+).
- Zitadel (`zitadel-apps-relay` stack, `pulumi-zitadel` v0.2.0).

**Spec:** [`docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md`](../specs/2026-11-07-vitruvian-relay-design.md).
It covers §4 protocol and drops, §5 dashboard, §6 identity, §7 security, §8
domains, the §10 P2 row, and §11 questions 7, 11, 12, 14, 15 and 17.

P1 evidence and findings are in [`2026-11-15-relay-p1-single-user-alpha.md`](2026-11-15-relay-p1-single-user-alpha.md),
Task 11. How Desktop Commander handles the same problems was read from its 0.3.1
package on 2026-11-18. That reading informs Part A; nothing is copied.

## Global Constraints

- **Scope (§10 P2):** sign-up, several devices, dashboard, local settings
  screen, both activity logs, and the isolation test in CI. P1's findings are
  also in scope.
- **Not in P2:**
  - Billing and entitlements (P3, so the device limit below is a flat cap).
  - Downloadable signed installers. Invitees install with the Bazel installer, as in P1.
  - Linux and Windows connectors, Cua Driver, bridging other stdio servers, the move to GCP, production Zitadel hosting.
  - A Gemini client per customer (§11 question 11).
  - A notification per call on the Mac (§7.3 says "can post"; the menu bar app's activity window covers seeing what ran).
  - Per-device rate limits beyond the connector's existing caps (16 calls in flight, one dialog at a time); P2 adds the per-person limit (Task 9).
  - ChatGPT dynamic client registration (§11 question 8). Part D only records whether ChatGPT's free tier can add a connector at all.
- **Protocol v2 replaces v1 outright.** The relay rejects `protocol: 1`
  with `reject{reason: "Update vrelay: this relay needs protocol 2."}`. One
  user runs v1 today, and Task 6 updates them.
- **Exact values:**

  | Constant | Value |
  |---|---|
  | `PROTOCOL` | 2 |
  | `ACK_SECS` | 5 |
  | `APPROVAL_REPLY_SECS` | 10 |
  | `REJOIN_WINDOW_SECS` | 120 |
  | `PARKED_RESULT_SECS` | 300 |
  | `RECONNECT_GRACE_SECS` | 10 |
  | `MAX_DEVICES_PER_USER` | 5 |
  | `CALLS_PER_MINUTE_PER_USER` | 60 |
  | `RATE_BURST` | 20 |
  | `ACTIVITY_RETENTION_DAYS` | 30 |
  | `ACTIVITY_PAGE` | 200 |
  | `DASHBOARD_SESSION_HOURS` | 12 |
  | `DEVICE_NAME_MAX` | 64 |

  P1's values stay: 20 s pings, 2 s in-call pings, 3 misses, the 90 s call
  budget, the 60 s dialog, the 4 MiB frame and the 600 s seen-id window.
- **Relay host:** `relay.vitruviansoftware.dev`.
  - It is the final production name (§8). Subdomains deeper than one label are avoided because Cloudflare's universal certificate covers only one level.
  - Dashboard callback: `https://relay.vitruviansoftware.dev/auth/callback`.
  - `relay.ipv1337.dev` is removed in Task 13, in the same change that moves the relay.
  - Sign-in stays on `auth.ipv1337.dev` (§11 question 2 is a launch decision).
- **Access is invite-only.** Being able to sign in to the relay means holding
  the `relay-user` role through a user grant.
  - Grants are listed in the stack config (`inviteUserIds`). They are applied by CI, never by hand.
  - `ALLOWED_SUBJECTS` goes away. The relay checks the role claim, and it still authorises on client id and subject, never on audience alone (§6).
- **One ownership check.** Every route that names a device or a request goes
  through `App::owned_device(subject, device_id)` or
  `Mcp::owned_request(subject, request_id)`.
  - Someone else's device or request gets exactly the same answer as one that does not exist: same status, body and headers (§7.4).
- **The relay keeps no content (§7.2).** Arguments and results exist only in
  memory, including parked results (at most `PARKED_RESULT_SECS`). Postgres
  holds devices, sessions' absence and activity rows (tool, sizes, duration,
  outcome) only. Duplicate detection keys are SHA-256 hashes, kept in memory.
- **The computer has the last word (§7.1).** Folder limits, pause, keep-awake
  and ask-first live in `rules.toml` on the Mac. Only the connector writes
  that file: `vrelay settings` and `vrelay pause` use `toml_edit`, which keeps
  comments. No frame and no dashboard action changes it.
- **Secrets on the Mac** live in the Keychain: service `dev.vitruvian.vrelay`,
  accounts `tokens` and `device_key`.
  - The files `token.json` and `device.key` are migrated, then deleted.
  - A `FileSecrets` store remains for tests and for `VRELAY_SECRETS=file`.
- **Repo rules (as in P1):**
  - Every git, gh, cluster and Pulumi operation goes through the Bazel targets in `AGENTS.md`.
  - Commits use `bazel run //tools/git:commit -- --agent <you>`.
  - Re-lock with `bazel run //tools/crates:lock -- --dir apps/suites/vitruvian-relay`.
  - License headers on every new file.
  - Each new package declares a `pipeline_unit`, and `presubmit.yaml` is regenerated.
  - Cloud stacks apply only through CI (`zitadel-apps-relay-apply.yaml`, which wren may start).
- **Writing (house style):** every message a person sees is plain English and
  names what to do next.

## Review Focus

1. **The Mac sleeps with a call parked.** When it wakes an hour later,
   nothing from that call may run. The call's deadline has passed, so the
   connector drops it on `start` and `check_request` says it expired. Test in
   Task 3: `call_past_its_deadline_never_runs_after_reconnect`.
2. **Someone runs the same command twice on purpose** after the first one
   finished and its result reached them. It must run again, with a new dialog,
   and must not get the old result. Test in Task 4:
   `delivered_call_is_never_reused`.
3. **A device is revoked while connected and mid-call.** The link closes, the
   call fails with "This computer was removed from your account.", and the
   next connect is refused. Test in Task 8: `revoke_closes_live_link`.
4. **Postgres is down or restarting** (CNPG switchover). Calls and sign-ins
   fail at once with "The relay is having trouble right now; try again in a
   minute." The relay does not hang or crash, and it recovers by itself.
   Test in Task 7: `database_down_fails_clearly_then_recovers`.
5. **Two people both name their computer "MacBook Pro".** Names are per
   person and need not be unique. Revoking one never touches the other. Test
   in Task 12: `same_names_stay_separate`.

---

## File Structure

```
apps/suites/vitruvian-relay/
  protocol/src/lib.rs            v2 frames: Ack, Pending, Start, ResultAck; new constants
  relay/src/
    registry.rs                  ack wait, reconnect grace, results from a new connection
    mcp.rs                       parking, check_request, rejoin keys, rate limit, activity rows
    parked.rs        (new)       ParkedCalls: request ids, rejoin index, expiry
    store.rs         (new)       Store trait (devices + activity), PgStore, MemStore (tests)
    migrations/0001_init.sql (new)
    dashboard/       (new)       mod.rs (routes), session.rs (cookie, CSRF, PKCE), pages.rs, relay.css
    devices.rs                   DeviceRecord grows fields; FileDeviceStore removed in Task 7
    http.rs, config.rs, main.rs  routing, owned_device, new env vars
  relay/tests/isolation.rs (new) two-person isolation test, also built as the canary
  relay/tests/expect_failure.sh (new)
  connector/src/
    link.rs                      ack/start, hold results across drops, pending frame, reattach dialogs
    secrets.rs       (new)       SecretStore trait, KeychainSecrets, FileSecrets, migration
    awake.rs         (new)       caffeinate child tied to `vrelay run`
    rules.rs                     allowed_folders, keep_awake; toml_edit writer
    settings.rs      (new)       `vrelay settings get|set`, `vrelay log`
  macmenu/           (new)       SwiftUI menu bar app "Vitruvian Relay" (model: apps/mobile/vitruvian-remote/macmenu)
gitops/argocd/platform/relay/    values.yaml, cnpg-cluster.yaml, cnpg-objectstore.yaml, cnpg-scheduledbackup.yaml (new)
gitops/argocd/projects/relay-project.yaml   whitelist CNPG kinds, Secret, SealedSecret
gitops/argocd/platform/sealed-secrets-manifests/relay-db-backup-s3.sealedsecret.yaml (new)
infrastructure/pulumi/platform/zitadel-apps-relay/   customer org, project grant, role assertion, dashboard app, invites
```

---

## Part A: Reliability (protocol v2)

### Task 1: Protocol v2 frames

**Files:**
- Modify: `apps/suites/vitruvian-relay/protocol/src/lib.rs`
- Test: the same file's `#[cfg(test)]` module

**Interfaces:**
- Produces:
  - `PROTOCOL: u32 = 2`, `ACK_SECS: u64 = 5`, `APPROVAL_REPLY_SECS: u64 = 10`, `RECONNECT_GRACE_SECS: u64 = 10`.
  - `ToRelay::Ack{call_id}`: received, not started.
  - `ToRelay::Pending{call_id}`: a dialog is open.
  - `ToConnector::Start{call_id}`: you may start.
  - `ToConnector::ResultAck{call_id}`: I have it, forget it.
  - `hello_message` keeps its format, with prefix `vrelay-hello-v2`.

- [ ] **Step 1: Write the failing tests.**
  - `v2_frames_round_trip`: each new variant encodes to `{"type":"ack","call_id":"c1"}` (and `pending`, `start`, `result_ack`) and decodes back.
  - `hello_message_names_v2`: it starts with `vrelay-hello-v2\n`.
  - `protocol_constants_are_pinned`: asserts every value in Global Constraints.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/protocol:unit_tests` → FAIL (unknown variants).
- [ ] **Step 3:** Add the variants and constants. Bump `PROTOCOL`.
- [ ] **Step 4:** The same command → PASS.
- [ ] **Step 5:** Commit `feat(relay): protocol v2 frames for receipts and approvals`.

### Task 2: Receipt handshake

The handshake fixes §11 question 15 (R14): a call frame held up in the
network must never start after the relay has given up.

**Files:**
- Modify: `relay/src/registry.rs` (`call`, `complete`), `relay/src/http.rs` (`run_connection` frame loop, `check_hello` version check), `connector/src/link.rs` (`Shared::on_call`, `session`).
- Test: `relay/src/http_tests.rs`, `connector/src/link_tests.rs`, `relay/tests/e2e.rs`.

**Interfaces:**
- Consumes: Task 1's frames.
- Produces:
  - `CallError::NotReceived` with `user_message()` = "Your computer didn't answer in time; try again."
  - Outcome string `not_received`.
  - Relay behaviour: after sending `Call`, it waits up to `ACK_SECS` for `Ack`. It then sends `Start` if the call is still waiting, otherwise `Cancel`.
  - Connector behaviour: `on_call` sends `Ack` at once. It runs the existing checks, but opens no dialog and runs nothing until `Start` arrives. A `Cancel` before `Start` logs `cancelled before running`.

- [ ] **Step 1: Write the failing tests.**
  - Relay, `call_without_ack_fails_not_received`: `FakeDevice` never acks; after 5 s (test timing 200 ms) the AI gets the message above and the device gets `Cancel`.
  - Relay, `v1_hello_is_rejected_with_update_message`.
  - Connector, `nothing_runs_before_start`: `FakeConn::call` without `start`; `FakeTools.calls` stays empty and `FakeAsker.opened` stays 0 for 1 s; then `start` → it runs once.
  - Connector, `cancel_before_start_never_runs`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/...` → the new tests FAIL.
- [ ] **Step 3:** Implement. Add `ack_timeout` and `call_margin` to the relay's `Timing` (defaults `ACK_SECS`, unchanged). Add `start` to the `fast()` test helpers. Update `FakeConn::call` to send `start` when the test asks for it, so existing tests opt in.
- [ ] **Step 4:** All relay tests → PASS, including the e2e suite.
- [ ] **Step 5:** Commit `feat(relay): no call starts until the relay confirms it is still waiting`.

### Task 3: Results survive a dropped link

Spike C showed most drops are network resets that recover in about 1 s. A
command that already ran must not lose its result to one of them, and must
never run twice.

**Files:**
- Modify: `relay/src/registry.rs` (`drop_connection`, `complete`), `connector/src/link.rs` (`stop_prompts`, the `Done` store, session start).
- Test: `relay/src/http_tests.rs`, `connector/src/link_tests.rs`, `relay/tests/e2e.rs`.

**Interfaces:**
- Produces, on the relay:
  - When a device's link drops, its pending calls are held for `RECONNECT_GRACE_SECS` before failing `Disconnected`.
  - `complete(device_id, result)` accepts a result from any current connection of the same device, not only the one that sent the call.
  - The relay sends `ResultAck` for every result it accepts.
- Produces, on the connector:
  - A finished result stays in `Calls` until it is acked, as long as the call is within its deadline.
  - After `Welcome`, every unacked result is sent again.
  - A dialog open when the link drops stays open for up to `RECONNECT_GRACE_SECS`. If the link is back by then, the answer is used. If not, the dialog closes and logs `link dropped at prompt`.
  - A command still running when the link drops keeps running, and its result is held as above.

- [ ] **Step 1: Write the failing tests.**
  - E2e, `result_after_a_one_second_drop_reaches_the_ai`: drop the socket mid-call, reconnect within 1 s, and the AI gets the real result.
  - E2e, `drop_longer_than_grace_fails_disconnected`.
  - Connector, `unacked_result_is_resent_after_welcome`.
  - Connector, `acked_result_is_not_resent`.
  - Connector, `dialog_survives_a_short_drop`.
  - Review Focus 1, `call_past_its_deadline_never_runs_after_reconnect`: the link drops before `Start`, the clock passes the deadline, the link returns with `Start`, and the call is refused with `TIMED_OUT` and never run.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/...` → the new tests FAIL.
- [ ] **Step 3:** Implement. Change `Phase::Done` to carry `acked: bool`; eviction prefers acked results.
- [ ] **Step 4:** All relay tests → PASS.
- [ ] **Step 5:** Commit `feat(relay): keep results and dialogs across short drops`.

### Task 4: Approvals that outlive the AI app's timeout

This replaces P1's dead end. Claude gives up on a call after 15 s and retries
it, which cancelled the dialog.

Desktop Commander's pattern is to answer within the client's limit and let the
AI ask again (`start_process` then `read_process_output`). Here that becomes a
reply naming a request id, plus a relay tool to fetch the result. Claude's
automatic retry of the same request also rejoins the open dialog instead of
starting a second one. This is also the duplicate detection §11 question 14
asks for.

**Files:**
- Create: `relay/src/parked.rs`.
- Modify: `relay/src/mcp.rs` (`call`, `handle` for `tools/list`, the cancel paths), `relay/src/registry.rs` (`PendingGuard` no longer cancels on an HTTP drop), `connector/src/link.rs` (send `Pending` when a dialog opens).
- Test: `relay/src/http_tests.rs`, `relay/tests/e2e.rs`, `connector/src/link_tests.rs`.

**Interfaces:**
- Consumes: `ToRelay::Pending` (Task 1).
- Produces:
  - `ParkedCalls` in `parked.rs`:
    ```rust
    pub struct RejoinKey([u8; 32]); // sha256(subject \0 device_id \0 tool \0 canonical_json(arguments))
    impl ParkedCalls {
        pub fn park(&self, key: RejoinKey, subject: &str, device_id: &str, call: CallHandle) -> RequestId;
        pub fn rejoin(&self, key: &RejoinKey) -> Option<CallHandle>;          // unfinished or undelivered, within REJOIN_WINDOW_SECS
        pub fn take(&self, subject: &str, id: &RequestId, wait: Duration) -> Fetch; // Fetch::{Done(result), Waiting, Unknown}
        pub fn mark_delivered(&self, key: &RejoinKey);                          // a delivered call is never rejoined
    }
    ```
  - `RequestId` is `"r_"` plus 16 lowercase hex characters, from the existing `random_id()` source. `canonical_json` sorts object keys recursively.
  - Results are kept at most `PARKED_RESULT_SECS` after finishing, then dropped.
  - The relay tool `check_request` is appended to every device's `tools/list`:
    - Input `{"request_id": string}`, description "Get the result of a request that was waiting for approval on the computer."
    - If the device advertises a tool with the same name, the device's tool is dropped and the drop is logged.
  - The waiting reply is a normal (non-error) text result:
    > Waiting for you to allow this on "{device name}". Call check_request with request_id "{id}" to get the result. The request is cancelled if nobody answers within 60 seconds.

    `{device name}` comes from Task 8. Until then it is the device id.
  - `check_request` waits up to `APPROVAL_REPLY_SECS`. It then returns the result, the same waiting text, or (for an unknown, expired or someone else's id) "That request has finished or expired. Send the original request again."
  - Rules:
    - A `tools/call` that the connector has marked `Pending` and that is still unanswered at `APPROVAL_REPLY_SECS` is parked and gets the waiting reply.
    - A `tools/call` whose `RejoinKey` matches an unfinished or undelivered call attaches to it, never starting a new one.
    - An HTTP request dropped by the client parks its call instead of cancelling it.
    - `notifications/cancelled` still cancels.
    - Outcome strings: `waiting_approval` (on the parked reply) and `rejoined`.
    - `check_request` calls are logged as tool `check_request`.

- [ ] **Step 1: Write the failing tests.**
  - `slow_approval_returns_waiting_then_result`: the fake device sends `Pending` and answers after 12 s (test timing scaled). The first reply is the waiting text with an id, and `check_request` returns the real result.
  - `retry_rejoins_the_open_dialog`: a second identical `tools/call` while the first waits; the device sees exactly one `Call`.
  - `client_timeout_parks_instead_of_cancelling`: drop the HTTP connection; the device gets no `Cancel`; a retry gets the result.
  - Review Focus 2, `delivered_call_is_never_reused`: the first identical call completes and is delivered; the second identical call reaches the device as a new `Call`.
  - `other_persons_request_id_is_unknown`: Bob's `check_request` with Alice's id gets the unknown text, byte-for-byte the same as a made-up id.
  - `cancelled_notification_still_cancels`.
  - `parked_result_is_dropped_after_300s` (test clock).
  - Connector, `pending_sent_when_dialog_opens`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/...` → the new tests FAIL.
- [ ] **Step 3:** Implement `parked.rs` and wire it into `Mcp::call`. Modern-era (sessionless) requests use the same `RejoinKey` path, which closes the P1 gap where they had no duplicate check.
- [ ] **Step 4:** All relay tests → PASS, including `logs_never_contain_arguments_outputs_or_tokens` extended to `check_request`.
- [ ] **Step 5:** Commit `feat(relay): approvals can take longer than the AI app waits`.

### Task 5: Keep the Mac awake, Keychain secrets, folder limits

**Files:**
- Create: `connector/src/awake.rs`, `connector/src/secrets.rs`.
- Modify: `connector/src/rules.rs` (`Rules` gains `keep_awake: bool` (default `true`) and `allowed_folders: Vec<String>` (default `["~"]`); `DEFAULT_RULES` and `PREVIOUS_DEFAULTS` updated so untouched P1 files upgrade), `connector/src/state.rs`, `auth.rs`, `keys.rs` (read and write secrets through `SecretStore`), `connector/src/main.rs` (`cmd_run` starts `Awake`), `connector/Cargo.toml` (`security-framework = "3"` under `cfg(target_os = "macos")`).
- Test: `connector/src/link_tests.rs`, `rules.rs` and `secrets.rs` tests.

**Interfaces:**
- Produces:
  - `awake.rs`:
    - `pub struct Awake` spawns `/usr/bin/caffeinate -is -w <vrelay pid>` while `rules.keep_awake` is true. It is restarted on `reload()` when the setting flips, and killed on drop.
    - `status.json` gains `"keep_awake": bool`.
    - `vrelay status` prints `Keeping this Mac awake: yes|no`.
  - `secrets.rs`:
    ```rust
    pub trait SecretStore: Send + Sync {
        fn get(&self, account: &str) -> Result<Option<Vec<u8>>, SecretError>;
        fn set(&self, account: &str, value: &[u8]) -> Result<(), SecretError>;
        fn delete(&self, account: &str) -> Result<(), SecretError>;
    }
    pub struct KeychainSecrets; // service "dev.vitruvian.vrelay"
    pub struct FileSecrets { dir: PathBuf } // the P1 file layout, mode 0600
    pub fn migrate_files_to(store: &dyn SecretStore, dir: &Path) -> Result<Migrated, SecretError>;
    pub fn from_env() -> Box<dyn SecretStore>; // VRELAY_SECRETS=file selects FileSecrets
    ```
  - Folder limits in `Rules::decide`: a `PATH_ARGS` value (or `start_search` root) that resolves outside every `allowed_folders` entry gives `Refuse("outside your allowed folders; change them in Vitruvian Relay's settings")`. It is checked after the guard and before `no_prompt`. Terminal commands are not path-checked (§7.1 says so plainly).

- [ ] **Step 1: Write the failing tests.**
  - `keep_awake_starts_caffeinate_and_stops_it`: `Awake` with a fake binary path writes its argv; flipping the setting and reloading kills it.
  - `file_tool_outside_allowed_folders_is_refused`: `/etc/hosts` with `allowed_folders = ["~"]`.
  - `symlink_out_of_allowed_folder_is_refused`.
  - `p1_rules_file_upgrades_with_new_defaults`.
  - `migrate_moves_token_and_key_then_deletes_files` (with `FileSecrets` as the target, in a temp dir).
  - `keychain_round_trip`: `KeychainSecrets` with a test service name. Tag it `manual`, since it runs on macOS only; Step 4 runs it by hand.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector:unit_tests` → FAIL.
- [ ] **Step 3:** Implement. Sign-in and logout write through `SecretStore`. Logout deletes both accounts.
- [ ] **Step 4:** `bazel test //apps/suites/vitruvian-relay/connector/...` → PASS. Then `bazel test //apps/suites/vitruvian-relay/connector:keychain_test` on the Mac → PASS.
- [ ] **Step 5:** Commit `feat(vrelay): keep the Mac awake, keep secrets in the Keychain, limit file tools to chosen folders`.

### Task 6: Ship Part A to James

**Files:**
- Modify: `gitops/argocd/platform/relay/values.yaml` (image digest after the image workflow runs).

- [ ] **Step 1:** Open the Part A PR (Tasks 1–5) with `pr-create`. Land it, then pin the new image digest in a second PR, as in P1.
- [ ] **Step 2:** Reinstall the connector on James's Mac: `bazel run //apps/suites/vitruvian-relay/connector/scripts:install`. Confirm `vrelay status` shows connected, `Keeping this Mac awake: yes`, and Keychain items `dev.vitruvian.vrelay` / `tokens` and `device_key`. Also confirm `token.json` and `device.key` are gone.
- [ ] **Step 3:** From the Claude phone app, ask for `uname -a`, wait 30 s, then click Allow.
  - Expected: Claude shows the waiting text, fetches the result with `check_request`, and shows the output.
  - Relay log: a `waiting_approval` line, then `check_request` `ok`.
- [ ] **Step 4:** Mid-command, unplug Ethernet for 3 s, then plug it back in. Expected: the result arrives (`ok`, not `disconnected`).
- [ ] **Step 5:** Record both results under this task.

---

## Part B: Multi-user

### Task 7: Postgres

**Files:**
- Create:
  - `relay/src/store.rs` and `relay/migrations/0001_init.sql`.
  - `gitops/argocd/platform/relay/cnpg-cluster.yaml`, `cnpg-objectstore.yaml` and `cnpg-scheduledbackup.yaml`, copied from `gitops/argocd/platform/umami/` with names `relay-db`, database and owner `relay`, and the bucket `relay-db-backup`.
  - `gitops/argocd/platform/sealed-secrets-manifests/relay-db-backup-s3.sealedsecret.yaml`, sealed with `bazel run //tools/gitops:kubeseal`.
- Modify:
  - The MinIO bucket and user in `gitops/argocd/platform/minio-amd64/applicationset.yaml`, as umami's.
  - `gitops/argocd/projects/relay-project.yaml`: whitelist CNPG `Cluster`, `ObjectStore` and `ScheduledBackup`, plus `Secret` and `SealedSecret`, as `buzz-project.yaml:75-82` does.
  - The relay chart: `DATABASE_URL` from the CNPG-generated `relay-db-app` secret (key `uri`), the CA from `relay-db-ca`, and a CiliumNetworkPolicy egress rule to `relay-db-rw:5432`.
  - `relay/src/config.rs` (`DATABASE_URL` required, `DATA_DIR` removed), `relay/src/main.rs`, `relay/Cargo.toml`.
  - `relay/BUILD`: an `itest_service` named `postgres`, copied from `apps/suites/vitruvian-tabs/api/BUILD:196-221`, and `service_test` targets for the Postgres tests.
- Delete: `FileDeviceStore`. The PVC stays mounted until Task 13 so the one-time import below can read `/data/devices.json`.

**Interfaces:**
- Produces:
  ```rust
  #[async_trait] pub trait Store: Send + Sync {
      async fn device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError>;
      async fn devices_of(&self, owner_sub: &str) -> Result<Vec<DeviceRecord>, StoreError>;
      async fn insert_device(&self, d: &NewDevice) -> Result<DeviceRecord, StoreError>; // StoreError::TooManyDevices at MAX_DEVICES_PER_USER
      async fn replace_key(&self, id: &str, owner_sub: &str, key: [u8; 32]) -> Result<bool, StoreError>;
      async fn rename(&self, id: &str, owner_sub: &str, name: &str) -> Result<bool, StoreError>;
      async fn revoke(&self, id: &str, owner_sub: &str) -> Result<bool, StoreError>;
      async fn touch_seen(&self, id: &str, at: SystemTime) -> Result<(), StoreError>;
      async fn record_activity(&self, row: &ActivityRow) -> Result<(), StoreError>;
      async fn activity_of(&self, owner_sub: &str, device: Option<&str>, limit: u32) -> Result<Vec<ActivityRow>, StoreError>;
      async fn purge_activity_before(&self, t: SystemTime) -> Result<u64, StoreError>;
  }
  pub struct PgStore; pub struct MemStore; // MemStore for unit tests only
  ```
  - `DeviceRecord` gains `name: String`, `created_at`, `last_seen: Option<SystemTime>` and `revoked: bool`. A revoked device is never returned by `device()`.
  - Schema (`0001_init.sql`):
    - `devices(id text pk, owner_sub text not null, name text not null, public_key bytea not null, created_at timestamptz, last_seen timestamptz, revoked_at timestamptz)`, index on `(owner_sub)`.
    - `activity(id bigserial pk, at timestamptz not null, owner_sub text not null, device_id text not null, client_id text not null, tool text not null, arg_bytes int, result_bytes int, duration_ms int, outcome text not null)`, index on `(owner_sub, at desc)`.
    - `schema_version(version int)`.
  - Migrations run at start, in one transaction, under `pg_advisory_lock(7313)`.
  - `StoreError::Unavailable` maps to the user message "The relay is having trouble right now; try again in a minute." and outcome `store_unavailable`.

- [ ] **Step 1: Write the failing tests.**
  - `store_contract` is one test body run against `MemStore` (a unit test) and `PgStore` (a `service_test`). It covers insert, get, `devices_of`, rename, revoke (revoked is invisible), `replace_key` by the wrong owner (false), activity order and limit, purge, and the sixth device erroring.
  - Review Focus 4, `database_down_fails_clearly_then_recovers`: stop the itest Postgres. `tools/call` and `/devices` give the message above within 5 s. Start it again; the next call works.
  - `migrations_are_idempotent`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay/...` → FAIL.
- [ ] **Step 3:** Implement `PgStore` with `deadpool-postgres` (pool size 8, 5 s connect and query timeout), with TLS verified against the CNPG CA. Switch `App` from `Arc<dyn DeviceStore>` to `Arc<dyn Store>`. The one-time import of `devices.json` (James's device) runs at start if the file exists and the table is empty; remove it in Task 13.
- [ ] **Step 4:** All relay tests → PASS. Render the chart: `bazel run //tools/gitops:helm -- template t apps/suites/vitruvian-relay/relay/deploy/chart -f gitops/argocd/platform/relay/values.yaml` shows the DB env, the netpol rule and no PVC.
- [ ] **Step 5:** Commit `feat(relay): keep devices and activity in Postgres`.

### Task 8: Several devices per person, and the role check

**Files:**
- Modify:
  - `packages/rust/vitruvian-mcp-auth/src/verifier.rs`: `VerifierConfig` gains `required_role: Option<String>`. An empty `allowed_subjects` is allowed only when `required_role` is set. The slack-mcp's behaviour is unchanged and its tests must still pass.
  - `relay/src/http.rs` (`register_device`, `check_hello`, `owned_device`), `relay/src/config.rs`: `ALLOWED_SUBJECTS` removed, `REQUIRED_ROLE` (default `relay-user`) added.
  - `connector/src/auth.rs` (`register_device` sends `device_id` when it has one and `name`), `connector/src/main.rs`: `vrelay login --name <name>`, defaulting to `scutil --get ComputerName`.
- Test: `verifier.rs` tests, `relay/src/http_tests.rs`, `relay/tests/e2e.rs`. `mint` takes `sub`, and `start_relay` drops `ALLOWED_SUBJECTS`.

**Interfaces:**
- Produces:
  - The role claim checked is `urn:zitadel:iam:org:project:{project_id}:roles`, an object whose keys include `required_role`. A missing or wrong role gives `VerifyError::RoleMissing`, which is logged as `auth_refused` code `role_missing`.
  - `POST /devices` takes `{public_key, name, device_id?}`:
    - With a `device_id` the caller owns, it replaces that key and kicks the old link.
    - Without one, it creates a new device.
    - At the limit it returns 409 with `{"error":"You already have 5 computers connected. Remove one in the dashboard first."}`.
    - A name is trimmed, 1–`DEVICE_NAME_MAX` characters, with control characters removed.
  - `App::owned_device(&self, subject: &str, device_id: &str) -> Result<Option<DeviceRecord>, StoreError>` is the only ownership check.
  - `App::revoke(subject, device_id)` revokes the device in the store, kicks its link, and fails its in-flight calls with `CallError::Revoked`: "This computer was removed from your account."

- [ ] **Step 1: Write the failing tests.**
  - `token_without_role_is_refused`.
  - `slack_mcp_config_still_needs_subjects`.
  - `second_device_gets_its_own_id_and_url`.
  - `relogin_with_device_id_keeps_the_id`.
  - `sixth_device_is_refused`.
  - `name_is_trimmed_and_capped`.
  - Review Focus 3, `revoke_closes_live_link`.
- [ ] **Step 2:** `bazel test //packages/rust/vitruvian-mcp-auth/... //apps/suites/vitruvian-relay/...` → FAIL.
- [ ] **Step 3:** Implement. Replace every `owner_sub == caller.subject` comparison in `http.rs` (`:468`, `:745`, `:1040`) with `owned_device`.
- [ ] **Step 4:** The same command → PASS. Also `bazel test //apps/mcp/vitruvian-slack-mcp/...` → PASS.
- [ ] **Step 5:** Commit `feat(relay): several computers per person, access by role`.

### Task 9: Activity log, offline wording, rate limit

**Files:**
- Modify: `relay/src/mcp.rs` (the `call` log drop guard also writes an `ActivityRow`, with `owner_sub` from the caller), `relay/src/http.rs` (`touch_seen` on connect, on disconnect and every 5 minutes while connected), `relay/src/main.rs` (an hourly purge task), and a new `relay/src/ratelimit.rs`.
- Test: `relay/src/http_tests.rs`.

**Interfaces:**
- Produces:
  - `ActivityRow{at, owner_sub, device_id, client_id, tool, arg_bytes, result_bytes, duration_ms, outcome}`. It is written for every `tools/call`, including refusals.
  - A failed write is logged (`activity_write_failed`) and never fails the call.
  - The offline message becomes:
    > Your computer "{name}" is offline (last seen {ago}). It may be asleep, shut down or off the network.

    `{ago}` is "just now", "N minutes ago", "N hours ago", "N days ago" or "never".
  - `RateLimit::check(subject) -> Result<(), Retry>` is a token bucket of `CALLS_PER_MINUTE_PER_USER` refilling per minute, with burst `RATE_BURST`, held in memory. When refused the message is "Too many requests from your account; wait a minute and try again." with outcome `rate_limited`.

- [ ] **Step 1: Write the failing tests.**
  - `activity_row_written_without_content`: the arguments and result contain a marker string, and no column contains it.
  - `activity_write_failure_does_not_fail_call`.
  - `offline_message_names_device_and_last_seen`.
  - `twenty_first_burst_call_is_rate_limited`.
  - `purge_removes_rows_older_than_30_days`.
  - `activity_survives_restart`: `PgStore` across two `App` instances.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay/...` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** The same command → PASS.
- [ ] **Step 5:** Commit `feat(relay): activity log, clearer offline message, per-person rate limit`.

### Task 10: Zitadel: customers, invites, dashboard client

**Files:**
- Modify: `infrastructure/pulumi/platform/zitadel-apps-relay/main.go`, `Pulumi.development.yaml`, `README.md`.

**Interfaces:**
- Produces (stack outputs): `customerOrgId`, `dashboardClientId`, `roleClaim` (the claim name the relay checks).
- Behaviour:
  - A new org, "Vitruvian Relay customers" (`zitadel.NewOrg`).
  - A `ProjectGrant` of the `relay` project to that org with role `relay-user`.
  - One `UserGrant` per id in `inviteUserIds`, a CSV of users in the customer org. James's existing `grantUserIds` grant stays.
  - The project sets `ProjectRoleAssertion: true`.
  - A new OIDC app, `relay-dashboard`:
    - web, authorization code with PKCE, `AuthMethodType NONE`, JWT access tokens;
    - redirect `https://relay.vitruviansoftware.dev/auth/callback`;
    - post-logout redirect `https://relay.vitruviansoftware.dev/`.
  - Every app's redirect URIs move to the new host where they name the relay.
  - Gemini's callback is the one Gemini shows for the new server URL (Task 15).

- [ ] **Step 1: Check, and record here:**
  - Does the customer org need a login policy with `allowRegister` for "sign-up"?
  - Does the Zitadel instance have SMTP for email verification? Read `gitops/argocd/platform/zitadel/applicationset.yaml` and the instance settings with `bazel run //tools/agent-app -- read` (Zitadel's console is not a GitOps source; read only).
  - **Ruling if SMTP is missing:** no open self-registration in P2. The invitee is created with `zitadel.NewHumanUser` in the customer org, and James gives them the initial password out of band. Self-registration moves to P3 with SMTP. This keeps "sign-up" honest: an invited person still creates their own password at first sign-in.
- [ ] **Step 2:** Write a Go unit test, `TestDashboardRedirectIsPinned`, against `parseRedirectURIs`. Then preview: `bazel run //tools/agent-app -- workflow-run zitadel-apps-relay-apply.yaml -f action=preview`. Read it: it may create only the org, project grant, user grant and dashboard app, and update the project and the existing apps' redirects, with **no deletes**.
- [ ] **Step 3:** Open the PR. After merge, apply: `workflow-run … -f action=up`. Confirm the outputs with `bazel run //infrastructure/pulumi/platform/zitadel-apps-relay:stack`.
- [ ] **Step 4:** Commit `feat(zitadel-apps-relay): customer org, invites and the dashboard client`.

### Task 11: Dashboard

**Files:**
- Create: `relay/src/dashboard/{mod.rs,session.rs,pages.rs}`, `relay/src/dashboard/relay.css`, served at `/static/relay.css` and embedded with `include_str!`.
- Modify: `relay/src/http.rs` (routing), `relay/src/config.rs` (`DASHBOARD_CLIENT_ID`, required).
- Test: `relay/src/dashboard/tests.rs`.

**Interfaces:**
- Consumes: `Store` (Task 7), `owned_device` and `revoke` (Task 8), the dashboard client (Task 10).
- Produces, as routes, all `Cache-Control: no-store` with CSP `default-src 'self'; frame-ancestors 'none'; form-action 'self'`:
  - `GET /` redirects to `/devices` when signed in, otherwise shows a sign-in page.
  - `GET /auth/login` starts PKCE with S256 (state and verifier in a 10-minute `vr_auth` cookie).
  - `GET /auth/callback` exchanges the code at `{issuer}/oauth/v2/token` and verifies the access token with a third `Verifier` (client id = dashboard, `required_role`).
  - `POST /auth/logout`.
  - `GET /devices` lists name, online, last seen and connector URL.
  - `GET /devices/{id}` shows setup steps for Claude (custom connector URL, client id `relay-claude`) and Gemini, plus Rename and Remove.
  - `POST /devices/{id}/rename` and `POST /devices/{id}/remove`.
  - `GET /activity?device={id}` shows the last `ACTIVITY_PAGE` rows: time (the viewer's local time, rendered as UTC with a `<time>` element), computer, AI app, tool, outcome and duration. It shows no arguments, ever.
- Sessions:
  - In memory, `DASHBOARD_SESSION_HOURS`.
  - Cookie `vr_session`: 32 random bytes, base64url, `HttpOnly; Secure; SameSite=Lax; Path=/`.
  - A restart signs everyone out, which is accepted for P2.
  - Every POST needs the session's CSRF token in a hidden field and an `Origin` equal to `PUBLIC_URL`. Otherwise it gets 403.
- Dashboard tokens are never accepted at `/mcp` or `/connect`, and MCP tokens never at `/auth/*`, because the client-id lists are disjoint (as `CONNECTOR_CLIENT_ID` already is).
- Every page follows `docs/standards/brand.md` (Vitruvian Relay name, no Desktop Commander wording, §9) and works at phone width.

- [ ] **Step 1: Write the failing tests.**
  - `signed_out_pages_redirect_to_sign_in`.
  - `callback_with_bad_state_is_refused`.
  - `post_without_csrf_is_403`.
  - `post_from_other_origin_is_403`.
  - `rename_trims_and_caps`.
  - `remove_kicks_the_link`.
  - `activity_page_shows_no_arguments`.
  - `mcp_token_cannot_open_dashboard`.
  - `dashboard_token_cannot_call_tools`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay/...` → FAIL.
- [ ] **Step 3:** Implement. Escape HTML with one `fn esc(&str) -> String` used by every template. No JavaScript.
- [ ] **Step 4:** Tests → PASS. Then open the pages in the browser against a local relay (`bazel run //apps/suites/vitruvian-relay/relay:relay` with the test issuer) at desktop and phone width, and fix anything that looks wrong before the PR.
- [ ] **Step 5:** Commit `feat(relay): a dashboard for devices and activity`.

### Task 12: Tenant isolation test, and its canary

This is §7.4 and the second half of P2's done-when.

**Files:**
- Create: `relay/tests/isolation.rs`, `relay/tests/expect_failure.sh`.
- Modify: `relay/src/http.rs`. `owned_device` gains `#[cfg(relay_broken_ownership)]`, which makes it return the device whatever the subject. That is the canary's deliberate break and the only place it exists. Also modify `relay/BUILD` (two targets, both in the `pipeline_unit`'s `test_targets`) and `.github/workflows/presubmit.yaml` (regenerated).

**Interfaces:**
- Produces:
  - `vitruvian_relay_isolation_test`, a `service_test` with Postgres, which must pass.
  - `vitruvian_relay_isolation_canary_test`, the same sources built with `rustc_flags = ["--cfg", "relay_broken_ownership"]` and run through `expect_failure.sh`. That script passes only if the inner test exits non-zero **and** its output names at least one `isolation::` test as failed.

- [ ] **Step 1: Write the tests (Alice and Bob, each with two devices).** For every case, Alice's answer about Bob's device or request is byte-identical (status, headers minus `Date`, body) to her answer about an id that does not exist:
  - `mcp_initialize_tools_list_and_call_on_bobs_device`
  - `protected_resource_metadata_for_bobs_device`
  - `hello_with_bobs_device_id`
  - `register_with_bobs_device_id`
  - `dashboard_device_page_rename_remove_for_bobs_device` (Bob's device is unchanged afterwards)
  - `activity_lists_only_own_rows`
  - `check_request_with_bobs_request_id`
  - `rejoin_never_crosses_people`: identical tool and arguments from both people run twice.
  - Review Focus 5, `same_names_stay_separate`.
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/relay:vitruvian_relay_isolation_test` → PASS (Tasks 4, 8 and 11 built the checks). Then `…:vitruvian_relay_isolation_canary_test` → PASS, meaning the broken build fails. Prove the canary is meaningful: temporarily make `expect_failure.sh` run the good build, and see the canary fail. Revert that.
- [ ] **Step 3:** Regenerate the presubmit workflow: `bazel run //tools/pipeline:gen -- --format=workflow --output-file=$PWD/.github/workflows/presubmit.yaml`.
- [ ] **Step 4:** Commit `test(relay): tenant isolation in CI, with a canary that must fail`.

### Task 13: Move to `relay.vitruviansoftware.dev`, and ship Part B

**Files:**
- Modify:
  - Chart `hostname` default and `gitops/argocd/platform/relay/values.yaml`: `hostname: relay.vitruviansoftware.dev`, `oidc.dashboardClientId`, `requiredRole`, no `allowedSubjects`.
  - `connector/src/config.rs`: default `VRELAY_RELAY_URL`, and `defaults_match_relay_stack` updated.
  - Remove the `devices.json` import from Task 7, the `/data` mount and the PVC template (the PVC object is pruned by Argo CD; confirm in the preview of the sync that nothing else is deleted).
  - Fix stale spike references in `apps/suites/vitruvian-relay/Cargo.toml`, `connector/src/auth.rs:24`, `bridge.rs` and `.github/workflows/vitruvian-relay-image.yaml:22`.

- [ ] **Step 1:** Open the Part B PR (Tasks 7–9 and 11–13). Then the digest PR. Confirm:
  - Argo CD shows `relay` and `relay-db` healthy (`bazel run //tools/gitops:status`).
  - `https://relay.vitruviansoftware.dev/.well-known/oauth-protected-resource` serves PRM.
  - `relay.ipv1337.dev` no longer resolves.
- [ ] **Step 2:** On James's Mac, reinstall the connector and run `vrelay login --name "James's MacBook"`. James's device keeps its id (imported, then re-registered with `device_id`).
- [ ] **Step 3:** James removes the old connector in Claude and adds the new URL from the dashboard's device page. From the phone, list Downloads. Expected: it works, and `/activity` shows the row.

---

## Part C: Local settings screen

### Task 14: `vrelay settings`, `vrelay log`, and the menu bar app

**Files:**
- Create:
  - `connector/src/settings.rs`.
  - `apps/suites/vitruvian-relay/macmenu/` (Swift package, `BUILD` with `macos_application` and Developer ID signing as in `apps/mobile/vitruvian-remote/macmenu/BUILD`), with `Sources/RelayMenu/App.swift`, `Sources/RelayMenuCore/{Connector.swift,Settings.swift,ActivityLog.swift}` and `Tests/RelayMenuCoreTests/`.
- Modify: `connector/src/main.rs` (subcommands), `connector/scripts/src/lib.rs`. The installer copies `Vitruvian Relay.app` to `~/Applications` and registers it as a login item, and `uninstall` removes it.

**Interfaces:**
- Produces, as connector CLI commands (the app's only way in):
  - `vrelay settings get --json` prints `{"paused":bool,"keep_awake":bool,"allowed_folders":[string],"tools":[{"name":string,"ask_first":bool,"hidden":bool}]}`.
  - `vrelay settings set keep_awake true|false`.
  - `vrelay settings set allowed_folders.add <path>` and `allowed_folders.remove <path>`. Paths are canonicalised, and the connector's own folders are refused.
  - `vrelay settings set ask_first <tool> true|false`. This edits `no_prompt`. A hidden tool is refused: "That tool is hidden from remote callers and can't be turned on here."
  - Each `set` writes `rules.toml` through `toml_edit` and SIGHUPs the agent (`nudge_agent`).
  - `vrelay log --json [--limit N]` prints the last N (default 200) `calls.log` entries, newest first, merging `calls.log.1`.
- The app (SwiftUI `MenuBarExtra`, name "Vitruvian Relay"):
  - The menu shows status (from `status.json`: connected, offline, paused or signed out, plus the device name), Pause/Resume, "Keep this Mac awake", Settings…, Activity…, Open dashboard and Quit.
  - Settings: Allowed folders (add with `NSOpenPanel`, remove) and "Ask before running" toggles per tool. Hidden tools are shown greyed with the reason.
  - Activity: a table of time, tool and decision. Selecting a row shows its arguments, which stay on this Mac.
  - Every change shells out to the installed `~/.local/share/vrelay/vrelay` and re-reads `settings get`. The app never writes `rules.toml` itself.

- [ ] **Step 1: Write the failing tests.**
  - Rust:
    - `settings_set_keeps_comments`.
    - `settings_refuse_hidden_tool`.
    - `allowed_folder_add_refuses_connector_dirs`.
    - `log_json_merges_rotated_file_newest_first`.
    - `settings_get_json_shape_is_pinned`.
  - Swift: `ConnectorTests.parsesSettingsJSON`, `ActivityLogTests.parsesLogJSON`, `StatusTests.mapsStates` (all on fixtures written by the Rust tests into `testdata/`).
- [ ] **Step 2:** `bazel test //apps/suites/vitruvian-relay/connector/... //apps/suites/vitruvian-relay/macmenu/...` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Tests → PASS. Build and run the app on James's Mac, screenshot each window, and check toggles and folder changes against `vrelay settings get`. Fix anything that looks wrong before the PR.
- [ ] **Step 5:** Commit `feat(vrelay): a menu bar app for settings and the local activity log`. Open the Part C PR.

---

## Part D: Done-when

### Task 15: Gemini and ChatGPT on the new relay

Done with James, driving his desktop through Claude in Chrome on his own
sign-ins. James types any password himself.

- [ ] **Step 1, Gemini:**
  1. Add a custom connector with server URL `https://relay.vitruviansoftware.dev/mcp/d/<James's device id>`.
  2. Copy the callback Gemini shows into `geminiRedirectUris`, then apply (Task 10's workflow).
  3. Paste the client id and secret, sign in, and ask Gemini to list Downloads.
  4. Expected: it works, and the relay log shows the Gemini client id.
- [ ] **Step 2, ChatGPT:** on the free tier, check whether a custom MCP connector can be added at all (settings, then connectors or developer mode).
  - If it can, record what its form asks for. With a fixed client id it may work like Gemini; with only dynamic registration, it is blocked on §11 question 8.
  - Try nothing that needs a paid plan.
- [ ] **Step 3:** Record the results in this task and in spec §6 and §11 (questions 3, 8 and 11).

### Task 16: A second invited person

- [ ] **Step 1:** Invite a second person: a second identity of James's on another computer or another macOS user account, or a team member.
  - Add their user id to `inviteUserIds` and apply.
  - Expected: they can sign in. A person not on the list gets Zitadel's "not authorised", with no relay access.
- [ ] **Step 2:** They install the connector (`…/connector/scripts:install`), run `vrelay login`, add their device URL in Claude, and run `uname -a` from Claude. The dialog appears on **their** computer; they Allow, and the output comes back.
- [ ] **Step 3:** From James's account, confirm that the dashboard and `/activity` show none of their devices or rows, and that their device URL in James's Claude gives the same "not found" as a made-up id.
- [ ] **Step 4:** Ask the second person how it felt to add one connector per computer, and record the answer for §11 question 7 (one URL per device or per account). No change in P2.
- [ ] **Step 5:** Confirm that the CI run on the Part B PR shows `vitruvian_relay_isolation_test` and `vitruvian_relay_isolation_canary_test` both passing (`bazel run //tools/agent-app -- read pr checks <n>`).
- [ ] **Step 6:** Record the results here (yes or no, with log lines) and set `status: completed`. Update the spec:
  - §4: the v2 frames, and the drop rules now built.
  - §10: the P2 row.
  - §11: questions 7, 14, 15 and 17 closed or updated with what P2 did.
