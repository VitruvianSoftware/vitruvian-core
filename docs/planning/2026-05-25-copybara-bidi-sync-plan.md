# Copybara Bidirectional Sync (Spec 3) — mcp-slack Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bidirectionally sync `vitruvian-core/mcp-slack/` ↔ `github.com/VitruvianSoftware/mcp-slack` (repo root) on push, near-real-time, with loops prevented (custom per-direction rev-id labels) and conflicts failing loud.

**Architecture:** Centralized hub in vitruvian-core: one `copy.bara.sky` with two workflows (`export_mcp_slack`, `import_mcp_slack`); an export GitHub Actions workflow (on push to `mcp-slack/**`) and an import workflow (on `repository_dispatch`); the standalone repo carries only a tiny dispatch workflow. Local validation precedes CI wiring because the loop-prevention behavior is the riskiest piece.

**Tech Stack:** Copybara (Starlark `copy.bara.sky`), the `copybara-action` GitHub Action (Docker + SSH), GitHub Actions (`repository_dispatch`), SSH deploy key + GitHub App (dispatch) for auth — provisioned via Pulumi IaC (`vitruvian-core-infra` stack).

**Spec:** `docs/planning/2026-05-25-copybara-bidi-sync-design.md`

**READ FIRST (authoritative references — Copybara syntax is version-specific, do not rely on memory):**
- Copybara examples: <https://github.com/google/copybara/blob/master/docs/examples.md>
- Bidirectional rev-id-label pattern (the crux): <https://dagster.io/blog/monorepos-the-hub-and-spoke-model-and-copybara> and the config <https://github.com/dagster-io/skills/blob/master/copy.bara.sky>
- copybara-action: <https://github.com/marketplace/actions/copybara-action>

**Prerequisites:** push access (your own git creds) to both `VitruvianSoftware/vitruvian-core` and `VitruvianSoftware/mcp-slack`; Docker available locally for running Copybara during the local-validation tasks.

---

### Task 1: Working one-way export, validated locally (monorepo → standalone)

**Files:**
- Create: `vitruvian-core/tools/copybara/copy.bara.sky`

- [ ] **Step 1: Write the `export_mcp_slack` workflow.** Start from this skeleton, then correct syntax against the READ-FIRST references:
```python
# tools/copybara/copy.bara.sky
MONOREPO = "git@github.com:VitruvianSoftware/vitruvian-core.git"
STANDALONE = "git@github.com:VitruvianSoftware/mcp-slack.git"
AUTHOR = "VitruvianSoftware Sync <sync@vitruviansoftware.com>"

core.workflow(
    name = "export_mcp_slack",
    origin = git.origin(url = MONOREPO, ref = "main"),
    destination = git.destination(url = STANDALONE, push = "main"),
    origin_files = glob(["mcp-slack/**"]),
    destination_files = glob(["**"]),
    authoring = authoring.pass_thru(AUTHOR),
    mode = "SQUASH",
    transformations = [core.move("mcp-slack", "")],
)
```

- [ ] **Step 2: Dry-run the export to a scratch branch.** Run Copybara locally (Docker) pointing the destination `push` at a throwaway branch `copybara-pilot` (NOT `main`) so nothing real is touched yet. Resolve any config/syntax errors here.
Expected: Copybara creates/updates `copybara-pilot` on the standalone repo.

- [ ] **Step 3: Verify the export result.** Clone/fetch the standalone repo's `copybara-pilot` branch; confirm its root matches `vitruvian-core/mcp-slack/` (the `core.move` stripped the prefix) and the commit carries a `GitOrigin-RevId` label.
Expected: file trees match; rev-id label present.

- [ ] **Step 4: Commit the config.**
```bash
git -C vitruvian-core add tools/copybara/copy.bara.sky
git -C vitruvian-core commit -m "feat(copybara): export_mcp_slack workflow (validated locally)"
```

### Task 2: Working one-way import, validated locally (standalone → monorepo)

**Files:**
- Modify: `vitruvian-core/tools/copybara/copy.bara.sky` (add the import workflow)

