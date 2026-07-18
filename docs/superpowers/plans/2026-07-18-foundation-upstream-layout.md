# Foundation Upstream-Layout Restructure — Implementation Plan

> **For agentic workers:** delegate each phase to a **fable** subagent with the phase's transformation
> spec + the upstream reference. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the Pulumi Go foundation mirror upstream `terraform-google-modules/terraform-example-foundation`'s
file/directory layout exactly, in BOTH `pulumi/examples/go-foundation/` (the user-facing reference) and
`infrastructure/pulumi/foundation/` (the live infra) — kept in perfect sync — so a terraform user switching to
our Pulumi port has the identical mental model.

**Architecture:** Each multi-env stage gets a shared `modules/` (the reusable logic, already largely present)
plus **thin Pulumi projects** at the upstream env/BU leaves (`envs/{shared,development,nonproduction,production}/`
for 1-org/2-env/3-networks; `business_unit_1/{shared,development,nonproduction,production}/` for 4-projects/
5-app-infra). Each leaf is its own Pulumi project (`Pulumi.yaml` + a thin `main.go` that calls the shared
`modules/` package with that leaf's config). This *adds* per-env code flexibility (a leaf can diverge) while the
one-project-multi-stack model still works because all logic lives in `modules/`. 0-bootstrap stays a single root
(no envs) and gains the optional builder modules.

**Tech Stack:** Pulumi Go, Bazel (`pulumi_project` macro + gazelle), Pulumi Cloud backend (`ipv1337`), the
in-repo `pulumi/library/go/pkg/*` modules.

## Global Constraints
- **Example and live infra are ALWAYS in sync** — every structural change lands in both trees, identically.
- **Faithfulness to upstream is the spec.** When Pulumi and Terraform engines differ, mimic upstream's
  *behavior* with a documented Pulumi workaround (see memory `replicate-upstream-behavior-with-documented-workaround`).
- **First apply must be race-free** — carry forward the cold-deploy fixes already on this branch (APS knob,
  missing APIs, SA-ordering, GCS/KMS-agent waits, PSA-vs-peering, library `Dependencies`/`PSAConnection`).
- **tfc-agent-gke / terraform_cloud builder** adapts to the **Pulumi Cloud** equivalent (Terraform Cloud is not
  our backend) — keep the file/module name for structural parity, document the adaptation in-code.
- **Destroy/recreate of live resources is APPROVED** — nothing is in use. No state-migration gymnastics; tear
  down and redeploy fresh under the new layout.
- Each leaf Pulumi project name follows `foundation-<stage>-<leaf>` (e.g. `foundation-environments-development`,
  `foundation-projects-bu1-production`); live stacks are `ipv1337/<project>/production` (one stack per leaf).

## Upstream target structure (authoritative — fetched from upstream `main`)
```
0-bootstrap/    modules/{cb-private-pool, gitlab-oidc, tfc-agent-gke, parent-iam-member, parent-iam-remove-role}
                root: build_{cloud_build,github_actions,gitlab,local,terraform_cloud}.go(.example)
                      outputs_{cb,github,gitlab,local,terraform_cloud}.go(.example)   ← ADD cb/github/gitlab/tfc
1-org/          envs/shared/   modules/{cai-monitoring/function-source, centralized-logging, network}
2-environments/ envs/{development,nonproduction,production}/   modules/env_baseline/
3-networks-svpc/            envs/{shared,development,nonproduction,production}/
                            modules/{base_env, shared_vpc, hierarchical_firewall_policy,
                                     dedicated_interconnect, partner_interconnect, vpn-ha}
3-networks-hub-and-spoke/   envs/{shared,development,nonproduction,production}/
                            modules/{…same… + transitivity}
4-projects/     business_unit_1/{shared,development,nonproduction,production}/
                modules/{base_env, infra_pipelines, single_project}
5-app-infra/    business_unit_1/{development,nonproduction,production}/
                modules/{confidential_space, env_base}
```

## Thin-leaf Pulumi project pattern (the reusable template)
Each leaf dir (`envs/<env>/` or `business_unit_1/<env>/`) contains:
- `Pulumi.yaml` — `name: foundation-<stage>-<leaf>`, `runtime: go`.
- `Pulumi.<stack>.yaml` — committed non-secret config for that leaf (env-specific).
- `go.mod` / `go.sum` — pins the published library modules (NO local replaces in the committed tree; use
  replaces only for the fast-iteration deploy, then re-pin — see Phase 8).
- `main.go` — thin: `loadConfig` → call the shared `../../modules/<mod>` `Deploy(ctx, args)` → export outputs.
- `BUILD` — `pulumi_project(name=…, dir=…)`; run `bazel run //:gazelle` after Go changes.
The shared `modules/<mod>/` holds ALL logic (already exists for most stages from the current flat code — the
restructure MOVES the flat root's body into the shared module + creates the thin leaves that call it).

---

## Phase 0 — Prep & teardown
- [ ] Keep #910 (bootstrap GCS-agent) + #911 (library deps) as the library layer; both merge/release later
      (Phase 8). Work proceeds on `restructure/foundation-upstream-layout` (has both + the stage fixes) via
      local replaces, same fast-iteration path as the redeploy.
- [ ] Tear down the live foundation (all stages except `org-folders`) — approved. Reuse
      `docs/foundation-teardown-redeploy-runbook.md`. Leaves a clean slate to redeploy under the new layout.

## Phase 1 — 0-bootstrap builder modules + outputs (example + live)
Self-contained; no envs restructure. **Delegate to a fable subagent.**
- [ ] Port `modules/cb-private-pool` (Cloud Build private worker pool), `modules/gitlab-oidc` (GitLab WIF pool/
      provider + SA bindings), `modules/tfc-agent-gke` (→ Pulumi Cloud agent on GKE equivalent, documented) as
      full Go modules mirroring upstream's inputs/outputs. Reference upstream module source for each.
- [ ] Add `outputs_cb.go`, `outputs_github.go(.example)`, `outputs_gitlab.go.example`,
      `outputs_terraform_cloud.go.example` mirroring upstream's per-builder outputs.
- [ ] Mirror identically into `infrastructure/pulumi/foundation/gcp-bootstrap/` (live).
- [ ] `GOWORK=off go build/vet/test` both trees; `bazel run //:gazelle`.

## Phases 2–7 — per-stage envs/BU restructure (one phase per stage; delegate each to a fable subagent)
For EACH stage, the subagent: (a) moves the flat root's body into the shared `modules/<mod>/` (preserving the
cold-deploy fixes), (b) creates the upstream leaf dirs as thin Pulumi projects calling that module, (c) mirrors
into the live tree, (d) builds/tests/gazelle, (e) reports. Leaf sets:
- [ ] **Phase 2 — 1-org:** `envs/shared/`; move `cai-monitoring-function/` → `modules/cai_monitoring/function-source/`.
- [ ] **Phase 3 — 2-environments:** `envs/{development,nonproduction,production}/`.
- [ ] **Phase 4 — 3-networks-svpc + 3-networks-hub-and-spoke:** `envs/{shared,development,nonproduction,production}/` each.
- [ ] **Phase 5 — 4-projects:** `business_unit_1/{shared,development,nonproduction,production}/`.
- [ ] **Phase 6 — 5-app-infra:** `business_unit_1/{development,nonproduction,production}/`.
- [ ] **Phase 7 — cross-cutting:** update `tools/copybara` export map, `.gitignore` allowlists, any workflow
      matrices (`foundation-preview`, release-please components) to the new leaf project paths.

## Phase 8 — Redeploy fresh + land
- [ ] Merge/release #910 + #911 (+ a post-#908 project_factory tag); re-pin every leaf `go.mod` to published
      versions; DROP temp local replaces; gazelle.
- [ ] Redeploy the whole foundation under the new layout, leaf by leaf, in dependency order
      (bootstrap → 1-org/envs/shared → 2-env leaves → 3-networks leaves → 4-projects BU leaves → 5-app-infra
      leaves), each first-apply-clean (billingbudgets quota project for user-cred applies; see runbook).
- [ ] Re-wire CI WIF/GitHub-env bindings to the new leaf projects + new seed/project IDs.
- [ ] Open the restructure PR(s) — per-stage or grouped — with a clean example↔live diff and no temp replaces.

## Verification (each phase)
- `GOWORK=off go build ./... && go vet ./... && go test ./...` in every changed module/leaf (both trees).
- `bazel run //:gazelle` then `bazel build //infrastructure/pulumi/foundation/...` green (no stale BUILD).
- `pulumi preview` per leaf resolves the shared module + plans the expected resources.
- Post-redeploy: every leaf stack applies with **0 errors** on the first apply.
- Example tree diff vs upstream: `gh api .../git/trees` name-for-name parity check per stage.

## Delegation
Dispatch a **fable** subagent per phase with: the phase's exact target leaf list, the thin-leaf template above,
the upstream module reference (fetch source via `gh api repos/terraform-google-modules/terraform-example-foundation`),
and the instruction to keep example + live identical and preserve the cold-deploy fixes. Verify each subagent's
diff + build before the next phase. Phases 1–6 are largely independent (different stages) and can pipeline;
Phase 8 (redeploy) is strictly ordered by stage dependency.
