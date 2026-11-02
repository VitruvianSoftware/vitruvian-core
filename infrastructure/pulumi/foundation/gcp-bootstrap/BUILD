load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

# Live foundation bootstrap for the vitruviansoftware.dev org. Not gazelle-built /
# not in //:go.work — consumes the PUBLISHED pulumi-library Go modules (no replace;
# dogfoods the mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-bootstrap:preview
pulumi_project(
    name = "gcp-bootstrap",
    dir = "infrastructure/pulumi/foundation/gcp-bootstrap",
)

# `bazel test //infrastructure/pulumi/foundation/gcp-bootstrap:test` runs the
# stack's `go test ./...` locally (see pulumi_go_test() in defs.bzl).
pulumi_go_test(
    # sa_preview_test.go runs the whole program with the committed stack config.
    extra_data = ["Pulumi.production.yaml"],
)
