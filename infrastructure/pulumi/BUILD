# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# `bazel run` wrappers for the root sync-auth Pulumi project (vitruvian-core-infra).
# It manages the Copybara sync auth — the GitHub deploy keys + Actions secrets for
# every synced component (see pkg/copybara_sync, ManageSyncAuth). Drive via Bazel:
#   bazel run //infrastructure/pulumi:preview
#   bazel run //infrastructure/pulumi:up -- --stack dev
load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "vitruvian-core-infra",
    dir = "infrastructure/pulumi",
)

# pkg/secrets has no BUILD file of its own, so it's part of THIS package.
# Exported so sibling Pulumi projects whose go.mod has
# `replace .../pkg/secrets => ../../pkg/secrets` (e.g. repo_config) can pull it
# into their pulumi_go_test() sandbox via extra_data — the replace directive
# resolves to a real path on disk, so `go test` needs the files there, not
# just the module declared.
filegroup(
    name = "pkg_secrets_files",
    srcs = glob(["pkg/secrets/**"]),
    visibility = ["//visibility:public"],
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2): the root sync-auth
# stack — the GitHub deploy keys + Actions secrets backing every one-way
# Copybara mirror (pkg/copybara_sync).
#
# PUSH APPLIES ARE OPT-IN. gate_var keeps the legacy switch: an affected push
# applies only when the SYNC_AUTH_AUTO_APPLY repo variable is "true" (off by
# default, because this stack manages auth for EVERY component), while a
# deliberate dispatch always runs. Dropping it would turn "cleanly does not
# run" into "runs on every affected push".
delivery(
    name = "copybara-sync-auth",
    # The stack this applies. There is no ladder and no GitHub Environment: the
    # legacy job binds none and authenticates with a minted GitHub App token.
    environments = ["dev"],
    extra_paths = [
        "infrastructure/pulumi/main\\.go",
        "infrastructure/pulumi/pkg/copybara_sync/",
        "infrastructure/pulumi/BUILD",
        "\\.github/workflows/copybara-sync-auth-apply\\.yaml",
    ],
    gate_var = "SYNC_AUTH_AUTO_APPLY",
    github_environment = "",
    kind = "pulumi",
    legacy_job = "apply",
    legacy_workflow = ".github/workflows/copybara-sync-auth-apply.yaml",
    render = "transcribed",
    run = "//infrastructure/pulumi:up",
)
