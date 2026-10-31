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
    name = "unitfile_lib",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "unitfile",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//tools/pipeline:__subpackages__"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "unitfile_test",
    size = "small",
    crate = ":unitfile_lib",
    data = [":real_units"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "unitfile_lib_test",
    tests = [":unitfile_test"],
)

# Every BUILD file in the repo that declared a pipeline_unit when the Rust
# port was written, as <path with / as __>.txt.
filegroup(
    name = "real_units",
    srcs = glob(["testdata/real_units/*"]),
    visibility = ["//tools/pipeline:__subpackages__"],
)
