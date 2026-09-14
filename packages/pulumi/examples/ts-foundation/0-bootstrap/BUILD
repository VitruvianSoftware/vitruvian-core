load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi TypeScript project). Wrapper-only under
# Bazel; resolves the in-tree library via the pnpm workspace (foundation-* =
# workspace:*). Run: bazel run //pulumi/examples/ts-foundation/0-bootstrap:preview
pulumi_project(
    name = "0-bootstrap",
    dir = "pulumi/examples/ts-foundation/0-bootstrap",
)
