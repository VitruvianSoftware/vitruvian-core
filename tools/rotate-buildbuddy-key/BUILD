# `bazel run //tools/rotate-buildbuddy-key` — guided BuildBuddy API-key rotation
# (issue #456). Automates the non-secret steps; prompts the operator to mint the
# new key and revoke the old one in the BuildBuddy console. The new value is read
# without echo and piped to `gh secret set` over stdin — never printed or logged.
# See rotate.sh.

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "rotate-buildbuddy-key",
    srcs = ["rotate.sh"],
    visibility = ["//visibility:public"],
)

exports_files(["rotate.sh"])
