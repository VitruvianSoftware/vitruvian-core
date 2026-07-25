load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 5-app-infra bu2 development leaf for the vitruviansoftware.dev
# org, mirroring upstream terraform-example-foundation
# 5-app-infra/business_unit_2/development. Not gazelle-built / not in //:go.work —
# consumes the PUBLISHED pulumi-library Go modules (dogfoods the
# mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-app-infra/business_unit_2/development:preview
pulumi_project(
    name = "development",
    dir = "infrastructure/pulumi/foundation/gcp-app-infra/business_unit_2/development",
)
