# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-only
#
# gazelle:ignore
# gazelle:exclude include
# gazelle:exclude proto
# gazelle:exclude src

load("@gchat_crates//:defs.bzl", "all_crate_deps")
load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_rust//cargo:defs.bzl", "cargo_build_script")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_static_library", "rust_test")
load("//apps/desktop/courier/libsignal:defs.bzl", "protoc_dist")

package(default_visibility = ["//apps/desktop/courier:__subpackages__"])

exports_files([
    "Cargo.lock",
    "Cargo.toml",
    "NOTICE",
    "include/gchat.h",
])

protoc_dist(
    name = "protoc",
    protoc = "@protobuf//:protoc",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    well_known_protos = ["@protobuf//:well_known_type_protos"],
)

_CARGO_TOML = "apps/desktop/courier/gchat/Cargo.toml"

_DEPS = all_crate_deps(
    normal = True,
    package_name = _CARGO_TOML,
)

_PROC_MACRO_DEPS = all_crate_deps(
    package_name = _CARGO_TOML,
    proc_macro = True,
)

_BUILD_DEPS = all_crate_deps(
    build = True,
    package_name = _CARGO_TOML,
)

_BUILD_PROC_MACRO_DEPS = all_crate_deps(
    build_proc_macro = True,
    package_name = _CARGO_TOML,
)

cargo_build_script(
    name = "gchat_build_script",
    srcs = ["build.rs"],
    build_script_env = {
        "PROTOC": "$(execpath :protoc)/bin/protoc",
        "PROTOC_INCLUDE": "$(execpath :protoc)/include",
    },
    crate_name = "build_script_build",
    data = [
        "proto/googlechat.proto",
    ],
    edition = "2021",
    proc_macro_deps = _BUILD_PROC_MACRO_DEPS,
    tools = [":protoc"],
    deps = _BUILD_DEPS,
)

_SRCS = glob(["src/**/*.rs"])

rust_library(
    name = "gchat_rlib",
    srcs = _SRCS,
    crate_name = "gchat_ffi",
    edition = "2021",
    proc_macro_deps = _PROC_MACRO_DEPS,
    deps = _DEPS + [":gchat_build_script"],
)

rust_static_library(
    name = "gchat_static",
    srcs = _SRCS,
    crate_name = "gchat_ffi",
    edition = "2021",
    proc_macro_deps = _PROC_MACRO_DEPS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = _DEPS + [":gchat_build_script"],
)

cc_library(
    name = "gchat_ffi",
    srcs = [":gchat_static"],
    hdrs = ["include/gchat.h"],
    includes = ["include"],
    linkopts = [
        "-framework",
        "Security",
        "-framework",
        "CoreFoundation",
        "-framework",
        "SystemConfiguration",
    ],
    target_compatible_with = ["@platforms//os:macos"],
)

rust_test(
    name = "gchat_ffi_test",
    crate = ":gchat_rlib",
    edition = "2021",
    proc_macro_deps = _PROC_MACRO_DEPS,
    deps = _DEPS + [":gchat_build_script"],
)
