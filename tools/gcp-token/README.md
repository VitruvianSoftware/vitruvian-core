# gcp-token

A short-lived GCP access token for a declared account — minted over the tailnet
when this machine has no credentials of its own.

```sh
bazel run //tools/gcp-token -- james@vitruviansoftware.dev
export GOOGLE_OAUTH_ACCESS_TOKEN="$(tools/gcp-token/gcp-token.sh <account>)"
```

You mostly won't call it directly. [`//tools/pulumi`](../pulumi) already does, so
`bazel run //infrastructure/pulumi/<project>:preview` works from a cloud session
with nothing extra.

## Why

A Claude Code cloud session has no GCP credentials and no human at a browser to
run `gcloud auth login`. The obvious fix — a service-account key on the cloud
environment — **is refused by our own org policy**:
`iam.disableServiceAccountKeyCreation` is enforced org-wide in
[`gcp-org/envs/shared/org_policy.go`](../../infrastructure/pulumi/foundation/gcp-org/envs/shared/org_policy.go),
and the comment above it says why: *"prevent SA key sprawl"*. Punching a hole in
a control we deliberately set, for the benefit of a sandbox, is the wrong trade.

A cloud session already has something better. It is **on the tailnet**, with
passwordless SSH to the homelab as `james`
([cloud sessions doc](../../docs/admin/claude-code-cloud-sessions.md)). A homelab
node that is already logged in can mint a token on demand:

- **No long-lived credential on the cloud environment at all** — not a key, not a
  refresh token. The session holds a ~1h access token and nothing else.
- **The refresh token never leaves the homelab box.**
- **Nothing to rotate** on the environment, and no org-policy exception.
- **Tailnet membership is the authentication factor.** Drop the node from the
  tailnet, or revoke the agent's SSH key, and cloud sessions lose GCP at once.

Compare the alternatives: an SA key is blocked by policy; a user refresh token in
the environment is *your whole identity* sitting in a sandbox; Pulumi ESC is the
better long-term answer but needs a WIF pool, an OIDC provider and a foundation
change. This needs a node you already run.

## Resolution order

1. **Local `gcloud`.** On a laptop or in CI that already has credentials, this is
   just `gcloud auth print-access-token` and the network is never touched.
2. **The tailnet broker.** Only when step 1 comes up empty.

That ordering is what lets `//tools/pulumi` call this unconditionally: laptop, CI
and cloud session share one code path, and auth is chosen at the edge.

## Minted on demand, never at session start

An access token lives about an hour; a Claude session outlives that comfortably.
A token fetched by the `SessionStart` hook would be stale exactly when it
mattered, so callers ask for one when they need one.

## Setting up the broker

One node, once:

```sh
# on an always-on homelab node
curl https://sdk.cloud.google.com | bash
gcloud auth login james@vitruviansoftware.dev
```

**Prefer an always-on node over a laptop** — GCP work fails whenever the laptop
sleeps. The default broker is `fedora`; override with `VITRUVIAN_GCP_BROKER`
(and `VITRUVIAN_GCP_BROKER_USER`, default `james`).

The account you log in as must be the one
[`infrastructure/gcp-identities.tsv`](../../infrastructure/gcp-identities.tsv)
pins for the work you want to do — the wrapper asks for that account by name, and
a broker that isn't logged into it fails with a checklist rather than quietly
handing back a different identity.

## Failure

Fatal and actionable. An unreachable broker, a broker without gcloud, or one not
logged into the requested account prints the checklist (tailnet up? gcloud
installed? logged in? different broker?) rather than a bare non-zero exit. A
reply too short to be an access token is also refused, so a truncated read or an
error string can never be exported as a credential that 401s later.

## Tests

`bazel test //tools/gcp-token:gcp_token_test` — hermetic, driving the real script
against a fake `gcloud` and a fake `ssh` that record argv. It pins: local
credentials preferred and the network untouched; the broker used only as a
fallback and asked for the **requested** account; stdout the bare token so
`$(...)` capture stays clean; the token absent from stderr; an account with shell
metacharacters refused *before* it reaches the remote command line; a
short/garbage reply refused rather than exported; and an unreachable broker fatal
with a message that names the fix.
