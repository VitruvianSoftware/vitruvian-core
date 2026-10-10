# Vitruvian Broker (stage A: the structure, and the Port manager) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app a tool manifest, a capability broker and a tool host, and move the Port manager onto them, so that no file belonging to the Port manager touches a sensitive service except through the broker.

**Architecture:** A manifest is a plain value in `Core`. The broker is a main-actor class in `Services` that runs three checks (declared, installed, granted) and then calls the shared helpers that exist today. A tool is handed `ToolServices`, a handle that carries its manifest, and reaches nothing else. The tool host builds a tool on first use and hands it to the views. The Port manager's service class becomes the tool: it keeps its file and logic, loses its singleton, and its two views stop calling services.

**Tech Stack:** Swift 6 (AppKit, SwiftUI), Bazel with `--config=macos-app`, the app's own `TestSuite` harness, `bazel/source_lints.py`.

**Spec:** `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md` (approved 2026-10-09). This is stage A of its section 11.

All paths are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## Decisions this plan makes

The spec's nine decisions stand. These are the ones the code forced while planning.

| # | Decision | Why |
|---|---|---|
| 1 | The `processes` capability hands out a **scanner**, a `Sendable` value with two operations, after the checks pass. | A port scan runs off the main thread, and the broker lives on it. The check happens once, on the main actor, when the scan starts. |
| 2 | The scanner returns `lsof`'s report as text, not parsed ports. The spec said `listeningPorts()`. | The parser and the "same process before and after the listing" rule are the Port manager's logic. Upstream edits them, and the existing tests drive them through `Scanning`. They stay in the tool's file. The host runs `lsof` with fixed arguments; the tool cannot choose them. |
| 3 | `proc_listallpids` stays a direct call in the tool. | It is a read-only libc call any program may make. It needs no grant and has no side effect. The broker guards services, not the C library. |
| 4 | A fourth refusal, `unavailable`, beside the spec's three. | "Ending a process is not offered because the Kill process feature is not installed" is none of declared, installed or granted. |
| 5 | **No `storage` capability in stage A.** The spec listed it here. | The Port manager reads no preference of its own. Stage B's tool does. A capability arrives with its first user. |
| 6 | **The host does not start or stop anything yet**, and `FeatureRuntime` is not touched. | The Port manager has no background work: `FeatureRuntime.actions(for: .portManager)` is `[]`, and a test pins it. Start, stop and the run rule arrive in stage B with the first tool that needs them. The host does stop every built tool at quit. |
| 7 | The manifest check is "every declared key is registered with the same default, and no two manifests declare one key", not "exactly the tool's keys". | Nothing in the app says which registered key belongs to which feature, so "exactly" cannot be tested. |

Decisions 2, 4 and 5 change the spec. Task 8 edits the spec to match.

## Global Constraints

- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file whose line 2 says `Copyright (C) 2026 Vorssaint`, test files included, is named in `UPSTREAM.md` under "Modifications" in the same commit. Task 2 creates one entry, `- **<date>**: Tool platform, the broker, stage A (...)`, and later tasks append sub-bullets. Check line 2 of each file you change; do not trust a list.
- Module order is `Core <- Design <- Services <- UI <- App`. All of them and the tests build in Swift 6 mode. What another module uses is `package`. Every initializer is written out.
- **Nothing a user can see changes.** No new string. No new command, tile or row. Same timing.
- **Nothing crosses the broker that could not be written as JSON**: no `NSPasteboard`, `CGEvent`, view type, or closure that captures app state. A completion closure the tool passes in is the exception: it is the in-process form of a reply.
- Under `Services/Platform/Broker/` no file names a tool. In a migrated tool's files no code names a service. Task 7 turns both into lints.
- The Port manager's existing tests (`Tests/PortManagerRefreshTests.swift`, and its parts of `Tests/UtilitiesFeatureTests.swift`) pass with their expectations untouched. If a call site in a test must change because a signature did, change only the call, and quote before and after in the report.
- Tests are behavioural. No test reads a source file as text, kills a real process, writes the real clipboard or opens a real link. The broker takes every service through its `Environment`; tests pass fakes.
- `Tests/mutation_checks.py` quotes exact source text. After editing it or any `.py` or `BUILD` file, run `bazel run //tools/format -- <path>`.
- Build and test through Bazel only, from the repository root, one command at a time:
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
- Commit titles: `refactor(desktop): ...` for every task. Nothing here changes what a release build does.
- The code in this plan was written against `main` at `3ad6ed46d` and has not been compiled. Where it does not compile or does not match the file, make the smallest change that keeps its meaning and record it as a deviation.

## Review Focus

Failure modes most likely to reach a user. Each has a test in the task named, except where it says by hand.

1. **The end-process button behaves differently.** Today it is hidden when the Kill process feature is not installed, disabled for a protected process or one with no stable identity, and ends the process otherwise, with an admin prompt when needed. (Task 6; the admin prompt by hand in Task 8.)
2. **A scan that used to succeed now fails, or blocks the main thread.** `lsof` must still run off the main thread with the same arguments and timeout. (Task 4, Task 6)
3. **The Settings page and the menu panel show different lists.** Today both observe one object. They must still get the same instance. (Task 5)
4. **A refused call does work anyway.** Every operation checks first. (Tasks 3 and 4)
5. **Copy and open-in-browser stop working, or stop beeping on failure.** (Task 6; by hand in Task 8.)

---

### Task 1: The manifest

**Files:**
- Create: `Sources/Vitruvian/Core/Platform/ToolManifest.swift`
- Modify: `Tests/ToolPlatformTests.swift`

