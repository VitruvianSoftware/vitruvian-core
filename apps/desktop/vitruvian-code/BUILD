load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")

# gazelle:ignore

# Inter-app boundary (#82): default targets to vitruvian-code-internal visibility
# so other top-level apps can't depend on internals.
package(default_visibility = ["//apps/desktop/vitruvian-code:__subpackages__"])

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
# //tools/ci:vitruvian_code_release_rehearsal_test reads it to keep the rehearsal
# (.github/workflows/vitruvian-code-mirror-toolchain.yaml) running the same steps.
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

filegroup(
    name = "sign_and_notarize_script",
    srcs = ["scripts/sign-and-notarize.sh"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

rust_library(
    name = "bot_lib",
    srcs = ["//apps/desktop/vitruvian-code/src:bot_lib.rs"],
    crate_name = "vitruvian_code_bot",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

rust_binary(
    name = "bot",
    srcs = ["//apps/desktop/vitruvian-code/src:bot_main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
    deps = [":bot_lib"],
)

rust_test(
    name = "bot_lib_test",
    size = "small",
    crate = ":bot_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/vitruvian-code:__subpackages__"],
)

# Developer-environment check: `bazel run //apps/desktop/vitruvian-code:doctor`. swift/python3
# are optional (used by the native/agent tooling paths).
doctor(
    name = "doctor",
    label = "vitruvian-code",
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

# The tool's version test (macos/tool/src/version_test.rs) holds release-please
# to writing the tool's version where the app's goes. A filegroup for the
# reason release_workflow is one.
filegroup(
    name = "release_please_config",
    srcs = ["release-please-config.json"],
    visibility = ["//apps/desktop/vitruvian-code/macos:__pkg__"],
)

# The mirror's Sponsor button. The stripe stack's donations_pages_test.go
# checks it opens a donate page that a Payment Link backs.
exports_files(
    [
        ".github/FUNDING.yml",
    ],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
