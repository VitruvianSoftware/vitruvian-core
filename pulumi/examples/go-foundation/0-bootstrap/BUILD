load("//tools/pulumi:defs.bzl", "pulumi_project")

# Reference-foundation stage (Pulumi Go project). Not gazelle-built / not in
# //:go.work — resolves the in-tree library via replace directives in go.mod,
# same convention as infrastructure/pulumi. Run: bazel run //pulumi/examples/go-foundation/0-bootstrap:preview
pulumi_project(
    name = "0-bootstrap",
    dir = "pulumi/examples/go-foundation/0-bootstrap",
)
