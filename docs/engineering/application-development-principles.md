# Application Development Guiding Principles

> **Status:** Authoritative standard for the `vitruvian-core` monorepo. Some rules are marked **(target)** where they are not yet universally adopted — see the [Alignment Gaps](#related-docs) doc for the per-app remediation backlog.
>
> **Audience:** Anyone building a new app in this repo, extending an existing one, or reviewing such a change.

---

## 1. Purpose & how to use this doc

This document sets the **engineering principles** every application in the monorepo is expected to follow, and then translates those principles into a **per-category playbook**. It is opinionated on purpose: these are the conventions new code aligns *to*, not a survey of what exists.

Use it three ways:

1. **Building a new app** — read [§4 Decision guide](#4-decision-guide-choosing-a-category--hosting-target-for-a-new-app) first to pick a category and hosting target, then read that category's section in [§3](#3-per-category-playbook) for the canonical stack, build, deploy, secrets, and observability rules.
2. **Extending an existing app** — read [§2 Cross-cutting principles](#2-cross-cutting-principles-every-app) (they apply to *every* app regardless of category) plus your app's category section.
3. **Reviewing a PR** — use [§2](#2-cross-cutting-principles-every-app) as a checklist. Every principle has a one-line "why" and a concrete "in practice" so a reviewer can point at the exact expectation.

### Related docs

This is one of three companion documents. Read them together:

| Doc | Role |
|---|---|
| **Application Development Guiding Principles** (this doc) | The *principles* and the *per-category playbook* — what good looks like. |
| [Contributing — Standard Operating Procedure](../../CONTRIBUTING.md) | The *mechanical how* — exact commands, file layouts, the build/deploy/secrets recipes, and the contributor SOP (commit format, merge queue, Copybara). Where this doc says "build via the Bazel graph," the SOP says which target. |
| [Alignment Gaps](application-alignment-gaps.md) | The *current delta* — the inventory of where specific apps diverge from these principles, severity-ranked, with remediation recommendations. When this doc marks a rule **(target)**, the gaps doc tracks who isn't there yet. |
| [Core vs. Application Infrastructure](core-vs-application-infrastructure.md) | *Where* a resource's IaC lives — the core/archetype/application split, and the rule that decides the boundary cases. |

When a principle here and a recipe in the SOP appear to conflict, **this doc defines intent and the SOP defines the current mechanism**; fix the SOP, not the principle.

---

## 2. Cross-cutting principles (every app)

These apply to **every** application in the repo — a Go CLI, a Cloud Run service, an MCP server, a Pulumi program, an ArgoCD app. They are the non-negotiable baseline; the per-category sections only *refine* them.

### 2.1 Everything-as-code; no click-ops

**Why:** Click-ops state is invisible, unreviewable, and unreproducible — it rots and drifts.

**In practice:** Infrastructure, deploy identities, GitHub repo settings, and per-app environments are declared in Pulumi (`infrastructure/pulumi/*`) and reconciled, not configured by hand. GitHub branch protection, the merge queue, required reviews, and per-app GitHub Environments are themselves Pulumi-managed (`infrastructure/pulumi/platform/repo_config`). The reference for a *new* deploy footprint is `oauth-user-inspector/infra/identity` — the first WIF identity codified as Pulumi. **(target):** some pre-existing footprints predate this rule (e.g. a Cloud Run app whose WIF pool and Actions variables were created by hand); new work does not add to that debt.

### 2.2 Infra ops run only through the Bazel wrappers

**Why:** Ambient `kubectl`/`pulumi`/`helm`/`gcloud` runs with whatever identity and version your shell happens to have — a recipe for "works on my machine" and wrong-project mistakes.

**In practice:** All Pulumi and GitOps operations go through `bazel run //tools/pulumi:*` and `bazel run //tools/gitops:*`. The Pulumi wrapper injects the correct per-project GCP identity from `infrastructure/gcp-identities.tsv` and a short-lived `GOOGLE_OAUTH_ACCESS_TOKEN` — **never rely on ambient `gcloud`**. No ad-hoc `kubectl apply`, `helm install`, or `pulumi up` from a laptop. These wrappers are for local *preview* and break-glass; the authoritative *trigger* for any apply is the pipeline, not a laptop (§2.14).

This is not just the big three CLIs — **all operational tooling** is a discoverable `bazel run //tools/...` target, never a bare script a developer must locate and invoke by hand: cluster reads/writes (`//tools/gitops:*`, including the Bitwarden-backed `sealed-secrets-{backup,restore,verify}`) and deploy-secret sync (`//tools/sync-env-secrets:{apply,bw-push,bw-pull,unlock,lock}`) and GCP Secret Manager value seeding (`//tools/gcp-secrets:{status,seed}`) and the pre-authenticated Neon/Upstash CLIs (`//tools/saas-cli:{neon,upstash,whoami}`). The wrapper folds in the environment the op needs (`KUBECONFIG`/context, a Bitwarden unlock, the GCP identity) so the human types one uniform command and remembers nothing. Shipping an operational `*.sh` you run directly is the anti-pattern; wrap it (`sh_binary` baking the subcommand) before it lands. Discover them with `bazel query //tools/...`.

### 2.3 GitOps closed-loop for the platform

**Why:** The dev-local cluster is a live homelab; out-of-band changes silently diverge from git and get reverted by reconciliation (or worse, persist undocumented).

**In practice:** Everything on the dev-local k3s cluster reconciles from git via the ArgoCD app-of-apps (`gitops/argocd/root-applications.yaml`). To change the cluster, change git. Manual cluster writes need explicit, per-instance human approval and must be backfilled into git immediately. This is mandatory, not aspirational.

### 2.4 Secrets never live in git

**Why:** A secret in git — *even Pulumi `secure:`-encrypted* — is a secret in history forever, one key-compromise away from disclosure.

**In practice:** Three tiers, each with one owner:

| Tier | Where it lives | Read by |
|---|---|---|
| App **runtime** secrets (Cloud Run) | Per-app **GCP Secret Manager** | The app at runtime (`secretKeyRef` / Secret Manager client). **Never transits CI.** |
| **Pulumi-stack** secrets | Gitignored `Pulumi.<stack>.yaml` locally; the **same value as a GitHub pipeline secret → env** in CI | Pulumi via the shared `secrets.EnvOrConfig(cfg, "ENV_NAME", "configKey")` helper in `infrastructure/pulumi/pkg/secrets` (`EnvOrConfigOptional` when the secret may be absent) |
| **k8s platform** secrets | **sealed-secrets** committed to git (encrypted), reconciled by ArgoCD | The cluster |

Non-secret *identifiers* (project id, region, SA email, WIF provider) **are** committed as config-as-code in `Pulumi.<stack>.yaml`. Every app that reads env/secret config ships a committed `.env.example` with placeholders only. The env-injection helper is now the shared `infrastructure/pulumi/pkg/secrets` module (`EnvOrConfig` / `EnvOrConfigOptional`), which `copybara_sync` and `repo_config` both route through (issue #456); new secret-bearing stacks should use it too.

### 2.5 Reproducibility: local matches CI

**Why:** A pipeline that can't be run the same way locally is a black box; a local flow that CI can't reproduce isn't a build.

**In practice:** The same Pulumi program runs locally (reading a gitignored config file) and in CI (reading the injected env) — that is the entire point of the shared `secrets.EnvOrConfig` helper. Builds and tests are the Bazel graph in both places, with BuildBuddy as remote cache. A stack must be **applyable in CI**: if its config is gitignored, the matching pipeline secrets must exist so CI can inject them.

### 2.6 Keyless, least-privilege identity

**Why:** Long-lived service-account keys are the most common cloud breach vector; broad deploy SAs turn one compromised workflow into total access.

**In practice:** Deploys authenticate via **GitHub Actions Workload Identity Federation** (`google-github-actions/auth`, `id-token: write`) — no JSON keys. Each GCP project gets a repo-scoped WIF pool/provider, a least-privilege **deploy SA**, and a separate **runtime SA**, codified as a Pulumi bootstrap (`oauth-user-inspector-deploy-identity` is the pattern). The only deploy-path GitHub secret is the repo-level `PULUMI_ACCESS_TOKEN` (plus `BUILDBUDDY_API_KEY` for Bazel builds).

### 2.7 One-way code mirroring; edit in the monorepo

**Why:** Two-way sync invites conflicting edits and provenance ambiguity.

**In practice:** First-party apps are mirrored one-way (monorepo → standalone repo in the `VitruvianSoftware` org) via Copybara (`tools/copybara/copy.bara.sky` + per-app `copybara-export-*.yaml` workflows). **Always edit in the monorepo, never the mirror.** A new mirrorable app is added to the Copybara `COMPONENTS` list; if an app is intentionally *not* mirrored, say so explicitly so the omission doesn't read as drift.

### 2.8 Build via the Bazel graph

**Why:** One build graph means one cache, one affected-target computation, one hygiene gate.

**In practice:** Go is Gazelle/`rules_go`; Node/TS libraries and servers are `ts_project`; tests run as Bazel targets (`go_test`, `jest_test`). **Frontends and containerized web apps are deliberately NOT bazel-built** — Bazel runs only their `jest_test`, and the shippable artifact is produced by a Dockerfile (with pnpm) or a Bazel `oci` image. Every shipped artifact must have a CI build+test gate. Repo hygiene is the single `bazel run //:tidy` entrypoint (gazelle + buildifier + prettier/gofmt).

### 2.9 PR + merge queue; finish with a PR

**Why:** The merge queue is the single enforcement authority; local merges bypass review and required checks.

**In practice:** Work lands via PR through the merge queue, never a local merge to the default branch. Required checks are `license-check`, `tidy-check`, `build-test`, `build-macos` (path-gated), `conformance-check`, `actionlint`, `migration-safety`, `go-race`, `osv-scan`, and `secret-scan`. Commits use Conventional Commit subjects and end with the `Co-Authored-By` trailer; a finished branch always becomes a PR.

### 2.10 Observability & health by default

**Why:** An app you can't see is an app you can't operate; an unhealthy-but-booted revision serving traffic is an outage you'll learn about from users.

**In practice:** Every long-running service emits **structured logs** (pino/winston/OTel — not bare `console.log`), exposes a `/health` (and ideally `/ready`) endpoint, and is gated by a post-deploy smoke check. Cloud Run services declare startup + liveness probes in their Pulumi spec **(target)** — a Dockerfile `HEALTHCHECK` is ignored by Cloud Run. Platform services emit to the dev-local Prometheus/Grafana/Loki/Tempo stack, and their alerting routes are codified in git.

### 2.11 Uniform license & governance

**Why:** Inconsistent licensing is a legal liability; missing governance files are a contributor friction tax.

**In practice:** **MIT, `(c) 2026 VitruvianSoftware`**, across all first-party code, enforced by `addlicense` in `license-check`. Every app ships the governance quartet: `LICENSE`, `CONTRIBUTING.md`, `CLA.md`, `CODE_OF_CONDUCT.md`. **(target):** several apps still ship Apache-2.0 `LICENSE` files or wrong holders, and `addlicense -check` only verifies a header is *present* (it won't catch a wrong license/holder) — a content gate is needed; see the gaps doc.

### 2.12 One canonical version; pins are temporary

**Why:** Version drift across the repo ("works on my machine") and stale pins (held back and forgotten) are a slow tax that eventually breaks a build or a deploy.

**In practice:** Every tool has ONE canonical version — the latest the repo has adopted — declared once in its source-of-truth: `.bazelversion` (Bazel), `go.work` (Go), `.nvmrc` (Node), the root `packageManager` (pnpm). Every consumer (each `go.mod`, each Dockerfile `FROM node:`, each app's `packageManager`) must match it. A deviation is allowed only as a **deliberate, temporary, justified pin** — recorded in the registry `tools/conformance/version-pins.tsv` and explained, with its removal plan, in [Version-Pin Exceptions](version-pin-exceptions.md) (the check keeps the two in sync) — carrying a reason, an owner, and a `review_by` date, and removed once its constraint no longer holds. The **conformance check** (`bazel run //tools/conformance:check`, a CI gate) fails on any undeclared drift, on a pin whose file has caught up to canonical (delete it), and on a pin past its review date. Staying on _latest_ is the goal; a pin is a tracked, expiring exception — never a resting place.

**Don't hardcode where you can source.** The best pin is the one you never need: prefer build paths that read the version from the canonical file directly. Bazel images (`node_image`) already take Node from `.nvmrc` via the toolchain (`node_version_from_nvmrc`); Dockerfile-built images parameterize it — `ARG NODE_VERSION` defaulting to the `.nvmrc` major, with the deploy passing `--build-arg NODE_VERSION="$(cut -d. -f1 .nvmrc)"` — instead of a hardcoded `FROM node:<major>`. The conformance check resolves the `ARG` default and still enforces it equals canonical. See [Version-Pin Exceptions § Preventing this class of exception](version-pin-exceptions.md#preventing-this-class-of-exception).

### 2.13 Sanctioned tools only; a new tool needs explicit sign-off

**Why:** Every tool the repo adopts is a permanent tax — one more thing to install, version-pin, secure, wire into CI, and teach. A second tool that does a job a sanctioned one already does fragments knowledge and invites drift, and reaching for an unfamiliar-but-comfortable tool is how that tax gets paid by accident.

**In practice:** Build on the toolchain the repo has already standardized on — **Pulumi-in-Go for all IaC** (never Terraform/OpenTofu/CDK), **Bazel** for the build graph, **ArgoCD + Helm** for the cluster, **pnpm** for Node, **Copybara** for mirroring, **Dependabot** for gomod/npm/github-actions dependency updates. Solving a problem *inside* the sanctioned tool is the default even when another tool looks marginally easier for the case at hand (e.g. a one-off Zitadel application belongs in a Pulumi program under `infrastructure/pulumi/*`, not a new `*.tf`). Introducing a **new** tool, language runtime, or IaC system is a deliberate, maintainer-approved decision: propose it explicitly — what it adds, what it replaces, and why the sanctioned tool can't do the job — and get sign-off **before** it lands, never slipped into the tree alongside a feature. When you are unsure whether something counts as "new," ask first.

**Example of a scoped sign-off:** Renovate was added (2026-07-31, sign-off in the `vitruvian-core-buzz` channel) for exactly one gap Dependabot's ecosystem list doesn't cover — Helm chart version pins inside `gitops/argocd/**` `Application`/`ApplicationSet` manifests (`targetRevision`). Its config (`renovate.json5`) sets `enabledManagers: ["argocd"]`, which disables every other Renovate manager — it can never open a competing PR against anything Dependabot already owns. A sign-off scopes the tool to the gap it was approved for; widening that scope is a new decision, not an assumed extension.

### 2.14 The pipeline is the only trigger; nothing waits on a human's keystroke

**Why:** A step that "just needs someone to run X locally" is the step that silently doesn't happen — it rots, drifts, and blocks both human developers and coding agents, who can't reach a credentialed shell. An SDLC that depends on a local trigger is a runbook, not a pipeline. The goal is a harness that *serves* developers and agents, not a pile of steps they must remember to run.

**In practice:** Every operation that changes a shipped artifact or live state — build, test, package, **IaC apply**, GitOps reconcile, promotion, and post-deploy verification — is initiated by the pipeline (push/merge → GitHub Actions, or git → ArgoCD), never by a person or agent running a command on a laptop. The Bazel wrappers (§2.2) are for local **preview** and break-glass, not the path to prod; a stack that can only be applied by `bazel run …:up` from someone's shell is *unfinished*. The single thing seeded out-of-band is a **root credential the pipeline then uses** — a WIF binding, or a machine-user key stored as a pipeline secret — and that seeding is a one-time, documented bootstrap (the `…-deploy-identity` and `dev-local` Pulumi stacks are the legitimate manual bootstraps; they create the very identities the automated pipelines authenticate with). Until a credential is seeded, gate the automated job so it cleanly no-ops rather than failing the pipeline (the `vars.*_AUTO_APPLY` flag on `copybara-sync-auth-apply` is the pattern). New work that ends in "then run X to apply" is incomplete: wire the trigger.

### 2.15 Infra lands before the app that needs it — expand, deploy, contract

**Why:** A new app revision that reaches for infrastructure not yet in place fails on arrival; a *destructive* infra change applied before the old revision drains breaks what is still serving. Deploy ordering is correctness, not politeness — and it belongs in the pipeline's job graph, not a human's memory.

**In practice:** Sequence infra and app via **expand/contract (parallel change)**, encoded as pipeline ordering:

1. **Expand** — apply *additive, backward-compatible* infra first (a new secret, env var, expand-only DB migration, OAuth redirect URI), with the app deploy **gated** to proceed only on its success. Cross-job `needs:` (or an ordered step) is the mechanism; `tabula-deploy` is the reference — Prisma `migrate deploy` and a no-traffic candidate land before any traffic shifts.
2. **Deploy** the app against the now-present infra.
3. **Contract** — remove the old infra (drop a column, delete a redirect URI, tighten a binding) only **after** the old revision is gone, in a *later* run. Never contract ahead of the rollover; expand changes must stay backward-compatible so a half-applied pipeline (infra ahead of app) is always safe.

Edge cases the sequence must respect: **(a) circular dependency on the app's own URL** — when the infra is "register the app's public URL," that URL must be a **stable, pre-known domain**, not a deploy-minted `*.run.app`, or infra cannot precede the app; provision the stable host first. **(b) Two infra planes order differently** — Pulumi infra chains in the deploy workflow via `needs:`, while ArgoCD-managed infra orders via sync-waves + reconcile and cannot be awaited from an Actions job. **(c) Additive-and-independent infra** the app does not consume at deploy time (e.g. a Zitadel redirect URI — runtime login needs it, the deploy does not) is still expand-first and still pipeline-triggered, but may run as a gated sibling job/workflow rather than hard-blocking the app deploy.

### Expand/contract migrations

Database schema is the sharpest instance of §2.15, because the blue-green rollout runs `prisma migrate deploy` **before** the new revision takes traffic: during the traffic shift the **old** revision keeps serving against the **new** schema. So a deploy-phase migration must be backward-**compatible** with the code already running — otherwise it breaks the live revision the instant it applies, and (Neon has no in-repo PITR) can't be rolled back to. This is enforced, not just documented (issue #819):

- **Expand migrations are the default and must be backward-compatible** — add a nullable/defaulted column, add a table, add an index. The `migration-safety` required check (`tools/ci/migration-safety.sh`, tuned by `tabula/api/prisma/.squawk.toml`, Squawk under the hood) **fails the PR** if an added/modified migration is backward-incompatible: drop/rename a column, narrow a type, add a validated (`NOT VALID`-less) constraint, add a `NOT NULL` column without a default. The gate self-tests on every run, so a mis-tuning surfaces in CI, not on a deploy.
- **Contract migrations are deliberate and separated** — a genuinely destructive change (drop the now-unused column after the new code stopped reading it) is committed as a migration whose directory name **ends in `_contract`** (e.g. `20260701120000_drop_legacy_workspace_id_contract`). That suffix exempts it from the safety gate (it is knowingly backward-incompatible) **and** tells the deploy wrapper not to auto-apply it.
- **The deploy applies only expand; contract is a later, explicit run.** The migrate step runs `migrate-deploy.cjs --phase expand`, which **refuses** if any pending migration is a `*_contract` one (it would be swept in by `migrate deploy`, which always applies *all* pending). You apply the contract deliberately, **after** the new revision has fully replaced the old and soaked, via `--phase contract`. Never contract ahead of the rollover.

The rename-a-column case is two migrations across two deploys: **expand** (add the new column, backfill, write both) → cut over the code → **contract** (drop the old column) in a later run. The gate makes the unsafe single-step rename impossible to merge unmarked.

**When the gate is wrong (a safe change it flags conservatively).** Some rules fire on changes that are actually backward-compatible — a type **widening** (`VARCHAR(100)`→`VARCHAR(500)`, `INT`→`BIGINT`) trips `changing-column-type` even though old code keeps working. That is *not* a contract change, so don't route it through `_contract` (which would force it down the post-soak `--phase contract` path). Instead add a per-statement `-- squawk-ignore <rule>` comment on the line above it; the migration then flows through as a normal expand migration. The ignore is rule-scoped, so it can't mask a different hazard on another statement. Use `_contract` only for changes that are genuinely backward-incompatible.

### 2.16 A human is the last resort; "needs a person" is a claim to disprove

**Why:** A developer or coding agent in this repo holds the **same tools and access** as the maintainer — `gh`, the cloud and IdP APIs, `kubectl`, Pulumi, and (for an agent) the maintainer's browser. Treating a step as "the human must do this" when the tooling can do it manufactures a false blocker that stalls delivery on someone who never needed to be involved. The asymmetry favors acting: a wrongly-automated *additive* step is cheap to undo; a wrongly-deferred one silently rots (§2.14).

**In practice:** Default to **doing it**. Before writing "you need to…", attempt it with the tools at hand — the CLI, the service's own API, an existing admin credential, or the **browser** when an operation is genuinely UI-only (granting a third-party GitHub App access to a repo is the canonical case: the REST API 403s, the browser does not). A human is *genuinely* required only for a short, defensible set:

- **A net-new root of trust no existing anchor can vouch for** — and even then only the first link (§2.17 shrinks this further).
- **Irreversible or destructive** actions — data deletion, prod teardown, contracting infra ahead of rollover (§2.15). Confirm; don't perform.
- **Legal, financial, or policy** calls a maintainer must own — licensing, spend, access policy.

Everything else — provisioning a secret, resolving an ID, granting a scope, minting a credential into a reachable system, re-running a job — is **automatable and therefore yours to do**, with a follow-up note rather than a permission request. When no principle yet steers you to the automated path, the fix is to **add one** (as this section was), not to fall back on a person.

### 2.17 Bootstrap credentials by chaining trust anchors, not by hand-carry

**Why:** "Someone pastes a secret into each environment" is the step that makes a pipeline *feel* human-gated — and the one most apt to leak, drift, or be forgotten. The one-time manual seed §2.14 permits is legitimate but **far narrower than it looks**, because we already hold anchors that can mint the next credential automatically.

**In practice:** To authenticate a pipeline into **any** trust domain — cloud, IdP, registry, cluster — derive the credential from an anchor we already trust, in this order:

1. **Federate the CI's existing OIDC identity.** GitHub Actions OIDC is already trusted by GCP (WIF, §2.6); extend the same token-exchange pattern into the new domain so CI authenticates with **no stored secret**. A new IdP-as-code stack (e.g. Zitadel apps) federates GitHub OIDC → an IdP service user before reaching for a key.
2. **Mint-and-store only if a static credential is unavoidable.** Generate it *programmatically* from an existing admin credential (e.g. the in-cluster, sealed-secret-managed `iam-admin-pat` called over the IdP's public API), write it to the **sanctioned store** (GCP Secret Manager / sealed-secrets / a per-app GitHub Environment, §2.4), and read it keylessly at deploy. Never hand-enter per run; never commit.
3. **Resolve identifiers by name.** Project/app/resource IDs come from the provider's data sources (`getProject` / `getApplicationOidc` / equivalents) — nothing copied out of a console.

A human seed is legitimate **only** when no existing anchor reaches the new domain — and then it is one credential, seeded once via §2.14's bootstrap stacks, never a recurring ask.

### 2.18 Every change ships as code — IaC, GitOps, or a pipeline; never an imperative one-off

**Why:** §2.1 says state is declared as code and §2.14 says the pipeline applies it — the gap between them is where work escapes into click-ops: a `gh secret set` here, a `kubectl apply` there, a `pulumi up` from a laptop "just to unblock myself." Each is invisible, unreviewed, and drift the moment it runs. And §2.16 ("additive changes are yours to do") is easily misread as license to do them *imperatively* — it is not. §2.16 grants the **authority** to make the change; this section fixes the **mechanism**: you make it as code.

**In practice:** Every change to infrastructure, identity, secrets, config, repo settings, a shipped artifact, or live cluster/cloud state is effected through exactly one of three sanctioned mechanisms, chosen by *what* is changing:

| What's changing | Mechanism | Home |
|---|---|---|
| Cloud/identity/repo/env infra, GitHub Actions **secrets & variables**, deploy footprint | **IaC** — Pulumi-in-Go | `infrastructure/pulumi/*` (CI & repo config in `repo_config`) |
| dev-local cluster workloads, platform services, k8s secrets | **GitOps** — ArgoCD reconciling git | `gitops/argocd/*` + sealed-secrets |
| Build, test, package, IaC apply, GitOps nudge, promotion, verification | **Pipeline** — GitHub Actions | `.github/workflows/*` (push/merge / `merge_group`) |

There is **no fourth path.** An imperative one-off — `gh secret set` / `gh variable set`, a console/SaaS click, ad-hoc `kubectl apply`, `pulumi up` from a shell — is only ever a break-glass *preview* (§2.2) or the act of *running* an already-codified change. It is **never the source of truth.** If you reached for one to move fast, the work is **not done until it is reconciled into code** — the secret declared in `repo_config` via `cfg.RequireSecret` (§2.4), the cluster object committed for ArgoCD, the apply wired into a workflow. "I had the access and it was additive" answers *who* may change it (§2.16), never *how*; the how is always code. If none of the three mechanisms obviously fits the work, that is a question to raise (§2.13), not a license to click.

**(target):** the `oauth-user-inspector` deploy environment's `ZITADEL_APPS_AUTO_APPLY` variable and its `ZITADEL_MACHINE_KEY_JSON` / `TS_OAUTH_*` secrets were set with `gh` during bring-up and are not yet declared in `repo_config` — the first debt to repay under this rule.

### 2.19 Every fix ships with the test or check that would catch it again

**Why:** A fix without a guard is one Dependabot bump, refactor, or redeploy away from silently regressing — and a green pipeline that never exercises the failure gives false confidence. Two prod outages shipped past green pipelines exactly this way: a `react`/`react-dom` 18-vs-19 mismatch that broke the SPA's mount (the test suite was backend-only), and a deploy smoke check that asserted HTTP 200 on a static shell which returns 200 even when the app is broken. A passing pipeline must *mean* "the thing works."

**In practice:** When you fix anything testable, the regression guard is part of *done*, not a follow-up. Pick the cheapest layer that actually catches it: a parity/lint check at the source of truth (e.g. assert `react` and `react-dom` share a major in `package.json`), a unit/integration test in the existing CI suite, and — when the break only manifests at runtime — a real post-deploy verification (headless-render and assert a post-mount marker, never a bare `200`). Verify the guard *both* ways: it passes on the fix **and** fails on the original broken state — a check you never watched fail proves nothing. Layer prevention + detection when it's cheap (group the dependency so a bump can't split it, *and* test for the split, *and* catch it at the deploy gate). "It's a small fix" is not an exemption; "there's no way to test this" is a claim to justify, not assume.

---

## 3. Per-category playbook

Pick the category that matches the artifact you are shipping. Each section is self-contained and scannable. The categories are the repo's shared taxonomy; an app occasionally spans two (a SaaS service that also ships a browser client) — in that case follow each category for the corresponding component.

> **Convention used below:** ✅ = the established standard, **(target)** = the standard but not yet universally adopted.

---

### 3.1 SaaS web service

**Definition / when to choose:** A user-facing, internet-hosted app — an HTTP API, a web UI, or both — that builds into a container and serves traffic. Choose this when end users (or other services) hit your code over the network and you need a managed runtime, autoscaling, and a URL. May co-ship multiple components (API + web + browser client + CLI) under one app; each non-service component follows its own category.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | Node 22 + TypeScript, pnpm workspace. **One canonical container front-door (target):** a `node:22-slim` + pnpm, non-root, healthchecked Dockerfile **or** a Bazel `oci` image — converged, not per-app. The frontend (Vite/Next/webpack) is **not** bazel-built; Bazel runs its `jest_test`, the production bundle is built inside the Dockerfile or a publish workflow. |
| **Local dev** | `devx up` brings up backing services (Postgres/Redis) with `.env` injection; the app process runs via its own `pnpm dev`. A committed `devx.yaml` declares the local topology. **(target):** no first-party app dogfoods `devx.yaml` yet — adopt it. |
| **Hosting & runtime** | **GCP Cloud Run**, per-app GCP project, image in per-app Artifact Registry, deployed by Pulumi `cloudrunv2`. |
| **Deploy / CI** | One environment-keyed GitHub Actions workflow: WIF auth → ensure Artifact Registry repo → build/push image (`:${SHA}` + `:latest`) → `pulumi up` (pins `imageTag=SHA`) → curl smoke. **(target):** a shared `_cloud-run-deploy.yaml` reusable workflow so a new app is one thin caller; blue-green (no-traffic candidate → smoke → promote) is the standard rollout primitive and migrations run before the shift. |
| **Environments & promotion** | At minimum `development` (auto on push to main) and `production` (workflow_dispatch + environment protection + required reviewer). **Every** environment must have *both* a committed `Pulumi.<env>.yaml` **and** a Pulumi-managed GitHub Environment — no environment slot without a backing stack. Promotion = re-run the workflow against the higher environment with the **same git SHA** (immutable image, promote-by-tag, never rebuild). |
| **Secrets & config** | Runtime secrets in **GCP Secret Manager**, read at runtime by the runtime SA — never in CI. Non-secret identifiers committed in `Pulumi.<env>.yaml`. Ship a `.env.example`. |
| **Observability** | Structured logger (pino/winston) → Cloud Logging with revision metadata; `/health` endpoint; post-deploy smoke; **(target)** Cloud Run startup + liveness probes in the Pulumi spec. Enforce a Jest `coverageThreshold` (~80%) under `bazel coverage`; every frontend gets at least a Jest smoke suite. |
| **Example apps** | `tabula` (multi-component, blue-green, the most mature deploy), `oauth-user-inspector` (single-container, the cleanest WIF-as-code reference). |

**Watch-outs (from the field):** don't leave a vestigial second Dockerfile or a half-wired k8s `Application.disabled` in the tree — pick one production host and delete the other surface, or document it as deliberately unwired. Don't expose `nonproduction`/`production` workflow options that have no backing Pulumi stack.

---

### 3.2 CLI / developer tool

**Definition / when to choose:** A command-line binary (Go) for developers or operators, distributed and run on the user's own machine — it provisions or operates environments rather than serving traffic. Choose this when the deliverable is a tool a human runs locally, not a service.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | **Go**, pinned to the `go.work` toolchain version **(target)** (drift exists today across 1.25.x/1.26.x — pin every `go.mod`). Bazel `go_binary` is the single developer build source of truth **(target)**; `goreleaser` is used *only* for mirror releases. Retire per-app `Mage`/`mise` divergence onto one task runner. |
| **Local dev** | `bazel run //<app>/...` to build/run; one documented Go task runner for `build`/`test`/`lint`. |
| **Hosting & runtime** | **Not managed-hosted** — runs on the end user's machine. |
| **Deploy / CI** | **Released, not deployed.** Shared Bazel checks in the monorepo; the real release is `release-please` + `goreleaser` from the standalone mirror, producing GitHub Release binaries + a Homebrew tap (`brew install vitruviansoftware/tap/<app>`). **(target):** mirror CI should be generated from a shared Go template (setup-go + golangci-lint + `go test -race`) rather than hand-authored per app. |
| **Environments & promotion** | **None, by design** — version + GitHub Release is the whole story. Classify explicitly as "released-not-deployed" so it isn't mistaken for a promotion gap. |
| **Secrets & config** | Local **gitignored `.env`** from a committed `.env.example`; or a YAML config file. No CI-deployed secrets. `devx`'s `config secrets` command is the reference for local rotation. |
| **Observability** | Structured logging package; emit OTel where the tool warrants it (`devx` ships a telemetry package). Maintain a per-package coverage floor (`devx` is the reference: ~107 test files vs 274 source). |
| **Example apps** | `devx` (local-dev orchestrator), `homelab` (cluster provisioning). |

**Watch-outs:** these two apps currently diverge on task runner (Mage vs mise) and license (Apache-2.0 vs the MIT standard) — a new CLI follows the standard, not the existing drift. High-blast-radius tools (cluster provisioners) need real unit coverage, not a thin 3-of-23 suite.

---

### 3.3 Agent / MCP service

**Definition / when to choose:** A long-running Node/TS process exposing AI-agent capabilities — either a **Model Context Protocol server** consumed by an LLM client, or a **chat bridge** that forwards prompts to a coding CLI. Choose this when the deliverable is agent-facing tooling distributed as an npm bin or run as a local daemon, not a hosted web service.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | Node 22 + TypeScript, a co-located `ts_project` pinned to the repo TypeScript and Node 22 `@types` **(target)** (per-app typedef drift exists). MCP servers ship a `manifest.json`. |
| **Local dev** | Join the **pnpm workspace** (`pnpm install` at root) — don't run bare `npm` despite workspace membership **(target)**. `pnpm build` / `pnpm dev` (tsc watch). |
| **Hosting & runtime** | **Runs on the user's machine** — MCP servers via `npx`, bridges as a local daemon/menu-bar process. No managed runtime. |
| **Deploy / CI** | **Released, not deployed.** **(target):** the documented `npx` install path needs a real `release-please` + npm-publish workflow behind it (today only Copybara export runs — the README's `npx` instruction has no automation). Package names are org-scoped (`@vitruviansoftware/<app>`). |
| **Environments & promotion** | None — distribution-only. |
| **Secrets & config** | Tokens read from `process.env` with a clear required-vars error; ship a committed `.env.example` documenting the keys **(target)** (some servers lack one). |
| **Observability** | Structured logger and a minimal unit suite wired as a Bazel test target so the app enters the test sweep **(target)** — several agents have zero tests and only `console`/`stderr` output today. MCP stdio transports legitimately log to stderr, but the logs should still be structured. |
| **Example apps** | `mcp-slack` (MCP server, dual-token), `nexus-agent` (Telegram→CLI bridge; also ships a Swift macOS client — see §3.5). |

---

### 3.4 IaC / platform definition

**Definition / when to choose:** Code that declares **infrastructure or platform state** rather than application behavior — Pulumi Go programs (per-app Cloud Run deploys, deploy-identity bootstraps, repo self-governance, the k8s bootstrap) and the ArgoCD/Helm app-of-apps. Choose this whenever you are provisioning cloud resources, deploy identities, GitHub settings, or the cluster.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | **Pulumi-in-Go**, one project per concern. Shared logic lives in `infrastructure/pulumi/pkg/*`. ArgoCD/Helm manifests for the cluster (not bazel-built). |
| **Local dev / ops** | **Bazel wrappers only** — `bazel run //tools/pulumi:*`, `bazel run //tools/gitops:*`. The wrapper injects the per-project identity from `gcp-identities.tsv`. Never ad-hoc `pulumi`/`kubectl`/`helm`. |
| **Hosting & runtime** | The resources this code *creates* (Cloud Run, WIF, GitHub settings, the k3s platform). The Pulumi state is the runtime artifact. |
| **Deploy / CI** | Pulumi stacks apply via their preview/apply workflows (`_repo-config-preview.yaml` / `_repo-config-apply.yaml` are the pattern); cluster state applies via ArgoCD reconciliation from git. A new deploy footprint **must** include a codified deploy-identity bootstrap (the `oauth-user-inspector-deploy-identity` pattern). |
| **Environments & promotion** | Cloud Run deploy stacks follow the SaaS ladder (§3.1). The k8s platform promotes via **git → ArgoCD only** — no dev/staging/prod ladder; a change is promoted by being merged. Pin cluster chart images to an immutable SHA, never `latest`. |
| **Secrets & config** | The shared `pkg/secrets` tier (§2.4): gitignored config locally, env in CI, value never in git — via `secrets.EnvOrConfig` / `EnvOrConfigOptional`, which `copybara_sync` and `repo_config` route through (issue #456). New secret-bearing stacks should use it. k8s secrets via sealed-secrets. |
| **Observability** | The platform *is* the observability stack (Prometheus/Grafana/Loki/Tempo). Codify alerting routes/receivers in git **(target)** — Alertmanager routing is currently out-of-band. |
| **Example apps** | `oauth-user-inspector/infra/identity` (reference WIF bootstrap), `infrastructure/pulumi/platform/repo_config` (repo self-governance), `infrastructure/pulumi/platform/dev-local` (k8s bootstrap), `gitops/` (app-of-apps). |

---

### 3.5 Browser extension / client

**Definition / when to choose:** A distributable client artifact — a Manifest-V3 browser extension or a native desktop/menu-bar app — that runs on the **end user's machine** and talks to a backend service. Choose this for the user-installed component of a product, distinct from its hosted API.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | pnpm/webpack (extension) or Swift/`rules_apple` (native macOS). **Not bazel-built for production** — Bazel runs the JS `jest_test` (and *compile-checks* the Swift app, the sole macOS CI leg); the shippable bundle/DMG comes from a publish path. |
| **Local dev** | Load the extension from its built `dist/`; run the native app from Bazel (`bazel build --config=macos-app //<app>/macos:...`). |
| **Hosting & runtime** | The user's browser / Mac. No server. |
| **Deploy / CI** | **(target):** the documented distribution (extension store, notarized DMG, Gemini extension) needs a real CI publish/notarize workflow — today distribution is README-documented but not codified. Store publication (e.g. Chrome Web Store) is an explicit, gated step. |
| **Environments & promotion** | Use **artifact release channels** (alpha/beta/stable) — this is a *distribution train*, orthogonal to server environments. Do not conflate it with the SaaS dev→prod ladder. |
| **Secrets & config** | Client-side config only; backend secrets stay in the backend. |
| **Observability** | App-appropriate client logging; a lightweight Playwright smoke for the critical render+auth path **(target)**. |
| **Example apps** | `tabula/extension` (MV3 Chrome/Edge/Firefox), `nexus-agent/macos` (Swift menu-bar app). |

---

### 3.6 Self-hosted platform service

**Definition / when to choose:** A third-party or platform component that runs on the dev-local k3s homelab and provides substrate for first-party apps (IdP, observability, databases, ingress, CNI). You choose this only when adding/operating a *platform capability*, not application code.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | Upstream Helm chart *consumed as-is* (values-only customization) via an `Application`/`ApplicationSet` under `gitops/argocd/platform/<name>/`; owned static manifests that were never chart-templated (CRs, dashboards, secrets) live in a distinctly-named sibling — `platform/<name>-manifests/` or a clearly-named subdirectory, never flat-mixed with the consuming `applicationset.yaml` (precedent: `sealed-secrets/` vs. `sealed-secrets-manifests/`, `grafana/` vs. `grafana-dashboards/`, `envoy-gateway/gateway/`). A **forked** chart — one whose upstream can't do something we need, so we've taken over its `Chart.yaml`/`templates`/`values.yaml` and now maintain it divergently — must be controller-agnostic: this repo's own GKE posture doc anticipates ArgoCD *or* Config Sync in prod, and Config Sync doesn't read ArgoCD's `Application`/`ApplicationSet` CRDs. So it does **not** live under `gitops/argocd/` at all: it goes in `gitops/charts/<name>/` (see that directory's README for the full how-to), with a header comment or README recording the version forked from, when, and why. Not bazel-built. |
| **Local dev / ops** | `bazel run //tools/gitops:*`; changes land in git and reconcile via ArgoCD. A forked chart under `gitops/charts/*` additionally needs `helm lint` + `helm template \| kubeconform` — `tools/ci/gitops-validate.sh` only validates static YAML under `gitops/argocd/**` today and cannot parse a chart's unrendered `{{ }}` templates **(target: extend gitops-validate.sh to cover gitops/charts/**)**. |
| **Hosting & runtime** | dev-local k3s (5-node laptop homelab). Storage = local-path + app-level redundancy. |
| **Deploy / CI** | **GitOps only** — ArgoCD app-of-apps (`selfHeal`, `prune:false`). No imperative apply. |
| **Environments & promotion** | git → ArgoCD; promoted by merge. |
| **Secrets & config** | **sealed-secrets** committed to git, reconciled by ArgoCD. Each critical secret (e.g. the Zitadel masterkey — *loss = total data loss*) has a documented (re)seal/rotate/backup runbook beside it **(target)**. |
| **Observability** | First-class — these *are* the metrics/logs/traces backends. Alerting routes codified in git **(target)**. |
| **Example services** | Zitadel (IdP at `auth.ipv1337.dev`), Prometheus/Grafana/Loki/Tempo, CNPG, MinIO, Cilium, Envoy Gateway, sealed-secrets, cloudflared. |

---

### 3.7 Shared library / tooling

**Definition / when to choose:** Cross-cutting build, CI/CD, and code-sharing machinery that is not itself a deployable product — Bazel rules and run-wrappers, Copybara config, OCI image rules, the GitHub Actions pipelines that gate every other app, and repo-wide standards enforcement. Choose this when you are changing *how the repo builds, ships, or governs* rather than shipping an app.

| Aspect | Standard |
|---|---|
| **Tech stack & build** | Bash + Starlark (Bazel) + Go. Lives in `tools/` and `.github/workflows/`. |
| **Local dev** | `bazel run //:tidy` is the single hygiene/format gate; affected-target logic via `tools/ci/affected-targets.sh`. |
| **Hosting & runtime** | Runs *in CI* and *in the build graph* — no managed runtime. |
| **Deploy / CI** | This category *is* CI. The merge queue is the single enforcement authority; required checks are `license-check`, `tidy-check`, `build-test`, `build-macos`, `conformance-check`, `actionlint`, `migration-safety`, `go-race`, `osv-scan`, and `secret-scan`. `charts-publish.yml` ships OCI Helm charts to GHCR. |
| **Environments & promotion** | N/A — changes ship by merge. |
| **Secrets & config** | Only `PULUMI_ACCESS_TOKEN` + `BUILDBUDDY_API_KEY` on the deploy path. No secret in a committed config — including the repo-governance stack **(target)**. |
| **Observability** | CI is the observability surface; keep workflows lint-clean and SHA-pinned. |
| **Examples** | `tools/pulumi` & `tools/gitops` (bazel wrappers), `tools/copybara`, `tools/oci`, `.github/workflows/ci.yaml` + per-app deploy/export workflows, `tabula/shared` (in-app shared types). |

---

## 4. Decision guide: choosing a category & hosting target for a new app

Answer these in order. The first match is your category.

1. **Is it infrastructure/platform state (cloud resources, deploy identity, repo settings, the cluster) rather than app behavior?**
   → **IaC / platform definition** (§3.4). If it's a third-party component to run *on* the cluster → **Self-hosted platform service** (§3.5/§3.6).

2. **Is it build/CI/code-sharing machinery used by other apps, not a product itself?**
   → **Shared library / tooling** (§3.7).

3. **Does it serve traffic over the network to users/other services and need a managed runtime + URL?**
   → **SaaS web service** (§3.1) → **Cloud Run**, per-app GCP project, WIF + Pulumi.

4. **Is it a command-line binary that developers/operators run on their own machine?**
   → **CLI / developer tool** (§3.2) → Go, `goreleaser` + Homebrew, *released-not-deployed*.

5. **Does it expose AI-agent capabilities (an MCP server or a prompt-forwarding bridge)?**
   → **Agent / MCP service** (§3.3) → Node/TS, npm/`npx` distribution, *released-not-deployed*.

6. **Is it a user-installed client (browser extension or native desktop app) talking to a backend?**
   → **Browser extension / client** (§3.5) → publish/notarize channel, alpha/beta/stable train.

**Hosting target follows category — there is no free choice:**

| If your app is a… | …it is hosted on | …and deploys via |
|---|---|---|
| SaaS web service | **GCP Cloud Run** (per-app project) | WIF → Artifact Registry → Pulumi `cloudrunv2` |
| CLI / developer tool | the **user's machine** | GitHub Releases + Homebrew tap (goreleaser) |
| Agent / MCP service | the **user's machine** | npm publish (`npx`) — *(target: codify the workflow)* |
| Browser extension / client | the **user's browser / Mac** | store / notarized DMG — *(target: codify the workflow)* |
| Self-hosted platform service | **dev-local k3s** | git → ArgoCD (GitOps) |
| IaC / platform definition | the resources it creates | `bazel run //tools/pulumi:*` / ArgoCD |

**Whatever the category, every new app inherits all of [§2](#2-cross-cutting-principles-every-app):** everything-as-code, a codified WIF deploy identity if it deploys, secrets out of git, a committed `.env.example`, MIT + the governance quartet, the Copybara mirror (or a documented exemption), a CI build+test gate, and `/health` + structured logs if it's long-running. A new app should be born *aligned* — see the [SOP](../../CONTRIBUTING.md) for the scaffold, and the [Alignment Gaps](application-alignment-gaps.md) doc for what existing apps still owe.
