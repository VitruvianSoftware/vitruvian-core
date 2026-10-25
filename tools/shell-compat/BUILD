"""shell-compat: the bash and coreutils behaviours the Rust ports of the
credential tools in tools/ reproduce exactly (`command -v`, `$(...)` capture,
`${#var}`, `read -r`, `sed 's/^/  /'`, `grep -qi`, `mktemp`, `umask`,
`dirname`, IFS splitting). Shared so each port carries its own logic and
nothing else; std only.

Used by //tools/gcp-token, //tools/gcp-secrets, //tools/sync-env-secrets,
//tools/github-app-key, //tools/github-security and //tools/saas-cli.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_library")
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "shell_compat",
    srcs = ["src/lib.rs"],
    crate_name = "shell_compat",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = [
        "//tools/agent-app:__pkg__",
        "//tools/apple-signing:__pkg__",
        "//tools/argocd-admin-password:__pkg__",
        "//tools/copybara:__pkg__",
        "//tools/gcp-secrets:__pkg__",
        "//tools/gcp-token:__pkg__",
        "//tools/github-app-key:__pkg__",
        "//tools/github-security:__pkg__",
        "//tools/platform-e2e:__pkg__",
        "//tools/saas-cli:__pkg__",
        "//tools/sync-env-secrets:__pkg__",
    ],
)

rust_test(
    name = "shell_compat_test",
    size = "small",
    crate = ":shell_compat",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The side-by-side harness each port's parity test runs: the script and the
# binary in two identical sandboxes, compared on exit code, stdout, stderr
# and every file left behind.
py_library(
    name = "parity_harness",
    srcs = ["parity_harness.py"],
    imports = ["."],
    visibility = [
        "//tools/agent-app:__pkg__",
        "//tools/apple-signing:__pkg__",
        "//tools/argocd-admin-password:__pkg__",
        "//tools/copybara:__pkg__",
        "//tools/gcp-secrets:__pkg__",
        "//tools/gcp-token:__pkg__",
        "//tools/github-app-key:__pkg__",
        "//tools/github-security:__pkg__",
        "//tools/platform-e2e:__pkg__",
        "//tools/saas-cli:__pkg__",
        "//tools/sync-env-secrets:__pkg__",
    ],
)
