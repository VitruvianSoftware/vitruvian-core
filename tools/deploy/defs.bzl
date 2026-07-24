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
"""Bazel macro for a per-app local/CI Cloud Run deploy target.

`cloud_run_deploy` bakes an app's FIXED deploy parameters (service name, env
prefix, pulumi dir, region, smoke path) into a `:deploy` `bazel run` target that
wraps //tools/deploy:cloud-run — the blue-green (candidate -> smoke -> promote)
sequencer. The operator supplies the per-invocation values after `--`:

    bazel run //tabula/infra/app:deploy -- \\
        --env development --project prj-d-bu2-oss-floating-c3d1 \\
        --image-digest <ref@sha256:..>

The same target runs in CI, so a GitHub Actions outage never blocks a deploy
(ops-as-bazel-targets). Auth is resolved by the shared pulumi wrapper (WIF in
CI, the pinned human identity locally), not here.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def cloud_run_deploy(
        name = "deploy",
        service = None,
        env_prefix = None,
        pulumi_dir = None,
        region = None,
        smoke_path = "/",
        custom_smoke_script = None,
        custom_smoke_script_file = None,
        refresh = False,
        visibility = ["//visibility:public"]):
    """Generate a per-app `:deploy` run target wrapping //tools/deploy:cloud-run.

    Args:
      name: target name (default "deploy").
      service: Cloud Run service base name, e.g. "tabula-api" (the stack env is
        appended at run time, e.g. tabula-api-development).
      env_prefix: the <PREFIX>_ env-var namespace the Pulumi program reads, e.g.
        "TABULA".
      pulumi_dir: workspace-relative Pulumi project dir, e.g. "tabula/infra/app".
      region: GCP region, e.g. "us-central1".
      smoke_path: HTTP path to smoke on the candidate, e.g. "/health".
      custom_smoke_script: optional shell run against $CAND instead of a plain GET.
      refresh: pass --refresh to the underlying `pulumi up` (e.g. tabula's
        DomainMapping heal, mirroring the deploy workflow's pulumi-refresh: true).
      visibility: target visibility.
    """
    if not (service and env_prefix and pulumi_dir and region):
        fail("cloud_run_deploy requires service, env_prefix, pulumi_dir, region")
    args = [
        "--service",
        service,
        "--env-prefix",
        env_prefix,
        "--pulumi-dir",
        pulumi_dir,
        "--region",
        region,
        "--smoke-path",
        smoke_path,
    ]
    if refresh:
        args.append("--refresh")
    if custom_smoke_script and custom_smoke_script_file:
        fail("cloud_run_deploy: set at most one of custom_smoke_script / custom_smoke_script_file")
    if custom_smoke_script:
        # sh_binary `args` undergo Bazel "Make variable" expansion, so a shell
        # `$` (e.g. ${CAND}) must be escaped to `$$` to reach the shell literally.
        # NB: a MULTI-line inline script is word-split by the bazel-run launcher --
        # use custom_smoke_script_file for anything beyond a one-liner.
        args += ["--custom-smoke-script", custom_smoke_script.replace("$", "$$")]
    if custom_smoke_script_file:
        # A workspace-relative path; the tool reads it from the source tree.
        args += ["--custom-smoke-script-file", custom_smoke_script_file]
    sh_binary(
        name = name,
        srcs = ["//tools/deploy:cloud-run.sh"],
        args = args,
        visibility = visibility,
    )
