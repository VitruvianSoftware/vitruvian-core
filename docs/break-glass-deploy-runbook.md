# Break-glass deploy (when GitHub Actions is unavailable)

> **This is the escape hatch, not the normal path.** The authoritative deploy path is push → GitHub Actions (apps + foundation) and git → ArgoCD (cluster). A stack that can *only* be applied by hand is unfinished (`docs/engineering/application-development-principles.md` §2.2/§2.14). Use this **only** when Actions is down (confirm at <https://www.githubstatus.com>), then **reconcile back to the pipeline** (last section).

> **Two tiers of fallback.** `docs/engineering/deployment-strategy.md` covers the lighter one — when Actions is *up* but the release path didn't fire, promote a single environment with the deploy workflow's `workflow_dispatch`. **This runbook is the deeper tier:** Actions itself is unavailable, so you deploy entirely from a workstation.

> **Drafted from the CI workflows; not yet battle-tested.** These steps mirror `_deploy-cloud-run.yaml`, the `<app>-deploy.yaml` callers, and `foundation-*-deploy.yaml` **as of `main` @ f8279d09**. The deploy workflows change often — **re-derive from the current workflow if it has moved**, and treat anything tagged **VERIFY** as check-live, not copy-blind. Before trusting this in an incident, rehearse Step 1 on `development` and stop at `pulumi preview`.

## Scope

1. **App hotfix** — `tabula` and `oauth-user-inspector`, via Cloud Run blue-green. Both now use the **same** model: build the image once, promote the **immutable digest** through each env.
2. **Foundation stage** — `gcp-projects` / `gcp-networks`.

**Not covered:** cluster / GitOps changes — that's ArgoCD reconciling from git, a separate failure domain that an Actions outage does not stop.

## Prerequisite — tools + auth

**Tools:** `gcloud`, `pulumi`, `bazel`, `docker` + `buildx`, `jq`, `git`, and headless Chrome (oauth smoke). Work from a **branch or worktree — never a detached HEAD** (the bazel wrapper refuses one), on the commit carrying the fix. Every `pulumi`/migrate command needs `export GOWORK=off` (the app/foundation Go modules sit outside the repo-root `go.work`).

**Auth — you cannot use CI's keyless WIF.** GitHub-OIDC WIF has no human equivalent. Local identities:

- **As the pinned human user** — `gcloud auth login <account>` (`james@vitruviansoftware.dev` for foundation + both apps; personal accounts per `infrastructure/gcp-identities.tsv`). The bazel Pulumi wrapper mints a short-lived `GOOGLE_OAUTH_ACCESS_TOKEN` from it (expires ~hourly).
  > **VERIFY (before an incident, not during):** app deploys likely run **as the project-owner human**, because the app deploy SAs grant you no `serviceAccountTokenCreator` (you can't impersonate them). That works only if your user already holds `run.admin` + `iam.serviceAccountUser` (on the runtime SA) + `secretAccessor` on the target project. #1081 changed how the app-infra identity is selected — **confirm the current deploy SA and your rights on it** (`gh api /repos/VitruvianSoftware/vitruvian-core/environments/<env>/variables`) before relying on this.
- **Impersonating a foundation SA** (only when the human 403s — specifically **org custom-role** ops, which `james@` can't do: has `organizationAdmin`, not `organizationRoleAdmin`). Only the foundation `sa-terraform-*` SAs are impersonable by you (org-admins hold TokenCreator). Set `CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=sa-terraform-<stage>@<seed>` and call `pulumi` **directly** (bypass the bazel wrapper, which overwrites the token).
  > **VERIFY** the seed project id — `prj-b-seed-<suffix>` changes on redeploy. Read it from live state; don't hardcode.

## App reference (VERIFY against the app's `<app>-deploy.yaml` — these drift)

| app | `pulumi-dir` | dev project | region | migrations | smoke |
|---|---|---|---|---|---|
| `tabula` (service `tabula-api`) | `tabula/infra/app` | `prj-d-bu2-oss-floating-c3d1` | `us-central1` | **yes** (`--phase expand`) | `GET /health` |
| `oauth-user-inspector` | `oauth-user-inspector/infra/app` | `prj-d-bu1-oss-floating-648a` | `us-west1` | no | `GET /` + DOM mount check |

Nonproduction / production use `prj-n-…` / `prj-p-…` projects (same suffix scheme) — **VERIFY suffixes live**. Both apps fetch `CLOUDFLARE_API_TOKEN` at deploy time (customDomain grey-cloud DNS).

## Step 1 — App hotfix (build once → per-env blue-green)

The reusable `_deploy-cloud-run.yaml` drives both apps. Substitute the table values for `<…>`.

```bash
export GOWORK=off
export PULUMI_ACCESS_TOKEN=...
export GIT_SHA="$(git rev-parse HEAD)"
# auth: gcloud login as the project-owner human (see Prerequisite)

# 1. BUILD ONCE + push to the build project's AR; capture the IMMUTABLE digest.
#    (tabula's image target is //tabula/api:image_push via Bazel; oauth builds a plain Dockerfile.
#     BUILD_PROJECT = the app's *-build GitHub Environment GCP_PROJECT_ID — VERIFY.)
export BUILD_PROJECT=<app-build-project>   BUILD_REGION=<region>
gcloud auth configure-docker "${BUILD_REGION}-docker.pkg.dev" --quiet
IMAGE="${BUILD_REGION}-docker.pkg.dev/${BUILD_PROJECT}/<app>/<image-path>"
# tabula:  bazel run //tabula/api:image_push -- --repository "$IMAGE" --tag "$GIT_SHA" --tag latest
# oauth:   docker buildx build --push --tag "${IMAGE}:${GIT_SHA}" oauth-user-inspector/
DIGEST="$(gcloud artifacts docker images describe "${IMAGE}:${GIT_SHA}" --format='value(image_summary.digest)')"
export IMAGE_DIGEST="${IMAGE}@${DIGEST}"          # this exact ref is promoted to EVERY env

# 2. PROMOTE into an env. Repeat: development → nonproduction → production.
export DEPLOY_ENV=development
export GCP_PROJECT_ID=<dev project from table>    GCP_REGION=<region>
export ENV_PREFIX=<TABULA | OAUTH_USER_INSPECTOR>
cd <pulumi-dir>
pulumi stack select "$DEPLOY_ENV" --create

# 2a. (tabula only) EXPAND migration — backward-compatible only  [from repo root, GOWORK=off]
#   bazel build //tabula/api:schema_engine //tabula/api:migrate_deploy_bin
#   export PRISMA_SCHEMA_ENGINE_BINARY="$PWD/bazel-bin/tabula/api/schema-engine"
#   export PRISMA_QUERY_ENGINE_LIBRARY="$PWD/tabula/api/prisma/engine-placeholder"
#   DATABASE_URL="$(gcloud secrets versions access latest --secret=DATABASE_URL --project="$GCP_PROJECT_ID")"; export DATABASE_URL
#   bazel run //tabula/api:migrate_deploy_bin -- --schema tabula/api/prisma/schema.prisma --phase expand

# 2b. (both apps) Cloudflare token for the customDomain DNS  [VERIFY secret/project in the caller workflow]
export CLOUDFLARE_API_TOKEN="$(gcloud secrets versions access latest --secret=CLOUDFLARE_API_TOKEN --project=<cloudflare-token-secret-project>)"

# 2c. Blue-green phase 1 — candidate at 0% traffic
SVC="<service-name>-${DEPLOY_ENV}"                # e.g. tabula-api-development (env == leaf name)
STABLE="$(gcloud run services describe "$SVC" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" \
  --format='value(status.traffic[0].revisionName)' 2>/dev/null || true)"   # empty => first-ever deploy
export ${ENV_PREFIX}_IMAGE_DIGEST="$IMAGE_DIGEST" ${ENV_PREFIX}_STABLE_REVISION="$STABLE" ${ENV_PREFIX}_PROMOTE=false
pulumi preview --diff        # <-- STOP if this shows unexpected deletes/replaces (see Guardrails)
pulumi up --yes

# 2d. SMOKE the candidate's dedicated tag URL (NOT the live URL, except first-ever deploy)
CAND="$(gcloud run services describe "$SVC" --project "$GCP_PROJECT_ID" --region "$GCP_REGION" --format=json \
  | jq -r '.status.traffic[]? | select(.tag=="candidate") | .url' | head -n1)"
curl --fail --retry 10 --retry-delay 5 --retry-connrefused "${CAND}<smoke path>"
# oauth also DOM-checks the SPA mounts: headless-chrome --dump-dom "$CAND/" | grep -q "Select a provider"

# 2e. Blue-green phase 2 — promote to 100% (re-pin the SAME stable from 2c)
export ${ENV_PREFIX}_IMAGE_DIGEST="$IMAGE_DIGEST" ${ENV_PREFIX}_STABLE_REVISION="$STABLE" ${ENV_PREFIX}_PROMOTE=true
pulumi up --yes
```

> **Preflight parity (optional).** CI runs `tools/ci/tabula-deploy-preflight.sh` and **skips** the whole migrate + blue-green when the live service already serves this exact digest+config (fail-open). Doing it by hand you'll just see a no-op `preview` — safe to proceed.

## Step 2 — Foundation stage (`gcp-projects` / `gcp-networks`)

Each **leaf** is a thin Pulumi project selected by **directory**, one stack named `production` regardless of leaf. Promotion order: `development → nonproduction → shared → production`.

```bash
export GOWORK=off
export PULUMI_ACCESS_TOKEN=...
export GITHUB_TOKEN=...            # PAT, so github:// plugin downloads dodge the 60/hr unauth limit
export BU=business_unit_1          # business_unit_1 | business_unit_2
export ENVIRONMENT=development     # shared | development | nonproduction | production
# auth: gcloud login as james@; for org custom-role ops, impersonate sa-terraform-<stage> (Prerequisite)

cd infrastructure/pulumi/foundation/gcp-projects/${BU}/${ENVIRONMENT}     # gcp-projects
# cd infrastructure/pulumi/foundation/gcp-networks/envs/${ENVIRONMENT}    # gcp-networks (envs/<leaf>)

pulumi stack select -c production
pulumi preview --diff             # <-- STOP on unexpected deletes/replaces
pulumi up --yes
```

> Stages that create a `billing.Budget` under a user credential also need `USER_PROJECT_OVERRIDE=true` + `GOOGLE_BILLING_PROJECT=<seed>`. Org custom-role changes must run **as `sa-terraform-<stage>`**, never as `james@`.

## Guardrails — do not skip

- **`pulumi preview --diff` before every `up`.** If the plan shows **deletes / replaces you did not intend**, **STOP** — almost always the gitignored config is missing (next point). Never `up` a destructive plan to fix an outage.
- **The empty-config trap (#1 way to destroy the platform).** A fresh checkout/worktree loads full Pulumi **state** but empty gitignored **config**, so `up` proposes **destroying** everything config-driven. Before any `up`: copy `Pulumi.<stack>.yaml` / `Pulumi.local.yaml` **and** `.env` from your main checkout into the worktree; confirm expected toggles are present.
- **Secrets.** App runtime secrets live in per-app GCP Secret Manager (never on a command line, never committed). Pulumi-stack secrets live in gitignored `Pulumi.<stack>.yaml` — source them, don't invent values.
- **Blue-green.** Candidate at **0% traffic** (`candidate` tag) → **smoke it** → only then promote. **Never** promote an unsmoked revision. Build **once**, promote by **digest**, never a mutable `:tag`.
- **Migrations are EXPAND-only.** `--phase expand` refuses any `*_contract` migration — leave that. **Never** `--phase contract` during a hotfix; contract runs deliberately, *after* the new revision soaks. Don't bypass the `migration-safety` gate.

## After Actions recovers — reconcile

A manual `pulumi up` updates Pulumi state, but the pipeline is still the source of truth:

1. **Merge the fix commit to main** — a manual deploy off an unmerged branch strands the change ("pushed" ≠ "in main"). Verify: `git merge-base --is-ancestor <sha> origin/main`.
2. **Let the normal deploy pipeline run** on that commit and confirm it's a **no-op / green** — proves live == git (no out-of-band drift).
3. **Verify the live effect** — the service serves the fix — not just that the plan applied.
