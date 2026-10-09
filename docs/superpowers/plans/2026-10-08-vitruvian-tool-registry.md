# Vitruvian Tool Registry (part 1: one command table) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the desktop app one registry of tools and commands, and make the radial menu, the Quick panel and the command bar run and list commands through it, with no change a user can see.

**Architecture:** Plain descriptor values in `Core`, a live `ToolRegistry` in `Services`, and one `BuiltinCommand` list that replaces three duplicated "which service call does this action run" switches. Existing enums (`RadialMenuTool`, `QuickLauncherItem`) stay as they are and map onto the command list, so saved user state and upstream ports are untouched. A command registered at run time, in no enum, can be put on a radial wheel and shows in the command bar; that is the seam later sub-projects plug outside tools into.

**Tech Stack:** Swift (AppKit and SwiftUI), Bazel with `--config=macos-app`, the app's own `TestSuite` harness run under Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (sub-project 1). Executors read both.

**What this plan leaves for part 2:** Quick panel tiles and the Shortcuts page listing registry commands that are in no enum. Both need their item model changed from an enum to an id, which is a larger change than everything here. Alerts need no work now: `QuickToolHUD.show` and `Notifier.post` already take plain values, and the capability broker (sub-project 2) is what wraps them.

All paths below are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## Global Constraints

- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file that came from upstream gets a dated entry under "Modifications" in `UPSTREAM.md`, in the same commit. Task 8 lists them; add each as its task lands.
- Module order is `Core <- Design <- Services <- UI <- App`. A file that names something from a later layer does not compile. Descriptors go in `Core`, the registry in `Services`.
- What another module uses must be `package`. A struct's memberwise initializer never leaves its module, so write every initializer out.
- `Core/` and `UI/` and the tests build in Swift 6 mode. `Services/` does not yet. A main-actor type that `Services` code calls is declared `@preconcurrency @MainActor`.
- No new user-facing string in this plan. Every user-facing string needs all 15 `AppLanguage` cases; this plan reuses existing ones.
- Bundled tools keep the ids users already have saved: a bundled tool's id is its `AppFeature` raw value. Never rename one.
- No behaviour a user can see changes. Saved radial wheels, Quick panel order and hidden tiles load exactly as before.
- Tests are behavioural. No test reads a source file as text (`bazel/source_lints.py` fails one that does).
- Build and test only through Bazel:
  ```sh
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest
  ```
  One suite: add `--test_arg=--suite=platform`.
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren)"
  ```
  The token lasts one hour; re-run before each push.
- Commit titles use `refactor(desktop): ...`. Nothing here is a `feat` or `fix`, so no release is cut.

## Review Focus

Failure modes the spec implies that are most likely to reach a user. Each has a test in the task named.

1. **A tool switched off in the Features hub while its command sits on a wheel or in the bar.** The command must neither list nor run. (Task 3, Task 5)
2. **A saved radial wheel holding a command id that no longer exists, or is malformed (`""`, `"noslash"`, `"a/b/c"`).** The slice disappears; the rest of the wheel loads; nothing crashes. (Task 1, Task 5)
3. **The same tool registered twice**, for example the install step running twice. The second is refused and the first keeps working. (Task 3)
4. **The language changes after registration.** A command's title follows the current language, not the one at registration. (Task 3)
5. **A radial tool mapped to the wrong command**, so the screenshot slice starts a recording. Every enum case maps to the command of its own feature. (Task 2, Task 4)

---

### Task 0: Record the baseline

The unit tests were reported not fully green on `main` on 2026-10-08 (27 of 47 suites not running). Know the starting state before changing anything.

**Files:** none.

- [ ] **Step 1: Run the full tests on an untouched checkout**

Run:
```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest 2>&1 | tail -40
```
Expected: a pass, or a failure list. Either is acceptable here.

- [ ] **Step 2: Write the result into the pull request description**

Record the commit hash, which suites ran and which failed. Any suite failing here is pre-existing. A suite that passes here and fails later is yours.

---

### Task 1: Descriptor values in Core

**Files:**
- Create: `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift`
- Create: `Tests/ToolPlatformTests.swift`
- Modify: `Tests/TestGroups.swift` (the `names` array and `all(_:)`)

**Interfaces:**
- Consumes: `AppFeature` (`Core/FeatureCatalog.swift`).
- Produces:
  - `ToolID`: `init?(_ rawValue: String)`, `rawValue: String`, `isBundledForm: Bool`
  - `CommandID`: `init?(_ rawValue: String)`, `init?(tool: ToolID, name: String)`, `tool: ToolID`, `name: String`, `rawValue: String`
  - `ToolSurface`: `.commandBar`, `.radial`, `.quickPanel`
  - `CommandDescriptor(id:title:symbol:surfaces:)`
  - `ToolDescriptor`: `init?(id:name:symbol:commands:)`, `feature: AppFeature?`

- [ ] **Step 1: Write the failing test**

Create `Tests/ToolPlatformTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The tool platform's values and registry, run over doubles: no tool runs.
enum ToolPlatformTests {
    static func run(_ suite: TestSuite) {
        ids(suite)
        descriptors(suite)
    }

    static func ids(_ suite: TestSuite) {
        suite.expect(ToolID("screenshot")?.isBundledForm == true, "a bare name is a bundled tool id")
        suite.expect(ToolID("com.acme.deploys")?.isBundledForm == false, "a dotted name is an outside tool id")
        for bad in ["", ".", ".acme", "acme.", "a/b", "a b", "a\nb", String(repeating: "a", count: 129)] {
            suite.expect(ToolID(bad) == nil, "\(bad.debugDescription) is not a tool id")
        }

        let parsed = CommandID("screenshot/capture")
        suite.expect(parsed?.tool.rawValue == "screenshot" && parsed?.name == "capture",
                     "a command id splits into its tool and its name")
        suite.expect(parsed?.rawValue == "screenshot/capture", "a command id writes back what it read")
        suite.expect(CommandID("com.acme.deploys/open")?.tool.rawValue == "com.acme.deploys",
                     "an outside tool's command keeps the dotted tool id")
        for bad in ["", "noslash", "a/b/c", "/capture", "screenshot/", "a b/c", "a/b c"] {
            suite.expect(CommandID(bad) == nil, "\(bad.debugDescription) is not a command id")
        }
    }

