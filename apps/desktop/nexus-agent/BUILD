load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/doctor:defs.bzl", "doctor")

# gazelle:ignore

# Inter-app boundary (#82): default targets to nexus-agent-internal visibility
# so other top-level apps can't depend on internals.
package(default_visibility = ["//apps/desktop/nexus-agent:__subpackages__"])

npm_link_all_packages(name = "node_modules")

# The examples both the bot's tests and the Mac apps' tests read
# (testdata/README.md). Two targets over the same files: rules_js only copies
# a file into a JavaScript test's sandbox when a js_library hands it over, and
# the Swift test takes plain files.
js_library(
    name = "testdata",
    srcs = glob(["testdata/*.json"]),
)

filegroup(
    name = "testdata_files",
    srcs = glob(["testdata/*.json"]),
)

# The mirror's release workflow. It never runs in this repository, so
# //tools/ci:nexus_agent_release_rehearsal_test reads it to keep the rehearsal
# (.github/workflows/nexus-agent-mirror-toolchain.yaml) running the same steps.
#
# A filegroup, not exports_files, on purpose: CI picks the tests to run by
# asking what depends on the rules of each changed package
# (tools/pipeline/plan), and a bare exported file is not a rule. Exported that
# way, a change to release.yml alone would not run the test that reads it.
filegroup(
    name = "release_workflow",
    srcs = [".github/workflows/release.yml"],
    visibility = ["//tools/ci:__pkg__"],
)

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
