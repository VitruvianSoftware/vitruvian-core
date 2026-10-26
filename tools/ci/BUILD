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
    # Read by //tools/delivery/gen: every script the generated workflow shells
    # out to must exist -- the promotion interlock, and the durable-base
    # resolver the orchestrate job feeds BEFORE_REV from.
    "require-dev-soak.sh",
    "resolve-deploy-base.sh",
    "resolve-unit-bases.sh",
    "deploy-affected.sh",
    "gate-evaluator.sh",
    "td-lib.sh",
    # Shared transport-failure classifier: sourced by go-test-with-retry.sh and,
    # across packages, by //tools/gomod:tidy.
    "transient-lib.sh",
    "preview-reaper.sh",
    "preview-reaper_test.sh",
    "gate-evaluator_test.sh",
    "gcp-secret-or-fail.sh",
    "gcp-secret-or-fail_test.sh",
    "llvm-cache-key.sh",
    "llvm-cache-key_test.sh",
    "llvm-cache-stage.sh",
    "llvm-cache-stage_test.sh",
    # Read by //tools/agent-app:agent-app_test: pr-hold must use the label
    # these gates honour as a person's hold (PERSON_LABEL).
    "release-beta-gate.sh",
    "release-hold.sh",
    # CI's gitleaks pin. //tools/secret-scan:secret-scan_test fails when it and
    # tools/tools.lock.json disagree.
    "secret-scan.sh",
    "bisect-culprit.sh",
    "delivery-drift.sh",
    "queue-runner-routing.sh",
    "queue-runner-watch.sh",
    "prune-pr-caches.sh",
    "site-pr-automerge.sh",
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
