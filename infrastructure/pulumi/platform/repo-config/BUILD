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
pulumi_go_test(
    # The default (moderate, 300 s) is too tight: a cold `go test` build of the
    # Pulumi SDKs alone takes ~100 s, and in a full //... sweep it timed out
    # at 300 s (#4402). Same fix as gcp-bootstrap. "long" allows 900 s.
    timeout = "long",
    # guard_review_test.go checks every file the session-start launcher
    # compiles is covered by guardReviewPaths, so it needs to see them.
    # preview_vars_test.go reads the committed stack config to check the
    # <app>-preview Environments name the read-only identity (#4120), and
    # preview_service_account_test.go runs the environment functions over it.
    extra_data = [
        "Pulumi.dev.yaml",
        "//tools/cloud-bootstrap:session_start_sources",
    ],
)

pipeline_unit(
    name = "pulumi-repo-config",
    persona = "infra",
    runner = "ubuntu-26.04",
    test_targets = [":test"],
    tier = "L1",
    timeout_minutes = 20,
)

# Which repositories show a Sponsor button, and from which FUNDING.yml. The
# stripe stack's donations_pages_test.go reads it to check every button opens
# a donate page that a Payment Link backs.
exports_files(
    [
        "sponsor-button-repos.txt",
    ],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
