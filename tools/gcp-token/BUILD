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

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["gcp-token.sh"])

# The tool, in Rust (src/): gcp-token.sh's sources, order, argv, stdout,
# stderr and exit codes, held to the script by the parity test below.
# Optimised in every build mode.
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

alias(
    name = "gcp-token-rs",
    actual = ":gcp-token",
    visibility = ["//visibility:public"],
)

alias(
    name = "gcp_token_rs",
    actual = ":gcp-token",
    visibility = ["//visibility:public"],
)

# The shell original, kept runnable and held to the port by the parity test.
# //tools/pulumi's wrapper still runs gcp-token.sh directly.
sh_binary(
    name = "gcp-token-sh",
    srcs = ["gcp-token.sh"],
    visibility = ["//visibility:public"],
)

# Hermetic guard for the properties whose failure would be a credential leak, a
# wrong identity, or a non-credential exported as one: local creds preferred and
# the network untouched; the broker used only as a fallback and asked for the
# REQUESTED account; stdout the bare token so `$(...)` capture is clean; the token
# absent from stderr; a metacharacter account refused before it reaches the remote
# command line; a short/garbage reply refused rather than exported; and an
# unreachable broker fatal with an actionable message.
sh_test(
    name = "gcp-token_test",
    size = "small",
    srcs = ["gcp-token_test.sh"],
    data = ["gcp-token.sh"],
)

# The same suite, run against the Rust binary (GCP_TOKEN_BIN).
sh_test(
    name = "gcp-token-rs_test",
    size = "small",
    srcs = ["gcp-token_test.sh"],
    data = [
        "gcp-token.sh",
        ":gcp-token",
    ],
    env = {"GCP_TOKEN_BIN": "$(rootpath :gcp-token)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "gcp_token_lib_test",
    size = "small",
    crate = ":gcp_token_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in gcp_token_rs_parity_test.py:
# exit code, stdout, stderr, the calls made to gcloud/pulumi/ssh and the
# broker cache left behind, compared byte for byte.
py_test(
    name = "gcp_token_rs_parity_test",
    size = "medium",
    srcs = ["gcp_token_rs_parity_test.py"],
    data = [
        "gcp-token.sh",
        ":gcp-token",
    ],
    env = {
        "GCP_TOKEN_RS": "$(rootpath :gcp-token)",
        "GCP_TOKEN_SH": "$(rootpath gcp-token.sh)",
    },
    main = "gcp_token_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)

alias(
    name = "gcp_token_test",
    actual = ":gcp-token_test",
    deprecation = "Target :gcp_token_test is deprecated. Use :gcp-token_test instead. Will be removed in Phase 5.",
)
