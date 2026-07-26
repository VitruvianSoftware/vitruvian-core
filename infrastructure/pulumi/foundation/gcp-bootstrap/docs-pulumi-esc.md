# Pulumi ESC federation (keyless GCP for agent sessions)

Lets a Claude Code cloud session obtain GCP credentials with **no key anywhere**,
removing the homelab dependency that [`//tools/gcp-token`](../../../../tools/gcp-token/README.md)
otherwise relies on.

## Why it exists

`iam.disableServiceAccountKeyCreation` is enforced org-wide by `gcp-org`
("prevent SA key sprawl"), so a sandbox cannot hold a service-account key. The
tailnet broker works around that by minting a token from a homelab node — good,
but it means GCP work depends on a machine at home being reachable.

ESC removes that: Pulumi Cloud presents an OIDC token, GCP exchanges it for a
short-lived access token, and nothing local need be awake.

## This was probed before it was written

Against the live account, ESC accepted a `fn::open::gcp-login` definition and
attempted a **real** exchange, failing only with:

```
status 400: invalid_target … the pool or provider is disabled or deleted
                              or because it doesn't exist
Subject:  "pulumi:environments:org:<org>:env:<project>/<env>"
Audience: "gcp:<org>"
```

`build_pulumi_esc.go` creates exactly what that error named — nothing more.

## Configuration

| key | meaning |
| --- | --- |
| `pulumi_esc_org` | **Gates everything.** Unset → nothing is provisioned. |
| `pulumi_esc_environments` | Comma-separated `project/env` names allowed to impersonate. Required when the org is set. |
| `pulumi_esc_roles` | Comma-separated project roles for the SA. **Empty by default.** |
| `pulumi_esc_manage_environments` | Create the ESC environments too. **Default true**; set `false` to leave an externally-owned environment alone. |
| `pulumi_esc_pool_id` / `_provider_id` / `_sa_id` | Optional name overrides. |

```sh
pulumi config set pulumi_esc_org ipv1337
pulumi config set pulumi_esc_environments vitruvian-core/cloud-session
pulumi config set pulumi_esc_roles roles/secretmanager.secretAccessor
```

### The service account is inert by default, on purpose

No roles are granted unless you ask. A federated identity that can authenticate
but do nothing is the right starting point: the **trust relationship** becomes
reviewable on its own, and capability becomes a separate, deliberate decision
rather than a default nobody chose. `roles/secretmanager.secretAccessor` alone is
enough to replace the Secret Manager half of `//tools/cloud-bootstrap`.

### Subjects are named, not pattern-matched

Each environment gets its own binding on the **exact** subject
(`principal://…/subject/pulumi:environments:org:<org>:env:<project>/<env>`) rather
than an attribute `principalSet://`. A principalSet would let any future
environment matching the attribute impersonate the account without review; naming
each subject means adding one is a diff.

## After applying

**Both halves are created by the apply — there is nothing to paste.** The stack
builds the GCP side (pool, provider, service account, bindings) *and* the Pulumi
side: one ESC environment per name in `pulumi_esc_environments`, with the
`fn::open::gcp-login` block already filled in.

That is deliberate. Federation only works when the two halves agree, and they
live in different systems; the environment definition has to quote the project
NUMBER, the pool id and the service-account email that this stack generates.
Hand-copying three generated identifiers into a web form is where the wiring
goes silently wrong, and a mistake surfaces as an opaque 400 at exchange time
that does not say which half is wrong. Taking them from the resources means they
cannot disagree.

Set `pulumi_esc_manage_environments` to `false` for an environment that already
exists or is owned elsewhere — otherwise the stack and its owner fight over it.

The stack still exports `pulumi_esc_wif_pool_name`,
`pulumi_esc_wif_provider_name` and `pulumi_esc_service_account` for inspection.

Verify the environment resolves, then point sessions at it:

```sh
pulumi env open <org>/<project>/<env>     # a JSON blob with a token = live
```

```
VITRUVIAN_ESC_ENV=<org>/<project>/<env>
```

The `<project>/<env>` part MUST match the `pulumi_esc_environments` entry — that
string is what the workload-identity subject is built from, so a mismatch binds
one environment and uses another.

`//tools/gcp-token` tries local credentials, then ESC, then the tailnet broker —
so ESC becomes primary and the homelab stays as the backup for when Pulumi is
unreachable.

## Status

The GCP resources and the `gcp-token` plumbing are **written and unit-tested**;
the end-to-end exchange is **unverified** until this stack is applied and an ESC
environment exists. The probe above proves Pulumi's half; this proves nothing
about the GCP half until it runs.
