load("@rules_go//go:def.bzl", "go_binary", "go_library")
load("//tools/doctor:defs.bzl", "doctor")

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
# binary needs no wider visibility: `bazel run/build //devx` from the CLI,
# workflows, and GoReleaser ignores visibility (it gates dep EDGES only).
package(default_visibility = ["//devx:__subpackages__"])

go_library(
    name = "devx_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/devx",
    visibility = ["//visibility:private"],
    deps = ["//devx/cmd"],
)

go_binary(
    name = "devx",
    embed = [":devx_lib"],
)

# Developer-environment check: `bazel run //devx:doctor`. Go is pinned to this
# app's own go.mod (`--gomod devx/go.mod`).
doctor(
    name = "doctor",
    gomod = "devx/go.mod",
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
