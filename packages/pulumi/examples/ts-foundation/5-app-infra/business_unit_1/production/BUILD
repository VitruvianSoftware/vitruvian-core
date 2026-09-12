load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi TypeScript project). Wrapper-only under
# Bazel; resolves the in-tree library via the pnpm workspace (foundation-* =
# workspace:*). Run: bazel run //pulumi/examples/ts-foundation/5-app-infra/business_unit_1/production:preview
pulumi_project(
    name = "5-app-infra-business_unit_1-production",
    dir = "pulumi/examples/ts-foundation/5-app-infra/business_unit_1/production",
)
