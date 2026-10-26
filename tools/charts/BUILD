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

"""Helm chart publishing.

The charts themselves are co-located with the apps they deploy
(tabula/deploy/chart, oauth-user-inspector/deploy/chart,
mcp-slack/deploy/chart), so no single app package owns "publish the charts" --
it is a repo-wide operation over a glob. This tool package owns it, which is
also where its delivery() unit is declared.

  bazel run //tools/charts:publish     # break-glass: package + push every
                                       # changed chart to GHCR
"""

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/delivery:defs.bzl", "delivery")

# gazelle:ignore

exports_files(["publish.sh"])

# The break-glass entry point. CI runs the SAME script directly
# (`bash tools/charts/publish.sh`, no Bazel on the runner's critical path);
# this target is what makes the delivery() declaration below nameable and what
# the runbook points at when Actions is unavailable. It is the Rust port in
# src/ (publish.sh's scoping, walk, helm calls and exit codes, held to the
# script by the parity test below); the script itself stays runnable as
# :publish-sh.
rust_library(
    name = "charts_lib",
    srcs = ["src/lib.rs"],
    crate_name = "charts",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "publish",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":charts_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":publish",
        visibility = ["//visibility:public"],
    )
    for name in [
        "publish-rs",
        "publish_rs",
    ]
]

sh_binary(
    name = "publish-sh",
    srcs = ["publish.sh"],
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "charts_lib_test",
    size = "small",
    crate = ":charts_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in publish_rs_parity_test.py
# (fake git and helm): exit code, stdout, stderr and every helm call, byte
# for byte, under every bash on the machine.
py_test(
    name = "publish_rs_parity_test",
    size = "medium",
    srcs = ["publish_rs_parity_test.py"],
    data = [
        "publish.sh",
        ":publish",
    ],
    env = {
        "PUBLISH_RS": "$(rootpath :publish)",
        "PUBLISH_SH": "$(rootpath publish.sh)",
    },
    main = "publish_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

# Delivery unit (delivery-orchestrator PHASE 2, Wave B2). The generated
# .github/workflows/delivery-charts.yaml now owns the push lane; charts-publish.yml
# keeps only workflow_dispatch until Phase 3 deletes it.
#
# WHY THE TRIGGER MOVE IS A FIX, not just a re-plumbing: the legacy workflow
# gated on `on.push.paths: ['**/deploy/chart/**']`, and a workflow-level path
# filter is evaluated over the range of the run that GitHub EVICTED from its
# coalescing concurrency group -- the #1351 shape, a permanent silent skip with
# no job to blame. The orchestrator decides from a durable base instead, and
# fails open.
delivery(
    name = "charts",
    app = "charts",
    environments = ["publish"],
    extra_paths = [
        # The legacy `**/deploy/chart/**` glob, as the ERE the affected engine
        # anchors at path start.
        ".*/deploy/chart/",
        # The publisher itself -- the same coupling //tools/conformance:check
        # enforces for tools/deploy/ on the Cloud Run lanes: the code that
        # performs the delivery must trigger the delivery. The legacy paths
        # list had neither this nor its own workflow file, so a change to the
        # publish logic never republished anything.
        "tools/charts/",
    ],
    # No GitHub Environment: the legacy publish job binds none (GHCR is reached
    # with the run's own GITHUB_TOKEN, and packages: write is a job permission,
    # not an environment secret).
    github_environment = "",
    kind = "publish",
    legacy_job = "publish",
    legacy_workflow = ".github/workflows/charts-publish.yml",
    render = "transcribed",
    run = "//tools/charts:publish",
)
