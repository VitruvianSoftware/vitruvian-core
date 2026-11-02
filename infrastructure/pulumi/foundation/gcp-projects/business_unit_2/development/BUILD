load("//tools/pulumi:defs.bzl", "pulumi_go_test", "pulumi_project")

# Live foundation 4-projects bu2 development leaf for the vitruviansoftware.dev
# org, mirroring upstream terraform-example-foundation
# 4-projects/business_unit_2/development. Not gazelle-built / not in //:go.work —
# consumes the PUBLISHED pulumi-library Go modules (dogfoods the
# mirror-published versions). Backend: Pulumi Cloud (ipv1337).
# Run: bazel run //infrastructure/pulumi/foundation/gcp-projects/business_unit_2/development:preview
pulumi_project(
    name = "development",
    dir = "infrastructure/pulumi/foundation/gcp-projects/business_unit_2/development",
)

# `bazel test` visibility into the same `go test ./...` CI's go-test-infra job
# runs. extra_data carries the shared modules the go.mod `replace` points at,
# plus the committed stack config the config-pinning tests read.
pulumi_go_test(
    extra_data = [
        "Pulumi.production.yaml",
        "//infrastructure/pulumi/foundation/gcp-projects/modules:srcs",
    ],
)
