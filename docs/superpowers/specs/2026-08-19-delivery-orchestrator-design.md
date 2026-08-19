# Delivery Orchestrator — the Bazel graph as the single source of deploy truth

> **Status:** Proposed (spec for review)
> **Date:** 2026-08-19
> **Owner:** platform
> **Related:** `docs/repo-assessment.md` §5, `docs/break-glass-deploy-runbook.md`,
> the application-initializer spec (`2026-08-18-universal-initializer-design.md`) —
> ADR-026/027 alignment noted in §4.1.

## 1. Problem

The repo has **five independent implementations** of "what did this commit
affect?": 50 workflow-level `push.paths` filters, `tools/ci/deploy-affected.sh`
(10 callers), `tools/ci/relevant-paths.sh` (5), `dorny/paths-filter` (3), and
`_deploy-gate.yaml` (2) — plus hand-maintained `extra-path-regex` strings inside
workflows. A job's *relevance* is expressed separately from its *dependencies*,
and nothing forces a job to consume the verdict its own workflow computed.

Measured consequences (all on real commits, 2026-08-18/19):

| defect | evidence |
|---|---|
| Jobs bypassing their own gate | `zitadel-dev` applied a Pulumi stack on every push (315s × ~11/day, ~7% relevant) while its sibling `build`/`deploy-*` jobs skipped — fixed by hand in #1794, the **third** instance of the identical shape (#1759, #1763 were the others) |
| Gate exists but can't see | `example-build` re-ran 452–474s on gitops-only pushes because its checkout lacked history (#1763) |
| Hand-regex drift | oauth's gate regex is a 6-alternation string someone must remember to extend; nothing checks it against reality |
| Waste at scale | gitops-only commits are ~5.9/day; pre-fix each paid ~15 min of provably-irrelevant work |

Fixing instances one at a time is a patch treadmill. The class survives because
the *architecture* allows any new job to re-answer "am I affected?" from
scratch, or not answer it at all.

## 2. Goals

1. **One** computation of "what does this commit require delivering", derived
   from the Bazel graph, consumed by construction — impossible to bypass.
2. Deploy/apply/publish jobs run **iff** their unit is affected (or a human
   dispatches them). No side-effecting job keyed on bare `push`.
3. Registration of a new deployable is a **side effect of scaffolding it**
   (initializer alignment) — never a workflow edit.
4. Workflow YAML for the delivery surface is a **generated artifact**; drift
   fails CI.
5. Correctness invariants preserved bit-for-bit: fail-open on uncertainty,
   serialize-never-cancel on state mutation, GitHub Environments approvals,
   WIF, merge queue, release-please promotion, break-glass targets.

## 3. Non-goals

- **The test half of CI.** `build-test`/`go-race` sweep + RBE cache was
  measured (twice) as the right design after #1297. Untouched.
- **ArgoCD-reconciled platform components.** `gitops/argocd/platform/*` deliver
  via the ArgoCD closed loop; their `:apply` targets are the manual-ops
  surface. The orchestrator governs only what **GitHub Actions itself
  mutates**: Cloud Run deploys, Pulumi applies (zitadel-apps, identity/build/
  data stacks), chart/artifact publishes.
- **Replacing GitHub Actions.** Merge queue, Environments and WIF stay. No new
  SaaS in the deploy path (break-glass doctrine).
- **Foundation release ladder** (`foundation-release.yaml`). It is
  release-please-driven, serialized by design, already precise (per-stage
  `paths` on its own subtree). Revisit in Phase 4 only if the model proves out.

## 4. Design

Four parts: **Declare → Decide → Act → Enforce.**

### 4.1 Declare — `delivery()` units in BUILD files

A Starlark macro (in `tools/delivery/defs.bzl`) declares each unit next to the
code it delivers:

```starlark
delivery(
    name = "oauth-user-inspector",
    kind = "cloud-run",                     # cloud-run | pulumi | publish
    target = "//oauth-user-inspector/infra/app:deploy",   # the break-glass target
    build = "//oauth-user-inspector:image",  # what must exist first ("" = none)
    environments = ["development", "nonproduction", "production"],
    github_environment = "oauth-user-inspector-{env}",
    promotion = "release:oauth-user-inspector-v",  # dev on push; later envs on this tag
    companions = [":zitadel-apps"],          # expand-before-serve deps, same unit set
    preflight = "//oauth-user-inspector/infra/app:preflight",  # optional, Phase 2
)
```

The macro materializes an inert `filegroup` carrying
`tags = ["delivery", "delivery-kind=cloud-run", ...]` plus a generated JSON
metadata file — so **the graph is the registry**:

```
bazel cquery 'attr(tags, "\bdelivery\b", //...)' → the complete delivery universe
```

