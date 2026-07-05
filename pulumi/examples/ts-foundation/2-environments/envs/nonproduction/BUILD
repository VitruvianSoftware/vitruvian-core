load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi TypeScript project). Wrapper-only under
# Bazel; resolves the in-tree library via the pnpm workspace (foundation-* =
# workspace:*). Run: bazel run //pulumi/examples/ts-foundation/2-environments/envs/nonproduction:preview
pulumi_project(
    name = "2-environments-envs-nonproduction",
    dir = "pulumi/examples/ts-foundation/2-environments/envs/nonproduction",
)
