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
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/state",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/cloudflare",
        "//apps/cli/vitruvian-devx/internal/config",
        "//apps/cli/vitruvian-devx/internal/database",
        "//apps/cli/vitruvian-devx/internal/doctor",
        "//apps/cli/vitruvian-devx/internal/exposure",
        "//apps/cli/vitruvian-devx/internal/provider",
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
    deps = ["//apps/cli/vitruvian-devx/internal/database"],
)
