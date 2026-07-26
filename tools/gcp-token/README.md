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
the environment is *your whole identity* sitting in a sandbox. This needs a node
you already run.

## Pulumi ESC — measured, and what it would take

ESC would remove the homelab dependency entirely: the credential would come from
Pulumi's servers rather than a machine at home, so nothing local needs to be
awake. **Its half already works** — probed against the live account, ESC accepted
a `fn::open::gcp-login` definition and attempted a real OIDC exchange with Google,
failing *only* because the trust relationship does not exist yet:

```
Diags: exchanging token: could not authenticate with GCP.
Subject:  "pulumi:environments:org:ipv1337:env:<project>/<env>"
Audience: "gcp:ipv1337"
status 400: invalid_target … the pool or provider is disabled or deleted or
                              because it doesn't exist
```

So the missing piece is entirely on the GCP side, and that error names it: a
workload identity pool + OIDC provider trusting Pulumi's issuer with audience
`gcp:ipv1337`, an attribute mapping on that subject, and a service account the
federated principal may impersonate. That is a foundation change
(`infrastructure/pulumi/foundation/`) touching org-level IAM — reviewed and
applied deliberately, not incidentally.

Nothing here is wasted when that lands: every caller already takes its credential
through `GOOGLE_OAUTH_ACCESS_TOKEN`, so ESC becomes another source in the
resolution order above and the tailnet broker stays as the fallback for when
Pulumi is unreachable.

## Resolution order

1. **Local `gcloud`.** On a laptop or in CI that already has credentials, this is
   just `gcloud auth print-access-token` and the network is never touched.
2. **Pulumi ESC**, when `VITRUVIAN_ESC_ENV` is set — keyless *and* with no
   homelab dependency. Ahead of the broker because a cloud service beats a
   machine in someone's house; behind local credentials because a logged-in
   laptop should not phone anything. Falls through on any failure rather than
   being fatal, which is what makes "ESC primary, homelab backup" real.
3. **The tailnet broker.** When the first two come up empty.

That ordering is what lets `//tools/pulumi` call this unconditionally: laptop, CI
and cloud session share one code path, and auth is chosen at the edge.

## Minted on demand, never at session start

An access token lives about an hour; a Claude session outlives that comfortably.
A token fetched by the `SessionStart` hook would be stale exactly when it
mattered, so callers ask for one when they need one.

## Brokers: a list, tried in order

`VITRUVIAN_GCP_BROKERS` is walked until one node mints. A single host is not
enough in practice — any given box may be asleep, lack the SDK, not be logged
into the account, or have had its Workspace login lapse — and which node that is
changes constantly. Always-on nodes come first so the fast path doesn't depend on
a laptop lid; laptops follow, because today they're the ones actually logged in.

**Finding gcloud on the broker is not just `command -v`.** A non-interactive ssh
session gets a bare PATH and does not source the user's shell profile, so a
perfectly good node looks like it has no SDK. Measured on `james-mbp16`: gcloud
sits at `/opt/homebrew/bin/gcloud` while non-interactive ssh sees only nix paths
and the system dirs. The remote command therefore resolves in three widening
steps — PATH, then the user's **login shell**, then known install locations.

The winning node is cached (`~/.config/vitruvian-core/cloud/gcp-broker`) and tried
first next time. A cached host no longer in the list is ignored.

**A long-lived tmux/screen session can serve a stale environment.** Setting
`nuc9i5` up, gcloud failed there with *"You are running gcloud with Python 2.7,
which is no longer supported"* — while a plain `ssh` and a login shell both ran
it fine. The cause was not the shell: a tmux server running since the previous
month had `CLOUDSDK_PYTHON=/bin/python2` in its environment, and tmux gives every
new window the **server's** environment rather than the client's, so the stale
value outlived the shell that set it. It appears in no profile file, and a fresh
tmux server was clean.

This never affects the broker, which uses plain non-interactive `ssh`. It is
recorded because the obvious fix — pinning `CLOUDSDK_PYTHON` in the profile —
would be a permanent workaround for transient state, and would hide the next
occurrence. The surgical fix, which does not disturb anything running in the
session:

```sh
tmux set-environment -g -u CLOUDSDK_PYTHON
```

Set a node up once:

```sh
curl https://sdk.cloud.google.com | bash
gcloud auth login <account>
```

`<account>` must be what
[`infrastructure/gcp-identities.tsv`](../../infrastructure/gcp-identities.tsv)
pins for the work you want — the wrapper asks for that account by name, so a
broker logged into a different one fails loudly rather than quietly handing back
the wrong identity.

## Workspace logins lapse per node — which is why the list matters

Google Workspace enforces **Google Cloud session control**: a managed account's
gcloud login expires periodically and wants an *interactive* re-login that SSH
cannot give it. Measured on the real fleet, for the same account at the same
moment:

```
james-macbook-pro   REAUTH LAPSED — this node's login for the account has expired
james-mbp16         MINTS (258 bytes)
```

This is a **per-node session**, not a property of the account. A node someone has
logged into recently mints fine; walking the list routes around the lapsed one
automatically. That is what turns broker failover from a nice-to-have into the
thing that makes this reliable.

Two ways to keep it healthy, neither urgent:

- `gcloud auth login <account>` on a node whose session lapsed, whenever
  convenient — normal use of any of these machines does this anyway.
- Widen **Admin console → Security → Access and data control → Google Cloud
  session control** to make lapses rarer.

The failure names itself (`REAUTH LAPSED`) and says another node may still work.

## Failure

Fatal, and it names the cause **per node** — the four failure modes want
completely different fixes, so collapsing them into "broker unreachable" would
send you to the wrong place:

```
gcp-token: no broker could mint a token for james@vitruviansoftware.dev
  fedora                 no gcloud installed
  nuc9i5                 gcloud present but not logged in as james@vitruviansoftware.dev
  nuc9i9                 no gcloud installed
  james-macbook-pro      REAUTH LAPSED — this node's login for the account has expired…
```

A reply too short to be an access token is also refused, so a truncated read or
an error string can never be exported as a credential that 401s later.

## Tests

`bazel test //tools/gcp-token:gcp_token_test` — hermetic, driving the real script
against a fake `gcloud` and a fake `ssh` that record argv. It pins: local
credentials preferred and the network untouched; the broker used only as a
fallback and asked for the **requested** account; stdout the bare token so
`$(...)` capture stays clean; the token absent from stderr; an account with shell
metacharacters refused *before* it reaches the remote command line; a
short/garbage reply refused rather than exported; and an unreachable broker fatal
with a message that names the fix.
