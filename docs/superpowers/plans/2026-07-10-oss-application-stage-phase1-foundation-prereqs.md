# OSS Application Stage — Phase 1 (Foundation Prerequisites) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Land + apply the foundation-side prerequisites that must exist before the OSS app modules and `oauth-user-inspector` deployment can be built (per spec `docs/superpowers/specs/2026-07-10-oss-application-stage-design.md` §7, §12).

**Architecture:** Each task is a separate PR to an existing foundation stack, verified by `pulumi preview` (all changes additive / in-place, zero destructive), landing + applying through the existing foundation release chain (release-please → `deploy-<stage>-{dev,nonprod,prod}` with prod approval) or repo_config auto-apply. These are independent PRs; the **apply order** is A → B → C → D → E per §12.

**Tech Stack:** Pulumi/Go (foundation stacks under `infrastructure/pulumi/foundation/*` + `platform/repo_config`), consumed published `pulumi-library` pins (no `replace`), Pulumi Cloud backend `ipv1337`, Bazel `pulumi_project` wrapper, GitHub Actions promotion chain.

## Global Constraints (verbatim from spec)

- **Upstream-faithful:** default to Google `terraform-example-foundation`; fix genuine port gaps in `pulumi/examples/go-foundation/*` too.
- **No `replace` in live stacks**; consume published pins; `go build`/`go vet`/`go test`/`gofmt` + `tools/license/verify.sh` green; `go mod tidy` clean before push.
- **MIT headers** on live `.go`/`.yaml` (`// Copyright (c) 2026 VitruvianSoftware` + MIT grant); example keeps Apache (license-verify excludes `pulumi/examples/`).
- **Non-destructive:** every preview must be all-creates / in-place updates, **zero deletes/replaces** against existing foundation resources.
- **Gated applies are James's:** merges + production environment approvals are manual; build up to each gate and pause.
- Config namespace per stack = its `Pulumi.yaml` `name` (`foundation-bootstrap`, `foundation-projects`, `foundation-org`, `vitruvian-core-repo-config`).

---

### Task A: gcp-bootstrap — WIF repo-pin (restore upstream repository scoping)

**Files:**
- Modify: `infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.production.yaml`

**Interfaces:**
- Produces: the org WIF provider `foundation-gh-provider` now rejects tokens from any repo except `VitruvianSoftware/vitruvian-core` (closes mirror-spoofing). No output-name change.

Context: `build_github_actions.go:71-75` reads `cfg.WIFAttributeCondition` (config key `wif_attribute_condition`), defaulting to `assertion.repository_owner=='VitruvianSoftware'`. Setting it to a repo-pinned condition is config-only.

- [ ] **Step 1: Set the repo-pinned condition in the committed production config**

Add to `infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.production.yaml` (under `config:`):

```yaml
  # WIF provider accepts tokens ONLY from the monorepo, restoring upstream's
  # per-repository scoping that our monorepo attribute.environment adaptation
  # dropped (closes sibling/mirror-repo environment-claim spoofing). Per-SA
  # scoping still uses attribute.environment/<stage>.
  foundation-bootstrap:wif_attribute_condition: "assertion.repository=='VitruvianSoftware/vitruvian-core'"
```

- [ ] **Step 2: Preview and confirm it's an in-place UPDATE of the provider, not a replace**

Run: `bazel run //infrastructure/pulumi/foundation/gcp-bootstrap:preview -- --stack production --diff`
Expected: exactly one change — `~ update` on `…WorkloadIdentityPoolProvider::foundation-gh-provider` with `attributeCondition` changing to the repo-pinned string. **Zero replaces/deletes.** (attributeCondition is a mutable field → in-place update.) If it shows a replace, STOP and reconsider.

- [ ] **Step 3: Commit + PR**

```bash
git add infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.production.yaml
git commit -m "fix(foundation): pin WIF provider to the monorepo (restore upstream repo scoping)"
```
Open PR; the CI `gcp-bootstrap` preview leg must show the single in-place update. Merge + apply via the bootstrap release chain (foundation-bootstrap env approval). **Gate: James.**

---

### Task B: gcp-bootstrap — folder-level SA grants for `sa-terraform-proj`

**Files:**
- Modify: `infrastructure/pulumi/foundation/gcp-bootstrap/sa.go` (the block granting proj-SA folder roles; near the existing `foundationProjectMetadataUpdater`/proj grants)
- Test: `infrastructure/pulumi/foundation/gcp-bootstrap/config_test.go` (assert the new grants are constructed)

