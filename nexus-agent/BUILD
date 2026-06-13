load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# gazelle:ignore

# Inter-app boundary (#82): default targets to nexus-agent-internal visibility
# so other top-level apps can't depend on internals.
package(default_visibility = ["//nexus-agent:__subpackages__"])

npm_link_all_packages(name = "node_modules")

sh_binary(
    name = "bot",
    srcs = ["bot.sh"],
)
