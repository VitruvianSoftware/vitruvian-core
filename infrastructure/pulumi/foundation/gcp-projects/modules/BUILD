load("//tools/pulumi:defs.bzl", "pulumi_go_test")

# Shared Go modules for the foundation 4-projects stage. A standalone Go module
# (own go.mod, outside //:go.work, not gazelle-built), consumed by every
# business-unit leaf through a `replace foundation-projects/modules => ../../modules`.

# The leaves' pulumi_go_test targets need these sources in their runfiles:
# their go.mod `replace` points here, and glob() cannot cross into this package.
filegroup(
    name = "srcs",
    srcs = glob(["**/*.go"]) + [
        "go.mod",
        "go.sum",
    ],
    visibility = ["//infrastructure/pulumi/foundation/gcp-projects:__subpackages__"],
)

# `bazel test //infrastructure/pulumi/foundation/gcp-projects/modules:test` --
# local `bazel test` visibility into the same `go test ./...` CI's
# go-test-infra job already runs (see pulumi_go_test() in defs.bzl).
pulumi_go_test()
