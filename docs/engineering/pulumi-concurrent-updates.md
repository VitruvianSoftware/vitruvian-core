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

## What we do about it now

`tools/pulumi/pulumi_cmd.sh` retries **only** this error, and only for
subcommands that take the update lock (`up`, `destroy`, `refresh`, `import`):

- up to `PULUMI_LOCK_MAX_ATTEMPTS` attempts (default 6)
- exponential backoff from `PULUMI_LOCK_BACKOFF_SECONDS` (default 20s), so the
  window covered is roughly 20+40+80+160+320s ≈ 10 minutes
- every other failure, including a genuine `pulumi up` error, still fails on the
  first attempt with no delay

This does **not** contradict the standing rule *"never re-run IaC to fix a
race."* That rule is about races between resources, where a re-run papers over a
missing dependency. Here there is no resource race to lose: the lock belongs to
a different stack and is guaranteed to be released. We are waiting in a queue,
and the retry loop *is* the wait.

Behaviour note: to inspect output for the 409, the retry path pipes pulumi's
combined stdout+stderr through `tee`. Output still streams live, but the two
streams are merged and pulumi renders non-interactively. Non-lock-taking
subcommands are still `exec`'d untouched.

## The real fix

A **Pulumi organization** supports concurrent updates and removes the constraint
at its root, rather than queueing around it. Every mitigation above is
compensating for a single-user-account limit.

Tracked in [#1843](https://github.com/VitruvianSoftware/vitruvian-core/issues/1843).

## If you hit it anyway

1. Check whether a lock is genuinely held:
   `pulumi stack history --stack <org>/<project>/<stack>` — a still-running
   update has no `endTime`.
2. If a run was cancelled mid-update, the lock can be **stale**. Only then:
   `pulumi cancel -s <org>/<project>/<stack>`. Never cancel a legitimately
   running update; it can leave state inconsistent with reality.
3. Re-run the failed job. Because deploys are digest-pinned and blue-green,
   re-running is safe and idempotent.
