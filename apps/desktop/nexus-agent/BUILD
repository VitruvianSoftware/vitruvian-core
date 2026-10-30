load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")

# gazelle:ignore

# Inter-app boundary (#82): default targets to nexus-agent-internal visibility
# so other top-level apps can't depend on internals.
package(default_visibility = ["//apps/desktop/nexus-agent:__subpackages__"])

# The examples both the bot's tests and the Mac apps' tests read
# (testdata/README.md).
alias(
    name = "testdata",
    actual = ":testdata_files",
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

alias(
    name = "bot",
    actual = ":bot-rs",
)

rust_library(
    name = "bot_lib",
    srcs = ["//apps/desktop/nexus-agent/src:bot_lib.rs"],
    crate_name = "nexus_agent_bot",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

rust_binary(
    name = "bot-rs",
    srcs = ["//apps/desktop/nexus-agent/src:bot_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
    deps = [":bot_lib"],
)

alias(
    name = "bot_rs",
    actual = ":bot-rs",
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

rust_test(
    name = "bot_lib_test",
    size = "small",
    crate = ":bot_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
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

# The tool's version test (macos/tool/version_test.py) holds release-please
# to writing the tool's version where the app's goes. A filegroup for the
# reason release_workflow is one.
filegroup(
    name = "release_please_config",
    srcs = ["release-please-config.json"],
    visibility = ["//apps/desktop/nexus-agent/macos:__pkg__"],
)
