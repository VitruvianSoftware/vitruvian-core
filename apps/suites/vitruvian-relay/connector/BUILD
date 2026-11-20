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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_clippy", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# vrelay, the connector that runs on the Mac: sign-in, the device key, token
# refresh, the rules, the bridge to desktop-commander, and the WebSocket link
# (`vrelay run`). `bazel run
# //apps/suites/vitruvian-relay/connector:vrelay -- <command>`.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

_CRATES = [
    "//apps/suites/vitruvian-relay/protocol:vitruvian_relay_protocol",
    "//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth",
    "@vitruvian_relay_crates//:base64",
    "@vitruvian_relay_crates//:futures-util",
    "@vitruvian_relay_crates//:libc",
    "@vitruvian_relay_crates//:ring",
    "@vitruvian_relay_crates//:rustls",
    "@vitruvian_relay_crates//:serde",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:tokio",
    "@vitruvian_relay_crates//:tokio-tungstenite",
    "@vitruvian_relay_crates//:toml",
    "@vitruvian_relay_crates//:ureq",
]

# The login Keychain (secrets.rs), on a Mac only; Linux CI keeps secrets in files.
_MACOS_CRATES = select({
    "@platforms//os:macos": ["@vitruvian_relay_crates//:security-framework"],
    "//conditions:default": [],
})

rust_library(
    name = "vitruvian_relay_connector",
    srcs = [
        "src/auth.rs",
        "src/awake.rs",
        "src/bridge.rs",
        "src/config.rs",
        "src/keys.rs",
        "src/lib.rs",
        "src/link.rs",
        "src/link_tests.rs",
        "src/proc.rs",
        "src/prompt.rs",
        "src/rules.rs",
        "src/secrets.rs",
        "src/state.rs",
        "src/status.rs",
    ],
    crate_name = "vitruvian_relay_connector",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = _CRATES + _MACOS_CRATES,
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
    # The bridge tests start real processes; medium leaves room on a slow
    # one-CPU executor.
    size = "medium",
    crate = ":vitruvian_relay_connector",
    data = [
        "testdata/dc-0.3.1-tools.json",
        ":fake_mcp",
        "//apps/suites/vitruvian-relay/connector/dc:package.json",
        "//apps/suites/vitruvian-relay/connector/dc:pnpm-lock.yaml",
        "//apps/suites/vitruvian-relay/relay:deploy/chart/values.yaml",
        "//gitops/argocd/platform/relay:values.yaml",
    ],
)

# The Keychain store against the real login Keychain, by hand on a Mac
# (`bazel test //apps/suites/vitruvian-relay/connector:keychain_test`): CI's
# Linux runners have none, so it is `manual`. It runs outside the sandbox,
# which cannot reach the Keychain, under its own service names. It needs the
# real HOME and USER: without them the Keychain finds no default keychain and
# waits on a "Keychain Not Found" dialog until the test times out.
rust_test(
    name = "keychain_test",
    srcs = ["tests/keychain.rs"],
    edition = "2021",
    env_inherit = [
        "HOME",
        "USER",
    ],
    tags = [
        "local",
        "manual",
        "no-sandbox",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":vitruvian_relay_connector"],
)

# The lock's pin and checksum are checked offline in the Rust tests. Building
# the package from its lock (a ~600-package fetch) is dc/'s own unit, so it
# runs only when dc/ changes.
# Clippy over the code and its tests; a lint error fails the unit.
rust_clippy(
    name = "vrelay_clippy",
    testonly = True,
    deps = [
        ":vitruvian_relay_connector",
        ":vitruvian_relay_connector_test",
        ":vrelay",
    ] + select({
        # keychain_test builds on a Mac only (a manual target).
        "@platforms//os:macos": [":keychain_test"],
        "//conditions:default": [],
    }),
)

test_suite(
    name = "unit_tests",
    tests = [":vitruvian_relay_connector_test"],
)

pipeline_unit(
    name = "vrelay",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":unit_tests",
        ":vrelay_clippy",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
