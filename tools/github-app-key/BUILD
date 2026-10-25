"""Store or rotate a GitHub App's private key as a repo secret.

  bazel run //tools/github-app-key -- renovate        # finds the .pem in ~/Downloads
  bazel run //tools/github-app-key -- --list          # which Apps it knows

GitHub cannot automate "Generate a private key" in the App's settings. This
does everything after it: proves the key belongs to the right App (by signing
an App JWT and asking GitHub), checks the App is installed and -- where it must
be -- NOT a merge-queue bypass actor, stores it with `gh secret set` over stdin
(never printed), then offers to delete the download. See set-key.sh.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# The tool, in Rust (src/): set-key.sh's checks, calls to gh and openssl,
# output and exit codes, held to the script by the parity test below. The
# manifest and the JWT claims are built with serde_json. Optimised in every
# build mode.
rust_library(
    name = "github_app_key_lib",
    srcs = ["src/lib.rs"],
    crate_name = "github_app_key",
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
    name = "github-app-key",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":github_app_key_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

alias(
    name = "github-app-key-rs",
    actual = ":github-app-key",
    visibility = ["//visibility:public"],
)

alias(
    name = "github_app_key_rs",
    actual = ":github-app-key",
    visibility = ["//visibility:public"],
)

# The shell original, kept runnable and held to the port by the parity test.
sh_binary(
    name = "github-app-key-sh",
    srcs = ["set-key.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "set-key_test",
    size = "small",
    srcs = ["set-key_test.sh"],
    data = ["set-key.sh"],
)

# The same suite against the Rust binary (GITHUB_APP_KEY_BIN).
sh_test(
    name = "set-key-rs_test",
    size = "small",
    srcs = ["set-key_test.sh"],
    data = [
        "set-key.sh",
        ":github-app-key",
    ],
    env = {"GITHUB_APP_KEY_BIN": "$(rootpath :github-app-key)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "github_app_key_lib_test",
    size = "small",
    crate = ":github_app_key_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# github_app_key_rs_parity_test.py: exit code, stdout, stderr, the calls to
# a fake gh (the JWT decoded and its signature checked), the stored key and
# the manifest form, compared byte for byte.
py_test(
    name = "github_app_key_rs_parity_test",
    size = "medium",
    srcs = ["github_app_key_rs_parity_test.py"],
    data = [
        "set-key.sh",
        ":github-app-key",
    ],
    env = {
        "GITHUB_APP_KEY_RS": "$(rootpath :github-app-key)",
        "GITHUB_APP_KEY_SH": "$(rootpath set-key.sh)",
    },
    main = "github_app_key_rs_parity_test.py",
    deps = ["//tools/shell-compat:parity_harness"],
)
