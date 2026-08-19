# Application Initializer — Design

**Date:** 2026-08-18 (revised same day, see §14)
**Status:** Approved in conversation; awaiting written-spec review
**Branch:** `docs/universal-initializer-spec`
**Requested by:** James Nguyen
**Scope:** Spring-Initializr-class **application** stamping into existing Bazel monorepos,
for every language `aspect-workflows-template` supports, exposed through Backstage, a REST
service, and a local CLI — all driven by one composition core.

This is the initiative's **root spec**. Per-phase implementation plans derive from it
(spec-driven flow, §13), architecture and technology decisions are recorded as ADRs (§11)
including ones made after this document lands, and decisions needed from James are
consolidated in §12 and referenced inline as `OQ-n`.

## 1. The distinction this initiative rests on

**Repo stamping and application stamping are different products.** Conflating them was the
central error of this spec's first draft (§14).

| | Repo stamping — **exists today** | Application stamping — **this initiative** |
|---|---|---|
| Produces | a brand-new monorepo: Bazel, CI, lint, release tooling, `hello/<lang>` example apps | one application **inside an existing monorepo** |
| Consumed | once, at repo birth | many times, over the repo's whole life |
| Delivered by | the 13 `backstage-*` templates + 26 starter repos, force-pushed by `deliver.yaml` | the initializer described here |
| Spring analogy | — | **this is what start.spring.io does** |

The two compose: stamp a monorepo, then stamp applications into it over time. The existing
13 templates and their skeleton machinery are **not** superseded and are **not** retired
(ADR-011).

Grounding, verified 2026-08-18:

- `vitruvian-core` lays applications out as **top-level directories**, each with its own
  `catalog-info.yaml`: `backstage/`, `devx/`, `homelab/`, `mcp-slack/`, `nexus-agent/`,
  `oauth-user-inspector/`, `tabula/`.
- A rendered starter monorepo contains `MODULE.bazel`, `bazel/`, `tools/`, `.github/`, and
  `hello/{cpp,go,java,js,kotlin,py,ruby,rust,scala,shell,swift}` — toy example apps.

So `hello/<lang>` is the placeholder for what this initializer should generate properly
(ADR-013 proposes unifying the two).

## 2. Purpose and success criteria

Success bar (chosen 2026-08-18): **"deploys itself."** A stamped application, out of the
box:

1. builds and its tests pass **inside the target monorepo**, with Bazel wiring that is
   already correct (BUILD files at gazelle fixed point — §6.3);
2. runs a real HTTP service: routing, graceful shutdown, `/healthz` + `/readyz`,
   structured JSON logging, typed config loading;
3. ships observability pre-wired: **OpenTelemetry SDK → OTLP → the platform
   Prometheus/Grafana stack** (open frameworks preferred everywhere — explicit
   requirement);
4. optionally ships a Postgres data layer (client + migrations);
5. deploys itself: OCI image build, k8s manifests, ArgoCD Application, image-updater
   wiring — live in the cluster minutes after Create, **with no human gate** (ADR-007).

Wave-1 languages for the full concern stack: **Go, TypeScript/JS, Python, Java+Kotlin**
(JVM is one track). Remaining languages get app templates without the concern stack until
a later wave.

## 3. Context: what exists today (verified 2026-08-18)

Established by direct inspection of `aspect-workflows-template@platform-v2.0` and the
deployed Backstage (`plugin-scaffolder-backend@4.0.2`, `plugin-scaffolder-node@0.13.6`,
`plugin-scaffolder@1.38.1`, RJSF 5.24.13):

- `template-config.json` declares **21 boolean flags** (11 language, 10 feature) and **28
  presets** (flag dicts, plus derived non-flag keys `platforms` and
  `copybara_components`). `rules` is a file-inclusion gate (AND/OR over flags, no NOT),
  `no_render` lists verbatim-copy files, `executable` lists chmod+x globs.
