# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# The orchestrator's hermetic tests drive the REAL decision engine (spec §4.2:
# deploy-affected.sh is shelled, never rewritten), so the scripts must be
# visible as runfiles to //tools/delivery/orchestrate:orchestrate_test.
load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# `bazel run //tools/ci:gen` — regenerate the generated delivery workflows
# (.github/workflows/delivery-<app>.yaml, one per app). Alias kept at the
# spec's name; the implementation lives in //tools/delivery/gen.
alias(
    name = "gen",
    actual = "//tools/delivery/gen",
    visibility = ["//visibility:public"],
)

exports_files([
    "actionlint.sh",
    "actionlint_test.sh",
    "affected-targets.sh",
    "affected-targets_test.sh",
    "agent-fast-lane.sh",
    "agent-fast-lane_test.sh",
    "backstage-boot-smoke.sh",
    "bisect-culprit.sh",
    "bisect-culprit_test.sh",
    "block-queue-bypass_test.sh",
    "changelog-summary.sh",
    "changelog-summary_test.sh",
    "chart-render.sh",
    "delivery-drift.sh",
    "delivery-drift_test.sh",
    "dependabot-lock-rebase.sh",
    "dependabot-lock-rebase_test.sh",
    "deploy-affected.sh",
    "deploy-affected_test.sh",
    "ensure-site-verification.sh",
    "ensure-site-verification_test.sh",
    "fast-lane-report.sh",
    "foundation-app-digest-guard.sh",
    "foundation-app-digest-guard_test.sh",
    "gate-evaluator.sh",
    "gate-evaluator_test.sh",
    "gcp-secret-or-fail.sh",
    "gcp-secret-or-fail_test.sh",
    "gitops-validate.sh",
    "gitops-values-render.sh",
    "go-test-with-retry.sh",
    "go-test-with-retry_test.sh",
    "image-sbom-scan.sh",
    "install-pinned-tool.sh",
    "install-pinned-tool_test.sh",
    "kube-setup_test.sh",
    "llvm-cache-key.sh",
    "llvm-cache-key_test.sh",
    "llvm-cache-stage.sh",
    "llvm-cache-stage_test.sh",
    "migration-safety.sh",
    "notify-ci-issues.sh",
    "notify-ci-issues_test.sh",
    "preview-reaper.sh",
    "preview-reaper_test.sh",
    "prune-pr-caches.sh",
    "prune-pr-caches_test.sh",
    "pulumi-summary.sh",
    "pulumi-summary_test.sh",
    "queue-fast-pass.sh",
    "queue-fast-pass_test.sh",
    "queue-runner-routing.sh",
    "queue-runner-routing_test.sh",
    "queue-runner-watch.sh",
    "queue-runner-watch_test.sh",
    "rdeps-map-ref.sh",
    "rdeps-map-ref_test.sh",
    "release-beta-gate.sh",
    "release-beta-gate_test.sh",
    "release-hold.sh",
    "release-hold_test.sh",
    "release-pr-dequeue.sh",
    "release-pr-dequeue_test.sh",
    "relevant-paths.sh",
    "relevant-paths_test.sh",
    "require-dev-soak.sh",
    "require-dev-soak_test.sh",
    "require-pinned-actions.sh",
    "resolve-deploy-base.sh",
    "resolve-deploy-base_test.sh",
    "resolve-unit-bases.sh",
    "resolve-unit-bases_test.sh",
    "secret-scan.sh",
    "secret-scan_test.sh",
    "session-start_test.sh",
    "site-pr-automerge.sh",
    "site-pr-automerge_test.sh",
    "tabula-deploy-preflight.sh",
    "tabula-deploy-preflight_test.sh",
    "td-lib.sh",
    "transient-lib.sh",
    "workflow-git-push-credentials_test.sh",
])

# The extracted-LLVM cache key. Keyed on every recorded input of the
# llvm_toolchain_llvm repo rule -- /etc/os-release included -- so a runner-image
# point release is a one-run miss instead of a permanent restore-and-re-extract
# (#2242). Hermetic: fixtures only, no bazel-in-bazel, no network.
sh_test(
    name = "llvm_cache_key_test",
    size = "small",
    srcs = ["llvm-cache-key_test.sh"],
    args = ["$(location llvm-cache-key.sh)"],
    data = ["llvm-cache-key.sh"],
)

# Moves the extracted LLVM toolchain between the cache's fixed stage folder and
# Bazel's contents cache, so no file pins the content-hash folder name (#2456).
sh_test(
    name = "llvm_cache_stage_test",
    size = "small",
    srcs = ["llvm-cache-stage_test.sh"],
    args = ["$(location llvm-cache-stage.sh)"],
    data = ["llvm-cache-stage.sh"],
)

# Arms auto-merge on the website PRs catalog-publish and site-sync-downloads
# open, at the commit they pushed, and leaves a held PR alone. Fake gh only.
sh_test(
    name = "site_pr_automerge_test",
    size = "small",
    srcs = ["site-pr-automerge_test.sh"],
    args = ["$(location site-pr-automerge.sh)"],
    data = ["site-pr-automerge.sh"],
)

sh_test(
    name = "gate_evaluator_test",
    size = "small",
    srcs = ["gate-evaluator_test.sh"],
    args = ["$(location gate-evaluator.sh)"],
    data = ["gate-evaluator.sh"],
)

# The drift detector shells the SAME decision engine the orchestrator does, so
# the detector can never disagree with the decider about "affected". Its test
# therefore needs both scripts as runfiles and drives the real engine (only gh
# and bazel are stubbed).
# Safety tests for the cache pruner. It DELETES, so the suite is mostly
# negative: an open PR's cache, a branch cache, and an undeterminable PR state
# must all survive.
# Per-unit durable bases (#1842). Hermetic: stubs only `gh`, and drives the real
# script against a fixture workflow, so it needs no network and no credentials.
sh_test(
    name = "resolve_unit_bases_test",
    size = "small",
    srcs = ["resolve-unit-bases_test.sh"],
    args = ["$(location resolve-unit-bases.sh)"],
    data = ["resolve-unit-bases.sh"],
)

# A workflow may name the homelab runner only through one exact rule, so a pull
# request (a fork's, too) can never choose it. Scans every workflow.
sh_test(
    name = "queue_runner_routing_test",
    size = "small",
    srcs = ["queue-runner-routing_test.sh"],
    args = [
        "$(location queue-runner-routing.sh)",
        "$(rootpaths //:workflow_files)",
    ],
    data = [
        "queue-runner-routing.sh",
        "//:workflow_files",
    ],
)

