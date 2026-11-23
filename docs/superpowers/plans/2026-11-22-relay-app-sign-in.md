---
status: active
---

# Relay App Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An invited person connects Gemini to their computer by pasting one URL, with no client id, secret or config change.

**Architecture:** A new `oauth` module makes the relay an authorization server for `/mcp/app/<device>` only. Registration is stateless (HMAC); people sign in through one Zitadel public client, approve on a relay consent page, and receive Zitadel's access token plus a sealed refresh token. `/mcp/d/<device>` and Claude are unchanged.

**Tech Stack:** Rust (hyper, `ring` for HMAC and AES-256-GCM, `ureq`), Helm, Pulumi Go (Zitadel), SealedSecrets.

**Spec:** `docs/superpowers/specs/2026-11-22-relay-app-sign-in-design.md`

## Global Constraints

- Paths: `/mcp/app/<device>`, `/.well-known/oauth-protected-resource/mcp/app/<device>`, `/.well-known/oauth-authorization-server`, `/oauth/register`, `/oauth/authorize`, `/oauth/callback`, `/oauth/consent`, `/oauth/token`.
- Registration accepts only redirect URIs on `oauth-redirect`, `oauth-redirect-sandbox`, `oauth-redirect-test` `.googleusercontent.com`, path `/r/` or `/a/` + `user_bound_custom-mcp-<24 lowercase hex>`, all with one shared id.
- `/oauth/authorize` accepts only `https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-<id>`.
- PKCE S256 is required. Codes are one-time and live 60 s.
- Env: `APP_SIGNIN_KEY` (base64, 32 bytes) and `APPS_CLIENT_ID`. Both unset = feature off, every new path 404. One set = startup error.
- `APPS_CLIENT_ID` must be in `MCP_CLIENT_IDS`, and must differ from the connector and dashboard ids.
- Never log tokens, codes, secrets or `state`.
- Someone else's device answers like a missing one. Existing `/mcp/d/` responses do not change.
- All commands go through Bazel. Commit with `bazel run //tools/git:commit -- --agent wren -m "..." <paths>`.

## Review Focus

- A consent link started by another Gemini account: Deny sends no code; a forged or replayed Allow does nothing. (Task 3)
- A code redeemed twice, late, or with the wrong client, verifier, callback or resource fails with `invalid_grant`. (Task 4)
- A refresh token presented by a different registered client fails. (Task 4)
- A person without `relay-user`, or who does not own the device, never reaches consent. (Task 3)
- A flood of `/oauth/register` and `/oauth/authorize` calls stores nothing unbounded. (Tasks 1, 2)

---

### Task 1: Stateless clients and sealing

**Files:** Create `relay/src/oauth/mod.rs`, `relay/src/oauth/clients.rs`, `relay/src/oauth/seal.rs`. Modify `relay/src/lib.rs`, `relay/src/config.rs`, `relay/BUILD`.

**Interfaces:**
- Produces: `struct AppKeys`, `AppKeys::from_b64(&str) -> Result<AppKeys, String>` (derives separate HMAC and AEAD keys with HKDF labels `relay-app-client`, `relay-app-seal`).
- `parse_registration(&[String]) -> Result<String, RegisterError>` returns the shared id.
- `AppKeys::issue_client(&self, id: &str) -> (String, String)` returns `(client_id, client_secret)`; `client_id` is `app.<id>.<b64url hmac>`.
- `AppKeys::client_callback_id(&self, client_id: &str) -> Option<String>`; `AppKeys::secret_ok(&self, client_id: &str, secret: &str) -> bool` (constant time).
- `production_callback(id: &str) -> String`.
- `AppKeys::seal(&self, client_id: &str, plaintext: &[u8]) -> String`; `AppKeys::open(&self, client_id: &str, sealed: &str) -> Option<Vec<u8>>` (client id is AEAD associated data; random nonce).
- `Settings.app_signin: Option<AppSignin { keys, client_id }>`, plus `app_mcp_url(device)`, `app_metadata_url(device)`, `apps_callback_url()`.

