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
load("@aspect_rules_js//js:defs.bzl", "js_binary")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

# tabcli: Tabula operations CLI (auth, workos, db, config, init, version).
# Dev-loop and infra commands were retired in the monorepo migration: code
# checks run via `bazel test //tabula/...`, deploys via the
# //infrastructure/pulumi/tabula project.
# gazelle:ignore
# gazelle:exclude src

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//tabula:__subpackages__"])

npm_link_all_packages(name = "node_modules")

ts_project(
    name = "lib",
    srcs = glob(
        ["src/**/*.ts"],
        exclude = ["src/**/*.test.ts"],
    ),
    declaration = True,
    declaration_map = True,
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    deps = [
        ":node_modules/@types/inquirer",
        ":node_modules/@types/node",
        ":node_modules/chalk",
        ":node_modules/commander",
        ":node_modules/dotenv",
        ":node_modules/inquirer",
        ":node_modules/ora",
        ":node_modules/table",
    ],
)

js_binary(
    name = "tabcli",
    data = [":lib"],
    entry_point = "src/index.js",
    visibility = ["//visibility:public"],
)

# Type gate for tests: jest runs swc-transpiled TS without type-checking, so
# tests are type-checked here (mirroring //tabula/extension:tests_lib). The
# emitted JS goes to dist_tests and is discarded — out_dir exists only to
# avoid colliding with :lib's in-place outputs for the shared sources.
ts_project(
    name = "tests_lib",
    testonly = True,
    srcs = glob(["src/**/*.ts"]),
    declaration = False,
    extends = "tsconfig.json",
    out_dir = "dist_tests",
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.test.json",
    deps = [
        ":node_modules/@types/inquirer",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/chalk",
        ":node_modules/commander",
        ":node_modules/dotenv",
        ":node_modules/inquirer",
        ":node_modules/ora",
        ":node_modules/table",
    ],
)

jest_test(
    name = "unit_tests",
    size = "medium",
    config = "jest.config.js",
    data = glob(["src/**/*.ts"]) + [
        ":node_modules/@swc/core",
        ":node_modules/@swc/jest",
        ":node_modules/chalk",
        ":node_modules/commander",
    ],
    node_modules = ":node_modules",
    # See //tabula/extension:unit_tests for why this flag is needed.
    node_options = ["--no-experimental-require-module"],
)
