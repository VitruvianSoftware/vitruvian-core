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
"""Bazel macro that wraps the shared `doctor` env-checker behind `bazel run`.

`doctor` is a single engine (`//tools/doctor:doctor.sh`) parameterized per
package via baked-in `args`. Each app declares which tools it needs; the macro
turns that into a `bazel run //<pkg>:doctor` target that checks the local
toolchain against the repo's source-of-truth files (.bazelversion / .nvmrc /
package.json / the app's go.mod) and exits non-zero if a REQUIRED tool is
missing or version-mismatched — making it a reliable pre-flight gate.

Example (in an app's BUILD file):

    load("//tools/doctor:defs.bzl", "doctor")

    doctor(
        name = "doctor",
        label = "tabula",
        required = ["bazel", "node", "pnpm", "git"],
        optional = ["docker", "gcloud"],
    )

A Go app additionally pins Go via its own go.mod:

    doctor(
        name = "doctor",
        label = "devx",
        gomod = "devx/go.mod",
        required = ["bazel", "go", "git"],
        optional = ["mage", "lima", "goreleaser"],
    )
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def doctor(
        name = "doctor",
        label = None,
        required = [],
        optional = [],
        gomod = None,
        # Private by default (#82): doctor targets are only ever `bazel run`
        # by label, which never checks visibility (it gates dep EDGES only).
        # A public default here would silently punch six macro-generated holes
        # in the inter-app firewall that the conformance literal-string scan
        # (tools/conformance/check.sh check_app_visibility) cannot see --
        # macro defaults never appear as "//visibility:public" in app BUILDs.
        visibility = ["//visibility:private"]):
    """Declare a `bazel run //<pkg>:doctor` env-checker for a package.

    Generates an `sh_binary` that runs the shared `//tools/doctor:doctor.sh`
    engine with this package's tool requirements baked into `args`. The engine
    reads EXPECTED versions from the repo's source-of-truth files (never
    hardcoded) and exits non-zero when a required tool fails its check.

    Args:
      name: target name (developer-facing label is typically `doctor`).
      label: human-readable scope shown in the report header (defaults to the
        package name if omitted).
      required: tool keys that MUST pass; a missing or major/minor-mismatched
        required tool (or a down docker daemon) fails the run (non-zero exit).
        Supported keys: bazel, node, pnpm, go, git, gh, gcloud, docker, direnv,
        mage, mise, lima, swift, python3, goreleaser (unknown keys -> presence
        only).
      optional: tool keys checked for info; missing/stopped only warns (exit
        stays 0).
      gomod: workspace-relative path to the app's go.mod; when set, the `go`
        tool is version-pinned to its `go X.Y.Z` directive.
      visibility: visibility for the generated target.
    """
    args = []
    if label:
        args += ["--label", label]
    if required:
        args += ["--required", ",".join(required)]
    if optional:
        args += ["--optional", ",".join(optional)]
    if gomod:
        args += ["--gomod", gomod]

    sh_binary(
        name = name,
        srcs = ["//tools/doctor:doctor.sh"],
        args = args,
        visibility = visibility,
    )
