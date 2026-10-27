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

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "metrics_rs",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_remote_macagent_metrics",
    crate_root = "src/lib.rs",
    edition = "2021",
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

alias(
    name = "metrics",
    actual = ":metrics_rs",
    visibility = ["//apps/mobile/android-remote:__subpackages__"],
)

rust_test(
    name = "metrics_rs_test",
    crate = ":metrics_rs",
    data = glob(["testdata/**"]),
    edition = "2021",
)

test_suite(
    name = "metrics_test",
    tests = [":metrics_rs_test"],
)
