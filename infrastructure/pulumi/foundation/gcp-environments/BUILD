load("//tools/pulumi:defs.bzl", "pulumi_project")

# Live foundation 2-environments for the vitruviansoftware.dev org. Not gazelle-built /
# not in //:go.work — consumes the PUBLISHED pulumi-library Go modules (no replace;
# dogfoods the mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-environments:preview
pulumi_project(
    name = "gcp-environments",
    dir = "infrastructure/pulumi/foundation/gcp-environments",
)
