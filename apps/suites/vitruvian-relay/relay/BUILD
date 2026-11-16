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
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The relay server: device registry and call routing, MCP over Streamable HTTP
# for AI apps, device registration, and the /connect WebSocket.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

_CRATES = [
    "//apps/suites/vitruvian-relay/protocol:vitruvian_relay_protocol",
    "//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth",
    "@vitruvian_relay_crates//:base64",
    "@vitruvian_relay_crates//:bytes",
    "@vitruvian_relay_crates//:futures-util",
    "@vitruvian_relay_crates//:http",
    "@vitruvian_relay_crates//:http-body-util",
    "@vitruvian_relay_crates//:hyper",
    "@vitruvian_relay_crates//:hyper-util",
    "@vitruvian_relay_crates//:ring",
    "@vitruvian_relay_crates//:serde",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:tokio",
    "@vitruvian_relay_crates//:tokio-tungstenite",
]

rust_library(
    name = "vitruvian_relay",
    srcs = [
        "src/config.rs",
        "src/devices.rs",
        "src/http.rs",
        "src/http_tests.rs",
        "src/lib.rs",
        "src/mcp.rs",
        "src/registry.rs",
    ],
    crate_name = "vitruvian_relay",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _CRATES,
)

# The server. `--version` prints the version and exits 0 (the image workflow
# runs it to check the image).
rust_binary(
    name = "vitruvian-relay",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    edition = "2021",
    deps = [
        ":vitruvian_relay",
        "//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth",
        "@vitruvian_relay_crates//:serde_json",
        "@vitruvian_relay_crates//:tokio",
    ],
)

rust_test(
    name = "vitruvian_relay_test",
    size = "small",
    crate = ":vitruvian_relay",
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_relay_test"],
)

pipeline_unit(
    name = "vitruvian-relay",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
