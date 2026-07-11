# OSS Application Stage — Phase 3 (oauth-user-inspector multi-env) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy `oauth-user-inspector` across dev/nonproduction/production, each landing in its `prj-{env}-bu1-oss-floating` project, built once and promoted by **digest** from a shared Artifact Registry, using the `serverless_space` module and the foundation's `foundation-pool` WIF — retiring the personal-project single-env deployment path (kept running until Phase 4 cutover).

**Architecture:** Evolve the existing `infrastructure/pulumi/apps/oauth-user-inspector{,-deploy-identity}` stacks **in place** (spec §4.1). Add a single shared **build stack** (AR + build identity in the infra-pipeline project). Per-env **identity** stacks federate against the shared `foundation-pool` (the per-app pool `github-actions-dev-1` is removed). Per-env **app** stacks call `serverless_space` and deploy a promoted digest. `zitadel-apps` goes multi-env and writes its clientId/secret into each env's Secret Manager (closing today's manual gap). The app reads secrets under a per-app `SECRET_PREFIX` so multiple OSS apps can co-tenant one oss project.

**Tech Stack:** Pulumi/Go (`pulumi-gcp/sdk/v9`), the published `cloud_run@v0.2.0` primitive + `serverless_space` module, `pulumiverse/pulumi-zitadel`, GitHub Actions (build-once/promote-digest), Bazel `pulumi_project`, Node/TypeScript (server).

## Global Constraints

- **Faithful to upstream**: this is our serverless-specific app-infra; where the pulumi port and upstream terraform diverge, mimic upstream behaviour + document. No shortcuts (reusable building block).
- **`pulumi-gcp` sdk v9** (`v9.29.0`) for all evolved/new Go stacks (the app + deploy-identity stacks are currently **v7.38.0** → bump to v9). Never v7.
- **Build once, promote by digest** — never rebuild per env; the image is referenced by `@sha256:…` digest, not a mutable `:tag`. The legacy `app:<sha>` tag ref and the `imageTag[:7]` revision-suffix truncation are removed.
- **Keyless WIF only** — no SA keys. Deploy identity federates the shared `foundation-pool` (`projects/1007864396578/locations/global/workloadIdentityPools/foundation-pool/providers/foundation-gh-provider`) scoped by `attribute.repository` (repo-pin, Phase 1) **and** `attribute.environment`.
- **Secrets are never committed** — GitHub-side secrets sync via `//tools/sync-env-secrets`; app-runtime secrets live in per-env GCP Secret Manager under the `OAUTH_USER_INSPECTOR_` prefix; deploy identifiers are GitHub Environment **variables** (Phase 1 Task E created the empty envs).
- **Additive/import-safe** — the live `apps/oauth-user-inspector` `development` deployment (personal project) and the live zitadel OIDC client must not be destroyed. `zitadel.ApplicationOidc` must **never** be `pulumi.Import`ed (force-new-replace deletes the live client — recovery runbook, incident 2026-06-26).
- Every added/moved `.go` file → `bazel run //:gazelle` before push. All Go ops `GOWORK=off`.
- **Live oss project ids** (StackReference `ipv1337/foundation-projects/{env}` outputs `oss_floating_project` / `oss_floating_project_number`):
  - dev `prj-d-bu1-oss-floating-2ad6`, nonprod `prj-n-bu1-oss-floating-cf11`, prod `prj-p-bu1-oss-floating-8e16` (number `318188220164`).
  - Shared build project: `prj-c-bu1-infra-pipeline-f4cb` (export `infra_pipeline_project_id` from `ipv1337/foundation-projects/production`).

---

## Ordering / sequencing

```
Task 1 (build stack)  ─┐
Task 2 (SECRET_PREFIX) ─┼─ independent, land first
                        │
Task 3 (identity) ← needs build project (service-agent grants target oss projects; identity needs foundation-pool)
Task 4 (app)      ← needs Task 1 AR + Task 3 SAs + published serverless_space/cloud_run
Task 5 (zitadel)  ← needs per-env oss projects (Secret Manager targets); independent of 3/4 but its secrets feed Task 4's runtime
Task 6 (CI)       ← needs 1,3,4 (wires build-once → per-env deploy)
Task 7 (identities.tsv + BUILD + gitignore) ← folded into 1/3/4 as each stack is created
```
Apply order per env: **build (once) → identity → zitadel (mint client + write secrets) → app**. Env order: **dev → nonproduction → production** (prod gated by its GitHub Environment reviewer).

