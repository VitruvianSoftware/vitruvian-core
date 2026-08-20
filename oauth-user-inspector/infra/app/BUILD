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
    name = "oauth-user-inspector",
    dir = "oauth-user-inspector/infra/app",
)

# One-command local blue-green deploy -- the SAME rollout CI runs
# (oauth-user-inspector-deploy.yaml), so a break-glass laptop and CI execute
# identical code. oauth builds its image once in the infra-pipeline project and
# promotes by digest, so pass --image-digest; it is stateless (no migrations).
# E.g.:
#   bazel run //oauth-user-inspector/infra/app:deploy -- \
#     --env development --project prj-d-bu1-oss-floating-648a --image-digest <ref@sha256:..>
cloud_run_deploy(
    name = "deploy",
    # Reachable AND the React SPA actually mounts (see smoke.sh) -- kept in sync
    # with oauth-user-inspector-deploy.yaml's custom-smoke-script.
    custom_smoke_script_file = "oauth-user-inspector/infra/app/smoke.sh",
    env_prefix = "OAUTH_USER_INSPECTOR",
    pulumi_dir = "oauth-user-inspector/infra/app",
    region = "us-central1",
    service = "oauth-user-inspector",
    smoke_path = "/",
)

# Delivery unit. PHASE 1 (spec §6): the DEVELOPMENT rung is delivered by the
# generated .github/workflows/delivery.yaml — oauth-user-inspector-deploy.yaml
# has lost its `push:` trigger and now only serves the release-gated
# nonproduction→production ladder and the workflow_dispatch break-glass.
# extra/exclude paths mirror that workflow's gate regexes verbatim, so a shadow
# verdict stays comparable against the live legacy gate during the A/B.
delivery(
    name = "oauth-user-inspector",
    build = "",  # standalone Docker Buildx build; no bazel image target
    # How the image is produced. These two are the ONLY parts of the build the
    # declaration owns; the region and project come from the build GitHub
    # Environment's vars, exactly as they did in the hand-written build job:
    #   IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/oauth-user-inspector/app"
    #   docker buildx build --push ... oauth-user-inspector/
    build_context = "oauth-user-inspector/",
    companions = ["zitadel-apps"],
    environments = [
        "development",
        "nonproduction",
        "production",
    ],
    exclude_paths = ["oauth-user-inspector/infra/identity/"],
    extra_paths = [
        "oauth-user-inspector/",
        "infrastructure/pulumi/platform/zitadel-apps/",
        "tools/deploy/",
        "\\.github/workflows/oauth-user-inspector-deploy\\.yaml",
        "\\.github/workflows/_deploy-cloud-run\\.yaml",
        "\\.github/workflows/_zitadel-apps-apply\\.yaml",
    ],
    github_environment = "oauth-user-inspector-{env}",
    image_repository_path = "oauth-user-inspector/app",
    kind = "cloud-run",
    promotion = "release:oauth-user-inspector-v",
    run = "//oauth-user-inspector/infra/app:deploy",
    # The `with:` map the generated development job passes to
    # _deploy-cloud-run.yaml. Every entry below is copied VERBATIM from
    # oauth-user-inspector-deploy.yaml's `deploy-dev` job (its comments live
    # there); //tools/delivery/gen's TestGeneratedDevLaneMatchesLegacy asserts
    # this map still equals that one, so the two cannot drift apart silently
    # while both exist.
    #
    # TWO KEYS ARE DELIBERATELY ABSENT, both supplied by the generator because
    # neither is a fact this declaration can know:
    #   - `environment`  comes from environments[0] (the ladder), so a
    #     declaration cannot make its development job deploy production.
    #   - `image-digest` comes from the generated `<unit>-build` job's output
    #     (`needs.oauth-user-inspector-build.outputs.image-digest`), which is a
    #     job NAME the generator owns. Build-once/promote-by-digest is not
    #     optional for this app: infra/app/main.go takes ONLY
    #     OAUTH_USER_INSPECTOR_IMAGE_DIGEST and documents "deliberately no
    #     mutable-tag fallback", so a tag-based deploy fails at `pulumi up`.
    workflow_inputs = {
        "app-name": "oauth-user-inspector",
        "cloudflare-token-secret-project": "prj-d-bu1-oss-floating-648a",
        "custom-smoke-script-file": "oauth-user-inspector/infra/app/smoke.sh",
        "default-region": "us-central1",
        "env-prefix": "OAUTH_USER_INSPECTOR",
        "pulumi-dir": "oauth-user-inspector/infra/app",
        "service-name": "oauth-user-inspector",
        "workload-migrated": False,
    },
)
