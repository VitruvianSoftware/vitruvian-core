load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("//tools/doctor:defs.bzl", "doctor")

# This BUILD is hand-authored: a single co-located ts_project whose tsconfig
# (rootDir ./src, outDir ./dist, include src/**/*) resolves consistently. The
# aspect JS/TS Gazelle extension would otherwise rewrite this file (leaving a
# broken empty src glob) and emit a separate src/BUILD, breaking the build.
# `gazelle:ignore` stops Gazelle from editing this file; `gazelle:exclude src`
# stops it from generating BUILD files under src/.
# gazelle:ignore
# gazelle:exclude src

# Inter-app boundary (#82): default targets to mcp-slack-internal visibility so
# other top-level apps can't depend on internals. The published ts_project
# below keeps its explicit //visibility:public.
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
    transpiler = "tsc",
    tsconfig = "tsconfig.json",
    visibility = ["//visibility:public"],
    deps = [
        ":node_modules/@modelcontextprotocol/sdk",
        ":node_modules/@types/node",
    ],
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
