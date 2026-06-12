# Tabula release channels (M2 of #45) — design

**Issue:** [#45](https://github.com/VitruvianSoftware/vitruvian-core/issues/45)
**Status:** approved 2026-06-12
**Builds on:** M1 (`2026-06-12-tabula-dev-self-update-design.md`, shipped in
PR #55): rolling `dev-latest` bundle, `tabcli ext update`, update banner.
**Scope:** Milestone 2 — release channels for the load-unpacked install.
Stable is **reserved in the UX** but mechanically deferred to M3 (Web Store).

## Problem

M1 gives dev installs one stream: every `main` commit. Testers need to choose
their risk level — track main (alpha), track deliberate release cuts (beta),
or eventually the Web Store build (stable). The user's channel model maps onto
the canonical release-train pattern (Chrome Canary→Beta→Stable, VS Code
Insiders→Stable) with one structural fact carried over from the M1 spec:
**stable is not a tabcli-switchable channel** — a Web Store install is a
different distribution identity that Chrome itself auto-updates. tabcli
switches alpha↔beta; stable arrives as the M3 listing.

## Channel model

| Channel | Artifact source                                           | Update signal (one endpoint: dev API `GET /`)  |
| ------- | --------------------------------------------------------- | ---------------------------------------------- |
| alpha   | rolling `tabula-extension-dev-latest` prerelease (M1)     | own `commit` ≠ API `commit` (M1, unchanged)    |
| beta    | newest `tabula-extension-v*` release zip (`*-chrome.zip`) | own `version` < API `version` (semver compare) |
| stable  | — reserved —                                              | arrives with the M3 Web Store listing          |

Why the API `version` works as beta's signal: release-please versions all
tabula components in **lockstep** (`node-workspace` + `linked-versions`), so
the deployed API's `version` field equals the latest cut's version. The
extension's own version comes from `chrome.runtime.getManifest().version`
(always authoritative). No GitHub API polling, no new fetch origins.

## Decision summary

| Decision         | Choice                                                                                                                                                                                                         |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Channel state    | **Self-describing install**: `channel.json` (`{"channel":"alpha"\|"beta"}`) written into the install dir by tabcli on every install, next to `build_info.json`                                                 |
| Channel default  | flag > installed `channel.json` > `alpha` (pre-M2 installs and fresh setups behave like today)                                                                                                                 |
| Stable selection | tabcli `--channel stable` and the Settings option both explain: "arrives with the Web Store listing (M3)" — visible so the 3-channel model is taught from day one                                              |
| Beta artifact    | the `${TAG}-chrome.zip` assets release-please already attaches — promotion of the existing build, never a rebuild                                                                                              |
| Release stamping | `tabula-release.yml` gains the same post-Bazel `build_info.json` stamping as `tabula-dev-latest.yaml` (release zips currently carry the `"dev"` placeholder, which would disable the checker on beta installs) |
| Settings UI      | Display + guide, never execute: picker reveals the exact `tabcli` command with a Copy button (only tabcli can swap files — no desired-state nag loop)                                                          |

## Components

### 1. tabcli (`tabula/cli/src/commands/ext.ts`, `tabula/cli/src/utils/extension.ts`)

- `ext update [--channel <alpha|beta|stable>]`:
  - Resolve channel: explicit flag → else the installed `channel.json` → else
    `alpha`.
  - `stable` → friendly error: not yet available, arrives with the Web Store
    listing (M3); alpha/beta remain usable.
  - `alpha` → download the rolling `dev-latest` zip (M1 path, unchanged).
  - `beta` → resolve the newest `tabula-extension-v*` tag (`gh release list`,
    filter by tag prefix, highest semver), download its `*-chrome.zip` asset.
  - After the atomic swap: write `channel.json` into the installed dir; print
    channel + identity (`✓ Installed beta v0.1.9 (6fc8bf7) → …`).
- `ext path`: unchanged.
- Utils gain `readInstalledChannel(dir)` (absent/corrupt → null → alpha) and
  the beta tag/asset resolution helper.

### 2. CI (`.github/workflows/tabula-release.yml`)

- The `package-extension` job stamps `build_info.json`
  (`{commit: GITHUB_SHA, builtAt, version: <from tag>}`) into the zip before
  `gh release upload` — same `RUNNER_TEMP` + `zip -q` mechanism as
  `tabula-dev-latest.yaml` (in-place entry replacement, hermetic Bazel build
  untouched).

### 3. Extension service (`tabula/extension/src/services/updateCheck.ts`)

- `getOwnChannel()`: reads `channel.json` via `chrome.runtime.getURL`,
  memoized per context exactly like the build-info read (a post-swap re-read
  must not change the running context's channel). Absent/unreadable → `alpha`.
- `checkForUpdate()` becomes channel-aware:
  - alpha: commit comparison, byte-identical to M1;
  - beta: `compareVersions(apiVersion, getManifest().version) > 0` →
    update available. `compareVersions` is a tiny dependency-free
    numeric-segment comparator in the same file.
- Eligibility gates unchanged (dev installType + commit ≠ `"dev"`); the API
  fetch is the same single `GET /` (it already returns both `commit` and
  `version`).
- Result shape gains the channel + the values compared, so the banner can
  phrase itself.

### 4. Banner (`tabula/extension/src/components/UpdateBanner.tsx`)

- alpha: today's copy ("New build deployed (sha7) — run `tabcli ext update`,
  then reload.").
- beta: "New release v\<version\> available — run `tabcli ext update`, then
  reload." (no flag needed — the channel persists in the install).
- Reload/Dismiss semantics unchanged; dismiss keys on the offered value
  (commit or version).

### 5. Settings (`tabula/extension/src/components/AccountSettings.tsx` — Preferences tab)

- New **Developer** section, rendered only when the update checker is
  eligible (dev install of a CI-built bundle) — invisible to Web Store users
  and local ad-hoc builds.
- Shows: current channel, version, sha7.
- Channel picker (alpha / beta / stable): selecting the **current** channel
  shows nothing extra; selecting a **different** switchable channel reveals
  the exact command (`tabcli ext update --channel beta`) with a Copy button;
  selecting **stable** shows the M3 note instead of a command.
- The picker never swaps files — display + guide only.
- Dashboard footer version line becomes `v0.1.9 · alpha · 6fc8bf7` when the
  identity is available (manifest version alone otherwise, as today).

## Error handling

- `--channel stable`: clear, non-fatal explanation (M3 pending).
- Beta resolution finds no `tabula-extension-v*` release: friendly error,
  install untouched.
- Absent/corrupt `channel.json` anywhere → alpha semantics (back-compat with
  M1 installs).
- API `version` missing/unparseable → beta check returns null (silent, same
  contract as M1's `"unknown"` commit guard).
- Atomic-install rollback semantics from M1 are untouched; `channel.json` is
  written only after a successful swap (a failed update never relabels the
  surviving install).

## Testing

- **tabcli (jest):** channel resolution precedence (flag > installed >
  default); beta tag resolution + asset pattern (mocked `gh` output, including
  monorepo tag noise like `tabula-cli-v*`/`devx-v*`); `channel.json` written
  post-install and not on failure; stable error path.
- **Extension (jest):** channel-aware service — alpha path regression
  (unchanged M1 behavior), beta newer/equal/older version cases,
  absent-channel → alpha, memoization; `compareVersions` table
  (incl. `0.10.0 > 0.9.9`, unequal segment counts); banner copy per channel;
  Developer section — eligibility gating, current-channel selection,
  command reveal + Copy, stable note.
- **No Playwright additions** (same M1 rationale: CI-stamped identity can't
  be exercised against the read-only e2e bundle; logic is fully jest-covered).
- **Release stamping** validates on the next real release cut (inspect the
  attached zip's `build_info.json`).

## Out of scope (and why)

- **Arbitrary-sha pinning / bisect** — different job (debugging, not risk
  selection); needs per-sha retention policy; add later if the need shows up.
- **Stable mechanics** — M3: CWS unlisted/public listing, publish pipeline,
  separate install identity.
- **Settings-driven switching** — would require a native-messaging host;
  the copy-command flow covers the actual frequency of channel switches.
