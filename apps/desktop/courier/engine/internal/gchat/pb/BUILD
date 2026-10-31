# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-only
#
# gazelle:ignore

load("@rules_go//go:def.bzl", "go_library")
load("@rules_go//proto:def.bzl", "go_proto_library")

package(default_visibility = ["//apps/desktop/courier:__subpackages__"])

go_proto_library(
    name = "googlechat_go_proto",
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/gchat/pb",
    proto = "//apps/desktop/courier/gchat:googlechat_proto",
)

go_library(
    name = "pb",
    srcs = ["helpers.go"],
    embed = [":googlechat_go_proto"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/gchat/pb",
)