    static func descriptors(_ suite: TestSuite) {
        let tool = ToolID("screenshot")!
        let capture = CommandDescriptor(id: CommandID(tool: tool, name: "capture")!, title: "Capture",
                                        symbol: "camera.viewfinder", surfaces: [.radial])
        let made = ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [capture])
        suite.expect(made?.feature == .screenshot, "a bundled tool finds its feature by id")
        suite.expect(ToolDescriptor(id: ToolID("com.acme.deploys")!, name: "Deploys", symbol: "shippingbox",
                                    commands: [])?.feature == nil,
                     "an outside tool has no feature")

        let stray = CommandDescriptor(id: CommandID("colorPicker/pick")!, title: "Pick", symbol: "eyedropper",
                                      surfaces: [.radial])
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [stray]) == nil,
                     "a tool cannot declare another tool's command")
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [capture, capture]) == nil,
                     "a tool cannot declare one command twice")
    }
}
```

In `Tests/TestGroups.swift`, add `"platform",` to the `names` array directly after `"features",`, and add this entry to the array `all(_:)` returns, directly after the `("features", { ... }),` entry:

```swift
            ("platform", { ToolPlatformTests.run(suite) }),
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ToolID' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vitruvian/Core/Platform/ToolDescriptor.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// A tool's stable identity. A bundled tool's id is its `AppFeature` raw
/// value, which is what users already have saved; an outside tool's is
/// reverse-DNS (`com.acme.deploys`). The dot is what tells them apart, so
/// the two can never collide.
package struct ToolID: Hashable, Sendable, CustomStringConvertible {
    package static let maxLength = 128

    package let rawValue: String

    package init?(_ rawValue: String) {
        guard Self.isValidPart(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    package var description: String { rawValue }

    /// True for an id with no dot: one of the app's own tools.
    package var isBundledForm: Bool { !rawValue.contains(".") }

    /// Letters, digits, dot, hyphen and underscore; no dot at either end.
    /// Ids are read back from saved state, so anything else is refused here
    /// instead of being trusted later.
    static func isValidPart(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= maxLength, !text.hasPrefix("."), !text.hasSuffix(".") else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
    }
}

/// One action of one tool, written `<tool id>/<name>`.
package struct CommandID: Hashable, Sendable, CustomStringConvertible {
    package let tool: ToolID
    package let name: String

    package init?(tool: ToolID, name: String) {
        guard ToolID.isValidPart(name) else { return nil }
        self.tool = tool
        self.name = name
    }

    /// Reads `<tool id>/<name>`. Exactly one slash: the tool id cannot hold
    /// one, and neither can the name.
    package init?(_ rawValue: String) {
        let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let tool = ToolID(String(parts[0])) else { return nil }
        self.init(tool: tool, name: String(parts[1]))
    }

    package var rawValue: String { "\(tool.rawValue)/\(name)" }
    package var description: String { rawValue }
}

/// Where a command may be offered. A command is listed only where its tool
/// asked for it.
package enum ToolSurface: String, Sendable, CaseIterable {
    case commandBar, radial, quickPanel
}

/// One command, as data. `title` is the plain fallback; a bundled tool's
/// title comes from its handler, in the current language.
package struct CommandDescriptor: Equatable, Sendable {
    package let id: CommandID
    package let title: String
    package let symbol: String
    package let surfaces: Set<ToolSurface>

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: CommandID, title: String, symbol: String, surfaces: Set<ToolSurface>) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.surfaces = surfaces
    }
}

/// One tool, as data: what a feature is today.
package struct ToolDescriptor: Equatable, Sendable {
    package let id: ToolID
    package let name: String
    package let symbol: String
    package let commands: [CommandDescriptor]

    /// Nil when a command belongs to another tool or is declared twice, so a
    /// tool that exists is always consistent.
    package init?(id: ToolID, name: String, symbol: String, commands: [CommandDescriptor]) {
        guard commands.allSatisfy({ $0.id.tool == id }),
              Set(commands.map(\.id)).count == commands.count else { return nil }
        self.id = id
        self.name = name
        self.symbol = symbol
        self.commands = commands
    }

    /// The hub feature behind a bundled tool; nil for an outside tool.
    package var feature: AppFeature? { AppFeature(rawValue: id.rawValue) }
}
```

- [ ] **Step 4: Run the test to make sure it passes**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS, with `platform: OK` in the log.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vitruvian/Core/Platform/ToolDescriptor.swift Tests/ToolPlatformTests.swift Tests/TestGroups.swift
git commit -m "refactor(desktop): add tool and command descriptors"
```

---

### Task 2: The built-in command list

Three places each decide which service call an action runs: `QuickLauncherService.Environment.live.perform`, `RadialMenuService.run(_ tool:)`, and the command bar. This is the one list they will share.

**Files:**
- Create: `Sources/Vitruvian/Core/Platform/BuiltinCommand.swift`
- Modify: `Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift` (inside `enum RadialMenuTool`, after `var symbolName`)
- Modify: `Tests/ToolPlatformTests.swift`

