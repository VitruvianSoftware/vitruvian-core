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
    "agent-fast-lane.sh",
    "agent-fast-lane_test.sh",
    "llvm-cache-key.sh",
    "llvm-cache-key_test.sh",
    "llvm-cache-stage.sh",
    "llvm-cache-stage_test.sh",
    "queue-fast-pass.sh",
    "queue-fast-pass_test.sh",
    "queue-runner-watch.sh",
    "queue-runner-watch_test.sh",
    "relevant-paths.sh",
    "relevant-paths_test.sh",
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

sh_test(
    name = "queue_runner_watch_test",
    size = "small",
    srcs = ["queue-runner-watch_test.sh"],
    args = ["$(location queue-runner-watch.sh)"],
    data = ["queue-runner-watch.sh"],
)

# Safety tests for the cache pruner. It DELETES, so the suite is mostly
# negative: an open PR's cache, a branch cache, and an undeterminable PR state
# must all survive. Runs the REAL binary with a fake gh on PATH (hermetic: no
# network, no token). Ported case for case from the former
# prune-pr-caches_test.sh.
rust_test(
    name = "prune_pr_caches_test",
    size = "small",
    srcs = ["src/prune_pr_caches/tests.rs"],
    data = [":prune_pr_caches"],
    edition = "2021",
    env = {"BIN": "$(rootpath :prune_pr_caches)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
)

# Jobs with no Bazel build these tools with the runner's rustc through
# .github/actions/build-ci-tool. This runs that action's build step exactly as
# written, with Bazel's rustc, for every tool a workflow asks it to build, and
# checks each result answers like the Bazel-built binary. TOOLS must list the
# tools the workflows build; the test fails when the two differ.
_BUILD_CI_TOOLS = [
    "changelog_summary",
    "foundation_app_digest_guard",
    "notify_ci_issues",
    "prune_pr_caches",
    "pulumi_summary",
    "release_beta_gate",
    "release_hold",
    "release_pr_dequeue",
]

rust_test(
    name = "build_ci_tool_test",
    size = "medium",
    srcs = ["src/build_ci_tool_test.rs"],
    data = [
        "//:composite_actions",
        "//:workflow_files",
        "//tools/shell-compat:src/lib.rs",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
        # The beta gate's fallback runs its real --jq through Bazel's jq.
        "@jq_toolchains//:resolved_toolchain",
    ] + [":" + t for t in _BUILD_CI_TOOLS] + [
        "src/%s/%s.rs" % (t, f)
        for t in _BUILD_CI_TOOLS
        for f in [
            "lib",
            "main",
        ]
    ],
    edition = "2021",
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "REAL_RUSTC": "$(rootpath @rules_rust//rust/toolchain:current_rustc_files)",
        "TOOLS": " ".join(_BUILD_CI_TOOLS),
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

# The mirror's release workflow for the standalone Nexus Agent never runs here;
# nexus-agent-mirror-toolchain.yaml rehearses its build and packaging on pull
# requests. This fails when the steps the two share stop being the same, which
# nothing else would report: the rehearsal would stay green while proving
# nothing about the release. Reads both files as text; builds nothing.
rust_test(
    name = "nexus_agent_release_rehearsal_test",
    size = "small",
    srcs = ["src/nexus_agent_release_rehearsal_test.rs"],
    args = [
        "$(rootpath //apps/desktop/nexus-agent:release_workflow)",
        "$(rootpath //:.github/workflows/nexus-agent-mirror-toolchain.yaml)",
    ],
    data = [
        "//:.github/workflows/nexus-agent-mirror-toolchain.yaml",
        "//apps/desktop/nexus-agent:release_workflow",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
)

# `bazel run //tools/ci:actionlint` -- the required `actionlint` check, locally:
# the pinned actionlint (tools/tools.lock.json, at the workflow's
# ACTIONLINT_VERSION) with shellcheck over the `run:` blocks, then the
# commit-SHA pin check, //tools/ci:require_pinned_actions, as the workflow does.
rust_library(
    name = "actionlint_lib",
    srcs = ["src/actionlint/lib.rs"],
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
        ":require_pinned_actions",
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

# Throwaway repos and the real pinned binaries; also fails when the workflow's
# ACTIONLINT_VERSION and the lockfile drift apart.
rust_test(
    name = "actionlint_test",
    size = "small",
    srcs = ["src/actionlint/tests.rs"],
    data = [
        ":actionlint",
        ":require_pinned_actions",
        "//:.github/workflows/actionlint.yaml",
        "//tools:tools.lock.json",
        "@multitool//tools/actionlint",
        "@multitool//tools/shellcheck",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :actionlint)",
        "LOCK": "$(rootpath //tools:tools.lock.json)",
        "WORKFLOW": "$(rootpath //:.github/workflows/actionlint.yaml)",
    },
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
)

# Runs, verbatim and with the toolchain's real rustc, every `rustc` line a
# workflow or composite action uses to build a tools/ci binary on a runner
# without Bazel, and checks each leaves its executable. See the test's header.
rust_test(
    name = "workflow_rustc_test",
    size = "medium",
    srcs = ["src/workflow_rustc/tests.rs"],
    data = [
        "src/backstage_boot_smoke/lib.rs",
        "src/backstage_boot_smoke/main.rs",
        "src/chart_render/lib.rs",
        "src/chart_render/main.rs",
        "src/gitops_validate/lib.rs",
        "src/gitops_validate/main.rs",
        "src/gitops_values_render/lib.rs",
        "src/gitops_values_render/main.rs",
        "src/go_test_with_retry/lib.rs",
        "src/go_test_with_retry/main.rs",
        "src/image_sbom_scan/lib.rs",
        "src/image_sbom_scan/main.rs",
        "src/install_pinned_tool/lib.rs",
        "src/install_pinned_tool/main.rs",
        "src/migration_safety/lib.rs",
        "src/migration_safety/main.rs",
        "src/secret_scan/lib.rs",
        "src/secret_scan/main.rs",
        "src/transient_lib/lib.rs",
        "//:composite_actions",
        "//:workflow_files",
        "//tools/gitops/appset-render:srcs",
        "//tools/gomod:srcs",
        "//tools/shell-compat:src/lib.rs",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
    ],
    edition = "2021",
    env = {"RUSTC": "$(RUSTC)"},
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@rules_rust//rust/toolchain:current_rust_toolchain"],
)

# The commit-SHA pin check: every outside action pinned to a full commit SHA.
# One std-only file with no crate deps ON PURPOSE: actionlint.yaml has no Bazel
# and builds it with a bare
#   rustc --edition 2021 -O tools/ci/src/require_pinned_actions/main.rs
# Adding a dependency would break that job, not this build.
rust_binary(
    name = "require_pinned_actions",
    srcs = ["src/require_pinned_actions/main.rs"],
    crate_root = "src/require_pinned_actions/main.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

# Throwaway repo trees for the pin rules, plus the rustc line from
# actionlint.yaml run as written with the toolchain's rustc, so the job that
# builds the check without Bazel cannot drift from what is tested here.
rust_test(
    name = "require_pinned_actions_test",
    size = "small",
    srcs = ["src/require_pinned_actions/tests.rs"],
    data = [
        "src/require_pinned_actions/main.rs",
        ":require_pinned_actions",
        "//:.github/workflows/actionlint.yaml",
        "@rules_rust//rust/toolchain:current_rust_stdlib_files",
        "@rules_rust//rust/toolchain:current_rustc_files",
        "@rules_rust//rust/toolchain:current_rustc_lib_files",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :require_pinned_actions)",
        "RUSTC": "$(RUSTC)",
        "WORKFLOW": "$(rootpath //:.github/workflows/actionlint.yaml)",
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@rules_rust//rust/toolchain:current_rust_toolchain"],
    deps = [":ci_testkit"],
)

# Every workflow that checks out with persist-credentials: false and pushes to
# origin gives git a credential first. Reads the real workflows.
rust_test(
    name = "workflow_git_push_credentials_test",
    size = "small",
    srcs = ["src/workflow_git_push_credentials/tests.rs"],
    data = ["//:workflow_files"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The Claude Code hooks in .claude/: each runs the REAL hook (bash) against
# fakes, and checks .claude/settings.json wires it. jq is the hermetic one:
# the hooks need it and the RBE image has none. Run by
# .github/workflows/repo-guards-test.yaml on the hook paths, because the
# presubmit planner maps a file outside every package (.claude/ has no BUILD)
# to no tests at all.
#
# kube_setup_join_test is the one kube-setup case that needs pgrep to see a
# sibling process: on the remote executor it did not, and the homelab queue
# runner's image has no procps. So it is manual and local-only, and
# repo-guards-test.yaml runs it on the hosted runner, where the shell suite
# always ran it; kube_setup_test runs every other case anywhere.
_KUBE_JOIN = "waits_for_a_tailscale_up_that_is_still_joining"

[
    rust_test(
        name = name,
        size = "small",
        srcs = [
            "src/hook_tests/common.rs",
            "src/hook_tests/" + src + ".rs",
        ],
        args = args,
        crate_root = "src/hook_tests/" + src + ".rs",
        data = hook_data + [
            "//:.claude/settings.json",
            "@jq_toolchains//:resolved_toolchain",
        ],
        edition = "2021",
        env = {"JQ_BIN": "$(JQ_BIN)"},
        rustc_flags = ["-Copt-level=3"],
        tags = tags,
        toolchains = ["@jq_toolchains//:resolved_toolchain"],
        deps = [":ci_testkit"],
    )
    for name, src, args, tags, hook_data in [
        (
            "block_queue_bypass_test",
            "block_queue_bypass",
            [],
            [],
            ["//:.claude/block-queue-bypass.sh"],
        ),
        (
            "kube_setup_test",
            "kube_setup",
            [
                "--skip",
                _KUBE_JOIN,
            ],
            [],
            [
                "//:.claude/kube-setup.sh",
                "//:.claude/session-start.sh",
            ],
        ),
        (
            "kube_setup_join_test",
            "kube_setup",
            [
                "--exact",
                _KUBE_JOIN,
            ],
            [
                "manual",
                "no-remote-exec",
            ],
            [
                "//:.claude/kube-setup.sh",
                "//:.claude/session-start.sh",
            ],
        ),
        (
            "session_start_test",
            "session_start",
            [],
            [],
            [
                "//:.claude/kube-setup.sh",
                "//:.claude/session-start.sh",
                "//:.claude/tailscale-up.sh",
                "//tools/cloud-bootstrap:cloud-bootstrap.sh",
            ],
        ),
    ]
]

# The #[cfg(test)] unit tests in src/actionlint/.
rust_test(
    name = "actionlint_lib_test",
    size = "small",
    crate = ":actionlint_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# ---------- Rust ports of CI / delivery helper scripts ----------

# Shared by the black-box rust_tests below: temp dirs, fake executables on
# PATH, throwaway git repos, and a runner for the binary under test.
rust_library(
    name = "ci_testkit",
    testonly = True,
    srcs = ["src/testkit/lib.rs"],
    crate_name = "ci_testkit",
    crate_root = "src/testkit/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

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

# Black-box: runs the REAL binary with only the result variables each case
# names. Ported case for case from the former gate-evaluator_test.sh.
rust_test(
    name = "gate_evaluator_test",
    size = "small",
    srcs = ["src/gate_evaluator/tests.rs"],
    data = [":gate_evaluator"],
    edition = "2021",
    env = {"BIN": "$(rootpath :gate_evaluator)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# A workflow may name the homelab runner only through one exact rule, so a pull
# request (a fork's, too) can never choose it. Scans every workflow.
rust_test(
    name = "queue_runner_routing_test",
    size = "small",
    srcs = ["src/queue_runner_routing/cli_test.rs"],
    data = [
        ":queue_runner_routing",
        "//:workflow_files",
    ],
    edition = "2021",
    env = {
        "QUEUE_RUNNER_ROUTING_BIN": "$(rootpath :queue_runner_routing)",
        "WORKFLOW_FILES": "$(rootpaths //:workflow_files)",
    },
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

# The culprit-finder workflow bisects a red main to the commit that broke it.
# Guards the GOOD_SHA == BAD_SHA rejection (#1518) and that a real range still
# converges. Hermetic: throwaway git repos, no network, no bazel-in-bazel.
rust_test(
    name = "bisect_culprit_test",
    size = "small",
    srcs = ["src/bisect_culprit/cli_test.rs"],
    data = [":bisect_culprit"],
    edition = "2021",
    env = {"BISECT_CULPRIT_BIN": "$(rootpath :bisect_culprit)"},
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "site_pr_automerge_test",
    size = "small",
    srcs = ["src/site_pr_automerge/tests.rs"],
    data = [":site_pr_automerge"],
    edition = "2021",
    env = {"BIN": "$(rootpath :site_pr_automerge)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "deploy_affected_test",
    size = "small",
    srcs = ["src/deploy_affected/tests.rs"],
    data = [":deploy_affected"],
    edition = "2021",
    env = {"BIN": "$(rootpath :deploy_affected)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "resolve_unit_bases_test",
    size = "small",
    srcs = ["src/resolve_unit_bases/tests.rs"],
    data = [":resolve_unit_bases"],
    edition = "2021",
    env = {"BIN": "$(rootpath :resolve_unit_bases)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# delivery-drift
rust_library(
    name = "delivery_drift_lib",
    srcs = ["src/delivery_drift/lib.rs"],
    crate_name = "delivery_drift",
    crate_root = "src/delivery_drift/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@rules_rust//rust/runfiles",
    ],
)

# Judges each unit with the SAME decision engine the orchestrator runs, found
# in its runfiles (DEPLOY_AFFECTED_BIN overrides it).
rust_binary(
    name = "delivery_drift",
    srcs = ["src/delivery_drift/main.rs"],
    data = [":deploy_affected"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":delivery_drift_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "delivery_drift_test",
    size = "small",
    srcs = ["src/delivery_drift/tests.rs"],
    # The gh stub runs every --jq filter through the hermetic jq, so a filter
    # jq cannot parse fails here as it would against GitHub.
    data = [
        ":delivery_drift",
        ":deploy_affected",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :delivery_drift)",
        "ENGINE": "$(rootpath :deploy_affected)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = [":ci_testkit"],
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

# Stubs gh, gcloud, kubectl and curl on PATH: no cloud, no network.
rust_test(
    name = "preview_reaper_test",
    size = "small",
    srcs = ["src/preview_reaper/cli_test.rs"],
    data = [":preview_reaper"],
    edition = "2021",
    env = {"PREVIEW_REAPER_BIN": "$(rootpath :preview_reaper)"},
)

# The transient Go-proxy/network failure classifier, shared by
# :go_test_with_retry and //tools/gomod. Standard library only: CI jobs without
# Bazel build it with a bare rustc.
rust_library(
    name = "transient_lib",
    srcs = ["src/transient_lib/lib.rs"],
    crate_name = "transient_lib",
    crate_root = "src/transient_lib/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "ensure_site_verification_test",
    size = "small",
    srcs = ["src/ensure_site_verification/tests.rs"],
    # The port shells out to jq, which the RBE image lacks: the hermetic one.
    data = [
        ":ensure_site_verification",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :ensure_site_verification)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = [":ci_testkit"],
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

# A real temp git repository and a fake bazel on PATH; jq is the hermetic toolchain one.
rust_test(
    name = "affected_targets_test",
    size = "small",
    srcs = ["src/affected_targets/cli_test.rs"],
    data = [
        ":affected_targets",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "AFFECTED_TARGETS_BIN": "$(rootpath :affected_targets)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former pulumi-summary_test.sh.
rust_test(
    name = "pulumi_summary_test",
    size = "small",
    srcs = ["src/pulumi_summary/tests.rs"],
    data = [":pulumi_summary"] + glob(["testdata/pulumi/*.txt"]),
    edition = "2021",
    env = {"BIN": "$(rootpath :pulumi_summary)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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
        "//tools/gitops/appset-render:appset_render_lib",
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

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former release-beta-gate_test.sh.
rust_test(
    name = "release_beta_gate_test",
    size = "small",
    srcs = ["src/release_beta_gate/tests.rs"],
    data = [":release_beta_gate"],
    edition = "2021",
    env = {"BIN": "$(rootpath :release_beta_gate)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

rust_test(
    name = "image_sbom_scan_lib_test",
    size = "small",
    crate = ":image_sbom_scan_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Black-box: the REAL binary against a fake registry (curl serving an index,
# its attestation manifest and SPDX blob), the hermetic jq and a fake
# osv-scanner, so the jq filters themselves run.
rust_test(
    name = "image_sbom_scan_test",
    size = "small",
    srcs = ["src/image_sbom_scan/tests.rs"],
    data = [
        ":image_sbom_scan",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :image_sbom_scan)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary with a fake gh on PATH, the way the
# generated *-require-dev-soak jobs call it. Ported case for case from the
# former require-dev-soak_test.sh.
rust_test(
    name = "require_dev_soak_test",
    size = "small",
    srcs = ["src/require_dev_soak/tests.rs"],
    data = [":require_dev_soak"],
    edition = "2021",
    env = {"BIN": "$(rootpath :require_dev_soak)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

rust_test(
    name = "backstage_boot_smoke_lib_test",
    size = "small",
    compile_data = ["src/backstage_boot_smoke/testdata/smoke-config.golden.yaml"],
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

rust_test(
    name = "notify_ci_issues_lib_test",
    size = "small",
    crate = ":notify_ci_issues_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former notify-ci-issues_test.sh.
rust_test(
    name = "notify_ci_issues_test",
    size = "small",
    srcs = ["src/notify_ci_issues/tests.rs"],
    # Bazel's jq, not one on PATH: the RBE image has none.
    data = [
        ":notify_ci_issues",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :notify_ci_issues)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = [":ci_testkit"],
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

sh_test(
    name = "queue_fast_pass_test",
    size = "small",
    srcs = ["queue-fast-pass_test.sh"],
    args = ["$(location queue-fast-pass.sh)"],
    data = [
        "queue-fast-pass.sh",
        "//:workflow_files",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "dependabot_lock_rebase_test",
    size = "small",
    srcs = ["src/dependabot_lock_rebase/tests.rs"],
    data = [":dependabot_lock_rebase"],
    edition = "2021",
    env = {"BIN": "$(rootpath :dependabot_lock_rebase)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former release-hold_test.sh.
rust_test(
    name = "release_hold_test",
    size = "small",
    srcs = ["src/release_hold/tests.rs"],
    data = [":release_hold"],
    edition = "2021",
    env = {"BIN": "$(rootpath :release_hold)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: the REAL binary in throwaway git repos with a stub gitleaks (and
# a fake curl for the download path). Ported case for case from the former
# secret-scan_test.sh, plus the scan range per BASE_REV/BASE_REF, the
# download failing closed, set -e exit codes, and the pin held level with
# tools/tools.lock.json.
rust_test(
    name = "secret_scan_test",
    size = "small",
    srcs = ["src/secret_scan/tests.rs"],
    data = [
        "src/secret_scan/lib.rs",
        ":secret_scan",
        "//tools:tools.lock.json",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :secret_scan)",
        "LOCK": "$(rootpath //tools:tools.lock.json)",
        "SRC": "$(rootpath src/secret_scan/lib.rs)",
    },
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# A bare repository stands in for GitHub; the binary runs the same git commands
# it runs in CI. jq is the hermetic toolchain one.
rust_test(
    name = "rdeps_map_ref_test",
    size = "small",
    srcs = ["src/rdeps_map_ref/cli_test.rs"],
    data = [
        ":rdeps_map_ref",
        "@jq_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "RDEPS_MAP_REF_BIN": "$(rootpath :rdeps_map_ref)",
    },
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "resolve_deploy_base_test",
    size = "small",
    srcs = ["src/resolve_deploy_base/tests.rs"],
    data = [":resolve_deploy_base"],
    edition = "2021",
    env = {"BIN": "$(rootpath :resolve_deploy_base)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Downloads a pinned CI tool (actionlint, kubeconform, osv-scanner, promtool)
# and verifies its checksum; the composite action
# .github/actions/install-pinned-tool builds and runs this binary. Also guards
# the curl retry policy: a fixed --retry-delay turns off curl's backoff, and ~6s
# of GitHub-releases 500s then failed a required merge-queue check. Black-box:
# fake curl, real tar/install/grep/sha256sum, no network.
rust_test(
    name = "install_pinned_tool_test",
    size = "small",
    srcs = ["src/install_pinned_tool/tests.rs"],
    data = [":install_pinned_tool"],
    edition = "2021",
    env = {"BIN": "$(rootpath :install_pinned_tool)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former changelog-summary_test.sh.
rust_test(
    name = "changelog_summary_test",
    size = "small",
    srcs = ["src/changelog_summary/tests.rs"],
    data = [":changelog_summary"],
    edition = "2021",
    env = {"BIN": "$(rootpath :changelog_summary)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: the REAL binary over a scratch tree of Go modules with a fake go
# and a fake sleep. Which modules run, that only a transport failure retries
# (10s, 20s), and the failing module's status. The classifier's own cases are
# //tools/ci:transient_lib_test.
rust_test(
    name = "go_test_with_retry_test",
    size = "small",
    srcs = ["src/go_test_with_retry/tests.rs"],
    data = [":go_test_with_retry"],
    edition = "2021",
    env = {"BIN": "$(rootpath :go_test_with_retry)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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
        "//tools/deploy:deploy_lib",
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

# Black-box: runs the REAL binary as CI does, with fake gh/gcloud/curl on
# PATH and throwaway git repos. Ported case for case from the shell suite.
rust_test(
    name = "tabula_deploy_preflight_test",
    size = "small",
    srcs = ["src/tabula_deploy_preflight/tests.rs"],
    data = [":tabula_deploy_preflight"],
    edition = "2021",
    env = {"BIN": "$(rootpath :tabula_deploy_preflight)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former release-pr-dequeue_test.sh.
rust_test(
    name = "release_pr_dequeue_test",
    size = "small",
    srcs = ["src/release_pr_dequeue/tests.rs"],
    # vitruvian-release.yaml: the dequeue must run before release-please.
    data = [
        ":release_pr_dequeue",
        "//:workflow_files",
    ],
    edition = "2021",
    env = {"BIN": "$(rootpath :release_pr_dequeue)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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

rust_test(
    name = "foundation_app_digest_guard_lib_test",
    size = "small",
    crate = ":foundation_app_digest_guard_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Black-box: runs the REAL binary the way its workflow step does, with fake
# programs on PATH (hermetic: no network, no token). Ported case for case from
# the former foundation-app-digest-guard_test.sh.
rust_test(
    name = "foundation_app_digest_guard_test",
    size = "small",
    srcs = ["src/foundation_app_digest_guard/tests.rs"],
    data = [":foundation_app_digest_guard"],
    edition = "2021",
    env = {"BIN": "$(rootpath :foundation_app_digest_guard)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
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
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
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

rust_test(
    name = "gcp_secret_or_fail_lib_test",
    size = "small",
    crate = ":gcp_secret_or_fail_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Black-box: runs the REAL binary with a fake gcloud on PATH, the way the
# deploy workflows call it. Ported case for case from the former
# gcp-secret-or-fail_test.sh.
rust_test(
    name = "gcp_secret_or_fail_test",
    size = "small",
    srcs = ["src/gcp_secret_or_fail/tests.rs"],
    data = [":gcp_secret_or_fail"],
    edition = "2021",
    env = {"BIN": "$(rootpath :gcp_secret_or_fail)"},
    rustc_flags = ["-Copt-level=3"],
    deps = [":ci_testkit"],
)

# Every gcp_secret_or_fail capture in a workflow is masked with ::add-mask::
# right after; a value fetched at runtime is not redacted on its own.
rust_test(
    name = "gcp_secret_or_fail_masking_test",
    size = "small",
    srcs = ["src/gcp_secret_or_fail/masking_test.rs"],
    data = ["//:workflow_files"],
    edition = "2021",
    env = {"WORKFLOW_FILES": "$(rootpaths //:workflow_files)"},
    rustc_flags = ["-Copt-level=3"],
)

# agent-guard reads this file to check its refusal advice names a real target
# (//tools/agent-guard:pending_target_files).
exports_files(
    ["BUILD"],
    visibility = ["//tools/agent-guard:__pkg__"],
)
