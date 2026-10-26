"""Reusable Pulumi `bazel run` wrappers.

`pulumi_project` (see defs.bzl) is applied in each Pulumi project's package to
generate `:preview :up :destroy :refresh :config :setup` run targets. The two
wrapper scripts are exported so those generated `sh_binary` targets can list
them in `srcs` from another package.

No `pulumi` CLI is vendored here — the wrappers exec the developer's installed
`pulumi` (run `bazel run //<project>:setup` to bootstrap it).

`create-app.sh` is the one-time, repo-level GitHub App Manifest-flow bootstrap;
`pulumi_create_app` declares it as `//tools/pulumi:create-app` (run once per org).
"""

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/pulumi:defs.bzl", "pulumi_create_app")

exports_files([
    "pulumi-cmd.sh",
    # Run by the pulumi-run-captured composite action and inline CI applies.
    "retry-concurrent-update.sh",
    # Consumed by //tools/gcp-secrets, which pins GCP identity the same way.
    "resolve_identity.sh",
    "pulumi_setup.sh",
    "create-app.sh",
    # Consumed by pulumi_go_test() (defs.bzl) from each project's own package.
    "pulumi_go_test.sh",
])

# One-time, repo-level App bootstrap: `bazel run //tools/pulumi:create-app`.
pulumi_create_app()

# Unit tests for the GCP identity resolver. The resolver is passed to the test
# as an arg via $(location) so it works under `bazel test` without runfiles glue.
sh_test(
    name = "resolve_identity_test",
    srcs = ["resolve_identity_test.sh"],
    args = ["$(location resolve_identity.sh)"],
    data = ["resolve_identity.sh"],
)

# Unit tests for the concurrent-update (409) retry. Same $(location) pattern as
# above: the wrapper and the retry helper it execs are passed as args, and a
# stub `pulumi` on PATH makes the retry observable without touching a real
# backend.
sh_test(
    name = "pulumi_cmd_test",
    srcs = ["pulumi_cmd_test.sh"],
    args = [
        "$(location pulumi-cmd.sh)",
        "$(location retry-concurrent-update.sh)",
    ],
    data = [
        "pulumi-cmd.sh",
        "retry-concurrent-update.sh",
    ],
)

# The helper on its own: delay cap, stderr pass-through and the exact match,
# which the wrapper tests cannot observe (they run with a zero delay).
sh_test(
    name = "retry_concurrent_update_test",
    srcs = ["retry_concurrent_update_test.sh"],
    args = ["$(location retry-concurrent-update.sh)"],
    data = ["retry-concurrent-update.sh"],
)

# Rotate the Pulumi Cloud token CI uses: mint, check it works, store it as
# PULUMI_ACCESS_TOKEN (Actions + Dependabot) over stdin -- never printed. Old
# tokens are deleted in a separate, confirmed --cleanup step once CI is green.
#   bazel run //tools/pulumi:rotate-access-token
#   bazel run //tools/pulumi:rotate-access-token -- --cleanup [--delete-old ID]
# :rotate-access-token is the Rust port (below); this is the Python original,
# kept runnable and held to the port by the parity test.
py_binary(
    name = "rotate-access-token-py",
    srcs = ["rotate_access_token.py"],
    imports = ["."],
    main = "rotate_access_token.py",
    visibility = ["//visibility:public"],
)

py_test(
    name = "rotate_access_token_test",
    size = "small",
    srcs = [
        "rotate_access_token.py",
        "rotate_access_token_test.py",
    ],
    imports = ["."],
    main = "rotate_access_token_test.py",
)

# The same tool in Rust, standard library only, so Cargo.lock and
# MODULE.bazel stay as they are. It carries what it needs of Python by hand:
# src/json.rs (json.loads/dumps), src/argparse.rs, src/http.rs (urlopen:
# http:// over a socket, https:// through curl, since std has no TLS).
# Optimised in every build mode.
rust_library(
    name = "rotate_access_token_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "rotate_access_token",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "rotate-access-token",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

alias(
    name = "rotate-access-token-rs",
    actual = ":rotate-access-token",
    visibility = ["//visibility:public"],
)

alias(
    name = "rotate_access_token_rs",
    actual = ":rotate-access-token",
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "rotate_access_token_lib_test",
    size = "small",
    crate = ":rotate_access_token_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Holds the Rust binary to the Python script: both run as programs against
# one fake Pulumi Cloud on localhost and a fake gh, comparing exit codes,
# stdout, stderr, the requests made and what gh was given, on every case in
# rotate_access_token_test.py and on command lines, credentials, API
# failures, prompts and answers built to break them.
py_test(
    name = "rotate_access_token_rs_parity_test",
    size = "small",
    srcs = [
        "rotate_access_token.py",
        "rotate_access_token_rs_parity_test.py",
    ],
    data = [":rotate-access-token"],
    env = {"ROTATE_ACCESS_TOKEN_RS": "$(rootpath :rotate-access-token)"},
    imports = ["."],
    main = "rotate_access_token_rs_parity_test.py",
)
