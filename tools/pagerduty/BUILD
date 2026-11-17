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

"""Read-only PagerDuty API reads, with contact details masked.

  bazel run //tools/pagerduty:read -- /schedules
  bazel run //tools/pagerduty:read -- /users/<id>/contact_methods
  bazel run //tools/pagerduty:read -- /users/<id>/notification_rules

GET only, to https://api.pagerduty.com only. The token comes from
PAGERDUTY_TOKEN, PAGERDUTY_API_KEY or ~/.config/pagerduty/api-key. Changes to
the account belong to //infrastructure/pulumi/platform/pagerduty.
"""

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "pagerduty_lib",
    srcs = ["src/lib.rs"],
    crate_name = "pagerduty",
    crate_root = "src/lib.rs",
    edition = "2021",
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "read",
    srcs = ["src/main.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [
        ":pagerduty_lib",
        "@crates//:serde_json",
    ],
)

rust_test(
    name = "pagerduty_lib_test",
    size = "small",
    crate = ":pagerduty_lib",
    edition = "2021",
)
