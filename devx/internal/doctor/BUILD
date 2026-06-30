load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "doctor",
    srcs = [
        "auth.go",
        "check.go",
        "install.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/doctor",
    visibility = ["//devx:__subpackages__"],
)

go_test(
    name = "doctor_test",
    srcs = [
        "check_test.go",
        "install_test.go",
    ],
    embed = [":doctor"],
)
