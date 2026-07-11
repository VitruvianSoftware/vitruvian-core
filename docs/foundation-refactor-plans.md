# Foundation Refactor — Per-Stage Plans

Companion to `foundation-port-structural-assessment.md`. Detailed, file/function-level refactor plans
for each stage, produced by comparing upstream `terraform-example-foundation` against our example + live
ports. **Rule discovered while planning:** match upstream's *actual* modularization — most stages keep
folders/iam/policies/etc. **inline in the root** and factor out only a few named modules. Fill the real
modules; don't over-modularize.

> **Recurring finding:** our existing `modules/*` dirs (gcp-org's cai/logging/network, gcp-projects'
> base_env/single_project, gcp-networks' example stubs) are **empty doc-only package stubs** — the logic is
> inline in `package main`. The refactor fills these stubs from the inline code.

> **Verification note:** all executed refactors here are code-only-verified (`go build`/`go test`/`gofmt`).
> A `pulumi preview` (post-reauth) must confirm the plan before redeploy. Since we teardown + re-provision
> fresh, URN preservation is *not* required — but names are kept stable where cheap (belt-and-suspenders).

---

## Stage 0 — gcp-bootstrap ✅ already faithful

Upstream `0-bootstrap` is a single root (no `envs/`) + `modules/{parent-iam-member, parent-iam-remove-role,
cb-private-pool, gitlab-oidc, tfc-agent-gke}`, consuming CFT modules (bootstrap, iam, google_group). Ours
maps cleanly: `projects.go`(seed via `bootstrap` lib)≈`main.tf`; `sa.go`(SAs + `parent-iam-member` + `iam`
lib + billing)≈`sa.tf`; `groups.go`≈`groups.tf`; `build_github_actions.go`(WIF)= the GitHub-Actions
adaptation of `build_cb.tf`. Omitted modules (cb-pool/gitlab/tfc) are TF-Cloud/GitLab CI backends we
correctly don't use. **No structural refactor needed.**

## Stage 1 — gcp-org (fill 3 real modules; keep the rest as root files)

Upstream `1-org` = `envs/shared` (one stack) + `modules/{cai-monitoring, centralized-logging, network}`.
Upstream keeps folders/iam/org_policy/projects/scc/tags/essential_contacts **inline** in the root — so do we.

- **Fill the 3 real (currently stub) modules:** move `cai_monitoring.go`→`modules/cai_monitoring`,
  `logging.go`→`modules/centralized_logging`, and the per-env Shared-VPC host-project creation (in
  `projects.go`)→`modules/network`. Each becomes a package with `Args/Result/New`.
- **Keep as root files** (matches upstream inline `.tf`): `folders.go`, `iam.go`, `policies.go`,
  `projects.go` (minus the network part), `scc.go`, `tags.go`, `essential_contacts.go`.
- **Thin main.go:** orchestrate the calls in dependency order; split config into `config.go`.
- **Preserve the logging→policy race guard** verbatim: `time.Sleep("wait-logs-export", 30s,
  DependsOn=[logs.LastResource])` gating the domain-restricted-sharing policy. `centralized_logging.Result`
  must keep exposing `LastResource`.
- **Stack:** upstream is `envs/shared` → rename the single `production` stack to `shared` (a state-affecting
  rename — do it as a discrete step, after the code move).
- **Do NOT** create folders/iam/tags/scc modules — upstream doesn't (avoid over-modularization).

## Stage 2 — gcp-environments ✅ EXECUTED (the exemplar)

Upstream `2-environments` = `envs/{development,nonproduction,production}` + `modules/env_baseline`. Our
`deployEnvBaseline` already creates exactly what `env_baseline` does. **Done:** extracted to
`modules/env_baseline` (Args/Result/Deploy); `main.go` thinned to read config + org StackReference, call
`Deploy`, export. Resource names preserved; build/test/vet/gofmt green. Per-env = Pulumi stacks (already
correct). Follow-up: mirror to the example tree (`pulumi/examples/go-foundation/2-environments`) + add the
missing `Pulumi.{development,nonproduction}.yaml.example`.

## Stage 3 — gcp-networks (the monolith; two-phase, Phase B gated)

Upstream `3-networks` = `envs/{development,nonproduction,production,shared}` + `modules/{base_env,
shared_vpc, hierarchical_firewall_policy, transitivity, dedicated_interconnect, partner_interconnect,
vpn-ha}`. **The published `network/v2` library already IS the primitive layer** (NewNetworking,
NewNetworkFirewallPolicy, NewHierarchicalFirewallPolicy, NewDnsZone, NewCloudRouter,
NewTransitivityAppliance, …). What's missing is the **stage-module layer** — our live inlines it into two
~275-line functions (`deployHubNetwork`, `deploySpokeNetwork`) in one 684-line `main.go`.

- **Extract 4 stage modules** over the library primitives:
  - `modules/shared_vpc` — the core, `Mode: "hub"|"spoke"`, unifies the ~70%-duplicated hub/spoke bodies.
    Split into files matching upstream: `main.go, dns.go, firewall.go, nat.go, psc.go, service_control.go`.
  - `modules/base_env` — thin per-env spoke orchestrator (builds spoke subnets + restricted-services, calls
    `shared_vpc` Mode=spoke).
  - `modules/hierarchical_firewall_policy` — wraps `NewHierarchicalFirewallPolicy` (hub only).
  - `modules/transitivity` — ~30-line wrapper over the library `NewTransitivityAppliance` + health-check FW
    (gated off today; keep `DependsOn(shared_vpc.VPC)` + FirewallPolicy for correct future teardown order).
  - Leave `dedicated_interconnect`/`partner_interconnect`/`vpn_ha` as `.example` (unused).
- **Use plain functions returning structs (NOT ComponentResource)** for the stage modules — a
  ComponentResource reparents children and forces replacement. (transitivity is already a library component,
  and is gated off, so no live state.)
- **Preserve verbatim:** the chained-`DependsOn` route serialization, the 60s/60s `time.Sleep` VPC-SC
  propagation gate, and the enforced-vs-dry-run VPC-SC branching (incl. the bridge `UseExplicitDryRunSpec =
  !Enforce` and the "enforced bridge member with dry-run-only regular perimeter is rejected" constraint).
  Keep all gates as-is: transitivity OFF, NAT OFF, VPC-SC dry-run.
- **Phase A (safe, no resource churn):** extract the modules, keep the current `Env=="development"` hub
  dispatch, verify `pulumi preview` = no-op on every stack.
- **Phase B (⚠️ gated — touches live state):** introduce a dedicated `shared` stack and `pulumi state move`
  the hub resources dev→shared to match upstream `envs/shared`. Destructive/stateful — needs explicit
  approval, or fold into the teardown+fresh-provision (in which case the `shared` stack is just a fresh
  deploy, no state move).

## Stage 4 — gcp-projects (fill modules + move the pipeline; ⚠️ one decision)

Upstream `4-projects` = `business_unit_1/{development,nonproduction,production,shared}` + `modules/{base_env,
single_project, infra_pipelines}`. Our `modules/{base_env,single_project}` are empty stubs; logic is inline
(`business_unit.go, cmek.go, confidential_space.go, peering.go`).

- **Fill `modules/single_project`** (leaf: project via `project_factory` + the **3 missing pipeline-SA IAM
  bindings** — `app_infra_pipeline_sa_roles`, folder `networkViewer`, subnet `networkUser`).
- **Fill `modules/base_env`** (per-env orchestrator: BU folder + `single_project` calls for
  svpc/floating/oss-floating/peering + `deployCMEKStorage` + `deployConfidentialSpaceProject` +
  `deployPeeringNetwork`, moved verbatim).
- **Add `modules/infra_pipelines`** — the app-infra pipeline. **This absorbs the two mis-located app stacks:**
  `apps/oauth-user-inspector-build` (AR + build SA + AR-writer) and `apps/oauth-user-inspector-deploy-identity`
  (WIF pool/provider + deploy SA + WIF binding). Deployed in a **`shared` stack** (cross-env singleton), it
  exports `terraform_service_accounts` (app→deploy-SA email) + `enable_cloudbuild_deploy` — which each env's
  `base_env` StackReferences (the upstream cross-stack link).
- **Runtime SA does NOT go in the pipeline** — it's app-runtime identity; it moves to stage 5
  (`gcp-app-infra`/`serverless_space`), prefix-conditioned secret access included.
- **Move the infra-pipeline PROJECT** (`deployInfraPipelineProject`, currently per-env in `main.go` step 5)
  into the `shared` stack (⚠️ the project already exists live → `pulumi state move`, or fold into
  teardown+fresh).
- **Add the missing exports** `infra_pipeline_project_id` (shared) + `oss_floating_project_number` (per env) —
  the build stack already depends on them but they aren't exported today.
- **⚠️ DECISION for James — pipeline SA topology:**
  - **(A) Match upstream (recommended):** ONE deploy SA in the shared `infra_pipelines`, granted per-env
    project roles by each env's `single_project`. Single SA across the 3 GitHub environments (WIF
    `attribute.repository` + optional `attribute.environment`).
  - **(B) Keep per-env deploy SAs** (current #887 design): shared WIF pool in `infra_pipelines`, but per-env
    deploy SA + roles in `base_env`/`single_project`. Diverges from upstream's single-SA shape but keeps
    per-env WIF isolation.
  Also reconcile the **two WIF pools** currently in tension (`github-actions-dev-1` per-app pool in
  deploy-identity vs the `foundation-pool` the build stack federates) — pick one source.
- **Stacks:** `development/nonproduction/production` (base_env) + new **`shared`** (infra_pipelines + pipeline
  project). Env stacks gain a `shared_stack_name` StackReference.

## Stage 5 — gcp-app-infra (new; workload only)

Create `foundation/gcp-app-infra` as the faithful port of `5-app-infra`: `business_unit_1/{development,
nonproduction,production}` + `modules/{env_base, confidential_space, serverless_space}`. It is **workload
only** — deploys `oauth-user-inspector` via `serverless_space` (consuming the published `cloud_run@0.3.0` with
blue-green, #892), running AS the stage-4 pipeline deploy SA, pulling the stage-4 shared AR, reading the oss
project via StackReference. The build/deploy identity is NOT here (it's stage-4 `infra_pipelines`). Add the
`business_unit` layer + `SECRET_PREFIX` runtime env + zitadel multi-env cred-sync + build-once/promote-digest
CI (per the merged Phase-3 plan #885, adjusted to this structure).

---

## Execution order (post-reauth)

Teardown (runbook) → refactor+redeploy bottom-up: bootstrap (as-is) → org (fill 3 modules, rename→shared) →
environments (done) → networks (Phase A extract, then shared stack) → projects (fill modules + infra_pipelines
shared + DECISION) → app-infra (new). Mirror every live change into the example tree (north star: the example
is the reference port). Preview each stage before `up`.
