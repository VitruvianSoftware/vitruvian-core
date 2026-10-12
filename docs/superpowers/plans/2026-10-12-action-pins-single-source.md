# GitHub Action Pins Single Source of Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `.github/actions/pins/action.yml` as the single source of truth for third-party GitHub Action pins, eliminate duplicated hardcoded constants across workflow generators, and ensure Dependabot bumps both the pin manifest and generated workflows in parity.

**Architecture:** A composite action `.github/actions/pins/action.yml` lists all action pins. A shared Go package `tools/ci/actionpins` parses the manifest via Bazel runfiles. Both `tools/delivery/gen` and `tools/pipeline/gen` query this package to render workflows. A conformance test guards against unpinned or hardcoded actions.

**Tech Stack:** Go, Bazel (bzlmod/rules_go), GitHub Actions, Shell

## Global Constraints

- Never commit secrets or hardcoded GCP IDs.
- Follow the One Version Rule: one canonical pin per third-party action.
- All generators must produce byte-identical output to current `main` when using existing pins.
- No flaky tests or non-hermetic dependencies.

---

### Task 1: Create Pin Manifest and Bazel Target

**Files:**
- Create: `.github/actions/pins/action.yml`
- Modify: `BUILD`

**Interfaces:**
- Produces: `//:pins_manifest` filegroup containing `.github/actions/pins/action.yml`

- [ ] **Step 1: Create `.github/actions/pins/action.yml`**
Write the composite action containing all third-party actions used across `delivery-*.yaml` and `presubmit.yaml`:
```yaml
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

name: "Action Pins"
description: "Single source of truth for third-party GitHub Action pins used across workflow generators."
runs:
  using: "composite"
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
    - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
    - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
    - uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
    - uses: google-github-actions/setup-gcloud@aa5489c8933f4cc7a4f7d45035b3b1440c9c10db # v3.0.1
    - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1
    - uses: azure/setup-helm@9bc31f4ebc9c6b171d7bfbaa5d006ae7abdb4310 # v5.0.1
    - uses: astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0
    - uses: pulumi/actions@8e5e406f4007fca908480587cb9893c07090f58d # v7.0.0
```

- [ ] **Step 2: Export target in root `BUILD`**
Add `pins_manifest` filegroup to root `BUILD`:
```python
filegroup(
    name = "pins_manifest",
    srcs = [".github/actions/pins/action.yml"],
    visibility = ["//visibility:public"],
)
```

- [ ] **Step 3: Verify target build**
Run: `bazel build //:pins_manifest`
Expected: SUCCESS

- [ ] **Step 4: Commit**
```bash
git add .github/actions/pins/action.yml BUILD
git commit -m "feat(ci): add single source of truth action pins manifest"
```

---

### Task 2: Implement `tools/ci/actionpins` Package

**Files:**
- Create: `tools/ci/actionpins/BUILD`
- Create: `tools/ci/actionpins/actionpins.go`
- Create: `tools/ci/actionpins/actionpins_test.go`

**Interfaces:**
- Produces:
  ```go
  type Pins struct { ... }
  func Load(path string) (*Pins, error)
  func MustLoadDefault() *Pins
  func (p *Pins) Resolve(action string) string
  func (p *Pins) All() map[string]string
  ```

- [ ] **Step 1: Write failing test in `tools/ci/actionpins/actionpins_test.go`**
Test parsing sample manifest lines, extracting action prefixes, SHAs, version comments, and verifying `Resolve()` behavior and panic/error on unknown action.

- [ ] **Step 2: Run test to verify failure**
Run: `bazel test //tools/ci/actionpins:actionpins_test`
Expected: FAIL

- [ ] **Step 3: Implement `tools/ci/actionpins/actionpins.go`**
Implement YAML parsing with line-by-line regex or yaml parser, runfiles lookup via `rules_go/go/runfiles`, and fast map lookup.

