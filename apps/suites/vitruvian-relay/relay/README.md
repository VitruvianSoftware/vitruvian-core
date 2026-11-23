<!--
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# Vitruvian Relay server

The server AI apps and Macs both connect to. It keeps no call content: only
names, sizes and outcomes are logged, as JSON lines on stdout.

| Route | Who | What |
|---|---|---|
| `POST /mcp/d/{device}` | AI app (its own Zitadel client) | MCP over Streamable HTTP, answered as JSON |
| `POST /devices` | `vrelay login` | `{public_key, name, device_id?}`: with the `device_id` this person already has, replaces that computer's key; without one, adds a computer (up to 5 per person) |
| `GET /connect` | `vrelay run` | The device's WebSocket |
| `GET /.well-known/oauth-protected-resource[/mcp/d/{device}]` | anyone | Where to sign in |
| `GET /`, `/auth/login`, `/auth/callback`, `POST /auth/logout`, `GET /devices`, `/devices/{id}`, `POST /devices/{id}/rename`, `POST /devices/{id}/remove`, `GET /activity?device={id}`, `GET /static/relay.css` | a signed-in browser | [The dashboard](#the-dashboard) |
| `GET /healthz` | the cluster | Liveness |

Settings come from the environment (`src/config.rs`): `PUBLIC_URL`,
`ISSUER`, `PROJECT_ID`, `MCP_CLIENT_IDS`, `CONNECTOR_CLIENT_ID`,
`DASHBOARD_CLIENT_ID` (all three client id lists must be disjoint),
`MCP_CLIENT_LABELS` (optional, `Claude=<id>,Gemini=<id>`: what the dashboard
calls each AI app), `TOKEN_URI` (optional, overrides
`{ISSUER}/oauth/v2/token` for local runs and tests; it, `ISSUER` and
`JWKS_URI` must be https, or http on localhost or 127.0.0.1, or the relay will
not start),
`REQUIRED_ROLE` (default `relay-user`), `DATABASE_URL` (Postgres; the
connection is TLS checked against `DATABASE_CA_FILE`, or the system's
certificates, unless the URL says `sslmode=disable`, which is for tests),
`PORT`. It stops on SIGTERM.

Access is invite-only: being able to sign in is not enough, the token must
carry the Zitadel project role `REQUIRED_ROLE`
(`urn:zitadel:iam:org:project:{PROJECT_ID}:roles`). A token without it is
refused with a 403 and logged as `auth_refused` code `role_missing`. There is
no list of people any more: `ALLOWED_SUBJECTS` is ignored (the relay logs
`setting_ignored` if it is still set). The relay still authorises on client id
and subject, never on audience alone, and a device answers only its owner: one
check (`App::owned_device`) decides it for every route, so someone else's
device looks exactly like one that does not exist.

## The dashboard

A few server-rendered pages (no JavaScript; `src/dashboard/`) where a signed-in
person sees their computers (online or not, last seen, the address to give an
AI app), the steps to add one to Claude or Gemini, and the last 200 calls, and
renames or removes a computer. Sign-in is the authorization-code flow with
PKCE (S256) against the `relay-dashboard` client; its token goes through a
third verifier pinned to `DASHBOARD_CLIENT_ID` and the same role, so a
dashboard token is refused at `/mcp`, `/devices` and `/connect`, and an AI
app's or the connector's is refused at `/auth/callback`. A sign-in becomes an
in-memory session (cookie `vr_session`; it ends at 12 hours or when the access
token expires, whichever is sooner, so a role taken away stops working with
the token; a restart signs everyone out). The sign-in always asks which
account (`prompt=select_account`), and at most 8 code exchanges run at once
(a ninth gets a plain 503 page). Every `POST` needs the session's CSRF token and an `Origin` equal to
`PUBLIC_URL`, or it gets a 403. Every route that names a computer goes through
`App::owned_device`. The activity page shows the tool, the time, the outcome
and the duration, never arguments: the relay keeps none. To look at the pages
without a database or an identity service, run
`DASHBOARD_PAGES_DIR=<dir> <relay test binary> --ignored write_pages_for_a_look`.

It closes an HTTP connection idle for 75 s (the first request's headers must
arrive within 10 s). A proxy in front must drop its idle upstream
connections sooner, or it will now and then reuse one the relay just closed
(a 503): set the gateway's upstream idle timeout to 60 s.

```
bazel test //apps/suites/vitruvian-relay/relay:unit_tests
bazel run //apps/suites/vitruvian-relay/relay:vitruvian-relay -- --version
```

## Tenant isolation, and its canaries

One person must never reach another's computer or request.
`tests/isolation.rs` has Alice and Bob, each with two computers (both call one
"MacBook Pro"), and checks that what Alice is told about Bob's computer or
request is byte for byte what she is told about one that does not exist, and
that Bob's side is untouched. There are two checks, and each is the only place
its question is decided: `App::owned_device` for every route that names a
computer, and `Mcp::owned_request` for every request id.

```
bazel test //apps/suites/vitruvian-relay/relay:vitruvian_relay_isolation_test
bazel test //apps/suites/vitruvian-relay/relay:vitruvian_relay_isolation_canary_test
bazel test //apps/suites/vitruvian-relay/relay:vitruvian_relay_isolation_request_canary_test
```

A check that cannot fail would prove nothing, so each check has a canary: the
same tests built against a relay with that one check broken on purpose (the
`relay_broken_ownership` and `relay_broken_request_ownership` cfgs, each in
exactly one place), run by `tests/expect_failure.sh`. A canary passes only if
the tests named for its break all fail, and some other test still passes (so
the failures are the break being noticed, not the database being down).

- The device canary (`App::owned_device`) must fail
  `mcp_initialize_tools_list_and_call_on_bobs_device`,
  `dashboard_device_page_rename_remove_for_bobs_device`,
  `hello_with_bobs_device_id` and `check_request_on_bobs_device_endpoint`.
- The request canary (`Mcp::owned_request`) must fail
  `check_request_with_bobs_request_id`.

Other isolation tests are not protected by a canary, because something else
holds even when those two checks are broken, and they pass in both canaries:
`register_with_bobs_device_id` and the rename and remove forms (the store only
changes a row its owner asks about), `rejoin_never_crosses_people` (a retry's
key includes the person), `activity_lists_only_own_rows` (the activity query
is by person), `protected_resource_metadata_for_bobs_device` (a public route
that never looks at who owns what) and `same_names_stay_separate`. They are
there to show those layers hold, not to notice a broken check.
