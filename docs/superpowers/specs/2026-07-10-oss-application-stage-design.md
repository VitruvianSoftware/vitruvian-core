# Design: OSS Application Stage (stage 5 / app-infra) — vitruviansoftware.dev foundation

**Date:** 2026-07-10
**Status:** Design — pending review
**Branch:** `feat/oss-application-stage-spec`
**Reference app:** `oauth-user-inspector` (first serverless OSS app)

## 1. Context & goal

Foundation stages 0–4 are live under `fldr-foundation-1`. Stage 4 (`gcp-projects`) deploys, per env
(development/nonproduction/production), business unit `bu1` with a `-sample-floating` reference project
and a `-oss-floating` project (live dev: `prj-d-bu1-oss-floating-2ad6`) that will **host the monorepo's
open-source applications**. Multiple OSS apps will share each `prj-{env}-bu1-oss-floating` project.

Today `oauth-user-inspector` is deployed **single-env to a personal project** (`gen-lang-client-0352693779`,
owner `james.nguyen@gmail.com`), region `us-west1`, one GitHub Environment, one WIF pool, one deploy/runtime
SA, secrets in one project.

**Goal:** a reusable, no-shortcuts **application stage** that deploys OSS apps across **dev → nonprod → prod**,
each landing in the env's `oss-floating` project, with proper environment isolation, artifact promotion, and
per-app multi-tenancy — using `oauth-user-inspector` as the reference app and the building block for future apps.

## 2. Guiding principles

