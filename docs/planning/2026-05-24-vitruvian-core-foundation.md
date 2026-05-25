# vitruvian-core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `VitruvianSoftware/vitruvian-core` from the kitchen-sink template and bring `homelab`, `devx`, and `mcp-slack` to a green `bazel build //...` + `bazel test //...`, with full git history preserved.

**Architecture:** Create a new repo from the kitchen-sink template (configured, source-light Bazel monorepo). Graft each project into a top-level folder via `git-filter-repo` (history-preserving merge). Integrate the two Go projects as **separate Go modules** (each keeps its own `go.mod`/module path, wired through a root `go.work` + per-module `go_deps.from_file`) and the TypeScript project into the existing pnpm + `aspect_rules_ts` workspace. Use Gazelle to generate BUILD files; iterate to green on Linux.

**Tech Stack:** Bazel (bzlmod) · rules_go 0.59 + Gazelle 0.47 · aspect_rules_js/ts + pnpm · git-filter-repo · gh CLI.

**Prerequisites:**
- `git-filter-repo` installed (`brew install git-filter-repo`).
- `gh` authenticated as a user with create rights in `VitruvianSoftware`.
- Bazel via the repo's `bazelisk`/`tools` (the template pins it).
- Decide repo visibility before Task 1 (these are OSS → likely `--public`).

---

### Task 1: Create vitruvian-core from the template and verify the baseline

**Files:**
- Modify: `BUILD` (root gazelle prefix)

- [ ] **Step 1: Create the repo from the template and clone**

```bash
gh repo create VitruvianSoftware/vitruvian-core \
  --template VitruvianSoftware/kitchen-sink --public --clone
cd vitruvian-core
```
(Swap `--public` for `--private` if James prefers. This creates a fresh repo seeded from the template — not a clone/fork of kitchen-sink.)

- [ ] **Step 2: Verify the baseline monorepo builds green**

Run: `bazel build //... && bazel test //...`
Expected: PASS. The template is known-good. **If this fails, STOP** — fix the baseline before grafting anything (a broken baseline makes later failures impossible to attribute).

- [ ] **Step 3: Set the root Gazelle prefix**

The root `BUILD` ships `# gazelle:prefix github.com/example/project`. Replace with a neutral monorepo prefix (per-project folders override it with their own prefix in later tasks):

```
# gazelle:prefix github.com/VitruvianSoftware/vitruvian-core
```

- [ ] **Step 4: Commit**

```bash
git add BUILD
git commit -m "chore: set root gazelle prefix for vitruvian-core"
```

---

### Task 2: Graft `homelab` (smallest Go project — proves the multi-module pattern)

**Files:**
- Create: `homelab/` (grafted tree), `homelab/BUILD.bazel`, `go.work`
- Modify: `MODULE.bazel`, root `go.mod` (go directive if needed)

- [ ] **Step 1: Rewrite homelab's history under `homelab/` in a scratch clone**

```bash
cd /tmp && rm -rf homelab-graft
git clone https://github.com/VitruvianSoftware/homelab homelab-graft
cd homelab-graft && git filter-repo --to-subdirectory-filter homelab/
```
Expected: every path (incl. `homelab/go.mod`, `homelab/cmd`, `homelab/internal`) now lives under `homelab/`.

- [ ] **Step 2: Merge into vitruvian-core, preserving history**

```bash
cd "$VITRUVIAN_CORE"   # the vitruvian-core checkout from Task 1
git remote add homelab-graft /tmp/homelab-graft
git fetch homelab-graft
git merge --allow-unrelated-histories homelab-graft/main \
  -m "feat: graft homelab into monorepo (history-preserving)"
git remote remove homelab-graft
```
Expected: `homelab/` present; `git log -- homelab/` shows the original commits.

- [ ] **Step 3: Register homelab as a second Go module**

Create `go.work` at the repo root:
```
go 1.26.2

use (
    .
    ./homelab
)
```
In `MODULE.bazel`, immediately after the existing `go_deps.from_file(go_mod = "//:go.mod")` line, add:
```
go_deps.from_file(go_mod = "//homelab:go.mod")
```
If the root `go.mod` `go` directive is below `1.26.2`, bump it to `go 1.26.2` so `go_sdk.from_file` fetches a sufficient SDK.

- [ ] **Step 4: Set homelab's Gazelle prefix and generate BUILD files**

```bash
printf '# gazelle:prefix github.com/VitruvianSoftware/homelab\n' > homelab/BUILD.bazel
bazel run //:gazelle
```
Expected: `BUILD.bazel` files generated under `homelab/cmd/...` and `homelab/internal/...`.

- [ ] **Step 5: Resolve deps and build + test homelab**

