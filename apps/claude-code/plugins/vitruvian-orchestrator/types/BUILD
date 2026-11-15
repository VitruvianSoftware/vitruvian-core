# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

# gazelle:ignore

load("@aspect_rules_js//js:defs.bzl", "js_library")

exports_files(
    ["index.d.ts"],
    visibility = ["//apps/claude-code/plugins/vitruvian-orchestrator:__pkg__"],
)

js_library(
    name = "types",
    srcs = ["index.d.ts"],
)
