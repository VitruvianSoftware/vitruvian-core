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

# The orchestrator's hermetic tests drive the REAL decision engine (spec §4.2:
# deploy-affected.sh is shelled, never rewritten), so the scripts must be
# visible as runfiles to //tools/delivery/orchestrate:orchestrate_test.
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# `bazel run //tools/ci:gen` — regenerate the generated delivery workflow
# (.github/workflows/delivery.yaml). Alias kept at the spec's name; the
# implementation lives in //tools/delivery/gen.
alias(
    name = "gen",
    actual = "//tools/delivery/gen",
    visibility = ["//visibility:public"],
)

exports_files([
    # Read by //tools/delivery/gen: every script the generated workflow shells
    # out to must exist -- the promotion interlock, and the durable-base
    # resolver the orchestrate job feeds BEFORE_REV from.
    "require-dev-soak.sh",
    "resolve-deploy-base.sh",
    "deploy-affected.sh",
    "td-lib.sh",
])

# The drift detector shells the SAME decision engine the orchestrator does, so
# the detector can never disagree with the decider about "affected". Its test
# therefore needs both scripts as runfiles and drives the real engine (only gh
# and bazel are stubbed).
sh_test(
    name = "delivery_drift_test",
    size = "small",
    srcs = ["delivery-drift_test.sh"],
    args = [
        "$(location delivery-drift.sh)",
        "$(location deploy-affected.sh)",
    ],
    data = [
        "delivery-drift.sh",
        "deploy-affected.sh",
        "td-lib.sh",
    ],
)
