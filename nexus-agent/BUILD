load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/doctor:defs.bzl", "doctor")

# gazelle:ignore

# Inter-app boundary (#82): default targets to nexus-agent-internal visibility
# so other top-level apps can't depend on internals.
package(default_visibility = ["//nexus-agent:__subpackages__"])

npm_link_all_packages(name = "node_modules")

sh_binary(
    name = "bot",
    srcs = ["bot.sh"],
)

# Developer-environment check: `bazel run //nexus-agent:doctor`. swift/python3
# are optional (used by the native/agent tooling paths).
doctor(
    name = "doctor",
    label = "nexus-agent",
    optional = [
        "swift",
        "python3",
    ],
    required = [
        "bazel",
        "node",
        "git",
    ],
)
