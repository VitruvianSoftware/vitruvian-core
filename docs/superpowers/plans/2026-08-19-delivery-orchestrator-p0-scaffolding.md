# Plan: Delivery Orchestrator — Phase 0 (shadow-mode scaffolding)

> Spec: `docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md`
> Invariant for this phase: **zero behaviour change.** The orchestrator runs in
> shadow on every push and emits manifests; nothing consumes them yet. Legacy
> workflows keep delivering. This gives real-world detection data to validate
> against before Phase 1 moves any trigger.

## Tasks

1. **`delivery()` macro** — `tools/delivery/defs.bzl` (done inline): metadata
   JSON + tagged inert filegroup; `manual` so wildcards never build it.
2. **First declaration (inert)** — oauth-user-inspector unit in
   `oauth-user-inspector/infra/app/BUILD`, mirroring today's gate regexes.
3. **Orchestrator** — `//tools/delivery/orchestrate` (Go): discover units via
   `bazel query` on the `delivery` tag; per unit, decide affected by shelling
   the existing `tools/ci/deploy-affected.sh` (graph or path mode from the
   declaration; the engine is NOT rewritten); emit `delivery-manifest.json`
   (schema in spec §4.2) + per-unit `affected_<name>` GITHUB_OUTPUTs; fail-open
   on every uncertainty with `computed_by: "fail-open"`.
4. **Generator** — `//tools/delivery/gen` (Go), aliased `//tools/ci:gen`:
   renders `.github/workflows/delivery.yaml`. Phase 0 output = the
   `orchestrate` job only (shadow), gated on
   `vars.DELIVERY_ORCHESTRATOR_ENABLED == 'true'`, concurrency
   `delivery-orchestrate` cancel-in-progress: false, artifact upload of the
   manifest. GENERATED banner + MIT header.
5. **Enforcement** — tidy-check step: `bazel run //tools/ci:gen && git diff
   --exit-code .github/workflows/delivery.yaml`; conformance: (a) side-effecting
   steps must be in a generated workflow or `tools/conformance/delivery-legacy.tsv`
   (seeded with the entire current surface), (b) every declaration's `run`
   target exists, (c) unit names unique.
6. **Kill switch** — `DELIVERY_ORCHESTRATOR_ENABLED` repo variable in
   `repo_config` `pipelineGates` (default "true": shadow orchestrate is
   side-effect-free) + generated-job no-op test.
7. **Tests** — macro golden JSON; orchestrator hermetic tests covering the spec
   §5 fail-open table (path-only mode, fake git repos; graph mode stubbed);
   generator golden-file test; conformance negative tests proving each new rule
   fails on a violation BEFORE it ships (test-the-guard).

## Verification gates (all before PR is ready)
- `bazel test //tools/delivery/...` green; goldens reviewed by eye.
- `bazel run //tools/ci:gen` idempotent (second run: no diff).
- actionlint + conformance + tidy green.
- Negative tests demonstrated failing on seeded violations.
- Live shadow run on the PR itself: orchestrate emits a manifest for a
  docs-only diff with `affected=false` for the oauth unit.

## File ownership (parallel agents, no overlaps)
- inline (this plan's author): defs.bzl, plan doc, oauth declaration,
  repo_config variable, tools/ci/BUILD alias.
- agent "orchestrate": tools/delivery/orchestrate/** (+ tests, fixtures).
- agent "gen+enforce": tools/delivery/gen/** (+ goldens),
  .github/workflows/delivery.yaml, tidy-check.yaml step, tools/conformance
  additions + delivery-legacy.tsv (+ negative tests).
- integration (author): gazelle, tidy, conformance, actionlint, live shadow A/B.
