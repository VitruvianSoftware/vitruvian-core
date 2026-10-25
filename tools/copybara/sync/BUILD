# gazelle:ignore
# Hand-maintained: the default :sync is the Rust port, which gazelle would
# otherwise replace with a go_binary of the same name. Keep the Go targets
# below in step with main.go by hand.

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The Go original. It stays buildable as :sync-go, and the parity test below
# holds the Rust port to it.
go_library(
    name = "sync_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/copybara/sync",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "sync-go",
    embed = [":sync_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "sync_test",
    srcs = ["main_test.go"],
    embed = [":sync_lib"],
)

# main.go in Rust, standard library only: the same docker invocations (found
# on PATH the way os/exec finds docker), the same retry and backoff, output
# and exit codes, with arguments handled as raw bytes like Go strings.
# Optimised in every build mode.
rust_library(
    name = "sync_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "copybara_sync",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# `bazel run //tools/copybara/sync -- <export|import> <component>` and
# `... -- import_pr <component> <pr-number>`: what the Copybara workflows run.
rust_binary(
    name = "sync",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":sync_rs_lib"],
)

alias(
    name = "sync-rs",
    actual = ":sync",
    visibility = ["//visibility:public"],
)

alias(
    name = "sync_rs",
    actual = ":sync",
    visibility = ["//visibility:public"],
)

# main_test.go's cases in Rust, with a fake runner.
rust_test(
    name = "sync_rs_lib_test",
    size = "small",
    crate = ":sync_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Runs the Go binary and the Rust binary against the same fake docker and
# compares exit code, stdout, stderr and every docker argument byte for byte,
# including the real import retry backoff (so: medium).
py_test(
    name = "sync_rs_parity_test",
    size = "medium",
    srcs = ["sync_rs_parity_test.py"],
    data = [
        ":sync",
        ":sync-go",
    ],
    env = {
        "SYNC_GO": "$(rootpath :sync-go)",
        "SYNC_RS": "$(rootpath :sync)",
    },
    main = "sync_rs_parity_test.py",
)