- [ ] **Step 4: Run test to verify it passes**
Run: `bazel test //tools/ci/actionpins:actionpins_test`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add tools/ci/actionpins/
git commit -m "feat(tools/ci): add actionpins parser package"
```

---

### Task 3: Refactor `tools/delivery/gen` to Consume Action Pins

**Files:**
- Modify: `tools/delivery/gen/BUILD`
- Modify: `tools/delivery/gen/main.go`
- Modify: `tools/delivery/gen/main_test.go`

**Interfaces:**
- Consumes: `actionpins.MustLoadDefault()` or `actionpins.Load()`
- Produces: Identical rendered delivery workflows without hardcoded constants

- [ ] **Step 1: Update `tools/delivery/gen/BUILD`**
Add `//tools/ci/actionpins` to `deps` and `//:pins_manifest` to `data`.

- [ ] **Step 2: Replace hardcoded constants in `tools/delivery/gen/main.go`**
Replace `checkoutPin`, `uploadArtifactPin`, `setupGcloudPin`, `setupBuildxPin`, `setupHelmPin`, `setupUvPin`, `cachePin`, `pulumiActionsPin` with calls to `pins.Resolve(...)`.

- [ ] **Step 3: Run delivery tests & verify zero diff**
Run: `bazel test //tools/delivery/gen:...`
Run: `bazel run //tools/ci:gen && git diff --exit-code -- .github/workflows/delivery-*.yaml`
Expected: PASS with 0 diff

- [ ] **Step 4: Commit**
```bash
git add tools/delivery/gen/
git commit -m "refactor(delivery/gen): consume action pins from manifest"
```

---

### Task 4: Refactor `tools/pipeline/gen` to Consume Action Pins

**Files:**
- Modify: `tools/pipeline/gen/BUILD`
- Modify: `tools/pipeline/gen/render.go`

**Interfaces:**
- Consumes: `actionpins.MustLoadDefault()` or `actionpins.Load()`
- Produces: Identical rendered `presubmit.yaml` without hardcoded `WriteString` pins

- [ ] **Step 1: Update `tools/pipeline/gen/BUILD`**
Add `//tools/ci/actionpins` to `deps` and `//:pins_manifest` to `data`.

- [ ] **Step 2: Update `tools/pipeline/gen/render.go`**
Replace hardcoded strings for `actions/checkout`, `actions/setup-go`, `actions/cache/save`, and `actions/upload-artifact` with `pins.Resolve(...)`.

- [ ] **Step 3: Run pipeline tests & verify zero diff**
Run: `bazel test //tools/pipeline/...`
Run: `bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml && git diff --exit-code -- .github/workflows/presubmit.yaml`
Expected: PASS with 0 diff

- [ ] **Step 4: Commit**
```bash
git add tools/pipeline/
git commit -m "refactor(pipeline/gen): consume action pins from manifest"
```

---

### Task 5: Add Conformance Guard Test

**Files:**
- Create: `tools/conformance/actionpins_conformance_test.go` (or add to `tools/conformance/BUILD`)

**Interfaces:**
- Asserts: All `uses:` lines in generated `.github/workflows/` match an entry in `.github/actions/pins/action.yml`.

- [ ] **Step 1: Write conformance test**
Ensure any unmanifested third-party action in generated workflows triggers a test failure.

- [ ] **Step 2: Run conformance tests**
Run: `bazel test //tools/conformance/...`
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add tools/conformance/
git commit -m "test(conformance): add action pins conformance guard"
```

---

### Task 6: End-to-End Verification & Claude Opus Review

- [ ] **Step 1: Run comprehensive tests across touched packages**
Run: `bazel test //tools/ci/actionpins/... //tools/delivery/... //tools/pipeline/... //tools/conformance/...`
Expected: All tests pass.

- [ ] **Step 2: Test simulated bump**
Temporarily change an action pin in `.github/actions/pins/action.yml`, run `//tools/ci:gen` and `//tools/pipeline:gen`, verify generated files update accordingly, then revert.

- [ ] **Step 3: Request Claude Opus Review**
Dispatch to Claude Opus (`beacon` subagent or Claude Code CLI) for architectural review of the completed changes.
