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
-->

# relay-spike

A throwaway server for the relay's phase 0
([plan](../../../../docs/superpowers/plans/2026-11-09-relay-p0-spikes.md),
[spec](../../../../docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md)).
It answers two questions and does nothing else:

- **Spike A:** can Claude (and ChatGPT) add an OAuth-protected MCP server on our
  domain, signing in through Zitadel? `POST /mcp` is a minimal MCP server with
  two read-only tools, `echo` and `whoami`.
- **Spike C:** does a WebSocket through the Cloudflare Tunnel stay up? `GET
  /connect` echoes text and pings every 20 seconds, and logs how long each
  socket lasted and why it closed.

| Path | Public | Who may call it |
|---|---|---|
| `/.well-known/oauth-protected-resource[/mcp]` | yes | anyone (it's the sign-in pointer) |
| `/mcp` | yes | a token from an AI-app client (`MCP_CLIENT_IDS`) for an allowed user |
| `/connect` | yes | a token from the connector client (`CONNECTOR_CLIENT_ID`) for an allowed user |
| `/healthz` | no | the kubelet |

Tokens are checked with mcp-slack's verifier, reused rather than copied:
signature against Zitadel's keys, issuer, expiry, audience, the exact client id,
and the subject allowlist. The `aud` claim alone proves nothing in our Zitadel,
which is why the client id and subject checks exist.

## Run it locally

```bash
bazel build //apps/suites/relay/spike:relay-spike
```

Settings come from the environment: `PUBLIC_URL`, `ISSUER`, `PROJECT_ID`,
`MCP_CLIENT_IDS`, `CONNECTOR_CLIENT_ID`, `ALLOWED_SUBJECTS` (all required) and
`PORT` (default 3000). `JWKS_URI` points the key fetch at a local key set for
testing with self-minted tokens. It is never set in the cluster.

## Not the relay

No device routing, no billing, no storage, one replica. It gets deleted, or
grows into the relay, after P0.
