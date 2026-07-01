# CI/CD Terminology Reference

> Quick-reference for CI/CD terms used in vitruvian-core workflows and documentation.

## Pipeline Phases

| Term | When It Runs | Purpose | vitruvian-core Equivalent |
|------|-------------|---------|--------------------------|
| **Presubmit** | Before merge — on `pull_request` and `merge_group` events | Catch breakage _before_ it lands on `main` | `ci.yaml` jobs gated on `pull_request` / `merge_group` |
| **Postsubmit** | After merge — on `push` to `main` | Verify the actual merged commit is clean (the **safety floor**) | `ci.yaml` jobs gated on `push` to `main` |
| **Periodic** | On a cron schedule (e.g., nightly, weekly) | Catch flaky tests, dependency rot, configuration drift | Copybara drift check (every 30 min); weekly full `//...` sweep (planned) |

## CI Concepts

| Term | Definition |
|------|-----------|
| **Affected targets** | The subset of Bazel targets whose build or test behavior could change given a code diff. Computed by `target-determinator` using Bazel's dependency graph. See [affected-targets.sh](/tools/ci/affected-targets.sh). |
| **Global-impact guard** | A check in `affected-targets.sh` that detects changes to files affecting _every_ target (e.g., `MODULE.bazel`, `.bazelrc`, `tools/`). When triggered, the affected-target optimization is bypassed and a full `//...` sweep runs instead. |
| **Safety floor** | The guarantee that no code path is ever _less_ tested than a full `//...` build+test. Every optimization (affected-targets, path-filtering, docs-only skip) fails safe to the full sweep. The postsubmit full sweep is the ultimate safety floor. |
| **Full sweep (`//...`)** | `bazel build //... && bazel test //...` — builds and tests every target in the repository. Expensive but comprehensive. |
| **Path filtering** | Skipping CI work when the diff only touches files that cannot affect the build (e.g., `docs/`, `*.md`, `gitops/`). See [relevant-paths.sh](/tools/ci/relevant-paths.sh). |
| **Merge queue** | GitHub's mechanism that serializes PR merges. Each queued PR is tested on top of the latest `main` + all PRs ahead of it in the queue, preventing "merge skew" where two individually-green PRs break when combined. |
| **Required status check** | A CI job that _must_ pass before a PR can merge. Configured in branch protection rules (managed as IaC in `infrastructure/pulumi/repo_config/`). |
| **Remote Build Execution (RBE)** | Offloading build and test actions to remote workers (BuildBuddy). Faster than local execution because actions run in parallel on a cluster. Enabled via `--config=remote` in `.bazelrc`. |
| **Remote cache** | Sharing build artifacts across CI runs and developers. A cache hit skips re-execution. Enabled via `--config=remotecache` in `.bazelrc`. |

## Deployment Concepts

| Term | Definition |
|------|-----------|
| **Blue-green deploy** | Deploy a new revision at 0% traffic behind a `candidate` tag, smoke-test it, then shift 100% traffic. If the smoke fails, the live revision keeps serving — nothing to roll back. |
| **Workload Identity Federation (WIF)** | Keyless authentication from GitHub Actions to GCP. GitHub's OIDC token is exchanged for a GCP access token via a Workload Identity Pool — no service account keys to manage or rotate. |
| **Environment (GitHub)** | A named deployment target (`tabula-development`, `tabula-production`) with its own variables, secrets, and protection rules. Used to decouple deploy workflows from hardcoded project IDs. |
| **Promotion** | Moving a verified build from one environment to the next (development → nonproduction → production). Gated by environment protection rules (e.g., required reviewer for production). |

## Build Concepts

| Term | Definition |
|------|-----------|
| **Bzlmod** | Bazel's modern module system (replaces WORKSPACE). External dependencies declared in `MODULE.bazel` with version resolution. |
| **Gazelle** | Automatic `BUILD` file generator. Reads source files and generates Bazel build targets. Run via `bazel run //:gazelle`. |
| **Hermetic build** | A build that depends only on declared inputs, not the host system. Bazel's toolchains (Go, Node, Python, etc.) are downloaded and managed by Bazel, not the developer's machine. |
| **`rules_oci`** | Bazel rules for building OCI container images without Docker. Produces deterministic, layer-optimized images. |
