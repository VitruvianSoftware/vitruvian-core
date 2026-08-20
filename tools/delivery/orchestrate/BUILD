load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "orchestrate_lib",
    srcs = ["main.go"],
    importpath = "github.com/VitruvianSoftware/vitruvian-core/tools/delivery/orchestrate",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "orchestrate",
    embed = [":orchestrate_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "orchestrate_test",
    size = "small",
    srcs = ["main_test.go"],
    # The decision engine is NOT stubbed: these tests drive the real
    # tools/ci/deploy-affected.sh over scratch git repos, so it (and the
    # td-lib.sh it sources) must be in the runfiles. rules_go runs the test
    # from its own package dir, so the test's "../../ci/..." path resolves
    # against the runfiles copy under bazel test and against the checkout
    # under a plain `GOWORK=off go test ./...`.
    data = [
        "//tools/ci:deploy-affected.sh",
        "//tools/ci:td-lib.sh",
    ],
    embed = [":orchestrate_lib"],
)
