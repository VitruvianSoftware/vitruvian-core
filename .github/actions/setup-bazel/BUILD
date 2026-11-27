# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pytest:defs.bzl", "py_test")

# gazelle:ignore

exports_files(
    [
        "cache_capacity_guard.py",
        "cache_prune.py",
    ],
    visibility = ["//.github/actions/android-emulator:__pkg__"],
)

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
        "libxml2_debs.sh",
        "//:.github/actions/bazel-repo-cache-warm/action.yml",
    ],
    env = {
        "SETUP_BAZEL_ACTION_PATH": "$(rootpath action.yml)",
        "WARM_COMPOSITE_ACTION_PATH": "$(rootpath //:.github/actions/bazel-repo-cache-warm/action.yml)",
    },
    deps = ["@pip//pyyaml"],
)

py_test(
    name = "libxml2_debs_test",
    size = "small",
    srcs = [
        "libxml2_debs_test.py",
    ],
    args = ["$(rootpath libxml2_debs_test.py)"],
    data = ["libxml2_debs.sh"],
    env = {"LIBXML2_DEBS_SCRIPT": "$(rootpath libxml2_debs.sh)"},
)

sh_test(
    name = "libxml2_debs_install_test",
    size = "small",
    srcs = ["libxml2_debs_install_test.sh"],
    data = ["libxml2_debs.sh"],
    env = {"LIBXML2_DEBS_SCRIPT": "$(rootpath libxml2_debs.sh)"},
)

py_test(
    name = "bazel_repo_cache_workflow_test",
    size = "small",
    srcs = [
        "bazel_repo_cache_workflow_test.py",
    ],
    args = ["$(rootpath bazel_repo_cache_workflow_test.py)"],
    data = [
        "//:.github/actions/bazel-repo-cache-warm/action.yml",
        "//:.github/workflows/bazel-repo-cache.yaml",
    ],
    env = {
        "BAZEL_REPO_CACHE_WORKFLOW_PATH": "$(rootpath //:.github/workflows/bazel-repo-cache.yaml)",
        "WARM_COMPOSITE_ACTION_PATH": "$(rootpath //:.github/actions/bazel-repo-cache-warm/action.yml)",
    },
)

sh_test(
    name = "bazel_race_retry_test",
    size = "small",
    srcs = ["bazel_race_retry_test.sh"],
    data = ["bazel_race_retry.sh"],
    env = {"BAZEL_RACE_RETRY_SCRIPT": "$(rootpath bazel_race_retry.sh)"},
)

py_test(
    name = "bazel_race_retry_wiring_test",
    size = "small",
    srcs = ["bazel_race_retry_wiring_test.py"],
    args = ["$(rootpath bazel_race_retry_wiring_test.py)"],
    data = ["action.yml"],
    env = {"SETUP_BAZEL_ACTION_PATH": "$(rootpath action.yml)"},
    deps = ["@pip//pyyaml"],
)
