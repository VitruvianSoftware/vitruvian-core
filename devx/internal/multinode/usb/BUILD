load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "usb",
    srcs = [
        "baked.go",
        "build.go",
        "coords.go",
        "fcos.go",
        "joinspec.go",
        "prune.go",
        "render.go",
        "ubuntu.go",
        "ventoy.go",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/multinode/usb",
    visibility = ["//devx:__subpackages__"],
    deps = [
        "//devx/internal/multinode/config",
        "//devx/internal/multinode/k3s",
        "//devx/internal/multinode/lima",
        "//devx/internal/multinode/util",
    ],
)

go_test(
    name = "usb_test",
    srcs = [
        "build_test.go",
        "joinspec_test.go",
        "prune_test.go",
        "render_test.go",
    ],
    data = glob(["testdata/**"]),
    embed = [":usb"],
    deps = ["//devx/internal/multinode/config"],
)
