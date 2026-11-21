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
| `GET /healthz` | the cluster | Liveness |

Settings come from the environment (`src/config.rs`): `PUBLIC_URL`,
`ISSUER`, `PROJECT_ID`, `MCP_CLIENT_IDS`, `CONNECTOR_CLIENT_ID`,
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

It closes an HTTP connection idle for 75 s (the first request's headers must
arrive within 10 s). A proxy in front must drop its idle upstream
connections sooner, or it will now and then reuse one the relay just closed
(a 503): set the gateway's upstream idle timeout to 60 s.

```
bazel test //apps/suites/vitruvian-relay/relay:unit_tests
bazel run //apps/suites/vitruvian-relay/relay:vitruvian-relay -- --version
```
