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
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//tabula/extension:webpack-cli/package_json.bzl", webpack_cli = "bin")

# @tabula/extension: Chrome MV3 extension (React), bundled by the package's
# own webpack.config.js (3 entries: popup, background, dashboard; CopyPlugin
# rewrites manifest.json host_permissions from API_URL).
# webpack-cli runs as a single cacheable js_run_binary action; the dedicated
# rules_webpack ruleset is deliberately not used (it lags rules_js majors and
# webpack_bundle is implemented the same way).
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude tests

npm_link_all_packages(name = "node_modules")

webpack_cli.webpack_cli(
    name = "dist",
    srcs = glob(["src/**"]) + [
        "tsconfig.json",
        "webpack.config.js",
        ":node_modules/@dnd-kit/core",
        ":node_modules/@dnd-kit/sortable",
        ":node_modules/@dnd-kit/utilities",
        ":node_modules/@tabula/shared",
        ":node_modules/@types/chrome",
        ":node_modules/@types/react",
        ":node_modules/@types/react-dom",
        ":node_modules/@types/webextension-polyfill",
        ":node_modules/copy-webpack-plugin",
        ":node_modules/css-loader",
        ":node_modules/framer-motion",
        ":node_modules/html-webpack-plugin",
        ":node_modules/react",
        ":node_modules/react-dom",
        ":node_modules/style-loader",
        ":node_modules/ts-loader",
        ":node_modules/typescript",
        ":node_modules/webpack",
        ":node_modules/zustand",
    ],
    args = [
        "--mode",
        "production",
        "--config",
        "webpack.config.js",
    ],
    chdir = package_name(),
    env = {"NODE_ENV": "production"},
    mnemonic = "WebpackBundle",
    out_dirs = ["dist"],
    visibility = ["//visibility:public"],
)

ts_project(
    name = "tests_lib",
    testonly = True,
    srcs = glob([
        "src/**/*.ts",
        "src/**/*.tsx",
    ]),
    declaration = False,
    extends = "tsconfig.json",
    resolve_json_module = True,
    source_map = True,
    transpiler = "tsc",
    tsconfig = "tsconfig.test.json",
    deps = [
        ":node_modules/@dnd-kit/core",
        ":node_modules/@dnd-kit/sortable",
        ":node_modules/@dnd-kit/utilities",
        ":node_modules/@tabula/shared",
        ":node_modules/@testing-library/jest-dom",
        ":node_modules/@testing-library/react",
        ":node_modules/@types/chrome",
        ":node_modules/@types/jest",
        ":node_modules/@types/react",
        ":node_modules/@types/react-dom",
        ":node_modules/@types/webextension-polyfill",
        ":node_modules/framer-motion",
        ":node_modules/react",
        ":node_modules/react-dom",
        ":node_modules/zustand",
    ],
)

jest_test(
    name = "unit_tests",
    size = "large",
    config = "jest.config.js",
    data = glob([
        "src/**/*.ts",
        "src/**/*.tsx",
        "src/**/*.js",
    ]) + [
        "jest.setup.js",
        "tests/styleMock.js",
        ":node_modules/@dnd-kit/core",
        ":node_modules/@dnd-kit/sortable",
        ":node_modules/@dnd-kit/utilities",
        ":node_modules/@swc/core",
        ":node_modules/@swc/jest",
        ":node_modules/@tabula/shared",
        ":node_modules/@testing-library/jest-dom",
        ":node_modules/@testing-library/react",
        ":node_modules/framer-motion",
        ":node_modules/jest-environment-jsdom",
        ":node_modules/react",
        ":node_modules/react-dom",
        ":node_modules/zustand",
    ],
    node_modules = ":node_modules",
    # jest 29's requireOrImportModule only catches ERR_REQUIRE_ESM; Node 22.12+
    # require(esm) support makes the generated .mjs config throw
    # ERR_REQUIRE_ASYNC_MODULE instead. Force the import() fallback.
    node_options = ["--no-experimental-require-module"],
    shard_count = 4,
)