**Interfaces:**
- Consumes: `ToolDescriptor`, `ToolID`, `FeatureGroup`, `AppPermission` (all in `Core`).
- Produces: `Capability`, `CapabilityRequest`, `PreferenceDeclaration.Value` (nested: `Core` already has a `PreferenceValue` protocol), `PreferenceDeclaration`, `Activation`, `ToolManifest`.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolPlatformTests.swift`, add `manifests(suite)` to the end of `run(_:)`, and add:

```swift
    static func manifests(_ suite: TestSuite) {
        let tool = ToolDescriptor(id: ToolID("portManager")!, name: "portManager", symbol: "network", commands: [])!
        let copy = CapabilityRequest(.clipboardWrite, reason: "Copies a port, PID or address you pick.")!
        let scan = CapabilityRequest(.processes, reason: "Lists what is listening on a port.")!
        let pref = PreferenceDeclaration(key: "panelUtilityPortManager", default: .bool(true))
        func manifest(capabilities: [CapabilityRequest] = [copy, scan],
                      preferences: [PreferenceDeclaration] = [pref],
                      enabledBy: String? = nil) -> ToolManifest? {
            ToolManifest(tool: tool, group: .tools, capabilities: capabilities, preferences: preferences,
                         activation: [.onShown], enabledBy: enabledBy)
        }

        suite.expect(manifest()?.declares(.processes) == true && manifest()?.declares(.open) == false,
                     "a manifest says which capabilities its tool asks for")
        suite.expect(CapabilityRequest(.open, reason: "  ") == nil,
                     "a capability with no reason is not a request")
        suite.expect(manifest(capabilities: [copy, copy]) == nil,
                     "a capability is listed once")
        suite.expect(manifest(preferences: [pref, pref]) == nil,
                     "a preference key is listed once")
        suite.expect(manifest(enabledBy: "somethingElse") == nil
                         && manifest(enabledBy: "panelUtilityPortManager") != nil,
                     "the preference that enables a tool is one it declares")
        suite.expect(Capability.allCases.allSatisfy { $0.ridesOn.isEmpty },
                     "no stage A capability rides on a macOS grant")
        suite.expect(Set(Capability.allCases.map(\.rawValue)) == ["notify", "open", "processes", "clipboard.write"],
                     "capabilities are named as the platform design names them")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `CapabilityRequest`.

- [ ] **Step 3: Write the manifest**

Create `Sources/Vitruvian/Core/Platform/ToolManifest.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Something the host does on a tool's behalf that needs trust. The raw
/// values are the names in the platform design, and will be the names in
/// the protocol. A case is added when a tool first needs it.
package enum Capability: String, CaseIterable, Hashable, Sendable {
    /// A beep now; alerts and notifications when a tool needs them.
    case notify
    /// Open a link in the person's browser.
    case open
    /// See what is listening on a port, and end a process.
    case processes
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite: return []
        }
    }
}

/// A capability a tool asks for, and why, in a sentence a person could be
/// shown. Nobody is shown it yet; writing it is the cheapest check that the
/// capability is needed.
package struct CapabilityRequest: Equatable, Sendable {
    package let capability: Capability
    package let reason: String

    package init?(_ capability: Capability, reason: String) {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.capability = capability
        self.reason = reason
    }
}

/// A saved value a manifest can state the default of.
package enum PreferenceValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)

    /// The value as `UserDefaults` holds it, for comparing with what the
    /// app registers.
    package var defaultsValue: Any {
        switch self {
        case .bool(let value): return value
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        }
    }
}

/// One preference a tool owns: the key it is saved under today, unchanged,
/// and its default.
package struct PreferenceDeclaration: Equatable, Sendable {
    package let key: String
    package let defaultValue: PreferenceValue

    package init(key: String, default defaultValue: PreferenceValue) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// When the host should have a tool ready.
package enum Activation: String, Sendable {
    case onLaunch, onCommand, onShown
}

/// What a tool is, what it needs and what it adds, as one value. The fields
/// are the platform design's manifest fields that mean something for a tool
/// compiled into the app.
package struct ToolManifest: Equatable, Sendable {
    package let tool: ToolDescriptor
    package let group: FeatureGroup
    package let capabilities: [CapabilityRequest]
    package let preferences: [PreferenceDeclaration]
    package let activation: [Activation]
    /// The preference that switches the tool on, when it has one.
    package let enabledBy: String?

    package init?(tool: ToolDescriptor, group: FeatureGroup, capabilities: [CapabilityRequest],
                  preferences: [PreferenceDeclaration], activation: [Activation], enabledBy: String?) {
        let asked = capabilities.map(\.capability)
        let keys = preferences.map(\.key)
        guard Set(asked).count == asked.count, Set(keys).count == keys.count,
              enabledBy.map(keys.contains) ?? true else { return nil }
        self.tool = tool
        self.group = group
        self.capabilities = capabilities
        self.preferences = preferences
        self.activation = activation
        self.enabledBy = enabledBy
    }

    package var id: ToolID { tool.id }

    package func declares(_ capability: Capability) -> Bool {
        capabilities.contains { $0.capability == capability }
    }
}
```

If `FeatureGroup` is not `Sendable` or `Equatable`, add the conformance to its declaration in `Core/FeatureCatalog.swift` (it is a `String` enum, so both are free) and log that file in `UPSTREAM.md` in Task 2.

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ToolManifest.swift apps/desktop/vitruvian/Tests/ToolPlatformTests.swift
git commit -m "refactor(desktop): describe a tool's needs in a manifest"
```

---

### Task 2: The broker's checks

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift`
- Create: `Tests/ToolBrokerTests.swift`
- Modify: `Tests/TestGroups.swift` (run `ToolBrokerTests.run` in the `platform` group), `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolManifest`, `Capability`, `AppPermission`.
- Produces:
  - `BrokerRefusal: Error, Equatable, Sendable`: `.notDeclared(Capability)`, `.notInstalled`, `.notGranted(AppPermission)`, `.unavailable`
  - `CapabilityBroker` (`@MainActor`): `shared`, `init(environment:)`, `Environment`, `refusal(of:for:) -> BrokerRefusal?`

- [ ] **Step 1: Write the failing test**

Create `Tests/ToolBrokerTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices

/// The capability broker against services that record what they were asked
/// and do nothing.
@MainActor
enum ToolBrokerTests {
    static func run(_ suite: TestSuite) {
        checks(suite)
    }

    /// What the broker is told about the world, and what it reported.
    final class World {
        var installed = true
        var granted: Set<AppPermission> = Set(AppPermission.allCases)
        var allowed = true
        var undeclared: [Capability] = []
    }

    static func manifest(_ capabilities: [Capability]) -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID("portManager")!, name: "portManager", symbol: "network",
                                          commands: [])!,
                     group: .tools,
                     capabilities: capabilities.map { CapabilityRequest($0, reason: "test")! },
                     preferences: [], activation: [.onShown], enabledBy: nil)!
    }

    static func checks(_ suite: TestSuite) {
        let world = World()
        let broker = CapabilityBroker(environment: .init(
            isInstalled: { _ in world.installed },
            isGranted: { world.granted.contains($0) },
            allows: { _, _ in world.allowed },
            reportUndeclared: { _, capability in world.undeclared.append(capability) }))
        let tool = manifest([.open])

        suite.expect(broker.refusal(of: .open, for: tool) == nil,
                     "a declared capability of an installed tool is allowed")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes)
                         && world.undeclared == [.processes],
                     "a capability the manifest does not list is refused, and reported as a mistake")
        world.installed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .notInstalled,
                     "a tool removed in the hub is refused")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes),
                     "not declared is said before not installed")
        world.installed = true
        world.allowed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .unavailable,
                     "a capability the person has not allowed is refused")
    }
}
```

In `Tests/TestGroups.swift`, in the `platform` entry, run both:

```swift
            ("platform", { ToolPlatformTests.run(suite); ToolBrokerTests.run(suite) }),
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `CapabilityBroker`.

- [ ] **Step 3: Write the broker**

Create `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Why the broker would not do something.
package enum BrokerRefusal: Error, Equatable, Sendable {
    /// The tool's manifest does not list the capability. A mistake in the
    /// tool, never something a person did.
    case notDeclared(Capability)
    /// The tool is not installed in the Features hub.
    case notInstalled
    /// A macOS grant the capability rides on is missing.
    case notGranted(AppPermission)
    /// The host cannot offer this right now: the person has not allowed it,
    /// or what it depends on is not there.
    case unavailable
}

/// The one door to the services that need trust. A tool reaches it through
/// `ToolServices`, which carries the tool's manifest, so a tool cannot ask
/// as another. Every operation asks `refusal(of:for:)` before it does
/// anything.
///
/// The broker names no tool. The files beside this one each serve one
/// capability.
@MainActor
package final class CapabilityBroker {
    package struct Environment {
        package var isInstalled: (ToolID) -> Bool
        package var isGranted: (AppPermission) -> Bool
        /// Whether the person allows this tool this capability. Always true
        /// for a tool compiled into the app; a consent screen fills this in
        /// when tools from outside arrive.
        package var allows: (ToolID, Capability) -> Bool
        package var reportUndeclared: (ToolID, Capability) -> Void

        package init(isInstalled: @escaping (ToolID) -> Bool,
                     isGranted: @escaping (AppPermission) -> Bool,
                     allows: @escaping (ToolID, Capability) -> Bool,
                     reportUndeclared: @escaping (ToolID, Capability) -> Void) {
            self.isInstalled = isInstalled
            self.isGranted = isGranted
            self.allows = allows
            self.reportUndeclared = reportUndeclared
        }
    }

    package let environment: Environment

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Why `tool` may not use `capability` now, or nil when it may. The
    /// order is fixed: a mistake in the tool is said before any state of
    /// the person's Mac.
    package func refusal(of capability: Capability, for tool: ToolManifest) -> BrokerRefusal? {
        guard tool.declares(capability) else {
            environment.reportUndeclared(tool.id, capability)
            return .notDeclared(capability)
        }
        guard environment.isInstalled(tool.id) else { return .notInstalled }
        if let missing = capability.ridesOn.first(where: { !environment.isGranted($0) }) {
            return .notGranted(missing)
        }
        guard environment.allows(tool.id, capability) else { return .unavailable }
        return nil
    }
}
```

`shared` and the live `Environment` arrive in Task 5, when every capability's backing exists.

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS. If `test_groups_list_what_they_run` objects to the `platform` entry, follow its message.

- [ ] **Step 5: Start the `UPSTREAM.md` entry**

At the top of `## Modifications`, add (use the day's date):

```markdown
- **<date>**: Tool platform, the broker, stage A (`docs/superpowers/plans/2026-10-09-vitruvian-broker-stage-a.md`):
```

and one sub-bullet for each `Vorssaint`-headed file changed so far (`Tests/TestGroups.swift` if it is one; `Core/FeatureCatalog.swift` if Task 1 touched it).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/Tests/TestGroups.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): check what a tool may use in one place"
```

---

### Task 3: Three small capabilities, and the handle a tool holds

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/NotifyAccess.swift`
- Create: `Sources/Vitruvian/Services/Platform/Broker/OpenAccess.swift`
- Create: `Sources/Vitruvian/Services/Platform/Broker/ClipboardAccess.swift`
- Create: `Sources/Vitruvian/Services/Platform/ToolServices.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift`, `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Consumes: `CapabilityBroker.refusal(of:for:)`.
- Produces:
  - `NotifyAccess`: `beep() -> BrokerRefusal?`; `NotifyAccess.Backing` (`beep`)
  - `OpenAccess`: `url(_:) -> Result<Bool, BrokerRefusal>`; `OpenAccess.Backing` (`open`)
  - `ClipboardAccess`: `write(_:completion:) -> BrokerRefusal?`; `ClipboardAccess.Backing` (`write`)
  - `ToolServices` (`@MainActor` struct): `manifest`, `notify`, `open`, `clipboard`
  - `CapabilityBroker.Backings` and `CapabilityBroker.services(for:)`

Each access type is a struct holding a `gate: () -> BrokerRefusal?` and its backing. Every operation calls the gate first and returns its refusal without touching the backing.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, add `smallCapabilities(suite)` to `run`, and add:

```swift
    /// Services that record and do nothing.
    final class Recorder {
        var beeps = 0
        var opened: [URL] = []
        var opens = true
        var written: [String] = []
        var writes = true
    }

    static func bench(_ capabilities: [Capability], world: World = World(),
                      recorder: Recorder = Recorder()) -> ToolServices {
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, capability in world.undeclared.append(capability) }),
            backings: .init(
                notify: .init(beep: { recorder.beeps += 1 }),
                open: .init(open: { recorder.opened.append($0); return recorder.opens }),
                clipboard: .init(write: { text, completion in
                    recorder.written.append(text)
                    completion(recorder.writes)
                }),
                processes: .inert))
        return broker.services(for: manifest(capabilities))
    }

    static func smallCapabilities(_ suite: TestSuite) {
        let recorder = Recorder()
        let world = World()
        let all = bench([.notify, .open, .clipboardWrite], world: world, recorder: recorder)
        let link = URL(string: "http://localhost:3000")!

        suite.expect(all.notify.beep() == nil && recorder.beeps == 1, "a tool that asks for it can beep")
        suite.expect(all.open.url(link) == .success(true) && recorder.opened == [link],
                     "a tool that asks for it can open a link")
        recorder.opens = false
        suite.expect(all.open.url(link) == .success(false), "a link the system would not open says so")
        var copied: Bool?
        suite.expect(all.clipboard.write("8080") { copied = $0 } == nil && recorder.written == ["8080"]
                         && copied == true,
                     "a tool that asks for it can put text on the clipboard, and hears how it went")

        let none = bench([], world: world, recorder: recorder)
        let before = (recorder.beeps, recorder.opened.count, recorder.written.count)
        var heard = false
        suite.expect(none.notify.beep() == .notDeclared(.notify)
                         && none.open.url(link) == .failure(.notDeclared(.open))
                         && none.clipboard.write("x") { _ in heard = true } == .notDeclared(.clipboardWrite)
                         && (recorder.beeps, recorder.opened.count, recorder.written.count) == before
                         && !heard,
                     "a refused call does no work and calls nothing back")
        world.installed = false
        suite.expect(all.notify.beep() == .notInstalled && recorder.beeps == before.0,
                     "a tool removed in the hub can no longer beep")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `backings` or `ToolServices`.

- [ ] **Step 3: Write the three capabilities**

Create `Sources/Vitruvian/Services/Platform/Broker/NotifyAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The `notify` capability: tell the person something happened.
@MainActor
package struct NotifyAccess {
    package struct Backing {
        package var beep: () -> Void

        package init(beep: @escaping () -> Void) {
            self.beep = beep
        }

        package static let live = Backing(beep: { NSSound.beep() })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// The system alert sound.
    @discardableResult
    package func beep() -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.beep()
        return nil
    }
}
```

Create `Sources/Vitruvian/Services/Platform/Broker/OpenAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The `open` capability: hand a link to the person's default app for it.
@MainActor
package struct OpenAccess {
    package struct Backing {
        package var open: (URL) -> Bool

        package init(open: @escaping (URL) -> Bool) {
            self.open = open
        }

        package static let live = Backing(open: { NSWorkspace.shared.open($0) })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// Whether the system opened `url`.
    package func url(_ url: URL) -> Result<Bool, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(backing.open(url))
    }
}
```

Create `Sources/Vitruvian/Services/Platform/Broker/ClipboardAccess.swift`. The live backing is the Port manager row's copy, moved here word for word: on the clipboard lane, clear, mark the contents as the app's own, set the string.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The clipboard capabilities. Stage A offers writing text; reading and
/// rewriting arrive with the first tool that needs them.
@MainActor
package struct ClipboardAccess {
    package struct Backing {
        /// Replace the clipboard with `text`, then say on the main thread
        /// whether it took.
        package var write: (_ text: String, _ completion: @escaping @MainActor (Bool) -> Void) -> Void

        package init(write: @escaping (String, @escaping @MainActor (Bool) -> Void) -> Void) {
            self.write = write
        }

        package static let live = Backing(write: { text, completion in
            GeneralPasteboardAccess.shared.async({
                NSPasteboard.general.clearContents()
                NSPasteboard.general.declareVitruvianSource()
                return NSPasteboard.general.setString(text, forType: .string)
            }, then: { copied in
                completion(copied)
            })
        })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// Replaces the clipboard with `text`. `completion` hears whether it
    /// took; it is not called when the call is refused.
    @discardableResult
    package func write(_ text: String, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.write(text, completion)
        return nil
    }
}
```

Read `GeneralPasteboardAccess.async(_:then:)` before writing the live backing: match its closure types exactly (the work closure runs off the main thread and is `@Sendable`; `then` runs on the main thread). Keep the three pasteboard calls in the same order as `PortManagerRowActions.copy` has them today.

- [ ] **Step 4: Write the handle, and let the broker make one**

Create `Sources/Vitruvian/Services/Platform/ToolServices.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Everything a tool may touch. A tool is built with one and reaches for
/// nothing else. It carries the tool's manifest, so each operation is
/// checked against what this tool declared.
@MainActor
package struct ToolServices {
    package let manifest: ToolManifest
    let broker: CapabilityBroker

    package var notify: NotifyAccess {
        NotifyAccess(gate: gate(.notify), backing: broker.backings.notify)
    }

    package var open: OpenAccess {
        OpenAccess(gate: gate(.open), backing: broker.backings.open)
    }

    package var clipboard: ClipboardAccess {
        ClipboardAccess(gate: gate(.clipboardWrite), backing: broker.backings.clipboard)
    }

    func gate(_ capability: Capability) -> () -> BrokerRefusal? {
        { [broker, manifest] in broker.refusal(of: capability, for: manifest) }
    }
}
```

In `CapabilityBroker.swift`, add the backings and the factory. `ProcessesAccess` is Task 4's; add its field there.

```swift
    /// What each capability calls to do its work.
    package struct Backings {
        package var notify: NotifyAccess.Backing
        package var open: OpenAccess.Backing
        package var clipboard: ClipboardAccess.Backing

        package init(notify: NotifyAccess.Backing, open: OpenAccess.Backing, clipboard: ClipboardAccess.Backing) {
            self.notify = notify
            self.open = open
            self.clipboard = clipboard
        }
    }

    package let backings: Backings

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
    }

    /// The handle for one tool.
    package func services(for manifest: ToolManifest) -> ToolServices {
        ToolServices(manifest: manifest, broker: self)
    }
```

Replace the one-argument `init(environment:)` with this one, and give Task 2's test a `backings:` argument. Until Task 4 exists, drop `processes: .inert` from the test's `bench` and add it back in Task 4.

- [ ] **Step 5: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): let a tool beep, open a link and copy text through the broker"
```

(`git add` of the `Broker` directory is fine here: every file in it is this plan's. Check `git status --short` first.)

---

### Task 4: The `processes` capability

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/ProcessesAccess.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (`Backings.processes`), `Sources/Vitruvian/Services/Platform/ToolServices.swift`, `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Produces:
  - `ProcessScanner: Sendable`: `startTime: @Sendable (pid_t) -> UInt64?`, `listeningSocketsReport: @Sendable () -> (status: Int32, output: String)`
  - `ProcessesAccess`: `scanner() -> Result<ProcessScanner, BrokerRefusal>`, `canTerminate: Bool`, `isProtected(pid:name:) -> Bool`, `terminate(pid:name:startedAt:force:completion:) -> BrokerRefusal?`
  - `ProcessesAccess.Backing` with `.live` and `.inert`

The live backing is today's calls, unchanged:

| Operation | Today, in `PortManagerService` or its views |
|---|---|
| `startTime` | `KillProcessService.startTime(for:)` |
| `listeningSocketsReport` | `Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"])` |
| `terminationAvailable` | `AppFeature.killProcess.isAvailable` |
| `isProtected` | `KillProcessService.isProtected(pid:name:)` |
| `terminate` | `KillProcessService.shared.kill(pid:name:startedAt:force:completion:)` |

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, add `processes(suite)` to `run`, put `processes: .inert` back in `bench`, and add:

```swift
    static func processes(_ suite: TestSuite) {
        final class Kills {
            var available = true
            var ended: [(pid: pid_t, name: String, startedAt: UInt64, force: Bool)] = []
            var protected: Set<pid_t> = [1]
        }
        let kills = Kills()
        let world = World()
        func services(_ capabilities: [Capability]) -> ToolServices {
            CapabilityBroker(
                environment: .init(isInstalled: { _ in world.installed },
                                   isGranted: { world.granted.contains($0) },
                                   allows: { _, _ in world.allowed },
                                   reportUndeclared: { _, _ in }),
                backings: .init(
                    notify: .init(beep: {}), open: .init(open: { _ in true }),
                    clipboard: .init(write: { _, _ in }),
                    processes: .init(
                        startTime: { $0 == 42 ? 7 : nil },
                        listeningSocketsReport: { (0, "p42\n") },
                        terminationAvailable: { kills.available },
                        isProtected: { pid, _ in kills.protected.contains(pid) },
                        terminate: { pid, name, startedAt, force, completion in
                            kills.ended.append((pid, name, startedAt, force))
                            completion()
                        })))
                .services(for: manifest(capabilities))
        }
        let tool = services([.processes])

        guard case .success(let scanner) = tool.processes.scanner() else {
            suite.expect(false, "a tool that asks for it gets a scanner")
            return
        }
        suite.expect(scanner.startTime(42) == 7 && scanner.startTime(43) == nil
                         && scanner.listeningSocketsReport().output == "p42\n",
                     "the scanner reads start times and the listening sockets")
        if case .failure(let refusal) = services([]).processes.scanner() {
            suite.expect(refusal == .notDeclared(.processes), "a tool that did not ask gets no scanner")
        } else {
            suite.expect(false, "a tool that did not ask gets no scanner")
        }

        var finished = 0
        suite.expect(tool.processes.canTerminate
                         && tool.processes.terminate(pid: 42, name: "node", startedAt: 7, force: true) { finished += 1 } == nil
                         && kills.ended.count == 1 && kills.ended[0].pid == 42 && kills.ended[0].name == "node"
                         && kills.ended[0].startedAt == 7 && kills.ended[0].force && finished == 1,
                     "ending a process passes its identity through and reports back")
        suite.expect(tool.processes.isProtected(pid: 1, name: "launchd") && !tool.processes.isProtected(pid: 42, name: "node"),
                     "the host says which processes may not be ended")

        kills.available = false
        suite.expect(!tool.processes.canTerminate
                         && tool.processes.terminate(pid: 42, name: "node", startedAt: 7, force: false) { finished += 1 } == .unavailable
                         && kills.ended.count == 1 && finished == 1,
                     "without the Kill process feature, ending a process is not offered and does nothing")
        kills.available = true
        let none = services([])
        suite.expect(!none.processes.canTerminate && none.processes.isProtected(pid: 42, name: "node")
                         && none.processes.terminate(pid: 42, name: "node", startedAt: 7, force: false) {} == .notDeclared(.processes)
                         && kills.ended.count == 1,
                     "a tool that did not ask can end nothing, and is told every process is protected")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `processes`.

- [ ] **Step 3: Write the capability**

Create `Sources/Vitruvian/Services/Platform/Broker/ProcessesAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore

/// What a tool scans processes with, off the main thread. It is handed out
/// after the broker's checks pass, and holds no way to change what it runs.
package struct ProcessScanner: Sendable {
    /// When a process started, as the kernel records it. With the PID it
    /// identifies one process even after the PID is used again.
    package let startTime: @Sendable (pid_t) -> UInt64?
    /// `lsof`'s field report of every listening TCP socket. A negative
    /// status means it ran out of time.
    package let listeningSocketsReport: @Sendable () -> (status: Int32, output: String)
}

/// The `processes` capability: see what is listening, and end a process.
@MainActor
package struct ProcessesAccess {
    package struct Backing {
        package var startTime: @Sendable (pid_t) -> UInt64?
        package var listeningSocketsReport: @Sendable () -> (status: Int32, output: String)
        /// Whether ending a process is offered at all. It is the Kill
        /// process feature's work, so it follows that feature.
        package var terminationAvailable: () -> Bool
        package var isProtected: (_ pid: pid_t, _ name: String) -> Bool
        package var terminate: (_ pid: pid_t, _ name: String, _ startedAt: UInt64, _ force: Bool,
                                _ completion: @escaping @MainActor @Sendable () -> Void) -> Void

        package init(startTime: @escaping @Sendable (pid_t) -> UInt64?,
                     listeningSocketsReport: @escaping @Sendable () -> (status: Int32, output: String),
                     terminationAvailable: @escaping () -> Bool,
                     isProtected: @escaping (pid_t, String) -> Bool,
                     terminate: @escaping (pid_t, String, UInt64, Bool, @escaping @MainActor @Sendable () -> Void) -> Void) {
            self.startTime = startTime
            self.listeningSocketsReport = listeningSocketsReport
            self.terminationAvailable = terminationAvailable
            self.isProtected = isProtected
            self.terminate = terminate
        }

        package static let live = Backing(
            startTime: { KillProcessService.startTime(for: $0) },
            listeningSocketsReport: {
                Shell.run("/usr/sbin/lsof", ["-nP", "+c0", "-iTCP", "-sTCP:LISTEN", "-F", "pcnPT"])
            },
            terminationAvailable: { AppFeature.killProcess.isAvailable },
            isProtected: { KillProcessService.isProtected(pid: $0, name: $1) },
            terminate: { pid, name, startedAt, force, completion in
                KillProcessService.shared.kill(pid: pid, name: name, startedAt: startedAt, force: force,
                                               completion: completion)
            })

        /// Sees nothing and ends nothing. For tests of other capabilities.
        package static let inert = Backing(startTime: { _ in nil }, listeningSocketsReport: { (0, "") },
                                           terminationAvailable: { false }, isProtected: { _, _ in true },
                                           terminate: { _, _, _, _, _ in })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// A scanner, once the checks pass. Ask each time a scan starts.
    package func scanner() -> Result<ProcessScanner, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(ProcessScanner(startTime: backing.startTime,
                                       listeningSocketsReport: backing.listeningSocketsReport))
    }

    /// Whether ending a process is offered to this tool right now.
    package var canTerminate: Bool {
        gate() == nil && backing.terminationAvailable()
    }

    /// Whether the host refuses to end this process. A tool that may not
    /// ask is told yes: the safe answer.
    package func isProtected(pid: pid_t, name: String) -> Bool {
        guard gate() == nil else { return true }
        return backing.isProtected(pid, name)
    }

    /// Ends the process that has this PID and started at `startedAt`.
    /// `completion` is not called when the call is refused.
    @discardableResult
    package func terminate(pid: pid_t, name: String, startedAt: UInt64, force: Bool,
                           completion: @escaping @MainActor @Sendable () -> Void) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        guard backing.terminationAvailable() else { return .unavailable }
        backing.terminate(pid, name, startedAt, force, completion)
        return nil
    }
}
```

In `CapabilityBroker.Backings`, add `package var processes: ProcessesAccess.Backing`, with its `init` parameter last. In `ToolServices`, add:

```swift
    package var processes: ProcessesAccess {
        ProcessesAccess(gate: gate(.processes), backing: broker.backings.processes)
    }
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): scan listening ports and end a process through the broker"
```

---

### Task 5: The bundled tool interface and the host

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/BundledTool.swift`
- Create: `Sources/Vitruvian/Services/Platform/ToolHost.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (`shared`, `Environment.live`, `Backings.live`)
- Modify: `Sources/Vitruvian/App/AppDelegate.swift` (`applicationWillTerminate`), `Tests/ToolBrokerTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Produces:
  - `protocol BundledTool: AnyObject` (`@MainActor`): `static var manifest: ToolManifest { get }`, `init(services: ToolServices)`, `func stop()`
  - `ToolHost` (`@MainActor`): `shared`, `init(broker:)`, `tool(_:) -> T`, `built: [ToolID]`, `stopAll()`
  - `CapabilityBroker.shared`

