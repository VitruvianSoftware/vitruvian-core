# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Harness² (arXiv:2610.14224) for Antigravity, with Claude Code as the improver.

  bazel run //tools/harness2 -- install     # install/refresh the live plugin in ~/.gemini/config
  bazel run //tools/harness2 -- status
  bazel run //tools/harness2 -- validate
  bazel run //tools/harness2 -- distill <conversation-id> [--apply]
  bazel test //tools/harness2/...

Standard-library Python 3.9+: the same modules are copied into the plugin's
lib/ and run by Antigravity's hooks under whatever python3 it finds. See README.md.
"""

# gazelle:ignore
# assets/ is the plugin's file tree, copied as data; a BUILD file inside it would
# make a package boundary that drops files from glob(["assets/**"]).
# gazelle:exclude assets

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")
load("//tools/pytest:defs.bzl", "py_test")

SRCS = [
    "cli.py",
    "common.py",
    "constraints.py",
    "installer.py",
    "library.py",
    "prompts.py",
    "runtime_hooks.py",
    "trajectory.py",
    "validator.py",
]

py_library(
    name = "harness2_lib",
    srcs = SRCS,
    data = glob(["assets/**"]),
    imports = ["."],
)

py_binary(
    name = "harness2",
    srcs = ["cli.py"],
    main = "cli.py",
    visibility = ["//visibility:public"],
    deps = [":harness2_lib"],
)

py_test(
    name = "harness2_test",
    size = "small",
    srcs = ["harness2_test.py"],
    deps = [":harness2_lib"],
)
