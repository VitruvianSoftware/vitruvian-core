# Vitruvian Tool Registry (part 2: tiles and wheel slices for any tool) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a tool that is in none of the app's fixed lists put a tile on the Quick panel and a slice on the radial wheel, reorderable and hideable like our own, with a sample tool in development builds to prove it by hand.

**Architecture:** Part 1 put one registry behind three surfaces but each surface still listed only its own enum. This part adds a second source to two of them: the Quick panel grid holds a `QuickLauncherTile` (an enum case or a registry command id), and the wheel editor's Tool picker lists registry commands beside the built-in tools. Saved layouts keep their text format; an id the app does not recognise yet is kept in place, not dropped. A sample tool, registered only when the app is built with a flag, is the one tool outside every list.

**Tech Stack:** Swift 6 (AppKit and SwiftUI), Bazel with `--config=macos-app`, the app's own `TestSuite` harness run under Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (sub-project 1, part 2). **Builds on:** part 1, `docs/superpowers/plans/2026-10-08-vitruvian-tool-registry.md`, which must be merged first ([VitruvianSoftware/vitruvian-core PR #2946](https://github.com/VitruvianSoftware/vitruvian-core/pull/2946)). Executors read all three.

All paths are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## What this plan leaves out, and why

**Shortcuts for registry commands are part 3.** They are their own subsystem: a store, a registrar, a row on the Shortcuts page, and a rework of clash detection across eight places that record a shortcut. Reading for this plan found facts part 3 must start from, recorded here so they are not lost:

- The closest existing pattern is the command bar's per-row shortcuts: `Services/CommandBar/CommandBarRowShortcuts.swift` (store) and `CommandBarService.syncRowHotkeys` (registrar, ids `200 + index`).
- After any shortcut recording, `ShortcutCapture.end()` gives keys back only through `FeatureRuntime.shared.sync(...)`. A registrar tied to no feature stays dead after the first recording unless `end()` also calls it. This fails silently.
- There is no single clash check. Each recorder chains its own. The role recorder on the Shortcuts page does not check command-bar row shortcuts today, so a user can already bind one combination twice. Part 3 should add one aggregator and fix that with it.
- Hotkey ids are hand-picked literals. Two already appear to share id 25 (Nexus Agent and the first screen-capture tool); that is being checked separately. Part 3 needs a free range (2000 and up is unused) or a single allocator.
- Ten of our fifteen commands already have a shortcut through `GlobalShortcutRole`. Part 3 must not offer a second one for the same action.

Also out: letting a registry command host a view inside the Quick panel, a tile's options card, and a live "active" state for a tile. Those need the content vocabulary from spec section 7.1.

## Decisions this plan makes

| # | Decision | Why |
|---|---|---|
| 1 | Our own commands ask for the Quick panel only when a tile already runs them. | Part 1 marked all 15 for the panel. Five have no tile. Listing them would give every user five new tiles, two duplicating tiles that exist and one that opens the panel from inside itself. |
| 2 | A surface offers a registry command only if none of that surface's fixed lists already offers it. | One action, one entry. |
| 3 | In the wheel editor a registry command appears in the existing **Tool** picker, not as a new kind of action. | The user is choosing a tool either way. It also needs no new user-facing string. |
| 4 | A saved order keeps an id it does not recognise, in place, if the id is well formed. | A tool that registers after launch, or is switched off for a while, must find its tile where the user left it. |
| 5 | The sample tool's code is always compiled and tested; only the line that registers it is behind a build flag. | CI tests it on every run, and no release build can show it. |

## Global Constraints

- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file that carries the Vorssaint header gets a dated entry under "Modifications" in `UPSTREAM.md`, in the same commit. Add one entry, `- **<date>**: Tool registry, part 2 (...)`, in Task 1 and append sub-bullets in later tasks.
- Module order is `Core <- Design <- Services <- UI <- App`. All four library modules, the app and the tests build in Swift 6 mode. (Part 1's plan said Services did not; that was wrong.)
- What another module uses is `package`. Every initializer is written out.
- **No new user-facing string.** Every user-facing string needs all 15 `AppLanguage` cases. The sample tool's two English strings are the one exception: they are never registered in a release build.
- **No saved identifier is renamed, and no saved format changes.** The Quick panel order stays a comma-joined string under `quickLauncherItemOrder`; the hidden set stays a sorted comma-joined string under `quickLauncherHiddenItems`.
- **Nothing a user of a release build can see changes.** With no tool outside the fixed lists registered, every surface lists exactly what it lists today.
- A preference is read and written through `defaults[Preferences.x]`. `source_lints_test` counts every `forKey: DefaultsKey.x` in the code and only lets that count fall.
- Tests are behavioural. No test reads a source file as text.
- `Tests/mutation_checks.py` quotes exact source text. These lines must stay byte-identical, or the mutation is updated in the same commit:
  - `        case .screenshot: return .screenshotCapture` in `Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift`
  - `        guard isToolAvailable(id.tool) else { return false }` in `Sources/Vitruvian/Services/Platform/ToolRegistry.swift`
  - the `switch item {` arms of `QuickLauncherService.run(_ item:)` beginning `        case .keepAwake, .micMute:` (Task 4 keeps that function's body untouched for this reason)
  - the `.screenRecorder` line of `QuickLauncherView.icon(for:state:)`
- Build and test through Bazel only, from the repository root. A full unit run now completes on a Mac in use:
  ```sh
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest
  ```
  One suite: add `--test_arg=--suite=platform` (repeat the flag for several).
- The `notch` and `switcher` suites have scroll checks that failed while the Mac's display was asleep. Run with the screen awake and unlocked.
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren 2>/dev/null)"
  ```
  Shell state does not persist between commands; put this in the same command as the commit.
- Commit titles use `refactor(desktop): ...`. Nothing here changes a release build's behaviour, so no release is cut.

## Review Focus

Failure modes the spec implies that are most likely to reach a user. Each has a test in the task named.

1. **A release build gains tiles.** With only our own tools registered, the Quick panel shows exactly today's tiles and the wheel editor's Tool picker exactly today's tools. (Task 1, Task 4, Task 5)
2. **A saved layout loses a tile's place.** A tool registers after the order was last saved, or is gone for one launch. Its id stays where the user left it. (Task 3)
3. **A saved order or wheel holds a malformed id** (`""`, `"a/b/c"`, `"not an id"`). It is dropped; everything else loads; nothing crashes. (Task 3)
4. **A tool is switched off in the Features hub while its tile is showing.** The tile goes and the selection stays inside the grid. A tile whose command cannot run does nothing when pressed. (Task 1, Task 4)
5. **An existing `command` slice whose tool is not installed is opened in the editor.** The picker still shows a selection and saving does not change the slice. (Task 5)

---

### Task 1: Registry housekeeping

Four small changes the rest of the plan stands on.

**Files:**
- Modify: `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift`
- Modify: `Sources/Vitruvian/Services/Platform/ToolRegistry.swift`
- Create: `Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift`
- Modify: `Sources/Vitruvian/Services/Platform/BuiltinTools.swift` (`install`)
- Modify: `Sources/Vitruvian/Services/FeatureRuntime.swift` (`Environment.live`, the `availabilityDidChange` closure)
- Modify: `Tests/ToolPlatformTests.swift`
- Modify: `UPSTREAM.md`

**Interfaces:**
- Consumes: part 1's `ToolID`, `CommandID`, `ToolSurface`, `CommandDescriptor`, `ToolDescriptor`, `ToolRegistry`, `BuiltinCommand`, `RadialMenuTool.command`, `QuickLauncherItem.command`.
- Produces:
  - `ToolRegistry.noteAvailabilityChanged()`
  - `ToolRegistry.extraCommands(on surface: ToolSurface) -> [CommandDescriptor]`
  - `ToolDescriptor.init?` and `CommandDescriptor.init?` now refuse empty names, titles and symbols. **`CommandDescriptor.init` becomes failable.**
  - `ToolID.init?` refuses two dots in a row; `ToolDescriptor.init?` refuses an id with no dot that names no `AppFeature`.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, add `housekeeping(suite)` to the end of `run(_:)`, and add:

```swift
    static func housekeeping(_ suite: TestSuite) {
        // Ids and descriptors refuse what would mislead later.
        suite.expect(ToolID("com..acme") == nil, "an id cannot hold two dots in a row")
        suite.expect(CommandID("screenshot/a..b") == nil, "a command name cannot hold two dots in a row")
        let tool = ToolID("com.acme.deploys")!
        let open = CommandID(tool: tool, name: "open")!
        suite.expect(CommandDescriptor(id: open, title: " ", symbol: "star", surfaces: [.radial]) == nil
                         && CommandDescriptor(id: open, title: "Open", symbol: "", surfaces: [.radial]) == nil,
                     "a command needs a title and a symbol")
        suite.expect(ToolDescriptor(id: tool, name: "", symbol: "star", commands: []) == nil
                         && ToolDescriptor(id: tool, name: "Deploys", symbol: " ", commands: []) == nil,
                     "a tool needs a name and a symbol")
        suite.expect(ToolDescriptor(id: ToolID("notAFeature")!, name: "X", symbol: "star", commands: []) == nil,
                     "an id with no dot must name one of the app's own features")
        suite.expect(ToolDescriptor(id: ToolID("screenshot")!, name: "X", symbol: "star", commands: []) != nil,
                     "an id that names a feature is one of the app's own tools")

        // A change of hub availability is something a surface can see.
        let world = World()
        let before = world.registry.revision
        world.registry.noteAvailabilityChanged()
        suite.expect(world.registry.revision == before + 1, "a hub change is a change surfaces can see")

        // A surface offers a registry command only when its own fixed list does not.
        do {
            try world.add("screenshot", "capture", surfaces: [.radial, .quickPanel, .commandBar])
            try world.add("com.acme.deploys", "open", surfaces: [.radial, .quickPanel, .commandBar])
        } catch {
            suite.expect(false, "registering two distinct tools succeeds, got \(error)")
        }
        suite.expect(world.registry.extraCommands(on: .radial).map(\.id.rawValue) == ["com.acme.deploys/open"],
                     "the wheel is offered only what no built-in tool slice runs")
        suite.expect(world.registry.extraCommands(on: .quickPanel).map(\.id.rawValue) == ["com.acme.deploys/open"],
                     "the panel is offered only what no built-in tile runs")
        suite.expect(world.registry.extraCommands(on: .commandBar).count == 2,
                     "the bar has no fixed list of commands to hold back")

        // The app's own tools, as a release build registers them.
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        let tiles = Set(QuickLauncherItem.allCases.compactMap { $0.command?.id })
        suite.expect(Set(shipped.commands(on: .quickPanel).map(\.id)) == tiles,
                     "a built-in command asks for the panel only when a tile runs it")
        suite.expect(shipped.extraCommands(on: .quickPanel).isEmpty && shipped.extraCommands(on: .radial).isEmpty,
                     "with only the app's own tools, no surface gains an entry")
    }
```

`World.add` builds a `CommandDescriptor` with a non-failable call today. Step 3 makes that initializer failable, so in `World.add` change

```swift
            let command = CommandDescriptor(id: id, title: "plain \(name)", symbol: "star", surfaces: surfaces)
```
to
```swift
            let command = CommandDescriptor(id: id, title: "plain \(name)", symbol: "star", surfaces: surfaces)!
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `value of type 'ToolRegistry' has no member 'noteAvailabilityChanged'`.

- [ ] **Step 3: Tighten the descriptors**

In `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift`:

In `ToolID.isValidPart`, change the guard to also refuse a doubled dot:

```swift
        guard !text.isEmpty, text.count <= maxLength, !text.hasPrefix("."), !text.hasSuffix("."),
              !text.contains("..") else {
            return false
        }
```

Add, directly above `package struct CommandDescriptor`:

```swift
/// Text a person will read: not empty, and not only spaces.
private func isPresentable(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

Replace `CommandDescriptor`'s initializer with:

```swift
    /// Nil without a title and a symbol: a command a surface lists must have
    /// something to show.
    package init?(id: CommandID, title: String, symbol: String, surfaces: Set<ToolSurface>) {
        guard isPresentable(title), isPresentable(symbol) else { return nil }
        self.id = id
        self.title = title
        self.symbol = symbol
        self.surfaces = surfaces
    }
```

Replace `ToolDescriptor`'s initializer with:

```swift
    /// Nil when a command belongs to another tool or is declared twice, when
    /// the name or symbol is empty, or when an id with no dot names none of
    /// the app's own features. So a tool that exists is always consistent,
    /// and an outside tool can never pass for one of ours.
    package init?(id: ToolID, name: String, symbol: String, commands: [CommandDescriptor]) {
        guard commands.allSatisfy({ $0.id.tool == id }),
              Set(commands.map(\.id)).count == commands.count,
              isPresentable(name), isPresentable(symbol),
              !id.isBundledForm || AppFeature(rawValue: id.rawValue) != nil else { return nil }
        self.id = id
        self.name = name
        self.symbol = symbol
        self.commands = commands
    }
```

Every existing call of `CommandDescriptor(...)` must now unwrap. Find them:

Run: `grep -rn "CommandDescriptor(id:" Sources Tests`
Expected: `BuiltinTools.swift` (one, inside a `.map`) and the tests. Fix the tests by adding `!` (they pass known-good values). `BuiltinTools` is fixed in Step 5.

- [ ] **Step 4: Add the registry pieces**

In `Sources/Vitruvian/Services/Platform/ToolRegistry.swift`, replace the doc comment above `revision` with:

```swift
    /// Bumped when a tool is registered or removed, a handler or a name is
    /// set, or the hub says a tool was switched on or off
    /// (`noteAvailabilityChanged`). A handler's own `isRunnable` can still
    /// change without it.
```

and add, directly after `unregister(_:)`:

```swift

    /// Called by the feature runtime when a tool is switched on or off in the
    /// hub, so a view that lists commands redraws. Never call this while a
    /// view is being drawn.
    package func noteAvailabilityChanged() {
        revision += 1
    }
```

Create `Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

extension ToolRegistry {
    /// The commands a surface should add to its own fixed list: those that
    /// ask for it and that the list does not already offer. One action, one
    /// entry. With only the app's own tools registered this is empty for the
    /// wheel and the panel.
    package func extraCommands(on surface: ToolSurface) -> [CommandDescriptor] {
        let offered: Set<CommandID>
        switch surface {
        case .radial: offered = Set(RadialMenuTool.allCases.map(\.command.id))
        case .quickPanel: offered = Set(QuickLauncherItem.allCases.compactMap { $0.command?.id })
        case .commandBar: offered = []
        }
        return commands(on: surface).filter { !offered.contains($0.id) }
    }
}
```

- [ ] **Step 5: Stop our own commands asking for the panel without a tile**

In `Sources/Vitruvian/Services/Platform/BuiltinTools.swift`, replace the body of `install(into:)` with:

```swift
        // A built-in command asks for the panel only when a tile runs it:
        // the others have no tile today, and listing them would put new
        // tiles in front of everyone.
        let tiled = Set(QuickLauncherItem.allCases.compactMap(\.command))
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            let own = BuiltinCommand.allCases.filter { $0.feature == feature }
            let commands = own.compactMap { command in
                CommandDescriptor(id: command.id, title: feature.rawValue, symbol: feature.symbolName,
                                  surfaces: tiled.contains(command) ? [.radial, .quickPanel] : [.radial])
            }
            guard commands.count == own.count,
                  let tool = ToolDescriptor(id: id, name: feature.rawValue, symbol: feature.symbolName,
                                            commands: commands) else {
                assertionFailure("the built-in tool \(feature.rawValue) could not be described")
                continue
            }
            try? registry.register(tool)
            try? registry.setName(titleProvider(for: feature), for: id)
            for command in own {
                try? registry.setHandler(handler(for: command), for: command.id)
            }
        }
```

`BuiltinCommand` is `Hashable` because it is a raw-value enum, so `Set(…compactMap(\.command))` compiles.

- [ ] **Step 6: Tell the registry when the hub changes**

In `Sources/Vitruvian/Services/FeatureRuntime.swift`, in `Environment.live`, the `availabilityDidChange` closure reads:

```swift
                availabilityDidChange: {
                    CommandBarService.shared.noteHubChange()
                    if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
                },
```

Add one line at its start:

```swift
                availabilityDidChange: {
                    ToolRegistry.shared.noteAvailabilityChanged()
                    CommandBarService.shared.noteHubChange()
                    if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
                },
```

- [ ] **Step 7: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=features --test_arg=--suite=launcher`
Expected: PASS for all three.

One existing expectation in `builtinTools` now needs a second look: `"every built-in command can sit on a wheel"` compares `commands(on: .radial)` with all 15 and still holds, because every command keeps `.radial`.

Run: `grep -c "        guard isToolAvailable(id.tool) else { return false }" Sources/Vitruvian/Services/Platform/ToolRegistry.swift`
Expected: `1`.

- [ ] **Step 8: Commit**

Add at the top of the list under `## Modifications` in `UPSTREAM.md`:

```markdown
- **2026-10-09**: Tool registry, part 2 (`docs/superpowers/plans/2026-10-08-vitruvian-tool-registry-part-2.md`):
  - `Services/FeatureRuntime.swift`: a change of hub availability also tells `ToolRegistry`, so views that list commands redraw.
```

```bash
git add Sources/Vitruvian/Core/Platform/ToolDescriptor.swift Sources/Vitruvian/Services/Platform/ToolRegistry.swift Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift Sources/Vitruvian/Services/Platform/BuiltinTools.swift Sources/Vitruvian/Services/FeatureRuntime.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): tighten tool descriptors and let surfaces see hub changes"
```

---

### Task 2: A sample tool for development builds

The one tool outside every fixed list. Its code is always compiled and tested. It is registered only when the app is built with a flag.

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/SampleTool.swift`
- Modify: `Sources/Vitruvian/main.swift` (after the `BuiltinTools.install()` line)
- Modify: `BUILD` (the `VitruvianLib` target, and one `config_setting`)
- Modify: `README.md` ("Build and test")
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolRegistry`, `ToolDescriptor`, `CommandDescriptor`, `QuickToolHUD.show(icon:message:)`.
- Produces: `SampleTool.id: ToolID` (`dev.vitruvian.sample`), `SampleTool.hello: CommandID` (`dev.vitruvian.sample/hello`), `SampleTool.install(into:say:)`.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `sampleTool(suite)` to the end of `run(_:)`, and add:

```swift
    static func sampleTool(_ suite: TestSuite) {
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)
        suite.expect(registry.tool(SampleTool.id) == nil,
                     "the app's own tools do not include the sample")

        var said: [String] = []
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(registry.extraCommands(on: .quickPanel).map(\.id) == [SampleTool.hello]
                         && registry.extraCommands(on: .radial).map(\.id) == [SampleTool.hello]
                         && registry.commands(on: .commandBar).map(\.id) == [SampleTool.hello],
                     "the sample is the one tool outside every fixed list, on all three surfaces")
        suite.expect(registry.run(SampleTool.hello) && said.count == 1 && !said[0].isEmpty,
                     "running the sample says something once")
        suite.expect(registry.name(for: SampleTool.id, language: .systemDefault)?.isEmpty == false
                         && registry.title(for: SampleTool.hello, language: .systemDefault)?.isEmpty == false,
                     "the sample has a name and a title to show")

        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(registry.commands(on: .commandBar).count == 1, "installing the sample twice registers it once")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'SampleTool' in scope`.

- [ ] **Step 3: Write the sample tool**

Create `Sources/Vitruvian/Services/Platform/SampleTool.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign

/// A tool that is in none of the app's fixed lists, for checking by hand
/// that a surface shows and runs one. `main.swift` registers it only in a
/// build made with `--define=vitruvian_sample_tool=true`; a release build
/// never does, which is why its two strings are plain English.
@MainActor
package enum SampleTool {
    package static let id = ToolID("dev.vitruvian.sample")!
    package static let hello = CommandID(tool: id, name: "hello")!

    /// Safe to call again: a sample already there is left alone. `say` is
    /// what running the command does; the app shows it on screen.
    package static func install(into registry: ToolRegistry = .shared,
                                say: @escaping @MainActor (String) -> Void = { message in
                                    QuickToolHUD.show(icon: "hand.wave", message: message)
                                }) {
        guard registry.tool(id) == nil,
              let command = CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave",
                                              surfaces: [.radial, .quickPanel, .commandBar]),
              let tool = ToolDescriptor(id: id, name: "Sample tool", symbol: "hand.wave", commands: [command])
        else { return }
        try? registry.register(tool)
        try? registry.setHandler(.init(title: { _ in command.title },
                                       run: { say("Hello from the sample tool") }),
                                 for: hello)
    }
}
```

- [ ] **Step 4: Register it behind a build flag**

In `Sources/Vitruvian/main.swift`, directly after the line

```swift
MainActor.assumeIsolated { BuiltinTools.install() }
```

add:

```swift
#if VITRUVIAN_SAMPLE_TOOL
// A tool outside every fixed list, for checking the surfaces by hand. Only
// a build made with --define=vitruvian_sample_tool=true has it.
MainActor.assumeIsolated { SampleTool.install() }
#endif
```

In `BUILD`, directly above the `swift_library(` whose `name = "VitruvianLib"`, add:

```python
# A development build that registers the sample tool (Services/Platform/
# SampleTool.swift), a tool outside every fixed list, so the surfaces can be
# checked by hand:  --define=vitruvian_sample_tool=true
config_setting(
    name = "sample_tool",
    define_values = {"vitruvian_sample_tool": "true"},
)
```

and inside that `swift_library`, directly after the `features = ["swift.enable_v6"],` line, add:

```python
    copts = select({
        ":sample_tool": ["-DVITRUVIAN_SAMPLE_TOOL"],
        "//conditions:default": [],
    }),
```

If the target already has a `copts` attribute, add the `select` to it with `+` instead of adding a second attribute.

In `README.md`, under "Build and test", after the paragraph that ends "they have to be granted again after each rebuild.", add:

````markdown
To check a surface with a tool that is in none of the app's fixed lists, build
with the sample tool registered. No release build has it:

```sh
bazel build --config=macos-app --define=vitruvian_sample_tool=true //apps/desktop/vitruvian:Vitruvian
```
````

- [ ] **Step 5: Run the tests and both builds**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel build --config=macos-app --define=vitruvian_sample_tool=true //apps/desktop/vitruvian:Vitruvian`
Expected: builds. This is the only proof the `#if` block compiles.

- [ ] **Step 6: Commit**

Append to the part 2 entry in `UPSTREAM.md`:

```markdown
  - `main.swift`: registers the sample tool, in a build made with `--define=vitruvian_sample_tool=true` only.
```

```bash
git add Sources/Vitruvian/Services/Platform/SampleTool.swift Sources/Vitruvian/main.swift BUILD README.md Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): add a sample tool that only development builds register"
```

---

### Task 3: A tile that is an enum case or a command, and an order that keeps what it does not know

Pure logic and one small type. Nothing uses them until Task 4.

**Files:**
- Modify: `Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift` (beside `hiddenIDs(from:)`)
- Create: `Sources/Vitruvian/Services/QuickTools/QuickLauncherTile.swift`
- Modify: `Sources/Vitruvian/Services/MenuPanel/PanelLayoutStore.swift` (`PanelOrderItem`, `itemOrder`, two new functions)
- Modify: every type that conforms to `PanelOrderItem` (listed in Step 4)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `CommandID`, `QuickLauncherItem`.
- Produces:
  - `QuickToolsSupport.tileOrder(live: [String], saved: [String]) -> [String]`
  - `QuickToolsSupport.savedTileOrder(afterMoving live: [String], previous saved: [String], isWellFormed: (String) -> Bool) -> [String]`
  - `QuickLauncherTile` (`.builtin(QuickLauncherItem)`, `.command(CommandID)`): `init?(rawValue:)`, `rawValue`, `id`, `builtin`, `commandID`. Conforms to `PanelOrderItem`.
  - `PanelOrderItem` no longer implies `CaseIterable`.
  - `PanelLayout.rawItemOrder(key:) -> [String]`, `PanelLayout.setRawItemOrder(_:key:)`

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, add `tiles(suite)` to the end of `run(_:)`, and add:

```swift
    static func tiles(_ suite: TestSuite) {
        // A tile reads and writes one id, whichever kind it is.
        let enumTile = QuickLauncherTile(rawValue: "screenshot")
        let commandTile = QuickLauncherTile(rawValue: "dev.vitruvian.sample/hello")
        suite.expect(enumTile == .builtin(.screenshot) && enumTile?.rawValue == "screenshot"
                         && enumTile?.builtin == .screenshot && enumTile?.commandID == nil,
                     "a built-in tile keeps the id users already have saved")
        suite.expect(commandTile == .command(SampleTool.hello) && commandTile?.rawValue == "dev.vitruvian.sample/hello"
                         && commandTile?.commandID == SampleTool.hello && commandTile?.builtin == nil,
                     "a command tile is known by its command id")
        for bad in ["", "notATile", "a/b/c", "not an id", "screenshot/"] {
            suite.expect(QuickLauncherTile(rawValue: bad) == nil, "\(bad.debugDescription) is not a tile")
        }

        // Showing: the saved order decides; what it does not name goes after, in the order given.
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "b", "x/1"], saved: []) == ["a", "b", "x/1"],
                     "with nothing saved, tiles keep the order they come in")
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "b", "x/1"], saved: ["x/1", "b", "gone/1", "a"])
                         == ["x/1", "b", "a"],
                     "a saved order places every tile it names")
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "new", "b", "x/1"], saved: ["b", "a"])
                         == ["b", "a", "new", "x/1"],
                     "a tile the saved order does not name goes after those it does")

        // Saving: an id that is not showing now keeps its place.
        let wellFormed: (String) -> Bool = { QuickLauncherTile(rawValue: $0) != nil }
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["screenshot", "keepAwake"],
                                                      previous: ["keepAwake", "dev.vitruvian.sample/hello", "screenshot"],
                                                      isWellFormed: wellFormed)
                         == ["screenshot", "dev.vitruvian.sample/hello", "keepAwake"],
                     "a tile that is not showing now keeps its place in the saved order")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["keepAwake", "screenshot"],
                                                      previous: ["", "a/b/c", "not an id", "keepAwake"],
                                                      isWellFormed: wellFormed)
                         == ["keepAwake", "screenshot"],
                     "a malformed id is dropped from the saved order, and the rest is kept")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["keepAwake"],
                                                      previous: ["micMute", "micMute", "keepAwake"],
                                                      isWellFormed: wellFormed)
                         == ["micMute", "keepAwake"],
                     "an id saved twice is kept once")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: [], previous: [], isWellFormed: wellFormed).isEmpty,
                     "nothing showing and nothing saved saves nothing")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'QuickLauncherTile' in scope`.

- [ ] **Step 3: Write the two order functions**

In `Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift`, directly after `serializeHiddenIDs(_:)`, add:

```swift

    /// The order to show `live` ids in. The saved order places every id it
    /// names; an id it does not name goes after those, in the order given.
    /// Ids the saved order names that are not live are passed over.
    package static func tileOrder(live: [String], saved: [String]) -> [String] {
        let rank = Dictionary(saved.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return live.enumerated().sorted { left, right in
            switch (rank[left.element], rank[right.element]) {
            case let (leftRank?, rightRank?): return leftRank < rightRank
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.offset < right.offset
            }
        }.map(\.element)
    }

    /// The order to save after the person rearranged the tiles that are
    /// showing. An id in the previous order that is not showing now (its tool
    /// is switched off, or has not registered yet) keeps its place, so its
    /// tile returns where it was left. An id that is not well formed is
    /// dropped, and so is a repeat.
    package static func savedTileOrder(afterMoving live: [String], previous saved: [String],
                                       isWellFormed: (String) -> Bool) -> [String] {
        let showing = Set(live)
        var moved = live.makeIterator()
        var seen = Set<String>()
        var result: [String] = []
        for id in saved where seen.insert(id).inserted {
            if showing.contains(id) {
                if let next = moved.next() { result.append(next) }
            } else if isWellFormed(id) {
                result.append(id)
            }
        }
        while let next = moved.next() { result.append(next) }
        return result
    }
```

