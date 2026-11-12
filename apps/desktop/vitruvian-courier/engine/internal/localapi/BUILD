load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "localapi",
    srcs = [
        "markdown.go",
        "pair.go",
        "rest.go",
        "schemas.go",
        "server.go",
        "tools.go",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-courier/engine/internal/localapi",
    visibility = ["//apps/desktop/vitruvian-courier/engine:__subpackages__"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/ids",
        "//apps/desktop/vitruvian-courier/engine/internal/richtext",
        "//apps/desktop/vitruvian-courier/engine/internal/searchtext",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_modelcontextprotocol_go_sdk//auth",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
    ],
)

go_test(
    name = "localapi_test",
    srcs = [
        "helpers_test.go",
        "markdown_test.go",
        "rest_test.go",
        "schema_test.go",
        "server_test.go",
        "tools_test.go",
    ],
    # The reference app's tool schemas, which TestToolsMatchReferenceSchemas holds the tools to.
    data = ["//apps/desktop/vitruvian-courier/protocol:mcp_tools"],
    embed = [":localapi"],
    deps = [
        "//apps/desktop/vitruvian-courier/engine/internal/actions",
        "//apps/desktop/vitruvian-courier/engine/internal/engine",
        "//apps/desktop/vitruvian-courier/engine/internal/fakenet",
        "//apps/desktop/vitruvian-courier/engine/internal/media",
        "//apps/desktop/vitruvian-courier/engine/internal/richtext",
        "//apps/desktop/vitruvian-courier/engine/internal/rpc",
        "//apps/desktop/vitruvian-courier/engine/internal/search",
        "//apps/desktop/vitruvian-courier/engine/internal/sqlite",
        "//apps/desktop/vitruvian-courier/engine/internal/store",
        "@com_github_modelcontextprotocol_go_sdk//mcp",
        "@com_github_rs_zerolog//:zerolog",
        "@com_github_stretchr_testify//require",
        "@net_maunium_go_mautrix//bridgev2",
    ],
)
