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
load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_library", "js_run_binary")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_itest//:itest.bzl", "itest_service", "itest_task", "port", "service_test")
load("@rules_oci//oci:defs.bzl", "oci_push")
load("//tools/oci:node_image.bzl", "node_image")

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

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//tabula:__subpackages__"])

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
    # prisma.config.ts is deliberately NOT in srcs: generate is schema-only
    # (works without it), and the config's env("DATABASE_URL") would fail the
    # hermetic sandbox, which has no database. Only Migrate consumes the
    # config (see :migrate_deploy_bin).
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

# rules_ts 3.8.8+ forbids a directory (TreeArtifact) in ts_project(srcs). Wrap the
# generated Prisma client dir in a js_library (yields JsInfo, which 3.8.11's deps
# requires) and consume it via deps; js_library copies it to the bin tree at the
# same package-relative path (src/generated/prisma/), so the relative imports
# (../generated/prisma/...) still resolve for tsc.
js_library(
    name = "prisma_client_lib",
    srcs = [":prisma_client"],
)

ts_project(
    name = "lib",
    srcs = glob(["src/**/*.ts"]),
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
        ":node_modules/@google-cloud/secret-manager",
        ":node_modules/@prisma/adapter-pg",
        ":node_modules/@prisma/client",
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
        ":prisma_client_lib",
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
    ),
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
        ":prisma_client_lib",
    ],
)

