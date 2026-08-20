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

load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "tabula-deploy-identity",
    dir = "tabula/infra/identity",
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2). The generated
# .github/workflows/delivery.yaml now owns the push lane; tabula-identity-stack.yaml
# keeps only workflow_dispatch until Phase 3 deletes it.
#
# ALL THREE RUNGS DELIVER ON A PUSH, and that is not the cloud-run policy being
# relaxed: this ladder's per-rung gate is its own foundation-proj-<env> GitHub
# Environment (protected, reviewer-gated), not a release tag, and the rungs are
# CHAINED -- nonproduction cannot start until development succeeded, production
# not until nonproduction did. That is exactly what the legacy workflow's three
# jobs do, job for job.
#
# github_environment is DELIBERATELY the foundation pattern, not the app one:
# the identity stack is applied AS the stage-4 projects SA for that leaf (the
# app deploy SA is what this stack CREATES, so it cannot be what applies it).
# It reaches the generated job as the reusable workflow's `gh-environment`
# INPUT, because GitHub rejects `environment:` on a job that has `uses:`.
delivery(
    name = "tabula-identity",
    environments = [
        "development",
        "nonproduction",
        "production",
    ],
    extra_paths = [
        "tabula/infra/identity/",
        "\\.github/workflows/tabula-identity-stack\\.yaml",
        "\\.github/workflows/_tabula-identity-apply\\.yaml",
    ],
    github_environment = "foundation-proj-{env}",
    kind = "pulumi",
    legacy_job = "development",
    legacy_workflow = ".github/workflows/tabula-identity-stack.yaml",
    render = "reusable",
    run = "//tabula/infra/identity:up",
)
