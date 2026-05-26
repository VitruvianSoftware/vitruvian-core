# Copybara Bidirectional Sync (Spec 3) — mcp-slack pilot

**Status:** Draft for review · 2026-05-25 — **partially superseded by the pilot.** History mode is `ITERATIVE`, not `SQUASH` (SQUASH's range-wide skip-guard got the export stuck), and conflicts do **not** fail loud — concurrent same-line edits silently diverge. See the `## Outcome` in [the plan](2026-05-25-copybara-bidi-sync-plan.md) and the operator runbook [`docs/copybara-bidi-sync.md`](../copybara-bidi-sync.md).

**Initiative:** Final piece of the VitruvianSoftware monorepo consolidation. Spec 1 built `vitruvian-core` and grafted devx/homelab/mcp-slack; Spec 2A/2B added Swift support and grafted nexus-agent. **Spec 3 (this):** keep each monorepo subfolder and its standalone GitHub repo in sync **bidirectionally** with Copybara — piloting on `mcp-slack` before templating to the rest.

## Goal & success criteria

Bidirectionally sync `vitruvian-core/mcp-slack/` ↔ `github.com/VitruvianSoftware/mcp-slack` (the standalone repo's root), near-real-time on push, such that:

1. A change pushed under `vitruvian-core/mcp-slack/` appears on the standalone repo — with **no import bounce-back**.
2. A change pushed to the standalone repo appears under `vitruvian-core/mcp-slack/` — with **no export bounce-back**.
3. A conflicting change (same content edited on both sides) **fails the sync loudly** (alert) — it never silently merges or overwrites.

## Decisions (from brainstorming)

- **True peer bidirectional** — both repos are actively developed; changes flow both ways (not a monorepo-as-source-of-truth mirror).
- **Pilot `mcp-slack` first**, then template to devx/homelab/nexus-agent. mcp-slack is TypeScript — simplest, and no `go.work`/Go-module complication.
- **On-push, near-real-time** trigger (not scheduled or manual).
- **Fail-loud conflicts** — manual resolution; no auto-winner, no silent merge.
- **Centralized hub** — all Copybara config + sync workflows live in vitruvian-core; the standalone repo only emits a `repository_dispatch` on push.
- **`SQUASH` history mode** for the pilot (one commit per sync, with notes referencing the originals); `ITERATIVE` (commit-by-commit) deferred.

## Architecture (centralized hub)

All sync logic lives in vitruvian-core:

- **`tools/copybara/copy.bara.sky`** — defines two `core.workflow`s:
  - `export_mcp_slack` (monorepo → standalone), and
  - `import_mcp_slack` (standalone → monorepo),
  each with a `core.move("mcp-slack", "")` transform mapping the subfolder to/from the standalone repo root, and `origin_files`/exclude globs so only `mcp-slack/**` participates.
- **`.github/workflows/copybara-export.yaml`** (vitruvian-core) — `on: push` to `mcp-slack/**`; runs the `export_mcp_slack` Copybara workflow (how Copybara is executed in CI — Docker image vs prebuilt JAR — is finalized in implementation; see Risks).
- **`.github/workflows/copybara-import.yaml`** (vitruvian-core) — `on: repository_dispatch` (type `mcp-slack-import`); runs `import_mcp_slack`.
- **Standalone `mcp-slack` repo** — one tiny workflow that fires a `repository_dispatch` (type `mcp-slack-import`) to vitruvian-core on push to `main`. (This is the only Copybara-related machinery the standalone repo carries.)

## Data flow & loop prevention

- **Export:** push under `mcp-slack/**` → Copybara pushes those changes to the standalone repo, stamping each resulting commit with a `GitOrigin-RevId` label referencing the originating monorepo commit.
- **Import:** standalone push → `repository_dispatch` → Copybara pulls standalone changes into `mcp-slack/`, stamping `GitOrigin-RevId` referencing the originating standalone commit.
- **Loop avoidance:** each direction reads these `GitOrigin-RevId` labels and **skips changes that originated from the other side**, so an exported change does not bounce back as an import (and vice-versa). Proving this no-bounce behavior end-to-end is the central goal of the pilot.

## Conflicts, loops & races (fail-loud)

- When both sides have diverged on the same content and Copybara cannot cleanly apply a sync, the workflow **fails** (red CI + notification). A human resolves by hand and re-runs. No auto-merge, no designated winner, no silent overwrite.
- The race window (both repos pushed within one sync cycle) is inherent to on-push peer bidi. Fail-loud means a race surfaces as a **failed run**, not as silent corruption.

## Auth / secrets

- **monorepo → standalone push:** a write **deploy key** on the standalone repo, stored as a secret in vitruvian-core. Managed via **Pulumi**, consistent with the existing starter-repo deploy-key setup.
- **standalone → monorepo dispatch:** a fine-grained **PAT (or GitHub App token)** with repo-dispatch scope on vitruvian-core, stored as a secret in the standalone repo. Also Pulumi-managed.
- vitruvian-core's import workflow pushes the imported change using its own `GITHUB_TOKEN` (same-repo write).

## History & path mapping

- Pilot uses Copybara **`SQUASH`** mode: each sync produces a single commit on the far side, with squash notes referencing the original commit(s). Simplest and Copybara's default. `ITERATIVE` (preserve each commit) is a noted future upgrade if per-commit fidelity matters.
- Path map: `mcp-slack/**` (monorepo) ↔ repo root (standalone), via `core.move`. mcp-slack is TypeScript, so there is no `go.work`/module-path concern here.

## Verification (pilot success criteria)

1. Edit a file in `vitruvian-core/mcp-slack/`, push → it appears on the standalone repo; confirm **no** import run bounces it back.
2. Edit a file on the standalone repo, push → it appears under `vitruvian-core/mcp-slack/`; confirm **no** export run bounces it back.
3. Edit the **same line** on both sides, push both → the sync **fails loudly** (does not silently merge or overwrite); resolve manually and confirm recovery.

## Templating to devx / homelab / nexus-agent (post-pilot)

Parameterize the pilot's config (project name, subfolder, standalone repo) per project. **Flagged risk for devx/homelab:** they remain multi-module (each keeps its own `go.mod`/`go.work`) so the standalone repo round-trips as a valid Go module. The monorepo-root `go.work` must **not** leak into the standalone repos — exclude it via Copybara `origin_files`/exclude globs. nexus-agent (Swift+Node+Python+shell) has no special module concern beyond path mapping.

## Alternative (documented for later): symmetric per-repo workflows

Instead of the centralized hub, each repo could run its own direction: vitruvian-core runs export on its push; each standalone repo runs import on its own push, with the Copybara config living in (or copied into) both. This makes each repo self-contained (no cross-repo `repository_dispatch`/PAT), at the cost of duplicating the config across 5 repos and putting Copybara machinery in every standalone repo. Recorded here in case decentralizing is preferred later; not chosen for the pilot.

## Out of scope (this spec)

- Rolling the sync out to devx/homelab/nexus-agent (a templated follow-up after the pilot proves out).
- `ITERATIVE` (commit-by-commit) history mode.
- PR-based review gating of synced changes.

## Risks & unknowns

- **Loop-prevention mechanics:** the exact `GitOrigin-RevId` handling that makes each direction skip the other side's changes is the riskiest piece — it is precisely what the pilot validates (success criteria 1 & 2).
- **Race window:** simultaneous pushes within one cycle. Mitigated (not eliminated) by fail-loud conflicts; acceptable for the pilot.
- **Copybara in GitHub Actions:** running Copybara in CI (Docker image or prebuilt JAR — there is no single canonical official image, so this is chosen during implementation) with SSH (deploy key) / token auth and persistent state for change detection.
- **`repository_dispatch` auth:** the PAT/App scope needed for the standalone repo to trigger vitruvian-core.
