load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation 5-app-infra bu1 nonproduction leaf (Pulumi Go project),
# mirroring upstream terraform-example-foundation
# 5-app-infra/business_unit_1/nonproduction. Not gazelle-built / not in //:go.work —
# resolves the in-tree library via replace directives in go.mod, same
# convention as infrastructure/pulumi.
# Run: bazel run //pulumi/examples/go-foundation/5-app-infra/business_unit_1/nonproduction:preview
pulumi_project(
    name = "nonproduction",
    dir = "pulumi/examples/go-foundation/5-app-infra/business_unit_1/nonproduction",
)
