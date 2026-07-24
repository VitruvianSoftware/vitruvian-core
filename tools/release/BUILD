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

# Break-glass local release publisher: the PUBLISH half (npm publish + Go-module
# tags) of a mirror release, for when GitHub Actions is down. The EXPORT half is
# //tools/copybara/sync. GoReleaser binaries + nexus-agent stay manual (runbook).
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["publish-local.sh"])

sh_binary(
    name = "publish-local",
    srcs = ["publish-local.sh"],
    visibility = ["//visibility:public"],
)

# Regression guard for the slash-form Go-module tag (the cloud_run "unknown
# revision" bug). Runs under `bazel test //...`.
sh_test(
    name = "publish-local_test",
    srcs = ["publish-local_test.sh"],
    args = ["$(location publish-local.sh)"],
    data = ["publish-local.sh"],
)
