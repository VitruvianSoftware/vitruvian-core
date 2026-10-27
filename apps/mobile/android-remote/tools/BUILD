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

# Test helpers for //mobile/android/remote. Its own package so the app package's
# glob(["src/main/kotlin/**/*.kt"]) never sweeps a shell script in, and so the
# script is exportable to the sh_test next door.
#
# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//apps/mobile/android-remote:__subpackages__"])

exports_files(["src/boot_smoke_main.rs"])

rust_library(
    name = "android_remote_tools_lib",
    srcs = [
        "src/boot_smoke.rs",
        "src/lib.rs",
        "src/publish.rs",
    ],
    crate_name = "android_remote_tools_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "publish-rs",
    srcs = ["src/publish_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":android_remote_tools_lib"],
)

rust_binary(
    name = "boot-smoke-rs",
    srcs = ["src/boot_smoke_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":android_remote_tools_lib"],
)

rust_test(
    name = "android_remote_tools_lib_test",
    size = "small",
    crate = ":android_remote_tools_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
