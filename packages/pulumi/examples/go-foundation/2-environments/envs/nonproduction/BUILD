load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation 2-environments nonproduction env root (Pulumi Go project),
# mirroring upstream terraform-example-foundation 2-environments/envs/nonproduction.
# Not gazelle-built / not in //:go.work — resolves the in-tree library via
# replace directives in go.mod, same convention as infrastructure/pulumi.
# Run: bazel run //pulumi/examples/go-foundation/2-environments/envs/nonproduction:preview
pulumi_project(
    name = "nonproduction",
    dir = "pulumi/examples/go-foundation/2-environments/envs/nonproduction",
)
