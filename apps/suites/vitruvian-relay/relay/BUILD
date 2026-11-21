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

load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_clippy", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The relay server: device registry and call routing, MCP over Streamable HTTP
# for AI apps, device registration, and the /connect WebSocket.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

# The chart defaults (hostname, issuer) that the connector's
# defaults_match_relay_stack test compares with its compiled-in ones.
exports_files(
    ["deploy/chart/values.yaml"],
    visibility = ["//apps/suites/vitruvian-relay/connector:__pkg__"],
)

_CRATES = [
    "//apps/suites/vitruvian-relay/protocol:vitruvian_relay_protocol",
    "//packages/mcp-auth:vitruvian_mcp_auth",
    "@vitruvian_relay_crates//:base64",
    "@vitruvian_relay_crates//:bytes",
    "@vitruvian_relay_crates//:deadpool-postgres",
    "@vitruvian_relay_crates//:futures-util",
    "@vitruvian_relay_crates//:http",
    "@vitruvian_relay_crates//:http-body-util",
    "@vitruvian_relay_crates//:hyper",
    "@vitruvian_relay_crates//:hyper-util",
    "@vitruvian_relay_crates//:ring",
    "@vitruvian_relay_crates//:rustls",
    "@vitruvian_relay_crates//:rustls-native-certs",
    "@vitruvian_relay_crates//:serde",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:tokio",
    "@vitruvian_relay_crates//:tokio-postgres",
    "@vitruvian_relay_crates//:tokio-postgres-rustls",
    "@vitruvian_relay_crates//:tokio-tungstenite",
    "@vitruvian_relay_crates//:ureq",
]

_LIB_SRCS = [
    "src/config.rs",
    "src/dashboard/mod.rs",
    "src/dashboard/pages.rs",
    "src/dashboard/session.rs",
    "src/dashboard/tests.rs",
    "src/devices.rs",
    "src/http.rs",
    "src/http_tests.rs",
    "src/lib.rs",
    "src/mcp.rs",
    "src/parked.rs",
    "src/ratelimit.rs",
    "src/registry.rs",
    "src/store.rs",
    "src/store_contract.rs",
]

# The schema (src/store.rs include_str!s it) and the dashboard's stylesheet
# (src/dashboard/mod.rs), compiled into the binary.
_LIB_COMPILE_DATA = glob(["migrations/*.sql"]) + ["src/dashboard/relay.css"]

rust_library(
    name = "vitruvian_relay",
    srcs = _LIB_SRCS,
    compile_data = _LIB_COMPILE_DATA,
    crate_name = "vitruvian_relay",
    crate_root = "src/lib.rs",
    edition = "2021",
    proc_macro_deps = ["@vitruvian_relay_crates//:async-trait"],
    # `relay_broken_ownership` (App::owned_device) and
    # `relay_broken_request_ownership` (Mcp::owned_request) are the canaries'
    # cfgs and are never set here; naming them keeps rustc from calling them
    # typos. Once any --check-cfg is given, rules_rust's build no longer knows
    # `test` on its own, so that is named too.
    rustc_flags = [
        "--check-cfg=cfg(relay_broken_ownership)",
        "--check-cfg=cfg(relay_broken_request_ownership)",
        "--check-cfg=cfg(test)",
    ],
    deps = _CRATES,
)

# The canaries' relays: the same sources with one ownership check deliberately
# broken each. This one breaks the device check (`App::owned_device` returns a
# device whatever the subject). Only the isolation canary test is built on it,
# and it must never be linked into anything that ships.
rust_library(
    name = "vitruvian_relay_broken_ownership",
    testonly = True,
    srcs = _LIB_SRCS,
    compile_data = _LIB_COMPILE_DATA,
    crate_name = "vitruvian_relay",
    crate_root = "src/lib.rs",
    edition = "2021",
    proc_macro_deps = ["@vitruvian_relay_crates//:async-trait"],
    rustc_flags = ["--cfg=relay_broken_ownership"],
    tags = ["manual"],
    visibility = ["//visibility:private"],
    deps = _CRATES,
)

# And this one breaks the request check (`Mcp::owned_request` returns a
# request whoever it belongs to). Same rules.
rust_library(
    name = "vitruvian_relay_broken_request_ownership",
    testonly = True,
    srcs = _LIB_SRCS,
    compile_data = _LIB_COMPILE_DATA,
    crate_name = "vitruvian_relay",
    crate_root = "src/lib.rs",
    edition = "2021",
    proc_macro_deps = ["@vitruvian_relay_crates//:async-trait"],
    rustc_flags = ["--cfg=relay_broken_request_ownership"],
    tags = ["manual"],
    visibility = ["//visibility:private"],
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
        "//packages/mcp-auth:vitruvian_mcp_auth",
        "@vitruvian_relay_crates//:serde_json",
        "@vitruvian_relay_crates//:tokio",
    ],
)

