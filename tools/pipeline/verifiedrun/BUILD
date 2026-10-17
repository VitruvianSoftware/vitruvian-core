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

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

# `bazel run //tools/pipeline/verifiedrun` -- runs a change's PR tests on the
# remote build machines and records a pass against the exact code (#3418).
# See README.md.

go_library(
    name = "verifiedrun_lib",
    srcs = [
        "main.go",
        "record.go",
        "shim.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/verifiedrun",
    visibility = ["//visibility:private"],
    deps = ["//tools/pipeline/unitfile"],
)

go_binary(
    name = "verifiedrun",
    args = [
        "--planner=$(rlocationpath //tools/pipeline/plan)",
        "--agent-app=$(rlocationpath //tools/agent-app:agent-app.sh)",
    ],
    data = [
        "//tools/agent-app:agent-app.sh",
        "//tools/pipeline/plan",
    ],
    embed = [":verifiedrun_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "verifiedrun_test",
    size = "small",
    srcs = [
        "main_test.go",
        "record_test.go",
        "shim_test.go",
    ],
    data = ["recorder.tsv"],
    embed = [":verifiedrun_lib"],
    deps = ["//tools/pipeline/unitfile"],
)
