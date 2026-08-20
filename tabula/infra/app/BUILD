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

# Read by //tools/delivery/gen: a unit declaring preflight = "revision-name"
# must actually ship the revision-name computer, or the preflight fails open on
# every deploy while looking like a working optimisation.
exports_files(["cmd/revname/main.go"])

pulumi_project(
    name = "tabula",
    dir = "tabula/infra/app",
)

# Break-glass / local blue-green deploy (candidate -> smoke -> promote), the same
# rollout CI runs. Image build + expand migration are prerequisite targets
# (//tabula/api:image_push, //tabula/api:migrate_deploy_bin); this drives the
# traffic-shifting rollout. refresh=True mirrors the workflow's pulumi-refresh
# (DomainMapping heal). E.g.:
#   bazel run //tabula/infra/app:deploy -- \
#     --env development --project prj-d-bu2-oss-floating-c3d1 --image-digest <ref@sha256:..>
cloud_run_deploy(
    name = "deploy",
    env_prefix = "TABULA",
    pulumi_dir = "tabula/infra/app",
    refresh = True,
    region = "us-central1",
    service = "tabula-api",
    smoke_path = "/health",
)

# Delivery unit (delivery-orchestrator PHASE 2, spec §6). The generated
# .github/workflows/delivery.yaml now owns tabula-api's ENTIRE ladder --
# development on an affected push, nonproduction+production on a published
# `tabula-api-v*` release -- and tabula-deploy.yaml has lost both its `push:`
# and its `release:` triggers, keeping only workflow_dispatch as a shell
# pending its Phase-3 deletion.
#
# Detection inputs are TRANSCRIBED from that workflow's `gate` job so a verdict
# stays A/B-comparable against the legacy gate during the migration:
#   deploy-targets:    //tabula/api:image_push //tabula/extension:chrome_zip
#   extra-path-regex:  tabula/infra/app/|tabula/infra/web/|tabula/web/|tools/deploy/|...
# tabula-web carries the SAME pair, deliberately: the dev banner clears only
# when the published extension bundle's commit equals the deployed API's, so a
# commit that moves either must re-stamp both (the coupling the single legacy
# gate encoded for both services).
delivery(
    name = "tabula-api",
    # The `with:` map for _changelog-summary.yaml -- verbatim from
    # tabula-deploy.yaml's `changelog` job.
    changelog_inputs = {
        "label": "tabula-api",
        "working-directory": "tabula/api",
    },
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
        "\\.github/workflows/_deploy-cloud-run\\.yaml",
    ],
    # _deploy-cloud-run.yaml binds `environment: <app-name>-<environment>`, so
    # this pattern IS the GitHub Environment set (tabula-development/-nonproduction/
    # -production) plus tabula-build for the shared build job.
    github_environment = "tabula-{env}",
    graph_targets = [
        "//tabula/api:image_push",
        "//tabula/extension:chrome_zip",
    ],
    # ONE build job (`tabula-build`) pushes both images; this unit deploys the
    # API one. tabula-web reads web-image-digest from the same job.
    image_digest_output = "image-digest",
    kind = "cloud-run",
    # PHASE 3 (spec §4.5). tabula/infra/app ships cmd/revname, so the desired
    # revision name (config hash + image digest) can be compared against the
    # live serving revision: EQUAL means the running service already IS what a
    # deploy would produce, and the migrate + blue-green + smoke are redundant.
    # This renders `skip-if-unchanged: true` onto every rung; the check runs
    # inside the deploy job (_deploy-cloud-run.yaml), which is the only place
    # the built digest it needs exists. Fail-open by construction:
    # tools/ci/tabula-deploy-preflight.sh only ever answers "unchanged" when
    # BOTH names were read successfully AND are equal.
    preflight = "revision-name",
    # ONE SANCTIONED DIVERGENCE FROM LEGACY, stated where it is decided.
    # tabula-deploy.yaml's promotion jobs fire on EITHER tabula tag
    # (`startsWith(tag, 'tabula-api-v') || startsWith(tag, 'tabula-web-v')`) for
    # BOTH services, so cutting a tabula-web release also promoted the API --
    # i.e. it shipped whatever was on main to production without an API release
    # PR ever being reviewed. Each generated unit promotes on its OWN tag
    # instead. Strictly narrower, never wider: an api-only release still
    # promotes the api, and the web service promotes when ITS release is cut.
    # //tools/delivery/gen's TestTabulaTagScopingIsNarrowerThanLegacy pins both
    # halves, so this stops being a divergence the day legacy is deleted.
    promotion = "release:tabula-api-v",
    run = "//tabula/infra/app:deploy",
    shared_build = "tabula",
    soak = True,
    # Copied VERBATIM from tabula-deploy.yaml's `deploy-dev-api` job (its
    # comments live there); //tools/delivery/gen's parity test asserts this map
    # still equals that one. `environment` and `image-digest` are deliberately
    # absent -- the ladder and the shared build job supply them.
    workflow_inputs = {
        "app-name": "tabula",
        "cloudflare-token-secret-project": "prj-d-bu2-oss-floating-c3d1",
        "default-region": "us-central1",
        "env-prefix": "TABULA",
        "pulumi-dir": "tabula/infra/app",
        "pulumi-refresh": True,
        "run-migrations": True,
        "secret-prefix": "TABULA_",
        "service-name": "tabula-api",
        "smoke-url-path": "/health",
        "workload-migrated": False,
    },
)
