"""What CI requires, and what is actually configured.

  bazel run //tools/ci-preflight            # report; non-zero if required is missing
  bazel run //tools/ci-preflight -- --list  # just the required set, no network

`//:doctor` answers "can I build this repo on THIS machine". This answers the
other half -- "is the REPO wired up so CI can actually run" -- which fails in a
nastier way, because a missing secret is not an error but an empty string.

The required set is DERIVED from every `secrets.X` / `vars.X` in
.github/workflows and .github/actions, so it cannot drift from the workflows it
describes. Its sharpest check is the Dependabot one: a secret read by a
`pull_request`-triggered workflow resolves to the empty string on Dependabot PRs
unless it also exists in the separate Dependabot store -- which is exactly how
#1164 failed. See tools/ci-preflight/ci-preflight.sh for the full rationale.

Deliberately NOT wired into CI as a gate: it reads repo configuration state that
lives outside the commit, so it would fail on forks and on any run whose token
lacks admin:repo. It is a developer/maintainer preflight, run on demand.
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

rust_library(
    name = "ci_preflight_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = ["ci-preflight.sh"],
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "ci-preflight",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":ci_preflight_lib"],
)

alias(
    name = "ci-preflight-rs",
    actual = ":ci-preflight",
    visibility = ["//visibility:public"],
)

alias(
    name = "ci_preflight_rs",
    actual = ":ci-preflight",
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "ci-preflight-sh",
    srcs = ["ci-preflight.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "ci-preflight_test",
    size = "small",
    srcs = ["ci-preflight_test.sh"],
    data = ["ci-preflight.sh"],
)

sh_test(
    name = "ci-preflight-rs_test",
    size = "small",
    srcs = ["ci-preflight_test.sh"],
    args = ["$(rootpath :ci-preflight)"],
    data = [":ci-preflight"],
)

rust_test(
    name = "ci_preflight_lib_test",
    size = "small",
    crate = ":ci_preflight_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "ci-preflight-rs-parity_test",
    size = "medium",
    srcs = ["ci-preflight-rs-parity_test.sh"],
    data = [
        "ci-preflight.sh",
        ":ci-preflight",
    ],
    env = {
        "RS_UNDER_TEST": "$(rootpath :ci-preflight)",
        "SH_UNDER_TEST": "$(rootpath ci-preflight.sh)",
    },
)
