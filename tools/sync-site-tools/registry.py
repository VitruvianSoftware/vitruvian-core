# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Convention-driven multi-marketplace registry generator for vitruviansoftware.dev.

Scans plugin, MCP server, and skill manifests across the monorepo without
copying mutable release-please version numbers (so release-please PRs never
make the committed site data stale) and writes:
  - apps/web/vitruviansoftware-dev/_data/extensions.yml
  - apps/web/vitruviansoftware-dev/ai/catalog.json
  - .claude-plugin/marketplace.json
  - apps/web/vitruviansoftware-dev/.claude-plugin/marketplace.json
"""

import json
from pathlib import Path

DATA_YML = "apps/web/vitruviansoftware-dev/_data/extensions.yml"
AI_CATALOG_JSON = "apps/web/vitruviansoftware-dev/ai/catalog.json"
CLAUDE_MARKETPLACE_ROOT = ".claude-plugin/marketplace.json"
CLAUDE_MARKETPLACE_WEB = (
    "apps/web/vitruviansoftware-dev/.claude-plugin/marketplace.json"
)

ANTIGRAVITY_PLUGINS_DIR = "apps/desktop/antigravity/plugins"
CLAUDE_CODE_PLUGINS_DIR = "apps/claude-code/plugins"

# Canonical presentation order for first-party Antigravity/Claude Code plugins;
# any new plugin directory discovered on disk that is not in this tuple is
# appended automatically in alphabetical order by id.
PREFERRED_PLUGIN_ORDER = (
    "ext-marketplace",
    "gh-watch",
    "worktree-band",
    "ralph-loop",
    "hookify",
    "security-guidance",
    "receipts-report",
    "live-context",
    "savvy-fleet",
)

# Optional human-friendly display titles and prerequisite notes when a plugin's
# manifest does not declare a custom `marketplace` block. New plugins work
# without an entry here via automatic title-casing and capability inspection.
KNOWN_PLUGIN_META = {
    "ext-marketplace": {
        "title": "ext-marketplace",
        "category": "Marketplace & Manager",
        "status": "in-development",
        "needs": "Antigravity desktop (or Claude Code CLI for skill/hook inspection)",
        "note": "Opens the Extensions Marketplace & Live Plugin Manager sidecar to toggle installed plugins and 1-click install any extension in this catalog.",
    },
    "gh-watch": {
        "title": "gh-watch",
        "category": "CI & GitHub",
        "status": "mirror",
        "needs": "Antigravity desktop or Claude Code CLI, and the GitHub CLI signed in",
    },
    "worktree-band": {
        "title": "worktree-band",
        "category": "Git & Workspaces",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI, git, and GitHub CLI",
    },
    "ralph-loop": {
        "title": "ralph-loop",
        "category": "Autonomous Loops",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
    "hookify": {
        "title": "hookify",
        "category": "Guardrails & Hooks",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
    "security-guidance": {
        "title": "security-guidance",
        "category": "Security & AppSec",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
    "receipts-report": {
        "title": "receipts-report",
        "category": "Telemetry & Audit",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
    "live-context": {
        "title": "live-context",
        "category": "Context & Anti-Drift",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
    "savvy-fleet": {
        "title": "savvy-fleet",
        "category": "Subagent Orchestration",
        "status": "in-development",
        "needs": "Antigravity desktop or Claude Code CLI",
    },
}

ECOSYSTEMS = [
    {
        "id": "all",
        "title": "All Ecosystems",
        "badge": "All",
        "blurb": "Every first-party plugin, MCP server, agent skill, and signed desktop/mobile extension across the Vitruvian monorepo.",
    },
    {
        "id": "antigravity",
        "title": "Antigravity Desktop",
        "badge": "Antigravity",
        "blurb": "Native plugins with sidecar web panels, lifecycle hooks, rules, and skills for Antigravity Desktop.",
        "bootstrap_label": "Install the Antigravity Extensions Marketplace",
        "bootstrap_command": "agy plugin install https://github.com/VitruvianSoftware/ext-marketplace",
        "feed_url": "/ai/catalog.json",
    },
    {
        "id": "claude-code",
        "title": "Claude Code",
        "badge": "Claude Code",
        "blurb": "Installable via the root .claude-plugin/marketplace.json catalog: hooks, guardrails, skills, and MCP servers.",
        "bootstrap_label": "Add the Vitruvian marketplace in Claude Code",
        "bootstrap_command": "claude plugin marketplace add VitruvianSoftware/vitruvian-core",
        "feed_url": "/.claude-plugin/marketplace.json",
    },
    {
        "id": "codex-opencode",
        "title": "Codex & OpenCode",
        "badge": "Codex / OpenCode",
        "blurb": "Portable SKILL.md agent workflows and standard stdio/HTTP Model Context Protocol servers.",
        "bootstrap_label": "Bootstrap project skills",
        "bootstrap_command": "devx agent init",
        "feed_url": "/ai/catalog.json",
    },
    {
        "id": "mcp",
        "title": "MCP Servers",
        "badge": "MCP",
        "blurb": "Model Context Protocol servers that work across Claude Code, Antigravity, OpenCode, Codex, and Cursor.",
        "bootstrap_label": "Add Slack MCP server",
        "bootstrap_command": "claude mcp add slack -- npx -y @vitruviansoftware/mcp-slack@latest",
        "feed_url": "/ai/catalog.json",
    },
    {
        "id": "vitruvian-desktop",
        "title": "Vitruvian Desktop (macOS)",
        "badge": "Vitruvian macOS",
        "blurb": "Ed25519-signed JSON-RPC 2.0 extensions for the macOS notch island, Command Bar, and Radial menu.",
        "bootstrap_label": "In-app catalog",
        "bootstrap_command": "Vitruvian › Settings › Extensions",
        "feed_url": "/tools/catalog/tools.json",
    },
    {
        "id": "vitruvian-remote",
        "title": "Vitruvian Remote (Android)",
        "badge": "Android Remote",
        "blurb": "Foldable Android remote, Tailscale bridge, Sony Google TV control, and live host observability companions.",
        "bootstrap_label": "Download Android APK",
        "bootstrap_command": "https://vitruviansoftware.dev/downloads/",
        "feed_url": "/tools/catalog/tools.json",
    },
]

EXTENSION_KINDS = [
    {
        "id": "plugin",
        "title": "Agent Plugins & Marketplaces",
        "blurb": "Installed into Antigravity Desktop or Claude Code as a unit. A plugin can add sidecar web panels, background watchers, lifecycle hooks, rules, and skills.",
    },
    {
        "id": "mcp",
        "title": "MCP Servers",
        "blurb": "Model Context Protocol servers. They give any MCP-compatible agent structured, reviewable access to external systems and hardware.",
    },
    {
        "id": "skill",
        "title": "Portable Agent Skills",
        "blurb": "SKILL.md instructions an agent loads on demand across Antigravity, Claude Code, OpenCode, and Codex.",
    },
]


def scalar(value):
    """A YAML scalar: JSON's double-quoted string is one."""
    return json.dumps(value, ensure_ascii=False)


