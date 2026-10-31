# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-only
#
# gazelle:ignore
# gazelle:exclude fuzz
# gazelle:exclude include
# gazelle:exclude proto
# gazelle:exclude src

load("@gchat_crates//:defs.bzl", "all_crate_deps")
load("@protobuf//bazel:proto_library.bzl", "proto_library")
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
    "proto/googlechat.proto",
])

proto_library(
    name = "googlechat_proto",
    srcs = ["proto/googlechat.proto"],
)

protoc_dist(
    name = "protoc",
    protoc = "@protobuf//:protoc",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    well_known_protos = ["@protobuf//:well_known_type_protos"],
)

_CARGO_TOML = "apps/desktop/courier/gchat/Cargo.toml"

_DEPS = all_crate_deps(
    package_name = _CARGO_TOML,
    normal = True,
)

_PROC_MACRO_DEPS = all_crate_deps(
    package_name = _CARGO_TOML,
    proc_macro = True,
)

_BUILD_DEPS = all_crate_deps(
    package_name = _CARGO_TOML,
    build = True,
)

_BUILD_PROC_MACRO_DEPS = all_crate_deps(
    package_name = _CARGO_TOML,
    build_proc_macro = True,
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

genrule(
    name = "gchat_scoped_archive",
    srcs = [":gchat_static"],
    outs = ["libgchat_ffi_scoped.a"],
    cmd = """
        set -eu
        if /usr/bin/nm -g $(location :gchat_static) 2>/dev/null | /usr/bin/grep -q gchat_test_only; then
            echo "ERROR: test-loopback feature leaked into production gchat_static" >&2
            exit 1
        fi
        REL_OBJ="$$(mktemp -t gchat_ffi_reloc).o"
        trap 'rm -f "$$REL_OBJ"' EXIT
        /usr/bin/clang -nostdlib -r -Wl,-exported_symbol,'_gchat_*' -Wl,-all_load $(location :gchat_static) -o "$$REL_OBJ"
        /usr/bin/ar rcs $@ "$$REL_OBJ"
    """,
    target_compatible_with = ["@platforms//os:macos"],
)

cc_library(
    name = "gchat_ffi",
    srcs = [":gchat_scoped_archive"],
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

rust_static_library(
    name = "gchat_static_test_loopback",
    testonly = True,
    srcs = _SRCS,
    crate_features = ["test-loopback"],
    crate_name = "gchat_ffi_test_loopback",
    edition = "2021",
    proc_macro_deps = _PROC_MACRO_DEPS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = _DEPS + [":gchat_build_script"],
)

genrule(
    name = "gchat_scoped_archive_test_loopback",
    testonly = True,
    srcs = [":gchat_static_test_loopback"],
    outs = ["libgchat_ffi_test_loopback_scoped.a"],
    cmd = """
        set -eu
        REL_OBJ="$$(mktemp -t gchat_ffi_test_reloc).o"
        trap 'rm -f "$$REL_OBJ"' EXIT
        /usr/bin/clang -nostdlib -r -Wl,-exported_symbol,'_gchat_*' -Wl,-all_load $(location :gchat_static_test_loopback) -o "$$REL_OBJ"
        /usr/bin/ar rcs $@ "$$REL_OBJ"
    """,
    target_compatible_with = ["@platforms//os:macos"],
)

cc_library(
    name = "gchat_ffi_test_loopback",
    testonly = True,
    srcs = [":gchat_scoped_archive_test_loopback"],
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

rust_test(
    name = "fuzz_chunk_parser_test",
    srcs = ["fuzz/fuzz_targets/fuzz_chunk_parser.rs"],
    edition = "2021",
    deps = [":gchat_rlib"],
)

rust_test(
    name = "fuzz_pblite_event_test",
    srcs = ["fuzz/fuzz_targets/fuzz_pblite_event.rs"],
    edition = "2021",
    deps = [":gchat_rlib"],
)

rust_test(
    name = "fuzz_fmt_annotations_test",
    srcs = ["fuzz/fuzz_targets/fuzz_fmt_annotations.rs"],
    edition = "2021",
    deps = [":gchat_rlib"],
)

rust_test(
    name = "fuzz_cookies_test",
    srcs = ["fuzz/fuzz_targets/fuzz_cookies.rs"],
    edition = "2021",
    deps = [":gchat_rlib"],
)
