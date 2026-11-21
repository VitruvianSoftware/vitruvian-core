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
]

rust_library(
    name = "vitruvian_relay",
    srcs = [
        "src/config.rs",
        "src/devices.rs",
        "src/http.rs",
        "src/http_tests.rs",
        "src/legacy_devices.rs",
        "src/lib.rs",
        "src/mcp.rs",
        "src/parked.rs",
        "src/ratelimit.rs",
        "src/registry.rs",
        "src/store.rs",
        "src/store_contract.rs",
    ],
    # The schema, compiled into the binary (src/store.rs include_str!s it).
    compile_data = glob(["migrations/*.sql"]),
    crate_name = "vitruvian_relay",
    crate_root = "src/lib.rs",
    edition = "2021",
    proc_macro_deps = ["@vitruvian_relay_crates//:async-trait"],
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
    ],
    crate_root = "tests/database_down.rs",
    edition = "2021",
    tags = ["manual"],
    deps = _PG_TEST_DEPS + [
        "//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth",
        "@vitruvian_relay_crates//:base64",
        "@vitruvian_relay_crates//:bytes",
        "@vitruvian_relay_crates//:http",
        "@vitruvian_relay_crates//:http-body-util",
        "@vitruvian_relay_crates//:hyper",
        "@vitruvian_relay_crates//:hyper-util",
        "@vitruvian_relay_crates//:ring",
    ],
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
