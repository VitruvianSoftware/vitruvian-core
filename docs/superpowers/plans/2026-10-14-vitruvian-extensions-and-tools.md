# Vitruvian Extensions & Tools Implementation Plan

> **For agentic workers:** Every task in this plan requires review and 100% alignment with Claude Code (Opus 5.5) before moving to the next task.

**Goal:** Promote Protocol 2 island panels to first-class Dynamic Island sections in Explore (`NotchSectionsView`) with inline drag-to-reorder and show/hide customization alongside built-in sections, keep `Tools` (`QuickLauncherView`) focused on quick tools and one-shot commands, and unify Settings/Catalog presentation as **Extensions & Tools**.

**Gate 1:** aligned 2026-10-14. Every task runs `unit_tests`, `selftest`, `source_lints_test` and `mutation_fixtures_test` before its review, and updates `mutation_checks.py` in the same change as the code a check guards.

**Spec:** [`docs/superpowers/specs/2026-10-14-vitruvian-extensions-and-tools-design.md`](../specs/2026-10-14-vitruvian-extensions-and-tools-design.md)

---

## Task 1: Unified Section Model, Ordering & Extension Section Entries (`VitruvianCore`, `VitruvianServices`, `VitruvianUI`)

**Gate 1:** aligned 2026-10-14 (all blocker fixes and recommendations accepted, including `extension:<toolID>`).

**Files:**
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Core/Notch/NotchSupport.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/ExternalToolStore.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/ToolPanels/ToolIslandTile.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch/NotchView.swift` (the `PanelOrderItem` conformance only)
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/NotchSettings.swift` (use the shared show/hide and order helpers)
- Modify, only where an exhaustive `switch` over `NotchQuickAction` needs the new case: `Services/Notch/NotchService.swift`, `UI/Settings/NotchLayoutEditor.swift`
- Modify: `apps/desktop/vitruvian/Tests/NotchTests.swift`
- Modify: `apps/desktop/vitruvian/Tests/ToolPanelScreensTests.swift`
- Modify if a quoted line moves: `apps/desktop/vitruvian/Tests/mutation_checks.py`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md` (dated `## Modifications` entry for the files above)

**Steps:**
1. In `NotchSupport.swift` (Core; no Services imports):
   - Add `package enum NotchSectionItem: Hashable, Identifiable, Sendable` with `.module(NotchModule)` and `.tool(ToolID)`, `rawValue` / `id` (`module.rawValue` or `tool.rawValue`), and `init?(rawValue:)` (parse `NotchModule(rawValue:)` first; else `ToolID(raw)` only when `!isBundledForm`).
   - Add the ordering helpers on top of `QuickToolsSupport.tileOrder` / `savedTileOrder`:
     - `NotchSupport.sectionOrder(live: [NotchSectionItem], from raw: String) -> [NotchSectionItem]`: saved tokens, then any `NotchModule.allCases` missing from them in default order, then `tileOrder`. Existing module-only strings order exactly as today.
     - `NotchSupport.savedSectionOrder(afterMoving live: [NotchSectionItem], previous raw: String, installedTools: Set<ToolID>) -> String`: when `raw` is empty the previous order is the full default `NotchModule.allCases` list (hidden and unavailable included). Well-formed = a `NotchModule.rawValue`, or a `ToolID` in `installedTools` (uninstalled extensions are dropped). Unavailable or hidden entries keep their slots.
   - Move `NotchSettings.moduleBinding`'s logic into `NotchSupport.isModuleShown(_ module:, in defaults:) -> Bool` and `NotchSupport.setModuleShown(_ module:, _ shown:, in defaults:)`, which flip `notchHiddenModules` **and** the section's own `Preferences.notch*Enabled` (timer, camera, calendar, notifications, agents, watch). `NotchSupport.modules(in:)` stays behaviourally identical.
   - Add generic `NotchSupport.filteredItems<T>(_:query:searchableText:)` and `NotchSupport.adjacentItem<T: Equatable>(to:items:backwards:)`; `filteredModules` / `adjacentModule` forward to them unchanged in behaviour.
   - Extend `NotchQuickAction` with `.extensionPanel(ToolID)`: `id` = `"extension:" + toolID.rawValue`; `init?(id:)` parses the `extension:` prefix (rest must be a valid, non-bundled `ToolID`). An unknown `control.<x>` still returns nil. `optionalActions` is unchanged (extensions come from a Services lookup in Task 3). `isAvailable(in:)` returns `false` for `.extensionPanel` (Core cannot see installed tools).
   - Any exhaustive switch elsewhere gets the new case with the narrowest safe behaviour (no-op with a comment naming Task 2/3); no user-visible behaviour change in Task 1.
