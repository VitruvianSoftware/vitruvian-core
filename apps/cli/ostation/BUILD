# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

# Standalone Python prototype for the Olight Ostation 2 Pro LAN protocol. The
# planned Rust port will replace these targets.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_library")
load("//tools/pytest:defs.bzl", "py_test")

py_library(
    name = "ostation_client",
    srcs = ["ostation_client.py"],
    imports = ["."],
    deps = ["@pip//cryptography"],
)

py_test(
    name = "ostation_client_test",
    size = "small",
    srcs = ["ostation_client_test.py"],
    deps = [":ostation_client"],
)
