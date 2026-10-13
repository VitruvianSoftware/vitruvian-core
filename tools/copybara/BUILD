# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# The export version maps in copy.bara.sky rewrite in-tree references to
# PUBLISHED versions for the standalone mirrors. They were hand-maintained,
# guarded only by a "keep in sync" comment, and had drifted in 35 of 42 entries
# -- leaving ts-example-foundation unable to resolve its own dependencies.
sh_binary(
    name = "check-version-maps",
    srcs = ["check-version-maps.sh"],
    visibility = ["//visibility:public"],
)

alias(
    name = "check_version_maps",
    actual = ":check-version-maps",
    visibility = ["//visibility:public"],
)

sh_test(
    name = "check_version_maps_test",
    size = "small",
    srcs = ["check_version_maps_test.sh"],
    args = ["$(location check-version-maps.sh)"],
    data = ["check-version-maps.sh"],
)

# //tools/registry-trust reads COMPONENTS to learn which mirror publishes a
# package; its test reads the real file so a layout change cannot hide one.
exports_files(
    ["copy.bara.sky"],
    visibility = ["//tools/registry-trust:__pkg__"],
)
