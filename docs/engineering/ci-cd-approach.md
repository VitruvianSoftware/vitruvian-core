# CI/CD Approach and Tooling

This document outlines the philosophy, tools, and scripts that power our CI/CD pipelines in the `vitruvian-core` monorepo.

## 1. Philosophy: Smart CI with Safety Nets

In a large monorepo, running `bazel test //...` and deploying every application on every single commit is slow and expensive. We use **Smart CI**—graph-based analysis to determine the exact subset of targets affected by a code change.

However, graph analysis introduces risk: if the tool fails or misinterprets a change, it could silently skip a critical test or deployment. To prevent this, our pipeline enforces strict **Safety Invariants**:
*   **Fail-Open Deployments**: If our CI tooling fails to determine what changed, we assume *everything* changed and deploy the application. A redundant deploy is an idempotent blue-green no-op; a silently skipped deploy is a production incident.
*   **Fail-Closed Testing**: If CI tooling fails to determine what tests to run, we fall back to a full `bazel test //...` sweep.
*   **Global-Impact Guards**: Any change to fundamental build configurations (like `MODULE.bazel`, `.bazelrc`, or `tools/`) bypasses graph analysis and forces a full test sweep and deployment.
*   **Nightly Full Sweep**: A scheduled job runs `bazel test //...` every night. This acts as a backstop, ensuring that any edge-case miss by our Smart CI tooling is caught within 24 hours.

## 2. Tooling: `target-determinator` vs. `bazel-diff`

To calculate affected targets, we use **[`target-determinator`](https://github.com/bazel-contrib/target-determinator)** (maintained by Bazel Contrib). 

### Why `target-determinator`?
*   It uses Bazel's `cquery` (configured query), meaning it accurately understands our build flags and `select()` statements when determining what changed.
*   It maintains a local cache of the graph to speed up subsequent runs.

### What about `bazel-diff`?
`bazel-diff` (originally by Tinder) is another industry-standard tool. It uses Bazel's standard `query` (which is less configuration-aware but often faster and avoids command-line limits). While `bazel-diff` is an excellent tool for massive scale, we use `target-determinator` because its `cquery` approach is more accurate for our configured builds, and our wrapper scripts mitigate its fragility (such as crashing on broken commits) via our fail-open safety nets.

## 3. The Core Scripts

Our CI/CD pipelines do not invoke `target-determinator` directly. Instead, they call custom Bash scripts that enforce our safety invariants and global-impact guards. These scripts live in `tools/ci/`:

### `affected-targets.sh`
*   **Purpose:** Determines which tests to run on PRs (`pull_request`) and merge queues (`merge_group`).
*   **How it works:**
    1. Computes the merge-base of the PR.
    2. Checks if any "global-impact" files (e.g., `MODULE.bazel`) changed. If so, it falls back to a full `//...` sweep.
    3. Runs `target-determinator` to get the exact list of affected targets.
    4. If `target-determinator` errors, it logs a degraded warning and falls back to a full `//...` sweep.
    5. Builds the affected targets and tests them using `--build_tests_only`.

### `deploy-affected.sh`
*   **Purpose:** Determines whether to deploy an application (e.g., Tabula) when a commit lands on `main`.
*   **How it works:**
    1. Takes a list of the application's deployable artifacts (e.g., `//tabula/api:image_push`) via the `DEPLOY_TARGETS` environment variable.
    2. Checks if any non-graph files (like the Pulumi program or the workflow file itself) changed. If so, returns `affected=true`.
    3. Checks the global-impact guard. If triggered, returns `affected=true`.
    4. Runs `target-determinator` over *only* the `DEPLOY_TARGETS` universe. 
    5. If `target-determinator` errors, it logs a degraded warning and returns `affected=true` (Fail-Open).
    6. If the deploy targets are in the affected list, the application deploys.

### `td-lib.sh`
*   **Purpose:** A shared utility script that pins the exact version and checksum of `target-determinator` and handles downloading it for both `affected-targets.sh` and `deploy-affected.sh`. This ensures version consistency across all CI lanes.

## 4. CI/CD Terminology

For a quick reference of terms like *Presubmit*, *RBE*, *Blue-green deploy*, and *Quarantine lanes*, see our [CI Definitions](../.github/CI_DEFINITIONS.md) document.
