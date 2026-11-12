load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore
# gazelle:exclude rs
# Inter-app boundary (#82): any future non-internal package generating as
# //visibility:public is caught by the conformance guard
# (tools/conformance/check.sh check_app_visibility).

# Inter-app boundary (#82): targets in this package default to vitruvian-homelab-internal
# visibility so other top-level apps can't depend on vitruvian-homelab internals.
package(default_visibility = ["//apps/cli/vitruvian-homelab:__subpackages__"])

# Developer-environment check: `bazel run //apps/cli/vitruvian-homelab:doctor` (CLI `run` ignores
# visibility, so the package default is wide enough).
doctor(
    name = "doctor",
    label = "vitruvian-homelab",
    optional = [
        "mise",
        "lima",
    ],
    required = [
        "bazel",
        "git",
    ],
)

pipeline_unit(
    name = "vitruvian-homelab",
    persona = "infra",
    runner = "ubuntu-26.04",
    test_targets = ["//apps/cli/vitruvian-homelab/..."],
    tier = "L1",
    timeout_minutes = 20,
)

rust_library(
    name = "vitruvian_homelab_lib",
    srcs = [
        "rs/src/cluster.rs",
        "rs/src/cmd.rs",
        "rs/src/config.rs",
        "rs/src/doctor.rs",
        "rs/src/k3s.rs",
        "rs/src/lib.rs",
        "rs/src/lima.rs",
        "rs/src/logging.rs",
        "rs/src/prereqs.rs",
        "rs/src/remote.rs",
    ],
    crate_name = "vitruvian_homelab_rs",
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/vitruvian-homelab:__subpackages__"],
)

rust_binary(
    name = "homelab",
    srcs = ["rs/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/vitruvian-homelab:__subpackages__"],
    deps = [":vitruvian_homelab_lib"],
)

rust_test(
    name = "vitruvian_homelab_test",
    size = "small",
    crate = ":vitruvian_homelab_lib",
    data = [
        ".release-please-manifest.json",
        "CHANGELOG.md",
        "homelab.example.yaml",
        "release-please-config.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/vitruvian-homelab:__subpackages__"],
)

# The mirror's Sponsor button. The stripe stack's donations_pages_test.go
# checks it opens a donate page that a Payment Link backs.
exports_files(
    [
        ".github/FUNDING.yml",
    ],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