1. **Upstream-faithful.** When in doubt, match Google's `terraform-example-foundation`. Where we diverge
   (serverless / Cloud Run vs upstream's VM model), we do so deliberately and keep the *module structure*
   faithful. Genuine gaps found in our Pulumi port (`pulumi/examples/go-foundation/*`) are fixed as part of
   this work.
2. **No shortcuts.** Build-once/promote-digest, environment-scoped WIF, per-app least-privilege IAM, prod gated.
3. **Multi-tenant by construction.** Every resource in a shared project is namespaced per app; every grant is
   per-app least-privilege. Isolation is enforced in the shared module, not by convention.

## 3. Architecture — `env_base` + `serverless_space` (upstream-aligned)

Upstream `5-app-infra/main.go` composes local modules: `env_base.DeployEnvBase` (base workload: SA + instance
template + compute instance) plus an application-type module such as `confidential_space.DeployConfidentialSpace`
(TEE VM + attestation WIF), both reusing published library primitives.

We add a **new application-type module, `serverless_space`** — the serverless (Cloud Run) peer to
`confidential_space`. `env_base` and `confidential_space` are untouched (VM/TEE types remain available);
`serverless_space` is a purely **additive** extension, back-ported to the ported example as the reference
serverless app-type.

`serverless_space` (per app, per env) encapsulates the full serverless deployment:
- per-env **deploy** + **runtime** service accounts (in the target oss project);
- **environment-scoped WIF binding** for the **deploy SA only** (never the runtime SA) to the shared
  `foundation-pool`, on `attribute.environment/<app>-<env>`;
- Cloud Run v2 service (`<app>-<env>`) + **opt-in** invoker IAM + secret-env wiring + blue-green traffic
  (candidate 0% → smoke → promote);
- **per-app** Artifact Registry repo reference + per-app secret namespacing;
- **per-app least-privilege IAM** (see §8).

It reuses a published primitive `pkg/cloud_run` (new library module) the way `confidential_space` reuses
`pkg/compute_instance`.

**Two-tier identity (kept, not collapsed):**
- The **identity/base** resources (SAs, WIF binding, per-app IAM) are created by an *identity* apply that runs
  under the **foundation projects identity** `sa-terraform-proj` (it owns the oss projects).
- The **app workload** (Cloud Run + traffic) is deployed under the **per-app-per-env deploy SA** that the
  identity apply created.

## 4. Full stack inventory (~8–10 applies for app #1)

The design is NOT four stacks; write the whole set so nothing is discovered mid-implementation.

**Foundation prerequisites (must land + apply first):**
1. **`gcp-bootstrap`** — WIF repo-pin hardening (§7.1) + (if identity applies use new envs) per-env `proj`
   saMappings; folder-level grants for `sa-terraform-proj` (§7.4). Applies via the foundation release chain.
2. **`gcp-projects`** (stage 4) — per-project API additions, single-stack infra-pipeline enablement,
   `infra_pipeline_project_id` + `oss_floating_project_number` exports, port-bug fix (§7.2). Rides
   release-please dev→nonprod→**prod** (prod approval is on the critical path).
3. **`gcp-org`** — DRS (domain-restricted-sharing) org-policy overrides on the oss projects so `allUsers`
   invoker is permitted (§7.3). Applied by the **org SA** (holds `orgpolicy.policyAdmin`; the proj SA does not).
4. **`repo_config`** — graduate `oauthEnvironment` to the multi-env map-of-maps shape (`oauth-user-inspector-
   {development,nonproduction,production}` + `oauth-user-inspector-build` + preview), import-name-safe (§7.5).

**App deployment stacks (per app; oauth-user-inspector first):**
5. **App shared/build stack** (`apps/oauth-user-inspector-build/`, single, not per-env) — the per-app Artifact
   Registry repo in the infra-pipeline project; the **build SA** (per-repo `artifactregistry.writer`) + its WIF
   binding + `oauth-user-inspector-build` environment; the Cloud Run **service-agent** AR-reader grants for each
   env's oss project (§8). Singletons that must NOT be created per-env.
6. **Per-env identity stacks** (`apps/oauth-user-inspector-deploy-identity/`, `Pulumi.{development,nonproduction,
   production}.yaml`) — per-env deploy + runtime SAs + env-scoped WIF binding (deploy SA only) + per-app
   least-priv IAM. Runs as `sa-terraform-proj`.
7. **Per-env app stacks** (`apps/oauth-user-inspector/`, `Pulumi.{development,nonproduction,production}.yaml`) —
   call `serverless_space`; consume the env's `oss_floating_project`(+number) and the shared build project via
   StackReference to `ipv1337/foundation-projects/{env}`; deploy the promoted **digest**. Runs as the per-env
   deploy SA.
8. **`zitadel-apps`** (multi-env) — per-env OIDC app + redirect URIs (deterministic Cloud Run URL, needs the
   oss project number) + **writes** the clientId/clientSecret into each env's Secret Manager (§9).

**Shared modules / library (built once, reused by all apps):**
9. `pulumi/library/go/pkg/cloud_run` (new published primitive).
10. `serverless_space` module in `pulumi/examples/go-foundation/5-app-infra/modules/serverless_space` (faithful
    reference peer to `env_base`/`confidential_space`), consumed by the live app stacks.

## 5. Application source & the SECRET_PREFIX change

`oauth-user-inspector/server/server.ts` reads secrets by **hardcoded bare names**
(`getSecret("GITHUB_APP_OAUTH_CLIENT_ID")`, …) from `projects/${GOOGLE_CLOUD_PROJECT}/secrets/<name>`.
Per-app secret namespacing (`<app>-<KEY>`, §8) therefore **requires a server change**: `serverless_space`
injects `SECRET_PREFIX=<app>-` (and `GOOGLE_CLOUD_PROJECT=<oss project>`); `getSecret` prepends the prefix.
The current smoke test only asserts the SPA mounts — **add a smoke that exercises a real Secret Manager read**
so broken secret wiring can't pass and promote.

## 6. Artifact promotion — build once, promote the digest

- **Build once** on merge in a dedicated build job (GitHub environment `oauth-user-inspector-build`, build SA),
  push to the **per-app AR repo in the single infra-pipeline project**, and **capture the immutable digest**
  (`buildx --metadata-file` / `imagetools inspect`) as a job output.
- **Deploy the same digest** to dev (auto) → nonprod → prod (each gated). No rebuilds.
- `cloud_run_app`/`serverless_space` takes **separate inputs**: image **digest** (ref uses `@sha256:…`, not
  `:tag`) and a **revision id** = short commit SHA (not `digest[:7]`, which is an illegal revision name).
- **Drop the mutable `:latest` tag** (blocks AR immutable-tags and defeats promotion).
- The runtime SA is NOT the image puller — the Cloud Run **service agent**
  (`service-<PROJECT_NUMBER>@serverless-robot-prod.iam.gserviceaccount.com`) pulls; it needs
  `artifactregistry.reader` on the per-app repo (cross-project), force-created via `projects.ServiceIdentity`
  before the grant (§8).

## 7. Foundation prerequisites (detail)

### 7.1 WIF repo-pin hardening (gcp-bootstrap) — restores upstream's repository scoping
Upstream scopes each CI SA to a **specific repository** (`attribute.repository/<owner>/<repo>`). Our monorepo
adaptation swapped that for `attribute.environment` scoping and dropped the repo pin, so any org repo (incl. our
copybara mirrors) could declare a `…-production` environment and impersonate. Fix: set the provider
`AttributeCondition` to `assertion.repository == 'VitruvianSoftware/vitruvian-core'` (via the existing
`WIFAttributeCondition` override — likely config-only). Optionally also make per-SA bindings composite
(`repository:environment`) for defense-in-depth. This **re-adds upstream's repository pin**, not a deviation.

### 7.2 gcp-projects (stage 4) changes
- **Enable the infra-pipeline project in EXACTLY ONE stack** (production). `deployInfraPipelineProject` has no
  env discriminator + `RandomSuffix` on, so enabling it in all three would create **three** duplicate
  `prj-c-bu1-infra-pipeline-*` projects. Enable in `Pulumi.production.yaml` only; document it. It's a **shared,
  cross-env** project (common folder) — production owns it for lifecycle stability (least likely to be torn
  down). Consequences: (a) it's provisioned by a **one-time** stage-4 prod-approval, then persists and serves
  all envs; (b) the app **build stack** and every env's app stack consume `infra_pipeline_project_id` from the
  **production** projects stack (`ipv1337/foundation-projects/production`), while consuming `oss_floating_project`
  from their **own** env's stack. Faithfulness note: upstream models this as a *shared, once-per-BU* resource
  (not env-owned); enabling-in-one-stack approximates that within our per-env stack layout. A maximally-faithful
  alternative — a dedicated shared/common BU sub-stack — is a possible follow-up, not required for v1.
- **Export `infra_pipeline_project_id`** — currently the return of `deployInfraPipelineProject` is **discarded**
  (`if _, err = …`). Upstream exports it; this is a **port bug** → fix in the live stack **and** the ported
  example (`pulumi/examples/go-foundation/4-projects`).
- **Export `oss_floating_project_number`** (add `OSSFloatingProjectNumber` to `BUProjects`) for deterministic
  Cloud Run URLs / service-agent identity.
- **Activate the APIs the app tier needs** on the oss projects: add `secretmanager.googleapis.com`,
  `iam.googleapis.com`, `iamcredentials.googleapis.com`; on the infra-pipeline project add
  `iamcredentials.googleapis.com`. (Check upstream's `example_project`/`infra_pipeline` API sets and match +
  extend; treat any missing-vs-upstream as a port fix.)

### 7.3 gcp-org DRS overrides
`gcp-org` enforces `constraints/iam.allowedPolicyMemberDomains` org-wide (live; `domains_to_allow: "C0316crd2"`).
`allUsers` invoker will be rejected in the oss projects. Add a **project-scoped override** of that constraint on
each oss project (allow `allUsers`/public), applied by the **org SA** in `gcp-org`. (Confirm public invoker is
intended for oauth-user-inspector; it's a public demo tool.)

### 7.4 sa-terraform-proj folder-level grants
The identity applies create SAs + set IAM + Secret Manager in the oss projects. `sa-terraform-proj` has org
`organizationAdmin` (⇒ `projects.setIamPolicy`) but relies on the implicit creator-owner grant for SA creation.
Codify explicit **BU-folder-level** `roles/iam.serviceAccountAdmin` + `roles/secretmanager.admin` for
`sa-terraform-proj` (in gcp-bootstrap/gcp-org) rather than depend on implicit owner.

### 7.5 repo_config graduation (import-safe)
Move `oauthEnvironment` from the single adopted `oauth-user-inspector-development` env + flat `oauthVars` to the
`tabulaEnvironments` **map-of-maps** shape: `oauth-user-inspector-{development(auto),nonproduction(reviewer),
production(reviewer)}` + `oauth-user-inspector-build` + preview envs. The dev env was adopted via `pulumi.Import`
with fixed resource names — **keep logical names/aliases** so the migration doesn't 409. Reconcile the var-name
split: pick **one** of `GCP_DEPLOY_SERVICE_ACCOUNT` (workflow reads this) vs `GCP_SERVICE_ACCOUNT` (foundation
convention) and use it consistently.

## 8. Multi-tenancy & least-privilege IAM (enforced in `serverless_space`)

Multiple apps share each oss project + the infra-pipeline project. Partition per app; grant per-app only:
- **Secrets** named `<app>-<KEY>`; runtime SA gets `secretmanager.secretAccessor` **per-secret on its own
  secrets only** — never the project-wide grant the current stack uses (which would let one app read every
  other app's secrets).
- **Service accounts** `<app>-deploy@` / `<app>-runtime@`.
- **Artifact Registry**: a **per-app repo** in the infra-pipeline project; build SA gets `artifactregistry.writer`
  on that repo only; each env's Cloud Run service agent gets `artifactregistry.reader` on that repo only.
- **`actAs`**: deploy SA gets `serviceaccount.iam.serviceAccountUser` **on its own runtime SA only** (never
  project-wide `iam.serviceAccountUser`, which is cross-app takeover).
- **WIF binding**: **deploy SA only**, on `attribute.environment/<app>-<env>` (composite with repo per §7.1).
- **Cloud Run** service `<app>-<env>`; **GitHub env / repo_config var** keyed `<app>-<env>`.
- **Do NOT template the current deploy-identity stack's IAM** (project-wide `serviceAccountUser` +
  `artifactregistry.admin` + `secretmanager.secretAccessor`).

## 9. Secrets & Zitadel (multi-env)

- Each oss project's Secret Manager holds the app's `<app>-<KEY>` runtime secrets; the app reads them at runtime.
- **`zitadel-apps` becomes multi-env**: per-env OIDC app + redirect URIs. Redirect URIs need the **deterministic
  Cloud Run URL** (`https://<service>-<PROJECT_NUMBER>.<region>.run.app`) → needs the oss project **number**
  (§7.2 export). Zitadel `DevMode: true` must be **off** for the production client.
- **Close the cred-sync-to-GCP-SM loop** (missing today): `zitadel-apps` only *exports* clientId/clientSecret,
  and `tools/sync-env-secrets` writes only GitHub secrets (`gh secret set`) — nothing seeds GCP Secret Manager.
  Simplest closure: `zitadel-apps` writes the Zitadel secret **versions** into each env's Secret Manager itself
  (it holds the values); extend the tool (or a sibling) for any Bitwarden→GCP-SM provider creds.

## 10. CI — promotion chain

- A per-app **build-once** job (own environment + build SA) → **digest** output.
- A promotion chain mirroring `foundation-release.yaml`: dev (auto, needs build) → nonprod (approval) → prod
  (approval), each a thin `uses:` of the reusable `_deploy-cloud-run.yaml`, evolved to **split build from
  per-env digest-deploy** and keep blue-green.
- Remove the workflow's imperative "Ensure Artifact Registry repository" step and the app stack's unconditional
  `pulumi.Import` of the repo (the repo is now owned by the shared/build stack; the import would fail first
  `pulumi up` in a fresh env).
- Rework the concurrency key now that all three envs run in one workflow run.
- Tighten secrets: pass **explicit** secrets, not blanket `secrets: inherit`; consider a per-purpose Pulumi
  token as app CI grows (the shared token currently grants write to all foundation state).

## 11. `gcp-identities.tsv` & stale configs

Add rows for the new per-env app + identity + build stacks (running as `sa-terraform-proj` / per-env deploy SAs
as appropriate). The existing `oauth-user-inspector` `Pulumi.nonproduction.yaml`/`Pulumi.production.yaml` point
at the **personal** project — a live footgun for a stray `:up`; repoint (or remove until cutover). Keep the
personal-project pipeline live until prod is verified; retire it in the deferred phase.

## 12. Ordering / sequencing

1. **gcp-bootstrap**: WIF repo-pin + (if new identity envs) `proj` saMappings + folder-level SA grants → release + apply.
2. **gcp-projects**: APIs + single-stack infra-pipeline + exports (`infra_pipeline_project_id`,
   `oss_floating_project_number`) → release-please dev→nonprod→**prod approval** (critical path).
3. **gcp-org**: DRS overrides on the oss projects → apply before any app stack binds `allUsers`.
4. **repo_config**: build + per-env app environments/vars (import-safe) → auto-applies on merge.
5. **Shared modules** (`pkg/cloud_run`, `serverless_space`) published/back-ported.
6. **App shared/build stack** (AR repo, build SA, service-agent readers) → **per-env identity stacks** →
   **GCP-SM seeding + zitadel multi-env** → **per-env app stacks** + CI cutover.
7. Verify prod, then retire the personal-project pipeline (deferred).

## 13. Testing / verification

- Unit: `config_test.go` for each new stack (loader defaults); module unit tests for `cloud_run`/`serverless_space`.
- Build/vet/gofmt/license green; `go mod tidy` against published pins (no `replace` in live).
- Per-env `pulumi preview` all-creates, zero destructive, in the correct oss project.
- **Smoke exercises a real Secret Manager read** (not just SPA mount) before promotion.
- Blast-radius: DRS override scoped to the oss projects only; WIF repo-pin previewed against the foundation
  stacks (must be non-destructive / non-breaking for existing foundation deploys).

## 14. Scope

**In (first spec):** WIF repo-pin; stage-4 API/infra-pipeline/export changes (+ port-bug fix in the example);
gcp-org DRS overrides; sa-terraform-proj grants; repo_config multi-env graduation; `pkg/cloud_run` +
`serverless_space` (+ example back-port); oauth per-env identity/app/build stacks on the oss projects;
`SECRET_PREFIX` server change + real-secret smoke; per-env secrets + zitadel multi-env + cred-sync-to-GCP-SM;
build-once/promote-digest CI; env-scoped WIF + per-app least-priv IAM.

**Deferred (follow-ups):** per-env custom domains (`oauth-inspector-{env}.ipv1337.dev`); retiring the personal
`gen-lang-client-*` project; onboarding a 2nd OSS app to validate the template; per-purpose Pulumi tokens.

## 15. Open risks

- The stage-4 prod approval gates the whole app stage — plan the lead time.
- `pulumi.Import` migrations in repo_config must preserve logical names or 409.
- The WIF repo-pin re-apply must be verified non-breaking for existing foundation deploys before merge.
- Confirm public-invoker intent (drives the DRS override).
