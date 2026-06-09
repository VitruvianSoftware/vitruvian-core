load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "usb",
    srcs = [
        "assemble_script.go",
        "baked.go",
        "build.go",
        "builder.go",
        "coords.go",
        "fcos.go",
        "flash.go",
        "joinspec.go",
        "prune.go",
        "render.go",
        "sink.go",
        "size.go",
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
        "assemble_script_test.go",
        "build_test.go",
        "builder_test.go",
        "butane_compile_test.go",
        "flash_test.go",
        "joinspec_test.go",
        "prune_test.go",
        "render_test.go",
        "size_test.go",
    ],
    data = glob(["testdata/**"]),
    embed = [":usb"],
    deps = ["//devx/internal/multinode/config"],
)
