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

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/doctor:defs.bzl", "doctor")

package(default_visibility = ["//apps/mobile/wearos:__subpackages__"])

exports_files([
    "CHANGELOG.md",
    "release-please-config.json",
])

sh_binary(
    name = "publish",
    srcs = ["scripts/publish.sh"],
)

sh_binary(
    name = "install_all",
    srcs = ["scripts/install_all.sh"],
)

rust_library(
    name = "wearos_apps_scripts_lib",
    srcs = [
        "scripts/src/install_all.rs",
        "scripts/src/lib.rs",
        "scripts/src/publish.rs",
    ],
    crate_name = "wearos_apps_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "install-all-rs",
    srcs = ["scripts/src/install_all_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":wearos_apps_scripts_lib"],
)

rust_binary(
    name = "publish-rs",
    srcs = ["scripts/src/publish_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":wearos_apps_scripts_lib"],
)

rust_test(
    name = "wearos_apps_scripts_lib_test",
    size = "small",
    crate = ":wearos_apps_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

doctor(
    name = "doctor",
    label = "wearos-apps (Vitruvian Wear OS Apps Suite)",
    required = [
        "bazel",
        "git",
    ],
)
