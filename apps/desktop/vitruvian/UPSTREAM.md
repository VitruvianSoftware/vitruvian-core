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
| 2026-10-09 | `UI/NexusAgent/NexusAgentQuickPromptView.swift` (the chat view and its parts; a thin view of the same name stays here) | `apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/`: `NexusAgentChatView.swift`, `NexusAgentMessageBubble.swift`, `NexusAgentCodeBlocks.swift`, `NexusAgentChatControls.swift` and `NexusAgentSessionRow.swift` |

Each file was checked before it left: its header named VitruvianSoftware
alone and its history has no upstream author. Not legal advice.

### Third-party code the app ships

Besides upstream's code and ours, the app bundle holds one piece of software
written by others. It arrives with the shared Nexus Agent chat view, not from
this folder.

| What | Version | Licence | Where in the app | Notice |
|---|---|---|---|---|
| [Mermaid](https://github.com/mermaid-js/mermaid), which draws the diagrams in the Nexus Agent chat | 11.17.2, unmodified | MIT, which the GPL allows combining with | `Contents/Resources/mermaid.min.js`, with its licence text beside it as `mermaid-LICENSE.txt` | [`apps/desktop/nexus-agent/THIRD_PARTY_NOTICES.md`](../nexus-agent/THIRD_PARTY_NOTICES.md): where the file came from, its checksum, and the libraries built into it |

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
- **Update feed and price list:** the public monorepo,
  `VitruvianSoftware/vitruvian-core`. The update check reads its
  `vitruvian-vX.Y.Z` release tags (`Core/Update/VitruvianReleases.swift`) and
  installs the universal disk image; prices come from
  `apps/desktop/vitruvian/Resources/agent-prices.json` on `main`.
- **Signing team:** the updater and the fan helper trust VitruvianSoftware's
  Developer ID team (`FanControlIdentifiers.teamID`), not upstream's.
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

- **2026-10-20**: The shared Nexus Agent chat replaces the raw model text field with a model dropdown menu for the active coding agent (`ChatModelBadge`, `ModularModelButtonView`, and the `agentEnvironmentCard`), with a "Custom Model…" option that opens the inline text field (`session.isEditingModel`) and a "Refresh Models" option. Model choices are remembered per provider in `NexusAgentHost.chosenModels` across provider switches and relaunches. Fixed OpenCode `agentArguments` passing `--`, which caused OpenCode's CLI (`ta.commands.run`) to append arguments after `--` a second time and duplicate every prompt, and joined multi-step OpenCode assistant text blocks with paragraph breaks (`\n\n`). None of it is in upstream files: the shared sources are under `apps/desktop/nexus-agent/macos/Sources/`, `Services/NexusAgent/VitruvianNexusAgentHost.swift` stores `chosenModels`, and `bazel/nexus_agent_shared.sha256` follows. Tests: `Tests/NexusAgentTests.swift`.
- **2026-10-20**: The shared Nexus Agent chat has OpenCode as a fourth built-in provider, after Antigravity, Claude Code and Ollama. A turn runs `opencode run --format json`, with the prompt after `--`; plan mode (or the plan approval mode) runs OpenCode's `plan` agent, YOLO passes `--auto`, and the other modes pass nothing. A set model is passed as `--model` and a resumed session as `--session`. Its JSON lines are read for the session id, the reply, the tools it runs, and the last step's tokens and cost; a step that ends to call tools does not end the turn. Its sessions, their transcripts and archiving are read from and written to OpenCode's own database (`~/.local/share/opencode/opencode.db`), in 2.x's tables (`session_v2`, `session_message`) and 1.x's (`session`, `message`, `part`), through `/usr/bin/sqlite3`; that database is not followed live as a transcript file, as it holds every session and runs to hundreds of megabytes. The worktree switch is shown only for Claude Code and Ollama, the providers with a worktree flag. None of it is in upstream files: the shared sources are `NexusAgentSupport.swift`, `NexusAgentQuickPromptLayout.swift`, `NexusAgentEngine.swift`, `NexusAgentHost.swift` and `NexusAgentChatView.swift` under `apps/desktop/nexus-agent/macos/Sources/`, and the pin (`bazel/nexus_agent_shared.sha256`) follows. Tests: `Tests/NexusAgentTests.swift` (four built-ins; OpenCode's arguments, its JSON lines, its sessions, transcripts and archiving against a database with both layouts).
- **2026-10-19**: A panel whose first page the app refuses (over 256 KB, or a field missing or of the wrong kind) says why where the page would be, instead of a spinner that never ends. In 3.64.0 HomeSpeaker's settings page was refused for `blocks[76].id is not well formed`, and Settings spun with only the extension's log, folded under "Log", saying so. Now it reads "HomeSpeaker sent a page Vitruvian can’t show (blocks[76].id is not well formed). Updating the extension may fix it." A panel that has drawn a page keeps it when a later one is refused, as before, and the log still says why each time.
  - Upstream file: `Tests/mutation_checks.py`: five new mutations: a refused first page left waiting, a refused page replacing the one drawn, an open answer dropped after a refused page, and the panel drawing the log's sentence or the tool's id instead of its name and why.
  - Not upstream's: `Services/Platform/External/ToolPanelHost.swift`: `Shown.notShown` holds the refused page's `ToolPanelProblem` (nil for the other reasons), `draw` sets it when the panel is still waiting, and `name(of:language:)` gives the tool's name from its manifest. `UI/ToolPanels/ToolPanelView.swift`: `ToolPanelNotShown` takes the sentence (`why:`), and the panel passes it for a refused page. `Core/ExternalToolStrings.swift`: `panelRefusedFormat`, `panelTooLargeFormat` and `panelNotWellFormedFormat` in all fifteen languages, put together by `panelRefused(_:_:)`. Tests: `Tests/ToolPanelHostTests.swift` (a malformed and a too-large first page leave the panel not shown with why; a page sent later is drawn; a refused page after a drawn one keeps it), `Tests/ExternalToolStringsTests.swift` (88 texts, and the sentence), `Tests/ExtensionSettingsLayoutTests.swift` (the Extensions sheet and the island drawn with a refused page, light and dark, with no spinner, kept as PNGs), and `.notShown(nil)` where other tests compared `.notShown`.
  - After review, the same day (none of it in upstream files but `Tests/mutation_checks.py`): the open answer's page is still drawn when a page the tool sent unprompted before it was refused (`ToolPanelHost.awaitsAPage`), and a second refused page before any is drawn says its own reason. Tests: `Tests/ToolPanelHostTests.swift` (those two; a page still being read keeps the panel waiting; a viewer and the menu bar panel letting go of a refused page still tell the tool; the bench holds its manifest rather than reaching it through itself), `Tests/ExtensionSettingsLayoutTests.swift` (the refused panel is drawn, in English and German, pixel for pixel as the sentence naming the tool and why, and unlike the log's sentence or the sentence naming the tool by its id).
- **2026-10-19**: Layout fixes James found in 3.63.0, each now checked against what is drawn. On the Dynamic Island page, an extension's live preview stays in its card (it drew past it, over the pane's header and the search field, which read as the pane opening scrolled down); the section links keep their places whichever is lit; Vitruvian's own switches end at the extension's trailing edge; the Extensions sheet's settings region takes the room the window has; and a menu on the island no longer cuts its title to "…".
  - Upstream files: `UI/Settings/NotchContentEditor.swift`: `NotchExtensionPreview` draws the page at its own height, top-aligned, in a card that is exactly the height it is given and clips it (a frame with only a maximum takes its content's height when that is taller, so a page taller than the card drew past it, centred); `NotchSectionScroll` and `NotchExtensionDetail`, the Content tab's scrolling column and an extension's part of it, taken out of `NotchSettings` so a test draws them with a panel host of its own, and `NotchExtensionSettings` hands its host to the page it draws. `UI/Settings/NotchSettings.swift`: the column is those two views; nothing is drawn differently. The pane never scrolled on opening: a test drawing it opens it at 0, and a link or a search in it leaves the pane where it is.
  - Not upstream's: `UI/Settings/ExtensionSettingsPage.swift`: every link is drawn in one weight with one padding and a faint capsule, the lit one in the accent colour, so lighting another changes no width and the rows wrap the same way whichever is lit (the lit link was bold, a few points wider, and moved others onto another row); `SheetColumn`, a leading column whose one marked view takes the height left within a budget, from its least up to all it holds; `SheetRoomReader`, which tells how tall the window a sheet hangs from is; the one page's region can fill (`fills`), and measures its own height for the link that is lit. `UI/Settings/ExternalToolsSection.swift`: `ExternalToolDetailView` is a `SheetColumn`, so the region of a tool with a Settings panel is as tall as the window lets the sheet be, up to the 790 points of `ToolAgreementContent.detailHeight` and down to 250, and takes a panel host (`host:`) for a test; Vitruvian's own switches (`ownSwitch`) and a manifest setting's switch are laid out as the extension's are, title leading and switch trailing. `UI/Settings/ExternalToolAgreementSheet.swift`: `pageListsHeight` is the region's least, with `detailHeight` and `sheetMargin`. `UI/ToolPanels/BlockTreeView.swift`: a choice's title has the row first and wraps, and the menu (`ShrinkingWidth`, down to `BlockTreeContent.menuLeastWidth`) gives way and cuts its own words. Tests: `Tests/ExtensionSettingsLayoutTests.swift` (new: draws the pane, the HomeSpeaker and Remote sheets as real sheets on windows 640 and 1009 points high, the links and an island menu, reads back the pixels and the AppKit controls, and keeps each drawing as a PNG in the test's outputs), `Tests/ExternalToolDetailHeightTests.swift` (the tallest detail with a Settings panel is at most 790 points with a region of at least 250, and the column's rule).
  - Upstream files: `Tests/mutation_checks.py`: five new mutations, one per fix. `Tests/TestGroups.swift`: the new tests run with `tool-runtime`.
  - After review, the same day (none of it in upstream files but `Tests/mutation_checks.py`): the lit link is also outlined (drawn inside its capsule, so no width changes), as its red is close to the others' grey in greyscale and to red-green colour blindness; the page that opens a tool's detail hands it its window's room (`SheetRoomReader(own:)`, `ExternalToolDetailView(room:)`), and the region reads what it holds in the same layout pass (`RegionFill`), so the sheet opens at its height; in a window too short for the region's 250 points, such as with the log open, it gives way down to 160 (`ToolAgreementContent.pageListsTightHeight`, `SheetColumn(give:)`) so the sheet stays in the window, and a search no longer makes the page's whole height a minimum; a choice's row is `ChoiceRow`, whose title takes at most 60% of a row too short for both and wraps onto two lines, so the menu keeps room for its value (`ShrinkingWidth` is gone); `fillsHeight` drops a redundant `listsScroll`. Tests: the sheets hang from a window with a title bar and toolbar, the window is resized while one is open, the log is opened before and while one is shown, the sheet's height is watched from its first appearance, a long choice title is drawn in the island, the menu bar panel and the sheet, and the Remote sheet's pictures are read for the lit link's outline and every other link's pill; the Remote fixture has Remote's own description and version. `Tests/mutation_checks.py`: the fill and choice mutations follow the change, and four new ones (the lit link told apart by colour alone, no pill on an unlit link, the sheet opening before it knows its room, a long title leaving the menu its least width).
- **2026-10-19**: An extension's settings links wrap onto rows so every section's name is in view, the Dynamic Island page's extension pane lets go of its pages when Settings closes, and a field is found by its placeholder.
  - Upstream files: `Core/Settings/FeatureVisibilitySupport.swift`: `SettingsWindowVisibility` has a `package init()`, so a test can make a window of its own. `UI/Settings/NotchContentEditor.swift`: `NotchExtensionPreview` and `NotchExtensionSettings` hold their page open only while they are on screen and Settings can be seen (`NotchPaneViewer`, which watches `SettingsWindowVisibility`): the window is kept when it closes, and the page that was showing is never removed, so neither `onDisappear` on close nor `onAppear` on reopening is sure to run.
  - Not upstream's: `UI/Settings/ExtensionSettingsPage.swift`: the links are `SettingsSheetLinks`, which wrap as chips do (`ChipFlow`, now `package`, in `UI/ToolPanels/BlockTreeView.swift`) instead of scrolling sideways, and can report where each link was placed, for a test. `UI/Settings/ExternalToolAgreementSheet.swift`: `pageListsHeight` 250 points, down from 270, so the tallest detail with two rows of links is 790. `UI/Settings/SettingsSheetSearch.swift`: a field's placeholder is among the words it is found by. Tests: `Tests/ExternalToolDetailHeightTests.swift` (every language; HomeSpeaker's eight links lie within the sheet's 436 points and none is cut short), `Tests/NotchExtensionPaneTests.swift` (Settings closing lets go of each page, and showing again asks once), `Tests/SettingsSheetSearchTests.swift`.
  - Upstream file: `Tests/mutation_checks.py`: the two let-go mutations follow the change, and six new ones: each view keeping its page after Settings closes, links that scroll off the edge, links cut short to fit one row, and a field not found by its placeholder.
- **2026-10-19**: On Settings › Dynamic Island › Content, an extension's pane shows a live preview of its island page and its own settings page, the one the Extensions sheet shows, with a Manage in Extensions button.
  - Upstream files: `UI/Settings/NotchSettings.swift`: an extension's pane draws, in order, its header, the live preview (in the narrow layout; the wide one keeps it in the preview column, now one preview per tool), its settings page in a card when it has one, and Manage in Extensions, which opens its detail on the Extensions page, as the header does now. `UI/Settings/NotchContentEditor.swift`: `NotchExtensionPane`, plain values, the pane's parts in order; `NotchExtensionPreview` draws the tool's real island page (`ToolPanelView` at the island's size) in the black island, as a viewer of the page, only as a picture (no hit testing, `notchSettingsPreview` set, cut off rather than scrolled, one element to VoiceOver), and keeps the tile for a page hidden from the island, a tool with none, a page that could not be shown, and a web page the island shows; `NotchExtensionSettings`, the tool's settings page with its search and links, as a viewer, without Vitruvian's own rows, which the Dynamic Island page has its own switch for. `Core/NotchEditorStrings.swift`: `extensionSummary` says its settings can be changed here or in Extensions, and `manageInExtensions`, in all fifteen languages.
  - Not upstream's: `Services/Platform/External/ToolPanelHost.swift`: `openAsViewer` and `closeAsViewer`, viewer-counted as the menu bar panel's are: a viewer never closes a page the island, the Extensions sheet, a window or the menu bar panel shows, and the page closes, and its tool is told, only when the last of them lets go; `close` is the place's own letting go. `UI/Settings/ExtensionSettingsPage.swift` (new): the one-page view (search field, links, scrolling page) and the extension's page section, taken out of `ExternalToolDetailView` in `UI/Settings/ExternalToolsSection.swift`, which now draws them, so the sheet and the island pane draw the same thing. `UI/Settings/SettingsSheetSearch.swift`: `SettingsSheetIndex(page:isWeb:title:)`, the index of the extension's page alone. `Core/ExternalToolStrings.swift`: `openExtensions`, now unused, is gone (85 texts). Tests: `Tests/ToolPanelHostTests.swift`, `Tests/ExtensionsPageTests.swift`, `Tests/SettingsSheetSearchTests.swift`, `Tests/ExternalToolStringsTests.swift`, `Tests/NotchExtensionPaneTests.swift` (new: the preview and the settings card drawn in a window ask for their page once, keep it while what they draw changes, let go when they go, and a click on the preview never reaches the tool).
  - Upstream files: `Tests/mutation_checks.py`: two quoted lines of `ToolPanelHost` follow the change, and five new mutations: the island closing a page a viewer shows, a viewer letting go of every viewer's page, the preview and the settings card never letting go of their page, and a click on the preview reaching the tool. `Tests/TestGroups.swift`: the new suite runs with `tool-runtime`.
- **2026-10-19**: An extension's settings sheet whose lists scroll is one page with a search field and a row of links to its sections, and two quick chip taps no longer lose the first.
  - Not upstream's: `UI/Settings/SettingsSheetSearch.swift` (new): `SettingsSheetIndex`, plain values: the sheet's sections in order ("Vitruvian" for the island switches and the manifest's settings, then the extension's page by its section headings, or one section titled with the sheet's settings title when it sends none or is a web page, then the commands, then what it uses), every setting with its section and the words it is found by (its title, its help or the caption directly after it, its sub-heading, its section's title, its chips' or its menu's options' titles), `matches` (every typed word, in any case and with any accents, so a section or a sub-heading that matches keeps its settings), `kept` (what the sheet draws for a search) and `current` (the section in view, whose link is lit). `UI/Settings/ExternalToolsSection.swift`: for a sheet whose lists scroll, the search field and the row of links stay above the lists, whose region is taller for a tool with a Settings panel (`ExternalToolDetail.listsHeight`) and stays 200 points for one without; a link scrolls to its section, the link of the section in view is lit, a search keeps only what it found under each section's heading, says "No settings match" when it finds nothing (also to VoiceOver), and says it cannot look inside a web page; Escape clears a search before it closes the sheet; `ExternalToolDetailView` is `package`, with an initializer, so a test can draw it; `ExternalToolDetail.Focus` has `search` and `section`. A sheet short enough to show everything is as before. `UI/Settings/ExternalToolAgreementSheet.swift`: `pageListsHeight`, 270 points: the tallest sheet with a Settings panel is 788, and without one 718. `UI/ToolPanels/ToolPanelView.swift`, `UI/ToolPanels/BlockTreeView.swift`: a page can be drawn with only some of its items (`BlockTreeContent.keeping`), and its section headings marked for the sheet's links; `BlockTreeContent.ChipPicks`: until the tool sends its next page, a chip tap starts from the last pick, not the page as last drawn, and the chips are drawn as picked; the next page, the same as the last or not, ends the pick. `Services/Platform/External/ToolPanelHost.swift`: `revisions`, how many pages each panel has been sent, which `ToolPanelView` hands to `BlockTreeView`. `Core/ExternalToolStrings.swift`: `vitruvianSection`, `searchSettings`, `noSettingsMatchFormat`, `pageNotSearchable`, in all fifteen languages (86 texts). Tests: `Tests/SettingsSheetSearchTests.swift` (new), `Tests/ExternalToolDetailHeightTests.swift` (new: the tallest sheets, with a Settings panel and without, drawn and measured under 800 points), `Tests/ExternalToolSettingsTests.swift`, `Tests/ExternalToolStringsTests.swift`, `Tests/ToolPanelScreensTests.swift`, `Tests/ToolPanelHostTests.swift`, `Tests/TestGroups.swift` (upstream file: both new suites run with `tool-runtime`).
  - Upstream file: `Tests/mutation_checks.py`: new mutations: a second quick chip tap that undoes the first, a search that reads no help, and a short last section whose link is never lit.
- **2026-10-19**: The app draws chips, help and section headings, and its hello names `ui.chips` and `ui.sections`.
  - Not upstream's: `UI/ToolPanels/BlockTreeView.swift`: a `chips` block is drawn as chips, not its fallback (`BlockTreeContent.Kind.chips`, `BlockTreeContent.Chip`): a row of small capsules that wraps within the page's width, filled with the accent colour while on and outlined while off, each a switch to VoiceOver named by its title; a chip that cannot be turned is dimmed, gives its reason as a tooltip and to VoiceOver, and does nothing when tapped. Turning one sends `change` with the values of every chip then on, in the options' order (`BlockTreeContent.turnChip`); the rows are laid out by `BlockTreeContent.chipFrames`. A switch, a field, a menu and chips draw their `help` as a caption of two lines at most under the control. A heading with `section` is drawn a step larger with more room above it, and `BlockTreeContent.sections` lists each one with its item's place in the page, for the settings sheet's jump row. `Services/Platform/External/ExternalToolStore.swift`: `ui.chips` and `ui.sections` move from `notDrawnYet`, now empty, into `features`. `Tests/ToolPanelScreensTests.swift`, `Tests/BlockTreeLayoutTests.swift` (chips drawn at the island's width wrap and none runs past it), `Tests/ExternalToolStoreTests.swift`: the tests.
  - Upstream file: `Tests/mutation_checks.py`: the quoted `features` and `notDrawnYet` lines follow the move, and the hello's sentence names chips, sections and help; new mutations: a name the app claims also listed as not drawn, a name of the protocol the app forgets, and a chip that cannot be turned that is turned.
- **2026-10-18**: The tool protocol gains chips, sections and help, with no new version. The app does not draw them yet and does not name the two new features, so a tool that asks first sends it what it sends today.
  - The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, 1693d0612ecb): the fourteenth kind of block, `chips` (`ChipsBlock`, `UIChipOption`), whose event `change` carries the values of every option then on; `section` on a heading (`HeadingBlock.section`); `help` on a switch, a field, a choice and chips; and the features `ui.chips` and `ui.sections` (`ProtocolFeature.chips`, `.sections`).
  - Upstream file: `Tests/mutation_checks.py` ("a choice with no id is read" quotes the list of kinds that need an id, which now ends with `chips`; a new mutation, "the app forgets a name of the protocol it does not draw yet").
  - Not upstream's: `UI/ToolPanels/BlockTreeView.swift` draws a `chips` block as its fallback, as it draws a kind it does not know, until the app draws chips. `Services/Platform/External/ExternalToolStore.swift`: `notDrawnYet` lists `ui.chips` and `ui.sections`, names the app knows and does not claim at hello; the change that draws them moves them into `features`. `Tests/ExternalToolStoreTests.swift`: every name of the protocol is in exactly one of the two lists, and the hello still names only `features`.

- **2026-10-18**: Text typed in an extension's field reaches the extension before a click that uses it. A field sent its text only when it was left, and on macOS clicking a button, switch or menu does not take the focus from a field, so pasting a Beeper or Slack token into HomeSpeaker's "Access token" and clicking "Save Token" sent the click alone: HomeSpeaker had no token and said "Paste the Beeper token first". A secret field now sends `change` as it is typed in (the tool never draws its value back and only holds it until its own button saves it); any other field's unsent text is held in `PendingFields` and sent as `change` before the event of any button, row, list row, switch or menu on the page. Return and leaving a field still send as before, and nothing is sent twice.
  - Not upstream's: `UI/ToolPanels/BlockTreeView.swift` (`PendingFields`; `BlockTreeView` sends every control's event but a field's through it; `BlockField` holds or sends its text as it changes), `Tests/BlockFieldPendingTests.swift` (new: the queue on its own, and a drawn page where a pasted secret is sent at once and a typed field is sent before a clicked button), `Tests/TestGroups.swift` (runs it with the tool-runtime suite).

- **2026-10-16**: The island's Tools grid is for the app's own tools and for tools from outside that have no island page of their own, as James approved that day. An outside tool whose manifest has an island panel (protocol 2, `contributes.panels` with `"placement": "island"`) no longer gets a tile there, even when one of its commands asks for `quickPanel`; its commands stay on the command bar, the wheel and the Shortcuts page. A tool with only a Settings or window panel, or none, keeps its tile. The app's own tiles are unchanged. The three extensions in this repository that asked for a tile (GitHub's "Open my pull requests", HomeSpeaker's "Speak the clipboard", the Android remote's "Pair with QR" and notifications switch) no longer ask, and GitHub and HomeSpeaker draw the action as a button on their island page instead.
  - Upstream files: `AGENTS.md` (the rule, beside the two sources a surface lists), `Tests/mutation_checks.py` (two mutations: the grid ignoring an island page, and a tool's island panel never noted).
  - Not upstream's: `Services/Platform/ToolRegistry.swift` (`setHasIslandPage(for:)`, `hasIslandPage(_:)`, forgotten on `unregister`; never set for one of the app's own tools), `Services/Platform/ToolRegistry+Surfaces.swift` (`extraCommands(on: .quickPanel)` leaves out a tool with an island page), `Services/Platform/External/ToolRegistry+ExternalTools.swift` (registering an outside tool notes its island panel), `Tests/ExternalToolHostTests.swift` (`toolsGrid`).
  - Known limits: the rule reads the manifest, not the "Show in the Dynamic Island" switch, so a person who hides a tool's island page reaches its actions from the command bar, not the grid. A tile a person had already placed in the grid keeps its place in the saved order, unseen, as any tile whose command is away does. Nobody has seen the grid in the app with this change.

- **2026-10-16**: An expanded card in the menu bar panel's Extensions tab showed nothing. The card's hooks that open its page as it appears and let go as it goes sat on a SwiftUI `Group`, which hands its modifiers to each view it draws; before the page was asked for, the card drew `ToolPanelView`, which draws nothing for a page the host does not have, so the hooks never ran and the page was never asked for. They also ran again on every change of what the card drew, closing and reopening the page as it went from drawn to "could not be shown" or to and from the island. The expanded body is now `MenuPanelExtensionPage`, whose hooks sit on one stack that always holds a view: a small spinner before the card asks, "could not be shown" once it has asked and there is no page, the page, or the island's line.
  - Upstream file: `Tests/mutation_checks.py` (a mutation that puts back the `Group` and the empty view before asking).
  - Not upstream's: `UI/MenuPanel/ExtensionsSection.swift` (`MenuPanelExtensionCard` is `package`, takes the host, and draws `MenuPanelExtensionPage` while expanded), `UI/ToolPanels/ToolPanelView.swift` (takes the host, `ToolPanelHost.shared` unless given), `Tests/MenuPanelExtensionsTests.swift` (`aDrawnCardOpensAndLetsGoOfItsPage` draws the real card in a window: expanding asks for the page, collapsing and the card going let go and the tool is told, and a page that ends with its tool is not asked for again by itself).
- **2026-10-16**: The menu bar panel's Extensions tab gains collapsible extension cards and an inline edit mode like the Controls tab, replacing the separate "Extensions tab" section in Settings › Menu bar, as James asked that day. Each extension card's header collapses and expands its panel body (`DefaultsKey.panelCollapsedExtensions`), opening the panel in `ToolPanelHost` only while expanded; the tab header's customize button (`supportsEditing: true`) enters inline edit mode to drag-reorder extensions (`DefaultsKey.panelExtensionOrder`), toggle visibility (`DefaultsKey.panelHiddenExtensions`), or reset order, visibility and collapsed state together; and when all extensions are hidden in the tab, "Choose Extensions…" opens inline edit mode directly in the tab.
  - Upstream files: `Core/DefaultsKey.swift` (`panelExtensionOrder` and `panelCollapsedExtensions`), `Core/SettingsBackupSupport.swift` (both keys travel in a backup), `UI/MenuPanel/PanelLayout.swift` (`PanelSection` accepts an optional `isEditing` binding so empty-state actions inside a section can enter edit mode), `UI/Settings/GeneralToolSettings.swift` (removed `MenuPanelExtensionsSettings()`, keeping the `Extensions` row in `PanelLayoutEditor`), `AGENTS.md`, `Tests/mutation_checks.py` (added `"the Extensions tab ignores its saved order"` and updated `"the Extensions tab ignores an extension's switch"`).
  - Not upstream's: `Core/MenuPanelExtensionsSupport.swift` (`ordered(_:in:)`, `setOrder(_:in:)`, `collapsed(in:)`, `isCollapsed(_:in:)`, `setCollapsed(_:for:in:)`, `reset(in:)`), `Services/MenuPanel/MenuPanelExtensions.swift` (`ordered(store:defaults:language:)`, removed `tabSettings`/`openTabSettings()`), `UI/MenuPanel/ExtensionsSection.swift` (collapsible `MenuPanelExtensionCard` header and inline `editorList` using `PanelReorderableItem`, `PanelDragHandle`, `PanelHiddenBadge` and `PanelInlineHideButton`), `Core/MenuPanelExtensionsStrings.swift` (removed unused `settingsTitle` and `settingsCaption`), deleted `UI/Settings/MenuPanelExtensionsSettings.swift`, `Tests/MenuPanelExtensionsTests.swift`.
- **2026-10-16**: A tool can open its own settings from one of its panels, approved by James that day (design: HomeSpeaker's island gets a "More settings…" button). Protocol 2 gains it with no new version and no new field: `open` in the answer to `ui/event` may now name the tool's own settings panel, and Vitruvian 3.57 and earlier log that answer as "not a panel of this place" and open nothing, as they always did.
  - The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, ed928b237f06): the feature `ui.open.settings` (`ProtocolFeature.openSettings`). `Services/Platform/External/ExternalToolStore.swift` (written by VitruvianSoftware): the hello names it (`ExternalToolStore.features`).
  - `Services/Platform/External/ToolPanelHost.swift` (written by VitruvianSoftware): `openAsked` looks the id up in the asking tool's own manifest, so a tool can name only its own panels; its settings panel calls the new `Parts.openSettings`, which closes the island as its own Settings buttons do (`NotchService.perform`), sends the router to the Extensions page with the tool named, and brings Settings to the front (`openSettingsWindow`). An id the manifest does not declare, or an island panel, is logged and opens nothing, as before.
  - `Core/Settings/FeatureVisibilitySupport.swift` (upstream file): `SettingsRouter.extensionTool`, a one-shot hint naming the tool, set by `request(extension:)` and dropped by any other request or page, as `notchCompanion` is. `Core/Settings/ExtensionsPageSupport.swift` (written by VitruvianSoftware): `askedDetail(_:listed:showing:busy:)` says what the page does with it. `UI/Settings/ExternalToolsSection.swift` (written by VitruvianSoftware): the Extensions page shows the named tool's detail. The detail is a sheet, so while another sheet or alert is up (the agreement sheet, another tool's detail, a refusal, or what a removal kept) the request waits and the detail opens when the page is free, the rule a catalog fetch's result already follows; nothing the person has open is taken away. The tool's own detail already up, or a tool no longer added, drops the request. `App/AppDelegate.swift` (upstream file): closing the Settings window calls `SettingsRouter.settingsWindowClosed()`, which drops a request still waiting, so reopening Settings later never shows a detail nobody asked for then.
  - `Tests/ToolPanelHostTests.swift`, `Tests/ExtensionsPageTests.swift`, `Tests/ExternalToolStoreTests.swift`. `Tests/mutation_checks.py` (upstream file): the hello's two mutations follow its new list and message; nine mutations, a hello that forgets the new name, a settings panel opened as a window, any panel not a window opening Settings, a hint that outlives another request, a change of page or the Settings window, a request that takes another sheet away, and each of the two rules that drop a request (a tool no longer added, its detail already up).
- **2026-10-16**: The Extensions page links to the Vitruvian SDK, as James asked that day, so a person who wants to build an extension reaches it in one click. The last line of "The Vitruvian catalog" card reads "Build your own extension with the Vitruvian SDK.", in the page's grey with "Vitruvian SDK" in the link colour; the whole line is one link, the control the About page uses for GitHub, and opens https://github.com/VitruvianSoftware/vitruvian-sdk in the default browser (vitruviansoftware.dev has no SDK page). It sits below the card's switch over the list, so it shows while the list loads, and when it is empty, cannot be fetched, is refused, lists tools or has everything installed. "Add from Folder…" is unchanged.
  - `Core/AppInfo.swift` (upstream file): `sdkURL`, beside the repository and website addresses.
  - `AGENTS.md` (upstream file): one sentence on the line and where it sits.
  - `Tests/mutation_checks.py` (upstream file): one new mutation, the link pointed at the website's `/sdk/`, which does not exist.
  - Not upstream's: `Core/ExternalToolStrings.swift` (`sdkLine`, in all fifteen languages, each naming "Vitruvian SDK" once, untranslated; the fourteen besides English written with the English and not yet read by a speaker; 82 texts), `UI/Settings/ExternalToolCatalogueSheet.swift` (`CatalogueSheetContent.SDKLine`, which splits the sentence around the name, and `CatalogueSDKLineView`), `UI/Settings/ExternalToolsSection.swift` (the line under the catalog), `Tests/ExtensionsPageTests.swift` (`sdkLink`: the words, the address, every language, and the six states of the card), `Tests/ExternalToolStringsTests.swift` (82 texts).
  - Known limits: nobody has seen the line drawn; the unit tests check the content the card is handed, not the drawing.
- **2026-10-16**: An extension added from a folder can update from the catalog (VitruvianSoftware/vitruvian-core#3396). When the catalog lists a newer version under the same id, its row on the Extensions page says "Update available" and offers "Update from the catalog", with the same spinner and waiting as the catalog's Update. The download is checked as any install from the catalog is (size, checksum, zip, manifest id and version), then the usual agreement sheet adds one sentence: the tool was added from its folder and comes from the Vitruvian catalog from now on. Agreeing replaces the app's copy, keeps what the tool saved, and records the tool as from the catalog, so its next update is the usual Update. The same version, an older one, and a tool that is held back are never offered. The sidebar's count of updates includes these. Before, such a tool showed neither Update nor Install, and the only way onto the catalog was Remove (keeping what it saved), then Install.
  - `AGENTS.md`, `README.md` (upstream files): a tool added from a folder is matched by its id, compared at the version agreed to, and moved onto the catalog by its update; the sidebar counts it.
  - `Tests/mutation_checks.py` (upstream file): the mutation that matched a folder tool by its id is gone, since that is now the rule; six new ones: a folder tool never offered the newer version, offered the same or an older one, offered while held back, left recorded as from a folder after the update, the sheet silent about the move, and the row's button saying plain Update. The older-version mutation quotes the reworded line.
  - Not upstream's: `Services/Platform/External/Catalogue/CatalogueWatch.swift` (`update(for:)` and `comparedVersion(of:)`), `Services/Platform/External/ToolOffer.swift` (`movesFromFolder`), `Services/Platform/External/ExternalToolStore.swift` (the offer names the folder), `Services/Platform/External/ToolRecords.swift` (a comment), `Core/ExternalToolStrings.swift` (`updateFromCatalog`, `updateMovesToCatalogFormat`, in all fifteen languages; the fourteen besides English written with the English and not yet read by a speaker; 80 texts), `UI/Settings/ExternalToolsSection.swift` (`ExternalToolRow.updateButton` and `updateWords`), `UI/Settings/ExternalToolAgreementSheet.swift` (`ToolAgreementContent.movesToCatalogue`), `UI/Settings/ExternalToolCatalogueSheet.swift`; tests in `Tests/CatalogueWatchTests.swift`, `Tests/CatalogueInstallerTests.swift`, `Tests/CatalogueScreensTests.swift`, `Tests/ExtensionsPageTests.swift`, `Tests/ExternalToolStringsTests.swift`.
  - Review fix, same day: on any update from the catalog the sheet said "This folder has version 1.3.0", meaning the app's own download folder, which the person never sees; beside the new sentence it read as if their folder held the new version. It now says "The catalog has version 1.3.0." (`updateVersionsCatalogFormat`, fifteen languages, 81 texts); an update from a folder is worded as before. `Tests/mutation_checks.py` (upstream file): two more mutations: the catalog's version called a folder's, and every catalog update said to move a tool from a folder.
  - Known limits: the list is still fetched on the app's own only while a tool from the catalog is installed, so a Mac with only folder tools learns of a newer version when the Extensions page is opened. Nobody has seen the sheet with the new sentence.

- **2026-10-15**: The menu bar panel has an Extensions tab (VitruvianSoftware/vitruvian-core#3360): each extension's island page, under a small header with its symbol and name, drawn by the same view the island uses (`ToolPanelView`), so a button, switch or field there reaches the tool as it does from the island. The tab is on by default only while an extension has an island page, so a Mac with none gets no empty tab; with the tab on and no such extension it says so in one line and offers Settings' extension management. Each extension has a switch for the tab in Settings › Menu bar, on until turned off. No SDK or protocol change: it is the existing island placement shown a second time.
  - Upstream files: `Services/MenuPanel/PanelLayoutStore.swift`: `PanelSectionID.extensions`, a new saved name at the end of the list (every earlier name unchanged, so a saved order gains the tab at its end); no hub feature gates it, so it is always available; `shownByDefault` is main-actor and follows whether an extension has an island page, with `shownByDefault(anyIslandPanel:)` for the rule itself; `PanelLayout.order(in:)`, `isShown(_:in:shownByDefault:)` and `isCollapsed(_:in:)` read given preferences, and `isShown` and `isVisibleInPanel` are main-actor. `Core/DefaultsKey.swift`: `panelShowExtensions` (never registered: absent means follow the default) and `panelHiddenExtensions` (the tool ids switched off for the tab). `Core/SettingsBackupSupport.swift`: both keys travel in a backup. `UI/MenuPanel/MenuPanelView.swift`: the tab, built only while the popover is up or the panel is inside the island; the panel redraws its tabs when an extension is added or goes. `UI/Settings/PanelLayoutEditor.swift`: the tab's line, and its default followed as extensions come and go. `UI/Settings/GeneralToolSettings.swift`: the extensions' switches under the panel's tabs. `AGENTS.md`: how the tab shares a page with the island. `Tests/mutation_checks.py`: four mutations: the island letting go closing the tab's page, the island refusing a page the tab has open, the tab on by default with no extension, and the tab ignoring an extension's switch.
  - Not upstream's: `Services/Platform/External/ToolPanelHost.swift`: `openInMenuPanel` and `closeInMenuPanel`, counted per view, and `inMenuPanel`; `close` leaves open a page the tab still shows; `open` in the island of a page the tab has open makes it the island's page and asks nothing. New: `Core/MenuPanelExtensionsSupport.swift`, `Core/MenuPanelExtensionsStrings.swift` (eight texts, fifteen languages, the fourteen besides English written with the English and not yet read by a speaker), `Services/MenuPanel/MenuPanelExtensions.swift` (what the tab lists, and the one place that says where Settings manages extensions: since the Extensions page landed, that page, `ExtensionsPageSupport.destination`), `UI/MenuPanel/ExtensionsSection.swift`, `UI/Settings/MenuPanelExtensionsSettings.swift`, `Tests/MenuPanelExtensionsTests.swift` (suite `tool-runtime`, `Tests/TestGroups.swift`).
  - Review fixes, same day: a web page is one web view, which one place can hold, so while the island shows a web page the tab draws "Showing in the Dynamic Island" in its place and takes the page back when the island lets go (`ToolPanelHost.defersToIsland`, not upstream's; the text in fifteen languages); before, the place opened second took the web view and the other stayed blank. An extension updated, or switched off and on, gets a new card that asks for its page again (`ExternalToolStore.activations`, not upstream's, in `MenuPanelExtensions.Entry.id`). Upstream file `Services/MenuPanel/PanelLayoutStore.swift`: whether any extension has an island page is asked only for the Extensions tab, and only when the person has not chosen (`isShown` takes the default as an autoclosure); the store works it out once per change (`ExternalToolStore.hasIslandPanels`, not upstream's). `Tests/mutation_checks.py` (upstream file): a fifth mutation, the tab taking a web page from the island. After the rebase onto the Extensions page: the tab's empty state leads to that page instead of Features (`MenuPanelExtensions.extensionSettings`), and a sixth mutation sends it back to Features. Second review, same day: each card of the tab holds the page under a token of its own and lets go of that token alone (`ToolPanelHost.openInMenuPanel(_:viewer:)` and `closeInMenuPanel(_:viewer:)`), so an updated extension's old card going after its new card appeared no longer closes the new card's page; the line shown in place of a web page the island holds gains "Open in the Dynamic Island" (`MenuPanelExtensions.showInIsland`, fifteen languages); a seventh mutation lets one card go of every card's view.
  - Known limits: nobody has opened the app with the tab in it; two views of the tab at once (the popover and the panel inside the island) showing one web page still share its one web view.

- **2026-10-15**: Review fixes to the Extensions page. A row's Update button, and a catalog row's Install, now draw a spinner while their tool downloads, and every other Install or Update is disabled until it is done; before, nothing changed on screen and a second press was silently ignored. An install or update no longer disappears when the person leaves the page mid-download: it runs in `CatalogueInstalls` (`Services/Platform/External/Catalogue/CatalogueInstalls.swift`, new, VitruvianSoftware's), whose result waits until the page is next shown. VoiceOver reads the Features page's line once, and hears whose Update or Install a button is ("Update, Deploys").
  - `Tests/mutation_checks.py` (upstream file): four mutations: no spinner for the row being fetched, every button enabled while one downloads, a second install started while one downloads, and a finished download dropped while the page is closed.
  - `AGENTS.md` (upstream file): where an install from the page lives and how its buttons wait.
  - Not upstream's: `UI/Settings/ExternalToolsSection.swift` (`ExtensionsPageContent.installButton` and `spoken`, `ExternalToolRow.updateSpoken`, the page and row drawing from `CatalogueInstalls`), `UI/Settings/ExternalToolCatalogueSheet.swift` (`CatalogueRow.actionSpoken`, `CatalogueRowView` takes the button's state), `Tests/ExtensionsPageTests.swift`.

- **2026-10-15**: Extensions get their own page in Settings, approved by James that day. Until now the tools that run as their own programs were the "Extensions & Tools" card at the end of the long Features page, with the catalog behind a "Browse Tools…" sheet. The new Extensions page sits in Essentials right after Features. Under its title and an "Add from Folder…" button (the same folder picker and agreement sheet as "Add a Tool…"), it lists what is installed, with the same rows, and then the catalog's tools that are not installed, each with Install, which goes through the same agreement sheet. A row whose catalog lists a newer version now has an Update button beside "Update available", and the sidebar's row counts those updates. The Features page keeps one line in place of the card: "3 extensions installed · Manage", "1 extension installed · Manage" or "No extensions yet · Browse", which opens the page. The Features page's two footnotes stay there: they are about uninstalling built-in features, not about extensions. Opening the page fetches the catalog's list, as opening the sheet did.
  - `Core/Settings/FeatureVisibilitySupport.swift` (upstream file): `SettingsPage.extensions`, after `features`, which no hub feature hides. No `SettingsSectionAnchor` was added, renamed or removed: the card never had one.
  - `Services/Settings/SettingsDirectory.swift` (upstream file): the page in Essentials, titled from `ExternalToolStrings.pageTitle` with the extension symbol, and searched by the old card's name, the catalog's heading and the Add button (`ExtensionsPageSupport.searchWords`), so "extensions", "tools" and "catalog" find it in English; the command bar lists it from the same items. The sidebar keeps it beside Features, before the Dynamic Island.
  - `UI/Settings/SettingsView.swift` (upstream file): the page's arm of `detail`, and a `.badge` on its sidebar row with the count of updates; the view observes `CatalogueWatch.shared` and `ToolRegistry.shared` for it.
  - `UI/Settings/FeatureHubSettings.swift` (upstream file): `ExtensionsSummaryLine` in place of `ExternalToolsSection`.
  - `UI/Settings/NotchSettings.swift` (upstream file): an extension's island page in the Dynamic Island's settings leads to the Extensions page, with "Open Extensions", instead of to Features. `Core/NotchEditorStrings.swift` (upstream file): `extensionSummary` says its own settings are in Extensions, in all fifteen languages.
  - `Tests/mutation_checks.py` (upstream file): five mutations: the catalog listing installed tools again, "1 extensions installed", Extensions after the Dynamic Island, every tool counted as an update, and the page found by its name alone.
  - `AGENTS.md`, `README.md`, `docs/PRIVACY.md` (upstream files): where a tool is added, what the page lists, and that opening the page, not "Browse Tools…", fetches the catalog's list.
  - Not upstream's: `Core/Settings/ExtensionsPageSupport.swift` (new): the page's destination, the Features line and its search words. `Core/ExternalToolStrings.swift`: nine new texts in all fifteen languages (`pageTitle`, `installedTitle`, `catalogAllInstalled`, `summaryNone`, `summaryOne`, `summaryCountFormat`, `summaryManage`, `summaryBrowse`, `openExtensions`), `addButton` reads "Add from Folder…", and `browseButton` is gone (78 texts). `UI/Settings/ExternalToolsSection.swift`: `ExtensionsSettings`, the page, in place of `ExternalToolsSection`, with `ExtensionsPageContent` and `ExtensionsSummaryLine`; the row's Update button. `UI/Settings/ExternalToolCatalogueSheet.swift`: the sheet's view is now `CatalogueRowView`, one row of the page's catalog; `CatalogueSheetContent.notInstalled` leaves out what is installed and says `catalogAllInstalled` when nothing is left; it no longer carries a Close word. `Tools/ByHand.swift`, `Tools/ByHandRules.swift`: `tools`, `add-tool` and `remove-tool` open the Extensions page and read it from its title (`ByHandRules.pageStart`), and press "Add from Folder…". `Tests/ExtensionsPageTests.swift` (new, in the `tool-runtime` suite), `Tests/ExternalToolStringsTests.swift`, `Tests/CatalogueScreensTests.swift`, `Tests/ByHandRulesTests.swift`, `Tests/TestGroups.swift`. Outside this folder: `catalog/README.md`.

- **2026-10-15**: Opening a stack on the island's Notifications list no longer slides its first message over the stack's summary. In 3.53.0 the closed stack's one-line summary faded over the whole 0.22 s opening while the row shrank around it, so for a moment two lines of text overlapped.
  - `UI/Notch/NotchNotificationsView.swift` (upstream file): the summary and time leave in 0.06 s (`NotchNotificationListMotion.summaryFade`, instantly under Reduce Motion), and the stack's row clips what it holds while it shrinks.
  - `Tests/NotchNotificationListTests.swift` (written by VitruvianSoftware): the summary must be gone in at most a third of the opening. `Tests/mutation_checks.py` (upstream file): a mutation that slows the summary to the whole opening; the Reduce Motion mutation quotes the reworded line.
- **2026-10-15**: The Dynamic Island's Notifications page can show a list instead of cards, with each app's notifications stacked into one row. Settings > Dynamic Island > Content > Notifications gains a Layout choice, Cards or List; Cards stays the default, so a Mac that never chooses sees the page it had. List draws one compact row per notification (the app's icon and name, the time, the title and one line of the message), newest first, scrolling down when there are more than fit: about seven rows where four cards fit. Under it, "Group by app" (on by default, shown only with List, since the cards never group) stacks an app's notifications into one row with a count, ordered by each app's newest notification, as Notification Center does; clicking the row opens the stack in place and clicking again closes it. An app with one notification, and a banner that names no app, stay plain rows. Open and Dismiss stay on every row, Clear All stays in the header, and a stack's own Dismiss clears that app's notifications. Opening and closing a stack animates briefly, and not at all with Reduce Motion on. VoiceOver reads a stack as "Slack, 3 notifications, newest: …".
  - `Core/Notch/NotchNotificationListSupport.swift` (new, VitruvianSoftware's): the layout choice, the grouping, order and open stacks, the VoiceOver label and the list's measurements.
  - `Core/DefaultsKey.swift`, `Core/Defaults.swift` (upstream files): the keys `notchNotificationsLayout` and `notchNotificationsGrouped`, registered from `Preferences`, so they are part of settings backup.
  - `Core/Notch/NotchNotificationSupport.swift` (upstream file): `NotchNotificationInbox.dismiss(_:)` takes a set of ids, for a stack. A notification that arrived after the list was drawn is not in it and stays.
  - `Services/Notch/NotchNotificationService.swift` (upstream file): `dismiss(_:)` for a stack, which waits while one of its notifications is being opened, as Clear All does.
  - `UI/Notch/NotchNotificationsView.swift` (upstream file): the page hands its notifications to `NotchNotificationPage`, which draws the cards as before or the list (`NotchNotificationList` and its rows). `NotchNotificationAppIcon` takes icons from the `notchNotificationIcons` environment value first, for a test that draws the page.
  - `UI/Settings/NotchSettings.swift`, `UI/Settings/NotchSettingsRows.swift` (upstream files): the Layout row (`NotchNotificationLayoutRow`) and the grouping switch, indented under it while List is chosen.
  - `Core/NotchNotificationStrings.swift` (upstream file): nine new strings in all 15 languages.
  - `Tests/NotchNotificationListTests.swift` (new, in the `notch` suite): grouping, order and counts, a group of one, dismissing a stack, opening and closing one, the setting's default, which layout each choice draws, and four pictures of the page kept with the test's outputs. `Tests/NotchSettingsChoiceTests.swift` (upstream file): the Layout row fits the narrowest options column in every language. `Tests/mutation_checks.py` (upstream file): nine mutations, among them groups ordered by the inbox, an app with one notification drawn as a stack, and the default flipped to List.

- **2026-10-15**: The update check no longer uses api.github.com. Without a token that API allows 60 requests an hour per network address, shared by everything on the network, and something on this network spent them: with 3.52.1 installed, Check now said "Couldn't check: GitHub is limiting requests" while `https://api.github.com/rate_limit` showed 0 of 60 left.
  - `Services/Update/UpdateService.swift` (upstream file): the check runs `VitruvianReleases.findNewest` (VitruvianSoftware's): git's own tag listing (`git-upload-pack`, protocol 2 `ls-refs`, the request `git ls-remote` makes) for the `vitruvian-v` tags, then HEAD on the newest release's universal disk image link for whether it is uploaded and its size. Only when that release will be offered does it read the notes, from the app's changelog at the tag on raw.githubusercontent.com, and it keeps them while the same version stays on offer. The service takes the transport as an argument (`VitruvianReleases.live` by default), so tests and `release_feed_check` pass their own. There is no fallback to the API: when github.com cannot be reached the API cannot either, and the API is the part that fails on its own. GitHub's releases Atom feed is not used either: it lists the newest ten releases of every product in vitruvian-core.
  - `Tests/mutation_checks.py` (upstream file): the mutation for the first disk image a release lists goes with the asset list it read; five new ones: the check asking the API first, another product's tag taken for Vitruvian's, the per-architecture image, a release whose image is not uploaded yet offered anyway, and the download left unbounded by the HEAD reply's size.
  - `Tests/AboutAndReleaseFeedTests.swift`, `Tools/ReleaseFeedCheck.swift` (VitruvianSoftware's): the tests answer from replies captured from GitHub on 2026-10-15 (`Tests/Fixtures/release-feed/`) and record every request; `release_feed_check` prints the API's quota, answers any request to api.github.com as limit reached, and lists what the check asked. `docs/PRIVACY.md` (upstream file): the update check's paragraph names the hosts it now asks and what it asks them. `bazel/source_lints.py` (VitruvianSoftware's): a new rule, `the_app_never_asks_the_github_api`, fails when any app source names api.github.com outside a comment.
- **2026-10-15**: Settings > About works again, and the app checks for and installs its own releases. Every link on the page, the update check, the price list and the showcase video pointed at `VitruvianSoftware/vitruvian`, a repository that does not exist (set by the rename, VitruvianSoftware/vitruvian-core#2641), so "Check for updates" said "Couldn't check: -". Releases are tags of `VitruvianSoftware/vitruvian-core`, which releases other products too.
  - `Core/AppInfo.swift` (upstream file): View on GitHub opens this app's folder in vitruvian-core, and the website is vitruviansoftware.dev. The copyright line is Info.plist's `NSHumanReadableCopyright`, so the page says what the About box says (set by VitruvianSoftware/vitruvian-core#3304), with `copyrightNotice` for a binary with no Info.plist.
  - `Services/Update/UpdateService.swift` (upstream file): the check lists the `vitruvian-v` tags, takes the newest by version, reads that release (`VitruvianReleases`, VitruvianSoftware's) and offers its universal disk image instead of the first image the release lists. A refusal says why: GitHub's request limit, an HTTP status, or no release found. The GitHub API types move to `VitruvianReleases`.
  - `Services/Update/UpdateInstallerSupport.swift` and `Services/FanControl/FanControlXPC.swift` (upstream files): the installer, the app and the fan helper trust VitruvianSoftware's Developer ID team, Q5MH753M3F, which signs the releases, instead of upstream's 3D485NHW29, so an update can pass the installer's signature checks. The installer reads the team from `FanControlIdentifiers.teamID` through `diskImageRequirement` and `appRequirement`.
  - `Services/Update/UpdateShowcaseMedia.swift` (upstream file): the showcase video is upstream's, so no server is asked for it and the showcase shows its unavailable state.
  - `Services/AgentUsage/AgentPriceSource.swift` (upstream file): the price list comes from this app's folder in vitruvian-core.
  - `UI/Settings/SettingsView.swift` (upstream file): the About header is `AboutHeader`, which shows the app's own icon at 128 points, as macOS's About panels show the app icon, instead of the logo drawn in white inside a 76-point tile.
  - `Core/Localization.swift` and `Core/Localizations/Strings+*.swift` (upstream files): `updateRateLimited` and `updateNoReleaseFound`, in all fifteen languages.
  - `Tests/SwitcherModelFeatureTests.swift` (upstream file): the link check names the repository instead of accepting anything under the organisation, which passed while every link was dead. `Tests/AboutAndReleaseFeedTests.swift` (VitruvianSoftware's) adds `VitruvianReleaseFeedContract`, `UpdateSignerContract` and `AboutPageContract`. `Tests/mutation_checks.py` (upstream file): six mutations for them.
  - `Tools/ReleaseFeedCheck.swift` (VitruvianSoftware's): `bazel run //apps/desktop/vitruvian:release_feed_check` runs the update check against the live GitHub API and opens the About links; `-- --verify-download` also checks the disk image as the installer does.
- **2026-10-15**: `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/Panels.swift` (MIT, written by VitruvianSoftware): comments on `PanelPlacement.island` and `UIBadgeParams` say "the island's Explore gallery" instead of "the island's Tools area", and the pin follows (`bazel/tool_protocol.sha256`, fa537c713a96).
- **2026-10-15**: The release's disk images are signed, and the About box names VitruvianSoftware while keeping Vorssaint's notice. Vitruvian 3.51.0 was the first release signed with the Developer ID: its app was signed and notarized, but `make-dmg.sh` never signed the disk images, so a downloaded DMG failed `spctl -t open` ("no usable signature") although Apple had notarized it.
  - `Tools/make-dmg.sh` (upstream file): signs the compressed image with the installed Developer ID and verifies it, before `notarize.sh` submits it; without an identity the image stays unsigned, as before.
  - `Resources/Info.plist` (upstream file): `NSHumanReadableCopyright` is "© 2026 VitruvianSoftware. Portions © 2026 Vorssaint." instead of "© 2026 Vorssaint".
  - `bazel/source_lints.py` (upstream file): `dmg_is_signed_after_compressing` and `about_box_credits_both_authors`.
- **2026-10-14**: Upstream checks the ports left out because they read Swift source or drove generated copies come back as behavioural tests on the real code:
  - The companion (4a8967e9): `Tests/NotchPresentationRefreshTests.swift` (upstream file) adds the two missing yield cases to `mascotYieldChecks`: a companion staying to react as an activity arrives is not told to fade out, and the stand-in closing the island sends home stays while its place is free and fades out once when something else takes it. `Tests/NotchIslandFixture.swift` (VitruvianSoftware's): the recording host keeps each `endMascotBridge(fading:)`.
  - The Command Bar's drop (46eda2a7): `Services/CommandBar/CommandBarDroplet.swift` (upstream file) takes a `CommandBarDroplet.Environment` (Core Animation's clock, the hook that registers a transaction's completion, Reduce Motion, and the island's drop source, `setMascotInBar` and `orderBelowIsland`); `shared` uses `.live`, which does what the code did before. It gains `typed(keyCode:presentation:)`, upstream's rule that a key or typed text hurries a falling drop unless it is Escape, which `Services/CommandBar/CommandBarService.swift` (upstream file, the key monitor) and `UI/CommandBar/CommandBarView.swift` (upstream file, the query change) call in place of their own `hurry()`. `Tests/CommandBarFeatureTests.swift` (upstream file): `CommandBarDropletContract` drives the real drop on a clock the test moves: typing while it falls hurries it, and closing a falling drop rewinds it before anything cancels it.
  - The keyboard light (992f2cb8): launch's wiring moves from `main.swift` (upstream file) into `NotchControlItem.wireKeyboardLight()` in `Services/Display/BrightnessService.swift` (upstream file), which `main.swift` calls at the same point. `UI/Notch/NotchControlsView.swift` and `UI/Settings/NotchLayoutEditor.swift` (upstream files) ask `NotchLayout.levelCardsShowDetails` for a single level card beside playback too, where each had its own `height >= 88`; the result is the same. `Tests/NotchTests.swift` (upstream file): the launch step reports what the brightness service says, and the shared rule folds level cards at the row heights both surfaces lay out. That both views call it is not something a behavioural test can see.
  - Display identities (9295f465): `Tests/DisplayRestorationTests.swift` (upstream file): the identity and the switched-off record are saved when the disable runs, so a monitor that later inherits the number is refused; and switching a display off while a wake retry is pending cancels the retry. Upstream ran the second on a service that was not running, through a private method; here it runs through `toggleDisplay` on a started one, since a service that is not running refuses the toggle. `Tests/BrightnessRig.swift` (VitruvianSoftware's) gains `Desk.onConfigure`.
  - `Tests/mutation_checks.py` (upstream file): eight mutations, two for each.
- **2026-10-14**: Upstream's `SpacesOrderRequestContract` (848b6042, db5d9cae) is ported as behavioural checks on the real hold. Upstream ran copies of the hold's private request and publication methods under a fake dispatch queue; this fork retired generated copies, so the contract was left out when those commits were ported (#2829). `Services/SpacesOrder/SpacesOrderHold.swift` (upstream file): the hold's serial queue, its "already on the queue" check and its main-thread hand-off move behind `SpacesOrderScheduler`, which `SpacesOrderHold.init` takes and which defaults to `SpacesOrderQueues`, the same queues as before, so the app's behaviour is unchanged. `Tests/SpacesOrderTests.swift` (upstream file): `runRequestContract`, with a scheduler that runs the hold's work step by step and preferences whose save can fail, holds upstream's eleven checks: a sync or removal superseded before it is admitted does nothing, toggle publication survives a failed save and a reentrant sync without losing recovery, off is saved before cleanup removes the marker, and turning the feature back on after a failed save starts a new hold. `Tests/mutation_checks.py` (upstream file): two mutations, a failed save of off that still lets recovery go, and a superseded reconcile that reads the Dock's setting.
- **2026-10-14**: Extensions and tools, task 1 (`docs/superpowers/plans/2026-10-14-vitruvian-extensions-and-tools.md`, design `docs/superpowers/specs/2026-10-14-vitruvian-extensions-and-tools-design.md`, section 2.3): the model a tool's island page needs to become one of the island's own sections. Nothing the person sees changes yet. Upstream files: `Core/Notch/NotchSupport.swift`: `NotchSectionItem` (a module, or an outside tool's id); `NotchSupport.sectionOrder(live:from:)` and `savedSectionOrder(afterMoving:previous:installedTools:)`, over `QuickToolsSupport.tileOrder` and `savedTileOrder`, so an order of modules alone reads as before, and a section that is not showing keeps its place when the others move; `NotchSupport.isModuleShown(_:in:)` and `setModuleShown(_:_:in:)`, taken from Settings, which flip the hidden list and the section's own switch; `modules(in:)` reads the same switches through them, unchanged in what it gives; `filteredItems` and `adjacentItem`, of which `filteredModules` and `adjacentModule` are now the module form; `NotchQuickAction.extensionPanel`, saved as `extension:<tool id>`, never available from Core, and in no fixed palette. `UI/Settings/NotchSettings.swift`: the show and hide switch uses the shared pair, and a reorder of the list saves through `savedSectionOrder`, so the places of tools' sections already saved stay. `UI/Notch/NotchView.swift`: `NotchSectionItem` is a `PanelOrderItem`. `Services/Notch/NotchService.swift` and `UI/Notch/NotchQuickAccessView.swift`: the new action does nothing yet and has a placeholder symbol and title; tasks 2 and 3 give it the tool's. `Tests/NotchTests.swift`: the tests. Not upstream's: `Services/Platform/External/ExternalToolStore.swift`: `availableIslandPanels()`, every island page there is, including those the person turned off; `UI/ToolPanels/ToolIslandTile.swift`: `ToolIslandEntry.available` and `ToolSectionTile`, a tool's page drawn as a section, not used until task 2; `Tests/ToolPanelScreensTests.swift`: the tests.
- **2026-10-14**: Extensions and tools, task 2 (`docs/superpowers/plans/2026-10-14-vitruvian-extensions-and-tools.md`, design `docs/superpowers/specs/2026-10-14-vitruvian-extensions-and-tools-design.md`, sections 2.2 and 2.4): a tool's island page is one of the island's sections in Explore, no longer a tile on the Tools page, and Explore can be customized in place. People whose Tools page held only tools' pages now see its "no tools" message there; the pages are in Explore. Upstream files: `Services/Notch/NotchService.swift`: `sections`, `availableSectionItems` and `filteredSectionItems` (the island's own pages and tools' pages, in `notchModuleOrder` through `NotchSupport.sectionOrder`); `highlightedSection` is a `NotchSectionItem`; `currentSection` and `extensionPage` say which page shows, so the page under a tool's page stops (camera, music reader, system monitor) and takes no keys; `selectSection`, `openExtensionSection` and `open(toolPage:)` open one tool's page at a time, closing the last first; an island page of its own, the app panel or a detail closes it; a refused page leaves Explore showing; Escape on it closes the island and the page; collapsing closes it and a last-page reopen opens it again; `islandPanelsChanged()` falls back to Explore, or the empty page with no section left, when the page goes with its tool or is hidden; reopening reads a tool's id as the saved page, falling back to the first section, else Explore (a value that names no section still gives Controls); `hasNoSections`, over every section, decides the empty page and the Explore button; `editingSections`, ended by leaving Explore or closing the island, sizes the island to the full page and keeps the wheel and search still; `setSectionShown` and `saveSectionOrder` for its editor; `activateQuickAction(.extensionPanel)` opens the tool's page. `UI/Notch/NotchSectionsView.swift`: tools' tiles (`ToolSectionTile`, with their badge) among the island's own; the editor, the Tools editor's grid with as many columns as the page is wide and no scroll view, each section with a hide button but the last, and a tray of hidden sections to show again. `UI/Notch/NotchView.swift`: the customize and done button in Explore's header (and its overflow menu), no search while customizing, a tool's page as the island's page with its title in the header, and the five checks of `modules.isEmpty` read `hasNoSections`. `UI/QuickLauncher/QuickLauncherView.swift`, `Services/QuickTools/QuickLauncherService.swift`: the Tools page no longer lists or hosts tools' pages. `UI/Notch/NotchAgentStrip.swift`: a tool's mark that is not green opens its section, whether or not Tools shows. `Core/NotchStrings.swift`: customize, done, hide, show and the hidden tray's heading, in fifteen languages. `Tests/NotchDestinationTests.swift`, `Tests/NotchKeyMonitorTests.swift`: the tests. `Tests/mutation_checks.py`: three mutations, Escape leaving Explore while customizing, an empty page that counts only the island's own pages, and an island page of its own that leaves a tool's page open. `AGENTS.md`: the rule that tools could not add island pages gives way to how they do. Not upstream's: `Services/Notch/NotchIslandServices.swift`: `visibleToolCount` counts the quick tools only; `islandPanels`, `availableIslandPanels`, `openToolPanel`, `islandPanelTitle`, `openIslandToolPanel` and `setIslandPanelShown`. `Services/Notch/NotchLocalEventRoute.swift`: Escape ends customizing before it leaves Explore, Return, Tab and the arrows do nothing while customizing, and a tool's page keeps the Tools rail's keys. `Services/Notch/NotchEventBindings.swift`: the Tools page no longer follows the island's panel. `UI/ToolPanels/ToolIslandTile.swift`: `ToolIslandTile` and `ToolsRailItem` go. `Tests/NotchIslandFixture.swift`: the services above, recorded.
- **2026-10-14**: Extensions and tools, task 3 (`docs/superpowers/plans/2026-10-14-vitruvian-extensions-and-tools.md`, design `docs/superpowers/specs/2026-10-14-vitruvian-extensions-and-tools-design.md`): the island's settings treat a tool's island page as one of its sections. Upstream files: `Core/Notch/NotchSupport.swift`: `NotchSupport.editorSections(tools:order:)`, every section the Content tab lists; `NotchReopeningTarget` and `NotchSupport.reopeningTarget(returnHome:saved:sections:)`, the reopening rule the island and the picker now share; `NotchReopeningChoice` and `reopeningChoice(returnHome:saved:sections:)`, what the picker shows, so a saved tool's page that is hidden or gone stays chosen, dimmed, as a hidden page of the island's own does, instead of the picker claiming Controls; a value that names nothing still reopens Controls while Controls shows, and with Controls hidden now falls back as a hidden page does (the first section, else Explore) rather than to the first of the island's own pages; `NotchQuickAction.isAvailable(in:shownIslandTools:)` and `NotchQuickAccessConfiguration.current(in:shownIslandTools:)` and `shown(in:shownIslandTools:)`, so a tool's button shows while the island lists its page. `Services/Notch/NotchService.swift`: `reopeningDestination` reads `reopeningTarget`; `quickAccess`, the buttons the island draws, a tool's included while its page is listed; `islandPanelsChanged()` redraws the buttons when one of them is a tool's. `UI/Settings/NotchSettings.swift`: the Content tab lists, shows or hides and reorders tools' island pages beside the island's own (`ExternalToolStore.setShowsInIsland` for a tool's, `savedSectionOrder` for a move); a tool's page has a header with its title, symbol and a line on where its settings are, a still preview, and no options; one that goes with its tool leaves Controls chosen; the "When reopening" picker lists the sections the island shows, tools' pages among them, through `reopeningChoice`. `UI/Settings/NotchContentEditor.swift`: `NotchSectionListRow`, `NotchSectionHeader` and `NotchSectionTile` take a section's title, summary and symbol, so a tool's page uses them too; `NotchExtensionPreview`. `UI/Settings/NotchLayoutEditor.swift`: the "Open a section" group offers each tool's island page (saved as `extension:<tool id>`), and a button dims by the Services lookup. `UI/Notch/NotchQuickAccessView.swift`: a tool's button has its island page's title and symbol, and is marked while its page shows; a module's button is not marked while a tool's page shows. `Core/NotchEditorStrings.swift`: `extensionSummary`, in fifteen languages. `Tests/NotchTests.swift`, `Tests/NotchDestinationTests.swift`: the tests. `Tests/mutation_checks.py`: five mutations: the picker showing a hidden tool's page as another, reopening on a section that is not showing, a tool's button that shows whether or not its page does, the island drawing a hidden page's button, and a button's title in English whatever the language. Not upstream's: `Services/Notch/NotchExtensionActions.swift` (new): a tool's quick-access button's title, symbol and whether it shows, from its island panel's declaration and `ExternalToolStore.availableIslandPanels()`; `Tests/ToolPanelScreensTests.swift`: its test against added tools.
- **2026-10-14**: Extensions and tools, task 4 (`docs/superpowers/plans/2026-10-14-vitruvian-extensions-and-tools.md`, design `docs/superpowers/specs/2026-10-14-vitruvian-extensions-and-tools-design.md`, section 4): the Features card is called "Extensions & Tools", and each added package is badged Extension (its manifest has panels, in any place) or Tool (commands only). The card's sentence and the catalog's empty line name extensions and tools both, and do not promise every extension an island page. Upstream files: `README.md`, `docs/PRIVACY.md`: the card's new name. `AGENTS.md`: the badge, and where the catalog cannot show one. Not upstream's: `Core/ExternalToolStrings.swift`: `kindExtension` and `kindTool`, and new words for `sectionTitle`, `sectionEmpty` and `catalogEmpty`, in fifteen languages; `UI/Settings/ExternalToolsSection.swift`: `ExternalToolRow.Kind`, `kind` and `kindBadge`, and the pill beside the byline (also in the row's VoiceOver label); `UI/Settings/ExternalToolCatalogueSheet.swift` is unchanged: a catalog entry carries no panels; `Tools/ByHandRules.swift`, `Tools/ByHand.swift`: the card is found by its new name; `Tests/ExternalToolStringsTests.swift` (70 texts), `Tests/ExternalToolScreensTests.swift`, `Tests/CatalogueScreensTests.swift`, `Tests/ByHandRulesTests.swift`: the tests.
  Every file tasks 1 to 4 change, for the record. Upstream files: `AGENTS.md`, `README.md`, `docs/PRIVACY.md`, `Core/Notch/NotchSupport.swift`, `Core/NotchEditorStrings.swift`, `Core/NotchStrings.swift`, `Services/Notch/NotchService.swift`, `Services/QuickTools/QuickLauncherService.swift`, `UI/Notch/NotchAgentStrip.swift`, `UI/Notch/NotchQuickAccessView.swift`, `UI/Notch/NotchSectionsView.swift`, `UI/Notch/NotchView.swift`, `UI/QuickLauncher/QuickLauncherView.swift`, `UI/Settings/NotchContentEditor.swift`, `UI/Settings/NotchLayoutEditor.swift`, `UI/Settings/NotchSettings.swift`, `Tests/NotchDestinationTests.swift`, `Tests/NotchKeyMonitorTests.swift`, `Tests/NotchTests.swift`, `Tests/mutation_checks.py`. Not upstream's: `Core/ExternalToolStrings.swift`, `Core/Platform/ToolPanel.swift`, `Services/Notch/NotchEventBindings.swift`, `Services/Notch/NotchExtensionActions.swift` (new), `Services/Notch/NotchIslandServices.swift`, `Services/Notch/NotchLocalEventRoute.swift`, `Services/Platform/External/ExternalToolCalls.swift`, `Services/Platform/External/ExternalToolStore.swift`, `Services/Platform/External/ToolPanelHost.swift`, `Services/Platform/External/ToolRecords.swift`, `UI/Settings/ExternalToolsSection.swift`, `UI/ToolPanels/ToolIslandTile.swift`, `Tools/ByHand.swift`, `Tools/ByHandRules.swift`, `Tests/ByHandRulesTests.swift`, `Tests/CatalogueScreensTests.swift`, `Tests/ExternalToolScreensTests.swift`, `Tests/ExternalToolStringsTests.swift`, `Tests/NotchIslandFixture.swift`, `Tests/ToolPanelScreensTests.swift`. In `ToolPanel.swift`, `ExternalToolCalls.swift`, `ToolPanelHost.swift` and `ToolRecords.swift` only comments changed: an island page is a section in Explore, not a page of the Tools area.
- **2026-10-14**: Extensions and tools, the catalog's pill: an entry in `catalog/tools.json` may list `panels` (its manifest's panel placements), and the catalog's sheet (`UI/Settings/ExternalToolCatalogueSheet.swift`, `CatalogueRow.kindBadge`) draws the same Extension or Tool pill (`ExternalToolKindBadge`) beside the byline when `panels` is present, and none when an older entry leaves it out. Upstream files: `AGENTS.md`, `Tests/mutation_checks.py` (one mutation, an extension badged as a tool on the catalog sheet). Not upstream's: `Services/Platform/External/Catalogue/CatalogueClient.swift` (`CatalogueEntry.panels`), `UI/Settings/ExternalToolCatalogueSheet.swift`, `UI/Settings/ExternalToolsSection.swift`, `Tests/CatalogueListTests.swift`, `Tests/CatalogueScreensTests.swift`.
- **2026-10-14**: The app no longer registers the `vitruvian://` URL scheme. It was added for the GitHub feature's browser sign-in, whose last code went with the feature in 3.49; since then macOS still sent `vitruvian://` links to the app, which ignored them. Nothing else in the repository opens such a link. Upstream file: `Resources/Info.plist`: `CFBundleURLTypes` goes. Not upstream's: `bazel/source_lints.py`: a new rule, `url_schemes_have_a_handler`, fails when `Info.plist` registers a URL scheme and no app source handles a URL event (`kAEGetURL`, `application(_:open:)` or `onOpenURL`).
- **2026-10-14**: Tools for everyone, the GitHub part's last step: the GitHub hand-off goes, after 3.50.1, one release after the feature (3.49). Adding the GitHub tool hands it nothing now; it starts signed out, with its own defaults. Nothing in the app touches the Keychain any more. The old feature's Keychain item ("Vitruvian GitHub sign-in") is left where it is: the app never reads or deletes it, so no prompt appears; the person may delete it in Keychain Access. The feature's old preferences stay in the person's preferences file, unread, and a backup neither writes nor restores them. Deleted, VitruvianSoftware's: `Services/GitHub/GitHubHandoff.swift`, `Services/GitHub/GitHubTokenStore.swift` (the Keychain store and `GitHubSavedToken`), `Tests/GitHubHandoffTests.swift`. Upstream files:
  - `Core/DefaultsKey.swift`, `Core/Defaults.swift`: the GitHub feature's seventeen keys and their defaults, `githubReplacedByTool` among them.
  - `Services/FeatureRuntime.swift`: `availabilityChangedElsewhere()`, whose last caller was the hand-off, goes.
  - `Tests/mutation_checks.py`: the hand-off's three mutations go; the two on the store's waiting add now name the suite `tool-runtime` and the tests that moved there; one more, an add that does not wait.
  - Not upstream's: `Core/Preferences.swift` (the feature's preferences); `Services/Platform/External/ExternalToolStore.swift`: `Parts.live` hands nothing over and keeps `beforeAdding`, `added` and `removed` for the next feature that becomes a tool; `UI/Settings/ExternalToolsSection.swift`, a comment; `Tests/ExternalToolStoreTests.swift`: the hand-off's checks of the store, tool-neutral (told before the program starts, an add that waits, a removal while it waits, agreeing twice); `Tests/FeatureRuntimeTests.swift`, `Tests/TestGroups.swift`; `bazel/source_lints.py`: `keychain_is_never_touched` now fails on `SecItem` anywhere in the app's sources, and `the_tools_card_never_waits_to_add` no longer names the GitHub tool; `BUILD`, a comment.

- **2026-10-14**: A click on the closed island while a Nexus session runs opens the Agents page, as the wings show. `UI/Notch/NotchAgentStrip.swift` (upstream file): the click passes `nexusSession.isRunning` to `RestingStatus.opens` (`Services/Platform/External/ToolPanelHost.swift`, not upstream's), which gives no tool page while it is true. Before, the session hid a tool's mark but the click still followed it to that tool's page. Found by the design of a tool's words on the closed island (`docs/superpowers/specs/2026-10-14-vitruvian-tool-resting-activity-design.md`, section 2, row 8). `Tests/ToolStatusTests.swift`: the test. `Tests/mutation_checks.py` (upstream file): one mutation, the guard taken away.
- **2026-10-14**: The closed island's Nexus sparkles keep still under Reduce Motion. `UI/Notch/NotchAgentStrip.swift` (upstream file): `NexusSparkleMotion` (new, in the same file) holds the swing, 85 % to 115 % each second, eased over 0.8 seconds, and gives a still sparkle at its own size and no animation when Reduce Motion is on; the resting wing reads `accessibilityReduceMotion` and draws through it. Found by the design of a tool's words on the closed island (`docs/superpowers/specs/2026-10-14-vitruvian-tool-resting-activity-design.md`, section 2, row 7). `Tests/NexusSparkleMotionTests.swift` (new, suite `agents`), `Tests/TestGroups.swift` (upstream file): the test. `Tests/mutation_checks.py` (upstream file): one mutation, the still sparkle taken away.
- **2026-10-14**: A tool's words on the closed island (`docs/superpowers/plans/2026-10-14-vitruvian-tool-resting-activity.md`, design `docs/superpowers/specs/2026-10-14-vitruvian-tool-resting-activity-design.md`). Protocol 2 gains them with no new version: Vitruvian 3.48 and 3.49 read each new field and key and ignore it.
  - The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, 83194a22ace4): `activity` and `since` on `ui/status` (`UIStatusParams`, whose decoder refuses a `since` below 0), `activity` in `contributes.status` (`ToolManifestFile.Status`), and the feature `ui.status.activity` (`ProtocolFeature.statusActivity`). `Services/Platform/External/ExternalToolStore.swift` (written by VitruvianSoftware) names the hello's features from a list of its own, `ExternalToolStore.features`, so the new name is not claimed before the app draws it. `Tests/ExternalToolStoreTests.swift`, `ExternalToolCallsTests.swift`. `Tests/mutation_checks.py` (upstream file): the mutation "the app says it has nothing" quotes the hello's new line; two mutations, a start time before 1970 read, and a hello that claims words the app does not draw.
  - The app keeps a status's words (`Core/Platform/ToolStatus.swift`: `ToolStatus.activity` and `since`; `RestingStatus.RightWing`, `rightWing`, `fewWords`, `seconds`, `ticksEverySecond`; `words` says the tool's few words after the mark's, never its seconds), reads `activity: true` from the manifest (`Core/Platform/ExternalToolManifest.swift`, `showsActivity`), and leaves out the words of a tool that does not declare them, logging it once for each run (`Services/Platform/External/ToolPanelHost.swift`). The hello names `ui.status.activity` (`ExternalToolStore.features`). All written by VitruvianSoftware. `Tests/ToolStatusTests.swift`, `ToolPanelHostTests.swift`, `ExternalToolStoreTests.swift`, `ExternalToolManifestTests.swift`. `Tests/mutation_checks.py` (upstream file): the hello's two mutations follow its new list and message ("the app claims words it does not draw" is now "the app forgets words it draws"); five mutations, undeclared words drawn, seconds that beat the words, a future start that counts down, another tool's words beside the mark, and a button that reads the seconds aloud.
  - `UI/Notch/NotchAgentStrip.swift` (upstream file): the closed island's right-hand wing draws the shown tool mark's few words, or the seconds since its start time, in place of the allowance percent, in the look of Nexus Agent's text (`Text(verbatim:)`, 9 point semibold monospaced, white, one line, shrinking to 70 %); with no words it draws the percent exactly as before. Its clock ticks every second while it counts seconds, as it does while Nexus runs, and every six seconds otherwise, as before. The left-hand wing, the tap, Nexus's own text and its sparkles are unchanged. `UI/Settings/ExternalToolAgreementSheet.swift` and `Core/ExternalToolStrings.swift` (written by VitruvianSoftware): the sheet says "It shows a small status mark and a few words on the closed Dynamic Island." for a tool whose status says `"activity": true`, in fifteen languages (68 texts). `Tests/ToolStatusTests.swift`, `ExternalToolScreensTests.swift`, `ExternalToolStringsTests.swift`. `Tests/mutation_checks.py` (upstream file): the sheet's mutation quotes its new lines; one mutation, a sheet that says a status but not its words.
- **2026-10-13** (ships one release after the stage E entry below): Tools for everyone, stage E, the removal: the GitHub feature is gone, the GitHub tool from the catalog having taken its place. Deleted, all VitruvianSoftware's: `Core/GitHub/` but `GitHubTokenStore.swift`, `Services/GitHub/` but the token store and `GitHubHandoff.swift`, `UI/Notch/NotchGitHubView.swift`, `UI/Settings/GitHubSettingsView.swift`, `Core/NotchGitHubStrings.swift`, `Tests/GitHubCoreTests.swift` and the `github` suite. Upstream files:
  - `Core/FeatureCatalog.swift`: the case `notchGitHub` and every arm of it; `isReplaced(in:)` and its part of `isAvailable(in:)` go with it. `Core/Settings/FeatureVisibilitySupport.swift`: the page `github`. `Core/Notch/NotchSupport.swift`: the island module `github` and its arms; a saved layout naming it is read without it, as any name the app lacks is. `Core/NotchEditorStrings.swift`, `UI/Settings/NotchContentEditor.swift`, `UI/Settings/NotchSettings.swift`, `UI/Notch/NotchView.swift`, `UI/Settings/SettingsView.swift`, `Services/Settings/SettingsDirectory.swift`, `Services/Settings/FeatureHubText.swift`, `Services/FeatureRuntime.swift`, `Core/FeaturePresets.swift`, `Core/SettingsBackupSupport.swift`: their arms for it. `UI/Notch/NotchAgentStrip.swift`: the resting wing's GitHub light and its tap. `UI/Settings/FeatureHubSettings.swift`: the replaced filter goes. `Core/DefaultsKey.swift`, `Core/Defaults.swift`: the switch and the relay address go; the feature's other keys stay one release for the hand-off, which now reads the token from the Keychain store itself. `Tests/FeatureCatalogTests.swift`, `Tests/mutation_checks.py`: what named the feature.
  - What the fixes made since stage E become, now that the feature is gone. The Keychain fix two entries below: `GitHubAuthService` is deleted, so its off-main read lives on as `GitHubSavedToken` in `Services/GitHub/GitHubHandoff.swift` (not upstream's), which reads the feature's Keychain item on a queue of its own, once, and which `GitHubHandoff.Parts.live` takes its `readToken` and `token` from; `prepare`, `ExternalToolStore.add(_:then:)`, the Add Tool button and the lint `the_tools_card_never_waits_to_add` are as that entry left them. The launch path that showed the sign-in as being checked (`syncWithPreferences`) went with the service, and with it `launchNeverWaitsForTheKeychain`, `aLateKeychainAnswerNeverOverridesThePerson` and their two mutations; the five tests in `GitHubHandoffTests` stay, over `GitHubSavedToken`, with `HeldGitHubTokenStore` moved into that file. The Settings fix below: the hand-off hides and brings back no feature any more, so `GitHubHandoff.Parts.availabilityChanged`, `Parts.featureOff` and the closure `toolRemoved` took are gone, with their mutation; `Services/FeatureRuntime.swift` keeps `availabilityChangedElsewhere()` and its test for the next feature a tool replaces, with no caller in the app until then.
  - What the closed island's status mark (the entry below, pull request #3245) becomes, now that the feature is gone. Its rule was "of the built-in GitHub mark and every tool's status the worst wins; on a tie the built-in, then the tool added first". The built-in mark is gone, so the rule is "of every tool's status the worst wins; on a tie the tool added first". `Core/Platform/ToolStatus.swift`: `RestingMark.gitHub` goes, so `RestingMark` has one case, `.tool`; `RestingStatus.severity(_: Verdict)`, `RestingStatus.gitHub(watching:aggregate:)` and the `gitHub:` argument of `winner` go, and with it the tie-break that favoured the built-in. `UI/Notch/NotchAgentStrip.swift` (upstream file): `NotchGitHubRestingIndicator` goes, and with it the wing's watch on `GitHubService` and the tap's middle case that opened the GitHub page on a red or amber mark; the case in front (a tool's mark that is not green opens its page) and the last (the agents' chat) stay. `Services/Platform/External/ToolPanelHost.swift`: `saidNow` and `saidChanges` no longer ask or watch `GitHubService`. `UI/ToolPanels/ToolStatusMark.swift`: the look is unchanged; its comments say it was the built-in's. `Tests/ToolStatusTests.swift`: the tests that set the built-in against a tool (`theBuiltInAloneIsTheBuiltIn`, the built-in half of `theWorstWins` and of the tie test, `theBuiltInMarkIsWhatItWas`, and one line each in `aSwitchedOffStatusIsKeptAndNotDrawn`, `aClickOpensTheToolsPageUnlessItIsOK` and `theIslandsButtonSaysTheMark`) go; the tie test is now `aTieGoesToTheEarlierTool`, over every state; `eachStateHasTheBuiltInsLook` is `eachStateHasItsLook`, with the same numbers. `Tests/mutation_checks.py` (upstream file): the mutation "busy does not breathe" waits for the renamed message.
- **2026-10-13**: A tool's status on the closed island, and a choice among fixed options (`docs/superpowers/plans/2026-10-13-vitruvian-tool-resting-status-and-choice.md`, design `docs/superpowers/specs/2026-10-13-vitruvian-tool-resting-status-and-choice-design.md`). Protocol 2 gains both with no new version: an older app ignores each new key and answers the one new request with -32601. The files of the app this changes that carry an upstream header are named in the lines below; the rest were written by VitruvianSoftware and have none.
  - The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, df4d20323c92): the request `ui/status` with its five states (`UIStatusParams`, `StatusState`); the thirteenth kind of block, `choice` (`ChoiceBlock`, `UIChoiceOption`); `contributes.status` and `options` on a `string` preference in the manifest (`ToolManifestFile.Status`, `Option`), with eight new `ManifestProblem` cases; `features` in `initialize` (`InitializeParams.features`, `ProtocolFeature`).
  - `Services/Platform/External/ExternalToolCalls.swift`, `UI/ToolPanels/BlockTreeView.swift`: one arm each, so the app compiles and stays honest until it has the feature: `ui/status` is answered -32601, as an app before this answers it, and a `choice` block is drawn as its fallback. `Tests/ExternalToolCallsTests.swift`, `ToolPanelTests.swift`, `ExternalToolManifestTests.swift`.
  - `Tests/mutation_checks.py` (upstream file): four mutations, planted in the protocol's sources: options on a setting that is not text, a default that is no option, a choice with no id, a status in a manifest of protocol 1.
  - The app keeps a tool's status and a setting's options; nothing a person sees changes yet. `Core/Platform/ToolStatus.swift` (new): `ToolStatus`, and `RestingStatus.winner`, which picks the one mark the closed island shows: the worst of the built-in GitHub mark and every tool's, the built-in on a tie, then the tool added first. `Core/Platform/ExternalToolManifest.swift`: `showsStatus`, `preferenceOptions`. `Services/Platform/External/ToolPanelHost.swift`: `statuses`, set by `status(_:_:)`, refused for a tool whose manifest declares none (-32602), shown at most once a second for each tool, and cleared when the tool's program ends or the tool is forgotten. `ExternalToolCalls.swift`: `ui/status` is handed on, behind nothing in `uses`. `ExternalToolStore.swift`, `ToolRecords.swift`: the hello names the app's three features; a record's `showsStatus`, written only once turned off; `statusTools()`; a setting carries its options. A value that is no option's is saved as before, by the tool and by the person.
  - `Tests/ToolStatusTests.swift` (new, suite `platform`), and more in `ExternalToolManifestTests.swift`, `ExternalToolStoreTests.swift`, `ToolPanelHostTests.swift`, `ExternalToolCallsTests.swift`. `Tests/mutation_checks.py` (upstream file): five mutations: a status that outlives its program, one from a tool that declared none, a switched-off status listed, the mildest status winning, a hello that names nothing.
  - `UI/Notch/NotchAgentStrip.swift` (upstream file): the resting wing draws one status mark where it drew the built-in GitHub mark alone. `RestingStatus.winner` picks it: the built-in mark, drawn by `NotchGitHubRestingIndicator` exactly as before, or a tool's, drawn by the new `ToolStatusMark`, or none. With no tool's status the wing is as it was. The rule for when the built-in has a verdict moved into `NotchGitHubRestingIndicator.verdict(watching:aggregate:)`, so the wing and the mark use one. The wing's tap gains one case in front: when the mark shown is a tool's and is not green, and the island lists that tool's page, it opens the Tools page on it; every other tap runs the lines it ran before. The wing now also watches `ToolPanelHost`, `ToolRegistry` and the language.
  - `UI/ToolPanels/ToolStatusMark.swift` (new): a tool's mark, with the built-in's sizes, colours and breathing (`ToolStatusMarkContent` holds them as plain values), a VoiceOver label and a tooltip. `UI/ToolPanels/BlockTreeView.swift`: a `choice` block is a pop-up menu, and a pick is the event `change`. `UI/Settings/ExternalToolsSection.swift`: a text setting with options is a pop-up menu (`ExternalToolSetting.Control.choice`), a stored value that is no option's is its first row as written, and the detail has a switch "Show its status on the closed Dynamic Island". `UI/Settings/ExternalToolAgreementSheet.swift`: one line for a tool that declares a status. `Core/ExternalToolStrings.swift`: six texts, in all fifteen languages; the fourteen that are not English were written with the English and read by nobody who speaks them.
  - Tests: `ToolStatusTests.swift`, `ExternalToolSettingsTests.swift`, `ExternalToolScreensTests.swift`, `ToolPanelScreensTests.swift`, `ExternalToolStringsTests.swift` (67 texts). `Tests/mutation_checks.py` (upstream file): four mutations: a stored value dropped from the menu, a green mark that opens the tool's page, a busy mark that does not breathe, an agreement sheet that says nothing of a status.
  - Not checked at a screen: nothing here was drawn. The plan's "By hand" list, checks 1 to 13, is owed.
  - After the first checks at a screen (pull request #3245), two accessibility defects, fixed. The closed island hides what it draws at rest from assistive technology (`UI/Notch/NotchView.swift`, `NotchRestingStrip`, upstream's `.accessibilityHidden(true)`, left as it is) and offers one button over it, so a tool's mark had no words anywhere. `Services/Notch/NotchService.swift` (upstream file) now names that button "Open Dynamic Island" and then what the mark says (`closedTitle`, `RestingStatus.buttonTitle`), only while the wings draw the mark, and names it again when the status changes (`restingStatusChanged`, fed by two new members of `Environment`, `restingStatus` and `restingStatusChanges`, which default to nothing). `Services/Notch/NotchMirrors.swift` gives a copy's button the same name and renames it when only the name changed. `Core/Platform/ToolStatus.swift` holds the words (`words`, `colon`, `buttonTitle`, `gitHub`), moved from `UI/ToolPanels/ToolStatusMark.swift` and `UI/Notch/NotchAgentStrip.swift` (upstream file, one line: the built-in mark's rule now calls `RestingStatus.gitHub`); `Services/Platform/External/ToolPanelHost.swift` reads them live (`saidNow`, `saidChanges`).
  - Every switch and field in a tool's detail, and every switch and field on a tool's page, is named with its row's title (`controlNamed`, in `UI/ToolPanels/BlockTreeView.swift`; used in `UI/Settings/ExternalToolsSection.swift`). A pop-up menu is not: its own label, though hidden, already names it, and a second name made VoiceOver say it twice (seen on screen, fixed). `bazel/source_lints.py`: `tool_screen_controls_have_names`, beside upstream's `menu_panel_switches_have_names`, fails a switch or a field with no name and a pop-up menu named twice.
  - Tests: `Tests/NotchRestingStatusVoiceTests.swift` (new, suite `notch`), called from `Tests/NotchPresentationRefreshTests.swift` (upstream file, one line); `Tests/NotchMirrorTests.swift` (upstream file: the copy's button's names are recorded and checked); `Tests/NotchIslandFixture.swift`; `Tests/ToolStatusTests.swift`. `Tests/mutation_checks.py` (upstream file): five mutations, a button that leaves the mark out, one that says a mark the wings do not draw, an island and a copy that do not hear a change.
  - Not checked at a screen: that VoiceOver reads the button's new name, and each switch's. In the test process SwiftUI builds no accessibility tree, so the tests check the name the island gives its button, and the lint checks that every control is named in the source.
- **2026-10-13**: The app no longer freezes while macOS asks for the login password to read the GitHub sign-in. Seen in 3.46.1: pressing Add Tool for the GitHub tool froze every window and the menu bar icon for as long as "Vitruvian wants to use your confidential information stored in "Vitruvian GitHub sign-in" in your keychain" stayed unanswered. The prompt is macOS's own and stays: the app is signed ad hoc, so after an update the new build must ask for an item the old build saved. The defect was that the main thread waited inside the read. None of the files below is upstream's except the last.
  - `Services/GitHub/GitHubAuthService.swift`: the saved token is read on a queue of its own, once (`loadToken(then:)`); `currentToken()` answers from what the service holds and never asks the Keychain. `syncWithPreferences` (launch, and the feature's switch) shows the sign-in as being checked while the Keychain is asked and goes on from its answer; a sign-in, a disconnect, a cancel or a 401 in between wins, and the late answer is dropped. `hasSavedToken`, which nothing used and which read on the main thread, is gone.
  - `Services/GitHub/GitHubHandoff.swift`: `prepare` has the token read before the GitHub tool is added (`Parts.readToken`); `perform` is unchanged and takes what was read. A refused prompt hands over everything but the token, as before.
  - `Services/Platform/External/ExternalToolStore.swift`: `add(_:then:)` waits for `Parts.beforeAdding`, then adds exactly as `add(_:)` does, so the hand-off still runs once and before the tool's program starts. Removing the tool, or agreeing to it again, while it waits drops the waiting add.
  - `UI/Settings/ExternalToolsSection.swift`: the Add Tool button takes `add(_:then:)`; while a tool waits to be added the card shows the small progress wheel the catalog's row already has. `bazel/source_lints.py` (`the_tools_card_never_waits_to_add`) holds the button to it.
  - Left as they are: the Keychain writes (`save` on sign-in, `delete` on disconnect and on a 401) still run on the main thread. They follow a click in a sign-in that already holds its token, and their order with the token in memory matters; none was seen to prompt.
  - Tests: `GitHubCoreTests` (`launchNeverWaitsForTheKeychain`, `aLateKeychainAnswerNeverOverridesThePerson`, suite `github`) and `GitHubHandoffTests` (five, suite `platform`) hold the read the way the prompt does. `Tests/mutation_checks.py` (upstream file): six mutations, the main-thread read among them.
- **2026-10-13**: Tools for everyone, stage F (`docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-f.md`), the Nexus Agent tool: the fifty-six texts of `Core/NexusAgentStrings.swift` that the tool's pages and chat show, in all fifteen languages, were copied to `apps/desktop/nexus-agent/macos/Sources/NexusAgentToolCore/Words.swift` and released under MIT by their copyright holder, VitruvianSoftware, which wrote all of them; the app's file is unchanged until the feature goes. Nothing upstream wrote left this folder.
- **2026-10-13**: Settings follows a feature a tool replaces, without a restart. Seen in 3.46.0: with the GitHub tool added, the Features page dropped the GitHub feature but the Settings sidebar went on listing "GitHub" until the app was restarted, and clicking it landed on Features; the same in reverse when the tool was removed. The sidebar is rebuilt when `FeatureRuntime.revision` moves, and only an install or uninstall in the hub moved it; the hand-off changes availability by a flag of its own. Upstream files:
  - `Services/FeatureRuntime.swift`: `availabilityChangedElsewhere()`, for a change made outside install and uninstall. It does what the end of a hub change does (one bump of `revision`, then the environment's follow-up: the tool registry, the Command Bar's rows, the island) and runs no binding, since whoever made the change wrote the defaults and stopped the service already.
  - `Tests/mutation_checks.py`: one mutation, a hand-off that hides the feature and tells Settings nothing.
  - Not upstream's: `Services/GitHub/GitHubHandoff.swift` calls it through `Parts.availabilityChanged` once the feature is hidden, and `toolRemoved` through a closure it is passed once the feature is back, which `Services/Platform/External/ExternalToolStore.swift` (`Parts.live`) gives it; `Tests/GitHubHandoffTests.swift` counts the calls, and `Tests/FeatureRuntimeTests.swift` checks the method.
- **2026-10-13**: Tools for everyone, stage E (`docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-e.md`): the GitHub feature becomes the GitHub tool from the catalog (`apps/desktop/vitruvian-tool-github`, id `dev.vitruvian.github`). New: `Services/GitHub/GitHubHandoff.swift`, which hands the feature's token, watched repositories, poll intervals, mouse settings and client ID to the tool through its `storage` once, when the tool is added, turns the feature's switch off and marks it replaced. Upstream files:
  - `Core/FeatureCatalog.swift`: `isReplaced(in:)`, and `isAvailable(in:)` is false for a replaced feature, so its island page, Settings page and Features row are hidden while the tool is installed. `Core/DefaultsKey.swift`, `Core/Defaults.swift`: the key `githubReplacedByTool` and its default, false.
  - `UI/Settings/FeatureHubSettings.swift`: the two lists of a group's members leave out a replaced feature.
  - `Tests/mutation_checks.py`: two mutations, a hand-off that forgets the token, and a replaced feature that stays listed.
  - Not upstream's: `Services/Platform/External/ExternalToolStore.swift` tells of an added tool before its program starts and of a removed one (`Parts.added`, `Parts.removed`); `Core/NotchGitHubStrings.swift` has one new text in all fifteen languages, `movesToTool`; `UI/Settings/GitHubSettingsView.swift` says it at the top of the page, with Browse Tools…; `Core/Preferences.swift` declares the flag; `Tests/GitHubHandoffTests.swift` is new, in the `platform` suite.
- **2026-10-12**: Tools for everyone, stage D (`docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-d.md`): protocol 2, a tool that can draw. The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, 868f1a82fa5a): a manifest may say `"protocol": "2"` and contribute `panels`, each in the island, in Settings or in a window, drawn by the app from blocks or shown as a web page from the tool's folder; five messages, `ui/open`, `ui/event`, `ui/close`, `ui/render` and `ui/badge`; the twelve kinds of block (`Panels.swift`); nine new `ManifestProblem` cases. The app offers versions 1 and 2 at `initialize`, and a tool of protocol 1 is read and run as before. The files of the app this changes that carry an upstream header are named in the lines below (the island's, for the tile and the windows); the rest were written by VitruvianSoftware and have none.
  - New: `Core/Platform/ToolPanel.swift`, a tool's panel as the app holds it. `Core/Platform/ExternalToolManifest.swift` reads a manifest's panels onto it. `Services/Platform/External/ExternalToolCalls.swift` answers `ui/badge` behind `notify`, as not available for now. `Tests/ExternalToolManifestTests.swift`, `ExternalToolCallsTests.swift`, `ExternalToolStoreTests.swift`; `Tests/mutation_checks.py`: one mutation (a manifest of protocol 1 with panels read).
  - `Core/Platform/ToolPanel.swift`: a page a tool sends is read within its limits, 256 KB and 200 blocks, with a block of a later kind kept for its fallback (`ToolPanelTree`); a web panel may go to files of its tool's folder and nowhere else (`ToolWebPolicy`); a picture is a file of the folder or a `data:` address (`ToolPanelImage`). With `Tests/ToolPanelTests.swift`; `Tests/mutation_checks.py`: four mutations.
  - `Services/Platform/External/ToolLink.swift`, `ExternalTool.swift`, `ExternalToolCalls.swift`: the link asks for a panel (`ui/open`), says what the person did (`ui/event`) and that a panel went away (`ui/close`), and hands on a page the tool sends (`ui/render`), stopping a tool that sends more than forty a second for one panel; opening a panel starts a tool's program as a command does, an open panel keeps it from the idle stop, and every panel ends with the program; `ui/badge` is handed on behind `notify`. `Tests/ToolLinkTests.swift`, `ExternalToolTests.swift`, `ExternalToolCallsTests.swift`; `Tests/mutation_checks.py`: four mutations.
  - New: `Services/Platform/External/ToolPanelHost.swift`, what tools draw: for each open panel the last page its tool sent, read away from the main thread and drawn at most four times a second; what the person did, passed to the tool; a tool's badge; a web panel's page, which the host alone keeps, and its calls, passed to the tool's program under the tool's `uses` and the link's flood rule. `ExternalToolStore.swift` hands each tool's pages, badge and end to it. `Tests/ToolPanelHostTests.swift`, `ExternalToolStoreTests.swift`; `Tests/mutation_checks.py`: seven mutations.
  - `Core/ExternalToolStrings.swift`: two texts in all fifteen languages, the sentence for a panel that could not be shown and the switch that lists a tool's page in the island; 61 texts now. `Tests/ExternalToolStringsTests.swift`; `Tests/mutation_checks.py`: one mutation.
  - New: `UI/ToolPanels/BlockTreeView.swift`, a page drawn with the app's own controls from a plain value (`BlockTreeContent`): the person's language, a line limit on every text and 2,000 characters at most, a picture from the tool's folder, a link only to a web or mail address, a later block's fallback; and `UI/ToolPanels/ToolPanelView.swift`, an open panel in any place, with the sentence for one that could not be shown. `UI/Settings/ExternalToolsSection.swift`: the detail's focus has a case for a control of the tool's panel. `Services/Platform/External/ToolPanelHost.swift`: a link block opens through the tool's own `open` service. `Tests/ToolPanelScreensTests.swift`, `ToolPanelHostTests.swift`; `Tests/mutation_checks.py`: three mutations.
  - `UI/Settings/ExternalToolsSection.swift`: a tool's detail draws its Settings panel under its own settings, lists its windows under its commands with the app's word Open, and has the switch "Show in the Dynamic Island" for a tool with an island page; every new control is bound to the detail's one focus. `Services/Platform/External/ToolRecords.swift` remembers that switch, written only once it is off; `ExternalToolStore.swift` keeps it and closes an island page turned off. `Tests/ToolPanelScreensTests.swift`; `Tests/mutation_checks.py`: three mutations.
  - The island's Tools page lists each tool's island page as a tile after the quick tools, with the tool's badge, and shows the page in place of the tiles, as it does a hosted utility. Upstream files: `UI/QuickLauncher/QuickLauncherView.swift` (the tiles of tools' pages in the rail, and the page with its back button), `Services/QuickTools/QuickLauncherService.swift` (Esc closes the page first; the page keeps the launcher open as a utility does; the arrow keys and Return stay with the quick tools), `UI/Notch/NotchView.swift` (the header's customize action steps aside while a page shows), `Services/Notch/NotchService.swift` (the page is sized as a hosted utility is; collapsing the island closes it, and its tool is told). Ours: `Services/Notch/NotchIslandServices.swift`, `NotchEventBindings.swift`, `Services/Platform/External/ExternalToolStore.swift` (`islandPanels`), new `UI/ToolPanels/ToolIslandTile.swift`; `Tests/NotchIslandFixture.swift`, `ToolPanelScreensTests.swift`; `Tests/mutation_checks.py`: two mutations.
  - A tool's window and a web panel. New: `UI/ToolPanels/ToolPanelWindows.swift`, a window the app owns for each window panel that is open, titled with the panel's title and the tool's name, 380 points wide and as tall as its blocks up to 560, or 640 by 480 for a web page; closing it tells the tool. `UI/ToolPanels/ToolWebPanel.swift`, a web panel: a web view that loads only files of the tool's folder, refuses any other navigation and every new window, and gives the page `window.vitruvian` before its scripts run; its calls go to the panel host. `UI/ToolPanels/ToolPanelView.swift` draws it; `Services/Platform/External/ToolPanelHost.swift` logs where a page tried to go. Upstream file: `main.swift`, one line that starts following the tools' windows at launch. `Tests/ToolWebPanelTests.swift`; `Tests/mutation_checks.py`: three mutations.
- **2026-10-12**: Tools for everyone, stage C (`docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-c.md`): the tool catalog. A person installs a tool from a curated, signed list, through the same agreement sheet as a folder, and is told when a newer version is listed. Every new file was written by VitruvianSoftware and has no upstream header.
  - New: `Core/ExternalToolStrings.swift` gains the 13 texts of the catalog in all fifteen languages; `Tests/mutation_checks.py`: one mutation (a sentence about the catalog left in English).
  - `Tests/mutation_checks.py`: two mutations (a list with a bad signature accepted, a fetch over plain http).
  - `Tests/mutation_checks.py`: three mutations (a download with a bad checksum, a zip entry that leaves its folder, an install before the person agrees).
  - `Tests/mutation_checks.py`: three mutations (a tool from a folder matched by its id, an update to an older version, an older list accepted).
  - `Sources/Vitruvian/main.swift`: at launch the catalog's installer deletes what a quit left half downloaded and the catalog's watch starts; a build made with `--define=vitruvian_sample_tool=true` may point the catalog at a rehearsal on this Mac. `Tests/mutation_checks.py`: one mutation (the sheet's line about the catalog missing).
  - `AGENTS.md`: how the catalog is built and tested. `docs/PRIVACY.md`: the catalog's connections, and what listing means.
- **2026-10-12**: Tools that run as their own programs, the words: 21 of the 644 texts in other languages corrected after a second reading by a model, none by a speaker (`Core/ExternalToolStrings.swift`, a VitruvianSoftware file). Turkish, Portuguese, Spanish, German, French, Slovak, Russian, Ukrainian and the three Chinese sets; the English and the placeholders are unchanged. No text on the two buttons that remove a tool changed. The spec's section 15 now records which checks by hand were run on the released app, and which were not.
- **2026-10-12**: Tool platform: picking a command that just stopped being runnable is never silent. The command bar and the radial menu leave out a command that cannot run, but each is made when it opens; a tool that then said the command cannot run, stopped, was switched off or was removed left a row or slice that could be picked once, and nothing happened. Now such a pick runs nothing and plays the alert sound, as a shortcut already did for a command that cannot run. No text is new. The row or slice stays until the surface is opened again: neither follows the registry while open.
  - `Services/CommandBar/CommandBarCatalog.swift`: `toolEntries` takes what to do when a row's command did not run, the alert sound by default, and a row calls it when `ToolRegistry.run` says no.
  - `Services/RadialMenu/RadialMenuService.swift`: a command slice runs through a static function, `run(_:registry:refuse:)`, that takes its registry and what to do when the command did not run; a built-in tool slice that cannot run now plays the alert sound too instead of returning in silence.
  - `Tests/ToolPlatformTests.swift`, `Tests/mutation_checks.py`: six checks in the `platform` suite, 781 to 787, and two mutations (a bar row, and a wheel slice, picked in silence). Nobody has heard the sound in the app.
- **2026-10-12**: Tools that run as their own programs: a tool's detail opens with the keyboard on Close. The detail lists the tool's own settings first, so with "Keyboard navigation" on in System Settings macOS put focus on the first of them as the detail opened, and Space would turn a tool's switch and tell the tool. `UI/Settings/ExternalToolsSection.swift` (written by VitruvianSoftware): `ExternalToolDetail.initialFocus` says where the keyboard starts, Close; the view binds every control of the detail to one focus (`ExternalToolDetail.Focus`) and moves the first focus macOS gives it there, once, as the agreement sheet does. A setting's field now reads "the keyboard left me" from that same focus. Every field and switch is still reached with Tab; the layout and every text are as before. `bazel/source_lints.py` (written by VitruvianSoftware): a rule, `a_tools_detail_places_its_focus`. `Tests/mutation_checks.py`: one mutation (the detail opens with its first setting focused). `AGENTS.md` and the spec's check by hand 40 say so. No test presses a key, and nobody has seen this in the app: only the check by hand proves it.
- **2026-10-12**: Tools that run as their own programs, a safety fault closed: the agreement sheet opens with the keyboard on Cancel. With "Keyboard navigation" on in System Settings, macOS put focus on the sheet's first button, the one that agrees, so Space added or updated the tool though Return and Escape cancel; found by pressing Space in 3.41.0 on macOS 27. `UI/Settings/ExternalToolAgreementSheet.swift` (written by VitruvianSoftware): `ToolAgreementContent.initialFocus` says where the keyboard starts, Cancel, for an offer to add and one to update; the view binds both buttons to a focus state and moves the first focus macOS gives it there, once. Setting the focus as the view appears, `defaultFocus` and `prefersDefaultFocus` were each tried in a scratch program on macOS 27 and each left the agreeing button focused. The agreeing button is still reached with Tab; the layout and every text are as before. `bazel/source_lints.py` (written by VitruvianSoftware): a rule, `the_agreement_sheet_places_its_focus`. `Tests/mutation_checks.py`: one mutation (the sheet opens with its agreeing button focused). `AGENTS.md` and the spec's checks by hand say so (check 8 presses Space; checks 26 and 27 corrected to what was built). No test presses a key: only the check by hand proves it.
- **2026-10-12**: Tool platform, a loose end closed: ending a tool also ends the programs it started. The kill reached the tool's own process alone, and nothing ended what a tool left running when it exited by itself, crashed, or was stopped for being idle; a helper could go on writing into a data folder the person had asked to be deleted. Every file changed was written by VitruvianSoftware and has no upstream header, but `Tests/mutation_checks.py`. How a tool is started did not change: `Foundation.Process`, with no spawn attribute of the app's own, so a tool has the app's macOS permissions exactly as before.
  - `Services/Platform/External/ProcessTransport.swift`: macOS starts a `Process` in a process group of its own, and `Process.terminate` already signals that group. The transport looks at the child once it runs, and only when it sees the child lead its own group (`ToolProcessGroup.led`) the kill signals the group, and when the tool's process is gone and collected, what is left of the group is killed, once (`sweep`). It never signals group 0 or 1, the app's own group, or one the child is merely in; a tool it did not see lead a group is killed alone, as before. `isRunning` stays true until the sweep is done.
  - `Tools/ToolFixture.swift`: three commands that start a helper, which writes a count into a file every two milliseconds: one that ends when asked, one that ignores being asked, one that leaves the tool's group.
  - New checks in `Tests/ToolProcessTests.swift` (`whichGroup`, `helpersEndWithTheirTool`, `helpersAreAskedThenKilled`, `helpersOutOfReach`) and `Tests/ExternalToolStoreTests.swift` (`aRealToolWithAHelper`: Remove, switch-off, quit). `tool-runtime` goes from 622 checks to 654.
  - `Tests/mutation_checks.py` (upstream file): five mutations (the kill does not reach the group; what a tool left running outlives it; a group the tool does not lead is signalled; the app's own group may be signalled; a group is swept while a process has its leader's id).
  - `packages/vitruvian-sdk` (MIT): `vitruvian-tool run` ends a tool the same way (`ToolFamily` in `Sources/VitruvianToolCLI/Session.swift`, written there and not copied from here), with one new test; the guide says what a tool must not assume about a program it starts.
  - `AGENTS.md` and the spec say so, with what stays out of reach; the spec's list of checks by hand gains two, one of them that a tool still reads the front window's title.
- **2026-10-12**: Tool platform, a loose end closed: a running tool is told when the app's language changes. The protocol had `language/changed` and the app never sent it, so a tool kept the language it was started in. Every file changed was written by VitruvianSoftware and has no upstream header, but `Tests/mutation_checks.py`. No file under `packages/vitruvian-sdk/Sources/VitruvianToolProtocol` changed, so the pin stands.
  - `Services/Platform/External/ExternalToolStore.swift`: hears each change of `L10n.shared.language` (`watch`, `Parts.watchLanguage`) and sends every tool that is running the notice, once (`languageChanged`). A tool that is resting, stopped, switched off or held back is sent nothing and is not started.
  - `Services/Platform/External/ToolLink.swift`: a link remembers the language its tool was last told. The same one is not sent again, and a tool greeted in a language that changed before it answered `initialize` is told the new one once it has.
  - New checks in `Tests/ExternalToolStoreTests.swift` (`languageChanges`) and `Tests/ToolLinkTests.swift`; `Tests/ExternalToolSettingsTests.swift` hands out the protocol's example of any message. `tool-runtime` goes from 606 checks to 622.
  - `Tests/mutation_checks.py` (upstream file): three mutations (a running tool not told; one greeted in a language that changed never told; the same language sent again).
  - `AGENTS.md`, the spec, the protocol's README and the guide no longer say the app never sends it; the spec's list of checks by hand gains one.
- **2026-10-12**: Tool platform, a loose end closed: the person is told when a removed tool's files could not be deleted. With the tool's program gone, a folder that could not be deleted (read-only, or a file in use) was a line in the system log, and removing answered "deleted". Every file changed was written by VitruvianSoftware and has no upstream header, but `Tests/mutation_checks.py`.
  - `Services/Platform/External/ExternalToolStore.swift`: `Removal` gains `notDeleted(folders:)`, each folder that is still there, the app's copy first (`ToolFolders.undeleted`, new in `ToolFolders.swift`). `deleted` now means nothing is left. A tool's preferences are deleted only together with the folder of what it saved; before, they were deleted although that folder stayed. A program that would not stop is still answered as kept.
  - `UI/Settings/ExternalToolsSection.swift`: the alert added for kept data says it too, with its own title and sentence, each folder on a line of its own, and the same Reveal in Finder button, which now shows every folder named (`ToolRemovalNotice.reveals`).
  - `Core/ExternalToolStrings.swift`: two new texts in all fifteen languages, `removeUndeletedTitleFormat` and `removeUndeletedMessage`, 46 in all.
  - New checks in `Tests/ExternalToolStoreTests.swift` (`saysWhatCouldNotBeDeleted`, over read-only folders under the temporary folder, with a relaunch) and `Tests/ExternalToolScreensTests.swift` (`undeletedAfterRemoval`); `Tests/ExternalToolStringsTests.swift` counts 46. `tool-runtime` goes from 591 checks to 606.
  - `Tests/mutation_checks.py` (upstream file): three mutations (a folder that could not be deleted is said to be deleted; nobody is told; settings deleted while the folder stays), and three that quote the changed lines follow them.
  - `AGENTS.md`, the spec and the guide in `packages/vitruvian-sdk/docs` say what happens to a tool's settings when its folder is kept; the spec's list of checks by hand gains one.
- **2026-10-12**: Tool platform, a loose end closed: a tool that is no longer there gives its shortcut keys back. The shortcut a person gave a tool's command stayed saved when the tool was removed, registered no key, and still refused the same keys to every other command, with no row left to clear it on. Every file changed was written by VitruvianSoftware and has no upstream header, but `Tests/mutation_checks.py`.
  - `Services/Platform/ToolCommandShortcuts.swift`, `ToolShortcutRegistrar.swift`: only the shortcut of a command that is here and asks for one holds its combination (`held`, `heldShortcuts`). One whose tool is switched off, or not registered this launch, stays saved, holds no key and blocks nobody, and is a key again when the tool returns. If its keys were given to another tool command meanwhile, its entry and its take-over go: one combination, one owner. `forget(_:)` clears the shortcuts and take-overs of a removed tool's commands. The limit of 64 still counts everything saved.
  - `Services/ShortcutConflicts.swift`: the roles, window-layout actions and Command Bar rows are refused a combination only by a tool command that is here. `UI/Settings/ToolCommandShortcutRow.swift`: the row's rule takes what is held beside what is saved.
  - `Services/Platform/External/ExternalToolStore.swift`: Remove clears the shortcuts of the tool's commands, whether or not what the tool saved is kept (`Parts.forgetShortcuts`). Switching a tool off and updating it clear nothing.
  - Expectations changed on purpose, in `Tests/ToolPlatformTests.swift`: a command that is not registered no longer holds its combination (`shortcutConflicts`, `shortcutRegistrar`, `shortcutRowDecision`), and `shortcutRowState` now puts the holder in the registry. New: `shortcutRegistrarAbsentCommand`, `shortcutRegistrarForgetsATool`, and `shortcutsOfARemovedTool` in `Tests/ExternalToolStoreTests.swift`. `platform` goes from 766 checks to 781, `tool-runtime` from 581 to 591.
  - `Tests/mutation_checks.py` (upstream file): two mutations (a removed tool keeps its shortcuts; a saved shortcut whose command is not here still takes its keys), and the one that takes the tool-command holder away is renamed to say that.
  - Known and accepted: when a role, a window-layout action or a Command Bar row was given the keys while the tool was away, both stay saved, the one that registers first has the key, and the returning command's row says its key is unavailable. That is the rule Command Bar rows already had.
- **2026-10-12**: Tool platform, a loose end closed: a command that is listed and cannot run now looks and acts unavailable on the Quick panel. A registry command stays on the panel while its tool says it cannot run, or while the tool's program is stopped after a crash; its tile looked like any other and did nothing when picked. The command bar and the wheel already leave such a command out, each for a reason its code states, and are unchanged.
  - `Services/QuickTools/QuickLauncherService.swift` (upstream file): `isUnavailable(_:)` says a tile is listed and cannot be run now. It is never true while the grid is edited, and never for one of the app's own tiles.
  - `UI/QuickLauncher/QuickLauncherView.swift` (upstream file): such a tile is a disabled button, so SwiftUI dims it as it dims every disabled button of the app and it takes no click; it shows no hover and the pointer does not select it. No colour and no text was added. The tile keeps its place, so the grid and the digits 1 to 9 do not move.
  - `Tests/QuickLauncherActionTests.swift` (upstream file): seven checks in the `launcher` suite; the test world counts how often the panel was closed. `Tests/mutation_checks.py` (upstream file): two mutations (the tile looks like one that can run; it is run all the same).
  - `AGENTS.md` says where each surface stands; the spec's list of checks by hand gains one.
- **2026-10-12**: Tools that run as their own programs, a known gap closed: a tool's own settings have a screen. Every file changed or added was written by VitruvianSoftware and has no upstream header, but `Tests/mutation_checks.py`.
  - `Core/Platform/ExternalToolManifest.swift`: the title a manifest gives a preference is kept, in every language (`preferenceTitles`). A preference with no title is kept as before and has none.
  - `Services/Platform/Broker/StorageAccess.swift`: text saved by key is at most 4,096 characters, the protocol's `StorageLimits.maxTextLength`, so the file now imports `VitruvianToolProtocol`; a longer one is refused (`StorageProblem.tooLong`), which `Services/Platform/External/ExternalToolCalls.swift` answers a tool's `storage/set` with as -32602. A preference a tool saved had no limit but the 1 MB line. `Services/Platform/ToolServices.swift`: builds the same `StorageAccess` through a new initializer; no behaviour changes.
  - `Services/Platform/External/ExternalToolStore.swift`: `settings(of:)` lists the titled preferences of an added tool with their saved values, and `setSetting(_:for:of:)` saves one where the tool itself does and then sends a running tool the protocol's `preferences/changed`, which the app had never sent. A tool that is not running, or has not answered `initialize`, is sent nothing and is not started.
  - `UI/Settings/ExternalToolsSection.swift`: a tool's detail lists its settings first, under the app's existing word "Settings" (`panelSettings`): a switch, a text field or a number field for each, by its kind (`ExternalToolSetting`). They count among the rows that make the detail's lists scroll. No text of the app was added.
  - New: `Tests/ExternalToolSettingsTests.swift`, in the `tool-runtime` suite (`Tests/TestGroups.swift`). `BUILD`: the unit tests are handed the protocol's example messages (`//packages/vitruvian-sdk:message_examples`), so what the app sends is held to the protocol's own example.
  - `Tests/mutation_checks.py`: five mutations (a setting saved under a bare key; a running tool not told; a preference with no title shown by its id; a tool told before it has answered `initialize`; text of any length saved).
  - `AGENTS.md` and `docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md` say so, and the spec's list of checks by hand gains four.
- **2026-10-12**: The radial menu's editor never shows a command id (issue #3149). A slice of kind "Vitruvian tool" whose tool was switched off or removed showed its saved command id in the Tool pop-up, such as `dev.vitruvian.samples.hello-python/hello`:
  - `UI/RadialMenu/RadialMenuView.swift`: `RadialToolChoice.all` lists a choice nothing can name under the words the wheel already draws for it, `kindTool` ("Vitruvian tool"), in place of the saved text. The choice keeps its own tag, so saving without touching the pop-up leaves the slice pointing where it did. No new text.
  - `Tests/ToolPlatformTests.swift`: the picker's titles for a registered command, a command that is not registered, a built-in tool that is switched off and a tool slice nothing answers to. `Tests/mutation_checks.py`: one mutation (a radial action whose tool is away shows its raw id).
- **2026-10-12**: The tool protocol's sources changed in `packages/vitruvian-sdk` (MIT, written by VitruvianSoftware), and the pin follows (`bazel/tool_protocol.sha256`, 64c68b608608): a preference in a tool's manifest may carry a `title`, text in several languages of at most 60 characters each with no control character (`ToolManifestFile.Preference.title`, `ManifestProblem.preferenceTitleNotWellFormed`), and `StorageLimits.maxTextLength` is the most text `storage/set` saves, 4,096 characters. The protocol's version is still 1: a manifest with no title is read as before. Nothing of the app reads either yet.
- **2026-10-12**: Tools that run as their own programs, a known gap closed: the person is told when what a tool saved was kept. Removing a tool with "Remove and Delete What It Saved" keeps its data folder and its settings when the tool's program is still there after the kill, and until now said nothing. `ExternalToolStore.remove` gives back what happened (`Removal`) in place of true or false, and the card shows one alert after the row has gone, with the folder and a button that shows it in the Finder (`ToolRemovalNotice`, in `UI/Settings/ExternalToolsSection.swift`). `Core/ExternalToolStrings.swift`: two new texts in all fifteen languages, 44 in all. `docs/PRIVACY.md`: the sentence about removing a tool names the exception. Every file changed was written by VitruvianSoftware. `Tests/mutation_checks.py`: two mutations (removing says deleted when it was kept; nobody is told).
- **2026-10-12**: Tools that run as their own programs, a known gap closed: a tool's own words are bounded where the app puts them inside a sentence of its own that has no line limit. A manifest could make the alert that refuses it, the question before a tool is removed, or the short on-screen message carry tens of kilobytes, line breaks, or the characters that turn a line of text round. Each is now one line of at most 120 characters with those characters taken out (`ToolOwnWords.oneLine`, in `Core/Platform/ExternalToolManifest.swift`; used by `UI/Settings/ExternalToolAgreementSheet.swift`, `UI/Settings/ExternalToolsSection.swift` and `Services/Platform/External/ExternalToolStore.swift`, all written by VitruvianSoftware). The agreement sheet's title and its line of versions are held to it too. No text of the app changed. `Tests/mutation_checks.py`: two mutations (a refusal that carries the manifest's words whole; a name that turns the sentence round).
- **2026-10-12**: Tool platform, tools that run as their own programs, stage D (`docs/superpowers/plans/2026-10-12-vitruvian-external-tools-stage-d.md`): a tool's program must be a file. A named pipe or a device where the program should be was taken as a program when it carried the execute permission; it is now refused as no program, which is what the SDK's `vitruvian-tool validate` already said (`Core/Platform/ExternalToolManifest.swift`, written by VitruvianSoftware). Both sides are held to it by a new example folder in `packages/vitruvian-sdk/protocol/examples/folders.json`. `Tests/mutation_checks.py`: one mutation (the check taken out).
- **2026-10-11**: Tool platform, tools that run as their own programs, stage C (`docs/superpowers/plans/2026-10-11-vitruvian-external-tools-stage-c.md`): the screens. A person adds such a tool in Settings, under Features, from a folder, after agreeing on one sheet; the app remembers it, lists it, and can update or remove it. Every new file was written by VitruvianSoftware and has no upstream header. A build with no tool added shows one new card on the Features page and behaves as before in every other way.
  - New: `Core/ExternalToolStrings.swift`, the app's 42 texts about these tools in all fifteen languages, with `Tests/ExternalToolStringsTests.swift`. Nothing shows them yet. `Tests/mutation_checks.py`: one mutation (a sentence left in English).
  - Adding a tool is two steps: `ExternalToolStore.offer(from:)` reads a folder and changes nothing, and `add` takes the person's consent to that offer (new: `Services/Platform/External/ToolOffer.swift`). A picked folder that is a link is followed before it is read or copied. A folder over 256 MB or 10,000 things, and a program macOS has quarantined, are refused before anything is copied (`ToolLimits.swift`, `ToolFolders.swift`). `bazel/source_lints.py`: a new rule, `only_the_agreement_sheet_consents`. `Tests/mutation_checks.py`: four mutations (a folder that changed after it was shown; a link copied as a link; a folder with too many things; a quarantined program), and the quoted line of one older entry.
  - The store remembers: new `Services/Platform/External/ToolRecords.swift` and the file `InstalledTools.json` in the app's support folder, with what the person agreed to. `main.swift`: at launch it brings back the tools the person added (`ExternalToolStore.restore`), in place of the development switch, which is gone with its build define (`BUILD`), its hidden preference and its source rule `a_release_build_adds_no_outside_tool`. A tool has a switch; choosing an added tool's folder again replaces it; a copy that is not what was agreed to is held back. `README.md` and `AGENTS.md` say so. `Tests/mutation_checks.py`: four mutations (a changed copy started at launch; a tool that is off coming back; an unreadable file written over; a later version's file read), one entry reworded, and the development switch's entry removed.
  - Removing a tool deletes the app's copy of it and, when the person says so, what it saved (`ToolFolders.delete`, `ExternalToolStore.remove(_:deletingData:)`). `Tests/mutation_checks.py`: three mutations (what a tool saved deleted when the person kept it; a delete through a link; preferences that outlive what was saved).
  - The person is told once per tool, per run of the app, that a tool stopped working, in the app's short on-screen message, and a tool the app gave up on can be started again (`ExternalToolStore.startAgain`). `Tests/mutation_checks.py`: one mutation (told at every crash).
  - New: `UI/Settings/ExternalToolAgreementSheet.swift`, the sheet that asks before a tool is added or updated, what it says as plain values, and each refusal as a sentence; `Tests/ExternalToolScreensTests.swift`. `BUILD`: `VitruvianUI` depends on `VitruvianToolProtocol`. Nothing presents the sheet yet. `Tests/mutation_checks.py`: two mutations (Return adding the tool; the quarantine command breaking on a quote).
  - Removing a tool waits for its program to be gone before anything is deleted: told goodbye, asked to end after half a second, killed a quarter later (`ToolHost.removeAndSeeOut`, three new `ToolLimits`), and what it saved is kept when the program is still there after the kill. `Tools/ToolFixture.swift`: a new command, `scribble`. `Tests/mutation_checks.py`: two mutations (data deleted while the program still runs; folders deleted without the wait), and the quoted line of one older entry.
  - `UI/Settings/FeatureHubSettings.swift`: the Features page ends with a new card, "Tools from outside" (new: `UI/Settings/ExternalToolsSection.swift`): a row for each added tool with its switch, its detail, and the buttons that add, update and remove. With no tool added it is one line and one button. The row and the detail cut a tool's own words short as the sheet does, the detail's two lists scroll when they are long, and it shows the newest 200 lines of a tool's log, as plain text. Which of the two buttons that remove a tool deletes what it saved is a value the tests check (`ToolRemovalContent.Choice.deletesData`), and so is what follows the folder picker (`ToolPicked`). `Tests/mutation_checks.py`: nine mutations (Start Again offered too early; Return removing the tool; a tool that is held back shown as ready; either removing button doing the other's work; the two carrying each other's words; a held-back tool's switch enabled; the whole log drawn; the detail's lists never scrolling).
  - `docs/PRIVACY.md`: a new section, "Tools you add from outside". The app's promises and its list of network connections cover the app alone.
- **2026-10-10**: Tool platform, tools that run as their own programs, stage B (`docs/superpowers/plans/2026-10-10-vitruvian-external-tools-stage-b.md`): the runtime that starts such a tool, talks to it and stops it. Every file it adds was written by VitruvianSoftware and has no upstream header. No build a person installs behaves differently: only a build made with `--define=vitruvian_external_tools=true` can add a tool.
  - New under `Services/Platform/External/`: `ToolLimits.swift`, `ToolClock.swift`, `ToolLineReader.swift` and `ToolLog.swift` (the numbers that hold a tool in check, the clock they are counted on, a tool's output read into messages, and its log), with `Tests/ToolRuntimeTests.swift` and `Tests/ToolRuntimeSupport.swift`. `BUILD`: `VitruvianServices` depends on `VitruvianToolProtocol`. `Tests/TestGroups.swift`: a new suite, `tool-runtime`. `bazel/source_lints.py`: `the_broker_names_no_tool` also covers `Services/Platform/External/`. `Tests/mutation_checks.py`: two mutations (a log that grows without end; a line over the limit taken for one that is not a message).
  - New: `Services/Platform/External/ToolTransport.swift` and `ToolLink.swift` (one run of a tool's program: the greeting, requests both ways with their deadlines, the goodbye), with `Tests/ToolLinkTests.swift`. `Tests/mutation_checks.py`: three mutations (a protocol version the app did not offer; a request answered twice; a tool that is never killed).
  - `Services/Platform/External/ToolLink.swift`: the limits on what a tool writes (a line too long, lines that are not messages, a flood). `Tests/mutation_checks.py`: two mutations (a flood put up with for ever; work done for a tool over its limit).
  - New: `Services/Platform/External/ProcessTransport.swift` (a tool's program as a child process, its pipes read and written off the main thread), `Tools/ToolFixture.swift` (a tool the tests start as a real process) and `Tests/ToolProcessTests.swift`. `BUILD`: `tool_fixture`, which `unit_tests` is handed in `VITRUVIAN_TOOL_FIXTURE`. `Tests/mutation_checks.py`: three mutations (a program run in the wrong folder; writing on to a tool that does not read; a signal taken for an exit status).
  - New: `Services/Platform/HostedTool.swift` (what the tool host holds) and `Services/Platform/External/ExternalTool.swift` (a tool from outside across runs of its program: started when needed, stopped when idle, held back after a crash), with `Tests/ExternalToolTests.swift`. `Services/Platform/BundledTool.swift`: `BundledTool` refines `HostedTool`, which now declares `start`, `stop`, `run` and `canRun`; no tool changes. `Tests/mutation_checks.py`: four mutations (a tool that crashes for ever; a command offered that the tool said cannot run; a tool that starts with the app stopped for being idle; a removed tool left running).
  - `Services/Platform/ToolHost.swift`: the host also holds tools handed over already made (`add`, `remove`), and at quit waits up to three seconds for their programs to leave. A build with no such tool does not wait and behaves as before. New: `Services/Platform/External/ToolRegistry+ExternalTools.swift`, `Tests/ExternalToolHostTests.swift`. `Tests/mutation_checks.py`: three mutations (a command of a tool that is not installed; a program left running at quit; an outside tool under one of the app's own ids).
  - `Services/Platform/Broker/StorageAccess.swift`: reading and writing a declared preference by its key (`value(for:)`, `set(_:for:)`), for a tool with no `Preference`; `ToolServices.swift` hands it the manifest's defaults. `Broker/CapabilityBroker.swift`: an undeclared capability stops a development build only for one of the app's own tools. New: `Services/Platform/External/ExternalToolCalls.swift` (each request of the protocol done through the broker), `Tests/ExternalToolCallsTests.swift`. `Tests/mutation_checks.py`: three mutations (a preference saved under a bare key; a protected process ended; a preference saved as another kind of value).
  - New: `Services/Platform/External/ToolFolders.swift` (a tool's two folders under the app's support folder) and `ExternalToolStore.swift` (the tools from outside that are installed, held for the life of the app), with `Tests/ExternalToolStoreTests.swift`. A folder that is, through a link, somewhere other than under the support folder is refused, and nothing is copied there. `Broker/CapabilityBroker.swift`: whether a tool whose id has a dot is installed is the store's answer, and an id that names nothing is not installed (it was). `Tests/mutation_checks.py`: three mutations (an id that names nothing counted as installed; the app's copy of a tool copied over itself; a tool added over one that is installed).
  - `main.swift`: in a build made with `--define=vitruvian_external_tools=true`, and in no other, adds the one tool whose folder the hidden preference `developmentToolFolder` names (`ExternalToolStore.installDevelopmentTool`). `BUILD`: the `external_tools` setting; `VitruvianLibWithSampleTool` is compiled with it too. `bazel/source_lints.py`: a new rule, `a_release_build_adds_no_outside_tool`. `Tests/mutation_checks.py`: one mutation (the switch adding a tool nobody named).
- **2026-10-10**: Tool platform, tools that run as their own programs, stage A (`docs/superpowers/plans/2026-10-10-vitruvian-external-tools-stage-a.md`):
  - `Core` now links `VitruvianToolProtocol`, an MIT module in `packages/vitruvian-sdk` that VitruvianSoftware wrote: the tool protocol's messages and the manifest file, with the rules a manifest must keep. Nothing upstream wrote is in it, and it imports nothing of this app. Its Swift sources are pinned in `bazel/tool_protocol.sha256`; `tool_protocol_pin_test` fails when they change and the pin does not.
  - New files, none with an upstream header: `Core/Platform/ExternalToolManifest.swift` (reads a tool's folder into a `ToolManifest`, or a reason it cannot be added), with its tests in `Tests/ExternalToolManifestTests.swift`. Nothing in the app calls it yet, so no build behaves differently.
  - `Core/Platform/ToolManifest.swift`: `CapabilityRequest` gains a second initializer, for a service an outside tool's manifest lists, which has no reason. The one built-in tools use is unchanged.
  - `bazel/pin_nexus_agent_shared.py`: takes `--name`, so it also pins the tool protocol's sources. With no `--name` it does what it did.
  - `BUILD`: `VitruvianCore` and the unit tests depend on the module; `pin_tool_protocol` and `tool_protocol_pin_test`, which the pipeline unit now runs.
  - `Tests/TestGroups.swift`: the `platform` suite also runs `ExternalToolManifestTests`.
  - `Tests/mutation_checks.py`: two mutations (a tool's program that is a link out of its folder; an outside tool held back for a macOS grant).
- **2026-10-10**: Tool platform, the broker, stage C (`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-c.md`):
  - New files, none with an upstream header: `Core/Platform/MenuKeyEquivalent.swift` (a menu item's key equivalent, as a value), `Services/Platform/Broker/FrontAppMenu.swift` (the walk through the front app's menus), `Services/Platform/Broker/HotkeyAccess.swift` (a role's global shortcut), `Services/Platform/Broker/KeystrokesAccess.swift` (a paste and a menu press), `UI/Settings/PastePlainSettingsSection.swift` (the tool's section of the Clipboard page), with their tests in `Tests/PastePlainTests.swift` and `Tests/ToolBrokerTests.swift`. `Services/TransientPaste.swift` was not changed.
  - `Services/QuickTools/PastePlainService.swift`: takes what it reaches outside itself (the saved preferences, its hotkey, Accessibility, the beep, the paste helper) as an `Environment`, so a press can be tested. Its walk through the front app's menus moved to `Services/Platform/Broker/FrontAppMenu.swift`, where it reads a menu bar through values, and its read of the clipboard's plain text moved, word for word, to `Services/Platform/Broker/ClipboardWatcher.swift`. Nothing it does changed.
  - `Core/QuickTools/QuickToolsSupport.swift`: `isMatchStyleEquivalent` is defined by a value, `matchStyleEquivalent`, that says the same key equivalent. Its answers are unchanged.
  - `Tests/ClipboardFeatureTests.swift`: the check that Paste as plain text reads on the clipboard lane calls the read where it lives now. Its expectations are unchanged.
  - `UI/Settings/ClipboardSettings.swift`: the Paste as plain text section moved, unchanged, to a view of its own, `UI/Settings/PastePlainSettingsSection.swift`, which the page shows in the same place and hands the Accessibility grant. An upstream change to that section no longer applies here: apply it by hand in the new file.
  - `Services/QuickTools/PastePlainService.swift`: Paste as plain text is a tool. It has a manifest and one command, is built by the tool host with the services that manifest allows, and holds its shortcut, asks for Accessibility, reads the clipboard, presses a menu item, pastes and beeps only through the broker. Its singleton, its hotkey and the `Environment` this entry added above are gone. Hotkey id 10 is now made in `Services/Platform/Broker/HotkeyAccess.swift`.
  - `Services/CommandBar/CommandBarCatalog.swift`: the "Paste as plain text" row runs the tool's command through the registry, after the same delay. It keeps its id.
  - `Services/FeatureRuntime.swift`: Paste as plain text's arm hands it to the tool host; its own binding action is gone.
  - `Services/SelfUninstall.swift`: a full uninstall lets go of Paste as plain text's shortcut through the tool host.
  - `bazel/source_lints.py`: Paste as plain text's two files join `MIGRATED_TOOLS`.
  - `Tests/mutation_checks.py`: five mutations (a capability used without the grant it rides on; the host waiting for a grant a tool starts without; a paste pressing the tool's own shortcut; the menu walk pressing a switched-off item; a press without Accessibility asking every time).
  - `Services/QuickTools/PastePlainService.swift`: `import ApplicationServices` is gone. Nothing in the file names Accessibility any more.
- **2026-10-10**: Tool platform, the broker, stage B (`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-b.md`):
  - New files, none with an upstream header: `Services/Platform/Broker/StorageAccess.swift` (a tool's preferences), `Services/Platform/Broker/ClipboardRewrite.swift` (one look at the clipboard), `Services/Platform/Broker/ClipboardWatcher.swift` (the one timer that looks, for the tools that ask), `Services/Platform/BundledTools.swift` (the list of tools), with their tests in `Tests/ToolBrokerTests.swift` and `Tests/URLCleanerTests.swift`.
  - `Services/URLCleanerService.swift`: takes what it reaches outside itself (the saved preferences, the clipboard lane, the pasteboard, its timer) as an `Environment`, so its timer and its copy can be tested. Nothing it does changed.
  - `Services/URLCleanerService.swift`: one look at the clipboard and the write that follows it moved, word for word, to `Services/Platform/Broker/ClipboardRewrite.swift`. The cleaner hands the look its three decisions (which types it touches, what a link becomes, whether the HTML may go) as a rule.
  - `Services/FeatureRuntime.swift`: one binding action, `tool`, hands a feature that has become a tool to the tool host. `FeatureBindingAction` is no longer `CaseIterable`; nothing read the list.
  - `Services/PortManager/PortManagerService.swift`: says it has nothing to start and no command, now that the tool interface asks.
  - `Services/URLCleanerService.swift`: the URL cleaner is a tool. It has a manifest and one command, is built by the tool host with the services that manifest allows, and reads its rules, reads and rewrites the clipboard and shows its message only through the broker. Its singleton, its timer, its pasteboard code and the `Environment` this entry added above are gone.
  - `UI/Settings/URLCleanerSettings.swift`, `UI/MenuPanel/PanelURLCleanerView.swift`: get the tool from the host, tell the host when the switch flips, and ask the tool for the clipboard's text, where they called the service's singleton and the pasteboard.
  - `Services/CommandBar/CommandBarCatalog.swift`: the "Clean URL" row runs the tool's command through the registry, and the selection row calls the tool. `cleanClipboardURL()` moved into the tool. Both rows keep their ids.
  - `Services/FeatureRuntime.swift`: the URL cleaner's arm hands it to the tool host; its own binding action is gone.
  - `App/AppDelegate.swift`: the URL cleaner's line left the quit list. The tool host stops it, and no longer builds it at quit when it never ran.
  - `Tests/ClipboardFeatureTests.swift`: the link cleaner's four checks call the look where it lives now. Their expectations are unchanged.
  - `bazel/source_lints.py`: the URL cleaner's four files join `MIGRATED_TOOLS`. The rule now reads `@AppStorage(Preferences.x)`, and fails when a key a tool's views may bind is not declared by its manifest, or is not spelled alike in `DefaultsKey` and `Preferences`.
  - `Tests/mutation_checks.py`: four mutations (a rewrite after the clipboard changed under the look; a watch taking its own rewrite for a new copy; a tool reading a preference it did not declare; the host starting a tool that is switched off).
- **2026-10-10**: Diagrams in the Nexus Agent chat are drawn with a copy of Mermaid 11.17.2 shipped in the app (`Contents/Resources/mermaid.min.js`, about 3.6 MB, MIT; see "Third-party code the app ships"), so nothing is fetched from the network and they work offline; before, the script came from a public CDN each time. The diagram's page can no longer load or open anything outside the app. What a user would notice: a diagram that cannot be read now shows the card's "could not draw" message with its source instead of Mermaid's own error picture, and markup or links written inside a diagram are shown as plain text.
- **2026-10-09**: Tool platform, the broker, stage A (`docs/superpowers/plans/2026-10-09-vitruvian-broker-stage-a.md`):
  - New files, none with an upstream header: `Core/Platform/ToolManifest.swift` (what a tool is and which capabilities it asks for) and `Services/Platform/Broker/CapabilityBroker.swift` (the one place that decides whether a tool may use a capability), with their tests in `Tests/ToolPlatformTests.swift` and `Tests/ToolBrokerTests.swift`.
  - `App/AppDelegate.swift`: stops the tools the host built, at quit.
  - `Services/PortManager/PortManagerService.swift`: the Port manager is a tool. It has a manifest, is built by the tool host with the services that manifest allows, and scans, ends a process, copies, opens a link and beeps only through the broker. Its singleton and `Scanning.system` are gone.
  - `UI/PortManager/PortManagerView.swift`, `UI/MenuPanel/PanelPortManagerView.swift`: get the tool from the host, and ask it what may be ended, to copy and to open, where they called `KillProcessService`, the pasteboard and `NSWorkspace`.
  - `bazel/source_lints.py`: `migrated_tools_reach_services_through_the_broker` fails when a file of a migrated tool names a service the broker guards, a singleton other than the tool host and the UI's own state, or another tool's preference, or when a listed file is gone. `the_broker_names_no_tool` fails when a file under `Services/Platform/Broker/` names a tool's type.
  - `Tests/mutation_checks.py`: two mutations (the broker working for a tool that did not ask; ending a process the host does not offer to end).
- **2026-10-09**: Reset and an accepted macOS take-over no longer bind a combination twice:
  - `UI/ShortcutRecorderButton.swift`, `UI/Settings/ShortcutsSettings.swift`, `UI/Settings/WindowLayoutSettings.swift`, `UI/Settings/CutPasteSettings.swift`: each row's three holder checks are one `refusal(for:)`, asked by recording as before and now also by Reset and by accepting a take-over offer. **Reset is refused, naming the holder, when another shortcut took the default meanwhile; so is accepting an offer whose combination was taken while the offer waited.**
  - `UI/ShortcutRecorderButton.swift`: a role row that is handed no extra check asks the window-layout one, so a role recorded on its own feature page can no longer take a window-layout action's combination.
  - `Tests/mutation_checks.py`: one mutation (Reset writing a default somebody else holds).
- **2026-10-09**: This log is checked for being whole:
  - `bazel/source_lints.py`: `modification_log_is_whole` fails when a section of this file is gone or out of order, when the Modifications log has fewer than 260 dated entries, or when a merge conflict marker is left in. A merge resolution had cut 2,600 lines out of the file and every check stayed green.
  - `BUILD`: `source_lints_test` reads `UPSTREAM.md`.
- **2026-10-09**: Tool registry, part 3 (`docs/superpowers/plans/2026-10-09-vitruvian-tool-registry-part-3.md`):
  - `Services/CommandBar/CommandBarRowShortcuts.swift`: the parts that are not about rows (reading, writing, setting, the limit, finding a holder) moved to `Services/ShortcutMap.swift`; every function here keeps its name and signature and calls it.
  - `Core/DefaultsKey.swift`, `Core/Defaults.swift`, `Core/SettingsBackupSupport.swift`: the `toolCommandShortcuts` preference, registered and backed up. (`Core/Preferences.swift` and the tests carry no upstream header.)
  - `Services/ShortcutCapture.swift`: when a recording ends, tool command shortcuts are registered again with everything else.
  - `App/AppDelegate.swift`: registers tool command shortcuts at launch.
  - `UI/ShortcutRecorderButton.swift`, `UI/Settings/ShortcutsSettings.swift`, `UI/Settings/WindowLayoutSettings.swift`, `UI/Settings/CutPasteSettings.swift`, `UI/Settings/RadialMenuSettings.swift`, `UI/Screenshot/ScreenshotToolOrderControls.swift`, `Services/CommandBar/CommandBarService.swift`, `Services/WindowLayout/WindowLayoutService.swift`: every recorder also refuses a combination a Command Bar row or a tool command holds (`Services/ShortcutConflicts.swift`). **This changes what a release build does:** recording a combination a Command Bar row already holds is now refused, with the message the other clashes show. Before this, only the radial menu's editor and the Command Bar's own looked at rows, so a role, a window-layout action, the Finder rename key or a screenshot tool could be given a combination a row already held, and one of the two silently lost. A row of a removed Command Bar does not block, the same as a removed role or window-layout action; if the bar is reinstalled after its row's combination was given away, the first to register wins, and Command Bar settings flags a row that lost. Reset buttons and accepting the macOS take-over offer are not covered by the new check.
  - `UI/Settings/ShortcutsSettings.swift`: a section per tool whose commands ask for a shortcut, headed by the tool's own name, with a row per command (`UI/Settings/ToolCommandShortcutRow.swift`); none with only the app's own tools, so the page of a release build is unchanged.
  - `Tests/mutation_checks.py`: two mutations (a switched-off tool keeping its key; a command that is not registered freeing its combination).
  - `Tests/mutation_checks.py`: the first of those two now expects the check "a shortcut whose command is not registered holds no key", which runs while another command asks for a shortcut, so it fails when the registrar stops passing over a command that does not ask. (The save step of a tool command's row, `ToolCommandShortcutSave.commit` in `UI/Settings/ToolCommandShortcutRow.swift`, and its tests carry no upstream header.)
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
- **2026-10-09**: The app carries the GravaStar mouse command and offers it as an MCP server:
  - `BUILD`: `//packages/peripherals:gravastar-mouse` (MIT) goes into `Contents/Helpers` through `additional_contents`, and the `vitruvian` delivery unit also follows `packages/peripherals/`. `Tools/package-release.sh` signs it with the other nested code.
  - `GitHubMouseBinary.swift`: `locate` tries that copy right after the configured path; `mcpConfig(binary:)` builds the `mcpServers` JSON for `gravastar-mouse mcp`.
  - `GitHubPeripheralSink.swift`: passes the bundle's copy to `locate`.
  - `GitHubSettingsView.swift` and `NotchGitHubStrings.swift`: the Mouse command hint names the copy inside the app, and a Copy MCP Config button copies the JSON for the command found, in every language.
  - `Tests/GitHubCoreTests.swift`: the bundled copy's place in the search order, the MCP JSON and the new label.
- **2026-10-09**: The GravaStar mouse command is found on any Mac, not at one person's home path:
  - `GitHubPeripheralSink.swift`: drops the hard-coded `/Users/james/bin/gravastar-mouse` and resolves the binary on each write through `GitHubMouseBinary.locate` (new, `Core/GitHub/GitHubMouseBinary.swift`): the `githubMouseBinaryPath` preference (`~` expanded), then absolute PATH entries, then `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and `~/bin`. With no binary it still does nothing.
  - Added the `githubMouseBinaryPath` preference (default empty, which searches) to `Preferences.swift`, `DefaultsKey.swift` and `Defaults.swift`, and to `SettingsBackupSupport.machineStateKeys`, since an install path belongs to one Mac.
  - `GitHubSettingsView.swift`: a "Mouse command" field under Hardware & Mouse Lighting, with a Choose… button, a note on where it searches, and the path in use or how to install it. The words are in `NotchGitHubStrings.swift`, in every language.
  - `Tests/GitHubCoreTests.swift`: `mouseBinaryResolution` covers the search order, `~` expansion, the fallback from a configured path that does not run, relative PATH entries, the no-binary case and the new strings.
- **2026-10-08**: Unit tests that pass or fail the same on a Mac in use as on a CI runner:
  - `Tests/RepositoryFeatureTests.swift`: the two checks that run a script against stand-in tools (`Tools/setup-signing.sh`, and `read_sleep_disabled` from `Tools/uninstall.sh`) start zsh with `-f`. Without it zsh reads `/etc/zshenv`, and where that file sets `PATH` (nix-darwin's does) the stand-ins were skipped and the script ran the Mac's real `security`, `codesign` and `pmset`.
- **2026-10-08**: Awaiting-approval GitHub pipeline notification:
  - Added `githubMouseApprovalColor`, `githubMouseApprovalMode`, and `githubMouseApprovalSpeed` preferences to `Defaults.swift` and `DefaultsKey.swift`.
- **2026-10-08**: Tool registry, part 1 (`docs/superpowers/plans/2026-10-08-vitruvian-tool-registry.md`):
  - `Core/RadialMenu/RadialMenuSupport.swift`: `RadialMenuTool.command` names the built-in command each slice runs.
  - `main.swift`: installs the built-in tools and command handlers into `ToolRegistry` before the app runs.
  - `Core/RadialMenu/RadialMenuSupport.swift`: `RadialMenuItem.Kind.command` and `commandID`, a slice that runs any registry command by id.
  - `Services/RadialMenu/RadialMenuService.swift`: tool slices run through `ToolRegistry` instead of a private switch; a `command` slice whose command cannot run is left off the wheel.
  - `UI/RadialMenu/RadialMenuView.swift`, `UI/Settings/RadialMenuSettings.swift`, `UI/Settings/RadialMenuVisualCanvas.swift`: arms for the `command` kind.
  - `Services/QuickTools/QuickLauncherService.swift`: `QuickLauncherItem.command`; the live `perform` runs it through `ToolRegistry` instead of a private switch.
  - `Services/CommandBar/CommandBarCatalog.swift`: `toolEntries` adds a row for each registry command that asks for the bar; none of the app's own commands do.
  - `Tests/mutation_checks.py`: two mutations for the registry wiring (a radial slice mapped to another tool's command; a switched-off tool that still runs).
  - `Services/CommandBar/CommandBarCatalog.swift`: `toolEntries` offers only commands that can run now, and files each row under its tool's localised name.
- **2026-10-08**: Zero-click GitHub CLI sign-in, Keychain-less sign-in and LED reconcile on launch:
  - `GitHubAuthService.swift`: `syncWithPreferences()` signs in with the GitHub CLI login (`~/.config/gh/hosts.yml`) when nobody is signed in and no token is saved, except after an explicit `disconnect()` this session or for a token GitHub already answered 401 to. `finishSignIn` keeps the token in memory when the Keychain refuses to save it (ad-hoc builds lack the entitlement) instead of failing the sign-in. The `hosts.yml` location is an initializer parameter (`cliHostsURL`) so tests use their own file.
  - `GitHubPeripheralSink.swift`: `update(verdict:force:)` writes even an unchanged verdict when forced; an injectable `Executor` stands in for the mouse binary in tests.
  - `GitHubService.swift`: the first completed poll after launch or sign-in forces the mouse LED write, since the mouse keeps its last LED state across app restarts.
  - `Tests/GitHubCoreTests.swift`: behavioural tests for CLI auto-connect, its disconnect and 401 guards, Keychain-less sign-in and the forced LED write.
- **2026-10-08**: Dedicated GitHub pipeline metrics tile in Notch Quick Access and resting wing:
  - Added `.github` module to `NotchModule` with symbol `"arrow.triangle.branch"`, shortcut `⌥⌘H`, feature availability mapping, and editor catalog descriptions.
  - Implemented `NotchGitHubView.swift` providing header bar (repo selector badge, branch & SHA pill, refresh action, web link) and metrics cards (Workflow Runs, Merge Queue, Open Pull Requests with check rollup progress).
  - Routed `.github` in `NotchView.swift` and `NotchContentEditor.swift`.
  - Added live pipeline activity indicators to `NotchRestingWing` in `NotchAgentStrip.swift` (green checkmark for clean `main`, amber breathing spinner during presubmits, red alert glyph on failing checks).
- **2026-10-08**: Telemetry accuracy fixes: parse Connect-RPC Antigravity quota and plan-wide limits:
  - Fixed `AgentAntigravityReader.swift` to parse Connect-RPC `{"response": {"groups": [...]}}` responses from local `language_server`.
  - Set `gemini-weekly` and `gemini-5h` primary limit scopes to `nil` so plan-wide focus and `NotchAgentLimitsCard` correctly display both session and weekly quota.
- **2026-10-08**: Performance optimization: throttled Antigravity quota probing and telemetry file stat caching:
  - Cached `stat()` checks for `.telemetry_state.json` and `conversation_summaries.db` in `AgentAntigravityReader` to avoid redundant file I/O and JSON parsing on the 2-second polling loop.
  - Cached language server daemon connection (`pid`, `port`, `token`) with `kill(pid, 0)` liveness check to avoid continuous `ps` and `lsof` process spawns.
  - Decoupled live quota probing from the 2-second poller to a 25-second throttle window, triggered on launch, Notch view appear, and 30-second timer ticks.
- **2026-10-08**: AI Agents title reversion and Antigravity telemetry integration:
  - Reverted the Notch AI agent title from "Nexus Agent" back to "AI Agents" across `NotchAgentStrings.swift` and tests.
  - Added `.antigravity` provider to `AgentProvider`, preferences (`notchAgentsAntigravity`), Notch UI, and settings.
  - Added pricing support for Gemini models (`gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-3.5-flash`, `gemini-3-pro`, `gemini-3.5-pro`) and `Gemini` display name formatting in `AgentPricing.swift`.
  - Added `AgentAntigravityReader.swift` reading `.telemetry_state.json` and `conversation_summaries.db`, plus live quota probing of the local `language_server` via `RetrieveUserQuotaSummary`.
  - Integrated Antigravity reading and quota polling into `AgentUsageService` and `AgentLogRoot`.
- **2026-10-02**: Imported. Added `BUILD`, `bazel/`, `UPSTREAM.md`,
  `README.md` and `AGENTS.md`. In `.gitignore`, dropped the `AGENTS.md` entry so
  the nested agent guide can be committed. Replaced the reserved brand artwork
  in `Resources/Brand/` with generated placeholders.
- **2026-10-02**: Renamed to Vitruvian (see "Trademarks and release blockers"):
  - names, bundle IDs, module and source paths (`Sources/Vorssaint` became
    `Sources/Vitruvian`), keys and namespaces;
  - upstream servers, feeds and community links replaced or disabled;
  - `BundleMigration.swift` deleted, and the legacy-app cleanup in `build.sh` and
    `Tools/uninstall.sh` dropped;
  - tests that pinned upstream's links and support prompt updated.

  Copyright notices, `LICENSE`, `TRADEMARKS.md` and `CHANGELOG.md` are unchanged.
- **2026-10-02**: Refactor step 1 (`REFACTOR.md`):
  - `FeatureRuntime`'s bindings dictionary became an exhaustive switch, adding
    the missing `connectedDevices` binding;
  - `AppDelegate`'s permission re-sync lists now come from
    `AppFeature.dependents(on:)`;
  - tests updated.
- **2026-10-03**: Refactor step 2 (`REFACTOR.md`):
  - `DockAutohideHold.recoverIfNeeded()` runs at launch from `AppDelegate`;
  - `applicationWillTerminate` documents the calls that must stay
    unconditional;
  - `DockAutohideHoldTests` extended.
- **2026-10-03**: Refactor step 3, first module (`REFACTOR.md`):
  - `Core/` builds as the `VitruvianCore` module, and its declarations are
    `package`;
  - `DefaultsKey` moved out of `Core/Defaults.swift`;
  - `KeepAwakeAutomationSupport.swift` and `ScratchpadSupport.swift` moved to
    `Core/`;
  - app and test files import `VitruvianCore`;
  - `build.sh` lists the moved files;
  - `Tests/generate_sources.py` tolerates `package`;
  - `RepositoryFeatureTests` French check hardened.
- **2026-10-03**: Refactor step 3.1b (`REFACTOR.md`):
  - 50 `*Support` and model files moved from `Services/` to `Core/` (same
    subfolders), and `FanControlSupport.swift` and
    `TemperatureSensorSelector.swift` to `FanControlKit/`;
  - `AirPlayRouteManager.airPlaySentinelUID` now aliases
    `MixerRoutingSupport.airPlaySentinelUID`;
  - explicit `package` initializers added to the structs and classes the
    module exports;
  - `import FanControlKit` added to `Sources/FanControlHelper/main.swift`
    and the three files the helper shares with the app;
  - `build.sh`, `Tests/mutation_checks.py` and four test files point at the
    new paths.
- **2026-10-03**: Refactor step 3.1c (`REFACTOR.md`):
  - the `NSScreen.displayID` extension moved from
    `Services/QuickTools/ScreenshotCaptureEngine.swift` into
    `Core/AppKitExtensions.swift`, whose members are now `package`;
  - `Permissions.swift` and `SecureInputMonitor.swift` moved from `Core/` to
    `Services/`.
- **2026-10-03**: Refactor step 3.2a (`REFACTOR.md`):
  - `App/FeatureRuntime.swift` and `App/AppAppearanceController.swift` moved
    to `Services/`, and `App/MenuBarRenderer.swift` to `Services/MenuBar/`;
  - `App/MenuBarSpacingSupport.swift`, `App/MenuBarAllowanceSupport.swift` and
    `App/StatusItemAnchorSupport.swift` moved to `Core/MenuBar/`, and
    `App/ReopenRequestSupport.swift` to `Core/`: their declarations are now
    `package`, without the self-import, and `MenuBarUsageBarSupport.RGB` and
    `ReopenRequestSupport.Sender` spell out their memberwise initializers;
  - `BlackHoleGlyph` moved from `App/StatusItemController.swift` into the new
    `UI/BlackHoleGlyph.swift`. Its one-time read of the bundled PNGs moved from
    a closure into `loadBase()`, so the repository check against file reads in
    view code, which covers `UI/` only, sees that the read happens in a
    function;
  - `build.sh`, `Tests/generate_sources.py` and three test files point at the
    new paths, and a comment in `Tools/MakeIcon.swift` names the glyph's new
    file.
- **2026-10-03**: Refactor step 3.2b (`REFACTOR.md`):
  - `UI/Settings/FeatureVisibilitySupport.swift`, `SettingsSearchSupport.swift`
    and `SettingsSidebarSupport.swift` moved to `Core/Settings/`. Their
    declarations are now `package`, without the self-import, and seven structs
    spell out their memberwise initializers.
  - `UI/Settings/SettingsDirectory.swift` moved to `Services/Settings/`.
  - `PermissionKind` moved from `UI/Settings/SettingsView.swift` into the new
    `Core/PermissionKind.swift`, now `package`.
  - `appDelegate()` was removed from `UI/Theme.swift`. Its calls, and every
    `NSApp.delegate as? AppDelegate` under `Services/` and `UI/`, now call
    `appShell()` (20 files).
  - `Services/Permissions.swift` shows the permission guide through it.
  - `SettingsWindow` conforms to `SettingsHistoryNavigating`. Its
    `navigationItem(for:in:)` now calls `MouseNavigationKeys.settingsItem`,
    which holds the menu lookup and finds the items by the protocol's
    selectors.
  - `StatusItemController.MetricStatusGroup` and `metricStatusGroups(for:strings:)`
    moved into `Services/MenuBar/MenuBarRenderer.swift`, and
    `UI/MenuBarMetricsPreview.swift` reads them there.
  - Five test contracts stub `appShell()` instead of the app delegate.
  - `build.sh` and `Tests/RecorderFeatureTests.swift` point at the new paths.
- **2026-10-03**: Refactor step 3.2c-1 (`REFACTOR.md`):
  - `UI/OverlayPanel.swift`, `UI/NonModalAlert.swift`, `UI/PlainTextEditor.swift`
    and `UI/MenuPanel/MixerPercentNativeTextField.swift` moved to the new
    `Design/`.
  - `HUDBackdrop` moved from `UI/SharedUI.swift` into `Design/HUDBackdrop.swift`.
  - `Theme` moved from `UI/Theme.swift` into `Design/SpaceGradient.swift`.
    The doc line it carried, which describes the whole file, stays in
    `Theme.swift` as a plain comment.
  - `UI/MenuPanel/PanelInteractionState.swift` moved to `Services/`.
  - `BackdropEditing` moved from `UI/Screenshot/ScreenshotBackdropPopover.swift`
    into `Services/QuickTools/BackdropEditing.swift`.
  - `BreakdownKind` moved from `UI/MenuPanel/SystemSection.swift` into
    `Services/SystemMonitor/BreakdownKind.swift`.
  - `build.sh` and `Tests/generate_sources.py` point at the new paths.
- **2026-10-03**: Refactor step 3.2c-2 (`REFACTOR.md`):
  - 17 service sites that built a SwiftUI view now ask
    `ServiceViews.factory`:
    - `AppSwitcher`, `SnippetLibraryService`, `ShelfService` (two),
      `ScreenshotEditorController`, `ScratchpadService`,
      `RecorderEditorController`, `RecentCaptureService`, `RadialMenuService`,
      `QuickLauncherService`, `DockPreviewService` (two), `FinderCutPaste`,
      `CommandBarService`, `ClipboardHistoryService`, `CleaningModeManager`
      and `CameraPreviewService`;
    - `CleaningModeManager`'s hosting view is now `NSHostingView<AnyView>`.
  - `main.swift` installs the factory after `Defaults.register()`.
  - `UI/QuitProtection/QuitProtectionHUD.swift` and
    `UI/Shelf/ShelfTooltipPopover.swift` moved to `Services/`.
  - `RecorderZoomLane.Kind` and `.Item` moved into
    `Services/Recorder/RecorderLane.swift` as `RecorderLaneKind` and
    `RecorderLaneItem`, and the view keeps typealiases.
  - `PanelOrderItem`, `PanelSectionID` and `PanelLayout` moved from
    `UI/MenuPanel/PanelLayout.swift` into
    `Services/MenuPanel/PanelLayoutStore.swift`.
  - `Tests/generate_sources.py` and three test files point at the new paths.
- **2026-10-03**: Refactor step 3.2d (`REFACTOR.md`):
  - Moved to `Services/`, unchanged except where noted:
    - `NotchLockScreenModel`, from `UI/Notch/NotchLockScreenView.swift`;
    - `MenuPanelFocus`, `MenuPanelFocusRequest` and `MenuPanelFocusTarget`,
      from `UI/MenuPanel/MenuPanelView.swift`;
    - `MetricDetailKind`, from `UI/MenuPanel/MetricDetailView.swift`;
    - `NotchCompactMusicSnapshot`, from `UI/Notch/NotchMusicStrip.swift`;
    - `NotchQuickAccessMotion`, from `UI/Notch/NotchQuickAccessView.swift`;
    - `NotchBackdropPresentation`, from `UI/Notch/NotchComponents.swift`. Its
      `contourBottom` is now internal, because the view left in that file
      reads it.
  - Moved to `Design/`:
    - `NotchShape`, from `UI/Notch/NotchView.swift`;
    - `NotchButtonStyle`, from `UI/Notch/NotchComponents.swift`;
    - `ShelfSharePickerAnchor`, from `UI/Shelf/ShelfView.swift`;
    - `UI/Shelf/ShelfSharePresenter.swift`.
  - `MediaWorkspaceView.panelModalActive` and `runPanelModal` moved into
    `Services/Media/MediaPanelModal.swift`, now callable by the view, and the
    view and `NotchService` call them there.
  - `NotchService` and `NotchLockScreenService` build their seven views
    through `ServiceViews.factory`.
  - `Tests/generate_sources.py` reads the moved declarations from their new
    files.
- **2026-10-03**: Refactor step 3.2e-1 (`REFACTOR.md`):
  - The files under `Design/` became the `VitruvianDesign` module. Their
    declarations are now `package`.
  - `HUDBackdrop`, `NotchButtonStyle`, `NotchShape` and
    `ShelfSharePickerAnchor` (and its `Anchor`) spell out their initializers.
  - `OverlayPanel` is `open` and its override `public`, so services can
    subclass it from their module. `Tests/generate_sources.py` no longer
    copies it into the test binary, and `OverlayPanelTests` says so.
  - Every app and test file that imports `VitruvianCore` also imports
    `VitruvianDesign`.
- **2026-10-03**: Refactor step 3.2e-2 (`REFACTOR.md`):
  - The files under `Services/` became the `VitruvianServices` module. Their
    declarations are now `package`; 149 structs spell out their memberwise
    initializer, and 32 structs and classes `package init() {}`.
  - `NotchMusicAutomationCapabilities.Event` and `.Position` declare their
    second property `package` too, and `Event` moved onto several lines to
    spell out its initializer.
  - `AppFeature.hubTitle`/`hubDescription` moved from
    `UI/Settings/FeatureHubSettings.swift` to the new
    `Services/Settings/FeatureHubText.swift`; `MenuBarMetric.detailKind` from
    `UI/MenuPanel/MetricDetailView.swift` to `MetricDetailKind.swift`;
    `Notification.Name.menuPanelWillShow` from `UI/MenuPanel/MenuPanelView.swift`
    to `MenuPanelFocus.swift`; `NotchModule.title` from `UI/Notch/NotchView.swift`
    to `Core/Notch/NotchSupport.swift`; `View.screenshotSafeHelp` from
    `UI/Screenshot/ScreenshotEditorView.swift` to the new
    `Design/ScreenshotSafeHelp.swift`.
  - Every `UI/`, `App/`, `Support/` and test file imports `VitruvianServices`.
  - `Tests/generate_sources.py` reads production sources without their
    `package` modifiers, drops the `NotchModule.title` and
    `NotchActivationButton` copies, and reads `detailKind` from its new file.
  - Six source-text checks that split a file at `    func name` now split
    at `    package func name` (`RepositoryFeatureTests`,
    `ScreenshotFeatureTests`, `ShelfFeatureTests`, `UtilitiesFeatureTests`).
- **2026-10-03**: Refactor step 3.2e-3 (`REFACTOR.md`):
  - The files under `UI/` became the `VitruvianUI` module. Their declarations
    are now `package`; `SettingsWindow` is `open` with `public` overrides, and
    the views the app, the probes and the tests build spell out their
    initializers.
  - Every `App/`, `Support/`, `main.swift` and test file imports
    `VitruvianUI`.
- **2026-10-03**: Refactor step 4a (`REFACTOR.md`):
  - `NotchService` calls the Shelf, the brightness keys and the precise volume
    roller through `NotchService.collaborators` (the new
    `Services/Notch/NotchCollaborators.swift`), which `main.swift` wires.
  - `Tests/generate_sources.py` gives the file-drop, fullscreen and
    destination contracts their own `collaborators` stand-ins.
- **2026-10-03**: Refactor step 5a (`REFACTOR.md`):
  - The session observers moved from `NotchService.installObservers()` into
    the new `Services/Notch/NotchSessionTracker.swift`; `NotchService` starts
    and stops the tracker and applies its changes as before.
  - New test: `Tests/NotchSessionTrackerTests.swift`, run in the notch suite.
- **2026-10-03**: Refactor step 5b (`REFACTOR.md`):
  - The menu-space timer, read queue and staleness checks moved from
    `NotchService` into the new `Services/Notch/NotchMenuSpaceReader.swift`;
    `NotchService` starts, stops and invalidates the reader and applies its
    answers as before.
  - `Tests/generate_sources.py` no longer copies `stopMenuSpaceMonitoring()`,
    which is gone, and `Tests/NotchScreenRefreshTests.swift` stands in for
    the reader instead of a timer. Its check that the menu bar's owner is
    measured reads the reader's file.
  - New test: `Tests/NotchMenuSpaceReaderTests.swift`, run in the notch suite.
- **2026-10-03**: Refactor step 5c (`REFACTOR.md`):
  - The copies of the island on other displays moved from `NotchService`
    into the new `Services/Notch/NotchMirrors.swift`: `syncMirrors()`,
    `mirrorSurface`, `mirrorSideRoom`, `makeMirror`, `closeMirrors()` and
    `updateFullscreenDisplays()`. `NotchService` keeps one-line forwards
    under the old names and `bringIsland(to:)`.
  - `Tests/NotchMirrorTests.swift` drives `NotchMirrors` itself, and
    `Tests/generate_sources.py` copies only `bringIsland(to:)` for it.
  - `Tests/mutation_checks.py` gains two mutations of `NotchMirrors`.
- **2026-10-03**: Refactor step 5d (`REFACTOR.md`):
  - The menu-bar click monitors and their press, drag and release rules
    moved from `NotchService` into the new
    `Services/Notch/NotchScreenEdgeClicks.swift`. `NotchService` keeps
    `screenEdgeClickArea`, a new `screenEdgePressed()` with the hover reset
    the press made, and one-line forwards under the old names.
  - `Tests/NotchScreenEdgeClickTests.swift` drives the new type, and
    `Tests/generate_sources.py` copies `screenEdgeClickArea` and
    `screenEdgePressed()` for it.
  - `Tests/mutation_checks.py` gains two mutations of the new type.
- **2026-10-03**: Refactor step 5e (`REFACTOR.md`):
  - Following the pointer to another display moved from `NotchService`
    into the new `Services/Notch/NotchPointerFollower.swift`:
    `syncPointerFollowing()`, `removePointerMonitors()`,
    `schedulePointerFollow()`, `followPointer()` and their state.
    `NotchService` keeps `canFollowPointer`, `move(to:)` and one-line
    forwards under the old names.
  - `Tests/NotchScreenRefreshTests.swift` drives the follower, and
    `Tests/generate_sources.py` copies only `canFollowPointer` and
    `move(to:)` for it.
  - `Tests/mutation_checks.py` gains two mutations of the follower.
- **2026-10-03**: Refactor step 5f (`REFACTOR.md`): the hidden-hover and
  hover-exit monitors in `NotchService` are two `NotchMovementWatch`es (new
  `Services/Notch/NotchMovementWatch.swift`); `NotchService` still decides
  when they run. `Tests/NotchHoverTests.swift` gives its stand-in island the
  same watches, and `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5g (`REFACTOR.md`): the agent strip's marks
  are sized in one place.
  - `Core/Notch/NotchAgentSupport.swift` gains `stripMarkSize(height:working:)`
    (formerly `NotchTimerSupport.stripAgentMarkSize`), `markFrame(size:)`,
    `marksWidth(size:count:)` and `stripMarksWidth(working:in:)`.
  - `NotchService`'s agent-strip wing now shrinks the marks on a short
    island, as `UI/Notch/NotchAgentStrip.swift` draws them; before, it
    reserved full-size marks.
  - `UI/Notch/NotchAgentStrip.swift`, `NotchTimerStrip.swift`,
    `NotchWatchView.swift`, `NotchAgentComponents.swift` and
    `Core/Notch/NotchSupport.swift` call those helpers instead of their own copies.
  - `UI/Notch/NotchAgentsView.swift` lists agents through
    `NotchAgentSupport.providers()`.
  - `Tests/NotchAgentTests.swift` checks the sizes, and
    `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5h (`REFACTOR.md`):
  - File-drop routing moved from `NotchService` into the new
    `Services/Notch/NotchFileDrop.swift`. That covers `beginFileDrop`,
    `updateFileDrop`, `endFileDrop`, `accept(_:)` and the two destinations
    they set.
  - `NotchService` keeps `canAcceptFileDrop` and two new private members,
    `mediaDropArea` and `fileDropLanded()`. Its forwards keep the old names
    and span several lines, so the contract can copy them.
  - `Tests/ShelfDropRoutingTests.swift` and `Tests/generate_sources.py` wire
    the contract's stand-in island to the new type, and the test gains one
    check. `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5i (`REFACTOR.md`): `NotchService`'s
  capture-controls click-through monitor is a `NotchMovementWatch` that
  watches this app only (`.system(matching:inOtherApps:)`, new). The stand-in
  island in `Tests/NotchPresentationRefreshTests.swift` and
  `Tests/NotchCaptureControlsTests.swift` uses the same watch, and
  `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5j (`REFACTOR.md`):
  - New `Core/Notch/NotchNoticeLayout.swift`.
  - `Core/Notch/NotchSupport.swift` gains `NotchGeometry.headerBottom`,
    `pageTop` and `headerSideWidth(contentWidth:)`.
  - These now use them:
    - `NotchService` (the notice's wing and the section scroll's header test);
    - `UI/Notch/NotchNoticeView.swift` and `UI/Notch/NotchView.swift`;
    - `UI/Settings/NotchContentEditor.swift`;
    - `Services/Notch/NotchFileToolsSupport.swift`;
    - `NotchCaptureControlsLayout`.
  - `UI/Notch/NotchCapsuleViews.swift` keeps one padding between the cover
    and the bars of an untitled music strip.
  - `Tests/NotchTests.swift` checks the new geometry.
  - `Tests/mutation_checks.py` gains one mutation, and its "device alerts
    return to the fixed level width" fixture reads the new wing expression.
- **2026-10-03**: Refactor step 6b (`REFACTOR.md`):
  - New `Core/Preference.swift`, `Core/Preferences.swift` and
    `Design/PreferenceStorage.swift`.
  - `Core/Defaults.swift` registers five keys from `Preferences`:
    `menuBarMetricSpacing`, `menuBarMetricOrder`, `micMuteMenuBarIndicator`,
    `screenshotPreviewPosition` and `windowLayoutShortcutsEnabled`.
  - Their `@AppStorage` properties in `UI/` take the `Preference`, which
    replaces a default that disagreed with the registered one:
    `MenuBarMetricsPreview`, `PanelWindowLayoutView`, `QuickLauncherView`,
    `MonitorSettings`, `QuickToolsSettings`, `ScreenshotSettings` and
    `WindowLayoutSettings`.
  - New test: `Tests/PreferenceTests.swift`, run in the preferences suite
    (`Tests/MetricsTests.swift`).
  - A second slice moved 358 on/off preferences with literal defaults:
    `Core/Defaults.swift` registers them from `Preferences`, and every
    `@AppStorage` in `UI/` that repeated one of their defaults takes the
    `Preference` instead.
  - A third slice did the same for 141 preferences with a literal number,
    fraction or text default, and a fourth for 63 with a computed default
    that every view repeated.
  - A fifth slice declared the last 139 registered defaults in
    `Core/Preferences.swift`, so `Core/Defaults.swift` registers every one
    from there. 19 `@AppStorage` properties that named their default through
    a constant take the `Preference`: in `MenuBarMetricsPreview`,
    `MenuPanelView`, `MixerSection`, `KeyboardDebounceSettings`,
    `MonitorSettings`, `MouseSettings`, `SwitcherSettings`,
    `TextSnippetsSettings` and `SwitcherView`.
- **2026-10-03**: Refactor step 6a (`REFACTOR.md`): `Core/` and `Design/`
  build in Swift 6 mode. To get there:
  - Shared statics that a lock, the main thread or a test guards, and the
    island's fonts, are `nonisolated(unsafe)`.
  - These are `@preconcurrency @MainActor`: `SettingsRouter`,
    `NonModalAlert`, `ShelfSharePresenter`, `ShelfSharePickerAnchor.Anchor`,
    `PlainTextEditor.Coordinator`, `NotchSupport.hasNotchedDisplay` and
    `hasDisplayWithoutNotch`, and `SwitcherAppIconCache.icon(for:)` with
    `SwitcherItem.appIcon`.
  - `RadialMenuItem` is `Sendable`, and the favicon download is
    `@unchecked Sendable`. `RadialMenuFaviconFetcher.fetchFavicon` calls back
    on the main actor.
  - `StatusItemAnchorSupport.isTrustworthyStatusFrame` takes its screen
    frames, and a main-actor overload supplies the attached ones.
- **2026-10-03**: Refactor step 6c (`REFACTOR.md`): six optional actions
  that chose between `nil` and one of the view's methods now pass a closure
  that calls the method, which the compiler accepts under Swift 6 checking:
  five in `UI/MenuPanel/MenuPanelView.swift` and one in
  `UI/Notch/NotchMixerView.swift`. Behavior is unchanged.
- **2026-10-03**: Refactor step 6d (`REFACTOR.md`): every place in `UI/`
  that complete concurrency checking reported says what isolates it, with
  no change in behavior. Upstream files touched:
  - **Main-actor types:** the coordinators in `MenuPanel/MixerSection.swift`,
    `MenuPanel/PanelHomebrewView.swift`, `Notch/NotchClipboardView.swift`,
    `Notch/NotchLevelSlider.swift`, `Notch/NotchTimerRuler.swift` and
    `Settings/SettingsView.swift`; `NotchMenuAnchor` in
    `Notch/NotchComponents.swift`; `PermissionGuideOverlay.swift`; the
    keyboard context in `Screenshot/ScreenshotToolOrderControls.swift`;
    `AgentMarks` in `Notch/NotchAgentComponents.swift`; and
    `RadialMenuIconStore` with `RadialMenuItem.displayName` in
    `RadialMenu/RadialMenuView.swift`.
  - **Observers:** `CommandBar/CommandBarView.swift`,
    `Notch/NotchAgentAnimationView.swift`, `Notch/NotchEqualizerBars.swift`,
    `ShortcutRecorderButton.swift`, `WindowVisibilityReader.swift`,
    `Notch/NotchComponents.swift` and `Notch/NotchScratchpadView.swift`
    reach the view through `MainActor.assumeIsolated` from main-queue
    observers, and mark what `deinit` removes `nonisolated(unsafe)`.
  - **Statics:** the caches in `CommandBar/CommandBarView.swift` and
    `Screenshot/ScreenshotBackdropPopover.swift`, the menu separator in
    `Notch/NotchComponents.swift`, and the preference keys in
    `MenuPanel/MenuPanelView.swift` and `Settings/SettingsSectionFocus.swift`.
  - **Across queues:** `Cleaner/CleanerView.swift` and
    `Settings/MonitorAlertsControls.swift` read the notification status
    before the hop to the main queue; `Uninstall/AppPickerView.swift` takes a
    `@Sendable` loader, and `Settings/AppBundleList.swift` and
    `Settings/QuitProtectionSettings.swift` hand it plain values, so Quit
    Protection no longer reads its service off the main thread;
    `Media/MediaWorkspaceView.swift` marks the list its lock guards.
  - **Closures:** `MenuPanel/MetricDetailView.swift`,
    `MenuPanel/NetworkSection.swift`, `Notch/NotchSectionsView.swift`,
    `Recorder/RecorderInspector.swift`, `Settings/TextSnippetsSettings.swift`
    and `KillProcess/KillProcessView.swift`; `MenuPanel/ClipboardQuickPanelView.swift`
    compares its row outside the main actor.
- **2026-10-03**: Refactor step 6e (`REFACTOR.md`): `UI/` builds in Swift 6
  mode. `Services/GeneralPasteboardAccess.swift` takes the work it runs on
  its lane as `@Sendable`, and `UI/Settings/NotchCalendarSelection.swift`
  handles EventKit's store-change notification on the main run loop.
- **2026-10-03**: Refactor step 6f (`REFACTOR.md`):
  - These six files are `@MainActor`:
    - `Services/AgentUsage/AgentCodexResetService.swift`
    - `Services/AppAppearanceController.swift`
    - `Services/Metrics/DiskProtectionService.swift`
    - `Services/Metrics/NetworkAddressService.swift`
    - `Services/PortManager/PortManagerService.swift`
    - `Services/Update/UpdateShowcaseMedia.swift` (the loader)
  - Their off-main helpers are `nonisolated`.
  - The showcase loader releases its session on the main thread.
  - `App/AppDelegate.swift`'s `setUpPopover()` is `@MainActor`.
  - `Tests/generate_sources.py` copies the port snapshot under its new
    `nonisolated` prefix.
- **2026-10-03**: Refactor step 6g (`REFACTOR.md`):
  - `Services/FeatureRuntime.swift` is `@MainActor`.
  - `Services/SettingsBackup.swift`'s `applyAndRelaunch` is `@MainActor`.
  - `Services/CommandBar/CommandBarCatalog.swift` (the feature toggles and
    the relaunch row), `Services/ShortcutCapture.swift` and
    `App/AppDelegate.swift`'s `relaunchApp()` reach it through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6h (`REFACTOR.md`):
  - These are `@MainActor`:
    - `Services/Audio/AudioPriorityService.swift`
    - `Services/Audio/MusicLaunchBlocker.swift`
    - `Services/Cleaner/CleanerScheduler.swift`
    - `Services/ManagedDownloads/WhatsAppDownloadScheduler.swift`
    - `Services/Wallpaper/WallpaperService.swift`
  - The schedulers' main-run-loop timers reach them through
    `MainActor.assumeIsolated`.
  - The wallpaper's apply generation and `needsCloudDownload` are
    `nonisolated`.
- **2026-10-03**: Refactor step 6i (`REFACTOR.md`):
  - Now `@MainActor`:
    - `DockPreviewPinnedPanel`
    - `ExtraBrightnessService`
    - `ClipboardIgnoredApps`
    - `HotkeyManager`
    - `CleaningModeManager`
    - `AudioInputDeviceManager`
    - `NotchAudioLevelService`
  - Methods that only main-actor code calls are `@MainActor`:
    - `Services/Update/UpdateService.swift`: `launchInstaller` and
      `launchAdminInstaller`;
    - `Services/Clipboard/ClipboardHistoryService.swift`:
      `syncWithPreferences`, `start`, `stop` and `captureIfChanged`;
    - `Services/DockPreview/DockPreviewService.swift`: `createPinnedPanel`,
      which `togglePinned()` reaches through `MainActor.assumeIsolated`;
    - `Services/SelfUninstall.swift`: `suspendInputInterceptors`;
    - `App/AppDelegate.swift`: `menuCleaningMode`.
  - These reach the newly isolated services through
    `MainActor.assumeIsolated`:
    - `ShortcutCapture.begin()`;
    - the command bar's Cleaning Mode row;
    - `NotchService`'s preference sync and teardown;
    - two main-run-loop timers.
  - The audio input manager's static HAL helpers are `nonisolated`.
- **2026-10-03**: Refactor step 6j (`REFACTOR.md`):
  - `App/AppDelegate.swift`'s `AppDelegate` and
    `Services/MenuPanel/MenuPanelFocus.swift` are `@MainActor`.
  - The per-method isolation added in 6f, 6g and 6i to `AppDelegate` is
    removed.
  - `main.swift` creates the delegate through `MainActor.assumeIsolated`.
  - `NotchService` reaches `MenuPanelFocus` through
    `MainActor.assumeIsolated`.
  - `Services/Wallpaper/WallpaperSupport.swift`'s
    `WallpaperGalleryLifecycle` is `@unchecked Sendable` (lock-guarded), and
    `WallpaperService.galleryLifecycle` is `nonisolated`.
- **2026-10-03**: Refactor step 6k (`REFACTOR.md`):
  - `Services/SecureInputMonitor.swift`,
    `Services/Audio/SoundOutputSwitcher.swift` and
    `Services/QuickTools/PastePlainService.swift` are `@MainActor`.
  - `PastePlainService.plainText(from:)` is `nonisolated`.
  - The secure-input timer, `ShortcutCapture.begin()` and the command bar's
    Paste Plain row reach them through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6l (`REFACTOR.md`):
  - `Services/AppShell.swift`'s `AppShell` is `@MainActor`.
  - `Services/RadialMenu/RadialMenuService.swift`'s `openSettings(at:)` is
    `@MainActor`.
  - These files reach the app shell through `MainActor.assumeIsolated`:
    - `CommandBarService` and `CommandBarCatalog`;
    - `ClipboardHistoryService`;
    - `RecentCaptureService`;
    - `Permissions`;
    - `NotchService`.
- **2026-10-03**: Refactor step 6m (`REFACTOR.md`):
  - `Services/Update/UpdateService.swift`,
    `Services/QuickTools/ColorSamplerService.swift`,
    `Services/Snippets/SnippetLibraryService.swift` and
    `App/StatusItemController.swift` are `@MainActor`.
  - `UpdateService`'s download completion invalidates its session on the
    main thread. `BoundedUpdateDownloadDelegate` takes `@Sendable` callbacks.
  - `UpdateService`'s `volumeIsReadOnly`, `installResultURL` and `isNewer`,
    and `ColorSamplerService`'s `formattedValue` and `copyQuietly`, are
    `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `afterBeat` takes
    `@MainActor` work.
  - `NotchService.showUpdate()`, `FeedbackDiagnostics.current()`,
    `ScreenCaptureService`, `TextSnippetService` and the command bar's
    snippet rows reach them through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6n (`REFACTOR.md`):
  - `Services/CommandBar/CommandBarService.swift`'s `CommandBarService` is
    `@MainActor`, and `spotlightApplicationPaths()` is `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `CommandBarEntry.run`
    is a `@MainActor` closure; `open(_:)` and `runScript(_:)` are
    `@MainActor`. Its rows and the bar's Settings calls drop
    `MainActor.assumeIsolated`.
  - The bar's restart observer, `NotchService`'s Command Bar action and
    `TextSnippetService`'s visibility read use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6o (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift`'s `NotchService` is `@MainActor`.
    Its `perform(_:)` takes `@MainActor` work, and
    `fullscreenVisibilityDidChange` is `nonisolated`.
  - These reach the island through `MainActor.assumeIsolated`:
    - `ShelfService`, `BrightnessService`, `BrightnessOSD`,
      `PreciseVolumeRollerService` and `MicMuteService`;
    - `CameraPreviewService`, `QuickLauncherService`, `ScratchpadService`
      and `ClipboardHistoryService`;
    - `ScreenCaptureService`, `ScreenshotService`,
      `ScreenshotQuickPreviewController` and
      `ScreenshotSelectionController`;
    - `NotchTimerService`, `NotchWatchService`, `NotchAccessoryService` and
      `NotchLockScreenService`;
    - `main.swift`.
  - These are `@MainActor`: `ShelfService`'s internal-drag methods,
    `ScratchpadService.exportText`, `MediaPanelModal.runPanelModal`,
    `NotchDownloadService`'s folder chooser and
    `NotchLyricsService.importLyrics`.
- **2026-10-03**: Refactor step 6p (`REFACTOR.md`):
  - In `Services/Notch/`, these are `@MainActor`:
    - `NotchWindowHost`, `NotchQuickAccessMotion` and
      `NotchBackdropPresentation`;
    - `NotchLockScreenService` and `NotchLockScreenModel`;
    - `NotchTimerService`, `NotchWatchService` and `NotchAccessoryService`.
  - `NotchAccessoryService`'s IOBluetooth callbacks and
    `NotchWatchService.scaledForRecognition` are `nonisolated`.
  - `NotchWindowHost.whenSettled` takes `@MainActor` work, and its Mission
    Control timer uses `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6q (`REFACTOR.md`):
  - In `Services/Notch/`, `NotchMusicService`, `NotchLyricsService`,
    `NotchCalendarService` and `NotchFileToolsService` are `@MainActor`.
  - `NotchMusicService.artworkTint(of:)` is `nonisolated`, and the lyrics
    download's completion is `@Sendable`.
  - `NotchCalendarService`'s store observers use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6r (`REFACTOR.md`):
  - `Services/Notch/NotchDownloadService.swift` and
    `Services/Notch/NotchNotificationService.swift` are `@MainActor`.
  - Their file-system source, workspace observers and Accessibility
    observer callback use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6s (`REFACTOR.md`):
  - In `Services/QuickTools/`, `QuickLauncherService`,
    `CameraPreviewService`, `ScratchpadService` and `ScreenTextService` are
    `@MainActor`.
  - `ScreenTextService.outcome`, the recognition it runs, and
    `QuickLauncherService.columns` are `nonisolated`.
  - `Services/SettingsBackup.swift`'s `runExportPanel()` is `@MainActor`.
  - `ScreenCaptureService` hands recognized text to `ScreenTextService`
    through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6t (`REFACTOR.md`):
  - `Services/URLCleanerService.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadManager.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadOrganizer.swift` and
    `Services/Homebrew/HomebrewManager.swift` are `@MainActor`; their
    queue-side statics are `nonisolated`.
  - Their timers and the organizer's folder source use
    `MainActor.assumeIsolated`.
  - `AppUpdatesService.startUpgrade`, `AppUninstaller.isRemovingWithHomebrew`
    and `PanelInteractionState.preventsPopoverDismissal` reach Homebrew
    through `MainActor.assumeIsolated`.
  - `AppUninstaller.removeSelectedWithHomebrew` and `CommandBarCatalog`'s
    `selectionEntries` and `cleanClipboardURL` are `@MainActor`.
- **2026-10-03**: Refactor step 6u (`REFACTOR.md`):
  - In `Services/QuickTools/`, `ScreenCaptureService`,
    `ScreenCaptureSelectionOptions`, `ScreenshotSelectionController`,
    `ScreenshotQuickPreviewController`, `ScreenshotQuickPreviewModel` and
    `ScreenshotService` are `@MainActor`, and so is
    `Services/Media/MediaService.swift`'s `MediaWorkspaceSelection`.
  - `ScreenshotService`'s static helpers are `nonisolated`, and the
    selection's session statics are `nonisolated(unsafe)`. Its
    `steppedLoupeNeedsRawWheel` is `nonisolated` and reads the session
    through `MainActor.assumeIsolated`.
  - The 6m, 6o and 6s `MainActor.assumeIsolated` calls in those files are
    gone.
  - `ScreenshotEditorController.windowWillClose` and
    `ScreenRecorderService.toggle` use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6v (`REFACTOR.md`):
  - `Services/KeepAwakeManager.swift` is `@MainActor`; its three timers use
    `MainActor.assumeIsolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `build` and
    `actionEntries` are `@MainActor`.
- **2026-10-03**: Refactor step 6w (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotEditorController.swift`: the model and
    controller are `@MainActor`; the text and code scans stop on a
    lock-guarded token instead of reading the model off the main thread; the
    clipboard and file helpers are `nonisolated`; the 6u close wrapper is
    gone.
  - `Services/Recorder/RecorderEditorController.swift`: the model and
    controller are `@MainActor`; the player's time observer uses
    `MainActor.assumeIsolated`.
  - `Services/QuickTools/BackdropEditing.swift` is `@MainActor`.
  - `Services/Recorder/ScreenRecorderService.swift`: the methods that open,
    close and sweep editors are `@MainActor`.
- **2026-10-03**: Refactor step 6x (`REFACTOR.md`):
  - `Services/WindowMaximizer.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/RadialMenu/RadialMenuService.swift` and
    `Services/SmoothScrollService.swift` are `@MainActor`. Their tap
    callbacks and main-run-loop timers use `MainActor.assumeIsolated`.
  - Mouse navigation's `registeredWebURLHandlers` is `nonisolated`; the
    radial menu's `postWhenModifiersReleased` takes `@MainActor` work.
- **2026-10-03**: Refactor step 6y (`REFACTOR.md`):
  - `Services/Audio/PreciseVolumeRollerService.swift`,
    `Services/AutoQuit/AutoQuitService.swift` and
    `Services/DockPreview/DockPreviewService.swift` are `@MainActor`. Their
    tap and Accessibility callbacks and main-run-loop timers use
    `MainActor.assumeIsolated`; the volume keys' 6o wrappers are gone.
  - `Services/DockClick/DockClickService.swift` and
    `Services/Switcher/WindowActivator.swift` reach Dock Preview and Auto
    Quit through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6z (`REFACTOR.md`):
  - `Services/WindowLayout/WindowLayoutService.swift`,
    `Services/WindowLayout/WindowLayoutIgnoredApps.swift` and
    `Services/WindowLayout/PointerDisplayService.swift` are `@MainActor`.
    Window Layout's taps and timers use `MainActor.assumeIsolated`; the
    ignored apps' `contains(_:in:)` and `matches` are `nonisolated`.
  - `Services/ShortcutCapture.swift` and `Services/ShortcutRecordingTap.swift`
    are `@MainActor`; the recording tap's callback uses
    `MainActor.assumeIsolated`, and `ShortcutCapture`'s wrappers are gone.
  - `UI/ShortcutRecorderButton.swift`'s `deinit` uses
    `MainActor.assumeIsolated` on the main thread.
- **2026-10-03**: Refactor step 6za (`REFACTOR.md`):
  - `Services/QuickTools/QuickTogglesService.swift` is `@MainActor`; its work
    queue returns results through the main queue, and the helpers it runs
    there are `nonisolated`.
  - `Services/Recorder/ScreenRecorderService.swift`:
    `RecorderSelectionAudioOptions` and `record(_:audioOptions:)` are
    `@MainActor`.
  - `UI/RadialMenu/RadialMenuView.swift`: `RadialMenuQuickToggle.radialTitle`
    is `@MainActor`.
- **2026-10-03**: Refactor step 6zb (`REFACTOR.md`):
  - `Services/Clipboard/ClipboardHistoryService.swift` is `@MainActor`; the
    statics its pasteboard lane and persist queue run are `nonisolated`, and
    its 6l and 6o wrappers are gone.
  - `Services/QuitProtection/QuitProtectionService.swift` is `@MainActor`;
    its tap callback and hold timer use `MainActor.assumeIsolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `clipboardEntries` and
    `clipboardBrowseEntries` are `@MainActor`.
  - `Services/Switcher/AppSwitcher.swift` reaches quit protection through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zc (`REFACTOR.md`):
  - `Services/Cleaner/JunkCleaner.swift` and
    `Services/Uninstall/AppUninstaller.swift` are `@MainActor`; their static
    scanners are `nonisolated`, on their own line. The uninstaller's 6t
    changes are reverted.
  - `Services/KillProcess/KillProcessService.swift` is `@MainActor`; its
    statics, batch kill and follow-up are `nonisolated`, and `refresh` is a
    `nonisolated` entry that runs its body (now `refreshOnMain`) on the main
    actor.
  - `Services/PanelInteractionState.swift` is `@MainActor`; its 6t wrapper
    is gone.
- **2026-10-03**: Refactor step 6zd (`REFACTOR.md`):
  - `Services/Shelf/ShelfService.swift` is `@MainActor`; its file sweeps,
    directories and persist queue are `nonisolated`, its timers use
    `MainActor.assumeIsolated`, and the 6o changes are reverted.
  - `Services/AppUpdates/AppUpdatesService.swift` is `@MainActor`; its
    work-queue methods and statics are `nonisolated`, its URL sessions are
    constants instead of lazy properties, the catalog cache is
    `nonisolated(unsafe)`, and the 6t change is reverted.
  - `Services/FanControl/FanControlService.swift` is `@MainActor`; the probe
    hardware is `nonisolated(unsafe)` and the removal statics are
    `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `keepOnShelf`, which hands
    a selection to the Shelf, is `@MainActor`.
- **2026-10-03**: Refactor step 6ze (`REFACTOR.md`):
  - `Services/Finder/FinderCutPaste.swift` is `@MainActor`; its tap thread's
    methods, the progress poller and the move statics are `nonisolated`,
    the tap state its lock guards is `nonisolated(unsafe)`, and the tap
    hands a shortcut to the main thread through `MainActor.assumeIsolated`.
  - `Services/Metrics/SpeedTest.swift` is `@MainActor`; its delegate-queue
    methods and the URL session delegate methods are `nonisolated`, and the
    state that queue owns is `nonisolated(unsafe)`.
  - `Services/AgentUsage/AgentUsageService.swift` is `@MainActor`; its
    reading-queue methods and statics are `nonisolated` (three on their own
    line), the state that queue owns is `nonisolated(unsafe)`, and its tick
    timer uses `MainActor.assumeIsolated`.
  - `Tests/SpeedTestTests.swift` runs its checks on the main actor.
- **2026-10-03**: Refactor step 6zf (`REFACTOR.md`):
  - `Services/KeyboardDebounce/KeyboardDebounceService.swift` is
    `@MainActor`; its tap thread's methods are `nonisolated`, the state its
    two locks guard is `nonisolated(unsafe)`, and its running flag is set
    through `MainActor.assumeIsolated` from a `@Sendable` closure.
  - `Services/SystemMonitor/SystemMonitor.swift` is `@MainActor`; its
    sampling-queue methods and the fan statics are `nonisolated`, the
    sensors, samplers, readings and histories that queue owns are
    `nonisolated(unsafe)`, and its timer uses `MainActor.assumeIsolated`.
  - `Services/SystemMonitor/MonitorAlertService.swift` is `@MainActor`.
  - `Services/Media/MediaService.swift` is `@MainActor`; its init and every
    work method but `run` are `nonisolated`, the operation state its lock
    guards is `nonisolated(unsafe)`, and `run` takes `@Sendable` work.
- **2026-10-03**: Refactor step 6zg (`REFACTOR.md`):
  - `Services/QuickTools/RecentCaptureService.swift` is `@MainActor`; its
    store is a constant made with the service instead of a lazy property,
    its location is found once in init, its queue methods and statics are
    `nonisolated`, the state its queue and lock own is
    `nonisolated(unsafe)`, and the 6l changes are reverted.
  - `Services/QuickTools/QuickToolHUD.swift`: the HUD and its scrolling
    capture model are `@MainActor`; `show` and `showCountdown` are
    `nonisolated` entries that hop to the main thread and run their bodies,
    now `showOnMain` and `showCountdownOnMain`, on the main actor.
- **2026-10-03**: Refactor step 6zh (`REFACTOR.md`):
  - `Services/Switcher/AppSwitcher.swift` is `@MainActor`; its tap thread's
    methods, the focused-window lookup the enumeration queue runs and the
    two lock-only ownership queries are `nonisolated`, the state its two
    locks guard is `nonisolated(unsafe)`, the tap enters the main actor
    inside its existing `main.sync` hops, and the 6zb changes are reverted.
  - `Services/Recorder/ScreenRecorderService.swift`: the service is
    `@MainActor`; its `stop` is a `nonisolated` entry that hops to the main
    thread and runs its body, now `stopOnMain`, on the main actor; the
    session's two callbacks are `@Sendable`; the microphone message is read
    before the session starts; its timer uses `MainActor.assumeIsolated`;
    and the 6u, 6w and 6za method-level changes are reverted.
- **2026-10-03**: Refactor step 6zi (`REFACTOR.md`):
  - `Services/SuperKey/SuperKeyService.swift` is `@MainActor`; its tap
    thread's methods (`runEventTap` on its own line), the mapping queue's
    work, the Caps Lock and key-posting helpers and the solo actions are
    `nonisolated`; the state its two locks and its mapping queue guard is
    `nonisolated(unsafe)`; the mapping's completion is `@MainActor`; and
    `forgetHeldKey` and `runOnMainIfNeeded` hand `@Sendable` work to the
    main thread.
  - `Services/Settings/SettingsDirectory.swift`: the four directory builders
    are `@MainActor` and take an optional source that defaults to nil,
    reading the Super key's own source when none is given.
  - `Services/CommandBar/CommandBarCatalog.swift`: `settingsEntries` is
    `@MainActor`.
  - `UI/Settings/SettingsView.swift`: the directory cache is `@MainActor`.
- **2026-10-03**: Refactor step 6zj (`REFACTOR.md`):
  - `Services/Audio/AppVolumeMixer.swift`: the mixer is `@MainActor`; its 26
    static HAL helpers, the two static constants others read and the
    output-volume selector table are `nonisolated`, the output-control
    lifetime its lock guards is `nonisolated(unsafe)`, and
    `isCurrentOutputAdjustment` is `nonisolated` on its own line.
- **2026-10-03**: Refactor step 6zk (`REFACTOR.md`):
  - `Services/Audio/AirPlayRouteManager.swift`: the manager is `@MainActor`;
    the stream registry is a constant made in init instead of a lazy
    property; the streaming methods, the context binding and the snapshot
    statics are `nonisolated`, with the renderer, the routing context, the
    message-send symbol and the snapshot behind their lock or set once;
    the picker delegate runs its bodies through `MainActor.assumeIsolated`
    (the second now `didEndPresentingRoutes`); its context observer and
    timer do too; and the renderer's failure callback is `@MainActor`.
  - `Services/Audio/AppVolumeMixer.swift`: an AirPlay build takes the
    manager from the main thread and hands it to its engine.
  - `Support/SelfTest.swift`: the AirPlay check reads the manager through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zl (`REFACTOR.md`):
  - `Services/MiddleClick/MiddleClickService.swift` is `@MainActor`; its
    shared instance and init are `nonisolated` (the multitouch callback
    reaches it from its own thread), its tap and contact-frame paths are
    `nonisolated`, the state its three locks guard is
    `nonisolated(unsafe)`, and its session, wake and hot-plug callbacks run
    their bodies through `MainActor.assumeIsolated`.
  - `Services/ScrollInverter.swift` is `@MainActor`; its tap callback is
    `nonisolated` on its own line, and the tap-thread state is
    `nonisolated(unsafe)`.
- **2026-10-03**: Refactor step 5k (`REFACTOR.md`):
  - `NotchService.bindEvents` keeps the volume and battery bindings; the
    other subscriptions moved to the new
    `Services/Notch/NotchEventBindings.swift`, and their reactions moved to
    the `eventBindings` wiring in `NotchService`, which also unbinds it on
    teardown.
  - `Tests/NotchTests.swift` runs the new `NotchEventBindingsTests`.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Switcher/WindowPreviewProvider.swift`: `captureIsPaused`
    gains a `package` overload that takes the preferences and the frontmost
    app's bundle identifier; the private one passes the system's.
  - `Services/Switcher/WindowEnumerator.swift`: `dockPreviewMayActivate`
    gains a `package` overload that takes the window, the preference and the
    desktop query; the one the app calls passes the system's.
  - `Tests/SwitcherModelFeatureTests.swift` and
    `Tests/DockPreviewScopeTests.swift` check those overloads directly and
    drop their stand-ins.
  - `Tests/generate_sources.py` no longer copies `captureIsPaused` or
    `dockPreviewMayActivate`.
- **2026-10-03**: Refactor step 6zm (`REFACTOR.md`):
  - `Services/Display/BrightnessService.swift` is `@MainActor`; the state
    behind the key-thread lock, the state lock and the work queue is
    `nonisolated(unsafe)` with comments naming each guard; the methods
    that run on the key thread or the work queue, and the static display,
    system-brightness and IOKit helpers, are `nonisolated`; the media-key
    tap and the screen-parameters and wake observers run their bodies
    through `MainActor.assumeIsolated`; and the display-toggle finish
    publishes through a `@Sendable` closure that enters the main actor on
    the main thread.
  - `Services/CommandBar/CommandBarCatalog.swift`: the brightness row's
    apply is `@MainActor`.
- **2026-10-03**: Refactor step 6zn (`REFACTOR.md`):
  - Main-queue notification observers run their bodies through
    `MainActor.assumeIsolated` in `Services/AppUpdates/AppUpdatesService.swift`,
    `Services/Audio/AppVolumeMixer.swift`,
    `Services/Audio/MusicLaunchBlocker.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Cleaner/CleanerScheduler.swift`,
    `Services/CleaningMode/CleaningModeManager.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/Clipboard/ClipboardIgnoredApps.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/Display/ExtraBrightnessService.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/KeepAwakeManager.swift`,
    `Services/KillProcess/KillProcessService.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadScheduler.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/Notch/NotchLockScreenService.swift`,
    `Services/QuickTools/CameraPreviewService.swift`,
    `Services/QuickTools/QuickLauncherService.swift`,
    `Services/QuickTools/RecentCaptureService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/RadialMenu/RadialMenuService.swift`,
    `Services/SmoothScrollService.swift`,
    `Services/Snippets/SnippetLibraryService.swift`,
    `Services/Switcher/AppSwitcher.swift` and
    `Services/WindowLayout/WindowLayoutService.swift`.
  - `Services/WindowLayout/WindowLayoutService.swift`: the edge-snap
    preview's fade-out completion does the same.
  - `Services/Audio/MusicLaunchBlocker.swift`: the replacement app's launch
    callback hops to the main queue before it reads the setting.
  - `Services/Audio/AudioInputDeviceManager.swift`: the lock-guarded
    input-volume write lifetime is `nonisolated(unsafe)`.
- **2026-10-03**: Refactor step 6zo (`REFACTOR.md`):
  - `Services/QuickTools/MicMuteService.swift` is `@MainActor`; the
    CoreAudio statics, the adjustment lifetime and `withUnmutedInput` are
    `nonisolated` (the last two on their own line), the lock-guarded flag
    and lifetime are `nonisolated(unsafe)`, and the 6o change is reverted.
  - `Services/Audio/AudioInputDeviceManager.swift`: a volume write takes
    the mute service on the main thread before it is queued.
- **2026-10-03**: Refactor step 6zp (`REFACTOR.md`):
  - `Services/MouseExceptions/MouseAppExceptions.swift` is `@MainActor`;
    its shared instance and init are `nonisolated`, loading is split into
    the lock-guarded lookups (filled in init) and the published lists
    (published on the main thread), the tap-facing questions and their
    helpers are `nonisolated`, the lock-guarded state and the clock are
    `nonisolated(unsafe)`, and the source rebuild publishes through
    `MainActor.assumeIsolated` inside its main-thread hop.
  - `Tests/PointerInputFeatureTests.swift`: the pointer contract's
    `reload()` runs through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zq (`REFACTOR.md`):
  - `App/AppDelegate.swift`: three main-queue observers and the quit-time
    input-source restore run through `MainActor.assumeIsolated`, and the
    notification delegate method is `nonisolated`.
  - `Services/QuickTools/QuickToolHUD.swift` and
    `Services/Notch/NotchWindowHost.swift`: their AppKit animation
    completions run through `MainActor.assumeIsolated`; the window host's
    completion parameter is `@MainActor @Sendable` and its
    `CAAnimationDelegate` conformance is `@preconcurrency`.
  - `Services/KeepAwakeManager.swift`: the running-apps handler is
    `@Sendable` and enters the main actor itself.
  - `Services/QuickTools/RecentCaptureService.swift`: the file manager is
    `nonisolated`.
  - `Services/Switcher/AppSwitcher.swift`: the wake observer runs through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zr (`REFACTOR.md`):
  - `Services/Permissions.swift` is `@MainActor`; Accessibility and Screen
    Recording are mirrored into lock-guarded statics as they are published,
    read through the new `nonisolated` `accessibilityGranted` and
    `screenRecordingGranted`; the Full Disk Access probe, its folder list
    and `automationStatus(for:)` are `nonisolated`; and the two observers
    and the polling timer run through `MainActor.assumeIsolated`.
  - `Services/Switcher/WindowActivator.swift`,
    `Services/Switcher/WindowPreviewProvider.swift`,
    `Services/Switcher/WindowEnumerator.swift` and
    `Services/QuickTools/ScreenshotCaptureEngine.swift` read the mirrored
    grants.
  - `Services/CommandBar/CommandBarCatalog.swift`: five builders that read
    a grant are `@MainActor`.
  - `Tests/ScreenshotFeatureTests.swift`: the window capture's permission
    gate is looked for as `Permissions.accessibilityGranted`.
- **2026-10-04**: Refactor step 6zs (`REFACTOR.md`):
  - `@unchecked Sendable` lock-guarded cancellations in
    `Services/AgentUsage/AgentUsageService.swift`,
    `Core/Cleaner/CleanerSupport.swift`,
    `Services/Uninstall/UninstallerSupport.swift` and
    `Services/Media/MediaService.swift`, which also keeps the conversion
    log in a new locked type.
  - `Services/Metrics/SpeedTest.swift`: the time box's action is `@Sendable`.
  - `Services/SuperKey/SuperKeyService.swift`: the mapping work is
    `@Sendable`; CoreFoundation is a `@preconcurrency` import.
  - `Services/Notch/NotchNotificationService.swift`: the reader reaches its
    queue through a `nonisolated(unsafe)` local.
  - `Services/Clipboard/ClipboardHistoryService.swift`: the resize observer
    reads the panel from the notification.
  - `Services/QuickTools/RecentCaptureService.swift`: the file manager is
    `nonisolated(unsafe)`.
  - `@preconcurrency` imports in
    `Services/QuickTools/CameraPreviewService.swift` (AVFoundation),
    `Services/Notch/NotchAccessoryService.swift` (IOBluetooth),
    `Services/WindowLayout/WindowLayoutService.swift` and
    `Services/WindowMaximizer.swift` (ApplicationServices), and
    `Services/Notch/NotchMusicService.swift` (Dispatch).
- **2026-10-04**: Refactor step 6zt (`REFACTOR.md`):
  - `Services/TransientPaste.swift` is `@MainActor`; `shared`, init and
    `paste` are `nonisolated`, `paste` keeps its main-thread check and runs
    the new private `pasteOnMain`, the snapshot crosses to the lane through
    `nonisolated(unsafe)` locals, the restore enters the main actor, and the
    snapshot reader is `nonisolated`.
  - `Services/Clipboard/ClipboardAutoClearService.swift` is `@MainActor`;
    its observers and timer run through `MainActor.assumeIsolated`, and the
    lock-guarded configuration generation is `nonisolated(unsafe)`.
- **2026-10-04**: Refactor step 6zu (`REFACTOR.md`):
  - Static state says what guards it, as `nonisolated(unsafe)` with a
    comment:
    - a lock: `Services/CommandBar/CommandBarSystemSettings.swift`,
      `Services/Notch/NotchAudioLevelService.swift`,
      `Services/Notch/NotchNotificationReader.swift`,
      `Services/QuickTools/ScreenshotService.swift`, the caches in
      `Services/Recorder/RecorderCursorSprite.swift`,
      `RecorderImageRenderer.swift` and `RecorderTextRenderer.swift`,
      `Services/SpotlightNames.swift`,
      `Services/SystemShortcutTakeover.swift`, the activation generations in
      `Services/Switcher/WindowActivator.swift`, the wallpaper thumbnail
      generation in `Services/Wallpaper/WallpaperService.swift` and the
      prompt flag in `Services/ShellSupport.swift`, whose sleep-state count
      only its queue touches;
    - the main thread: `Services/ActivationHandoff.swift`,
      `Services/Display/BrightnessOSD.swift`,
      `Services/HorizontalWheelScrolling.swift`,
      `Services/MouseNavigation/MouseNavigationKeys.swift`,
      `Services/QuickTools/QuickToolHotkey.swift`,
      `Services/Switcher/SpaceHop.swift`, the pending close and restore in
      `Services/Switcher/WindowActivator.swift`, the command bar caches in
      `Services/CommandBar/CommandBarCatalog.swift` and
      `CommandBarExtras.swift`, the file icon list in
      `Services/Clipboard/ClipboardHistoryService.swift` and the app icons
      in `Services/RadialMenu/RadialNowPlayingService.swift`;
    - `NSCache`, which is thread-safe, in
      `Services/Clipboard/ClipboardHistoryService.swift`,
      `Services/MenuBar/MenuBarRenderer.swift`,
      `Services/ResponsibleProcess.swift` and
      `Services/Wallpaper/WallpaperService.swift`;
    - `dlopen` handles that only `dlsym` reads, in
      `Services/DockPreview/DockAutohideHold.swift`,
      `Services/Display/BrightnessService.swift` and
      `Services/MiddleClick/MiddleClickService.swift`, and the constant
      audio settings in `Services/Recorder/RecorderWriter.swift`.
  - `@MainActor`: `Services/QuickTools/WindowActivationPolicy.swift`,
    `Services/ServiceViews.swift` and `MediaPanelModal.panelModalActive`
    in `Services/Media/MediaPanelModal.swift`. `main.swift` installs the
    view factory inside `MainActor.assumeIsolated`.
- **2026-10-04**: Refactor step 6zv (`REFACTOR.md`):
  - `@MainActor`: `Services/DockPreview/DockPreviewDragGhost.swift`,
    `Services/Shelf/ShelfTooltipPopover.swift`,
    `Services/QuickTools/QRResultController.swift`,
    `Services/QuickTools/ScreenshotPinController.swift`,
    `Services/Bluetooth/BluetoothSleepService.swift`,
    `Services/RadialMenu/RadialNowPlayingService.swift` (the service, not
    its bridge), and:
    - `Services/ScrollWheelTarget.swift`, whose `shared`, init and
      `contains` are `nonisolated` and whose self-locking cache is
      `nonisolated(unsafe)`;
    - `Services/MouseAcceleration/MouseAccelerationService.swift`, whose
      HID device callback is `nonisolated` and enters the main actor;
    - `Services/FocusFollowsMouse/FocusFollowsMouseService.swift`, whose
      window query helpers are `nonisolated` and whose timer enters the
      main actor;
    - `Services/DockClick/DockClickService.swift`, whose tap enters the
      main actor and whose Accessibility helpers are `nonisolated`;
    - `Services/DiskImageInstaller/DiskImageInstallerService.swift`, whose
      mount check, install and their static helpers are `nonisolated`.

    Their main-queue observers enter the main actor through
    `MainActor.assumeIsolated`.
  - `@unchecked Sendable`, with a comment saying why:
    `Services/SessionActivity.swift` and
    `Services/GeneralPasteboardAccess.swift`.
  - `main.swift` recovers mouse acceleration inside
    `MainActor.assumeIsolated`.
- **2026-10-04**: Refactor step 6zw (`REFACTOR.md`):
  - `@MainActor`: `Services/Recorder/RecorderIndicator.swift`,
    `Services/QuitProtection/QuitProtectionHUD.swift`,
    `Services/HorizontalWheelScrolling.swift` (its state no longer
    `nonisolated(unsafe)`), `NotchFrameProbe` in
    `Services/Notch/NotchWindowHost.swift`, `WheelMotion` and
    `PanelDismissal` in `Services/RadialMenu/RadialMenuService.swift`, and
    `DiskImageInstallDestinationPrompt` in
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`.
  - `Services/Display/BrightnessOSD.swift` is `@MainActor` with plain
    statics; `show`, `teardown` and `dismiss` are `nonisolated`, hop to the
    main thread and run the new private `showOnMain`, `teardownOnMain` and
    `dismissOnMain`.
  - `@MainActor` functions: `appShell()` in `Services/AppShell.swift`,
    `runImportPanel` in `Services/SettingsBackup.swift`,
    `trashOwnBundleAndQuit` in `Services/SelfUninstall.swift`, `snapshot`,
    `listWindows(for:maximumCount:currentSpaceOnly:marksHiddenSpaces:)` and
    `listWindowsForDockPreview` in `Services/Switcher/WindowEnumerator.swift`
    and `add` in `Services/Notch/NotchOverlaySpace.swift`.
  - `MainActor.assumeIsolated` with a comment in
    `Services/Switcher/WindowActivator.swift` (this app's own windows),
    `Services/ActivationHandoff.swift`, `Services/ShellSupport.swift`,
    `Services/Notch/NotchMenuSpaceReader.swift`,
    `Services/Notch/NotchGestureSupport.swift` (`nativeInteraction`, which the
    tests call from plain code),
    `Services/CommandBar/CommandBarCatalog.swift`, the display-link tick in
    `Services/Notch/NotchWindowHost.swift`, and the animation completions in
    `BrightnessOSD.swift`, `RecorderIndicator.swift`,
    `RadialMenuService.swift` and `Services/Notch/NotchLockScreenService.swift`,
    whose completion types are `@MainActor () -> Void` where they cross.
  - `Services/MouseNavigation/MouseNavigationKeys.swift`: `Shortcut` is
    `Sendable`, `shortcut(for:)` reads the main menu inside
    `MainActor.assumeIsolated`, and `refresh` runs the new main-actor
    `refreshOnMain`.
  - `Services/DockClick/DockClickService.swift`: `activate(pid:)` and
    `restore(_:)` are `nonisolated`, and the restore and minimize walks take
    `[weak self]` in the main-queue block that uses it.
  - `nonisolated(unsafe)` with a comment: the formatters in
    `Services/AgentUsage/AgentLogParser.swift`, the attributes in
    `Services/EnhancedUserInterfaceSuspension.swift` and
    `Services/SpotlightNames.swift`, the UUIDs in
    `Services/Metrics/PeripheralBatterySampler.swift`, `Environment.system`
    in `Services/Notch/NotchPointerFollower.swift` and the run loop in
    `Services/PointerTapRunLoop.swift`.
- **2026-10-04**: Refactor step 6zx (`REFACTOR.md`):
  - `@unchecked Sendable`, with a comment naming what guards each:
    `Services/Finder/FinderRenameService.swift`,
    `Services/MouseClickDebounce/MouseClickDebounceService.swift`,
    `Services/Snippets/TextSnippetService.swift`,
    `Services/Switcher/WindowUseTracker.swift`,
    `Services/SystemMonitor/ProcessUsageService.swift`,
    `Services/Metrics/MaxCapacityProbe.swift` and
    `Services/Switcher/WindowPreviewProvider.swift`, whose `onUpdate` is
    `@MainActor @Sendable`.
  - `AlertSound` in `TextSnippetService.swift` is `Sendable`.
  - `@MainActor @Sendable` callback types: `WheelMotion.dismiss` and
    `PanelDismissal.begin` in `Services/RadialMenu/RadialMenuService.swift`,
    and `fadeOut` (with its caller's counter) in
    `Services/Notch/NotchLockScreenService.swift`.
- **2026-10-04**: Refactor step 6zy (`REFACTOR.md`):
  - `Services/DockClick/DockClickService.swift`: the restore and minimize
    walks' outer queue blocks take `[weak self]` again, beside the inner
    main-queue blocks that use it.
- **2026-10-04**: Refactor step 6zz (`REFACTOR.md`):
  - `@preconcurrency import CoreGraphics` in
    `Services/DockClick/DockClickService.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/ShortcutRecordingTap.swift`, `Services/SmoothScrollService.swift`,
    `Services/Switcher/AppSwitcher.swift`,
    `Services/WindowLayout/WindowLayoutService.swift` and
    `Services/WindowMaximizer.swift`, and added to
    `Services/Audio/PreciseVolumeRollerService.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Display/BrightnessService.swift` and
    `Services/RadialMenu/RadialMenuService.swift`.
- **2026-10-04**: Refactor step 6zza (`REFACTOR.md`):
  - `Services/TransientPaste.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift` and
    `Services/Notch/NotchService.swift`: callbacks and a planned pasteboard
    write handed across threads as `nonisolated(unsafe)` lets.
  - `Services/Clipboard/ClipboardAutoClearService.swift`,
    `Services/KillProcess/KillProcessService.swift`,
    `Services/Homebrew/HomebrewManager.swift` and
    `Services/Switcher/WindowEnumerator.swift`: callback parameters typed
    `@Sendable` or `@MainActor @Sendable`.
  - `Services/Homebrew/HomebrewManager.swift`: a lock-guarded output box
    replaces captured `var`s; completion blocks take `[weak self]` inside.
  - `Services/Switcher/WindowEnumerator.swift`: a lock-guarded batch type
    replaces captured `var`s.
  - `Services/AgentUsage/AgentCodexServer.swift`: the pipe buffer moves into
    its own lock-guarded inbox.
  - `@unchecked Sendable` with what guards them:
    `Services/URLCleanerService.swift` (poll token),
    `Services/Notch/NotchMusicService.swift` (pipe reader),
    `Services/Recorder/ScreenRecorderService.swift` (session),
    `Services/Recorder/RecorderPointerSampler.swift` and
    `Services/Recorder/RecorderTypingTrack.swift`.
  - `Services/Recorder/ScreenRecorderService.swift`: the tap audio choice
    is settled before the stream runs and withdrawn through an atomic flag.
  - `Services/KillProcess/KillProcessService.swift` and
    `Services/QuickTools/CameraPreviewService.swift`: notification fields
    read before `MainActor.assumeIsolated`.
  - `Services/Permissions.swift`: the Accessibility prompt option spelled as
    its value.
  - `Sources/VMStatisticsCompat/include/VMStatisticsCompat.h`,
    `Services/Metrics/VMStatisticsDecoder.swift` and
    `Services/SystemInfo.swift`: the kernel page size read in C.
- **2026-10-04**: Refactor step 6zzb (`REFACTOR.md`):
  - Notification fields read before `MainActor.assumeIsolated` in
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/Clipboard/ClipboardIgnoredApps.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/QuickTools/QuickLauncherService.swift`,
    `Services/QuickTools/RecentCaptureService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/RadialMenu/RadialMenuService.swift`,
    `Services/Snippets/SnippetLibraryService.swift` and
    `Services/Switcher/AppSwitcher.swift`.
  - The notification or timer handed over as a `nonisolated(unsafe)` let in
    `Services/Audio/MusicLaunchBlocker.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Shelf/ShelfService.swift` and `Services/WindowMaximizer.swift`.
- **2026-10-04**: Refactor step 6zzc (`REFACTOR.md`):
  - Properties a main-actor `deinit` reads are `nonisolated(unsafe)` in
    `Services/Audio/AirPlayRouteManager.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/FanControl/FanControlService.swift`,
    `Services/Notch/NotchWindowHost.swift`, `Services/Permissions.swift` and
    `Services/Recorder/RecorderEditorController.swift`.
- **2026-10-04**: Refactor step 6zzd (`REFACTOR.md`):
  - Event-tap verdicts returned from `DispatchQueue.main.sync` in
    `Services/Switcher/AppSwitcher.swift` and
    `Services/Finder/FinderCutPaste.swift`.
  - Main-queue hops take their own `[weak self]` in
    `Services/Clipboard/ClipboardHistoryService.swift`.
  - `@unchecked Sendable` with what guards them:
    `Services/CommandBar/CommandBarFileSearch.swift`,
    `Services/CommandBar/CommandBarScriptRunner.swift`,
    `Services/Notch/NotchTimerAlert.swift`,
    `Services/Recorder/RecorderCaptureEngine.swift`,
    `Services/Recorder/RecorderCursorCatalog.swift` and two classes in
    `Services/Switcher/WindowActivator.swift`.
- **2026-10-04**: Refactor step 6zze (`REFACTOR.md`):
  - Callbacks typed `@MainActor @Sendable` or `@Sendable` in
    `Services/Notch/NotchNotificationService.swift`,
    `Services/Permissions.swift`, `Services/SelfUninstall.swift`,
    `Services/WindowMaximizer.swift`,
    `Services/Homebrew/HomebrewManager.swift`,
    `Services/SuperKey/SuperKeyService.swift` and
    `Services/ShellSupport.swift`.
  - `Services/GeneralPasteboardAccess.swift`: `Sendable` results and
    main-actor completions; the deadline canceller and `didFinish` move into
    the delivery object.
  - `Services/CommandBar/CommandBarCatalog.swift`: the clipboard helper is
    `@MainActor` and takes a main-actor body.
  - Callbacks passed through as `nonisolated(unsafe)` lets in
    `Services/KeepAwakeManager.swift`, `Services/TransientPaste.swift` and
    `Services/Notch/NotchMenuSpaceReader.swift`.
  - `Services/Switcher/WindowServerCaptureQueue.swift`: the captured value is
    a `nonisolated(unsafe)` let, handed to the caller as `sending`.
- **2026-10-04**: Refactor step 6zzf (`REFACTOR.md`):
  - Values read before the hop in
    `Services/AppUpdates/AppUpdatesService.swift`,
    `Services/Display/BrightnessService.swift` and
    `Services/MouseAcceleration/MouseAccelerationService.swift`.
  - `Services/DockPreview/DockPreviewFrameRestoration.swift`: a main-actor
    `isCurrent`. `Services/Media/MediaService.swift`: a `sending` operation,
    and the asset it reads handed over as a `nonisolated(unsafe)` let.
  - `@unchecked Sendable` with what keeps them safe:
    `Core/Switcher/SwitcherSupport.swift`,
    `Services/Switcher/WindowActivator.swift` and
    `Services/Shelf/ShelfFilePromiseTransfer.swift`.
  - `nonisolated(unsafe)` hand-offs in
    `Services/DockClick/DockClickService.swift`,
    `Services/CommandBar/CommandBarCatalog.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Audio/AppVolumeMixer.swift` and
    `Services/Snippets/TextSnippetService.swift`.
- **2026-10-04**: Refactor step 6zzg (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotCaptureEngine.swift`: only window IDs
    cross to the main actor when finding the windows to exclude.
  - `Services/Recorder/RecorderExporter.swift`: `Sendable`, with a
    `@Sendable` progress callback, and `nonisolated(unsafe)` hand-offs into
    the task group.
  - `Services/Recorder/RecorderEditorController.swift`: the waveform tracks
    and asset are handed over as `nonisolated(unsafe)` lets, and the
    progress closures take their own `[weak self]`.
- **2026-10-04**: Refactor step 6zzh (`REFACTOR.md`):
  - Tap callbacks as `nonisolated` static lets in
    `Services/ScrollInverter.swift` and
    `Services/MiddleClick/MiddleClickService.swift`.
  - `Services/PointerTapRunLoop.swift`: `TapThreadRunLoop.stop(_:)`, used by
    `Services/Switcher/AppSwitcher.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/SuperKey/SuperKeyService.swift`,
    `Services/KeyboardDebounce/KeyboardDebounceService.swift` and
    `Services/Display/BrightnessService.swift`.
  - `nonisolated` static helpers for the sound completion in
    `Services/Notch/NotchLockScreenService.swift` and the XPC error handler
    in `Services/FanControl/FanControlService.swift`.
- **2026-10-04**: Refactor step 6zzi (`REFACTOR.md`): `Services/` builds in
  Swift 6 mode (`BUILD`).
- **2026-10-04**: Refactor step 6zzj (`REFACTOR.md`): the app target builds
  in Swift 6 mode (`BUILD`).
  - `App/AppDelegate.swift` reads what it needs from two notifications before
    entering the main actor.
  - `App/StatusItemController.swift` marks the four properties its `deinit`
    reads `nonisolated(unsafe)`.
- **2026-10-04**: `Tests/SwitcherScrollTests.swift` gives each scroll check up
  to 3 s, not 0.5 s, to settle. On a loaded runner an animated reveal has
  landed later than that.
- **2026-10-04**: Refactor step 6zzk (`REFACTOR.md`): `FanControlKit/` and
  the fan control helper build in Swift 6 mode (`BUILD`).
- **2026-10-04**: Refactor step 6zzl (`REFACTOR.md`): the Now Playing helper
  builds in Swift 6 mode (`BUILD`). `NowPlayingAdapter/NowPlayingAdapter.swift`,
  `NowPlayingQueue.swift` and `NowPlayingSelection.swift` mark their shared
  state `nonisolated(unsafe)`, each with the lock, queue or rule that guards
  it, and the watch's `refresh()` is `@Sendable`.
- **2026-10-04**: Refactor step 6zzm (`REFACTOR.md`): the tests build in
  Swift 6 mode, with the main actor as their default isolation (`BUILD`).
  - `Services/GeneralPasteboardAccess.swift`,
    `Services/MouseExceptions/MouseAppExceptions.swift` and
    `Services/Metrics/SpeedTest.swift` take `@Sendable` clocks, and
    `SpeedTest` a `@Sendable` time-box scheduler: each calls them on its own
    queue.
  - `Tests/`: what runs off the main thread says `nonisolated`, stand-in base
    classes declare `init() {}`, and `TestSuite` is `Sendable`.
  - `Tests/generate_sources.py` can keep a `nonisolated` written above a
    copied declaration, and the app-updates copies do.
- **2026-10-04**: Refactor step 6zzn (`REFACTOR.md`): `make_icon` builds in
  Swift 6 mode, with the main actor as its default isolation (`BUILD`).
  `Tools/MakeIcon.swift` is unchanged.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more tests through
  the module:
  - `Services/ResponsibleProcess.swift`: `displayName` has an overload that
    takes the app name, kernel name and executable path lookups.
  - `Core/AppKitExtensions.swift`: `NSScreen.withMouse` makes its choice
    through `screen(containing:among:frame:fallback:)`.
  - `UI/Switcher/ScrollingTitle.swift`: `shouldScroll(scrolls:reduceMotion:overflows:)`.
  - `Tests/ProcessNameTests.swift`, `PointerScreenTests.swift` and
    `ScrollingTitleMotionTests.swift` call these, and
    `Tests/generate_sources.py` no longer copies them.
  - `Tests/PointerDisplayLookupTests.swift`: the stand-in screen, which still
    takes a copy of `withMouse`, chooses through the module's helper.
- **2026-10-04**: `Tests/SpeedTestTests.swift` fires the download time box
  only once the speed test has counted a chunk's bytes. The fixture finishes
  the first chunk and leaves the second unanswered: the delegate asks for the
  second only after counting the first. Before, the time box could fire
  between the fixture handing over the bytes and the delegate receiving them,
  and measure no download.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more tests through
  the module:
  - `Services/SystemMonitor/SystemMonitor.swift`: `readCPUUsage` hands the
    host's tick counters to `cpuUsage(ticks:now:previous:held:heldReadAt:)`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `copyAnswer` has an
    overload that takes the pasteboard write and the HUD.
  - `Services/Clipboard/ClipboardHistoryService.swift`: `pasteIntoPreviousApp`
    has an overload that takes the target app's state, the Accessibility
    grant, the beep, the prompt and the paste.
  - `Tests/SystemMonitorCPUTests.swift`, `CommandBarFeatureTests.swift` and
    `ClipboardFeatureTests.swift` call these, and `Tests/generate_sources.py`
    no longer copies them.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more generated
  copies dropped:
  - `Services/Audio/AppVolumeMixer.swift`: `switchToNextSoundOutput(in:)`
    switches through `switchToNextSoundOutput(in:outputs:currentUID:switchTo:)`.
  - `UI/Settings/ShortcutsSettings.swift`: `expansionBinding(for:in:)` hands
    its state to `expansionBinding(for:in:expanded:)`.
  - `Tests/SoundOutputSwitchTests.swift` and `FeatureCatalogTests.swift` call
    these, and the tests use the shipped `NotchNotice`.
    `Tests/generate_sources.py` no longer copies any of the three.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), two more generated
  copies dropped:
  - `Services/Switcher/WindowPreviewProvider.swift`: `captureViaWindowServer`
    captures through an overload that takes the connection, capture
    function, options and queue; its two typealiases are `package`.
  - `Tests/WindowServerCaptureTests.swift` calls it with its fake, and
    `Tests/NotchPanelTests.swift` builds the shipped `NotchPanel`.
    `Tests/generate_sources.py` no longer copies either.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), two more generated
  files dropped:
  - `UI/MenuPanel/MixerSection.swift`: the level field's Escape monitor
    decides through `MixerPercentEscape.cancelsLevel`.
  - `Tests/MixerPercentKeyTests.swift` calls it, and the notch tests use the
    shipped `NotchShape`. `Tests/generate_sources.py` no longer copies either,
    nor `NotchActivityPicker`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/MenuPanel/BrightnessSection.swift` decides which display rows offer the
  dimming choice through `SoftwareDimmingButton.offersChoice`, which
  `Tests/SoftwareDimmingRouteTests.swift` calls; `Tests/generate_sources.py`
  no longer copies the row's rule.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/MenuPanel/MenuPanelView.swift` lists its rows' hub features in
  `MenuPanelRowFeatures`, which `Tests/MenuPanelSectionGateTests.swift` checks
  against the shipped section gates; `Tests/generate_sources.py` no longer
  copies the sections, rows or quick toggles.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AgentUsage/AgentUsageService.swift` settles and saves progress
  through `settleArchive(on:keeping:save:remove:)` and
  `saveProgress(mark:savedMark:providers:store:cursors:save:)`, and filters
  agent events through `delivers(_:queuedIn:running:session:providers:in:)`,
  which `Tests/AgentUsageArchiveTests.swift` and
  `Tests/AgentUsageEventDeliveryTests.swift` call; `Tests/generate_sources.py`
  no longer copies the settle, save or report methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AgentUsage/AgentUsageService.swift` reads agent logs through
  `read(_:provider:cursors:store:isCancelled:report:lines:)`, which
  `Tests/AgentUsageReadTests.swift` calls; `Tests/generate_sources.py` no
  longer copies the read method. The test's cancelled read now has a new line
  to skip.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Cleaner/CleanerScheduler.swift` saves a finished pass through
  `recordRun(freed:failed:at:in:)`, and `UI/Cleaner/CleanerView.swift` builds
  its last-run line in `lastRunLine(ranAt:freed:failed:strings:)`, both called
  by `Tests/CleanerLastRunContract.swift`; `Tests/generate_sources.py` no
  longer copies `finishRun` or the card's line.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicService.swift` plays a queue row through
  `playQueued(_:visible:request:upcoming:playback:pending:failed:in:send:)`,
  which `Tests/NotchMusicHardeningTests.swift` calls; `Tests/generate_sources.py`
  no longer copies the row action.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/KeepAwakeManager.swift` decides a timer's handoff to automation in
  `timerHandoff(trigger:suppressed:in:batteryAllows:matching:enabled:requireAll:)`,
  which `Tests/KeepAwakeTimerHandoffTests.swift` calls; `Tests/generate_sources.py`
  no longer copies `continueAutomaticallyAfterTimerIfNeeded`, and
  `Tests/mutation_checks.py` targets the static's guard.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): `Tests/generate_sources.py`
  no longer copies nine data types the production modules export
  (`DisplayControlFailure`, `CommandBarService.Mode`, `JunkCleaner.Phase`,
  `UpdateService.State`, the quick preview's `Action`, `NotchMediaSession` and
  `SpaceWindowBridge.Topology` three times). The generated tests alias the
  module's types instead.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the Dock preview's
  desktop-change observation moves from `Services/DockPreview/DockPreviewService.swift`
  into the new `Services/DockPreview/DockPreviewSpaceObservation.swift`, which
  `Tests/DockPreviewScopeTests.swift` drives directly; `Tests/generate_sources.py`
  no longer copies the observation methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Cleaner/JunkCleaner.swift` reads its home folder, screenshot
  folders and Launch Services lookup from an injected `Places`, and runs its
  category scans and queues through an injected `Scanning`; `scan(attended:)`
  loops over the categories in the same order. `Tests/CleanerEligibilityTests.swift`
  and `Tests/CleanerScanFlowTests.swift` call the module, and
  `Tests/generate_sources.py` no longer copies the cleaner.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/CommandBar/CommandBarCatalog.swift` routes the bar's brightness
  command through an injected `BrightnessRoute`, which
  `Tests/CommandBarFeatureTests.swift` passes; `Tests/generate_sources.py` no
  longer copies `applyBrightness`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/DockPreview/DockPreviewFrameRestoration.swift` checks and
  restores a window through an injected `RestoreHost`, which
  `Tests/DockPreviewFrameRestorationTests.swift` passes; `Tests/generate_sources.py`
  no longer copies `restore`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/KeyboardDebounce/KeyboardDebounceService.swift` decides a key
  event in `suppresses(_:event:state:config:)`, which
  `Tests/KeyboardDebounceTapTests.swift` calls; `Tests/generate_sources.py` no
  longer copies the tap handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/PortManager/PortManagerService.swift` reads processes, the lsof
  listing and its queues through an injected `Scanning`, and `snapshot(_:)` is
  `package`; `Tests/PortManagerRefreshTests.swift` passes inert ones, and
  `Tests/generate_sources.py` no longer copies the refresh.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/FanControl/FanControlLifecycle.swift` (new) holds fan control's
  resume, preference and idle-work decisions, which
  `Services/FanControl/FanControlService.swift` forwards to;
  `Tests/FanControlResumeTests.swift` drives it with a recording host, and
  `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchAudioLevelService.swift` reads its preferences, playback
  and readers through an injected `Environment`, with readers behind
  `NotchAudioLevelReading`; `Tests/NotchAudioLevelTests.swift` passes its own,
  and `Tests/generate_sources.py` no longer copies the service.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Audio/MusicLaunchBlocker.swift` reads its defaults, permission,
  clock, running players, notifications, key tap and replacement launcher
  through an injected `System`; the tap callback hands keys to
  `observeMediaKey(type:key:)`. `Tests/FeatureCatalogTests.swift` drives it
  with doubles, and `Tests/generate_sources.py` no longer copies its methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/RadialMenu/RadialNowPlayingService.swift` opens the player through an
  injected `Opening` (`open(_:using:)`); `Tests/NowPlayingOpenContract.swift`
  passes recording doubles, and `Tests/generate_sources.py` no longer copies
  `open`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Update/UpdateService.swift` runs its administrator install through
  an injected `AdminInstall`; `Tests/UpdateAdminInstallTests.swift` passes
  doubles to its own service, and `Tests/generate_sources.py` no longer copies
  `launchAdminInstaller`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Media/MediaPanelModal.swift` runs dialogs through
  `run(_:host:completion:)` with an injected `Dialog` and `Host`, and the island
  window behind `IslandWindowing`; `Tests/MediaDialogHostTests.swift` drives it
  with doubles, and `Tests/generate_sources.py` no longer copies
  `runPanelModal`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchLyricsService.swift` reads its preferences, lookups, island,
  file chooser, activation and queues through an injected `Environment`;
  `Services/Media/MediaPanelModal.swift`'s `IslandWindowing` is `Sendable`.
  `Tests/NotchMusicHardeningTests.swift` drives the real service with doubles,
  and `Tests/generate_sources.py` no longer copies its lifecycle.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchDownloadFolderChoice.swift` (new) holds the download
  folder chooser that `Services/Notch/NotchDownloadService.swift` forwards to,
  and `Services/Notch/NotchIslandSurface.swift` (new) the island state it and
  `Services/Notch/NotchLyricsService.swift` return to.
  `Tests/NotchDownloadFolderChoiceTests.swift` drives the choice with doubles,
  and `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Recorder/RecorderExportProgressChip.swift` (new) is the export chip that
  `UI/Recorder/RecorderEditorView.swift` shows; `Tests/RecorderExportChipTests.swift`
  lays it out, and `Tests/generate_sources.py` no longer copies its body.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/SelfUninstall.swift` runs its clear and uninstall flows through
  injected `Steps`; `Tests/SelfUninstallTests.swift` passes logging doubles,
  and `Tests/generate_sources.py` no longer copies the flows.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Clipboard/ClipboardHistoryService.swift` hands a history image to the
  screenshot editor through a static `editImage(_:editing:)` with an injected
  `ImageEditing`; `Tests/ClipboardHistoryImageEditorTests.swift` runs it, and
  `Tests/generate_sources.py` no longer copies it or `imageCapture(from:)`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMissionControlPolling.swift` (new) holds the Mission Control
  polling that `Services/Notch/NotchWindowHost.swift` forwards to;
  `Tests/NotchMissionControlPollingTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the host's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/ScrollInverter.swift` decides each wheel event in
  `adjustWheel(_:state:defaults:ownProcessID:targets:)`, which
  `Tests/LinearScrollTapTests.swift` calls with real events;
  `Tests/generate_sources.py` no longer copies the tap handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Shelf/ShelfInternalDrag.swift` (new) holds the drag out of a shelf
  that `Services/Shelf/ShelfService.swift` forwards to;
  `Tests/ShelfDragCompletionTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScreenshotQuickPreviewController.swift` takes an injected
  `Scheduler` and opens its hover, action and auto-dismiss members to the
  package; `Tests/ScreenshotPreviewHoverTests.swift` drives a real preview, and
  `Tests/generate_sources.py` no longer copies the controller.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/CommandBar/CommandBarInputSourceBorrowing.swift` (new) holds the ASCII
  layout borrowing that `Services/CommandBar/CommandBarService.swift` forwards to;
  `Tests/CommandBarFeatureTests.swift` drives it, and `Tests/generate_sources.py`
  no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Switcher/WindowActivator.swift` activates apps through injected
  `ActivationCalls` over `SwitcherActivatableApp`, and
  `Services/Switcher/SpaceWindowBridge.swift` fronts windows through injected
  `FrontingCalls`; `Tests/SwitcherActivationTests.swift` drives both, and
  `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScreenshotScrollingCapture.swift` runs its capture loop
  over an injected `FrameSource`; `Tests/ScreenshotScrollingCaptureTests.swift`
  supplies the frames, and `Tests/generate_sources.py` no longer copies the enum.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/UpdateHighlightsView.swift` takes the tour animation's URL and opens
  `UpdateHighlightsGIF` to the package; `Tests/UpdateHighlightsTests.swift`
  renders the real view, and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Settings/NotchSettingsRows.swift` (new) holds the destination and AI agents
  rows that `UI/Settings/NotchSettings.swift` and
  `UI/Settings/NotchAgentsSettings.swift` draw; `Tests/NotchSettingsChoiceTests.swift`
  measures them, and `Tests/generate_sources.py` no longer copies the rows or the
  card primitives.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Media/MediaWorkspaceView.swift` draws its layout and drop target through
  `MediaWorkspaceStack` and `MediaInputDropTarget` and picks tools through a
  static `pick`, and `UI/Notch/NotchFilesView.swift` sizes the island through a
  static `mediaHeightChanged` over `NotchMediaHeightTracking`
  (`Services/Notch/NotchFileToolsService.swift`);
  `Tests/MediaWorkspaceLayoutTests.swift` uses them, and
  `Tests/generate_sources.py` no longer copies the view members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuitProtection/QuitProtectionHUD.swift` opens the HUD and its content
  view to the package; the progress checks move from
  `Tests/Fixtures/QuitProtectionHUDChecks.swift` to `Tests/QuitProtectionHUDTests.swift`,
  and `Tests/generate_sources.py` no longer copies the HUD.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchPointerFollower.swift` gains `NotchIslandSummons`, which
  `Services/Notch/NotchService.swift` wires in place of `bringIsland(to:)`;
  `Tests/NotchMirrorTests.swift` drives it, and `Tests/generate_sources.py` no
  longer copies the service's method.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchScreenEdgeClicks.swift` works out the island's edge-click
  area and press in `area(for:)` and `pressed(hoverWork:hoverState:)`, which
  `Services/Notch/NotchService.swift` calls; `Tests/NotchScreenEdgeClickTests.swift`
  feeds them, and `Tests/generate_sources.py` no longer copies the members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AppUpdates/AppUpdatesService.swift` takes an injected `Environment`
  (preferences, availability, notifications, scan) and splits the scan from
  `check()`; `Tests/AppUpdateRulesTests.swift` drives the real service, and
  `Tests/generate_sources.py` no longer copies its rule members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AppUpdates/AppUpdatesService.swift` takes an injected `Network` (clock,
  catalog session, feed URL loading) and opens its online sources to the package,
  and `Services/AppUpdates/AppUpdateFeedLoader.swift` accepts URL protocol classes;
  `Tests/AppUpdatesTests.swift` drives them, and `Tests/generate_sources.py` no
  longer copies the loader or the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's volume notice
  moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchVolumeFeedback.swift`, which takes an injected output
  and island; `NotchService` forwards to it. `Tests/NotchVolumeFeedbackTests.swift`
  drives it, `Tests/generate_sources.py` no longer copies the service's volume
  members, and `Tests/mutation_checks.py` mutates the new file.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScratchpadService.swift` takes an injected environment
  (store, HUD warning, autosave timer, save dialog, island window, activation,
  main queue) and exports from an `IslandWindowing` host;
  `Tests/ScratchpadStoreContractTests.swift` drives the real service, and
  `Tests/generate_sources.py` no longer copies its export and save members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the gallery's scroll
  routing moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchSectionScrollRoute.swift`;
  `Tests/NotchSectionPagingTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's scroll handlers.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's local key
  and click routing moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchLocalEventRoute.swift`; `Tests/NotchKeyMonitorTests.swift`
  drives it, and `Tests/generate_sources.py` no longer copies
  `installEventMonitors()`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Notch/NotchUpdateControl.swift` draws a new `NotchUpdateBadge` for a
  given state, `Services/Update/UpdateService.swift` adds `State.isOffer`,
  and `Services/Notch/NotchService.swift` names its update rule;
  `Tests/NotchUpdateTests.swift` uses them, and `Tests/generate_sources.py`
  no longer copies the control or `showUpdate()`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the menu bar panel's key
  routing moves from `App/AppDelegate.swift` to
  `Services/MenuPanelKeyRoute.swift`; `Tests/MenuPanelKeyTests.swift` drives
  it, and `Tests/generate_sources.py` no longer copies the delegate's key
  handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the post-update menu bar
  icon check moves from `App/AppDelegate.swift` to
  `Services/StatusItemUpdateCheck.swift`;
  `Tests/PostUpdateStatusItemRecoveryTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the delegate's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): quitting with a borrowed
  keyboard layout moves from `App/AppDelegate.swift` to
  `Services/CommandBar/CommandBarTermination.swift`;
  `Tests/CommandBarFeatureTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies `applicationShouldTerminate`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's queue rows
  and covers move from `Services/Notch/NotchMusicService.swift` to
  `NotchUpcomingQueue` in `Services/Notch/NotchQueueSupport.swift`;
  `Tests/NotchMusicHardeningTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's queue members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicAutomation.swift` takes an injected `System`, and
  the Apple Event fallback flow moves from `Services/Notch/NotchMusicService.swift`
  to `Services/Notch/NotchMusicAutomationFlow.swift`;
  `Tests/NotchMusicAutomationTests.swift` drives them, and
  `Tests/generate_sources.py` no longer copies the service's automation members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/QuickLauncherService.swift` takes an injected
  environment and reads keys through `QuickLauncherKey`, and
  `UI/QuickLauncher/QuickLauncherView.swift` exposes its tile icons for a
  given state; `Tests/QuickLauncherActionTests.swift` and
  `Tests/NotchDestinationTests.swift` drive them, and
  `Tests/generate_sources.py` no longer copies the launcher.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Clipboard/ClipboardHistoryService.swift` takes an injected
  environment (settings, history file, byte limit, stored images, pasteboard
  lane and search folding); `Tests/ClipboardFeatureTests.swift` drives it,
  and `Tests/generate_sources.py` no longer copies its history members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the Dock preview's
  auto-hide hold session moves from
  `Services/DockPreview/DockPreviewService.swift` to
  `Services/DockPreview/DockHoldSession.swift`;
  `Tests/DockAutohideHoldTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's hold members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotQuickPreviewController.swift` takes its
    link actions from the new `Services/QuickTools/ScreenshotLinkActions.swift`
    and exposes its view model.
  - The latest-capture state moves from
    `Services/QuickTools/ScreenshotService.swift` to
    `Services/QuickTools/ScreenshotLatestCapture.swift`.
  - `Tests/ScreenshotShareCompletionTests.swift` drives both, and
    `Tests/generate_sources.py` no longer copies them.
  - `Tests/ScreenshotFeatureTests.swift` and `Tests/mutation_checks.py`
    follow the moved code.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/SuperKey/SuperKeyService.swift` takes an injected system (settings,
  event taps, tap thread, main queue, Accessibility trust, hidutil);
  `Tests/SuperKeyTapContract.swift` drives it, `Tests/PointerInputFeatureTests.swift`
  reads the new tap call, and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicService.swift` takes an injected environment
  (adapter launch, main queue, delayed work, clock, command queue, settings,
  lyrics, Apple Events) and keeps a `NotchMusicAdapterLink` instead of the
  process and its pipes; `Tests/NotchMusicHardeningTests.swift` drives it,
  and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/KeepAwakeManager.swift` takes an injected system: settings,
    the sleep override, `pmset`, its queues and delayed work, timers, power
    assertions, the battery, the screen lock, the lid, the power manager
    and the built-in panel.
  - The `pmset disablesleep` lane, its probes and authorized restores move
    from `Sudoers` in `Services/ShellSupport.swift` to the new
    `Services/SleepOverride.swift`. `Sudoers` keeps the rule paths, the
    install command and two delegating calls.
  - `Tests/KeepAwakeLidSleepTests.swift`, `Tests/KeepAwakeClamshellTests.swift`
    and `Tests/KeepAwakeDimmingTests.swift` drive both, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the output volume and
  mute state of `Services/Audio/AppVolumeMixer.swift` moves to the new
  `Services/Audio/MixerOutputControl.swift`; `Tests/MixerOutputAdjustmentTests.swift`
  drives it, and `Tests/generate_sources.py` no longer copies the mixer's
  members (it also loses a comment left from an earlier removed block).
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Audio/AudioInputDeviceManager.swift` and
  `Services/QuickTools/MicMuteService.swift` take an injected environment
  (CoreAudio through the new `Services/Audio/AudioHAL.swift`, their queues,
  settings and feedback); `Tests/MixerInputVolumeTests.swift` drives both,
  and `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `NowPlayingAdapter/NowPlayingSelection.swift` takes an injected platform
  (MediaRemote, the running applications, the uptime, the reply line, the
  refresh and the queue). The command switch moves there from
  `NowPlayingAdapter/NowPlayingAdapter.swift` as `perform`, and both files
  open what the test needs as `package`.
  - `Tests/NotchPlaybackRoutingTests.swift` drives the adapter's module
    (`BUILD` adds it to the test binary), and `Tests/NotchMusicHardeningTests.swift`
    reaches it through reply and request lines.
  - `Tests/generate_sources.py` no longer copies the selection.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): what running a row
  teaches `Services/CommandBar/CommandBarService.swift` moves to the new
  `Services/CommandBar/CommandBarRunRecorder.swift`, and
  `CommandBarCatalog.emojiEntries` in `Services/CommandBar/CommandBarCatalog.swift`
  takes its settings, permission and typing. `Tests/CommandBarEmojiTests.swift`
  drives both, `Tests/generate_sources.py` no longer copies them, and two
  emoji fixtures in `Tests/mutation_checks.py` follow the code to the
  recorder.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): whether the pointer
  is on a display moves into pure functions in `Core/Switcher/SpaceHopSupport.swift`,
  `Core/QuickTools/ScreenshotSupport.swift` and `Core/DockPreview/DockPreviewSupport.swift`,
  which `Services/Switcher/SpaceHop.swift`, `Services/QuickTools/ScreenshotSelectionController.swift`
  and `Services/DockPreview/DockPreviewService.swift` call.
  `Tests/PointerOnDisplayTests.swift` calls them, and `Tests/generate_sources.py`
  no longer copies the three owners.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the display under
  the pointer is read through the new `Core/ScreenGeometry.swift`.
  - Pure placement functions join `Core/WindowLayout/WindowLayoutSupport.swift`,
    `Core/QuitProtectionSupport.swift`, `Core/QuickTools/ScreenshotSupport.swift`,
    `Core/DockPreview/DockPreviewSupport.swift` and
    `Services/Switcher/SpaceWindowBridge.swift`.
  - `Services/QuickTools/ScreenshotService.swift`, `ScreenshotSelectionController.swift`,
    `Services/WindowLayout/WindowLayoutService.swift`, `Services/QuitProtection/QuitProtectionHUD.swift`
    and `Services/DockPreview/DockPreviewService.swift` call them.
  - `Tests/PointerDisplayLookupTests.swift` calls them, and
    `Tests/generate_sources.py` no longer copies the seven members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the update-intro
  sequence in `App/AppDelegate.swift` moves to the new
  `Services/Update/UpdateIntroSequence.swift`. `Core/AppInfo.swift` gains
  `isPrerelease`. `Tests/UpdateIntroFlowTests.swift` drives the sequence,
  and `Tests/generate_sources.py` no longer copies the delegate's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the key routing of
  `Services/QuickTools/ScreenshotQuickPreviewController.swift` and
  `Services/QuickTools/ScreenshotSelectionController.swift` moves to the new
  `Services/QuickTools/ScreenshotCaptureKeys.swift`.
  `Services/Notch/NotchService.swift` gains `CaptureFocus` behind
  `isCaptureVisible(id:)`. `Tests/NotchCaptureKeyboardTests.swift` calls
  them, and `Tests/generate_sources.py` no longer copies the monitors.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Uninstall/AppUninstaller.swift` gains an injected
    `Environment` and a `PackageManager` protocol (`HomebrewManager`
    adopts it). Its scan and removal bodies move unchanged into
    `scan(_:)` and `remove(_:)`.
  - The command bar's uninstall review moves from
    `Services/CommandBar/CommandBarService.swift` to the new
    `Services/CommandBar/CommandBarUninstallReview.swift`.
  - `FinderBridge.selectionURLs` in
    `Services/Finder/FinderCutPaste.swift` takes an `Automation`.
  - `Tests/UninstallerFlowTests.swift` drives them, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Display/BrightnessService.swift` takes an injected
    `Environment`. Its display-side platform calls go through it: queues,
    preferences, clock, displays, system brightness, DDC, gamma, the
    reconfiguration call and the lid.
  - The lid's IOKit subscription moves into a nested `LidObservation`.
  - `start()` and `step` become package-visible.
  - `Tests/DisplayRestorationTests.swift`, `Tests/BrightnessStepTests.swift`
    and `Tests/SoftwareDimmingRouteTests.swift` drive the service over the
    new `Tests/BrightnessRig.swift`, and `Tests/generate_sources.py` no
    longer copies its members.
  - `Tests/FeatureCatalogTests.swift`: the reconfiguration checks read
    `configureDisplay`, where the main-thread, built-in and lid guards now
    sit in front of the environment's transaction.
  - `Tests/RecorderExportRenderingTests.swift` names the export failure.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `RecorderEditorModel` in
    `Services/Recorder/RecorderEditorController.swift` takes an injected
    `Environment`: its preferences, how the recording's facts are read
    when it opens, and how the preview's composition is made.
  - `Tests/RecorderZoomAimingTests.swift` drives the model, and
    `Tests/generate_sources.py` no longer copies its members.
  - A source-text check in `Tests/RecorderFeatureTests.swift` (a redrawn
    blur keeps its strength) becomes a behavioral check there.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotSelectionController.swift` takes an
    injected `Environment`: the displays, the pointer, the preferences, the
    capture engine's calls and how the panels reach the screen. A panel is
    built from an `Environment.Display` instead of an `NSScreen`.
  - The panel and overlay view become package-visible, with the
    confirmations and the state their checks read.
  - `Services/QuickTools/ScreenCaptureService.swift`: the capture-controls
    forwarding is a static that takes whether the session is current.
  - `Tests/ScreenshotSelectionRefreshTests.swift` drives the controller, and
    `Tests/generate_sources.py` no longer copies it.
  - `Tests/MetricsTests.swift` line-buffers its output, so a crash still
    shows which suites finished.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The island stepping aside for a full-screen Space moves from
    `Services/Notch/NotchService.swift` to the new
    `Services/Notch/NotchFullscreenVisibility.swift`.
  - `Services/Audio/PreciseVolumeRollerService.swift` takes an injected
    `Environment`: its preference, whether the island takes the volume keys,
    Accessibility, the session and the event tap's creation.
  - `Tests/NotchFullscreenTests.swift` drives both, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The island's deferred preference and screen passes, its menu reader's
    schedule, its response to another app coming forward and its move to
    another display go from `Services/Notch/NotchService.swift` to the new
    `Services/Notch/NotchScreenRefresh.swift`.
  - `Tests/NotchScreenRefreshTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies those members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The drag handling of the private canvas view in
    `Services/Notch/NotchWindowHost.swift` goes to the new
    `Services/Notch/NotchCanvasDrop.swift`. The canvas forwards to it.
  - `Tests/ShelfDropRoutingTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies the canvas.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The rule for when the island takes files goes from
    `Services/Notch/NotchService.swift` to
    `Services/Notch/NotchFileDrop.swift`. `canAcceptFileDrop` forwards.
  - `Tests/ShelfDropRoutingTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies the island's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - Where a shelf drop goes moves from `Services/Shelf/ShelfService.swift`
    to the new `Services/Shelf/ShelfDropIntake.swift`. `acceptDrop`,
    `accept(draggingInfo:)` and `merge(draggingInfo:into:)` forward to it.
  - The shelf's `fileURLs(from:)` reader moves to `ShelfPasteboardSupport`
    in `Core/Shelf/ShelfSupport.swift`, and `ShelfService` forwards to it.
  - `Tests/ShelfDropRoutingTests.swift` drives the intake, and
    `Tests/generate_sources.py` no longer copies the shelf's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - What the island's media tools take as a drop goes from
    `Services/Notch/NotchFileToolsService.swift` to the new
    `Services/Notch/NotchMediaDrop.swift`. The service forwards to it.
  - The service takes an injected `Environment` for its switches.
  - `Tests/ShelfDropRoutingTests.swift` and
    `Tests/MediaWorkspaceLayoutTests.swift` drive the module's own types,
    and `Tests/generate_sources.py` no longer writes `ShelfDropRouting.swift`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The preview and title strips in `UI/Switcher/SwitcherView.swift` use
    the new `UI/Switcher/SwitcherWindowStrip.swift`, which holds their
    scroll view and selection reveal.
  - The search filter in `Services/Switcher/AppSwitcher.swift` moves to
    `SwitcherSupport.searchResult` in `Core/Switcher/SwitcherSupport.swift`.
  - `Tests/SwitcherScrollTests.swift` drives both, `Tests/mutation_checks.py`
    points its two switcher mutations at the new file, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 6zzo (`REFACTOR.md`):
  - `Core/Defaults.swift` registers 12 more preferences:
    - the Auto Quit, cut-and-paste and shelf switches;
    - the six menu bar metric switches;
    - the onboarding step;
    - the command bar's links and row shortcuts.

    Each is registered with the empty value its views already assumed.
  - Their `@AppStorage` properties take the `Preference`, in:
    - `UI/MenuBarMetricsPreview.swift`;
    - `UI/MenuPanel/MenuPanelView.swift`;
    - `UI/Onboarding/OnboardingView.swift`;
    - the Auto Quit, command bar, cut-and-paste, monitor and shelf
      settings views.
- **2026-10-05**: Refactor step 5m (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` takes a `NotchService.Environment`
    with the preferences it reads; `.shared` passes the standard ones. Its
    defaults reads, `NotchSupport` queries, feature checks and the lock
    screen's sound check go through them.
  - `Tests/generate_sources.py` reads the island's text with that argument
    taken out, so its copies are unchanged, and `Tests/mutation_checks.py`
    names the new text in one mutation.
- **2026-10-05**: Refactor step 5n (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` holds its window as the new
    `NotchIslandHost` (`Services/Notch/NotchIslandHost.swift`), built by
    `Environment.makeHost`; `.system` builds the `NotchWindowHost` as before.
  - Its one `present` call passes `hideWhenSettled: false`, the default it
    used, and `Tests/NotchPresentationRefreshTests.swift`'s stand-in window
    takes that argument.
- **2026-10-05**: Refactor step 5o (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads the pointer and Reduce Motion,
    and schedules its main-queue timers, through `NotchService.Environment`;
    `.system` passes the system calls it used.
  - `Tests/generate_sources.py` maps those back when it copies the island.
- **2026-10-05**: Refactor step 5p (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` calls the services it uses through
    the new `NotchIslandServices` (`Services/Notch/NotchIslandServices.swift`),
    whose `SystemNotchIslandServices` forwards to the shared instances.
  - `Tests/generate_sources.py` maps the members back when it copies the
    island.
- **2026-10-05**: Refactor step 5q (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` takes its last shared-service
    readings through `NotchIslandServices`: the calendar, the watch, the
    timer's clock, the artwork, the scratchpad and the tools page.
- **2026-10-05**: Refactor step 5r (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads displays as the new
    `NotchDisplayInfo` (`Services/Notch/NotchDisplayInfo.swift`) through its
    environment; `.system` builds them from `NSScreen`.
- **2026-10-05**: Refactor step 5s (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` builds its movement watches, event
    bindings, volume feedback, menu reader, pointer follower, screen
    refresh, full-screen visibility, screen-edge clicks, file drop and
    session tracker from `Environment.Parts`, and observes and posts through
    the notification centers there; `.system` passes the system's.
- **2026-10-05**: Refactor step 5t (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads its remaining preferences
    through the defaults it was built with, and asks `NotchIslandServices`
    for the modal window, the status item, the Accessibility Keyboard, the
    popover, settings and the update preview.
- **2026-10-05**: Refactor step 5u (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` asks its window for the keyboard
    through `NotchIslandHost` (`hasKeyboard`, `takeKeyboard()`,
    `releaseKeyboard()`) and installs the open island's click and key
    monitors through `Environment.Parts.openEvents`, the new
    `NotchOpenEvents` (`Services/Notch/NotchOpenEvents.swift`); `.system`
    passes the panel's own calls and `NSEvent`'s monitors.
  - `Tests/generate_sources.py` maps the keyboard calls back when it copies
    the island.
- **2026-10-05**: Refactor step 5v (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` builds its copies' windows through
    `Environment.makeMirror`, reads full-screen displays through
    `Environment.Parts.fullscreenDisplays` and the battery through
    `Environment.hasBattery`; `.system` passes what it used before.
  - `Tests/generate_sources.py` maps the battery back when it copies the
    island.
- **2026-10-05**: Refactor step 4b, the island's destinations (`REFACTOR.md`):
  - `Tests/NotchDestinationTests.swift` drives a real island built by the
    new `Tests/NotchIslandFixture.swift`, not compiled copies of its
    opening, step-back and session members.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the island's music reader (`REFACTOR.md`):
  - `Tests/NotchMusicVisibilityTests.swift` drives a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its
    presentation and consumer members.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 5w (`REFACTOR.md`):
  - `Services/Notch/NotchWindowHost.swift` keeps whether its panel takes the
    mouse, through Mission Control and a settling hide, in the new
    `NotchWindowInputPolicy` (`Services/Notch/NotchWindowInputPolicy.swift`).
- **2026-10-05**: Refactor step 4b, the island's presentation (`REFACTOR.md`):
  - `Tests/NotchPresentationRefreshTests.swift` and
    `Tests/NotchCaptureControlsTests.swift` drive a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its refresh,
    capture and departure members or the window host's restore.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the island's hover (`REFACTOR.md`):
  - `Tests/NotchHoverTests.swift` drives a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its hover,
    notice and hidden-hover members.
  - `Tests/generate_sources.py` no longer copies them, drops its map of the
    island's environment and services, which no copy uses any more, and
    deletes generated files it no longer writes.
- **2026-10-05**: Refactor step 4b, the compact calendar rows and rail (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Notch/NotchCalendarView.swift`: `NotchCalendarEventRow`
    is `package` and spells out its initializer.
  - `Sources/Vitruvian/UI/Notch/NotchComponents.swift`: `NotchRail` spells out
    its initializer.
  - `Tests/NotchCompactTests.swift` renders both real views;
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the compact camera page and page sizing (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Notch/NotchCameraView.swift`: the view takes its
    camera (the new `NotchEmbeddedCamera`, which `CameraPreviewService`
    adopts) and preview; `init(size:)` passes the app's.
  - `Sources/Vitruvian/UI/Notch/NotchView.swift`: `pageSize` calls the new
    `NotchLayout.pageSize` (`Core/Notch/NotchPageSize.swift`), which holds
    the rule it held.
  - `Tests/NotchCompactTests.swift` tests both on the real code;
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the compact scratchpad (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/QuickTools/ScratchpadService.swift`: its
    `Environment` carries the `defaults` it reads its preferences from.
    `focusText` goes through the new `ScratchpadFocus`
    (`Services/QuickTools/ScratchpadFocus.swift`).
  - `Sources/Vitruvian/UI/Notch/NotchScratchpadView.swift` and
    `Sources/Vitruvian/UI/Scratchpad/ScratchpadFormatBar.swift` take their pad,
    defaulting to the shared one. The island page places its caret through
    `ScratchpadFocus`.
  - `Tests/NotchCompactTests.swift` tests the real page and focus rules;
    `Tests/ScratchpadStoreContractTests.swift`'s harness passes its own
    defaults; `Tests/mutation_checks.py` mutates the focus guard where it
    now lives; `Tests/generate_sources.py` no longer copies any of it.
- **2026-10-05**: Refactor step 4b, the menu panel's presentation (`REFACTOR.md`):
  - `Sources/Vitruvian/App/AppDelegate.swift`: the panel's placement,
    drift correction, close, foreign-close recovery and Settings placement
    move, with their state, to the new `MenuPanelPresenter`
    (`Services/MenuPanel/MenuPanelPresenter.swift`). `AppDelegate` builds it
    over AppKit and its own hooks, and forwards the popover's close
    callbacks to it.
  - `Tests/MenuPanelRecoveryTests.swift` drives the real presenter instead of
    a compiled copy over shadowed AppKit types.
  - `Tests/generate_sources.py` copies nothing any more; it writes the
    localization registry.
- **2026-10-05**: Refactor step 5x (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` keeps its notice in the new
    `NotchNoticeQueue` (`Services/Notch/NotchNoticeQueue.swift`), which decides
    which notice may show and how it arrives and leaves.
  - `Tests/NotchTests.swift` runs the new `Tests/NotchNoticeQueueTests.swift`.
- **2026-10-05**: Refactor step 5l (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` keeps its capture controls in the new
    `NotchCaptureControlsState` (`Services/Notch/NotchCaptureControlsState.swift`),
    which decides the clicks they take and what the pointer does to them.
  - `Tests/NotchTests.swift` runs the new
    `Tests/NotchCaptureControlsStateTests.swift`.
- **2026-10-05**: Refactor step 7b, the Command Bar catalog (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift`: the
    clipboard clear, keep awake, restart and volume confirmation rows come
    from their own builders (`clipboardClearEntry`, `keepAwakeEntries`,
    `restartAppEntry`, `confirmVolume`) with their actions passed in.
    `toggleEntries` and the uninstall rows read the `defaults` they are
    given; the Finder selection row is told whether the app is in
    Applications and whether the uninstaller takes it; `windowEntries` is
    given the frontmost app, the beat and the activation. `afterBeat` is
    package. Every caller passes the live values, so the bar behaves as before.
  - `Tests/CommandBarFeatureTests.swift`, `Tests/PointerInputFeatureTests.swift`
    and `Tests/SwitcherModelFeatureTests.swift` no longer read the catalog's
    source; the new `Tests/CommandBarCatalogRowTests.swift` builds the rows and
    runs them. `Tests/KeepAwakeCatalogTests.swift` is gone with its
    registration in `Tests/MetricsTests.swift`; its checks are among the new
    ones.
- **2026-10-05**: Refactor step 5y (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/Notch/NotchService.swift`,
    `Sources/Vitruvian/UI/Notch/NotchView.swift` and
    `Sources/Vitruvian/UI/Notch/NotchMusicView.swift` read the music page's
    row of controls from the new `NotchMusicControls`
    (`Core/Notch/NotchMusicControls.swift`). Lyrics and the queue count from
    their switches and features in the size as in the drawing, so the
    Settings preview no longer squeezes the player.
  - `Sources/Vitruvian/Core/Notch/NotchNotificationSupport.swift` adds
    `NotchNotificationBannerLayout.iconSide(stripHeight:)`, which
    `Sources/Vitruvian/UI/Notch/NotchNoticeView.swift` draws the banner's
    icon with.
  - `Tests/NotchCompactTests.swift` and `Tests/NotchTests.swift` check both.
- **2026-10-05**: Refactor step 5z (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchGeometry.compactReadingInset(textSize:)`. `Services/Notch/NotchService.swift`,
  `Core/Notch/NotchKeepAwakeSupport.swift`, `Core/Notch/NotchDownloadSupport.swift`
  and the timer, agent, keep awake and watch strips in `UI/Notch/` use it
  instead of spelling the digits' inset out.
- **2026-10-05**: Refactor step 5za (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds `NotchControlGroups`.
  `Services/Notch/NotchService.swift`, `Core/Notch/NotchPageSize.swift`,
  `UI/Notch/NotchControlsView.swift` and `UI/Settings/NotchLayoutEditor.swift`
  split the home page's controls with it instead of their own filters.
- **2026-10-05**: Refactor step 5zb (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.musicControlsRow(_:)`, `musicMainHeight(hasPlayback:layout:height:)`
  and `musicPlayerMinimumHeight`, used by its own sizing,
  `Core/Notch/NotchPageSize.swift` and `UI/Notch/NotchMusicView.swift`.
- **2026-10-05**: Refactor step 5zc (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchNoticeLayout.swift` adds `minimumWing`.
  `Core/Notch/NotchNotificationSupport.swift` takes the banner's inset and the
  low end of its range from `NotchNoticeLayout`, and
  `Services/Notch/NotchService.swift` a text notice's narrowest wing.
  `Tests/mutation_checks.py` quotes the changed line.
- **2026-10-05**: Refactor step 5zd (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` names the peek's height
  and adds `NotchLayout.scrollBottomPadding`, `captureCollapsedSide`,
  `dropHintHeight`, `dropHintBottomGap` and `NotchGeometry.dropPlaceholder`
  and `collapsedCaptureControls`. `Core/Notch/NotchDownloadSupport.swift` adds
  `companionWing`. `Services/Notch/NotchService.swift`, `UI/Notch/NotchView.swift`
  and `UI/Notch/NotchTimerStrip.swift` use them instead of the numbers.
- **2026-10-05**: Refactor step 5ze (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.iconButtonSide` and `headerButtonSpacing` and measures the
  header with them. `UI/Notch/NotchComponents.swift` (`NotchIconButton`) and
  `UI/Notch/NotchView.swift`'s header draw with them.
- **2026-10-05**: Refactor step 5zf (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds the lyrics and queue
  cards' padding, spacing, title height and `musicExtraListHeight(_:)`, which
  `UI/Notch/NotchLyricsView.swift` and `UI/Notch/NotchQueueView.swift` draw with.
- **2026-10-05**: Refactor step 5zg (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.displaySideMargins`, `displayBottomMargin` and
  `NotchGeometry.maximumSurfaceWidth`/`maximumSurfaceHeight`, and its sizing
  uses them. `Services/Notch/NotchService.swift` (the activity picker) and
  `Services/Notch/NotchLockScreenSupport.swift` do too.
- **2026-10-05**: Refactor step 5zh (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchGeometry.compactMarkInset(side:)`, `NotchLayout.compactMarkWing` and
  `compactReadingWing`.
  - The mark's inset is measured with the new rule in
    `Services/Notch/NotchService.swift` and in `Core/Notch/NotchKeepAwakeSupport.swift`,
    `NotchDownloadSupport.swift` and `NotchAgentSupport.swift`.
  - It is drawn with it in the timer, keep awake, watch, agent and download
    views (`UI/Notch/`). Those strips and the calendar strip use the named
    wing widths.
- **2026-10-05**: Refactor step 5zi (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.systemGridHeight(count:width:)` in place of
  `NotchGeometry.systemRows(cards:)`; `UI/Notch/NotchSystemView.swift` uses it.
- **2026-10-05**: Refactor step 6zzp (`REFACTOR.md`): 30 `@AppStorage`
  properties take their `Preference` instead of `DefaultsKey` and a written
  default, in `UI/MenuBarMetricsPreview.swift`, `UI/MenuPanel/PanelClipboardView.swift`,
  `UI/MenuPanel/PanelWindowLayoutView.swift`, `UI/Notch/NotchAgentStrip.swift`,
  `UI/Notch/NotchAgentsView.swift`, `UI/Notch/NotchCapsuleViews.swift`,
  `UI/Notch/NotchClipboardView.swift`, `UI/Notch/NotchLockScreenView.swift`,
  `UI/QuickLauncher/QuickLauncherView.swift` and the Clipboard, Keyboard
  Debounce, Monitor, Notch Agents, Notch, Screenshot, Shelf and Switcher
  settings (`UI/Settings/`).
- **2026-10-05**: Refactor steps 7c and 6zzq (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Settings/MouseButtonSettings.swift` decides its
    captures, prompts and refusals, the drag's binding and its exception
    list through the new `MouseButtonCapture`
    (`Core/MouseButtons/MouseButtonCapture.swift`).
    `UI/Settings/MouseSettings.swift` and `UI/MenuPanel/MenuPanelView.swift`
    read whether either mouse-button switch is on from it.
  - Those three views take the mouse-button, smooth scrolling and clipboard
    switches from their `Preference`, as `UI/Switcher/SwitcherView.swift`
    takes the window shortcut and `UI/Settings/CommandBarSettings.swift` the
    disabled sources.
  - `Tests/PointerInputFeatureTests.swift` no longer reads the three views;
    `Tests/MouseButtonCaptureTests.swift` (run from `Tests/MetricsTests.swift`)
    checks the rules.
- **2026-10-05**: Refactor step 5zj (`REFACTOR.md`):
  - `Sources/Vitruvian/Core/Notch/NotchSupport.swift` names the running
    timer's sizes, the music card's and the activity picker's label and
    chrome.
  - `Core/Notch/NotchAgentSupport.swift` adds `pageProviders(seen:)` and
    `pageRows(providers:width:)`.
  - `Core/Shelf/ShelfSupport.swift` holds the shelf tile's size, spacing and
    inset, which `UI/Shelf/ShelfTilesView.swift` now reads.
  - `Core/Notch/NotchPageSize.swift`, `Services/Notch/NotchService.swift` and
    the timer, music, files, agents and island views (`UI/Notch/`) use them.
- **2026-10-05**: Refactor step 7d (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/FeatureRuntime.swift` takes an `Environment`
    (defaults, binding performer, change follow-up, saved domain), with the
    live one for `.shared`. Each feature's binding is a list of
    `FeatureBindingAction`s from `actions(for:in:)`, which `perform` runs on
    the live services in the same order as before.
  - `Tests/FeatureCatalogTests.swift`, `Tests/PointerInputFeatureTests.swift`
    and `Tests/ScreenshotFeatureTests.swift` no longer read it. The new
    `Tests/FeatureRuntimeTests.swift`, run from `Tests/MetricsTests.swift`,
    checks the runtime on its own defaults.
- **2026-10-05**: Refactor step 7e (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Settings/FeatureHubSettings.swift` undoes the
    never-used offer through the new `FeatureRuntime.reinstallKept(_:)`
    (`Services/FeatureRuntime.swift`).
  - The new `Tests/source_pins.txt` counts the tests' reads of source files,
    which the new `Tests/SourcePinLedgerTests.swift` (run from
    `Tests/MetricsTests.swift`) recounts.
  - `Tests/FeatureCatalogTests.swift` drops the undo's source read, and
    `Tests/FeatureRuntimeTests.swift` checks it instead.
- **2026-10-05**: Refactor step 7f (`REFACTOR.md`):
  - `Tests/MetricsTests.swift` takes its suites from the new
    `Tests/TestGroups.swift` instead of listing them itself, so the new
    `Tests/SwiftTesting/UnitTests.swift` runs the same list through Swift
    Testing.
  - `Tests/TestSuite.swift` (the harness checks) checks that the names
    Swift Testing lists match the runner's suites, in order.
- **2026-10-05**: Refactor step 4c (`REFACTOR.md`): test stand-ins no
  longer take the names of the types they stand in for.
  - `Tests/NotchScreenRefreshTests.swift`: `DispatchQueue`, `NSWorkspace`,
    `Bundle`, `NSEvent`, `NSScreen` and `ClipboardHistoryService` become
    `Clock`, `Frontmost`, `OwnApp`, `Pointer`, `Display` and `Clipboard`.
  - `Tests/ShelfDropRoutingTests.swift`: `AppFeature`, `NotchSupport`,
    `UserDefaults` and `ShelfService` become `Features`, `IslandModules`,
    `Switches` and `Shelf`.
  - `Tests/NotchAudioLevelTests.swift` (`RecordingReader`),
    `Tests/NotchVolumeFeedbackTests.swift` (`Mixer`),
    `Tests/UpdateIntroFlowTests.swift` (`IntroShell`) and
    `Tests/WindowServerCaptureTests.swift` (`Connection`,
    `CaptureFunction`).
  - The new `Tests/TestDoubleNameTests.swift` keeps it so.
- **2026-10-05**: Refactor step 6zzr (`REFACTOR.md`): five more
  `@AppStorage` properties take their `Preference` instead of a
  `DefaultsKey` and a written-out default.
  - `Sources/Vitruvian/UI/Notch/NotchTimerView.swift` (the timer mode) and
    `Sources/Vitruvian/UI/Settings/MouseSettings.swift` (the horizontal
    scroll modifier) read theirs as enums, through a new `@AppStorage`
    initializer in `Design/PreferenceStorage.swift`.
  - `Sources/Vitruvian/UI/Settings/CommandBarSettings.swift` (ASCII
    layout) and `Sources/Vitruvian/UI/Settings/WindowLayoutSettings.swift`
    (side repeat, disabled snap zones).
  - `Tests/CommandBarFeatureTests.swift` and
    `Tests/WindowLayoutFeatureTests.swift` look for the `Preferences` name
    in those views.
- **2026-10-05**: Refactor step 7g (`REFACTOR.md`): Swift Testing runs the
  unit tests.
  - `Tests/MetricsTests.swift`, the `@main` runner, is deleted. Its suites
    run from `Tests/TestGroups.swift` through
    `Tests/SwiftTesting/UnitTests.swift`.
  - `Tests/TestSuite.swift` drops `finish()`, which only that runner
    called.
  - `build.sh --test` still names `Tests/*.swift`. It has not built since
    the tests import the app's modules, and is unchanged.
- **2026-10-06**: Refactor step 7h (`REFACTOR.md`): source pins turned
  behavioral, first part. Each change puts a rule a test read as text
  behind a seam the code calls, with no change in behavior.
  - `build.sh`: the Developer build's fan helper rename is the function
    `rename_fan_helper`. `Tools/uninstall.sh`: its removal, rule search and
    sleep read are the functions `remove_user_state`,
    `find_closed_lid_rules` and `read_sleep_disabled`.
  - `Services/SelfUninstall.swift` (`ownedPaths`, `restoreSleep`),
    `Services/ShellSupport.swift` (`Sudoers.ruleFiles`),
    `Services/Metrics/DiskSampler.swift` (`volumeKeys`, `importantFree`
    made `package`), `Services/Homebrew/HomebrewManager.swift`
    (`awaitExit`).
  - Recorder: `Services/Recorder/RecorderComposer.swift` and
    `RecorderExporter.swift` take the filtering composition as a
    `FilteredComposition`; `RecorderTypingTrack.swift` adds `record(at:)`.
  - Command bar and keyboard: `Services/CommandBar/CommandBarService.swift`
    (`CommandBarKeys`), `CommandBarCatalog.swift` (`storeBootVolumeSpace`,
    `storeSystemAnswers`), `Services/ShortcutCapture.swift`
    (`ShortcutListening`, also used by `UI/ShortcutRecorderButton.swift`),
    `UI/CommandBar/CommandBarView.swift` (`examples(_:hasBattery:)`),
    `Core/GlobalShortcut.swift` (`KeycapLayoutSource`),
    `Core/InputSourceSelection.swift` (`selectNextSource`, used by
    `Services/SuperKey/SuperKeyService.swift`).
  - `App/AppDelegate.swift`: Settings' Command Tab presence goes through
    `WindowActivationClaim` (`Services/QuickTools/WindowActivationPolicy.swift`),
    the permission sinks through `FeatureRuntime.permissionDidChange(_:)`,
    and the quit's input releases through `QuitInputRelease`
    (`Services/FeatureRuntime.swift`).
  - `UI/Onboarding/OnboardingView.swift` (`OnboardingFeatureNames`),
    `Services/CleaningMode/CleaningUnlockCounter.swift`
    (`shippedPressWindow`) and `CleaningModeManager.swift`, whose session
    and disabled-tap decisions move to the new
    `CleaningSessionSupport.swift`.
  - Pointer input: `Core/MouseButtons/MouseButtonShortcutSupport.swift` and
    `MouseSpacesGestureSupport.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/Switcher/SpaceWindowBridge.swift`,
    `Core/SuperKey/SuperKeySupport.swift` (`SuperKeyMouseTapRefusals`),
    `Services/SuperKey/SuperKeyService.swift`,
    `UI/Settings/SuperKeySettings.swift` (`SuperKeyStatusLine`),
    `Core/FocusFollowsMouse/FocusFollowsMouseSupport.swift`,
    `Services/FocusFollowsMouse/FocusFollowsMouseService.swift`,
    `Core/MouseExceptions/MouseAppExceptionSupport.swift`,
    `Services/MouseExceptions/MouseAppExceptions.swift`,
    `Services/InstalledApps.swift`, `UI/Settings/AppBundleList.swift`,
    `UI/Uninstall/AppPickerView.swift`,
    `Services/SessionActivitySupport.swift` (`TapCreationRetry`, used by
    `Services/ScrollInverter.swift` and `SmoothScrollService.swift`),
    `Services/MouseAcceleration/MouseAccelerationService.swift`.
  - Floating panels: each surface builds its panel through a `package`
    factory that the tests build: `App/AppDelegate.swift` (through
    `AppKitMenuPanel.makePositioningPanel`), `UI/PermissionGuideOverlay.swift`,
    `Services/CleaningMode/CleaningModeManager.swift`,
    `Services/Recorder/RecorderIndicator.swift`,
    `Services/QuitProtection/QuitProtectionHUD.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/RadialMenu/RadialMenuService.swift` and
    `RadialNowPlayingService.swift`, `Services/Switcher/AppSwitcher.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/Display/BrightnessOSD.swift`,
    `Services/Snippets/SnippetLibraryService.swift`,
    `Services/WindowLayout/WindowLayoutService.swift`,
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`, and in
    `Services/QuickTools/`: `QuickToolHUD`, `QuickLauncherService`,
    `CameraPreviewService`, `RecentCaptureService`, `ScratchpadService`,
    `QRResultController`, `ScreenshotQuickPreviewController`;
    `ScreenshotPinController.swift`'s window is `package`.
  - Shelf: `Core/Shelf/ShelfSupport.swift` (`ShelfDragWatchdog`,
    `ShelfDismissal`, `ShelfStoreLoad.isWhole`),
    `Services/Shelf/ShelfService.swift` (`dismiss(_:)`, `makePanel()`),
    `ShelfTooltipPopover.swift`, `UI/Shelf/ShelfView.swift` (a `dismissal`
    instead of an `onDismiss` closure) and `ShelfDropZoneView.swift`.
  - Elsewhere: `Services/HorizontalWheelScrolling.swift`,
    `Services/Notch/NotchWindowHost.swift` (`NotchPanel.takesScroll`),
    `Core/Notch/NotchWatchSupport.swift` and
    `Services/Notch/NotchWatchService.swift` (`NotchWatchLastReading`,
    `areaPicture`), `Services/QuickTools/PastePlainService.swift`,
    `Services/SettingsBackup.swift` (`restore(_:into:)`),
    `Core/WindowLayout/WindowLayoutSupport.swift` and
    `Services/WindowLayout/WindowLayoutService.swift`
    (`WindowLayoutSettledFrames`), `Services/Audio/MixerRender.swift` and
    `AppVolumeMixer.swift` (`renderCycle`, `MixerEngineTeardown`),
    `UI/KeepAwakeAutomationView.swift` (`KeepAwakeMatchModePicker`).
  - App management and utilities: `Services/Uninstall/AppUninstaller.swift`
    and `UninstallerSupport.swift`, `UI/Uninstall/AppPickerView.swift` and
    `UninstallerView.swift`, `UI/MenuPanel/PanelUninstallerView.swift`,
    `UI/SharedUI.swift`, `Services/Cleaner/JunkCleaner.swift` and
    `CleanerScheduler.swift`, `UI/Cleaner/CleanerView.swift`,
    `Services/AutoQuit/AutoQuitService.swift` and `AutoQuitSupport.swift`,
    `UI/Settings/AutoQuitSettings.swift`,
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`,
    `Services/QuitProtection/QuitProtectionHUD.swift`,
    `Core/RadialMenu/RadialMenuSupport.swift` and
    `Services/RadialMenu/RadialMenuService.swift`,
    `UI/Settings/ShortcutsSettings.swift` and `DiskExclusionsList.swift`,
    `Services/QuickTools/QuickTogglesSupport.swift` and
    `ScreenshotShareService.swift`, `Services/Recorder/RecordingShareService.swift`,
    `Services/Update/UpdateShowcaseMedia.swift`, `Services/LaunchAtLogin.swift`.
    `UninstallerSupport.offeredApplications()` without arguments and
    `PanelUninstallerView.selectFirstApp`, now unused, are removed.
  - Screenshots: `Services/QuickTools/QuickToolHotkey.swift`,
    `RecentCaptureService.swift`, `ScreenshotCaptureEngine.swift`,
    `ScreenshotCapturePolicy.swift`, `ScreenshotQuickPreviewController.swift`,
    `ScreenshotSelectionController.swift`, `ScreenshotService.swift`,
    `UI/Recorder/RecorderEditorView.swift` and `RecorderInspector.swift`,
    `UI/Screenshot/ScreenshotEditorView.swift`,
    `UI/Settings/ScreenCaptureSettings.swift`.
  - Switcher: `Core/Switcher/SwitcherSupport.swift`,
    `Services/ActivationHandoff.swift`, `Services/DockClick/DockClickService.swift`,
    `Services/DockPreview/DockPreviewService.swift`, and in
    `Services/Switcher/`: `AppSwitcher.swift`, `WindowActivator.swift`,
    `WindowEnumerator.swift`, `WindowPreviewProvider.swift`,
    `WindowUseTracker.swift`; `UI/MenuPanel/MenuPanelView.swift`,
    `UI/Switcher/ScrollingTitle.swift`, `UI/Theme.swift`. The status item's
    recovery in `App/AppDelegate.swift` and `App/StatusItemController.swift`
    moves into the new `Services/MenuBar/StatusItemRecovery.swift`.
  - The suites that read those files as text check the code instead:
    `ScreenshotFeatureTests`, `SwitcherModelFeatureTests`,
    `AppManagementFeatureTests`, `StorageFeatureTests`,
    `UtilitiesFeatureTests`, `UpdateFeatureTests`, `ShelfFeatureTests`, `OverlayPanelTests`, `ScrollHorizontalModifierTests`,
    `NotchScreenRefreshTests`, `NotchWatchTests`, `ClipboardFeatureTests`,
    `SettingsFeatureTests`, `WindowLayoutFeatureTests`,
    `PreferencesFeatureTests`, `MixerFeatureTests`,
    `LocalizationFeatureContractTests`, `NotchTests`,
    `PreferenceNamespaceTests`, `RepositoryFeatureTests`,
    `RecorderFeatureTests`, `RecorderExportRenderingTests`,
    `CommandBarFeatureTests`, `KeyboardFeatureTests`,
    `FeatureCatalogTests` and `PointerInputFeatureTests`.
- **2026-10-06**: Refactor step 7i (`REFACTOR.md`): source pins turned
  behavioral, second part, with no change in behavior.
  - Settings and onboarding views read their decisions from values:
    `UI/Settings/CommandBarSettings.swift` (`CommandBarSettingsActions`,
    `shortcutToggleTitle`, `asciiLayoutRow`), `WindowLayoutSettings.swift`
    (`sideRepeatRow`), `SettingsCard.swift` (`PreferenceSwitchRow`),
    `FeatureHubSettings.swift` (`FeatureHubTally`, `FeatureHubScrollPage`,
    `FeatureHubColumn`), `EnergySettings.swift` (`EnergyDisplayRow`),
    `UI/MenuPanel/BrightnessSection.swift` (`BrightnessPanelDisplayRow`),
    `UI/Onboarding/OnboardingView.swift` (`OnboardingOtherPermissionsList`).
    `Services/FeatureRuntime.swift`'s `Environment` takes the hardware
    reading, and `installBlockedReason(_:)` moves there from `AppFeature`.
  - Switcher, Dock preview and panels: `Core/DockPreview/DockPreviewSupport.swift`
    (`cardTitleBand`, `pinMenuTitle`), `Core/Switcher/SwitcherModels.swift`
    (`statusBadges`), `UI/Switcher/DockPreviewPanelView.swift`,
    `ScrollingTitle.swift` (`WindowNamePlacement`), `SwitcherView.swift`
    (`SwitcherWindowlessDivider`), `UI/Theme.swift` (`PanelSurfaceFit`,
    and borders that take `increasedContrast:`),
    `UI/MenuPanel/MenuPanelView.swift` (`Mode`).
  - Screenshot and scratchpad: `UI/SharedUI.swift` (`sliderColumnLabel`),
    used by `UI/Screenshot/ScreenshotBackdropPopover.swift`,
    `ScreenshotWatermarkPopover.swift` and `UI/Recorder/RecorderInspector.swift`;
    `UI/Scratchpad/ScratchpadView.swift` (`ScratchpadIconTarget`,
    `ScratchpadHitTarget`).
  - `RepositoryFeatureTests`' single-file rules:
    `UI/Settings/URLCleanerSettings.swift` (`URLCleanerField`),
    `Core/Homebrew/HomebrewSupport.swift` and
    `Services/Homebrew/HomebrewManager.swift` (`HomebrewOperationEnd`,
    `init(locateBrew:)`), `Services/SelfUninstall.swift`
    (`Steps.wired(to:)`, `SystemCalls`, `InputInterceptor`,
    `commandLineSleepReport`, used by `Support/Uninstaller.swift`),
    `Services/Display/BrightnessService.swift` (`inputTapsAreSuspended`).
  - Its repository-wide rules, and the one in
    `Tests/MenuPanelToggleLabelTests.swift` (deleted), move into the new
    `bazel/source_lints.py`, run as `source_lints_test`.
    `Tests/SourceNames.swift` lists the symbols, tools and format fields the
    Mac checks.
- **2026-10-06**: Refactor step 7j (`REFACTOR.md`): the last source pins,
  with no change in behavior.
  - Switcher and Dock Preview wiring behind seams:
    `Services/Switcher/AppSwitcher.swift` (`SwitcherTapEvent`,
    `SwitcherSessionSteps`), `WindowActivator.swift` (`ActivationSteps`,
    `SwitcherActivationSources`), `SpaceHop.swift`
    (`scheduleArrivalPulses`), `Services/DockPreview/DockPreviewService.swift`
    (`DockPreviewReattachment`, `DockPreviewActions`; the clamped edge move
    names `animate: false` where it was implied).
  - `Services/QuickTools/ScreenshotService.swift` (`route`/`restore` over
    `PreviewRoute`, `previewAction`).
  - Scrolling: `Services/SmoothScrollService.swift` (an `Environment`, and
    the glide moved into `SmoothScrollGlide`), `Core/SmoothScrollSupport.swift`
    (`wheelEntry`), `Services/MouseButtons/MouseButtonShortcutService.swift`
    (an `Environment`).
  - `Services/MouseClickDebounce/MouseClickDebounceService.swift` and
    `MouseClickDebounceSupport.swift` (`MouseClickDebounceLifecycle`,
    `init(environment:)`).
  - `Services/CleaningMode/CleaningModeManager.swift` (an `Environment`,
    `handle(_:)`).
  - `Services/Display/BrightnessService.swift` (`Environment.isMainThread`,
    `stateLockIsFree`).
  - Command bar: `Services/CommandBar/CommandBarService.swift`,
    `CommandBarInputSourceBorrowing.swift` (`CommandBarPresentationSteps`),
    `CommandBarCatalog.swift` (`offersUninstall`, `uninstallableAppIDs`).
  - Search: `Core/Settings/SettingsSearchSupport.swift` (`SearchFolding`),
    used by `Core/CommandBar/CommandBarSupport.swift`,
    `Core/Switcher/SwitcherSupport.swift` and
    `Services/Clipboard/ClipboardHistorySupport.swift`.
  - Recorder: `Services/Recorder/RecorderPointerSampler.swift` and
    `RecorderTypingTrack.swift`, whose `start()` and `stop()` are
    `@MainActor`.
  - The absences these suites still read, and `TestDoubleNameTests`, move
    into `bazel/source_lints.py`. `SourcePinLedgerTests` and
    `Tests/source_pins.txt` are deleted, and the lint keeps the unit tests
    from reading source text.
- **2026-10-06**: Refactor step 8a (`REFACTOR.md`): switches read and
  written through their `Preference`, with no change in behavior.
  - Every `bool(forKey: DefaultsKey.x)` on a declared preference outside
    `Core/Defaults.swift` reads `UserDefaults[Preferences.x]`. Every
    `set(_:forKey:)` of a switch assigns through it.
  - That is 402 reads and 43 writes in 118 files across `Core/`,
    `Services/`, `UI/`, `App/` and `Support/`. Each is the same call on the
    same receiver.
  - Registration runs first, so the app reads the same values as before.
- **2026-10-06**: Refactor step 8b (`REFACTOR.md`): whole numbers and
  fractions read and written through their `Preference`, with no change in
  behavior.
  - 72 `integer`/`double(forKey:)` reads and 27 writes in 38 files across
    `Core/`, `Services/`, `UI/` and `App/`.
  - `CleanerScheduler.recordRun` and WhatsApp's cleanup record write their
    `Int64` byte counts as `Int(_:)`, the type their preferences hold.
- **2026-10-06**: Refactor step 8c (`REFACTOR.md`): text read and
  written through its `Preference`, with no change in behavior.
  - 117 `string(forKey:)` reads and 31 writes in 50 files across `Core/`,
    `Services/` and `UI/`. A `?? fallback` after a read goes, because the
    declared default takes its place.
  - `WindowLayoutService` decodes the directional shortcut with
    `GlobalShortcut(storageValue:)`. `UpdateShowcaseMedia` drops an
    `if let` that a typed read no longer needs.
- **2026-10-06**: Refactor step 8d (`REFACTOR.md`): lists, tables and data
  read and written through their `Preference`, with no change in behavior.
  - 34 reads and 33 writes in 26 files across `Core/`, `Services/` and
    `UI/`.
  - Four `guard`/`if let data = …` reads became `isEmpty` checks on the
    typed value. `MouseButtonShortcutSupport` reads its table without `?`.
- **2026-10-06**: Refactor step 8e (`REFACTOR.md`): presence checks and
  resets through their `Preference`, with no change in behavior.
  - `Core/Preference.swift` adds `UserDefaults.removeValue(for:)`.
  - 21 `object(forKey:) as? T ?? fallback` reads, whose fallbacks equal the
    declared defaults, and 18 `removeObject(forKey:)` resets in 13 files.
    The command bar's aliases and row shortcuts write or remove their
    encoded text. `WallpaperService.applyAllDisplays` reads its preference
- **2026-10-07**: MacBook Notch chat telemetry color scheme and card layout parity:
  - `NotchAgentsView`: styled pop-out button with warm coral palette `Color(red: 0.85, green: 0.47, blue: 0.34)` and passed `embeddedInNotch: true` to `NexusAgentQuickPromptView`;
  - `NexusAgentQuickPromptView`: defined `NexusAgentTheme` (`warmCoral`, `warmCoralLight`, `gradient`, `cardFill`, `cardBorder`), eliminated the opaque `HUDBackdrop` box in Notch mode so the chat blends seamlessly into the Notch's liquid glass black surface, styled prompt bars and session drawer with Telemetry translucent dark glass cards (`.white.opacity(0.065)` fill, `.white.opacity(0.08)` hairline border), added `agentEnvironmentCard` displaying active provider, model, working directory, and shortcut hints when sessions are empty, and replaced all remaining legacy blue/orange/indigo accents across sparkles, plan mode, send button, message bubbles, active subagent banner, and session rows with warm coral;
  - `QuickPromptWindow` (Nexus Agent macOS): aligned theme palette 1:1 with `QuickPromptTheme`, updating permission approval cards, session buttons, message bubbles, user/assistant avatars, code block copy buttons, and error banners.
- **2026-10-07**: Notch chat pop-out, docking, and telemetry theme styling:
  - `NotchService`: added `popOutToQuickPrompt()` to transition from Notch HUD to floating Quick Prompt window, and uncapped `agentsHeight` in `.chat` mode so the chat interface uses the full Notch island budget;
  - `NexusAgentService`: added `dockToNotch()` to transition from the floating window back into the Notch HUD `.agents` module with `.chat` selected;
  - `NotchAgentsView`: added pop-out button (`arrow.up.forward.app`) beside the mode picker to easily pop out to the floating window (`⌃Space`);
  - `NexusAgentQuickPromptView`: added dock-to-notch button (`sparkles.rectangle.stack`) in `chatHeader`, and restyled message bubbles with Telemetry tab's dark glass card aesthetic (warm coral/terracotta gradients `#D87856`, translucent dark glass fills, subtle hairline borders, and warm accent markdown elements);
  - `NotchAgentStrings`: updated `enUS` module title from "AI Agents" to "Nexus Agent";
  - `NexusAgentTests`: added test cases verifying pop-out navigation, docking navigation, and `enUS` title string resolution.
- **2026-10-07**: MacBook Notch / Dynamic Island native integration for Nexus Agent:
  - `NotchAgentSupport`: added `NotchAgentTab` enum (`.chat` vs `.telemetry`) to represent the active mode of the Notch AI Agents page;
  - `NotchService`: added `@Published package var agentTab: NotchAgentTab = .chat`;
  - `NotchAgentsView`: added top segmented picker allowing switching between interactive prompt / chat (`NexusAgentQuickPromptView`) and telemetry card grid;
  - `NotchAgentStrip`: updated `NotchAgentRestingWing` to observe `NexusAgentService.shared.session`, rendering an animated breathing sparkles glyph on the leading wing and active tool execution or elapsed time badge on the trailing wing when an agent turn runs, with click-to-open interaction opening `.agents` in `.chat` mode;
  - `NexusAgentQuickPromptSession`: added native `NotchNotice` slide-out alerts on agent turn completion and when pausing for tool approval;
  - `NexusAgentTests`: added `notchIntegration` unit test suite covering `NotchAgentTab`, `NotchService.agentTab` mutations, and `NotchNotice` agent event creation.
- **2026-10-07**: Token streaming, plan mode append, and approval cards for Nexus Agent:
  - `NexusAgentSupport`: added `claudePermissionMode` mapping to `NexusAgentApprovalMode` (`bypassPermissions`, `acceptEdits`, `plan`, `default`), added `NexusAgentApprovalRequest` data model, added `totalCostUSD: Double?` to `NexusAgentTurnMetrics`, updated agent arguments to use `--append-system-prompt` instead of `--system-prompt` to prevent clobbering Claude Code internal tools, added `--output-format stream-json --include-partial-messages --verbose` for live token streaming, and extended `NexusAgentStreamEvent` to emit `.approval` and parse cost and token usage from `result` events;
  - `NexusAgentQuickPromptSession`: added `approvalRequest` and `totalCostUSD` properties to `NexusAgentChatMessage`, handled `.approval` stream events, added `decideApproval(messageID:decision:)` state machine, and captured turn cost;
  - `NexusAgentQuickPromptView`: added `NexusAgentApprovalCardView` rendering tool name, parameter preview, Allow / Deny / Allow for Session actions, and interactive status badges; updated `NexusAgentMessageBubble` to render approval cards and display cost metrics;
  - `NexusAgentTests`: added `claudeEnhancementsAndApprovals` unit test suite covering `--append-system-prompt`, `--include-partial-messages`, Claude token deltas, tool_use approval parsing, `result` metrics, and `decideApproval` status transitions.
- **2026-10-07**: Claude Code session titles and scheduled task parity in Quick Prompt:
  - `NexusAgentQuickPromptLayout`: updated `parseClaudeSessions` to check companion `custom-title.json` (`~/.claude/projects/<slug>/<sessionID>/custom-title.json`), parse in-stream `custom-title`, `agent-name`, and `ai-title` events, added `formatTaskName` and `extractScheduledTaskName` to extract and format task names from `<scheduled-task name="...">`, and enhanced `extractUserPrompt` to strip `<system-reminder>` and `<scheduled-task>` XML wrappers;
  - `NexusAgentTests`: added `claudeSessionTitles` unit test suite verifying task name formatting, XML tag extraction, prompt sanitization, and companion file / in-stream title resolution.
- **2026-10-07**: Session archiving parity across Antigravity and Claude Code in Quick Prompt:
  - `NexusAgentSessionSummary`: added `isArchived: Bool` property defaulting to `false`, updated Antigravity query to select `killed` status from `conversation_summaries` where `killed = 1` marks archived sessions, added `claudeHiddenSessionIds(home:)` querying `hiddenSessionIds` from VS Code's `state.vscdb` (`Anthropic.claude-code`) and `UserDefaults` (`vitruvian.claude.hiddenSessionIds`), and updated `parseClaudeSessions` to mark sessions in `hiddenIds` as `isArchived: true`;
  - `NexusAgentService`: added `archiveSession` and `unarchiveSession` updating `conversation_summaries SET killed = 1/0` in SQLite for Antigravity, and `UserDefaults` + `state.vscdb` for Claude Code;
  - `NexusAgentQuickPromptSession`: linked `weak var service: NexusAgentService?`, added `archive` and `unarchive` methods triggering service updates and refreshing the session drawer;
  - `NexusAgentQuickPromptView`: updated `sessionsList` to partition sessions into active and a collapsible "Archived (N)" section with spring animation, and added `NexusAgentSessionRow` with interactive hover states displaying `archivebox` and `arrow.uturn.backward.circle` actions;
  - `SourceNames`: added `archivebox` and `arrow.uturn.backward.circle` SF symbols;
  - `NexusAgentTests`: added `sessionArchiving` unit test suite covering Antigravity `killed` parsing, Claude hidden ID discovery, active/archived list partitioning, and service archive/unarchive operations.
- **2026-10-07**: Claude Code Task and tool_use parsing in Quick Prompt:
  - `NexusAgentService`: extended `parseClaudeTranscript` to extract collapsible tool execution steps (`Bash`, `Task`, `Read`, `Edit`, and generic tools) and `thinking` blocks from assistant turns, and updated `parseActiveSubagents(from:)` to detect spawned Claude subagents from `Task` tool calls and clear them on matching `tool_result` blocks;
  - `NexusAgentTests`: added unit tests in `liveTranscriptAndSubagents` verifying Claude `tool_use` steps, `thinkingText`, and active `Task` subagent tracking and clearance.
- **2026-10-07**: Live transcript following and active subagent status banner in Quick Prompt:
  - `NexusAgentSupport`: added `NexusAgentActiveSubagent` and `NexusAgentToolStep` data models;
  - `NexusAgentService`: added `transcriptPath(home:conversationID:provider:)` and `parseActiveSubagents(from:)` to track running vs completed subagents from JSONL logs, updated `parseTranscript` to extract tool execution steps and thinking content, and wired `showQuickPrompt`, `hideQuickPrompt`, and `modeObserver` to manage the transcript follower lifecycle;
  - `NexusAgentQuickPromptSession`: added `@Published activeSubagents` and `@Published isFollowerActive` with 1.5s file attribute/modification poller syncing messages and active subagents in real time;
  - `NexusAgentQuickPromptView`: added `ActiveSubagentBannerView` above the follow-up bar with expandable subagent details (spinner, role, typeName, model pill badge), and collapsible tool execution steps and thinking bubbles in `NexusAgentMessageBubble`;
  - `NexusAgentTests`: added `liveTranscriptAndSubagents` unit test suite covering active subagent extraction, lifecycle clearance on completion messages, and follower file polling.
- **2026-10-07**: Provider-aware session history and Claude transcript restoration in Quick Prompt:
  - `NexusAgentSessionSummary`: added `projectSlug(for:)` mapping path strings to Claude project directory slugs, and `parseClaudeSessions(home:directory:)` discovering and parsing JSONL sessions from `~/.claude/projects/`;
  - `NexusAgentService`: updated `Environment.listSessions` and `Environment.readTranscript` to be provider-aware with `NexusAgentCLIProvider`, implemented `parseClaudeTranscript` extracting user turns and assistant text blocks, and wired `updateActiveProvider` to refresh sessions when switching providers;
  - `NexusAgentQuickPromptSession`: updated `toggleSessions` and `resume` to pass active provider, added `refreshSessions(configuration:)`, and updated resumed message fallback to name the active provider;
  - `NexusAgentTests`: added unit tests for `projectSlug(for:)`, `parseClaudeTranscript`, and provider-aware session refresh on active provider switch.
- **2026-10-06**: Complete 100% Quick Prompt parity with upstream Nexus Agent:
  - Window pinning: `isPinned` state, `.floating` window level, outside-click dismissal suppression, animated 45° rotation toggle between `pin.circle` and `pin.circle.fill`;
  - Interactive CLI provider switching: `NexusAgentCLIProvider` (Antigravity CLI, Claude Code, Ollama), `ModularProviderButtonView` with `cpu` icon on hover input bar, `ChatProviderBadge` in header, dynamic placeholders;
  - Interactive header badges: `ChatModelBadge` with inline model editor, `ChatWorkingDirectoryBadge` with folder picker;
  - Mode toggle strip: `ModeToggleStrip` above follow-up bar with Plan mode and Worktree mode pills;
  - Floating scroll-to-bottom capsule: `ScrollOffsetPreferenceKey` and `ScrollViewHeightPreferenceKey` tracking with "Scroll to bottom" / "New messages" floating button;
  - Animated typing indicator: avatar circle, 3 oscillating bouncing dots, elapsed timer, activity label, inline Stop button;
  - Message bubble details: user and assistant gradient avatar circles, double-click to copy, hover copy button with spring bounce, expandable token metrics summary card;
  - Shimmer skeleton loading state: 3 animated placeholder bars during initial prompt execution;
  - Character counter overlay on follow-up input when draft exceeds 20 characters;
  - Background completion notifications: `Notifier.post(title:body:)` alerts when generation finishes while panel is backgrounded;
  - Keyboard shortcuts: `⌘N` new chat, `⌘W` / `Esc` dismissal, Up/Down prompt history;
  - Inline error banner with 1-click retry (`arrow.clockwise`);
  - Comprehensive unit test suite covering providers, arguments, metrics, pinning, and retry.
- **2026-10-06**: Rich Markdown blocks and interactive Mermaid diagrams in Quick Prompt:
  - `NexusAgentQuickPromptLayout`: added `NexusAgentMarkdownBlock` enum (`heading`, `bulletItem`, `numberedItem`, `blockquote`, `divider`, `paragraph`) with block parser;
  - `NexusAgentQuickPromptView`: updated `NexusAgentMessageBubble` to render structured Markdown blocks (headings with proportional scale, custom styled bullets and numbered items, blockquote callouts, dividers), added `NexusAgentMermaidCard` with `WKWebView` rendering and Diagram/Source toggle, and added styled `NexusAgentCodeBlockView` with language tags and line numbers;
  - `SourceNames`: added `point.3.connected.trianglepath.dotted` SF symbol;
  - `NexusAgentTests`: added comprehensive test suite for `NexusAgentMarkdownBlock.parse` and Mermaid code fence detection.
- **2026-10-06**: Restore Quick Prompt resumed session content and header parity:
  - `NexusAgentSessionSummary`: retain `preview` property extracted from SQL `preview` column;
  - `NexusAgentService`: add `readTranscript`, `parseTranscript`, and `extractUserPrompt` to parse conversation transcript turns from `~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl`;
  - `NexusAgentQuickPromptSession.resume`: restore turn-by-turn history or seed initial preview and resumption notice bubble, track `sessionTitle` and `isResumed`;
  - `NexusAgentQuickPromptView`: display `sessionTitle` and `Resumed` capsule badge in chat header;
  - `NexusAgentTests`: test session preview retention, resumption messages, and transcript parsing.
- **2026-10-06**: Fix Quick Prompt recent sessions drawer:
  - `NexusAgentService.readSessions`: removed `-readonly` from `/usr/bin/sqlite3`
    arguments so SQLite can read conversations when `conversation_summaries.db`
    has an active WAL file (`SQLITE_CANTOPEN` 14);
  - `NexusAgentQuickPromptSession.sessionsDirectory`: return empty string when
    `configuration.workingDirectory` is empty instead of falling back to home,
    allowing all project workspace sessions to be listed;
  - `NexusAgentSessionSummary.parse`: normalize paths and match both parent and
    sub-directory workspace URIs, keeping all workspaces when directory is empty;
  - `NexusAgentTests`: added test coverage for empty directory workspace matching.
- **2026-10-06**: Release staging off `build/`:
  - `Tools/make-dmg.sh` takes the signed app as its argument instead of reading
    `build/stage/Vitruvian.app`, and renders the installer background into its
    own temp dir instead of `build/`. On macOS's case-insensitive filesystem
    `build` is this package's Bazel `BUILD` file, so the first beta publish
    failed at `mkdir: build: Not a directory`.
- **2026-10-03**: Refactor step 7a (`REFACTOR.md`):
  - `Tests/mutation_checks.py` runs the unit tests through Bazel instead of
    `build.sh`, which no longer builds the app. It mutates the checkout in
    place, refuses to start while a file it mutates has uncommitted changes,
    and puts each file back however the run ends.
  - Its `func toggle()` fixture reads `package func toggle()`, as
    `NotchService` has since step 3.2e-2.
- **2026-10-06**: Upstream tracking (see "Tracking and porting upstream"):
  added `upstream/` (the ledger, `upstream.py` and its tests) and the
  `track_upstream` and `upstream_test` targets in `BUILD`. No upstream file
  changed.
- **2026-10-07**: Notch companion and in-island Command Bar (upstream
  `4a8967e9`), placed in this fork's modules:
  - upstream's `NotchMascotView.swift` is split: the AppKit host
    (`NotchMascotHostView`, its rig and cues) is in
    `Services/Notch/NotchMascotHost.swift`, so the island's window host can
    carry the companion across a resize, and the SwiftUI wrappers stay in UI;
  - `NotchMascotSupport` and `NotchMascotStrings` are in Core,
    `CommandBarDroplet` is in Services, and the bar's width and field height
    are `CommandBarLayout` in Core, for the droplet and the view to share;
  - the island reaches the companion's inputs (Keep Awake, agent usage, the
    calendar, playback, updates) through `NotchIslandServices`, closes the
    bar through `NotchCollaborators.commandBarIslandDidClose`, and the mic,
    screenshot and drop reactions through each service's environment;
  - notice sizing uses this fork's `NotchNoticeLayout` constants;
  - upstream's checks on generated copies of the island are ported onto the
    real island, except two companion-yield cases (lingering music and the
    bridge fade) that need a seam the island does not have yet.
- **2026-10-08**: Archived Antigravity sessions no longer show as active in Quick Prompt:
  - `NexusAgentSessionSummary`: archived state now comes from agy's annotations (`annotations/<id>.pbtxt`, `archived:true`) instead of the index's `killed` column, which marks an aborted run; added `antigravityAnnotationIsArchived`, `antigravityAnnotation(_:archived:now:)`, `antigravityArchivedSessionIds(home:)` and `antigravitySummariesDatabase(home:)`, and `parse` takes the archived ids. The index and annotations are looked up in both of agy's data folders (`~/.gemini/antigravity`, `~/.gemini/antigravity-cli`);
  - `NexusAgentService`: `archiveSession` / `unarchiveSession` write the annotation (`archived:true` + `archival_status_timestamp`, other fields kept) and no longer touch `killed`;
  - `NexusAgentTests`: `sessionArchiving` covers annotation parsing, rewriting, and archive/unarchive against a throwaway home.
- **2026-10-08**: Nexus Agent's pure rules (`NexusAgentSupport`, `NexusAgentQuickPromptLayout`) moved to the shared `NexusAgentCore` library in `apps/desktop/nexus-agent` and are re-exported from `Core/NexusAgentCoreExport.swift`. No behaviour change.
- **2026-10-09**: Nexus Agent's bot runner, `.env` handling, agent turns, session list and chat session state moved to the shared `NexusAgentCore` library (`apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/`) as `NexusAgentEngine` and `NexusAgentQuickPromptSession`, with the `NexusAgentHost` protocol through which they ask the app they run in for its settings, text and notices. Here, `NexusAgentService` is now a subclass of the engine that adds only the floating window, the global shortcut and notch docking, and `VitruvianNexusAgentHost` answers the host protocol from `Preferences`, the translations, `Notifier` and `NotchService`. The shared library takes the app's list of archived Claude sessions from the host (`NexusAgentSessionSummary.claudeHiddenSessionIds` and `parseClaudeSessions` now take `appHidden`) instead of reading this app's `vitruvian.claude.hiddenSessionIds` key; the host's list is that same key. The session's engine reference and turn-finished callback can be set only inside the library. `/usr/bin/sqlite3` left `Tests/SourceNames.swift` because the code that names it moved; its existence is now checked beside the shared code, in `apps/desktop/nexus-agent/macos/Tests/EngineHostTests.swift`. No behaviour change.
- **2026-10-09**: The shared `.env` rule can write which program the bot runs (`CLI_PROVIDER`, `CLI_COMMAND_TEMPLATE`) when the app sets `NexusAgentConfiguration.botProvider`. This app does not set it, so its saves leave those lines alone, as before.
- **2026-10-09**: The shared engine can describe its current problem in words (`problemDescription`), for an app that has only a log panel to show it in. Not used here.
- **2026-10-09**: Comment only: `NexusAgentConfiguration.botProvider` says it is nil after the engine saves or loads.
- **2026-10-09**: An approval mode in `.env` is now read exactly as the bot reads it: a value padded with spaces (which only reaches the bot from inside quotes, `" plan "`) is not a mode the bot knows, so it shows as Default here too and this app's own chat turns pass no permission flag for it. Capitals are still recognised, because the bot recognises them. The examples are shared with the bot's tests (`apps/desktop/nexus-agent/testdata/approval-modes.json`).
- **2026-10-09**: A line of `.env` is now read exactly as the bot's dotenv reads it (for one: an unquoted value ends at a `#`, with or without a space before it). A value holding a `#` and both a single and a double quote is now written in backticks, which dotenv reads back whole; it used to be cut short. The examples, and the check that what this app writes is read back unchanged, are shared with the bot's tests (`apps/desktop/nexus-agent/testdata/env-lines.json`, `env-written-values.json`).
- **2026-10-09**: A `.env` file is split into lines only where the bot's dotenv splits it (`\n`, `\r`, `\r\n`), not at every Unicode line break. Shared examples: `apps/desktop/nexus-agent/testdata/env-files.json`.
- **2026-10-09**: The provider chosen in the Quick Prompt is remembered. The shared engine used to fall back to Antigravity every time it read the bot's `.env` (showing the window, saving the model or folder, starting the bot); it now asks the host for the choice (`chosenProviderID`) each time and tells the host when the user picks another. It also offers any providers the host has saved (`savedProviders`) after the three built in. Here the host keeps both in two new preferences (`nexusAgentChosenProvider`, `nexusAgentSavedProviders`), and the two provider menus of the chat list the engine's `providers`. Nothing in this app can add a provider yet.
- **2026-10-09**: The Quick Prompt's prompt history (the up and down arrows) and worktree mode are kept between launches. The shared chat session starts with what the host kept (`promptHistory`, `worktreeMode`), hands the host the twenty most recent prompts each time a new one is sent, and tells it when worktree mode changes. The arrows behave as before: a prompt already in the history is not added again. Here the host keeps them in two new preferences (`nexusAgentPromptHistory`, `nexusAgentWorktreeMode`); the history is private content, so a settings backup leaves it out.
- **2026-10-09**: Ollama with no model set is no longer run with the model name `default`. The shared chat session asks `ollama list` which models there are (through a new `runProgram` entry of the engine's environment, off the main thread) and runs the first; if that fails it runs `qwen3`, the name the standalone app falls back to. The turn shows as running while it waits, and stopping it then ends it. A model set in the bot's settings is used as before, without asking.
- **2026-10-09**: A provider that is a command of the user's own is run as its command, not as agy. The shared chat session cuts the template into words, fills `{prompt}` and `{model}` into them afterwards (so the prompt is always one argument, whatever it holds), finds the program where the standalone app looks, and starts it directly, never through a shell (a new `launchCommand` entry of the engine's environment, which keeps what the command prints apart from what it complains about). What it prints is the reply. A provider whose template starts with `claude` or `ollama` is run the way that built-in provider is, and the three built-in ones are run their own way whatever their template says. In plan mode a command of the user's own, and Ollama, get the rules in front of the prompt, in the standalone's words; agy and Claude keep their flags. None can be added from this app yet, so nothing changes here until one is saved.
- **2026-10-09**: An agy conversation can be deleted. The shared engine takes its row out of agy's index and removes the three files agy keeps it in (`deleteSession`), or does that for every top-level conversation of one working folder (`deleteAllSessions`, scoped as the standalone app's "Clear All"), through a new `runSqlite` entry of its environment; the chat session has `delete` and `deleteAll`, which read the list again. Any other provider's conversation is refused, and so is an id that is not a plain name. Here, each row of the Quick Prompt's drawer gains a Delete item in its right-click menu while Antigravity is the provider (`NexusAgentQuickPromptView.swift`); the label is the shared `deleteSession` text, in English. There is no "Clear All" control in this app yet.
- **2026-10-09**: Hardening of the shared Nexus Agent chat: an edited built-in provider's command is read only from an entry marked built-in; `ollama list` is given 20 seconds; Claude and Ollama are also looked for where the standalone app looks; and this app's settings backup no longer carries saved provider commands, because they are now run (`Core/SettingsBackupSupport.swift`).
- **2026-10-09**: More hardening of the shared Nexus Agent chat: the time limit on `ollama list` now holds for a program that ignores a polite stop; a command template may not take its program name from the prompt; a conversation id with control characters is refused; deleting the open conversation starts a new chat; and a conversation's files are removed only when its row was.
- **2026-10-09**: A second shared library, `NexusAgentUI` (`apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/`), for the chat view both apps will show. It holds two types so far and no view: the chat's text (`NexusAgentChatStrings`, English by default) and what differs between the apps around the chat (`NexusAgentChatChrome`: the backdrop, the pin, bringing the window back, docking to the notch). This app's UI module builds against it and the pin (`bazel/nexus_agent_shared.sha256`) now covers its sources as well as the core's. Nothing here uses it yet. No behaviour change.
- **2026-10-09**: The Nexus Agent chat view moved to the shared `NexusAgentUI` library as `NexusAgentChatView`, cut into five files (the view; the message bubble and approval card; code and diagram blocks; buttons, badges and the subagent banner; the session row). `UI/NexusAgent/NexusAgentQuickPromptView.swift` here is now a thin view with the old name and initialiser that hands it this app's service, translations, backdrop (`HUDBackdrop`, which upstream wrote and which stays here), pin, notch docking and `vitruvian-error` scheme. The shared view reads its text from `NexusAgentChatStrings`: the 23 strings this app already had, in the app's language, and 64 that were English literals in the view, which stay the same English. The pin and the dock button show only when the app offers them; this app offers both, in the window and in the notch, as before. The two scroll measurements are written through bindings so the library also compiles with the older SDK the standalone's mirror builds with. Images of 44 chat states (9 states, two of them at two moments, as the floating window and in the notch, light and dark) rendered before and after the move by `Tools/NexusAgentChatSnapshots.swift` are identical byte for byte. The 14 SF Symbols only that view drew left `Tests/SourceNames.swift`; that they exist, and that the shared view names nothing of this app, is now checked beside the shared code in `apps/desktop/nexus-agent/macos/Tests/ChatSymbolsTests.swift`. No behaviour change.
- **2026-10-09**: The shared chat view gained what the standalone app's own chat had, ahead of that app moving to it. One thing is new in this app: in the sessions drawer the up and down arrows now pick a row (it is tinted and shows a Return mark) and Return opens it, from the prompt above an open drawer or from the filter field; typing a prompt, pointing at a row, or opening or closing the drawer lets the selection go. That holds in the notch too, where the drawer is always open. The arrows in the chat's follow-up bar still walk the prompt history, and with the drawer closed they do what they did. The rest does not show here: a Clear All button for the drawer exists but this app's chrome turns it off (`offersClearAll: false`), and it deletes off the main thread through a new `runSqliteOffMain` entry of the engine's environment (`deleteAll` now returns at once and the session says `isClearingSessions` meanwhile; this app never calls it); and the shared view's default for the empty notch card's hint no longer names this app's ⌥⌘G shortcut, so `UI/NexusAgent/NexusAgentQuickPromptView.swift` now passes that line and the new-chat tooltip's "(⌘N)" itself, word for word as before. The snapshot tool also draws the shared view with no app around it (22 extra images named `standalone-`). This app's look is unchanged: its 44 images are identical byte for byte.
- **2026-10-09**: Shared code for the standalone app's settings, and two menu items here. New in this app: a session row's right-click menu in the Quick Prompt drawer gains Resume (the same as clicking the row) and Copy Title (the title as the row shows it), above Delete, for every provider's conversations; the labels are the shared view's English (`resumeSession`, `copySessionTitle`). The rest is not used here: the engine has `providersChanged()` for an app whose settings page saves providers itself (this app never calls it), and a new shared file `NexusAgentStoredProviders.swift` holds the standalone's rules for its two stored provider lists and for what it says when a turn ends (`NexusAgentTurnAnnouncement`); this app's host keeps its own announcement rule, unchanged. A context menu is in no snapshot: the 44 images are identical byte for byte.
- **2026-10-09**: Fixes from the review of the shared chat's keyboard and Clear All work. Changed in this app: in the pill's prompt field the arrow keys pick a conversation only when the prompt is empty, and Return opens a picked row only then; with text typed, the arrows move the caret and Return sends the text (before, down then Return on a typed prompt opened an old conversation instead of sending, which mattered most in the notch where the list is always open). The drawer's filter field keeps the arrows always; an arrow held with Shift, Option, Command or Control is left to the text field in both. Not shown here, because this app turns Clear All off: its two-click guard is now by time (the second click deletes only within 2 seconds of the first, worked out from the two times by `NexusAgentClearAllGuard`, so a cancelled wait can no longer leave one click away from deleting everything), and while a clear runs a row cannot be opened or deleted. The unused main-thread `deleteAllSessions` is gone. A filter that matches nothing has a line of its own in the shared view ("No matching sessions"); this app passes its existing translated "no sessions" text for it, so its wording is unchanged. The 44 images are identical byte for byte.
- **2026-10-09**: Fixes from the review of the shared code for the standalone app's settings and notices. A failed turn's notice now also carries the failure's own words, the text of the chat's error bubble (`NexusAgentTurnNotice.failureDetail`), for an app that shows them; this app's host does not read it and every other field is sent as before, so this app's notch notices, sound and notifications are unchanged. Plan mode and worktree mode are now taken at the moment a prompt is sent: with Ollama and no model set, the turn waits for `ollama list`, and switching plan mode off during that wait used to start the turn outside plan mode (in yolo, skipping every prompt); a turn that does not wait is started as before. The rest is the standalone's own and not used here: its rule says nothing for a turn the user stopped before anything arrived, and has a notification for a turn waiting for approval out of sight (`NexusAgentTurnAnnouncement.needsApproval`). An agy turn that cannot be started still reports nothing to the host, here or there. A comment on Copy Title says an untitled conversation copies the placeholder. The 44 images are identical byte for byte.
- **2026-10-09**: Comments in the shared code now speak of the standalone app's own chat in the past and cite its history (it was removed in step 3c), and the comment on bringing the window back after the folder picker says where it comes back is the app's to say. One addition this app does not use: the chrome has `keepsPromptPlaceholderOverSessions`, which keeps the prompt's own placeholder in the top field while the session list is open; the standalone turns it on, because text typed there is a prompt. It is off by default, so this app's top field still reads "Filter sessions" over an open list, as it always has (what is typed there is a prompt here too). This app's behaviour is unchanged: its 44 images are identical byte for byte.
- **2026-10-09**: Settings that cannot be read no longer replace the ones already loaded. Changed in this app too: when the bot's `.env` is there but cannot be read, or holds nothing but blank lines (no permission, or caught while being rewritten), the shared engine's `load()` now keeps the settings it last read from that same file. Before, it took the empty configuration, whose approval mode is `yolo`, so the next Quick Prompt turn skipped every permission prompt and a save from the chat's model badge or folder picker wrote from blanks. A file that is not there at all still means no settings, as before, and so does a first read that fails; settings are not carried over to another bot folder. The comments about the standalone app's removed chat now name the last release that had it (nexus-agent 1.19.0), not a commit. No existing test of this app was edited, and its 44 images are identical byte for byte.
- **2026-10-09**: Three keyboard fixes in the shared Nexus Agent chat, and all three change this app. (1) The caret follows the conversation. After the first prompt is sent, a session is resumed, the session list is closed back onto a conversation, or New Chat, the caret is in the field a prompt is typed in (the follow-up bar under a conversation, the pill otherwise) with no click needed; before, it was left with the window and the next thing typed went nowhere. It also goes back to the prompt when the model name's editor closes. The shared view now gives the caret to a field once that field is in the window, and no longer in the update that brings it. (2) Esc closes an open model-name editor first and leaves the Quick Prompt window, or the notch, open; before, it closed the window or the island and the editor with it. The floating window's key monitor (`NexusAgentService`) asks the shared session, and in the notch `NexusAgentQuickPromptView` reports the open editor as the Agents page's layer, which the island already closes before itself. This app's Esc still does not stop a reply. (3) The pill's field keeps its own placeholder ("Ask … anything…") while the session list is open, in the window and in the notch; it used to say "Filter sessions" although what is typed there is sent as a prompt. Only the list's own filter field says that now, and the chrome flag `keepsPromptPlaceholderOverSessions` is gone. None of this was run in this app: the caret and Esc were checked on the standalone app's window, which shows the same view. Four of the 44 images change, the session-list state as the floating window and as the notch, light and dark (`02-sessions-drawer-*`), and in each only that placeholder's words differ; the other 40 are identical byte for byte.
- **2026-10-09**: Three changes in the shared Nexus Agent code, and all three change this app. (1) A turn that cannot start is reported. When the agent's program is not installed, or starting it fails (agy, Claude or Ollama), the chat already showed an error bubble; now the host is also told of a failed turn, so this app shows its usual "… — Failed" notice in the notch and, when the Quick Prompt window is not on screen (the chat docked in the notch counts as not on screen, as for every other turn), posts its usual failure notification. This app's notice shows the reply, and such a turn has none, so the notch notice has no detail line and the notification no body; the reason is in the chat's bubble and in the notice's `failureDetail`, which this app does not read yet. A command of the user's own whose program is missing is still not reported. (2) The effort and thinking lines of the bot's `.env` are read as the bot reads them. A turn passes agy the effort line exactly as written (`HIGH`, `max`, spaces kept by quotes) where it used to lower-case it, trim it and drop a word it did not know; `AGY_THINKING=true` now means high effort when there is no effort line, where it was ignored; and only the exact word `true` counts, where `GEMINI_THINKING=True` used to. Settings still shows the nearest of its four choices, and saving with the effort untouched leaves such a line as it was; choosing an effort replaces it. Nothing was added to Settings: `AGY_THINKING` is kept by a save, as every key the page does not own is. This app still reads `.env` alone and never its own process environment, which the bot lets win over the file (`apps/desktop/nexus-agent/testdata/README.md`). (3) In the notch, Esc now does close an open model-name editor before the island: `NexusAgentQuickPromptView` listens to the chat session for the editor opening, where it watched a value that only redrew when the service changed, so the island was never told. The snapshot tool opens a finished conversation through the session list now, since sending a prompt with no agent has become a failed turn. All 44 images are identical byte for byte to a render of the branch before this change.
- **2026-10-09**: Failure notices give the reason, a refused command is reported, and the effort setting keeps what the file says. All of it changes this app. (1) A failed turn says why. The "… — Failed" notice in the notch now shows what went wrong under its title, and the failure notification has it as its body: the words of the chat's error bubble, cut as a reply is (its first line that is not blank, 80 characters in the notch, 200 in the notification). Before, both were empty for a turn that failed with no reply, which is most of them. A failed turn that has both part of a reply and words for the failure shows the failure; one with no such words is told as before. Changed in `Services/NexusAgent/VitruvianNexusAgentHost.swift` (this app's own file). (2) A command of the user's own that cannot start is reported. When its program is not installed, its template is empty, or its template would take the program's name from the prompt, the chat already showed an error bubble; now this app also shows its "… — Failed" notice and, away from the chat, its notification, as for agy, Claude and Ollama. (3) The effort setting and the `AGY_THINKING` line of the bot's `.env`. Choosing Automatic on the Settings page now sticks when the file says `AGY_THINKING=true`: the save writes `AGY_THINKING=false` with the empty effort, where before the line was left, the bot went on running at high effort and the page showed High again the next time it read the file. Choosing Low, Medium or High leaves the thinking line alone, as before (the effort line wins over it). A save that does not change the effort no longer writes `high` into the effort line when High came from `AGY_THINKING=true`: both lines stay as they are. A file with an effort word the page has no name for (`max`) together with `AGY_THINKING=true` is now shown as Automatic, not High; turns still pass the word as written, as the bot does, and a save that leaves the effort alone still keeps it. Not changed here: this app's Settings page still has no row for such a word, so it shows Automatic for it (the standalone app's page now shows the word itself).
- **2026-10-09**: A missing program is named, a failure's reason is shown whole, and Settings shows an effort word it does not know as itself. All three change this app. (1) When the provider in use is not agy and its program is not installed, the chat's error bubble, the "… — Failed" notice and the line under Quick Prompt on the Settings page no longer say "The Antigravity CLI (agy) was not found." They name the program that was looked for: "Could not find 'claude' in PATH. Is it installed?", likewise `ollama`, or the first word of a command of the user's own. That sentence is the shared English one in every language, as it already was for a missing command. For agy this app's own sentence is kept word for word, in every language it has. The Settings page now asks the shared engine for the line (`missingProgramText`); `NexusAgentFeatureStrings.missingAgent` is still where the agy sentence comes from. (2) The reason under a "… — Failed" notice and in the failure notification is the whole failure on one line: the non-blank lines of the chat's error bubble joined by single spaces, then cut as before (80 characters in the notch, 200 in the notification). The first line alone was usually only "The agent stopped with an error."; now the program's own complaint follows it. The joining is the shared `NexusAgentTurnNotice.failureSummary`. The standalone app's notification is not changed: it already showed all of the failure's words, line breaks kept, cut to 200. (3) The effort picker on the Settings page has one more row when the bot's `.env` holds an effort word that is none of its four (`max`): the word itself, as "max (from .env)" (that suffix is English in every language). It is the row selected, a save that leaves it alone keeps the word in the file, and picking another row replaces it. Before, such a word was shown as Automatic. The picker is bound to the shared `NexusAgentConfiguration.effortChoice`, the rule the standalone app's page uses; no setting was added.
- **2026-10-09**: The diagram view in the shared chat now hears when its page gives up, and that changes this app. A Mermaid diagram is drawn by a small web page; when the page cannot start the drawing library (offline, or the library did not load) it goes to a `vitruvian-error://` address to say so. The method meant to catch that was written slightly differently from the one WebKit calls, so WebKit never called it and the card stayed an empty box. It is now WebKit's method: the card shows its "could not draw" line with the diagram's source under it, as it was always meant to, and the address is cancelled inside the app instead of being left to the system. Every other page load is allowed, as before. Not covered: a diagram whose own text is wrong is reported by the drawing library inside the page, and still is. The 44 chat images hold no diagram and are identical byte for byte.
- **2026-10-10**: Settings names a command's real program, and that changes this app. For a command of the user's own whose program is written with the model in it (`{model} run {prompt}`), the "Could not find '…' in PATH" line on the Nexus Agent settings page named the placeholder, `{model}`, while the chat's error bubble named the program it had looked for. Both now take the name from one shared function, so the page names the model in use, or the stand-in model (`gemma4:31b-cloud`) when none is set, exactly as the chat does. Every other provider and command is named as before. Not changed: a command with an empty template still gets "Could not find ''" on the page, where the chat says the template is invalid. The 44 chat images are identical byte for byte.
- **2026-10-12**: The notch's AI telemetry page no longer draws its cards over one another, and the provider switch no longer shows a stray "Provider" label that wrapped into it on a narrow island:
  - `NotchAgentSupport`: a row is as tall as its tallest card instead of a fixed 96 pt. A limits card is sized for the allowance rows it draws (`limitRows`, `limitsHeight(rows:)`: 104 / 122 / 164 / 206 pt for one to four, as measured from the drawn card), the spending card is 142 pt (`spendHeight`) and the other small cards 102 pt (`cardHeight`); `height(of:)` and `contentHeight` take the rows per agent, and `telemetryHeight` adds the 84 pt of switches above the cards (`telemetryChromeHeight`), or the empty message's room when there are no cards;
  - `NotchAgentSupport.telemetryFilter(in:)` and `pageProviders(seen:filter:in:)`: the provider tab's rule moved out of the view, and `NotchService.agentsContentHeight` now sizes the island for the tab shown rather than for every agent;
  - `NotchAgentsView`: the cards always sit in a scroll view, which scrolls only when they are taller than the island; each row takes its own height and both cards in it fill it; the Mode and Provider pickers hide their titles (kept for VoiceOver);
  - card polish: a card's title is read whole and what sits beside it gives way; a limits row's percentage keeps its width and its tooltip has the whole forecast; in a paired card the account address drops out beside the plan chip (it stays in the tooltip), the credits chip shows the amount alone, and the spending card's token figures take short labels ("Latest", "30d tok."); the period menu keeps its width;
  - `NotchAgentTests`: the row, page and island heights and the provider tab's rule.
- **2026-10-13**: Launch no longer waits for the Bluetooth permission prompt. macOS holds an app's first Bluetooth read until the person answers "Allow Vitruvian to use Bluetooth?", and asks again after an update because the app is ad hoc signed. `NotchAccessoryService.syncWithPreferences` made that read on the main thread during launch, so until the prompt was answered the app had no menu bar icon and no windows, and looked dead when the prompt sat behind another window:
  - `NotchAccessoryService`: the first read (who is paired and connected) runs on a queue of its own. When it returns, the main thread sets the silent baseline, watches those devices for disconnects and starts watching for connections, in that order, as before. A stop or a restart in between changes `generation`, and a late answer is dropped. Battery readings start at once, as before; they never touched Bluetooth on the main thread. Without permission the read returns nobody and no connection is ever announced.
  - `NotchAccessoryEnvironment` and `NotchAccessoryBaseline` are new: what the service reaches outside itself (the preference gate, the first read, the connection observer, the battery samples and the monitor's switch), so a test can stand in for them. `NotchAccessoryService.init(environment:)` and `connectionState` are `package`.
  - `NotchAccessoryLaunchTests` (new, in the `notch` suite) holds the first read the way the prompt does; `mutation_checks.py` plants the main-thread read and the missing generation check.
- **2026-10-13**: `Tests/mutation_checks.py` checks that its mutations still match the code, in the pull request that moves the code. Four of them quoted lines that the change adding tool pages (#3182) had reworded, so the weekly run would have stopped at the first. No app code changes.
  - The four quote the code as it is now and plant the same regressions: closing the island's controls no longer stops the music reader; a tool that starts with the app is stopped for being idle; a tool's detail never scrolls its long lists; a running tool is not told the language changed.
  - `--check --app-dir <folder>` is new: it only reads, and lists every mutation whose quoted text is not in its file exactly once. `:mutation_fixtures_test` runs it with the pull-request tests. The full run makes the same check before it builds anything, and names all of them at once.
- **2026-10-13**: A tool folder whose files are read-only can be added, and a copy that failed no longer blocks the next. A folder copied out of a build has folders nothing may be written in; the app's copy kept those modes, macOS will not move such a folder to another place, and what was left beside the tool's place could not be deleted, so every later attempt for that tool failed too.
  - `Services/Platform/External/ToolFolders.swift` (written by VitruvianSoftware): in the app's copy the person may read, write and enter every folder and read and write every file; no other bit of a mode changes, and a link is neither followed nor changed. Whatever the app deletes there (what an earlier copy left, the copy an update replaces, a removed tool's copy and what it saved) is opened up first when it cannot be deleted as it is.
  - `Tests/ToolFoldersReadOnlyTests.swift` (new, in the `tool-runtime` suite). Three older checks stood a read-only data folder in for one that cannot be deleted; it can be now, so they use a folder macOS holds as it is (`UF_IMMUTABLE`, Finder's Locked) and expect what they did.
  - `Tests/mutation_checks.py` (upstream file): eight mutations for the above, and the one that quotes the delete follows the reworded line.
- **2026-10-15**: The closed island's left-hand resting wing hides the cycling agent allowance ring (`NotchAgentMark`) when a tool's own words or elapsed seconds replace the agent allowance percentage on the right-hand wing (`RestingStatus.showsAgentMark`).
  - `Core/Platform/ToolStatus.swift` (written by VitruvianSoftware): `RestingStatus.showsAgentMark(_:)` returns `true` only when the right-hand wing is `.allowance`.
  - `UI/Notch/NotchAgentStrip.swift` (upstream file): `NotchAgentRestingWing` draws `NotchAgentMark` only while `RestingStatus.showsAgentMark(restingWing)` is `true`, so a tool's status mark stands alone beside its own words or timer.
  - `Tests/ToolStatusTests.swift` and `Tests/mutation_checks.py` (upstream file): verify `RestingStatus.showsAgentMark` across `.allowance`, `.words`, `.seconds`, and `nil`, plus a mutation check in the `platform` suite.
- **2026-10-21**: The Nexus Agent chat header is split into two rows so its title, badges and folder name do not crush one another in the island, the Pin and Dock buttons are left out when the chat is already docked in the island, Plan has one switch, the conversation has Top and Bottom jump buttons, and an OpenCode turn's tool steps are gathered into one reply bubble with the code or path each tool ran:
  - `UI/NexusAgent/NexusAgentQuickPromptView.swift` (upstream file): passes `isPinned: nil` and `dockToNotch: nil` to `NexusAgentChatChrome` when `embeddedInNotch` is `true`, and `Tests/NexusAgentTests.swift` checks that an embedded chat hides both buttons.
  - Shared `NexusAgentUI` (`NexusAgentChatView.swift`, `NexusAgentChatControls.swift`, `NexusAgentMessageBubble.swift`, `NexusAgentChatStrings.swift`) and `NexusAgentCore` (`NexusAgentEngine.swift`): two-row `chatHeader` with `.fixedSize()` on `Resumed` and the message count pill, `minWidth: 50, maxWidth: 160` on `ChatWorkingDirectoryBadge`, single `ModeToggleStrip` above the follow-up bar, floating Top/Bottom scroll buttons (`⌘↑` / `⌘↓`), single-line tool summary headers, and OpenCode transcript coalescing with `state.title` and `input.code`/`path`/`pattern`/`url` extraction (`bazel/nexus_agent_shared.sha256` updated).

## Tracking and porting upstream

Upstream ships fixes and features most days: 150 commits landed in the four days
after the import. This fork keeps up with a ledger, a tool, a daily watch and a
weekly sync.

- **The ledger**, [`upstream/ledger.tsv`](upstream/ledger.tsv), lists every
  upstream commit since the import, oldest first, and what this fork did with it:
  - `pending`: not decided, or worth porting but not ported yet;
  - `ported`: its ref is the PR that ported it;
  - `skipped`: its ref says why.

  Its `# base` line is the upstream commit the import matches, with its tree.

  A merge commit is listed only when it changed something of its own beyond
  joining its parents: a conflict resolution, or a fix made in the merge itself.
  Upstream sometimes lands a fix that way (`848b6042` reworked the fixed Space
  order inside a merge), and those changes are in no other commit. A merge that
  only resolved conflicts between two sides this fork ports anyway is `skipped`
  with that reason.
- **The tool**, run as `bazel run //apps/desktop/vitruvian:track_upstream -- <command>`:
  - `status` lists the upstream commits not yet in the ledger, and how many are
    pending.
  - `triage` adds them to the ledger. A commit that touches only paths the import
    left out (CI, upstream's README and changelog, brand artwork) is marked
    `skipped`; the rest are `pending`.
  - `show <sha>` prints an upstream commit, with where each of its files lives in
    this tree.
  - `port <sha>...` applies upstream commits to this tree. It is a first pass; see
    "Porting" below.

  `bazel test //apps/desktop/vitruvian:upstream_test` tests the tool and checks
  the ledger's format.
- **The watch**, `.github/workflows/vitruvian-upstream-watch.yaml`, runs daily. It
  keeps one issue, "Upstream vorssaint-utils: commits to triage and port", that
  lists the untriaged and pending commits. It comments when new upstream commits
  appear, and closes the issue when nothing is left.
- **The weekly sync**, [`upstream/SYNC.md`](upstream/SYNC.md), is what an agent
  follows to port everything pending and land it. A Claude Code routine runs it
  every Monday morning (Pacific). The routine holds only the schedule and a
  pointer to that file, so the steps change through pull requests like any
  other file here.

Upstream rewrites its history now and then: the import's commit `aa6ddcb9` was
replaced by `e80abdb1`, with the same tree, after the import. The tool follows
such rewrites. It finds the base again by its tree, and ledger rows by their
`git patch-id`.

### Triage

Run `triage` and commit the ledger, then decide each pending commit:

- **Port** fixes and features that apply to this fork.
- **Skip**, with the reason as the ref:
  - upstream's brand, servers, update feed, community links or donation prompts,
    which the fork must never use (`TRADEMARKS.md`);
  - code this fork removed, such as `BundleMigration` and the upstream install
    migrations;
  - upstream's release bookkeeping: version bumps, changelog and release notes;
  - what the refactor already covers.
- **Leave pending** what is worth porting but not ported yet.

### Porting

1. Group pending commits by feature (one upstream PR, or a feature and its
   follow-up fixes) and port each group in its own PR, oldest first: later
   commits build on earlier ones.
2. Run `port <sha>...` to apply them in order. For each file the tool:
   - finds where the file lives now (the refactor renamed or split most of them);
   - rewrites upstream's names to this fork's;
   - three-way merges the upstream change into this fork's copy, ignoring the
     `package` modifiers the module split added, then puts them back where this
     fork had them;
   - gives a new declaration `package` when its neighbours of the same kind
     have it, since what another module uses must be `package`, and gives a new
     type `package` when a `package` declaration's signature names it;
   - flags, for init review, a stored property the merge added to a type whose
     cross-module initializer this fork wrote out ("Spelled out because a
     memberwise initializer never leaves its module") when that initializer
     does not take it;
   - flags, for preference review, a new `@AppStorage(DefaultsKey.x)` whose
     key this fork declares in `Preferences.swift`: here it is read through
     `@AppStorage(Preferences.x)`, so its default cannot drift;
   - does not merge `Tests/generate_sources.py`, whose generated test copies
     this fork retired. It reports the change with the upstream patch, so that
     the test it feeds can be ported as a behavioural test;
   - does not merge upstream's `Core/Defaults.swift`, which this fork split into
     `DefaultsKey.swift`, `Preferences.swift` and `Defaults.swift`. It reports
     the change with the upstream patch, to apply where each part now lives;
   - does not merge a merge commit's own changes: they are a diff against what
     git would have merged (`git show --remerge-diff`, git 2.36 or later), and
     never apply to this tree as they are. It writes them to a patch, to apply
     by hand.

   It never rewrites upstream's domains, repository or services. Any line that
   still names upstream is reported for brand review. Its `report.md` lists what
   is left: conflicts, files it could not place (with the upstream patch), binary
   files (check them for upstream's brand before copying), and upstream renames
   and deletions. On 2026-10-06, applying each of the 126 pending commits on its
   own to this tree:
   - 32 commits applied cleanly;
   - of the files the commits change, 405 merged or were added cleanly and 341
     have conflicts to resolve.

   The conflicts are mostly where the refactor rewrote the code, and in source-pin
   tests this fork replaced. Porting in order lowers the count.
3. Finish the port by hand:
   - Resolve the conflicts against the refactored code (`REFACTOR.md`).
   - Keep the Swift 6 rules in `AGENTS.md`.
   - Give a new declaration `package` when another module uses it.
   - Port upstream's tests as behavioural tests: a test that reads source text
     fails `source_lints_test`, and a generated-copy fixture (a `Fixture` class
     whose typealiases stand in for app types) fails its shadowing check.
     Where the code under test is private, move the rule into a function the
     test can call, the way `KillProcessService.sorted(_:by:ascending:)` and
     `RadialMenuProfile.deleting(_:from:)` were. If that needs seams that
     don't exist yet, port the fix without the test and say so in the commit.
   - Run `bazel test //apps/desktop/vitruvian:source_lints_test`, which runs on
     Linux, before pushing. Compile errors only show on macOS.
   - Keep upstream's notice (`Copyright (C) 2026 Vorssaint`) on files that are
     upstream's code.
4. If `build.sh` changed, run `bazel run //apps/desktop/vitruvian:sync_sources`.
   Then build and test (see `README.md`).
5. In the same PR, set each ported commit's ledger row to `ported` with the PR
   number (`#1234`). Set any commit dropped while porting to `skipped`, with why.
6. Title the commit `fix(vitruvian): ...` or `feat(vitruvian): ...`, because
   release-please writes the release notes from these. End the message with
   `Upstream-Commit: vorssaint/vorssaint-utils@<sha>` for each upstream commit,
   and `Co-authored-by:` for each upstream author.

The ledger is the dated record of what was ported from upstream. "Modifications"
above still logs this fork's own changes, including any change of behaviour a
port makes beyond upstream's.
