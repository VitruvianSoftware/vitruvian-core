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
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/cloudflare",
        "//devx/internal/config",
        "//devx/internal/database",
        "//devx/internal/doctor",
        "//devx/internal/exposure",
        "//devx/internal/provider",
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
    deps = ["//devx/internal/database"],
)