**Interfaces:**
- Consumes: `CommandID`, `ToolID`, `AppFeature`, `RadialMenuTool`.
- Produces:
  - `BuiltinCommand` (15 cases, `CaseIterable`): `id: CommandID`, `feature: AppFeature`
  - `RadialMenuTool.command: BuiltinCommand`

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        builtins(suite)
```

and add:

```swift
    static func builtins(_ suite: TestSuite) {
        for command in BuiltinCommand.allCases {
            suite.expect(CommandID(command.rawValue) != nil, "\(command.rawValue) is a command id")
            suite.expect(command.id.tool.rawValue == command.feature.rawValue,
                         "\(command.rawValue) belongs to the tool of its own feature")
        }
        suite.expect(Set(BuiltinCommand.allCases.map(\.rawValue)).count == BuiltinCommand.allCases.count,
                     "no built-in command id repeats")
        for tool in RadialMenuTool.allCases {
            suite.expect(tool.command.feature == tool.feature,
                         "every radial tool runs the command of its own feature")
        }
        suite.expect(Set(RadialMenuTool.allCases.map(\.command)).count == RadialMenuTool.allCases.count,
                     "no two radial tools share a command")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'BuiltinCommand' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vitruvian/Core/Platform/BuiltinCommand.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Every action of the app's own tools that a surface can trigger. The one
/// list: the radial menu, the Quick panel and the command bar map onto it
/// instead of each choosing a service call. Raw values are command ids and
/// may end up in saved state; never rename one.
package enum BuiltinCommand: String, CaseIterable, Sendable {
    case screenshotCapture = "screenshot/capture"
    case screenRecorderToggle = "screenRecorder/toggle"
    case colorPickerPick = "colorPicker/pick"
    case screenOCRCapture = "screenOCR/capture"
    case micMuteToggle = "micMute/toggle"
    case clipboardHistoryShow = "clipboardHistory/show"
    case quickLauncherShow = "quickLauncher/show"
    case cameraPreviewShow = "cameraPreview/show"
    case scratchpadShow = "scratchpad/show"
    case shelfSummon = "shelf/summon"
    case cleanerOpen = "cleaner/open"
    case uninstallerOpen = "uninstaller/open"
    case appUpdatesCheck = "appUpdates/check"
    case cleaningModeActivate = "cleaningMode/activate"
    case keepAwakeToggle = "keepAwake/toggle"

    /// Every raw value above parses and names a real feature; the
    /// "built-in commands" test fails the build's tests otherwise.
    package var id: CommandID { CommandID(rawValue)! }

    package var feature: AppFeature { AppFeature(rawValue: id.tool.rawValue)! }
}
```

In `Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift`, inside `enum RadialMenuTool`, directly after the line `package var symbolName: String { feature.symbolName }`, add:

```swift

    /// The registry command this slice runs.
    package var command: BuiltinCommand {
        switch self {
        case .screenshot: return .screenshotCapture
        case .screenRecorder: return .screenRecorderToggle
        case .colorPicker: return .colorPickerPick
        case .screenOCR: return .screenOCRCapture
        case .micMute: return .micMuteToggle
        case .clipboardHistory: return .clipboardHistoryShow
        case .quickLauncher: return .quickLauncherShow
        case .cameraPreview: return .cameraPreviewShow
        case .scratchpad: return .scratchpadShow
        case .shelf: return .shelfSummon
        case .cleaner: return .cleanerOpen
        case .uninstaller: return .uninstallerOpen
        case .appUpdates: return .appUpdatesCheck
        case .cleaningMode: return .cleaningModeActivate
        case .keepAwake: return .keepAwakeToggle
        }
    }
```

- [ ] **Step 4: Run the test to make sure it passes**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS, with `platform: OK` in the log.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vitruvian/Core/Platform/BuiltinCommand.swift Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift Tests/ToolPlatformTests.swift
git commit -m "refactor(desktop): list the built-in commands once"
```

---

### Task 3: The registry

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/ToolRegistry.swift`
- Modify: `Tests/ToolPlatformTests.swift`

**Interfaces:**
- Consumes: `ToolDescriptor`, `CommandDescriptor`, `CommandID`, `ToolID`, `ToolSurface`, `AppFeature`, `AppLanguage`.
- Produces, on `ToolRegistry` (`@preconcurrency @MainActor`, `ObservableObject`):
  - `static let shared: ToolRegistry`
  - `init(isAvailable: @escaping (AppFeature) -> Bool)`
  - `struct Handler { init(title: @escaping @MainActor (AppLanguage) -> String, isRunnable: @escaping @MainActor () -> Bool = { true }, run: @escaping @MainActor () -> Void) }`
  - `enum RegistrationError: Error, Equatable { case duplicateTool(ToolID), unknownCommand(CommandID) }`
  - `func register(_ tool: ToolDescriptor) throws`
  - `func setHandler(_ handler: Handler, for id: CommandID) throws`
  - `func unregister(_ id: ToolID)`
  - `func tool(_ id: ToolID) -> ToolDescriptor?`
  - `func command(_ id: CommandID) -> CommandDescriptor?`
  - `func hasHandler(for id: CommandID) -> Bool`
  - `func commands(on surface: ToolSurface) -> [CommandDescriptor]`
  - `func title(for id: CommandID, language: AppLanguage) -> String?`
  - `func canRun(_ id: CommandID) -> Bool`
  - `@discardableResult func run(_ id: CommandID) -> Bool`

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        registry(suite)
```

and add:

```swift
    /// A registry over doubles: `off` holds the features switched off in the hub.
    final class World {
        var off: Set<AppFeature> = []
        var ran: [String] = []
        var language = "first"
        lazy var registry = ToolRegistry(isAvailable: { [unowned self] in !self.off.contains($0) })

        func add(_ toolID: String, _ name: String, surfaces: Set<ToolSurface>, runnable: Bool = true) throws {
            let tool = ToolID(toolID)!
            let id = CommandID(tool: tool, name: name)!
            let command = CommandDescriptor(id: id, title: "plain \(name)", symbol: "star", surfaces: surfaces)
            try registry.register(ToolDescriptor(id: tool, name: toolID, symbol: "star", commands: [command])!)
            try registry.setHandler(.init(title: { [unowned self] _ in "\(self.language) \(name)" },
                                          isRunnable: { runnable },
                                          run: { [unowned self] in self.ran.append(id.rawValue) }),
                                    for: id)
        }
    }

    static func registry(_ suite: TestSuite) {
        let world = World()
        let registry = world.registry
        let capture = CommandID("screenshot/capture")!
        let open = CommandID("com.acme.deploys/open")!
        do {
            try world.add("screenshot", "capture", surfaces: [.radial, .quickPanel])
            try world.add("com.acme.deploys", "open", surfaces: [.radial, .commandBar])
            try world.add("shelf", "summon", surfaces: [.radial], runnable: false)
        } catch {
            suite.expect(false, "registering three distinct tools succeeds, got \(error)")
        }

        suite.expect(registry.commands(on: .radial).map(\.id.rawValue)
                         == ["screenshot/capture", "com.acme.deploys/open", "shelf/summon"],
                     "a surface lists its commands in registration order")
        suite.expect(registry.commands(on: .commandBar).map(\.id) == [open],
                     "a command is listed only where its tool asked for it")
        suite.expect(registry.commands(on: .quickPanel).map(\.id) == [capture],
                     "a command is listed only where its tool asked for it")

        suite.expect(registry.run(capture) && registry.run(open) && world.ran == [capture.rawValue, open.rawValue],
                     "running a command calls its handler once")

        suite.expect(registry.title(for: capture, language: .systemDefault) == "first capture",
                     "a title comes from the handler")
        world.language = "second"
        suite.expect(registry.title(for: capture, language: .systemDefault) == "second capture",
                     "a title follows the language of the moment it is read")

        let summon = CommandID("shelf/summon")!
        world.ran = []
        suite.expect(!registry.canRun(summon) && !registry.run(summon) && world.ran.isEmpty,
                     "a command its handler calls not runnable does not run")

        world.off = [.screenshot]
        suite.expect(!registry.commands(on: .radial).contains { $0.id == capture }
                         && !registry.canRun(capture) && !registry.run(capture) && world.ran.isEmpty,
                     "a command of a switched-off tool neither lists nor runs")
        suite.expect(registry.canRun(open), "an outside tool is not tied to a hub feature")
        world.off = []

        var refused: ToolRegistry.RegistrationError?
        do { try world.add("screenshot", "capture", surfaces: [.radial]) } catch {
            refused = error as? ToolRegistry.RegistrationError
        }
        suite.expect(refused == .duplicateTool(ToolID("screenshot")!), "a tool registers once")
        suite.expect(registry.run(capture) && world.ran == [capture.rawValue],
                     "the first registration keeps working after a refused second one")

        let missing = CommandID("screenshot/missing")!
        var unknown: ToolRegistry.RegistrationError?
        do { try registry.setHandler(.init(title: { _ in "" }, run: {}), for: missing) } catch {
            unknown = error as? ToolRegistry.RegistrationError
        }
        suite.expect(unknown == .unknownCommand(missing), "a handler needs a declared command")
        suite.expect(!registry.run(missing) && !registry.canRun(missing) && registry.title(for: missing, language: .systemDefault) == nil,
                     "an id nothing declared neither runs nor has a title")

        let before = registry.revision
        registry.unregister(ToolID("com.acme.deploys")!)
        suite.expect(registry.tool(open.tool) == nil && registry.command(open) == nil && !registry.run(open)
                         && registry.commands(on: .commandBar).isEmpty && registry.revision > before,
                     "an unregistered tool takes its commands and handlers with it")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'ToolRegistry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vitruvian/Services/Platform/ToolRegistry.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The app's live table of tools and their commands. A surface asks it what
/// to list and tells it what to run, and names no tool's service.
///
/// Main-actor isolated: every surface reads it on the main thread.
/// `@preconcurrency` keeps the services that call it, which are not
/// actor-isolated yet, free of diagnostics.
@preconcurrency @MainActor
package final class ToolRegistry: ObservableObject {
    package static let shared = ToolRegistry(isAvailable: { $0.isAvailable })

    /// The live half of a command: what its descriptor cannot say as data.
    package struct Handler {
        /// The title in a given language, read each time it is shown.
        package var title: @MainActor (AppLanguage) -> String
        /// False while the tool's own switch is off, beyond hub availability.
        package var isRunnable: @MainActor () -> Bool
        package var run: @MainActor () -> Void

        package init(title: @escaping @MainActor (AppLanguage) -> String,
                     isRunnable: @escaping @MainActor () -> Bool = { true },
                     run: @escaping @MainActor () -> Void) {
            self.title = title
            self.isRunnable = isRunnable
            self.run = run
        }
    }

    package enum RegistrationError: Error, Equatable {
        case duplicateTool(ToolID)
        case unknownCommand(CommandID)
    }

    /// Bumped on every change, so a view that lists commands redraws.
    @Published package private(set) var revision = 0

    private let isAvailable: (AppFeature) -> Bool
    private var order: [ToolID] = []
    private var tools: [ToolID: ToolDescriptor] = [:]
    private var handlers: [CommandID: Handler] = [:]

    package init(isAvailable: @escaping (AppFeature) -> Bool) {
        self.isAvailable = isAvailable
    }

    // MARK: - Registration

    package func register(_ tool: ToolDescriptor) throws {
        guard tools[tool.id] == nil else { throw RegistrationError.duplicateTool(tool.id) }
        tools[tool.id] = tool
        order.append(tool.id)
        revision += 1
    }

    package func setHandler(_ handler: Handler, for id: CommandID) throws {
        guard command(id) != nil else { throw RegistrationError.unknownCommand(id) }
        handlers[id] = handler
        revision += 1
    }

    package func unregister(_ id: ToolID) {
        guard let tool = tools.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        tool.commands.forEach { handlers[$0.id] = nil }
        revision += 1
    }

    // MARK: - Reading

    package func tool(_ id: ToolID) -> ToolDescriptor? { tools[id] }

    package func command(_ id: CommandID) -> CommandDescriptor? {
        tools[id.tool]?.commands.first { $0.id == id }
    }

    package func hasHandler(for id: CommandID) -> Bool { handlers[id] != nil }

    /// What a surface offers now: commands that asked for it, whose tool is
    /// switched on in the hub and that something can run. In registration
    /// order, then the tool's own order.
    package func commands(on surface: ToolSurface) -> [CommandDescriptor] {
        order.compactMap { tools[$0] }
            .filter { isToolAvailable($0.id) }
            .flatMap(\.commands)
            .filter { $0.surfaces.contains(surface) && handlers[$0.id] != nil }
    }

    package func title(for id: CommandID, language: AppLanguage) -> String? {
        guard command(id) != nil else { return nil }
        return handlers[id]?.title(language)
    }

    // MARK: - Running

    package func canRun(_ id: CommandID) -> Bool {
        guard isToolAvailable(id.tool) else { return false }
        return handlers[id]?.isRunnable() ?? false
    }

    @discardableResult
    package func run(_ id: CommandID) -> Bool {
        guard canRun(id), let handler = handlers[id] else { return false }
        handler.run()
        return true
    }

    /// A bundled tool follows its hub feature. An outside tool has none, and
    /// is available while it is registered.
    private func isToolAvailable(_ id: ToolID) -> Bool {
        guard let tool = tools[id] else { return false }
        guard let feature = tool.feature else { return true }
        return isAvailable(feature)
    }
}
```

- [ ] **Step 4: Run the test to make sure it passes**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS, with `platform: OK` in the log.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vitruvian/Services/Platform/ToolRegistry.swift Tests/ToolPlatformTests.swift
git commit -m "refactor(desktop): add the tool registry"
```

---

### Task 4: Register the built-in tools and their handlers

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/BuiltinTools.swift`
- Modify: `Sources/Vitruvian/main.swift` (after the `ServiceViews.install` line, line 17)
- Modify: `Tests/ToolPlatformTests.swift`
- Modify: `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolRegistry`, `BuiltinCommand`, `AppFeature.symbolName`, `AppFeature.hubTitle(_:hub:)` (`Services/Settings/FeatureHubText.swift:13`), `Strings.localized(_:)`, `FeatureStrings.hub(_:)`, `SettingsRouter`, `appShell()`.
- Produces: `BuiltinTools.install(into registry: ToolRegistry = .shared)` (`@MainActor`). After it, every `BuiltinCommand` has a descriptor and a handler in `registry`.

Built-in commands ask for `.radial` and `.quickPanel` only. They do not ask for `.commandBar`, because the bar's hand-built rows for the same actions already exist (`CommandBarCatalog.actionEntries`); asking would list each twice.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        builtinTools(suite)
```

and add:

```swift
    static func builtinTools(_ suite: TestSuite) {
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)

        for feature in AppFeature.allCases {
            suite.expect(registry.tool(ToolID(feature.rawValue)!)?.feature == feature,
                         "\(feature.rawValue) is registered as a tool under its own id")
        }
        for command in BuiltinCommand.allCases {
            suite.expect(registry.command(command.id) != nil && registry.hasHandler(for: command.id),
                         "\(command.rawValue) has a descriptor and a handler")
            suite.expect(registry.title(for: command.id, language: .systemDefault)?.isEmpty == false,
                         "\(command.rawValue) has a title")
        }
        suite.expect(Set(registry.commands(on: .radial).map(\.id)) == Set(BuiltinCommand.allCases.map(\.id)),
                     "every built-in command can sit on a wheel")
        suite.expect(registry.commands(on: .commandBar).isEmpty,
                     "built-in commands leave the bar to its hand-built rows")

        // Installing again must not disturb what is there.
        BuiltinTools.install(into: registry)
        suite.expect(registry.commands(on: .radial).count == BuiltinCommand.allCases.count,
                     "installing twice registers nothing twice")
    }
