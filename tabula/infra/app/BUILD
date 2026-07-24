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
