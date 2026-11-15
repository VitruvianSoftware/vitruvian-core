load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "agent",
    srcs = ["embed.go"],
    embedsrcs = [
        "templates/skills/devx/SKILL.md",
        "templates/skills/platform-engineer/SKILL.md",
    ],
    importpath = "github.com/VitruvianSoftware/vitruvian-devx/internal/agent",
    visibility = ["//apps/cli/vitruvian-devx:__subpackages__"],
)

go_test(
    name = "agent_test",
    srcs = ["embed_test.go"],
    embed = [":agent"],
)
