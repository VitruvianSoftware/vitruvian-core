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

"""Go `encoding/json`-compatible serializer, scanner, parser, and decoder on top of serde_json."""

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "vitruvian_gojson",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "vitruvian_gojson",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        "//packages/gocompat:vitruvian_gocompat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "vitruvian_gojson_test",
    size = "small",
    crate = ":vitruvian_gojson",
    data = ["//packages/gocompat/gojson/testdata/goparity:fixture.txt"],
    rustc_flags = ["-Copt-level=3"],
)
