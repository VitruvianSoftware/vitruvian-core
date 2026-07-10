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

# @tabula/web: the Next.js (app-router) web companion. Tests run under
# rules_jest via next/jest (jest.config.js already rewrites
# transformIgnorePatterns for the rules_js virtual store). No next-build target
# yet — this gets the web app's jest suite into CI for the first time.

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@npm//:defs.bzl", "npm_link_all_packages")

# Inter-app boundary (#82): tabula-internal by default, matching the sibling
# tabula packages (api/cli/extension/shared).
package(default_visibility = ["//tabula:__subpackages__"])

npm_link_all_packages(name = "node_modules")

jest_test(
    name = "unit_tests",
    size = "large",
    config = "jest.config.js",
    data = glob(
        [
            "app/**/*.ts",
            "app/**/*.tsx",
            "app/**/*.css",
            "lib/**/*.ts",
            "lib/**/*.tsx",
            "types/**/*.ts",
            "__tests__/**/*.ts",
            "__tests__/**/*.tsx",
            "__mocks__/**/*.js",
        ],
        allow_empty = True,
    ) + [
        "//tabula:jest_resolver",
        "jest.setup.js",
        "next.config.ts",
        "postcss.config.mjs",
        "tsconfig.json",
        "package.json",
        ":node_modules/@tabula/shared",
        ":node_modules/@testing-library/jest-dom",
        ":node_modules/@testing-library/react",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/@types/react",
        ":node_modules/@types/react-dom",
        ":node_modules/geist",
        ":node_modules/jest-environment-jsdom",
        ":node_modules/next",
        ":node_modules/react",
        ":node_modules/react-dom",
        # next/jest detects TypeScript and will try to `npm install` it if it is
        # not present — declare it so Next finds it in the hermetic sandbox.
        ":node_modules/typescript",
        ":node_modules/zustand",
    ],
    node_modules = ":node_modules",
    # jest 29's requireOrImportModule only catches ERR_REQUIRE_ESM; Node 22.12+
    # require(esm) support makes the generated config throw
    # ERR_REQUIRE_ASYNC_MODULE instead. Force the import() fallback.
    node_options = ["--no-experimental-require-module"],
)
