# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("//tools/pytest:defs.bzl", "py_test")

# gazelle:ignore

# runner_cache_check.py runs under the runner's own python3 before Bazel
# starts (action.yml), so it is standard library only and has no py_binary.
py_test(
    name = "runner_cache_check_test",
    size = "small",
    srcs = [
        "runner_cache_check.py",
        "runner_cache_check_test.py",
    ],
    # pytest skips directories whose name starts with a dot (.github), so name
    # the file, or it collects nothing and fails with exit code 5.
    args = ["$(rootpath runner_cache_check_test.py)"],
    data = ["action.yml"],
)

py_test(
    name = "cache_capacity_guard_test",
    size = "small",
    srcs = [
        "cache_capacity_guard.py",
        "cache_capacity_guard_test.py",
    ],
    args = ["$(rootpath cache_capacity_guard_test.py)"],
    data = ["//:.github/actions/bazel-repo-cache-warm/action.yml"],
    env = {
        "WARM_COMPOSITE_ACTION_PATH": "$(rootpath //:.github/actions/bazel-repo-cache-warm/action.yml)",
    },
    deps = ["@pip//pyyaml"],
)

py_test(
    name = "cache_prune_test",
    size = "small",
    srcs = [
        "cache_capacity_guard.py",
        "cache_prune.py",
        "cache_prune_test.py",
    ],
    args = ["$(rootpath cache_prune_test.py)"],
)

py_test(
    name = "bazelisk_cache_key_test",
    size = "small",
    srcs = [
        "bazelisk_cache_key_test.py",
    ],
    args = ["$(rootpath bazelisk_cache_key_test.py)"],
    data = ["//:.bazelversion"],
    env = {"BAZELVERSION_PATH": "$(rootpath //:.bazelversion)"},
)

py_test(
    name = "restore_keys_test",
    size = "small",
    srcs = [
        "restore_keys_test.py",
    ],
    args = ["$(rootpath restore_keys_test.py)"],
    data = [
        "action.yml",
        "//:.github/actions/bazel-repo-cache-warm/action.yml",
    ],
    env = {
        "SETUP_BAZEL_ACTION_PATH": "$(rootpath action.yml)",
        "WARM_COMPOSITE_ACTION_PATH": "$(rootpath //:.github/actions/bazel-repo-cache-warm/action.yml)",
    },
    deps = ["@pip//pyyaml"],
)

py_test(
    name = "bazel_repo_cache_workflow_test",
    size = "small",
    srcs = [
        "bazel_repo_cache_workflow_test.py",
    ],
    args = ["$(rootpath bazel_repo_cache_workflow_test.py)"],
    data = ["//:.github/workflows/bazel-repo-cache.yaml"],
    env = {
        "BAZEL_REPO_CACHE_WORKFLOW_PATH": "$(rootpath //:.github/workflows/bazel-repo-cache.yaml)",
    },
    deps = ["@pip//pyyaml"],
)
