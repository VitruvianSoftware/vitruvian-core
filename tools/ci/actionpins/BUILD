# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT

load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "actionpins",
    srcs = ["actionpins.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/ci/actionpins",
    visibility = ["//visibility:public"],
)

go_test(
    name = "actionpins_test",
    size = "small",
    srcs = ["actionpins_test.go"],
    data = [
        "//:pins_manifest",
        "//:workflow_files",
    ],
    deps = [":actionpins"],
)
