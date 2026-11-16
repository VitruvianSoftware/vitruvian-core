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
| `POST /devices` | `vrelay login` | Registers this person's device key (one device per person in P1) |
| `GET /connect` | `vrelay run` | The device's WebSocket |
| `GET /.well-known/oauth-protected-resource[/mcp/d/{device}]` | anyone | Where to sign in |
| `GET /healthz` | the cluster | Liveness |

Settings come from the environment (`src/config.rs`): `PUBLIC_URL`,
`ISSUER`, `PROJECT_ID`, `MCP_CLIENT_IDS`, `CONNECTOR_CLIENT_ID`,
`ALLOWED_SUBJECTS`, `DATA_DIR` (the device records; must be a persistent
volume), `PORT`. It stops on SIGTERM.

```
bazel test //apps/suites/vitruvian-relay/relay:unit_tests
bazel run //apps/suites/vitruvian-relay/relay:vitruvian-relay -- --version
```
