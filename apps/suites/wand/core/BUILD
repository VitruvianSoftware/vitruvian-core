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

load("@rules_rust//rust:defs.bzl", "rust_lint_config")
load(
    "//apps/suites/wand/build:defs.bzl",
    "wand_rust_clippy",
    "wand_rust_library",
    "wand_rust_test",
)

package(default_visibility = ["//apps/suites/wand:__subpackages__"])

exports_files([
    "Cargo.toml",
])

rust_lint_config(
    name = "wand_core_lints",
    clippy = {
        "all": "deny",
        "chunks_exact_to_as_chunks": "allow",
        "field_reassign_with_default": "allow",
        "neg_multiply": "allow",
    },
)

wand_rust_library(
    name = "wand_core",
    srcs = glob(["src/**/*.rs"]),
    crate_name = "wand_core",
    crate_root = "src/lib.rs",
    edition = "2021",
    lint_config = ":wand_core_lints",
    deps = [
        "@wand_crates//:serde",
        "@wand_crates//:serde_json",
    ],
)

wand_rust_test(
    name = "wand_core_unit_test",
    size = "small",
    compile_data = glob(["testdata/**"]),
    crate = ":wand_core",
    edition = "2021",
    lint_config = ":wand_core_lints",
    deps = [
        "@wand_crates//:serde",
        "@wand_crates//:serde_json",
    ],
)

wand_rust_test(
    name = "integration_test",
    size = "small",
    srcs = glob(["tests/**/*.rs"]),
    compile_data = glob(["testdata/**"]),
    edition = "2021",
    lint_config = ":wand_core_lints",
    deps = [
        ":wand_core",
        "@wand_crates//:serde",
        "@wand_crates//:serde_json",
    ],
)

wand_rust_clippy(
    name = "wand_core_clippy",
    testonly = True,
    deps = [
        ":integration_test",
        ":wand_core",
    ],
)