sh_test(
    name = "queue_runner_watch_test",
    size = "small",
    srcs = ["queue-runner-watch_test.sh"],
    args = ["$(location queue-runner-watch.sh)"],
    data = ["queue-runner-watch.sh"],
)

sh_test(
    name = "prune_pr_caches_test",
    size = "small",
    srcs = ["prune-pr-caches_test.sh"],
    args = ["$(location prune-pr-caches.sh)"],
    data = ["prune-pr-caches.sh"],
)

sh_test(
    name = "delivery_drift_test",
    size = "small",
    srcs = ["delivery-drift_test.sh"],
    args = [
        "$(location delivery-drift.sh)",
        "$(location deploy-affected.sh)",
    ],
    data = [
        "delivery-drift.sh",
        "deploy-affected.sh",
        "td-lib.sh",
    ],
)

sh_test(
    name = "preview_reaper_test",
    size = "small",
    srcs = ["preview-reaper_test.sh"],
    args = ["$(location preview-reaper.sh)"],
    data = ["preview-reaper.sh"],
)

# Downloads a pinned CI tool (actionlint, kubeconform, osv-scanner, promtool)
# and verifies its checksum. Also guards the curl retry policy: a fixed
# --retry-delay turns off curl's backoff, and ~6s of GitHub-releases 500s then
# failed a required merge-queue check. Hermetic: fake curl, no network.
# Linux-only, like the script: it needs GNU sha256sum, which is not on the
# macOS Bazel sandbox PATH, so a Mac `bazel test //...` skips it.
sh_test(
    name = "install_pinned_tool_test",
    size = "small",
    srcs = ["install-pinned-tool_test.sh"],
    args = ["$(location install-pinned-tool.sh)"],
    data = ["install-pinned-tool.sh"],
    target_compatible_with = ["@platforms//os:linux"],
)

# The culprit-finder workflow bisects a red main to the commit that broke it.
# Guards the GOOD_SHA == BAD_SHA rejection (#1518) and that a real range still
# converges. Hermetic: throwaway git repos, no network, no bazel-in-bazel.
sh_test(
    name = "bisect_culprit_test",
    size = "small",
    srcs = ["bisect-culprit_test.sh"],
    args = ["$(location bisect-culprit.sh)"],
    data = ["bisect-culprit.sh"],
)

sh_test(
    name = "deploy_affected_test",
    size = "small",
    srcs = ["deploy-affected_test.sh"],
    args = ["$(location deploy-affected.sh)"],
    data = [
        "deploy-affected.sh",
        "td-lib.sh",
    ],
)

# The mirror's release workflow for the standalone Nexus Agent never runs here;
# nexus-agent-mirror-toolchain.yaml rehearses its build and packaging on pull
# requests. This fails when the steps the two share stop being the same, which
# nothing else would report: the rehearsal would stay green while proving
# nothing about the release. Reads both files as text; builds nothing.
py_test(
    name = "nexus_agent_release_rehearsal_test",
    size = "small",
    srcs = ["nexus_agent_release_rehearsal_test.py"],
    args = [
        "$(rootpath //apps/desktop/nexus-agent:release_workflow)",
        "$(rootpath //:.github/workflows/nexus-agent-mirror-toolchain.yaml)",
    ],
    data = [
        "//:.github/workflows/nexus-agent-mirror-toolchain.yaml",
        "//apps/desktop/nexus-agent:release_workflow",
    ],
    main = "nexus_agent_release_rehearsal_test.py",
)

# `bazel run //tools/ci:actionlint` -- the required `actionlint` check, locally:
# the pinned actionlint (tools/tools.lock.json, at the workflow's
# ACTIONLINT_VERSION) with shellcheck over the `run:` blocks, then the
# commit-SHA pin check the workflow runs from require-pinned-actions.sh.
# The Rust port in src/actionlint/ (actionlint.sh's steps, messages and exit
# codes, held to the script by :actionlint_rs_parity_test); --help is the
# script's own header, compiled in. The script stays runnable as
# :actionlint-sh.
rust_library(
    name = "actionlint_lib",
    srcs = ["src/actionlint/lib.rs"],
    compile_data = ["actionlint.sh"],
    crate_name = "actionlint",
    crate_root = "src/actionlint/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@rules_rust//rust/runfiles",
    ],
)

rust_binary(
    name = "actionlint",
    srcs = ["src/actionlint/main.rs"],
    data = [
        "require-pinned-actions.sh",
        "@multitool//tools/actionlint",
        "@multitool//tools/shellcheck",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":actionlint_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":actionlint",
        visibility = ["//visibility:public"],
    )
    for name in [
        "actionlint-rs",
        "actionlint_rs",
    ]
]

