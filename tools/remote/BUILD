load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# Remote-build (RBE) setup helper.
#
# Run `bazel run //tools/remote:setup` in your repo to point Bazel at a remote
# builder (BuildBuddy by default, or any Remote Execution API provider) for both
# local and CI builds. It is dormant until you run it. See docs/remote-build.md.
sh_binary(
    name = "setup",
    srcs = ["setup.sh"],
    visibility = ["//visibility:public"],
)