2. In `UI/Notch/NotchView.swift`: add `extension NotchSectionItem: PanelOrderItem {}` beside `extension NotchModule: PanelOrderItem {}`.
3. In `NotchSettings.swift`: `moduleBinding` calls `NotchSupport.isModuleShown` / `setModuleShown` (keeping its `@AppStorage` reads so SwiftUI still refreshes), and the section list's order setter saves through `NotchSupport.savedSectionOrder(afterMoving:previous:installedTools:)` so a reorder in Settings keeps any extension IDs already in the saved string.
4. In `ExternalToolStore.swift`:
   - Add `package func availableIslandPanels() -> [ToolPanelHost.Key]`: the `.island` panel key for every record with `installed[id]?.tool.panel(in: .island) != nil`, whatever `showsInIsland` says. Do **not** filter on `standing` (every installed tool has one); switched-off and held tools are already absent from `installed`.
   - Leave `islandPanels()` byte-for-byte as it is (a mutation check quotes it).
5. In `ToolIslandTile.swift`:
   - Add `ToolIslandEntry.available(store:host:language:) -> [ToolIslandEntry]` built from `store.availableIslandPanels()`, reusing the existing `ToolIslandEntry` init (do not copy the `99+` badge line; a mutation check quotes it).
   - Add a tile that draws an extension section in `NotchSectionsView`'s style (`NotchLayout.sectionTileWidth` × `sectionTileHeight`, active/highlighted states, badge count or dot from `ToolIslandEntry`). It is not wired into Explore until Task 2.
6. Tests:
   - `NotchTests.swift`: `NotchSectionItem` round-trip and rejection (bundled form, empty, malformed); `sectionOrder` with a legacy module-only string (unchanged order), mixed modules and tools, missing modules appended; `savedSectionOrder` keeps hidden/unavailable slots, first save keeps hidden modules' default slots, drops uninstalled tool IDs; `setModuleShown` flips both preferences for timer (and the rest) and a hidden-then-shown timer appears in `modules(in:)`; `NotchQuickAction` `extension:<id>` round-trip, `control.<unknown>` → nil, `extension:` with a bundled or malformed id → nil, `isAvailable` false for extensions.
   - `ToolPanelScreensTests.swift`: `availableIslandPanels()` includes a tool with `showsInIsland == false` that `islandPanels()` excludes; excludes a tool with no island panel; `ToolIslandEntry.available` maps titles, symbols and badges.
7. Add the dated `UPSTREAM.md` entry and update `mutation_checks.py` in the same change if any quoted line moves.
8. Run and get green:
   `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:mutation_fixtures_test`
   Then review with Claude Code (Opus 5.5) before Task 2.

---

## Task 2: Promote Extension Island Panels to Top-Level Explore & Add Inline Customize Mode (`NotchService`, `NotchView`, `NotchSectionsView`, `QuickLauncherView`)

