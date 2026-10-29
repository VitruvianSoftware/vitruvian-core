"""shell-compat: the bash and coreutils behaviours the Rust ports of the
credential tools in tools/ reproduce exactly (`command -v`, `$(...)` capture,
`${#var}`, `read -r`, `sed 's/^/  /'`, `grep -qi`, `mktemp`, `umask`,
`dirname`, IFS splitting). Shared so each port carries its own logic and
nothing else; std only.

Used by packages across //tools/...
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")

rust_library(
    name = "shell_compat",
    srcs = ["src/lib.rs"],
    crate_name = "shell_compat",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//tools:__subpackages__"],
)

rust_test(
    name = "shell_compat_test",
    size = "small",
    crate = ":shell_compat",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
