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

"""Read-only look at a Cloud Run service or revision.

  bazel run //tools/gcp-cloudrun:describe -- --app oauth-user-inspector --env dev \\
      --service oauth-user-inspector-development

Resolves the project from infrastructure/gcp-identities.tsv (or the app's
Pulumi.<env>.yaml), mints a token with //tools/gcp-token, and runs only
`gcloud run services|revisions describe|list` and `gcloud logging read`.
Every argv goes through one guard that refuses any other verb.
See tools/gcp-cloudrun/README.md.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "gcp_cloudrun_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "gcp_cloudrun",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "describe",
    srcs = ["src/main.rs"],
    data = ["//tools/gcp-token"],
    edition = "2021",
    env = {"GCP_CLOUDRUN_GCP_TOKEN": "$(rootpath //tools/gcp-token)"},
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gcp_cloudrun_lib"],
)

rust_test(
    name = "gcp_cloudrun_lib_test",
    size = "small",
    crate = ":gcp_cloudrun_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