- [ ] **Step 4: Let a reorderable item be something other than an enum**

In `Sources/Vitruvian/Services/MenuPanel/PanelLayoutStore.swift`, replace

```swift
package protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}
```
with
```swift
/// Something a person can reorder: it has a text id to save and to drag.
/// An enum that conforms is `CaseIterable` in its own right; the Quick
/// panel's tile is not an enum of cases, so the protocol does not ask.
package protocol PanelOrderItem: RawRepresentable, Hashable where RawValue == String {}
```

and change the signature of `itemOrder` from

```swift
    package static func itemOrder<Item: PanelOrderItem>(_ type: Item.Type, key: String) -> [Item] {
```
to
```swift
    package static func itemOrder<Item: PanelOrderItem & CaseIterable>(_ type: Item.Type, key: String) -> [Item] {
```

Directly after `resetItemOrder(key:)`, add:

```swift

    /// The saved order as written, for a list that also holds ids no enum
    /// names. Nothing is dropped here: the caller decides what is well formed.
    package static func rawItemOrder(key: String) -> [String] {
        (defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init)
    }

    package static func setRawItemOrder(_ ids: [String], key: String) {
        defaults.set(ids.joined(separator: ","), forKey: key)
    }
```

Every conforming type got `CaseIterable` from the protocol and now has to say it. Add `CaseIterable` to each of these declarations (and only these):

| File | Declaration to change |
|---|---|
| `Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift` | `package enum QuickLauncherItem: String, PanelOrderItem, Identifiable` → add `, CaseIterable` |
| `Sources/Vitruvian/Services/QuickTools/QuickTogglesService.swift` | `package enum QuickToggleAction: String, PanelOrderItem, Identifiable` |
| `Sources/Vitruvian/UI/MenuPanel/MenuPanelView.swift` | `private enum UtilityPanelItem: String, PanelOrderItem, Identifiable` and `private enum ControlPanelItem: String, PanelOrderItem, Identifiable` |
| `Sources/Vitruvian/UI/MenuPanel/PowerSection.swift`, `SystemSection.swift`, `NetworkSection.swift`, `DiskSection.swift` | `private enum Block: String, PanelOrderItem` in each |

The four `extension X: PanelOrderItem {}` lines (`NotchModule`, `NotchAgentCard`, `NotchControlItem`, `MenuBarMetric`) extend types that are already `CaseIterable`; leave them. If the build says one is not, add `CaseIterable` to that type's own declaration.

Run: `grep -rn "PanelOrderItem" Sources | grep -v "protocol PanelOrderItem"`
Expected: the lines above, the two generic uses in `UI/MenuPanel/PanelLayout.swift`, and the two in `PanelLayoutStore.swift`. Anything else is a conformer this table missed: give it `CaseIterable` too.

- [ ] **Step 5: Write the tile type**

Create `Sources/Vitruvian/Services/QuickTools/QuickLauncherTile.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// One tile of the Quick panel: one of the app's own, or a registry command
/// that no built-in tile runs. Its raw value is what the saved order and the
/// hidden set hold. A built-in tile's is its enum raw value, as it always
/// was; a command's is its command id. The slash tells them apart: no enum
/// raw value has one, and every command id has exactly one.
package enum QuickLauncherTile: Hashable, Identifiable, PanelOrderItem {
    case builtin(QuickLauncherItem)
    case command(CommandID)

    package init?(rawValue: String) {
        if let item = QuickLauncherItem(rawValue: rawValue) {
            self = .builtin(item)
        } else if let id = CommandID(rawValue) {
            self = .command(id)
        } else {
            return nil
        }
    }

    package var rawValue: String {
        switch self {
        case .builtin(let item): return item.rawValue
        case .command(let id): return id.rawValue
        }
    }

    package var id: String { rawValue }

    package var builtin: QuickLauncherItem? {
        if case .builtin(let item) = self { return item }
        return nil
    }

    package var commandID: CommandID? {
        if case .command(let id) = self { return id }
        return nil
    }
}
```

- [ ] **Step 6: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=launcher`
Expected: PASS for both.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds. This is what proves every `PanelOrderItem` conformer still compiles.

- [ ] **Step 7: Commit**

Append to the part 2 entry in `UPSTREAM.md`:

```markdown
  - `Services/MenuPanel/PanelLayoutStore.swift`: `PanelOrderItem` no longer implies `CaseIterable`; `rawItemOrder` and `setRawItemOrder` read and write a saved order without dropping ids no enum names. Each conforming enum now states `CaseIterable` itself.
  - `Core/QuickTools/QuickToolsSupport.swift`: `tileOrder` and `savedTileOrder`, the Quick panel's order with tiles no enum names.
```

```bash
git add -u Sources Tests UPSTREAM.md
git add Sources/Vitruvian/Services/QuickTools/QuickLauncherTile.swift
git status --short
git commit -m "refactor(desktop): a Quick panel tile can be an enum case or a command"
```

Check `git status --short` before committing: only the files this task names may be staged.

---

### Task 4: The Quick panel shows and runs command tiles

**Files:**
- Modify: `Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift`
- Modify: `Sources/Vitruvian/UI/QuickLauncher/QuickLauncherView.swift`
- Modify: `Sources/Vitruvian/Services/Notch/NotchIslandServices.swift` (the protocol requirement and its live implementation)
- Modify: `Sources/Vitruvian/Services/Notch/NotchService.swift` (two uses of `visibleTools.count`)
- Modify: `Sources/Vitruvian/Services/Notch/NotchEventBindings.swift` (the `tools:` publisher)
- Modify: `Tests/NotchIslandFixture.swift`, `Tests/QuickLauncherActionTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: Task 1's `extraCommands(on:)`; Task 3's `QuickLauncherTile`, `tileOrder`, `savedTileOrder`, `rawItemOrder`, `setRawItemOrder`.
- Produces, on `QuickLauncherService`:
  - `Environment` gains `savedTileOrder`, `saveTileOrder`, `commands`, `canRunCommand`, `runCommand`, all with defaults so existing callers compile unchanged
  - `visibleTiles`, `hiddenTiles: [QuickLauncherTile]`; `tileOrderBinding: Binding<[QuickLauncherTile]>`
  - `run(_ tile:)`, `select(_ tile:)`, `setHidden(_ tile:, _:)`
  - `visibleItems`, `hiddenItems`, `run(_ item:)`, `select(_ item:)`, `setHidden(_ item:, _:)` stay, for the built-in tiles; `itemOrderBinding` is removed
- `NotchIslandServices.visibleTools: [QuickLauncherItem]` becomes `visibleToolCount: Int`.

The body of `run(_ item: QuickLauncherItem)` is not edited: a mutation check quotes it.

- [ ] **Step 1: Write the failing tests**

In `Tests/QuickLauncherActionTests.swift`, add `commandTileContracts(suite)` as the last call in `run(_:)`, and add:

