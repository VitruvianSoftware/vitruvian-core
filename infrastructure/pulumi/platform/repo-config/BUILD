"""`bazel run` wrappers for the repo-config Pulumi project.

This is a standalone Pulumi Go program that manages this repo's own GitHub
settings (see README.md). Developers drive it through Bazel instead of the raw
`pulumi` CLI:

    bazel run //infrastructure/pulumi/platform/repo-config:setup            # one-time bootstrap
    bazel run //infrastructure/pulumi/platform/repo-config:config -- set repoOwner my-org
    bazel run //infrastructure/pulumi/platform/repo-config:preview
    bazel run //infrastructure/pulumi/platform/repo-config:up

Pulumi compiles and runs main.go itself; the wrappers only launch it.
"""

load("//tools/pipeline:defs.bzl", "pipeline_unit")
load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

pulumi_project(
    name = "repo-config",
    dir = "infrastructure/pulumi/platform/repo-config",
)

# `bazel test //infrastructure/pulumi/platform/repo-config:test` — local
# `bazel test` visibility into the same `go test ./...` CI already runs (see
# pulumi_go_test() in defs.bzl for why this doesn't run on RBE).
pulumi_go_test()

pipeline_unit(
    name = "pulumi-repo-config",
    persona = "infra",
    runner = "ubuntu-latest",
    test_targets = [":test"],
    tier = "L1",
    timeout_minutes = 20,
)