```

This test runs no handler, so no real service starts.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `cannot find 'BuiltinTools' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vitruvian/Services/Platform/BuiltinTools.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// Puts the app's own tools in the registry: one tool per hub feature, and a
/// handler for each built-in command. This is the only place that knows
/// which service call a built-in command runs.
@MainActor
package enum BuiltinTools {
    /// Called once from `main.swift`, before anything can present. Safe to
    /// call again: a tool already there is left alone.
    package static func install(into registry: ToolRegistry = .shared) {
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            let commands = BuiltinCommand.allCases.filter { $0.feature == feature }.map { command in
                CommandDescriptor(id: command.id, title: feature.rawValue, symbol: feature.symbolName,
                                  surfaces: [.radial, .quickPanel])
            }
            guard let tool = ToolDescriptor(id: id, name: feature.rawValue, symbol: feature.symbolName,
                                            commands: commands) else { continue }
            try? registry.register(tool)
            for command in BuiltinCommand.allCases where command.feature == feature {
                try? registry.setHandler(handler(for: command), for: command.id)
            }
        }
    }

    /// A built-in command is titled after its feature, as the radial menu
    /// and the Quick panel title it today.
    private static func title(_ feature: AppFeature) -> @MainActor (AppLanguage) -> String {
        { language in feature.hubTitle(Strings.localized(language), hub: FeatureStrings.hub(language)) }
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        appShell()?.openSettingsWindow()
    }

    /// Exhaustive on purpose: a new `BuiltinCommand` does not compile until
    /// it says what it runs.
    private static func handler(for command: BuiltinCommand) -> ToolRegistry.Handler {
        let title = title(command.feature)
        switch command {
        case .screenshotCapture:
            return .init(title: title, run: { ScreenshotService.shared.capture() })
        case .screenRecorderToggle:
            return .init(title: title, run: { ScreenRecorderService.shared.toggle() })
        case .colorPickerPick:
            return .init(title: title, run: { ColorSamplerService.shared.pick() })
        case .screenOCRCapture:
            return .init(title: title, run: { ScreenTextService.shared.capture() })
        case .micMuteToggle:
            return .init(title: title, run: { MicMuteService.shared.toggle() })
        case .clipboardHistoryShow:
            return .init(title: title, run: { ClipboardHistoryService.shared.showHistoryWindow() })
        case .quickLauncherShow:
            return .init(title: title, run: { QuickLauncherService.shared.show() })
        case .cameraPreviewShow:
            return .init(title: title, run: { CameraPreviewService.shared.show() })
        case .scratchpadShow:
            return .init(title: title, run: { ScratchpadService.shared.show() })
        case .shelfSummon:
            // Hub availability and Shelf's own switch are separate: a saved
            // slice stays dormant while Shelf is off and returns with it.
            return .init(title: title,
                         isRunnable: { UserDefaults.standard[Preferences.shelfEnabled] },
                         run: { ShelfService.shared.summon() })
        case .cleanerOpen:
            return .init(title: title, run: { openSettings(at: .cleaner) })
        case .uninstallerOpen:
            return .init(title: title, run: { openSettings(at: .uninstaller) })
        case .appUpdatesCheck:
            return .init(title: title, run: {
                AppUpdatesService.shared.check()
                openSettings(at: .appUpdates)
            })
        case .cleaningModeActivate:
            return .init(title: title, run: { CleaningModeManager.shared.activate() })
        case .keepAwakeToggle:
            return .init(title: title, run: { KeepAwakeManager.shared.toggle() })
        }
    }
}
```

The service calls above are copied from `RadialMenuService.run(_ tool:)` (`Services/RadialMenu/RadialMenuService.swift:784-808`). Before moving on, open that function and confirm each line matches it; it is the behaviour of record.

In `Sources/Vitruvian/main.swift`, directly after the line

```swift
MainActor.assumeIsolated { ServiceViews.install(UIServiceViewFactory()) }
```

add:

```swift
// The app's own tools and commands, in the registry before any surface
// lists or runs one. Top-level code runs on the main thread.
MainActor.assumeIsolated { BuiltinTools.install() }
```

In `UPSTREAM.md`, add at the top of the list under "## Modifications":

```markdown
- **2026-10-08**: Tool registry, part 1 (`docs/superpowers/plans/2026-10-08-vitruvian-tool-registry.md`):
  - `main.swift`: installs the built-in tools and command handlers into `ToolRegistry` before the app runs.
  - `Core/RadialMenu/RadialMenuSupport.swift`: `RadialMenuTool.command` names the built-in command each slice runs.
