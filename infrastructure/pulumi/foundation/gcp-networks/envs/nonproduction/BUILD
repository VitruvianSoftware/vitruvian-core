load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 3-networks (hub-and-spoke) nonproduction spoke root for the
# vitruviansoftware.dev org, mirroring upstream terraform-example-foundation
# 3-networks-hub-and-spoke/envs/nonproduction. Not gazelle-built / not in
# //:go.work — consumes the PUBLISHED pulumi-library Go modules (dogfoods the
# mirror-published versions; see go.mod for the TEMP local replace).
# Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-networks/envs/nonproduction:preview
pulumi_project(
    name = "nonproduction",
    dir = "infrastructure/pulumi/foundation/gcp-networks/envs/nonproduction",
)