- [ ] **Step 1: Add the `import_mcp_slack` workflow:**
```python
core.workflow(
    name = "import_mcp_slack",
    origin = git.origin(url = STANDALONE, ref = "main"),
    destination = git.destination(url = MONOREPO, push = "main"),
    origin_files = glob(["**"]),
    destination_files = glob(["mcp-slack/**"]),
    authoring = authoring.pass_thru(AUTHOR),
    mode = "SQUASH",
    transformations = [core.move("", "mcp-slack")],
)
```

- [ ] **Step 2: Dry-run the import to a scratch branch.** Run the import workflow locally with the monorepo destination `push` set to a throwaway branch `copybara-pilot-import`.
Expected: the standalone repo's content lands under `mcp-slack/` on that branch.

- [ ] **Step 3: Verify the import result.** Confirm the standalone files appear under `mcp-slack/` (the reverse `core.move`) and nothing outside `mcp-slack/` changed.
Expected: only `mcp-slack/**` modified; rev-id label present.

- [ ] **Step 4: Commit.**
```bash
git -C vitruvian-core add tools/copybara/copy.bara.sky
git -C vitruvian-core commit -m "feat(copybara): import_mcp_slack workflow (validated locally)"
```

### Task 3: Bidirectional loop prevention (the crux — validate no-bounce)

**Files:**
- Modify: `vitruvian-core/tools/copybara/copy.bara.sky`

- [ ] **Step 1: Give each direction a distinct rev-id label.** Per the dagster reference, the two directions must NOT share the default `GitOrigin-RevId` or iterative/repeat syncs misattribute commits and loop. Configure the export to stamp one label (e.g. `MonorepoRevId`) and the import another (e.g. `McpSlackRevId`), using the label-customization mechanism shown in the dagster `copy.bara.sky` / Copybara docs. Apply it to both workflows.

- [ ] **Step 2: Reset the scratch branches to mirror `main`** on both repos (clean slate for the round-trip test).

- [ ] **Step 3: Export, then import, against the scratch branches.** Make a change under `vitruvian-core/mcp-slack/`, run `export`, then run `import`.
Expected: the `import` run reports **no migratable changes** for the just-exported commit (it recognizes the label and skips it) — i.e. no bounce-back.

- [ ] **Step 4: Reverse round-trip.** Make a change on the standalone scratch branch, run `import`, then run `export`.
Expected: the `export` run reports **no migratable changes** for the just-imported commit — no bounce-back.

- [ ] **Step 5: Commit the validated bidi config.**
```bash
git -C vitruvian-core add tools/copybara/copy.bara.sky
git -C vitruvian-core commit -m "feat(copybara): distinct per-direction rev-id labels (no-bounce verified locally)"
```

### Task 4: Auth — deploy key + GitHub App, via Pulumi IaC ✅ DONE (2026-05-25)

**Decision (supersedes the original manual/PAT plan):** auth is **codified in Pulumi**, consistent with the starter-repo deploy-key setup — not configured by hand. The import trigger uses a **GitHub App** (not a fine-grained PAT), so the credential is org-managed and rotatable.

**Files:**
- `infrastructure/pulumi/pkg/copybara_sync/sync.go` (+ `Pulumi.yaml`, `main.go`) — project `vitruvian-core-infra`, stack `dev`.

