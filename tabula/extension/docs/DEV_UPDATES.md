# Dev builds & self-update

Every `main` commit touching `tabula/extension/**` publishes a rolling
prerelease (`tabula-extension-dev-latest`) with the built bundle, stamped with
the source commit (`build_info.json`).

## One-time setup

1. `tabcli ext update` — downloads the latest bundle to `~/.tabula/extension`
   (override with `--dir`).
2. `chrome://extensions` → enable **Developer mode** → **Load unpacked** →
   pick the directory printed by `tabcli ext path`.

## Updating

When a newer build is deployed, the dashboard shows a banner
("New build deployed (…) — run `tabcli ext update`, then reload"):

1. `tabcli ext update`
2. Click **Reload** in the banner (or ↻ on chrome://extensions).

The banner only appears on load-unpacked installs of CI-built bundles —
local `npm run build` bundles carry `commit: "dev"` and never check. The
check compares this build's commit against the deployed dev API's `GET /`
provenance and polls every 15 minutes; network failures stay silent.

Requirements: `gh` (authenticated: `gh auth login`) and `unzip` on PATH.
