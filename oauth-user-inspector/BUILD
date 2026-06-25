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

# oauth-user-inspector: a Vite/React frontend + Express/TS backend served as one
# container (see Dockerfile + infrastructure/pulumi/oauth-user-inspector for the
# Cloud Run deploy). The production build runs via pnpm/vite/tsc (the monorepo
# does not bazel-build frontends — cf. tabula/web); bazel runs the jest suite so
# the server tests land in CI. gazelle:ignore stops the JS/TS extension from
# rewriting this hand-authored file.
# gazelle:ignore
# gazelle:exclude frontend
# gazelle:exclude server
# gazelle:exclude scripts
# gazelle:exclude dist
# gazelle:exclude dist-server

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@npm//:defs.bzl", "npm_link_all_packages")

package(default_visibility = ["//oauth-user-inspector:__subpackages__"])

npm_link_all_packages(name = "node_modules")

# Server-side jest suite (ts-jest; testMatch **/__tests__/**/*.test.ts).
jest_test(
    name = "unit_tests",
    size = "small",
    config = "jest.config.cjs",
    data = glob(
        [
            "server/**/*.ts",
        ],
        allow_empty = True,
    ) + [
        "jest.config.cjs",
        "package.json",
        "server/tsconfig.server.json",
        "tsconfig.json",
        ":node_modules/@google-cloud/logging-winston",
        ":node_modules/@google-cloud/secret-manager",
        ":node_modules/@types/express",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/@types/node-fetch",
        ":node_modules/@types/supertest",
        ":node_modules/@types/uuid",
        ":node_modules/dotenv",
        ":node_modules/express",
        ":node_modules/js-base64",
        ":node_modules/jwt-decode",
        ":node_modules/msw",
        ":node_modules/node-fetch",
        ":node_modules/supertest",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
        ":node_modules/uuid",
        ":node_modules/winston",
    ],
    node_modules = ":node_modules",
    # Node 22.12+ require(esm) makes jest's generated config throw
    # ERR_REQUIRE_ASYNC_MODULE; force the import() fallback (cf. tabula/web).
    node_options = ["--no-experimental-require-module"],
)
