load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

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

bzl_library(
    name = "package_groups",
    srcs = ["package_groups.bzl"],
)