```

Later tasks append their own lines to this entry.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS, with `platform: OK` in the log.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds. This is what proves `main.swift` compiles; the unit tests do not include it.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vitruvian/Services/Platform/BuiltinTools.swift Sources/Vitruvian/main.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): register the built-in tools and their commands"
```

---

### Task 5: The radial menu runs through the registry

Two changes. Existing tool slices run their command through the registry instead of a private switch. And a slice can be a `command`: any registry command by id, which is how a tool in no enum reaches the wheel.

**Files:**
- Modify: `Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift` (`RadialMenuItem.Kind` at :259; `var tool` at :271; `defaultSymbolName` at :290; `isValidPayload` at :729)
- Modify: `Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift` (`availableItems` at :492; `run(_ item:)` at :743; `run(_ tool:)` at :784)
- Modify: `Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift` (title switch at :452)
- Modify: `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift` (`kindLabel` at :679; payload default at :954; editor switch at :1051)
- Modify: `Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift` (`kindLabel(for:)` at :362)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolRegistry.shared.run`, `.canRun`, `.title(for:language:)`, `.commands(on:)`; `CommandID`; `RadialMenuTool.command`.
- Produces: `RadialMenuItem.Kind.command`; `RadialMenuItem.commandID: CommandID?`.

A version of the app older than this one drops a `command` slice when it loads a wheel (its decoder skips an unknown kind and keeps the rest, `RadialMenuSupport.swift:345-372`). That is the intended downgrade behaviour.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        radial(suite)
```

