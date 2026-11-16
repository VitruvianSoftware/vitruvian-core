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
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# vrelay, the connector that runs on the Mac: sign-in, the device key, token
# refresh, the rules, the bridge to desktop-commander, and (in later tasks)
# the WebSocket link. `bazel run
# //apps/suites/vitruvian-relay/connector:vrelay -- <command>`.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

_CRATES = [
    "//apps/suites/vitruvian-relay/protocol:vitruvian_relay_protocol",
    "@vitruvian_relay_crates//:base64",
    "@vitruvian_relay_crates//:libc",
    "@vitruvian_relay_crates//:ring",
    "@vitruvian_relay_crates//:rustls",
    "@vitruvian_relay_crates//:rustls-native-certs",
    "@vitruvian_relay_crates//:serde",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:tokio",
    "@vitruvian_relay_crates//:toml",
    "@vitruvian_relay_crates//:ureq",
]

rust_library(
    name = "vitruvian_relay_connector",
    srcs = [
        "src/auth.rs",
        "src/bridge.rs",
        "src/config.rs",
        "src/keys.rs",
        "src/lib.rs",
        "src/prompt.rs",
        "src/rules.rs",
        "src/state.rs",
        "src/status.rs",
    ],
    crate_name = "vitruvian_relay_connector",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _CRATES,
)

# Under `bazel run` the pinned desktop-commander comes from the runfiles
# (bridge.rs, `BridgeCommand::locate`); an installed vrelay reads bridge.json.
rust_binary(
    name = "vrelay",
    srcs = ["src/main.rs"],
    crate_root = "src/main.rs",
    data = ["//apps/suites/vitruvian-relay/connector/dc:desktop_commander"],
    edition = "2021",
    deps = [
        ":vitruvian_relay_connector",
        "@vitruvian_relay_crates//:serde_json",
        "@vitruvian_relay_crates//:tokio",
    ],
)

# A tiny stand-in MCP server for the bridge tests.
sh_binary(
    name = "fake_mcp",
    testonly = True,
    srcs = ["testdata/fake_mcp.sh"],
)

rust_test(
    name = "vitruvian_relay_connector_test",
    size = "small",
    crate = ":vitruvian_relay_connector",
    data = [
        "testdata/dc-0.3.1-tools.json",
        ":fake_mcp",
        "//apps/suites/vitruvian-relay/connector/dc:package.json",
    ],
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_relay_connector_test"],
)

pipeline_unit(
    name = "vrelay",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [":unit_tests"],
    tier = "L1",
    timeout_minutes = 15,
)
