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

# zitadel-apps-mcp-slack

The Zitadel **project** and **OIDC client** that let Google Gemini Spark reach the
hosted mcp-slack HTTP listener.

## Why this is a sibling of `zitadel-apps`, not an entry in it

`platform/zitadel-apps` is oauth-user-inspector's stack: hardcoded
`OAUTH_USER_INSPECTOR_` secret prefix, GCP Secret Manager cred-sync, per-env Cloud
Run origins appended to the redirect list. mcp-slack shares none of that — no GCP
target, one deployment, and it needs a project of its own. Generalising that stack
would mean refactoring a live path whose client has already been destroyed once by
an accidental replacement (2026-06-26). Separate stack, no shared blast radius.

## Why its own Zitadel project

Zitadel's audience-granting scope is
`urn:zitadel:iam:org:project:id:{projectId}:aud` — scoped to the **project**, not
the application. If mcp-slack's client lived in oauth-user-inspector's project, an
access token audienced for that project would validate at *both* apps, and the
`aud` claim would stop being a boundary. mcp-slack validates that claim locally, so
the boundary has to be real.

## Who is the client here

**Spark is the OAuth client; mcp-slack is the resource server.** Two consequences
that look like mistakes until you know that:

- The only redirect URI is Google's fixed
  `https://vertexaisearch.cloud.google.com/oauth-redirect`. It is identical for
  every customer and environment. The mcp-slack hostname appears nowhere in this
  stack, and there is no per-environment callback to register.
- mcp-slack exposes no OAuth discovery endpoint and performs no dynamic client
  registration. It validates a JWT that Zitadel issued, against JWKS.

## Outputs

| Output | Used by |
|---|---|
| `projectId` | mcp-slack's audience validation (config/env, never a constant) |
| `sparkScopes` | The exact space-separated scope string to paste into Spark |
| `clientId` / `clientSecret` | Pasted into Spark's connector config (secret is masked in state) |
| `authorizationEndpoint` / `tokenEndpoint` | Pasted into Spark; base URLs, no query parameters |
| `accessTokenType` | Drift check — see below |
| `projectRoleCheck` | Whether the access restriction is actually enabled — see below |

`sparkScopes` is assembled here on purpose. A scope string missing the audience
term still yields a **valid** token — correct signature, issuer and expiry — that
mcp-slack then rejects on every call. That failure looks exactly like a broken
build, so the value is generated rather than hand-written.

## Checking the token type (the one field Pulumi won't fix)

`accessTokenType` sits in the `IgnoreChanges` list, so it is the single setting
this stack will never reconcile. mcp-slack's entire auth model assumes `JWT`: if
the live client ends up on `BEARER`, the stack reports clean forever while the
server rejects every request — and that failure is indistinguishable from a broken
transport, because Spark authenticates fine and then every call fails.

`IgnoreChanges` governs diffs, not creates, so the first apply sets it correctly.
Nothing corrects it afterwards, which is why it's worth confirming rather than
assuming:

```sh
bazel run //infrastructure/pulumi/platform/zitadel-apps-mcp-slack:refresh
pulumi stack output accessTokenType   # want: OIDC_TOKEN_TYPE_JWT
```

The `refresh` is load-bearing. Without it the output reports the value Pulumi last
wrote, not the value Zitadel currently holds; refresh updates state from live even
for ignored fields, because the ignore suppresses the diff being *applied*, not the
state being read.

Note that `authMethodType` is deliberately **not** ignored — a POST↔BASIC change
reconciles normally on a re-apply. `accessTokenType` is the only stuck field.

## Never import this client

The pulumiverse/zitadel provider treats `appType`, `version`, `accessTokenType`,
`clockSkew` and the assertion booleans as replace-triggering and does not populate
them on import, so `pulumi.Import` plans a *replacement* — which for this resource
means "create replacement + delete original" and destroys the live client. This is
not theoretical; it is what broke the sibling stack's app on 2026-06-26
(`Errors.App.NotFound`).

There is a `:import` Bazel target because the macro generates one. Do not use it
here. If the client needs changing, change it in `main.go` and re-apply. Never
hand-create one in the Zitadel console with the intention of adopting it.

## Applying

The Zitadel management API is **not reachable over the public Cloudflare edge** —
its bot protection returns `403 error code: 1010` to non-browser clients. Applies
route over tailnet to the internal Envoy gateway LB. The prerequisites and the CI
job shape are documented in [`../zitadel-apps/APPLYING-FROM-CI.md`](../zitadel-apps/APPLYING-FROM-CI.md)
and apply unchanged here.

```sh
bazel run //infrastructure/pulumi/platform/zitadel-apps-mcp-slack:preview
bazel run //infrastructure/pulumi/platform/zitadel-apps-mcp-slack:up
```

Both need the Zitadel provider credential (`ZITADEL_MACHINE_KEY_JSON`) and tailnet
reachability; neither is available from a plain checkout.

## Restricting who may connect

`projectRoleCheck` is the enforcement point for "only this subject may connect".
With it `true`, Zitadel will not issue a token for this project to a user who has
no role grant on it — a server-side restriction rather than a de-facto one that
holds only while the instance has a single user.

A value this stack cannot parse as a boolean is an **apply error**, not a silent
`false`. `cfg.GetBool` would have been fail-open here — it routes through
`cast.ToBool`, which swallows the parse error, so `projectRoleCheck: "yes"` (a
plausible way to try to turn this *on*) would disable the check and report a
successful apply. For the flag that decides who may obtain a token, refusing to
apply is the only honest response to a value we can't interpret.

It ships **`false`**, deliberately. Enabling it before the role grant exists locks
everyone out, including the first end-to-end Spark login. The sequence is:

1. apply with `projectRoleCheck: "false"` (this is the committed state),
2. grant the `mcp-slack-user` role to the intended user id,
3. set `projectRoleCheck: "true"` and apply again.

Steps 2 and 3 belong in one change.

**Nothing functional forces step 3.** After the grant, the endpoint works completely
— tokens issue, tools list, channels read and write — with the restriction still
off, and no symptom distinguishes that from the intended state. So the check is a
query, not a memory:

```sh
pulumi stack output projectRoleCheck   # want: true
```

That output, not someone recalling they ran the apply, is what establishes the
deployment is restricted to its intended subject.

## Client authentication method

`OIDC_AUTH_METHOD_TYPE_POST`. Google's connector documentation does not state which
method Gemini uses at the token endpoint, and the Zitadel instance advertises both
`client_secret_post` and `client_secret_basic` — so if the flow fails, this field
is the first thing to change.

**Failure signature:** Zitadel returns `invalid_client` at `/oauth/v2/token` *after*
a successful redirect back to Google. Browser round-trip working plus failure at
token exchange means this field, not the mcp-slack server.
