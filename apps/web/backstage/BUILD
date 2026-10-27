# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# backstage — first-party developer portal for vitruvian-core services, catalog, and documentation.
# gazelle:ignore
# gazelle:exclude packages
# gazelle:exclude dist

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")

# Inter-app boundary (#82): default targets to backstage-internal visibility
# so other top-level apps cannot depend on backstage internals.
package(default_visibility = ["//apps/web/backstage:__subpackages__"])

# Developer-environment check: `bazel run //backstage:doctor`.
doctor(
    name = "doctor",
    label = "backstage",
    optional = [
        "docker",
    ],
    required = [
        "bazel",
        "node",
        "pnpm",
        "git",
    ],
)

rust_library(
    name = "bump_release_lib",
    srcs = ["src/lib.rs"],
    crate_name = "backstage_bump_release",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/web/backstage:__subpackages__"],
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "bump-release-rs",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/web/backstage:__subpackages__"],
    deps = [":bump_release_lib"],
)

alias(
    name = "bump_release_rs",
    actual = ":bump-release-rs",
    visibility = ["//apps/web/backstage:__subpackages__"],
)

alias(
    name = "bump-release",
    actual = ":bump-release-rs",
    visibility = ["//apps/web/backstage:__subpackages__"],
)

alias(
    name = "bump_release",
    actual = ":bump-release-rs",
    visibility = ["//apps/web/backstage:__subpackages__"],
)

rust_test(
    name = "bump_release_lib_test",
    size = "small",
    crate = ":bump_release_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/web/backstage:__subpackages__"],
)
