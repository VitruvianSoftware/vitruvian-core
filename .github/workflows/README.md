# GitHub Actions workflows

Reference for the non-obvious automation in this directory. For CI/CD
*terminology*, see [`../CI_DEFINITIONS.md`](../CI_DEFINITIONS.md).

## Merge automation

`main` is protected by a **merge queue** (ruleset `merge-queue`, managed as code
in `infrastructure/pulumi/platform/repo-config`): every PR merges through the
queue once the required status checks pass on the queued (speculative) merge
commit. The robots below feed bot-authored PRs into that queue so they don't
sit waiting on a human.

> ℹ️ The merge-queue ruleset can also require a code-owner review, but that is
> gated off by default (`requireCodeOwnerReview` in `repo-config`) because a
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
fork or Dependabot PR — which is why `dependabot-auto-merge.yaml` must use
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

The automated gates hold with labels of their own, never with yours:
`release-beta-gate` uses **`beta-not-built`** and `release-hold` uses
**`dev-deploy-red`**. Each clears only its own label when its condition is
green again, and leaves auto-merge off while your `do-not-automerge` is on.
(Before 2026-10-13 they shared your label, and a green beta cleared a hold a
person had just placed on the 3.43.0 release.) A hold must also turn auto-merge
off: `gh pr merge <n> --disable-auto`; the label alone does not stop a merge
that was already armed.

### `release-scope.yaml` — a pull request says which products it releases

**What it does:** fails a pull request that would make release-please release a
product the pull request does not name. Required in the merge queue (context
`release-scope`).

**Why it exists:** release-please proposes a release of a product whenever a
`feat` or `fix` commit on `main` changes a file in that product's folder, and
`main` is squash-merged, so one pull request is one commit. A pull request for
one product that also changes a file in another's folder releases both, and the
second release has nothing in it: the same code published again under a new
version, or an update offered to every user that changes nothing. It happened
three times on 13 October 2026 (#3193, #3211, #3217).

**How it decides:** by release-please's own rules, with the products read from
the `release-please-config.json` files (the code of `//tools/release-scope`
says which rule comes from which file of release-please's source). A pull
request releases a product when what it lands as has a releasing type (`feat`,
`fix`, `perf`, `revert`, a `!`, a `BREAKING CHANGE` footer) and it changes a
file in the product's folder that is not under one of its `exclude-paths`. It
names a product when the scope is the product's `component` or `package-name`,
or an alias in `tools/release-scope/aliases.json` (`desktop` means `vitruvian`).

**What a pull request lands as:** with more than one commit, its title. With
**one commit, that commit's message**, not the title: that is how GitHub
squashes here. So a one-commit pull request is fixed by changing the commit
(or pushing a second one), not by retitling.

**When it fails**, the log names the product, the files, and three ways out:

1. Split it: the other product's files go in a pull request of their own.
2. If nothing a user gets changes, use a type that does not release: `chore`,
   `ci`, `test`, `docs`, `refactor`, `build`, `style`.
3. If it truly changes each product, say so on a line of its own in the pull
   request's description:

   ```text
   Releases: vitruvian-sdk, vitruvian-tool-github
   ```

   The names are components, as in each `release-please-config.json`.

It runs again when the title or description is edited and when commits are
pushed. release-please's own pull requests and the dependency bots' are left
alone.

### `dependabot-auto-merge.yaml` — auto-merge Dependabot minor/patch PRs

The same idea for Dependabot's grouped `*-minor-patch` PRs, but triggered on
`workflow_run` after CI completes (Dependabot PRs run with restricted secrets on
`pull_request`, so it waits for CI in the default-branch context, then enables
auto-merge as the App). **Major** bumps are never auto-merged — they land as a
single PR for deliberate review.

### `catalog-publish.yaml` and `site-sync-downloads.yaml` — website PRs arm themselves

Each opens or updates one PR that writes into the website (the signed tool
catalog; the downloads list). After pushing, the same step arms auto-merge on
that PR, as the App, at the commit it just pushed (`--match-head-commit`), so
the queue merges it on green CI. Before 2026-10-18 nothing armed them, and they
sat open for hours with green checks.

`tools/ci/site-pr-automerge.sh` does the arming, tested by
`//tools/ci:site_pr_automerge_test`. It turns auto-merge off before each push
and arms again only at the new commit. It does not arm a PR labelled
`do-not-automerge` or `needs-human`, or a draft; it never adds or removes those
labels. A failed arm fails the step, with a warning in the job summary.

## Scheduled checks

### `delivery-drift.yaml` — did every app ship what is on `main`?

Hourly, it asks each delivery unit whether the last commit it delivered still
covers everything on `main` that affects it (`//tools/ci:delivery_drift`). A
skipped delivery looks green in the runs list, so this is the check that can
see one.

**Read its verdict from the `delivery-drift verdict` check run** on the commit
it checked, not from the run's colour:

| Check run | Means | What to do |
|---|---|---|
| success | At least one unit was checked and none is behind. Units it skipped are named in the summary. | Nothing. |
| **neutral** | **Nothing was checked.** Every unit was skipped: no app's workflow had a finished run to judge against, or each was parked on an approval. Not a pass. | Nothing for one. Several in a row means the check is blind: look at why in the summary. |
| failure | A unit is behind `main` (DRIFT), its state is UNKNOWN (a failed API read is never a pass), or the check did not finish. | Read the summary and the job log. |

It never waits for deliveries to finish. Each app's delivery workflow starts
on every push, so on a busy day one is nearly always running. Instead, each
unit is judged up to the newest commit its app's workflow has **finished** a
run for; newer commits are still being delivered, and a later check judges
them. A run cancelled by a newer push is passed over (the newer run carries
its commits). A run that finished with a failure still counts, so a failed
delivery is reported. A run parked on an approval leaves its units not
checked. In the runs list a neutral verdict still shows as a green run,
because Actions has no neutral run; the run page carries a "nothing checked"
notice.