`start`, `run` and `canRun` from the spec's section 6 are not in the protocol yet. No stage A tool has background work or a command, and a requirement nothing calls is a requirement nothing tests. Stage B adds them with their first caller.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, add `host(suite)` to `run`, and add:

```swift
    final class ProbeTool: BundledTool {
        static let manifest = ToolBrokerTests.manifest([.notify])
        static var built = 0
        let services: ToolServices
        var stops = 0
        init(services: ToolServices) {
            self.services = services
            Self.built += 1
        }
        func stop() { stops += 1 }
    }

    static func host(_ suite: TestSuite) {
        let recorder = Recorder()
        ProbeTool.built = 0
        let host = ToolHost(broker: bench([], recorder: recorder).broker)
        suite.expect(host.built.isEmpty && ProbeTool.built == 0, "a tool nobody asked for is never built")

        let first = host.tool(ProbeTool.self)
        let second = host.tool(ProbeTool.self)
        suite.expect(first === second && ProbeTool.built == 1 && host.built == [ProbeTool.manifest.id],
                     "everyone who asks for a tool gets the same one")
        suite.expect(first.services.notify.beep() == nil && recorder.beeps == 1,
                     "a tool is handed services checked against its own manifest")
        suite.expect(first.services.open.url(URL(string: "http://localhost")!) == .failure(.notDeclared(.open)),
                     "and against nothing more")

        host.stopAll()
        host.stopAll()
        suite.expect(first.stops == 2 && ProbeTool.built == 1, "quitting stops every built tool, and builds none")
    }
```

