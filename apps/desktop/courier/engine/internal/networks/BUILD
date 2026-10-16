load("@rules_go//go:def.bzl", "go_test")

go_test(
    name = "networks_test",
    srcs = ["signal_link_test.go"],
    deps = select({
        "@rules_go//go/platform:darwin": [
            "@com_github_stretchr_testify//require",
            "@fi_mau_go_mautrix_signal//pkg/libsignalgo",
        ],
        "@rules_go//go/platform:ios": [
            "@com_github_stretchr_testify//require",
            "@fi_mau_go_mautrix_signal//pkg/libsignalgo",
        ],
        "//conditions:default": [],
    }),
)
