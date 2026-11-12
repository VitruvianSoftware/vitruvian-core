# Copyright (c) 2026 VitruvianSoftware
# gazelle:ignore

load("@rules_cc//cc:defs.bzl", "cc_library")
load(
    "//apps/suites/vitruvian-wand/build:defs.bzl",
    "vitruvian_wand_rust_library",
    "vitruvian_wand_rust_shared_library",
    "vitruvian_wand_rust_test",
)

package(default_visibility = ["//apps/suites/vitruvian-wand/android:__subpackages__"])

vitruvian_wand_rust_library(
    name = "vitruvian_wand_jni_lib",
    srcs = [
        "src/bridge.rs",
        "src/lib.rs",
    ],
    crate_name = "vitruvian_wand_jni",
    edition = "2024",
    deps = [
        "//apps/suites/vitruvian-wand/core:vitruvian_wand_core",
        "@vitruvian_wand_crates//:jni",
        "@vitruvian_wand_crates//:log",
        "@vitruvian_wand_crates//:serde_json",
    ] + select({
        "@platforms//os:android": ["@vitruvian_wand_crates//:android_logger"],
        "//conditions:default": [],
    }),
)

vitruvian_wand_rust_test(
    name = "vitruvian_wand_jni_test",
    crate = ":vitruvian_wand_jni_lib",
    edition = "2024",
)

vitruvian_wand_rust_shared_library(
    name = "vitruvian_wand_jni",
    srcs = [
        "src/bridge.rs",
        "src/lib.rs",
    ],
    crate_name = "vitruvian_wand_jni",
    edition = "2024",
    rustc_flags = [
        "-Cstrip=debuginfo",
        "-Cstrip=symbols",
    ],
    target_compatible_with = ["@platforms//os:android"],
    deps = [
        "//apps/suites/vitruvian-wand/core:vitruvian_wand_core",
        "@vitruvian_wand_crates//:android_logger",
        "@vitruvian_wand_crates//:jni",
        "@vitruvian_wand_crates//:log",
        "@vitruvian_wand_crates//:serde_json",
    ],
)

cc_library(
    name = "vitruvian_wand_jni_cc",
    srcs = [":vitruvian_wand_jni"],
    target_compatible_with = ["@platforms//os:android"],
)