Facts that make this cheap and safe today: the universe is ~12 units (tabula
api/web, oauth, zitadel-apps ×3 envs, identity/build/data stacks, mcp-slack
zitadel, charts, tabula-dev-latest); every one already exists as a `bazel run`
target because the break-glass initiative required it. CI and break-glass
therefore execute the **same target** — one delivery path, two triggers.

**Initializer alignment:** the app scaffold (ADR-026/027) emits the
`delivery()` block in the app's `infra/app/BUILD`. Creating an app registers
it; no workflow edit exists to forget.

### 4.2 Decide — one orchestrator job, one manifest

A single `orchestrate` job on `push: [main]` (and on `release:` events for
promotion), implemented as `//tools/delivery:orchestrate` (Go, like
`tools/copybara/*`):

1. **Universe:** `cquery` the `delivery` tag over `//...` *minus the known
   platform-incompatible subtrees* — reusing the `TD_UNIVERSE` lesson: the
   query must never expand `//nexus-agent/macos/...`. Cost is trivial (~12
   units).
2. **Affected:** per unit, the existing `deploy-affected.sh` engine (graph mode
   when the unit's targets are graph-tracked, path mode otherwise — its two
   modes already exist and are proven). The per-unit path regexes move from
   workflow YAML into the `delivery()` declaration (`extra_paths` attr), so
   they live next to the code and are testable.
3. **Manifest:** emit `delivery-manifest.json`, uploaded as artifact **and**
   exposed as a job output:

```json
{
  "schema": 1,
  "commit": "…", "before": "…", "computed_by": "graph|paths|fail-open",
  "units": [
    {"name": "oauth-user-inspector", "affected": true,
     "reason": "oauth-user-inspector/infra/app/main.go",
     "environments": ["development"], "kind": "cloud-run",
     "github_environment": "oauth-user-inspector-development",
     "run": "//oauth-user-inspector/infra/app:deploy"}
  ]
}
```

**Fail-open, inherited verbatim:** any uncertainty (unresolvable base, forced
push, cquery failure) marks **every** unit affected, with
`computed_by: "fail-open"` so the run UI says why. The orchestrator can only
ever over-deliver, never silently under-deliver — the same invariant
`deploy-affected.sh:33-35` documents today.

### 4.3 Act — one generated delivery workflow

`bazel run //tools/ci:gen` renders `.github/workflows/delivery.yaml` from the
declarations. The generator (same binary as the orchestrator, different
subcommand) emits, **per unit**, a statically-generated job chain — because GHA
has no dynamic `needs`, generation is what makes per-unit ladders tractable
where hand-YAML wasn't:

```
orchestrate ─┬─ oauth: zitadel-dev ─→ deploy-dev ─→ [release] zitadel-nonprod → …
             ├─ tabula-api: build ─→ deploy-dev ─→ …
             └─ charts: publish
```

Every generated job carries, non-negotiably (generator-enforced, not
convention):

- `needs:` chaining back to `orchestrate` — the bypass class is structurally
  dead;
