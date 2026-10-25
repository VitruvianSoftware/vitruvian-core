load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "media",
    srcs = [
        "blurhash.go",
        "inspect.go",
        "media.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/media",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = ["@org_golang_x_image//webp"],
)

go_test(
    name = "media_test",
    srcs = [
        "blurhash_test.go",
        "inspect_test.go",
        "media_test.go",
    ],
    embed = [":media"],
    deps = ["@com_github_stretchr_testify//require"],
)
