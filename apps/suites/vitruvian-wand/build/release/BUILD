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

# Builds and publishes a Vitruvian Wand release (src/lib.rs). The release
# workflow runs one part per job:
#
#   bazel run //apps/suites/vitruvian-wand/build/release:publish -- android
#   bazel run //apps/suites/vitruvian-wand/build/release:publish -- linux
#   bazel run //apps/suites/vitruvian-wand/build/release:publish -- macos
#   bazel run //apps/suites/vitruvian-wand/build/release:publish -- expected-assets 0.1.1
#
# Add --dry-run to build and check without uploading.
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/suites/vitruvian-wand:__subpackages__"])

rust_library(
    name = "vitruvian_wand_release_lib",
    srcs = ["src/lib.rs"],
    crate_name = "vitruvian_wand_release_lib",
    edition = "2021",
)

rust_binary(
    name = "publish",
    srcs = ["src/main.rs"],
    args = ["$(rootpath //tools/desktop-package:package-desktop)"],
    data = ["//tools/desktop-package:package-desktop"],
    edition = "2021",
    deps = [":vitruvian_wand_release_lib"],
)

rust_test(
    name = "release_test",
    size = "small",
    crate = ":vitruvian_wand_release_lib",
    data = [
        "//apps/suites/vitruvian-wand:.release-please-manifest.json",
        "//apps/suites/vitruvian-wand:Cargo.lock",
        "//apps/suites/vitruvian-wand:Cargo.toml",
        "//apps/suites/vitruvian-wand:release-please-config.json",
        "//apps/suites/vitruvian-wand:version.bzl",
    ],
    edition = "2021",
    env = {
        "WAND_CARGO_LOCK": "$(rootpath //apps/suites/vitruvian-wand:Cargo.lock)",
        "WAND_CARGO_TOML": "$(rootpath //apps/suites/vitruvian-wand:Cargo.toml)",
        "WAND_MANIFEST": "$(rootpath //apps/suites/vitruvian-wand:.release-please-manifest.json)",
        "WAND_RELEASE_CONFIG": "$(rootpath //apps/suites/vitruvian-wand:release-please-config.json)",
        "WAND_VERSION_BZL": "$(rootpath //apps/suites/vitruvian-wand:version.bzl)",
    },
)
