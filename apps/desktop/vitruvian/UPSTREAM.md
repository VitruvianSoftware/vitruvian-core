# Upstream provenance

This directory is a fork of **vorssaint-utils**, a macOS menu-bar utility app.

| | |
| --- | --- |
| Upstream | <https://github.com/vorssaint/vorssaint-utils> |
| Imported commit | `aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958` (2026-10-02, "chore(agents): update AI price list"). Upstream has since rewritten it as `e80abdb1`, with the same tree. |
| Upstream version at import | 3.4.1-beta.1 (build 96) |
| Imported on | 2026-10-02 |
| License | GPL-3.0-or-later (see [`LICENSE`](LICENSE)) |
| Tracked through | [`upstream/ledger.tsv`](upstream/ledger.tsv): every upstream commit since, and what this fork did with it (see "Tracking and porting upstream") |

## Licensing: this directory is GPL, not Apache

The monorepo is Apache-2.0, but **everything under `apps/desktop/vitruvian/` is
GPL-3.0-or-later**, including the files added here (BUILD, `bazel/`, docs). The
upstream project has many contributors, so it cannot be relicensed.

What that means in practice:

- Keep every upstream `SPDX-License-Identifier` / `Copyright (C) 2026 Vorssaint`
  header exactly as it is. New files in this directory carry
  `GPL-3.0-or-later` with a VitruvianSoftware copyright line.
- Code from this directory must not be copied into Apache-licensed parts of the
  monorepo, and Apache-licensed targets must not link against it. The `BUILD`
  file keeps every target private for that reason.
- Distributing a build, including to testers, obliges us to offer the complete
  corresponding source under the GPL. A Copybara export of this directory to a
  public mirror is the natural way to do that, and the mirror has to be in place
  before the first build goes out.

### Files released under MIT by their copyright holder

The rule above stands for everything upstream wrote. Files that
VitruvianSoftware wrote alone can be released under another licence by
VitruvianSoftware. On 2026-10-08 James approved doing that for Nexus Agent so
the standalone app and this feature build from one copy
(`docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`).

| Date | File, as it was named here | Now at |
|---|---|---|
| 2026-10-08 | `Core/NexusAgent/NexusAgentSupport.swift` | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/` |
| 2026-10-08 | `Core/NexusAgent/NexusAgentQuickPromptLayout.swift` | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/` |
| 2026-10-09 | `Services/NexusAgent/NexusAgentService.swift` (in part: the engine and the host protocol; the window, shortcut and notch docking stay here) | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentEngine.swift` and `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentHost.swift` |
| 2026-10-09 | `Services/NexusAgent/NexusAgentQuickPromptSession.swift` | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentQuickPromptSession.swift` |

Each file was checked before it left: its header named VitruvianSoftware
alone and its history has no upstream author. Not legal advice.

## Trademarks and release blockers

Upstream's [`TRADEMARKS.md`](TRADEMARKS.md) reserves the Vorssaint name, logo,
icon, bundle identity, signing identity and update feed for upstream. The rename
(2026-10-02) replaced them:

- **Name:** Vitruvian everywhere the app shows or reads it. Upstream's
  copyright lines stay, because they are legal notices, not branding (GPL-3.0 §5).
- **Bundle IDs:** `com.vitruviansoftware.vitruvian`, plus its fan helper and Now
  Playing adapter IDs.
- **Icon:** Vitruvian's own app icon and menu bar mark (VitruvianSoftware/vitruvian-core#2643),
  which replaced the placeholders the import used.
- **Update feed and price list:** the planned public mirror
  `VitruvianSoftware/vitruvian`. It does not exist yet, so update checks find
  nothing and prices fall back to the bundled list.
- **Temporary links and feedback:** these were upstream's own servers. They now
  target reserved `.invalid` hosts (RFC 6761) and fail closed, so no capture or
  report leaves the Mac.
- **Donation, Discord and X:** `AppInfo.hasCommunityChannels` is `false`. That
  hides the Support settings page and upstream's post-update support prompt, and
  the remaining links point at the repository.
- **Upstream migrations removed:** the fork must never act on an upstream
  install. `BundleMigration` (it renamed or removed old Vorssaint bundles) is
  deleted, and `build.sh` and `Tools/uninstall.sh` no longer touch legacy
  upstream app paths. The Cleaner also protects upstream's data namespaces.

**Cleared for the first release (2026-10-06):**

- **Artwork:** `Resources/Gifs/highlights-notch.gif` lost the 8 pixel strip at
  its left edge, the only place upstream's planet mark showed (in the menu bar).
  `Resources/Gifs/commandBar.gif`, which showed the mark in the command bar and
  which nothing loads, is deleted.
- **Release pipeline:** `vitruvian-release.yaml` cuts each release, and the
  `vitruvian` delivery unit (`publish.sh`) builds, signs, packages and attaches
  `Vitruvian-X.Y.Z.dmg` to it.
- **Source:** every release is a tag of this public repository, so the source
  of each build is offered beside it, as the GPL requires.

**Still open, not blocking:**

- **A Developer ID signing identity and notary credentials.** Until they are
  set as the `VITRUVIAN_SIGNING_*` and `VITRUVIAN_NOTARY_*` secrets, releases
  are signed ad hoc and macOS asks before the first open.
- **The public mirror `VitruvianSoftware/vitruvian`.** The update feed points
  there, so update checks find nothing until it exists.
- **The temporary-link and feedback backends:** run our own, or remove those
  features and their dead UI.
- **`CHANGELOG.md`:** release-please writes Vitruvian's entries above
  upstream's history, which the app shows under Release notes.

## What the import left out

