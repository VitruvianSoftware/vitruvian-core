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

# `bazel run //infrastructure/pulumi/platform/stripe:{setup,preview,config}`.
# No :up from a laptop (AGENTS.md): the delivery() unit below applies it.
pulumi_project(
    name = "stripe",
    dir = "infrastructure/pulumi/platform/stripe",
)

# Validates both committed stack configs and the key-mode guard. The tests read
# Pulumi.sandbox.yaml and Pulumi.production.yaml, so they are passed in as data.
pulumi_go_test(
    # The default (moderate, 300 s) is too tight: a cold `go test` build of the
    # Pulumi SDKs alone takes ~100 s, and in a full //... sweep it timed out
    # at 300 s (#4402). Same fix as gcp-bootstrap. "long" allows 900 s.
    timeout = "long",
    extra_data = [
        "Pulumi.production.yaml",
        "Pulumi.sandbox.yaml",
        # The replace in go.mod points here; glob("go.mod") only matches the
        # top-level one.
        "sdks/stripe/go.mod",
        # internal/donations/donations_pages_test.go: every app's link has its
        # page on the site.
        "//apps/web/vitruviansoftware-dev:donate_pages",
        # ...and every Sponsor button opens one of those pages.
        "//:.github/FUNDING.yml",
        "//:apps/desktop/courier/.github/FUNDING.yml",
        "//:packages/pulumi/library/.github/FUNDING.yml",
        "//packages/pulumi/examples:go-foundation/.github/FUNDING.yml",
        "//packages/pulumi/examples:ts-foundation/.github/FUNDING.yml",
        "//apps/antigravity/plugins/gh-watch:.github/FUNDING.yml",
        "//apps/cli/vitruvian-devx:.github/FUNDING.yml",
        "//apps/cli/vitruvian-homelab:.github/FUNDING.yml",
        "//apps/desktop/home-speaker:.github/FUNDING.yml",
        "//apps/desktop/vitruvian:.github/FUNDING.yml",
        "//apps/desktop/vitruvian-code:.github/FUNDING.yml",
        "//apps/desktop/vitruvian-tool-github:.github/FUNDING.yml",
        "//apps/embedded/esp32-s3:.github/FUNDING.yml",
        "//apps/mcp/roborock:.github/FUNDING.yml",
        "//apps/mcp/slack:.github/FUNDING.yml",
        "//apps/mobile/android-remote:.github/FUNDING.yml",
        "//apps/web/oauth-user-inspector:.github/FUNDING.yml",
        "//apps/web/vitruviansoftware-dev:.github/FUNDING.yml",
        "//packages/vitruvian-sdk:.github/FUNDING.yml",
        "//infrastructure/pulumi/platform/repo-config:sponsor-button-repos.txt",
    ],
)

# Applies the stacks from .github/workflows/delivery-stripe.yaml, in order, on
# every push to main that touches them (and on dispatch):
#   1. sandbox (test mode). Refuses a key that is not sk_test_/rk_test_ and a
#      stack config whose mode is not "test".
#   2. production (live mode, real money). Starts only after the sandbox
#      ACTUALLY applied in the same run, waits for the stripe-production
#      Environment's required reviewer, and refuses a key that is not
#      sk_live_/rk_live_ and a config whose mode is not "live".
# The program refuses a mismatched key again. Each key is its Environment's
# STRIPE_API_KEY secret (main only, declared in repo-config). With no key there
# yet, a rung says so and applies nothing, and production stays shut. The
# job's steps live in //tools/delivery/gen (render_stripe_steps): this stack
# never had a hand-written workflow.
delivery(
    name = "stripe",
    app = "stripe",
    environments = [
        "sandbox",
        "production",
    ],
    extra_paths = [
        "infrastructure/pulumi/platform/stripe/",
    ],
    github_environment = "stripe-{env}",
    kind = "pulumi",
    render = "transcribed",
    run = "//infrastructure/pulumi/platform/stripe:up",
)
