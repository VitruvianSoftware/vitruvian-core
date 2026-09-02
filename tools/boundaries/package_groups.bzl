# Copyright (c) 2026 VitruvianSoftware
#
# Formal monorepo architectural layer definitions and package groups.

PLATFORM_TOOLS_PACKAGES = [
    "//tools/...",
    "//githooks/...",
    "//.aspect/...",
    "//",
]

INFRASTRUCTURE_PACKAGES = [
    "//infrastructure/...",
    "//pulumi/...",
    "//gitops/...",
]

SHARED_PACKAGES = [
    "//packages/...",
    "//architecture/...",
]

APPLICATION_PACKAGES = [
    "//backstage/...",
    "//devx/...",
    "//homelab/...",
    "//mcp-slack/...",
    "//nexus-agent/...",
    "//oauth-user-inspector/...",
    "//tabula/...",
]

LAYER_PLATFORM_TOOLS = 0
LAYER_INFRA = 1
LAYER_SHARED_PACKAGES = 2
LAYER_APPS = 3

LAYER_NAMES = {
    LAYER_PLATFORM_TOOLS: "platform_tools",
    LAYER_INFRA: "infra",
    LAYER_SHARED_PACKAGES: "shared_packages",
    LAYER_APPS: "apps",
}
