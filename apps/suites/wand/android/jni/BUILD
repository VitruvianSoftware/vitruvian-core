# Copyright (c) 2026 VitruvianSoftware
# gazelle:ignore

load("@rules_cc//cc:defs.bzl", "cc_library")
load(
    "//apps/suites/wand/build:defs.bzl",
    "wand_rust_library",
    "wand_rust_shared_library",
    "wand_rust_test",
)

package(default_visibility = ["//apps/suites/wand/android:__subpackages__"])

wand_rust_library(
    name = "wand_jni_lib",
    srcs = [
        "src/bridge.rs",
        "src/lib.rs",
    ],
    crate_name = "wand_jni",
    edition = "2024",
    deps = [
        "//apps/suites/wand/core:wand_core",
        "@wand_crates//:jni",
        "@wand_crates//:log",
        "@wand_crates//:serde_json",
    ] + select({
        "@platforms//os:android": ["@wand_crates//:android_logger"],
        "//conditions:default": [],
    }),
)

wand_rust_test(
    name = "wand_jni_test",
    crate = ":wand_jni_lib",
    edition = "2024",
)

wand_rust_shared_library(
    name = "wand_jni",
    srcs = [
        "src/bridge.rs",
        "src/lib.rs",
    ],
    crate_name = "wand_jni",
    edition = "2024",
    rustc_flags = [
        "-Cstrip=debuginfo",
        "-Cstrip=symbols",
    ],
    target_compatible_with = ["@platforms//os:android"],
    deps = [
        "//apps/suites/wand/core:wand_core",
        "@wand_crates//:android_logger",
        "@wand_crates//:jni",
        "@wand_crates//:log",
        "@wand_crates//:serde_json",
    ],
)

cc_library(
    name = "wand_jni_cc",
    srcs = [":wand_jni"],
    target_compatible_with = ["@platforms//os:android"],
)
