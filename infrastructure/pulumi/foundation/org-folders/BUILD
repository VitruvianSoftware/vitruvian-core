load("//tools/pulumi:defs.bzl", "pulumi_project")

# Minimal umbrella-folder stage: creates fldr-foundation-1 at the org root and
# exports its numeric id for foundation-bootstrap's parent_folder config.
# Run: bazel run //infrastructure/pulumi/foundation/org-folders:up
pulumi_project(
    name = "org-folders",
    dir = "infrastructure/pulumi/foundation/org-folders",
)