- The renderer is the Aspect CLI's embedded AXL runtime (`render.axl` + minijinja).
  `render()` **already accepts an arbitrary flags dict**; only the CLI task
  (`aspect render-preset`) is preset-locked. Rendering is pure templating — no bazel, no
  network — but needs the `aspect` binary (AXL has no standalone interpreter).
- **Nothing validates flag combinations.** The 28 presets are the only known-good points,
  enforced socially by CI's per-preset build matrix.
- Post-render normalization (lockfile repin, `bazel mod deps`, gazelle, format, license
  headers) lives in CI/deliver workflows, not the renderer, and needs a full bazel
  toolchain.
- The `backstage` flag makes a render emit `template.yaml` + a `skeleton/` copy that
  Backstage re-templates with Nunjucks at create time — 83 escaped `${{ '{{' }}` idioms
  across 6 files, populated by `_populate_skeleton()` in `dev.axl`. **This machinery
  serves repo stamping and is retained**; the application initializer does not use it.
- Backstage scaffolder: custom actions register via `scaffolderActionsExtensionPoint` from
  `@backstage/plugin-scaffolder-node` (main entry, not `/alpha`); `ctx.checkpoint`
  idempotency is GA; a programmatic dry-run endpoint exists
  (`POST /api/scaffolder/v2/dry-run`); shell-outs use `executeShellCommand` with the action
  logger (the UI stalls if a step is silent >60s). RJSF conditional schemas are broken in
  Backstage for deep nesting (upstream #30090, #7343) — custom field extensions are the
  sanctioned escape hatch.
- **`publish:github:pull-request` is registered and live** in the deployed action registry
  (confirmed in the running backend's startup log alongside `publish:github`). That is this
  initiative's terminal action — not `publish:github`, which creates repositories.
- Stale-doc warning: `test.sh`, `README.md`, `AGENTS.md` and the template repo's Backstage
  quick-start still describe the **removed** `hay-kot/scaffold` engine. Trust
  `render.axl` / `dev.axl` / the workflows.

## 4. Architecture: one foundation, three frontends

Spring Initializr is one core library and one metadata contract behind several frontends
(web UI, `curl` API, `spring init` CLI, IDE wizards). We adopt that shape (ADR-001).

```mermaid
flowchart TD
    MC["Metadata contract - app section in template-config.json"]
    RA["render-app AXL task - validate, render app subtree"]
    MC --> RA
    MC --> A["Frontend A: Backstage Create page"]
    MC --> B["Frontend B: initializer HTTP service"]
    MC --> C["Frontend C: local CLI, stamps into the monorepo you are in"]
    RA --> A
    RA --> B
    RA --> C
    A --> PR["publish:github:pull-request into the target monorepo"]
    B --> ZIP["app subtree as zip or patch"]
    C --> FS["files written into the working tree"]
    PR --> MQ["merge queue - auto-merge - ArgoCD"]

    RS["Repo stamping - 13 templates, 26 starter repos - adjacent tier, unchanged"]
    MC -.shares metadata and renderer.- RS
```

The foundation lives in `aspect-workflows-template`: the generator repo stays the single
source of truth for what can be composed, and frontends are transports.

## 5. Foundation: the composition core

### 5.1 Application metadata contract

Extend `template-config.json` with an `app` section (schema-checked in CI; drift fails the
build):

```jsonc
"app": {
  "languages": {
    "go":     { "label": "Go", "wave": 1, "concerns": ["svc_http","svc_config", ...] },
    "python": { "label": "Python", "wave": 1, ... },
    "ruby":   { "label": "Ruby", "wave": 2, "concerns": [] }
  },
  "concerns": {
    "svc_http":   { "label": "HTTP service", "requires": ["svc_config"],
                    "description": "routing, graceful shutdown, health endpoints" },
    "svc_otel":   { "label": "OpenTelemetry", "requires": ["svc_logging"] },
    "svc_deploy": { "label": "Deploy to cluster", "requires": ["svc_http","oci"] }
  },
  "presets": {
    "go-service": { "language": "go",
                    "concerns": ["svc_http","svc_config","svc_logging","svc_otel"] }
  }
}
```

Every consumer reads this one section: the Backstage field extension, the service's
`GET /metadata`, the CLI's `--help`, `render-app` validation, and CI's generated test
matrix.

### 5.2 `render-app` task

New AXL task beside `render-preset`, same engine, same `rules`/`no_render`/`executable`
semantics:

```
aspect render-app --language go --concerns svc_http,svc_otel \
                  --name payments --out DIR [--module-path ...]
aspect render-app --metadata          # print the app section (the /metadata analog)
```

Behavior:

1. Parse language + concerns; reject unknown names.
2. **Validate against the contract — fail loudly on violation.** This is the system's first
   validation of any kind and is shared by every frontend (never trust a form).
3. Render the app template tree (§6.1) for that language/concern combination into
   `out/<name>/`.
4. Emit BUILD files that are already a gazelle fixed point (§6.3).

`render-preset` is untouched; repo stamping keeps its own path.

## 6. The application template asset

### 6.1 A new tree, not the monorepo tree

`template/` is monorepo-shaped (MODULE.bazel, tools/, .github/). Application stamping needs
app-shaped templates: a new `app-template/<language>/` tree in the same repo, rendered by
the same engine with the same conditional machinery. ADR-013 proposes deriving
`hello/<lang>` from it so the two cannot drift and every app template is proven inside a
real monorepo on every CI run.

### 6.2 Application concerns (Spring-Boot-parity layer)

An application is **one language** (ADR-008), so concerns compose within a single track:

| Concern | Wires | Go | TS/JS | Python | JVM |
|---|---|---|---|---|---|
| `svc_http` | server, routing, graceful shutdown, `/healthz` `/readyz` | chi (OQ-6) | Fastify | FastAPI | **Spring Boot** |
| `svc_config` | typed env/file config | koanf | zod-config | pydantic-settings | Spring config |
| `svc_logging` | structured JSON logs | slog | pino | structlog | logback-json |
| `svc_otel` | OTel SDK traces + metrics → OTLP → platform Prometheus/Grafana | OTel-Go | OTel-JS auto-instr | OTel-Py | Spring Boot OTel starter |
| `svc_db_postgres` | Postgres client + migrations (provisioning scope: OQ-3) | pgx + goose | drizzle | SQLAlchemy + alembic | Spring Data + Flyway |
| `svc_deploy` | rules_oci image, image-build CI, k8s manifests, ArgoCD Application, image-updater CR (the buzz pattern) | — language-agnostic — | | | |

Requires-chains: `svc_http → svc_config`; `svc_otel → svc_logging → svc_config`;
`svc_deploy → svc_http + oci`. The JVM track uses **actual Spring Boot** — it *is* the open
framework there (ADR-009); the other tracks replicate its concerns with consensus open
libraries. All four emit the same operational surface (identical endpoint names, OTLP
wiring, log shape) so the deploy bundle and dashboards stay language-agnostic.

### 6.3 Bazel integration — the hard part

"Wire up Bazel so it works well in our monorepo" is the core engineering problem, and it
has two halves:

**BUILD files.** The renderer knows exactly which files it emits, so app templates emit
BUILD files that are **already what gazelle would generate**. This is testable: a tier-2
check renders an app into a real monorepo and asserts `gazelle` is a no-op (fixed point).
Without this the first PR fails the repo's stale-BUILD gate, which already exists.

**Toolchain gaps.** Stamping a Python app into a Go-only monorepo requires editing
`MODULE.bazel` and repinning lockfiles — a surgical edit to an existing file, not a render.
For v1 the initializer **detects the gap and refuses with a clear message** naming the
change needed, rather than attempting a merge into a file it does not own (ADR-012, OQ-9).
Automatic toolchain onboarding is a later phase.

## 7. Frontend A — Backstage (built first)

- **One template**, `stamp-application`, alongside the 13 repo-stamping templates. Its form
  is a custom field extension, `AppInitializerPicker`, rendering language + concerns from
  the metadata contract with live `requires`/`conflicts` enforcement (ADR-005).
- **Form parameters**: target monorepo (OQ-8), application name, owner, language, concerns.
- **Custom action `vitruvian:app:render`** (new backend module, same pattern as our
  auth/permission modules): invokes the `aspect` binary vendored into the backstage image
  (ADR-004) via `executeShellCommand`, streaming output to the task log, wrapped in
  `ctx.checkpoint` for idempotent retries.
- **Steps**: clone/fetch target repo → `vitruvian:app:render` → *(if `svc_deploy`)* add
  gitops manifests → `publish:github:pull-request` → `catalog:register` for the new
  `catalog-info.yaml`.
- **Preview**: "Explore before create" via the scaffolder dry-run endpoint — see the file
  tree for the current selection with no side effects.

### 7.1 The fully-automatic deploy step (ADR-007)

James chose "fully automatic — no human gate." Because the application and its gitops
manifests live in the **same repository** for `vitruvian-core`, this is a **single PR**
with auto-merge enabled: the merge queue runs the normal gates, merges unattended on green,
ArgoCD reconciles, and the service is live minutes after Create with zero human action. The
gitops closed loop and every-change-through-CI invariants hold, and no merge-queue-bypass
credential is minted. A red gate blocks the deploy exactly as it would any other change —
correct behavior, surfaced in the scaffolder task log.

## 8. Frontend B — initializer HTTP service

In-cluster service, the start.spring.io analog:

- `GET /metadata` — serves the contract (drives any future frontend or IDE plugin).
- `POST /render` — language + concerns → app subtree.
- `GET /starter.zip?language=go&concerns=svc_http,svc_otel&name=payments` — the `curl`
  experience.

Unlike A it can carry a full bazel toolchain, so it can validate the rendered app builds
before returning. Output shape for a *subtree* (zip vs git patch vs PR-on-request) is
OQ-10. Once it exists, A may switch from embedded binary to calling B — same contracts,
swappable transport.

**Dogfood milestone:** B is itself stamped by A into `vitruvian-core`
(`go + svc_http + svc_otel + svc_deploy`) — the initializer creating the initializer service
is the acceptance test for the whole program.

## 9. Frontend C — local CLI

A developer standing in a monorepo runs one command and the application appears in the
working tree, correctly wired, with no Backstage and no network round-trip. This is
Initializr's `spring init`, and it is the frontend most likely to get daily use.

Surface: `aspect init-app --language go --concerns svc_http,svc_otel --name payments`, or a
`devx` subcommand (OQ-11). Because it runs on a developer machine with bazel available, it
can run gazelle and repin immediately.

## 10. Testing: what "green" warrants

The valid space is exponential; CI cannot build it. Four tiers:

1. **Metadata self-consistency** — constraint graph acyclic, `requires` targets exist,
   presets valid, contract/flags drift fails CI.
2. **Render smoke over pairwise-sampled valid combinations** — render only, no bazel: no
   Jinja residue, no orphaned references, `executable`/`no_render` honored. Pairwise covers
   every concern-pair interaction, which is where template conditionals actually couple.
3. **Build + test for every app preset, stamped into a real monorepo** — including the
   gazelle fixed-point assertion (§6.3). These are the only **warranted** combinations,
   the same warranty model Spring Initializr uses.
4. **Backstage e2e** — dry-run-based stamp test in vitruvian-core CI so the
   action/form/renderer contract cannot silently drift.

## 11. Architecture Decision Records

Lightweight ADRs (context → decision → consequences). **Accepted** = decided in the
2026-08-18 sessions; **Proposed** = recommended, awaiting James. Later decisions append
(ADR-014+) rather than rewriting history; an answered OQ converts into an ADR.

- **ADR-001 (Accepted) — One foundation, several frontends.** A/B/C are transports over one
  composition core and metadata contract, mirroring Spring Initializr. *Consequence:*
  foundation ships first; no frontend forks composition logic.
- **ADR-002 (Accepted) — Metadata lives in `template-config.json`.** The generator repo
  stays the single source of truth; frontends read, never redefine.
- **ADR-003 (Accepted) — Extend the AXL renderer; do not reimplement.** `render-app` reuses
  the existing engine, and validation becomes the shared enforcement point. *Consequence:*
  every frontend needs the `aspect` binary — accepted; porting minijinja and the glob
  semantics would invite drift.
- **ADR-004 (Accepted) — Frontend A embeds the renderer binary in the backstage image.**
  Rendering is pure templating; ~50MB buys zero new runtime infrastructure.
  *Consequence:* renderer version pins to image releases; later extraction to B is a
  transport swap.
- **ADR-005 (Accepted) — Custom field extension over RJSF conditional schemas.** Upstream
  conditional rendering is broken at our depth (#30090, #7343). *Consequence:* we own a
  React component, and constraint logic must also run server-side.
- **ADR-006 (Accepted) — Frontend A does not run bazel.** Normalization that needs a
  toolchain is handled by emitting gazelle-fixed-point BUILD files (§6.3) and, where that
  is insufficient, by the target repo's own CI on the stamping PR. *Consequence:* the PR is
  the verification point, which is where the repo's gates already live.
- **ADR-007 (Accepted) — "Fully automatic" = auto-merge PR through the merge queue.** Zero
  human action, live in minutes, gates still run, no bypass credential.
- **ADR-008 (Accepted, revised) — An application is one language.** The first draft applied
  concerns to every selected language, an artifact of conflating repo and app stamping.
  Multi-language monorepos are composed by stamping several applications.
- **ADR-009 (Part-Accepted) — Framework choices.** Accepted: OpenTelemetry everywhere
  (explicit requirement); Spring Boot for JVM; FastAPI for Python; Fastify for TS.
  Proposed: chi for Go (OQ-6 — stdlib `net/http` is the leaner alternative since 1.22's
  mux).
- **ADR-010 (Accepted) — Warranty model.** App presets are the fully-built combinations;
  arbitrary combinations get constraint validation plus pairwise render-smoke.
  *Consequence:* an exotic combination can render and still fail its first build — surfaced
  immediately by the stamping PR's CI, not silently.
- **ADR-011 (Accepted) — Repo stamping is retained, untouched.** The 13 `backstage-*`
  templates, the 26 starter repos, the `backstage` flag, `skeleton/`,
  `_populate_skeleton()` and the 83 Nunjucks escapes all serve a different product (§1) and
  are not superseded by this initiative. *Resolves OQ-5.*
- **ADR-012 (Proposed) — Refuse, do not merge, on a toolchain gap.** If the target monorepo
  lacks the language's toolchain, fail with a clear message rather than editing
  `MODULE.bazel`. *Consequence:* some stamps need a preparatory change first; automatic
  onboarding is a later phase (OQ-9).
- **ADR-013 (Proposed) — Derive `hello/<lang>` from the app templates.** Repo stamping would
  render its example apps from the same source the initializer uses, so the two cannot
  drift and every app template is exercised inside a real monorepo on every CI run.

## 12. Open questions — decisions needed from James

`OQ-5` is resolved (ADR-011). `OQ-1` was largely dissolved by the repo→app correction: for
`vitruvian-core` the application and its gitops manifests are in the same repository, so a
single same-repo PR replaces the cross-repo write.

| # | Question | Needed by | Recommendation |
|---|---|---|---|
| **OQ-7** | Application layout in a target monorepo: assume top-level directories (the `vitruvian-core` convention), or also support `apps/<name>/`? | P1 | Top-level for v1; make it a metadata-driven per-repo setting later |
| **OQ-8** | Valid target monorepos: `vitruvian-core` only for v1, or any repo descended from a starter (detected by `MODULE.bazel` plus our tooling markers)? | P1 | `vitruvian-core` only for v1 |
| **OQ-9** | Toolchain gap (ADR-012): refuse-with-message, or attempt surgical `MODULE.bazel` onboarding? | P2 | Refuse for v1 |
| **OQ-10** | Frontend B output for an app *subtree*: zip, git patch, or open a PR on request? | P4 | Zip plus optional PR |
| **OQ-11** | Frontend C home: `aspect init-app` task in the template repo, or a `devx` subcommand? | P5 | `devx` — it is already the platform CLI |
| **OQ-3** | `svc_db_postgres` scope: client + migrations only, or also CNPG Cluster manifests (vs external Neon per the app-infra boundary)? | P2 (Go DB slice) | Client + migrations first; provisioning as a later `svc_db_provision` flag |
| **OQ-4** | Deploy target: homelab ArgoCD (buzz pattern — this design's assumption) only, or also the Cloud Run path as a form choice? | P3 | Homelab-only for v1 |
| **OQ-6** | Go HTTP framework: chi, or stdlib `net/http` (1.22+ mux)? (ADR-009) | P2 (Go) | chi; stdlib acceptable |
| **OQ-12** | Credential for the stamping PR: reuse the existing `backstage-github-token` (already has repository Administration write) or mint a dedicated GitHub App for a cleaner audit line? | P1 | GitHub App |

## 13. Rollout

| Phase | Delivers | Depends on |
|---|---|---|
| **P0** | App metadata contract, `render-app` + validation, tiers 1–2 tests | — |
| **P1** | Frontend A: stamp an application into `vitruvian-core` (no concerns yet) — the mechanism, end to end | P0; OQ-7, OQ-8, OQ-12 |
| **P2** | Concern stack per track: **Go → TS → Python → JVM**; each ships its app preset, CI leg, and tier-3 build | P0; OQ-3, OQ-6, OQ-9 |
| **P3** | `svc_deploy` and the fully-automatic single-PR deploy | P2 (Go); OQ-4 |
| **P4** | Frontend B, itself stamped by A (dogfood) | P2 (Go), P3; OQ-10 |
| **P5** | Frontend C, the local CLI | P0; OQ-11 |

Each phase gets its own implementation plan. P2 is the bulk of the program and its four
tracks are independent, so they can run in parallel across sessions.

## 14. Process, and this document's revision history

1. **This document is the root spec.** Scope and architecture changes land here first.
2. **Every phase gets its own implementation plan** (superpowers writing-plans flow) in
   `docs/superpowers/plans/`, referencing this spec.
3. **Decisions get ADRs** — appended to §11 with date and status, never rewritten.
4. **Cross-repo note:** the metadata contract, `render-app`, and app templates land in
   `aspect-workflows-template`; Frontend A and the gitops wiring land in `vitruvian-core`;
   this spec, the coordination point, lives in `vitruvian-core`.
5. **Verification discipline:** each plan defines falsifiable checks up front (§10),
   matching the repo's test-the-real-path norms.

**Revision 2026-08-18b — repo stamping vs application stamping.** The first draft designed
the initializer to create new repositories via `publish:github`. That is repo stamping,
which the 13 existing templates already do. James corrected the framing: this initiative
stamps **applications into existing monorepos**, and must wire Bazel so the result works in
that monorepo. Consequences: the terminal action became
`publish:github:pull-request`; a new app-template asset replaced the monorepo-shaped tree;
ADR-008 inverted (one language per app, a simplification); the gitops step collapsed to a
single same-repo PR; Frontend C changed from "curated starters" (which are repo stamping,
not a frontend of this core) to a local CLI, matching Initializr's actual third frontend;
and OQ-5 resolved to ADR-011.
