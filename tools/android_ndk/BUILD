load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

# Hermetic Android NDK toolchain. See extension.bzl.

bzl_library(
    name = "extension",
    srcs = ["extension.bzl"],
    visibility = ["//visibility:public"],
    # keep: gazelle infers @rules_android_ndk//:rules from the load in
    # extension.bzl, but that module ships no bzl_library, so the target does
    # not exist and every Bazel invocation in the repo fails to analyse.
    deps = [],
)
