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

# `bazel run //tools/ci:gen` — regenerate the generated delivery workflow
# (.github/workflows/delivery.yaml). Alias kept at the spec's name; the
# implementation lives in //tools/delivery/gen.
alias(
    name = "gen",
    actual = "//tools/delivery/gen",
    visibility = ["//visibility:public"],
)

# The orchestrator's hermetic tests drive the REAL decision engine (spec §4.2:
# deploy-affected.sh is shelled, never rewritten), so the scripts must be
# visible as runfiles to //tools/delivery/orchestrate:orchestrate_test.
exports_files([
    "deploy-affected.sh",
    "td-lib.sh",
])
