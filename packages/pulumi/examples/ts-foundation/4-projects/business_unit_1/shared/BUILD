load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi TypeScript project). Wrapper-only under
# Bazel; resolves the in-tree library via the pnpm workspace (foundation-* =
# workspace:*). Run: bazel run //pulumi/examples/ts-foundation/4-projects/business_unit_1/shared:preview
pulumi_project(
    name = "4-projects-business_unit_1-shared",
    dir = "pulumi/examples/ts-foundation/4-projects/business_unit_1/shared",
)
