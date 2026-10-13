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

# //packages/vitruvian-sdk/kits/typescript: the TypeScript kit, published as
# @vitruviansoftware/tool-kit from the vitruvian-sdk mirror. See README.md.
#
# Hand-written, like the package's own BUILD: Gazelle is kept out of kits/.
# gazelle:ignore

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

npm_link_all_packages(name = "node_modules")

# Written by //tools/sdk-codegen; its drift test reads them.
filegroup(
    name = "generated",
    srcs = glob(["src/generated/**"]),
    visibility = ["//packages/vitruvian-sdk:__pkg__"],
)

# Read by //packages/vitruvian-sdk:samples_test, which holds the SDK to one version.
exports_files(["package.json"])

# The kit compiled the way `npm run build` compiles it before a publish: tsc,
# to dist/, with the declarations beside the JavaScript.
ts_project(
    name = "kit",
    srcs = glob(["src/**/*.ts"]),
    declaration = True,
    out_dir = "dist",
    root_dir = "src",
    tsconfig = "tsconfig.json",
    deps = [":node_modules/@types/node"],
)

# What npm would receive: package.json, the README, the licence and dist/.
# The samples' folders are built with it in their node_modules.
npm_package(
    name = "tool-kit-typescript",
    srcs = [
        "LICENSE",
        "README.md",
        "package.json",
        ":kit",
    ],
    package = "@vitruviansoftware/tool-kit",
    visibility = ["//packages/vitruvian-sdk:__pkg__"],
)
