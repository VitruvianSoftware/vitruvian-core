# Pulumi Cloud: one update at a time, account-wide

## The limitation

Our Pulumi Cloud backend is an **individual account** (`ipv1337`). Individual
accounts permit exactly **one running update across the entire account** — not
one per stack, not one per project. While any stack is updating, an update to
*any other* stack is rejected immediately:

```
error: [409] Conflict: You have a running update for the stack 'pulumi_tabula_web/development'.
Individual user accounts do not support concurrent updates. Create an organization to have
concurrent updates, wait for this update to complete, or run
`pulumi cancel -s pulumi_tabula_web/development` to cancel the ongoing update.
```

Note what the message names: the stack holding the lock is a **completely
unrelated one**. A failure here says nothing about the stack you were deploying.

## What it cost us

On 2026-08-20, `oauth-user-inspector` v1.11.0's **production** promotion
([run 32355118334](https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/32355118334))
failed at 16:09:19Z. Two seconds earlier, at 16:09:17Z, an unrelated
`tabula-web` **development** deploy had begun its own update. The production
rollout was rejected with the 409 above.

Blast radius was limited only because the rollout is blue-green and fail-closed:
the 409 landed during the *candidate* phase, so no traffic ever moved and
production kept serving the previous revision. The promotion simply did not
happen — silently, from the operator's point of view, until someone read the
run.

The two runs were each individually correct. Nothing was misconfigured. They
merely overlapped, which this backend does not allow.

## Why delivery makes this more likely, not less

Each app delivers through its own generated workflow,
`.github/workflows/delivery-<app>.yaml`, with its own queue. That keeps one
app's approval wait from holding back another app, but it also means two apps'
Pulumi applies can now run at the same time. Inside one app's workflow it was
never prevented either: on 2026-10-06 one run of the old shared workflow lost
`tabula-build-stack-shared` and `oauth-user-inspector-identity-development` to
this 409, from parallel jobs in the same run.

Each workflow also deliberately does *not* serialize:

- **release runs**, which get one lane per tag (so two releases published in the
  same minute cannot evict each other), and
- **`workflow_dispatch` runs**, which get one lane per unit+environment (so a
  break-glass deploy is never stuck behind the push lane).

Any overlap where *both* sides touch Pulumi is a 409. GitHub `concurrency:`
groups cannot prevent it: the limit spans different stacks, and one repo-wide
group would cancel pending runs instead of queueing them, silently dropping
applies.

## What we do about it: wait and retry

Every path that runs a Pulumi update goes through
[`tools/pulumi/retry-concurrent-update.sh`](../../tools/pulumi/retry-concurrent-update.sh):

- the Bazel wrapper, `tools/pulumi/pulumi-cmd.sh` (and so
  `//tools/deploy:cloud-run`, the Cloud Run blue-green rollout);
- the `.github/actions/pulumi-run-captured` composite action (the identity
  applies, tabula's build stack, the foundation workflows);
- the inline `pulumi up` / `pulumi refresh` in the zitadel-apps workflows.

It retries **only** this error: a `[409]` that also says "concurrent update".
The 409 is raised when the update is created, before any resource is touched,
so a retry is safe. Waits start at 15 seconds, double, and are capped at 60
seconds, for 8 attempts: about 6 minutes in all, enough for a few other applies
to finish first. Any other failure exits at once with Pulumi's own exit code.
`PULUMI_CONFLICT_MAX_ATTEMPTS`, `PULUMI_CONFLICT_RETRY_DELAY` and
`PULUMI_CONFLICT_MAX_DELAY` override the budget. Tests:
`//tools/pulumi:retry_concurrent_update_test` and
`//tools/pulumi:pulumi_cmd_test`.

The retry turns most collisions into a delay. It does not remove the limit:
Pulumi updates still run one at a time across the account, and an update that
waits longer than the budget still fails.

## Removing the limit (open: #1843)

All stacks are still on Pulumi Cloud under `ipv1337`; no state has moved.
[#1843](https://github.com/VitruvianSoftware/vitruvian-core/issues/1843) tracks
the decision. The options:

- **A Pulumi Cloud organization.** Allows concurrent updates and keeps the UI,
  update history and PR integration. Costs a paid plan, and every
  `ipv1337/<project>/<stack>` reference must be renamed to the organization.
- **A self-managed GCS backend.** One lock per stack, so different stacks never
  block each other, and no Pulumi Cloud dependency. It costs:
  - Pulumi Cloud's UI, update history, audit log and `pulumi[bot]` PR comments;
  - a secrets provider of our own (Cloud KMS) instead of Pulumi's managed
    encryption;
  - a migration of the whole stack graph: about 39 `StackReference`s point at
    `ipv1337/foundation-*` stacks, and a reference cannot read across
    backends, so the foundation stacks would have to move along with the apps.

  `tools/pulumi/pulumi-cmd.sh` already derives `gs://<project>-pulumi-state`
  when no `PULUMI_ACCESS_TOKEN` is set, but CI passes the token, so CI never
  takes that path.
- **Keep the retry** (today). Cheapest, and enough while collisions stay short.

## If an update still fails with this 409

1. Read the stack named in the error: that is the update holding the account,
   not necessarily yours. `pulumi stack history --stack <stack>` shows it; a
   still-running update has no end time.
2. If a run was cancelled mid-update and left the stack marked as updating:
   `pulumi cancel -s <stack>`. Never cancel a legitimately running update.
3. Re-run the failed job. Deploys are digest-pinned and blue-green, so a
   re-run is safe.
