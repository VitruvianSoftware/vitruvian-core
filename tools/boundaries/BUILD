load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

# Copyright (c) 2026 VitruvianSoftware
#
# Package group definitions for architectural layer enforcement.

load(
    ":package_groups.bzl",
    "APPLICATION_PACKAGES",
    "INFRASTRUCTURE_PACKAGES",
    "PLATFORM_TOOLS_PACKAGES",
    "SHARED_PACKAGES",
)

package(default_visibility = ["//visibility:public"])

package_group(
    name = "platform_tools",
    packages = PLATFORM_TOOLS_PACKAGES,
)

package_group(
    name = "infrastructure",
    packages = INFRASTRUCTURE_PACKAGES,
)

package_group(
    name = "shared_packages",
    packages = SHARED_PACKAGES,
)

package_group(
    name = "applications",
    packages = APPLICATION_PACKAGES,
)

package_group(
    name = "all_packages",
    includes = [
        ":applications",
        ":infrastructure",
        ":platform_tools",
        ":shared_packages",
    ],
)

# gazelle:ignore

rust_library(
    name = "boundaries_lib",
    srcs = ["src/lib.rs"],
    crate_name = "boundaries",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "boundaries_test",
    size = "small",
    crate = ":boundaries_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "boundaries_test_rs",
    tests = [":boundaries_test"],
)

test_suite(
    name = "check_test",
    tests = [":boundaries_test"],
)

bzl_library(
    name = "package_groups",
    srcs = ["package_groups.bzl"],
)
