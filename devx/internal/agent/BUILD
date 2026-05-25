load("@rules_go//go:def.bzl", "go_library")

go_library(
    name = "agent",
    srcs = ["embed.go"],
    embedsrcs = [
        "templates/.agents/skills/devx/SKILL.md",
        "templates/.agents/skills/platform-engineer/SKILL.md",
        "templates/.claude/skills/devx/SKILL.md",
        "templates/.claude/skills/platform-engineer/SKILL.md",
        "templates/.cursor/skills/devx/SKILL.md",
        "templates/.cursor/skills/platform-engineer/SKILL.md",
        "templates/.github/skills/devx/SKILL.md",
        "templates/.github/skills/platform-engineer/SKILL.md",
    ],
    importpath = "github.com/VitruvianSoftware/devx/internal/agent",
    visibility = ["//devx:__subpackages__"],
)
