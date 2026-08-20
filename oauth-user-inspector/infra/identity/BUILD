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
    name = "oauth-user-inspector-deploy-identity",
    dir = "oauth-user-inspector/infra/identity",
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2) — see
# tabula/infra/identity/BUILD for why all three rungs deliver on a push and why
# github_environment is the foundation pattern rather than the app one.
delivery(
    name = "oauth-user-inspector-identity",
    environments = [
        "development",
        "nonproduction",
        "production",
    ],
    extra_paths = [
        "oauth-user-inspector/infra/identity/",
        "\\.github/workflows/_oauth-identity-apply\\.yaml",
    ],
    github_environment = "foundation-proj-{env}",
    kind = "pulumi",
    legacy_job = "development",
    legacy_workflow = ".github/workflows/oauth-user-inspector-identity-stack.yaml",
    render = "reusable",
    run = "//oauth-user-inspector/infra/identity:up",
)
