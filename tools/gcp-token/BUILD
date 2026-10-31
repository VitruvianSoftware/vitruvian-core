"""Short-lived GCP access tokens, minted over the tailnet when this machine has none.

  bazel run //tools/gcp-token -- james@vitruviansoftware.dev

A Claude Code *cloud* session has no GCP credentials and no human at a browser to
run `gcloud auth login`. The obvious fix -- a service-account key on the cloud
environment -- is refused by this org's own policy
(`iam.disableServiceAccountKeyCreation`, enforced in
//infrastructure/pulumi/foundation/gcp-org, comment: "prevent SA key sprawl"), and
working around a control we deliberately set is the wrong move.

But a cloud session is already ON THE TAILNET with passwordless SSH to the homelab.
A node that is already logged in can mint a token on demand, so the session holds
only a ~1h access token and NO long-lived credential exists on the cloud
environment at all -- no key, no refresh token, nothing to rotate, no org-policy
exception. Tailnet membership is the authentication factor.

Local credentials always win, so the same command works on a laptop, in CI and in
a cloud session -- which is why //tools/pulumi can call it unconditionally.

See tools/gcp-token/README.md and docs/admin/claude-code-cloud-sessions.md.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "gcp_token_lib",
    srcs = ["src/lib.rs"],
    crate_name = "gcp_token",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["//tools/shell-compat:shell_compat"],
)

rust_binary(
    name = "gcp-token",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":gcp_token_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

rust_test(
    name = "gcp_token_lib_test",
    size = "small",
    crate = ":gcp_token_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "gcp-token_test",
    tests = [":gcp_token_lib_test"],
)

test_suite(
    name = "gcp_token_test",
    tests = [":gcp_token_lib_test"],
)