---

## Task 1: Shared build stack (`apps/oauth-user-inspector-build/`)

**Files:**
- Create: `infrastructure/pulumi/apps/oauth-user-inspector-build/{main.go,Pulumi.yaml,Pulumi.production.yaml,go.mod,go.sum,BUILD}`
- Modify: `infrastructure/pulumi/.gitignore` (allowlist `!apps/oauth-user-inspector-build/Pulumi.*.yaml`)
- Modify: `infrastructure/gcp-identities.tsv` (row for the build stack)

**Interfaces:**
- Produces exports: `artifact_registry` (`<region>-docker.pkg.dev/<build-proj>/oauth-user-inspector`), `build_service_account` (email), `build_wif_provider`.
- Consumed by: Task 4 (app pulls the digest from this AR), Task 6 (CI build job authenticates as the build SA, pushes by digest).

Single stack (not per-env), `Pulumi.production.yaml` only — it owns cross-env singletons in the shared infra-pipeline project (same rationale as gcp-projects `infra_pipeline_enabled` being prod-only). Config: `build_project` (StackReference `ipv1337/foundation-projects/production` → `infra_pipeline_project_id`), `region: us-west1`, `repository: VitruvianSoftware/vitruvian-core`, and the three env oss project numbers (StackRef per env → `oss_floating_project_number`) for the Cloud Run service-agent AR-reader grants.

- [ ] **Step 1: Scaffold go.mod (sdk v9 + cloud_run pin) + BUILD + Pulumi.yaml**

`Pulumi.yaml` name `pulumi_oauth_user_inspector_build`. `go.mod` requires `github.com/pulumi/pulumi-gcp/sdk/v9 v9.29.0`, `github.com/pulumi/pulumi/sdk/v3 v3.251.0`. `BUILD`:
```python
load("//tools/pulumi:defs.bzl", "pulumi_project")
pulumi_project(name = "oauth-user-inspector-build", dir = "infrastructure/pulumi/apps/oauth-user-inspector-build")
```

- [ ] **Step 2: main.go — AR repo + build SA + WIF binding + service-agent AR-reader grants**

```go
package main

import (
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/artifactregistry"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := config.New(ctx, "oauth-user-inspector-build")
		region := cfg.Get("region")
		if region == "" { region = "us-west1" }
		repo := cfg.Get("repository")
		if repo == "" { repo = "VitruvianSoftware/vitruvian-core" }

		projStack, err := pulumi.NewStackReference(ctx, "projects-prod",
			&pulumi.StackReferenceArgs{Name: pulumi.String("ipv1337/foundation-projects/production")})
		if err != nil { return err }
		buildProject := projStack.GetStringOutput(pulumi.String("infra_pipeline_project_id"))

		// 1. Shared Artifact Registry for the app image (build once, promote digest).
		ar, err := artifactregistry.NewRepository(ctx, "oauth-user-inspector-images", &artifactregistry.RepositoryArgs{
			Project:      buildProject,
			Location:     pulumi.String(region),
			RepositoryId: pulumi.String("oauth-user-inspector"),
			Format:       pulumi.String("DOCKER"),
			Description:  pulumi.String("oauth-user-inspector container images (build-once, promoted by digest)"),
		})
		if err != nil { return err }

		// 2. Build identity: pushes images to the AR. Federated per Task 6 (build env).
		buildSA, err := serviceaccount.NewAccount(ctx, "build-sa", &serviceaccount.AccountArgs{
			Project:     buildProject,
			AccountId:   pulumi.String("oauth-user-inspector-build"),
			DisplayName: pulumi.String("oauth-user-inspector image build/push"),
		})
		if err != nil { return err }
		if _, err := artifactregistry.NewRepositoryIamMember(ctx, "build-sa-ar-writer", &artifactregistry.RepositoryIamMemberArgs{
			Project:    buildProject,
			Location:   pulumi.String(region),
			Repository: ar.RepositoryId,
			Role:       pulumi.String("roles/artifactregistry.writer"),
			Member:     pulumi.Sprintf("serviceAccount:%s", buildSA.Email),
		}); err != nil { return err }

		// 3. Per-env Cloud Run service agent AR reader: each env's oss project's Cloud
		//    Run service agent (service-<projnum>@serverless-robot-prod.iam...) must pull
		//    from the shared AR. Reads oss project numbers per env via StackReference.
		for _, env := range []string{"development", "nonproduction", "production"} {
			s, err := pulumi.NewStackReference(ctx, "projects-"+env,
				&pulumi.StackReferenceArgs{Name: pulumi.String("ipv1337/foundation-projects/" + env)})
			if err != nil { return err }
			num := s.GetStringOutput(pulumi.String("oss_floating_project_number"))
			if _, err := artifactregistry.NewRepositoryIamMember(ctx, "ar-reader-"+env, &artifactregistry.RepositoryIamMemberArgs{
				Project:    buildProject,
				Location:   pulumi.String(region),
				Repository: ar.RepositoryId,
				Role:       pulumi.String("roles/artifactregistry.reader"),
				Member:     pulumi.Sprintf("serviceAccount:service-%s@serverless-robot-prod.iam.gserviceaccount.com", num),
			}); err != nil { return err }
		}

		ctx.Export("artifact_registry", pulumi.Sprintf("%s-docker.pkg.dev/%s/oauth-user-inspector", region, buildProject))
		ctx.Export("build_service_account", buildSA.Email)
		return nil
	})
}
```

