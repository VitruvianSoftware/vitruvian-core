# Claude Code Plugins (`apps/claude-code/plugins/`)

Standalone plugins and mods built specifically for **Claude Code** live in subdirectories here (`apps/claude-code/plugins/<plugin-name>/`). Multi-host plugins that also include an Antigravity Desktop sidecar panel live in [`apps/desktop/antigravity/plugins/`](../../desktop/antigravity/plugins/) and carry both `plugin.json` (Antigravity) and `.claude-plugin/plugin.json` (Claude Code).

## Self-Registration by Convention

You do **not** need to hand-edit `apps/web/vitruviansoftware-dev/_data/extensions.yml`, `apps/web/vitruviansoftware-dev/ai/catalog.json`, or the root `.claude-plugin/marketplace.json`.

Any directory under `apps/claude-code/plugins/<name>/` (or `apps/desktop/antigravity/plugins/<name>/`) containing `.claude-plugin/plugin.json` or `plugin.json` is discovered automatically by `//tools/sync-site-tools:sync`.

### Standard Directory Layout

```text
apps/claude-code/plugins/<name>/
├── .claude-plugin/
│   └── plugin.json          # Required: name, description, author, repository, license, keywords
├── skills/
│   └── <skill-name>/
│       └── SKILL.md         # Optional: portable agent skills (Claude Code, Antigravity, OpenCode, Codex)
├── hooks/                   # Optional: PreToolUse, PostToolUse, Stop hook scripts
├── .mcp.json                # Optional: bundled MCP server definition
└── README.md
```

### Syncing the Multi-Marketplace Catalogs

After adding or updating a plugin, run:

```sh
bazel run //tools/sync-site-tools:sync
```

This single command regenerates:
1. `apps/web/vitruviansoftware-dev/_data/extensions.yml` (powers `https://vitruviansoftware.dev/ai/`)
2. `apps/web/vitruviansoftware-dev/ai/catalog.json` (public multi-marketplace JSON registry)
3. `.claude-plugin/marketplace.json` and `apps/web/vitruviansoftware-dev/.claude-plugin/marketplace.json` (`claude plugin marketplace add VitruvianSoftware/vitruvian-core`)

CI enforces zero drift via `bazel test //tools/sync-site-tools:in_sync_test` and `bazel run //tools/conformance:check`.
