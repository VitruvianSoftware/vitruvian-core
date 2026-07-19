load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation 3-networks-hub-and-spoke shared/hub root (Pulumi Go
# project), mirroring upstream terraform-example-foundation
# 3-networks-hub-and-spoke/envs/shared. Not gazelle-built / not in //:go.work —
# resolves the in-tree library via replace directives in go.mod, same
# convention as infrastructure/pulumi.
# Run: bazel run //pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared:preview
pulumi_project(
    name = "shared",
    dir = "pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared",
)
