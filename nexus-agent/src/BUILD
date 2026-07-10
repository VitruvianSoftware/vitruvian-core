load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_library", "js_test")

# Plain ESM JavaScript — no TypeScript compilation needed.

js_library(
    name = "formatter",
    srcs = ["formatter.js"],
    visibility = ["//nexus-agent/src:__pkg__"],
)

js_library(
    name = "sessions",
    srcs = ["sessions.js"],
    visibility = ["//nexus-agent/src:__pkg__"],
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
    name = "gemini",
    srcs = ["gemini.js"],
    visibility = ["//nexus-agent/src:__pkg__"],
    deps = [
        ":sessions",
    ],
)

js_library(
    name = "bot_lib",
    srcs = ["bot.js"],
    visibility = ["//nexus-agent/src:__pkg__"],
    deps = [
        ":formatter",
        ":gemini",
        ":sessions",
        "//nexus-agent:node_modules/dotenv",
        "//nexus-agent:node_modules/telegraf",
    ],
)

js_binary(
    name = "bot",
    data = [
        ":formatter",
        ":gemini",
        ":sessions",
        "//nexus-agent:node_modules/dotenv",
        "//nexus-agent:node_modules/telegraf",
    ],
    entry_point = "bot.js",
    visibility = ["//nexus-agent:__subpackages__"],
)
