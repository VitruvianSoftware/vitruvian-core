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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["gcp-token.sh"])

sh_binary(
    name = "gcp-token",
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
    name = "gcp_token_test",
    size = "small",
    srcs = ["gcp-token_test.sh"],
    data = ["gcp-token.sh"],
)
