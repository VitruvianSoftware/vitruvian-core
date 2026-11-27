# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("//tools/pytest:defs.bzl", "py_test")

# gazelle:ignore

py_test(
    name = "sdk_cache_test",
    size = "small",
    srcs = [
        "sdk_cache.py",
        "sdk_cache_test.py",
    ],
    # pytest skips directories whose name starts with a dot (.github), so name
    # the file, or it collects nothing and fails with exit code 5.
    args = ["$(rootpath sdk_cache_test.py)"],
    data = [
        "action.yml",
        "//:.github/workflows/android-emulator-cache.yaml",
        "//.github/actions/setup-bazel:cache_capacity_guard.py",
    ],
    env = {
        "ANDROID_EMULATOR_ACTION_PATH": "$(rootpath action.yml)",
        "ANDROID_EMULATOR_WORKFLOW_PATH": "$(rootpath //:.github/workflows/android-emulator-cache.yaml)",
    },
    deps = ["@pip//pyyaml"],
)
