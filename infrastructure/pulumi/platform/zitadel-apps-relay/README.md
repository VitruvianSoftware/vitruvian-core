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

# zitadel-apps-relay

The Zitadel project and sign-in clients for the Vitruvian Relay
([design spec](../../../../docs/superpowers/specs/2026-11-07-vitruvian-relay-design.md)).

| Client | Who uses it | How it signs in |
|---|---|---|
| `relay-connector` | The program on the user's computer | OAuth device flow: the terminal shows a code, the user approves it in a browser. No redirect URI |
| `relay-claude` | Claude (web, desktop, mobile), via "Use your own OAuth client" | Authorization code with PKCE, callback `https://claude.ai/api/mcp/auth_callback` |
| `relay-chatgpt` | ChatGPT, only once `chatgptRedirectUris` is set | Authorization code with PKCE, ChatGPT's per-connector callback |
| `relay-gemini` | The Gemini app (Settings → Connectors → + Custom), only once `geminiRedirectUris` is set | Authorization code with a client secret (`client_secret_post`), Gemini's per-user callback on `oauth-redirect.googleusercontent.com` |

All of them issue JWT access tokens, so the relay can check them locally against
Zitadel's public keys. All but `relay-gemini` are public clients (no secret;
PKCE is required). Gemini's form asks for a client id and a secret, so
`relay-gemini` is confidential, like the Gemini client in
[`zitadel-apps-mcp-slack`](../zitadel-apps-mcp-slack/README.md). Its secret is the
`geminiClientSecret` stack output. It stays masked in the apply log; after an apply,
James reads it locally and pastes it into Gemini himself:

```sh
bazel run //infrastructure/pulumi/platform/zitadel-apps-relay:stack -- output geminiClientSecret --show-secrets --stack development
```

The client id is printed in the apply report (`geminiClientId`).

Callbacks are checked on host **and** path before anything is created: ChatGPT's
must sit under `https://chatgpt.com/connector`, Gemini's under
`https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-`. A callback
outside those is an apply error, because a wrong one would send the sign-in code
somewhere else. If Gemini's sign-in fails with `invalid_client` at
`/oauth/v2/token` after the browser round trip, the auth method is the first thing
to change (the sibling stack's README explains why).

## Two things to know

- **`aud` is not a boundary in this Zitadel.** Any signed-in user can ask for any
  project's audience scope. The relay must accept a token only when its client
  id (`azp`) is one of this stack's clients **and** its subject is allowed. See
  `zitadel-apps-mcp-slack`'s README for how that was established.
- **During P0 only James can sign in.** `projectRoleCheck` is on with one grant.
  The stack refuses to apply the check without a grant, because that combination
  locks everyone out and looks like a server bug at the next login.

## Applying

CI only, never from a workstation: the public edge blocks Zitadel's management
API. Dispatch `.github/workflows/zitadel-apps-relay-apply.yaml` from `main`,
`preview` first, then `up`. The job prints the client ids and checks every client
issues JWTs. wren can dispatch it (`bazel run //tools/agent-app -- workflow-run
zitadel-apps-relay-apply.yaml -f action=preview`); James allowed that on 2026-11-09.
Read the preview's plan before running `up`.

Never run the `:import` target here. The provider plans a replacement, which
deletes the live client.

## Interface
- Internal implementation components

## Invariants
- None

## Side Effects
- [main.go:124]: `return nil, fmt.Errorf("%s: redirect URI %q must be an https URL on %s with n...`

## Verification
- Run: `bazel test //infrastructure/pulumi/platform/zitadel-apps-relay/...`