and add:

```swift
    static func radial(_ suite: TestSuite) {
        let item = RadialMenuItem(kind: .command, name: "Deploys", payload: "com.acme.deploys/open")
        suite.expect(item.commandID == CommandID("com.acme.deploys/open"), "a command slice reads its command id")
        suite.expect(RadialMenuItem(kind: .tool, payload: "com.acme.deploys/open").commandID == nil,
                     "only a command slice has a command id")
        suite.expect(RadialMenuSupport.isValidPayload(item), "a well-formed command id is a valid target")
        for bad in ["", "noslash", "a/b/c"] {
            suite.expect(!RadialMenuSupport.isValidPayload(RadialMenuItem(kind: .command, payload: bad)),
                         "\(bad.debugDescription) is not a valid command target")
        }
        suite.expect(!item.effectiveSymbolName.isEmpty, "a command slice has a symbol to draw")

        let saved = [item, RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)]
        let data = try? JSONEncoder().encode(saved)
        let loaded = data.flatMap { try? JSONDecoder().decode([RadialMenuItem].self, from: $0) }
        suite.expect(loaded == saved, "a wheel with a command slice saves and loads unchanged")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `type 'RadialMenuItem.Kind' has no member 'command'`.

- [ ] **Step 3: Extend the model in Core**

In `Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift`:

Replace
```swift
        case app, file, url, shortcut, tool, quickToggle, windowLayout, media, submenu
```
with
```swift
        case app, file, url, shortcut, tool, quickToggle, windowLayout, media, submenu
        /// Any registry command, by id. Added last: raw values persist.
        case command
```

Directly after the `package var tool: RadialMenuTool? { ... }` property, add:

```swift

    /// The registry command a `command` slice runs; nil when the payload is
    /// not a well-formed command id.
    package var commandID: CommandID? {
        kind == .command ? CommandID(payload) : nil
    }
```

In `defaultSymbolName`, after the `case .submenu: return "ellipsis.circle"` line, add:

```swift
        case .command: return "puzzlepiece.extension"
```

In `isValidPayload`, after the `case .submenu: return true` line, add:

```swift
        case .command: return item.commandID != nil
```

- [ ] **Step 4: Run and let the compiler list the remaining switches**

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian 2>&1 | grep -E "error:.*(exhaustive|command)"`
Expected: `switch must be exhaustive` errors at exactly these places: `RadialMenuService.swift` (`run(_ item:)`), `RadialMenuView.swift` (title), `RadialMenuSettings.swift` (three switches) and `RadialMenuVisualCanvas.swift` (one). If it names any other file, that switch also needs an arm: give it the same result as its `.tool` arm, and add the file to this task's commit.

- [ ] **Step 5: Run slices through the registry in Services**

In `Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift`:

In `availableItems`, directly after the line
```swift
            if let tool = item.tool, !tool.isRunnable() { return nil }
```
add:
```swift
            if item.kind == .command {
                guard let id = item.commandID,
                      MainActor.assumeIsolated({ ToolRegistry.shared.canRun(id) }) else { return nil }
            }
```

In `run(_ item: RadialMenuItem)`, after the `case .submenu: break` arm, add:
```swift
        case .command:
            if let id = item.commandID { run(id) }
```

Replace the whole of `private func run(_ tool: RadialMenuTool) { ... }` (from its signature through its closing brace, lines 784-809) with:

```swift
    private func run(_ tool: RadialMenuTool) {
        guard tool.isRunnable() else { return }
        run(tool.command.id)
    }

    private func run(_ id: CommandID) {
        // The same beat the quick panel gives screen-touching tools, so the
        // wheel is really gone before anything captures or presents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // The main queue's block runs on the main thread.
            MainActor.assumeIsolated { _ = ToolRegistry.shared.run(id) }
        }
    }
```

Then check whether `private static func openSettings(at page: SettingsPage)` directly below still has a caller in this file:

Run: `grep -n "openSettings(at:" Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift`
Expected: only the definition line. Delete the function and the `// Every action runs from a main-queue block.` comment and `@MainActor` attribute above it. If the grep shows another caller, leave it.

- [ ] **Step 6: Give the views their arms**

In `Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift`, in the switch at line 452, after the `.tool` arm (which ends `return tool.feature.hubTitle(...)`), add:

```swift
        case .command:
            guard let commandID else { return text.kindTool }
            // Views draw on the main thread, where the registry lives.
            return MainActor.assumeIsolated {
                ToolRegistry.shared.title(for: commandID, language: L10n.shared.language)
            } ?? text.kindTool
```

In `Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift`:

- In `kindLabel` (line 679), after `case .tool: return text.kindTool`, add:
  ```swift
          case .command: return text.kindTool
  ```
- In the payload-default switch (line 954), after the `.tool` arm, add:
  ```swift
              case .command: item.payload = ToolRegistry.shared.commands(on: .radial).first?.id.rawValue ?? ""
  ```
- In the editor switch (line 1051), after the `.tool` arm's closing brace, add:
  ```swift
          case .command:
              Picker(text.toolLabel, selection: $item.payload) {
                  ForEach(ToolRegistry.shared.commands(on: .radial), id: \.id) { command in
                      Text(ToolRegistry.shared.title(for: command.id, language: l10n.language) ?? command.title)
                          .tag(command.id.rawValue)
                  }
              }
  ```

In `Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift`, in `kindLabel(for:)` (line 362), after `case .tool: return text.kindTool`, add:

```swift
        case .command: return text.kindTool
```

Do **not** add `command` to the editor's "add an item" menu. Find how that menu is built:

Run: `grep -n "kindTool\|Kind\." Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift | head -40`

If the menu lists kinds one by one, leave it as it is. If it iterates `RadialMenuItem.Kind.allCases`, filter the new case out there with `.filter { $0 != .command }`. A user gets no way to add a command slice until a tool exists that is in no enum (part 2); until then the kind exists for saved wheels and tests only.

