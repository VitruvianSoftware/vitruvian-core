# CI/CD Pipeline Assessment

**Date:** 2026-07-09 · **Scope:** all 38 root workflows + the exported per-app mirror workflows on `main`
**Method:** 14-agent audit across six dimensions (triggers/path-scoping, coverage-by-app-type, enforcement/correctness, bottlenecks, gaps/security, consistency/hygiene); every **high**-severity finding was adversarially re-verified against the repo before inclusion.

> This is a living document. Each finding is tracked as a `workflows`-labelled issue (linked below). It supersedes the 7-byte `docs/repo-assessment.md` stub for the CI/CD lens.

## Bottom line

The CI **core is strong and correct** — the June 2026 gaps are closed and hold up under scrutiny: `go-lint` / `go-test (-race)` / `validate-butane` are now both **required and path-gated**, joined by `actionlint` and `gitops-validate` (12 required checks total). The real weaknesses have **shifted** to three areas that didn't scale with the repo:

1. **Governance / security posture** — free, high-value settings that are simply off.
2. **The newer `foundation` / pulumi IaC lane** — added after the last hardening pass, it skipped several patterns the rest of the repo already follows.
3. **Test/lint coverage for the non-Go subsystems** — coverage was built for the Go apps and never extended.

## What's solid (verified strengths)

