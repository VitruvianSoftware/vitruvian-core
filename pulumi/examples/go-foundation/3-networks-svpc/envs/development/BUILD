load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation 3-networks-svpc development env root (Pulumi Go
# project), mirroring upstream terraform-example-foundation
# 3-networks-svpc/envs/development. Not gazelle-built / not in //:go.work —
# resolves the in-tree library via replace directives in go.mod, same
# convention as infrastructure/pulumi.
# Run: bazel run //pulumi/examples/go-foundation/3-networks-svpc/envs/development:preview
pulumi_project(
    name = "development",
    dir = "pulumi/examples/go-foundation/3-networks-svpc/envs/development",
)