`bench` returns `ToolServices`; give `ToolServices` a `package let broker` (it is `let broker` in Task 3) so the test can reach the broker it was built with, or change `bench` to return the broker and build the services at each call site. Use whichever needs fewer changes.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `BundledTool`.

- [ ] **Step 3: Write the interface and the host**

Create `Sources/Vitruvian/Services/Platform/BundledTool.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A tool compiled into the app. It says what it is in `manifest`, is built
/// with the services that manifest allows, and reaches nothing else: no
/// singleton, no system service.
@MainActor
package protocol BundledTool: AnyObject {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
    /// Undo whatever the tool has running. Safe to call twice.
    func stop()
}
```

Create `Sources/Vitruvian/Services/Platform/ToolHost.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Owns the live tools. It builds a tool the first time somebody asks for
/// it, hands the same one to everybody after, and stops them all at quit.
/// A view gets its tool here.
@MainActor
package final class ToolHost {
    package static let shared = ToolHost(broker: .shared)

    private let broker: CapabilityBroker
    private var tools: [ToolID: any BundledTool] = [:]
    /// The tools that have been built, in the order they were.
    package private(set) var built: [ToolID] = []

    package init(broker: CapabilityBroker) {
        self.broker = broker
    }

    /// The one instance of `type`, built on first use.
    package func tool<T: BundledTool>(_ type: T.Type) -> T {
        let id = type.manifest.id
        if let existing = tools[id] as? T { return existing }
        let tool = T(services: broker.services(for: type.manifest))
        tools[id] = tool
        built.append(id)
        return tool
    }

    /// Stops every built tool, last built first. Builds none.
    package func stopAll() {
        for id in built.reversed() { tools[id]?.stop() }
    }
}
```

