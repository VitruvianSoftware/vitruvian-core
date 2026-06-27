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
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//tabula/extension:@playwright/test/package_json.bzl", playwright = "bin")
load("@npm//tabula/extension:webpack-cli/package_json.bzl", webpack_cli = "bin")
load("@rules_itest//:itest.bzl", "service_test")

# @tabula/extension: Chrome MV3 extension (React), bundled by the package's
# own webpack.config.js (3 entries: popup, background, dashboard; CopyPlugin
# rewrites manifest.json host_permissions from API_URL).
# webpack-cli runs as a single cacheable js_run_binary action; the dedicated
# rules_webpack ruleset is deliberately not used (it lags rules_js majors and
# webpack_bundle is implemented the same way).
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude tests

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//tabula:__subpackages__"])

npm_link_all_packages(name = "node_modules")

webpack_cli.webpack_cli(
    name = "dist",
    srcs = glob(["src/**"]) + [
        "package.json",
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
    transpiler = swc,
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
        # manifest.json is asserted on by background/index.test.ts (the
        # externally_connectable allow-list is the relay's real trust boundary).
        "src/**/*.json",
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
    # No shard_count: each shard would run 1/N of the tests while collecting
    # coverage over all sources, so the jest coverageThreshold gate would
    # evaluate against artificially fractional numbers under bazel coverage.
)

playwright.playwright_test(
    name = "pw_suite",
    data = glob([
        "tests/**/*.ts",
        "src/**/*.ts",
        "src/**/*.tsx",
    ]) + [
        "playwright.config.ts",
        ":dist",
        ":node_modules/@playwright/test",
        ":node_modules/@types/jsonwebtoken",
        ":node_modules/jsonwebtoken",
        "@playwright//:chromium",
    ],
    env = {
        "CI": "1",
        "EXTENSION_PATH": "$(rootpath :dist)",
        # Playwright creates browser profiles under os.tmpdir(). Bazel's
        # TEST_TMPDIR is deep inside the sandbox; Chrome's SingletonSocket
        # inside the profile then exceeds the 108-char unix-socket path limit
        # and the browser CHECK-fails (SIGTRAP) at launch on Linux runners.
        "TMPDIR": "/tmp",
        "JWT_SECRET": "e2e-test-jwt-secret-key",
        "PLAYWRIGHT_BROWSERS_PATH": "$(rootpath @playwright//:chromium)/../",
    },
    # fixed_args (not args): the service manager execs this binary directly,
    # so Bazel-time test args never reach it.
    fixed_args = [
        "test",
        "--config=tabula/extension/playwright.config.ts",
    ],
    tags = ["manual"],
)

service_test(
    name = "e2e",
    size = "enormous",
    services = [
        "//tabula/api:api_service",
        "//tabula/api:migrate",
        "//tabula/api:postgres",
        "//tabula/api:redis",
        "//tabula/api:seed_e2e_user",
    ],
    tags = [
        "e2e",
        # Chromium needs host system libraries (nss/atk/fonts) that the RBE
        # image is not guaranteed to provide; the dedicated CI lane installs
        # them and runs this locally on the runner.
        "no-remote-exec",
        # Specs open real pages (https://example.com) as workspace tabs, as
        # the suite always has. A local fixture server would make this fully
        # hermetic; until then the e2e lane needs internet.
        "requires-network",
    ],
    test = ":pw_suite",
)

# Release bundle: identical to :dist except API_URL targets the deployed API
# (the :dist default of localhost:8080 is for local development; the old
# repo's releases were accidentally localhost-bound for their whole life).
# The URL is stable: Cloud Run derives it from service name + project number.
# When nonproduction/production exist this becomes per-channel configuration.
webpack_cli.webpack_cli(
    name = "dist_release",
    srcs = glob(["src/**"]) + [
        "package.json",
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
    env = {
        "API_URL": "https://tabula-api-dev-q7dosy3wiq-uc.a.run.app/api/v1",
        "NODE_ENV": "production",
        "WEBPACK_OUT_DIR": "dist_release",
    },
    mnemonic = "WebpackBundle",
    out_dirs = ["dist_release"],
)

# Release artifact: the release bundle minus sourcemaps/declarations,
# attached to tabula-extension-v* releases by .github/workflows/tabula-release.yml.
genrule(
    name = "chrome_zip",
    srcs = [":dist_release"],
    outs = ["tabula-extension-chrome.zip"],
    cmd = "cd $(location :dist_release) && zip -qrX $$OLDPWD/$@ . -x '*.map' -x '*.d.ts'",
)
