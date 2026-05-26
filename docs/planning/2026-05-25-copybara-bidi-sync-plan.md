# Copybara Bidirectional Sync (Spec 3) — mcp-slack Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bidirectionally sync `vitruvian-core/mcp-slack/` ↔ `github.com/VitruvianSoftware/mcp-slack` (repo root) on push, near-real-time, with loops prevented (custom per-direction rev-id labels) and conflicts failing loud.

**Architecture:** Centralized hub in vitruvian-core: one `copy.bara.sky` with two workflows (`export_mcp_slack`, `import_mcp_slack`); an export GitHub Actions workflow (on push to `mcp-slack/**`) and an import workflow (on `repository_dispatch`); the standalone repo carries only a tiny dispatch workflow. Local validation precedes CI wiring because the loop-prevention behavior is the riskiest piece.

**Tech Stack:** Copybara (Starlark `copy.bara.sky`), the `copybara-action` GitHub Action (Docker + SSH), GitHub Actions (`repository_dispatch`), SSH deploy key + fine-grained PAT for auth.

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

### Task 4: Auth — deploy key + dispatch PAT (pilot)

**Files:** (no repo files; GitHub settings + secrets. For the pilot these are set up manually; Pulumi-codify when templating — see Notes.)

- [ ] **Step 1: Generate an ED25519 deploy key** for syncing: `ssh-keygen -t ed25519 -f /tmp/mcp-slack-sync -N "" -C "copybara-sync"`.
- [ ] **Step 2:** Add the **public** key as a **write-enabled deploy key** on `VitruvianSoftware/mcp-slack` (Settings → Deploy keys → Allow write access).
- [ ] **Step 3:** Add the **private** key as the secret `MCP_SLACK_SYNC_SSH_KEY` in `VitruvianSoftware/vitruvian-core` (used by both export and import workflows for SSH push).
- [ ] **Step 4:** Create a **fine-grained PAT** scoped to `vitruvian-core` with permission to send `repository_dispatch`; add it as the secret `MONOREPO_DISPATCH_TOKEN` in `VitruvianSoftware/mcp-slack`.
- [ ] **Step 5: Verify** the deploy key can push (test push to the `copybara-pilot` branch over SSH using the new key) and the PAT can dispatch (`curl` a test `repository_dispatch` to vitruvian-core and confirm a 204).

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

- [ ] **Step 1: Standalone dispatch workflow** (committed to the `mcp-slack` repo):
```yaml
name: Notify monorepo of changes
on:
  push:
    branches: [main]
jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - name: repository_dispatch to vitruvian-core
        run: |
          curl -fsS -X POST \
            -H "Authorization: Bearer ${{ secrets.MONOREPO_DISPATCH_TOKEN }}" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/repos/VitruvianSoftware/vitruvian-core/dispatches \
            -d '{"event_type":"mcp-slack-import"}'
```

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

- **Templating to devx / homelab / nexus-agent.** Parameterize `copy.bara.sky` + the workflows per project. For devx/homelab, exclude the monorepo-root `go.work` from `origin_files` so each standalone repo round-trips as a valid multi-module Go repo.
- **Pulumi-codify the auth** (deploy keys + dispatch PATs) the way the starter-repo deploy keys are managed, replacing the manual Task-4 setup.
- **`ITERATIVE` history mode** (commit-by-commit) if `SQUASH` loses too much fidelity.
- **The symmetric per-repo architecture** (documented in the spec) if decentralizing later.