**Files:**
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Services/Notch/NotchIslandServices.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Services/Notch/NotchService.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Services/Notch/NotchLocalEventRoute.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch/NotchSectionsView.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch/NotchView.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Notch/NotchAgentStrip.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/QuickLauncher/QuickLauncherView.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift`
- Modify: `apps/desktop/vitruvian/Tests/NotchIslandFixture.swift`
- Modify: `apps/desktop/vitruvian/Tests/NotchDestinationTests.swift`

**Steps:**
1. In `NotchIslandServices.swift` & `NotchIslandFixture.swift`:
   - Update `SystemNotchIslandServices.visibleToolCount` to `QuickLauncherService.shared.visibleTiles.count` (since extension island panels are now top-level sections, not tiles inside `Tools`).
   - Expose `islandPanels: [ToolPanelHost.Key]`, `availableIslandPanels: [ToolPanelHost.Key]`, `openToolPanel: ToolPanelHost.Key?`, `openIslandToolPanel(_ key: ToolPanelHost.Key)`, and `islandPanelTitle(_ key: ToolPanelHost.Key, language: AppLanguage) -> String` on `NotchIslandServices` (with defaults in `RecordingIslandServices` for tests).
2. In `NotchService.swift` & `NotchLocalEventRoute.swift`:
   - Add `@Published package var editingSections = false`. Reset `editingSections = false` when `showingSections` turns off, when a section is selected, or when the island collapses/tears down.
   - Add `sections: [NotchSectionItem]` (visible built-in modules + visible extension island panels, ordered by `NotchSupport.sectionOrder(live:from:)`), `availableSectionItems: [NotchSectionItem]`, and `filteredSectionItems: [NotchSectionItem]`.
   - Change `highlightedSection` to `NotchSectionItem?` (one state; update its ~15 readers and the test).
   - Add `@Published package var currentSection: NotchSectionItem` and drive the spec's case table (Escape collapses; collapse closes the panel and "last page" reopens it; watch `ToolPanelHost.island` and fall back to Explore or the first section when the tool crashes, is held, switched off, uninstalled or hidden; app panel or metric closes the extension; opening an extension stops the built-in page underneath, e.g. the camera).
   - Add `selectSection(_ item: NotchSectionItem)` and `openExtensionSection(_ key: ToolPanelHost.Key)`:
     - Selecting `.module(let module)` closes any open extension island panel (`services.closeToolPanel()`) and opens `module`.
     - Selecting `.tool(let toolID)` first closes any current island panel (`ToolPanelHost.open` neither closes the old one nor reopens an already-open one), then opens its island panel via `services.openIslandToolPanel(key)`; if the open is refused, stay on (or return to) Explore. On success it sets `showingSections = false`, `editingSections = false`, and refreshes presentation at `pageBudget` height.
   - Update `expandedSize`: when `services.showsToolPanel` is true (and `!showingSections && !showingAppPanel && selectedMetric == nil`), size the island to `pageBudget` height (`pageSize(..., module: .tools, toolCount: nil)` or dedicated `extensionPanel: true`).
   - Update `keepsWorkingSurface`: include `(expanded && showingSections && editingSections)` and `(expanded && !showingSections && services.showsToolPanel)`.
   - Update `NotchLocalEventRoute.handle(_:)`: when `showingSections && editingSections`, `Escape` sets `editingSections = false` before closing Explore or collapsing; Return, arrows, Tab and the scroll wheel do not pick or page sections while editing.
   - Update `reopeningDestination` and `open()`: support `Preferences.notchHomeModule` holding a `ToolID.rawValue` for a visible extension section; an unavailable one falls back to the first visible section, else Explore.
   - Replace the five `service.modules.isEmpty` checks in `NotchView` (empty state, Explore button) with the full section list.
   - Update `activateQuickAction`: handle `.extensionPanel(let id)` by opening that extension's section.
3. In `NotchSectionsView.swift` & `NotchView.swift`:
   - In `NotchView.swift`:
     - When `showingSections` is true and `sectionQuery.isEmpty`, show the Customize header button (`slider.horizontal.3` $\rightarrow$ `checkmark`, accessibility label `customize` / `done`) that toggles `service.editingSections`.
     - When `!showingSections && !showingAppPanel && selectedMetric == nil`, if `let key = panels.island`, display the extension panel's localized title in the header and render `hostedPanel(key, height: size.height)` as the top-level page!
   - In `NotchSectionsView.swift`:
     - Render `NotchSectionItem` tiles (both `.module` and `.tool` with badge support) in the paged/searchable gallery.
     - When `service.editingSections` is true, render the inline customization view with:
       - The Tools editor's grid, reused exactly (its column logic, **no** `ScrollView`), of visible `NotchSectionItem`s using `PanelReorderableItem` and a top-right `minus.circle.fill` hide button (hidden on the last visible section, as a nicety only).
       - A divider and `FlowLayoutLite` hidden tray for hidden built-in modules whose feature is on and hidden extension island panels (`showsInIsland == false`), each with a `plus.circle.fill` button calling `NotchSupport.setModuleShown` / `ExternalToolStore.setShowsInIsland`.
       - The island is sized to full page height while editing; the search field is hidden.
4. In `NotchAgentStrip.swift`:
   - When tapping a non-green tool status mark on the closed island, call `NotchService.shared.openExtensionSection(page)` directly (without requiring `.tools` to be in `modules`).
5. In `QuickLauncherView.swift` & `QuickLauncherService.swift`:
   - Remove `islandPages`, `QuickLauncherIslandItem`, and `islandToolPage` from `QuickLauncherView.swift` so `Tools` shows only quick tools and one-shot commands.
   - Remove `ToolPanelHost.shared.island` checks from `QuickLauncherService.swift`, and delete the now-unused `ToolsRailItem.page`.
6. Strings: add `NotchStrings` customize/done, hide/show and hidden-tray heading in all 15 languages.
7. Mutation checks (same change): Escape leaves edit mode first; empty state uses the full section list; picking a built-in section closes an extension page.
8. Rewrite the `AGENTS.md` passage (around lines 680–684) that says tools may not add island pages, and add this PR's dated `UPSTREAM.md` entry.
9. Run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:mutation_fixtures_test`, do the `hello-panel-swift` by-hand check, and review with Claude Code (Opus 5.5).

---

## Task 3: Dynamic Island Settings & Layout Editor Parity for Extensions (`NotchSettings`, `NotchContentEditor`, `NotchLayoutEditor`)

