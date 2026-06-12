# Tabula dev self-update (M1) — design

**Issue:** [#45](https://github.com/VitruvianSoftware/vitruvian-core/issues/45)
**Status:** approved 2026-06-12
**Scope:** Milestone 1 of three (see Roadmap). Dev-channel self-update for
load-unpacked installs only. No Web Store work in this milestone.

## Problem

Testers running the unpacked dev extension have no update path: every new
build means a manual `bazel build`, unzip, and reload. Issue #45's vision is
release channels (`dev` / `staging` / `production`) with self-update. The hard
platform constraint: **unpacked extensions cannot self-replace their files** —
something outside Chrome must swap the files, and only a reload (or
`chrome.runtime.reload()`) loads them.

## Decision summary

| Decision | Choice |
|---|---|
| MVP scope | Dev channel only (M1); staging/production via Web Store deferred to M3 |
| Update UX | Pull + auto-detect + prompt (extension nudges when a newer build is deployed) |
| "Latest" signal | The deployed dev API's `GET /` `commit` field (reuses #32 provenance; origin already in `host_permissions`) |
| Bundle hosting | Rolling `dev-latest` GitHub **prerelease** with a fixed tag, overwritten per `main` commit |
| Download auth | `tabcli` shells out to the authenticated `gh` CLI |
| Load-unpacked path | `~/.tabula/extension` (overridable via tabcli config) |
| Banner surface | Dashboard (dev-facing), not the popup |
| Bundle flavor | `dist_release` (points at the deployed dev API — what testers exercise) |

## The loop

```
main commit ──► CI: build chrome_zip (GIT_SHA baked in) ──► overwrite rolling
                  "dev-latest" GitHub prerelease (zip + build_info.json)
       │
       └──► dev API auto-redeploys (same commit) ──► GET / reports {commit}

running extension (dev install)               tabcli ext update
  polls dev API GET / on load + ~15min          gh release download dev-latest
  if API.commit != __BUILD_COMMIT__             → unzip to temp dir
    → "Update available" banner                 → atomic swap into the
      [Reload] button                              load-unpacked path
  tester: tabcli ext update, click Reload
    → chrome.runtime.reload() → new files load → commits match → banner clears
```

Detection is a single signal: the extension's baked-in commit vs the deployed
API's reported commit. Precise on-disk "files swapped" detection was
deliberately dropped: `chrome.runtime.getURL()` resources are cached for the
process lifetime, so the extension cannot reliably see the swap before a
reload — a chicken-and-egg. The API poll plus an always-available Reload
button gives the same UX without that fragility. The dev API and the extension
artifact are built from the same `main` commit, so commit-vs-commit is exact
in practice; a brief skew window while CI publishes is acceptable for a dev
channel.

## Components

### 1. Build-time identity (`tabula/extension/webpack.config.js`)

- Inject `GIT_SHA` (env var, same convention as the API deploy) as a
  compile-time constant `__BUILD_COMMIT__` (webpack `DefinePlugin`).
- Emit `build_info.json` into the bundle root: `{commit, builtAt, version}`
  (provenance for humans and tabcli; not used by the runtime checker).
- No `GIT_SHA` (local builds) → `__BUILD_COMMIT__ = "dev"`, which disables the
  update checker.

### 2. CI publish workflow (`.github/workflows/tabula-dev-latest.yaml`, new)

- Trigger: push to `main`, paths `tabula/extension/**` (plus the workflow
  itself).
- Steps: `GIT_SHA=${{ github.sha }} bazel build //tabula/extension:chrome_zip`
  → `gh release upload tabula-extension-dev-latest --clobber` (zip +
  `build_info.json`).
- The rolling prerelease uses the fixed tag `tabula-extension-dev-latest`,
  marked `prerelease: true`. Release-please assigns releases by its own
  `tabula-extension-v*` tag pattern, so the fixed tag does not interfere.
- A failed publish leaves the previous `dev-latest` intact.

### 3. `tabcli ext` command (`tabula/cli/src/commands/ext.ts`, new)

- `tabcli ext update`:
  1. `gh release download tabula-extension-dev-latest` into a temp dir;
  2. unzip + validate (`manifest.json` present);
  3. atomic swap into the load-unpacked path (rename old → install new →
     remove old); the live folder is never left corrupt on failure;
  4. print the new build id and "click Reload in the extension banner (or
     chrome://extensions)".
- `tabcli ext path`: prints the load-unpacked path for the one-time
  `chrome://extensions` → "Load unpacked" setup.
- Path default `~/.tabula/extension`, overridable through the existing tabcli
  config mechanism.

### 4. Extension update checker (new service + banner)

- Gate: only runs when `chrome.management.getSelf().installType ===
  "development"` AND `__BUILD_COMMIT__ !== "dev"`. Web Store installs and
  local ad-hoc builds never poll.
- Poll `GET ${API_URL origin}/` on dashboard load and every ~15 minutes;
  compare `commit` to `__BUILD_COMMIT__`.
- Mismatch → dashboard banner: "New build available (<short-sha>) — run
  `tabcli ext update`, then **Reload**". The Reload button calls
  `chrome.runtime.reload()` and is always functional (it does not depend on
  detecting the on-disk swap).
- The `management` permission addition to the manifest is part of this work.

## Error handling

- **tabcli:** clear messages for: `gh` missing/unauthenticated; no
  `dev-latest` release yet; download/unzip failure (live folder untouched);
  load-unpacked dir not yet set up (hint → `tabcli ext path` + one-time
  chrome://extensions step).
- **Checker:** network/API errors are silent (nudge, not critical); backoff on
  repeated failures; `commit: "unknown"` from the API disables the check (no
  false positives).
- **CI:** `--clobber` is idempotent; re-runs converge.

## Testing

- **Unit (extension):** checker service — mismatch sets banner state; `"dev"`
  build / `"unknown"` API commit / non-development installType disable it;
  poll backoff. Banner component — render + reload invocation.
- **Unit (webpack):** build with `GIT_SHA` set → constant + `build_info.json`
  present; without → `"dev"`.
- **Unit (tabcli):** `ext update` with mocked `gh`/fs — happy path, atomic
  swap, every failure path leaves the existing install intact.
- **E2E (Playwright):** extension built with a fake commit + stubbed API `/`
  response → banner appears; Reload button triggers `chrome.runtime.reload()`.
- CI publish job is validated by its first run on `main` (inspect the
  `dev-latest` release assets).

## Roadmap (out of scope for M1)

- **M2 — channel picker:** Settings UI choosing `dev-latest` vs a pinned sha;
  tabcli gains `--channel`/pin support; per-sha artifacts need retention
  decisions.
- **M3 — staging/production:** Chrome Web Store unlisted listings + automated
  publish via the CWS API (developer account, OAuth publishing creds, review
  latency). A separate install identity from the load-unpacked dev install —
  the Settings picker cannot switch across the load-unpacked/Web Store
  boundary; moving channels there means installing the other listing.

Each milestone gets its own spec → plan → implementation cycle.
