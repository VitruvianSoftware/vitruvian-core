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
| Load-unpacked path | `~/.tabula/extension` (overridable via `--dir`; the cwd-relative tabcli config is project-scoped, wrong fit for a machine-global path) |
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

### 1. Build-time identity (`build_info.json`, CI-injected)

**Constraint discovered at planning:** the webpack bundle is a hermetic Bazel
action — baking a commit SHA into it would break action caching (documented in
`webpack.config.js`; the migration explicitly decided against this). So the
identity is injected *after* the hermetic build:

- The bundle always ships a `build_info.json`; the source placeholder
  (`src/build_info.json`) is `{"commit": "dev"}`, copied as-is by webpack.
- The CI publish workflow overwrites that entry inside the built zip with the
  real `{commit, builtAt, version}` (zip updates same-name entries). The Bazel
  build stays hermetic and cacheable.
- At startup the extension reads its own identity via
  `fetch(chrome.runtime.getURL("build_info.json"))` — no compile-time
  constant. `commit === "dev"` (any non-CI build) disables the update checker.

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
- Path default `~/.tabula/extension`, overridable via `--dir` on both
  subcommands (the existing tabcli config file is cwd-relative/project-scoped
  — the wrong fit for a machine-global install path).

### 4. Extension update checker (new service + banner)

- Gate: only runs when `chrome.management.getSelf().installType ===
  "development"` AND own `build_info.json` commit is present and not `"dev"`.
  Web Store installs and local ad-hoc builds never poll. (`getSelf()` is
  exempt from the `management` permission — no manifest change needed.)
- Poll `GET ${API_URL origin}/` on dashboard load and every ~15 minutes;
  compare its `commit` to the own-build commit.
- Mismatch → dashboard banner: "New build available (<short-sha>) — run
  `tabcli ext update`, then **Reload**". The Reload button calls
  `chrome.runtime.reload()` and is always functional (it does not depend on
  detecting the on-disk swap). A Dismiss hides the banner for that deployed
  commit until a newer one appears.

## Error handling

- **tabcli:** clear messages for: `gh` missing/unauthenticated; no
  `dev-latest` release yet; download/unzip failure (live folder untouched);
  load-unpacked dir not yet set up (hint → `tabcli ext path` + one-time
  chrome://extensions step).
- **Checker:** network/API errors are silent (nudge, not critical); the fixed
  ~15-minute poll interval is the backoff — failed checks simply wait for the
  next tick; `commit: "unknown"` from the API disables the check (no false
  positives).
- **CI:** `--clobber` is idempotent; re-runs converge.

## Testing

- **Unit (extension):** checker service — mismatch reported; `"dev"` build /
  `"unknown"` API commit / non-development installType disable it; fetch
  failures return null. Banner component — render on mismatch, reload
  invocation, dismiss-per-commit.
- **Unit (tabcli):** new jest harness for the CLI (none existed). Atomic
  install utils with real temp dirs — happy path, validation failure, rollback
  on failed swap; every failure path leaves the existing install intact.
  Command-level: friendly error when `gh` is missing.
- **Build check:** `bazel build //tabula/extension:dist` output contains the
  placeholder `build_info.json`.
- **No Playwright spec for the banner** (revised): exercising the CI-injected
  identity would require mutating the read-only e2e runfiles bundle. The
  banner logic is fully jest-covered; the CI publish path is validated by its
  first run on `main` (inspect the `dev-latest` release assets, run
  `tabcli ext update`, observe the banner on the next API deploy).

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