# --- Tests against a real Postgres (rules_itest) ----------------------------
#
# A throwaway Postgres on a loopback port the test reads from ASSIGNED_PORTS,
# the same service the tabs API's tests use. Each test makes its own database
# in it, so tests do not see each other's rows.
itest_service(
    name = "postgres",
    args = [
        "$(rootpath //tools/testinfra:pg_initdb_bin)",
        "$(rootpath //tools/testinfra:pg_postgres_bin)",
        "$${PORT}",
        "$${TMPDIR}",
    ],
    autoassign_port = True,
    data = [
        "//tools/testinfra:pg_initdb_bin",
        "//tools/testinfra:pg_isready_bin",
        "//tools/testinfra:pg_postgres_bin",
    ],
    exe = "//tools/testinfra/postgres:run_postgres",
    health_check = "//tools/testinfra/postgres:check_postgres",
    health_check_args = [
        "$(rootpath //tools/testinfra:pg_isready_bin)",
        "$${PORT}",
    ],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
)

_PG_TEST_DEPS = [
    ":vitruvian_relay",
    "@vitruvian_relay_crates//:serde_json",
    "@vitruvian_relay_crates//:tokio",
    "@vitruvian_relay_crates//:tokio-postgres",
]

# What the tests that run the whole relay over HTTP (tests/relay_support.rs)
# use besides the library itself.
_RELAY_OVER_HTTP_TEST_DEPS = [
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
    "@vitruvian_relay_crates//:tokio-tungstenite",
]

# The store contract on PostgreSQL (the same checks the unit test runs on the
# in-memory store), the migrations, and the TLS default. Run through
# :store_pg_test, which starts the database; on its own it has none.
rust_test(
    name = "store_pg_itest_bin",
    size = "small",
    srcs = [
        "tests/pg_support.rs",
        "tests/store_pg.rs",
    ],
    crate_root = "tests/store_pg.rs",
    edition = "2021",
    tags = ["manual"],
    deps = _PG_TEST_DEPS,
)

service_test(
    name = "store_pg_test",
    size = "medium",
    services = [":postgres"],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    test = ":store_pg_itest_bin",
)

# The database going away and coming back, with the whole relay over HTTP: a
# small TCP proxy between the store and the itest Postgres is cut and restored.
rust_test(
    name = "database_down_itest_bin",
    size = "small",
    srcs = [
        "tests/database_down.rs",
        "tests/pg_support.rs",
        "tests/relay_support.rs",
    ],
    crate_root = "tests/database_down.rs",
    edition = "2021",
    tags = ["manual"],
    deps = _PG_TEST_DEPS + _RELAY_OVER_HTTP_TEST_DEPS,
)

service_test(
    name = "database_down_test",
    size = "medium",
    services = [":postgres"],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    test = ":database_down_itest_bin",
)

# Tenant isolation (spec 7.4, tests/isolation.rs): two people, each with two
# computers, and nothing one can ask reaches or reveals the other's. The same
# sources are built three times. `:vitruvian_relay_isolation_test` runs them
# against the relay as it is and must pass. The two canaries run them against
# a relay with one ownership check deliberately broken, through
# expect_failure.sh, and pass only if the tests that exist to notice that break
# fail there (a check that cannot fail proves nothing):
#   `:vitruvian_relay_isolation_canary_test`          the device check
#   `:vitruvian_relay_isolation_request_canary_test`  the request check
_ISOLATION_SRCS = [
    "tests/isolation.rs",
    "tests/pg_support.rs",
    "tests/relay_support.rs",
]

rust_test(
    name = "isolation_itest_bin",
    size = "small",
    srcs = _ISOLATION_SRCS,
    crate_root = "tests/isolation.rs",
    edition = "2021",
    tags = ["manual"],
    deps = _PG_TEST_DEPS + _RELAY_OVER_HTTP_TEST_DEPS,
)

rust_test(
    name = "isolation_canary_itest_bin",
    size = "small",
    srcs = _ISOLATION_SRCS,
    crate_root = "tests/isolation.rs",
    edition = "2021",
    tags = ["manual"],
    deps = [
        d
        for d in _PG_TEST_DEPS
        if d != ":vitruvian_relay"
    ] + [":vitruvian_relay_broken_ownership"] + _RELAY_OVER_HTTP_TEST_DEPS,
)

service_test(
    name = "vitruvian_relay_isolation_test",
    size = "medium",
    services = [":postgres"],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    test = ":isolation_itest_bin",
)

