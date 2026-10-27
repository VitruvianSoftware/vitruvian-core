# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":defs.bzl", "pulumi_create_app")

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
# The Rust binary is the primary target; the sh_binary is kept as create-app-sh.
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
alias(
    name = "rotate-access-token-py",
    actual = ":rotate-access-token",
    visibility = ["//visibility:public"],
)

test_suite(
    name = "rotate_access_token_test",
    tests = [":rotate_access_token_lib_test"],
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
        exclude = [
            "src/main.rs",
            "src/bin/*.rs",
        ],
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

test_suite(
    name = "rotate_access_token_rs_parity_test",
    tests = [":rotate_access_token_lib_test"],
)

# ---------------------------------------------------------------------------
# Rust ports of the Pulumi tool scripts (resolve-identity, retry-concurrent-
# update, pulumi-cmd, pulumi-go-test, create-app, pulumi-setup). Each gets a
# rust_binary with a clean name and an sh_binary with a -sh suffix for the
# original shell script. Parity tests run existing test suites against both.
# ---------------------------------------------------------------------------

rust_binary(
    name = "resolve-identity",
    srcs = ["src/bin/resolve_identity.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

sh_binary(
    name = "resolve-identity-sh",
    srcs = ["resolve_identity.sh"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "retry-concurrent-update",
    srcs = ["src/bin/retry_concurrent_update.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

sh_binary(
    name = "retry-concurrent-update-sh",
    srcs = ["retry-concurrent-update.sh"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "pulumi-cmd",
    srcs = ["src/bin/pulumi_cmd.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

sh_binary(
    name = "pulumi-cmd-sh",
    srcs = ["pulumi-cmd.sh"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "pulumi-go-test",
    srcs = ["src/bin/pulumi_go_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

sh_binary(
    name = "pulumi-go-test-sh",
    srcs = ["pulumi_go_test.sh"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "pulumi-setup",
    srcs = ["src/bin/pulumi_setup.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":rotate_access_token_lib"],
)

sh_binary(
    name = "pulumi-setup-sh",
    srcs = ["pulumi_setup.sh"],
    visibility = ["//visibility:public"],
)

# Parity tests: run the existing test suites against the Rust binaries.
# The same test script works for both shell and Rust because we invoke the
# tool via "$TOOL" (not `bash "$TOOL"`), so both shebanged scripts and
# compiled binaries work.
sh_test(
    name = "resolve_identity_rs_test",
    srcs = ["resolve_identity_test.sh"],
    args = ["$(location :resolve-identity)"],
    data = [":resolve-identity"],
)

sh_test(
    name = "retry_concurrent_update_rs_test",
    srcs = ["retry_concurrent_update_test.sh"],
    args = ["$(location :retry-concurrent-update)"],
    data = [":retry-concurrent-update"],
)

sh_test(
    name = "pulumi_cmd_rs_test",
    srcs = ["pulumi_cmd_test.sh"],
    args = [
        "$(location :pulumi-cmd)",
        "$(location retry-concurrent-update.sh)",
    ],
    data = [
        "retry-concurrent-update.sh",
        ":pulumi-cmd",
    ],
)

sh_test(
    name = "pulumi_go_test_test",
    srcs = ["pulumi_go_test_test.sh"],
    args = ["$(location pulumi_go_test.sh)"],
    data = ["pulumi_go_test.sh"],
    env_inherit = [
        "PATH",
        "HOME",
    ],
)

sh_test(
    name = "pulumi_go_test_rs_test",
    srcs = ["pulumi_go_test_test.sh"],
    args = ["$(location :pulumi-go-test)"],
    data = [":pulumi-go-test"],
    env_inherit = [
        "PATH",
        "HOME",
    ],
)

test_suite(
    name = "pulumi_tools_parity_test",
    tests = [":rotate_access_token_lib_test"],
)
