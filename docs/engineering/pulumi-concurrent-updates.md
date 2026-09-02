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

`delivery.yaml` serializes **push** runs into a single concurrency group, but
by design it does *not* serialize:

- **release runs**, which get one lane per tag (so two releases published in the
  same minute cannot evict each other), and
- **`workflow_dispatch` runs**, which get one lane per unit+environment (so a
  break-glass deploy is never stuck behind the push lane).

Both exemptions exist for good reasons, and both permit a release or dispatch
run to overlap a push run. Any overlap where *both* sides touch Pulumi is a 409.

This hazard predates the orchestrator — parallel foundation deploys hit it too.
Phase 2 masked it by funnelling every run into one lane; Phase 3's per-tag
release isolation re-exposed it.

## The Resolution (Decoupled State Backends)

As part of the enterprise monorepo scalability overhaul (Milestone 1), state storage was decoupled from the shared individual Pulumi Cloud account:

- **Per-App / Per-Env GCS State Backends**: Stacks now resolve to self-managed Google Cloud Storage buckets (`gs://${GOOGLE_CLOUD_PROJECT}-pulumi-state` or explicit `PULUMI_BACKEND_URL`).
- **Atomic Object Precondition Locking**: GCS uses native generation preconditions (`x-goog-if-generation-match`) per stack JSON file (`.pulumi/stacks/<stack>.json`), ensuring strict per-stack optimistic locking with zero cross-app or cross-environment lock contention.
- **Fail-Fast Direct Execution**: All client-side 409 retry loops, `tee` output capturing hacks, and exponential backoff sleeps in `tools/pulumi/pulumi-cmd.sh` and CI workflows have been completely removed in favor of clean, direct, unbuffered process execution (`exec pulumi "$SUBCMD" "$@"`).
- **Issue Status**: [#1843](https://github.com/VitruvianSoftware/vitruvian-core/issues/1843) is resolved.

## If you encounter a lock issue

1. Check whether a lock is genuinely held on the state bucket:
   `pulumi stack history --stack <stack>` — a still-running update has no `endTime`.
2. If a run was cancelled mid-update and the state lock lease remains held:
   `pulumi cancel -s <stack>`. Never cancel a legitimately running update.
3. Re-run the failed job. Because deploys are digest-pinned and blue-green, re-running is safe and idempotent.
