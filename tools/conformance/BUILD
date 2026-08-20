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
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "check",
    srcs = ["check.sh"],
    data = [
        "delivery-legacy.tsv",
        "version-pins.tsv",
    ],
    visibility = ["//visibility:public"],
)

# Regression guard for check.sh's arms whose failure mode is SILENCE. check.sh is
# a data dep rather than a src: the test execs it as a subprocess against a
# throwaway ROOT it builds itself (BUILD_WORKSPACE_DIRECTORY), so the assertions
# are hermetic — no file in the real tree can flip them. Deliberately NOT
# covering all of check.sh; the arms here are the ones guarding a control that
# can be green while not in force (merge-queue trigger filters, renovate's
# cadence window), which is a failure a missing check cannot produce.
sh_test(
    name = "check_test",
    size = "small",
    srcs = ["check_test.sh"],
    data = ["check.sh"],
)

# Test-the-guard for check_delivery (the delivery-orchestrator arms). Kept as
# its own sh_test rather than folded into check_test.sh because it is a
# different subject with its own fixture shape (BUILD files carrying delivery()
# blocks, a legacy TSV, a generated workflow) — and because the two files are
# owned by different changes and would otherwise collide on every edit.
#
# Same hermetic contract as check_test: check.sh is a data dep, executed as a
# subprocess against a throwaway BUILD_WORKSPACE_DIRECTORY the test builds
# itself, so no file in the real tree can flip these assertions.
# size = "small" (60s) with ~12s of headroom measured on macOS, which is the
# PESSIMISTIC platform here: this test's cost is ~13 check.sh subprocesses and
# a few hundred forks each, and macOS process spawn is several times slower
# than the Linux runner's. Kept deliberately cheap -- the mutation-verb arm
# seeds all six verbs into one root rather than paying a check.sh run per verb.
sh_test(
    name = "conformance-delivery_test",
    size = "small",
    srcs = ["conformance-delivery_test.sh"],
    data = ["check.sh"],
)
