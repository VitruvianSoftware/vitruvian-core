load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi TypeScript project). Wrapper-only under
# Bazel; resolves the in-tree library via the pnpm workspace (foundation-* =
# workspace:*). Run: bazel run //pulumi/examples/ts-foundation/3-networks-hub-and-spoke/envs/shared:preview
pulumi_project(
    name = "3-networks-hub-and-spoke-envs-shared",
    dir = "pulumi/examples/ts-foundation/3-networks-hub-and-spoke/envs/shared",
)