- [ ] **Step 4: Give the broker its live form**

In `CapabilityBroker.swift`:

```swift
    package static let shared = CapabilityBroker(environment: .live, backings: .live)
```

```swift
        /// The app as it is: a tool with the id of a hub feature follows
        /// that feature; the two macOS grants the app watches are read
        /// from `Permissions`; a compiled-in tool is always allowed.
        package static let live = Environment(
            isInstalled: { id in AppFeature(rawValue: id.rawValue)?.isAvailable ?? true },
            isGranted: { permission in
                switch permission {
                case .accessibility: return Permissions.shared.accessibility
                case .screenRecording: return Permissions.shared.screenRecording
                default: return true
                }
            },
            allows: { _, _ in true },
            reportUndeclared: { id, capability in
                assertionFailure("\(id) used \(capability.rawValue) without declaring it")
            })
```

```swift
        package static let live = Backings(notify: .live, open: .live, clipboard: .live, processes: .live)
```

Read `Permissions` before writing `isGranted`: use the names of its two published grants as they are. No stage A capability rides on a grant, so this closure is not reached yet; it must still be right.

- [ ] **Step 5: Stop tools at quit**

In `App/AppDelegate.swift`, in `applicationWillTerminate`, before the hand-kept list of `stop()` calls, add:

```swift
        // Tools the host built stop here. A feature that has become a tool
        // has no line of its own below.
        ToolHost.shared.stopAll()
```

- [ ] **Step 6: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 7: Commit**

Append to the stage A entry in `UPSTREAM.md`:

```markdown
  - `App/AppDelegate.swift`: stops the tools the host built, at quit.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform apps/desktop/vitruvian/Sources/Vitruvian/App/AppDelegate.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): host tools compiled into the app"
```

---

### Task 6: The Port manager becomes a tool

