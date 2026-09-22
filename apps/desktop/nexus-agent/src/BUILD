load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_library", "js_test")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# Plain ESM JavaScript — no TypeScript compilation needed for runtime, but
# type-checked hermetically with tsc --checkJs (#836).

ts_project(
    name = "typecheck",
    srcs = [
        "formatter.js",
        "sessions.js",
    ],
    allow_js = True,
    declaration = False,
    extends = "tsconfig.json",
    incremental = True,
    out_dir = "dist_typecheck",
    source_map = False,
    transpiler = "tsc",
    tsconfig = "tsconfig.typecheck.json",
    deps = [
        "//apps/desktop/nexus-agent:node_modules/@types/node",
    ],
)

js_library(
    name = "formatter",
    srcs = ["formatter.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
)

js_library(
    name = "sessions",
    srcs = ["sessions.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
)

# Unit tests for the pure-logic bridge modules, run with Node's built-in
# `node:test` runner (no jest/devDep plumbing). These run in the standard
# `bazel test //...` lane, so nexus JS is finally covered in monorepo CI (#807).
js_test(
    name = "formatter_test",
    data = [":formatter"],
    entry_point = "formatter.test.js",
)

js_test(
    name = "sessions_test",
    data = [":sessions"],
    entry_point = "sessions.test.js",
)

js_library(
    name = "agy",
    srcs = ["agy.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
    deps = [
        ":sessions",
    ],
)

js_library(
    name = "bot_lib",
    srcs = ["bot.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
    deps = [
        ":agy",
        ":formatter",
        ":sessions",
        "//apps/desktop/nexus-agent:node_modules/dotenv",
        "//apps/desktop/nexus-agent:node_modules/telegraf",
    ],
)

js_binary(
    name = "bot",
    data = [
        ":agy",
        ":formatter",
        ":sessions",
        "//apps/desktop/nexus-agent:node_modules/dotenv",
        "//apps/desktop/nexus-agent:node_modules/telegraf",
    ],
    entry_point = "bot.js",
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

pipeline_unit(
    name = "nexus-agent-src",
    persona = "backend",
    runner = "ubuntu-24.04",
    test_targets = [
        ":formatter_test",
        ":sessions_test",
        ":typecheck_typecheck_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
