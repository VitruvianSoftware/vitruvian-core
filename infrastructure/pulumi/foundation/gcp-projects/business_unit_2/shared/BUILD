load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 4-projects bu2 shared (common) leaf for the vitruviansoftware.dev
# org, mirroring upstream terraform-example-foundation
# 4-projects/business_unit_2/shared. Not gazelle-built / not in //:go.work —
# consumes the PUBLISHED pulumi-library Go modules (dogfoods the
# mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-projects/business_unit_2/shared:preview
pulumi_project(
    name = "shared",
    dir = "infrastructure/pulumi/foundation/gcp-projects/business_unit_2/shared",
)
