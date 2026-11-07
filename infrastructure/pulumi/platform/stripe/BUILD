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

# Validates the committed sandbox config and the key-mode guard. The test reads
# Pulumi.sandbox.yaml, so it is passed in as data.
pulumi_go_test(
    extra_data = [
        "Pulumi.sandbox.yaml",
        # The replace in go.mod points here; glob("go.mod") only matches the
        # top-level one.
        "sdks/stripe/go.mod",
    ],
)

# Applies the stack to the Stripe SANDBOX on every push to main that touches it
# (and on dispatch), from .github/workflows/delivery-stripe.yaml. One rung, test
# mode only: the job refuses a key that is not sk_test_/rk_test_ and a stack
# config whose mode is not "test", and the program refuses a mismatched key
# again. The key is the stripe-sandbox Environment's STRIPE_API_KEY secret
# (main only, declared in repo-config). With no key there yet, the job says so
# and applies nothing. The job's steps live in //tools/delivery/gen
# (render_stripe_steps): this stack never had a hand-written workflow.
delivery(
    name = "stripe",
    app = "stripe",
    environments = ["sandbox"],
    extra_paths = [
        "infrastructure/pulumi/platform/stripe/",
    ],
    github_environment = "stripe-{env}",
    kind = "pulumi",
    render = "transcribed",
    run = "//infrastructure/pulumi/platform/stripe:up",
)
