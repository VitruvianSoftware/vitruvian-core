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
"""Bazel macro wrapping ArgoCD/GitOps manifests behind `bazel run` targets.

No ad-hoc kubectl. Apply/delete/diff a component's manifests only via, e.g.:

    bazel run //gitops/argocd/platform/opentelemetry-operator:apply
    bazel run //gitops/argocd/platform/opentelemetry-operator:diff
    bazel run //gitops/argocd/platform/opentelemetry-operator:delete

The wrapper (//tools/gitops:gitops_cmd.sh) injects KUBECONFIG + context and
operates on the working tree, mirroring //tools/pulumi.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def gitops_manifest(name, manifests, visibility = ["//visibility:public"]):
    """Generate :apply/:delete/:diff run targets for a package's manifests.

    Args:
      name: unique handle (developer-facing names are fixed: apply/delete/diff).
      manifests: manifest files in THIS package (package-relative).
      visibility: target visibility.
    """
    pkg = native.package_name()
    file_args = []
    for m in manifests:
        file_args += ["-f", (pkg + "/" + m) if pkg else m]
    for sub in ("apply", "delete", "diff"):
        sh_binary(
            name = sub,
            srcs = ["//tools/gitops:gitops_cmd.sh"],
            args = [sub] + file_args,
            data = manifests,
            visibility = visibility,
        )
