"""sync-env-secrets `bazel run` wrappers — deploy-time GitHub Actions secrets that
are NOT in GCP Secret Manager, synced from a gitignored, Bitwarden-backed store.

Each binary target bakes the subcommand as $1 (mirrors //tools/gitops). See
sync-env-secrets.sh + README.md and docs/engineering/application-development-principles.md
(§2.2 ops run through bazel wrappers, §2.18 every change ships as code).

  bazel run //tools/sync-env-secrets:unlock                            # once: caches a bw session so the rest run headless
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-development
  bazel run //tools/sync-env-secrets:bw-push
  bazel run //tools/sync-env-secrets:bw-pull                           # Bitwarden -> store (e.g. on a new machine)
  bazel run //tools/sync-env-secrets:lock                              # clear the cached session + lock the vault
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["sync-env-secrets.sh"])

# The subcommands, each a binary target: `bazel run :<name>` runs <name>.
# `set` safely adds/updates one secret: `set <github-environment> <SECRET_NAME>`
# prompts for the value, then pull -> write -> push (never pushes a partial store).
SUBCOMMANDS = [
    "apply",
    "set",
    "bw-push",
    "agent-keys-push",
    "agent-keys-pull",
    "bw-pull",
    "unlock",
    "lock",
]

# The tool, in Rust (src/): sync-env-secrets.sh's calls to bw, gh and tar, its
# output and exit codes, held to the script by the parity test below. bw's JSON
# is read with serde_json (src/jq.rs), so it needs no jq. One library; each
# subcommand is the same src/main.rs with the subcommand baked in as $1.
rust_library(
    name = "sync_env_secrets_lib",
    srcs = [
        "src/jq.rs",
        "src/lib.rs",
    ],
    crate_name = "sync_env_secrets",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

[
    rust_binary(
        name = sub,
        srcs = ["src/main.rs"],
        args = [sub],
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        visibility = ["//visibility:public"],
        deps = [
            ":sync_env_secrets_lib",
            "//tools/shell-compat:shell_compat",
        ],
    )
    for sub in SUBCOMMANDS
]

[
    alias(
        name = name,
        actual = ":" + sub,
        visibility = ["//visibility:public"],
    )
    for sub in SUBCOMMANDS
    for name in [
        sub + "-rs",
        sub.replace("-", "_") + "_rs",
    ]
]

# The shell original, kept runnable and held to the port by the parity test.
# tools/release/publish-local.sh still runs sync-env-secrets.sh directly.
[
    sh_binary(
        name = sub + "-sh",
        srcs = ["sync-env-secrets.sh"],
        args = [sub],
        visibility = ["//visibility:public"],
    )
    for sub in SUBCOMMANDS
]

# How a Bitwarden session is picked, with a fake bw: no vault, no network.
sh_test(
    name = "sync-env-secrets_test",
    size = "small",
    srcs = ["sync-env-secrets_test.sh"],
    # The script's bw_state pipes through jq; the test image has none.
    data = [
        "sync-env-secrets.sh",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

# The same checks against the Rust binary (SYNC_ENV_SECRETS_BIN), each one a
# whole subcommand run (see the test).
sh_test(
    name = "sync-env-secrets-rs_test",
    size = "small",
    srcs = ["sync-env-secrets_test.sh"],
    data = [
        "sync-env-secrets.sh",
        ":unlock",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "SYNC_ENV_SECRETS_BIN": "$(rootpath :unlock)",
    },
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

# The #[cfg(test)] unit tests in src/ (the jq filters among them).
rust_test(
    name = "sync_env_secrets_lib_test",
    size = "small",
    crate = ":sync_env_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in
# sync_env_secrets_rs_parity_test.py: exit code, stdout, stderr, the calls to
# a fake bw and gh, and the vault, store and session cache left behind.
py_test(
    name = "sync_env_secrets_rs_parity_test",
    size = "medium",
    srcs = ["sync_env_secrets_rs_parity_test.py"],
    data = [
        "sync-env-secrets.sh",
        ":unlock",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "JQ_BIN": "$(JQ_BIN)",
        "SYNC_ENV_SECRETS_RS": "$(rootpath :unlock)",
        "SYNC_ENV_SECRETS_SH": "$(rootpath sync-env-secrets.sh)",
    },
    main = "sync_env_secrets_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = ["//tools/shell-compat:parity_harness"],
)
