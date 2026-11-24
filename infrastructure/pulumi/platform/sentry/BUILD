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

load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

# `bazel run //infrastructure/pulumi/platform/sentry:{setup,preview,up,config}`.
# Applied in CI by .github/workflows/sentry-apply.yaml over the Headscale mesh
# (Envoy Gateway https-sentry NodePort :31103), with `sentry-production`
# holding SENTRY_TOKEN + HEADSCALE_CI_AUTHKEY.
exports_files(
    [
        "go.mod",
        "go.sum",
    ],
    visibility = ["//.github/actions/setup-go:__pkg__"],
)

pulumi_project(
    name = "sentry",
    dir = "infrastructure/pulumi/platform/sentry",
)

# Checks committed stack config (secret/unknown-key guards) and the
# organization privacy settings, dashboards, and inbound filters under mocks.
pulumi_go_test(
    # Cold `go test` compilation of the Pulumi SDKs can exceed the 300 s default.
    timeout = "long",
    extra_data = [
        "Pulumi.production.yaml",
    ],
)
