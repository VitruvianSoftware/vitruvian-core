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

load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_run_binary")
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
