load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_test")

# Remote-build (RBE) setup helper.
#
# Run `bazel run //tools/remote:setup` in your repo to point Bazel at a remote
# builder (BuildBuddy by default, or any Remote Execution API provider) for both
# local and CI builds. It is dormant until you run it. See docs/guides/remote-build.md.
#
# std only and a single crate, so it also builds with a bare
# `rustc --edition 2021 tools/remote/src/main.rs` where Bazel is not installed yet.
rust_binary(
    name = "setup",
    srcs = ["src/main.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
)

# Drives the real binary: the auth header must expand EXACTLY ONCE for any
# --config combination (the scoped-header doubling bug comma-joined the key into
# "KEY,KEY" under --config=remote), plus every mode, prompt and exit code, and
# parity with the retired shell script's outputs, recorded in testdata/setup_sh.golden.
rust_test(
    name = "setup_test",
    size = "small",
    srcs = ["src/tests.rs"],
    data = [
        "testdata/setup_sh.golden",
        ":setup",
        "//tools:remote.bazelrc",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :setup)",
        "COMMITTED_REMOTE_BAZELRC": "$(rootpath //tools:remote.bazelrc)",
        "GOLDEN": "$(rootpath testdata/setup_sh.golden)",
    },
)

# The source the session-start launcher (tools/cloud-bootstrap/cloud-bootstrap.sh)
# builds with plain rustc: guard-review checks it needs James's approval.
filegroup(
    name = "session_start_sources",
    srcs = ["src/main.rs"],
    visibility = [
        "//infrastructure/pulumi/platform/repo-config:__pkg__",
        "//tools/cloud-bootstrap:__pkg__",
    ],
)
