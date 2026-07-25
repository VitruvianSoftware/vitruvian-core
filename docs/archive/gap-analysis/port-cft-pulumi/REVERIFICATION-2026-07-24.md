# Foundation Port Gap Re-verification — 2026-07-24

Re-verification of [`GAPREPORT.md`](GAPREPORT.md) (the 236 confirmed
`terraform-example-foundation` → Pulumi-port gaps) against **current code**, plus
an audit of a dimension the original analysis never covered: **the live
foundation's committed config *values*** (the class the `us-south1` secondary-region
drift belonged to).

Produced by the [`foundation-fidelity-reverify`](#how-this-was-produced) multi-agent
workflow: per-stage re-verify + fresh TF-vs-go diff, a live-config-drift finder per
stage, adversarial verification of every new finding, and a completeness critique.
Upstream reference: `terraform-example-foundation` @ `ed07500` (2026-07-01) — the
same baseline the original report used.

## Headline

- **111 of 236 documented gaps are FIXED. 0 regressed.** 79 still open, 41 partially
  fixed, ~19 unverifiable (TS-only, de-prioritized — the **go** port is what feeds
  the live foundation).
- **21 new confirmed findings** (0 critical, 6 major, 9 minor, 6 info) — 15 from a
  fresh TF-vs-go diff, 6 from the live-config-value audit. 15 more were refuted.
- The `us-south1` region drift, the `serverless_space`/region-inheritance work, the
  projects-SA `serviceUsageAdmin` grant, and the whole stage-4 fidelity batch
  (#877/#883/#889/#1097/#1100/#1118/#1122) account for much of the "fixed" column.

> ⚠️ **Methodology lesson (see [`METHODOLOGY-BLINDSPOTS.md`](METHODOLOGY-BLINDSPOTS.md)):**
> a fidelity audit **must run against the deployed ref** (origin/main) with finder
> agents forced to **absolute paths**. The first two re-run attempts read a checkout
> 28 commits stale and manufactured already-fixed "critical" findings (the region
> drift, a 5-app-infra compile error) that had been merged days earlier. The numbers
> here are from a clean run with the tree at origin/main.

## Per-stage re-verify status

| stage | total | fixed | still-open | partial | unverifiable |
|---|--:|--:|--:|--:|--:|
| 0-bootstrap | 42 | 16 | 10 | 6 | 10 |
| 1-org | 34 | 21 | 6 | 6 | 0 |
| 2-environments | 12 | 10 | 2 | 0 | 0 |
| 3-networks-svpc | 28 | 10 | 9 | 6 | 2 |
| 3-networks-hub-and-spoke | 34 | 20 | 5 | 9 | 0 |
| 4-projects | 25 | 5 | 18 | 2 | 0 |
| 5-app-infra | 20 | 11 | 3 | 6 | 0 |
| policy-library | 55 | 18 | 26 | 6 | 0 |
| **TOTAL** | **250** | **111** | **79** | **41** | — |

(Exact per-status counts carry normal LLM-finder variance of a few each; the shape —
~45% fixed, 0 regressed, remaining gaps concentrated in **4-projects** and the
**policy-library / CI-tooling** surface — is stable across runs.)

## 21 new confirmed findings

### Major (6)

1. **[gcp-networks · live-guard] The region regression guard did not cover the actual
   drift vector.** `config_test` forces the region env/config empty and asserts only
   the *code* fallback, so it would still pass if a `Pulumi.production.yaml` were
   edited back to `us-south1` (the committed value is what deploys). **→ Fixed in
   #1128** (`TestCommittedRegionsAreCanonical` reads the committed yaml; verified it
   fails on the drift).
2. **[3-networks-hub-and-spoke · go] Spoke VPC-SC bridge indexes `args.VpcScProjects[0]`
   with no bounds check** — Go panic on every spoke preview/up when `vpc_sc_projects`
   is unset (`modules/shared_vpc/service_control.go:133`; no default for the key).
3. **[5-app-infra · go] Confidential Space workload is deployed into the shared-VPC
   project, not the dedicated `confidential_space_project`** (`remote.go:71-72` sources
   the app project from the shared VPC). TF uses the confidential-space project/number.
   *Example-port only — our live apps use `serverless_space` (Cloud Run), not the
   confidential/compute path.*
4. **[5-app-infra · go] Only the sample-svpc instance is deployed; the sample-peering
   compute instance (and its IAP secure tags) is never created.** *Example-port only.*
5. **[5-app-infra · go] The leaf exports 3 of TF's ~14 stage outputs; `env_base` /
   `confidential_space` module results are discarded** (`main.go:60,81 → _`). *Example-port only.*
6. **[policy-library · both] The newly-wired CrossGuard policy-pack gate cannot execute
   — the pipelines never `npm install` the pack's node dependencies** (`build/pulumi-preview.yml`
   has `setup-go` only; `--policy-pack ../policy-library` needs node). The gate is
   effectively a no-op / hard-errors depending on the runner.

