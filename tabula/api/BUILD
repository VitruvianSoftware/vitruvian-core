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

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_run_binary")
load("@rules_itest//:itest.bzl", "itest_service", "itest_task", "port", "service_test")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

# @tabula/api: Fastify + Prisma (engine-free) + ioredis API server.
# The Prisma client is generated at build time (never checked in) by the
# `prisma-client` generator, which emits plain TypeScript compiled here like
# any other source. The engine placeholder satisfies the CLI's engine
# existence check; no engine binary is ever executed during generate.
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude tests
# gazelle:exclude prisma
# gazelle:exclude scripts

npm_link_all_packages(name = "node_modules")

# Single generate-and-compile action; see prisma/generate-client.cjs for why
# compilation happens here instead of in the ts_project below.
js_binary(
    name = "prisma_client_gen_tool",
    data = [
        ":node_modules/@prisma/client",
        ":node_modules/prisma",
        "//:node_modules/typescript",
    ],
    entry_point = "prisma/generate-client.cjs",
)

js_run_binary(
    name = "prisma_client",
    srcs = [
        "prisma/engine-placeholder",
        "prisma/schema.prisma",
        ":node_modules/@prisma/client",
        ":node_modules/prisma",
        "//:node_modules/typescript",
    ],
    chdir = package_name(),
    env = {
        "PRISMA_SCHEMA_ENGINE_BINARY": "prisma/engine-placeholder",
        "PRISMA_QUERY_ENGINE_LIBRARY": "prisma/engine-placeholder",
        "PRISMA_HIDE_UPDATE_MESSAGE": "1",
    },
    mnemonic = "PrismaGenerate",
    out_dirs = ["src/generated/prisma"],
    tool = ":prisma_client_gen_tool",
)

ts_project(
    name = "lib",
    srcs = glob(["src/**/*.ts"]) + [":prisma_client"],
    declaration = True,
    declaration_map = True,
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    visibility = ["//tabula:__subpackages__"],
    deps = [
        ":node_modules/@fastify/cors",
        ":node_modules/@fastify/jwt",
        ":node_modules/@fastify/rate-limit",
        ":node_modules/@prisma/adapter-pg",
        ":node_modules/@prisma/client",
        ":node_modules/@types/bcryptjs",
        ":node_modules/@types/jsonwebtoken",
        ":node_modules/@types/node",
        ":node_modules/@types/pg",
        ":node_modules/@workos-inc/node",
        ":node_modules/bcryptjs",
        ":node_modules/dotenv",
        ":node_modules/fastify",
        ":node_modules/ioredis",
        ":node_modules/jsonwebtoken",
        ":node_modules/pg",
        ":node_modules/zod",
    ],
)

# Operational entry points outside src/: test-user seeding (E2E setup task)
# and ad-hoc db scripts.
ts_project(
    name = "tools_lib",
    srcs = glob(
        [
            "prisma/**/*.ts",
            "scripts/**/*.ts",
        ],
        allow_empty = True,
        exclude = ["prisma/generate-client.cjs"],
    ) + [":prisma_client"],
    declaration = True,
    declaration_map = True,
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    deps = [
        ":lib",
        ":node_modules/@types/node",
        ":node_modules/bcryptjs",
        ":node_modules/dotenv",
    ],
)

js_binary(
    name = "api_bin",
    data = [
        ":lib",
        ":node_modules/@prisma/adapter-pg",
        ":node_modules/@prisma/client",
        ":node_modules/pg",
        ":prisma_client",
    ],
    entry_point = "src/app.js",
    visibility = ["//visibility:public"],
)

js_binary(
    name = "seed_test_user_bin",
    data = [
        ":prisma_client",
        ":tools_lib",
    ],
    entry_point = "prisma/seed-test-user.js",
    visibility = ["//tabula:__subpackages__"],
)

# Type-check gate for the test sources (jest itself runs @swc/jest, which does
# not type-check).
ts_project(
    name = "tests_lib",
    testonly = True,
    srcs = glob(["tests/**/*.ts"]),
    declaration = True,
    declaration_map = True,
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    deps = [
        ":lib",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/@types/supertest",
        ":node_modules/fastify",
        ":node_modules/supertest",
    ],
)

# --- Hermetic integration-test stack (rules_itest) -------------------------
# Real PostgreSQL 16 + redis-server as health-checked test services; prisma
# migrate runs as a setup task with the vendored schema-engine. The jest
# suite (unit + integration) executes only once the stack is healthy.

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
        "prisma/engine-placeholder",
        "prisma/schema.prisma",
        ":node_modules/prisma",
    ] + glob(["prisma/migrations/**"]),
    entry_point = "prisma/migrate-deploy.cjs",
    visibility = ["//tabula:__subpackages__"],
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
    visibility = ["//tabula:__subpackages__"],
)

itest_service(
    name = "redis",
    args = [
        "--port",
        "$${PORT}",
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
    visibility = ["//tabula:__subpackages__"],
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
    visibility = ["//tabula:__subpackages__"],
)

# The full jest suite (tests/unit needs no services; tests/integration uses
# the live stack). Tagged manual: only runnable through :tests.
jest_test(
    name = "jest_suite",
    config = "jest.config.js",
    data = glob([
        "src/**/*.ts",
        "tests/**/*.ts",
    ]) + [
        ":node_modules/@fastify/cors",
        ":node_modules/@fastify/jwt",
        ":node_modules/@fastify/rate-limit",
        ":node_modules/@prisma/adapter-pg",
        ":node_modules/@prisma/client",
        ":node_modules/@swc/core",
        ":node_modules/@swc/jest",
        ":node_modules/@workos-inc/node",
        ":node_modules/bcryptjs",
        ":node_modules/dotenv",
        ":node_modules/fastify",
        ":node_modules/ioredis",
        ":node_modules/jsonwebtoken",
        ":node_modules/pg",
        ":node_modules/supertest",
        ":node_modules/zod",
        ":prisma_client",
    ],
    node_modules = ":node_modules",
    node_options = ["--no-experimental-require-module"],
    tags = ["manual"],
)

service_test(
    name = "integration_tests",
    size = "medium",
    env = {
        "JWT_SECRET": "test-secret-key-for-testing-only",
        "JWT_REFRESH_SECRET": "test-refresh-secret-key-for-testing-only",
        "NODE_ENV": "test",
        "RATE_LIMIT_MAX": "100000",
        "WORKOS_API_KEY": "sk_test_e2e_dummy",
        "WORKOS_CLIENT_ID": "client_e2e_dummy",
    },
    services = [
        ":migrate",
        ":postgres",
        ":redis",
    ],
    test = ":jest_suite",
)