def inspect_capabilities(plugin_dir: Path):
    """Inspects a plugin directory on disk and returns capability badges and lists."""
    capabilities = []
    skills = []
    hooks = []
    rules = []
    has_sidecar = False
    has_claude_plugin = (plugin_dir / ".claude-plugin" / "plugin.json").is_file()

    sidecars_dir = plugin_dir / "sidecars"
    if sidecars_dir.is_dir():
        for child in sorted(sidecars_dir.iterdir()):
            if child.is_dir() and (child / "sidecar.json").is_file():
                has_sidecar = True
                break
    if has_sidecar:
        capabilities.append("Sidecar UI")

    hooks_json = plugin_dir / "hooks.json"
    if hooks_json.is_file():
        try:
            data = json.loads(hooks_json.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                hooks = sorted(data.keys())
        except Exception:
            hooks = ["hooks"]
        capabilities.append("Lifecycle Hooks")

    skills_dir = plugin_dir / "skills"
    if skills_dir.is_dir():
        for child in sorted(skills_dir.iterdir()):
            if child.is_dir() and (child / "SKILL.md").is_file():
                skills.append(child.name)
        if skills:
            capabilities.append(
                f"{len(skills)} Skill" + ("s" if len(skills) != 1 else "")
            )

    rules_dir = plugin_dir / "rules"
    if rules_dir.is_dir():
        for child in sorted(rules_dir.iterdir()):
            if child.is_file() and child.name.endswith(".md"):
                rules.append(child.name)
        if rules:
            capabilities.append("Rules")

    if (plugin_dir / ".mcp.json").is_file() or (plugin_dir / "mcp.json").is_file():
        capabilities.append("MCP Server")

    return {
        "capabilities": capabilities,
        "skills": skills,
        "hooks": hooks,
        "rules": rules,
        "has_sidecar": has_sidecar,
        "has_claude_plugin": has_claude_plugin,
    }


def discover_plugin_dir(root: Path, plugin_dir: Path, default_host: str):
    """Builds a normalized extension entry from a plugin directory on disk."""
    plugin_json_path = plugin_dir / "plugin.json"
    claude_json_path = plugin_dir / ".claude-plugin" / "plugin.json"
    if plugin_json_path.is_file():
        manifest = json.loads(plugin_json_path.read_text(encoding="utf-8"))
    elif claude_json_path.is_file():
        manifest = json.loads(claude_json_path.read_text(encoding="utf-8"))
    else:
        return None

    ext_id = manifest["name"]
    custom = manifest.get("marketplace") or manifest.get("x-vitruvian") or {}
    known = KNOWN_PLUGIN_META.get(ext_id, {})
    caps = inspect_capabilities(plugin_dir)

    rel_source = plugin_dir.relative_to(root).as_posix()
    repo_url = custom.get("repo") or manifest.get(
        "repository", f"https://github.com/VitruvianSoftware/{ext_id}"
    )
    status = custom.get("status") or known.get("status", "in-development")
    # If not yet mirrored to a standalone repo, link the card title to the monorepo source tree.
    public_repo = repo_url if status in ("released", "mirror") else ""

    ecosystems = list(custom.get("ecosystems") or [])
    if not ecosystems:
        if plugin_json_path.is_file() or default_host == "antigravity":
            ecosystems.append("antigravity")
        if caps["has_claude_plugin"] or default_host == "claude-code":
            ecosystems.append("claude-code")
        if caps["skills"]:
            ecosystems.append("codex-opencode")

    installs = list(custom.get("installs") or [])
    if not installs:
        if "antigravity" in ecosystems:
            install_target = (
                repo_url
                if status in ("released", "mirror")
                else f"https://github.com/VitruvianSoftware/vitruvian-core/tree/main/{rel_source}"
            )
            installs.append(
                {
                    "tool": "Antigravity",
                    "ecosystem": "antigravity",
                    "label": "Install in Antigravity",
                    "command": f"agy plugin install {repo_url}",
                    "monorepo_command": f"agy plugin install {install_target}",
                }
            )
        if "claude-code" in ecosystems:
            installs.append(
                {
                    "tool": "Claude Code",
                    "ecosystem": "claude-code",
                    "label": "Install in Claude Code (after adding marketplace)",
                    "command": f"claude plugin install {ext_id}",
                }
            )
        if "codex-opencode" in ecosystems and caps["skills"]:
            skill_list = ", ".join(f"/{s}" for s in caps["skills"])
            installs.append(
                {
                    "tool": "Codex / OpenCode",
                    "ecosystem": "codex-opencode",
                    "label": f"Load portable SKILL.md ({skill_list})",
                    "command": f"cp -R {rel_source}/skills/* ~/.agents/skills/",
                }
            )

    return {
        "id": ext_id,
        "name": custom.get("title") or known.get("title") or ext_id,
        "kind": "plugin",
        "category": custom.get("category") or known.get("category") or "Agent Plugin",
        "status": status,
        "summary": custom.get("summary") or manifest.get("description", ""),
        "repo": public_repo,
        "mirror_repo": repo_url,
        "source": rel_source,
        "ecosystems": ecosystems,
        "capabilities": caps["capabilities"],
        "skills": caps["skills"],
        "hooks": caps["hooks"],
        "rules": caps["rules"],
        "keywords": manifest.get("keywords", []),
        "needs": custom.get("needs")
        or known.get("needs", "Antigravity desktop or Claude Code CLI"),
        "note": custom.get("note") or known.get("note", ""),
        "installs": installs,
        "claude_marketplace_source": f"./{rel_source}"
        if caps["has_claude_plugin"]
        else "",
    }


def discover_all(root: Path):
    """Discovers all plugins, MCP servers, and skills across the monorepo."""
    discovered_plugins = []

    ag_root = root / ANTIGRAVITY_PLUGINS_DIR
    if ag_root.is_dir():
        for child in sorted(ag_root.iterdir()):
            if child.is_dir():
                item = discover_plugin_dir(root, child, "antigravity")
                if item:
                    discovered_plugins.append(item)

    cc_root = root / CLAUDE_CODE_PLUGINS_DIR
    if cc_root.is_dir():
        for child in sorted(cc_root.iterdir()):
            if child.is_dir():
                item = discover_plugin_dir(root, child, "claude-code")
                if item:
                    discovered_plugins.append(item)

    order_map = {name: idx for idx, name in enumerate(PREFERRED_PLUGIN_ORDER)}
    discovered_plugins.sort(
        key=lambda item: (order_map.get(item["id"], 999), item["id"])
    )

    # Multi-surface & MCP extensions from apps/desktop/nexus-agent, apps/mcp/*, apps/cli/devx
    additional = [
        {
            "id": "mcp-roborock",
            "name": "mcp-roborock",
            "kind": "plugin",
            "category": "Home Automation & FastMCP",
            "status": "mirror",
            "summary": "A Roborock vacuum integration: a local daemon, a FastMCP server and plugins that let a coding agent check status, start room cleans or send the robot home.",
            "repo": "https://github.com/VitruvianSoftware/mcp-roborock",
            "mirror_repo": "https://github.com/VitruvianSoftware/mcp-roborock",
            "source": "apps/mcp/roborock",
            "ecosystems": ["claude-code", "antigravity", "codex-opencode", "mcp"],
            "capabilities": ["MCP Server", "2 Skills", "CLI Daemon"],
            "skills": ["roborock-control", "roborock-setup"],
            "hooks": [],
            "rules": [],
            "keywords": ["roborock", "vacuum", "home-automation", "mcp"],
            "needs": "uv, and a Roborock account (the plugin walks you through logging in)",
            "note": "",
            "installs": [
                {
                    "tool": "Claude Code",
                    "ecosystem": "claude-code",
                    "label": "Claude Code, step 1: add the marketplace",
                    "command": "claude plugin marketplace add VitruvianSoftware/mcp-roborock",
                },
                {
                    "tool": "Claude Code",
                    "ecosystem": "claude-code",
                    "label": "Claude Code, step 2: install",
                    "command": "claude plugin install vitruvian-roborock",
                },
                {
                    "tool": "Antigravity",
                    "ecosystem": "antigravity",
                    "label": "Install in Antigravity",
                    "command": "agy plugin install https://github.com/VitruvianSoftware/mcp-roborock",
                },
            ],
            "claude_marketplace_source": "./apps/mcp/roborock/plugin",
        },
        {
            "id": "nexus-agent",
            "name": "NexusAgent",
            "kind": "plugin",
            "category": "Remote Agent Bridge",
            "status": "mirror",
            "summary": "A macOS menu bar app and Telegram bot that forwards your messages to a locally installed AI coding CLI, so a full agent session is reachable from your phone.",
            "repo": "https://github.com/VitruvianSoftware/nexus-agent",
            "mirror_repo": "https://github.com/VitruvianSoftware/nexus-agent",
            "source": "apps/desktop/nexus-agent",
            "ecosystems": ["antigravity", "claude-code", "vitruvian-desktop"],
            "capabilities": ["2 Skills", "macOS Menu Bar", "Telegram Bridge"],
            "skills": ["configure", "access"],
            "hooks": [],
            "rules": [],
            "keywords": ["telegram", "remote-agent", "macos", "antigravity"],
            "needs": "Node.js and a Telegram account",
            "note": 'Installing adds a setup guide to Antigravity. Then ask the agent to "help me set up the Telegram bot" and it walks you through creating the bot and starting it.',
            "installs": [
                {
                    "tool": "Antigravity",
                    "ecosystem": "antigravity",
                    "label": "Install in Antigravity",
                    "command": "agy plugin install https://github.com/VitruvianSoftware/nexus-agent",
                }
            ],
            "claude_marketplace_source": "",
        },
        {
            "id": "mcp-slack",
            "name": "mcp-slack",
            "kind": "mcp",
            "category": "Team Communication MCP",
            "status": "mirror",
            "summary": "A Slack MCP server with dual-token auth: around forty tools covering channels, threads, search, files, user groups and Canvas editing, acting as the bot or as you.",
            "repo": "https://github.com/VitruvianSoftware/mcp-slack",
            "mirror_repo": "https://github.com/VitruvianSoftware/mcp-slack",
            "source": "apps/mcp/slack",
            "ecosystems": ["claude-code", "antigravity", "codex-opencode", "mcp"],
            "capabilities": ["MCP Server", "40+ Slack Tools", "Dual-Token Auth"],
            "skills": [],
            "hooks": [],
            "rules": [],
            "keywords": ["slack", "mcp", "typescript"],
            "needs": "Slack bot and user tokens, passed to the server as environment variables (add an --env flag for each; the README lists them)",
            "note": "",
            "installs": [
                {
                    "tool": "Claude Code",
                    "ecosystem": "claude-code",
                    "label": "Install in Claude Code",
                    "command": "claude mcp add slack -- npx -y @vitruviansoftware/mcp-slack@latest",
                },
                {
                    "tool": "Antigravity",
                    "ecosystem": "antigravity",
                    "label": "Install in Antigravity",
                    "command": "agy mcp add slack npx -y @vitruviansoftware/mcp-slack@latest",
                },
                {
                    "tool": "Codex / OpenCode",
                    "ecosystem": "codex-opencode",
                    "label": "Run via npx (stdio MCP)",
                    "command": "npx -y @vitruviansoftware/mcp-slack@latest",
                },
            ],
            "claude_marketplace_source": "",
        },
        {
            "id": "devx",
            "name": "devx",
            "kind": "skill",
            "category": "Local Dev & K3s Skills",
            "status": "released",
            "summary": "A local development orchestrator. One CLI provisions container VMs, ephemeral databases and cloud emulators, local K3s clusters and Cloudflare tunnel ingress, and starts everything in dependency order.",
            "repo": "https://github.com/VitruvianSoftware/devx",
            "mirror_repo": "https://github.com/VitruvianSoftware/devx",
            "source": "apps/cli/devx",
            "ecosystems": ["antigravity", "claude-code", "codex-opencode"],
            "capabilities": ["Portable Agent Skills", "Homebrew CLI"],
            "skills": ["devx"],
            "hooks": [],
            "rules": [],
            "keywords": ["devx", "k3s", "lima", "skills"],
            "needs": "devx installed (`brew install VitruvianSoftware/tap/devx`)",
            "note": "",
            "installs": [
                {
                    "tool": "Any agent",
                    "ecosystem": "codex-opencode",
                    "label": "Add the skills to your project (Antigravity, Claude Code, Codex, OpenCode)",
                    "command": "devx agent init",
                }
            ],
            "claude_marketplace_source": "",
        },
    ]

    return discovered_plugins + additional


def render_extensions_yml(extensions):
    """Renders apps/web/vitruviansoftware-dev/_data/extensions.yml."""
    lines = [
        "# Written by tools/sync-site-tools/registry.py from monorepo plugin manifests.",
        "# Do not edit by hand; run:",
        "#   bazel run //tools/sync-site-tools:sync",
        "ecosystems:",
    ]
    for eco in ECOSYSTEMS:
        lines += [
            f"  - id: {scalar(eco['id'])}",
            f"    title: {scalar(eco['title'])}",
            f"    badge: {scalar(eco['badge'])}",
            f"    blurb: {scalar(eco['blurb'])}",
        ]
        if "bootstrap_label" in eco:
            lines.append(f"    bootstrap_label: {scalar(eco['bootstrap_label'])}")
        if "bootstrap_command" in eco:
            lines.append(f"    bootstrap_command: {scalar(eco['bootstrap_command'])}")
        if "feed_url" in eco:
            lines.append(f"    feed_url: {scalar(eco['feed_url'])}")

    lines.append("extension_kinds:")
    for kind in EXTENSION_KINDS:
        lines += [
            f"  - id: {scalar(kind['id'])}",
            f"    title: {scalar(kind['title'])}",
            f"    blurb: {scalar(kind['blurb'])}",
        ]

    lines.append("extensions:")
    for ext in extensions:
        lines += [
            f"  - id: {scalar(ext['id'])}",
            f"    name: {scalar(ext['name'])}",
            f"    kind: {scalar(ext['kind'])}",
            f"    category: {scalar(ext['category'])}",
            f"    status: {scalar(ext['status'])}",
            f"    summary: {scalar(ext['summary'])}",
            f"    repo: {scalar(ext['repo'])}",
            f"    mirror_repo: {scalar(ext['mirror_repo'])}",
            f"    source: {scalar(ext['source'])}",
        ]
        if ext.get("needs"):
            lines.append(f"    needs: {scalar(ext['needs'])}")
        if ext.get("note"):
            lines.append(f"    note: {scalar(ext['note'])}")

        lines.append("    ecosystems:")
        for eco_id in ext["ecosystems"]:
            lines.append(f"      - {scalar(eco_id)}")

        if ext["capabilities"]:
            lines.append("    capabilities:")
            for cap in ext["capabilities"]:
                lines.append(f"      - {scalar(cap)}")
        else:
            lines.append("    capabilities: []")

        lines.append("    installs:")
        for inst in ext["installs"]:
            lines += [
                f"      - tool: {scalar(inst['tool'])}",
                f"        ecosystem: {scalar(inst['ecosystem'])}",
                f"        label: {scalar(inst['label'])}",
                f"        command: {scalar(inst['command'])}",
            ]

    return ("\n".join(lines) + "\n").encode("utf-8")


def render_ai_catalog_json(extensions):
    """Renders apps/web/vitruviansoftware-dev/ai/catalog.json."""
    payload = {
        "$schema": "https://vitruviansoftware.dev/ai/catalog.schema.json",
        "name": "vitruvian-ai-extensions",
        "title": "Vitruvian Multi-Marketplace Extension Registry",
        "description": "Convention-discovered plugins, MCP servers, portable agent skills, and signed desktop/mobile tools from VitruvianSoftware.",
        "homepage": "https://vitruviansoftware.dev/ai/",
        "repository": "https://github.com/VitruvianSoftware/vitruvian-core",
        "feeds": {
            "unified": "https://vitruviansoftware.dev/ai/catalog.json",
            "claudeCodeMarketplace": "https://vitruviansoftware.dev/.claude-plugin/marketplace.json",
            "vitruvianDesktopTools": "https://vitruviansoftware.dev/tools/catalog/tools.json",
            "vitruvianDesktopSignature": "https://vitruviansoftware.dev/tools/catalog/tools.json.sig",
        },
        "ecosystems": ECOSYSTEMS,
        "extensions": [
            {
                "id": ext["id"],
                "name": ext["name"],
                "kind": ext["kind"],
                "category": ext["category"],
                "status": ext["status"],
                "summary": ext["summary"],
                "repo": ext["repo"],
                "mirrorRepo": ext["mirror_repo"],
                "source": ext["source"],
                "ecosystems": ext["ecosystems"],
                "capabilities": ext["capabilities"],
                "skills": ext["skills"],
                "hooks": ext["hooks"],
                "rules": ext["rules"],
                "needs": ext["needs"],
                "note": ext["note"],
                "installs": ext["installs"],
            }
            for ext in extensions
        ],
    }
    return (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def render_claude_marketplace_json(extensions):
    """Renders .claude-plugin/marketplace.json for Claude Code."""
    plugins = []
    for ext in extensions:
        src = ext.get("claude_marketplace_source")
        if not src:
            continue
        plugins.append(
            {
                "name": ext["id"],
                "source": src,
                "description": ext["summary"],
                "author": {
                    "name": "VitruvianSoftware",
                    "url": "https://github.com/VitruvianSoftware",
                },
                "homepage": "https://vitruviansoftware.dev/ai/",
                "repository": ext["mirror_repo"],
                "license": "MIT",
                "keywords": ext["keywords"],
            }
        )

    payload = {
        "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
        "name": "vitruvian-core",
        "description": "Vitruvian Software multi-agent plugins, guardrails, FastMCP servers, and workflow skills for Claude Code and Antigravity",
        "owner": {
            "name": "VitruvianSoftware",
            "url": "https://github.com/VitruvianSoftware",
        },
        "plugins": plugins,
    }
    return (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def outputs(root: Path):
    """Returns all generated marketplace files keyed by repo-relative path."""
    extensions = discover_all(root)
    claude_bytes = render_claude_marketplace_json(extensions)
    return {
        DATA_YML: render_extensions_yml(extensions),
        AI_CATALOG_JSON: render_ai_catalog_json(extensions),
        CLAUDE_MARKETPLACE_ROOT: claude_bytes,
        CLAUDE_MARKETPLACE_WEB: claude_bytes,
    }
