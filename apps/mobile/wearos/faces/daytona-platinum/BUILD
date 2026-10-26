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

# //apps/mobile/wearos/faces/daytona-platinum: Rolex Cosmograph Daytona Platinum
# (Ref. 126506) Declarative Watch Face Format (WFF) package for Pixel Watch 4.
#
# gazelle:ignore

load("@rules_python//python:defs.bzl", "py_binary")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pytest:defs.bzl", "py_test")

package(default_visibility = ["//apps/mobile/wearos:__subpackages__"])

exports_files([
    "BUILD",
    "release-please-config.json",
])

# `bazel run :generate_assets` re-renders src/main/res/drawable-nodpi.
#
# The default is the Rust port in src/ (std only, no crates). Like the
# Python, it builds one SVG per asset and rasterises it with rsvg-convert
# (librsvg, from PATH or /opt/homebrew/bin), so both need librsvg on the
# host. The Python stays as :generate_assets_py until the port has run in
# anger; :generate_assets_rs_parity_test holds the two to the same output.
rust_library(
    name = "generate_assets_lib",
    srcs = ["src/lib.rs"],
    crate_name = "generate_assets",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "generate_assets",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":generate_assets_lib"],
)

alias(
    name = "generate_assets_rs",
    actual = ":generate_assets",
)

py_binary(
    name = "generate_assets_py",
    srcs = ["scripts/generate_assets.py"],
    main = "scripts/generate_assets.py",
)

# The #[cfg(test)] unit tests in src/lib.rs.
rust_test(
    name = "generate_assets_lib_test",
    size = "small",
    crate = ":generate_assets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# :generate_assets_py and :generate_assets side by side: the SVG each hands
# to rsvg-convert must match byte for byte, every PNG must decode to the same
# size and RGBA pixels, and the command lines and exit codes must hold. The
# pixel half needs rsvg-convert on the host and skips (saying so) without it.
py_test(
    name = "generate_assets_rs_parity_test",
    size = "medium",
    srcs = ["generate_assets_rs_parity_test.py"],
    data = [
        ":generate_assets",
        ":generate_assets_py",
    ],
    env = {
        "GENERATE_ASSETS_PY": "$(rootpath :generate_assets_py)",
        "GENERATE_ASSETS_RS": "$(rootpath :generate_assets)",
    },
)

filegroup(
    name = "wff_sources",
    srcs = glob([
        "src/main/AndroidManifest.xml",
        "src/main/res/**",
    ]),
)

py_test(
    name = "watchface_test",
    srcs = ["watchface_test.py"],
    data = [":wff_sources"],
)

sh_binary(
    name = "build_apk",
    srcs = ["scripts/build_wff_apk.sh"],
    data = [":wff_sources"],
)

sh_binary(
    name = "install",
    srcs = ["scripts/install.sh"],
    data = [
        "scripts/build_wff_apk.sh",
        ":wff_sources",
    ],
)

sh_binary(
    name = "publish",
    srcs = ["scripts/publish.sh"],
    data = [
        ".release-please-manifest.json",
        "scripts/build_wff_apk.sh",
        ":wff_sources",
    ],
)

rust_library(
    name = "daytona_scripts_lib",
    srcs = [
        "scripts/src/build_wff_apk.rs",
        "scripts/src/install.rs",
        "scripts/src/lib.rs",
        "scripts/src/publish.rs",
    ],
    crate_name = "daytona_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "build-apk-rs",
    srcs = ["scripts/src/build_wff_apk_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":daytona_scripts_lib"],
)

rust_binary(
    name = "install-rs",
    srcs = ["scripts/src/install_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":daytona_scripts_lib"],
)

rust_binary(
    name = "publish-rs",
    srcs = ["scripts/src/publish_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":daytona_scripts_lib"],
)

rust_test(
    name = "daytona_scripts_lib_test",
    size = "small",
    crate = ":daytona_scripts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

doctor(
    name = "doctor",
    label = "daytona-platinum (Wear OS Watch Face)",
    required = [
        "bazel",
        "git",
    ],
)
