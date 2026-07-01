load("@aspect_rules_js//js:defs.bzl", "js_binary", "js_library")

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
