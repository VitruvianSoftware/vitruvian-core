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
