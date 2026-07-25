# Foundation cold-deploy race audit & redeploy continuation

**Context.** After the 2026-07-11/12 teardown, the `vitruviansoftware.dev` foundation is being
redeployed under `fldr-foundation-1` (`folders/823326946563`). Policy (James): **the first apply of
each stage must succeed with zero errors — a race is a porting-fidelity bug, not something to retry.**
On a cold (from-empty) apply, pulumi-gcp `projects.Service` returns *before* the API is usable, so any
same-apply resource against a freshly-enabled API can fail. Terraform masks this with provider retries +
`depends_on`; our port must gate explicitly.

**The contract** (`pulumi/library/go/pkg/project_factory/project.go`): `ProjectArgs.ApiPropagationSeconds`
> 0 (and ≥1 API enabled) creates a `local.Command "sleep N"` gated on all `Service` resources and sets
`component.ApisReady` to it; at 0 it is the bare project (no wait). A same-apply API consumer is SAFE only
if BOTH (a) its project sets `ApiPropagationSeconds > 0` AND (b) it `DependsOn` that project's `ApisReady`.
Pulumi Go does **not** propagate a component-level `DependsOn` to a component's children, so gating a
library component's inner resources needs either a data-dependency (thread a gated project-id) or a
`Dependencies []pulumi.Resource` field the component applies to each child.

## Status (2026-07-18)

| Stage | Live-deploy complexity | Fix status | Deployed? |
|---|---|---|---|
| gcp-bootstrap | — | #908 (project_factory+bootstrap) merged; GCS-agent wait **PR #910** | ✅ 300 res, 0 err (seed `prj-b-seed-c010`, cicd `prj-b-cicd-e096`) |
| gcp-org | COMPLEX | fixes implemented (subagent) | ⬜ pending review+deploy |
| gcp-environments | SIMPLE | fixes implemented + build/vet/test pass | ⬜ |
| gcp-networks | MODERATE | fixes implemented + build/test pass | ⬜ |
| gcp-projects | SIMPLE (live floating-only) | fixes implemented (subagent) | ⬜ |

**Deploy order:** `org → (env, net) → proj`. env/net StackReference `foundation-org`; proj refs org+env+net;
org refs bootstrap. env/net/proj are per-env stacks (development/nonproduction/production) → ~10 applies.
`org-folders` (8 res) is preserved, not torn down.

**Deploy mechanics (fast-iteration path used for bootstrap):** from the stage dir, `GOWORK=off` +
temp local `replace` to the fixed worktree libs + `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token
james@vitruviansoftware.dev)` + `PULUMI_BACKEND_URL=https://api.pulumi.com`, then `pulumi preview` →
`pulumi up -s ipv1337/<stack>/<env> --yes`. Token expires ~hourly — refresh before each stage.

