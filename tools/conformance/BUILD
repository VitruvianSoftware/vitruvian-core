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

# The repo version-conformance checker: `bazel run //tools/conformance:check`.
# A hand-authored portable-bash sh_binary that reads the live source tree via
# BUILD_WORKSPACE_DIRECTORY (so under `run` it does not strictly need the data
# dep to function), checking that every go.mod / Dockerfile-node / package.json
# matches the repo's canonical version, with deviations allowed only as justified
# temporary pins in version-pins.tsv. Keep gazelle out (it would emit a
# bzl_library with an unresolvable rules_shell dep, same as //tools/pulumi,
# //tools/gitops, and //tools/doctor).
# gazelle:ignore

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "check",
    srcs = ["check.sh"],
    data = ["version-pins.tsv"],
    visibility = ["//visibility:public"],
)
