# Vitruvian Tool Registry (part 3: shortcuts for any tool) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a tool that is in none of the app's fixed lists give its commands a global shortcut that the user records on the Shortcuts page, that cannot clash with any other shortcut in the app, and that runs the command through the registry.

**Architecture:** A command asks for a shortcut the way it asks for any surface. The saved combinations live in one new preference, keyed by command id. A registrar turns them into registered hotkeys and re-does that whenever the registry changes or a shortcut recording ends. One shared check answers "who else holds this combination?" for the two lists the existing role check cannot see: command-bar rows and tool commands. Every place that records a shortcut calls it, which also closes a gap that exists today.

**Tech Stack:** Swift 6 (AppKit, SwiftUI, Combine), Carbon hotkeys through the app's `QuickToolHotkey`, Bazel with `--config=macos-app`, the app's own `TestSuite` harness run under Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (sub-project 1, part 3).

**Builds on, and must come after:**
- Part 2, `docs/superpowers/plans/2026-10-08-vitruvian-tool-registry-part-2.md`: it adds `SampleTool`, `ToolRegistry.extraCommands(on:)` and `noteAvailabilityChanged()`, all used here.
- The hotkey id fix (`hotkey_ids_are_unique` in `bazel/source_lints.py`): Task 4 adds this plan's id run to that rule.

All paths are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## Decisions this plan makes

| # | Decision | Why |
|---|---|---|
| 1 | A command gets a shortcut only if it asks for the new `shortcut` surface. Our own commands do not ask. | Ten of our fifteen already have a shortcut through `GlobalShortcutRole`. Offering a second for the same action lets one action hold two combinations. |
| 2 | No default combination. A command's shortcut starts empty. | A tool the user did not choose must not take a key. |
| 3 | A saved shortcut outlives its tool. When the tool is switched off or not registered, the key is released; the saved combination is kept, still counts for clashes, and returns with the tool. | Losing a binding because a tool was off for one launch is a surprise. So is another shortcut silently taking its combination. |
| 4 | The store reuses the command bar's row-shortcut logic by extracting it, not by copying it. | Same rules, one implementation. |
| 5 | A separate preference and a separate registrar from the command bar's. | The command bar's are gated on the command bar being switched on, and hold command-bar row keys. |
| 6 | At most 64 command shortcuts, the command bar's limit. | A bounded id run, and the same message when full. |
| 7 | A shortcut whose command cannot run beeps, as a command-bar row shortcut does. | A key that does nothing is worse than one that says no. |

## Global Constraints

- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file that carries the Vorssaint header gets a dated entry under "Modifications" in `UPSTREAM.md`, in the same commit. Add one entry, `- **<date>**: Tool registry, part 3 (...)`, in Task 2 and append sub-bullets in later tasks.
- Module order is `Core <- Design <- Services <- UI <- App`. All of them and the tests build in Swift 6 mode.
- What another module uses is `package`. Every initializer is written out.
- **No new user-facing string.** This plan uses only strings that exist: `shortcutPressKeys`, `shortcutNone`, `shortcutClear`, `shortcutNotCaptured`, `shortcutInvalid`, `shortcutConflictFormat`, `shortcutUnavailable` (all on `Strings`), `active` and `inactive` (`FeatureStrings.shortcuts`), and `rowShortcutsLimitFormat` (`FeatureStrings.commandBar`). A section's heading is the tool's own name.
- A new preference is declared in `Core/Preferences.swift` with its default, registered through `Defaults.registeredDefaults`, and added to `SettingsBackupSupport`. It is read and written as `defaults[Preferences.x]`. `source_lints_test` counts `forKey: DefaultsKey.x` calls and only lets that count fall.
- **Nothing a user of a release build can see changes**, except that a shortcut can no longer be recorded when a command-bar row already holds the combination (Task 5: today it can, and one of the two silently loses).
- Tests are behavioural. No test reads a source file as text. No unit test registers a real global hotkey: the registrar takes its hotkeys through a factory, and tests pass a double.
- `Tests/mutation_checks.py` quotes exact source text. Before moving or rewording code in `CommandBarRowShortcuts.swift`, `CommandBarService.swift` or `ShortcutRecorderButton.swift`, search that file for the text and update the mutation in the same commit if it is quoted.
- Build and test through Bazel only, from the repository root, with the display awake:
  ```sh
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest
  ```
  One suite: add `--test_arg=--suite=platform` (repeat the flag for several).
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren 2>/dev/null)"
  ```
  Put this in the same command as the commit.
- Commit titles: `refactor(desktop): ...` for Tasks 1 to 4 and 6 to 7. Task 5 changes what a release build does, so its commit is `fix(desktop): ...`.

## Review Focus

Failure modes most likely to reach a user. Each has a test in the task named, except where it says by hand.

1. **A shortcut stops working after the user records any other shortcut.** Recording releases every key the app holds, and gives them back only through each feature's own sync. A registrar tied to no feature stays dead. (Task 4 wires it; checked by hand in Task 7, because the unit tests do not record.)
2. **One combination bound twice.** A role, a window-layout action, a wheel, a command-bar row and a tool command must each refuse a combination any of the others holds. (Task 5)
3. **A tool is switched off, or not registered this launch.** Its key is released, its saved combination is kept and still blocks others, and it works again when the tool returns. (Task 4, Task 5)
4. **The saved preference holds an id that is malformed, or names a command that no longer asks for a shortcut.** It is ignored, not deleted, and nothing crashes. (Task 3, Task 4)
5. **Another app already holds the combination.** macOS refuses it. The row says so and the saved value stays. (Task 4, Task 6)

---

### Task 1: A command can ask for a shortcut

**Files:**
- Modify: `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift` (`ToolSurface`)
- Modify: `Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift` (`extraCommands(on:)`)
- Modify: `Sources/Vitruvian/Services/Platform/SampleTool.swift` (the command's `surfaces`)
- Modify: `Tests/ToolPlatformTests.swift`

**Interfaces:**
- Consumes: part 2's `SampleTool`, `ToolRegistry.extraCommands(on:)`.
- Produces: `ToolSurface.shortcut`. `registry.commands(on: .shortcut)` is the list of commands that may have a shortcut.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `shortcutSurface(suite)` to the end of `run(_:)`, and add:

```swift
    static func shortcutSurface(_ suite: TestSuite) {
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        suite.expect(shipped.commands(on: .shortcut).isEmpty,
                     "the app's own commands keep the shortcuts they have, and ask for no second one")
        SampleTool.install(into: shipped, say: { _ in })
        suite.expect(shipped.commands(on: .shortcut).map(\.id) == [SampleTool.hello]
                         && shipped.extraCommands(on: .shortcut).map(\.id) == [SampleTool.hello],
                     "a tool outside the fixed lists can ask for a shortcut")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `type 'ToolSurface' has no member 'shortcut'`.

- [ ] **Step 3: Write the implementation**

In `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift`, replace

```swift
    case commandBar, radial, quickPanel
```
with
```swift
    case commandBar, radial, quickPanel
    /// A global shortcut the person records on the Shortcuts page.
    case shortcut
```

In `Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift`, in `extraCommands(on:)`, change

```swift
        case .commandBar: offered = []
```
to
```swift
        // The app's own commands have their shortcuts through
        // `GlobalShortcutRole` and do not ask for this surface.
        case .commandBar, .shortcut: offered = []
```

In `Sources/Vitruvian/Services/Platform/SampleTool.swift`, change the command's surfaces from `[.radial, .quickPanel, .commandBar]` to `[.radial, .quickPanel, .commandBar, .shortcut]`.

Run: `grep -rn "switch.*surface\|ToolSurface.allCases" Sources Tests`
Expected: only `extraCommands(on:)`. Any other switch over the surface needs an arm for `.shortcut`.

- [ ] **Step 4: Run the test**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vitruvian/Core/Platform/ToolDescriptor.swift Sources/Vitruvian/Services/Platform/ToolRegistry+Surfaces.swift Sources/Vitruvian/Services/Platform/SampleTool.swift Tests/ToolPlatformTests.swift
git commit -m "refactor(desktop): let a command ask for a shortcut"
```

---

### Task 2: One implementation of "a list of things, each with its own shortcut"

The command bar already has this logic for its rows. Extract the part that is not about rows, and have the command bar use it.

**Files:**
- Create: `Sources/Vitruvian/Services/ShortcutMap.swift`
- Modify: `Sources/Vitruvian/Services/CommandBar/CommandBarRowShortcuts.swift`
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `GlobalShortcut` (`init?(storageValue:)`, `storageValue`, `modifiers`).
- Produces `ShortcutMap` (a namespace):
  - `enum AssignmentIssue: Equatable { case invalid, occupied(String), full }`
  - `decode(_ raw: String?) -> [String: GlobalShortcut]`
  - `encode(_ shortcuts: [String: GlobalShortcut]) -> String?`
  - `setting(_ shortcut: GlobalShortcut?, for key: String, in shortcuts: [String: GlobalShortcut], limit: Int) -> [String: GlobalShortcut]`
  - `hasRoom(for key: String, in shortcuts: [String: GlobalShortcut], limit: Int) -> Bool`
  - `key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String?`
  - `isUsable(_ shortcut: GlobalShortcut) -> Bool`
  - `assignmentIssue(_ shortcut: GlobalShortcut, for key: String, in shortcuts: [String: GlobalShortcut], limit: Int) -> AssignmentIssue?`
- `CommandBarRowShortcuts` keeps every name and signature it has; its bodies call `ShortcutMap`.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `shortcutMap(suite)` to the end of `run(_:)`, and add:

```swift
    static func shortcutMap(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let bare = GlobalShortcut(keyCode: 11, modifiers: [])

        var map = ShortcutMap.setting(optionB, for: "a", in: [:], limit: 2)
        suite.expect(map == ["a": optionB] && ShortcutMap.key(for: optionB, in: map) == "a",
                     "a key gets its shortcut, and the shortcut finds its key")
        suite.expect(ShortcutMap.decode(ShortcutMap.encode(map)) == map, "a map reads back what it wrote")
        suite.expect(ShortcutMap.decode(nil).isEmpty && ShortcutMap.decode("not json").isEmpty
                         && ShortcutMap.decode(#"{"a":"nonsense"}"#).isEmpty,
                     "what cannot be read is no shortcut, and nothing crashes")

        map = ShortcutMap.setting(optionB, for: "b", in: map, limit: 2)
        suite.expect(map == ["b": optionB], "a combination given to another key moves to it")
        map = ShortcutMap.setting(optionN, for: "a", in: map, limit: 2)
        suite.expect(ShortcutMap.setting(GlobalShortcut(keyCode: 0, modifiers: [.control]), for: "c", in: map, limit: 2) == map
                         && !ShortcutMap.hasRoom(for: "c", in: map, limit: 2)
                         && ShortcutMap.hasRoom(for: "a", in: map, limit: 2),
                     "a full map takes no new key, and an existing key can still change")
        suite.expect(ShortcutMap.setting(nil, for: "a", in: map, limit: 2) == ["b": optionB],
                     "clearing a key removes it")

        suite.expect(ShortcutMap.assignmentIssue(bare, for: "a", in: map, limit: 2) == .invalid,
                     "a bare key is refused: it would take that key from every app")
        suite.expect(ShortcutMap.assignmentIssue(optionB, for: "a", in: map, limit: 2) == .occupied("b"),
                     "a combination another key holds is refused, and names its holder")
        suite.expect(ShortcutMap.assignmentIssue(GlobalShortcut(keyCode: 0, modifiers: [.control]), for: "c", in: map, limit: 2) == .full,
                     "a full map says so")
        suite.expect(ShortcutMap.assignmentIssue(optionN, for: "a", in: map, limit: 2) == nil,
                     "a key may keep the combination it has")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ShortcutMap' in scope`.

- [ ] **Step 3: Write `ShortcutMap`**

Create `Sources/Vitruvian/Services/ShortcutMap.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A list of things that each may have a global shortcut of their own, kept
/// as one preference: `{"<key>": "<shortcut storage value>"}`. Command Bar
/// rows and tool commands both keep theirs this way.
package enum ShortcutMap {
    package enum AssignmentIssue: Equatable {
        /// Not a combination a global shortcut may use.
        case invalid
        /// Another key in the same map holds it.
        case occupied(String)
        /// The map holds as many as it may.
        case full
    }

    package static func decode(_ raw: String?) -> [String: GlobalShortcut] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.compactMapValues(GlobalShortcut.init(storageValue:))
    }

    package static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? {
        let stored = shortcuts.mapValues(\.storageValue)
        guard let data = try? JSONEncoder().encode(stored) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The map with `key` given `shortcut`, or cleared when it is nil. A
    /// combination another key holds moves to this one. Past `limit` a new
    /// key is not added; `assignmentIssue` says so first.
    package static func setting(_ shortcut: GlobalShortcut?, for key: String,
                                in shortcuts: [String: GlobalShortcut], limit: Int) -> [String: GlobalShortcut] {
        var next = shortcuts
        guard let shortcut else {
            next.removeValue(forKey: key)
            return next
        }
        for (otherKey, other) in next where other == shortcut && otherKey != key {
            next.removeValue(forKey: otherKey)
        }
        guard next[key] != nil || next.count < limit else { return next }
        next[key] = shortcut
        return next
    }

    package static func hasRoom(for key: String, in shortcuts: [String: GlobalShortcut], limit: Int) -> Bool {
        shortcuts[key] != nil || shortcuts.count < limit
    }

    package static func key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }

    /// A bare letter would take that letter away from every app on the Mac.
    package static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }

    package static func assignmentIssue(_ shortcut: GlobalShortcut, for key: String,
                                        in shortcuts: [String: GlobalShortcut], limit: Int) -> AssignmentIssue? {
        guard isUsable(shortcut) else { return .invalid }
        if let owner = self.key(for: shortcut, in: shortcuts), owner != key {
            return .occupied(owner)
        }
        return hasRoom(for: key, in: shortcuts, limit: limit) ? nil : .full
    }
}
```

- [ ] **Step 4: Have the command bar use it**

In `Sources/Vitruvian/Services/CommandBar/CommandBarRowShortcuts.swift`:

Replace the declaration of `enum AssignmentIssue` (the whole enum, with its three cases) with:

```swift
    package typealias AssignmentIssue = ShortcutMap.AssignmentIssue
```

Replace the bodies, keeping each signature exactly as it is:

```swift
    package static func assignmentIssue(_ shortcut: GlobalShortcut, for key: String,
                                in shortcuts: [String: GlobalShortcut]) -> AssignmentIssue? {
        ShortcutMap.assignmentIssue(shortcut, for: key, in: shortcuts, limit: limit)
    }

    package static func decode(_ raw: String?) -> [String: GlobalShortcut] {
        ShortcutMap.decode(raw)
    }

    package static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? {
        ShortcutMap.encode(shortcuts)
    }

    package static func setting(_ shortcut: GlobalShortcut?,
                        for key: String,
                        in shortcuts: [String: GlobalShortcut]) -> [String: GlobalShortcut] {
        ShortcutMap.setting(shortcut, for: key, in: shortcuts, limit: limit)
    }

    package static func hasRoom(for key: String, in shortcuts: [String: GlobalShortcut]) -> Bool {
        ShortcutMap.hasRoom(for: key, in: shortcuts, limit: limit)
    }

    package static func key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String? {
        ShortcutMap.key(for: shortcut, in: shortcuts)
    }

    package static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        ShortcutMap.isUsable(shortcut)
    }
```

Keep each function's existing doc comment above it. Leave `limit`, `hidesAppInFront`, `PendingAppLaunch`, `appKey`, `keyFreed`, `takeOverKey` and `takeOverDecision` untouched.

Run: `grep -n "CommandBarRowShortcuts.swift" Tests/mutation_checks.py`
Expected: no output. If a mutation quotes text you replaced, move the mutation to `Sources/Vitruvian/Services/ShortcutMap.swift` with the same text and the same diagnostic.

- [ ] **Step 5: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=command-bar`
Expected: PASS for both. The `command-bar` suite's row-shortcut checks (the 64 limit, `assignmentIssue`, `decode(encode(x)) == x`) pass unchanged: that is the proof the extraction changed nothing.

- [ ] **Step 6: Commit**

Add at the top of the list under `## Modifications` in `UPSTREAM.md`:

```markdown
- **2026-10-09**: Tool registry, part 3 (`docs/superpowers/plans/2026-10-09-vitruvian-tool-registry-part-3.md`):
  - `Services/CommandBar/CommandBarRowShortcuts.swift`: the parts that are not about rows (reading, writing, setting, the limit, finding a holder) moved to `Services/ShortcutMap.swift`; every function here keeps its name and signature and calls it.
```

```bash
git add Sources/Vitruvian/Services/ShortcutMap.swift Sources/Vitruvian/Services/CommandBar/CommandBarRowShortcuts.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): share the shortcut list logic the command bar keeps"
```

---

### Task 3: The preference that holds command shortcuts

**Files:**
- Modify: `Sources/Vitruvian/Core/DefaultsKey.swift` (after `commandBarRowShortcuts`, line 599)
- Modify: `Sources/Vitruvian/Core/Preferences.swift` (after `commandBarRowShortcuts`, line 899)
- Modify: `Sources/Vitruvian/Core/Defaults.swift` (after the `commandBarRowShortcuts` line, 1002)
- Modify: `Sources/Vitruvian/Core/SettingsBackupSupport.swift` (after the `commandBarRowShortcuts` line, 56)
- Create: `Sources/Vitruvian/Services/Platform/ToolCommandShortcuts.swift`
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ShortcutMap`, `CommandID`.
- Produces:
  - `Preferences.toolCommandShortcuts` (a `String`, default `""`)
  - `ToolCommandShortcuts.limit` (64), `.takeOverKey(for: CommandID) -> String`, `.decode(_:) -> [String: GlobalShortcut]`, `.encode(_:) -> String?`, `.shortcut(for: CommandID, in:) -> GlobalShortcut?`, `.holder(of: GlobalShortcut, in:, excluding: CommandID?) -> String?`

The map is keyed by the command id's text, not by `CommandID`, so an id that is malformed or names nothing registered is carried through untouched (decision 3).

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `commandShortcutStore(suite)` to the end of `run(_:)`, and add:

```swift
    static func commandShortcutStore(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let hello = SampleTool.hello
        let raw = ToolCommandShortcuts.encode([hello.rawValue: optionB, "com.acme.gone/open": optionN, "not an id": optionB])
        let map = ToolCommandShortcuts.decode(raw)
        suite.expect(map.count == 3, "ids that name nothing now, or are not ids at all, are carried, not dropped")
        suite.expect(ToolCommandShortcuts.shortcut(for: hello, in: map) == optionB,
                     "a command finds its shortcut")
        suite.expect(ToolCommandShortcuts.holder(of: optionN, in: map, excluding: nil) == "com.acme.gone/open",
                     "a command that is not registered still holds its combination")
        suite.expect(ToolCommandShortcuts.holder(of: optionN, in: map, excluding: CommandID("com.acme.gone/open")) == nil,
                     "a command does not clash with itself")
        suite.expect(ToolCommandShortcuts.takeOverKey(for: hello) == "toolCommandShortcuts.dev.vitruvian.sample/hello",
                     "a command's take-over is kept under the name its hotkey is claimed with")
        suite.expect(Preferences.toolCommandShortcuts.defaultValue.isEmpty && ToolCommandShortcuts.limit == 64,
                     "no command starts with a shortcut, and the list has the command bar's limit")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ToolCommandShortcuts' in scope`.

- [ ] **Step 3: Declare the preference**

Add, each directly after the matching `commandBarRowShortcuts` line:

`Sources/Vitruvian/Core/DefaultsKey.swift`:
```swift
    package static let toolCommandShortcuts = "toolCommandShortcuts" // {command id: shortcut}
```

`Sources/Vitruvian/Core/Preferences.swift`:
```swift
    package static let toolCommandShortcuts = Preference(DefaultsKey.toolCommandShortcuts, default: "")
```

`Sources/Vitruvian/Core/Defaults.swift`:
```swift
        DefaultsKey.toolCommandShortcuts: Preferences.toolCommandShortcuts.defaultValue,
```

`Sources/Vitruvian/Core/SettingsBackupSupport.swift`:
```swift
        DefaultsKey.toolCommandShortcuts,
```

- [ ] **Step 4: Write the store**

Create `Sources/Vitruvian/Services/Platform/ToolCommandShortcuts.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The shortcuts people gave to tool commands: one preference, a map from a
/// command id's text to a combination. Keyed by the text, not by
/// `CommandID`, so an entry whose tool is switched off, not registered this
/// launch, or misspelled in a restored backup is carried through untouched.
/// It returns with its tool, and until then still holds its combination.
package enum ToolCommandShortcuts {
    /// As many as the Command Bar's row shortcuts.
    package static let limit = 64

    package static func decode(_ raw: String?) -> [String: GlobalShortcut] { ShortcutMap.decode(raw) }
    package static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? { ShortcutMap.encode(shortcuts) }

    package static func shortcut(for id: CommandID, in shortcuts: [String: GlobalShortcut]) -> GlobalShortcut? {
        shortcuts[id.rawValue]
    }

    /// The id text of the command that holds `shortcut`, other than `excluded`.
    package static func holder(of shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut],
                               excluding excluded: CommandID?) -> String? {
        shortcuts.first { $0.value == shortcut && $0.key != excluded?.rawValue }?.key
    }

    /// The name a command's hotkey is claimed under, and its take-over of a
    /// macOS shortcut kept under.
    package static func takeOverKey(for id: CommandID) -> String {
        "\(DefaultsKey.toolCommandShortcuts).\(id.rawValue)"
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=preferences --test_arg=--suite=settings`
Expected: PASS for all three. `preferences` and `settings` hold the checks that every preference is registered and backed up.

Run: `bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 6: Commit**

Append to the part 3 entry in `UPSTREAM.md`:

```markdown
  - `Core/DefaultsKey.swift`, `Core/Preferences.swift`, `Core/Defaults.swift`, `Core/SettingsBackupSupport.swift`: the `toolCommandShortcuts` preference, registered and backed up.
```

```bash
git add Sources/Vitruvian/Core/DefaultsKey.swift Sources/Vitruvian/Core/Preferences.swift Sources/Vitruvian/Core/Defaults.swift Sources/Vitruvian/Core/SettingsBackupSupport.swift Sources/Vitruvian/Services/Platform/ToolCommandShortcuts.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): keep tool command shortcuts in a preference of their own"
```

---

### Task 4: The registrar: saved shortcuts become keys that work

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift`
- Modify: `Sources/Vitruvian/Services/ShortcutCapture.swift` (`end()`)
- Modify: `Sources/Vitruvian/App/AppDelegate.swift` (after `FeatureRuntime.shared.syncAtLaunch()`, line 202)
- Modify: `bazel/source_lints.py` (`HOTKEY_ID_COUNTERS`)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolCommandShortcuts`, `ShortcutMap`, `ToolRegistry` (`commands(on: .shortcut)`, `run`, `$revision`), `QuickToolHotkey`.
- Produces:
  - `protocol ToolHotkey: AnyObject` (`onPress`, `sync(enabled:shortcut:storageKey:) -> Bool`, `unregister()`); `QuickToolHotkey` conforms.
  - `ToolShortcutRegistrar` (`@MainActor`, `ObservableObject`): `shared`, `init(environment:)`, `Environment`, `firstHotkeyID` (2000), `shortcuts: [String: GlobalShortcut]`, `refused: Set<CommandID>` (published), `sync()`, `assign(_ shortcut: GlobalShortcut?, to id: CommandID)`.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, add `shortcutRegistrar(suite)` to the end of `run(_:)`, and add:

```swift
    /// A hotkey that registers nothing, and records what it was asked. Not
    /// main-actor isolated, like the protocol it stands in for; the registrar
    /// only ever touches it on the main thread.
    nonisolated final class FakeHotkey: ToolHotkey {
        let id: UInt32
        var onPress: (() -> Void)?
        var registered: (shortcut: GlobalShortcut, storageKey: String)?
        var accepts = true
        init(id: UInt32) { self.id = id }
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            guard enabled, accepts else { return false }
            registered = (shortcut, storageKey)
            return true
        }
        func unregister() { registered = nil }
    }

    static func shortcutRegistrar(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let registry = ToolRegistry(isAvailable: { _ in true })
        var said: [String] = []
        var saved: [String: GlobalShortcut] = [:]
        var made: [FakeHotkey] = []
        var refusals = 0
        var refuseNext = false
        let registrar = ToolShortcutRegistrar(environment: .init(
            registry: registry,
            shortcuts: { saved },
            save: { saved = $0 },
            makeHotkey: { id in
                let hotkey = FakeHotkey(id: id)
                hotkey.accepts = !refuseNext
                made.append(hotkey)
                return hotkey
            },
            refuse: { refusals += 1 },
            setTakeOver: { _, _ in }))
        var live: [FakeHotkey] { made.filter { $0.registered != nil } }
        let hello = SampleTool.hello

        // Saved before its tool registers: nothing is held.
        saved = [hello.rawValue: optionB, "com.acme.gone/open": optionN, "not an id": optionB]
        registrar.sync()
        suite.expect(live.isEmpty, "a shortcut whose command is not registered holds no key")

        // The tool registers: the registrar hears it and takes the key.
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(live.count == 1 && live[0].registered?.shortcut == optionB
                         && live[0].registered?.storageKey == ToolCommandShortcuts.takeOverKey(for: hello)
                         && live[0].id >= ToolShortcutRegistrar.firstHotkeyID,
                     "a tool that registers gets the key its command was given, without being told to sync")
        suite.expect(saved.count == 3, "syncing drops nothing from what is saved")

        live[0].onPress?()
        suite.expect(said.count == 1 && refusals == 0, "pressing the key runs the command once")

        // Unregistering the tool releases the key and keeps what is saved.
        registry.unregister(SampleTool.id)
        suite.expect(live.isEmpty && saved[hello.rawValue] == optionB,
                     "a tool that leaves gives its key back and keeps its shortcut for its return")
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(live.count == 1, "a tool that returns gets its key back")

        // Assigning and clearing.
        registrar.assign(optionN, to: hello)
        suite.expect(saved[hello.rawValue] == optionN && saved["com.acme.gone/open"] == nil
                         && live.count == 1 && live[0].registered?.shortcut == optionN,
                     "a combination given to a command moves to it, and its key follows")
        registrar.assign(nil, to: hello)
        suite.expect(saved[hello.rawValue] == nil && live.isEmpty, "clearing a shortcut releases its key")

        // Another app holds the combination.
        refuseNext = true
        registrar.assign(optionB, to: hello)
        suite.expect(registrar.refused == [hello] && saved[hello.rawValue] == optionB,
                     "a combination macOS refuses is reported, and stays saved")
        refuseNext = false
        registrar.sync()
        suite.expect(registrar.refused.isEmpty && live.count == 1, "a refusal clears when the key can be taken")

        // A command that stops asking for a shortcut.
        registry.unregister(SampleTool.id)
        let quiet = ToolDescriptor(id: SampleTool.id, name: "Sample tool", symbol: "hand.wave", commands: [
            CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave", surfaces: [.radial])!,
        ])!
        try? registry.register(quiet)
        try? registry.setHandler(.init(title: { _ in "Say hello" }, run: {}), for: hello)
        suite.expect(live.isEmpty && saved[hello.rawValue] == optionB,
                     "a command that no longer asks for a shortcut holds no key")
    }
```

`live` reads `made` each time, so it reflects the hotkeys the last `sync` built.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find type 'ToolHotkey' in scope`.

- [ ] **Step 3: Write the registrar**

Create `Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Combine
import VitruvianCore

/// What the registrar needs of a global hotkey. `QuickToolHotkey` is one; a
/// test passes a double that registers nothing.
package protocol ToolHotkey: AnyObject {
    var onPress: (() -> Void)? { get set }
    @discardableResult func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool
    func unregister()
}

extension QuickToolHotkey: ToolHotkey {}

/// Turns the shortcuts people gave to tool commands into keys that work.
///
/// It is tied to no hub feature, so nothing re-syncs it for free. It syncs
/// at launch (`AppDelegate`), whenever the registry changes (it watches
/// `revision`), and when a shortcut recording ends (`ShortcutCapture.end`),
/// because recording releases every key the app holds.
@MainActor
package final class ToolShortcutRegistrar: ObservableObject {
    package static let shared = ToolShortcutRegistrar(environment: .live)

    /// The first id of this registrar's run, clear of every other hotkey's
    /// (`hotkey_ids_are_unique` in bazel/source_lints.py).
    package static let firstHotkeyID: UInt32 = 2000

    @MainActor
    package struct Environment {
        package var registry: ToolRegistry
        package var shortcuts: () -> [String: GlobalShortcut]
        package var save: ([String: GlobalShortcut]) -> Void
        package var makeHotkey: (UInt32) -> ToolHotkey
        /// What a key does when its command cannot run.
        package var refuse: () -> Void
        package var setTakeOver: (String, Bool) -> Void

        package init(registry: ToolRegistry, shortcuts: @escaping () -> [String: GlobalShortcut],
                     save: @escaping ([String: GlobalShortcut]) -> Void,
                     makeHotkey: @escaping (UInt32) -> ToolHotkey, refuse: @escaping () -> Void,
                     setTakeOver: @escaping (String, Bool) -> Void) {
            self.registry = registry
            self.shortcuts = shortcuts
            self.save = save
            self.makeHotkey = makeHotkey
            self.refuse = refuse
            self.setTakeOver = setTakeOver
        }

        package static var live: Environment {
            Environment(
                registry: .shared,
                shortcuts: { ToolCommandShortcuts.decode(UserDefaults.standard[Preferences.toolCommandShortcuts]) },
                save: { shortcuts in
                    if let encoded = ToolCommandShortcuts.encode(shortcuts) {
                        UserDefaults.standard[Preferences.toolCommandShortcuts] = encoded
                    } else {
                        UserDefaults.standard.removeValue(for: Preferences.toolCommandShortcuts)
                    }
                },
                makeHotkey: { QuickToolHotkey(id: $0) },
                refuse: { NSSound.beep() },
                setTakeOver: { SystemShortcutTakeover.setTakeOver($0, $1) })
        }
    }

    /// Commands whose combination macOS would not give: another app holds it.
    @Published package private(set) var refused: Set<CommandID> = []

    private let environment: Environment
    private var hotkeys: [ToolHotkey] = []
    private var watching: AnyCancellable?

    package init(environment: Environment) {
        self.environment = environment
        // `revision` publishes before it changes, but the registry has
        // already changed by then: it bumps the count last.
        watching = environment.registry.$revision.dropFirst().sink { [weak self] _ in self?.sync() }
    }

    /// Every saved shortcut, whether or not its command is here to use it.
    package var shortcuts: [String: GlobalShortcut] { environment.shortcuts() }

    /// One key per shortcut whose command asks for one and is switched on,
    /// and not one more. Nothing saved is changed.
    package func sync() {
        for hotkey in hotkeys { hotkey.unregister() }
        hotkeys = []
        let asking = Set(environment.registry.commands(on: .shortcut).map(\.id))
        var index: UInt32 = 0
        var refused: Set<CommandID> = []
        for (text, shortcut) in environment.shortcuts().sorted(by: { $0.key < $1.key }) {
            guard index < UInt32(ToolCommandShortcuts.limit), let id = CommandID(text), asking.contains(id),
                  ShortcutMap.isUsable(shortcut) else { continue }
            let hotkey = environment.makeHotkey(Self.firstHotkeyID + index)
            // A hotkey calls back on the main thread.
            hotkey.onPress = { [weak self] in MainActor.assumeIsolated { self?.pressed(id) } }
            if !hotkey.sync(enabled: true, shortcut: shortcut, storageKey: ToolCommandShortcuts.takeOverKey(for: id)) {
                refused.insert(id)
            }
            hotkeys.append(hotkey)
            index += 1
        }
        if refused != self.refused { self.refused = refused }
    }

    /// Gives `id` a shortcut, or clears it with nil, and re-syncs. The caller
    /// has already checked the combination is free.
    package func assign(_ shortcut: GlobalShortcut?, to id: CommandID) {
        if shortcut == nil { environment.setTakeOver(ToolCommandShortcuts.takeOverKey(for: id), false) }
        environment.save(ShortcutMap.setting(shortcut, for: id.rawValue, in: environment.shortcuts(),
                                             limit: ToolCommandShortcuts.limit))
        sync()
        objectWillChange.send()
    }

    private func pressed(_ id: CommandID) {
        if !environment.registry.run(id) { environment.refuse() }
    }
}
```

- [ ] **Step 4: Wire the three moments it must sync**

In `Sources/Vitruvian/App/AppDelegate.swift`, directly after

```swift
        FeatureRuntime.shared.syncAtLaunch()
```
add
```swift
        // Tool command shortcuts hang off no feature binding, so nothing
        // above registers them.
        ToolShortcutRegistrar.shared.sync()
```

In `Sources/Vitruvian/Services/ShortcutCapture.swift`, in `end()`, directly after

```swift
        FeatureRuntime.shared.sync(GlobalShortcutRole.featuresToSilenceWhileRecording)
```
add
```swift
        // `begin` released these with every other quick tool key, and no
        // feature's sync gives them back.
        ToolShortcutRegistrar.shared.sync()
```

In `bazel/source_lints.py`, tell the hotkey id rule about this run. The rule reads `QuickToolHotkey(id: <number>)` and `QuickToolHotkey(id: <number> + ...)`; the registrar's live factory is `QuickToolHotkey(id: $0)`, which it cannot read as a number, so the run is declared as a counter. Add to `HOTKEY_ID_COUNTERS`:

```python
    # One per tool command shortcut, counted from `firstHotkeyID`, up to
    # `ToolCommandShortcuts.limit`.
    APP_PREFIX + "Services/Platform/ToolShortcutRegistrar.swift": (
        re.compile(r"static let firstHotkeyID: UInt32 = (\d+)"),
        64,
    ),
```

Run: `python3 apps/desktop/vitruvian/bazel/source_lints.py --app-dir apps/desktop/vitruvian` (from the repository root)
Expected: the last line is `<N> source rules hold across <M> Swift files`. If it prints `the id ... is neither a number nor a run listed in this rule` for `ToolShortcutRegistrar.swift`, the counter entry's path or pattern does not match the file: fix the entry, not the rule.

- [ ] **Step 5: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=keyboard`
Expected: PASS for both.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian && bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: builds, and the lint passes.

- [ ] **Step 6: Commit**

Append to the part 3 entry in `UPSTREAM.md`:

```markdown
  - `Services/ShortcutCapture.swift`: when a recording ends, tool command shortcuts are registered again with everything else.
  - `App/AppDelegate.swift`: registers tool command shortcuts at launch.
```

```bash
git add Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift Sources/Vitruvian/Services/ShortcutCapture.swift Sources/Vitruvian/App/AppDelegate.swift bazel/source_lints.py Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): register the shortcuts given to tool commands"
```

---

### Task 5: One combination, one owner

Today five lists can hold a global shortcut: roles, window-layout actions, radial wheels, command-bar rows, and (after Task 4) tool commands. `GlobalShortcutRole.conflict` sees roles and wheels. Window layout has its own check. Only two of the eight places that record a shortcut look at command-bar rows. This task adds one check for the two lists the others cannot see, and calls it everywhere.

**Files:**
- Create: `Sources/Vitruvian/Services/ShortcutConflicts.swift`
- Modify: `Sources/Vitruvian/UI/ShortcutRecorderButton.swift` (`ShortcutPreferenceRow.save`)
- Modify: `Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift` (`CentralWindowLayoutShortcutRow.save`)
- Modify: `Sources/Vitruvian/UI/Settings/WindowLayoutSettings.swift` (the row's `save`, near line 551)
- Modify: `Sources/Vitruvian/UI/Settings/CutPasteSettings.swift` (`saveRenameShortcut`)
- Modify: `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift` (`shortcutConflictTitle`)
- Modify: `Sources/Vitruvian/UI/Screenshot/ScreenshotToolOrderControls.swift` (`assign`)
- Modify: `Sources/Vitruvian/Services/CommandBar/CommandBarService.swift` (`rowShortcutIssue`)
- Modify: `Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift` (`directionalShortcutConflictTitle`)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolCommandShortcuts`, `ToolShortcutRegistrar.shared.shortcuts`, `ToolRegistry` (`title(for:language:)`), `CommandBarService.shared` (`rowShortcuts`, `entryTitle(forStableKey:)`), `CommandBarRowShortcuts.key(for:in:)`.
- Produces `ShortcutConflicts` (`@MainActor`):
  - `enum Holder: Equatable { case commandBarRow(String), toolCommand(String) }`
  - `holder(of:rows:commands:excludingRow:excludingCommand:) -> Holder?` (pure)
  - `title(for shortcut: GlobalShortcut, excludingRow: String? = nil, excludingCommand: CommandID? = nil) -> String?` (live)

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `shortcutConflicts(suite)` to the end of `run(_:)`, and add:

```swift
    static func shortcutConflicts(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let free = GlobalShortcut(keyCode: 0, modifiers: [.control])
        let rows = ["app.bundle.mail": optionB]
        let commands = ["dev.vitruvian.sample/hello": optionN, "com.acme.gone/open": free]
        func holder(_ shortcut: GlobalShortcut, row: String? = nil, command: CommandID? = nil) -> ShortcutConflicts.Holder? {
            ShortcutConflicts.holder(of: shortcut, rows: rows, commands: commands,
                                     excludingRow: row, excludingCommand: command)
        }
        suite.expect(holder(optionB) == .commandBarRow("app.bundle.mail"),
                     "a combination a Command Bar row holds is taken")
        suite.expect(holder(optionN) == .toolCommand("dev.vitruvian.sample/hello"),
                     "a combination a tool command holds is taken")
        suite.expect(holder(free) == .toolCommand("com.acme.gone/open"),
                     "a command that is not registered now still holds its combination")
        suite.expect(holder(optionB, row: "app.bundle.mail") == nil
                         && holder(optionN, command: SampleTool.hello) == nil,
                     "a row or a command does not clash with itself")
        suite.expect(holder(GlobalShortcut(keyCode: 1, modifiers: [.command])) == nil,
                     "a combination nothing holds is free")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ShortcutConflicts' in scope`.

- [ ] **Step 3: Write the check**

Create `Sources/Vitruvian/Services/ShortcutConflicts.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Who holds a combination among the two lists `GlobalShortcutRole.conflict`
/// cannot see: Command Bar row shortcuts and tool command shortcuts. Every
/// place that records a global shortcut asks here after it has asked the
/// role check and the window-layout check, so one combination has one owner.
@MainActor
package enum ShortcutConflicts {
    package enum Holder: Equatable {
        /// A Command Bar row, by its stable key.
        case commandBarRow(String)
        /// A tool command, by its id text. It may not be registered now.
        case toolCommand(String)
    }

    /// The rule, with everything it reads handed in.
    package static func holder(of shortcut: GlobalShortcut, rows: [String: GlobalShortcut],
                               commands: [String: GlobalShortcut],
                               excludingRow: String?, excludingCommand: CommandID?) -> Holder? {
        if let row = rows.first(where: { $0.value == shortcut && $0.key != excludingRow })?.key {
            return .commandBarRow(row)
        }
        if let command = ToolCommandShortcuts.holder(of: shortcut, in: commands, excluding: excludingCommand) {
            return .toolCommand(command)
        }
        return nil
    }

    /// The holder's name as the other shortcut rows would name it, or nil
    /// when the combination is free of both lists.
    package static func title(for shortcut: GlobalShortcut, excludingRow: String? = nil,
                              excludingCommand: CommandID? = nil) -> String? {
        let rows = AppFeature.commandBar.isAvailable ? CommandBarService.shared.rowShortcuts : [:]
        switch holder(of: shortcut, rows: rows, commands: ToolShortcutRegistrar.shared.shortcuts,
                      excludingRow: excludingRow, excludingCommand: excludingCommand) {
        case .commandBarRow(let key):
            return CommandBarService.shared.entryTitle(forStableKey: key)
                ?? FeatureStrings.commandBar(L10n.shared.language).rowShortcutsTitle
        case .toolCommand(let text):
            // A command that is not registered now has no title to give.
            return CommandID(text).flatMap { ToolRegistry.shared.title(for: $0, language: L10n.shared.language) } ?? text
        case nil:
            return nil
        }
    }
}
```

- [ ] **Step 4: Ask it at every place that records a shortcut**

Each edit adds one check after the existing ones. `shortcutConflictFormat` is the existing string "This shortcut is already used by %@."

**`Sources/Vitruvian/UI/ShortcutRecorderButton.swift`**, `ShortcutPreferenceRow.save`. After the block

```swift
        if let conflict = additionalConflict(shortcut) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
```
add
```swift
        if let conflict = ShortcutConflicts.title(for: shortcut) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
```
This one row type is every role's recorder, on the Shortcuts page and on each feature's own page.

**`Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift`**, `CentralWindowLayoutShortcutRow.save`. After the block that begins `if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut,` and ends `return\n        }`, add the same four lines as above.

**`Sources/Vitruvian/UI/Settings/WindowLayoutSettings.swift`**, the row's `save` (it has the same two checks). After the `WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: action)` block, add the same four lines.

**`Sources/Vitruvian/UI/Settings/CutPasteSettings.swift`**, `saveRenameShortcut`. After the block

```swift
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
```
add
```swift
        if let conflict = ShortcutConflicts.title(for: shortcut) {
            renameError = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
```

**`Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift`**, `shortcutConflictTitle(_:excluding:)`. It already looks at command-bar rows by hand. Replace its tail

```swift
        guard AppFeature.commandBar.isAvailable,
              let row = CommandBarRowShortcuts.key(for: shortcut, in: CommandBarService.shared.rowShortcuts)
        else { return nil }
        return CommandBarService.shared.entryTitle(forStableKey: row)
            ?? FeatureStrings.commandBar(l10n.language).rowShortcutsTitle
```
with
```swift
        return ShortcutConflicts.title(for: shortcut)
```

**`Sources/Vitruvian/UI/Screenshot/ScreenshotToolOrderControls.swift`**, `assign`. The call passes `windowLayoutConflict: { WindowLayoutService.shared.shortcutConflictTitle($0) }`, a closure that returns the holder's name. Change that argument to

```swift
            windowLayoutConflict: { WindowLayoutService.shared.shortcutConflictTitle($0) ?? ShortcutConflicts.title(for: $0) },
```
The rejection it produces is shown with `shortcutConflictFormat` and the name, which is what a row or command clash should show.

**`Sources/Vitruvian/Services/CommandBar/CommandBarService.swift`**, `rowShortcutIssue`. Before its final `return nil`, add

```swift
        if let title = ShortcutConflicts.title(for: shortcut, excludingRow: entry.stableKey) {
            return String(format: strings.shortcutConflictFormat, title)
        }
```
The row map is already checked above through `assignmentIssue`; excluding this row keeps that the only word on rows, and this adds tool commands.

**`Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift`**, `directionalShortcutConflictTitle`. Replace its last line

```swift
        return shortcutConflictTitle(shortcut, excluding: nil, includingDirectional: false)
```
with
```swift
        return shortcutConflictTitle(shortcut, excluding: nil, includingDirectional: false)
            ?? ShortcutConflicts.title(for: shortcut)
```

Find anything this list missed:

Run: `grep -rn "GlobalShortcutRole.conflict(" Sources | grep -v "Core/GlobalShortcut.swift"`
Expected: the eight places above (some call it through a closure). For each line of output, the function it is in must also reach `ShortcutConflicts.title`, directly or through `WindowLayoutService.directionalShortcutConflictTitle`. A place that does not is a recorder this task missed: add the check there in the same form as its neighbours.

- [ ] **Step 5: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=command-bar --test_arg=--suite=window-layout --test_arg=--suite=utilities --test_arg=--suite=screenshots --test_arg=--suite=settings`
Expected: PASS for all six.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

- [ ] **Step 6: Commit**

Append to the part 3 entry in `UPSTREAM.md`:

```markdown
  - `UI/ShortcutRecorderButton.swift`, `UI/Settings/ShortcutsSettings.swift`, `UI/Settings/WindowLayoutSettings.swift`, `UI/Settings/CutPasteSettings.swift`, `UI/Settings/RadialMenuSettings.swift`, `UI/Screenshot/ScreenshotToolOrderControls.swift`, `Services/CommandBar/CommandBarService.swift`, `Services/WindowLayout/WindowLayoutService.swift`: every recorder also refuses a combination a Command Bar row or a tool command holds (`Services/ShortcutConflicts.swift`). Before this, only the radial menu's editor and the Command Bar's own looked at rows, so a role or a window-layout action could be given a combination a row already held.
```

```bash
git add Sources/Vitruvian/Services/ShortcutConflicts.swift Sources/Vitruvian/UI/ShortcutRecorderButton.swift Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift Sources/Vitruvian/UI/Settings/WindowLayoutSettings.swift Sources/Vitruvian/UI/Settings/CutPasteSettings.swift Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift Sources/Vitruvian/UI/Screenshot/ScreenshotToolOrderControls.swift Sources/Vitruvian/Services/CommandBar/CommandBarService.swift Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "fix(desktop): refuse a shortcut a Command Bar row or a tool command already holds"
```

---

### Task 6: Rows on the Shortcuts page

**Files:**
- Create: `Sources/Vitruvian/UI/Settings/ToolCommandShortcutRow.swift`
- Modify: `Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift` (two observed objects, one computed property, one `ForEach` in `body`)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolShortcutRegistrar.shared` (`shortcuts`, `refused`, `assign`), `ToolRegistry.shared` (`commands(on: .shortcut)`, `title`, `name`, `canRun`), `ShortcutConflicts.title`, `GlobalShortcutRole.conflict`, `WindowLayoutService.shared.shortcutConflictTitle`, `ShortcutMap.assignmentIssue`, `SystemShortcutTakeover`, `SystemShortcutTakeoverSupport.recorderDecision`, the UI module's `ShortcutRecorderButton`, `ShortcutRowLabel`, `SystemShortcutTakeOverOffer`, `ShortcutRecordingCaption`.
- Produces:
  - `ToolCommandShortcutSection` (`toolID`, `name`, `commands`) and `ToolCommandShortcutSection.all(registry:language:)`
  - `ToolCommandShortcutRow(command:)`

The row is modelled on `CentralWindowLayoutShortcutRow` in `ShortcutsSettings.swift`, the app's existing row for a shortcut that may be empty. It differs in three ways: there is no default, so no Reset button; the value is saved through the registrar, not `@AppStorage`; and it can show that macOS refused the key.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `shortcutSections(suite)` to the end of `run(_:)`, and add:

```swift
    static func shortcutSections(_ suite: TestSuite) {
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        suite.expect(ToolCommandShortcutSection.all(registry: shipped, language: .systemDefault).isEmpty,
                     "with only the app's own tools, the Shortcuts page gains no section")
        SampleTool.install(into: shipped, say: { _ in })
        let sections = ToolCommandShortcutSection.all(registry: shipped, language: .systemDefault)
        suite.expect(sections.count == 1 && sections[0].toolID == SampleTool.id
                         && sections[0].name == "Sample tool"
                         && sections[0].commands.map(\.id) == [SampleTool.hello],
                     "a tool whose commands ask for a shortcut gets a section under its own name")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ToolCommandShortcutSection' in scope`.

- [ ] **Step 3: Write the section model and the row**

Create `Sources/Vitruvian/UI/Settings/ToolCommandShortcutRow.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// One tool's commands that may have a shortcut, for the Shortcuts page.
package struct ToolCommandShortcutSection: Identifiable, Equatable {
    package let toolID: ToolID
    package let name: String
    package let commands: [CommandDescriptor]
    package var id: String { toolID.rawValue }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(toolID: ToolID, name: String, commands: [CommandDescriptor]) {
        self.toolID = toolID
        self.name = name
        self.commands = commands
    }

    /// A section per tool, in the registry's order, headed by the tool's own
    /// name. Empty when no registered command asks for a shortcut.
    @MainActor package static func all(registry: ToolRegistry = .shared,
                                       language: AppLanguage = L10n.shared.language) -> [ToolCommandShortcutSection] {
        var order: [ToolID] = []
        var byTool: [ToolID: [CommandDescriptor]] = [:]
        for command in registry.commands(on: .shortcut) {
            if byTool[command.id.tool] == nil { order.append(command.id.tool) }
            byTool[command.id.tool, default: []].append(command)
        }
        return order.map { tool in
            ToolCommandShortcutSection(toolID: tool,
                                       name: registry.name(for: tool, language: language) ?? tool.rawValue,
                                       commands: byTool[tool] ?? [])
        }
    }
}

/// A tool command's row on the Shortcuts page: its shortcut, empty until the
/// person records one.
package struct ToolCommandShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var registry = ToolRegistry.shared
    @ObservedObject private var registrar = ToolShortcutRegistrar.shared
    private let command: CommandDescriptor
    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    package init(command: CommandDescriptor) {
        self.command = command
    }

    private var text: ShortcutSettingsStrings { FeatureStrings.shortcuts(l10n.language) }
    private var id: CommandID { command.id }
    private var takeOverKey: String { ToolCommandShortcuts.takeOverKey(for: id) }

    private var shortcut: GlobalShortcut? {
        ToolCommandShortcuts.shortcut(for: id, in: registrar.shortcuts)
    }

    /// Holds a key now: it has a combination, its command can run, and macOS gave it.
    private var isActive: Bool {
        shortcut != nil && registry.canRun(id) && !registrar.refused.contains(id)
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                ShortcutRowLabel(
                    title: registry.title(for: id, language: l10n.language) ?? command.title,
                    symbolName: command.symbol,
                    contextLabel: nil,
                    statusText: isActive ? text.active : text.inactive,
                    statusIsActive: isActive
                )
                Spacer()
                HStack(spacing: 8) {
                    ShortcutRecorderButton(
                        shortcut: pendingTakeOver ?? shortcut ?? .commandBarDefault,
                        isEnabled: true,
                        waitingTitle: l10n.s.shortcutPressKeys,
                        emptyTitle: pendingTakeOver == nil && shortcut == nil ? l10n.s.shortcutNone : nil,
                        clearAction: clear,
                        notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                        recordingChanged: { recording in
                            isRecording = recording
                            if recording {
                                errorText = nil
                                pendingTakeOver = nil
                            }
                        },
                        invalidAction: { errorText = l10n.s.shortcutInvalid },
                        captureAction: save
                    )
                    .frame(width: 108)
                    if registrar.refused.contains(id) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(l10n.s.shortcutUnavailable)
                            .accessibilityLabel(l10n.s.shortcutUnavailable)
                    }
                    Button {
                        clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(shortcut == nil)
                    .help(l10n.s.shortcutClear)
                    .accessibilityLabel(l10n.s.shortcutClear)
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        SystemShortcutTakeover.setTakeOver(takeOverKey, true)
                        registrar.assign(pendingTakeOver, to: id)
                        self.pendingTakeOver = nil
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private func clear() {
        errorText = nil
        pendingTakeOver = nil
        registrar.assign(nil, to: id)
    }

    /// Every list that can hold a combination is asked before it is saved,
    /// in the order the other rows ask: roles and wheels, window layout,
    /// then Command Bar rows and other tool commands.
    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: nil, includeInactive: true) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        if let conflict = ShortcutConflicts.title(for: shortcut, excludingCommand: id) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        switch ShortcutMap.assignmentIssue(shortcut, for: id.rawValue, in: registrar.shortcuts,
                                           limit: ToolCommandShortcuts.limit) {
        case .invalid:
            errorText = l10n.s.shortcutInvalid
            return
        case .full:
            errorText = String(format: FeatureStrings.commandBar(l10n.language).rowShortcutsLimitFormat,
                               ToolCommandShortcuts.limit)
            return
        case .occupied, nil:
            // Another command holding it was refused just above.
            break
        }
        // The offer is the last word on a combination: every other check has
        // already passed, so accepting it writes exactly what a save writes.
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(takeOverKey),
            current: self.shortcut) {
        case .offer:
            pendingTakeOver = shortcut
            errorText = nil
        case .save(let clearTakeOver):
            errorText = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(takeOverKey, false) }
            registrar.assign(shortcut, to: id)
        }
    }
}
```

`rowShortcutsLimitFormat` is the Command Bar's existing "at most %d" message; it does not name the Command Bar. Confirm that before relying on it:

Run: `grep -n "rowShortcutsLimitFormat" Sources/Vitruvian/Core/*.swift | head -3`
Expected: a format string with one `%d` and no mention of the Command Bar. If it names the Command Bar, show `l10n.s.shortcutInvalid` for `.full` instead, and say so in the pull request: a list of 64 is not expected to fill.

- [ ] **Step 4: Show the sections on the page**

In `Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift`, add beside the other observed objects of `ShortcutsSettings`:

```swift
    /// Redraw when a tool registers, leaves, or is switched on or off, and
    /// when a command's shortcut changes.
    @ObservedObject private var registry = ToolRegistry.shared
    @ObservedObject private var toolShortcuts = ToolShortcutRegistrar.shared
```

In `body`, directly after the closing brace of

```swift
            ForEach(visibleGroups, id: \.self) { group in
                Section(groupTitle(group)) {
                    ...
                }
            }
```
and before `if AppFeature.commandBar.isAvailable {`, add:

```swift
            // Tools outside the app's own lists, each under its own name.
            ForEach(ToolCommandShortcutSection.all(registry: registry, language: l10n.language)) { section in
                Section(section.name) {
                    ForEach(section.commands, id: \.id) { command in
                        ToolCommandShortcutRow(command: command)
                    }
                }
            }
```

- [ ] **Step 5: Run the tests and both builds**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=settings`
Expected: PASS for both.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian && bazel build --config=macos-app --define=vitruvian_sample_tool=true //apps/desktop/vitruvian:Vitruvian`
Expected: both build.

- [ ] **Step 6: Commit**

Append to the part 3 entry in `UPSTREAM.md`:

```markdown
  - `UI/Settings/ShortcutsSettings.swift`: a section per tool whose commands ask for a shortcut, headed by the tool's own name; none with only the app's own tools.
```

```bash
git add Sources/Vitruvian/UI/Settings/ToolCommandShortcutRow.swift Sources/Vitruvian/UI/Settings/ShortcutsSettings.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): record shortcuts for tool commands on the Shortcuts page"
```

---

### Task 7: Guard, document, and check by hand

**Files:**
- Modify: `Tests/mutation_checks.py`
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (section 12, sub-project 1 row)
- Modify: `UPSTREAM.md`

- [ ] **Step 1: Plant two regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of the `MUTATIONS` list:

```python
    ("a switched-off tool keeps its key", "platform",
     "Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift",
     "let id = CommandID(text), asking.contains(id),",
     "let id = CommandID(text),",
     "a shortcut whose command is not registered holds no key"),
    ("a command that is not registered frees its combination", "platform",
     "Sources/Vitruvian/Services/ShortcutConflicts.swift",
     "        if let command = ToolCommandShortcuts.holder(of: shortcut, in: commands, excluding: excludingCommand) {\n            return .toolCommand(command)\n        }\n",
     "",
     "a combination a tool command holds is taken"),
```

Run: `grep -c "let id = CommandID(text), asking.contains(id)," Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift; grep -c "ToolCommandShortcuts.holder(of: shortcut, in: commands, excluding: excludingCommand)" Sources/Vitruvian/Services/ShortcutConflicts.swift`
Expected: `1` and `1`.

- [ ] **Step 2: Prove each mutation by hand**

For each of the two: apply it by editing the file, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`, confirm it fails with exactly the entry's sixth field, undo the edit, and confirm `git diff --stat -- <file>` shows nothing. Put both failing outputs in the pull request. If a mutation is not detected, stop: do not adjust the test to fit.

Run: `python3 -c "import ast; ast.parse(open('apps/desktop/vitruvian/Tests/mutation_checks.py').read())"` (from the repository root)
Expected: no output.

- [ ] **Step 3: Write the rules down**

In `AGENTS.md`, directly after the bullets about the tool registry, add:

```markdown
- A global shortcut lives in one of five lists: `GlobalShortcutRole` (and the
  radial wheels it reads), window-layout actions, Command Bar rows, and tool
  commands. Anything that records one asks all of them before it saves:
  `GlobalShortcutRole.conflict`, `WindowLayoutService.shortcutConflictTitle`,
  then `ShortcutConflicts.title`, which covers rows and tool commands. A new
  list of shortcuts is added to `ShortcutConflicts`, not checked by hand at
  each recorder.
- A hotkey registrar that is tied to no hub feature must be re-synced in
  `ShortcutCapture.end()`: recording releases every key the app holds, and
  only each feature's own sync gives them back. Leaving this out fails
  silently, after the first shortcut the person records.
- One of the app's own commands that already has a `GlobalShortcutRole` does
  not also ask for the `shortcut` surface: that would give one action two
  combinations.
```

In `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`, section 12, in the sub-project 1 row's last cell, replace

```
Part 3: shortcuts for such commands, on the Shortcuts page.
```
with
```
Part 3 (done): such commands can be given a shortcut on the Shortcuts page, and every recorder refuses a combination any other list holds.
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

- [ ] **Step 5: Check by hand**

No unit test registers a real key or records one. Accessibility has to be granted again after each rebuild.

**A release-shaped build** (no flag):

1. Open Settings › Shortcuts. The page has the sections it had before and no new one.
2. Open the Command Bar's app shortcuts and give an app Option-M. On the Shortcuts page, try to record Option-M for Keep awake. It is refused, naming that app. (Before this plan it was accepted.) Clear the app's shortcut again.

**A development build** (`--define=vitruvian_sample_tool=true`):

3. Settings › Shortcuts shows a "Sample tool" section with one row, "Say hello", reading "None" and inactive.
4. Record Control-Option-H on it. The row reads active. Press Control-Option-H in another app: "Hello from the sample tool" appears.
5. **Record any other shortcut on the page** (change Keep awake's, then change it back). Press Control-Option-H again: it still works. This is the check for Review Focus 1.
6. Try to record Control-Option-H for Keep awake: refused, naming "Say hello". Try to record Keep awake's combination on "Say hello": refused, naming Keep awake.
7. Record a combination macOS uses (Command-Space, if Spotlight has it). The take-over offer appears; dismiss it and the row says the combination is in use by macOS.
8. Quit. Open the release-shaped build: no "Sample tool" section, and Control-Option-H does nothing. Try to record Control-Option-H for Keep awake: it is still refused (the saved combination is kept for the tool's return). Open the development build again: the row still reads Control-Option-H and the key works.
9. Clear the shortcut with the row's clear button. The key stops working and Control-Option-H can be recorded elsewhere.

Record the Mac model, the macOS version and the result of each of the nine steps in the pull request. Say plainly which, if any, were not done.

- [ ] **Step 6: Commit and open the pull request**

Append to the part 3 entry in `UPSTREAM.md`:

```markdown
  - `Tests/mutation_checks.py`: two mutations (a switched-off tool keeping its key; a command that is not registered freeing its combination).
```

```bash
git add Tests/mutation_checks.py AGENTS.md UPSTREAM.md ../../../docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md
git commit -m "refactor(desktop): guard and document shortcuts for tool commands"
```

Open one pull request. Because Task 5 is a `fix`, merging it cuts a release: say so in the description, with the one behaviour that changes for users (step 2 above). State what was run, on which Mac and macOS version, the nine hand checks and their results, and what remains untested.
