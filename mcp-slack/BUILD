load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("//tools/doctor:defs.bzl", "doctor")

# This BUILD is hand-authored: a single co-located ts_project whose tsconfig
# (rootDir ./src, outDir ./dist, include src/**/*) resolves consistently. The
# aspect JS/TS Gazelle extension would otherwise rewrite this file (leaving a
# broken empty src glob) and emit a separate src/BUILD, breaking the build.
# `gazelle:ignore` stops Gazelle from editing this file; `gazelle:exclude src`
# stops it from generating BUILD files under src/.
#
# __tests__ needs the same exclusion for a different reason: the suites import
# across directories (`../src/auth.js`), which Gazelle cannot resolve when it
# generates a separate BUILD for that directory — it fails with "unknown js
# dependency" rather than producing something broken. The jest_test target
# below covers those files explicitly instead.
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude __tests__

# Inter-app boundary (#82): default targets to mcp-slack-internal visibility so
# other top-level apps can't depend on internals. The npm-published artifact is
# built by label (`bazel build //mcp-slack`) which ignores visibility, so even
# the published ts_project needs no wider scope.
package(default_visibility = ["//mcp-slack:__subpackages__"])

npm_link_all_packages(name = "node_modules")

# @vitruviansoftware/mcp-slack is a TypeScript (ESM) project built with `tsc`.
# The ts_project is co-located with tsconfig.json so the tsconfig's
# rootDir (./src) / outDir (./dist) / include (src/**/*) resolve consistently.
ts_project(
    name = "mcp-slack",
    srcs = glob(["src/**/*.ts"]),
    declaration = True,
    declaration_map = True,
    out_dir = "dist",
    resolve_json_module = True,
    root_dir = "src",
    source_map = True,
    transpiler = swc,
    tsconfig = "tsconfig.json",
    deps = [
        ":node_modules/@modelcontextprotocol/sdk",
        ":node_modules/@types/node",
        ":node_modules/jose",
    ],
)

# First test suite for this package. It exists because the HTTP transport puts
# a Slack-capable endpoint on the public internet, and "the package compiles"
# is not a meaningful gate for that. Coverage is deliberately narrow: the two
# checks that ARE the security boundary — the channel allow-list, and bearer
# token validation (signature, issuer, expiry, and the project audience).
#
# ts-jest, mirroring oauth-user-inspector's suite. Deps are hand-listed because
# `gazelle:ignore` above means nothing generates this file.
jest_test(
    name = "unit_tests",
    size = "small",
    config = "jest.config.cjs",
    data = glob(
        [
            "src/**/*.ts",
            "__tests__/**/*.test.ts",
        ],
        allow_empty = False,
    ) + [
        "jest.config.cjs",
        "package.json",
        "tsconfig.json",
        "tsconfig.test.json",
        ":node_modules/@modelcontextprotocol/sdk",
        ":node_modules/@types/jest",
        ":node_modules/@types/node",
        ":node_modules/jose",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
    ],
    node_modules = ":node_modules",
    # Node 22.12+ require(esm) makes jest's generated config throw
    # ERR_REQUIRE_ASYNC_MODULE; force the import() fallback (cf. tabula/web
    # and oauth-user-inspector).
    node_options = ["--no-experimental-require-module"],
)

# Developer-environment check: `bazel run //mcp-slack:doctor`.
doctor(
    name = "doctor",
    label = "mcp-slack",
    required = [
        "bazel",
        "node",
        "pnpm",
        "git",
    ],
)
