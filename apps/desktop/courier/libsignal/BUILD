# Copyright 2026 VitruvianSoftware
# Upstream: https://github.com/signalapp/libsignal (AGPL-3.0-only); this file
# is build glue for it, under the same licence.
# SPDX-License-Identifier: AGPL-3.0-only
#
# libsignal_ffi.a, Signal's Rust library, built from source for
# mautrix-signal's libsignalgo (cgo, -lsignal_ffi). README.md explains the
# pieces; MODULE.bazel has the toolchain, crate graph and BoringSSL.
#
# Hand-written: gazelle's C++ extension would delete :signal_ffi (a cc_library
# with no sources of its own), so gazelle leaves this file alone.
# gazelle:ignore
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")
load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_static_library", "rust_test")
load(":defs.bzl", "boringssl_prefix", "protoc_dist", "with_rust_1_98_1")

package(default_visibility = ["//visibility:private"])

# Everything below that is only meaningful inside the Rust 1.98.1 build is
# incompatible elsewhere, so `bazel build //...` skips it rather than building
# it a second time (BoringSSL) or with the SDK's Rust 1.75.0 (which fails).
# It is macOS-only because the 1.98.1 toolchains are only registered for darwin.
_ONLY_UNDER_RUST_1_98_1 = select({
    ":rust_1_98_1_enabled": ["@platforms//os:macos"],
    "//conditions:default": ["@platforms//:incompatible"],
})

exports_files([
    "Cargo.lock",
    "Cargo.toml",
    "boring-pq.patch",
])

# True only under //apps/desktop/courier/libsignal:signal_ffi (set by with_rust_1_98_1).
# Selects the Rust 1.98.1 toolchains MODULE.bazel registers for libsignal.
bool_flag(
    name = "rust_1_98_1",
    build_setting_default = False,
    # Propagate into the exec configuration too: build scripts and proc macros
    # run there, and they must use the same compiler as the crates they serve.
    scope = "universal",
)

config_setting(
    name = "rust_1_98_1_enabled",
    flag_values = {":rust_1_98_1": "True"},
    visibility = ["//visibility:public"],
)

# Tools handed to libsignal's build scripts (see the crate.annotation tags in
# MODULE.bazel), named here so MODULE.bazel only refers to this package.
alias(
    name = "libclang",
    actual = "@llvm_toolchain_llvm//:libclang",
    visibility = ["//visibility:public"],
)

alias(
    name = "clang_headers",
    actual = "@llvm_toolchain_llvm//:include",
    visibility = ["//visibility:public"],
)

protoc_dist(
    name = "protoc",
    protoc = "@protobuf//:protoc",
    target_compatible_with = _ONLY_UNDER_RUST_1_98_1,
    visibility = ["//visibility:public"],
    well_known_protos = [
        "@protobuf//:descriptor_proto_srcs",
        "@protobuf//:well_known_type_protos",
    ],
)

boringssl_prefix(
    name = "boringssl_prefix",
    crypto = "@signal_boringssl//:crypto",
    ssl = "@signal_boringssl//:ssl",
    target_compatible_with = _ONLY_UNDER_RUST_1_98_1,
    visibility = ["//visibility:public"],
)

# libsignal-ffi's crate root, as a static library: lib + crate name
# signal_ffi gives libsignal_ffi.a, the file cgo's -lsignal_ffi asks for.
rust_static_library(
    name = "signal_ffi_rust",
    srcs = ["lib.rs"],
    crate_name = "signal_ffi",
    edition = "2024",
    target_compatible_with = _ONLY_UNDER_RUST_1_98_1,
    deps = [
        "@libsignal_crates//:libsignal-ffi-impl",
        "@libsignal_crates//:log",
    ],
)

with_rust_1_98_1(
    name = "signal_ffi_rust_1_98_1",
    dep = ":signal_ffi_rust",
    target_compatible_with = ["@platforms//os:macos"],
)

# What Go links: libsignalgo's go_library has this in cdeps (see the
# go.mau.fi/mautrix-signal override in MODULE.bazel). macOS only for now: the
# Rust 1.98.1 toolchains are only registered for darwin.
cc_library(
    name = "signal_ffi",
    linkopts = [
        "-lc++",
        "-lz",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    deps = [":signal_ffi_rust_1_98_1"],
)

# Used by the ring annotation in MODULE.bazel.
rust_library(
    name = "cc_in_execroot_lib",
    srcs = ["scripts/src/cc_in_execroot/lib.rs"],
    crate_name = "cc_in_execroot_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/courier:__subpackages__"],
)

rust_binary(
    name = "cc_in_execroot",
    srcs = ["scripts/src/cc_in_execroot/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":cc_in_execroot_lib"],
)

rust_test(
    name = "cc_in_execroot_test",
    size = "small",
    crate = ":cc_in_execroot_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    deps = ["@rules_cc//cc/common"],
)
