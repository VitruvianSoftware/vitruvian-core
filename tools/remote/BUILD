load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

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
# parity with setup.sh run as an oracle over the same scenarios.
rust_test(
    name = "setup_test",
    size = "small",
    srcs = ["src/tests.rs"],
    data = [
        "setup.sh",
        "testdata/setup_sh.golden",
        ":setup",
        "//tools:remote.bazelrc",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :setup)",
        "COMMITTED_REMOTE_BAZELRC": "$(rootpath //tools:remote.bazelrc)",
        "GOLDEN": "$(rootpath testdata/setup_sh.golden)",
        "SETUP_SH": "$(rootpath setup.sh)",
    },
)

# setup.sh is still what //tools/cloud-bootstrap runs at session start (by path,
# before Bazel exists), and agent-guard protects it, so it stays until the gated
# change that moves cloud-bootstrap onto the Rust binary. Until then its own
# regression test keeps running.
sh_test(
    name = "setup_sh_test",
    size = "small",
    srcs = ["setup_test.sh"],
    data = ["setup.sh"],
)
