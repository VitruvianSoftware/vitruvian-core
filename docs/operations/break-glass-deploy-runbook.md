# Break-glass deploy (when GitHub Actions is unavailable)

> **This is the escape hatch, not the normal path.** The authoritative deploy path is push → GitHub Actions (apps + foundation) and git → ArgoCD (cluster). A stack that can *only* be applied by hand is unfinished (`docs/engineering/application-development-principles.md` §2.2/§2.14). Use this **only** when Actions is down (confirm at <https://www.githubstatus.com>), then **reconcile back to the pipeline** (last section).

> **Two tiers of fallback.** `docs/engineering/deployment-strategy.md` covers the lighter one — when Actions is *up* but the release path didn't fire, promote a single environment with `.github/workflows/delivery.yaml`'s `workflow_dispatch` (`unit` + `environment` inputs). **This runbook is the deeper tier:** Actions itself is unavailable, so you deploy entirely from a workstation.

> **Drafted from the CI workflows; not yet battle-tested.** These steps mirror `_deploy-cloud-run.yaml`, the GENERATED `delivery.yaml` (which replaced the per-app `<app>-deploy.yaml` callers — delivery-orchestrator Phase 3), and `foundation-*-deploy.yaml`. The deploy workflows change often — **re-derive from the current workflow if it has moved**, and treat anything tagged **VERIFY** as check-live, not copy-blind. Before trusting this in an incident, rehearse Step 1 on `development` and stop at `pulumi preview`.

## Scope

1. **App hotfix** — `tabula` and `oauth-user-inspector`, via Cloud Run blue-green. Both now use the **same** model: build the image once, promote the **immutable digest** through each env.
2. **Foundation stage** — `gcp-projects` / `gcp-networks`.

**Not covered:** cluster / GitOps changes — that's ArgoCD reconciling from git, a separate failure domain that an Actions outage does not stop.

## Prerequisite — tools + auth

**Tools:** `gcloud`, `pulumi`, `bazel`, `docker` + `buildx`, `jq`, `git`, and headless Chrome (oauth smoke). Work from a **branch or worktree — never a detached HEAD** (the bazel wrapper refuses one), on the commit carrying the fix. Every `pulumi`/migrate command needs `export GOWORK=off` (the app/foundation Go modules sit outside the repo-root `go.work`).

**Auth — you cannot use CI's keyless WIF, but the pulumi wrapper is ambient-auth-first (#1119),** so hand it any GCP credential in the environment and every `bazel run …:up`/`:deploy` uses it:

- **Simplest break-glass:** `export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token)"`. The wrapper honors an ambient token, so you do **not** need an interactive `gcloud auth login` (which can't run in a non-interactive shell). This runs as your ADC identity.
- **Or a pinned login:** `gcloud auth login james@vitruviansoftware.dev` — with no ambient token set, the wrapper mints one from the account pinned for the project dir in `infrastructure/gcp-identities.tsv` (expires ~hourly).
  > **VERIFY (before an incident):** app deploys run as your human identity — the app deploy SAs grant you no `serviceAccountTokenCreator`, so you can't impersonate them. That works only if you already hold `run.admin` + `iam.serviceAccountUser` (on the runtime SA) + `secretAccessor` on the target project.
- **Foundation org custom-role ops** (which `james@` can't do — has `organizationAdmin`, not `organizationRoleAdmin`): impersonate the stage SA and hand the wrapper that token — `export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token --impersonate-service-account=sa-terraform-<stage>@<seed>)"` (org-admins hold TokenCreator on the `sa-terraform-*` SAs). Ambient-first means no wrapper bypass is needed.
  > **VERIFY** the seed project id (`prj-b-seed-<suffix>`) live; it changes on redeploy.

## App reference (VERIFY against the app's `<app>-deploy.yaml` — these drift)

| app | `pulumi-dir` | dev project | region | migrations | smoke |
|---|---|---|---|---|---|
| `tabula` (service `tabula-api`) | `tabula/infra/app` | `prj-d-bu2-oss-floating-c3d1` | `us-central1` | **yes** (`--phase expand`) | `GET /health` |
| `oauth-user-inspector` | `oauth-user-inspector/infra/app` | `prj-d-bu1-oss-floating-648a` | `us-central1` | no | `GET /` + DOM mount check |

Nonproduction / production use `prj-n-…` / `prj-p-…` projects (same suffix scheme) — **VERIFY suffixes live**. Both apps fetch `CLOUDFLARE_API_TOKEN` at deploy time (customDomain grey-cloud DNS).

## Step 1 — App hotfix (build once → deploy per env)

Each app has a **`:deploy` target** that runs the SAME blue-green rollout (capture stable → candidate at 0% → smoke → promote) CI runs, via `//tools/deploy:cloud-run`. The target does NOT build the image or run migrations — those are prerequisite steps. Add `--dry-run` to any `:deploy` to print the plan first; `--phase candidate` stops before promotion.

```bash
export GOWORK=off
export PULUMI_ACCESS_TOKEN=...
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token)"   # ambient auth (Prerequisite)
# customDomain apps need the Cloudflare token in env for the pulumi step:
export CLOUDFLARE_API_TOKEN="$(gcloud secrets versions access latest --secret=CLOUDFLARE_API_TOKEN --project=<cloudflare-token-secret-project>)"  # VERIFY project
GIT_SHA="$(git rev-parse HEAD)"
```

**tabula** (build → EXPAND migration → deploy; repeat the `:deploy` per env development → nonproduction → production):

```bash
IMAGE="us-central1-docker.pkg.dev/<build-project>/tabula/api"                 # VERIFY build project
bazel run //tabula/api:image_push -- --repository "$IMAGE" --tag "$GIT_SHA"
DIGEST="$IMAGE@$(gcloud artifacts docker images describe "$IMAGE:$GIT_SHA" --format='value(image_summary.digest)')"
# EXPAND migration only (--phase expand refuses any *_contract migration):
bazel build //tabula/api:schema_engine //tabula/api:migrate_deploy_bin
export PRISMA_SCHEMA_ENGINE_BINARY="$PWD/bazel-bin/tabula/api/schema-engine"
export PRISMA_QUERY_ENGINE_LIBRARY="$PWD/tabula/api/prisma/engine-placeholder"
DATABASE_URL="$(gcloud secrets versions access latest --secret=DATABASE_URL --project=prj-d-bu2-oss-floating-c3d1)"; export DATABASE_URL  # VERIFY project
bazel run //tabula/api:migrate_deploy_bin -- --schema tabula/api/prisma/schema.prisma --phase expand
bazel run //tabula/infra/app:deploy -- --env development --project prj-d-bu2-oss-floating-c3d1 --image-digest "$DIGEST"  # VERIFY project
```

**oauth-user-inspector** (build once, promote the SAME digest to every env; no migrations):

```bash
IMAGE="us-central1-docker.pkg.dev/<build-project>/oauth-user-inspector/app"   # VERIFY build project
docker buildx build --push --tag "$IMAGE:$GIT_SHA" oauth-user-inspector/
DIGEST="$IMAGE@$(gcloud artifacts docker images describe "$IMAGE:$GIT_SHA" --format='value(image_summary.digest)')"
bazel run //oauth-user-inspector/infra/app:deploy -- --env development --project prj-d-bu1-oss-floating-648a --image-digest "$DIGEST"  # VERIFY project
```

The `:deploy` target fails closed if a non-first deploy's candidate URL can't be resolved (never false-greens; #808), and promotes only after the smoke passes.

> **Preflight parity.** CI's `tools/ci/tabula-deploy-preflight.sh` skips the whole rollout when the live service already serves this exact digest+config (fail-open). By hand, a re-run just deploys an identical candidate + no-op promote — harmless.

## Step 2 — Foundation stage (`gcp-projects` / `gcp-networks`)

Each **leaf** is a thin Pulumi project with a `:preview` / `:up` target (via `pulumi_project`). Apply in ladder order: `development → nonproduction → shared → production`. There is no aggregate "apply-tier" target yet — run the leaves you need, in order.

```bash
export GOWORK=off
export PULUMI_ACCESS_TOKEN=...
export GITHUB_TOKEN=...            # PAT, so github:// plugin downloads dodge the 60/hr unauth limit
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token)"   # ambient auth (Prerequisite)

# gcp-projects leaf (business_unit_1 | business_unit_2):
LEAF=//infrastructure/pulumi/foundation/gcp-projects/business_unit_1/development
# gcp-networks leaf: //infrastructure/pulumi/foundation/gcp-networks/envs/development
bazel run ${LEAF}:preview          # <-- STOP on unexpected deletes/replaces (see Guardrails)
bazel run ${LEAF}:up
```

> Stages that create a `billing.Budget` under a user credential also need `USER_PROJECT_OVERRIDE=true` + `GOOGLE_BILLING_PROJECT=<seed>`. Org custom-role changes must run with an **impersonated `sa-terraform-<stage>`** token (Prerequisite), never as `james@`.

## Step 3 — Publish a package release (npm / Go) when Actions is down

Releases normally flow: `release-please` bumps the manifest → `//tools/copybara/sync` exports the bump to the mirror → the mirror's workflow tags + publishes. With Actions down, do the last step by hand. **Always export first** so the mirror has the bumped code + manifest:

```bash
bazel run //tools/copybara/sync -- export <component>     # push the bump to the mirror
```

**npm packages + Go modules** (mcp-slack, and the pulumi-library `ts/packages/*` + `go/pkg/*`) — one tool, dry-run by default:

```bash
bazel run //tools/release:publish-local -- pulumi-library            # dry run: prints the plan
bazel run //tools/release:publish-local -- pulumi-library --execute  # publish (npm + slash-form go tags)
bazel run //tools/release:publish-local -- mcp-slack --execute
#   --package <name> limits to one; already-published versions/tags are skipped.
```

On the first `--execute` it **prompts you** for the npm token (a `@vitruviansoftware` automation token — the only publish cred with no local equivalent), stores it, backs it up to Bitwarden, and reuses it thereafter — no pre-setup, no hunting. GitHub-side auth is your `gh auth token`. Go-module "publishing" is just the tag `go/pkg/<name>/vX.Y.Z` (**slash** before the version — a dash is `go get`'s "unknown revision"; the tool enforces it, guarded by a test).

**Go binaries** (devx, homelab) and **nexus-agent** (macOS `.app`/DMG/cask) are Mac/toolchain-bound and stay **manual** — no tool:

```bash
# clone the mirror, tag the release, run GoReleaser (needs gh token with contents:write on the
# mirror AND the homebrew-tap repo). homelab is darwin-only; nexus-agent needs Swift + create-dmg.
git clone https://github.com/VitruvianSoftware/<component>.git && cd <component>
git tag vX.Y.Z && git push origin vX.Y.Z           # nexus-agent: plain vX.Y.Z, NOT nexus-agent-vX
GITHUB_TOKEN="$(gh auth token)" goreleaser release --clean   # devx/homelab; nexus-agent: see its release.yml
```

## Guardrails — do not skip

- **Preview before you apply.** Foundation: `bazel run <leaf>:preview`. Apps: `bazel run <app>/infra/app:deploy -- … --dry-run` (or `--phase candidate` to stop at 0% traffic). If a preview shows **deletes / replaces you did not intend**, **STOP** — almost always the gitignored config is missing (next point). Never apply a destructive plan to fix an outage.
- **The empty-config trap (#1 way to destroy the platform).** A fresh checkout/worktree loads full Pulumi **state** but empty gitignored **config**, so `up` proposes **destroying** everything config-driven. Before any `up`: copy `Pulumi.<stack>.yaml` / `Pulumi.local.yaml` **and** `.env` from your main checkout into the worktree; confirm expected toggles are present.
- **Secrets.** App runtime secrets live in per-app GCP Secret Manager (never on a command line, never committed). Pulumi-stack secrets live in gitignored `Pulumi.<stack>.yaml` — source them, don't invent values.
- **Blue-green.** Candidate at **0% traffic** (`candidate` tag) → **smoke it** → only then promote. **Never** promote an unsmoked revision. Build **once**, promote by **digest**, never a mutable `:tag`.
- **Migrations are EXPAND-only.** `--phase expand` refuses any `*_contract` migration — leave that. **Never** `--phase contract` during a hotfix; contract runs deliberately, *after* the new revision soaks. Don't bypass the `migration-safety` gate.

## Landing the fix (when the merge queue is wedged)

An Actions outage also stalls the **merge queue** — the required checks can't run or report, so a PR can't merge the normal way. Two routes, in order of preference:

1. **Deploy first, merge later.** The `:deploy` targets run off *any* checkout, so ship the fix to prod from your branch now (Step 1) — you don't need it on `main` first. Then reconcile once Actions recovers (below). In an incident this is usually the right move: stop the bleeding, tidy up after.
2. **Admin-merge it.** If it must land on `main` immediately, a repository **admin** can bypass the wedged queue — the merge-queue ruleset lists `RepositoryRole:5` (admin) as a bypass actor. Use `gh pr merge <PR> --admin --squash` or the GitHub UI's *"merge without waiting for requirements"*. The merge is a GitHub API call and does **not** need Actions, so it works during the outage. ⚠️ It **skips every required check** (build, tests, `migration-safety`, license) — so only do it when you've verified the fix locally (`bazel test //...` + the relevant lint), because nothing else will.

## After Actions recovers — reconcile

A manual `pulumi up` updates Pulumi state, but the pipeline is still the source of truth:

1. **Merge the fix commit to main** — a manual deploy off an unmerged branch strands the change ("pushed" ≠ "in main"). Verify: `git merge-base --is-ancestor <sha> origin/main`. If you **admin-merged** during the outage, the required checks were skipped — re-run them on that commit (or confirm the next PR's checks are green) so `main` is actually proven.
2. **Let the normal deploy pipeline run** on that commit and confirm it's a **no-op / green** — proves live == git (no out-of-band drift).
3. **Verify the live effect** — the service serves the fix — not just that the plan applied.
