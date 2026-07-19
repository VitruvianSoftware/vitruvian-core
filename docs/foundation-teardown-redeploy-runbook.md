# Foundation Teardown + Redeploy Runbook

> Executed **after** the structural refactor lands and after `gcloud auth login james@vitruviansoftware.dev`
> (the foundation identity requires periodic interactive reauth — this runbook cannot run non-interactively).

## Prerequisite: authenticate

```bash
gcloud auth login james@vitruviansoftware.dev          # interactive; satisfies Google reauth
gcloud auth list                                        # confirm james@vitruviansoftware.dev is ACTIVE
export PULUMI_BACKEND_URL=https://api.pulumi.com        # foundation stacks are Pulumi Cloud (ipv1337)
```

Run everything from a **git worktree** on a branch (the bazel guard refuses a detached HEAD).

## Scope + safety

- **Teardown everything under `fldr-foundation-1` EXCEPT `org-folders`** (it owns `fldr-foundation-1`; we
  re-provision under the same folder).
- **NEVER touch `fldr-foundation-0`** (the other, off-limits foundation).
- Foundation is inactive → a clean teardown + fresh provision is intended (no URN preservation needed).

## Step 1 — Teardown (reverse dependency order)

> Upstream-leaf layout: every multi-env stage is a set of thin per-leaf Pulumi
> projects (`envs/<leaf>` or `business_unit_1/<leaf>`), each with a single
> `production` stack — the bazel target is per-leaf, the stack is always
> `production`.

```bash
B=//infrastructure/pulumi/foundation
# stage 4 (projects) — per business-unit leaf (envs first, shared infra-pipeline last)
for leaf in development nonproduction production shared; do
  bazel run $B/gcp-projects/business_unit_1/$leaf:destroy -- --stack production --yes
done
# stage 3 (networks) — spokes first, then the shared hub
for leaf in development nonproduction production shared; do
  bazel run $B/gcp-networks/envs/$leaf:destroy -- --stack production --yes
done
# stage 2 (environments) — per env leaf
for leaf in development nonproduction production; do
  bazel run $B/gcp-environments/envs/$leaf:destroy -- --stack production --yes
done
# stage 1 (org) — single envs/shared leaf
bazel run $B/gcp-org/envs/shared:destroy -- --stack production --yes
# stage 0 (bootstrap) — LAST (holds the seed/cicd projects + WIF); single root
bazel run $B/gcp-bootstrap:destroy -- --stack production --yes

# DO NOT destroy org-folders — it owns fldr-foundation-1.
```

If a destroy stalls on delete-ordering (e.g. transitivity backend-service→MIG→template, or SA-owned
resources), delete the blocking resource by hand in dependency order (gcloud, net-SA impersonation) to
unblock, then re-run — do NOT delete templates Pulumi still tracks (provider 404s and fails the apply).
`pulumi refresh` reconciles drift. (See the network teardown lessons in memory.)

## Step 2 — Verify blast radius

```bash
# fldr-foundation-1 still exists; fldr-foundation-0 untouched
gcloud resource-manager folders list --organization=<ORG_ID> | grep foundation
# org-level IAM (projectCreator / billing.creator) unchanged for fldr-foundation-0 members
gcloud organizations get-iam-policy <ORG_ID> > /tmp/org-iam-after.json
```

## Step 3 — Redeploy the restructured stages (bottom-up, per leaf)

Each leaf is its own Pulumi project with one `production` stack
(`ipv1337/foundation-<stage>-<leaf>/production`); all logic lives in the stage's
shared `modules/` package, so one-project-multi-stack still works for forks that
prefer it — the live tree uses one-stack-per-leaf.

```bash
B=//infrastructure/pulumi/foundation
# 0-bootstrap first (recreates seed/cicd projects + WIF that later CI previews need); single root
bazel run $B/gcp-bootstrap:up -- --stack production --yes
# 1-org — single envs/shared leaf (stack ipv1337/foundation-org-shared/production)
bazel run $B/gcp-org/envs/shared:up -- --stack production --yes
# 2-environments — per env leaf
for leaf in development nonproduction production; do
  bazel run $B/gcp-environments/envs/$leaf:up -- --stack production --yes
done
# 3-networks — the shared hub FIRST, then the spokes
for leaf in shared development nonproduction production; do
  bazel run $B/gcp-networks/envs/$leaf:up -- --stack production --yes
done
# 4-projects — the shared infra-pipeline leaf FIRST, then the env leaves
for leaf in shared development nonproduction production; do
  bazel run $B/gcp-projects/business_unit_1/$leaf:up -- --stack production --yes
done
# 5-app-infra (when the live stage lands; leaf pattern mirrors 4-projects,
# without a shared leaf)
for leaf in development nonproduction production; do
  bazel run $B/gcp-app-infra/business_unit_1/$leaf:up -- --stack production --yes
done
```

**Preview before each apply** (`<leaf>:preview -- --stack production --diff`) — the restructure is
code-only-verified (build/test); a preview against the (now empty) stacks should be all-creates.
Sanity-check the plan before `:up`.

## Step 4 — Reconcile downstream references

- StackReference names follow the per-leaf projects: `ipv1337/foundation-org-shared/production`,
  `ipv1337/foundation-environments-<env>/production`, `ipv1337/foundation-networks-<leaf>/production`,
  `ipv1337/foundation-projects-bu1-<leaf>/production`. Update any consumer still pointing at the old
  flat names (`ipv1337/foundation-{org,environments,networks,projects}/<env>`).
- `repo_config` publishes the WIF vars to GitHub Environments — re-run its apply if the pool/provider names
  changed.

> The project-name changes (flat `foundation-<stage>` + per-env stacks → per-leaf
> `foundation-<stage>-<leaf>` + a single `production` stack) are the main coordination point; keep them
> consistent across a stage's exports and its consumers' StackReferences.
