"""sync-env-secrets `bazel run` wrappers — deploy-time GitHub Actions secrets that
are NOT in GCP Secret Manager, synced from a gitignored, Bitwarden-backed store.

Each binary target bakes the subcommand as $1 (mirrors //tools/gitops). See
README.md and docs/engineering/application-development-principles.md
(§2.2 ops run through bazel wrappers, §2.18 every change ships as code).

  bazel run //tools/sync-env-secrets:unlock                            # once: caches a bw session so the rest run headless
  bazel run //tools/sync-env-secrets:apply -- oauth-user-inspector-development
  bazel run //tools/sync-env-secrets:bw-push
  bazel run //tools/sync-env-secrets:bw-pull                           # Bitwarden -> store (e.g. on a new machine)
  bazel run //tools/sync-env-secrets:lock                              # clear the cached session + lock the vault
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

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

rust_test(
    name = "sync_env_secrets_lib_test",
    size = "small",
    crate = ":sync_env_secrets_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "sync-env-secrets_test",
    tests = [":sync_env_secrets_lib_test"],
)

test_suite(
    name = "sync-env-secrets-rs_test",
    tests = [":sync_env_secrets_lib_test"],
)