rust_test(
    name = "isolation_request_canary_itest_bin",
    size = "small",
    srcs = _ISOLATION_SRCS,
    crate_root = "tests/isolation.rs",
    edition = "2021",
    tags = ["manual"],
    deps = [
        d
        for d in _PG_TEST_DEPS
        if d != ":vitruvian_relay"
    ] + [":vitruvian_relay_broken_request_ownership"] + _RELAY_OVER_HTTP_TEST_DEPS,
)

# Run a broken build's isolation tests and pass only if the tests listed in
# EXPECT_FAILURE_REQUIRED fail (and some other test passes). Not `args`:
# service_test starts its test without any, but does pass the test's
# environment on.
sh_test(
    name = "isolation_canary_runner",
    size = "small",
    srcs = ["tests/expect_failure.sh"],
    data = [":isolation_canary_itest_bin"],
    env = {
        "EXPECT_FAILURE_BINARY": "$(rootpath :isolation_canary_itest_bin)",
        "EXPECT_FAILURE_PREFIX": "isolation::",
        # The tests that look at someone else's computer.
        "EXPECT_FAILURE_REQUIRED": " ".join([
            "isolation::mcp_initialize_tools_list_and_call_on_bobs_device",
            "isolation::dashboard_device_page_rename_remove_for_bobs_device",
            "isolation::hello_with_bobs_device_id",
            "isolation::check_request_on_bobs_device_endpoint",
        ]),
    },
    tags = ["manual"],
)

sh_test(
    name = "isolation_request_canary_runner",
    size = "small",
    srcs = ["tests/expect_failure.sh"],
    data = [":isolation_request_canary_itest_bin"],
    env = {
        "EXPECT_FAILURE_BINARY": "$(rootpath :isolation_request_canary_itest_bin)",
        "EXPECT_FAILURE_PREFIX": "isolation::",
        # The test that asks for someone else's request by id.
        "EXPECT_FAILURE_REQUIRED": "isolation::check_request_with_bobs_request_id",
    },
    tags = ["manual"],
)

service_test(
    name = "vitruvian_relay_isolation_canary_test",
    size = "medium",
    services = [":postgres"],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    test = ":isolation_canary_runner",
)

service_test(
    name = "vitruvian_relay_isolation_request_canary_test",
    size = "medium",
    services = [":postgres"],
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    test = ":isolation_request_canary_runner",
)

rust_test(
    name = "vitruvian_relay_test",
    size = "small",
    crate = ":vitruvian_relay",
)

# The real relay against the real connector (tests/e2e.rs): the relay's App
# on a loopback port, the connector's Link dialling it, an AI app over MCP.
# VRELAY_SECRETS=file: the connector's device key and sign-in go in the test's
# own folder, never into the login Keychain's real items.
rust_test(
    name = "vitruvian_relay_e2e_test",
    size = "medium",
    srcs = ["tests/e2e.rs"],
    edition = "2021",
    env = {"VRELAY_SECRETS": "file"},
    deps = [
        ":vitruvian_relay",
        "//apps/suites/vitruvian-relay/connector:vitruvian_relay_connector",
        "//apps/suites/vitruvian-relay/protocol:vitruvian_relay_protocol",
        "//packages/mcp-auth:vitruvian_mcp_auth",
        "@vitruvian_relay_crates//:base64",
        "@vitruvian_relay_crates//:bytes",
        "@vitruvian_relay_crates//:http",
        "@vitruvian_relay_crates//:http-body-util",
        "@vitruvian_relay_crates//:hyper",
        "@vitruvian_relay_crates//:hyper-util",
        "@vitruvian_relay_crates//:ring",
        "@vitruvian_relay_crates//:serde_json",
        "@vitruvian_relay_crates//:tokio",
    ],
)

# Clippy over the code and its tests; a lint error fails the unit.
rust_clippy(
    name = "vitruvian_relay_clippy",
    testonly = True,
    deps = [
        ":database_down_itest_bin",
        ":isolation_canary_itest_bin",
        ":isolation_itest_bin",
        ":isolation_request_canary_itest_bin",
        ":store_pg_itest_bin",
        ":vitruvian-relay",
        ":vitruvian_relay",
        ":vitruvian_relay_e2e_test",
        ":vitruvian_relay_test",
    ],
)

test_suite(
    name = "unit_tests",
    tests = [
        ":vitruvian_relay_e2e_test",
        ":vitruvian_relay_test",
    ],
)

# The tests that need the Postgres service.
test_suite(
    name = "postgres_tests",
    tests = [
        ":database_down_test",
        ":store_pg_test",
        ":vitruvian_relay_isolation_canary_test",
        ":vitruvian_relay_isolation_request_canary_test",
        ":vitruvian_relay_isolation_test",
    ],
)

pipeline_unit(
    name = "vitruvian-relay",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":unit_tests",
        ":postgres_tests",
        ":vitruvian_relay_clippy",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
