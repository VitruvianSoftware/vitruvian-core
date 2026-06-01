"""`bazel run` wrappers for the lab-gmail Pulumi project.

A standalone Pulumi Go program that provisions personal GCP resources (Cloud
Run, service accounts, Secret Manager, IAM, GCS) plus optional Cloudflare DNS.
Drive it through Bazel instead of the raw `pulumi` CLI:

    bazel run //infrastructure/pulumi/lab-gmail:preview
    bazel run //infrastructure/pulumi/lab-gmail:up
    bazel run //infrastructure/pulumi/lab-gmail:config -- set <key> <value>

Pulumi compiles and runs main.go itself; the wrappers only launch it.
"""

load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "lab-gmail",
    dir = "infrastructure/pulumi/lab-gmail",
)
