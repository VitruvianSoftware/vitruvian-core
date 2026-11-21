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
load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_run_binary")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//apps/desktop/vitruvian-code/macos/claude-helper:esbuild/package_json.bzl", esbuild = "bin")
load(":node_lock.bzl", "rules_nodejs_darwin_sums")

npm_link_all_packages(name = "node_modules")

exports_files(["package.json"])

filegroup(
    name = "protocol_files",
    srcs = glob(["protocol/**/*.json"]),
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

filegroup(
    name = "bundle_files",
    srcs = ["bundle/claude-helper.mjs"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

filegroup(
    name = "bundle_manifest",
    srcs = ["bundle/packages.json"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

filegroup(
    name = "node_lock_file",
    srcs = ["node.lock"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

esbuild.esbuild(
    name = "bundle_build",
    srcs = glob(["src/**/*.ts"]) + [
        "package.json",
        "tsconfig.json",
        ":node_modules",
    ],
    outs = [
        "built/esbuild/claude-helper.mjs",
        "built/metafile.json",
    ],
    args = [
        "src/main.ts",
        "--bundle",
        "--platform=node",
        "--target=node22",
        "--format=esm",
        "--outfile=built/esbuild/claude-helper.mjs",
        "--metafile=built/metafile.json",
    ],
    chdir = package_name(),
)

js_binary(
    name = "extract_packages_bin",
    entry_point = "scripts/extract-packages.mjs",
)

js_binary(
    name = "normalize_bundle_bin",
    entry_point = "scripts/normalize-bundle.mjs",
)

# esbuild's module comments spell the sandbox path (bazel-out/<host config>/...);
# keep the checked-in bundle the same bytes on every machine and build mode.
js_run_binary(
    name = "built_bundle",
    srcs = [":built/esbuild/claude-helper.mjs"],
    outs = ["built/claude-helper.mjs"],
    args = [
        "built/esbuild/claude-helper.mjs",
        "built/claude-helper.mjs",
    ],
    chdir = package_name(),
    tool = ":normalize_bundle_bin",
)

js_run_binary(
    name = "built_packages_json",
    srcs = [
        ":built/metafile.json",
        ":node_modules",
    ],
    outs = ["built/packages.json"],
    args = [
        "built/metafile.json",
        "built/packages.json",
    ],
    chdir = package_name(),
    tool = ":extract_packages_bin",
)

write_source_files(
    name = "update_bundle",
    diff_test = True,
    files = {
        "bundle/claude-helper.mjs": ":built/claude-helper.mjs",
        "bundle/packages.json": ":built/packages.json",
    },
    suggested_update_target = "//apps/desktop/vitruvian-code/macos/claude-helper:update_bundle",
)

rules_nodejs_darwin_sums(
    name = "rules_nodejs_darwin_sums",
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
    data = glob(
        [
            "src/**/*.ts",
            "test/**/*.test.ts",
        ],
        exclude = [
            "test/bundle.test.ts",
            "test/nodeLock.test.ts",
            "test/thirdPartyNotices.test.ts",
        ],
    ) + [
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

jest_test(
    name = "bundle_isolated_load_test",
    size = "small",
    args = [
        "--testMatch=**/test/bundle.test.ts",
    ],
    config = "jest.config.cjs",
    data = [
        "bundle/claude-helper.mjs",
        "bundle/packages.json",
        "jest.config.cjs",
        "package.json",
        "scripts/normalize-bundle.mjs",
        "test/bundle.test.ts",
        "tsconfig.json",
        "tsconfig.test.json",
        ":node_modules/@agentclientprotocol/sdk",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/ajv",
        ":node_modules/ajv-formats",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
        ":protocol_files",
    ],
    node_modules = ":node_modules",
    node_options = [
        "--experimental-vm-modules",
        "--no-experimental-require-module",
    ],
)

jest_test(
    name = "node_lock_test",
    size = "small",
    args = [
        "--testMatch=**/test/nodeLock.test.ts",
    ],
    config = "jest.config.cjs",
    data = [
        "jest.config.cjs",
        "node.lock",
        "package.json",
        "test/nodeLock.test.ts",
        "tsconfig.json",
        "tsconfig.test.json",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
        ":rules_nodejs_darwin_sums",
        "//:nvmrc",
    ],
    node_modules = ":node_modules",
    node_options = [
        "--experimental-vm-modules",
        "--no-experimental-require-module",
    ],
)

jest_test(
    name = "third_party_notices_test",
    size = "small",
    args = [
        "--testMatch=**/test/thirdPartyNotices.test.ts",
    ],
    config = "jest.config.cjs",
    data = [
        "bundle/packages.json",
        "jest.config.cjs",
        "node.lock",
        "package.json",
        "test/thirdPartyNotices.test.ts",
        "tsconfig.json",
        "tsconfig.test.json",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
        "//apps/desktop/vitruvian-code:third_party_notices",
    ],
    node_modules = ":node_modules",
    node_options = [
        "--experimental-vm-modules",
        "--no-experimental-require-module",
    ],
)
