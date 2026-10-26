load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_library", "js_test")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# Plain ESM JavaScript — no TypeScript compilation needed for runtime, but
# type-checked hermetically with tsc --checkJs (#836).

ts_project(
    name = "typecheck",
    srcs = [
        "annotations.js",
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
    name = "annotations",
    srcs = ["annotations.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
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
    name = "annotations_test",
    data = [":annotations"],
    entry_point = "annotations.test.js",
)

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

# The examples shared with the Mac apps' tests (../testdata), run through the
# bot's own code. See ../testdata/README.md.
js_test(
    name = "shared_cases_test",
    data = [
        ":agy",
        ":annotations",
        "//apps/desktop/nexus-agent:node_modules/dotenv",
        "//apps/desktop/nexus-agent:testdata",
    ],
    entry_point = "shared-cases.test.js",
)

js_library(
    name = "agy",
    srcs = ["agy.js"],
    visibility = ["//apps/desktop/nexus-agent/src:__pkg__"],
    deps = [
        ":annotations",
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
        ":annotations",
        ":formatter",
        ":sessions",
        "//apps/desktop/nexus-agent:node_modules/dotenv",
        "//apps/desktop/nexus-agent:node_modules/telegraf",
    ],
    entry_point = "bot.js",
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

# ─── Native Rust port of the Nexus Agent bridge & Telegram bot engine ────────

rust_library(
    name = "nexus_agent_src_lib",
    srcs = [
        "rs/agy.rs",
        "rs/annotations.rs",
        "rs/bot.rs",
        "rs/formatter.rs",
        "rs/lib.rs",
        "rs/sessions.rs",
    ],
    crate_name = "nexus_agent_src_lib",
    crate_root = "rs/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

rust_binary(
    name = "bot-engine-rs",
    srcs = ["rs/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
    deps = [":nexus_agent_src_lib"],
)

alias(
    name = "bot_engine_rs",
    actual = ":bot-engine-rs",
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

rust_test(
    name = "nexus_agent_src_lib_test",
    size = "small",
    crate = ":nexus_agent_src_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "annotations_rs_test",
    size = "small",
    srcs = ["rs/annotations_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "formatter_rs_test",
    size = "small",
    srcs = ["rs/formatter_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "sessions_rs_test",
    size = "small",
    srcs = ["rs/sessions_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "shared_cases_rs_test",
    size = "small",
    srcs = ["rs/shared_cases_test.rs"],
    data = ["//apps/desktop/nexus-agent:testdata_files"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

pipeline_unit(
    name = "nexus-agent-src",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":annotations_rs_test",
        ":annotations_test",
        ":formatter_rs_test",
        ":formatter_test",
        ":nexus_agent_src_lib_test",
        ":sessions_rs_test",
        ":sessions_test",
        ":shared_cases_rs_test",
        ":shared_cases_test",
        ":typecheck_typecheck_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)

exports_files(
    [
        "bot_lib.rs",
        "bot_main.rs",
    ],
    visibility = ["//apps/desktop/nexus-agent:__pkg__"],
)
