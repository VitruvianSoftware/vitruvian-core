# GitHub Actions workflows

Reference for the non-obvious automation in this directory. For CI/CD
*terminology*, see [`../CI_DEFINITIONS.md`](../CI_DEFINITIONS.md).

## Merge automation

`main` is protected by a **merge queue** (ruleset `merge-queue`, managed as code
in `infrastructure/pulumi/platform/repo_config`): every PR merges through the
queue once the required status checks pass on the queued (speculative) merge
commit. Two robots feed bot-authored PRs into that queue so they don't sit
waiting on a human.

> ℹ️ The merge-queue ruleset can also require a code-owner review, but that is
> gated off by default (`requireCodeOwnerReview` in `repo_config`) because a
> solo repo has no second reviewer — and, critically, a ruleset **bypass actor's
> bypass applies only to a *direct* merge, never to auto-merge *into* the queue**,
> so a required review would leave every bot PR stuck `REVIEW_REQUIRED` forever.
> Flip the toggle on once there is a second reviewer.

### `release-pr-automerge.yaml` — auto-merge release-please PRs

**What it does:** on every bot-authored `release-please--*` PR, enables
auto-merge (as the `vitruvian-copybara-sync` App) so the PR flows through the
merge queue on green CI with **no human step**.

**Why it exists:** release-please only *creates/updates* its release PRs —
nothing else enables auto-merge, so without this robot every release PR sits
open indefinitely (and a maintainer has to merge each by hand).

**How it works:** `pull_request`-triggered. A GitHub **App** installation token
(unlike the default `GITHUB_TOKEN`) *does* trigger downstream workflows, and
secrets are available because `release-please--*` branches are in-repo (not a
fork or Dependabot PR — which is why `dependabot-auto-merge.yml` must use
`workflow_run` instead). The job runs `gh pr merge --squash --auto`; the merge
queue does the rest.

#### ⚠️ Holding a release PR

By default **every** `release-please--*` PR auto-merges on green CI — including
**deploy-triggering** phase releases (e.g. `gcp-*`, `org-folders`) and
**breaking majors** that need a coordinated cut. To hold one for a maintainer to
handle deliberately, do **either**:

- add the **`do-not-automerge`** label, **or**
- leave the PR a **draft**.

The workflow skips both. To release a held PR back into the auto-merge flow,
**remove the label** (and mark it ready if it was a draft) — the `unlabeled` /
`ready_for_review` events re-trigger the workflow.

### `dependabot-auto-merge.yml` — auto-merge Dependabot minor/patch PRs

The same idea for Dependabot's grouped `*-minor-patch` PRs, but triggered on
`workflow_run` after CI completes (Dependabot PRs run with restricted secrets on
`pull_request`, so it waits for CI in the default-branch context, then enables
auto-merge as the App). **Major** bumps are never auto-merged — they land as a
single PR for deliberate review.