```bash
bazel mod tidy
bazel build //homelab/... && bazel test //homelab/...
```
Expected: PASS. If not, iterate on the most common causes:
- *Unknown repo for a dep* → re-run `bazel mod tidy` then `bazel run //:gazelle`.
- *Go SDK too old* → bump root `go.mod` `go` directive (Step 3) and retry.
- *A test needs network/filesystem* → add `tags = ["manual"]` to that `go_test` (note it for follow-up; do not silently delete tests).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(homelab): build under bazel (multi-module + gazelle)"
```

---

### Task 3: Graft `devx` (Go, larger — 81 test files, charmbracelet TUI deps)

**Files:**
- Create: `devx/` (grafted tree), `devx/BUILD.bazel`
- Modify: `go.work`, `MODULE.bazel`, root `go.mod` (go directive if needed)

- [ ] **Step 1: Rewrite devx's history under `devx/` in a scratch clone**

```bash
cd /tmp && rm -rf devx-graft
git clone https://github.com/VitruvianSoftware/devx devx-graft
cd devx-graft && git filter-repo --to-subdirectory-filter devx/
```
Expected: paths under `devx/` (incl. `devx/go.mod`, `devx/cmd`, `devx/internal`).

- [ ] **Step 2: Merge into vitruvian-core, preserving history**

```bash
cd "$VITRUVIAN_CORE"
git remote add devx-graft /tmp/devx-graft
git fetch devx-graft
git merge --allow-unrelated-histories devx-graft/main \
  -m "feat: graft devx into monorepo (history-preserving)"
git remote remove devx-graft
```

- [ ] **Step 3: Register devx as a Go module**

Update `go.work` `use (...)` to add `./devx`:
```
use (
    .
    ./homelab
    ./devx
)
```
Do **not** add another `go_deps.from_file` line — Gazelle 0.47 allows only one `from_file` tag per module, and the existing `go_deps.from_file(go_work = "//:go.work")` (established in Task 2) already covers every `go.work` member. After updating `go.work`, just run `bazel mod tidy`. (devx is go 1.25.5 — already covered by the root SDK ≥1.26.2 from Task 2.)

- [ ] **Step 4: Set devx's Gazelle prefix and generate BUILD files**

```bash
printf '# gazelle:prefix github.com/VitruvianSoftware/devx\n' > devx/BUILD.bazel
bazel run //:gazelle
```
Expected: BUILD files under `devx/cmd/...`, `devx/internal/...`.

- [ ] **Step 5: Resolve deps and build + test devx**

```bash
bazel mod tidy
bazel build //devx/... && bazel test //devx/...
```
Expected: PASS. devx-specific watch-items:
- charmbracelet (bubbletea/huh/lipgloss) are pure-Go libs → Gazelle handles them after `bazel mod tidy`.
- Some of the 81 tests may assume a TTY or local files → mark those `tags = ["manual"]` and list them for follow-up rather than deleting.
- devx's minor Python/TS helper code is **not** in scope for the green build — leave it un-Bazelized for now (only `//devx/...` Go targets must build/test).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(devx): build under bazel (multi-module + gazelle)"
```

---

### Task 4: Graft `mcp-slack` (TypeScript) into the pnpm + rules_ts workspace

**Files:**
- Create: `mcp-slack/` (grafted tree), `mcp-slack/BUILD.bazel`
- Modify: `pnpm-workspace.yaml` (create if absent), `package.json`/`pnpm-lock.yaml`

- [ ] **Step 1: Rewrite mcp-slack's history under `mcp-slack/`**

```bash
cd /tmp && rm -rf mcp-slack-graft
git clone https://github.com/VitruvianSoftware/mcp-slack mcp-slack-graft
cd mcp-slack-graft && git filter-repo --to-subdirectory-filter mcp-slack/
```

- [ ] **Step 2: Merge into vitruvian-core, preserving history**

```bash
cd "$VITRUVIAN_CORE"
git remote add mcp-slack-graft /tmp/mcp-slack-graft
git fetch mcp-slack-graft
git merge --allow-unrelated-histories mcp-slack-graft/main \
  -m "feat: graft mcp-slack into monorepo (history-preserving)"
git remote remove mcp-slack-graft
```

- [ ] **Step 3: Add mcp-slack to the pnpm workspace (npm → pnpm)**

mcp-slack ships an npm `package-lock.json`; the monorepo uses pnpm. Add it to the workspace and drop the npm lock:
```bash
# Ensure pnpm-workspace.yaml exists at root and lists packages:
cat > pnpm-workspace.yaml <<'YAML'
packages:
  - "mcp-slack"
