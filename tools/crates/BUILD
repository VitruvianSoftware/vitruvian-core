"""Re-lock the root Cargo.lock for the Bazel Rust toolchain.

  bazel run //tools/crates:lock              # after editing a Cargo.toml
  bazel run //tools/crates:lock -- --check   # is Cargo.lock in step? changes nothing
  bazel run //tools/crates:lock -- -p ring   # anything else goes to `cargo update`
  bazel run //tools/crates:check             # every Cargo.lock vs its Cargo.toml files, offline

`:check` is what tidy-check runs on every PR: it compares each committed
Cargo.lock's workspace packages (name, version, dependency list) with their
Cargo.toml files, with no cargo and no network (#4026). `:lock -- --check`
goes further (it re-resolves with cargo) but needs the crates.io index.

Raw `cargo` is blocked for agents (tools/agent-guard), and the toolchain's own
cargo (1.75) cannot resolve by rust-version. This runs a pinned newer cargo
(MODULE.bazel, `relock_cargo_*`) with MSRV-aware resolution, after checking
that every workspace member declares the toolchain's rust-version.
"""

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "crates_lock_lib",
    srcs = [
        "src/fresh.rs",
        "src/lib.rs",
    ],
    crate_name = "crates_lock",
    crate_root = "src/lib.rs",
    edition = "2021",
)

rust_test(
    name = "crates_lock_test",
    size = "small",
    crate = ":crates_lock_lib",
    edition = "2021",
)

config_setting(
    name = "darwin_arm64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:aarch64",
    ],
)

config_setting(
    name = "darwin_x86_64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "linux_arm64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)

config_setting(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

alias(
    name = "relock_cargo",
    actual = select({
        ":darwin_arm64": "@relock_cargo_aarch64_apple_darwin//:cargo/bin/cargo",
        ":darwin_x86_64": "@relock_cargo_x86_64_apple_darwin//:cargo/bin/cargo",
        ":linux_arm64": "@relock_cargo_aarch64_unknown_linux_gnu//:cargo/bin/cargo",
        ":linux_x86_64": "@relock_cargo_x86_64_unknown_linux_gnu//:cargo/bin/cargo",
    }),
)

rust_binary(
    name = "lock",
    srcs = ["src/main.rs"],
    data = [":relock_cargo"],
    edition = "2021",
    env = {"RELOCK_CARGO": "$(rootpath :relock_cargo)"},
    visibility = ["//visibility:public"],
    deps = [":crates_lock_lib"],
)

# Offline: no relock cargo in its runfiles, so CI does not download one.
rust_binary(
    name = "check",
    srcs = ["src/check.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":crates_lock_lib"],
)
