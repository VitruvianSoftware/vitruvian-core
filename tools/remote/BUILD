load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Remote-build (RBE) setup helper.
#
# Run `bazel run //tools/remote:setup` in your repo to point Bazel at a remote
# builder (BuildBuddy by default, or any Remote Execution API provider) for both
# local and CI builds. It is dormant until you run it. See docs/guides/remote-build.md.
sh_binary(
    name = "setup",
    srcs = ["setup.sh"],
    visibility = ["//visibility:public"],
)

# Regression tests for setup.sh's user.bazelrc output — the auth header must
# expand EXACTLY ONCE for any --config combination (the scoped-header doubling
# bug comma-joined the key into "KEY,KEY" under --config=remote).
sh_test(
    name = "setup_test",
    size = "small",
    srcs = ["setup_test.sh"],
    data = ["setup.sh"],
)