js_binary(
    name = "api_bin",
    data = [
        "package.json",
        ":lib",
        ":node_modules/@prisma/adapter-pg",
        ":node_modules/@prisma/client",
        ":node_modules/pg",
        ":prisma_client",
    ],
    entry_point = "src/app.js",
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
    # TS 6 stopped auto-including @types/jest from the rules_js virtual store
    # under nodenext (@types/node still resolves; jest's transitive type graph
    # does not). tsconfig.test.json declares types: [node, jest] explicitly for
    # the test compile only — src (:lib) keeps the base config unchanged.
    extends = "tsconfig.json",
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.test.json",
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
#
# Port hygiene (intermittent CI flake; observed on #377): the locally-run
# (no-remote-exec) service_tests below are tagged "exclusive-if-local" so Bazel
# runs them one at a time. rules_itest's svcinit assigns each autoassigned port
# by binding 127.0.0.1:0, recording it, then CLOSING that listener (assignPorts)
# -- the service itself binds the port only later (postgres after initdb, ~0.75s
# in the failing log). Two svcinit processes that share a network namespace can
# be handed the same just-freed port in that window; the loser's postgres dies
# "could not bind ... Address already in use" and svcinit panics during setup
# (`panic: exit status 1`). These local tests DO share the host netns: Bazel
# runs them under processwrapper-sandbox, which -- unlike linux-sandbox --
# creates no network namespace, so --nosandbox_default_allow_network (preset
# .bazelrc) silently does not isolate them. Serializing the local actions
# removes the concurrency the race needs. This is a no-op on RBE (each remote
# action already gets its own netns) and for cached results. The deeper fix is
# atomic port reservation in svcinit (hold the listener until the service binds)
# -- not possible for postgres/redis, which don't support SO_REUSEPORT, and not
# yet in upstream rules_itest 0.0.56 (the latest); tracked for a follow-up.

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
    tags = [
        # PostgreSQL refuses to run as root and BuildBuddy RBE containers
        # execute as root; these run locally on the (non-root) CI runner.
        "no-remote-exec",
        # Run one-at-a-time locally: svcinit's assign-then-close port
        # reservation races across concurrent svcinit (see stack header).
        "exclusive-if-local",
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
    # No "exclusive-if-local" here (cf. the other services): redis runs as root,
    # so redis_hygiene_test executes on RBE in its own network namespace and
    # can't collide. As a dependency of api_service/integration_tests it comes
    # up inside their svcinit, which the serialization of those tests covers.
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
    tags = [
        # Depends on postgres, which cannot run as root (BuildBuddy RBE
        # containers are root); runs locally on the (non-root) CI runner.
        "no-remote-exec",
        # Run one-at-a-time locally: svcinit's assign-then-close port
        # reservation races across concurrent svcinit (see stack header).
        "exclusive-if-local",
    ],
    visibility = ["//tabula:__subpackages__"],
    deps = [":postgres"],
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
        "package.json",
        ":node_modules/@fastify/cors",
        ":node_modules/@fastify/jwt",
        ":node_modules/@fastify/rate-limit",
        ":node_modules/@google-cloud/secret-manager",
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
        "//tabula:jest_resolver",
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
    tags = [
        # PostgreSQL refuses to run as root and BuildBuddy RBE containers
        # execute as root; runs locally on the (non-root) CI runner.
        "no-remote-exec",
        # Run one-at-a-time locally: svcinit's assign-then-close port
        # reservation races across concurrent svcinit (see stack header).
        "exclusive-if-local",
    ],
    test = ":jest_suite",
)

# Seeds the deterministic E2E test user (the Playwright config self-signs the
# matching JWT from the shared test secret).
itest_task(
    name = "seed_e2e_user",
    env = {
        "DATABASE_URL": "postgresql://postgres@127.0.0.1:" + port(":postgres") + "/postgres",
        "JWT_SECRET": "e2e-test-jwt-secret-key",
    },
    exe = ":seed_test_user_bin",
    tags = [
        # Depends on postgres, which cannot run as root (BuildBuddy RBE
        # containers are root); runs locally on the (non-root) CI runner.
        "no-remote-exec",
        # Run one-at-a-time locally: svcinit's assign-then-close port
        # reservation races across concurrent svcinit (see stack header).
        "exclusive-if-local",
    ],
    visibility = ["//tabula:__subpackages__"],
    deps = [":migrate"],
)

# The API server as a test service for the extension E2E suite. The port is
# fixed (not autoassigned): the extension bundle bakes API_URL in at build
# time (webpack DefinePlugin, default http://localhost:8080/api/v1) and the
# spec helpers hardcode the same origin — mirroring the old CI topology.
# 8080 is reserved for this single test target.
itest_service(
    name = "api_service",
    env = {
        "DATABASE_URL": "postgresql://postgres@127.0.0.1:" + port(":postgres") + "/postgres",
        "HOST": "127.0.0.1",
        "JWT_REFRESH_SECRET": "e2e-test-refresh-secret-key",
        "JWT_SECRET": "e2e-test-jwt-secret-key",
        "NODE_ENV": "test",
        "PORT": "8080",
        # The whole suite shares one IP and one API; live tab-sync PUTs from
        # parallel browser instances blow through any realistic per-IP limit.
        "RATE_LIMIT_MAX": "100000",
        "REDIS_URL": "redis://127.0.0.1:" + port(":redis"),
        # WorkOS is validated at import; E2E never exercises the login flow.
        "WORKOS_API_KEY": "sk_test_e2e_dummy",
        "WORKOS_CLIENT_ID": "client_e2e_dummy",
    },
    exe = ":api_bin",
    http_health_check_address = "http://127.0.0.1:8080/health",
    tags = [
        # Depends on postgres, which cannot run as root (BuildBuddy RBE
        # containers are root); runs locally on the (non-root) CI runner.
        "no-remote-exec",
        # Run one-at-a-time locally: svcinit's assign-then-close port
        # reservation races across concurrent svcinit (see stack header).
        # This is the target that flaked on #377 (postgres :43595 collision).
        "exclusive-if-local",
    ],
    visibility = ["//tabula:__subpackages__"],
    deps = [
        ":migrate",
        ":redis",
    ],
)

# --- Container image + push (deployed by //tabula/infra/app) ----

node_image(
    name = "image",
    binary = ":api_bin",
    env = {"NODE_ENV": "production"},
)

# The repository placeholder is overridden at run time (oci_push accepts
# --repository/--tag): the deploy workflow passes the project-qualified
# Artifact Registry path and the git SHA.
oci_push(
    name = "image_push",
    image = ":image",
    remote_tags = ["latest"],
    repository = "us-central1-docker.pkg.dev/REPLACED-AT-RUNTIME/tabula/api",
)
