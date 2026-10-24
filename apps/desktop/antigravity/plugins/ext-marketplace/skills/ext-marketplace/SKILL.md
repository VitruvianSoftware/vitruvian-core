---
name: ext-marketplace
description: Browse the Antigravity Extensions Marketplace catalog, inspect installed plugins (skills, hooks, rules, sidecars), and install, toggle, or update extensions. Use when the user asks about Antigravity plugins, extensions, or marketplace customizations.
---

# Extensions Marketplace (`ext-marketplace`)

`ext-marketplace` provides a unified catalog and management plane for Antigravity desktop extensions, combining the 9 first-party Vitruvian plugins with official and custom plugins installed under `~/.gemini/config/plugins/` and `~/.gemini/config/config.json`.

## Opening the Sidecar Panel

Surface a one-click pill in your chat response so the user can open the interactive Extensions Marketplace panel directly in the side pane:

```markdown
[Extensions Marketplace](sidecar://ext-marketplace/panel/)
```

## First-Party Vitruvian Catalog

1. **`gh-watch`** (`apps/desktop/antigravity/plugins/gh-watch`) — Polls GitHub pull requests and wakes the owning conversation when CI fails.
2. **`worktree-band`** (`apps/desktop/antigravity/plugins/worktree-band`) — Tracks git worktrees, branch hygiene, and safe worktree pruning.
3. **`ralph-loop`** (`apps/desktop/antigravity/plugins/ralph-loop`) — Runs iterative verification loops until completion criteria are met.
4. **`hookify`** (`apps/desktop/antigravity/plugins/hookify`) — Declarative PreToolUse and PostToolUse hook rule manager.
5. **`security-guidance`** (`apps/desktop/antigravity/plugins/security-guidance`) — Security posture scanner, secret check, and command risk advisor.
6. **`receipts-report`** (`apps/desktop/antigravity/plugins/receipts-report`) — Generates structured engineering receipts and audit summaries.
7. **`live-context`** (`apps/desktop/antigravity/plugins/live-context`) — Live workspace context, active rules, and MCP tool inventory inspector.
8. **`savvy-fleet`** (`apps/desktop/antigravity/plugins/savvy-fleet`) — Tiered `savvy-flow` orchestrator-worker workflow and subagent fleet telemetry.
9. **`ext-marketplace`** (`apps/desktop/antigravity/plugins/ext-marketplace`) — Extensions Marketplace catalog and plugin lifecycle manager.

## Managing Plugins

- **Enable / Disable**: Use the panel's toggle button (`/api/toggle`), which runs `agy plugin enable|disable <name>` and non-destructively updates `plugins.<name>.enabled` in `~/.gemini/config/config.json`.
- **Install**: Click **Install** in the panel (`/api/install`) to link from the local `vitruvian-core` monorepo (`apps/desktop/antigravity/plugins/<name>`) when available, or run `agy plugin install https://github.com/VitruvianSoftware/<name>`.
- **Update**: Click **Update** in the panel (`/api/update`) to run `git -C ~/.gemini/config/plugins/<name> pull`.
- **Uninstall**: Click **Uninstall** in the panel (`/api/uninstall`) to run `agy plugin uninstall <name>`.