- [x] **Step 1: GitHub App (one-time manual operator bootstrap).** Create App `vitruvian-copybara-sync` (App ID **3863936**) under the VitruvianSoftware org: Contents **Read & write**, webhook off; **install on `vitruvian-core` only** (least-privilege — it only fires `repository_dispatch` *into* the monorepo). Generate a private key (`.pem`). Created by hand because GitHub has no headless App-creation API; Pulumi only places its credentials.
- [x] **Step 2: Provision the rest via Pulumi** (`pkg/copybara_sync/sync.go`): an ED25519 `tls.PrivateKey` → a **write** `RepositoryDeployKey` on `mcp-slack` → the private half as `MCP_SLACK_SYNC_SSH_KEY` in `vitruvian-core` (export push) → the App id/key as `MCP_SLACK_DISPATCH_APP_ID` + `MCP_SLACK_DISPATCH_APP_PRIVATE_KEY` secrets in `mcp-slack` (import dispatch). App creds supplied as stack config secrets `mcpSlackDispatchAppId` / `mcpSlackDispatchAppPrivateKey`.
- [x] **Step 3: Apply.** `pulumi config set --secret` the App id + key (key read from the `.pem` via stdin, never printed) → `pulumi preview` → `pulumi up` (6 resources). GitHub provider auth via `GITHUB_TOKEN`/`GITHUB_OWNER=VitruvianSoftware` env.
- [x] **Step 4: Verify** (`gh api`): the `mcp-slack` write deploy key (`copybara-sync (write)`, read_only=false), the two `mcp-slack` App secrets, and the `vitruvian-core` `MCP_SLACK_SYNC_SSH_KEY` all exist. ✅ all confirmed.

### Task 5: Export workflow in CI (vitruvian-core)

**Files:**
- Create: `vitruvian-core/.github/workflows/copybara-export.yaml`

