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

"""One-shot, idempotent bootstrap for Sentry's PagerDuty integration.

  bazel run //tools/sentry:pagerduty-install -- --subdomain vitruviansoftware --name "Vitruvian Software"

See tools/sentry/README.md.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "sentry_lib",
    srcs = [
        "src/http.rs",
        "src/lib.rs",
    ],
    crate_name = "sentry_tools",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "pagerduty-install",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":sentry_lib"],
)

rust_test(
    name = "sentry_lib_test",
    size = "small",
    crate = ":sentry_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "pagerduty_install_test",
    size = "small",
    srcs = ["tests/pagerduty_install_test.rs"],
    crate_root = "tests/pagerduty_install_test.rs",
    data = [":pagerduty-install"],
    edition = "2021",
    env = {"PAGERDUTY_INSTALL_BIN": "$(rootpath :pagerduty-install)"},
    rustc_flags = ["-Copt-level=3"],
    deps = ["@crates//:serde_json"],
)
