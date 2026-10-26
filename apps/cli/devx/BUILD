load("@rules_go//go:def.bzl", "go_binary", "go_library")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# gazelle:prefix github.com/VitruvianSoftware/devx
# gazelle:exclude docs
# gazelle:exclude scripts
# gazelle:exclude .agents
# gazelle:exclude .github
# gazelle:exclude internal/scaffold/templates/node-api
# gazelle:exclude internal/scaffold/templates/next-app
# gazelle:exclude internal/scaffold/templates/python-api
# Inter-app boundary (#82) for gazelle-generated packages: //devx/cmd carries
# a hand-set app-scoped visibility, which gazelle PRESERVES on regeneration
# (it never rewrites an already-set visibility attribute). A future NON-
# internal package would still generate as //visibility:public -- the
# conformance guard (tools/conformance/check.sh check_app_visibility) fails
# CI on exactly that literal, so the firewall cannot silently reopen.

# Inter-app boundary (#82): targets in this package default to devx-internal
# visibility so other top-level apps can't depend on devx internals. The
# binary needs no wider visibility: `bazel run/build //apps/cli/devx` from the CLI,
# workflows, and GoReleaser ignores visibility (it gates dep EDGES only).
package(default_visibility = ["//apps/cli/devx:__subpackages__"])

go_library(
    name = "devx_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/devx",
    visibility = ["//visibility:private"],
    deps = ["//apps/cli/devx/cmd"],
)

go_binary(
    name = "devx",
    embed = [":devx_lib"],
)

# Developer-environment check: `bazel run //apps/cli/devx:doctor`. Go is pinned to this
# app's own go.mod (`--gomod apps/cli/devx/go.mod`).
doctor(
    name = "doctor",
    gomod = "apps/cli/devx/go.mod",
    label = "devx",
    optional = [
        "mage",
        "lima",
        "goreleaser",
    ],
    required = [
        "bazel",
        "go",
        "git",
    ],
)

pipeline_unit(
    name = "devx-cli",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = ["//apps/cli/devx/..."],
    tier = "L1",
    timeout_minutes = 20,
)

rust_library(
    name = "migrate_to_docker_lib",
    srcs = ["scripts/src/lib.rs"],
    crate_name = "devx_migrate_to_docker",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/devx:__subpackages__"],
)

rust_binary(
    name = "migrate-to-docker-rs",
    srcs = ["scripts/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [":migrate_to_docker_lib"],
)

alias(
    name = "migrate_to_docker_rs",
    actual = ":migrate-to-docker-rs",
    visibility = ["//apps/cli/devx:__subpackages__"],
)

rust_test(
    name = "migrate_to_docker_lib_test",
    size = "small",
    crate = ":migrate_to_docker_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/devx:__subpackages__"],
)
