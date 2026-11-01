# ext-marketplace

An Antigravity desktop plugin that provides an interactive **Extensions Marketplace** and installed plugin manager inside Antigravity's auxiliary sidecar pane.

## Features

- **Curated First-Party Catalog**: Includes all 9 first-party Vitruvian Antigravity extensions (`gh-watch`, `worktree-band`, `ralph-loop`, `hookify`, `security-guidance`, `receipts-report`, `live-context`, `savvy-fleet`, `ext-marketplace`) alongside any official or custom plugins installed in `~/.gemini/config/plugins/` and `~/.gemini/config/config.json`.
- **Deep Plugin Metadata Inspection**: Automatically inspects every installed plugin directory for `plugin.json`, `sidecars/*/sidecar.json` (`hasSidecarUi`), `skills/*/SKILL.md`, `hooks.json`, `mcp.json`, and `rules/*.md`.
- **Safe Non-Destructive Config Toggling**: Toggling a plugin runs `agy plugin enable|disable <name>` and atomically updates `plugins.<name>.enabled` in `~/.gemini/config/config.json` while preserving `installedFrom` and all other configuration keys.
- **One-Click Install, Update & Uninstall**: Install directly from the local `vitruvian-core` monorepo path (via symlink) or GitHub repository URL (`agy plugin install <repo>`), pull updates (`git -C ~/.gemini/config/plugins/<name> pull`), or uninstall (`agy plugin uninstall <name>`).
- **OpenUI Lang v0.5 Dashboard**: Exposes `/api/state` and `/api/openui` producing a valid `Card([Header(...), Grid(4, [...]), Table([...])])` specification.

## Requirements

The hook is written in Rust using only the standard library. The first time it
runs, `hooks/rust-hook.sh` compiles it with `rustc` (about a second) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)). Without it the hook leaves no notes about `agy plugin` commands (the panel still lists plugins on refresh) and says why on stderr. The side panel runs on
Antigravity's Node.js.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/ext-marketplace
```

Or link directly from the `vitruvian-core` monorepo:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/ext-marketplace
```

Open the marketplace panel from any conversation using `[Extensions Marketplace](sidecar://ext-marketplace/panel/)`.

## Update

```bash
git -C ~/.gemini/config/plugins/ext-marketplace pull
```

## Architecture

| Path | Purpose |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json`, `hooks/note-plugin-cmd.sh` | `PostToolUse` hook noticing `agy plugin` CLI invocations |
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (logic and tests), `main.rs` (entry point) |
| `rules/AGENTS.md` | Standing instructions for discovering and managing Antigravity plugins |
| `skills/ext-marketplace/SKILL.md` | Skill guide for inspecting the catalog, toggling plugins, and opening the marketplace pane |
| `sidecars/panel/sidecar.json` | Sidecar manifest (`SIDECAR_UI_ENTRYPOINT_AUX_PANE`) |
| `sidecars/panel/main.mjs` | Sidecar HTTP server (`/api/state`, `/api/openui`, `/api/toggle`, `/api/install`, `/api/uninstall`, `/api/update`) |
| `sidecars/panel/lib/core.mjs` | Pure functions: `MARKETPLACE_CATALOG`, `mergeInstalledWithCatalog`, `applyPluginToggleToConfig`, `inspectPluginDirMeta`, `summariseMarketplace` |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, HTML compiler, and `toOpenUILang(state)` |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive sidecar web panel |

## Test

Run the unit test suite with Node's built-in test runner:

```bash
node --test sidecars/panel/lib/core.test.mjs sidecars/panel/lib/openui.test.mjs
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/ext-marketplace-hook-test && /tmp/ext-marketplace-hook-test
```

Or via Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/ext-marketplace/...
```
