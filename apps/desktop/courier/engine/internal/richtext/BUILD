load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "richtext",
    srcs = ["richtext.go"],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/richtext",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
)

go_test(
    name = "richtext_test",
    srcs = [
        "fuzz_test.go",
        "richtext_test.go",
    ],
    # The shared cases, which seed the fuzzer too; the app's Swift tests read the same file.
    data = ["//apps/desktop/courier/protocol:richtext_cases"],
    embed = [":richtext"],
    deps = [
        "@com_github_stretchr_testify//assert",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//format",
    ],
)
