load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

# Hermetic Android NDK toolchain. See extension.bzl.

bzl_library(
    name = "extension",
    srcs = ["extension.bzl"],
    visibility = ["//visibility:public"],
    deps = ["@rules_android_ndk//:rules"],
)
