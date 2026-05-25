load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")

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