```swift
    /// A launcher over doubles that also holds one registry command.
    final class TileWorld {
        var events: [String] = []
        var unavailable: Set<AppFeature> = []
        var saved: [String] = []
        var commands: [CommandDescriptor] = []
        var runnable = true
        var jobs: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

        lazy var launcher: QuickLauncherService = QuickLauncherService(environment: .init(
            isAvailable: { [unowned self] in !self.unavailable.contains($0) },
            itemOrder: { [.keepAwake, .screenshot] },
            islandShowsTools: { false },
            collapseIsland: {},
            showCameraInIsland: { false },
            perform: { [unowned self] in self.events.append("perform \($0.rawValue)") },
            after: { [unowned self] delay, work in self.jobs.append((delay, work)) },
            savedTileOrder: { [unowned self] in self.saved },
            saveTileOrder: { [unowned self] in self.saved = $0 },
            commands: { [unowned self] in self.commands },
            canRunCommand: { [unowned self] _ in self.runnable },
            runCommand: { [unowned self] in self.events.append("command \($0.rawValue)") }))

        func drain() {
            let pending = jobs
            jobs.removeAll()
            pending.forEach { $0.work() }
        }
    }

    static func commandTileContracts(_ suite: TestSuite) {
        let hello = CommandID("dev.vitruvian.sample/hello")!
        let descriptor = CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave", surfaces: [.quickPanel])!

        let plain = TileWorld()
        suite.expect(plain.launcher.visibleTiles == [.builtin(.keepAwake), .builtin(.screenshot)]
                         && plain.launcher.visibleItems == [.keepAwake, .screenshot],
                     "with no command offered, the panel holds exactly its own tiles")

        let world = TileWorld()
        world.commands = [descriptor]
        let launcher = world.launcher
        suite.expect(launcher.visibleTiles == [.builtin(.keepAwake), .builtin(.screenshot), .command(hello)],
                     "a command tile joins after the tiles a saved order names")
        suite.expect(launcher.visibleItems == [.keepAwake, .screenshot],
                     "the built-in tiles are still listed on their own")

        world.saved = ["dev.vitruvian.sample/hello", "screenshot", "keepAwake"]
        suite.expect(launcher.visibleTiles == [.command(hello), .builtin(.screenshot), .builtin(.keepAwake)],
                     "a saved order places a command tile among the others")

        launcher.prepareForPresentation()
        launcher.run(.command(hello))
        suite.expect(world.events.isEmpty && world.jobs.count == 1 && world.jobs[0].delay == 0.15,
                     "a command tile runs after the panel has had time to go")
        world.drain()
        suite.expect(world.events == ["command dev.vitruvian.sample/hello"], "a command tile runs its command once")

        world.events = []
        world.runnable = false
        launcher.run(.command(hello))
        world.drain()
        suite.expect(world.events.isEmpty, "a command tile whose command cannot run does nothing")
        world.runnable = true

        launcher.isEditing = true
        launcher.run(.command(hello))
        world.drain()
        suite.expect(world.events.isEmpty, "a command tile does nothing in edit mode")
        launcher.isEditing = false

        // Digit 1 is the first tile, whatever kind it is.
        launcher.prepareForPresentation()
        launcher.activate(at: 0)
        world.drain()
        suite.expect(world.events == ["command dev.vitruvian.sample/hello"], "the first tile answers to its place, whatever it is")
        world.events = []

        // Reordering saves the tiles showing, and keeps what is not showing.
        world.saved = ["keepAwake", "com.acme.gone/open", "dev.vitruvian.sample/hello", "screenshot"]
        launcher.tileOrderBinding.wrappedValue = [.builtin(.screenshot), .command(hello), .builtin(.keepAwake)]
        suite.expect(world.saved == ["screenshot", "com.acme.gone/open", "dev.vitruvian.sample/hello", "keepAwake"],
                     "reordering keeps the place of a tile that is not showing now")

        // Hiding and showing a command tile.
        launcher.setHidden(.command(hello), true)
        suite.expect(!launcher.visibleTiles.contains(.command(hello)) && launcher.hiddenTiles == [.command(hello)],
                     "a hidden command tile leaves the grid and waits in the tray")
        launcher.setHidden(.command(hello), false)
        suite.expect(launcher.visibleTiles.contains(.command(hello)) && launcher.hiddenTiles.isEmpty,
                     "a command tile shown again returns to the grid")

        // The command goes away while the panel is up.
        launcher.prepareForPresentation()
        launcher.select(.command(hello))
        world.commands = []
        launcher.refreshAvailability()
        suite.expect(!launcher.visibleTiles.contains(.command(hello))
                         && (launcher.selectedIndex ?? 0) < launcher.visibleTiles.count,
                     "a command that goes away takes its tile, and the selection stays inside the grid")
    }
```

`setHidden` writes the hidden set to `UserDefaults.standard`. Under the test runner that is the test binary's own preferences domain, which the runner sweeps afterwards; the test also leaves the set as it found it.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=launcher`
Expected: a build failure, `extra arguments at positions … in call` on the `Environment` initializer, or `no member 'visibleTiles'`.

- [ ] **Step 3: Extend the service's environment**

In `Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift`, in `struct Environment`, after the `after` property add:

```swift
        /// Tile ids in the person's saved order, as written: tiles of either kind.
        package var savedTileOrder: () -> [String]
        package var saveTileOrder: ([String]) -> Void
        /// Registry commands that ask for the panel and that no built-in tile runs.
        package var commands: () -> [CommandDescriptor]
        package var canRunCommand: (CommandID) -> Bool
        package var runCommand: (CommandID) -> Void
```

Replace the `Environment` initializer with (the five new parameters have defaults, so the existing test double compiles unchanged):

```swift
        package init(isAvailable: @escaping (AppFeature) -> Bool,
                     itemOrder: @escaping () -> [QuickLauncherItem],
                     islandShowsTools: @escaping () -> Bool, collapseIsland: @escaping () -> Void,
                     showCameraInIsland: @escaping () -> Bool, perform: @escaping (QuickLauncherItem) -> Void,
                     after: @escaping (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     savedTileOrder: @escaping () -> [String] = { [] },
                     saveTileOrder: @escaping ([String]) -> Void = { _ in },
                     commands: @escaping () -> [CommandDescriptor] = { [] },
                     canRunCommand: @escaping (CommandID) -> Bool = { _ in true },
                     runCommand: @escaping (CommandID) -> Void = { _ in }) {
            self.isAvailable = isAvailable
            self.itemOrder = itemOrder
            self.islandShowsTools = islandShowsTools
            self.collapseIsland = collapseIsland
            self.showCameraInIsland = showCameraInIsland
            self.perform = perform
            self.after = after
            self.savedTileOrder = savedTileOrder
            self.saveTileOrder = saveTileOrder
            self.commands = commands
            self.canRunCommand = canRunCommand
            self.runCommand = runCommand
        }
```

In `static var live`, the call currently ends with the `after:` argument. Add five arguments after it (change the closing `)` of the `after:` line to `,` first):

```swift
                after: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } },
                savedTileOrder: { PanelLayout.rawItemOrder(key: DefaultsKey.quickLauncherItemOrder) },
                saveTileOrder: { PanelLayout.setRawItemOrder($0, key: DefaultsKey.quickLauncherItemOrder) },
                commands: { ToolRegistry.shared.extraCommands(on: .quickPanel) },
                canRunCommand: { ToolRegistry.shared.canRun($0) },
                runCommand: { ToolRegistry.shared.run($0) })
```

- [ ] **Step 4: Hold tiles in the service**

In the same file, replace everything from `package var visibleItems` through the closing brace of `setHidden(_:_:)` (the "Items" section: `visibleItems`, `hiddenItems`, `orderedItems`, `itemOrderBinding`, `setHidden`) with:

```swift
    /// Every tile in the grid, in the person's order.
    package var visibleTiles: [QuickLauncherTile] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedTiles.filter { !hidden.contains($0.rawValue) }
    }

    package var hiddenTiles: [QuickLauncherTile] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedTiles.filter { hidden.contains($0.rawValue) }
    }

    /// The app's own tiles among them, in the same order.
    package var visibleItems: [QuickLauncherItem] { visibleTiles.compactMap(\.builtin) }
    package var hiddenItems: [QuickLauncherItem] { hiddenTiles.compactMap(\.builtin) }

    /// The app's own tiles that are switched on, then the commands on offer,
    /// placed by the saved order.
    private var orderedTiles: [QuickLauncherTile] {
        let builtins = environment.itemOrder().filter { environment.isAvailable($0.feature) }
            .map(QuickLauncherTile.builtin)
        let commands = environment.commands().map { QuickLauncherTile.command($0.id) }
        let live = builtins + commands
        let byID = Dictionary(live.map { ($0.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        return QuickToolsSupport.tileOrder(live: live.map(\.rawValue), saved: environment.savedTileOrder())
            .compactMap { byID[$0] }
    }

    package var tileOrderBinding: Binding<[QuickLauncherTile]> {
        Binding {
            self.orderedTiles
        } set: { newValue in
            self.environment.saveTileOrder(
                QuickToolsSupport.savedTileOrder(afterMoving: newValue.map(\.rawValue),
                                                 previous: self.environment.savedTileOrder(),
                                                 isWellFormed: { QuickLauncherTile(rawValue: $0) != nil }))
            self.objectWillChange.send()
        }
    }

    package func setHidden(_ tile: QuickLauncherTile, _ hidden: Bool) {
        var ids = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        if hidden {
            ids.insert(tile.rawValue)
            // Hiding the tile whose options card is open would orphan the
            // card below a grid that no longer shows its owner.
            if let item = tile.builtin, editingOptionsItem == item { editingOptionsItem = nil }
        } else {
            ids.remove(tile.rawValue)
        }
        hiddenItemsRaw = QuickToolsSupport.serializeHiddenIDs(ids)
        UserDefaults.standard[Preferences.quickLauncherHiddenItems] = hiddenItemsRaw
        clampSelection()
    }

    package func setHidden(_ item: QuickLauncherItem, _ hidden: Bool) {
        setHidden(.builtin(item), hidden)
    }
```

Then make everything that counts or indexes tiles use `visibleTiles`. Replace `activateSelection` and `activate(at:)` with:

```swift
    package func activateSelection() {
        guard let selectedIndex, visibleTiles.indices.contains(selectedIndex) else { return }
        run(visibleTiles[selectedIndex])
    }

    package func activate(at index: Int) {
        guard visibleTiles.indices.contains(index) else { return }
        run(visibleTiles[index])
    }
```

In `moveSelection`, change `let count = visibleItems.count` to `let count = visibleTiles.count`.
In `clampSelection`, change `let count = visibleItems.count` to `let count = visibleTiles.count`.
In `prepareForPresentation`, change `selectedIndex = visibleItems.isEmpty ? nil : 0` to `selectedIndex = visibleTiles.isEmpty ? nil : 0`.

Replace `select(_ item:)` with the pair:

```swift
    /// The pointer's selection. The hovered tile is already in view, so the
    /// rail stays where it is.
    package func select(_ tile: QuickLauncherTile) {
        selectedIndex = visibleTiles.firstIndex(of: tile)
        keyboardIndex = nil
    }

    package func select(_ item: QuickLauncherItem) {
        select(.builtin(item))
    }
```

Directly **above** the existing `package func run(_ item: QuickLauncherItem)` (whose body stays exactly as it is), add:

```swift
    package func run(_ tile: QuickLauncherTile) {
        switch tile {
        case .builtin(let item):
            run(item)
        case .command(let id):
            guard !isEditing, environment.canRunCommand(id) else { return }
            // The same beat the app's own screen-touching tiles get, so the
            // panel is really gone before the command shows anything.
            hide()
            environment.after(0.15) { [weak self] in self?.environment.runCommand(id) }
        }
    }

```

Run: `grep -rn "itemOrderBinding" Sources/Vitruvian/Services/QuickTools Sources/Vitruvian/UI/QuickLauncher`
Expected: one hit, in `QuickLauncherView.swift`. Step 5 replaces it.

- [ ] **Step 5: Draw tiles in the view**

In `Sources/Vitruvian/UI/QuickLauncher/QuickLauncherView.swift`:

Add beside the other observed objects at the top of the view:

```swift
    /// Redraws the grid when a tool registers, leaves, or is switched on or off.
    @ObservedObject private var registry = ToolRegistry.shared
```

Change the two state properties:

```swift
    @State private var hoveredItem: QuickLauncherTile?
    @State private var draggingItem: QuickLauncherTile?
```

In `body`, change `launcher.visibleItems.isEmpty` to `launcher.visibleTiles.isEmpty`, and `!launcher.hiddenItems.isEmpty` to `!launcher.hiddenTiles.isEmpty`. Add, beside the existing `.onChange(of: features.revision, initial: true) { launcher.refreshAvailability() }`:

```swift
        .onChange(of: registry.revision) { launcher.refreshAvailability() }
```

In `grid`, replace every `launcher.visibleItems` with `launcher.visibleTiles` (four places), and `order: launcher.itemOrderBinding` with `order: launcher.tileOrderBinding`.

Change `cell` to take a tile. Its signature becomes `private func cell(_ item: QuickLauncherTile) -> some View`; the parameter keeps the name `item` so the body's other lines need no edit beyond these:

| Line as it is | Change to |
|---|---|
| `let index = launcher.visibleItems.firstIndex(of: item)` | `let index = launcher.visibleTiles.firstIndex(of: item)` |
| `launcher.editingOptionsItem = optionsItem == item ? nil : item` | `launcher.editingOptionsItem = optionsItem == item.builtin ? nil : item.builtin` |
| `.foregroundStyle(.white, optionsItem == item ? Color.accentColor : Color.secondary)` | `.foregroundStyle(.white, optionsItem == item.builtin ? Color.accentColor : Color.secondary)` |

`launcher.run(item)`, `launcher.setHidden(item, true)` and `launcher.select(item)` now resolve to the tile overloads with no edit.

In the hidden tray, change `ForEach(launcher.hiddenItems) { item in` to `ForEach(launcher.hiddenTiles) { item in`.

Add tile versions of the helpers `cell` calls, directly above `// MARK: - Item metadata`. Each hands a built-in tile to the existing helper and answers for a command from the registry:

```swift
    // MARK: - Tile metadata

    private func title(for tile: QuickLauncherTile) -> String {
        switch tile {
        case .builtin(let item): return title(for: item)
        case .command(let id):
            return registry.title(for: id, language: l10n.language) ?? registry.command(id)?.title ?? id.name
        }
    }

    private func icon(for tile: QuickLauncherTile) -> String {
        switch tile {
        case .builtin(let item): return icon(for: item)
        case .command(let id): return registry.command(id)?.symbol ?? "puzzlepiece.extension"
        }
    }

    /// A command tile has no state of its own to show.
    private func isActive(_ tile: QuickLauncherTile) -> Bool {
        tile.builtin.map { isActive($0) } ?? false
    }

    private func iconColor(_ tile: QuickLauncherTile) -> Color {
        tile.builtin.map { iconColor($0) } ?? .primary.opacity(0.85)
    }

    private func iconBackground(_ tile: QuickLauncherTile, isSelected: Bool, isHovered: Bool) -> Color {
        if let item = tile.builtin { return iconBackground(item, isSelected: isSelected, isHovered: isHovered) }
        if notchSize != nil { return .white.opacity(isSelected || isHovered ? 0.14 : 0.065) }
        return Color.primary.opacity(isSelected || isHovered ? 0.1 : 0.07)
    }

    /// Only the app's own tiles have an options card.
    private func hasQuickOptions(_ tile: QuickLauncherTile) -> Bool {
        tile.builtin.map { hasQuickOptions($0) } ?? false
    }
```

Do not edit the existing enum-typed `title(for:)`, `icon(for:)`, `isActive`, `iconColor`, `iconBackground`, `hasQuickOptions`, `optionsCard` or `hostedUtility`, or the two `package static` functions: tests call them, and a mutation check quotes one line.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian 2>&1 | grep -E "error:" | head`
Expected: no output. If an error names an ambiguous overload inside `cell`, the call has a literal the compiler cannot place; write the tile out, for example `title(for: item as QuickLauncherTile)`.

- [ ] **Step 6: Let the island count tiles of both kinds, and resize when the registry changes**

In `Sources/Vitruvian/Services/Notch/NotchIslandServices.swift`, in the protocol change

```swift
    var visibleTools: [QuickLauncherItem] { get }
```
to
```swift
    /// How many tiles the Tools page shows now, of either kind.
    var visibleToolCount: Int { get }
```
and in the live implementation change
```swift
    package var visibleTools: [QuickLauncherItem] { QuickLauncherService.shared.visibleItems }
```
to
```swift
    package var visibleToolCount: Int { QuickLauncherService.shared.visibleTiles.count }
```

In `Sources/Vitruvian/Services/Notch/NotchService.swift`, change both `services.visibleTools.count` to `services.visibleToolCount`.

In `Tests/NotchIslandFixture.swift`, change `var visibleTools: [QuickLauncherItem] = []` to `var visibleToolCount = 0`.

Run: `grep -rn "visibleTools" Sources Tests`
Expected: no output. If a test assigns `visibleTools = [...]`, assign `visibleToolCount` the count of that array instead.

In `Sources/Vitruvian/Services/Notch/NotchEventBindings.swift`, the `tools:` publisher merges three publishers and drops the three values they emit on subscription:

```swift
                tools: {
                    let launcher = QuickLauncherService.shared
                    return launcher.$isEditing.map { _ in () }
                        .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () })
                        .dropFirst(3).receive(on: DispatchQueue.main).eraseToAnyPublisher()
                },
```

Add the registry's revision as a fourth, and drop four:

```swift
                tools: {
                    let launcher = QuickLauncherService.shared
                    // Four publishers, each of which emits once on subscription:
                    // the count dropped below has to match the count merged.
                    return launcher.$isEditing.map { _ in () }
                        .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () },
                               ToolRegistry.shared.$revision.map { _ in () })
                        .dropFirst(4).receive(on: DispatchQueue.main).eraseToAnyPublisher()
                },
```

- [ ] **Step 7: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=launcher --test_arg=--suite=platform --test_arg=--suite=notch`
Expected: PASS for all three. The existing `launcher` checks pass unchanged: they use the built-in overloads, and with no command offered `visibleTiles` holds exactly the tiles `visibleItems` held.

Run: `bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS. The lint counts `forKey: DefaultsKey.x` calls. The two new uses are `key:` arguments to `PanelLayout`, as the existing one is, so the count does not change.

- [ ] **Step 8: Commit**

Append to the part 2 entry in `UPSTREAM.md`:

```markdown
  - `Services/QuickTools/QuickLauncherService.swift`: the grid holds `QuickLauncherTile`s, the app's own tiles plus registry commands no tile runs; a reorder keeps the place of a tile that is not showing.
  - `UI/QuickLauncher/QuickLauncherView.swift`: draws a command tile from the registry and redraws when the registry changes.
  - `Services/Notch/NotchIslandServices.swift`, `Services/Notch/NotchService.swift`, `Services/Notch/NotchEventBindings.swift`: the island counts tiles of both kinds and resizes when the registry changes.
