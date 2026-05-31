"""Reusable Pulumi `bazel run` wrappers.

`pulumi_project` (see defs.bzl) is applied in each Pulumi project's package to
generate `:preview :up :destroy :refresh :config :setup` run targets. The two
wrapper scripts are exported so those generated `sh_binary` targets can list
them in `srcs` from another package.

No `pulumi` CLI is vendored here — the wrappers exec the developer's installed
`pulumi` (run `bazel run //<project>:setup` to bootstrap it).

`create_app.sh` is the one-time, repo-level GitHub App Manifest-flow bootstrap;
`pulumi_create_app` declares it as `//tools/pulumi:create-app` (run once per org).
"""

load("//tools/pulumi:defs.bzl", "pulumi_create_app")

exports_files([
    "pulumi_cmd.sh",
    "pulumi_setup.sh",
    "create_app.sh",
])

# One-time, repo-level App bootstrap: `bazel run //tools/pulumi:create-app`.
pulumi_create_app()