**Files:**
- Modify: `Sources/Vitruvian/Services/PortManager/PortManagerService.swift`
- Modify: `Sources/Vitruvian/UI/PortManager/PortManagerView.swift` (the service property; lines near 129 to 139; `PortManagerRowActions`)
- Modify: `Sources/Vitruvian/UI/MenuPanel/PanelPortManagerView.swift` (the service property; lines near 190 to 200)
- Modify: `Tests/ToolBrokerTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `BundledTool`, `ToolServices`, `ToolHost.shared.tool(_:)`.
- Produces, on `PortManagerService`: `static let manifest`, `init(services:)`, `stop()`, `canTerminate`, `isProtected(_:)`, `copy(_:)`, `open(_:)`. `terminate(_:force:)`, `refresh()` and the published state keep their names. `static let shared` and `Scanning.system` are gone.

The class keeps its name and its file. Renaming it to "tool" would show as a deleted and an added file to the upstream porting tool, for no gain.

What the eight lines being replaced do today, which is the contract the new tests pin. There is no seam to test the old lines directly: they call a singleton that ends real processes.

| Today | Must still hold |
|---|---|
| `terminate` returns unless `AppFeature.killProcess.isAvailable` | nothing is ended when the host does not offer it |
| `terminate` returns unless `entry.startedAt` is set | an entry with no stable identity is never ended |
| otherwise `KillProcessService.shared.kill(pid:name:startedAt:force:)`, then `refresh()` | identity and `force` pass through; the list refreshes after |
| views show the end buttons only if the Kill process feature is installed | same, through `canTerminate` |
| views disable a button when `startedAt == nil` or the process is protected | same, through `isProtected(_:)` |
| a row copies port, PID or address; beeps if the copy failed | same |
| a row opens the port in the browser; beeps if it would not open | same |

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, add `portManager(suite)` to `run`, and add the test below. It builds the tool through a host over fake backings.

```swift
    static func portManager(_ suite: TestSuite) {
        final class Kills {
            var available = true
            var ended: [(pid: pid_t, startedAt: UInt64, force: Bool)] = []
            var finish: [@MainActor @Sendable () -> Void] = []
        }
        let kills = Kills()
        let recorder = Recorder()
        let reports = PortManagerRefreshTests.Processes()
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in true }, isGranted: { _ in true }, allows: { _, _ in true },
                               reportUndeclared: { _, capability in
                                   suite.expect(false, "the Port manager used \(capability.rawValue) without declaring it")
                               }),
            backings: .init(
                notify: .init(beep: { recorder.beeps += 1 }),
                open: .init(open: { recorder.opened.append($0); return recorder.opens }),
                clipboard: .init(write: { text, completion in
                    recorder.written.append(text)
                    completion(recorder.writes)
                }),
                processes: .init(
                    startTime: { reports.current[$0] },
                    listeningSocketsReport: { reports.listing() },
                    terminationAvailable: { kills.available },
                    isProtected: { pid, _ in pid == 1 },
                    terminate: { pid, _, startedAt, force, completion in
                        kills.ended.append((pid, startedAt, force))
                        kills.finish.append(completion)
                    })))
        let tool = ToolHost(broker: broker).tool(PortManagerService.self)
        let stable = PortManagerEntry(port: 3000, protocolName: "TCP", address: "*", pid: 42,
                                      processName: "node", startedAt: 7)
        let unstable = PortManagerEntry(port: 3001, protocolName: "TCP", address: "*", pid: 43,
                                        processName: "node", startedAt: nil)

        suite.expect(Set(PortManagerService.manifest.capabilities.map(\.capability))
                         == [.processes, .clipboardWrite, .open, .notify],
                     "the Port manager asks for exactly what it uses")

        tool.terminate(unstable, force: false)
        suite.expect(kills.ended.isEmpty, "an entry with no stable identity is never ended")
        tool.terminate(stable, force: true)
        suite.expect(kills.ended.count == 1 && kills.ended[0].pid == 42 && kills.ended[0].startedAt == 7
                         && kills.ended[0].force,
                     "ending a process passes its identity and force through")
        let scans = reports.calls
        kills.finish.forEach { $0() }
        suite.expect(tool.isRefreshing || reports.calls > scans, "the list refreshes after a process is ended")

        suite.expect(tool.canTerminate && tool.isProtected(PortManagerEntry(
                         port: 1, protocolName: "TCP", address: "*", pid: 1, processName: "launchd", startedAt: 1))
                         && !tool.isProtected(stable),
                     "the views ask the tool what may be ended")
        kills.available = false
        tool.terminate(stable, force: false)
        suite.expect(!tool.canTerminate && kills.ended.count == 1,
                     "without the Kill process feature nothing is offered and nothing is ended")

        tool.copy("3000")
        suite.expect(recorder.written == ["3000"] && recorder.beeps == 0, "a row copies its value")
        recorder.writes = false
        tool.copy("3001")
        suite.expect(recorder.beeps == 1, "a copy that did not take beeps")
        let link = URL(string: "http://localhost:3000")!
        tool.open(link)
        suite.expect(recorder.opened == [link] && recorder.beeps == 1, "a row opens its port in the browser")
        recorder.opens = false
        tool.open(link)
        suite.expect(recorder.beeps == 2, "a link that would not open beeps")
    }
```

`PortManagerRefreshTests.Processes` is the existing fake process table; reuse it, do not copy it. The "refreshes after" check reads whatever the tool exposes: if `refresh()` runs its scan on a real background queue here, assert `tool.isRefreshing` alone and say so in the report. `PortManagerEntry`'s initializer is in `Services/PortManager/PortManagerSupport.swift`; match its labels.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `manifest` or `BundledTool`.

- [ ] **Step 3: Turn the service into the tool**

In `Services/PortManager/PortManagerService.swift`:

1. Delete `package static let system = Scanning(...)`. Add, inside `Scanning`:

```swift
        /// A scan that reads through the broker's scanner. The list of PIDs
        /// is a plain libc read that needs no trust; the start times and
        /// the listing are the host's.
        package init(scanner: ProcessScanner) {
            self.init(listPIDs: { proc_listallpids($0, $1) },
                      startTime: scanner.startTime,
                      listing: scanner.listeningSocketsReport,
                      background: { DispatchQueue.global(qos: .userInitiated).async(execute: $0) },
                      main: { work in DispatchQueue.main.async { work() } })
        }
```

2. Delete `package static let shared = PortManagerService()`.

3. Replace the stored `scanning` and the initializer:

```swift
    private let services: ToolServices?
    /// The scan to run, asked for each time one starts: the broker checks
    /// then. Nil when the scan is refused.
    private let scanning: () -> Scanning?

    /// For tests of the scan itself, which hand in the process data.
    package init(scanning: Scanning) {
        self.services = nil
        self.scanning = { scanning }
    }

    package init(services: ToolServices) {
        self.services = services
        self.scanning = {
            guard case .success(let scanner) = services.processes.scanner() else { return nil }
            return Scanning(scanner: scanner)
        }
    }
```

4. In `refresh()`, replace `let scanning = scanning` with:

```swift
        guard let scanning = scanning() else {
            refreshFailed = true
            isRefreshing = false
            return
        }
```

keeping it after `isRefreshing = true` and `refreshFailed = false`, so a refused scan ends in the same state a timed-out one does.

5. Replace `terminate` and add the rest:

```swift
    package func terminate(_ entry: PortManagerEntry, force: Bool) {
        guard let services, let startedAt = entry.startedAt else { return }
        services.processes.terminate(pid: entry.pid, name: entry.processName, startedAt: startedAt,
                                     force: force) { [weak self] in
            self?.refresh()
        }
    }

    /// Whether ending a process is offered at all.
    package var canTerminate: Bool { services?.processes.canTerminate ?? false }

    /// Whether the host refuses to end this entry's process.
    package func isProtected(_ entry: PortManagerEntry) -> Bool {
        services?.processes.isProtected(pid: entry.pid, name: entry.processName) ?? true
    }

    /// Puts `value` on the clipboard, and beeps if it did not take.
    package func copy(_ value: String) {
        guard let services else { return }
        services.clipboard.write(value) { copied in
            if !copied { services.notify.beep() }
        }
    }

    /// Opens `url` in the browser, and beeps if it would not open.
    package func open(_ url: URL) {
        guard let services else { return }
        if (try? services.open.url(url).get()) != true { services.notify.beep() }
    }

    package func stop() {}
