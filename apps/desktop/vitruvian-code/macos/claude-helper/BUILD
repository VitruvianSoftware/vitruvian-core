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

# //apps/desktop/vitruvian-code/macos/claude-helper: Node helper that runs the
# Claude Agent SDK over ACP v1 stdio JSON-RPC 2.0 for Vitruvian Code.
#
# Hand-written: Gazelle does not manage this standalone-exportable package.
# gazelle:ignore

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

npm_link_all_packages(name = "node_modules")

exports_files(["package.json"])

filegroup(
    name = "protocol_files",
    srcs = glob(["protocol/**/*.json"]),
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

ts_project(
    name = "helper",
    srcs = glob(["src/**/*.ts"]),
    declaration = True,
    out_dir = "dist",
    root_dir = "src",
    tsconfig = "tsconfig.json",
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
    deps = [
        ":node_modules/@agentclientprotocol/sdk",
        ":node_modules/@anthropic-ai/claude-agent-sdk",
        ":node_modules/@types/node",
    ],
)

jest_test(
    name = "helper_test",
    size = "small",
    config = "jest.config.cjs",
    data = glob([
        "src/**/*.ts",
        "test/**/*.test.ts",
    ]) + [
        "jest.config.cjs",
        "package.json",
        "tsconfig.json",
        "tsconfig.test.json",
        ":helper",
        ":node_modules/@agentclientprotocol/sdk",
        ":node_modules/@anthropic-ai/claude-agent-sdk",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/ajv",
        ":node_modules/ajv-formats",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
        ":protocol_files",
        "//:pnpm_workspace_yaml",
    ],
    node_modules = ":node_modules",
    # Node 22.12+ require(esm) makes jest's generated config throw
    # ERR_REQUIRE_ASYNC_MODULE; force the import() fallback, as vitruvian-slack-mcp does.
    node_options = [
        "--experimental-vm-modules",
        "--no-experimental-require-module",
    ],
)
