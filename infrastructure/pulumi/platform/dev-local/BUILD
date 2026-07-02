"""`bazel run` wrappers for the dev-local Pulumi project.

A standalone Pulumi Go program that provisions the local k3s dev platform
(longhorn, cert-manager, minio, CNPG, grafana, tempo, prometheus,
external-secrets/dns, otel). Drive it through Bazel instead of the raw
`pulumi` CLI:

    bazel run //infrastructure/pulumi/platform/dev-local:preview
    bazel run //infrastructure/pulumi/platform/dev-local:up
    bazel run //infrastructure/pulumi/platform/dev-local:config -- set <key> <value>

Pulumi compiles and runs main.go itself; the wrappers only launch it.
"""

load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "dev-local",
    dir = "infrastructure/pulumi/platform/dev-local",
)