- [ ] **Step 7: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest`
Expected: PASS apart from anything recorded in Task 0.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

- [ ] **Step 8: Check the wheel by hand**

Unit tests do not open the wheel. Run the app:

```sh
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

Open the radial menu and run three slices: Screenshot, Keep awake, Scratchpad. Each must do what it did before. Open Settings › Radial menu and confirm the "add" menu shows no new kind. Record the Mac model and macOS version in the pull request. Accessibility must be granted again after each rebuild, because the build is signed ad hoc.

- [ ] **Step 9: Commit**

Append to the 2026-10-08 registry entry in `UPSTREAM.md`:

```markdown
  - `Core/RadialMenu/RadialMenuSupport.swift`: `RadialMenuItem.Kind.command` and `commandID`, a slice that runs any registry command by id.
  - `Services/RadialMenu/RadialMenuService.swift`: tool slices run through `ToolRegistry` instead of a private switch; a `command` slice whose command cannot run is left off the wheel.
  - `UI/RadialMenu/RadialMenuView.swift`, `UI/Settings/RadialMenuSettings.swift`, `UI/Settings/RadialMenuVisualCanvas.swift`: arms for the `command` kind.
```

```bash
git add Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift Sources/Vitruvian/UI/RadialMenu/RadialMenuView.swift Sources/Vitruvian/UI/Settings/RadialMenuSettings.swift Sources/Vitruvian/UI/Settings/RadialMenuVisualCanvas.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): run radial menu tools through the registry"
```

---

### Task 6: The Quick panel runs through the registry

**Files:**
- Modify: `Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift` (after `enum QuickLauncherItem`, line 46; `Environment.live`, the `perform:` closure at lines 93-107)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `BuiltinCommand`, `ToolRegistry.shared.run`.
- Produces: `QuickLauncherItem.command: BuiltinCommand?` (nil for the seven utilities the panel hosts inside itself).

