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

load("@aspect_rules_js//js:defs.bzl", "js_binary")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_itest//:itest.bzl", "itest_service", "itest_task", "port", "service_test")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load", "oci_push")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@tar.bzl", "tar")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# @tabula/api: Native Rust API server + Prisma migration tooling.
# gazelle:ignore
# gazelle:exclude prisma
# gazelle:exclude rs

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//apps/suites/tabula:__subpackages__"])

npm_link_all_packages(name = "node_modules")

rust_library(
    name = "tabula_api_tools_rs_lib",
    srcs = [
        "rs/src/auth_lib.rs",
        "rs/src/crypto.rs",
        "rs/src/device.rs",
        "rs/src/errors.rs",
        "rs/src/ids.rs",
        "rs/src/lib.rs",
        "rs/src/migration_guard.rs",
        "rs/src/presence.rs",
        "rs/src/scanner_reject.rs",
        "rs/src/schemas.rs",
        "rs/src/secrets.rs",
        "rs/src/server.rs",
        "rs/src/services.rs",
        "rs/src/store.rs",
        "rs/src/sync_events.rs",
        "rs/src/tests_integration.rs",
        "rs/src/tests_unit.rs",
        "rs/src/tiers.rs",
        "rs/src/tombstones.rs",
        "rs/src/workos.rs",
    ],
    crate_name = "tabula_api_tools_rs_lib",
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "api_bin",
    srcs = ["rs/src/bin/server.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [":tabula_api_tools_rs_lib"],
)

rust_binary(
    name = "prisma-client-gen-rs",
    srcs = ["rs/src/bin/generate_client.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":tabula_api_tools_rs_lib"],
)

rust_binary(
    name = "migrate-deploy-rs",
    srcs = ["rs/src/bin/migrate_deploy.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [":tabula_api_tools_rs_lib"],
)

rust_binary(
    name = "seed-test-user-rs",
    srcs = ["rs/src/bin/seed_test_user.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [":tabula_api_tools_rs_lib"],
)

alias(
    name = "seed_test_user_bin",
    actual = ":seed-test-user-rs",
    visibility = ["//apps/suites/tabula:__subpackages__"],
)

rust_test(
    name = "tabula_api_tools_rs_test",
    size = "small",
    crate = ":tabula_api_tools_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "integration_tests",
    size = "small",
    crate = ":tabula_api_tools_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

# --- Hermetic E2E & migration stack (rules_itest) ----------------------------

genrule(
    name = "schema_engine",
    srcs = select({
        "//tools/testinfra:darwin_amd64": ["@prisma_schema_engine_darwin_arm64_gz//file"],
        "//tools/testinfra:darwin_arm64": ["@prisma_schema_engine_darwin_arm64_gz//file"],
        "//tools/testinfra:linux_amd64": ["@prisma_schema_engine_linux_gz//file"],
        "//tools/testinfra:linux_arm64": ["@prisma_schema_engine_linux_gz//file"],
    }),
    outs = ["schema-engine"],
    cmd = "gunzip -c $< > $@ && chmod +x $@",
    executable = True,
)

js_binary(
    name = "migrate_deploy_bin",
    data = [
        "prisma.config.ts",
        "prisma/engine-placeholder",
        "prisma/schema.prisma",
        ":node_modules/prisma",
    ] + glob(["prisma/migrations/**"]),
    entry_point = "prisma/migrate-deploy.cjs",
    visibility = ["//apps/suites/tabula:__subpackages__"],
)

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
    visibility = ["//apps/suites/tabula:__subpackages__"],
)

itest_service(
    name = "redis",
    args = [
        "--port",
        "$${PORT}",
        "--bind",
        "127.0.0.1",
        "--dir",
        "$${TMPDIR}",
    ],
    autoassign_port = True,
    exe = "@redis//:redis-server",
    health_check = "@redis//:redis-cli",
    health_check_args = [
        "-h",
        "127.0.0.1",
        "-p",
        "$${PORT}",
        "PING",
    ],
    visibility = ["//apps/suites/tabula:__subpackages__"],
)

service_test(
    name = "redis_loopback_test",
    size = "small",
    env = {"ITEST_SERVICE_LABEL": "@@//apps/suites/tabula/api:redis"},
    services = [":redis"],
    test = "//tools/testinfra/redis:check_loopback",
)

itest_task(
    name = "migrate",
    data = [
        "prisma/engine-placeholder",
        ":schema_engine",
    ],
    env = {
        "DATABASE_URL": "postgresql://postgres@127.0.0.1:" + port(":postgres") + "/postgres",
        "PRISMA_QUERY_ENGINE_LIBRARY": "$(rootpath prisma/engine-placeholder)",
        "PRISMA_SCHEMA_ENGINE_BINARY": "$(rootpath :schema_engine)",
    },
    exe = ":migrate_deploy_bin",
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [":postgres"],
)

itest_task(
    name = "seed_e2e_user",
    env = {
        "DATABASE_URL": "postgresql://postgres@127.0.0.1:" + port(":postgres") + "/postgres",
        "JWT_SECRET": "e2e-test-jwt-secret-key",
    },
    exe = ":seed_test_user_bin",
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [":migrate"],
)

itest_service(
    name = "api_service",
    env = {
        "DATABASE_URL": "postgresql://postgres@127.0.0.1:" + port(":postgres") + "/postgres",
        "HOST": "127.0.0.1",
        "JWT_REFRESH_SECRET": "e2e-test-refresh-secret-key",
        "JWT_SECRET": "e2e-test-jwt-secret-key",
        "NODE_ENV": "test",
        "PORT": "8080",
        "RATE_LIMIT_MAX": "100000",
        "REDIS_URL": "redis://127.0.0.1:" + port(":redis"),
        "WORKOS_API_KEY": "sk_test_e2e_dummy",
        "WORKOS_CLIENT_ID": "client_e2e_dummy",
    },
    exe = ":api_bin",
    http_health_check_address = "http://127.0.0.1:8080/health",
    tags = [
        "exclusive-if-local",
        "no-remote-exec",
    ],
    visibility = ["//apps/suites/tabula:__subpackages__"],
    deps = [
        ":migrate",
        ":redis",
    ],
)

# --- Container image + push (deployed by //apps/suites/tabula/infra/app) ----

tar(
    name = "image_app_layer",
    srcs = [":api_bin"],
    mtree = [
        "./opt/app type=file content=$(execpath :api_bin)",
    ],
)

oci_image(
    name = "image",
    base = "@nodejs_base",
    entrypoint = ["/opt/app"],
    env = {"NODE_ENV": "production"},
    tars = [":image_app_layer"],
)

oci_load(
    name = "image.load",
    image = ":image",
    repo_tags = ["apps/suites/tabula/api:latest"],
)

oci_push(
    name = "image_push",
    image = ":image",
    remote_tags = ["latest"],
    repository = "us-central1-docker.pkg.dev/REPLACED-AT-RUNTIME/tabula/api",
)

pipeline_unit(
    name = "tabula-api",
    depends_on = ["tabula-shared"],
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":integration_tests",
        ":tabula_api_tools_rs_test",
        # cloud_run_deploy's launcher check: the real :deploy reaches the sequencer.
        "//apps/suites/tabula/infra/app:deploy_launcher_test",
    ],
    tier = "L1",
    timeout_minutes = 20,
)