```

6. Add the manifest and the conformance, at the end of the file:

```swift
extension PortManagerService: BundledTool {
    package static let manifest: ToolManifest = {
        let feature = AppFeature.portManager
        guard let id = ToolID(feature.rawValue),
              let tool = ToolDescriptor(id: id, name: feature.rawValue, symbol: feature.symbolName, commands: []),
              let scan = CapabilityRequest(.processes, reason: "Lists what is listening on each port, and ends a process you pick."),
              let copy = CapabilityRequest(.clipboardWrite, reason: "Copies a port, PID or address you pick."),
              let open = CapabilityRequest(.open, reason: "Opens a local port in your browser."),
              let beep = CapabilityRequest(.notify, reason: "Beeps when a copy or an open did not work."),
              let manifest = ToolManifest(
                  tool: tool, group: feature.group, capabilities: [scan, copy, open, beep],
                  preferences: [PreferenceDeclaration(key: DefaultsKey.panelUtilityPortManager, default: .bool(true))],
                  activation: [.onShown], enabledBy: nil)
        else { preconditionFailure("the Port manager's manifest is not valid") }
        return manifest
    }()
}
```

If `init(services:)` must be marked `required` or the tests' `PortManagerService(scanning:)` calls no longer resolve, fix the declaration, not the tests.

- [ ] **Step 4: Point the views at the tool**

In both `UI/PortManager/PortManagerView.swift` and `UI/MenuPanel/PanelPortManagerView.swift`:

```swift
    @ObservedObject private var service = PortManagerService.shared
```
becomes
```swift
    @ObservedObject private var service = ToolHost.shared.tool(PortManagerService.self)
```

`AppFeature.killProcess.isAvailable` becomes `service.canTerminate`. Each
`KillProcessService.isProtected(pid: entry.pid, name: entry.processName)` becomes `service.isProtected(entry)`.

In `PortManagerRowActions` (in `PortManagerView.swift`), replace the `NSWorkspace` line and the `copy` function:

```swift
            Button(FeatureStrings.commandBar(language).openInBrowser) {
                ToolHost.shared.tool(PortManagerService.self).open(url)
            }
```

```swift
    private func copy(_ value: String) {
        ToolHost.shared.tool(PortManagerService.self).copy(value)
    }
```

`PortManagerRowActions` keeps its two properties, so its two call sites do not change. Remove imports the views no longer need only if the build says they are unused.

- [ ] **Step 5: Add the agreement test**

In `Tests/ToolBrokerTests.swift`, add `manifestsAgree(suite)` to `run`:

```swift
    /// A manifest and the `AppFeature` it stands beside describe one thing.
    static func manifestsAgree(_ suite: TestSuite) {
        let manifests = [PortManagerService.manifest]
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)
        var keys: [String] = []
        for manifest in manifests {
            guard let feature = AppFeature(rawValue: manifest.id.rawValue) else {
                suite.expect(false, "\(manifest.id) names a feature")
                continue
            }
            suite.expect(manifest.group == feature.group && manifest.tool.symbol == feature.symbolName,
                         "\(manifest.id) is filed and drawn as its feature is")
            suite.expect(Set(manifest.capabilities.flatMap(\.capability.ridesOn)) == Set(feature.permissions),
                         "\(manifest.id) needs the macOS grants its feature declares, and no others")
            suite.expect(registry.tool(manifest.id) == manifest.tool,
                         "\(manifest.id) is the tool the registry already holds")
            suite.expect(manifest.preferences.allSatisfy { declared in
                (Defaults.registeredDefaults[declared.key] as? NSObject)
                    == (declared.defaultValue.defaultsValue as? NSObject)
            }, "\(manifest.id) declares each preference with the default the app registers")
            keys += manifest.preferences.map(\.key)
        }
        suite.expect(Set(keys).count == keys.count, "no preference belongs to two tools")
    }
```

- [ ] **Step 6: Run everything**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=utilities`
Expected: PASS. Find the suite that runs `PortManagerRefreshTests` in `Tests/TestGroups.swift` and add it to the command if it is neither of these.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `grep -rn "PortManagerService.shared\|Scanning.system" apps/desktop/vitruvian/Sources apps/desktop/vitruvian/Tests`
Expected: no output.

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest`
Expected: PASS, every suite reporting.

- [ ] **Step 7: Commit**

Append to the stage A entry in `UPSTREAM.md`:

```markdown
  - `Services/PortManager/PortManagerService.swift`: the Port manager is a tool. It has a manifest, is built by the tool host with the services that manifest allows, and scans, ends a process, copies, opens a link and beeps only through the broker. Its singleton and `Scanning.system` are gone.
  - `UI/PortManager/PortManagerView.swift`, `UI/MenuPanel/PanelPortManagerView.swift`: get the tool from the host, and ask it what may be ended, to copy and to open, where they called `KillProcessService`, the pasteboard and `NSWorkspace`.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/PortManager/PortManagerService.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/PortManager/PortManagerView.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/MenuPanel/PanelPortManagerView.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): the Port manager reaches the system only through the broker"
```

---

### Task 7: Make "only through the broker" a lint

**Files:**
- Modify: `bazel/source_lints.py`
- Modify: `Tests/mutation_checks.py`, `UPSTREAM.md`

**Interfaces:**
- Produces: two rules in `RULES`, `migrated_tools_reach_services_through_the_broker` and `the_broker_names_no_tool`, and one table, `MIGRATED_TOOLS`.

Read three existing rules in `bazel/source_lints.py` first (`hotkey_ids_are_unique` is a good one): how a rule reads files, how it skips comments and string literals, how it reports a problem, and how it tests itself on a sample at the top. Write these two the same way.

- [ ] **Step 1: Write the table and the first rule**

```python
# A feature that has become a tool. In its files no code reaches a service:
# everything goes through the `ToolServices` the tool was built with. A row
# is added in the pull request that migrates the feature.
MIGRATED_TOOLS = {
    "portManager": {
        "files": [
            "Sources/Vitruvian/Services/PortManager/PortManagerService.swift",
            "Sources/Vitruvian/Services/PortManager/PortManagerSupport.swift",
            "Sources/Vitruvian/UI/PortManager/PortManagerView.swift",
            "Sources/Vitruvian/UI/MenuPanel/PanelPortManagerView.swift",
        ],
        # Type names the broker's files must never mention.
        "types": ["PortManagerService", "PortManagerEntry", "PortManagerSupport"],
        # Preference keys a view of this tool may bind with @AppStorage.
        "keys": ["panelUtilityPortManager"],
    },
}

# What a migrated tool's files may not name, and what to say.
BROKERED = [
    (r"\bNSPasteboard\b", "the clipboard"),
    (r"\bGeneralPasteboardAccess\b", "the clipboard lane"),
    (r"\bCGEvent(Source)?\b", "synthesised input"),
    (r"\bAXIsProcessTrusted\b|\bAXUIElement", "Accessibility"),
    (r"\bQuickToolHotkey\s*\(|\bRegisterEventHotKey\b", "a global hotkey"),
    (r"\bProcess\s*\(\s*\)|\bShell\.|\bAdminShell\.", "a subprocess"),
    (r"\bNSWorkspace\b", "the workspace"),
    (r"\bUserDefaults\b", "saved preferences"),
    (r"\bNotifier\.|\bQuickToolHUD\.|\bNSSound\b", "an alert"),
    (r"\bTransientPaste\b", "the paste helper"),
    (r"\bAppFeature\.\w+\.isAvailable\b", "whether another feature is installed"),
]