- [ ] **Step 1:** Write failing tests: `accepts_geminis_six_measured_uris` (the exact six from the spec), `refuses_other_host`, `refuses_lookalike_host`, `refuses_http`, `refuses_query_or_fragment`, `refuses_mixed_ids`, `refuses_empty`, `refuses_more_than_six`, `forged_client_id_is_refused`, `secret_is_bound_to_client`, `sealed_value_opens_only_for_its_client`, `tampered_seal_is_refused`, `config_needs_both_or_neither`, `apps_client_must_be_an_mcp_client`.
- [ ] **Step 2:** Run `bazel test //apps/suites/vitruvian-relay/relay:all`. Expected: FAIL to compile.
- [ ] **Step 3:** Implement with `ring::hmac`, `ring::hkdf`, `ring::aead::AES_256_GCM`; parse URLs by exact string shape, not a URL library.
- [ ] **Step 4:** Run the same test command. Expected: PASS.
- [ ] **Step 5:** Commit `feat(relay): stateless app clients and token sealing`.

### Task 2: Discovery, registration and the app URL

**Files:** Create `relay/src/oauth/http.rs`, `relay/src/oauth/tests.rs`. Modify `relay/src/http.rs`, `relay/src/ratelimit.rs` only if a per-IP bucket needs a new constructor.

**Interfaces:**
- Consumes: Task 1.
- Produces: `oauth::wants(&Method, &str) -> bool`, `oauth::handle(Arc<App>, Request<Incoming>) -> Response<Body>`.
- `mcp_post(app, req, device_id, metadata_url: String)`: `/mcp/d/` passes `device_metadata_url`, `/mcp/app/` passes `app_metadata_url`.

- [ ] **Step 1:** Write failing tests: `app_prm_names_the_relay`, `device_prm_still_names_zitadel`, `as_metadata_lists_register_authorize_token_s256_and_client_secret_post`, `app_url_401_points_at_app_metadata`, `register_returns_201_with_client_and_secret`, `register_refuses_foreign_callback_with_invalid_redirect_uri`, `register_body_over_16k_is_refused`, `register_is_rate_limited_per_ip`, `feature_off_every_new_path_is_404`.
- [ ] **Step 2:** Run the test command. Expected: FAIL.
- [ ] **Step 3:** Implement. Per-IP limit: 10/minute, burst 10, using the forwarded client IP the way the relay's existing per-IP code does; if none exists, a bounded map of at most 10,000 IPs.
- [ ] **Step 4:** Run the test command. Expected: PASS.
- [ ] **Step 5:** Commit `feat(relay): discovery and registration for self-registering apps`.

### Task 3: Sign-in and consent

**Files:** Create `relay/src/oauth/pending.rs`, `relay/src/oauth/consent.rs`. Modify `relay/src/oauth/http.rs`, `relay/src/oauth/tests.rs`, `relay/src/dashboard/pages.rs` only to reuse its page shell.

**Interfaces:**
- Consumes: the dashboard's `Pkce`, `same_secret`, exchange-slot limit, and the app's role-requiring verifier.
- Produces: `Pending::{begin, take_for_callback, put_consent, take_consent, put_code, take_code}`. At most 2,000 entries, oldest evicted; sign-in entries live 10 minutes, consent 5, codes 60 s.
- `struct IssuedCode { client_id, callback, challenge, resource, access_token, refresh_token, expires_in, subject, device_id }`.

- [ ] **Step 1:** Write failing tests: `authorize_redirects_to_zitadel_with_fixed_callback_and_own_pkce`, `authorize_refuses_sandbox_callback_without_redirecting`, `authorize_refuses_unknown_client_without_redirecting`, `authorize_refuses_plain_pkce`, `authorize_refuses_resource_for_another_host`, `callback_without_role_never_shows_consent`, `callback_for_someone_elses_device_looks_like_missing`, `consent_names_person_app_and_computer`, `consent_page_sets_no_store_and_frame_deny`, `deny_sends_access_denied_and_no_code`, `allow_redirects_with_code_and_original_state`, `allow_without_csrf_does_nothing`, `allow_from_other_origin_does_nothing`, `allow_replayed_does_nothing`, `pending_is_bounded`.
- [ ] **Step 2:** Run the test command. Expected: FAIL.
- [ ] **Step 3:** Implement. Ask Zitadel for `openid offline_access` plus the project audience scope, with `prompt=select_account`. Exchange the code before consent, so role and owner are checked first. Bind consent to an HttpOnly, Secure, SameSite=Lax cookie.
- [ ] **Step 4:** Run the test command. Expected: PASS.
- [ ] **Step 5:** Commit `feat(relay): app sign-in with a consent page`.