**billingbudgets quota project (james@ user-cred deploys):** any stage that creates `billing.Budget`
resources (env, projects, and org if budgets are configured) fails under james@ ADC/user token with
*"billingbudgets.googleapis.com API requires a quota project"* unless you also export
`USER_PROJECT_OVERRIDE=true` + `GOOGLE_BILLING_PROJECT=prj-b-seed-c010` (the seed has billingbudgets
enabled and james@ owns it). This is a user-credential requirement only — under CI-as-SA the SA's own
project is the quota project automatically, so it's a local-deploy prereq, NOT a code bug. ⚠️ Do NOT use
this override for a stage that makes org-scoped calls it would break (bootstrap's `getOrganization`); env
creates only projects/budgets/keys so it's safe. Watch networks (org-scoped VPC-SC/ACM) — apply it only if
networks also creates budgets and the override doesn't break the ACM calls.

## Common fix (every stage)
Config-driven `api_propagation_seconds` (default **120**) threaded to every `project_factory.NewProject`.
Stages pin a **pre-#908** project_factory pseudo-version (`v1.0.3-0.20260708…`) that lacks the auto-append
(billingbudgets/iam) + gating fixes → each stage adds a temp local `replace` to the worktree project_factory
for the deploy; the committed PRs must bump to a **post-#908** project_factory pin once one is tagged
(release PR #681 open; published bootstrap v2.1.3 transitively pins the stale pseudo — a release-transitivity
gap to fix).

## Per-stage findings

### gcp-org (COMPLEX — SCC + CAI are ACTIVE in prod: `enable_hub_and_spoke=true`, `gcp_scc_admin` set)
- **Missing APIs (hard-fail):** audit-logs project needs `pubsub` + `storage-api`; SCC project needs
  `cloudasset`, `cloudbuild`, `cloudfunctions`, `artifactregistry`, `run`, `eventarc`, `storage-api`
  (the CAI-monitoring Cloud Function pipeline).
- **SA-ordering (guaranteed fail):** `cai-monitoring-builder` SA created in `iam.go` (step 8) but consumed
  by the Cloud Function in `main.go` step 6b via a string-built email with no dependency → "service account
  does not exist". Fix: create the builder SA before the cai deploy, thread the `*serviceaccount.Account`,
  derive the email from `sa.Email`.
- **KMS org service-agent:** insert a `sleep 60` propagation wait between the KMS identity create and the
  org IAM binding (GCS-agent pattern).
- **Library changes:** `Dependencies []pulumi.Resource` on `centralized_logging` + `cai_monitoring` (apply
  to children) so audit-logs/SCC `ApisReady` actually gates the pubsub/BQ/function children.
- Thread `ApiPropagationSeconds` (incl. `modules/network` svpc + net-hub project calls).

### gcp-environments (SIMPLE)
- Thread config-driven `ApiPropagationSeconds` (default 120) to KMS + Secrets `NewProject` in
  `modules/env_baseline`. Post-#908 project_factory auto-appends the 2 missing APIs (billingbudgets for the
  budget, iam for the `deprivilege` default-SA) — no ActivateApis edits needed with the local replace.

### gcp-networks (MODERATE — pure API-consumer, cold-clean for propagation)
- Two same-apply **PSA-vs-VPC-peering** serialization races (one peering op per VPC). Fix: expose
  `PSAConnection` on the `network` lib `Networking` struct + `DependsOn` it from the spoke-to-hub peering
  (`shared_vpc.go`) and the hub `hubDependsOn` (`main.go`). Needs a `network/v2` patch (temp replace for now).
- **Config staleness FIXED:** `vpc_sc_members` in all 3 configs referenced the old seed `prj-b-seed-8ebb`
  → updated to `prj-b-seed-c010`. **Follow-up:** wire these from the bootstrap/org StackReference instead of
  hardcoding (they are the `*_step_terraform_service_account_email` outputs) so they never go stale again.

### gcp-projects (SIMPLE for the live floating-only config)
- Live prod/dev = floating-only + infra-pipeline → only the `ApiPropagationSeconds` knob matters (budget +
  default-SA propagation). The heavy races (svpc-attach, peering VPC/firewall component boundary via a
  gated-project-id data-dep, cmek GCS-agent lookup + bucket ordering, conf-space SA) are on the example
  default-true path — fixed too for faithfulness but not exercised live.

## Deploy-time config prerequisites (forward-references)
- **gcp-org:** `oss_public_invoker_projects` (Pulumi.production.yaml) hardcodes the OLD floating-project IDs
  (`prj-{d,n,p}-bu1-oss-floating-{2ad6,cf11,8e16}`) which don't exist until gcp-projects redeploys with NEW
  random IDs. `policies.go:174` creates a per-project DRS AllowAll policy for each → the org apply would fail.
  **Clear `foundation-org:oss_public_invoker_projects` before the first org apply** (config_test asserts empty
  is the default), then set it to the new floating IDs and re-apply org AFTER gcp-projects redeploys.

## Remaining work
1. Review + deploy gcp-org (clear oss_public_invoker first). 2. Deploy env ×3, net ×3, proj ×3. 3. Reset
   org `oss_public_invoker_projects` to new floating IDs + re-apply org. 4. Land PRs: the 3 library changes
   (centralized_logging/cai_monitoring `Dependencies`, network `PSAConnection`) + per-stage code fixes
   (APS knob, missing APIs, SA-ordering) with post-#908 published pins (drop temp replaces). 5. Fix the
   release-transitivity gap (bootstrap/stage pins → post-#908 project_factory). See memory
   `foundation-teardown-redeploy` + `pulumi-library-release-infra-and-transitivity`.
