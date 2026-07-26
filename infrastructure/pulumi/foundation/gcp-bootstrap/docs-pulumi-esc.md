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

The stack exports `pulumi_esc_wif_pool_name`, `pulumi_esc_wif_provider_name` and
`pulumi_esc_service_account`. Use them in the ESC environment definition:

```yaml
values:
  gcp:
    login:
      fn::open::gcp-login:
        project: <project number>
        oidc:
          workloadPoolId: pulumi-esc-pool
          providerId: pulumi-esc-provider
          serviceAccount: <pulumi_esc_service_account>
```

Then point sessions at it:

```
VITRUVIAN_ESC_ENV=<project>/<env>
```

`//tools/gcp-token` tries local credentials, then ESC, then the tailnet broker —
so ESC becomes primary and the homelab stays as the backup for when Pulumi is
unreachable.

## Status

The GCP resources and the `gcp-token` plumbing are **written and unit-tested**;
the end-to-end exchange is **unverified** until this stack is applied and an ESC
environment exists. The probe above proves Pulumi's half; this proves nothing
about the GCP half until it runs.