The panel's own `run(_:)` (line 334) is unchanged: it still decides the delay and whether to hide, and still calls `environment.perform`. Only what `perform` does in the live app changes.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        quickPanel(suite)
```

and add:

```swift
    static func quickPanel(_ suite: TestSuite) {
        let expected: [QuickLauncherItem: BuiltinCommand] = [
            .keepAwake: .keepAwakeToggle, .micMute: .micMuteToggle, .screenOCR: .screenOCRCapture,
            .screenshot: .screenshotCapture, .screenRecorder: .screenRecorderToggle,
            .colorPicker: .colorPickerPick, .cameraPreview: .cameraPreviewShow,
            .scratchpad: .scratchpadShow, .clipboard: .clipboardHistoryShow, .cleaning: .cleaningModeActivate,
        ]
        for item in QuickLauncherItem.allCases {
            suite.expect(item.command == expected[item], "\(item.rawValue) runs the command it always ran")
            if let command = item.command {
                suite.expect(command.feature == item.feature, "\(item.rawValue)'s command belongs to its feature")
            }
        }
        let hosted: Set<QuickLauncherItem> = [.windowLayout, .homebrew, .media, .urlCleaner, .uninstaller,
                                              .cleaner, .toggles]
        suite.expect(Set(QuickLauncherItem.allCases.filter { $0.command == nil }) == hosted,
                     "only the utilities the panel hosts itself have no command")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `value of type 'QuickLauncherItem' has no member 'command'`.

- [ ] **Step 3: Write the implementation**

In `Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift`, directly after the closing brace of `enum QuickLauncherItem` (line 46), add:

```swift

extension QuickLauncherItem {
    /// The registry command a tile runs. Nil for the utilities the panel
    /// hosts inside itself, which run nothing outside it.
    package var command: BuiltinCommand? {
        switch self {
        case .keepAwake: return .keepAwakeToggle
        case .micMute: return .micMuteToggle
        case .screenOCR: return .screenOCRCapture
        case .screenshot: return .screenshotCapture
        case .screenRecorder: return .screenRecorderToggle
        case .colorPicker: return .colorPickerPick
        case .cameraPreview: return .cameraPreviewShow
        case .scratchpad: return .scratchpadShow
        case .clipboard: return .clipboardHistoryShow
        case .cleaning: return .cleaningModeActivate
        case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles: return nil
        }
    }
}
```

In `Environment.live`, replace the whole `perform:` argument:

```swift
                perform: { item in
                    switch item {
                    case .keepAwake: KeepAwakeManager.shared.toggle()
                    case .micMute: MicMuteService.shared.toggle()
                    case .screenOCR: ScreenTextService.shared.capture()
                    case .screenshot: ScreenshotService.shared.capture()
                    case .screenRecorder: ScreenRecorderService.shared.toggle()
                    case .colorPicker: ColorSamplerService.shared.pick()
                    case .cameraPreview: CameraPreviewService.shared.show()
                    case .scratchpad: ScratchpadService.shared.show()
                    case .clipboard: ClipboardHistoryService.shared.showHistoryWindow()
                    case .cleaning: CleaningModeManager.shared.activate()
                    case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles: break
                    }
                },
```

with:

```swift
                perform: { item in
                    if let command = item.command { ToolRegistry.shared.run(command.id) }
                },
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=launcher`
Expected: PASS for both suites. The existing `launcher` suite (`QuickLauncherContract`) passes its own `perform` double, so it proves the panel's delay and hide rules did not move.

- [ ] **Step 5: Check the panel by hand**

Rebuild and run as in Task 5 Step 8. Open the Quick panel and run Keep awake, Screenshot and Clipboard. Each must do what it did before. Record the result in the pull request.

- [ ] **Step 6: Commit**

Append to the 2026-10-08 registry entry in `UPSTREAM.md`:

```markdown
  - `Services/QuickTools/QuickLauncherService.swift`: `QuickLauncherItem.command`; the live `perform` runs it through `ToolRegistry` instead of a private switch.
```

```bash
git add Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): run Quick panel tiles through the registry"
```

---

### Task 7: The command bar lists registry commands

**Files:**
- Modify: `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift` (`build(automationDenied:)` at line 184; a new function after it)
- Modify: `Tests/ToolPlatformTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolRegistry.commands(on: .commandBar)`, `.title(for:language:)`, `.tool(_:)`, `.run(_:)`; `CommandBarEntry.init(id:stableKey:title:subtitle:keywords:icon:...run:)` (`CommandBarCatalog.swift:125`).
- Produces: `CommandBarCatalog.toolEntries(registry: ToolRegistry, language: AppLanguage) -> [CommandBarEntry]` (`@MainActor`).

No built-in command asks for the bar (Task 4), so the live bar gains no row from this task. A row appears the moment any tool registers a command with `.commandBar`.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add to `run(_:)`:

```swift
        commandBar(suite)
```

and add:

```swift
    static func commandBar(_ suite: TestSuite) {
        let world = World()
        do {
            try world.add("com.acme.deploys", "open", surfaces: [.commandBar])
            try world.add("screenshot", "capture", surfaces: [.radial])
        } catch {
            suite.expect(false, "registering two distinct tools succeeds, got \(error)")
        }
        let rows = CommandBarCatalog.toolEntries(registry: world.registry, language: .systemDefault)
        suite.expect(rows.map(\.id) == ["tool.com.acme.deploys/open"],
                     "the bar lists the commands that asked for it, and only those")
        suite.expect(rows.first?.title == "first open" && rows.first?.subtitle == "com.acme.deploys",
                     "a row is titled by its command and filed under its tool")
        suite.expect(rows.first?.stableKey == rows.first?.id,
                     "a row's name and pin survive under its command id")
        rows.first?.run(nil)
        suite.expect(world.ran == ["com.acme.deploys/open"], "Return on a row runs its command")

        world.registry.unregister(ToolID("com.acme.deploys")!)
        suite.expect(CommandBarCatalog.toolEntries(registry: world.registry, language: .systemDefault).isEmpty,
                     "a removed tool leaves no row behind")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a build failure, `type 'CommandBarCatalog' has no member 'toolEntries'`.

- [ ] **Step 3: Write the implementation**

In `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift`, inside `build(automationDenied:)`, directly after the line

```swift
        entries.append(contentsOf: toggleEntries(s, language: language, bar: bar))
```

add:

```swift
        entries.append(contentsOf: toolEntries(registry: .shared, language: language))
```

Directly after the closing brace of `build(automationDenied:)`, add:

```swift

    // MARK: - Registry commands

    /// A row for each registry command that asked for the bar. The app's own
    /// commands do not ask: their rows are the hand-built ones above, with
    /// their arguments, confirmations and live states.
    @MainActor
    package static func toolEntries(registry: ToolRegistry, language: AppLanguage) -> [CommandBarEntry] {
        registry.commands(on: .commandBar).map { command in
            let title = registry.title(for: command.id, language: language) ?? command.title
            return CommandBarEntry(
                id: "tool.\(command.id.rawValue)",
                title: title,
                subtitle: registry.tool(command.id.tool)?.name ?? "",
                keywords: title,
                icon: .symbol(command.symbol),
                run: { _ in registry.run(command.id) })
        }
    }
```

`stableKey` is left out on purpose: the initializer sets it to the id (`self.stableKey = stableKey ?? id`, line 148), which is what the test's third expectation checks.

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=command-bar`
Expected: PASS for both suites.

- [ ] **Step 5: Commit**

Append to the 2026-10-08 registry entry in `UPSTREAM.md`:

```markdown
  - `Services/CommandBar/CommandBarCatalog.swift`: `toolEntries` adds a row for each registry command that asks for the bar; none of the app's own commands do.
```

```bash
git add Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift Tests/ToolPlatformTests.swift UPSTREAM.md
git commit -m "refactor(desktop): list registry commands in the command bar"
```

---

### Task 8: Guard the wiring, document the rule, verify everything

**Files:**
- Modify: `Tests/mutation_checks.py` (the `MUTATIONS` list)
- Modify: `AGENTS.md` (under "Conventions (from upstream)")
- Modify: `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (section 12, sub-project 1 row)

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Plant two regressions that the tests must catch**

In `Tests/mutation_checks.py`, add to the end of the `MUTATIONS` list (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("radial slice runs another tool's command", "platform",
     "Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift",
     "        case .screenshot: return .screenshotCapture\n",
     "        case .screenshot: return .screenRecorderToggle\n",
     "every radial tool runs the command of its own feature"),
    ("switched-off tool still runs", "platform",
     "Sources/Vitruvian/Services/Platform/ToolRegistry.swift",
     "        guard isToolAvailable(id.tool) else { return false }\n",
     "",
     "a command of a switched-off tool neither lists nor runs"),
```

Each "before" text must occur exactly once in its file, or the check refuses to run:

Run: `grep -c "case .screenshot: return .screenshotCapture" Sources/Vitruvian/Core/RadialMenu/RadialMenuSupport.swift; grep -c "guard isToolAvailable(id.tool) else { return false }" Sources/Vitruvian/Services/Platform/ToolRegistry.swift`
Expected: `1` and `1`.

- [ ] **Step 2: Run the mutation checks**

Commit everything first (the checks edit files in place and refuse a dirty tree), then:

Run: `bazel run --config=macos-app //apps/desktop/vitruvian:mutation_checks`
Expected: every mutation reported as detected, including the two new ones. This runs the unit tests once per mutation and takes a long time; it is the weekly CI job run by hand.

- [ ] **Step 3: Write the rule down for the next person**

In `AGENTS.md`, under "## Conventions (from upstream)", add this bullet after the bullet that begins "A new feature needs an `AppFeature` case":

```markdown
- An action a surface can trigger is a command. Add it as a `BuiltinCommand`
  case (`Core/Platform/BuiltinCommand.swift`) and give it a handler in
  `Services/Platform/BuiltinTools.swift`; the compiler asks for the handler.
  The radial menu, the Quick panel and the command bar run and list commands
  through `ToolRegistry`. Do not add a service call to a surface's own
  switch.
```

- [ ] **Step 4: Bring the spec in line with what was built**

In `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`, section 12, replace the sub-project 1 row's last cell

```
Those five surfaces have no fixed list of tools; saved user layouts are unchanged
```

with

```
Part 1 (done): one command list; the radial menu, Quick panel and command bar run through the registry; a command in no fixed list can sit on a wheel and shows in the bar. Part 2: Quick panel tiles and the Shortcuts page list such commands too. Saved user layouts are unchanged throughout
```

- [ ] **Step 5: Run everything**

Run:
```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
```
Expected: all pass, apart from anything recorded in Task 0. Compare against that record and say so in the pull request.

- [ ] **Step 6: Commit and open the pull request**

```bash
git add Tests/mutation_checks.py AGENTS.md ../../../docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md
git commit -m "refactor(desktop): guard and document the tool registry"
```

Open one pull request for Tasks 1 to 4 (new code and its install; nothing a user can reach changes), then one each for Tasks 5, 6 and 7 with 8. Each description states: what was run, on which Mac and macOS version, what was checked by hand, and what remains untested (the wheel and the panel are exercised by hand only).
