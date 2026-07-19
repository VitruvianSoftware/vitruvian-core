load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 2-environments production env root for the vitruviansoftware.dev
# org, mirroring upstream terraform-example-foundation 2-environments/envs/production.
# Not gazelle-built / not in //:go.work — consumes the PUBLISHED pulumi-library
# Go modules (temp local replace for the cold-deploy fixes until published;
# dogfoods the mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-environments/envs/production:preview
pulumi_project(
    name = "production",
    dir = "infrastructure/pulumi/foundation/gcp-environments/envs/production",
)