# The singletons a migrated tool's files may name: the host that hands out
# tools, and the UI's own state. Grows only by review.
TOOL_FILE_SINGLETONS = {"ToolHost", "L10n", "SettingsRouter", "PanelInteractionState"}
```

The rule, for each file of each tool, on code with comments and string literals removed:

- fails on any `BROKERED` pattern, saying `<file>:<line> reaches <what> directly; a migrated tool goes through its ToolServices`;
- fails on `<Name>.shared` where `<Name>` is not in `TOOL_FILE_SINGLETONS`, saying `<file>:<line> names the singleton <Name>`;
- fails on `@AppStorage(` whose key is not one of the tool's `keys` (match both a quoted key and `DefaultsKey.<key>`).

It also fails if a listed file does not exist, so a moved file cannot slip out of the rule.

Its self-test, at the top of the rule, runs the same checks on a sample and compares the problems with an exact list. The sample must contain at least: one clean line; `NSPasteboard.general.clearContents()`; `KillProcessService.shared.kill(`; `L10n.shared`; a comment that mentions `NSWorkspace`; `@AppStorage(DefaultsKey.panelUtilityPortManager)`; `@AppStorage("somethingElse")`; `AppFeature.killProcess.isAvailable`.

`proc_listallpids` and `DispatchQueue` are not in the table on purpose (decision 3).

- [ ] **Step 2: Write the second rule**

`the_broker_names_no_tool`: for every `.swift` file under `Sources/Vitruvian/Services/Platform/Broker/`, on code with comments removed, fail on any name in any tool's `types`, saying `<file>:<line> names the tool type <Name>; the broker serves tools and knows none`. Self-test on a sample with one clean line, one line naming `PortManagerService`, and one comment naming it.

Add both to `RULES`.

- [ ] **Step 3: Prove the rules see the app**

Run: `bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

Then, one at a time, make each change, run the test and confirm it FAILS naming the line. Undo each by reversing the edit by hand (not with `git checkout` or `git stash`), and confirm `git diff --stat -- <file>` prints nothing:

1. In `PortManagerView.swift`, add `_ = NSWorkspace.shared` inside `PortManagerRowActions.copy`.
2. In `PortManagerService.swift`, add `_ = KillProcessService.shared` inside `stop()`.
3. In `Services/Platform/Broker/NotifyAccess.swift`, add `_ = PortManagerService.manifest` inside `beep()`.

Put the three failing outputs in the report.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/bazel/source_lints.py`

- [ ] **Step 4: Plant two regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of `MUTATIONS` (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("the broker does work for a tool that did not ask", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift",
     "        guard tool.declares(capability) else {\n            environment.reportUndeclared(tool.id, capability)\n            return .notDeclared(capability)\n        }\n",
     "",
     "a capability the manifest does not list is refused, and reported as a mistake"),
    ("the Port manager ends a process the host does not offer to end", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/ProcessesAccess.swift",
     "        guard backing.terminationAvailable() else { return .unavailable }\n",
     "",
     "without the Kill process feature, ending a process is not offered and does nothing"),
```

Each "before" text must occur exactly once in its file, and must quote the file exactly: if the code differs from this plan, use the code. For each entry: apply it, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`, confirm it fails with the sixth field among the messages, undo it, confirm `git diff --stat -- <file>` prints nothing. If a mutation is not detected, stop and report: do not adjust a test to fit.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/Tests/mutation_checks.py`

- [ ] **Step 5: Commit**

Append to the stage A entry in `UPSTREAM.md`:

```markdown
  - `Tests/mutation_checks.py`: two mutations (the broker working for a tool that did not ask; ending a process the host does not offer to end).
```

```bash
git add apps/desktop/vitruvian/bazel/source_lints.py apps/desktop/vitruvian/Tests/mutation_checks.py apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): fail the lint when a migrated tool reaches past the broker"
```

---

### Task 8: Document, and check by hand

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md`

- [ ] **Step 1: Write the rules down**

In `AGENTS.md`, directly after the bullets about the tool registry and shortcuts, add:

```markdown
- A feature that has become a tool has a manifest (`ToolManifest`), conforms
  to `BundledTool`, and is built by `ToolHost` with a `ToolServices`. It has
  no `static let shared`. Everything outside its own logic, it reaches
  through `services`: the clipboard, a subprocess, a link, a beep. A view
  gets its tool with `ToolHost.shared.tool(X.self)` and calls the tool, never
  a service. `bazel/source_lints.py` holds the list of migrated tools and
  their files (`MIGRATED_TOOLS`) and fails on a direct call.
- The broker (`Services/Platform/Broker/`) names no tool. An operation is
  named for what it does to the system, never for the tool that wanted it,
  and takes and returns plain values. A capability is added with the first
  tool that needs it.
- Every broker operation calls its gate first and does nothing when refused.
  A test for a new operation asserts that a refused call did no work.
```

- [ ] **Step 2: Bring the spec in line with what was built**

In the spec:

- Section 7.1: "one of those three reasons" becomes four, and add the fourth: **unavailable**, when the host cannot offer the operation right now.
- Section 7.2, the `processes` row: operations are `scanner()` (start times and the listening-sockets report), `canTerminate`, `isProtected(pid, name)`, `terminate(pid, name, startedAt, force)`. Add one sentence under the table: the report is `lsof`'s text because the parser and the stability rule are the tool's logic and stay in its file.
- Section 7.2, the `notify` row: stage A builds `beep()` only.
- Section 7.2, the `storage` row: first needed by the URL cleaner.
- Section 6: say that `start`, `run`, `canRun` and the run rule arrive in stage B, with the first tool that needs them.
- Section 11: stage A's capabilities are `notify`, `open`, `processes`, `clipboard.write`. Stage B gains `storage`, the host's start and stop, and the `FeatureRuntime` action. Mark stage A done, with the pull request number once it exists.

- [ ] **Step 3: Run everything**

With the display awake and the screen unlocked, from the repository root:

```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
```

Expected: all pass, every unit suite reports, the build succeeds.

- [ ] **Step 4: Check by hand**

No unit test ends a real process, writes the real clipboard or opens a real link. Build, unzip and open the app:

```sh
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

Start something that listens: `python3 -m http.server 8765` in a terminal.

1. Settings › Port manager: the list fills and shows port 8765. The menu panel's Port manager shows the same list.
2. On that row's menu: Copy port puts `8765` on the clipboard. Copy PID and Copy address work.
3. Open in browser opens `http://localhost:8765`.
4. End the process from the Settings page. The row goes and the terminal's server has stopped.
5. Start it again and end it from the menu panel. Same.
6. End a process owned by another user or root that is listening (for example a system service you can restart): the admin prompt appears, as before. If there is none to hand, say so.
7. In the Features hub remove Kill process. The Port manager's end buttons are gone, as they were before this change. Put Kill process back.
8. A protected process (`launchd`, or the app itself): its end button is disabled.

Record the Mac model, the macOS version and the result of each of the eight in the pull request. Say plainly which, if any, were not done.

- [ ] **Step 5: Commit and open the pull request**

```bash
git add apps/desktop/vitruvian/AGENTS.md docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md
git commit -m "refactor(desktop): document the broker, and the Port manager as its first tool"
```

Open one pull request. Its description states what was run, on which Mac and macOS version, the eight hand checks and their results, and what remains untested. Its title is a `refactor`: merging it cuts no release.

---

## What stage A leaves for stage B

- `start`, `run` and `canRun` on `BundledTool`; the host's run rule; the `FeatureRuntime` action for tools; re-deciding on a permission or preference change.
- The `storage` capability, and reading and rewriting the clipboard.
- A tool's commands registered through the host, with saved command-bar keys kept.
- The first macOS grant a capability rides on. Until then `Environment.live.isGranted` is written and not reached.