sh_binary(
    name = "actionlint-sh",
    srcs = ["actionlint.sh"],
    data = [
        "require-pinned-actions.sh",
        "@multitool//tools/actionlint",
        "@multitool//tools/shellcheck",
    ],
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# Throwaway repos and the real pinned binaries; also fails when the workflow's
# ACTIONLINT_VERSION and the lockfile drift apart.
sh_test(
    name = "actionlint_test",
    size = "small",
    srcs = ["actionlint_test.sh"],
    args = [
        "$(location actionlint.sh)",
        "$(location //:.github/workflows/actionlint.yaml)",
        "$(location //tools:tools.lock.json)",
    ],
    data = [
        "actionlint.sh",
        "require-pinned-actions.sh",
        "//:.github/workflows/actionlint.yaml",
        "//tools:tools.lock.json",
        "@multitool//tools/actionlint",
        "@multitool//tools/shellcheck",
    ],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# The same suite against the Rust binary (ACTIONLINT_UNDER_TEST).
sh_test(
    name = "actionlint-rs_test",
    size = "small",
    srcs = ["actionlint_test.sh"],
    args = [
        "$(location actionlint.sh)",
        "$(location //:.github/workflows/actionlint.yaml)",
        "$(location //tools:tools.lock.json)",
    ],
    data = [
        "actionlint.sh",
        "require-pinned-actions.sh",
        ":actionlint",
        "//:.github/workflows/actionlint.yaml",
        "//tools:tools.lock.json",
        "@multitool//tools/actionlint",
        "@multitool//tools/shellcheck",
    ],
    env = {"ACTIONLINT_UNDER_TEST": "$(rootpath :actionlint)"},
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# The #[cfg(test)] unit tests in src/actionlint/.
rust_test(
    name = "actionlint_lib_test",
    size = "small",
    crate = ":actionlint_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in actionlint_rs_parity_test.py
# (fake actionlint, shellcheck and pin check, plus a runfiles tree with the
# real runfiles.bash): exit code, stdout, stderr and every tool call, byte for
# byte, under every bash on the machine.
py_test(
    name = "actionlint_rs_parity_test",
    size = "medium",
    srcs = ["actionlint_rs_parity_test.py"],
    data = [
        "actionlint.sh",
        ":actionlint",
        "@bazel_tools//tools/bash/runfiles",
    ],
    env = {
        "ACTIONLINT_RS": "$(rootpath :actionlint)",
        "ACTIONLINT_SH": "$(rootpath actionlint.sh)",
    },
    main = "actionlint_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],  # keep
)

# ---------- Rust ports of CI / delivery helper scripts ----------

# gate-evaluator
rust_library(
    name = "gate_evaluator_lib",
    srcs = ["src/gate_evaluator/lib.rs"],
    crate_name = "gate_evaluator",
    crate_root = "src/gate_evaluator/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "gate_evaluator",
    srcs = ["src/gate_evaluator/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gate_evaluator_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":gate_evaluator",
    visibility = ["//visibility:public"],
) for n in [
    "gate-evaluator-rs",
    "gate_evaluator_rs",
]]

sh_binary(
    name = "gate-evaluator-sh",
    srcs = ["gate-evaluator.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "gate_evaluator_rs_test",
    size = "small",
    srcs = ["gate-evaluator_test.sh"],
    args = ["$(location :gate_evaluator)"],
    data = [
        "gate-evaluator.sh",
        ":gate_evaluator",
    ],
)

# llvm-cache-key
rust_library(
    name = "llvm_cache_key_lib",
    srcs = ["src/llvm_cache_key/lib.rs"],
    crate_name = "llvm_cache_key",
    crate_root = "src/llvm_cache_key/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "llvm_cache_key",
    srcs = ["src/llvm_cache_key/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":llvm_cache_key_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":llvm_cache_key",
    visibility = ["//visibility:public"],
) for n in [
    "llvm-cache-key-rs",
    "llvm_cache_key_rs",
]]

sh_binary(
    name = "llvm-cache-key-sh",
    srcs = ["llvm-cache-key.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "llvm_cache_key_rs_test",
    size = "small",
    srcs = ["llvm-cache-key_test.sh"],
    args = ["$(location :llvm_cache_key)"],
    data = [
        "llvm-cache-key.sh",
        ":llvm_cache_key",
    ],
)

# llvm-cache-stage
rust_library(
    name = "llvm_cache_stage_lib",
    srcs = ["src/llvm_cache_stage/lib.rs"],
    crate_name = "llvm_cache_stage",
    crate_root = "src/llvm_cache_stage/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "llvm_cache_stage",
    srcs = ["src/llvm_cache_stage/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":llvm_cache_stage_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":llvm_cache_stage",
    visibility = ["//visibility:public"],
) for n in [
    "llvm-cache-stage-rs",
    "llvm_cache_stage_rs",
]]

sh_binary(
    name = "llvm-cache-stage-sh",
    srcs = ["llvm-cache-stage.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "llvm_cache_stage_rs_test",
    size = "small",
    srcs = ["llvm-cache-stage_test.sh"],
    args = ["$(location :llvm_cache_stage)"],
    data = [
        "llvm-cache-stage.sh",
        ":llvm_cache_stage",
    ],
)

# queue-runner-routing
rust_library(
    name = "queue_runner_routing_lib",
    srcs = ["src/queue_runner_routing/lib.rs"],
    crate_name = "queue_runner_routing",
    crate_root = "src/queue_runner_routing/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "queue_runner_routing",
    srcs = ["src/queue_runner_routing/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":queue_runner_routing_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":queue_runner_routing",
    visibility = ["//visibility:public"],
) for n in [
    "queue-runner-routing-rs",
    "queue_runner_routing_rs",
]]

sh_binary(
    name = "queue-runner-routing-sh",
    srcs = ["queue-runner-routing.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "queue_runner_routing_rs_test",
    size = "small",
    srcs = ["queue-runner-routing_test.sh"],
    args = [
        "$(location :queue_runner_routing)",
        "$(rootpaths //:workflow_files)",
    ],
    data = [
        "queue-runner-routing.sh",
        ":queue_runner_routing",
        "//:workflow_files",
    ],
)

# queue-runner-watch
rust_library(
    name = "queue_runner_watch_lib",
    srcs = ["src/queue_runner_watch/lib.rs"],
    crate_name = "queue_runner_watch",
    crate_root = "src/queue_runner_watch/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "queue_runner_watch",
    srcs = ["src/queue_runner_watch/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":queue_runner_watch_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":queue_runner_watch",
    visibility = ["//visibility:public"],
) for n in [
    "queue-runner-watch-rs",
    "queue_runner_watch_rs",
]]

sh_binary(
    name = "queue-runner-watch-sh",
    srcs = ["queue-runner-watch.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "queue_runner_watch_rs_test",
    size = "small",
    srcs = ["queue-runner-watch_test.sh"],
    args = ["$(location :queue_runner_watch)"],
    data = [
        "queue-runner-watch.sh",
        ":queue_runner_watch",
    ],
)

# bisect-culprit
rust_library(
    name = "bisect_culprit_lib",
    srcs = ["src/bisect_culprit/lib.rs"],
    crate_name = "bisect_culprit",
    crate_root = "src/bisect_culprit/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "bisect_culprit",
    srcs = ["src/bisect_culprit/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":bisect_culprit_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":bisect_culprit",
    visibility = ["//visibility:public"],
) for n in [
    "bisect-culprit-rs",
    "bisect_culprit_rs",
]]

sh_binary(
    name = "bisect-culprit-sh",
    srcs = ["bisect-culprit.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "bisect_culprit_rs_test",
    size = "small",
    srcs = ["bisect-culprit_test.sh"],
    args = [
        "$(location :bisect_culprit)",
        "$(location bisect-culprit.sh)",
    ],
    data = [
        "bisect-culprit.sh",
        ":bisect_culprit",
    ],
)

# site-pr-automerge
rust_library(
    name = "site_pr_automerge_lib",
    srcs = ["src/site_pr_automerge/lib.rs"],
    crate_name = "site_pr_automerge",
    crate_root = "src/site_pr_automerge/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "site_pr_automerge",
    srcs = ["src/site_pr_automerge/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":site_pr_automerge_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":site_pr_automerge",
    visibility = ["//visibility:public"],
) for n in [
    "site-pr-automerge-rs",
    "site_pr_automerge_rs",
]]

sh_binary(
    name = "site-pr-automerge-sh",
    srcs = ["site-pr-automerge.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "site_pr_automerge_rs_test",
    size = "small",
    srcs = ["site-pr-automerge_test.sh"],
    args = ["$(location :site_pr_automerge)"],
    data = [
        "site-pr-automerge.sh",
        ":site_pr_automerge",
    ],
)

# deploy-affected
rust_library(
    name = "deploy_affected_lib",
    srcs = ["src/deploy_affected/lib.rs"],
    crate_name = "deploy_affected",
    crate_root = "src/deploy_affected/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "deploy_affected",
    srcs = ["src/deploy_affected/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":deploy_affected_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":deploy_affected",
    visibility = ["//visibility:public"],
) for n in [
    "deploy-affected-rs",
    "deploy_affected_rs",
]]

sh_binary(
    name = "deploy-affected-sh",
    srcs = ["deploy-affected.sh"],
    data = ["td-lib.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "deploy_affected_rs_test",
    size = "small",
    srcs = ["deploy-affected_test.sh"],
    args = ["$(location :deploy_affected)"],
    data = [
        "deploy-affected.sh",
        "td-lib.sh",
        ":deploy_affected",
    ],
)

# resolve-unit-bases
rust_library(
    name = "resolve_unit_bases_lib",
    srcs = ["src/resolve_unit_bases/lib.rs"],
    crate_name = "resolve_unit_bases",
    crate_root = "src/resolve_unit_bases/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "resolve_unit_bases",
    srcs = ["src/resolve_unit_bases/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":resolve_unit_bases_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":resolve_unit_bases",
    visibility = ["//visibility:public"],
) for n in [
    "resolve-unit-bases-rs",
    "resolve_unit_bases_rs",
]]

sh_binary(
    name = "resolve-unit-bases-sh",
    srcs = ["resolve-unit-bases.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "resolve_unit_bases_rs_test",
    size = "small",
    srcs = ["resolve-unit-bases_test.sh"],
    args = ["$(location :resolve_unit_bases)"],
    data = [
        "resolve-unit-bases.sh",
        ":resolve_unit_bases",
    ],
)

# prune-pr-caches
rust_library(
    name = "prune_pr_caches_lib",
    srcs = ["src/prune_pr_caches/lib.rs"],
    crate_name = "prune_pr_caches",
    crate_root = "src/prune_pr_caches/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "prune_pr_caches",
    srcs = ["src/prune_pr_caches/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":prune_pr_caches_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":prune_pr_caches",
    visibility = ["//visibility:public"],
) for n in [
    "prune-pr-caches-rs",
    "prune_pr_caches_rs",
]]

sh_binary(
    name = "prune-pr-caches-sh",
    srcs = ["prune-pr-caches.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "prune_pr_caches_rs_test",
    size = "small",
    srcs = ["prune-pr-caches_test.sh"],
    args = ["$(location :prune_pr_caches)"],
    data = [
        "prune-pr-caches.sh",
        ":prune_pr_caches",
    ],
)

# delivery-drift
rust_library(
    name = "delivery_drift_lib",
    srcs = ["src/delivery_drift/lib.rs"],
    crate_name = "delivery_drift",
    crate_root = "src/delivery_drift/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "delivery_drift",
    srcs = ["src/delivery_drift/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":delivery_drift_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":delivery_drift",
    visibility = ["//visibility:public"],
) for n in [
    "delivery-drift-rs",
    "delivery_drift_rs",
]]

sh_binary(
    name = "delivery-drift-sh",
    srcs = ["delivery-drift.sh"],
    data = [
        "deploy-affected.sh",
        "td-lib.sh",
    ],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "delivery_drift_rs_test",
    size = "small",
    srcs = ["delivery-drift_test.sh"],
    args = [
        "$(location :delivery_drift)",
        "$(location deploy-affected.sh)",
    ],
    data = [
        "delivery-drift.sh",
        "deploy-affected.sh",
        "td-lib.sh",
        ":delivery_drift",
    ],
)

# preview-reaper
rust_library(
    name = "preview_reaper_lib",
    srcs = ["src/preview_reaper/lib.rs"],
    crate_name = "preview_reaper",
    crate_root = "src/preview_reaper/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "preview_reaper",
    srcs = ["src/preview_reaper/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":preview_reaper_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":preview_reaper",
    visibility = ["//visibility:public"],
) for n in [
    "preview-reaper-rs",
    "preview_reaper_rs",
]]

sh_binary(
    name = "preview-reaper-sh",
    srcs = ["preview-reaper.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "preview_reaper_rs_test",
    size = "small",
    srcs = ["preview-reaper_test.sh"],
    args = ["$(location :preview_reaper)"],
    data = [
        "preview-reaper.sh",
        ":preview_reaper",
    ],
)

# transient-lib
rust_library(
    name = "transient_lib",
    srcs = ["src/transient_lib/lib.rs"],
    crate_name = "transient_lib",
    crate_root = "src/transient_lib/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_test(
    name = "transient_lib_test",
    size = "small",
    crate = ":transient_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# ensure-site-verification
rust_library(
    name = "ensure_site_verification_lib",
    srcs = ["src/ensure_site_verification/lib.rs"],
    crate_name = "ensure_site_verification",
    crate_root = "src/ensure_site_verification/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "ensure_site_verification",
    srcs = ["src/ensure_site_verification/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":ensure_site_verification_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":ensure_site_verification",
    visibility = ["//visibility:public"],
) for n in [
    "ensure-site-verification-rs",
    "ensure_site_verification_rs",
]]

sh_test(
    name = "ensure_site_verification_test",
    size = "small",
    srcs = ["ensure-site-verification_test.sh"],
    args = ["$(location ensure-site-verification.sh)"],
    data = [
        "ensure-site-verification.sh",
    ],
)

sh_test(
    name = "ensure_site_verification_rs_test",
    size = "small",
    srcs = ["ensure-site-verification_test.sh"],
    args = ["$(location :ensure_site_verification)"],
    data = [
        "ensure-site-verification.sh",
        ":ensure_site_verification",
    ],
)

# affected-targets
rust_library(
    name = "affected_targets_lib",
    srcs = ["src/affected_targets/lib.rs"],
    crate_name = "affected_targets",
    crate_root = "src/affected_targets/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "affected_targets",
    srcs = ["src/affected_targets/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":affected_targets_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":affected_targets",
    visibility = ["//visibility:public"],
) for n in [
    "affected-targets-rs",
    "affected_targets_rs",
]]

sh_test(
    name = "affected_targets_test",
    size = "small",
    srcs = ["affected-targets_test.sh"],
    args = ["$(location affected-targets.sh)"],
    data = [
        "affected-targets.sh",
    ],
)

sh_test(
    name = "affected_targets_rs_test",
    size = "small",
    srcs = ["affected-targets_test.sh"],
    args = ["$(location :affected_targets)"],
    data = [
        "affected-targets.sh",
        ":affected_targets",
    ],
)

# pulumi-summary
rust_library(
    name = "pulumi_summary_lib",
    srcs = ["src/pulumi_summary/lib.rs"],
    crate_name = "pulumi_summary",
    crate_root = "src/pulumi_summary/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "pulumi_summary",
    srcs = ["src/pulumi_summary/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":pulumi_summary_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":pulumi_summary",
    visibility = ["//visibility:public"],
) for n in [
    "pulumi-summary-rs",
    "pulumi_summary_rs",
]]

sh_test(
    name = "pulumi_summary_test",
    size = "small",
    srcs = ["pulumi-summary_test.sh"],
    args = ["$(location pulumi-summary.sh)"],
    data = [
        "pulumi-summary.sh",
    ] + glob(["testdata/pulumi/*.txt"]),
)

sh_test(
    name = "pulumi_summary_rs_test",
    size = "small",
    srcs = ["pulumi-summary_test.sh"],
    args = ["$(location :pulumi_summary)"],
    data = [
        "pulumi-summary.sh",
        ":pulumi_summary",
    ] + glob(["testdata/pulumi/*.txt"]),
)

# gitops-validate
rust_library(
    name = "gitops_validate_lib",
    srcs = ["src/gitops_validate/lib.rs"],
    crate_name = "gitops_validate",
    crate_root = "src/gitops_validate/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "gitops_validate",
    srcs = ["src/gitops_validate/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gitops_validate_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":gitops_validate",
    visibility = ["//visibility:public"],
) for n in [
    "gitops-validate-rs",
    "gitops_validate_rs",
]]

rust_test(
    name = "gitops_validate_lib_test",
    size = "small",
    crate = ":gitops_validate_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# release-beta-gate
rust_library(
    name = "release_beta_gate_lib",
    srcs = ["src/release_beta_gate/lib.rs"],
    crate_name = "release_beta_gate",
    crate_root = "src/release_beta_gate/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "release_beta_gate",
    srcs = ["src/release_beta_gate/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":release_beta_gate_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":release_beta_gate",
    visibility = ["//visibility:public"],
) for n in [
    "release-beta-gate-rs",
    "release_beta_gate_rs",
]]

sh_test(
    name = "release_beta_gate_test",
    size = "small",
    srcs = ["release-beta-gate_test.sh"],
    args = ["$(location release-beta-gate.sh)"],
    data = [
        "release-beta-gate.sh",
    ],
)

sh_test(
    name = "release_beta_gate_rs_test",
    size = "small",
    srcs = ["release-beta-gate_test.sh"],
    args = ["$(location :release_beta_gate)"],
    data = [
        "release-beta-gate.sh",
        ":release_beta_gate",
    ],
)

# gitops-values-render
rust_library(
    name = "gitops_values_render_lib",
    srcs = ["src/gitops_values_render/lib.rs"],
    crate_name = "gitops_values_render",
    crate_root = "src/gitops_values_render/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "gitops_values_render",
    srcs = ["src/gitops_values_render/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gitops_values_render_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":gitops_values_render",
    visibility = ["//visibility:public"],
) for n in [
    "gitops-values-render-rs",
    "gitops_values_render_rs",
]]

rust_test(
    name = "gitops_values_render_lib_test",
    size = "small",
    crate = ":gitops_values_render_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# image-sbom-scan
rust_library(
    name = "image_sbom_scan_lib",
    srcs = ["src/image_sbom_scan/lib.rs"],
    crate_name = "image_sbom_scan",
    crate_root = "src/image_sbom_scan/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "image_sbom_scan",
    srcs = ["src/image_sbom_scan/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":image_sbom_scan_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":image_sbom_scan",
    visibility = ["//visibility:public"],
) for n in [
    "image-sbom-scan-rs",
    "image_sbom_scan_rs",
]]

rust_test(
    name = "image_sbom_scan_lib_test",
    size = "small",
    crate = ":image_sbom_scan_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# chart-render
rust_library(
    name = "chart_render_lib",
    srcs = ["src/chart_render/lib.rs"],
    crate_name = "chart_render",
    crate_root = "src/chart_render/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "chart_render",
    srcs = ["src/chart_render/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":chart_render_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":chart_render",
    visibility = ["//visibility:public"],
) for n in [
    "chart-render-rs",
    "chart_render_rs",
]]

rust_test(
    name = "chart_render_lib_test",
    size = "small",
    crate = ":chart_render_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# require-dev-soak
rust_library(
    name = "require_dev_soak_lib",
    srcs = ["src/require_dev_soak/lib.rs"],
    crate_name = "require_dev_soak",
    crate_root = "src/require_dev_soak/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "require_dev_soak",
    srcs = ["src/require_dev_soak/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":require_dev_soak_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":require_dev_soak",
    visibility = ["//visibility:public"],
) for n in [
    "require-dev-soak-rs",
    "require_dev_soak_rs",
]]

sh_test(
    name = "require_dev_soak_test",
    size = "small",
    srcs = ["require-dev-soak_test.sh"],
    args = ["$(location require-dev-soak.sh)"],
    data = [
        "require-dev-soak.sh",
    ],
)

sh_test(
    name = "require_dev_soak_rs_test",
    size = "small",
    srcs = ["require-dev-soak_test.sh"],
    args = ["$(location :require_dev_soak)"],
    data = [
        "require-dev-soak.sh",
        ":require_dev_soak",
    ],
)

# backstage-boot-smoke
rust_library(
    name = "backstage_boot_smoke_lib",
    srcs = ["src/backstage_boot_smoke/lib.rs"],
    crate_name = "backstage_boot_smoke",
    crate_root = "src/backstage_boot_smoke/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "backstage_boot_smoke",
    srcs = ["src/backstage_boot_smoke/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":backstage_boot_smoke_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":backstage_boot_smoke",
    visibility = ["//visibility:public"],
) for n in [
    "backstage-boot-smoke-rs",
    "backstage_boot_smoke_rs",
]]

rust_test(
    name = "backstage_boot_smoke_lib_test",
    size = "small",
    crate = ":backstage_boot_smoke_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# notify-ci-issues
rust_library(
    name = "notify_ci_issues_lib",
    srcs = ["src/notify_ci_issues/lib.rs"],
    crate_name = "notify_ci_issues",
    crate_root = "src/notify_ci_issues/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "notify_ci_issues",
    srcs = ["src/notify_ci_issues/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":notify_ci_issues_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":notify_ci_issues",
    visibility = ["//visibility:public"],
) for n in [
    "notify-ci-issues-rs",
    "notify_ci_issues_rs",
]]

rust_test(
    name = "notify_ci_issues_lib_test",
    size = "small",
    crate = ":notify_ci_issues_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "notify_ci_issues_test",
    size = "small",
    srcs = ["notify-ci-issues_test.sh"],
    args = ["$(location notify-ci-issues.sh)"],
    data = [
        "notify-ci-issues.sh",
    ],
)

sh_test(
    name = "notify_ci_issues_rs_test",
    size = "small",
    srcs = ["notify-ci-issues_test.sh"],
    args = ["$(location :notify_ci_issues)"],
    data = [
        "notify-ci-issues.sh",
        ":notify_ci_issues",
    ],
)

# queue-fast-pass
rust_library(
    name = "queue_fast_pass_lib",
    srcs = ["src/queue_fast_pass/lib.rs"],
    crate_name = "queue_fast_pass",
    crate_root = "src/queue_fast_pass/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "queue_fast_pass",
    srcs = ["src/queue_fast_pass/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":queue_fast_pass_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":queue_fast_pass",
    visibility = ["//visibility:public"],
) for n in [
    "queue-fast-pass-rs",
    "queue_fast_pass_rs",
]]

sh_test(
    name = "queue_fast_pass_test",
    size = "small",
    srcs = ["queue-fast-pass_test.sh"],
    args = ["$(location queue-fast-pass.sh)"],
    data = [
        "queue-fast-pass.sh",
        "//:workflow_files",
    ],
)

sh_test(
    name = "queue_fast_pass_rs_test",
    size = "small",
    srcs = ["queue-fast-pass_test.sh"],
    args = ["$(location :queue_fast_pass)"],
    data = [
        "queue-fast-pass.sh",
        ":queue_fast_pass",
        "//:workflow_files",
    ],
)

# migration-safety
rust_library(
    name = "migration_safety_lib",
    srcs = ["src/migration_safety/lib.rs"],
    crate_name = "migration_safety",
    crate_root = "src/migration_safety/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "migration_safety",
    srcs = ["src/migration_safety/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":migration_safety_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":migration_safety",
    visibility = ["//visibility:public"],
) for n in [
    "migration-safety-rs",
    "migration_safety_rs",
]]

rust_test(
    name = "migration_safety_lib_test",
    size = "small",
    crate = ":migration_safety_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# dependabot-lock-rebase
rust_library(
    name = "dependabot_lock_rebase_lib",
    srcs = ["src/dependabot_lock_rebase/lib.rs"],
    crate_name = "dependabot_lock_rebase",
    crate_root = "src/dependabot_lock_rebase/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "dependabot_lock_rebase",
    srcs = ["src/dependabot_lock_rebase/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":dependabot_lock_rebase_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":dependabot_lock_rebase",
    visibility = ["//visibility:public"],
) for n in [
    "dependabot-lock-rebase-rs",
    "dependabot_lock_rebase_rs",
]]

sh_test(
    name = "dependabot_lock_rebase_test",
    size = "small",
    srcs = ["dependabot-lock-rebase_test.sh"],
    args = ["$(location dependabot-lock-rebase.sh)"],
    data = [
        "dependabot-lock-rebase.sh",
    ],
)

sh_test(
    name = "dependabot_lock_rebase_rs_test",
    size = "small",
    srcs = ["dependabot-lock-rebase_test.sh"],
    args = ["$(location :dependabot_lock_rebase)"],
    data = [
        "dependabot-lock-rebase.sh",
        ":dependabot_lock_rebase",
    ],
)

# release-hold
rust_library(
    name = "release_hold_lib",
    srcs = ["src/release_hold/lib.rs"],
    crate_name = "release_hold",
    crate_root = "src/release_hold/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "release_hold",
    srcs = ["src/release_hold/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":release_hold_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":release_hold",
    visibility = ["//visibility:public"],
) for n in [
    "release-hold-rs",
    "release_hold_rs",
]]

sh_test(
    name = "release_hold_test",
    size = "small",
    srcs = ["release-hold_test.sh"],
    args = ["$(location release-hold.sh)"],
    data = [
        "release-hold.sh",
    ],
)

sh_test(
    name = "release_hold_rs_test",
    size = "small",
    srcs = ["release-hold_test.sh"],
    args = ["$(location :release_hold)"],
    data = [
        "release-hold.sh",
        ":release_hold",
    ],
)

# secret-scan
rust_library(
    name = "secret_scan_lib",
    srcs = ["src/secret_scan/lib.rs"],
    crate_name = "secret_scan",
    crate_root = "src/secret_scan/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "secret_scan",
    srcs = ["src/secret_scan/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":secret_scan_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":secret_scan",
    visibility = ["//visibility:public"],
) for n in [
    "secret-scan-rs",
    "secret_scan_rs",
]]

sh_test(
    name = "secret_scan_test",
    size = "small",
    srcs = ["secret-scan_test.sh"],
    args = ["$(location secret-scan.sh)"],
    data = [
        "secret-scan.sh",
    ],
)

sh_test(
    name = "secret_scan_rs_test",
    size = "small",
    srcs = ["secret-scan_test.sh"],
    args = ["$(location :secret_scan)"],
    data = [
        "secret-scan.sh",
        ":secret_scan",
    ],
)

# rdeps-map-ref
rust_library(
    name = "rdeps_map_ref_lib",
    srcs = ["src/rdeps_map_ref/lib.rs"],
    crate_name = "rdeps_map_ref",
    crate_root = "src/rdeps_map_ref/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "rdeps_map_ref",
    srcs = ["src/rdeps_map_ref/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":rdeps_map_ref_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":rdeps_map_ref",
    visibility = ["//visibility:public"],
) for n in [
    "rdeps-map-ref-rs",
    "rdeps_map_ref_rs",
]]

sh_test(
    name = "rdeps_map_ref_test",
    size = "small",
    srcs = ["rdeps-map-ref_test.sh"],
    args = ["$(location rdeps-map-ref.sh)"],
    data = [
        "rdeps-map-ref.sh",
    ],
)

sh_test(
    name = "rdeps_map_ref_rs_test",
    size = "small",
    srcs = ["rdeps-map-ref_test.sh"],
    args = ["$(location :rdeps_map_ref)"],
    data = [
        "rdeps-map-ref.sh",
        ":rdeps_map_ref",
    ],
)

# resolve-deploy-base
rust_library(
    name = "resolve_deploy_base_lib",
    srcs = ["src/resolve_deploy_base/lib.rs"],
    crate_name = "resolve_deploy_base",
    crate_root = "src/resolve_deploy_base/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "resolve_deploy_base",
    srcs = ["src/resolve_deploy_base/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":resolve_deploy_base_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":resolve_deploy_base",
    visibility = ["//visibility:public"],
) for n in [
    "resolve-deploy-base-rs",
    "resolve_deploy_base_rs",
]]

sh_test(
    name = "resolve_deploy_base_test",
    size = "small",
    srcs = ["resolve-deploy-base_test.sh"],
    args = ["$(location resolve-deploy-base.sh)"],
    data = [
        "resolve-deploy-base.sh",
    ],
)

sh_test(
    name = "resolve_deploy_base_rs_test",
    size = "small",
    srcs = ["resolve-deploy-base_test.sh"],
    args = ["$(location :resolve_deploy_base)"],
    data = [
        "resolve-deploy-base.sh",
        ":resolve_deploy_base",
    ],
)

# install-pinned-tool
rust_library(
    name = "install_pinned_tool_lib",
    srcs = ["src/install_pinned_tool/lib.rs"],
    crate_name = "install_pinned_tool",
    crate_root = "src/install_pinned_tool/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "install_pinned_tool",
    srcs = ["src/install_pinned_tool/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":install_pinned_tool_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":install_pinned_tool",
    visibility = ["//visibility:public"],
) for n in [
    "install-pinned-tool-rs",
    "install_pinned_tool_rs",
]]

sh_test(
    name = "install_pinned_tool_rs_test",
    size = "small",
    srcs = ["install-pinned-tool_test.sh"],
    args = ["$(location :install_pinned_tool)"],
    data = [
        "install-pinned-tool.sh",
        ":install_pinned_tool",
    ],
    target_compatible_with = ["@platforms//os:linux"],
)

# changelog-summary
rust_library(
    name = "changelog_summary_lib",
    srcs = ["src/changelog_summary/lib.rs"],
    crate_name = "changelog_summary",
    crate_root = "src/changelog_summary/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "changelog_summary",
    srcs = ["src/changelog_summary/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":changelog_summary_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":changelog_summary",
    visibility = ["//visibility:public"],
) for n in [
    "changelog-summary-rs",
    "changelog_summary_rs",
]]

sh_test(
    name = "changelog_summary_test",
    size = "small",
    srcs = ["changelog-summary_test.sh"],
    args = ["$(location changelog-summary.sh)"],
    data = [
        "changelog-summary.sh",
    ],
)

sh_test(
    name = "changelog_summary_rs_test",
    size = "small",
    srcs = ["changelog-summary_test.sh"],
    args = ["$(location :changelog_summary)"],
    data = [
        "changelog-summary.sh",
        ":changelog_summary",
    ],
)

# relevant-paths
rust_library(
    name = "relevant_paths_lib",
    srcs = ["src/relevant_paths/lib.rs"],
    crate_name = "relevant_paths",
    crate_root = "src/relevant_paths/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "relevant_paths",
    srcs = ["src/relevant_paths/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":relevant_paths_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":relevant_paths",
    visibility = ["//visibility:public"],
) for n in [
    "relevant-paths-rs",
    "relevant_paths_rs",
]]

sh_test(
    name = "relevant_paths_test",
    size = "small",
    srcs = ["relevant-paths_test.sh"],
    args = ["$(location relevant-paths.sh)"],
    data = [
        "relevant-paths.sh",
        "//:workflow_files",
    ],
)

sh_test(
    name = "relevant_paths_rs_test",
    size = "small",
    srcs = ["relevant-paths_test.sh"],
    args = ["$(location :relevant_paths)"],
    data = [
        "relevant-paths.sh",
        ":relevant_paths",
        "//:workflow_files",
    ],
)

# go-test-with-retry
rust_library(
    name = "go_test_with_retry_lib",
    srcs = ["src/go_test_with_retry/lib.rs"],
    crate_name = "go_test_with_retry",
    crate_root = "src/go_test_with_retry/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        ":transient_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "go_test_with_retry",
    srcs = ["src/go_test_with_retry/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":go_test_with_retry_lib",
        ":transient_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":go_test_with_retry",
    visibility = ["//visibility:public"],
) for n in [
    "go-test-with-retry-rs",
    "go_test_with_retry_rs",
]]

sh_test(
    name = "go_test_with_retry_test",
    size = "small",
    srcs = ["go-test-with-retry_test.sh"],
    args = ["$(location go-test-with-retry.sh)"],
    data = [
        "go-test-with-retry.sh",
        "transient-lib.sh",
    ],
)

sh_test(
    name = "go_test_with_retry_rs_test",
    size = "small",
    srcs = ["go-test-with-retry_test.sh"],
    args = ["$(location :go_test_with_retry)"],
    data = [
        "go-test-with-retry.sh",
        "transient-lib.sh",
        ":go_test_with_retry",
    ],
)

# tabula-deploy-preflight
rust_library(
    name = "tabula_deploy_preflight_lib",
    srcs = ["src/tabula_deploy_preflight/lib.rs"],
    crate_name = "tabula_deploy_preflight",
    crate_root = "src/tabula_deploy_preflight/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "tabula_deploy_preflight",
    srcs = ["src/tabula_deploy_preflight/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":tabula_deploy_preflight_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":tabula_deploy_preflight",
    visibility = ["//visibility:public"],
) for n in [
    "tabula-deploy-preflight-rs",
    "tabula_deploy_preflight_rs",
]]

sh_test(
    name = "tabula_deploy_preflight_test",
    size = "small",
    srcs = ["tabula-deploy-preflight_test.sh"],
    args = ["$(location tabula-deploy-preflight.sh)"],
    data = [
        "tabula-deploy-preflight.sh",
    ],
)

sh_test(
    name = "tabula_deploy_preflight_rs_test",
    size = "small",
    srcs = ["tabula-deploy-preflight_test.sh"],
    args = ["$(location :tabula_deploy_preflight)"],
    data = [
        "tabula-deploy-preflight.sh",
        ":tabula_deploy_preflight",
    ],
)

# release-pr-dequeue
rust_library(
    name = "release_pr_dequeue_lib",
    srcs = ["src/release_pr_dequeue/lib.rs"],
    crate_name = "release_pr_dequeue",
    crate_root = "src/release_pr_dequeue/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "release_pr_dequeue",
    srcs = ["src/release_pr_dequeue/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":release_pr_dequeue_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":release_pr_dequeue",
    visibility = ["//visibility:public"],
) for n in [
    "release-pr-dequeue-rs",
    "release_pr_dequeue_rs",
]]

sh_test(
    name = "release_pr_dequeue_test",
    size = "small",
    srcs = ["release-pr-dequeue_test.sh"],
    args = ["$(location release-pr-dequeue.sh)"],
    data = [
        "release-pr-dequeue.sh",
        "//:workflow_files",
    ],
)

sh_test(
    name = "release_pr_dequeue_rs_test",
    size = "small",
    srcs = ["release-pr-dequeue_test.sh"],
    args = ["$(location :release_pr_dequeue)"],
    data = [
        "release-pr-dequeue.sh",
        ":release_pr_dequeue",
        "//:workflow_files",
    ],
)

# foundation-app-digest-guard
rust_library(
    name = "foundation_app_digest_guard_lib",
    srcs = ["src/foundation_app_digest_guard/lib.rs"],
    crate_name = "foundation_app_digest_guard",
    crate_root = "src/foundation_app_digest_guard/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "foundation_app_digest_guard",
    srcs = ["src/foundation_app_digest_guard/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":foundation_app_digest_guard_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":foundation_app_digest_guard",
    visibility = ["//visibility:public"],
) for n in [
    "foundation-app-digest-guard-rs",
    "foundation_app_digest_guard_rs",
]]

rust_test(
    name = "foundation_app_digest_guard_lib_test",
    size = "small",
    crate = ":foundation_app_digest_guard_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "foundation_app_digest_guard_test",
    size = "small",
    srcs = ["foundation-app-digest-guard_test.sh"],
    args = ["$(location foundation-app-digest-guard.sh)"],
    data = [
        "foundation-app-digest-guard.sh",
    ],
)

sh_test(
    name = "foundation_app_digest_guard_rs_test",
    size = "small",
    srcs = ["foundation-app-digest-guard_test.sh"],
    args = ["$(location :foundation_app_digest_guard)"],
    data = [
        "foundation-app-digest-guard.sh",
        ":foundation_app_digest_guard",
    ],
)

# fast-lane-report
rust_library(
    name = "fast_lane_report_lib",
    srcs = ["src/fast_lane_report/lib.rs"],
    crate_name = "fast_lane_report",
    crate_root = "src/fast_lane_report/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "fast_lane_report",
    srcs = ["src/fast_lane_report/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":fast_lane_report_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":fast_lane_report",
    visibility = ["//visibility:public"],
) for n in [
    "fast-lane-report-rs",
    "fast_lane_report_rs",
]]

rust_test(
    name = "fast_lane_report_lib_test",
    size = "small",
    crate = ":fast_lane_report_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# agent-fast-lane
rust_library(
    name = "agent_fast_lane_lib",
    srcs = ["src/agent_fast_lane/lib.rs"],
    crate_name = "agent_fast_lane",
    crate_root = "src/agent_fast_lane/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "agent_fast_lane",
    srcs = ["src/agent_fast_lane/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":agent_fast_lane_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":agent_fast_lane",
    visibility = ["//visibility:public"],
) for n in [
    "agent-fast-lane-rs",
    "agent_fast_lane_rs",
]]

rust_test(
    name = "agent_fast_lane_lib_test",
    size = "small",
    crate = ":agent_fast_lane_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "agent_fast_lane_test",
    size = "small",
    srcs = ["agent-fast-lane_test.sh"],
    args = ["$(location agent-fast-lane.sh)"],
    data = [
        "agent-fast-lane.sh",
        "//:workflow_files",
        "//tools/agent-app:agent-app-sh",
    ],
)

sh_test(
    name = "agent_fast_lane_rs_test",
    size = "small",
    srcs = ["agent-fast-lane_test.sh"],
    args = ["$(location :agent_fast_lane)"],
    data = [
        "agent-fast-lane.sh",
        ":agent_fast_lane",
        "//:workflow_files",
        "//tools/agent-app:agent-app-sh",
    ],
)

# gcp-secret-or-fail
rust_library(
    name = "gcp_secret_or_fail_lib",
    srcs = ["src/gcp_secret_or_fail/lib.rs"],
    crate_name = "gcp_secret_or_fail",
    crate_root = "src/gcp_secret_or_fail/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
    ],
)

rust_binary(
    name = "gcp_secret_or_fail",
    srcs = ["src/gcp_secret_or_fail/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gcp_secret_or_fail_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[alias(
    name = n,
    actual = ":gcp_secret_or_fail",
    visibility = ["//visibility:public"],
) for n in [
    "gcp-secret-or-fail-rs",
    "gcp_secret_or_fail_rs",
]]

rust_test(
    name = "gcp_secret_or_fail_lib_test",
    size = "small",
    crate = ":gcp_secret_or_fail_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "gcp_secret_or_fail_test",
    size = "small",
    srcs = ["gcp-secret-or-fail_test.sh"],
    args = ["$(location gcp-secret-or-fail.sh)"],
    data = [
        "gcp-secret-or-fail.sh",
    ],
)

sh_test(
    name = "gcp_secret_or_fail_rs_test",
    size = "small",
    srcs = ["gcp-secret-or-fail_test.sh"],
    args = ["$(location :gcp_secret_or_fail)"],
    data = [
        "gcp-secret-or-fail.sh",
        ":gcp_secret_or_fail",
    ],
)
