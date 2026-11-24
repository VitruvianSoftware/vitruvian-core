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

"""Keep tools/testinfra/claude_cli.bzl on the newest Claude Code CLI.

  bazel run //tools/claude-cli-pin:update
  bazel run //tools/claude-cli-pin:update -- --check
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "claude_cli_pin_lib",
    srcs = [
        "src/lib.rs",
        "src/tests.rs",
    ],
    crate_name = "claude_cli_pin",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "update",
    srcs = ["src/main.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":claude_cli_pin_lib"],
)

rust_test(
    name = "claude_cli_pin_lib_test",
    size = "small",
    compile_data = ["//tools/testinfra:claude_cli.bzl"],
    crate = ":claude_cli_pin_lib",
    data = glob(["testdata/**"]),
    edition = "2021",
)