```

```bash
git add Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift Sources/Vitruvian/UI/QuickLauncher/QuickLauncherView.swift Sources/Vitruvian/Services/Notch/NotchIslandServices.swift Sources/Vitruvian/Services/Notch/NotchService.swift Sources/Vitruvian/Services/Notch/NotchEventBindings.swift Tests/NotchIslandFixture.swift Tests/QuickLauncherActionTests.swift UPSTREAM.md
git commit -m "refactor(desktop): show registry commands as Quick panel tiles"
```

---

### Task 5: The wheel editor offers registry commands, and the wheel shows their own symbol

**Files:**
- Modify: `Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift` (`availableItems`)
- Modify: `Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift` (the `extension RadialMenuItem`; the wheel's `icon`)
- Modify: `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift` (`RadialItemEditor`: `availableTools` region, the kind picker, `kindBinding`, `payloadEditor`; the row badge)
- Modify: `Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift` (`chipIcon`)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: Task 1's `extraCommands(on:)` and `noteAvailabilityChanged()`.
- Produces:
  - `RadialMenuService.availableItems(_:registry:isFeatureAvailable:toolIsRunnable:)`, a `package static` function a test can call
  - `RadialMenuItem.resolvedSymbolName(registry:)` (in the UI module)
  - `RadialToolChoice` (in the UI module): one entry of the editor's Tool picker

Decision 3: in the editor a registry command is a choice in the **Tool** picker. The saved slice still has kind `command`; the editor shows it as a Tool.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, add `wheel(suite)` to the end of `run(_:)`, and add:

```swift
    static func wheel(_ suite: TestSuite) {
        let world = World()
        do {
            try world.add("com.acme.deploys", "open", surfaces: [.radial])
            try world.add("com.acme.paused", "wake", surfaces: [.radial], runnable: false)
        } catch {
            suite.expect(false, "registering two distinct tools succeeds, got \(error)")
        }
        let open = RadialMenuItem(kind: .command, payload: "com.acme.deploys/open")
        let paused = RadialMenuItem(kind: .command, payload: "com.acme.paused/wake")
        let gone = RadialMenuItem(kind: .command, payload: "com.acme.gone/open")
        let app = RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")
        let screenshot = RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)
        let folder = RadialMenuItem(kind: .submenu, children: [gone, open])
        let emptyFolder = RadialMenuItem(kind: .submenu, children: [gone, paused])

        func shown(_ items: [RadialMenuItem], toolsRun: Bool = true) -> [RadialMenuItem] {
            RadialMenuService.availableItems(items, registry: world.registry,
                                             isFeatureAvailable: { _ in true },
                                             toolIsRunnable: { _ in toolsRun })
        }
        suite.expect(shown([open, paused, gone, app]) == [open, app],
                     "the wheel shows a command slice only while its command can run")
        suite.expect(shown([screenshot]) == [screenshot] && shown([screenshot], toolsRun: false).isEmpty,
                     "a built-in tool slice follows its own rule, as before")
        let kept = shown([folder, emptyFolder])
        suite.expect(kept.count == 1 && kept.first?.children == [open],
                     "a folder keeps the slices that can run, and goes when none can")

        // A command slice draws its command's own symbol unless the person chose one.
        suite.expect(open.resolvedSymbolName(registry: world.registry) == "star",
                     "a command slice draws its command's symbol")
        var chosen = open
        chosen.symbolName = "bolt"
        suite.expect(chosen.resolvedSymbolName(registry: world.registry) == "bolt",
                     "a symbol the person chose wins")
        suite.expect(gone.resolvedSymbolName(registry: world.registry) == gone.defaultSymbolName
                         && app.resolvedSymbolName(registry: world.registry) == app.effectiveSymbolName,
                     "a slice with no command to ask draws what it drew before")

        // The editor's Tool picker: the app's tools, then commands no tool slice runs.
        let choices = RadialToolChoice.all(tools: [.screenshot, .keepAwake], registry: world.registry, keeping: gone)
        suite.expect(choices.map(\.tag) == ["tool:screenshot", "tool:keepAwake", "command:com.acme.deploys/open",
                                            "command:com.acme.gone/open"],
                     "the Tool picker lists the app's tools, then runnable commands, then the slice's own missing one")
        suite.expect(RadialToolChoice.all(tools: [.screenshot], registry: ToolRegistry(isAvailable: { _ in true }),
                                          keeping: screenshot).map(\.tag) == ["tool:screenshot"],
                     "with no command on offer, the Tool picker lists exactly the app's tools")
        var edited = RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)
        RadialToolChoice.apply("command:com.acme.deploys/open", to: &edited)
        suite.expect(edited.kind == .command && edited.payload == "com.acme.deploys/open",
                     "choosing a command makes the slice a command slice")
        RadialToolChoice.apply("tool:keepAwake", to: &edited)
        suite.expect(edited.kind == .tool && edited.payload == "keepAwake", "choosing a tool makes it a tool slice again")
        suite.expect(RadialToolChoice.tag(of: open) == "command:com.acme.deploys/open"
                         && RadialToolChoice.tag(of: screenshot) == "tool:screenshot",
                     "a slice knows which choice it is")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `type 'RadialMenuService' has no member 'availableItems'` (the instance method is private) or `cannot find 'RadialToolChoice' in scope`.

- [ ] **Step 3: Make the wheel's filter testable**

In `Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift`, replace the private `availableItems(_:)` with:

```swift
    /// Wheels only show what can actually run today: tools whose feature was
    /// uninstalled in the hub disappear instead of leaving a dead slice.
    private func availableItems(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        Self.availableItems(items, registry: .shared)
    }

    /// The rule itself, with everything it reads handed in, so it can be
    /// checked against a registry of doubles.
    package static func availableItems(_ items: [RadialMenuItem], registry: ToolRegistry,
                                       isFeatureAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                                       toolIsRunnable: (RadialMenuTool) -> Bool = { $0.isRunnable() })
        -> [RadialMenuItem] {
        items.compactMap { item in
            var item = item
            if let tool = item.tool, !toolIsRunnable(tool) { return nil }
            if item.kind == .command {
                guard let id = item.commandID, registry.canRun(id) else { return nil }
            }
            if item.kind == .quickToggle, !isFeatureAvailable(.quickToggles) { return nil }
            if item.kind == .windowLayout, !isFeatureAvailable(.windowLayout) { return nil }
            if item.kind == .submenu {
                item.children = availableItems(item.children, registry: registry,
                                               isFeatureAvailable: isFeatureAvailable,
                                               toolIsRunnable: toolIsRunnable)
                if item.children.isEmpty { return nil }
            }
            return item
        }
    }
```

- [ ] **Step 4: Give a command slice its command's symbol, and write the picker's model**

In `Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift`, inside the existing `extension RadialMenuItem` (the one that holds `displayName`), directly after `usesFileIcon`, add:

```swift

    /// The symbol to draw: the one the person chose, else for a command slice
    /// its command's own, else what the kind draws by default. Core cannot
    /// see the registry, so this lives here beside `displayName`.
    @MainActor package func resolvedSymbolName(registry: ToolRegistry = .shared) -> String {
        if symbolName.isEmpty, let commandID, let symbol = registry.command(commandID)?.symbol {
            return symbol
        }
        return effectiveSymbolName
    }
```

Directly after the closing brace of that extension, add:

```swift

/// One entry of the editor's Tool picker: one of the app's tools, or a
/// registry command no tool slice runs. The person is choosing a tool either
/// way; which kind of slice that makes is the editor's business.
package struct RadialToolChoice: Identifiable, Equatable {
    package let tag: String
    package let title: String
    package var id: String { tag }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(tag: String, title: String) {
        self.tag = tag
        self.title = title
    }

    private static let toolPrefix = "tool:"
    private static let commandPrefix = "command:"

    /// The choice a slice is, or nil when it is not a tool of either kind.
    package static func tag(of item: RadialMenuItem) -> String? {
        switch item.kind {
        case .tool: return toolPrefix + item.payload
        case .command: return commandPrefix + item.payload
        default: return nil
        }
    }

    /// Makes `item` the slice a choice stands for.
    package static func apply(_ tag: String, to item: inout RadialMenuItem) {
        if tag.hasPrefix(commandPrefix) {
            item.kind = .command
            item.payload = String(tag.dropFirst(commandPrefix.count))
        } else if tag.hasPrefix(toolPrefix) {
            item.kind = .tool
            item.payload = String(tag.dropFirst(toolPrefix.count))
        }
    }

    /// The app's tools that can run, then the registry commands the wheel
    /// may add that can run. `keeping` is the slice being edited: its own
    /// choice stays in the list even when its command cannot run or is not
    /// registered, so the picker always has its selection to show.
    @MainActor package static func all(tools: [RadialMenuTool], registry: ToolRegistry = .shared,
                                       keeping item: RadialMenuItem,
                                       language: AppLanguage = L10n.shared.language) -> [RadialToolChoice] {
        var choices = tools.map { tool in
            RadialToolChoice(tag: toolPrefix + tool.rawValue,
                             title: tool.feature.hubTitle(Strings.localized(language), hub: FeatureStrings.hub(language)))
        }
        for command in registry.extraCommands(on: .radial) where registry.canRun(command.id) {
            choices.append(RadialToolChoice(tag: commandPrefix + command.id.rawValue,
                                            title: registry.title(for: command.id, language: language) ?? command.title))
        }
        if let own = tag(of: item), !choices.contains(where: { $0.tag == own }) {
            let title = item.commandID.flatMap { registry.title(for: $0, language: language) } ?? item.payload
            choices.append(RadialToolChoice(tag: own, title: title))
        }
        return choices
    }
}
```

In the same file, in the wheel's `icon`, change the final branch's `Image(systemName: item.effectiveSymbolName)` to `Image(systemName: item.resolvedSymbolName())`.

In `Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift`, in `chipIcon`, change `Image(systemName: item.effectiveSymbolName)` to `Image(systemName: item.resolvedSymbolName())`.

In `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift`, in the row badge (`RadialItemRow`), change `Image(systemName: item.effectiveSymbolName)` to `Image(systemName: item.resolvedSymbolName())`.

Run: `grep -rn "effectiveSymbolName" Sources/Vitruvian/UI`
Expected: no output. (The definition in `Core/RadialMenu/RadialMenuSupport.swift` stays.)

- [ ] **Step 5: Offer commands in the editor's Tool picker**

In `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift`, in `RadialItemEditor`:

Add beside the other observed objects of `RadialItemEditor`:

```swift
    /// Redraws the picker when a tool registers, leaves, or is switched on or off.
    @ObservedObject private var registry = ToolRegistry.shared
```

Directly after the `availableQuickToggles` property, add:

```swift

    /// Every tool this slice could be: the app's own, and registry commands
    /// no tool slice runs.
    private var toolChoices: [RadialToolChoice] {
        RadialToolChoice.all(tools: availableTools, registry: registry, keeping: item, language: l10n.language)
    }

    private var toolChoiceBinding: Binding<String> {
        Binding(get: { RadialToolChoice.tag(of: item) ?? "" },
                set: { RadialToolChoice.apply($0, to: &item) })
    }
```

In the kind `Picker`, change

```swift
                    if !availableTools.isEmpty {
                        Text(text.kindTool).tag(RadialMenuItem.Kind.tool)
                    }
```
to
```swift
                    if !toolChoices.isEmpty {
                        Text(text.kindTool).tag(RadialMenuItem.Kind.tool)
                    }
```

Replace the whole of `kindBinding` with the version below. Three things change: a command slice shows as a Tool; the `.tool` and `.command` arms become one; and the first choice is read before the kind changes, so the slice's old target is not offered back as a choice.

```swift
    /// Changing the action type clears targets that no longer make sense but
    /// keeps the custom name and icon. A command slice is shown as a Tool:
    /// which kind of slice a tool makes is settled by the choice, below.
    private var kindBinding: Binding<RadialMenuItem.Kind> {
        Binding(get: { item.kind == .command ? .tool : item.kind }, set: { kind in
            let shown: RadialMenuItem.Kind = item.kind == .command ? .tool : item.kind
            guard kind != shown else { return }
            let firstTool = RadialToolChoice.all(tools: availableTools, registry: registry,
                                                 keeping: RadialMenuItem(kind: .app),
                                                 language: l10n.language).first
            item.kind = kind
            shortcutMessage = nil
            faviconStatus = nil
            if kind != .url { item.customIconData = nil }
            switch kind {
            case .tool, .command:
                item.payload = ""
                // The first choice may be a command: applying it sets the kind too.
                if let firstTool { RadialToolChoice.apply(firstTool.tag, to: &item) }
            case .quickToggle: item.payload = availableQuickToggles.first?.rawValue ?? ""
            case .windowLayout: item.payload = WindowLayoutAction.leftHalf.rawValue
            case .media: item.payload = RadialMenuMediaKey.playPause.rawValue
            default: item.payload = ""
            }
            if kind != .submenu { item.children = [] }
        })
    }
```

In `payloadEditor`, replace the two arms

```swift
        case .tool:
            Picker(text.toolLabel, selection: $item.payload) {
                ForEach(availableTools) { tool in
                    Text(tool.feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
                        .tag(tool.rawValue)
                }
            }
        case .command:
            Picker(text.toolLabel, selection: $item.payload) {
                ForEach(ToolRegistry.shared.commands(on: .radial), id: \.id) { command in
                    Text(ToolRegistry.shared.title(for: command.id, language: l10n.language) ?? command.title)
                        .tag(command.id.rawValue)
                }
            }
```
with the single arm
```swift
        case .tool, .command:
            Picker(text.toolLabel, selection: toolChoiceBinding) {
                ForEach(toolChoices) { choice in
                    Text(choice.title).tag(choice.tag)
                }
            }
```

`RadialMenuSupport.isValidPayload` already accepts a well-formed command id, so `saveDisabled` needs no change. A slice whose command is not registered stays valid and saves unchanged; the wheel leaves it off until its tool returns.

- [ ] **Step 6: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=utilities --test_arg=--suite=settings --test_arg=--suite=overlays`
Expected: PASS for all four.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `grep -c "        case .screenshot: return .screenshotCapture" Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift`
Expected: `1`.

- [ ] **Step 7: Commit**

Append to the part 2 entry in `UPSTREAM.md`:

```markdown
  - `Services/RadialMenu/RadialMenuService.swift`: the wheel's "what can run" rule is a static function that takes its registry.
  - `UI/RadialMenu/RadialMenuView.swift`: `resolvedSymbolName` draws a command slice with its command's own symbol; `RadialToolChoice` is the editor's Tool picker.
  - `UI/Settings/RadialMenuSettings.swift`, `UI/Settings/RadialMenuVisualCanvas.swift`: the editor's Tool picker lists registry commands no tool slice runs, and a command slice is edited as a Tool.
```

```bash
git add Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): offer registry commands in the wheel editor"
```

---

### Task 6: Guard, document, and check by hand

**Files:**
- Modify: `Tests/mutation_checks.py`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (section 12, sub-project 1 row)
- Modify: `UPSTREAM.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Plant two regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of the `MUTATIONS` list (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("built-in commands with no tile ask for the panel", "platform",
     "Sources/Vitruvian/Services/Platform/BuiltinTools.swift",
     "surfaces: tiled.contains(command) ? [.radial, .quickPanel] : [.radial])",
     "surfaces: [.radial, .quickPanel])",
     "a built-in command asks for the panel only when a tile runs it"),
    ("reordering forgets a tile that is not showing", "platform",
     "Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift",
     "            } else if isWellFormed(id) {\n                result.append(id)\n            }\n",
     "            }\n",
     "a tile that is not showing now keeps its place in the saved order"),
```

Each "before" text must occur exactly once in its file:

Run: `grep -c "surfaces: tiled.contains(command) ? \[.radial, .quickPanel\] : \[.radial\])" Sources/Vitruvian/Services/Platform/BuiltinTools.swift; grep -c "} else if isWellFormed(id) {" Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift`
Expected: `1` and `1`.

- [ ] **Step 2: Prove each mutation by hand**

The full mutation run repeats the unit tests once per entry. For each of the two new entries: apply it by editing the file, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`, confirm the run fails with exactly the entry's sixth field, undo the edit, and confirm `git diff --stat -- <file>` shows nothing. Put both failing outputs in the pull request. If a mutation is not detected, stop: do not adjust the test to fit.

Run: `python3 -c "import ast; ast.parse(open('apps/desktop/vitruvian/Tests/mutation_checks.py').read())"` (from the repository root)
Expected: no output.

- [ ] **Step 3: Write the rules down**

In `AGENTS.md`, directly after the bullet that begins "An action a surface can trigger is a command.", add:

```markdown
- A surface that lists tools has two sources: its own fixed list, and
  `ToolRegistry.extraCommands(on:)`, the commands that ask for that surface
  and that the fixed list does not already offer. Never list
  `commands(on:)` straight onto the Quick panel or the wheel: every built-in
  command is in it, and each would appear twice. A built-in command asks for
  a surface in `BuiltinTools.install` only when something there already runs
  it.
- A saved order may hold an id the app does not recognise right now: a tool
  that has not registered yet, or one that is switched off. Keep it where it
  is (`QuickToolsSupport.savedTileOrder`); drop only what is not well formed.
- To see a tool that is in no fixed list, build with
  `--define=vitruvian_sample_tool=true` (`Services/Platform/SampleTool.swift`).
```

In `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`, section 12, in the sub-project 1 row's last cell, replace

```
Part 2: Quick panel tiles and the Shortcuts page list such commands too.
```
with
```
Part 2 (done): Quick panel tiles and the wheel editor offer such commands too, and a development build has a sample tool to check them with. Part 3: shortcuts for such commands, on the Shortcuts page.
```

- [ ] **Step 4: Run everything**

With the display awake and the screen unlocked, from the repository root:

```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
bazel build --config=macos-app --define=vitruvian_sample_tool=true //apps/desktop/vitruvian:Vitruvian
```

Expected: all pass, every unit suite reports, both builds succeed.

- [ ] **Step 5: Check the surfaces by hand, twice**

Unit tests do not open the panel or the wheel. Accessibility has to be granted again after each rebuild, because the build is signed ad hoc.

**A release-shaped build** (no flag). Build, unzip and open it:

```sh
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

1. Open the Quick panel. It shows the same tiles, in the same order, as before this change. There is no "Say hello" tile.
2. Open Settings › Radial menu, edit a slice, choose Tool. The picker lists the same tools as before.

**A development build** (with the flag):

```sh
bazel build --config=macos-app --define=vitruvian_sample_tool=true //apps/desktop/vitruvian:Vitruvian
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

3. Open the Quick panel. A "Say hello" tile with a waving hand is last. Press it: the panel closes and "Hello from the sample tool" appears.
4. Enter edit mode. Drag the tile to the first place; hide it; bring it back from the tray. Quit and reopen the app: it is where it was left.
5. Open the island's Tools page. The tile is there and the island is sized for it.
6. Open the command bar and type "hello". A "Say hello" row filed under "Sample tool" runs it.
7. Settings › Radial menu: add a slice, choose Tool, pick "Say hello", save. The slice shows the waving hand. Open the wheel and run it.
8. Quit. Open the release-shaped build again (step 1's). The Quick panel has no "Say hello" tile and the wheel does not show that slice. Open the development build again: both are back, the tile in the place it was left.

Record the Mac model, the macOS version, and the result of each of the eight steps in the pull request. Say plainly which, if any, were not done.

- [ ] **Step 6: Commit and open the pull request**

Append to the part 2 entry in `UPSTREAM.md`:

```markdown
  - `Tests/mutation_checks.py`: two mutations (a built-in command with no tile asking for the panel; a reorder forgetting a tile that is not showing).
```

```bash
git add Tests/mutation_checks.py AGENTS.md UPSTREAM.md ../../../docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md
git commit -m "refactor(desktop): guard and document tiles and slices for any tool"
```

Open one pull request. Its description states what was run, on which Mac and macOS version, the eight hand checks and their results, and what remains untested.
