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
)