The import is the upstream tree at the commit above. Every file kept is byte for
byte identical to upstream except `.gitignore` (listed below). Left out:

- `Resources/Brand/`: upstream's logo, app icon and Icon Composer project.
  Upstream reserves this artwork as brand material and does not license it
  under the GPL (its SVG says so in its metadata, and see `TRADEMARKS.md`), so we
  have no licence to copy it. In its place, `Resources/Brand/` holds original
  placeholder artwork with the same file names, drawn by
  `Resources/Brand/make_placeholder_brand.py`. Vitruvian's own artwork has since
  replaced `AppIcon-Default.png` and `logo.png`
  (VitruvianSoftware/vitruvian-core#2643). Do not rerun the script: it would
  overwrite them.
- `.github/`: upstream CI, release and issue workflows. The monorepo pipeline
  replaces them.
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md` and
  `docs/AI-CONTRIBUTIONS.md`: upstream's own contact points and processes.
  `README.md` and `AGENTS.md` here replace them.
- `docs/assets/`, `docs/demo.gif` and `ReleaseAssets/`: marketing screenshots
  and videos (about 45 MB) that are not used by the build or the tests.

## Modifications

GPL-3.0 §5(a) requires a notice that the work was modified, with a date. This log
is that notice. Add an entry for every change to upstream files.

- **2026-10-09**: Tool registry, part 2 (`docs/superpowers/plans/2026-10-08-vitruvian-tool-registry-part-2.md`):
  - `Services/FeatureRuntime.swift`: a change of hub availability also tells `ToolRegistry`, so views that list commands redraw.
  - `main.swift`: registers the sample tool, in a build made with `--define=vitruvian_sample_tool=true` only.
  - `Services/MenuPanel/PanelLayoutStore.swift`: `PanelOrderItem` no longer implies `CaseIterable`; `rawItemOrder` and `setRawItemOrder` read and write a saved order without dropping ids no enum names. Each conforming enum now states `CaseIterable` itself (`Services/QuickTools/QuickTogglesService.swift`, `UI/MenuPanel/DiskSection.swift`, `UI/MenuPanel/MenuPanelView.swift`, `UI/MenuPanel/NetworkSection.swift`, `UI/MenuPanel/PowerSection.swift`, `UI/MenuPanel/SystemSection.swift`).
  - `Core/QuickTools/QuickToolsSupport.swift`: `tileOrder` and `savedTileOrder`, the Quick panel's order with tiles no enum names.
  - `Services/QuickTools/QuickLauncherService.swift`: the grid holds `QuickLauncherTile`s, the app's own tiles plus registry commands no tile runs; a reorder keeps the place of a tile that is not showing.
  - `UI/QuickLauncher/QuickLauncherView.swift`: draws a command tile from the registry and redraws when the registry changes.
  - `Services/Notch/NotchIslandServices.swift`, `Services/Notch/NotchService.swift`, `Services/Notch/NotchEventBindings.swift`: the island counts tiles of both kinds and resizes when the registry changes.
  - `Tests/QuickLauncherActionTests.swift`: `commandTileContracts` covers command tiles in the Quick panel (listing, running, hiding, a reorder that keeps a tile it cannot show) and `savedBuiltinOrderContracts` covers a saved order of the app's own tiles reading back unchanged.
  - `Services/RadialMenu/RadialMenuService.swift`: the wheel's "what can run" rule is a static function that takes its registry.
  - `UI/RadialMenu/RadialMenuView.swift`: `resolvedSymbolName` draws a command slice with its command's own symbol; `RadialToolChoice` is the editor's Tool picker.
  - `UI/Settings/RadialMenuSettings.swift`, `UI/Settings/RadialMenuVisualCanvas.swift`: the editor's Tool picker lists registry commands no tool slice runs, and a command slice is edited as a Tool.
  - `Tests/mutation_checks.py`: two mutations (a built-in command with no tile asking for the panel; a reorder forgetting a tile that is not showing).
- **2026-10-09**: No two global hotkeys share an id:
  - `Services/QuickTools/ScreenCaptureService.swift`: the comment on the capture tools' hotkey ids says where the run starts and what keeps it clear; it claimed the hand-assigned ids ended at 24 after the Quick Prompt had been given 25. No code change in this file.
  - `bazel/source_lints.py`: `hotkey_ids_are_unique` fails when two `QuickToolHotkey` ids, or runs of ids, overlap.
- **2026-10-09**: A run paused for approval on an earlier commit of `main` still counts:
  - `Services/GitHub/GitHubAPIClient.swift`: `fetchSnapshot` kept only the head commit's workflow runs, so a deploy waiting at its gate vanished as soon as the next push moved `main`, and the mouse showed building instead of awaiting approval. It now also keeps any `waiting` run on the default branch, and asks for those by status so the newest ten runs cannot crowd one out. Other runs of earlier commits are still dropped.
  - `Tests/GitHubCoreTests.swift`: `restSnapshotCarriesAWaitingRun` asserted the earlier commit's waiting run was dropped; it now expects it kept, a completed run of that commit dropped, and the approval signal held while it waits.
- **2026-10-09**: Settings says when the typed mouse command path is ignored:
  - `GitHubMouseBinary.swift`: `configuredIsIgnored` is true when a path is configured and does not run.
  - `GitHubPeripheralSink.swift`: `configuredBinaryIsIgnored` asks that for this Mac.
  - `GitHubSettingsView.swift` and `NotchGitHubStrings.swift`: an orange line under the Mouse command hint says the path is ignored, in every language. Before, the "Using" line named another copy with no word about the typed one.
  - `Tests/GitHubCoreTests.swift`: `mouseBinaryResolution` covers the ignored and not-ignored cases and the new line in every language.
