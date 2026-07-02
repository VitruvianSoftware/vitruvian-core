# CI/CD Terminology Reference

> Quick-reference for CI/CD terms used in vitruvian-core workflows and documentation.

## Pipeline Phases

| Term | When It Runs | Purpose | vitruvian-core Equivalent |
|------|-------------|---------|--------------------------|
| **Presubmit** | Before merge — on `pull_request` and `merge_group` events | Catch breakage _before_ it lands on `main` | `ci.yaml` jobs gated on `pull_request` / `merge_group` — **affected targets** on both |
| **Postsubmit** | After merge — on `push` to `main` | Verify the actual merged commit is clean | `ci.yaml` jobs gated on `push` to `main` — **affected targets** (queue-merged commits were just tested as `merge_group`) |
| **Periodic** | On a cron schedule | Catch what per-change selection can't: under-attributed diffs, flaky tests, drift | **Nightly full `//...` sweep** (`periodic-full-sweep.yaml`, 06:00 UTC — the whole-graph backstop; files a P0 issue on red); **nightly quarantine lane** (`tabula-e2e.yaml` schedule, 06:30 UTC); Copybara drift check (every 30 min) |

## CI Concepts

| Term | Definition |
|------|-----------|
| **Affected targets** | The subset of Bazel targets whose build or test behavior could change given a code diff. Computed by `target-determinator` using Bazel's dependency graph. See [affected-targets.sh](/tools/ci/affected-targets.sh). |
| **Global-impact guard** | A check in `affected-targets.sh` that detects changes to files affecting _every_ target (e.g., `MODULE.bazel`, `.bazelrc`, `tools/`). When triggered, the affected-target optimization is bypassed and a full `//...` sweep runs instead. |
| **Safety floor** | The guarantee that no code path is ever _less_ tested than a full `//...` build+test. Every optimization (affected-targets, path-filtering, docs-only skip) fails safe to the full sweep _within its run_, and the **nightly full sweep** is the whole-graph backstop that bounds any affected-selection miss to <24h. `//tools/conformance:check` enforces the pairing: the affected-scoped lanes may exist only while the scheduled sweep does. |
| **Deploy gate (fail-open)** | The push-to-main decision in [deploy-affected.sh](/tools/ci/deploy-affected.sh): deploy iff the app's deployable targets are graph-affected or a non-graph input (Pulumi program, workflow file) changed. The mirror image of CI selection's fail-_closed_ sweep: any uncertainty **deploys** (idempotent blue-green), because a silently skipped deploy is the failure mode being fixed. |
| **Quarantine lane** | The nightly run of `@quarantine`-tagged e2e specs (`//tabula/extension:e2e_quarantine`) — excluded from blocking lanes so one flake can't fail a merge batch, still exercised nightly for the un-quarantine evidence. See [flaky-tests.md](/docs/engineering/flaky-tests.md). |
| **Culprit finder** | Mechanical bisection of a red nightly sweep ([culprit-finder.yaml](/.github/workflows/culprit-finder.yaml)): `git bisect run` driving `bazel test` on the failing targets over the last-green..red range; posts the first bad commit onto the breakage issue. |
| **Pipeline gates** | The repo-level Actions variables (`REPO_CONFIG_AUTO_APPLY`, `SYNC_AUTH_AUTO_APPLY`, `PULUMI_PREVIEW_ENABLED`, ...) that switch IaC workflows between advisory and applying. Pulumi-managed in `repo_config` (`pipelineGates`) — never hand-set. |
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
