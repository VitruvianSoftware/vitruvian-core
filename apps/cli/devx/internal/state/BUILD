load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "state",
    srcs = [
        "checkpoint.go",
        "crypto.go",
        "dump.go",
        "relay.go",
        "replication.go",
        "wordlist.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/state",
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [
        "//apps/cli/devx/internal/cloudflare",
        "//apps/cli/devx/internal/config",
        "//apps/cli/devx/internal/database",
        "//apps/cli/devx/internal/doctor",
        "//apps/cli/devx/internal/exposure",
        "//apps/cli/devx/internal/provider",
        "@org_golang_x_crypto//pbkdf2",
    ],
)

go_test(
    name = "state_test",
    srcs = [
        "crypto_test.go",
        "relay_test.go",
        "replication_test.go",
    ],
    embed = [":state"],
    deps = ["//apps/cli/devx/internal/database"],
)