- [ ] **Step 1: Write the export workflow** (pin `copybara-action` by commit SHA per the repo's action-pinning convention):
```yaml
name: Copybara Export (mcp-slack)
on:
  push:
    branches: [main]
    paths: ["mcp-slack/**"]
jobs:
  export:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Copybara export mcp-slack -> standalone
        uses: olivr/copybara-action@<PINNED_SHA>  # resolve latest release SHA
        with:
          ssh_key: ${{ secrets.MCP_SLACK_SYNC_SSH_KEY }}
          access_token: ${{ secrets.GITHUB_TOKEN }}
          copybara_options: "--ignore-noop"
          workflow: export_mcp_slack
          copybara_config: tools/copybara/copy.bara.sky
```
(If `copybara-action`'s inputs differ from the above, adjust per its README — the action README is authoritative for input names.)

- [ ] **Step 2: Point the config back at `main`.** Change the destination `push` in both workflows from the scratch branches to `main` now that no-bounce is proven.
- [ ] **Step 3: Commit + push a no-op-ish change under `mcp-slack/`** (e.g. a comment) to trigger the workflow.
- [ ] **Step 4: Verify** the export run is green and the change appears on the standalone repo `main` with the `MonorepoRevId` label.
- [ ] **Step 5: Commit** (the workflow file was committed in Step 1's commit; this confirms green).

### Task 6: Standalone dispatch + monorepo import workflow

**Files:**
- Create (in `VitruvianSoftware/mcp-slack`): `.github/workflows/sync-to-monorepo.yaml`
- Create (in vitruvian-core): `.github/workflows/copybara-import.yaml`

- [ ] **Step 1: Standalone dispatch workflow** (committed to the `mcp-slack` repo). Mints a short-lived token from the `vitruvian-copybara-sync` App (secrets provisioned by Pulumi in Task 4) and fires the `repository_dispatch` — no PAT:
```yaml
name: Notify monorepo of changes
on:
  push:
    branches: [main]
jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - name: Mint dispatch token from GitHub App
        id: app-token
        uses: actions/create-github-app-token@<PINNED_SHA>  # pin to a release SHA
        with:
          app-id: ${{ secrets.MCP_SLACK_DISPATCH_APP_ID }}
          private-key: ${{ secrets.MCP_SLACK_DISPATCH_APP_PRIVATE_KEY }}
          owner: VitruvianSoftware
          repositories: vitruvian-core
      - name: repository_dispatch to vitruvian-core
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
        run: gh api -X POST repos/VitruvianSoftware/vitruvian-core/dispatches -f event_type=mcp-slack-import
```
(The App needs Contents:write on `vitruvian-core` — which `repository_dispatch` requires — and must be installed there; both done in Task 4.)

- [ ] **Step 2: Import workflow** (vitruvian-core):
```yaml
name: Copybara Import (mcp-slack)
on:
  repository_dispatch:
    types: [mcp-slack-import]
jobs:
  import:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Copybara import standalone -> mcp-slack
        uses: olivr/copybara-action@<PINNED_SHA>
        with:
          ssh_key: ${{ secrets.MCP_SLACK_SYNC_SSH_KEY }}
          access_token: ${{ secrets.GITHUB_TOKEN }}
          copybara_options: "--ignore-noop"
          workflow: import_mcp_slack
          copybara_config: tools/copybara/copy.bara.sky
```

- [ ] **Step 3: Trigger** by pushing a small change to the standalone repo `main`.
- [ ] **Step 4: Verify** the dispatch fires, the import workflow runs green, and the change appears under `vitruvian-core/mcp-slack/` on `main` with the `McpSlackRevId` label — and crucially that the export workflow does NOT then bounce it back (watch both repos' Actions).
- [ ] **Step 5: Commit** the vitruvian-core import workflow.

### Task 7: End-to-end verification (spec success criteria)

**Files:** (verification only)

- [ ] **Step 1: Export round-trip, no bounce.** Edit `vitruvian-core/mcp-slack/README` (or any file), push → confirm it lands on the standalone repo and NO import run re-applies it.
- [ ] **Step 2: Import round-trip, no bounce.** Edit a file on the standalone repo, push → confirm it lands under `vitruvian-core/mcp-slack/` and NO export run re-applies it.
- [ ] **Step 3: Conflict fails loud.** Edit the **same line** on both repos and push both within a short window → confirm the losing-direction sync run **fails** (red CI), nothing is silently merged/overwritten; then resolve manually and confirm recovery.
- [ ] **Step 4: Document the pilot outcome** in an `## Outcome` section appended to the spec/plan (what worked, the exact label-customization syntax that proved out, the `copybara-action` inputs used), so templating to devx/homelab/nexus-agent is mechanical.

---

## Notes on iteration

The genuinely uncertain pieces — the exact rev-id-label customization syntax (Task 3) and the `copybara-action` input names (Tasks 5–6) — are validated against the real tool in the early/local tasks before any CI or `main` wiring. Keep the destination `push` on throwaway branches until Task 5 Step 2. Use `superpowers:systematic-debugging` when a sync misbehaves (especially bounce-backs — that means the rev-id labels aren't being read).

## Deferred (not this plan)

- ~~**Templating to devx / homelab / nexus-agent.**~~ — **DONE 2026-05-26** (see Templating outcome below). `copy.bara.sky` is now a `COMPONENTS` loop; CI is two reusable workflows + per-component callers. The `go.work` concern was moot — it sits at the monorepo root, outside every `<comp>/**` glob, so it's monorepo-only for free. The real per-component exclude is `**/BUILD` (gazelle generates many; devx has 57).
- ~~**Template the auth to devx/homelab/nexus-agent.**~~ — **DONE 2026-05-26.** Appended the three to `syncedProjects`; **reused the single existing App** (App ID 3863936) with its creds placed as per-component config secrets; `pulumi up` created 3 deploy keys + 3 monorepo SSH secrets + 6 standalone App secrets.
- **Harden the Copybara image pin (GHCR mirror) — PREPARED, pending an operator hand-off.** Still `olivr/copybara@sha256:87e2e90…` from Docker Hub. Mirroring to `ghcr.io/vitruviansoftware/copybara` + repinning needs a token with `write:packages` (the automation token has only `repo`/`workflow`). Exact steps in the runbook §10 ("Pending hardening — mirror the Copybara image to GHCR"). Do not repin before the GHCR image exists.
- ~~`ITERATIVE` history mode~~ — **adopted during the pilot** (see Outcome): it is *required* for correct bidi loop-prevention, not an optional fidelity upgrade.
- **The symmetric per-repo architecture** (documented in the spec) if decentralizing later.

---

## Outcome (pilot executed end-to-end in CI, 2026-05-26)

The pilot ran live against `main` on both repos. **Result: bidirectional no-bounce sync works; fail-loud conflict handling does not.** Operator runbook: [`docs/copybara-bidi-sync.md`](../copybara-bidi-sync.md).

**Success criteria:**
- **1 — export round-trip, no bounce: ✅** A monorepo `mcp-slack/` edit reaches the standalone; the dispatch-triggered import skip-guards it (no bounce).
- **2 — import round-trip, no bounce: ✅** A standalone edit reaches `vitruvian-core/mcp-slack/`; no export bounces it back.
- **3 — conflict fails loud: ❌** Concurrent edits to the *same line* on both repos **silently diverge** — both syncs run green and the repos end up holding opposite values, with no error. Copybara's `git.destination` state-syncs (overwrites the destination to match the origin); the rev-id labels do loop-prevention, **not** conflict-detection. Before production with concurrent writers, add one of: a pre-push baseline check (fail if the destination's rev-id ≠ expected), serialized syncs (a lock/queue so two never run at once), or an external consistency monitor.

**Key decisions proven out (details + diagrams in the runbook):**
- **History mode = `ITERATIVE`, not `SQUASH`.** SQUASH evaluates the skip-guard over the whole squashed range, so a range that merely *contains* a peer-origin commit is skipped entirely — including genuine changes batched with it; in CI this left the export direction **stuck** after any import. ITERATIVE runs the skip-guard per commit.
- **Rev-id syntax = `experimental_custom_rev_id`** with `_REV_ID` labels — required by the pinned 2023 `olivr/copybara` build.
- **Run the `olivr/copybara` image directly** (pinned `@sha256:87e2e90…`), NOT `olivr/copybara-action`: the action reads `ssh_key` via `core.getInput` (trims the trailing newline) and writes it verbatim, yielding an `id_rsa` OpenSSH rejects as "invalid format".
- **Auth via Pulumi IaC** (`infrastructure/pulumi`, project `vitruvian-core-infra`) + a **GitHub App** (`vitruvian-copybara-sync`, App ID 3863936) for the dispatch — App is a one-time manual operator bootstrap.
- **`GITHUB_TOKEN` pushes don't trigger workflows** — the import's push to monorepo `main` does not re-trigger the export (extra no-bounce safety).

---

## Templating outcome (devx / homelab / nexus-agent, 2026-05-26)

All three onboarded and validated; the drift check reports **all four components in sync**.

**What was built:**
- **`copy.bara.sky`** parameterized to a `COMPONENTS` loop. Copybara's Starlark forbids top-level `for`, so a `_define_component()` function is driven by a top-level list comprehension; the closure-based `dynamic_transform` skip-guard works. Validated offline with `docker run --network none` (config evaluates; lists all 8 workflows). Export label `MONOREPO_REV_ID` is shared (each lands on a separate standalone); import labels are unique per component (`DEVX_REV_ID`, …) since they all land in the shared monorepo. Monorepo-only exclude unified to `**/BUILD`.
- **CI:** two reusable workflows (`_copybara-{export,import}.yaml`) hold the logic + image pin; thin per-component callers own the triggers. `conflict-precheck.sh` and `copybara-drift-check.yaml` generalized to all components. `actionlint` clean.

**New lessons (beyond the pilot):**
- **Seeding needs a real migration, not just `--force`.** A fresh destination errors unless `--init-history` is passed, and the baseline is anchored by a commit that touches managed paths. When the repos are already byte-identical the seed no-ops and stamps nothing — so seed via a transient marker (add in monorepo → `--force --squash --init-history` export → remove on standalone → `--force --last-rev <export-seed-SHA>` import). **The import seed must NOT use `--squash`**: the squash range includes the export-seed `Project import` commit (carries `MONOREPO_REV_ID`) and the skip-guard drops the whole squash (the SQUASH-over-fire again). Full recipe in runbook §8b.
- **Imports must not share a concurrency group.** All imports push to the same monorepo `main`; a shared group made GitHub cancel an intermediate pending import (would drop a change). Fix: per-component groups + a **retry** in the import reusable (a "behind destination" push just means another import landed first; re-running re-fetches and replays). Runbook §10.
- **Pulumi:** reused the one App (creds copied to per-component config keys via `get | set --secret`, never printed); set `github:owner=VitruvianSoftware`; run with `GOWORK=off` (the pulumi program is its own module outside `go.work`).

**Still pending:** the GHCR image mirror (operator hand-off — needs `write:packages`; see Deferred + runbook §10).
