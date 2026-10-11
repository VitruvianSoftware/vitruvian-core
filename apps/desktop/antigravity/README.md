# Antigravity plugins

Plugins for the Antigravity desktop app that we share across the team. Each
one lives in its own folder under `plugins/` and is the folder Antigravity
loads, so installing one is a link into `~/.gemini/config/plugins/`.

| Plugin | What it does |
| --- | --- |
| [`pr-watch`](plugins/pr-watch/README.md) | Watches pull requests and wakes the owning conversation when CI starts failing. |

These are not native macOS apps, so the release contract in
[`apps/desktop/AGENTS.md`](../AGENTS.md) (DMGs, Homebrew cask, downloads
catalog) does not apply to them.
