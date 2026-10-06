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
load("//tools/pulumi:defs.bzl", "pulumi_project")

pulumi_project(
    name = "zitadel-apps",
    dir = "infrastructure/pulumi/platform/zitadel-apps",
)

# Delivery unit (Phase 0: SHADOW; _zitadel-apps-apply.yaml remains the acting
# path until Phase 1). The expand half of oauth's expand-before-serve pair.
delivery(
    name = "zitadel-apps",
    # A companion applies inside its consumer's ladder, so it delivers
    # through the consumer's workflow (.github/workflows/delivery-oauth-user-inspector.yaml).
    app = "oauth-user-inspector",
    environments = [
        "development",
        "nonproduction",
        "production",
    ],
    extra_paths = [
        "infrastructure/pulumi/platform/zitadel-apps/",
        "\\.github/workflows/_zitadel-apps-apply\\.yaml",
    ],
    github_environment = "oauth-user-inspector-{env}",
    kind = "pulumi",
    promotion = "release:oauth-user-inspector-v",
    run = "//infrastructure/pulumi/platform/zitadel-apps:up",
)
