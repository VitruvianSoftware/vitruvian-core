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

load("//tools/delivery:defs.bzl", "delivery")
load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

# `bazel run //infrastructure/pulumi/platform/pagerduty:{setup,preview,config}`.
# Never run `:up` from a laptop; CI applies the production stack after merge.
exports_files(
    [
        "go.mod",
        "go.sum",
    ],
    visibility = ["//.github/actions/setup-go:__pkg__"],
)

pulumi_project(
    name = "pagerduty",
    dir = "infrastructure/pulumi/platform/pagerduty",
)

# Validates committed stack config, token resolution, plaintext token guard,
# and Pulumi resource wiring under mocks.
pulumi_go_test(
    # Cold `go test` compilation of the Pulumi SDKs can exceed the 300 s default.
    timeout = "long",
    extra_data = ["Pulumi.production.yaml"],
)

# Applies the production stack from .github/workflows/delivery-pagerduty.yaml
# on every push to main that touches it (and on dispatch). PAGERDUTY_TOKEN is
# the pagerduty-production GitHub Environment's secret (main only, declared in
# repo-config). With no token there yet, the job emits a notice and applies
# nothing so main stays green. The job's steps live in //tools/delivery/gen
# (render_pagerduty_steps): this stack never had a hand-written workflow.
delivery(
    name = "pagerduty",
    app = "pagerduty",
    environments = [
        "production",
    ],
    exclude_paths = [
        "infrastructure/pulumi/platform/pagerduty/(.*/)?README\\.md$",
    ],
    extra_paths = [
        "infrastructure/pulumi/platform/pagerduty/",
    ],
    github_environment = "pagerduty-{env}",
    kind = "pulumi",
    render = "transcribed",
    run = "//infrastructure/pulumi/platform/pagerduty:up",
)
