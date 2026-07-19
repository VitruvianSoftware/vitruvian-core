load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation 4-projects bu1 production leaf (Pulumi Go project),
# mirroring upstream terraform-example-foundation
# 4-projects/business_unit_1/production. Not gazelle-built / not in //:go.work —
# resolves the in-tree library via replace directives in go.mod, same
# convention as infrastructure/pulumi.
# Run: bazel run //pulumi/examples/go-foundation/4-projects/business_unit_1/production:preview
pulumi_project(
    name = "production",
    dir = "pulumi/examples/go-foundation/4-projects/business_unit_1/production",
)
