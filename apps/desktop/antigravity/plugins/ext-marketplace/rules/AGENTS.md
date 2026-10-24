# ext-marketplace: managing Antigravity plugins and extensions

When the user asks to browse, install, enable, disable, or update Antigravity plugins, or wants to see which skills, hooks, rules, and sidecar panels each extension provides:

- Surface a one-click pill to open the Extensions Marketplace sidecar pane:
  `[Extensions Marketplace](sidecar://ext-marketplace/panel/)`
- First-party Vitruvian extensions live in the monorepo under `apps/desktop/antigravity/plugins/<name>` and mirror to `https://github.com/VitruvianSoftware/<name>`.
- When toggling plugins in `~/.gemini/config/config.json`, always preserve existing `installedFrom` metadata and unrelated settings under `plugins.<name>`.
