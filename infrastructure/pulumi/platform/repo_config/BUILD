"""`bazel run` wrappers for the repo_config Pulumi project.

This is a standalone Pulumi Go program that manages this repo's own GitHub
settings (see README.md). Developers drive it through Bazel instead of the raw
`pulumi` CLI:

    bazel run //infrastructure/pulumi/platform/repo_config:setup            # one-time bootstrap
    bazel run //infrastructure/pulumi/platform/repo_config:config -- set repoOwner my-org
    bazel run //infrastructure/pulumi/platform/repo_config:preview
    bazel run //infrastructure/pulumi/platform/repo_config:up

Pulumi compiles and runs main.go itself; the wrappers only launch it.
"""

load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

pulumi_project(
    name = "repo_config",
    dir = "infrastructure/pulumi/platform/repo_config",
)

# `bazel test //infrastructure/pulumi/platform/repo_config:test` — local
# `bazel test` visibility into the same `go test ./...` CI already runs (see
# pulumi_go_test() in defs.bzl for why this doesn't run on RBE).
pulumi_go_test(
    # go.mod: `replace .../pkg/secrets => ../../pkg/secrets`.
    extra_data = ["//infrastructure/pulumi:pkg_secrets_files"],
)