- [ ] **Step 3: gcp-identities.tsv row** — add (space-aligned to match the file), account `james@vitruviansoftware.dev`, project `-` (StackRef-driven; set to `prj-c-bu1-infra-pipeline-f4cb` if a quota project is needed):
  `infrastructure/pulumi/apps/oauth-user-inspector-build   james@vitruviansoftware.dev   prj-c-bu1-infra-pipeline-f4cb   oauth-user-inspector shared AR + build identity (infra-pipeline project)`
- [ ] **Step 4: build/vet + preview** — `( cd infrastructure/pulumi/apps/oauth-user-inspector-build && GOWORK=off go mod tidy && GOWORK=off go build ./... && GOWORK=off go vet ./... )` then `bazel run //:gazelle`, then `bazel run //infrastructure/pulumi/apps/oauth-user-inspector-build:preview -- --stack production --diff`. Expect: AR repo + build SA + 1 AR-writer + 3 AR-reader IAM = all creates, zero deletes.
- [ ] **Step 5: Commit + PR.** Gate: James merge + apply (as `sa-terraform-proj`). Record `build_service_account` for Task 3/6.

## Task 2: `SECRET_PREFIX` server change (`oauth-user-inspector/server/server.ts`)

**Files:**
- Modify: `oauth-user-inspector/server/server.ts` (`getSecret` path + cache key)
- Test: `oauth-user-inspector/server/server.<test>.ts` (co-located test; match the repo's existing server test file naming)

**Interfaces:**
- Consumes: `process.env.SECRET_PREFIX` (empty string default — backward compatible with the personal-project deployment which has bare secret names).
- Produces: secret reads at `projects/<GOOGLE_CLOUD_PROJECT>/secrets/<SECRET_PREFIX><name>/versions/latest`.

- [ ] **Step 1: Write the failing test** — assert `getSecret("GITHUB_APP_OAUTH_CLIENT_ID")` requests `.../secrets/OAUTH_USER_INSPECTOR_GITHUB_APP_OAUTH_CLIENT_ID/versions/latest` when `SECRET_PREFIX=OAUTH_USER_INSPECTOR_`, and the bare name when `SECRET_PREFIX` is unset. Mock `secretManagerClient.accessSecretVersion` and assert on the `name` arg. Also assert the TTL cache keys on the **prefixed** id (so two apps sharing a project don't collide).
- [ ] **Step 2: Run it — FAIL** (`SECRET_PREFIX` not yet applied).
- [ ] **Step 3: Implement** — in `getSecret` (server.ts ~70–108):
  ```ts
  const prefix = process.env.SECRET_PREFIX ?? "";
  const fullName = `${prefix}${secretName}`;
  // cache key = fullName (not secretName)
  const name = `projects/${projectId}/secrets/${fullName}/versions/latest`;
  ```
  Keep `GOOGLE_CLOUD_PROJECT || GCP_PROJECT` project resolution unchanged.
- [ ] **Step 4: Run test — PASS.**
- [ ] **Step 5: Commit.** (Server ships in the image; used once Task 4's app stack injects `SECRET_PREFIX=OAUTH_USER_INSPECTOR_`.)

> The full runtime secret set (per env, prefixed) must exist in each oss project's Secret Manager before the app serves traffic: `OAUTH_USER_INSPECTOR_{GITHUB,GOOGLE,GITLAB,AUTH0,ZITADEL,LINKEDIN}_APP_OAUTH_CLIENT_ID/…_CLIENT_SECRET`, `OAUTH_USER_INSPECTOR_ZITADEL_APP_OAUTH_DOMAIN`, `OAUTH_USER_INSPECTOR_AUTH0_APP_OAUTH_DOMAIN`. Zitadel client id/secret are written by Task 5; the rest are synced via `//tools/sync-env-secrets` (documented, not committed). A real-secret smoke (Task 6 Phase-2) verifies at least the zitadel path resolves.

## Task 3: Per-env identity stacks (`apps/oauth-user-inspector-deploy-identity/`) — retire per-app pool

**Files:**
- Rewrite: `infrastructure/pulumi/apps/oauth-user-inspector-deploy-identity/main.go` (v7→v9; remove pool/provider; foundation-pool binding; per-app IAM)
- Create: `Pulumi.{development,nonproduction,production}.yaml` (replace the lone dev config)
- Modify: its `go.mod` (sdk v9), `gcp-identities.tsv` (per-env rows or a single StackRef-driven row)

**Interfaces:**
- Consumes: `foundation-pool` full name (bootstrap StackReference `ipv1337/foundation-bootstrap/production` → the WIF pool name/id) + the env's oss project id (StackRef `ipv1337/foundation-projects/{env}` → `oss_floating_project`) + build SA email (Task 1).
- Produces exports: `deployServiceAccount`, `runtimeServiceAccount` (consumed by Task 4 app config + Task 6 env vars).

- [ ] **Step 1: Remove the per-app WIF pool + provider** (main.go:59–84). The deploy identity now federates the **shared** `foundation-pool`; no new pool/provider is created here.
- [ ] **Step 2: Per-env SAs in the oss project** — `deploy-sa` (`AccountId: oauth-user-inspector-deploy`) + `runtime-sa` (`AccountId: oauth-user-inspector-rt`), both `Project: ossProjectID`. (Names are per-app to allow co-tenant apps; drop the dev-named `github-actions-dev`/`oauth-user-inspector` ids.)
- [ ] **Step 3: Env-scoped foundation-pool binding (deploy SA only)** — grant the deploy SA `roles/iam.workloadIdentityUser` for the principalSet scoped to **both** the repo and the environment, so only the `oauth-user-inspector-<env>` GitHub Environment can impersonate it:
  ```go
  Member: pulumi.Sprintf(
    "principalSet://iam.googleapis.com/%s/attribute.repository/%s",
    foundationPoolName, "VitruvianSoftware/vitruvian-core"),
  ```
  (Repository scoping matches the foundation's `attribute.repository`; the GitHub Environment gate + per-env deploy SA give env isolation. If finer WIF `attribute.environment` scoping is enabled on the foundation provider, use `attribute.environment/<env>` — mirror whatever `gcp-bootstrap` exposes; do NOT invent a new attribute.)
- [ ] **Step 4: Per-app least-priv IAM (spec §8)** — grant the deploy SA, **scoped to the oss project**: `roles/run.admin`, `roles/iam.serviceAccountUser` (to act as the runtime SA), `roles/serviceusage.serviceUsageConsumer`, `roles/logging.viewer`. Grant the runtime SA `roles/secretmanager.secretAccessor` — but **condition it to this app's secret prefix** where feasible (IAM condition on `resource.name.startsWith("projects/<num>/secrets/OAUTH_USER_INSPECTOR_")`) so a co-tenant app can't read another's secrets. Drop `roles/artifactregistry.admin` (the app no longer owns an AR — it pulls the shared one; the AR-reader grant lives in Task 1).
- [ ] **Step 5: Per-env config files** — each sets `project: <oss project id>`, `region: us-west1`, `foundation_pool_stack: ipv1337/foundation-bootstrap/production`, `projects_stack: ipv1337/foundation-projects/<env>`.
- [ ] **Step 6: go.mod v9 + gazelle + build/vet + preview (dev)** — `bazel run //infrastructure/pulumi/apps/oauth-user-inspector-deploy-identity:preview -- --stack development --diff`. Expect: the OLD dev deployment (personal project pool/SAs) shows as **replaced/deleted** ONLY on the personal-project stack — since we are moving to a NEW oss-project stack, prefer creating fresh per-env stacks and leaving the personal `development` stack untouched until Phase-4 cutover. **Decision point (confirm in review):** cut brand-new per-env stacks (dev/nonprod/prod on oss projects) and retire the personal one in Phase 4, vs. repoint the existing dev stack now. Default: new stacks, retire later — zero disruption to the live demo.
- [ ] **Step 7: Commit + PR.** Gate: James merge + apply (`sa-terraform-proj`). **This is the WIF-touching change** approved 2026-07-10.

## Task 4: Per-env app stacks (`apps/oauth-user-inspector/`) — serverless_space + digest

**Files:**
- Rewrite: `infrastructure/pulumi/apps/oauth-user-inspector/main.go` (v7→v9; consume `serverless_space`; digest image; oss-project config)
- Modify: `Pulumi.{development,nonproduction,production}.yaml` (repoint to oss projects)
- Modify: `go.mod` (sdk v9 + `serverless_space` is an example module, so the app consumes the **published `cloud_run@v0.2.0`** directly for the Cloud Run primitive; `serverless_space` lives in `pulumi/examples` and is not published — the live app composes `pkg/cloud_run` + its own SA/invoker inline, mirroring `serverless_space`'s shape). See note below.

> **serverless_space vs the live app:** `serverless_space` is the *reference* module in the example tree (Phase 2). The live app stack is not an example, so it consumes the published **`pkg/cloud_run`** primitive and reproduces `serverless_space`'s composition (runtime SA lookup + SECRET_PREFIX env + secret env + optional allUsers invoker) inline. This keeps the live app on published pins (no dependency on the example tree) while staying behaviourally identical to the reference module.

**Interfaces:**
- Consumes: StackRef `ipv1337/foundation-projects/{env}` (`oss_floating_project`, `oss_floating_project_number`), the build stack's AR + the promoted **digest** (via `OAUTH_USER_INSPECTOR_IMAGE_DIGEST` env / `imageDigest` config), the identity stack's `runtimeServiceAccount`.
- Produces exports: `serviceUrl`, `serviceAccount`.

- [ ] **Step 1: Replace the AR-repo creation** — the app no longer creates `oauth-user-inspector-images` (Task 1 owns it). Remove the `artifactregistry.NewRepository` + its import.
- [ ] **Step 2: Digest image ref** — replace `image := Sprintf("%s-docker.pkg.dev/%s/oauth-user-inspector/app:%s", region, project, imageTag)` with a **digest**:
  ```go
  imageDigest := envOrConfig("OAUTH_USER_INSPECTOR_IMAGE_DIGEST", cfg, "imageDigest") // <build-AR>/app@sha256:...
  ```
  Remove `imageTag`, `imageTag[:7]` revision-suffix truncation. Revision suffix derives from the digest's short hash (`strings.TrimPrefix(...":sha256:")[:8]`), computed in Go from the digest string.
- [ ] **Step 3: Compose cloud_run + invoker** — build the service via `cloud_run.NewCloudRun` (published `v0.2.0`): `Image: imageDigest`, `ServiceAccountEmail: runtimeSA`, `Env: {NODE_ENV:"production", GOOGLE_CLOUD_PROJECT:<oss project>, SECRET_PREFIX:"OAUTH_USER_INSPECTOR_"}`, `MaxInstances:10`, `Port:8080`. Then the `allUsers` `run.invoker` binding (relies on Phase-1 #867 DRS override). Keep the blue-green promote/stableRevision logic (it operates on revisions, digest-agnostic).
- [ ] **Step 4: Per-env config** — each `Pulumi.<env>.yaml`: `project: <oss project id>`, `region: us-west1`, `environment: <env>`, `runtimeServiceAccount: oauth-user-inspector-rt@<oss project>.iam.gserviceaccount.com`. Remove the personal-project `gcp:project`.
- [ ] **Step 5: go.mod (v9 + cloud_run pin) + gazelle + build/vet + preview** per env against the oss projects. Expect creates (new stacks) — no destruction of the live personal-project `development` stack (new stack names/projects).
- [ ] **Step 6: Commit + PR.** Gate: James merge + apply (per-env **deploy SA** via CI, dev→nonprod→prod).

## Task 5: `zitadel-apps` multi-env + cred-sync-to-GCP-SM

**Files:**
- Modify: `infrastructure/pulumi/platform/zitadel-apps/main.go` (write clientId/secret to each env's Secret Manager)
- Create: `Pulumi.{nonproduction,production}.yaml` (per-env redirect URIs; dev exists)

**Interfaces:**
- Consumes: the env's oss project id + number (StackRef) for the deterministic Cloud Run host + the Secret Manager target project.
- Produces: `ZITADEL_APP_OAUTH_CLIENT_ID` / `ZITADEL_APP_OAUTH_CLIENT_SECRET` **written to** `projects/<oss project>/secrets/OAUTH_USER_INSPECTOR_ZITADEL_APP_OAUTH_CLIENT_ID` (+ `_SECRET`), version `latest`.

- [ ] **Step 1: Close the cred-sync gap** — after `zitadel.NewApplicationOidc`, create `secretmanager.NewSecret` + `secretmanager.NewSecretVersion` for the client id and secret in the oss project, named with the `OAUTH_USER_INSPECTOR_` prefix:
  ```go
  for _, s := range []struct{ id string; val pulumi.StringOutput }{
    {"OAUTH_USER_INSPECTOR_ZITADEL_APP_OAUTH_CLIENT_ID", app.ClientId},
    {"OAUTH_USER_INSPECTOR_ZITADEL_APP_OAUTH_CLIENT_SECRET", app.ClientSecret},
  } {
    sec, err := secretmanager.NewSecret(ctx, s.id, &secretmanager.SecretArgs{
      Project: ossProjectID, SecretId: pulumi.String(s.id),
      Replication: &secretmanager.SecretReplicationArgs{Auto: &secretmanager.SecretReplicationAutoArgs{}},
    })
    if err != nil { return err }
    if _, err := secretmanager.NewSecretVersion(ctx, s.id+"-v", &secretmanager.SecretVersionArgs{
      Secret: sec.Id, SecretData: s.val, // clientSecret is a Pulumi secret output — stays encrypted in state
    }); err != nil { return err }
  }
  ```
  (`sa-terraform-proj` gained `roles/secretmanager.admin` on the folder in Phase 1 Task B, so it can create these.) **Do NOT** `pulumi.Import` the `ApplicationOidc` — creating a per-env client is correct (the personal-project client is a separate stack, untouched).
- [ ] **Step 2: Per-env redirect URIs** — derive from the env's deterministic Cloud Run host. The current dev config hardcodes `oauth-user-inspector-rwwbf2knaa-uw.a.run.app`; per env the host is `oauth-user-inspector-<env>-<projnum-hash>-uw.a.run.app`. Since the exact hash isn't known until first deploy, set the redirect URIs in a **second apply** after Task 4's first deploy exports `serviceUrl` (or read `serviceUrl` via StackRef `ipv1337/oauth-user-inspector/<env>` once it exists). Keep `https://oauth-inspector.ipv1337.dev/` + `http://localhost:8080/` in all envs.
- [ ] **Step 3: build/vet + preview per env** (dev first). Expect: +2 Secret + 2 SecretVersion per env, the OIDC app create; zero deletes on the existing personal client.
- [ ] **Step 4: Commit + PR.** Gate: James merge + apply. (zitadel-infra job runs over the tailnet to reach the IdP — see Task 6.)

## Task 6: CI — build-once / promote-digest + multi-env wiring

**Files:**
- Modify: `.github/workflows/_deploy-cloud-run.yaml` (accept a pre-built **digest**; drop per-env rebuild)
- Modify: `.github/workflows/oauth-user-inspector-deploy.yaml` (build-once job → per-env deploy fan-out; dev auto, nonprod/prod gated; multi-env dispatch)
- Modify: `infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml` (populate the nonprod/prod/build `oauthVars` Phase-1 Task E left empty)

**Interfaces:**
- The build job authenticates as Task 1's **build SA** (build env), builds once, pushes to the shared AR, and outputs the **digest** (`docker buildx --push` → `.digest`, or `gcloud artifacts docker images describe --format='value(image_summary.digest)'`).
- Each env deploy job passes `OAUTH_USER_INSPECTOR_IMAGE_DIGEST=<AR>/app@<digest>` to the Pulumi app stack (Task 4), promoting the identical artifact.

- [ ] **Step 1: Build-once job** — new `build` job in `oauth-user-inspector-deploy.yaml`: `environment: oauth-user-inspector-build`, WIF-auth as the build SA (its env vars, Phase-1 Task E `build` env — populate in Step 4), `docker buildx build --push -t <AR>/app:<sha> -t <AR>/app:latest`, capture the **digest** as a job output.
- [ ] **Step 2: `_deploy-cloud-run.yaml` — consume a digest** — add input `image-digest`; when set, skip the build/tag steps and pass `<env-prefix>_IMAGE_DIGEST=<digest>` to Pulumi (instead of `_IMAGE_TAG=$GITHUB_SHA`). Fix the region default: set `GCP_REGION` in each Environment to `us-west1` (the Pulumi config's region) — the workflow's `us-central1` fallback is wrong for this app.
- [ ] **Step 3: Per-env deploy fan-out** — `oauth-user-inspector-deploy.yaml`: `deploy-dev` (needs build, auto), `deploy-nonprod` (needs deploy-dev, `environment: oauth-user-inspector-nonproduction` → reviewer-gated), `deploy-prod` (needs deploy-nonprod, gated). Each calls `_deploy-cloud-run.yaml` with the shared `image-digest` from the build job. The `zitadel-infra` job runs per-env (mint client + write secrets via Task 5) before that env's app deploy. `workflow_dispatch` `environment` choice gains `nonproduction` + `production`.
- [ ] **Step 4: Populate repo_config oauthVars** — set `oauthVars["build"]` (build SA WIF vars: `GCP_PROJECT_ID=prj-c-bu1-infra-pipeline-f4cb`, `GCP_DEPLOY_SERVICE_ACCOUNT=oauth-user-inspector-build@…`, `GCP_WORKLOAD_IDENTITY_PROVIDER=<foundation-pool provider>`) and `oauthVars["nonproduction"]`/`["production"]` (per-env deploy SA `oauth-user-inspector-deploy@prj-{n,p}-bu1-oss-floating-…`, `GCP_PROJECT_ID`, `GCP_REGION=us-west1`, the foundation-pool provider). These are known once Tasks 1+3 apply. repo_config auto-applies on merge.
- [ ] **Step 5: Verify** — actionlint + a dev end-to-end dispatch: build once → deploy-dev → the custom smoke (headless-Chrome "Select a provider") passes against the dev oss-project Cloud Run URL, reading real secrets (zitadel path) from the dev oss project's Secret Manager.
- [ ] **Step 6: Commit + PR.** Gate: James merge.

## Task 7: identities.tsv / BUILD / gitignore (folded into 1, 3, 4)

Handled inline: Task 1 adds the build stack's tsv row + gitignore allowlist + BUILD; Tasks 3/4 already have BUILD + gitignore entries (existing) — add the new per-env `Pulumi.*.yaml` (already allowlisted by `!apps/oauth-user-inspector*/Pulumi.*.yaml`). Remove the stray tracked binaries `apps/oauth-user-inspector/oauth-user-inspector` + `…-deploy-identity/…` if tracked (`git rm --cached`), and add a `.gitignore` rule for the compiled program artifacts.

## Self-Review

- **Spec coverage:** build stack (§4 item 5) → T1; per-env identity + foundation-pool + retire per-app pool (§4 item 6, §4.1) → T3; per-env app + serverless_space shape + digest (§4 item 7) → T4; zitadel multi-env + cred-sync (§4 item 8, §9) → T5; SECRET_PREFIX (§5) → T2; build-once/promote-digest CI (§6, §10) → T6; per-app multi-tenancy IAM (§8) → T3 Step 4; identities/stale configs (§11) → T7.
- **Placeholder scan:** live project ids/numbers/paths are concrete; the one deferred value (per-env Cloud Run host hash for zitadel redirect URIs) is explicitly a second-apply-after-first-deploy, not a placeholder.
- **Type consistency:** `runtimeServiceAccount` naming (`oauth-user-inspector-rt@<oss>`) is consistent across T3 (produces) and T4 (consumes); `OAUTH_USER_INSPECTOR_` prefix consistent across T2 (server), T4 (env), T5 (secret ids), T3 (IAM condition).
- **Open decision (surface in review):** T3 Step 6 — new per-env stacks vs repoint the existing dev stack. Default: new stacks, retire personal in Phase 4.