**Interfaces:**
- Consumes: the `fldr-foundation-1` parent folder id from config (`parent_folder`), the proj SA email.
- Produces: `sa-terraform-proj` holds `roles/iam.serviceAccountAdmin` + `roles/secretmanager.admin` at the `fldr-foundation-1` folder, so the per-env identity stacks can create SAs + manage Secret Manager in the oss projects without relying on implicit creator-owner.

- [ ] **Step 1: Read the current proj-SA grant block to mirror its pattern**

Run: `grep -n "sa-terraform-proj\|proj.*IAMMember\|Folder.*IAMMember\|serviceAccountAdmin" infrastructure/pulumi/foundation/gcp-bootstrap/sa.go`
Expected: locate how proj-SA folder/org grants are declared (resource type + args) so the two new grants follow the same idiom.

- [ ] **Step 2: Add the two folder-level grants (FolderIAMMember on `folders/<parent_folder>`)**

Add, mirroring the existing folder-grant idiom in `sa.go` (member = the proj SA, folder = `folders/${parent_folder}`):
- `roles/iam.serviceAccountAdmin`
- `roles/secretmanager.admin`

(Use `organizations.NewIAMMember`/`resourcemanager.NewFolderIAMMember` consistent with the file's existing grants — match what Step 1 found. Additive `IAMMember`, never authoritative `IAMBinding`.)

- [ ] **Step 3: gazelle + build/vet/test**

```bash
cd infrastructure/pulumi/foundation/gcp-bootstrap
GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test ./... && gofmt -l .
```
Expected: all green, gofmt empty.

- [ ] **Step 4: Preview — additive IAM members only**

Run: `bazel run //infrastructure/pulumi/foundation/gcp-bootstrap:preview -- --stack production --diff`
Expected: `+ create` of two `IAMMember` resources, zero deletes/replaces.

- [ ] **Step 5: Commit + PR**

```bash
git add infrastructure/pulumi/foundation/gcp-bootstrap/sa.go infrastructure/pulumi/foundation/gcp-bootstrap/config_test.go
git commit -m "feat(foundation): grant sa-terraform-proj folder-level serviceAccountAdmin + secretmanager.admin"
```
Can share Task A's PR or its own. Merge + apply via bootstrap release chain. **Gate: James.**

---

### Task C: gcp-projects — app-tier APIs, single infra-pipeline, exports (+ port-bug fix)

**Files:**
- Modify: `infrastructure/pulumi/foundation/gcp-projects/business_unit.go` (oss-floating `ActivateApis`; infra-pipeline `ActivateApis`)
- Modify: `infrastructure/pulumi/foundation/gcp-projects/main.go` (export `infra_pipeline_project_id`; export `oss_floating_project_number`; capture the infra-pipeline return)
- Modify: `infrastructure/pulumi/foundation/gcp-projects/business_unit.go` (`BUProjects` struct: add `OSSFloatingProjectNumber`; return it)
- Modify: `infrastructure/pulumi/foundation/gcp-projects/Pulumi.production.yaml` (`infra_pipeline_enabled: "true"`)
- **Port fix (both):** `pulumi/examples/go-foundation/4-projects/main.go` — export `infra_pipeline_project_id` (upstream exports it; our port discards it)
- Test: `infrastructure/pulumi/foundation/gcp-projects/config_test.go`

**Interfaces:**
- Produces (from the **production** projects stack only): `infra_pipeline_project_id`. From every env stack: `oss_floating_project_number`.
- Consumed later by: the app build stack (`infra_pipeline_project_id` off `ipv1337/foundation-projects/production`), zitadel-apps (`oss_floating_project_number` for deterministic Cloud Run URLs).

- [ ] **Step 1: Check upstream's API sets for the floating + infra-pipeline projects and match**

Read `pulumi/examples/go-foundation/4-projects/business_unit.go` (floating project `ActivateApis`) and the upstream `terraform-example-foundation/4-projects` `example_project.tf` / infra-pipeline. Confirm which APIs upstream enables. Then to the **oss-floating** project add (if not already, per app-tier need): `secretmanager.googleapis.com`, `iam.googleapis.com`, `iamcredentials.googleapis.com`. To the **infra-pipeline** project add `iamcredentials.googleapis.com`. (Any API present upstream but missing in our port = a port fix → add to the example too.)

- [ ] **Step 2: Add the APIs (oss-floating block + infra-pipeline block in `business_unit.go`)**

Append the listed APIs to the respective `ActivateApis: []string{…}` slices.

- [ ] **Step 3: Capture + export `infra_pipeline_project_id` (port-bug fix), live and example**

In live `main.go`, change the discarded call:
```go
if cfg.InfraPipelineEnabled {
    infraPipelineID, err := deployInfraPipelineProject(ctx, cfg, commonFolderID)
    if err != nil {
        return err
    }
    ctx.Export("infra_pipeline_project_id", infraPipelineID)
}
```
Apply the same export in `pulumi/examples/go-foundation/4-projects/main.go` (the example currently discards it too — the port bug).

- [ ] **Step 4: Add `OSSFloatingProjectNumber` to `BUProjects` + export it**

In `business_unit.go`: add `OSSFloatingProjectNumber pulumi.StringOutput` to `BUProjects`, default it to `emptyStr`, and in the OSS floating block set `result.OSSFloatingProjectNumber = ossFloatingProject.Project.Number`. In `main.go`: `ctx.Export("oss_floating_project_number", projects.OSSFloatingProjectNumber)`.

- [ ] **Step 5: Enable infra-pipeline in the PRODUCTION stack only**

In `infrastructure/pulumi/foundation/gcp-projects/Pulumi.production.yaml` set `foundation-projects:infra_pipeline_enabled: "true"`. Leave development/nonproduction `"false"` (avoids the 3-duplicate-projects trap).

- [ ] **Step 6: build/vet/test/gofmt (live + example)**

```bash
( cd infrastructure/pulumi/foundation/gcp-projects && GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test ./... && gofmt -l . )
( cd pulumi/examples/go-foundation/4-projects && GOWORK=off go build ./... && GOWORK=off go test ./... )
```
Expected: all green.

- [ ] **Step 7: Preview each env — additive only**

Run preview for development (expect + `oss_floating_project_number` output + the new Services on the oss project; NO infra-pipeline in dev/nonprod), and production (expect + the infra-pipeline project + its APIs + `infra_pipeline_project_id` output). Zero deletes/replaces.

- [ ] **Step 8: Commit + PR (gcp-projects change + example port-fix in one PR)**

```bash
git add infrastructure/pulumi/foundation/gcp-projects pulumi/examples/go-foundation/4-projects/main.go
git commit -m "feat(foundation): app-tier APIs + infra-pipeline + exports for stage 5 (fix infra_pipeline_project_id port bug)"
```
Merge → release-please dev→nonprod→**prod approval** (prod stands up the infra-pipeline project). **Gate: James (incl. prod approval — critical path).**

---

### Task D: gcp-org — DRS override on the oss projects (permit public invoker)

**Files:**
- Modify: `infrastructure/pulumi/foundation/gcp-org/` (a new project-scoped org-policy override; follow the existing org-policy idiom in `policies.go`)
- Test: `infrastructure/pulumi/foundation/gcp-org/config_test.go` if a loader value is added

**Interfaces:**
- Consumes: the per-env oss project ids (from the projects stacks or config). Applied by the **org SA** (holds `orgpolicy.policyAdmin`).
- Produces: `constraints/iam.allowedPolicyMemberDomains` overridden (allow `allUsers`/public) on each `prj-{env}-bu1-oss-floating` project, so `allUsers` `run.invoker` succeeds.

- [ ] **Step 1: Read the existing DRS policy in gcp-org to mirror the resource type + how it's scoped**

Run: `grep -n "allowedPolicyMemberDomains\|domain_restricted\|OrgPolicy\|orgpolicy\|allowAll\|denyAll" infrastructure/pulumi/foundation/gcp-org/policies.go`
Expected: the existing folder/org DRS policy resource + how `domains_to_allow` is applied — mirror it for a **project-scoped** override that allows all (or adds `allUsers`).

- [ ] **Step 2: Add a project-scoped override per oss project**

For each env's oss project id, create a `constraints/iam.allowedPolicyMemberDomains` policy at `projects/<oss-project>` with `allowAll` (or the members needed for public invoker), consistent with the file's org-policy idiom. Gate it behind a config list (e.g. `oss_public_invoker_projects`) so it's explicit + data-driven.

- [ ] **Step 3: build/vet/test/gofmt**

```bash
( cd infrastructure/pulumi/foundation/gcp-org && GOWORK=off go build ./... && GOWORK=off go vet ./... && GOWORK=off go test ./... && gofmt -l . )
```

- [ ] **Step 4: Preview — additive org-policy resources**

Run: `bazel run //infrastructure/pulumi/foundation/gcp-org:preview -- --stack production --diff`
Expected: `+ create` of the project-scoped override(s); zero deletes/replaces to existing org policies.

- [ ] **Step 5: Commit + PR**

```bash
git add infrastructure/pulumi/foundation/gcp-org
git commit -m "feat(foundation): DRS override permitting public invoker on the oss projects"
```
Merge + apply via gcp-org release chain. **Gate: James.** (Must apply before any app stack binds `allUsers`.)

---

### Task E: repo_config — multi-env oauth environments (import-safe)

**Files:**
- Modify: `infrastructure/pulumi/platform/repo_config/main.go` (`oauthEnvironment` → multi-env, mirroring `tabulaEnvironments`)
- Modify: `infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml` (`oauthVars` flat → map-of-maps per env; add `oauth-user-inspector-build`)

**Interfaces:**
- Produces: GitHub Environments `oauth-user-inspector-{development,nonproduction,production,build,preview}` with per-env `GCP_*` vars (dev auto; nonprod/prod reviewer-gated), consumed by the app deploy/build workflows in Phase 3.

- [ ] **Step 1: Read `tabulaEnvironments` + the current `oauthEnvironment` to plan an import-safe migration**

Run: `grep -n "func oauthEnvironment\|func tabulaEnvironments\|pulumi.Import\|oauthVars\|tabulaVars\|ZITADEL_APPS_AUTO_APPLY" infrastructure/pulumi/platform/repo_config/main.go`
Expected: identify the adopted (imported) `oauth-user-inspector-development` resources + fixed logical names that must be PRESERVED (or aliased) so the migration doesn't 409, and the `tabulaEnvironments` map-of-maps loop shape to copy.

- [ ] **Step 2: Refactor `oauthEnvironment` to the 3-env + build + preview loop**

Rewrite `oauthEnvironment` to loop `{development:false, nonproduction:true, production:true}` (reviewer-gated) + a `build` env + preview, reading per-env vars from `oauthVars["<env>"]`, KEEPING the existing `oauth-user-inspector-development` resource logical names (so the imported resources map cleanly). Reconcile the var name: standardize on `GCP_DEPLOY_SERVICE_ACCOUNT` (the workflow reads this) — note it for Phase 3.

- [ ] **Step 3: Update `oauthVars` to map-of-maps in `Pulumi.dev.yaml`**

Convert the flat `oauthVars` to per-env objects (development/nonproduction/production/build) with `GCP_PROJECT_ID`, `GCP_DEPLOY_SERVICE_ACCOUNT`, `GCP_WORKLOAD_IDENTITY_PROVIDER` (= the `foundation-pool` provider). Values for nonprod/prod point at the per-env oss projects + per-env deploy SAs (created in Phase 3 — placeholder-free: use the deterministic names `oauth-user-inspector-deploy@prj-{env}-bu1-oss-floating-<suffix>…`; if a suffix is unknown until deploy, set the var in Phase 3 instead and keep only dev/build here). Keep dev pointing at existing until cutover.

- [ ] **Step 4: build/vet + preview (repo_config)**

```bash
( cd infrastructure/pulumi/platform/repo_config && GOWORK=off go build ./... && GOWORK=off go vet ./... )
bazel run //infrastructure/pulumi/platform/repo_config:preview -- --stack dev --diff
```
Expected: `+ create` of the new environments/vars; the existing `oauth-user-inspector-development` resources show **no replace** (import-safe). Zero deletes.

- [ ] **Step 5: Commit + PR**

```bash
git add infrastructure/pulumi/platform/repo_config/main.go infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml
git commit -m "feat(repo-config): graduate oauth-user-inspector to multi-env GitHub environments"
```
Merge → repo_config auto-applies (REPO_CONFIG_AUTO_APPLY=true). **Gate: James (merge).**

---

## Phase 1 exit criteria

- Bootstrap WIF pinned to the monorepo (applied, non-breaking); proj SA holds folder-level serviceAccountAdmin + secretmanager.admin (applied).
- `prj-c-bu1-infra-pipeline` live (from the production projects stack) exporting `infra_pipeline_project_id`; oss projects have secretmanager/iam/iamcredentials APIs + export `oss_floating_project_number`; example port-bug fixed.
- DRS override live on the oss projects.
- `oauth-user-inspector-{development,nonproduction,production,build,preview}` GitHub environments live.

## Next phases (planned just-in-time after Phase 1 applies)

- **Phase 2 — shared modules:** `pulumi/library/go/pkg/cloud_run` (published) + `serverless_space` module in the example (faithful peer to env_base/confidential_space), + its published-pin plumbing.
- **Phase 3 — oauth-user-inspector multi-env:** app build stack (per-app AR repo + build SA + service-agent AR readers), per-env identity stacks, per-env app stacks (consume the digest), `SECRET_PREFIX` server change + real-secret smoke, zitadel multi-env + cred-sync-to-GCP-SM, build-once/promote-digest CI + the app release/promote chain, gcp-identities.tsv rows, repoint stale app configs.
- **Phase 4 — cutover + deferred:** verify prod, retire the personal `gen-lang-client-*` pipeline; then custom domains + a 2nd app to validate the template.
