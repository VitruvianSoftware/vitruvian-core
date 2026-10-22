load("@rules_go//go:def.bzl", "go_library", "go_test")

go_test(
    name = "networks_test",
    srcs = [
        "networks_test.go",
        "offline_test.go",
        "signal_absent_other_test.go",
        "signal_link_test.go",
        "signal_registered_darwin_test.go",
    ],
    # The engine's go.mod, read by TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks, and the protocol's
    # networks.json, read by TestRegistryMatchesTheProtocolsNetworkList.
    data = [
        "//apps/desktop/courier/engine:go.mod",
        "//apps/desktop/courier/protocol",
    ],
    embed = [":networks"],
    deps = [
        "//apps/desktop/courier/engine/internal/actions",
        "//apps/desktop/courier/engine/internal/host",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/richtext",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@fi_mau_go_mautrix_gmessages//pkg/connector",
        "@fi_mau_go_mautrix_gmessages//pkg/libgm/gmproto",
        "@fi_mau_go_mautrix_slack//pkg/connector",
        "@fi_mau_go_mautrix_slack//pkg/slackid",
        "@fi_mau_go_mautrix_telegram//pkg/connector",
        "@fi_mau_go_mautrix_telegram//pkg/connector/ids",
        "@fi_mau_go_mautrix_whatsapp//pkg/connector",
        "@fi_mau_go_mautrix_whatsapp//pkg/waid",
        "@in_gopkg_yaml_v3//:yaml_v3",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//bridgev2/database",
        "@net_maunium_go_mautrix//bridgev2/networkid",
        "@net_maunium_go_mautrix//event",
    ] + select({
        "@rules_go//go/platform:darwin": [
            "@fi_mau_go_mautrix_signal//pkg/connector",
            "@fi_mau_go_mautrix_signal//pkg/libsignalgo",
        ],
        "@rules_go//go/platform:ios": [
            "@fi_mau_go_mautrix_signal//pkg/connector",
            "@fi_mau_go_mautrix_signal//pkg/libsignalgo",
        ],
        "//conditions:default": [],
    }),
)

go_library(
    name = "networks",
    srcs = [
        "networks.go",
        "networks_signal_darwin.go",
        "networks_signal_other.go",
    ],
    importpath = "github.com/VitruvianSoftware/courier/engine/internal/networks",
    visibility = ["//apps/desktop/courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/courier/engine/internal/engine",
        "//apps/desktop/courier/engine/internal/media",
        "//apps/desktop/courier/engine/internal/store",
        "@com_github_rs_zerolog//:zerolog",
        "@fi_mau_go_mautrix_gmessages//pkg/connector",
        "@fi_mau_go_mautrix_slack//pkg/connector",
        "@fi_mau_go_mautrix_telegram//pkg/connector",
        "@fi_mau_go_mautrix_whatsapp//pkg/connector",
        "@in_gopkg_yaml_v3//:yaml_v3",
        "@net_maunium_go_mautrix//bridgev2",
        "@net_maunium_go_mautrix//event",
    ] + select({
        "@rules_go//go/platform:darwin": [
            "@fi_mau_go_mautrix_signal//pkg/connector",
        ],
        "@rules_go//go/platform:ios": [
            "@fi_mau_go_mautrix_signal//pkg/connector",
        ],
        "//conditions:default": [],
    }),
)
