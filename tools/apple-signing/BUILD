"""The Developer ID certificate and notary API key that sign the Vitruvian app.

  bazel run //tools/apple-signing -- csr
  bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <AuthKey_*.p8>
  bazel run //tools/apple-signing -- check

Asking Apple for the certificate and creating the API key are the two steps
that cannot live here: Apple has no API for them and both need the account
holder signed in. See README.md.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "apple-signing",
    srcs = ["apple-signing.sh"],
    visibility = ["//visibility:public"],
)

# Offline: gh, bw, xcrun and security are fakes; the certificate is a throwaway.
sh_test(
    name = "apple-signing_test",
    size = "small",
    srcs = ["apple-signing_test.sh"],
    data = ["apple-signing.sh"],
)