### Task 4: Token endpoint

**Files:** Modify `relay/src/oauth/http.rs`, `relay/src/oauth/tests.rs`.

**Interfaces:** Consumes `take_code`, `secret_ok`, `seal`, `open`. Accepts `client_secret_post` and `client_secret_basic`.

- [ ] **Step 1:** Write failing tests: `code_redeems_once`, `expired_code_is_invalid_grant`, `wrong_verifier_is_invalid_grant_and_burns_code`, `wrong_client_is_invalid_client`, `wrong_callback_is_invalid_grant`, `wrong_resource_is_invalid_grant`, `refresh_token_is_sealed_not_zitadels`, `refresh_rotates_sealed_token`, `refresh_from_another_client_is_invalid_grant`, `zitadel_refusing_refresh_is_invalid_grant`, `zitadel_down_is_503_temporarily_unavailable`, `responses_are_no_store`.
- [ ] **Step 2:** Run the test command. Expected: FAIL.
- [ ] **Step 3:** Implement; forward refresh to Zitadel as the `relay-apps` public client, within the dashboard's exchange-slot limit.
- [ ] **Step 4:** Run the test command. Expected: PASS.
- [ ] **Step 5:** Commit `feat(relay): token endpoint for self-registering apps`.

### Task 5: End-to-end isolation

**Files:** Modify `relay/tests/isolation.rs`, `relay/tests/relay_support.rs`.

- [ ] **Step 1:** Add `gemini_flow_reaches_only_own_computer`: register, authorize, fake Zitadel, Allow, redeem, then call `/mcp/app/<own>` (works) and `/mcp/app/<other>` (404). Add `claude_on_device_url_is_unchanged`.
- [ ] **Step 2:** Run `bazel test //apps/suites/vitruvian-relay/relay:all`. Expected: PASS. The existing ownership canaries must also fail on `/mcp/app/`: add the new test to the names `expect_failure.sh` requires.
- [ ] **Step 3:** Commit `test(relay): isolation through the app sign-in path`.

### Task 6: Zitadel client, chart and URLs

**Files:** Modify `infrastructure/pulumi/platform/zitadel-apps-relay/{main.go,main_test.go,README.md}`, `apps/suites/vitruvian-relay/relay/deploy/chart/{values.yaml,templates/deployment.yaml,templates/httproute.yaml,templates/_helpers.tpl}`, `tools/ci/chart-render/vitruvian-relay.values.yaml`, `tools/ci/src/chart_render/lib.rs`, `apps/suites/vitruvian-relay/connector/src/{auth.rs,main.rs}`, `relay/src/dashboard/pages.rs`. Create `gitops/argocd/platform/relay/relay-app-signin-sealed.yaml`.

- [ ] **Step 1:** Add failing tests: Go `TestAppsClientIsPublicWithRoleAssertion` (PKCE, callback exactly `https://relay.vitruviansoftware.dev/oauth/callback`, `AccessTokenRoleAssertion: true`, `IdTokenUserinfoAssertion: true` so the consent page can name the person, exported as `appsClientId`); connector `login_prints_the_app_url_for_gemini`; dashboard `device_row_shows_app_url`.
- [ ] **Step 2:** Run `bazel test` on those packages. Expected: FAIL.
- [ ] **Step 3:** Implement. Chart switch `appSignin.enabled` defaults false; when on it needs `oidc.appsClientId` and `appSignin.secretName`, and the route adds `/oauth/` and `/mcp/app/`. Seal a generated 32-byte key with the repo's sealing target; never print it.
- [ ] **Step 4:** Run `bazel test` on those packages and `bazel run //tools/ci:chart_render`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(relay): deploy wiring for app sign-in, off by default`.

### Task 7: Roll out and prove it

- [ ] **Step 1:** Land the PR. Run `zitadel-apps-relay-apply` as preview; apply only with +1 client and no replace or delete.
- [ ] **Step 2:** Land a values PR with the new image digest, `appSignin.enabled: true`, `oidc.appsClientId`, and that id added to `mcpClientIds` and to `mcpClientLabels` as Gemini.
- [ ] **Step 3:** Verify every "Done when" item in the spec on the live relay, including that the live consent page shows the person's name and email rather than their subject id.
