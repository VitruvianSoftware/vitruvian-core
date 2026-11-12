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
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/usb",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
    deps = [
        "//apps/cli/vitruvian-devx/internal/multinode/config",
        "//apps/cli/vitruvian-devx/internal/multinode/k3s",
        "//apps/cli/vitruvian-devx/internal/multinode/lima",
        "//apps/cli/vitruvian-devx/internal/multinode/util",
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
    deps = ["//apps/cli/vitruvian-devx/internal/multinode/config"],
)
