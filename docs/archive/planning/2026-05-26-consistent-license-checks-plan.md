# Consistent License Headers + Checks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every vitruvian-core component (and the monorepo's own hand-authored files) carries an MIT license header, enforced by `addlicense` both in the monorepo CI (whole-repo) and in each standalone's own CI.

**Architecture:** One `addlicense` add-mode pass headers the whole monorepo (headers fan out to standalones via the Copybara export). The monorepo `license-check` CI job is widened from devx-only to the whole repo. Each standalone gets its own `addlicense -check` (devx already has one; add to homelab + mcp-slack `ci.yml`; create one for nexus-agent). Generated/tool-managed files are ignored so the tool never fights their regeneration.

**Tech Stack:** `github.com/google/addlicense@v1.2.0`, GitHub Actions, Copybara bidi-sync.

**Spec:** [`docs/planning/2026-05-26-consistent-license-checks-design.md`](2026-05-26-consistent-license-checks-design.md). **Sync runbook:** [`docs/copybara-sync.md`](../../admin/copybara-sync.md) §9.

**Conventions:** run from repo root `/Users/james/Workspace/gh/application/vitruvian/vitruvian-core` unless noted. `addlicense` is invoked at `"$(go env GOPATH)/bin/addlicense"` (GOPATH/bin isn't on PATH locally or on CI runners). Commit with the bot identity for standalone-bound edits where the existing convention uses it; monorepo commits use the repo's default identity.

---

## Canonical ignore lists (used verbatim below)

**MONOREPO (whole-repo, run from repo root) — `MONO_IGNORES`:**
```
-ignore "**/BUILD" -ignore "**/BUILD.bazel" \
-ignore "**/docs/**" -ignore "**/internal/scaffold/templates/**" \
-ignore "pnpm-lock.yaml" -ignore "**/package-lock.json" -ignore "**/Cargo.lock" -ignore "MODULE.bazel.lock" \
-ignore "**/gazelle_python.yaml" -ignore "**/*-baseline.xml" -ignore "**/.release-please-manifest.json" \
-ignore "bazel-*/**" -ignore "**/node_modules/**" -ignore "**/*.venv/**" -ignore ".git/**"
```

**Per-standalone (NO `**/BUILD` — standalones have no Bazel files):**
- **devx:** `-ignore "docs/**" -ignore "internal/scaffold/templates/**"` (existing)
- **homelab:** *(none needed — Go; `go.sum` isn't addlicense-recognized; confirm via dry-run)*
- **mcp-slack:** `-ignore "package-lock.json" -ignore "node_modules/**"`
- **nexus-agent:** `-ignore "package-lock.json" -ignore "node_modules/**" -ignore ".release-please-manifest.json"`

---

## File structure

| File | Change |
|---|---|
| (whole monorepo, ~80–90 hand-authored files) | addlicense add-mode adds MIT headers (Task 1) |
| `.github/workflows/ci.yaml` (monorepo) | widen `license-check` job from devx-only to whole-repo (Task 2) |
| `devx/.github/workflows/ci.yml` | re-pin addlicense `@latest`→`@v1.2.0` (Task 3) |
| `homelab/.github/workflows/ci.yml` | add a `license-check` job (Task 3) |
| `mcp-slack/.github/workflows/ci.yml` | add a `license-check` job (Task 3) |
| `nexus-agent/.github/workflows/license-check.yml` | **create** (nexus-agent has no `ci.yml`) (Task 4) |

---

### Task 1: Header the whole monorepo (addlicense add-mode)

**Files:** ~80–90 hand-authored files across homelab, nexus-agent, mcp-slack, and monorepo-only tooling/config (devx already compliant → unchanged).

- [ ] **Step 1: Install the pinned tool**

```bash
go install github.com/google/addlicense@v1.2.0
ls "$(go env GOPATH)/bin/addlicense"   # expect the path to exist
```

- [ ] **Step 2: Dry-run the CHECK first to capture the baseline (what's missing)**

```bash
"$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
  -ignore "**/BUILD" -ignore "**/BUILD.bazel" \
  -ignore "**/docs/**" -ignore "**/internal/scaffold/templates/**" \
  -ignore "pnpm-lock.yaml" -ignore "**/package-lock.json" -ignore "**/Cargo.lock" -ignore "MODULE.bazel.lock" \
  -ignore "**/gazelle_python.yaml" -ignore "**/*-baseline.xml" -ignore "**/.release-please-manifest.json" \
  -ignore "bazel-*/**" -ignore "**/node_modules/**" -ignore "**/*.venv/**" -ignore ".git/**" \
  . > /tmp/lic-before.txt 2>&1; echo "missing: $(wc -l < /tmp/lic-before.txt)"
```
Expected: a non-zero count (~80–90). Sanity-check `/tmp/lic-before.txt` contains **no** `BUILD`, lockfiles, or `*-baseline.xml` (proves the ignores work).

- [ ] **Step 3: Add the headers (same flags, drop `-check`)**

```bash
"$(go env GOPATH)/bin/addlicense" -c "VitruvianSoftware" -l mit \
  -ignore "**/BUILD" -ignore "**/BUILD.bazel" \
  -ignore "**/docs/**" -ignore "**/internal/scaffold/templates/**" \
  -ignore "pnpm-lock.yaml" -ignore "**/package-lock.json" -ignore "**/Cargo.lock" -ignore "MODULE.bazel.lock" \
  -ignore "**/gazelle_python.yaml" -ignore "**/*-baseline.xml" -ignore "**/.release-please-manifest.json" \
  -ignore "bazel-*/**" -ignore "**/node_modules/**" -ignore "**/*.venv/**" -ignore ".git/**" \
  .
```

- [ ] **Step 4: Verify the check now passes + nothing generated was touched**

```bash
"$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
  -ignore "**/BUILD" -ignore "**/BUILD.bazel" -ignore "**/docs/**" -ignore "**/internal/scaffold/templates/**" \
  -ignore "pnpm-lock.yaml" -ignore "**/package-lock.json" -ignore "**/Cargo.lock" -ignore "MODULE.bazel.lock" \
  -ignore "**/gazelle_python.yaml" -ignore "**/*-baseline.xml" -ignore "**/.release-please-manifest.json" \
  -ignore "bazel-*/**" -ignore "**/node_modules/**" -ignore "**/*.venv/**" -ignore ".git/**" \
  . && echo "CHECK PASS"
git status --porcelain | grep -E '/BUILD$|lock|-baseline\.xml|\.venv' && echo "!! generated file touched — STOP" || echo "no generated files modified"
```
Expected: `CHECK PASS` and `no generated files modified`. Also confirm `bazel run //:gazelle` is still a no-op: `bazel run //:gazelle && git status --porcelain | grep -E '/BUILD$' && echo "BUILD churn!" || echo "gazelle clean"`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(license): add MIT headers across the monorepo (addlicense)"
```

- [ ] **Step 6: Push + watch the fan-out (headers propagate to standalones)**

```bash
git push origin main
# headers under homelab/**, nexus-agent/**, mcp-slack/** trigger their exports:
for c in homelab nexus-agent mcp-slack; do
  gh run watch "$(gh run list --workflow copybara-export-$c.yaml --event push --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
done
gh workflow run copybara-drift-check.yaml; sleep 8
gh run watch "$(gh run list --workflow copybara-drift-check.yaml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: each export green; drift-check reports all 4 components in sync. (devx has no change → no export-devx.) The standalones now carry headers; their CIs run **without** a license check yet (added in Tasks 3–4), so they pass on the header-only change.

---

### Task 2: Widen the monorepo `license-check` job to the whole repo

**Files:** Modify `.github/workflows/ci.yaml` (the `license-check` job added earlier, currently devx-only).

- [ ] **Step 1: Replace the job's check step** so it runs from the repo root over the whole repo with `MONO_IGNORES` and pins the tool. Replace the existing `license-check` job body with:

```yaml
  license-check:
    # Whole-repo MIT license-header check (addlicense). Generated/tool-managed
    # files are ignored (BUILD = gazelle, lockfiles, baselines) so the tool never
    # fights their regeneration. Catches a missing header on the PR, before fan-out.
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: Install addlicense
        run: go install github.com/google/addlicense@v1.2.0
      - name: Check license headers (whole repo)
        run: |
          # go install drops the binary in GOPATH/bin, which isn't on PATH on the runner.
          "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
            -ignore "**/BUILD" -ignore "**/BUILD.bazel" \
            -ignore "**/docs/**" -ignore "**/internal/scaffold/templates/**" \
            -ignore "pnpm-lock.yaml" -ignore "**/package-lock.json" -ignore "**/Cargo.lock" -ignore "MODULE.bazel.lock" \
            -ignore "**/gazelle_python.yaml" -ignore "**/*-baseline.xml" -ignore "**/.release-please-manifest.json" \
            -ignore "bazel-*/**" -ignore "**/node_modules/**" -ignore "**/*.venv/**" -ignore ".git/**" \
            .
```

- [ ] **Step 2: Lint**

```bash
~/go/bin/actionlint .github/workflows/ci.yaml
```
Expected: exit 0.

- [ ] **Step 3: Commit + push, watch the monorepo `license-check` job**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci(license): widen license-check to the whole monorepo"
git push origin main
id=$(gh run list --workflow CI --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
until [ "$(gh run view "$id" --json jobs --jq '[.jobs[]|select(.name=="license-check")][0].status')" = completed ]; do sleep 10; done
gh run view "$id" --json jobs --jq '.jobs[]|select(.name=="license-check")|.conclusion'
```
Expected: `success` (Task 1 headered everything the whole-repo check covers).

---

### Task 3: Per-standalone checks — devx re-pin + homelab/mcp-slack add a `license-check` job

**Files:** Modify `devx/.github/workflows/ci.yml`, `homelab/.github/workflows/ci.yml`, `mcp-slack/.github/workflows/ci.yml` (all synced — edits fan out).

- [ ] **Step 1: devx — pin the tool version**

In `devx/.github/workflows/ci.yml`, change the addlicense install from `go install github.com/google/addlicense@latest` to `go install github.com/google/addlicense@v1.2.0`. (The file already carries a header; leave it.)

- [ ] **Step 2: homelab — add a `license-check` job**

Read `homelab/.github/workflows/ci.yml`, then add this job (homelab has no special ignores; the file already got its header in Task 1):

```yaml
  license-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: go install github.com/google/addlicense@v1.2.0
      - name: Check license headers
        run: '"$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit .'
```

- [ ] **Step 3: mcp-slack — add a `license-check` job**

Read `mcp-slack/.github/workflows/ci.yml`, then add this job:

```yaml
  license-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: go install github.com/google/addlicense@v1.2.0
      - name: Check license headers
        run: |
          "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
            -ignore "package-lock.json" -ignore "node_modules/**" .
```

- [ ] **Step 4: Lint + local per-standalone dry-run (confirm each will pass on its standalone)**

```bash
~/go/bin/actionlint devx/.github/workflows/ci.yml homelab/.github/workflows/ci.yml mcp-slack/.github/workflows/ci.yml
# Dry-run each standalone's exact check against a fresh clone:
for c in homelab mcp-slack; do
  d=/tmp/lic-$c; rm -rf "$d"; git clone --quiet --depth 1 "https://github.com/VitruvianSoftware/$c.git" "$d"
  echo "=== $c ==="; ( cd "$d" && case "$c" in
    homelab) "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit . ;;
    mcp-slack) "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit -ignore "package-lock.json" -ignore "node_modules/**" . ;;
  esac && echo "$c PASS" || echo "$c FAIL — add the flagged generated files to that standalone's ignore set" )
done
```
Expected: each prints `PASS`. (Task 1's headers haven't fanned out to these clones *if run before Task 1's push completes* — run this AFTER Task 1 Step 6 so the clones already carry headers.) If a generated file is flagged, add it to that component's ignore set in the job + re-dry-run.

- [ ] **Step 5: Commit + push, watch fan-out + each standalone CI**

```bash
git add devx/.github/workflows/ci.yml homelab/.github/workflows/ci.yml mcp-slack/.github/workflows/ci.yml
git commit -m "ci(license): add per-standalone addlicense check (homelab, mcp-slack); pin devx tool"
git push origin main
for c in devx homelab mcp-slack; do
  gh run watch "$(gh run list --workflow copybara-export-$c.yaml --event push --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
done
# Then watch each STANDALONE's own CI (the new license-check) on the fanned-out commit:
for c in devx homelab mcp-slack; do
  echo "$c standalone CI: $(gh run list -R VitruvianSoftware/$c --branch main --limit 5 --json name,conclusion --jq '[.[]|select(.name=="CI")][0].conclusion')"
done
```
Expected: exports green; each standalone's CI (incl. the new `license-check`) green.

---

### Task 4: nexus-agent — create a standalone `license-check.yml`

**Files:** Create `nexus-agent/.github/workflows/license-check.yml` (nexus-agent has no `ci.yml`). Synced → fans out.

- [ ] **Step 1: Create the workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  license-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - run: go install github.com/google/addlicense@v1.2.0
      - name: Check license headers
        run: |
          "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
            -ignore "package-lock.json" -ignore "node_modules/**" -ignore ".release-please-manifest.json" .
```

- [ ] **Step 2: Header the new workflow file + lint**

```bash
"$(go env GOPATH)/bin/addlicense" -c "VitruvianSoftware" -l mit nexus-agent/.github/workflows/license-check.yml
~/go/bin/actionlint nexus-agent/.github/workflows/license-check.yml
```
Expected: header added; actionlint exit 0.

- [ ] **Step 3: Local dry-run against the nexus-agent standalone**

```bash
d=/tmp/lic-nexus; rm -rf "$d"; git clone --quiet --depth 1 "https://github.com/VitruvianSoftware/nexus-agent.git" "$d"
( cd "$d" && "$(go env GOPATH)/bin/addlicense" -check -c "VitruvianSoftware" -l mit \
    -ignore "package-lock.json" -ignore "node_modules/**" -ignore ".release-please-manifest.json" . \
    && echo "nexus PASS" || echo "nexus FAIL — add flagged generated files to the ignore set" )
```
Expected: `nexus PASS` (run after Task 1's headers have fanned out to nexus-agent).

- [ ] **Step 4: Commit + push, watch export + the new standalone CI**

```bash
git add nexus-agent/.github/workflows/license-check.yml
git commit -m "ci(license): add license-header check workflow to nexus-agent"
git push origin main
gh run watch "$(gh run list --workflow copybara-export-nexus-agent.yaml --event push --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
sleep 10
gh run list -R VitruvianSoftware/nexus-agent --branch main --limit 5 --json name,conclusion --jq '[.[]|select(.name=="CI")][0] | "nexus CI: \(.conclusion)"'
```
Expected: export green; the new nexus-agent `CI` (license-check) green.

---

### Task 5: Final validation

- [ ] **Step 1: Monorepo CI green** (the whole-repo `license-check` + build/test) on `main` HEAD.

```bash
id=$(gh run list --workflow CI --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$id" --json jobs --jq '.jobs[]|"\(.name): \(.conclusion // .status)"'
```
Expected: `license-check: success` (plus build-test/build-macos).

- [ ] **Step 2: Drift green across all 4 components.**

```bash
gh workflow run copybara-drift-check.yaml; sleep 8
gh run watch "$(gh run list --workflow copybara-drift-check.yaml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: all seeded components in sync.

- [ ] **Step 3: All four standalone CIs green** (each now enforces headers).

```bash
for c in devx homelab mcp-slack nexus-agent; do
  echo "$c: $(gh run list -R VitruvianSoftware/$c --branch main --limit 5 --json name,conclusion --jq '[.[]|select(.name=="CI")][0].conclusion // "no-CI"')"
done
```
Expected: `success` for all four.

- [ ] **Step 4: Update runbook §11/§9** — note that all four components now enforce license headers (monorepo whole-repo check + per-standalone checks), and the canonical ignore list. Commit + push.

---

## Notes on iteration

The only real risk is **headering a generated file** (it gets regenerated headerless → the check fails next run). The ignore list guards the known ones (BUILD, lockfiles, baselines, manifests); Task 1 Step 4 and the per-standalone dry-runs (Tasks 3–4) are the gates — if any check flags a generated file, **add it to the ignore set**, don't header it. Header changes are otherwise low-risk (comment-only) and fan out like any other content change. Sequencing is load-bearing: **headers must land + fan out (Task 1) before the checks are enabled (Tasks 2–4)**, or a standalone CI will go red on its first run.
