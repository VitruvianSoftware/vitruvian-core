load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:ignore
# gazelle:exclude rs
# Inter-app boundary (#82) for gazelle-generated packages: the hand-set
# app-scoped visibility on //homelab/cmd/homelab is PRESERVED by gazelle on
# regeneration; any future non-internal package generating as
# //visibility:public is caught by the conformance guard
# (tools/conformance/check.sh check_app_visibility).

# Inter-app boundary (#82): targets in this package default to homelab-internal
# visibility so other top-level apps can't depend on homelab internals. Each
# internal/* package already sets explicit //homelab:__subpackages__; this marks
# the boundary at the app root for consistency and future root-package targets.
package(default_visibility = ["//apps/cli/homelab:__subpackages__"])

# Developer-environment check: `bazel run //apps/cli/homelab:doctor` (CLI `run` ignores
# visibility, so the package default is wide enough).
doctor(
    name = "doctor",
    label = "homelab",
    optional = [
        "mise",
        "lima",
    ],
    required = [
        "bazel",
        "git",
    ],
)

alias(
    name = "homelab",
    actual = ":homelab-rs",
    visibility = ["//apps/cli/homelab:__subpackages__"],
)

pipeline_unit(
    name = "homelab",
    persona = "infra",
    runner = "ubuntu-26.04",
    test_targets = ["//apps/cli/homelab/..."],
    tier = "L1",
    timeout_minutes = 20,
)

rust_library(
    name = "homelab_rs_lib",
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
    crate_name = "homelab_rs",
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/homelab:__subpackages__"],
)

rust_binary(
    name = "homelab-rs",
    srcs = ["rs/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/homelab:__subpackages__"],
    deps = [":homelab_rs_lib"],
)

alias(
    name = "homelab_rs",
    actual = ":homelab-rs",
    visibility = ["//apps/cli/homelab:__subpackages__"],
)

rust_test(
    name = "homelab_rs_test",
    size = "small",
    crate = ":homelab_rs_lib",
    data = [
        ".release-please-manifest.json",
        "CHANGELOG.md",
        "homelab.example.yaml",
        "release-please-config.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/homelab:__subpackages__"],
)
