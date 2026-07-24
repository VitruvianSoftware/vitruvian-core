# App-infra scaffolding/workload boundary migration (2026-07-24)

Reverses the "workload-into-the-foundation-leaf" cutover in favor of a clean boundary:

- **Foundation `gcp-app-infra` (stage 5) = scaffolding + outputs only.** It creates
  **zero** GCP resources; it consumes stage-4 `gcp-projects` facts (host project
  id/number, region, per-app deploy SA) by StackReference and **re-exports** them.
  The image-less foundation chain never needs a digest.
- **Each app's own `infra/app` stack = the workload.** It consumes the foundation
  outputs and deploys the Cloud Run service **with the image digest** its own pipeline
  builds.

Motivation: the foundation-release chain was deploying the app *workload* (via the
leaf's `_workload_enabled` path) with no image → the `foundation-app-deploy` digest
guard fails on every foundation release. See the `deploy-app-development` failure that
surfaced this.

## Decisions
1. App-stack inputs (project / region / runtime SA / image digest): **kept as-is** — the app
   already sources these from its own stack config (`project`, `region`,
   `runtimeServiceAccount`) and the `<APP>_IMAGE_DIGEST` env, which is exactly the working
   pre-cutover shape. The foundation leaf *re-exports* the same facts (outputs.go) as a
   consumable contract, but rewiring the app to read them via a new StackReference is a
   deliberate **follow-up** (it adds a cross-stack Pulumi state-read grant for the app deploy
   SA and a deploy-order coupling on the leaf). Right-sized here: restore correctness first,
   consume-by-reference later.
2. `workloadMigrated` flag in app stacks: **removed** (app always owns the workload).
3. `deploy-app-*` in `foundation-release`: **kept**, but now deploys the image-less
   scaffolding leaf (guard passes trivially — zero enabled workloads — and outputs
   stay fresh after stage-4 changes). Foundation still deploys *scaffolding*, never a
   workload.
4. `modules/serverless_space`: left in place unused for now; delete in a follow-up
   after confirming tabula's `revision`-pkg naming parity (409-safe suffix).
5. AR repo / WIF / all SAs consolidation into foundation: tracked follow-up, not here.

## Precondition (verified)
Each env's stage-4 `default_region` **equals** the live service region (all `us-central1`),
so consuming the foundation `region` output is a no-op — no region-replace (which
`deletion_protection=true` would block). **Re-verify per env before the state move.**

## Verified live state (2026-07-24, read-only `pulumi stack export`)
Uniform across **all 6 envs** (bu1 oauth ×3, bu2 tabula ×3):
- **Foundation leaf** (`ipv1337/foundation-app-infra-bu{N}-<env>/production`, 7 resources):
  owns the workload — `pkg:index:CloudRun` component → child `gcp:cloudrunv2/service:Service`
  (**`deletionProtection=true`**) + a sibling `gcp:cloudrunv2/serviceIamMember:ServiceIamMember`
  (`<app>-public-invoker`). The workload cutover DID land here.
- **App stack** (`ipv1337/pulumi_oauth_user_inspector/<env>`, `ipv1337/pulumi_tabula_app/<env>`,
  5 resources): owns only the `gcp:cloudrun/domainMapping:DomainMapping` (+ cloudflare CNAME).

Consequence: the scaffolding-only leaf program declares zero workload, so a leaf `pulumi up`
would try to DELETE the `Service` → the provider's `deletionProtection=true` **blocks** the
delete and the deploy fails closed (non-destructive). Hence the state move below is mandatory
**before** the leaf next deploys. `deploy-app-*` is release-gated (needs a foundation
release-please merge), so merging this PR does not auto-trigger it — there is a controlled window.

## Code changes (one PR)

### Foundation `gcp-app-infra` — all 6 leaves (`business_unit_{1,2}/{development,nonproduction,production}`)
- `main.go`: delete the workload loop (`for _, app := range cfg.Apps` → `serverless_space.DeployServerlessSpace`), the `serviceURLs`/`serviceNames` maps, the `_service_uri`/`_service_name` exports, the `appEnv`/`imageDigest`/`stableRevision`/`promote`/`revisionSuffix` helpers (bu2 also `shortImageDigest`/`deployedEnv`/`configHash`), and the `serverless_space` + now-unused `os`/`strings` imports. Keep `loadConfig → loadStackReferences → exportOutputs(ctx, cfg, refs, refs.DeployServiceAccounts)`. (Proven on bu1/dev.)
- `config.go`: reduce `AppConfig` to `{ Name string }`; the app loop to `AppConfig{Name: name}`; drop the `strconv` import and the now-dead `splitKV` helper.
- `config_test.go`: drop assertions on the removed workload fields.
- `Pulumi.production.yaml`: remove `<app>_workload_enabled`, `_service_name`, `_secret_prefix`, `_env_vars`, `_runtime_service_account`, `_max_instances`, `_public_invoker`; fix the stale "NOT YET CUT OVER / bu1 us-west1" comments (bu1 app hosting is us-central1).
- bu2 only: delete `revision_test.go`.

### App stacks
- `oauth-user-inspector/infra/app/main.go` and `tabula/infra/app/main.go`: remove the `workloadMigrated` flag and its `if !workloadMigrated` guard so the Cloud Run service + allUsers invoker are always declared; `serviceUrl` always exported (DomainMapping already binds via the service output).
- App `Pulumi.{development,nonproduction,production}.yaml`: delete `workloadMigrated: "true"` (and its stale comment). App inputs (project/region/runtimeServiceAccount) are unchanged — they were already in config.
- (Outputs contract — FOLLOW-UP, not this PR) each app stack could later add a StackReference to `ipv1337/foundation-app-infra-bu{N}-<env>/production` and read project id / number / region from its outputs (instead of the committed config), plus runtime SA from the sibling `infra/identity` StackReference. Deferred per decision #1 (adds a cross-stack read grant + deploy-order coupling); the leaf already exports the contract for when it lands.

### Workflows
- `oauth-user-inspector-deploy.yaml` + `tabula-deploy.yaml`: set `workload-migrated: false` in the three `_deploy-cloud-run` calls (flips `PHASE` candidate→`all` so the app's own dir runs the full blue-green with `image-digest`). No change to `_deploy-cloud-run.yaml`.
- `foundation-release.yaml`: **no change** — `deploy-app-*` now deploys the scaffolding-only leaf (guard passes).
- `foundation-app-deploy.yaml`: **no change** — the digest guard stays as the real safety net.

## State migration (per env, after the PR merges — the deliberate live step)
The 6 live services (`oauth-user-inspector-<env>`, `tabula-api-<env>`) currently sit in
the **foundation leaf** Pulumi state. Recreate is the safe path (nothing is launched):

For each env (bu1: oauth ×3 component `oauth-user-inspector`; bu2: tabula ×3 component `tabula`):
1. **State-delete the workload from the LEAF** (state-only; live service keeps serving).
   Delete the component with `--target-dependents` (removes the component *and* its child
   `Service`), then the sibling invoker. Example (bu1/development):
   ```
   pulumi state delete --stack ipv1337/foundation-app-infra-bu1-development/production \
     'urn:pulumi:production::foundation-app-infra-bu1-development::pkg:index:CloudRun::oauth-user-inspector' \
     --target-dependents --force --yes
   pulumi state delete --stack ipv1337/foundation-app-infra-bu1-development/production \
     'urn:pulumi:production::foundation-app-infra-bu1-development::gcp:cloudrunv2/serviceIamMember:ServiceIamMember::oauth-user-inspector-public-invoker' \
     --yes
   ```
   **Do NOT** let `pulumi up` delete it — `deletionProtection=true` blocks a provider delete.
   (`gcloud run services delete` is unaffected — the guard is provider-side on `up`, not on gcloud.)
2. `gcloud run services delete <service> --region us-central1 --project <oss-floating> --quiet`
   (`<service>` = `oauth-user-inspector-<env>` / `tabula-api-<env>`; removes the live service so
   the app recreate is a clean create, not a 409 — brief gap is free, not launched).
3. Run the app's own deploy pipeline (`oauth-user-inspector-deploy` / `tabula-deploy`,
   now `workload-migrated:false` → PHASE=all) → recreates the service + invoker in the **app**
   stack with the built digest; the DomainMapping (already in app state) rebinds to the same name.
4. Verify: service serves 200; foundation leaf `pulumi preview` is clean (no workload, just the
   re-exported outputs); the app stack owns the `Service`.

Zero-downtime alternative (if ever needed): after step 1, `pulumi import` the live `Service` +
invoker into the app stack instead of steps 2–3 — avoids the gap but requires exact input
matching. Recreate is preferred here (apps not launched, fewer failure modes).

## ✅ Executed (2026-07-24) — all 6 envs

The state-move ran for all six envs after #1137 merged; every env verified: leaf state
**workload-free**, app stack owns **Service + invoker + DomainMapping**, live service **HTTP 200**.
Recreate deploys: oauth dev/nonprod/prod + tabula dev/nonprod/prod all green.

Execution notes (landmines the runbook above didn't anticipate):
- **Delete order within the leaf is child-first for a reason.** The public invoker's `Name`
  references `Service.Name`, so Pulumi treats the invoker as a *dependent* of the Service —
  deleting the Service first errors `…depend on it…`. Correct order: **invoker → Service →
  component**.
- **Per-env `protect` flag was inconsistent.** `tabula-nonprod` and `tabula-prod` had Pulumi
  `protect=true` on the Service+component (the others didn't), so those two needed
  `pulumi state delete … --force`. (This is the Pulumi `protect` flag, distinct from the
  provider-side `deletion_protection` input.)
- **`gcloud run services delete` is NOT blocked by `deletion_protection`** — that guard is a
  provider-side input enforced only on a Pulumi `up`/replace, invisible to gcloud.
- **Identity for the gcloud delete:** the org USER token (`james@vitruviansoftware.dev`) can't
  refresh headless; use the still-valid ADC token —
  `CLOUDSDK_AUTH_ACCESS_TOKEN=$(gcloud auth application-default print-access-token)`. (Pulumi
  *state* ops need no GCP identity — they only touch Pulumi Cloud state; `whoami`=ipv1337.)
- **Prod recreate gates:** `gh workflow run <app>-deploy.yaml -f environment=production` pauses
  at the `production` GitHub Environment reviewer gate (oauth gates *twice* — `zitadel-prod` and
  `deploy-prod`); approve via `POST /actions/runs/{id}/pending_deployments`
  (`environment_ids[]=<id>`, `state=approved`).

## Risks
- `deletion_protection=true` blocks any Pulumi-side delete → use `pulumi state delete` (step 1), never `pulumi up`.
- bu2 deploy-SA output gap: tabula-deploy is minted in `tabula/infra/identity`, not stage-4, and foundation bu2 `remote.go` skips reading it — so the bu2 foundation contract can't export `tabula_deploy_service_account` (the app already sources it from identity; nothing breaks, contract is asymmetric).
- Deleting `serverless_space` later removes its 409-safe revision naming — confirm `tabula/infra/app` parity via the shared `revision` pkg first (hence decision #4).
- App stacks now depend on the foundation leaf's outputs being current — ensure the scaffolding leaf is deployed after any stage-4 change (decision #3 keeps it in the chain).
