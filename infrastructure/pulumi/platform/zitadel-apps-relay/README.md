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
| `relay-dashboard` | The relay's own web page, where signed-in people see their computers and activity | Authorization code with PKCE, no secret. Callback `https://relay.vitruviansoftware.dev/auth/callback`, after sign-out back to `https://relay.vitruviansoftware.dev/` |
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

Callbacks are checked on host **and** exact path shape before anything is
created:

- ChatGPT: `https://chatgpt.com/connector/oauth/{id}`, or exactly
  `https://chatgpt.com/connector_platform_oauth_redirect`
- Gemini: `https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-{id}`
- Dashboard: exactly `https://relay.vitruviansoftware.dev/auth/callback` (a fixed
  value in `main.go`, checked the same way)

`{id}` is letters, digits, `_` and `-` only. Anything else is an apply error: a
look-alike path, an extra segment, a `.` or `..` id, a `%` escape, a backslash, a
`?` or `#` (even empty), or a scheme other than lower-case `https://`. A wrong
callback would send the sign-in code somewhere else.

If Gemini's sign-in fails with `invalid_client` at `/oauth/v2/token` after the
browser round trip, the auth method is the first thing to change (the sibling
stack's README explains why).

## Two things to know

- **`aud` is not a boundary in this Zitadel.** Any signed-in user can ask for any
  project's audience scope. The relay must accept a token only when its client
  id (`azp`) is one of this stack's clients **and** its subject is allowed. See
  `zitadel-apps-mcp-slack`'s README for how that was established.
- **Access is invite-only.** You can sign in only if you hold the `relay-user`
  role through a user grant. `projectRoleCheck` is on, and the stack refuses to
  apply it without at least one grant in `grantUserIds`, because that
  combination locks everyone out and looks like a server bug at the next login.

## Who can sign in

- **James** holds `relay-user` through `grantUserIds` (his account in the
  "Vitruvian" org). That grant already names the role, so it carries over. The
  relay now refuses tokens without the role, so James must hold it before the
  new relay image rolls out. After an apply, `roleClaim` and `projectId` show
  what the relay checks.
- **Everyone else** lives in a separate org, "Vitruvian Relay customers"
  (`customerOrgId` output). The `relay` project is granted to that org with the
  one role, `relay-user`. Each id in `inviteUserIds` (comma-separated, in the
  stack config) gets a user grant on that project grant. Merge the change and
  CI applies it. Nobody is added by hand in the console.
- The project asserts roles, so access tokens carry
  `urn:zitadel:iam:org:project:{projectId}:roles`, an object keyed by role key.
  That claim name is the `roleClaim` output. The relay checks it, and it still
  checks the client id and the subject too, never the audience alone.

## Sign-up and invites

Findings from reading the repo on 2026-11-21:

- **Open self-registration needs a login policy with `allowRegister`**, set on
  the customer org (or the instance). This stack does not set one, so
  registration stays off. The instance's own default is not in GitOps and I
  could not read the live setting (there is no read-only Bazel target for
  Zitadel's management API; the API is reachable only from CI over the tailnet).
- **No SMTP is configured.** `gitops/argocd/platform/zitadel/applicationset.yaml`
  has no mail settings, and nothing else under `gitops/` mentions SMTP. Without
  mail, Zitadel cannot send the email-verification or password-reset messages
  that open sign-up depends on.

So, for P2, there is **no open sign-up**. An invited person is created in the
customer org (their user is not made by this stack, because a password cannot
live in git), James gives them the first password in person or over a private
channel, and they set their own password at first sign-in. James then adds their
user id to `inviteUserIds` and CI grants them the role. Open self-registration
(`allowRegister`) moves to P3, once Zitadel has SMTP.

## Applying

Applying runs through the plan guard (`//tools/pulumi:guarded-up`): a plan
that deletes or replaces anything is refused. This stack applies only from a
manual dispatch, which never carries an `Allow-destroy` approval, so a delete
or replace here can't be applied from CI. Add a push trigger to the workflow
first if one is ever needed.

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
