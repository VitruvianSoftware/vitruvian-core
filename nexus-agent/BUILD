load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# gazelle:ignore
npm_link_all_packages(name = "node_modules")

sh_binary(
    name = "bot",
    srcs = ["bot.sh"],
)
