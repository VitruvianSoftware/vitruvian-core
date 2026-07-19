# Application Alignment Gaps

> **Status:** Living backlog. Last refreshed from a full repository survey covering tech stacks, local dev, CI/CD, hosting, environments/promotion, secrets, governance, and testing/observability.
> **Companion docs:** *Application Catalog & Categories* (the shared app taxonomy and per-app reference) and *Platform Conventions & Principles* (the target standard each app should converge to). Throughout this doc, "the Principles doc" refers to *Platform Conventions & Principles*.

## 1. Purpose & how to use this doc

This is the **delta document**. The Principles doc says where every app *should* be; this one is an honest, evidence-grounded catalog of where the apps *are not there yet*, and what it takes to close each gap.

Use it as a **backlog**, not a spec:

- **Picking work?** Start with the [Alignment Matrix](#2-alignment-matrix) to see the worst-aligned cells, then read the matching gap section for current state, target, action, priority, and effort.
- **Landing a change?** When an app reaches the target for a dimension, flip its matrix cell and strike the gap. This doc is expected to shrink.
- **Adding a new app?** Every gap here is something a new app should be born *without*. The fastest way to retire most of this list permanently is the [app scaffold](#37-no-new-app-scaffold-the-meta-gap) — most rows below exist because new apps were hand-wired.

Each gap is labeled **P0** (blocks the standard / live correctness or security issue), **P1** (real divergence, fix this quarter), or **P2** (cleanup / consistency). Effort is a rough engineering estimate (S = hours, M = a day or two, L = a week+, per app).

Two framing rules this doc enforces:

1. **"No environments" is not always a gap.** The CLIs and agents (`devx`, `homelab`, `mcp-slack`, `nexus-agent`) are *released, not deployed*. They legitimately have no dev→prod ladder. Where that's the correct end state, it's marked **n/a**, not red. The actual gap there is that this is undocumented, so it *reads* as a hole.
2. **A claimed standard that isn't enforced is a gap.** Several "standards" (MIT-via-`addlicense`, `actionlint`, Codecov) are asserted in docs but verifiably not wired or not enforcing. Those are called out explicitly because they are more dangerous than honest omissions.

---

## 2. Alignment Matrix

Legend: **A** = aligned (meets the target) · **P** = partial (works but diverges) · **G** = gap (missing or wrong) · **n/a** = not applicable to this app type.

| App | Local dev | Remote dev | CI/CD | Hosting | Envs / promotion | Secrets / config | Deploy identity | Testing | Observability | Governance |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **tabula** | P | G | A | P | P | P | **G** | P | P | P |
| **oauth-user-inspector** | P | G | P | A | P | A | **A** | P | P | A |
| **devx** | P | G | P | A | n/a | A | n/a | A | A | A |
| **homelab** | P | G | G | A | n/a | P | n/a | P | P | G |
| **mcp-slack** | G | G | P | P | n/a | P | n/a | G | G | G |
| **nexus-agent** | G | G | G | P | n/a | A | n/a | G | G | G |

Reading the matrix:

- **No app is fully aligned across the board.** The closest is `devx`, which is correctly a *released-not-deployed* CLI.
- **The columns hide an inversion worth calling out:** `tabula` has the most mature CI/CD and the *least* reproducible deploy identity (its WIF is click-ops). `oauth-user-inspector` has the cleanest deploy identity (the only Pulumi-codified WIF) but a thinner pipeline (single-shot deploy, development-only). The reference pattern is split across two apps; neither embodies it whole.
- **`mcp-slack` and `nexus-agent` are the consistent laggards** — zero tests, no structured observability, divergent licenses, no publish automation behind their documented install paths.
- **Remote dev is `G` for every app** because there is no standard remote/cloud dev environment at all (only a generic, app-agnostic root `.devcontainer`).

---

## 3. Gaps

Each gap below consolidates the dimension surveys and the explicitly-named session concerns. Priorities reflect blast radius and how badly the gap undermines a *claimed* standard.

### 3.1 No uniform "how to run this app locally" — and tabula's docs actively lie

**Priority: P0 · Effort: M per app (docs) + L for the tabula rewrite**

**Current state.** Five different inner loops coexist with no shared front door:

| App | Local run today |
|---|---|
| tabula | `bazel build\|test\|run //tabula/...`, Bazel-managed hermetic Postgres/Redis for tests |
| oauth-user-inspector | `npm run dev` (concurrently vite + nodemon) — plain npm, bypasses pnpm/Bazel |
| devx | `mage` (magefile.go) |
| homelab | `mise run {build,test,lint}` (.mise.toml) |
| mcp-slack | `npm install && npm run build && npm start` |
| nexus-agent | `npm start` / `./bot.sh` / `node --watch` / DMG — four documented modes |

The worst offender is **tabula**, which ships **two contradictory narratives**. The root README describes the real pnpm+Bazel+Pulumi monorepo flow; but `docs/tabula/getting-started/{setup,development}.md` and `CONTRIBUTING.md` describe a stale pre-monorepo world: `git clone github.com/BlueCentre/tabula`, npm workspaces, `docker-compose up -d` (Postgres 16 / Redis 7), Terraform, `tabcli dev start`, and **Node 18**. None of that is true: there is **no `docker-compose.yml` anywhere in the repo**, the build is Bazel+Pulumi (not npm+Terraform), and Node is pinned to 22. A new contributor following tabula's own getting-started docs cannot get the app running.

Separately, the repo **builds a full local-dev orchestrator (`devx`)** — `devx up`, ephemeral DBs with `.env` injection, `devx scaffold` templates that emit a `devx.yaml` — yet **not one of the six first-party apps contains a `devx.yaml`.** The repo does not dogfood its own tool.

**Target (Principles doc).** One documented "Run locally" contract per app type, `devx` as the dogfooded entrypoint for apps that need backing services, and a single `docs/` local-dev index linking each app's section.

**Recommended action.**
1. Rewrite tabula's `getting-started`/`CONTRIBUTING` to the real Bazel+pnpm+Pulumi flow (fix the `BlueCentre` clone URL, Node 18→22, drop Terraform and the non-existent compose file) — **or** commit the `docker-compose.yml` the docs assume and make them true. Pick one.
2. Add a committed `devx.yaml` to each app, generated from the matching `devx scaffold` template, starting with the two that need Postgres/secret injection: `tabula/api` and `oauth-user-inspector`.
3. Write one `docs/` "Local development" page linking every app's run section.

### 3.2 No remote/cloud dev environment

**Priority: P2 · Effort: M (or S to formally descope)**

**Current state.** A generic root `.devcontainer/devcontainer.json` exists (Bazel+Kind+gcloud+Pulumi kitchen-sink, Codespaces-capable) but is app-agnostic — no per-app post-create, no documented hosted-dev path. Everything is local + CI.

**Target.** Either invest in the `.devcontainer` as a documented Codespaces/Cloud Workstations path (per-app post-create that runs `devx up`), or explicitly declare remote dev out of scope so contributors don't expect it.

**Recommended action.** Make a decision and write it down. This is `G` across all apps today only because it's undecided; a one-paragraph "remote dev is out of scope" note converts six reds to an honest n/a.

### 3.3 Two production build front-doors for the same Cloud Run archetype

**Priority: P1 · Effort: M**

**Current state.** The two SaaS web apps build their container two different ways:

| App | Build mechanism | Base | Package mgr |
|---|---|---|---|
| tabula (`//tabula/api:image`) | Bazel `node_image` + `oci_push` | node:20 | npm |
| oauth-user-inspector | hand-written multi-stage `Dockerfile` + `docker buildx` | node:22-slim | pnpm/corepack |

There is **no rule** saying which a containerized app should use, and tabula additionally still carries a `tabula/api/Dockerfile` (node:20-slim) that **no live workflow references** — vestigial and confusing. The verified core convention (frontends are *not* Bazel-built; Bazel runs only their `jest_test`) is correct and shared, but the production-image path is not.

**Target (Principles doc).** One canonical container-build mechanism for Cloud Run apps, on a shared base (node:22-slim + pnpm, non-root, healthcheck, frozen lockfile in CI), emitted by the scaffold. Bazel `node_image` is the more-mature, remote-cacheable choice; if Dockerfile+buildx is blessed instead, tabula migrates onto it.

**Recommended action.** Pick one. Converge both apps. Delete `tabula/api/Dockerfile` if it is truly unused. Have the scaffold emit the chosen path.

### 3.4 Three Go task runners + Go version drift

**Priority: P1 · Effort: S–M**

**Current state.** Both Go CLIs are Gazelle/Bazel targets, but each adds a *different* out-of-band runner: **`devx` uses Mage**, **`homelab` uses `mise`**, and the Pulumi projects use Bazel `sh_binary` wrappers. A contributor switching directories must learn a different "how do I build" each time. (The Go _version_ drift this section also flagged — `go.work` 1.26.2 vs `devx` 1.25.5, `infrastructure/pulumi` 1.26.1, and four more behind — has since been **fixed**: every `go.mod` was aligned to `go.work` 1.26.2 and is now enforced by `//tools/conformance:check`, see [3.22](#322-no-toolchain-version-enforcement-or-environment-self-check). The _task-runner_ divergence remains.)

**Target.** One Go developer build (Bazel `go_binary` as source of truth; `mise` is the alternative pick since it also pins the toolchain — choose one), `goreleaser` only for mirror releases, and every `go.mod` pinned to the `go.work` toolchain version with a CI `//:tidy`/version check that fails on drift.

**Recommended action.** Converge `devx` and `homelab` onto one runner, delete the other. (Pinning all `go.mod` files to the workspace Go version + a drift gate is **done** — every `go.mod` == `go.work`, enforced by `//tools/conformance:check`.)

### 3.5 No written app-type → hosting-target rule

**Priority: P1 · Effort: S (doc) + the per-app cleanups below**

**Current state.** The repo has four hosting targets and the mapping is purely conventional, reverse-engineered from each app's files:

| Hosting target | Apps | Mechanism |
|---|---|---|
| GCP Cloud Run | tabula, oauth-user-inspector | image → Artifact Registry → Pulumi `cloudrunv2`, WIF, per-app GitHub Environment |
| Standalone repo + Homebrew/Releases | devx, homelab | goreleaser binaries + tap |
| Standalone repo + npm / DMG | mcp-slack, nexus-agent | `npx` / macOS DMG |
| dev-local k3s (ArgoCD GitOps) | *platform infra only* | app-of-apps; the one app wired for it (tabula) is checked in **disabled** |

A new app has nothing authoritative to follow. tabula even straddles two targets: it has a live-but-**disabled** k8s path (`gitops/argocd/applications/tabula.yaml.disabled` + `tabula/deploy/chart`, published OCI to GHCR) whose status — supported self-host option vs abandoned scaffolding — is undocumented.

**Target (Principles doc).** A published app-type → hosting-target decision matrix, referenced from each app's README/AGENTS, and encoded in the scaffold so the target is chosen at creation.

**Recommended action.** Write the matrix. Then resolve tabula's dual identity: declare Cloud Run the sole production host and remove the disabled Application + `deploy/chart` dirs, **or** keep k8s as a deliberate option and document when it's used. Do not leave a half-wired second target in the tree.

### 3.6 No traversable dev→staging→prod ladder — even tabula can't promote past `development`

**Priority: P0 · Effort: M**

**Current state.** This is the headline environments gap, and it's verified against the filesystem. tabula's deploy workflow and `repo_config` offer `development`/`nonproduction`/`production`, and `infrastructure/pulumi/apps/tabula/main.go` branches on all three — but the **only committed Pulumi stack files anywhere under `infrastructure/pulumi` are `development`/`dev`**:

```
oauth-user-inspector/infra/app/Pulumi.development.yaml
oauth-user-inspector/infra/identity/Pulumi.development.yaml
infrastructure/pulumi/apps/tabula/Pulumi.development.yaml
infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml
infrastructure/pulumi/platform/dev-local/Pulumi.example.yaml
```

There are **zero `nonproduction`/`production` stacks**. So even the reference app cannot be promoted past development without first creating those stacks — the ladder is wired in CI and code but **not traversable**. `oauth-user-inspector` is worse: its `workflow_dispatch` choice list is `development`-only and its rollout is a straight cutover (no candidate/smoke/traffic-shift) vs tabula's real blue-green (no-traffic candidate → smoke → `promote=true` shift).

**Target (Principles doc).** Every Cloud Run app has at minimum `development` (auto on main) and `production` (workflow_dispatch + environment protection + required reviewer), each backed by (a) a committed `Pulumi.<env>.yaml` and (b) a GitHub Environment codified in `repo_config`. Promotion = re-run the same workflow against the higher env with the **same git SHA** (immutable image, promote-by-tag). tabula's blue-green is the shared rollout primitive, backported to oauth.

**Recommended action.** Commit the missing `Pulumi.<env>.yaml` stacks (at least `production`) per Cloud Run app, **or** explicitly scope each app to development-only and delete the dead env slots from the workflow + `repo_config` until a real target exists. Do not ship environment options that have no backing stack. Backport the candidate→smoke→promote pattern to oauth.

### 3.7 Live secrets-model violation: a Pulumi-encrypted key committed to git

**Priority: P0 · Effort: S (code) + rotation · Status: code done (#456), rotation pending**

**Original state.** `infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml` contained `buildbuddyApiKey: secure: AAAB...` and `main.go` read it via `cfg.RequireSecret` with **no env-injection fallback** — the single live violation of the formalized invariant (*secrets never in git, not even Pulumi `secure:`-encrypted*), and the only Pulumi stack not CI-reproducible the formalized way. The env-or-config pattern existed only as the private `envOrConfigSecret()` in `pkg/copybara_sync`, so every new secret-bearing stack re-decided how to handle secrets (and `repo_config` got it wrong).

**Target (Principles doc).** Tier-3 Pulumi secrets follow "env in CI / gitignored config locally, value never in git," routed through one shared helper.

**Resolution.**
1. ✅ The `secure:` blob is removed from the committed file; `repo_config` reads the key from the `BUILDBUDDY_API_KEY` env (CI pipeline secret) with a gitignored config fallback locally (#484).
2. ✅ The helper is promoted to a shared library module `infrastructure/pulumi/pkg/secrets` — `EnvOrConfig` (required) and `EnvOrConfigOptional` (nil when absent) — and both `copybara_sync` and `repo_config` route through it via a local `replace` (#486). Non-secret values stay committed as config-as-code.
3. ⏳ **Remaining:** rotate the BuildBuddy key (it has been in git history) and update the pipeline secret. This is an operator action at the BuildBuddy console, guided by `bazel run //tools/rotate-buildbuddy-key`.

### 3.8 tabula's WIF deploy identity is click-ops

**Priority: P0 · Effort: M**

**Current state.** The inversion noted in the matrix: the **most-deployed** app is the one **not** following the keyless-identity-as-code standard. `oauth-user-inspector-deploy-identity` is the reference — a Pulumi bootstrap of a repo-scoped WIF pool/provider + least-privilege deploy SA + runtime SA. tabula has **no equivalent**: its WIF pool/provider are click-ops, and only the resulting identifiers are mirrored into `repo_config`'s `tabulaVars` after the fact. The identity backing the most-mature deploy is the least reproducible and reviewable.

**Target (Principles doc).** A codified per-app deploy-identity Pulumi bootstrap, modeled on `oauth-user-inspector-deploy-identity`, is mandatory for every Cloud Run app.

**Recommended action.** Author `infrastructure/pulumi/apps/tabula-deploy-identity` mirroring the reference pattern, **import** the existing click-ops resources into its state, and make *it* (not hand-entered `repo_config` values) the source of truth for tabula's WIF provider/SA identifiers.

### 3.9 oauth's GitHub Environment + Actions variables are click-ops

**Priority: P1 · Effort: S**

**Current state.** The mirror image of 3.8. `repo_config`'s environment logic is tabula-specific — the Pulumi function is literally named `tabulaEnvironments`. There is **no oauth equivalent**, so the `oauth-user-inspector-development` GitHub Environment and its non-secret Actions variables that the deploy workflow depends on are unmanaged click-ops.

**Target.** All GitHub Environments + their non-secret variables codified in `repo_config`, via an app-agnostic per-app helper.

**Recommended action.** Generalize `tabulaEnvironments` into a generic `envForApp` helper and add an `oauthVars`/`oauthEnvironments` block. (Rename the function while you're there — it manages more than tabula.)

### 3.10 `actionlint` is claimed but absent; ESLint configured but never gated

**Priority: P1 · Effort: S each (actionlint addressed)**

**Current state.** Two "standards" that don't exist where it counts:

- ✅ **`actionlint`** was missing, but has now been added (`.github/workflows/actionlint.yaml`) and wired as a required merge-queue check in `repo_config`.
- **ESLint** is configured (`eslint.config.mjs`) but **never enforced** — only prettier formatting runs (via `bazel run //:tidy`). TS lint rules can drift or break with no gate.

**Target.** `actionlint` is a required CI job; ESLint runs in the lint gate (a Bazel eslint target or a CI step) so configured rules actually fail PRs. Optionally add a workflow-pinning/`zizmor`-style security check (third-party actions are already mostly SHA-pinned).

**Recommended action.** Add the ESLint gate to monorepo CI, and to the mirror-CI template (3.11). (The `actionlint` job is completed.)

### 3.11 Two parallel, divergent CI surfaces (the standalone-mirror CIs)

**Priority: P1 · Effort: M (build the templates) + S per app**

**Current state.** Monorepo CI is Bazel `//...` and shared. But each app's **standalone-mirror** `<app>/.github/workflows/ci.yml` (copybara-exported) is **hand-authored with a different native toolchain**, and they diverge heavily:

| App | Mirror CI toolchain | Runner | Test? | Lint? | Notable |
|---|---|---|---|---|---|
| devx | setup-go + golangci-lint + `go test -race` | ubuntu | yes | yes | Butane validation job; hand-rolled |
| homelab | **`mise run`** on **macos-latest** | macOS | yes | yes | biggest outlier; older action pins (checkout@v4) |
| mcp-slack | `npm ci` + `npm run build` | ubuntu | **no** | no | no test/lint job at all |
| nexus-agent | `node --check` (syntax only) + `swift build` | mixed | **no** | no | weakest test story in the repo |

Pins (checkout v4 vs v6), runners, and which checks run all differ. `homelab` and `nexus-agent` are the worst.

**Target.** Generate each mirror `ci.yml` from a shared per-language template (the `aspect-workflows-template` lineage): one Go matrix (setup-go + golangci-lint + `go test -race`), one Node matrix (pnpm install + lint + test + build). Pin runner timeouts, concurrency, and SHA-pinned actions in the template.

**Recommended action.** Build the two templates, move `homelab` off macos-latest/`mise`-in-CI onto the standard Go template, and give `mcp-slack` and `nexus-agent` real test+lint jobs.

### 3.12 No reusable Cloud Run deploy workflow

**Priority: P1 · Effort: M (Partially Addressed)**

**Current state.** tabula and oauth-user-inspector are both Cloud Run + WIF + Pulumi and their deploy workflows are near-identical in *shape* (auth → ensure-AR-repo → build/push image → `pulumi up` → smoke) yet **share zero code**. tabula adds blue-green + a `prisma migrate` step + 3 environments; oauth is single-shot, development-only. A new Cloud Run app has no thin caller to copy.

**Addressed in this PR.** A reusable workflow `_deploy-cloud-run.yaml` was extracted, and `tabula-deploy.yaml` has been converted into a thin caller of this shared pipeline.

**Remaining.** `oauth-user-inspector-deploy.yaml` has not yet been converged onto `_deploy-cloud-run.yaml` (it still uses `docker buildx` natively instead of Bazel OCI rules). Converge it.

**Target (Principles doc).** One reusable `_cloud-run-deploy.yaml` (the oauth pattern as base) with optional blue-green/migrate inputs (tabula's logic), parameterized by GitHub Environment, so a new Cloud Run app is one caller file.

**Recommended action.** Converge `oauth-user-inspector` onto the new reusable workflow. This folds together cleanly with 3.6 (ladder) and 3.8/3.9 (identity/env codification).

### 3.13 Documented distribution with no publishing automation

**Priority: P1 · Effort: M each**

**Current state.** Two apps document an install path that **no CI produces**:

- **mcp-slack** — README says `npx -y @vitruviansoftware/mcp-slack@latest`, and the package has a `bin` entry, but **no npm-publish workflow exists** (the only mcp-slack workflow is copybara export). The documented `npx` path has nothing behind it.
- **nexus-agent** — README documents a DMG from Releases + a Gemini-CLI extension, but there is **no DMG-build/notarize workflow**. Its npm package is also named `nexus-agent` (not org-scoped like `@vitruviansoftware/mcp-slack`), which will collide with the public npm namespace if ever published.

**Target.** Every shipped artifact has a CI build that produces it: `release-please` + npm-publish for mcp-slack; a notarized-DMG release workflow (or goreleaser-equivalent) for nexus-agent.

**Recommended action.** Add the publish workflows so the READMEs become reproducible. Scope `nexus-agent` to `@vitruviansoftware/nexus-agent` (and decide whether it distributes via npm at all, or DMG-only).

### 3.14 License divergence — and the check that's supposed to catch it doesn't

**Priority: P0 · Effort: S (relicense) + S (the real gate)**

**Current state.** The repo claims MIT + VitruvianSoftware, enforced by `addlicense`. Reality:

| App | LICENSE | Source headers | Holder issue |
|---|---|---|---|
| tabula | MIT | MIT/VitruvianSoftware | `Copyright (c) 2025 **BlueCentre**` |
| oauth-user-inspector | MIT | MIT/VitruvianSoftware | — (reference) |
| devx | MIT | MIT/VitruvianSoftware | — (reference) |
| homelab | **Apache-2.0** | MIT (disagree!) | LICENSE ≠ headers |
| mcp-slack | **Apache-2.0** | **Apache-2.0** header (`Vitruvian Software`, note the space) | both wrong |
| nexus-agent | **Apache-2.0** | MIT (disagree!) | LICENSE ≠ headers; `package.json` also Apache-2.0 |

Critically, the **license-check CI does not actually enforce MIT-ness or the holder**. `addlicense -check` only verifies a recognized header is *present* — verified empirically: the exact CI command exits 0 clean on the current tree despite the Apache files, and a fabricated `Apache / SomeRandomCorp` header also passes. The "MIT enforced repo-wide" invariant is **not enforced**.

**Target (Principles doc).** One MIT license + `VitruvianSoftware (c) 2026` across all first-party apps; a real content gate that fails CI on non-MIT or wrong-holder headers/LICENSE files; all four governance files generated from one template so LICENSE and headers can't drift apart.

**Recommended action.** Relicense `homelab`/`mcp-slack`/`nexus-agent` to MIT; fix tabula's `BlueCentre` holder; replace mcp-slack's Apache source header. Add a grep/diff (or small custom checker) alongside `addlicense` that fails on non-MIT or non-VitruvianSoftware content. Also fix `nexus-agent`'s `package.json` license field (license-check covers headers, not `package.json` fields).

### 3.15 Uneven governance files; no root governance set

**Priority: P2 · Effort: S**

**Current state.** Per-app governance is patchy: **tabula** has no standalone `CLA.md` and no `CODE_OF_CONDUCT.md` (only an inline section in a 747-line `CONTRIBUTING.md`); **homelab** and **nexus-agent** lack `CODE_OF_CONDUCT.md`. There is **no root-level governance set** — every app reimplements its own, ranging from 21-line stubs to 747 lines, and only `devx/CONTRIBUTING.md` documents the `Co-Authored-By` trailer. Also: **tabula is the only first-party app not Copybara-mirrored** (the other five are in `tools/copybara/copy.bara.sky`), and whether that's intentional is undocumented.

**Target.** Identical governance quartet (LICENSE, CONTRIBUTING, CLA, CODE_OF_CONDUCT) per app, generated from one template; a thin per-app CONTRIBUTING that links a canonical root CONTRIBUTING/CODE_OF_CONDUCT (which should be added). Commit/PR/merge-queue conventions documented once at root.

**Recommended action.** Add the missing files, add a root governance set, and either add tabula to the Copybara `COMPONENTS` list or document it as intentionally un-mirrored.

### 3.16 Testing coverage is concentrated in one app

**Priority: P1 · Effort: M–L**

**Current state.**

| App | Tests | Coverage gate |
|---|---|---|
| tabula | 4 Jest suites + Playwright e2e (hermetic Bazel stack) | api 85/70, extension 80/65; **web + cli: none** |
| oauth-user-inspector | one ts-jest server suite; **React frontend untested** | none |
| devx | 107 test files vs 274 source; integration-tagged | none (but strong) |
| homelab | **3 test files vs 23 source**; lima/cluster/k3s untested | none |
| mcp-slack | **zero tests** | — |
| nexus-agent | **zero tests** (macOS app compile-checked only) | — |

`mcp-slack` and `nexus-agent` sit **outside the test sweep entirely** (compile-checked only). `homelab` is alarmingly thin given it provisions the **live** homelab cluster. `ADR-003` claims Codecov gating, but **Codecov is not wired**.

**Target (Principles doc).** A minimum test gate per language wired as a Bazel test target (so everything enters the sweep): `go test -race` with a coverage floor (devx is the reference); Jest + `coverageThreshold` for TS, every frontend gets a Jest smoke suite. Wire Codecov or delete the claim from ADR-003.

**Recommended action.** Add minimal unit suites for `mcp-slack` (tool handlers) and `nexus-agent` (formatter/sessions) as Bazel `jest_test`/`go_test`. Add `coverageThreshold` to tabula web/cli and oauth. Raise `homelab` coverage on cluster/k3s/lima using devx's table-test+fake patterns. Resolve the Codecov claim.

### 3.17 No uniform observability baseline; Cloud Run apps have no probes; alerting routing is click-ops

**Priority: P1 (P0 for the alerting routing) · Effort: M**

**Current state.** Observability is bimodal and per-app:

- dev-local k8s has a full Prometheus/Grafana/Loki/Tempo/OTel stack with a GitOps-codified **alerting ruleset** — but the **Alertmanager routing/receivers** (healthchecks.io dead-man's-switch + null receiver) are **absent from git**, so notification delivery is out-of-band click-ops. This violates the closed-loop GitOps mandate and is effectively **P0** for the platform (it's the long-open R3 alerting gap).
- Cloud Run apps log structured (tabula pino, oauth winston) and both have a `/health` + Dockerfile `HEALTHCHECK` + post-deploy curl smoke — but **neither declares Cloud Run startup/liveness probes in Pulumi** (the Dockerfile HEALTHCHECK is ignored by Cloud Run), so an unhealthy-but-booted revision can serve traffic outside the smoke window.
- `mcp-slack` and `nexus-agent` emit only raw `console`/stderr — no structured logger, correlation IDs, metrics, or health surface.

**Target (Principles doc).** Per-type observability standard: structured JSON logger everywhere, `/health` (+ `/ready`), correlation IDs; Cloud Run startup+liveness probes in the `cloudrunv2` container spec; the dev-local Alertmanager route/receivers codified in git via the Prometheus ApplicationSet (healthchecks.io URL via sealed-secret).

**Recommended action.** Codify the Alertmanager config in git (P0). Add startup+liveness probes to both Cloud Run apps' `/health` endpoints. Put `mcp-slack`/`nexus-agent` on a real logger.

### 3.18 IaC reproducibility: gitignored Pulumi stack config

**Priority: P1 · Effort: S (already mostly patterned) · Status: resolved (#486)**

**Original state.** `Pulumi.<stack>.yaml` is gitignored for secret-bearing stacks, so a stack can't be applied in CI without injecting config from pipeline secrets. The env-or-config pattern (CI env / local config / value never in git) **solves this**, but it was implemented only as a private helper in `copybara_sync`. The Cloud Run deploy stacks dodge the problem differently (runtime secrets live in GCP Secret Manager; their committed `Pulumi.development.yaml` holds only non-secret identifiers) — which is fine, but there was no shared helper or documented rule, so each new stack re-decided (and `repo_config` decided wrong — see 3.7).

**Target.** One documented Tier-3 rule and one shared helper; every secret-bearing stack reproducible in CI.

**Resolution.** ✅ Same fix as 3.7 — the helper is now the shared `infrastructure/pulumi/pkg/secrets` module (`EnvOrConfig` / `EnvOrConfigOptional`), routed through by `copybara_sync` and `repo_config` and documented in the Principles doc and CONTRIBUTING (#486). This gap and 3.7's code half close together; only 3.7's key rotation remains.

### 3.19 The local gitignored-`.env` convention is undocumented for half the apps

**Priority: P2 · Effort: S**

**Current state.** `tabula` (`api/.env.example`), `devx`, and `nexus-agent` ship a committed `.env.example`. **`mcp-slack`, `oauth-user-inspector`, and `homelab` do not** — so "how do I supply secrets to run this locally" is partly tribal knowledge. `mcp-slack` reads `SLACK_*` straight from `process.env` with no example; `oauth` reads runtime secrets from GCP Secret Manager but documents no local keys.

**Target.** Every app that reads env/secret config ships a committed `.env.example` (placeholders only) listing required keys.

**Recommended action.** Add `.env.example` to `mcp-slack`, `oauth-user-inspector`, and `homelab`. This is the cheap, uniform documentation of the local-secrets model and dovetails with 3.1.

### 3.20 Sealed-secrets rotation/runbook undocumented in-tree

**Priority: P2 · Effort: S**

**Current state.** `gitops/argocd/platform/sealed-secrets-manifests/` holds ~13 critical SealedSecrets — including the **zitadel masterkey whose loss is total data loss** and `minio-root` — but there is no README/runbook beside them; rotation/backup logic lives only in Makefile targets referenced from commit history. (A top-level `docs/sealed-secrets.md` and `docs/key-rotation.md` exist, but the manifests dir itself is undocumented.)

**Target.** A short README in `sealed-secrets-manifests/` documenting how to (re)seal, rotate, and back up each secret, linking the existing `sealed-secrets-verify`/`backup` make targets, so the GitOps secrets tier is self-documenting.

**Recommended action.** Add the README; cross-link the existing `docs/sealed-secrets.md`.

### 3.21 No "new app" scaffold covering build+deploy+secrets+env (the meta-gap)

**Priority: P0 · Effort: L**

**Current state.** `devx scaffold` templates (`go-api`, `node-api`, `next-app`, `python-api`, `go-cli`, `empty`) emit a runnable skeleton — Dockerfile, `go.mod`/`package.json`, a `devx.yaml`, a `.gitignore` that excludes `.env` — **but no Bazel BUILD files, no per-app deploy workflow, no Pulumi deploy-identity (WIF) project, and no GitHub-Environment/secrets wiring.** A new app therefore starts **non-aligned** — which is exactly how `oauth-user-inspector` arrived needing to be hand-wired this engagement. **Almost every gap in this doc exists because new apps were hand-assembled.** This is the single highest-leverage fix: the scaffold is the enforcement mechanism for the entire Principles doc.

**Target (Principles doc).** A fixed matrix of app archetypes, one canonical build+package front-door each, and a `devx scaffold` that emits an *already-aligned* app per archetype — Bazel BUILD, the reusable deploy workflow caller, the Pulumi deploy-identity project (modeled on `oauth-user-inspector-deploy-identity`), a committed `devx.yaml`, `.env.example`, the governance quartet, and the mirror CI from the shared template.

**Recommended action.** Extend the scaffold templates to emit all of the above. Every other gap then becomes "retrofit existing apps to what the scaffold now produces," and no *future* app reopens these.

---

### 3.22 No toolchain version enforcement or environment self-check

**Priority: P1 · Effort: S (largely addressed in this PR)**

**Current state.** The only thing pinning a developer's Bazel was `.bazelversion` — which a _non-Bazelisk_ `bazel` ignores entirely. A developer who skipped Bazelisk (or had a stray system `bazel` on `PATH`) would hit cryptic `Unrecognized option` flag errors, lockfile churn, or — worst — a silent local-vs-CI behavior split, with nothing naming the real cause. The `.nvmrc`/`packageManager` pins are likewise only honored by `nvm`/`corepack`, not enforced, and Go versions drift outright ([3.4](#34-three-go-task-runners--go-version-drift)). There was no single command to tell a developer "your environment is wrong — here's what to fix."

**Addressed in this PR.** `MODULE.bazel` now declares `bazel_compatibility = [">=9.1.0", "<10.0.0"]`, so _any_ Bazel out of range fails immediately with a clear message, independent of Bazelisk. And `bazel run //:doctor` (plus per-app `//<app>:doctor`) checks the local toolchain against the source-of-truth files (`.bazelversion`, `.nvmrc`, the root `packageManager`, each app's `go.mod`) and reports missing/wrong tools with fix hints.

**Addressed further (this PR).** The version-drift half is now a real CI gate: **`//tools/conformance:check`** (workflow _Conformance Check_) enforces that every `go.mod` / Dockerfile `FROM node:` / app `packageManager` matches canonical (`go.work` / `.nvmrc` / the root `packageManager`); temporary deviations live in `tools/conformance/version-pins.tsv` with a reason + owner + `review_by`, and the check fails on undeclared drift, on a stale pin (file caught up to canonical), and on an expired pin. All pre-existing Go drift ([3.4](#34-three-go-task-runners--go-version-drift)) was fixed to canonical.

**Remaining.** _Conformance Check_ is now in the merge-queue required-status-check set (via `repo_config`, alongside `tidy-check` — which the docs already claimed but the config had omitted — and a `merge_group` trigger on both workflows), so it gates the queue. Still open: make `//:doctor` a pre-commit/CI check too; and have `devx scaffold` ([3.21](#321-no-new-app-scaffold-covering-builddeploysecretsenv-the-meta-gap)) emit a `doctor` target + conformance-clean pins for every new app.

---

### 3.23 IaC steps that need a local trigger; deploy-ordering not codified

**Priority: P1 · Effort: S (partially addressed in this PR)**

**Current state.** Most state-changing ops are pipeline-triggered (Cloud Run deploys on push, the `repo_config` / `sync-auth` apply workflows, ArgoCD reconcile) — but not all. The `zitadel-apps` Pulumi stack (the hosted OAuth applications) was applied **only** by a local `bazel run …:up`, exactly the "then run X locally" rot principle **§2.14** forbids. Separately, infra→app **ordering** was implicit: `tabula-deploy` correctly *expands* (Prisma `migrate deploy` + a no-traffic candidate) before shifting traffic, but nothing named the rule, so a new deploy could just as easily apply infra *after* the app (**§2.15**).

**Addressed in this PR.** Principles **§2.14** (the pipeline is the only trigger) and **§2.15** (expand → deploy → contract) are codified. The `zitadel-apps` apply is now wired as the gated **expand** job of `oauth-user-inspector-deploy` (runs before the app revision; `vars.ZITADEL_APPS_AUTO_APPLY`-gated so it cleanly no-ops until the machine-user key + org/project IDs are seeded once). The legitimate manual bootstraps (`…-deploy-identity`, `dev-local` — they seed the very identities the pipelines authenticate with) are the documented exception, not violations.

**Remaining.** A maintainer seeds the `ZITADEL_MACHINE_KEY_JSON` secret + the org/project/import IDs (committed `Pulumi.development.yaml`) and flips `ZITADEL_APPS_AUTO_APPLY=true` to activate it. There is still no **reusable** "IaC-as-a-gated-expand-step" pattern — it is hand-wired into one workflow; fold it into the reusable Cloud Run deploy workflow ([3.12](#312-no-reusable-cloud-run-deploy-workflow)) and the scaffold ([3.21](#321-no-new-app-scaffold-covering-builddeploysecretsenv-the-meta-gap)) so every app's deploy inherits expand/contract ordering for free.

---

## 4. What to standardize first

Ordered by leverage (how many gaps a single fix closes) and by live-correctness/security risk. The first three are correctness/security issues that exist *today*; the rest are leverage plays.

| # | Action | Closes / unblocks | Priority |
|---|---|---|---|
| 1 | ✅ **Removed the committed `secure:` BuildBuddy key and routed `repo_config` through the shared `pkg/secrets` helper** (#456 code / #484 / #486) — ⏳ only the operator key rotation remains (`bazel run //tools/rotate-buildbuddy-key`) | 3.7, 3.18 (and the secrets-model invariant) — *a key is in git history now* | P0 |
| 2 | **Codify the dev-local Alertmanager routing/receivers in git** (sealed-secret healthchecks.io URL) | 3.17 — the long-open R3 alerting gap; restores the GitOps closed loop | P0 |
| 3 | **Make license-check actually enforce MIT + holder**, then relicense homelab/mcp-slack/nexus-agent and fix tabula's holder | 3.14 — a claimed invariant is currently fake | P0 |
| 4 | **Extend `devx scaffold` to emit a fully-aligned app** (Bazel BUILD + reusable deploy workflow caller + Pulumi deploy-identity + `devx.yaml` + `.env.example` + governance quartet + mirror CI) | 3.3, 3.4, 3.8–3.13, 3.15, 3.19, 3.21 — stops new apps reopening every gap | P0 |
| 5 | **Codify tabula's WIF deploy-identity as Pulumi** (import click-ops) and **generalize `tabulaEnvironments` → `envForApp`** to cover oauth | 3.8, 3.9 — the two click-ops deploy-identity halves | P0/P1 |
| 6 | ⏳ **Commit the missing `Pulumi.<env>.yaml` stacks (≥ production)** or descope apps to development-only; ✅ **extract the reusable Cloud Run deploy workflow with blue-green/migrate inputs** (partially rolled out to tabula) | 3.6, 3.12 — makes promotion real | P0/P1 |
| 7 | **Fix tabula's local-dev docs** (real Bazel+pnpm+Pulumi flow) and add a `devx.yaml` to tabula + oauth; write the `docs/` local-dev index | 3.1 — stops the docs from lying | P0 |
| 8 | ⏳ **Add `actionlint` (✅ done) + ESLint gates**; build the shared mirror-CI templates and give mcp-slack/nexus-agent real test+lint jobs | 3.10, 3.11, 3.16 | P1 |
| 9 | **Decide and document the app-type → hosting-target matrix**; resolve tabula's disabled k8s path; decide remote-dev scope | 3.5, 3.2 | P1/P2 |

**The single most valuable move is #4 (the scaffold).** It is the enforcement surface for the Principles doc: most rows in [the matrix](#2-alignment-matrix) are red because apps were hand-wired, and a scaffold that emits an already-aligned app is what stops this backlog from regrowing every time a new app lands.
