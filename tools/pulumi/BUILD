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

"""Reusable Pulumi `bazel run` wrappers, in Rust (standard library only).

`pulumi_project` (see defs.bzl) is applied in each Pulumi project's package to
generate `:preview :up :destroy :refresh :config :stack :state :import :setup`
run targets; they run `:pulumi-cmd` / `:pulumi-setup` from here.
`pulumi_go_test` runs `:pulumi-go-test`.

No `pulumi` CLI is vendored here: the wrappers exec the developer's installed
`pulumi` (run `bazel run //<project>:setup` to bootstrap it).

`:create-app` is the one-time, repo-level GitHub App Manifest-flow bootstrap
(`bazel run //tools/pulumi:create-app`, once per org).
"""

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# Every tool's code, plus what it needs of Python carried by hand for
# rotate-access-token: src/json.rs (json.loads/dumps), src/argparse.rs,
# src/http.rs (urlopen: http:// over a socket, https:// through curl, since
# std has no TLS). Optimised in every build mode. //tools/gcp-secrets and
# //tools/saas-cli use its gcp-identities.tsv resolver.
rust_library(
    name = "pulumi_tools",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/bin/*.rs",
        ],
    ),
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = [
        "//tools/gcp-secrets:__pkg__",
        "//tools/saas-cli:__pkg__",
    ],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "pulumi_tools_test",
    size = "small",
    crate = ":pulumi_tools",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Rotate the Pulumi Cloud token CI uses: mint, check it works, store it as
# PULUMI_ACCESS_TOKEN (Actions + Dependabot) over stdin -- never printed. Old
# tokens are deleted in a separate, confirmed --cleanup step once CI is green.
#   bazel run //tools/pulumi:rotate-access-token
#   bazel run //tools/pulumi:rotate-access-token -- --cleanup [--delete-old ID]
rust_binary(
    name = "rotate-access-token",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":pulumi_tools"],
)

# One binary per tool, each a thin main over src/<tool>.rs.
#   pulumi-cmd               the wrapper behind every pulumi_project() target
#                            and //tools/deploy:cloud-run
#   pulumi-setup             every pulumi_project() :setup
#   pulumi-go-test           every pulumi_go_test()
#   resolve-identity         <map> <infra-dir> -> "account<TAB>project"
#   retry-concurrent-update  retries ONLY Pulumi Cloud's concurrent-update 409
#   create-app               the one-time org App bootstrap
[
    rust_binary(
        name = name,
        srcs = ["src/bin/%s.rs" % name.replace("-", "_")],
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        visibility = ["//visibility:public"],
        deps = [":pulumi_tools"],
    )
    for name in [
        "pulumi-cmd",
        "pulumi-setup",
        "pulumi-go-test",
        "resolve-identity",
        "create-app",
    ]
]

# Built from its own file plus src/retry_concurrent_update.rs, with no crate
# deps, because CI jobs without Bazel (.github/actions/pulumi-run-captured,
# the zitadel-apps applies) build the same binary with a bare
#   rustc --edition 2021 -O tools/pulumi/src/bin/retry_concurrent_update.rs
# Adding a dependency here would break those jobs, not this build.
rust_binary(
    name = "retry-concurrent-update",
    srcs = [
        "src/bin/retry_concurrent_update.rs",
        "src/retry_concurrent_update.rs",
    ],
    crate_root = "src/bin/retry_concurrent_update.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
)

# Behaviour suites: each runs its binary as a subprocess with stub programs
# (pulumi, gcloud, gh, go, sleep, ...) on a private PATH. tests/common holds
# the shared helpers.
[
    rust_test(
        name = "%s_test" % name.replace("-", "_"),
        size = "small",
        srcs = [
            "tests/%s_test.rs" % name.replace("-", "_"),
            "tests/common/mod.rs",
        ],
        crate_root = "tests/%s_test.rs" % name.replace("-", "_"),
        data = [":" + name],
        edition = "2021",
        env = {"%s_BIN" % name.replace("-", "_").upper(): "$(rootpath :%s)" % name},
    )
    for name in [
        "pulumi-cmd",
        "pulumi-setup",
        "pulumi-go-test",
        "resolve-identity",
        "retry-concurrent-update",
        "create-app",
    ]
]