**Files:**
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/NotchContentEditor.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/NotchSettings.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/NotchLayoutEditor.swift`
- Modify: `apps/desktop/vitruvian/Tests/NotchTests.swift`

**Steps:**
1. In `NotchSettings.swift`'s section list (`sectionList` / `orderedModules`, around line 338; there is no `NotchSectionsContentEditor`):
   - Observe `ToolRegistry.shared` and `ToolPanelHost.shared`.
   - Build the unified list of available `NotchSectionItem`s (available built-in `NotchModule`s + `ExternalToolStore.shared.availableIslandPanels()`), ordered by `NotchSupport.sectionOrder`.
   - Allow dragging any `NotchSectionItem` to reorder (`NotchSupport.savedSectionOrder(afterMoving:previous:installedTools:)`) and toggling visibility (`NotchSupport.setModuleShown` for `.module`, `ExternalToolStore.shared.setShowsInIsland(id, shown)` for `.tool`).
2. In `NotchSettings.swift`:
   - Update the `When reopening` picker (`Preferences.notchHomeModule`) to list visible extension island sections alongside visible `NotchModule`s, `App panel`, and `Explore`; an unrecognised or unavailable value no longer silently shows Controls.
3. In `NotchLayoutEditor.swift`:
   - Observe `ToolRegistry.shared` / `ToolPanelHost.shared`. Add a Services-layer lookup for extension quick actions (availability, title, symbol) and include available extension island sections (`.extensionPanel(id)`, saved as `extension:<toolID>`) in the *"Open a section"* palette and button action menu. `NotchService.activateQuickAction(.extensionPanel(id))` opens the section.
4. Add unit tests in `NotchTests.swift`; run `unit_tests`, `selftest`, `source_lints_test`, `mutation_fixtures_test`; add this PR's dated `UPSTREAM.md` entry; review with Claude Code (Opus 5.5).

---

## Task 4: Unified "Extensions & Tools" Settings Card, Badging, Localization & Provenance (`ExternalToolsSection`, `ExternalToolStrings`, `UPSTREAM.md`)

**Files:**
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/Core/ExternalToolStrings.swift`
- Modify only if the settings search index needs the new card name: `Services/Settings/FeatureHubText.swift`, `Core/Settings/SettingsSearchSupport.swift` (neither mentions this card today)
- Modify: `apps/desktop/vitruvian/Tools/ByHandRules.swift`, `apps/desktop/vitruvian/Tools/ByHand.swift` (they find the card by its English name)
- Modify: `packages/vitruvian-sdk` README and docs that say island panels appear in "the Tools area" (docs only; avoid touching `Panels.swift`, which would need the protocol pin refreshed)
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/ExternalToolsSection.swift`
- Modify: `apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/ExternalToolCatalogueSheet.swift`
- Modify: `apps/desktop/vitruvian/Tests/ExternalToolStringsTests.swift`
- Modify: `apps/desktop/vitruvian/Tests/ExternalToolScreensTests.swift`
- Modify: `apps/desktop/vitruvian/Tests/mutation_checks.py`
- Modify: `apps/desktop/vitruvian/AGENTS.md`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`

**Steps:**
1. In `ExternalToolStrings.swift`:
   - Add localized strings in all 15 `AppLanguage`s for `kindExtension` ("Extension") and `kindTool` ("Tool"), and update `sectionTitle` ("Extensions & Tools") and `sectionSubtitle` so the Features card and Catalog sheet clearly describe both Extensions and Tools.
   - Update `ExternalToolStringsTests.swift` (`count` 68 → 70 and assertions) and `Tests/mutation_checks.py` if any quoted string changes.
2. In `ExternalToolsSection.swift`:
   - Add `ExternalToolRow.Kind` (`.extensionPackage` when `listed.tool?.panels.isEmpty == false`, `.tool` otherwise) and `kindBadge: String` (`strings.kindExtension` vs `strings.kindTool`) on `ExternalToolRow`.
   - Draw the subtle capsule badge next to the publisher/version line in `ExternalToolsSection`.
3. Update `Tests/ExternalToolScreensTests.swift` to verify `ExternalToolRow.kind` and `kindBadge` for panel-bearing extensions vs command-only tools.
4. The catalog subtitle must not promise island pages to every Extension (some only have Settings or window panels). Update the by-hand tool's card lookup. Add a dated entry under `## Modifications` in `apps/desktop/vitruvian/UPSTREAM.md` listing every modified upstream file.
5. Run all verification targets (`unit_tests`, `selftest`, `source_lints_test`, `mutation_fixtures_test`, `sources_in_sync_test`, `tool_protocol_pin_test`, `upstream_test`; then `bazel run //tools/license:verify` and `bazel run //tools/conformance:check`, which are run targets, not tests), repeat the `hello-panel-swift` by-hand check, and get final Opus 5.5 sign-off.
