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

```bash
B=//infrastructure/pulumi/foundation
# stage 4 (projects) — per env
for env in development nonproduction production; do
  bazel run $B/gcp-projects:destroy -- --stack $env --yes
done
# stage 3 (networks) — per env (+ shared, if present after refactor)
for env in development nonproduction production; do
  bazel run $B/gcp-networks:destroy -- --stack $env --yes
done
# stage 2 (environments) — per env
for env in development nonproduction production; do
  bazel run $B/gcp-environments:destroy -- --stack $env --yes
done
# stage 1 (org)
bazel run $B/gcp-org:destroy -- --stack production --yes
# stage 0 (bootstrap) — LAST (holds the seed/cicd projects + WIF)
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

## Step 3 — Redeploy the refactored stages (bottom-up)

```bash
B=//infrastructure/pulumi/foundation
# 0-bootstrap first (recreates seed/cicd projects + WIF that later CI previews need)
bazel run $B/gcp-bootstrap:up -- --stack production --yes
# 1-org
bazel run $B/gcp-org:up -- --stack shared --yes         # (shared stack after refactor; was 'production')
# 2-environments
for env in development nonproduction production; do bazel run $B/gcp-environments:up -- --stack $env --yes; done
# 3-networks (+ shared for the DNS hub)
bazel run $B/gcp-networks:up -- --stack shared --yes
for env in development nonproduction production; do bazel run $B/gcp-networks:up -- --stack $env --yes; done
# 4-projects (+ shared for the infra-pipeline)
bazel run $B/gcp-projects:up -- --stack shared --yes
for env in development nonproduction production; do bazel run $B/gcp-projects:up -- --stack $env --yes; done
# 5-app-infra (new)
bazel run $B/gcp-app-infra:up -- --stack shared --yes
for env in development nonproduction production; do bazel run $B/gcp-app-infra:up -- --stack $env --yes; done
```

**Preview before each apply** (`:preview -- --stack <env> --diff`) — the refactor is code-only-verified
(build/test); a preview against the (now empty) stacks should be all-creates. Sanity-check the plan before
`:up`.

## Step 4 — Reconcile downstream references

- StackReference names may change if stack names change (e.g. `foundation-org/production` → `.../shared`).
  Update consumers (`gcp-environments` reads org; `gcp-networks`/`gcp-projects` read env/net; `gcp-app-infra`
  reads projects/bootstrap) to the new stack refs.
- `repo_config` publishes the WIF vars to GitHub Environments — re-run its apply if the pool/provider names
  changed.

> Stack-name changes (`production` → `shared`) are the main coordination point; keep them consistent across a
> stage's exports and its consumers' StackReferences.
