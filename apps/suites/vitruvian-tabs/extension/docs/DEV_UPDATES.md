# Dev builds & self-update

Every `main` commit touching `apps/suites/vitruvian-tabs/extension/**` publishes a rolling
prerelease (`vitruvian-tabs-extension-dev-latest`) with the built bundle, stamped with
the source commit (`build_info.json`).

## One-time setup

1. `vitruvian-tabs ext update` — downloads the latest bundle to `~/.vitruvian-tabs/extension`
   (override with `--dir`).
2. `chrome://extensions` → enable **Developer mode** → **Load unpacked** →
   pick the directory printed by `vitruvian-tabs ext path`.

## Updating

When a newer build is deployed, the dashboard shows a banner
("New build deployed (…) — run `vitruvian-tabs ext update`, then reload"):

1. `vitruvian-tabs ext update`
2. Click **Reload** in the banner (or ↻ on chrome://extensions).

The banner only appears on load-unpacked installs of CI-built bundles —
local `npm run build` bundles carry `commit: "dev"` and never check. The
check compares this build's commit against the deployed dev API's `GET /`
provenance and polls every 15 minutes; network failures stay silent.

Requirements: `gh` (authenticated: `gh auth login`) and `unzip` on PATH.

## Channels

The install carries its channel (`channel.json`, written by vitruvian-tabs); a bare
`vitruvian-tabs ext update` stays on it.

| Channel | Tracks                                         | Switch                              |
| ------- | ---------------------------------------------- | ----------------------------------- |
| alpha   | every `main` commit (rolling dev-latest)       | `vitruvian-tabs ext update --channel alpha` |
| beta    | the latest release cut (`vitruvian-tabs-extension-v*`) | `vitruvian-tabs ext update --channel beta`  |
| stable  | the Web Store listing — **arrives with M3**    | —                                   |

The update banner is channel-aware: alpha offers new commits, beta offers new
release versions (never downgrades; prerelease-style tags are ignored by
design). Settings → Preferences → Developer shows the current channel/build
and the exact switch command.

Note: release zips cut before this feature carry a placeholder identity — the
first post-merge release cut is the first beta-installable build.
