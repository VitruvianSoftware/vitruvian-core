"""Store or rotate a GitHub App's private key as a repo secret.

  bazel run //tools/github-app-key -- renovate        # finds the .pem in ~/Downloads
  bazel run //tools/github-app-key -- --list          # which Apps it knows

GitHub cannot automate "Generate a private key" in the App's settings. This
does everything after it: proves the key belongs to the right App (by signing
an App JWT and asking GitHub), checks the App is installed and -- where it must
be -- NOT a merge-queue bypass actor, stores it with `gh secret set` over stdin
(never printed), then offers to delete the download. See set-key.sh.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "github-app-key",
    srcs = ["set-key.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "set-key_test",
    size = "small",
    srcs = ["set-key_test.sh"],
    data = ["set-key.sh"],
)