- **Merge-queue invariant holds** for all 12 required checks: each always reports a status on the `merge_group` commit; heavy *steps* are path-gated with a fail-safe ("run unless the filter is CERTAIN nothing relevant changed"), so no required check can hang the queue while docs-only PRs still fast-path.
- **Hot path is not cron-polluted** — the nightly full-graph correctness sweep lives in `periodic-full-sweep.yaml`, not `ci.yaml`.
- **Non-cancelling concurrency** guards nearly every state-mutating workflow (apps-release, tabula-deploy, pulumi-library-release, repo-config, …).
- **`pulumi-preview.yaml` per-leg path-gating is exemplary** — the exact pattern the foundation lane should have copied.
- **Dependency-aware path scoping exists** — `copybara-sync-auth-apply.yaml` includes the shared `pkg/copybara_sync/**` its consumer imports (the pattern `repo_config` should follow — see #811).

## Priority tracker

| # | Sev | Area | Finding |
|---|---|---|---|
| [#803](https://github.com/VitruvianSoftware/vitruvian-core/issues/803) | P1 | security | Enable secret scanning + push protection (free, off) |
| [#804](https://github.com/VitruvianSoftware/vitruvian-core/issues/804) | P1 | governance | Enforce required PR review on `main` (CODEOWNERS unenforced) |
| [#805](https://github.com/VitruvianSoftware/vitruvian-core/issues/805) | P1 | foundation | Concurrency guard on production `pulumi up` |
| [#806](https://github.com/VitruvianSoftware/vitruvian-core/issues/806) | P1 | foundation | Run the foundation IaC unit tests in CI |
| [#807](https://github.com/VitruvianSoftware/vitruvian-core/issues/807) | P1 | nexus | Add test coverage + type-checking |
| [#808](https://github.com/VitruvianSoftware/vitruvian-core/issues/808) | P2 | tabula | Blue-green smoke false-green fallback |
| [#809](https://github.com/VitruvianSoftware/vitruvian-core/issues/809) | P2 | foundation | Make org-level IaC previews required, not advisory |
| [#810](https://github.com/VitruvianSoftware/vitruvian-core/issues/810) | P2 | foundation | `foundation-preview` dead paths-filter (all 5 legs run) |
| [#811](https://github.com/VitruvianSoftware/vitruvian-core/issues/811) | P2 | triggers | `repo_config` omits the `pkg/secrets` path it consumes |
| [#812](https://github.com/VitruvianSoftware/vitruvian-core/issues/812) | P2 | security | Add SAST/CodeQL + dependency-review gate |
| [#813](https://github.com/VitruvianSoftware/vitruvian-core/issues/813) | P2 | security | Release provenance (SBOM / attestation / signing) |
| [#814](https://github.com/VitruvianSoftware/vitruvian-core/issues/814) | P2 | deps | Dependabot github-actions blind spot on mirror workflows |
| [#815](https://github.com/VitruvianSoftware/vitruvian-core/issues/815) | P2 | deps | Enable Dependabot security updates |
| [#816](https://github.com/VitruvianSoftware/vitruvian-core/issues/816) | P2 | coverage | Wire the TS/JS/shell lint aspects (TS unlinted) |
| [#817](https://github.com/VitruvianSoftware/vitruvian-core/issues/817) | P2 | coverage | Extend golangci-lint beyond devx/homelab |
| [#818](https://github.com/VitruvianSoftware/vitruvian-core/issues/818) | P2 | coverage | mcp-slack has no unit tests (published to npm) |
| [#819](https://github.com/VitruvianSoftware/vitruvian-core/issues/819) | P2 | tabula | Migrations run before blue-green with no rollback |
| [#820](https://github.com/VitruvianSoftware/vitruvian-core/issues/820) | P2 | tabula | `tabula-e2e` is advisory (can merge red + auto-deploy) |
| [#821](https://github.com/VitruvianSoftware/vitruvian-core/issues/821) | P2 | perf | `build-macos` claims a macOS runner on every PR |
| [#822](https://github.com/VitruvianSoftware/vitruvian-core/issues/822) | P2 | perf | `tidy-check` full-repo (~9 min) on every merge_group |
| [#823](https://github.com/VitruvianSoftware/vitruvian-core/issues/823) | P3 | perf | `copybara-import-pr` 15-min poll (~96 no-ops/day) |
| [#824](https://github.com/VitruvianSoftware/vitruvian-core/issues/824) | P3 | security | `culprit-finder` shell-injection shape |
| [#825](https://github.com/VitruvianSoftware/vitruvian-core/issues/825) | P3 | foundation | Foundation workflow copy-paste + sibling drift |
| [#826](https://github.com/VitruvianSoftware/vitruvian-core/issues/826) | P3 | foundation | No IaC policy-as-code (CrossGuard/OPA) for the GCP org |
| [#827](https://github.com/VitruvianSoftware/vitruvian-core/issues/827) | P3 | coverage | tabula/web not type-checked in CI |
| [#828](https://github.com/VitruvianSoftware/vitruvian-core/issues/828) | P3 | governance | Enforce org 2FA + narrow member powers |

## Findings by dimension

### Correctness — mostly right, real bugs in the deploy path
- **Foundation deploy has no `concurrency:`** on production `pulumi up` (#805) — the sole outlier among deploy workflows; with manual-approval gates holding runs open, org infra can be applied out of order. This is the [#499](https://github.com/VitruvianSoftware/vitruvian-core/issues/499) serialize-pattern that foundation never adopted.
- **Blue-green smoke can false-green** (#808) — `tabula-deploy` silently falls back to the *stable* revision URL when the candidate tag doesn't resolve, "passing" against the old revision and promoting the untested one. A bug in the [#204](https://github.com/VitruvianSoftware/vitruvian-core/issues/204) deploy.
- **Migrations run before blue-green with no rollback** (#819) — the [#204](https://github.com/VitruvianSoftware/vitruvian-core/issues/204) "with rollback" claim doesn't cover DB migrations.

### Alignment by app/subsystem type — Go strong, the rest has holes
| Subsystem | Build | Test | Lint / type-check | Issue |
|---|---|---|---|---|
| devx / homelab (Go) | ✅ | ✅ `-race` | ✅ golangci-lint | — |
| foundation / app-pulumi / library (Go IaC) | preview only | ❌ never run | ❌ unlinted | #806, #817 |
| nexus-agent (Swift + JS) | ✅ build | ❌ zero tests | ❌ no type-check | #807 |
| mcp-slack (npm) | ✅ | ❌ no unit tests | type-check only | #818 |
| tabula (TS) | ✅ | ✅ jest | ❌ eslint aspect never run | #816, #827 |

The theme: **coverage was built for the Go apps and never extended.** The sharpest is #806 — live `*_test.go` foundation modules that no workflow executes.

### Triggering / path-relevance — strong, two real leaks
- **`foundation-preview` computes a paths-filter it never uses** (#810) — all 5 foundation stacks run full preview + a GCP WIF auth on any `foundation/**` PR. `pulumi-preview.yaml` next door does it correctly.
- **`repo_config` omits `pkg/secrets`** (#811) — a change to the consumed shared pkg is neither previewed nor applied until an unrelated repo_config change rides along.
- (The `apps-release` 4-app matrix firing on a single-app change is **benign** — per-app release-please no-ops for unchanged apps.)

### Check relevance / enforcement — the required set is good; IaC is the gap
- The 12 required checks are correctly path-gated and always-reporting. The gap is **advisory IaC**: `foundation-preview` / `pulumi-preview` don't gate merges, and `tabula-e2e` is advisory too (#809, #820) — broken IaC / red e2e can merge and auto-deploy to development.

### Bottlenecks
- **`build-macos`** claims a scarce macOS runner on every PR/merge_group just to gate inner steps (#821).
- **`tidy-check`** does a full-repo gazelle + pnpm resolve (~9 min) on every queued PR (#822) — the biggest per-queued-PR cost.
- **`copybara-import-pr`** 15-min poll, ~96 no-op spins/day (#823).

### Gaps — governance + supply chain (the biggest category)
- **Governance (P1):** secret scanning + push protection off (#803); no required PR review on `main` (#804, CODEOWNERS from [#82](https://github.com/VitruvianSoftware/vitruvian-core/issues/82) is unenforced); org 2FA not enforced (#828).
- **Supply chain (P2):** no SAST/CodeQL or dependency-review (#812); no SBOM / attestation / signing on any release (#813); Dependabot github-actions blind spot on the exported mirror workflows (#814); Dependabot security updates disabled (#815).
- **IaC safety (P3):** no policy-as-code (CrossGuard/OPA) blocking destructive org changes (#826).

## Recommended order

1. **Free governance wins (minutes):** #803, #804, promote the IaC previews (#809).
2. **Foundation concurrency race (#805)** — real risk to org infra, small fix.
3. **Deploy correctness bugs** — #808, #819.
4. **Coverage holes** — #806, #807, #816.
5. **Path leaks + supply chain** — #810, #811, #812, #813 as follow-ups.
