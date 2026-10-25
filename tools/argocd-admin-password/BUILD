"""Pin the dev-local Argo CD admin password to a Bitwarden-held value.

See sync.sh for the why. Run from the main checkout (it needs the gitignored
Pulumi.local.yaml):

  bazel run //tools/sync-env-secrets:unlock        # once, if the vault is locked
  bazel run //tools/argocd-admin-password:sync
  bazel run //infrastructure/pulumi/platform/dev-local:preview   # then :up

`:sync` is the Rust port (src/): sync.sh's calls to bw, kubectl, htpasswd and
pulumi, its output and exit codes, with the script's jq done through serde.
The script stays runnable as `:sync-sh` and is held to the port by the parity
test below.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

exports_files(["sync.sh"])

rust_library(
    name = "argocd_admin_password_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "argocd_admin_password",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "sync",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":argocd_admin_password_lib"],
)

alias(
    name = "sync-rs",
    actual = ":sync",
)

alias(
    name = "sync_rs",
    actual = ":sync",
)

sh_binary(
    name = "sync-sh",
    srcs = ["sync.sh"],
)

# The #[cfg(test)] unit tests in src/ (the jq programs, base64, the item
# document, dates).
rust_test(
    name = "argocd_admin_password_lib_test",
    size = "small",
    crate = ":argocd_admin_password_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# sync_rs_parity_test.py: exit code, stdout, stderr, the calls made to fake
# bw, kubectl, htpasswd and pulumi (with the environment they saw), and the
# Bitwarden and stack state left behind. The script's jq is the repo's
# pinned one, so its messages are the ones the port reproduces.
py_test(
    name = "sync_rs_parity_test",
    size = "medium",
    srcs = ["sync_rs_parity_test.py"],
    data = [
        "sync.sh",
        ":sync",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "SYNC_RS": "$(rootpath :sync)",
        "SYNC_SH": "$(rootpath sync.sh)",
    },
    main = "sync_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = ["//tools/shell-compat:parity_harness"],
)