### Minor (9) — condensed

- **SCC config key was silently inert** — live gcp-org read `enable_scc_resources` vs
  canonical `enable_scc_resources_in_pulumi`. **→ Fixed in #1128.**
- `build_local.go.example` imports a nonexistent library path (`go/pkg/storage`).
- Essential-Contacts governance groups sourced from stack config, not bootstrap
  `required_groups`.
- `project_budget` config schema diverges from upstream's flat tfvar (silently ignores
  upstream keys).
- Cloud NAT external-IP count not configurable per region (one value for both).
- `enable_all_vpc_internal_traffic` toggle not exposed (hardcoded off).
- Spoke→hub bridge perimeter is unconditionally enforced, ignoring `enforce_vpcsc`.
- SVPC / confidential-space perimeter-attach and shared-VPC-attach are not serialized
  (missing upstream's 60s propagation sleep) — a deploy-ordering race.
- Policy-pack enforcement levels diverge between README (advisory) and code (mandatory).

### Info (6) — condensed

- `enforce_org_billing_creator` and `create_access_context_manager_policy` defaults are
  **intentionally** inverted live-vs-example (documented co-tenant / org-singleton
  rationale; yaml overrides where it matters) — *not bugs, recorded for traceability.*
- Live-vs-example: shared stack adds hub proxy-only CIDRs absent from the example.
- App-infra region is consumed correctly, but note it inherits the projects default.
- Dead code (`BootstrapOutputs` struct unused in a `remote.go`); SVPC route-name
  convention drift; billing_code label still the upstream placeholder `"1234"`.

## Notable STILL-OPEN (prior critical/major, relevant to the go/live port)

- **4-projects (18 open)** — the largest cluster. Includes the SVPC service-project /
  VPC-SC perimeter attach race, infra_pipelines gaps, and per-BU output/CMEK
  divergences. Worth a dedicated stage-4 pass.
- **3-networks-svpc** — the example `base_env` **hardcodes the development address plan
  (CIDRs / secondary / proxy ranges) for every environment**; there are no per-env CIDR
  inputs. (Our **live** networks pins per-env CIDRs as consts in each leaf's `main.go`,
  so live is not affected — but the example port is unusable for multi-env as-is.)
- **0-bootstrap** — no `tf_cloud_builder` runner-image build pipeline, and the private
  worker pool is an in-example module not a reusable library component. *Largely N/A for
  us: we deploy via GitHub Actions WIF, not Cloud Build.* GitLab-build gaps are also N/A.
- **policy-library (26 open)** — mostly the CrossGuard pack wiring / CI-integration
  surface (see the major above) and doc/enforcement-level mismatches.
- Several **TS-only** majors remain (org-admin impersonation, folder-scope org policies,
  budgets) — lower priority since the live foundation deploys the **go** port.

## What was fixed (highlights of the 111)

0-bootstrap: authoritative `projectCreator`/`billing.creator` bindings, `billing.admin`
to billing-admins, `iamcredentials` on the seed, the `cb-private-pool` module, group
`user_project_override`, group→IAM ordering, `project_deletion_policy` wiring.
1-org (21/34): the bulk of org-policy/IAM/logging/SCC gaps. 2-env: 10/12.
3-networks: peering, VPC-SC project-number usage, PSC-IP config, hierarchical firewall.
5-app-infra: the `serverless_space` region-inheritance + compile fixes (#1097/#1100).
Cross-cutting: the projects-SA `serviceUsageAdmin` grant (#1118), the region-consumption
chain (#1113/#1117/#1122).

## How this was produced

Workflow script: `scratchpad/audit/fidelity-reverify.js` (49–52 agents/run,
~4.6M tokens). Repos compared: upstream TF (`ed07500`), `pulumi/examples/{go,ts}-foundation`,
`pulumi/library`, and — new this round — `infrastructure/pulumi/foundation` (live). The
187 structured prior findings drove the re-verify; a per-stage live-drift finder added
the config-value dimension; every new finding faced an adversarial refuter (default
`isReal=false`); a completeness critic produced the blind-spot list.

**Follow-ups landed:** #1128 (region guard + SCC key). **Recommended next:** the
open-finding clusters above, and the un-run audit dimensions in
[`METHODOLOGY-BLINDSPOTS.md`](METHODOLOGY-BLINDSPOTS.md).