YAML
rm -f mcp-slack/package-lock.json
```
Regenerate the root lockfile with the monorepo's pnpm (via the Bazel-managed pnpm or a local pnpm):
```bash
pnpm -w install --lockfile-only
```
Expected: root `pnpm-lock.yaml` now includes `mcp-slack` and its `@modelcontextprotocol/sdk` dep.

- [ ] **Step 4: Generate JS BUILD files and add the TS compile target**

```bash
bazel run //:gazelle
```
Gazelle (with `aspect_rules_js`) generates `js_library`/`npm` targets. Because mcp-slack is **TypeScript** (`tsconfig.json`, `src/`, `build` script = `tsc`), add an explicit `ts_project` in `mcp-slack/BUILD.bazel`:
```python
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")

ts_project(
    name = "mcp-slack",
    srcs = glob(["src/**/*.ts"]),
    tsconfig = "tsconfig.json",
    declaration = True,
    transpiler = "tsc",
    deps = [":node_modules/@modelcontextprotocol/sdk"],
    visibility = ["//visibility:public"],
)
```
(Adjust `deps` to the `node_modules` labels Gazelle created.)

- [ ] **Step 5: Build mcp-slack**

```bash
bazel build //mcp-slack/...
```
Expected: PASS — the TS compiles via `ts_project`. Common fixes:
- *`tsconfig` extends a base not present* → vendor the referenced base or inline the needed compilerOptions.
- *Missing `@types/*`* → add to `mcp-slack/package.json` devDependencies and re-run Step 3.
(mcp-slack has no test script today — no `bazel test` target required for it.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(mcp-slack): build under bazel (pnpm workspace + ts_project)"
```

---

### Task 5: Verify the whole monorepo is green and CI builds it

**Files:**
- Modify: `.github/workflows/ci.yaml` (only if target adjustments are needed)

- [ ] **Step 1: Full-tree build + test locally**

```bash
bazel build //... && bazel test //...
```
Expected: PASS across `//homelab/...`, `//devx/...`, `//mcp-slack/...`, and the template's own targets.

- [ ] **Step 2: Confirm history was preserved**

```bash
git log --oneline -- homelab/ | tail -3
git log --oneline -- devx/ | tail -3
git log --oneline -- mcp-slack/ | tail -3
```
Expected: each shows original pre-graft commits (not just the merge).

- [ ] **Step 3: Push and watch CI**

```bash
git push -u origin main
gh run watch "$(gh run list -R VitruvianSoftware/vitruvian-core --limit 1 --json databaseId -q '.[0].databaseId')" \
  -R VitruvianSoftware/vitruvian-core --exit-status
```
Expected: CI green on `ubuntu-latest`. (Per James's standing preference, always watch the run.) If CI fails on something that passed locally, it's usually a toolchain/cache difference — reproduce with `--config=ci` locally.

---

### Task 6: Relocate the spec and this plan into vitruvian-core

**Files:**
- Move: `docs/superpowers/specs/2026-05-24-vitruvian-core-foundation-design.md` and `docs/superpowers/plans/2026-05-24-vitruvian-core-foundation.md` → into `vitruvian-core/docs/`

- [ ] **Step 1: Copy the planning docs into the new repo**

```bash
mkdir -p "$VITRUVIAN_CORE/docs/planning"
cp "$TEMPLATE_REPO/docs/superpowers/specs/2026-05-24-vitruvian-core-foundation-design.md" "$VITRUVIAN_CORE/docs/planning/"
cp "$TEMPLATE_REPO/docs/superpowers/plans/2026-05-24-vitruvian-core-foundation.md" "$VITRUVIAN_CORE/docs/planning/"
```

- [ ] **Step 2: Commit in vitruvian-core, and remove the transient copies from the template repo**

```bash
cd "$VITRUVIAN_CORE" && git add docs/planning && git commit -m "docs: add vitruvian-core foundation spec + plan"
cd "$TEMPLATE_REPO" && git rm -r docs/superpowers && git commit -m "chore: move vitruvian-core planning docs to vitruvian-core repo"
```
(Push the template-repo cleanup only after confirming the docs landed in vitruvian-core.)

---

## Notes on iteration (honest expectation-setting)

Tasks 2–4's "build + test" steps are genuinely **iterative** — the projects have no existing Bazel setup, so Gazelle output plus dependency resolution will need a few rounds of `bazel mod tidy` → `gazelle` → build. The commands and common-failure fixes above cover the expected cases; novel failures should be debugged with `superpowers:systematic-debugging` rather than guessed at. Do **not** delete or stub tests to force green — quarantine with `tags = ["manual"]` and record them for follow-up.

## Deferred to later specs

- **Swift / `nexus-agent`** → Spec 2 (also adds `rules_swift`/`rules_apple` + `swift`/`backstage-swift` presets to the template on `platform-v2.0`; needs a macOS CI runner).
- **Copybara bidirectional sync** → Spec 3 (the per-project folder layout + preserved module paths set this up).
