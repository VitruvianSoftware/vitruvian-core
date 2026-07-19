load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 1-org env root for the vitruviansoftware.dev org, mirroring
# upstream terraform-example-foundation 1-org/envs/shared. Not gazelle-built /
# not in //:go.work — consumes the PUBLISHED pulumi-library Go modules (temp
# local replaces for the cold-deploy fixes until published; dogfoods the
# mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-org/envs/shared:preview
pulumi_project(
    name = "shared",
    dir = "infrastructure/pulumi/foundation/gcp-org/envs/shared",
)
