# gazelle:ignore
# Hand-maintained: the default :conflict-precheck is the Rust port, which
# gazelle would otherwise replace with a go_binary of the same name. Keep the
# Go targets below in step with main.go by hand.

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The Go original. It stays buildable as :conflict-precheck-go, and the parity
# test below holds the Rust port to it.
go_library(
    name = "conflict_precheck_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/copybara/conflict-precheck",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "conflict-precheck-go",
    embed = [":conflict_precheck_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "conflict_precheck_test",
    srcs = ["main_test.go"],
    embed = [":conflict_precheck_lib"],
)

alias(
    name = "conflict-precheck_test",
    actual = ":conflict_precheck_test",
)

# main.go in Rust, standard library only: the same git invocations (found on
# PATH the way os/exec finds them), the same output and exit codes, with
# arguments handled as raw bytes like Go strings. Optimised in every build mode.
rust_library(
    name = "conflict_precheck_rs_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "conflict_precheck",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# `bazel run //tools/copybara/conflict-precheck` — what the export workflow runs.
rust_binary(
    name = "conflict-precheck",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":conflict_precheck_rs_lib"],
)

alias(
    name = "conflict_precheck",
    actual = ":conflict-precheck",
    visibility = ["//visibility:public"],
)

alias(
    name = "conflict-precheck-rs",
    actual = ":conflict-precheck",
    visibility = ["//visibility:public"],
)

alias(
    name = "conflict_precheck_rs",
    actual = ":conflict-precheck",
    visibility = ["//visibility:public"],
)

# main_test.go's cases in Rust, against real git repos in temp dirs.
rust_test(
    name = "conflict_precheck_rs_lib_test",
    size = "small",
    crate = ":conflict_precheck_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Runs the Go binary and the Rust binary on the same git repos and compares
# exit code, stdout and stderr byte for byte: every main_test.go scenario,
# then usage errors, odd components and labels, merges, unreachable and
# malformed baselines, missing repos, and git missing from PATH.
py_test(
    name = "conflict_precheck_rs_parity_test",
    size = "medium",
    srcs = ["conflict_precheck_rs_parity_test.py"],
    data = [
        ":conflict-precheck",
        ":conflict-precheck-go",
    ],
    env = {
        "CONFLICT_PRECHECK_GO": "$(rootpath :conflict-precheck-go)",
        "CONFLICT_PRECHECK_RS": "$(rootpath :conflict-precheck)",
    },
    main = "conflict_precheck_rs_parity_test.py",
)