- `if: fromJSON(needs.orchestrate.outputs.manifest).units[…].affected` (via a
  small `jq` step where expressions can't reach into JSON) — plus the
  fail-open arm mirroring `build`'s shape today;
- `environment: <github_environment>` — approvals and WIF vars exactly as now;
- `concurrency: {group: delivery-<unit>-<env>, cancel-in-progress: false}` —
  serialize-never-cancel per unit+env, the repo's standing invariant;
- `workflow_dispatch` inputs for manual per-unit/per-env runs (replacing
  today's per-workflow dispatch paths);
- promotion jobs keyed on `release:` + tag prefix from the declaration
  (release-please flow unchanged).

The reusable workhorses (`_deploy-cloud-run.yaml`, `_zitadel-apps-apply.yaml`)
are **kept as-is** — the generated file is a thin caller layer, which is why
this is a re-plumbing, not a rewrite of deploy logic.

### 4.4 Enforce — generation asserted, class closed

1. **tidy-check** (existing idiom): `bazel run //tools/ci:gen && git diff
   --exit-code .github/workflows/delivery.yaml` — hand-edits fail CI.
2. **conformance** additions:
   - every workflow step that mutates state (`pulumi up`, `bazel run …:deploy`,
     `helm push`, `gh release upload`) must live in a generated workflow or in
     the explicit legacy allowlist (`tools/conformance/delivery-legacy.tsv`,
     shrinking to empty by Phase 3 — same reviewed-exception pattern as
     `public-targets.tsv`);
   - every `delivery()` unit's `run` target must exist (`bazel query` proves
     it) and vice versa — no orphaned declarations, no undeclared deploy
     targets;
   - the merge-queue guard keeps its existing jurisdiction — `orchestrate` is
     postsubmit and never a required check, so the queue cannot wedge on it.

### 4.5 Phase 2 — digest-based detection (Aspect-grade correctness)

Graph/path detection over-triggers (deps-only bumps) and — per Aspect's
published caveat — graph diffing *alone* can also miss. The end-state detector
compares **content digests of unstamped outputs** against the
last-delivered manifest (fetched from the most recent successful `orchestrate`
run via `gh api`, with a missing/unfetchable prior manifest ⇒ fail-open):

- `tabula-deploy-preflight.sh` already implements exactly this for one app
  (desired revision hash vs live revision, fail-open) — Phase 2 generalizes it
  behind the `preflight` attr;
- detection builds **unstamped**; delivery rebuilds **stamped** (the
  version-stamping trap from Aspect's guide);
- Phase 2 changes only *detection sharpness*; the fan-out machinery is
  untouched.

## 5. Failure modes

| failure | behaviour |
|---|---|
| Orchestrator can't compute (base missing, query fails) | fail-open: all units affected; loud `computed_by: fail-open` annotation |
| Two pushes race | per-unit+env `cancel-in-progress: false` groups serialize applies; manifests are per-commit so the later run re-decides on its own diff |
| Fan-out job fails mid-ladder | identical to today: ladder halts at the failed env; `workflow_dispatch` resumes |
| Environment approval pending | identical to today (Environments unchanged) |
| Generated YAML hand-edited | tidy-check red |
| New deployable added without declaration | conformance red (undeclared side-effecting step) |
| Declaration without target | conformance red (query proves existence) |
| Break-glass during Actions outage | unchanged: the same `bazel run` targets, per the runbook |
| First run post-migration | no prior manifest ⇒ Phase 1 doesn't need one; Phase 2 fail-opens |

## 6. Migration

Strangler pattern; at every step both paths are gated and serialized, so the
worst case is a redundant (idempotent) apply, never a missed one.

- **Phase 0 — scaffolding (no behaviour change):** `delivery()` macro,
  orchestrator binary + manifest, generator + `delivery.yaml` containing *only*
  `orchestrate`, tidy-check regen assertion, conformance rules with the entire
  legacy surface allowlisted. Golden tests for generator output; `sh_test`
  fakes for the orchestrator (the repo's established pattern).
- **Phase 1 — oauth-user-inspector** (smallest ladder; gate just audited in
  #1794): its dev-lane jobs move into the generated file; legacy workflow's
  push trigger removed, dispatch retained one release cycle as escape hatch.
  **Verification: the A/B discipline from this session** — a gitops-only push
  (expect: single skipped-manifest orchestrate job, zero fan-out) and an
  oauth-touching push (expect: identical deploy behaviour to today), measured
  from real runs before the legacy path is deleted.
- **Phase 2 — tabula (api/web), zitadel-apps, identity/build/data stacks,
  charts-publish, tabula-dev-latest.** Allowlist shrinks per migration.
- **Phase 3 — digest detection** (§4.5) + delete legacy workflows + empty
  allowlist becomes a hard conformance floor.
- **Phase 4 (optional, separate decision):** evaluate folding the foundation
  ladder in.

Rollback at any phase = revert the generated file + re-add the legacy workflow
(both are single commits; state is never migrated, only triggers).

## 7. Alternatives considered

- **Aspect Workflows (buy):** the mature product version of this design
  (selective delivery, content-hash detection, manifests). Rejected: adds a
  SaaS control plane inside the deploy path, against the standing break-glass
  doctrine; the repo already owns every primitive the build requires.
- **Re-platform (Buildkite dynamic pipelines / Dagger):** real dynamic job
  graphs, but forfeits GH-native merge queue, Environments and WIF for a
  dynamism problem the matrix/generation pattern covers at this scale.
- **Keep patching:** three instances of the same bypass in one week is the
  argument against itself.

## 8. Testing strategy

- Generator: golden-file tests (`ci_gen_test`) — declarations in, YAML out;
  a change to either fails visibly in review.
- Orchestrator: hermetic `sh_test`/`go_test` with fake git trees covering the
  fail-open table in §5 (the `osv-scan_test.sh` pattern).
- Conformance: negative tests proving the new rules fail on (a) a hand-edited
  generated file, (b) an undeclared `pulumi up`, (c) an orphaned declaration —
  verified failing before the rules ship (test-the-guard discipline).
- Migration gates: per-phase live A/B on real commits, published in the PR
  before the legacy path is removed.

## 9. Decisions (were open questions)

1. **Manifest-of-record location (Phase 2):** last successful `orchestrate`
   run's artifact via `gh api`, not a committed file — avoids commit noise and
   merge races; unfetchable ⇒ fail-open.
2. **Generator language:** Go (`tools/delivery`, gazelle-managed) — matches
   `tools/copybara`, testable, no new toolchain.
3. **Per-unit path regexes** move into `delivery()` attrs; `deploy-affected.sh`
   stays the engine and gains no new modes.
4. **`site-verification-test.yaml` / other self-tests** are not delivery units
   (no side effects on shared state) — out of scope.
