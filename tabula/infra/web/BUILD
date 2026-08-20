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
load("//tools/deploy:defs.bzl", "cloud_run_deploy")
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "tabula-web",
    dir = "tabula/infra/web",
)

cloud_run_deploy(
    name = "deploy",
    env_prefix = "TABULA_WEB",
    pulumi_dir = "tabula/infra/web",
    refresh = True,
    region = "us-central1",
    service = "tabula-web",
    smoke_path = "/",
)

# Delivery unit (delivery-orchestrator PHASE 2, spec §6). tabula-web promotes
# INDEPENDENTLY of tabula-api -- its own `tabula-web-v*` release tag, its own
# dev-soak interlock reading its OWN development job -- but shares the single
# `tabula-build` job, consuming that job's web-image-digest output. See
# tabula/infra/app/BUILD for why both units carry the same detection inputs.
delivery(
    name = "tabula-web",
    environments = [
        "development",
        "nonproduction",
        "production",
    ],
    extra_paths = [
        "tabula/infra/app/",
        "tabula/infra/web/",
        "tabula/web/",
        "tools/deploy/",
        "\\.github/workflows/tabula-deploy\\.yaml",
        "\\.github/workflows/tabula-dev-latest\\.yaml",
        "\\.github/workflows/_deploy-cloud-run\\.yaml",
    ],
    github_environment = "tabula-{env}",
    graph_targets = [
        "//tabula/api:image_push",
        "//tabula/extension:chrome_zip",
    ],
    # The OTHER output of the shared build: tabula/web/Dockerfile's image,
    # pushed by the same job's `web-image` step.
    image_digest_output = "web-image-digest",
    kind = "cloud-run",
    # Own tag, not the union legacy used -- see tabula/infra/app/BUILD's note
    # on the one sanctioned divergence from tabula-deploy.yaml.
    promotion = "release:tabula-web-v",
    run = "//tabula/infra/web:deploy",
    shared_build = "tabula",
    soak = True,
    # Copied VERBATIM from tabula-deploy.yaml's `deploy-dev-web` job.
    workflow_inputs = {
        "app-name": "tabula",
        "cloudflare-token-secret-project": "prj-d-bu2-oss-floating-c3d1",
        "default-region": "us-central1",
        "env-prefix": "TABULA_WEB",
        "pulumi-dir": "tabula/infra/web",
        "pulumi-refresh": True,
        "run-migrations": False,
        "secret-prefix": "TABULA_",
        "service-name": "tabula-web",
        "skip-if-unchanged": False,
        "smoke-url-path": "/",
        "workload-migrated": False,
    },
)
