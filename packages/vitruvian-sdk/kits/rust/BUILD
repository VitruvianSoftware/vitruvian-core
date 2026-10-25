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

# The Rust kit, crate vitruvian-tool-kit. Hand-written: Gazelle has no Rust
# here. Its two dependencies, serde and serde_json, come from the crate
# universe @crates, which MODULE.bazel reads from the root Cargo.toml and
# Cargo.lock: this crate is a member of that workspace. The Rust toolchain
# is the hermetic one MODULE.bazel registers, which is also the oldest Rust
# the crate says it builds with (`rust-version` in Cargo.toml).

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

package(default_visibility = ["//packages/vitruvian-sdk:__subpackages__"])

exports_files([
    "Cargo.toml",
    "src/app.rs",
    "src/generated/mod.rs",
])

rust_library(
    name = "vitruvian_tool_kit",
    srcs = glob(["src/**/*.rs"]),
    crate_root = "src/lib.rs",
    edition = "2021",
    # Tools built in this repository link the kit too; who they are is
    # listed in //packages/vitruvian-sdk/consumers, never here.
    visibility = [
        "//packages/vitruvian-sdk:__subpackages__",
        "//packages/vitruvian-sdk/consumers:tools",
    ],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# The Swift kit's ToolTests, ported, against a link of two buffers. It
# starts no process.
rust_test(
    name = "tool_test",
    size = "small",
    srcs = ["tests/tool.rs"],
    edition = "2021",
    deps = [
        ":vitruvian_tool_kit",
        "@crates//:serde_json",
    ],
)

# The generated types against the protocol's files, which the test reads in
# at compile time.
rust_test(
    name = "protocol_test",
    size = "small",
    srcs = ["tests/protocol.rs"],
    compile_data = ["//packages/vitruvian-sdk:protocol_files"],
    edition = "2021",
    deps = [
        ":vitruvian_tool_kit",
        "@crates//:serde_json",
    ],
)
