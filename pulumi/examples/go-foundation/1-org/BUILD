load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi Go project). Not gazelle-built / not in
# //:go.work — resolves the in-tree library via replace directives in go.mod,
# same convention as infrastructure/pulumi. Run: bazel run //pulumi/examples/go-foundation/1-org:preview
pulumi_project(
    name = "1-org",
    dir = "pulumi/examples/go-foundation/1-org",
)
