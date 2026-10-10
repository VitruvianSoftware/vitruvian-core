# Vitruvian Broker (stage C: Paste as plain text, with a shortcut and keystrokes behind the broker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Paste as plain text onto the broker, so that no file belonging to it touches a global hotkey, Accessibility, the clipboard, a synthesised keystroke or a beep except through the broker. This is the last of the three migrations, so the last task also closes sub-project 2.

**Architecture:** The broker gains two capabilities. `hotkey` takes and gives back the key of a `GlobalShortcutRole`, with the combination and the hotkey id the role always had. `keystrokes` pastes text through `TransientPaste`, which is not edited, and presses a command in the front app's menus by its key equivalent. `keystrokes` is the first capability that rides on a macOS grant, Accessibility, so three things become real: the broker's "not granted" refusal, the grant clause of the host's run rule, and a way for a tool to say it starts without its grant. Paste as plain text says so: its shortcut is taken at once, and the first press asks. The service class becomes the tool: it keeps its file and its order of work, loses its singleton, its hotkey, its Accessibility calls and its menu walk.

**Tech Stack:** Swift 6 (AppKit, SwiftUI, Carbon hotkeys), Bazel with `--config=macos-app`, the app's own `TestSuite` harness, `bazel/source_lints.py`.

**Spec:** `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md` (approved 2026-10-09). This is stage C of its section 11. It follows `docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-b.md`.

All paths are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## Decisions this plan makes

The spec's nine decisions stand. These are the ones the code forced while planning. Eight change, narrow or add to the spec (1 to 8); Task 8 edits the spec to match.

| # | Decision | Why |
|---|---|---|
| 1 | **A tool says "I start without this grant" on the capability that rides on it**: `CapabilityRequest(.keystrokes, reason:, startsWithoutGrant: true)`. The host starts a tool when it holds `ToolManifest.grantsNeededToStart`: the grants its capabilities ride on, less those. The broker's own check is untouched: every `keystrokes` call is still refused with `notGranted` until the grant is there. **Adds to the spec**, which says only that a tool "declared it can start without". | Today the shortcut is registered with no look at Accessibility, and a press without it asks or beeps. A flag on the whole manifest would also wave through a second grant the tool does need. A request that rides on nothing may not set the flag: the initializer returns nil. |
| 2 | **The app's broker asks macOS about a grant at the moment of each call**, not `Permissions`. **Changes the spec's stage C row** ("`Permissions` in place before the host's first decision at launch"). | Putting `Permissions` in place first does not close the gap. Its init publishes the grants one main-queue hop later, and the host's first decision (`FeatureRuntime.syncAtLaunch`, `AppDelegate.swift:202`) runs in the same turn of the main thread as everything else in `applicationDidFinishLaunching`. The published value is false there whoever touched `Permissions` first. Worse, it lags while the app runs: it is refreshed by a poll every 2.5 seconds while a needed grant is missing and every 60 once it is held. Today a press asks `AXIsProcessTrusted()` at that instant. A broker that read the published value would beep for up to 2.5 seconds after a grant, and try to paste for up to 60 after a revocation. |
| 3 | **`keystrokes` gains two operations the spec does not list**: `refusal`, which asks "may I?" and does nothing, and `requestGrant()`, the system prompt and the app's guide. **Adds to the spec.** | Today the Accessibility check comes before the clipboard is read: without the grant an empty clipboard still asks or beeps, and nothing is read. A tool that learned of the refusal only from `paste` would have read first. The once-per-launch memory stays in the tool; the prompt is the host's. |
| 4 | **`pressFrontAppMenuItem(matching:)` takes key equivalents only**, as plain values (`MenuKeyEquivalent`: a character and the Accessibility modifier mask). No titles, no rule. **Narrows the spec**, which says "titles and key equivalents". | Today's code finds the item by key equivalent and never by title, on purpose: titles change with the language. A character and a mask say all of "which items count", so no function has to cross the broker. "Is it enabled" is the walk's: it will not press what cannot be pressed. A title has no user and would have no test. |
| 5 | **`keystrokes.paste` itself lets go of the calling tool's own key when that key is Command-V, and takes it again once the paste is typed.** **Adds to the spec.** | The paste types Command-V. A tool whose shortcut is Command-V would be pressed by its own paste. Today the service does this inside the two callbacks of `TransientPaste`. A callback in the middle of an operation is not a reply, so it may not cross the broker; and the host knows both facts (what it is about to type, which keys the tool holds). |
| 6 | **`hotkey` is `bind(role, onPress:, onRegistered:)` and `unbind(role)`.** A press, and whether macOS gave the key, are replies handed to `bind`. A tool may bind only a role of its own feature. **Narrows the spec**, which lists `onPress` as an operation. | `onRegistered` is called each time the host takes the key, not only at `bind`: after a paste retakes it (decision 5) the Settings warning must still be right. |
| 7 | **`clipboard.read` gains `readPlainText()`**: the plain string, else the words of the RTF or HTML. **Adds to the spec.** | It is `PastePlainService.plainText(from:)`, moved unchanged. It names `NSPasteboard`, so it cannot stay in the tool's file. Stage B's `readText()` reads the plain string only. |
| 8 | **The Settings section moves to a view file of its own**, `UI/Settings/PastePlainSettingsSection.swift`, listed for the tool in the lint. The page still decides whether it shows, and hands it the Accessibility grant as a plain value. **The spec's default 4 stands**: it is still a section of the Clipboard page, in the same place, with the same anchor. | The lint lists whole files, and `ClipboardSettings.swift` rightly calls clipboard history's services. A line range would rot at the next upstream edit; leaving the section out would leave a view of a migrated tool unchecked. Cost for upstream porting: an upstream change to that section (24 lines) no longer applies; it is applied by hand in the new file. `UPSTREAM.md` says so. |
| 9 | **The hotkey id of a role lives in one place, `HotkeyBindings.Environment.live`**, spelled `QuickToolHotkey(id: 10)`. It moves there in the same commit that takes it out of the service (Task 6). | `hotkey_ids_are_unique` reads literal ids from source. Spelled in two files it fails; passed as a variable it cannot be read. The rule needs no change, and Task 7 proves it still sees the id. |
| 10 | **`TransientPaste.swift` is not edited, and gets no unit test.** Its guarantee is an empty diff, checked in Task 8. | Every seam into it would be an edit to hand-tuned timing. The tests pin what is handed to it and what happens in its two callbacks. Text snippets keep calling it directly. Its call to clipboard history's `ignoreNextChange` now sits behind `keystrokes.paste` without moving. |
| 11 | **"Suspend" for a tool is `ToolHost.suspend(id)`**: stop it now, whatever the run rule says, build nothing; the next `sync` starts it again. `SelfUninstall` calls it. | It is what `PastePlainService.shared.suspend()` meant: let go of the key at once. A full uninstall that fails re-syncs every feature, which reaches the host. |
| 12 | **`ShortcutCapture.end()` does not change.** | Recording releases every key. This tool gets its key back as every feature does: `end()` syncs `GlobalShortcutRole.featuresToSilenceWhileRecording`, which holds `.pastePlain` because the role names it; its arm is `.tool(id)`; the host calls `start()`, which binds again. The rule in `AGENTS.md` is for a registrar tied to no feature. |
| 13 | **The tool declares four capabilities**: `hotkey`, `keystrokes` (starts without its grant), `clipboard.read`, `notify`. Not `storage`. | It reads no preference itself any more: its switch is the host's run rule and its shortcut is the `hotkey` capability's. The manifest still declares both keys, so they stay the tool's. |
| 14 | **One command, `pastePlain/paste`, with no surface.** The command bar's `action.pastePlain` row stays hand-built, keeps its id, title, subtitle, shortcut hint, trouble mark and its 0.15 second delay, and runs the command through `ToolRegistry`. | As the URL cleaner's row. A command can run while the tool's switch is off, which is today's gating: the row asks only whether the feature is installed. |
| 15 | **`QuickToolsSupport.isMatchStyleEquivalent` stays, and is defined by the value the tool hands over** (`QuickToolsSupport.matchStyleEquivalent`). | Its ten existing expectations then pin the very comparison the walk makes. Cost: six lines of one more upstream file. |
| 16 | **The menu walk moves to its final file in Task 1**, with the lane read, before the capabilities exist. | A test can only reach the walk once it reads a menu bar made of values. Doing that in the service and moving it again three tasks later would list the walk twice for no gain. |
| 17 | **Not in stage C:** text snippets; a failure reply or a "delete first" step for `keystrokes.paste`; titles in the menu press; `storage.set`; commands with arguments; an observer for preferences; removing the `pastePlain` case from `AppFeature` or `GlobalShortcutRole`. | Each is another feature's change, or has no user yet. |

Six things the code does today that this plan keeps and does not fix:

- An app whose Paste and Match Style item was greyed out at the first press is remembered as having none until it is opened again, or until 65 such apps have been met.
- The memory of having asked for Accessibility lasts the whole launch. After a grant and a revocation, a press beeps.
- With the grant held and nothing on the clipboard, a press does nothing and says nothing.
- A copy that carries only HTML is turned into words by `NSAttributedString(html:)` on the clipboard lane, off the main thread.
- A press while an earlier paste is still under way is dropped by `TransientPaste`, silently.
- While a shortcut is being recorded, a sync takes this key again at once. `ToolShortcutRegistrar` waits for the recording to end; this service never did.

Four places a line of today's code behaves differently. None can be met by a person in ordinary use, and none is pinned by a test, on purpose:

- A press already under way when the feature is removed in the hub (the 0.15 seconds after the command bar's row is chosen): today it pastes, after the move the broker refuses it.
- Accessibility taken away between the check and the paste (the moment the clipboard lane takes to answer): today the clipboard is swapped and put back around a keystroke macOS drops; after the move nothing happens.
- A full uninstall clears the "macOS would not give this shortcut" flag, where today it leaves it. The warning it drives is on Settings › Clipboard; a failed uninstall re-syncs and sets it again.
- At quit the key is released by `ToolHost.stopAll()`, a few lines before `SystemShortcutTakeover.restoreAll()` gives every taken-over macOS shortcut back anyway.

## Global Constraints

- The code in this plan was written against the branch head `41aaf8fb0` (`refactor/vitruvian-broker-stage-c`, which holds stages A and B) and has not been compiled. Where it does not compile or does not match the file, make the smallest change that keeps its meaning and record it as a deviation.
- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file whose line 2 says `Copyright (C) 2026 Vorssaint`, test files included, is named in `UPSTREAM.md` under "Modifications" in the same commit. Task 1 creates one entry, `- **<date>**: Tool platform, the broker, stage C (...)`, and later tasks append sub-bullets. Check line 2 of each file you change; do not trust a list.
- Module order is `Core <- Design <- Services <- UI <- App`. All of them and the tests build in Swift 6 mode. What another module uses is `package`. Every initializer is written out.
- **Nothing a user can see changes.** No new string. No new command, tile or row. The same key, saved under the same preference, with hotkey id 10. The same number of hops between a press and the paste: the Carbon handler's hop to the main queue, the clipboard lane, the hop back.
- **`Sources/Vitruvian/Services/TransientPaste.swift` is not edited.** Not a line, not a comment. If a step seems to need it, stop and report.
- **Nothing crosses the broker that could not be written as JSON**: no `NSPasteboard`, `CGEvent`, `AXUIElement`, `QuickToolHotkey`, view type, or closure that captures app state. The in-process exceptions are stage B's two (a completion, a `ClipboardRewriteRule`) and replies that arrive more than once: `onPress` and `onRegistered`, as stage B's `onRewrite` is.
- Under `Services/Platform/Broker/` no file names a tool, in code. In a migrated tool's files no code names a service. Task 7 adds Paste as plain text to both lints.
- **Hotkey id 10 is spelled in exactly one source file at every commit.** Until Task 6 that is `PastePlainService.swift`; from Task 6 it is `Services/Platform/Broker/HotkeyAccess.swift`. `source_lints_test` fails otherwise.
- Existing tests keep their expectations. Three things change on purpose, each quoted before and after where it happens: one call site in `Tests/ClipboardFeatureTests.swift` (Task 1: the function it called moved), two expectations in `Tests/ToolPlatformTests.swift` that pin the list of capabilities (Task 2), and one helper in `Tests/URLCleanerTests.swift` that gains defaulted parameters (Task 6).
- Tests are behavioural. No test reads a source file as text, registers a real hotkey, posts a real `CGEvent`, calls real Accessibility (`AXIsProcessTrusted` included), reads or writes the real clipboard, or waits for a timer. A clipboard in a test is `NSPasteboard.withUniqueName()`, released at the end. A hotkey in a test is `ToolPlatformTests.FakeHotkey`. A menu bar in a test is made of `MenuItemProbe` values.
- Three rules of the test target that this plan's tests must obey:
  - A defaults suite is opened with a name spelled as a literal on the line above. This plan opens none: its tests use `URLCleanerTests.CleanerRig`, which has one.
  - A type declared in a test, nested ones included, is not named like a production type (`test_types_do_not_shadow_real_ones`). The new ones are `PasteRig`, `MenuLog`, `NeedsGrantProbe` and `AsksLaterProbe`.
  - A test enum has one `static func run`, reached from `Tests/TestGroups.swift` (`TestRegistrationContract`).
- The test module defaults to the main actor (`-default-isolation MainActor`). A class declared in a test is main-actor isolated unless it says `nonisolated`.
- Swift 6 notes, each with a fallback if the compiler disagrees:
  - A closure written in main-actor code and stored as a plain `() -> Void` may call main-actor code: it keeps the isolation of where it was written. `ToolShortcutRegistrar.hold` and today's `PastePlainService` both rely on it. This plan does so in `HotkeyBindings.bind` (`hotkey.onPress = { onPress() }`) and `KeystrokesAccess.paste` (the two closures handed to the paste). Fallback: wrap the body in `MainActor.assumeIsolated { ... }`.
  - `KeystrokesAccess.paste` shares one local `var released` between those two closures. Neither is `@Sendable`, so this is allowed. Fallback: a `final class` with one `var`, made in the method.
  - `FrontAppMenu`'s two helpers that touch `AXUIElement` are `nonisolated static`, so the closures a `MenuItemProbe` holds are plain closures. They are only ever called on the main thread.
  - `MenuItemProbe`, `HotkeyBindings.Environment`, `FrontAppMenu.Environment` and `KeystrokesAccess.Backing` are not `Sendable` and must not be marked so. A type nested in a main-actor type is not itself main-actor: its `live` value says `@MainActor`, and its `inert` value is a plain computed `static var`, because it is a default argument of a plain initializer.
  - `GlobalShortcutRole` is an enum with no payloads, so it is `Hashable` without saying so; `HotkeyBindings` uses it in a dictionary key.
- `Tests/mutation_checks.py` quotes exact source text. After editing it or any `.py` or `BUILD` file, run `bazel run //tools/format -- <path>`.
- Build and test through Bazel only, from the repository root, one command at a time:
  ```sh
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest
  ```
  One suite: add `--test_arg=--suite=platform` (repeat the flag for several). Paste as plain text's own tests are in `clipboard`; the broker's are in `platform`.
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren 2>/dev/null)"
  ```
  Put this in the same command as the commit.
- Commit titles: `refactor(desktop): ...` for every task. Nothing here changes what a release build does.

## Review Focus

Failure modes most likely to reach a user. Each has a test in the task named, except where it says by hand.

1. **The shortcut stops working**: after any other shortcut is recorded, after a paste when the shortcut is Command-V, after the feature is switched off and on, after a relaunch. (Tasks 1, 3, 4 and 6; the real key by hand in Task 8.)
2. **A press without Accessibility misbehaves**: it pastes nothing and says nothing, or asks at every press, or reads the clipboard first. (Tasks 1 and 6)
3. **A press with Accessibility is refused**: at launch, because a published grant had not landed, or in the seconds after the person granted it. (Task 2; by hand in Task 8.)
4. **The paste's timing changes.** `TransientPaste.swift` must not change, and no hop may be added between the press and the paste. (An empty diff, checked in Task 8; real apps by hand.)
5. **The menu press hits the wrong item, a greyed-out one, or stalls on a huge menu bar.** (Task 1)
6. **Hotkey id 10 is made twice, or the saved shortcut is read from another key.** (The lint at every commit; Tasks 3 and 6.)
7. **The Settings section moves, or loses its anchor, its warning or its permission row.** (Task 5 by eye; by hand in Task 8: no unit test draws a Settings page.)
8. **The command bar's row moves, doubles, loses its delay, or stops working while the switch is off.** (Task 6; the row itself by hand in Task 8.)
9. **A refused call does work anyway.** (Tasks 2, 3 and 4)

---

### Task 1: Pin what Paste as plain text does today

**Files:**
- Modify: `Sources/Vitruvian/Services/QuickTools/PastePlainService.swift`
- Create: `Sources/Vitruvian/Core/Platform/MenuKeyEquivalent.swift`
- Create: `Sources/Vitruvian/Services/Platform/Broker/FrontAppMenu.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift` (two members added)
- Modify: `Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift` (`isMatchStyleEquivalent`)
- Create: `Tests/PastePlainTests.swift`
- Modify: `Tests/ClipboardFeatureTests.swift` (one call site near line 1177), `Tests/TestGroups.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `ToolHotkey`, `ToolPlatformTests.FakeHotkey`, `URLCleanerTests.CleanerRig`, `ClipboardWatcher.Environment`, `TransientPaste`.
- Produces:
  - `MenuKeyEquivalent` (`character`, `modifierMask`, `matches(commandCharacter:modifierMask:)`); `QuickToolsSupport.matchStyleEquivalent`
  - `MenuItemProbe` (`read`, `children`, `press`); `FrontAppMenu` with `Environment` (`frontmostApp`, `menuBar`; `.live`, `.inert`), `pressItem(matching:)`, and the constants `elementTimeout`, `elementCap`, `depthLimit`, `rememberedApps`
  - `ClipboardWatcher.readPlainText(completion:)`, `ClipboardWatcher.plainText(from:)`
  - `PastePlainService.Environment` with `.live`, and `PastePlainService.init(environment:)`
  - `PastePlainTests.PasteRig`, `PastePlainTests.MenuLog`, `PastePlainTests.bench(_:)`, `PastePlainTests.item`, `PastePlainTests.editMenu`

Nothing the feature does changes in this task. Three things happen so a test can stand in for the outside world. The service stops reaching for `UserDefaults.standard`, its hotkey, `AXIsProcessTrusted`, `NSSound`, `Permissions` and `TransientPaste` by name: they arrive in an `Environment`, which lasts five commits (Task 6 replaces it with `ToolServices`). The menu walk moves to `FrontAppMenu`, where it reads a menu bar through `MenuItemProbe` values instead of `AXUIElement`; that file is where it stays. The read of the clipboard on its lane moves to `ClipboardWatcher`, beside stage B's `readText`.

What each line of today's file does, and where it ends up. This table is the contract for the whole stage.

| Today, in `PastePlainService` | After stage C |
|---|---|
| `QuickToolHotkey(id: 10)`, made with the singleton | made in `HotkeyBindings.Environment.live`, the first time the tool binds (Tasks 3 and 6) |
| `syncWithPreferences()`: installed in the hub and switched on; Accessibility is not asked | `ToolHost.shouldRun`, with `startsWithoutGrant` (Task 2) |
| `hotkey.sync(enabled: true, shortcut: saved, storageKey:)`, and `shortcutRegistrationFailed` from its answer | `hotkey.bind(.pastePlain)` from `start()`; the answer through `onRegistered` (Task 3) |
| `hotkey.sync(enabled: false, …)`: let go, and the flag goes false | `stop()`: `hotkey.unbind(.pastePlain)`, and the flag goes false |
| `suspend()` | `ToolHost.suspend(id)` (Task 2) |
| `hotkey.onPress` | `bind`'s `onPress` |
| `AXIsProcessTrusted()` at the press, before anything is read | `keystrokes.refusal`: the broker's check, which asks macOS at the press (Tasks 2 and 4) |
| `NSSound.beep()` | `notify.beep()` |
| `Permissions.shared.requestAccessibility()`, once per launch | `keystrokes.requestGrant()`; the once-per-launch memory stays in the tool (Task 4) |
| `readPlainText(on:from:then:)` and `plainText(from:)` | `clipboard.readPlainText` over `ClipboardWatcher.readPlainText` (this task and Task 4); "not empty" stays in the tool |
| `pressNativeMatchStyleItem()`: the walk, its limits, the apps it remembers | `keystrokes.pressFrontAppMenuItem(matching:)` over `FrontAppMenu` (this task and Task 4) |
| `QuickToolsSupport.isMatchStyleEquivalent` | the tool hands over `QuickToolsSupport.matchStyleEquivalent`; "enabled" is the walk's |
| `TransientPaste.shared.paste(plain, willPostShortcut:, didPostShortcut:)` | `keystrokes.paste(text)`; `TransientPaste` unchanged (Task 4) |
| let go of the key when the saved shortcut is Command-V, sync again after | inside `keystrokes.paste`: `HotkeyBindings.release` and `retake` (Tasks 3 and 4) |

What a press does with and without Accessibility, today. The tests in this task pin every row, and must still pass unchanged after Task 6.

| Situation | What happens |
|---|---|
| Launch, installed and switched on, Accessibility never granted | The shortcut is taken. Nobody is asked for anything. |
| First press this launch without it (shortcut or command bar) | The person is asked: the system prompt and the app's guide. Nothing is read, pasted or beeped. |
| Every later press this launch without it | A beep. Nothing else. |
| Granted while the app runs | The next press pastes, at once: the press asks macOS itself. When `Permissions` notices, within 2.5 seconds, the feature is synced again, which takes no key twice. |
| Taken away while the app runs | The shortcut stays taken. The next press beeps, or asks if it has not asked yet this launch. When `Permissions` notices, within 60 seconds, the sync changes nothing. |
| Switched off | The shortcut is let go. The command bar's row still works, by the rows above. |
| Removed in the hub | The shortcut is let go. The row and the Settings section are gone. |

- [ ] **Step 1: Write the failing test**

Create `Tests/PastePlainTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Carbon.HIToolbox
import Foundation
import VitruvianCore
import VitruvianServices

/// Paste as plain text over a clipboard, a preference suite, a hotkey, a
/// menu bar and a paste helper of its own. Nothing here registers a key,
/// asks Accessibility anything, posts a keystroke or touches the real
/// clipboard, and no test waits for a timer.
@MainActor
enum PastePlainTests {
    static let commandV = GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
    /// Option-Shift-Command-V as the Accessibility menu attributes spell it.
    static let matchStyle: (String, UInt32) = ("V", 3)

    static func run(_ suite: TestSuite) {
        runRule(suite)
        withoutTheGrant(suite)
        press(suite)
        ownShortcut(suite)
        plainText(suite)
        menuWalk(suite)
        whatTheMenuRemembers(suite)
    }

    /// What a made-up menu bar was asked.
    final class MenuLog {
        var reads = 0
        var pressed: [String] = []
        /// Whether the app accepts a press.
        var pressTakes = true
    }

    /// The feature's outside world for one test.
    final class PasteRig {
        /// The clipboard, its lane and the saved preferences.
        let clipboard = URLCleanerTests.CleanerRig()
        /// Whether macOS would give the shortcut's key.
        var keyIsGiven = true
        lazy var key = ToolPlatformTests.FakeHotkey(id: 10, accepts: { [unowned self] in self.keyIsGiven })
        /// Whether Accessibility is granted.
        var trusted = true
        var beeps = 0
        /// How many times the person was asked for Accessibility.
        var prompts = 0
        /// The app in front, and each app's menu bar.
        var frontApp: pid_t? = 501
        var menuBars: [pid_t: MenuItemProbe] = [:]
        /// The apps whose menu bar was asked for, in order.
        var menuBarsAsked: [pid_t] = []
        /// Each paste the helper was asked for, with what it is to call just
        /// before Command-V goes down and once it is up.
        var pastes: [(text: String, willPost: () -> Void, didPost: () -> Void)] = []

        func close() { clipboard.close() }

        /// Installs or removes the feature in the hub, and flips its switch.
        func set(installed: Bool, on: Bool) {
            clipboard.defaults.set(installed, forKey: AppFeature.pastePlain.availabilityKey)
            clipboard.defaults.set(on, forKey: DefaultsKey.pastePlainEnabled)
        }

        /// Saves a shortcut as the recorder in Settings does.
        func save(_ shortcut: GlobalShortcut) {
            clipboard.defaults.set(shortcut.storageValue, forKey: DefaultsKey.pastePlainShortcut)
        }

        /// The front app and its menus, as the menu walk reaches them.
        var menu: FrontAppMenu.Environment {
            FrontAppMenu.Environment(
                frontmostApp: { [unowned self] in self.frontApp },
                menuBar: { [unowned self] app in
                    self.menuBarsAsked.append(app)
                    return self.menuBars[app]
                })
        }
    }

    /// The feature over `rig`: how the app re-decides whether it runs, what
    /// the command bar's row does, and what a full uninstall does first. A
    /// press of the shortcut is `rig.key.onPress?()`.
    static func bench(_ rig: PasteRig)
        -> (tool: PastePlainService, sync: () -> Void, run: () -> Void, suspend: () -> Void) {
        let tool = PastePlainService(environment: .init(
            defaults: rig.clipboard.defaults,
            hotkey: rig.key,
            isTrusted: { rig.trusted },
            beep: { rig.beeps += 1 },
            requestAccessibility: { rig.prompts += 1 },
            clipboard: ClipboardWatcher(environment: rig.clipboard.watching),
            menu: FrontAppMenu(environment: rig.menu),
            paste: { text, willPost, didPost in rig.pastes.append((text, willPost, didPost)) }))
        return (tool, { tool.syncWithPreferences() }, { tool.performPastePlain() }, { tool.suspend() })
    }

    /// A menu element made of values. `key` is its command character and its
    /// modifier mask.
    static func item(_ name: String, key: (String, UInt32)? = nil, enabled: Bool = true, _ log: MenuLog,
                     _ children: [MenuItemProbe] = []) -> MenuItemProbe {
        MenuItemProbe(
            read: {
                log.reads += 1
                return (key?.0, key?.1, enabled)
            },
            children: { children },
            press: {
                log.pressed.append(name)
                return log.pressTakes
            })
    }

    /// A menu bar with one menu, Edit, holding `items`: bar, bar item, menu,
    /// items, as every app lays its menus out.
    static func editMenu(_ log: MenuLog, _ items: [MenuItemProbe]) -> MenuItemProbe {
        item("bar", log, [item("Edit", log, [item("menu", log, items)])])
    }

    /// Installed in the hub and switched on: the shortcut is taken. Anything
    /// else: it is not. Accessibility is not asked about.
    static func runRule(_ suite: TestSuite) {
        for installed in [false, true] {
            for on in [false, true] {
                for trusted in [false, true] {
                    let rig = PasteRig()
                    rig.set(installed: installed, on: on)
                    rig.trusted = trusted
                    let (tool, sync, _, _) = bench(rig)
                    sync()
                    let wanted = installed && on
                    suite.expect((rig.key.registered != nil) == wanted && !tool.shortcutRegistrationFailed
                                     && rig.prompts == 0 && rig.beeps == 0,
                                 "installed \(installed), switched on \(on), Accessibility \(trusted): the shortcut is "
                                     + (wanted ? "taken, and nobody is asked for anything" : "left alone"))
                    rig.close()
                }
            }
        }

        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        let (tool, sync, _, suspend) = bench(rig)
        sync()
        suite.expect(rig.key.registered?.shortcut == .pastePlainDefault
                         && rig.key.registered?.storageKey == DefaultsKey.pastePlainShortcut,
                     "with nothing saved the shortcut is the default one, claimed under its own preference")
        sync()
        suite.expect(rig.key.registrations == 1, "deciding again while it holds its key takes no key twice")

        rig.save(commandV)
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV && rig.key.registrations == 2,
                     "a shortcut recorded in Settings is the one held after the next decision")

        // Recording any shortcut releases every key the app holds
        // (`QuickToolHotkey.unregisterAll`); the decision that follows takes
        // this one back.
        rig.key.unregister()
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV,
                     "a key let go for a recording comes back at the next decision")

        rig.keyIsGiven = false
        rig.save(.pastePlainDefault)
        sync()
        suite.expect(rig.key.registered == nil && tool.shortcutRegistrationFailed,
                     "a combination macOS will not give is reported, for Settings to say so")
        rig.keyIsGiven = true
        sync()
        suite.expect(rig.key.registered != nil && !tool.shortcutRegistrationFailed,
                     "and the report clears once the key is given")

        suspend()
        suite.expect(rig.key.registered == nil,
                     "a full uninstall lets go of the key at once, whatever the switches say")
        sync()
        suite.expect(rig.key.registered != nil, "and the next decision takes it back")

        rig.keyIsGiven = false
        rig.save(commandV)
        sync()
        rig.set(installed: true, on: false)
        sync()
        suite.expect(rig.key.registered == nil && !tool.shortcutRegistrationFailed,
                     "switching it off lets go of the key, and of the report")
        rig.keyIsGiven = true
        rig.set(installed: false, on: true)
        sync()
        suite.expect(rig.key.registered == nil, "removing the feature in the hub lets go of the key")
    }

    /// Never granted, granted while the app runs, taken away while it runs.
    static func withoutTheGrant(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        rig.trusted = false
        rig.clipboard.copy("Plain words")
        let (_, sync, run, _) = bench(rig)
        sync()

        rig.key.onPress?()
        suite.expect(rig.prompts == 1 && rig.beeps == 0 && rig.clipboard.lane.isEmpty && rig.pastes.isEmpty
                         && rig.menuBarsAsked.isEmpty,
                     "without Accessibility the first press asks for it, once, and reads nothing")
        rig.key.onPress?()
        run()
        suite.expect(rig.prompts == 1 && rig.beeps == 2 && rig.clipboard.lane.isEmpty,
                     "every press after that only beeps, from the shortcut or from the command bar")
        sync()
        suite.expect(rig.key.registered != nil, "the shortcut stays taken while Accessibility is missing")

        // Granted in System Settings while the app runs: the very next press
        // pastes, before anything has told the app.
        rig.trusted = true
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.map { $0.text } == ["Plain words"] && rig.prompts == 1 && rig.beeps == 2,
                     "a press pastes as soon as Accessibility is granted")
        sync()
        suite.expect(rig.key.registrations == 1, "hearing of the grant takes no key twice")

        // Taken away again while the app runs.
        rig.trusted = false
        rig.key.onPress?()
        suite.expect(rig.beeps == 3 && rig.prompts == 1 && rig.pastes.count == 1 && rig.clipboard.lane.isEmpty
                         && rig.key.registered != nil,
                     "with Accessibility taken away a press beeps: the person was asked once this launch already")
    }

    /// One press, with Accessibility granted.
    static func press(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        let log = MenuLog()
        let (_, sync, run, _) = bench(rig)
        sync()

        rig.clipboard.board.clearContents()
        rig.key.onPress?()
        suite.expect(rig.clipboard.lane.count == 1,
                     "a press reads the clipboard on its lane, never on the main thread")
        rig.clipboard.settle()
        suite.expect(rig.menuBarsAsked.isEmpty && rig.pastes.isEmpty && rig.beeps == 0,
                     "an empty clipboard pastes nothing, and says nothing")
        rig.clipboard.copy("")
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.menuBarsAsked.isEmpty && rig.pastes.isEmpty, "text of no length pastes nothing")

        // An app with its own matching-style paste.
        rig.menuBars[501] = editMenu(log, [item("Paste", key: ("V", 0), log), item("Match", key: matchStyle, log)])
        rig.clipboard.copy("Plain words")
        let count = rig.clipboard.board.changeCount
        rig.key.onPress?()
        suite.expect(log.pressed.isEmpty, "nothing is pressed until the clipboard has answered")
        rig.clipboard.settle()
        suite.expect(log.pressed == ["Match"] && rig.pastes.isEmpty && rig.clipboard.board.changeCount == count,
                     "an app with its own Paste and Match Style has that item pressed, and the clipboard is not touched")

        // An app without one.
        rig.frontApp = 502
        rig.menuBars[502] = editMenu(log, [item("Paste", key: ("V", 0), log)])
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.map { $0.text } == ["Plain words"] && log.pressed == ["Match"],
                     "an app without one is handed the text through the paste helper")

        // An app that has the item and refuses the press.
        rig.frontApp = 501
        log.pressTakes = false
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 2, "an item the app would not press falls back to the paste helper")

        rig.frontApp = nil
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 3, "with no app in front the paste helper is still asked")

        // A copy that is only rich text.
        rig.frontApp = 502
        let rich = NSAttributedString(string: "Rich words", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        rig.clipboard.board.clearContents()
        rig.clipboard.board.setData(rich.rtf(from: NSRange(location: 0, length: rich.length)), forType: .rtf)
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 4 && rig.pastes.last?.text == "Rich words",
                     "a copy that is only rich text is pasted as its words")

        // The command bar's row asks only whether the feature is installed.
        rig.set(installed: true, on: false)
        sync()
        run()
        rig.clipboard.settle()
        suite.expect(rig.key.registered == nil && rig.pastes.count == 5,
                     "the command bar's row pastes while the shortcut is switched off")
    }

    /// The paste types Command-V. When Command-V is also this feature's own
    /// shortcut, the key is let go while the paste is typed.
    static func ownShortcut(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        rig.clipboard.copy("Plain words")
        let (tool, sync, run, _) = bench(rig)

        sync()
        rig.key.onPress?()
        rig.clipboard.settle()
        rig.pastes[0].willPost()
        suite.expect(rig.key.registered != nil, "the default shortcut is kept while the paste is typed")
        rig.pastes[0].didPost()
        suite.expect(rig.key.registrations == 1, "and nothing is taken again after it")

        rig.save(commandV)
        sync()
        rig.key.onPress?()
        rig.clipboard.settle()
        suite.expect(rig.key.registered != nil,
                     "a shortcut saved as Command-V is held until the paste is about to be typed")
        rig.pastes[1].willPost()
        suite.expect(rig.key.registered == nil,
                     "a shortcut saved as Command-V is let go just before the paste is typed")
        rig.keyIsGiven = false
        rig.pastes[1].didPost()
        suite.expect(rig.key.registered == nil && tool.shortcutRegistrationFailed,
                     "it is asked for again once the paste is typed, and a refusal is reported")
        rig.keyIsGiven = true
        sync()
        suite.expect(rig.key.registered?.shortcut == commandV && !tool.shortcutRegistrationFailed,
                     "the next decision takes it")

        // Switched off, the command bar's row still pastes. No key is taken
        // for it, before or after.
        rig.set(installed: true, on: false)
        sync()
        run()
        rig.clipboard.settle()
        rig.pastes[2].willPost()
        rig.pastes[2].didPost()
        suite.expect(rig.key.registered == nil && !tool.shortcutRegistrationFailed,
                     "switched off, typing the paste takes no key")
    }

    /// The clipboard's text without its formatting. The HTML branch is not
    /// here: it builds a web view, which is checked by hand.
    static func plainText(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        suite.expect(ClipboardWatcher.plainText(from: board) == nil, "an empty clipboard has no text")
        let rich = NSAttributedString(string: "Rich words", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        board.setData(rich.rtf(from: NSRange(location: 0, length: rich.length)), forType: .rtf)
        suite.expect(ClipboardWatcher.plainText(from: board) == "Rich words", "rich text is read as its words")
        board.setString("Plain words", forType: .string)
        suite.expect(ClipboardWatcher.plainText(from: board) == "Plain words",
                     "the plain string wins when the copy carries one")
        board.clearContents()
        board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        suite.expect(ClipboardWatcher.plainText(from: board) == nil, "a picture has no text")
    }

    /// The walk through an app's menus: what it presses, and where it stops.
    static func menuWalk(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        let menu = FrontAppMenu(environment: rig.menu)
        let wanted = [QuickToolsSupport.matchStyleEquivalent]
        var app: pid_t = 600
        /// Presses in an app not met before, whose menu bar `build` makes.
        func walk(_ build: (MenuLog) -> MenuItemProbe) -> (pressed: Bool, log: MenuLog) {
            let log = MenuLog()
            app += 1
            rig.frontApp = app
            rig.menuBars[app] = build(log)
            return (menu.pressItem(matching: wanted), log)
        }

        var result = walk { log in
            editMenu(log, [item("Paste", key: ("V", 0), log), item("Match", key: ("v", 3), log),
                           item("Later", key: matchStyle, log)])
        }
        suite.expect(result.pressed && result.log.pressed == ["Match"] && result.log.reads == 5,
                     "the walk presses the first item with the wanted key equivalent, and reads nothing after it")

        result = walk { log in
            editMenu(log, [item("Shift", key: ("V", 1), log), item("Control", key: ("V", 7), log),
                           item("Copy", key: ("C", 3), log), item("None", log)])
        }
        suite.expect(!result.pressed && result.log.pressed.isEmpty,
                     "an item with a modifier more or less, or another letter, is another command")

        result = walk { log in
            editMenu(log, [item("Off", key: matchStyle, enabled: false, log), item("On", key: matchStyle, log)])
        }
        suite.expect(result.pressed && result.log.pressed == ["On"],
                     "a matching item that is switched off is passed over")

        result = walk { log in
            editMenu(log, [item("Submenu", log, [item("Match", key: matchStyle, log)])])
        }
        suite.expect(!result.pressed && result.log.reads == 4,
                     "an item inside a submenu is out of reach, and is not read")

        result = walk { log in
            item("bar", log, (0 ..< 700).map { index in
                item("Menu \(index)", key: index == 650 ? matchStyle : nil, log)
            })
        }
        suite.expect(!result.pressed && result.log.reads == 600, "one walk reads 600 elements and no more")
        result = walk { log in
            item("bar", log, (0 ..< 700).map { index in
                item("Menu \(index)", key: index == 100 ? matchStyle : nil, log)
            })
        }
        suite.expect(result.pressed && result.log.reads == 102, "and it stops as soon as it finds the item")

        result = walk { log in
            log.pressTakes = false
            return editMenu(log, [item("Match", key: matchStyle, log)])
        }
        suite.expect(!result.pressed && result.log.pressed == ["Match"],
                     "an item the app would not press counts as not pressed")
        suite.expect(FrontAppMenu.elementTimeout == 0.35 && FrontAppMenu.elementCap == 600
                         && FrontAppMenu.depthLimit == 3 && FrontAppMenu.rememberedApps == 64,
                     "an element gets 0.35 seconds to answer, a walk reads 600 at most and goes three levels down")
    }

    /// Apps known to have no such item are not walked at every press.
    static func whatTheMenuRemembers(_ suite: TestSuite) {
        let rig = PasteRig()
        defer { rig.close() }
        let menu = FrontAppMenu(environment: rig.menu)
        let wanted = [QuickToolsSupport.matchStyleEquivalent]
        let log = MenuLog()
        func press(in app: pid_t?, with menu: FrontAppMenu) -> Bool {
            rig.frontApp = app
            return menu.pressItem(matching: wanted)
        }

        suite.expect(!press(in: nil, with: menu) && rig.menuBarsAsked.isEmpty,
                     "with no app in front nothing is asked")
        suite.expect(!press(in: 1, with: menu) && !press(in: 1, with: menu) && rig.menuBarsAsked == [1, 1],
                     "an app that gives no menu bar is asked again the next time")

        rig.menuBars[2] = editMenu(log, [item("Paste", key: ("V", 0), log)])
        suite.expect(!press(in: 2, with: menu) && !press(in: 2, with: menu) && rig.menuBarsAsked == [1, 1, 2],
                     "an app without the item is remembered, and its menus are not walked again")
        rig.menuBars[2] = editMenu(log, [item("Match", key: matchStyle, log)])
        suite.expect(!press(in: 2, with: menu) && rig.menuBarsAsked == [1, 1, 2],
                     "even when its menus have gained the item since: it gets another chance when it is opened again")

        rig.menuBars[3] = editMenu(log, [item("Match", key: matchStyle, log)])
        suite.expect(press(in: 3, with: menu) && press(in: 3, with: menu) && rig.menuBarsAsked == [1, 1, 2, 3, 3],
                     "an app with the item is walked at every press")

        rig.frontApp = 2
        suite.expect(menu.pressItem(matching: [MenuKeyEquivalent(character: "V", modifierMask: 3)])
                         == false && rig.menuBarsAsked.count == 5,
                     "what is remembered is the app and the key equivalents asked for")
        suite.expect(!menu.pressItem(matching: [MenuKeyEquivalent(character: "Z", modifierMask: 0)])
                         && rig.menuBarsAsked.count == 6,
                     "so another command is looked for afresh")

        // Sixty-four are remembered. One more and the list starts again.
        let fresh = FrontAppMenu(environment: rig.menu)
        rig.menuBarsAsked = []
        for app in pid_t(100) ..< pid_t(164) {
            rig.menuBars[app] = editMenu(log, [])
            _ = press(in: app, with: fresh)
        }
        _ = press(in: 100, with: fresh)
        suite.expect(rig.menuBarsAsked.count == 64, "sixty-four apps without the item are remembered")
        rig.menuBars[164] = editMenu(log, [])
        _ = press(in: 164, with: fresh)
        _ = press(in: 164, with: fresh)
        _ = press(in: 100, with: fresh)
        suite.expect(rig.menuBarsAsked.count == 67 && rig.menuBarsAsked.suffix(2) == [164, 100],
                     "the sixty-fifth empties the list, itself included, and every app is walked again")
    }
}
```

In `Tests/TestGroups.swift`, the `clipboard` entry runs all three:

```swift
            ("clipboard", { ClipboardFeatureTests.run(suite); URLCleanerTests.run(suite) }),
```
becomes
```swift
            ("clipboard", {
                ClipboardFeatureTests.run(suite)
                URLCleanerTests.run(suite)
                PastePlainTests.run(suite)
            }),
```

In `Tests/ClipboardFeatureTests.swift`, one call site changes because the function it called moves. The two expectations below it are untouched.

```swift
        PastePlainService.readPlainText(on: pasteboardAccess,
                                        from: { NSPasteboard(name: NSPasteboard.Name("vitru.tests.paste-plain")) },
                                        then: { text in
                                            pastedPlain = text
                                            pastedPlainOnMain = Thread.isMainThread
                                        })
```
becomes
```swift
        ClipboardWatcher(environment: .init(
            lane: { pasteboardAccess.async($0) },
            main: { work in DispatchQueue.main.async { work() } },
            pasteboard: { NSPasteboard(name: NSPasteboard.Name("vitru.tests.paste-plain")) },
            every: { _, _, _ in {} }))
            .readPlainText { text in
                pastedPlain = text
                pastedPlainOnMain = Thread.isMainThread
            }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard`
Expected: a compile failure naming `FrontAppMenu`, `MenuItemProbe` or `environment`.

- [ ] **Step 3: Say a key equivalent as a value**

Create `Sources/Vitruvian/Core/Platform/MenuKeyEquivalent.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// A menu item's key equivalent, as Accessibility reports it: the character,
/// and a mask of the modifiers that go with Command. In the mask 1 is Shift,
/// 2 is Option and 4 is Control; 0 is Command alone.
///
/// It is a plain value, so a tool can tell the host which items it would
/// press without the host knowing the tool.
package struct MenuKeyEquivalent: Hashable, Sendable {
    package let character: String
    package let modifierMask: UInt32

    package init(character: String, modifierMask: UInt32) {
        self.character = character
        self.modifierMask = modifierMask
    }

    /// Whether a menu item that reports this character and this mask has
    /// this key equivalent. The character is compared without case. The
    /// mask must match exactly: an item with one modifier more is another
    /// command.
    package func matches(commandCharacter: String?, modifierMask: UInt32?) -> Bool {
        commandCharacter?.uppercased() == character.uppercased() && modifierMask == self.modifierMask
    }
}
```

In `Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift`, the doc comment above the function stays as it is:

```swift
    package static func isMatchStyleEquivalent(commandCharacter: String?,
                                       modifierMask: UInt32?,
                                       isEnabled: Bool) -> Bool {
        let shiftAndOption: UInt32 = 1 | 2
        return commandCharacter?.uppercased() == "V"
            && modifierMask == shiftAndOption
            && isEnabled
    }
```
becomes
```swift
    package static func isMatchStyleEquivalent(commandCharacter: String?,
                                       modifierMask: UInt32?,
                                       isEnabled: Bool) -> Bool {
        matchStyleEquivalent.matches(commandCharacter: commandCharacter, modifierMask: modifierMask)
            && isEnabled
    }

    /// The same key equivalent as a value: what Paste as plain text hands
    /// the menu walk, which looks for it among the items that are enabled.
    package static let matchStyleEquivalent = MenuKeyEquivalent(character: "V", modifierMask: 1 | 2)
```

The ten expectations on `isMatchStyleEquivalent` in `Tests/SwitcherModelFeatureTests.swift` (near line 4727) are not touched, and now pin the comparison the walk makes.

- [ ] **Step 4: Give the menu walk a file of its own**

Create `Sources/Vitruvian/Services/Platform/Broker/FrontAppMenu.swift`. The walk is `PastePlainService.pressNativeMatchStyleItem` and `findMatchStyleItem`, in the same order, with three differences and no others: an element is read through a `MenuItemProbe`; the item wanted is a list of `MenuKeyEquivalent`; and an app is remembered together with what was asked of it.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import ApplicationServices
import VitruvianCore

/// One element of an app's menu bar, as the walk meets it. Each part is
/// asked for only when the walk gets there: reading an element is a round
/// trip to the other app.
package struct MenuItemProbe {
    /// The element's key equivalent, and whether it can be pressed.
    package let read: () -> (commandCharacter: String?, modifierMask: UInt32?, isEnabled: Bool)
    package let children: () -> [MenuItemProbe]
    /// Presses the element. False when the app refused.
    package let press: () -> Bool

    package init(read: @escaping () -> (commandCharacter: String?, modifierMask: UInt32?, isEnabled: Bool),
                 children: @escaping () -> [MenuItemProbe],
                 press: @escaping () -> Bool) {
        self.read = read
        self.children = children
        self.press = press
    }
}

/// Presses a command in the front app's own menus. The command is found by
/// its key equivalent, never by its title, which changes with the language.
/// Main thread only, like the Accessibility calls under it.
@MainActor
package final class FrontAppMenu {
    /// What the walk reaches. The app's is the workspace and Accessibility.
    /// A test passes an app and a menu bar made of values.
    package struct Environment {
        /// The process in front, or nil when there is none.
        package var frontmostApp: () -> pid_t?
        /// That process's menu bar, or nil when it gives none.
        package var menuBar: (pid_t) -> MenuItemProbe?

        package init(frontmostApp: @escaping () -> pid_t?, menuBar: @escaping (pid_t) -> MenuItemProbe?) {
            self.frontmostApp = frontmostApp
            self.menuBar = menuBar
        }

        @MainActor package static let live = Environment(
            frontmostApp: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            menuBar: { app in
                let application = AXUIElementCreateApplication(app)
                // A busy target must not hold the main thread for AX's default
                // multi-second timeout; every traversed element gets the same bound.
                AXUIElementSetMessagingTimeout(application, FrontAppMenu.elementTimeout)
                guard let menuBar: AXUIElement = FrontAppMenu.attribute(kAXMenuBarAttribute, from: application)
                else { return nil }
                return FrontAppMenu.probe(menuBar)
            })

        /// No app is ever in front. For tests of other capabilities.
        package static var inert: Environment {
            Environment(frontmostApp: { nil }, menuBar: { _ in nil })
        }
    }

    /// How long one element may take to answer, in seconds.
    nonisolated package static let elementTimeout: Float = 0.35
    /// How many elements one walk reads at most, so a pathological menu bar
    /// cannot stall a press.
    nonisolated package static let elementCap = 600
    /// Depth 3 is a direct item of a top level menu (bar, bar item, menu,
    /// item), where every app keeps its paste commands; anything deeper is
    /// out of reach on purpose.
    nonisolated package static let depthLimit = 3
    /// How many apps without the item are remembered before the list starts
    /// again.
    nonisolated package static let rememberedApps = 64

    /// An app, and what was looked for in it and not found.
    private struct Absent: Hashable {
        let app: pid_t
        let equivalents: [MenuKeyEquivalent]
    }

    private let environment: Environment
    /// Apps known to carry no such item, so their menu bar is not re-walked
    /// on every single press. An app gets another chance after a relaunch
    /// (the pid changes): menus rarely grow the item mid-run, and the
    /// caller's fallback covers it if they do.
    private var absent: Set<Absent> = []

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Presses the first enabled item in the front app's menus that has one
    /// of `equivalents`. False when there is no such item, or the app
    /// refused the press.
    package func pressItem(matching equivalents: [MenuKeyEquivalent]) -> Bool {
        guard let app = environment.frontmostApp() else { return false }
        let key = Absent(app: app, equivalents: equivalents)
        if absent.contains(key) { return false }
        guard let menuBar = environment.menuBar(app) else { return false }
        var visited = 0
        guard let item = Self.find(equivalents, in: menuBar, depth: 0, visited: &visited) else {
            absent.insert(key)
            if absent.count > Self.rememberedApps { absent.removeAll() }
            return false
        }
        return item.press()
    }

    private static func find(_ equivalents: [MenuKeyEquivalent], in node: MenuItemProbe, depth: Int,
                             visited: inout Int) -> MenuItemProbe? {
        guard depth <= depthLimit, visited < elementCap else { return nil }
        visited += 1
        let item = node.read()
        let wanted = equivalents.contains {
            $0.matches(commandCharacter: item.commandCharacter, modifierMask: item.modifierMask)
        }
        if wanted, item.isEnabled { return node }

        guard depth < depthLimit else { return nil }
        for child in node.children() {
            if let match = find(equivalents, in: child, depth: depth + 1, visited: &visited) {
                return match
            }
        }
        return nil
    }

    /// An element as the walk reads it. The timeout is set when the element
    /// is read, as it always was, and its children are not looked at until
    /// the walk asks.
    nonisolated private static func probe(_ element: AXUIElement) -> MenuItemProbe {
        MenuItemProbe(
            read: {
                AXUIElementSetMessagingTimeout(element, elementTimeout)
                let command: String? = attribute(kAXMenuItemCmdCharAttribute, from: element)
                let modifiers: NSNumber? = attribute(kAXMenuItemCmdModifiersAttribute, from: element)
                let enabled: NSNumber? = attribute(kAXEnabledAttribute, from: element)
                return (command, modifiers?.uint32Value, enabled?.boolValue != false)
            },
            children: {
                let children: [AXUIElement] = attribute(kAXChildrenAttribute, from: element) ?? []
                return children.map { probe($0) }
            },
            press: { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success })
    }

    nonisolated private static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
```

Read it against lines 100 to 167 of today's `PastePlainService.swift` once more before going on. The calls to Accessibility are the same, in the same order, with the same arguments: the timeout on the application, the menu bar attribute; then for each element the timeout, the command character, the modifiers, the enabled flag, and its children only below depth 3 and only when it did not match.

- [ ] **Step 5: Read the clipboard's plain text in the broker's watcher**

In `Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift`, after `readText(completion:)`, add the two members below. `plainText(from:)` is `PastePlainService.plainText(from:)`, moved word for word with its two comments.

```swift
    /// The clipboard's text without its formatting, read on the lane and
    /// handed back on the main thread. Nil when it holds no text. Promised
    /// content renders when read, so a busy source app would hold the main
    /// thread here; the lane answers back on main when it can.
    package func readPlainText(completion: @escaping @MainActor (String?) -> Void) {
        let board = environment.pasteboard
        let main = environment.main
        environment.lane {
            let text = ClipboardWatcher.plainText(from: board())
            main { completion(text) }
        }
    }

    /// The clipboard's text without any formatting: the plain string when
    /// present, else the text of its RTF or HTML content.
    // Read on the pasteboard's own lane.
    nonisolated package static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let plain = pasteboard.string(forType: .string) {
            return plain
        }
        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed.string
        }
        if let html = pasteboard.data(forType: .html),
           let attributed = NSAttributedString(html: html, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }
```

This is today's `readPlainText(on:from:then:)` written out: `GeneralPasteboardAccess.async(_:then:)` is one job on the lane followed by one hop to the main queue, which is what `lane` and `main` are. The "not empty" check that sat in the old function stays with the service, below.

- [ ] **Step 6: Give the service its seam**

Replace `Sources/Vitruvian/Services/QuickTools/PastePlainService.swift` from line 9 (the doc comment `/// Pastes the clipboard as plain text on a global shortcut`) to the end of the file with the text below. Lines 1 to 8 (the header and the imports) stay as they are.

```swift
/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
@MainActor
package final class PastePlainService: ObservableObject {
    package static let shared = PastePlainService(environment: .live)

    /// What the service reaches outside itself. The app's is the saved
    /// preferences, hotkey 10, Accessibility, the clipboard lane, the front
    /// app's menus and the paste helper. A test passes doubles, so it
    /// registers no key, asks macOS nothing and touches no clipboard.
    package struct Environment {
        /// Where the hub's switch, this feature's own switch and its
        /// shortcut are saved.
        package var defaults: UserDefaults
        package var hotkey: ToolHotkey
        /// Whether Accessibility is granted at this instant.
        package var isTrusted: () -> Bool
        package var beep: () -> Void
        /// The system's Accessibility prompt and the app's guide.
        package var requestAccessibility: () -> Void
        /// Reads the clipboard on its lane.
        package var clipboard: ClipboardWatcher
        package var menu: FrontAppMenu
        /// The paste helper: the text, what to do just before Command-V
        /// goes down, and what to do once it is up.
        package var paste: (_ text: String, _ willPost: @escaping () -> Void, _ didPost: @escaping () -> Void) -> Void

        package init(defaults: UserDefaults, hotkey: ToolHotkey, isTrusted: @escaping () -> Bool,
                     beep: @escaping () -> Void, requestAccessibility: @escaping () -> Void,
                     clipboard: ClipboardWatcher, menu: FrontAppMenu,
                     paste: @escaping (String, @escaping () -> Void, @escaping () -> Void) -> Void) {
            self.defaults = defaults
            self.hotkey = hotkey
            self.isTrusted = isTrusted
            self.beep = beep
            self.requestAccessibility = requestAccessibility
            self.clipboard = clipboard
            self.menu = menu
            self.paste = paste
        }

        @MainActor package static let live = Environment(
            defaults: .standard,
            hotkey: QuickToolHotkey(id: 10),
            isTrusted: { AXIsProcessTrusted() },
            beep: { NSSound.beep() },
            requestAccessibility: { Permissions.shared.requestAccessibility() },
            clipboard: ClipboardWatcher(environment: .live),
            menu: FrontAppMenu(environment: .live),
            paste: { text, willPost, didPost in
                _ = TransientPaste.shared.paste(text, willPostShortcut: willPost, didPostShortcut: didPost)
            })
    }

    @Published package private(set) var shortcutRegistrationFailed = false

    private let environment: Environment

    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    package init(environment: Environment) {
        self.environment = environment
        environment.hotkey.onPress = { [weak self] in self?.performPastePlain() }
    }

    /// The saved shortcut, or the default when none is saved or it cannot
    /// be read.
    private var savedShortcut: GlobalShortcut {
        environment.defaults.string(forKey: DefaultsKey.pastePlainShortcut)
            .flatMap { GlobalShortcut(storageValue: $0) } ?? .pastePlainDefault
    }

    package func syncWithPreferences() {
        let enabled = AppFeature.pastePlain.isAvailable(in: environment.defaults)
            && environment.defaults[Preferences.pastePlainEnabled]
        shortcutRegistrationFailed = !environment.hotkey.sync(enabled: enabled, shortcut: savedShortcut,
                                                              storageKey: DefaultsKey.pastePlainShortcut)
    }

    package func suspend() {
        environment.hotkey.unregister()
    }

    package func performPastePlain() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        guard environment.isTrusted() else {
            if promptedForAccessibility {
                environment.beep()
            } else {
                promptedForAccessibility = true
                environment.requestAccessibility()
            }
            return
        }
        environment.clipboard.readPlainText { [weak self] plain in
            guard let plain, !plain.isEmpty else { return }
            self?.pastePlain(plain)
        }
    }

    private func pastePlain(_ plain: String) {
        // An app that ships its own matching-style paste does this better
        // than any synthesized ⌘V: the destination decides the typing
        // attributes (a stripped string pasted normally can leave the
        // insertion point stuck with the styling of what it landed in,
        // issue #349), the pasteboard keeps the original formatting for
        // later pastes, and held modifier keys don't matter to a menu
        // press. The strip-and-restore dance below stays as the fallback
        // for every app without that command.
        if environment.menu.pressItem(matching: [QuickToolsSupport.matchStyleEquivalent]) { return }

        var releaseHotkey = false
        environment.paste(
            plain,
            { [weak self] in
                guard let self else { return }
                releaseHotkey = self.savedShortcut.isStandardPasteCommand
                if releaseHotkey { self.environment.hotkey.unregister() }
            },
            { [weak self] in
                if releaseHotkey { self?.syncWithPreferences() }
            })
    }
}
```

What changed, and nothing else may:

- `shared` is built with `.live`. `private init()` is `init(environment:)`.
- `QuickToolHotkey(id: 10)` is made in `Environment.live`. It is the only place in the source that spells that id.
- `GlobalShortcut.saved(for:fallback:)`, which reads `UserDefaults.standard`, is `savedShortcut`, the same two lines over `environment.defaults`.
- `AXIsProcessTrusted()`, `NSSound.beep()`, `Permissions.shared.requestAccessibility()` and `TransientPaste.shared.paste` are called through the environment. `performPastePlain` and `pastePlain` keep their order, line for line.
- `readPlainText(on:from:then:)` and `plainText(from:)` left for `ClipboardWatcher` (Step 5); the "not empty" check is the first line of the completion.
- `pressNativeMatchStyleItem`, `findMatchStyleItem`, `attribute` and `noMatchStyleItem` left for `FrontAppMenu` (Step 4).

- [ ] **Step 7: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard --test_arg=--suite=switcher-model --test_arg=--suite=repository --test_arg=--suite=harness`
Expected: PASS. If a `PastePlainTests` expectation fails, the test is wrong about today's behaviour or the seam changed it: read lines 13 to 186 of the file as it was (`git show 41aaf8fb0:apps/desktop/vitruvian/Sources/Vitruvian/Services/QuickTools/PastePlainService.swift`) and find out which before touching either. Do not adjust an expectation to pass. `switcher-model` holds the ten checks on `isMatchStyleEquivalent`; `repository` holds `TestRegistrationContract`, which checks the new test enum runs.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS. `hotkey_ids_are_unique` still finds id 10 once.

Run: `git diff --stat 41aaf8fb0 -- apps/desktop/vitruvian/Sources/Vitruvian/Services/TransientPaste.swift`
Expected: no output.

- [ ] **Step 8: See one of the new tests fail for the right reason**

In `PastePlainService.swift`, comment out the line `promptedForAccessibility = true`. Run the `clipboard` suite with `--test_output=errors`.
Expected: FAIL, with "every press after that only beeps, from the shortcut or from the command bar" among the messages. Put the line back by hand and confirm `git diff --stat -- apps/desktop/vitruvian/Sources/Vitruvian/Services/QuickTools/PastePlainService.swift` shows only this task's change.

- [ ] **Step 9: Start the `UPSTREAM.md` entry and commit**

At the top of `## Modifications`, add (use the day's date):

```markdown
- **<date>**: Tool platform, the broker, stage C (`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-c.md`):
  - `Services/QuickTools/PastePlainService.swift`: takes what it reaches outside itself (the saved preferences, its hotkey, Accessibility, the beep, the paste helper) as an `Environment`, so a press can be tested. Its walk through the front app's menus moved to `Services/Platform/Broker/FrontAppMenu.swift`, where it reads a menu bar through values, and its read of the clipboard's plain text moved, word for word, to `Services/Platform/Broker/ClipboardWatcher.swift`. Nothing it does changed.
  - `Core/QuickTools/QuickToolsSupport.swift`: `isMatchStyleEquivalent` is defined by a value, `matchStyleEquivalent`, that says the same key equivalent. Its answers are unchanged.
  - `Tests/ClipboardFeatureTests.swift`: the check that Paste as plain text reads on the clipboard lane calls the read where it lives now. Its expectations are unchanged.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/QuickTools/PastePlainService.swift apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/MenuKeyEquivalent.swift apps/desktop/vitruvian/Sources/Vitruvian/Core/QuickTools/QuickToolsSupport.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/FrontAppMenu.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift apps/desktop/vitruvian/Tests/PastePlainTests.swift apps/desktop/vitruvian/Tests/ClipboardFeatureTests.swift apps/desktop/vitruvian/Tests/TestGroups.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): pin what Paste as plain text does today"
```

---

### Task 2: A tool that starts without its grant, and grants asked of macOS itself

**Files:**
- Modify: `Sources/Vitruvian/Core/Platform/ToolManifest.swift` (`Capability`, `CapabilityRequest`, `ToolManifest`)
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (imports, `Environment.live`)
- Modify: `Sources/Vitruvian/Services/Platform/ToolHost.swift` (`shouldRun(_:)`, `suspend(_:)`)
- Modify: `Tests/ToolPlatformTests.swift`, `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Consumes: `CapabilityBroker.refusal(of:for:)`, `ToolHost.shouldRun(installed:switchedOn:holdsGrants:)`.
- Produces:
  - `Capability.hotkey`, `Capability.keystrokes`; `Capability.keystrokes.ridesOn == [.accessibility]`
  - `CapabilityRequest.startsWithoutGrant`, and `init?(_:reason:startsWithoutGrant:)`
  - `ToolManifest.grantsNeededToStart`
  - `CapabilityBroker.Environment.reading(accessibility:screenRecording:)`; `live` built from it
  - `ToolHost.suspend(_ id: ToolID)`

Three questions from the brief are answered here, before any code.

**Can the host decide about Paste as plain text before `Permissions` exists?** Yes, and it would not matter if it could not. The host's first decision is `FeatureRuntime.shared.syncAtLaunch()` at `AppDelegate.swift:202`. The first touch of `Permissions.shared` that can be proved by reading is at line 215, thirteen lines later (`MenuPanelView.swift:591` may touch it sooner, when the panel is first drawn). But `Permissions.init` only schedules its first publish with `DispatchQueue.main.async`, and all of `applicationDidFinishLaunching` is one turn of the main thread: no hop lands inside it. So `Permissions.shared.accessibility` reads false at line 202 whatever was touched first. The fix is not an order of launch. It is decision 2: the broker asks macOS.

**Does a grant that changes while the app runs reach the host?** Yes, with nothing added. `AppDelegate.swift:215` to `229` call `FeatureRuntime.shared.permissionDidChange(.accessibility)`. That syncs `AppFeature.dependents(on: .accessibility)`, which are derived from each feature's `permissions`; `pastePlain` declares `[.accessibility]`. `sync` runs the feature's binding, and from Task 6 that binding is `.tool(id)`, which `perform` hands to `ToolHost.shared.sync(id)`. Task 6 adds the test, when the arm exists.

**What does the run rule do with a tool that starts without its grant?** It does not ask about that grant. The table the test below pins:

| Accessibility | A tool whose `keystrokes` request is plain | A tool whose request says `startsWithoutGrant` |
|---|---|---|
| missing at the decision | not started; not built | started |
| given later, next decision | started | `start()` again |
| taken away later, next decision | stopped | `start()` again: it keeps running |
| any, a `keystrokes` call | refused `notGranted` while missing | refused `notGranted` while missing |

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, `manifests(_:)`, two expectations change on purpose: the stage adds two capabilities, and one of them rides on a grant.

```swift
        suite.expect(Capability.allCases.allSatisfy { $0.ridesOn.isEmpty },
                     "no stage A capability rides on a macOS grant")
        suite.expect(Set(Capability.allCases.map(\.rawValue))
                         == ["notify", "open", "processes", "clipboard.write", "storage", "clipboard.read",
                             "clipboard.rewrite"],
                     "capabilities are named as the platform design names them")
```
becomes
```swift
        suite.expect(Capability.allCases.filter { !$0.ridesOn.isEmpty } == [.keystrokes]
                         && Capability.keystrokes.ridesOn == [.accessibility],
                     "one capability rides on a macOS grant: keystrokes, on Accessibility")
        suite.expect(Set(Capability.allCases.map(\.rawValue))
                         == ["notify", "open", "processes", "clipboard.write", "storage", "clipboard.read",
                             "clipboard.rewrite", "hotkey", "keystrokes"],
                     "capabilities are named as the platform design names them")
        let typing = CapabilityRequest(.keystrokes, reason: "Types for you.")!
        let typingLater = CapabilityRequest(.keystrokes, reason: "Types for you.", startsWithoutGrant: true)!
        suite.expect(manifest(capabilities: [copy, typing])?.grantsNeededToStart == [.accessibility]
                         && manifest(capabilities: [copy, typingLater])?.grantsNeededToStart == []
                         && manifest(capabilities: [copy])?.grantsNeededToStart == [],
                     "a tool needs the grants its capabilities ride on before it starts, unless it says it starts without")
        suite.expect(CapabilityRequest(.clipboardWrite, reason: "Copies.", startsWithoutGrant: true) == nil,
                     "only a capability that rides on a grant can say its tool starts without it")
```

In `Tests/ToolBrokerTests.swift`, add `grants(suite)` to `run` after `runRule(suite)`, and add:

```swift
    /// A tool that cannot start without Accessibility. It has no switch, so
    /// only the grant decides.
    final class NeedsGrantProbe: BundledTool {
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("wallpaper")!, name: "wallpaper", symbol: "photo", commands: [])!,
            group: .tools, capabilities: [CapabilityRequest(.keystrokes, reason: "test")!],
            preferences: [], activation: [.onLaunch], enabledBy: nil)!
        init(services: ToolServices) {}
        func start() { ToolBrokerTests.events.append("needs start") }
        func stop() { ToolBrokerTests.events.append("needs stop") }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }

    /// A tool that says it starts without Accessibility, and asks later.
    final class AsksLaterProbe: BundledTool {
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("mediaTools")!, name: "mediaTools", symbol: "film", commands: [])!,
            group: .tools,
            capabilities: [CapabilityRequest(.keystrokes, reason: "test", startsWithoutGrant: true)!],
            preferences: [], activation: [.onLaunch], enabledBy: nil)!
        init(services: ToolServices) {}
        func start() { ToolBrokerTests.events.append("later start") }
        func stop() { ToolBrokerTests.events.append("later stop") }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }

    /// The first capability that rides on a macOS grant: the broker's
    /// refusal, where the app's broker gets its answer, and the run rule's
    /// grant clause through the host.
    static func grants(_ suite: TestSuite) {
        let world = World()
        let broker = bench(world: world)
        let typing = manifest([.keystrokes, .notify], id: "wallpaper")

        world.granted = []
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "a capability that rides on a macOS grant is refused without it")
        suite.expect(broker.refusal(of: .notify, for: typing) == nil,
                     "a capability that rides on nothing is not held back by another's grant")
        world.granted = [.accessibility]
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == nil,
                     "the grant is asked about at every call: given while the app runs, it holds from the next one")
        world.granted = [.screenRecording]
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "and taken away, it is missed at the next one")
        world.installed = false
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notInstalled,
                     "not installed is said before a missing grant")
        world.installed = true
        world.allowed = false
        suite.expect(broker.refusal(of: .keystrokes, for: typing) == .notGranted(.accessibility),
                     "a missing grant is said before what the person allows")
        world.allowed = true

        // The app's own broker, with the two questions it puts to macOS
        // answered here.
        var accessibility = false
        var screen = false
        let live = CapabilityBroker.Environment.reading(accessibility: { accessibility },
                                                        screenRecording: { screen })
        suite.expect(!live.isGranted(.accessibility) && !live.isGranted(.screenRecording)
                         && live.isGranted(.notifications),
                     "the app's broker asks about the two grants the app watches, and takes the others as given")
        accessibility = true
        suite.expect(live.isGranted(.accessibility) && !live.isGranted(.screenRecording),
                     "it asks at the moment of the call: a grant holds the instant it is given, with no hop and no poll to wait for")
        accessibility = false
        screen = true
        suite.expect(!live.isGranted(.accessibility) && live.isGranted(.screenRecording),
                     "each grant is asked of its own source")

        // The run rule's grant clause, through the host.
        let needs = NeedsGrantProbe.manifest.id
        let later = AsksLaterProbe.manifest.id
        for granted in [false, true] {
            events = []
            world.granted = granted ? [.accessibility] : []
            let host = ToolHost(broker: broker, tools: [NeedsGrantProbe.self, AsksLaterProbe.self])
            host.sync(needs)
            host.sync(later)
            suite.expect(events == (granted ? ["needs start", "later start"] : ["later start"])
                             && host.built == (granted ? [needs, later] : [later]),
                         "Accessibility \(granted): a tool that needs it " + (granted ? "starts" : "waits")
                             + ", and a tool that says it starts without it starts")
        }

        events = []
        world.granted = []
        let host = ToolHost(broker: broker, tools: [NeedsGrantProbe.self, AsksLaterProbe.self])
        func decide() {
            host.sync(needs)
            host.sync(later)
        }
        decide()
        world.granted = [.accessibility]
        decide()
        suite.expect(events == ["later start", "needs start", "later start"] && host.running == [later, needs],
                     "a grant given while the app runs starts the tool that waited for it, at the next decision")
        world.granted = []
        decide()
        suite.expect(events.suffix(2) == ["needs stop", "later start"] && host.running == [later],
                     "a grant taken away stops the tool that needs it, and leaves the other running")
        suite.expect(broker.refusal(of: .keystrokes, for: AsksLaterProbe.manifest) == .notGranted(.accessibility),
                     "starting without the grant does not open the capability: each call is still refused")

        // Suspending.
        events = []
        host.suspend(later)
        host.suspend(needs)
        host.suspend(ToolID("screenshot")!)
        suite.expect(events == ["later stop", "needs stop"] && host.running.isEmpty,
                     "suspending stops a built tool at once, whatever the run rule says")
        decide()
        suite.expect(events.suffix(1) == ["later start"] && host.running == [later],
                     "and the next decision starts it again")
        let unbuilt = ToolHost(broker: broker, tools: [AsksLaterProbe.self])
        unbuilt.suspend(later)
        suite.expect(unbuilt.built.isEmpty, "suspending a tool that was never built builds nothing")
    }
```

`NeedsGrantProbe` and `AsksLaterProbe` borrow the ids of two hub features that have no built-in command (`wallpaper`, `mediaTools`), because a tool id with no dot must name a feature. They are test doubles and touch nothing of either feature.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `keystrokes`, `startsWithoutGrant` or `reading`.

- [ ] **Step 3: Name the two capabilities, and the flag**

In `Core/Platform/ToolManifest.swift`:

```swift
    /// Read the preferences the tool's manifest declares.
    case storage

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite, .clipboardRead, .clipboardRewrite, .storage: return []
        }
    }
```
becomes
```swift
    /// Read the preferences the tool's manifest declares.
    case storage
    /// Hold a global shortcut.
    case hotkey
    /// Paste, and press a menu command, in the app in front.
    case keystrokes

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite, .clipboardRead, .clipboardRewrite, .storage, .hotkey:
            return []
        case .keystrokes: return [.accessibility]
        }
    }
```

```swift
package struct CapabilityRequest: Equatable, Sendable {
    package let capability: Capability
    package let reason: String

    package init?(_ capability: Capability, reason: String) {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.capability = capability
        self.reason = reason
    }
}
```
becomes
```swift
package struct CapabilityRequest: Equatable, Sendable {
    package let capability: Capability
    package let reason: String
    /// True when the tool starts without the macOS grants this capability
    /// rides on, and asks for them when it first needs one. Every operation
    /// of the capability is still refused until the grant is there.
    package let startsWithoutGrant: Bool

    /// Nil without a reason. Nil too when `startsWithoutGrant` is set on a
    /// capability that rides on no grant: there is nothing to start without.
    package init?(_ capability: Capability, reason: String, startsWithoutGrant: Bool = false) {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !startsWithoutGrant || !capability.ridesOn.isEmpty else { return nil }
        self.capability = capability
        self.reason = reason
        self.startsWithoutGrant = startsWithoutGrant
    }
}
```

and in `ToolManifest`, after `declares(_:)`:

```swift
    /// The macOS grants the tool must hold before the host starts it: those
    /// its capabilities ride on, less the ones it says it starts without.
    package var grantsNeededToStart: [AppPermission] {
        capabilities.filter { !$0.startsWithoutGrant }.flatMap(\.capability.ridesOn)
    }
```

- [ ] **Step 4: Have the host ask for those grants only, and let it suspend a tool**

In `Services/Platform/ToolHost.swift`:

```swift
            holdsGrants: manifest.capabilities.flatMap(\.capability.ridesOn)
                .allSatisfy(broker.environment.isGranted))
```
becomes
```swift
            holdsGrants: manifest.grantsNeededToStart.allSatisfy(broker.environment.isGranted))
```

In the doc comment of the static `shouldRun(installed:switchedOn:holdsGrants:)`, the words "and holding every macOS grant its capabilities ride on" (they wrap across two lines) become "and holding every macOS grant it needs to start (`ToolManifest.grantsNeededToStart`)".

After `sync<T: BundledTool>(_ type: T.Type)`, add:

```swift
    /// Stops the tool with this id at once, whatever the run rule says, and
    /// builds nothing. For the moments the app lets go of every input it
    /// holds, such as a full uninstall. The next `sync` starts it again.
    package func suspend(_ id: ToolID) {
        running.removeAll { $0 == id }
        tools[id]?.stop()
    }
```

- [ ] **Step 5: Have the app's broker ask macOS**

In `Services/Platform/Broker/CapabilityBroker.swift`, the imports:

```swift
import Foundation
import VitruvianCore
```
become
```swift
import ApplicationServices
import CoreGraphics
import Foundation
import VitruvianCore
```

and

```swift
        /// The app as it is: a tool with the id of a hub feature follows
        /// that feature; the two macOS grants the app watches are read
        /// from `Permissions`; a compiled-in tool is always allowed.
        @MainActor package static let live = Environment(
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
becomes
```swift
        /// The app as it is: a tool with the id of a hub feature follows
        /// that feature; a compiled-in tool is always allowed; and the two
        /// macOS grants the app watches are asked of macOS itself, at the
        /// moment of each call.
        ///
        /// Not of `Permissions`. It publishes a grant one main-queue hop
        /// after it is first touched, so it reads false all through launch,
        /// and afterwards only as often as it polls: up to 2.5 seconds
        /// behind a grant and 60 behind a revocation. A tool's press is
        /// answered by the state of that instant, as it was before tools.
        @MainActor package static let live = Environment.reading(
            accessibility: { AXIsProcessTrusted() },
            screenRecording: { CGPreflightScreenCaptureAccess() })

        /// `live`, with the two questions it puts to macOS handed in, so a
        /// test can answer them.
        @MainActor package static func reading(accessibility: @escaping () -> Bool,
                                               screenRecording: @escaping () -> Bool) -> Environment {
            Environment(
                isInstalled: { id in AppFeature(rawValue: id.rawValue)?.isAvailable ?? true },
                isGranted: { permission in
                    switch permission {
                    case .accessibility: return accessibility()
                    case .screenRecording: return screenRecording()
                    default: return true
                    }
                },
                allows: { _, _ in true },
                reportUndeclared: { id, capability in
                    assertionFailure("\(id) used \(capability.rawValue) without declaring it")
                })
        }
```

These are the two calls `Permissions.refreshActivePermissions` makes, which its own comment calls free and without side effects. No tool reaches the changed line yet: the Port manager and the URL cleaner ride on no grant.

- [ ] **Step 6: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=clipboard --test_arg=--suite=features`
Expected: PASS. `ToolBrokerTests.manifestsAgree` passes unchanged: neither tool that exists rides on a grant.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 7: Commit**

No file with an upstream header changed, so `UPSTREAM.md` is not touched.

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ToolManifest.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolHost.swift apps/desktop/vitruvian/Tests/ToolPlatformTests.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): let a tool start without its grant, and ask macOS about grants at each call"
```

---

### Task 3: A global shortcut through the broker

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/HotkeyAccess.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (`Backings`, `hotkeys`, `init`)
- Modify: `Sources/Vitruvian/Services/Platform/ToolServices.swift`
- Modify: `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Consumes: `ToolHotkey` (`Services/Platform/ToolShortcutRegistrar.swift`), `GlobalShortcutRole` (`storageKey`, `savedShortcut`, `defaultShortcut`, `availabilityFeatures`), `CapabilityBroker.refusal(of:for:)`.
- Produces:
  - `HotkeyBindings` with `Environment` (`makeHotkey`, `savedShortcut`; `.live`, `.inert`), `bind(_:for:onPress:onRegistered:) -> Bool`, `unbind(_:for:)`, `release(of:where:) -> [GlobalShortcutRole]`, `retake(_:for:)`
  - `HotkeyAccess`: `bind(_:onPress:onRegistered:) -> BrokerRefusal?`, `unbind(_:)`
  - `CapabilityBroker.Backings.hotkey`, `CapabilityBroker.hotkeys`, `ToolServices.hotkey`

Each step of today's code that touches the hotkey, and the home it gets:

| Today | Here |
|---|---|
| `QuickToolHotkey(id: 10)`, one for the life of the app | `Environment.makeHotkey`, asked once for each tool and role, kept for the life of the app |
| `hotkey.sync(enabled: true, shortcut: saved, storageKey: role's key)` | `take`, from `bind` and from `retake` |
| `SystemShortcutTakeover.claim` and `release` | untouched: `QuickToolHotkey` calls them itself, in `sync` and `unregister` |
| `shortcutRegistrationFailed = !…` | `onRegistered`, each time the key is taken |
| `hotkey.sync(enabled: false, …)` and `suspend()` | `unbind` |
| `hotkey.unregister()` around its own paste, `syncWithPreferences()` after | `release(of:where:)` and `retake(_:for:)`, called by `keystrokes.paste` in Task 4 |
| `QuickToolHotkey.unregisterAll()` from a shortcut recording | untouched: it reaches this hotkey as it reaches every other, and the next `bind` takes the key again |

No real key is made in this task. `Environment.live` gives no role a hotkey yet: id 10 is still spelled in `PastePlainService.swift`, and it may be spelled in one file only. Task 6 moves it.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolBrokerTests.swift`, add `hotkeys(suite)` to `run` after `messages(suite)`, and add:

```swift
    static func hotkeys(_ suite: TestSuite) {
        let world = World()
        var given = true
        var saved = GlobalShortcut.pastePlainDefault
        var made = 0
        let key = ToolPlatformTests.FakeHotkey(id: 10, accepts: { given })
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, _ in }),
            backings: .init(
                notify: .init(beep: {}), open: .init(open: { _ in true }),
                clipboard: .init(write: { _, _ in }), processes: .inert,
                hotkey: .init(makeHotkey: { role in
                    made += 1
                    return role == .pastePlain ? key : nil
                }, savedShortcut: { _ in saved })))
        let owner = ToolID("pastePlain")!
        let tool = broker.services(for: manifest([.hotkey], id: "pastePlain")).hotkey
        let commandV = PastePlainTests.commandV
        var presses = 0
        var heard: [Bool] = []
        func bind() -> BrokerRefusal? {
            tool.bind(.pastePlain, onPress: { presses += 1 }, onRegistered: { heard.append($0) })
        }

        suite.expect(bind() == nil && key.registered?.shortcut == .pastePlainDefault
                         && key.registered?.storageKey == DefaultsKey.pastePlainShortcut && heard == [true],
                     "a tool that asks for it takes the key saved for its role, claimed under the role's own preference")
        key.onPress?()
        suite.expect(presses == 1, "a press of the key reaches the tool")
        suite.expect(bind() == nil && key.registrations == 1 && made == 1 && heard == [true, true],
                     "asking again while the key is held takes nothing twice, and makes no second hotkey")
        saved = commandV
        suite.expect(bind() == nil && key.registered?.shortcut == commandV && key.registrations == 2,
                     "asking again after the saved combination changed takes the new one")
        // What a shortcut recording does to every key the app holds.
        key.unregister()
        suite.expect(bind() == nil && key.registered?.shortcut == commandV,
                     "asking again after the key was let go takes it back")
        given = false
        saved = .pastePlainDefault
        suite.expect(bind() == nil && key.registered == nil && heard.last == false,
                     "a combination macOS will not give is not a refusal: the tool hears that the key was not given")
        given = true

        // The host lets go of a key by its combination, and takes it again.
        saved = commandV
        _ = bind()
        let before = heard.count
        suite.expect(broker.hotkeys.release(of: ToolID("portManager")!, where: { _ in true }).isEmpty
                         && broker.hotkeys.release(of: owner, where: { $0 == .pastePlainDefault }).isEmpty
                         && key.registered != nil,
                     "a key is let go only for the tool that holds it, and only when its combination is the one named")
        suite.expect(broker.hotkeys.release(of: owner, where: { $0 == commandV }) == [.pastePlain]
                         && key.registered == nil && heard.count == before,
                     "the host can let go of a tool's key and keep what the tool asked for")
        broker.hotkeys.retake([.pastePlain], for: owner)
        suite.expect(key.registered?.shortcut == commandV && heard.count == before + 1 && heard.last == true,
                     "and take it again, telling the tool how that went")

        tool.unbind(.pastePlain)
        tool.unbind(.pastePlain)
        suite.expect(key.registered == nil, "giving a key back lets go of it, and doing so twice is safe")
        broker.hotkeys.retake([.pastePlain], for: owner)
        suite.expect(key.registered == nil && heard.count == before + 1,
                     "a key the tool gave back in the meantime is not taken again")

        // Refusals.
        suite.expect(tool.bind(.clipboard, onPress: {}) == .unavailable && made == 1,
                     "a tool takes only a key of its own feature")
        let other = broker.services(for: manifest([.hotkey], id: "finderRename")).hotkey
        suite.expect(other.bind(.finderRename, onPress: {}) == .unavailable && made == 2,
                     "a role the host holds no key for is not offered")
        let none = broker.services(for: manifest([], id: "pastePlain")).hotkey
        suite.expect(none.bind(.pastePlain, onPress: { presses += 1 }) == .notDeclared(.hotkey)
                         && key.registered == nil && made == 2,
                     "a refused bind takes no key and makes no hotkey")
        world.installed = false
        suite.expect(bind() == .notInstalled && key.registered == nil,
                     "a tool removed in the hub is refused its key")
        world.installed = true
        _ = bind()
        world.installed = false
        tool.unbind(.pastePlain)
        suite.expect(key.registered == nil, "but can always give one back")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `hotkey`.

- [ ] **Step 3: Write the capability**

Create `Sources/Vitruvian/Services/Platform/Broker/HotkeyAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The global keys tools hold. A key belongs to a `GlobalShortcutRole`: its
/// combination is the one saved for the role and it is claimed under the
/// role's own preference, so nothing a person saved moves. The host owns
/// the hotkey ids; a tool never sees one.
///
/// A binding is what a tool asked for, whether or not macOS gave the key.
/// It stays until the tool gives it back, so the host can take the key
/// again without the tool asking twice.
@MainActor
package final class HotkeyBindings {
    package struct Environment {
        /// The hotkey for a role, or nil for a role the host holds no key
        /// for. Asked once for each tool and role.
        package var makeHotkey: (GlobalShortcutRole) -> ToolHotkey?
        /// The combination saved for a role now.
        package var savedShortcut: (GlobalShortcutRole) -> GlobalShortcut

        package init(makeHotkey: @escaping (GlobalShortcutRole) -> ToolHotkey?,
                     savedShortcut: @escaping (GlobalShortcutRole) -> GlobalShortcut) {
            self.makeHotkey = makeHotkey
            self.savedShortcut = savedShortcut
        }

        /// The app's own. No role has a key here yet. A role's id moves in
        /// with the tool that holds it, in the same change, so no id is
        /// ever made in two places (`hotkey_ids_are_unique`).
        @MainActor package static let live = Environment(makeHotkey: { _ in nil },
                                                         savedShortcut: { $0.savedShortcut })

        /// Holds no key. For tests of other capabilities.
        package static var inert: Environment {
            Environment(makeHotkey: { _ in nil }, savedShortcut: { $0.defaultShortcut })
        }
    }

    /// A tool, and the role it holds a key for.
    private struct Holder: Hashable {
        let tool: ToolID
        let role: GlobalShortcutRole
    }

    private struct Binding {
        let hotkey: ToolHotkey
        let onRegistered: @MainActor (Bool) -> Void
    }

    private let environment: Environment
    /// Every hotkey made, kept for the life of the app, as the service's
    /// one hotkey was before it was a tool.
    private var hotkeys: [Holder: ToolHotkey] = [:]
    private var bindings: [Holder: Binding] = [:]

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Takes the key of `role` for `tool`, with the combination saved for
    /// the role now. `onPress` hears each press. `onRegistered` hears
    /// whether macOS gave the key, now and each time the host takes it
    /// again. Asked again for a key it holds, it takes nothing twice; asked
    /// after the key was let go or its combination changed, it takes it.
    /// False when the host holds no key for the role.
    package func bind(_ role: GlobalShortcutRole, for tool: ToolID,
                      onPress: @escaping @MainActor () -> Void,
                      onRegistered: @escaping @MainActor (Bool) -> Void) -> Bool {
        let holder = Holder(tool: tool, role: role)
        guard let hotkey = hotkeys[holder] ?? environment.makeHotkey(role) else { return false }
        hotkeys[holder] = hotkey
        hotkey.onPress = { onPress() }
        bindings[holder] = Binding(hotkey: hotkey, onRegistered: onRegistered)
        take(holder)
        return true
    }

    /// Gives the key back. Safe when the tool holds none.
    package func unbind(_ role: GlobalShortcutRole, for tool: ToolID) {
        guard let binding = bindings.removeValue(forKey: Holder(tool: tool, role: role)) else { return }
        binding.hotkey.unregister()
    }

    /// Lets go of each key `tool` asked for whose saved combination
    /// `matches`, and says for which roles. What the tool asked for is
    /// kept: `retake` takes the keys again.
    package func release(of tool: ToolID, where matches: (GlobalShortcut) -> Bool) -> [GlobalShortcutRole] {
        var released: [GlobalShortcutRole] = []
        for (holder, binding) in bindings
        where holder.tool == tool && matches(environment.savedShortcut(holder.role)) {
            binding.hotkey.unregister()
            released.append(holder.role)
        }
        return released
    }

    /// Takes again the keys `release` let go of, for what the tool still
    /// asks for, and tells the tool how each went.
    package func retake(_ roles: [GlobalShortcutRole], for tool: ToolID) {
        for role in roles { take(Holder(tool: tool, role: role)) }
    }

    private func take(_ holder: Holder) {
        guard let binding = bindings[holder] else { return }
        let given = binding.hotkey.sync(enabled: true, shortcut: environment.savedShortcut(holder.role),
                                        storageKey: holder.role.storageKey)
        binding.onRegistered(given)
    }
}

/// The `hotkey` capability: hold the global shortcut of a role.
@MainActor
package struct HotkeyAccess {
    let gate: () -> BrokerRefusal?
    let bindings: HotkeyBindings
    let tool: ToolID

    /// Takes the key saved for `role`. `onPress` hears each press, on the
    /// main thread. `onRegistered` hears whether macOS gave the key, each
    /// time the host takes it; a combination another app holds is not a
    /// refusal. Refused as unavailable for a role of another feature, or
    /// one the host holds no key for. Neither closure is called when the
    /// call is refused.
    @discardableResult
    package func bind(_ role: GlobalShortcutRole, onPress: @escaping @MainActor () -> Void,
                      onRegistered: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        guard role.availabilityFeatures.contains(where: { $0.rawValue == tool.rawValue }),
              bindings.bind(role, for: tool, onPress: onPress, onRegistered: onRegistered)
        else { return .unavailable }
        return nil
    }

    /// Gives the key back. Never refused: a tool that was removed in the
    /// hub must still be able to let go.
    package func unbind(_ role: GlobalShortcutRole) {
        bindings.unbind(role, for: tool)
    }
}
```

In `Services/Platform/Broker/CapabilityBroker.swift`:

```swift
        package var storage: StorageAccess.Backing

        package init(notify: NotifyAccess.Backing, open: OpenAccess.Backing, clipboard: ClipboardAccess.Backing,
                     processes: ProcessesAccess.Backing, storage: StorageAccess.Backing = .inert) {
            self.notify = notify
            self.open = open
            self.clipboard = clipboard
            self.processes = processes
            self.storage = storage
        }

        @MainActor package static let live = Backings(notify: .live, open: .live, clipboard: .live, processes: .live,
                                                      storage: .live)
    }

    package let environment: Environment
    package let backings: Backings
    /// The one watch on the clipboard, shared by every tool that asks.
    package let clipboardWatcher: ClipboardWatcher

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
        self.clipboardWatcher = ClipboardWatcher(environment: backings.clipboard.watching)
    }
```
becomes
```swift
        package var storage: StorageAccess.Backing
        package var hotkey: HotkeyBindings.Environment

        package init(notify: NotifyAccess.Backing, open: OpenAccess.Backing, clipboard: ClipboardAccess.Backing,
                     processes: ProcessesAccess.Backing, storage: StorageAccess.Backing = .inert,
                     hotkey: HotkeyBindings.Environment = .inert) {
            self.notify = notify
            self.open = open
            self.clipboard = clipboard
            self.processes = processes
            self.storage = storage
            self.hotkey = hotkey
        }

        @MainActor package static let live = Backings(notify: .live, open: .live, clipboard: .live, processes: .live,
                                                      storage: .live, hotkey: .live)
    }

    package let environment: Environment
    package let backings: Backings
    /// The one watch on the clipboard, shared by every tool that asks.
    package let clipboardWatcher: ClipboardWatcher
    /// The global keys tools hold.
    package let hotkeys: HotkeyBindings

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
        self.clipboardWatcher = ClipboardWatcher(environment: backings.clipboard.watching)
        self.hotkeys = HotkeyBindings(environment: backings.hotkey)
    }
```

In `Services/Platform/ToolServices.swift`, after `storage`:

```swift
    package var hotkey: HotkeyAccess {
        HotkeyAccess(gate: gate(.hotkey), bindings: broker.hotkeys, tool: manifest.id)
    }
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=clipboard`
Expected: PASS.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS. `the_broker_names_no_tool` reads the new file; it names a role, which is the app's vocabulary for a shortcut, and no tool.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/HotkeyAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): hold a role's global shortcut through the broker"
```

---

### Task 4: Keystrokes through the broker

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/KeystrokesAccess.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/ClipboardAccess.swift` (one operation added)
- Modify: `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (`Backings`, `frontAppMenu`, `init`)
- Modify: `Sources/Vitruvian/Services/Platform/ToolServices.swift`
- Modify: `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Consumes: `FrontAppMenu`, `MenuKeyEquivalent`, `ClipboardWatcher.readPlainText` (Task 1); `HotkeyBindings.release` and `retake` (Task 3); `TransientPaste.shared.paste`; `Permissions.shared.requestAccessibility`.
- Produces:
  - `KeystrokesAccess`: `refusal`, `requestGrant() -> BrokerRefusal?`, `paste(_:) -> BrokerRefusal?`, `pressFrontAppMenuItem(matching:) -> Result<Bool, BrokerRefusal>`; `KeystrokesAccess.Backing` (`paste`, `requestGrant`, `menu`) with `.live` and `.inert`
  - `ClipboardAccess.readPlainText(completion:) -> BrokerRefusal?`
  - `CapabilityBroker.Backings.keystrokes`, `CapabilityBroker.frontAppMenu`, `ToolServices.keystrokes`

`TransientPaste.swift` is not opened in this task. Its `live` backing is one line that calls it, as the service's `Environment.live` does since Task 1. Text snippets keep calling it directly. The call it makes to `ClipboardHistoryService.ignoreNextChange` is now behind `keystrokes.paste` without having moved.

Nothing uses the capability yet: the service keeps its `Environment` until Task 6.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, add `keystrokes(suite)` to `run` after `hotkeys(suite)`, and add:

```swift
    static func keystrokes(_ suite: TestSuite) {
        let world = World()
        var pastes: [(text: String, willPost: () -> Void, didPost: () -> Void)] = []
        var asked = 0
        var front: pid_t? = 7
        let log = PastePlainTests.MenuLog()
        let bar = PastePlainTests.editMenu(log, [PastePlainTests.item("Match", key: PastePlainTests.matchStyle, log)])
        var given = true
        var saved = PastePlainTests.commandV
        let key = ToolPlatformTests.FakeHotkey(id: 10, accepts: { given })
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, _ in }),
            backings: .init(
                notify: .init(beep: {}), open: .init(open: { _ in true }),
                clipboard: .init(write: { _, _ in }), processes: .inert,
                hotkey: .init(makeHotkey: { _ in key }, savedShortcut: { _ in saved }),
                keystrokes: .init(paste: { text, willPost, didPost in pastes.append((text, willPost, didPost)) },
                                  requestGrant: { asked += 1 },
                                  menu: .init(frontmostApp: { front }, menuBar: { _ in bar }))))
        let services = broker.services(for: manifest([.keystrokes, .hotkey], id: "pastePlain"))
        let tool = services.keystrokes
        let wanted = [QuickToolsSupport.matchStyleEquivalent]

        world.granted = []
        suite.expect(tool.refusal == .notGranted(.accessibility)
                         && tool.paste("x") == .notGranted(.accessibility)
                         && tool.pressFrontAppMenuItem(matching: wanted) == .failure(.notGranted(.accessibility))
                         && pastes.isEmpty && log.reads == 0,
                     "without Accessibility a tool can neither paste nor press a menu item, and nothing is tried")
        suite.expect(tool.requestGrant() == nil && asked == 1,
                     "a tool that lacks the grant can have the person asked for it")
        world.granted = [.accessibility]
        suite.expect(tool.refusal == nil && tool.requestGrant() == nil && asked == 1,
                     "with the grant held there is nothing to ask")

        suite.expect(tool.pressFrontAppMenuItem(matching: wanted) == .success(true) && log.pressed == ["Match"],
                     "a tool that asks for it has a menu item of the front app pressed, by its key equivalent")
        front = nil
        suite.expect(tool.pressFrontAppMenuItem(matching: wanted) == .success(false) && log.pressed == ["Match"],
                     "and is told when nothing was pressed")

        var heard: [Bool] = []
        services.hotkey.bind(.pastePlain, onPress: {}, onRegistered: { heard.append($0) })
        suite.expect(tool.paste("Plain words") == nil && pastes.count == 1 && pastes[0].text == "Plain words"
                         && key.registered != nil,
                     "a paste hands the text to the paste helper, and holds the tool's key until the paste is typed")
        pastes[0].willPost()
        suite.expect(key.registered == nil,
                     "the tool's own key, when it is Command-V, is let go just before the paste is typed")
        given = false
        pastes[0].didPost()
        suite.expect(key.registered == nil && heard == [true, false],
                     "and asked for again once it is typed: the tool hears how that went")

        given = true
        saved = .pastePlainDefault
        services.hotkey.bind(.pastePlain, onPress: {}, onRegistered: { heard.append($0) })
        let taken = key.registrations
        _ = tool.paste("again")
        pastes[1].willPost()
        suite.expect(key.registered != nil, "a key that is not Command-V is kept while the paste is typed")
        pastes[1].didPost()
        suite.expect(key.registrations == taken && heard.count == 3, "and nothing is taken again after it")

        let none = broker.services(for: manifest([], id: "pastePlain")).keystrokes
        suite.expect(none.refusal == .notDeclared(.keystrokes) && none.paste("x") == .notDeclared(.keystrokes)
                         && none.requestGrant() == .notDeclared(.keystrokes)
                         && none.pressFrontAppMenuItem(matching: wanted) == .failure(.notDeclared(.keystrokes))
                         && pastes.count == 2 && asked == 1,
                     "a tool that did not ask for keystrokes gets none, and nobody is asked on its behalf")
        world.installed = false
        world.granted = []
        suite.expect(tool.requestGrant() == .notInstalled && tool.paste("x") == .notInstalled
                         && asked == 1 && pastes.count == 2,
                     "a tool removed in the hub can neither paste nor ask for the grant")
    }
```

In `clipboard(_:)`, directly after the expectation "a tool that asks for it reads the clipboard's text, and nothing from an empty one", add:

```swift
        var plain: [String?] = []
        rig.copy("words")
        suite.expect(tool.readPlainText { plain.append($0) } == nil && plain.isEmpty && rig.lane.count == 1
                         && none.readPlainText { plain.append($0) } == .notDeclared(.clipboardRead)
                         && rig.lane.count == 1,
                     "reading the clipboard's text without its formatting waits for the lane, and is refused as any read is")
        rig.settle()
        suite.expect(plain == ["words"], "and the text arrives once the lane has run")
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `keystrokes` or `readPlainText`.

- [ ] **Step 3: Write the capability**

Create `Sources/Vitruvian/Services/Platform/Broker/KeystrokesAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The `keystrokes` capability: paste text into the app in front, and press
/// one of its menu commands. It rides on Accessibility, so every operation
/// is refused until the person grants it.
@MainActor
package struct KeystrokesAccess {
    package struct Backing {
        /// Puts `text` on the clipboard, types Command-V and puts back what
        /// was there. `willPost` is called just before the key goes down
        /// and `didPost` once it is up; neither when the paste cannot start.
        package var paste: (_ text: String, _ willPost: @escaping () -> Void, _ didPost: @escaping () -> Void) -> Void
        /// Asks the person for Accessibility: the system prompt, and the
        /// app's guide to System Settings.
        package var requestGrant: () -> Void
        /// The front app and its menus.
        package var menu: FrontAppMenu.Environment

        package init(paste: @escaping (String, @escaping () -> Void, @escaping () -> Void) -> Void,
                     requestGrant: @escaping () -> Void, menu: FrontAppMenu.Environment) {
            self.paste = paste
            self.requestGrant = requestGrant
            self.menu = menu
        }

        /// The paste is `TransientPaste`, as it is: its delays are tuned by
        /// hand against real apps.
        @MainActor package static let live = Backing(
            paste: { text, willPost, didPost in
                _ = TransientPaste.shared.paste(text, willPostShortcut: willPost, didPostShortcut: didPost)
            },
            requestGrant: { Permissions.shared.requestAccessibility() },
            menu: .live)

        /// Types nothing and asks nobody. For tests of other capabilities.
        package static var inert: Backing {
            Backing(paste: { _, _, _ in }, requestGrant: {}, menu: .inert)
        }
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing
    let menu: FrontAppMenu
    let hotkeys: HotkeyBindings
    let tool: ToolID

    /// Why the tool may not send keystrokes now, or nil when it may. A tool
    /// asks before it reads what it means to paste, so that without the
    /// grant nothing is read at all.
    package var refusal: BrokerRefusal? { gate() }

    /// Has the person asked for the grant this capability rides on: the
    /// system prompt, which macOS shows once, and the app's guide. Does
    /// nothing when the grant is held. Refused for a tool that did not
    /// declare the capability or is not installed.
    @discardableResult
    package func requestGrant() -> BrokerRefusal? {
        let refusal = gate()
        guard case .notGranted? = refusal else { return refusal }
        backing.requestGrant()
        return nil
    }

    /// Presses the first enabled item in the front app's menus that has one
    /// of these key equivalents. True when an item was pressed.
    package func pressFrontAppMenuItem(matching equivalents: [MenuKeyEquivalent]) -> Result<Bool, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(menu.pressItem(matching: equivalents))
    }

    /// Pastes `text` into the app in front and leaves the clipboard as it
    /// was. The paste types Command-V, so a key of the tool's own that is
    /// Command-V is let go just before it and taken again once it is
    /// typed: the paste never presses the tool's own shortcut.
    @discardableResult
    package func paste(_ text: String) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        let hotkeys = self.hotkeys
        let tool = self.tool
        var released: [GlobalShortcutRole] = []
        backing.paste(text,
                      { released = hotkeys.release(of: tool, where: { $0.isStandardPasteCommand }) },
                      { hotkeys.retake(released, for: tool) })
        return nil
    }
}
```

In `Services/Platform/Broker/ClipboardAccess.swift`, after `readText(completion:)`, add:

```swift
    /// Reads the clipboard's text without its formatting: the plain string,
    /// else the words of its rich text. `completion` hears it on the main
    /// thread, nil when there is none; it is not called when the call is
    /// refused.
    @discardableResult
    package func readPlainText(completion: @escaping @MainActor (String?) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRead) { return refusal }
        watcher.readPlainText(completion: completion)
        return nil
    }
```

In `Services/Platform/Broker/CapabilityBroker.swift`, five small edits to what Task 3 left:

```swift
        package var hotkey: HotkeyBindings.Environment

        package init(
```
becomes
```swift
        package var hotkey: HotkeyBindings.Environment
        package var keystrokes: KeystrokesAccess.Backing

        package init(
```

```swift
                     hotkey: HotkeyBindings.Environment = .inert) {
```
becomes
```swift
                     hotkey: HotkeyBindings.Environment = .inert, keystrokes: KeystrokesAccess.Backing = .inert) {
```

```swift
            self.hotkey = hotkey
        }
```
becomes
```swift
            self.hotkey = hotkey
            self.keystrokes = keystrokes
        }
```

```swift
                                                      storage: .live, hotkey: .live)
```
becomes
```swift
                                                      storage: .live, hotkey: .live, keystrokes: .live)
```

```swift
    package let hotkeys: HotkeyBindings

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
        self.clipboardWatcher = ClipboardWatcher(environment: backings.clipboard.watching)
        self.hotkeys = HotkeyBindings(environment: backings.hotkey)
    }
```
becomes
```swift
    package let hotkeys: HotkeyBindings
    /// The walk through the front app's menus, and the apps it remembers.
    package let frontAppMenu: FrontAppMenu

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
        self.clipboardWatcher = ClipboardWatcher(environment: backings.clipboard.watching)
        self.hotkeys = HotkeyBindings(environment: backings.hotkey)
        self.frontAppMenu = FrontAppMenu(environment: backings.keystrokes.menu)
    }
```

In `Services/Platform/ToolServices.swift`, after `hotkey`:

```swift
    package var keystrokes: KeystrokesAccess {
        KeystrokesAccess(gate: gate(.keystrokes), backing: broker.backings.keystrokes, menu: broker.frontAppMenu,
                         hotkeys: broker.hotkeys, tool: manifest.id)
    }
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=clipboard`
Expected: PASS.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

Run: `git diff --stat 41aaf8fb0 -- apps/desktop/vitruvian/Sources/Vitruvian/Services/TransientPaste.swift`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/KeystrokesAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/ClipboardAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): paste and press a menu command through the broker"
```

---

### Task 5: The Settings section in a file of its own

**Files:**
- Create: `Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift`
- Modify: `Sources/Vitruvian/UI/Settings/ClipboardSettings.swift` (lines 13, 16 and 110 to 135), `UPSTREAM.md`

**Interfaces:**
- Produces: `PastePlainSettingsSection(accessibilityGranted:)`, a view whose body is the one `Section`.

Paste as plain text has no Settings page. It is a section of Settings › Clipboard, a page that belongs to clipboard history and rightly calls its services. The lint that holds a tool's files to the broker lists whole files, so the section gets a file. This task is the move alone: the new view still calls `PastePlainService.shared`. Task 6 changes three of its lines.

Nothing a person sees may change: the section's place on the page (after "Paste image as file", before the statistics), its header, its five rows, and its anchor, which is what the Features hub's link to "Paste as plain text" scrolls to. The `Section` and its `.settingsFormSectionAnchor(.pastePlain)` move as one expression, unchanged. The page keeps the `if AppFeature.pastePlain.isAvailable` around it, and keeps observing `Permissions`, which it hands down as a plain value: a tool's view may not name that singleton.

No unit test draws a Settings page, so no test can fail first here. The compiler stands in: the page is edited first and does not build until the view exists.

- [ ] **Step 1: Have the page use the view**

In `UI/Settings/ClipboardSettings.swift`:

```swift
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var clearingIDs: Set<UUID>?
    @AppStorage(Preferences.pastePlainEnabled) private var pastePlainEnabled: Bool
    @AppStorage(Preferences.clipboardHistoryEnabled) private var enabled: Bool
```
becomes
```swift
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var clearingIDs: Set<UUID>?
    @AppStorage(Preferences.clipboardHistoryEnabled) private var enabled: Bool
```

and

```swift
            if AppFeature.pastePlain.isAvailable {
                Section {
                    Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                        .onChange(of: pastePlainEnabled) { _, _ in
                            PastePlainService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.pastePlainCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShortcutPreferenceRow(role: .pastePlain,
                                          isEnabled: pastePlainEnabled) {
                        PastePlainService.shared.syncWithPreferences()
                    }
                    if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if pastePlainEnabled, !permissions.accessibility {
                        PermissionRow(kind: .accessibility)
                    }
                } header: {
                    Text(l10n.s.pastePlainName)
                }
                .settingsFormSectionAnchor(.pastePlain)
            }
```
becomes
```swift
            if AppFeature.pastePlain.isAvailable {
                // Paste as plain text's section is a view of its own.
                PastePlainSettingsSection(accessibilityGranted: permissions.accessibility)
            }
```

`permissions` stays: the "Paste image as file" section above still reads it.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: a compile failure, "cannot find 'PastePlainSettingsSection' in scope".

- [ ] **Step 3: Write the view**

Create `Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift`. The body is the block Step 1 took out, with one change: `permissions.accessibility` is `accessibilityGranted`.

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The Paste as plain text section of Settings › Clipboard. It is a file of
/// its own so that everything in it can be held to the tool's own rules; the
/// page decides whether it shows, and where.
struct PastePlainSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var pastePlain = PastePlainService.shared
    @AppStorage(Preferences.pastePlainEnabled) private var pastePlainEnabled: Bool
    /// Whether Accessibility is granted, as the page that shows this section
    /// observes it.
    let accessibilityGranted: Bool

    var body: some View {
        Section {
            Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                .onChange(of: pastePlainEnabled) { _, _ in
                    PastePlainService.shared.syncWithPreferences()
                }
            Text(l10n.s.pastePlainCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ShortcutPreferenceRow(role: .pastePlain,
                                  isEnabled: pastePlainEnabled) {
                PastePlainService.shared.syncWithPreferences()
            }
            if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if pastePlainEnabled, !accessibilityGranted {
                PermissionRow(kind: .accessibility)
            }
        } header: {
            Text(l10n.s.pastePlainName)
        }
        .settingsFormSectionAnchor(.pastePlain)
    }
}
```

The view takes no `package`: only the page uses it, in the same module. It needs no written initializer: `PermissionRow`, in `SettingsView.swift`, is built the same way, from its one `let`.

- [ ] **Step 4: Build, and run the lints**

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

Run: `git diff -U0 -- apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/ClipboardSettings.swift`
Expected: two lines removed near the top, and the 24 lines of the section replaced by two. Nothing else.

- [ ] **Step 5: Look at it**

Open the build (`rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app`), then Settings › Clipboard. The section is where it was, under the same header. Flip its switch off and on: the shortcut row greys and returns. In the Features hub, use the link to Paste as plain text's settings: the Clipboard page opens with the section outlined. Task 8 repeats this against the build from before the stage; this look is so that a wrong move is found now.

- [ ] **Step 6: Commit**

Append to the stage C entry in `UPSTREAM.md`:

```markdown
  - `UI/Settings/ClipboardSettings.swift`: the Paste as plain text section moved, unchanged, to a view of its own, `UI/Settings/PastePlainSettingsSection.swift`, which the page shows in the same place and hands the Accessibility grant. An upstream change to that section no longer applies here: apply it by hand in the new file.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/ClipboardSettings.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): give Paste as plain text's settings section a file of its own"
```

---

### Task 6: Paste as plain text becomes a tool

**Files:**
- Modify: `Sources/Vitruvian/Services/QuickTools/PastePlainService.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/HotkeyAccess.swift` (`HotkeyBindings.Environment.live`)
- Modify: `Sources/Vitruvian/Services/Platform/BundledTools.swift`
- Modify: `Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift` (three lines)
- Modify: `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift` (line near 476)
- Modify: `Sources/Vitruvian/Services/FeatureRuntime.swift` (`actions(for:in:)`, `perform`, `FeatureBindingAction`)
- Modify: `Sources/Vitruvian/Services/SelfUninstall.swift` (line near 332)
- Modify: `Tests/PastePlainTests.swift`, `Tests/URLCleanerTests.swift`, `Tests/ToolBrokerTests.swift`, `Tests/FeatureRuntimeTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `BundledTool`, `ToolServices` (`hotkey`, `keystrokes`, `clipboard`, `notify`), `ToolHost` (`sync`, `run`, `suspend`), `QuickToolsSupport.matchStyleEquivalent`.
- Produces, on `PastePlainService`: `static let manifest`, `static let paste`, `init(services:)`, `start()`, `stop()`, `run(_:)`, `canRun(_:)`. `shortcutRegistrationFailed` keeps its name. `static let shared`, `Environment`, `init(environment:)`, `syncWithPreferences()`, `suspend()` and `performPastePlain()` are gone.

The class keeps its name and its file, as the other two did.

Every caller of the singleton today, and what it becomes. Found with `grep -rn "PastePlainService" Sources Tests`; there are no others.

| Where | Today | After |
|---|---|---|
| `PastePlainSettingsSection.swift` (was `ClipboardSettings.swift:13`) | `@ObservedObject private var pastePlain = PastePlainService.shared` | `ToolHost.shared.tool(PastePlainService.self)` |
| the same file, the switch and the shortcut row (were lines 114 and 121) | `PastePlainService.shared.syncWithPreferences()` | `ToolHost.shared.sync(PastePlainService.self)` |
| `CommandBarCatalog.swift:476` | the `action.pastePlain` row runs `afterBeat { PastePlainService.shared.performPastePlain() }` | `afterBeat { ToolRegistry.shared.run(PastePlainService.paste) }` |
| `FeatureRuntime.swift:365`, `470`, `537` | the arm `[.pastePlain]`, `PastePlainService.shared.syncWithPreferences()`, and the action's case | the arm `[.tool(id)]`; the `perform` arm and the case go |
| `SelfUninstall.swift:332` | `PastePlainService.shared.suspend()` | `ToolHost.shared.suspend(PastePlainService.manifest.id)` |
| `AppDelegate.swift`, `applicationWillTerminate` | no line: the feature was never on the quit list | none needed: `ToolHost.shared.stopAll()` gives the key back when the tool ran |
| `Tests/ClipboardFeatureTests.swift:1177` | changed in Task 1 | no further change |

These name the feature and nothing of its service, and do not change: `UI/Settings/ShortcutsSettings.swift:258` (the Shortcuts page syncs `role.availabilityFeatures` through `FeatureRuntime`, which now reaches the host), `Services/ShortcutCapture.swift` (decision 12), `Core/GlobalShortcut.swift`, `Core/FeatureCatalog.swift`, `Core/Settings/FeatureVisibilitySupport.swift`, `Services/Settings/SettingsDirectory.swift`, `Services/Settings/FeatureHubText.swift`, and `App/AppDelegate.swift`, whose permission subscriptions already do what Task 2 found.

- [ ] **Step 1: Move the tests onto the tool**

In `Tests/URLCleanerTests.swift`, the rig's broker gains four parameters, each with the value it had. No call of it changes.

```swift
        @MainActor func broker() -> CapabilityBroker {
            CapabilityBroker(
                environment: .init(
                    isInstalled: { [self] id in AppFeature(rawValue: id.rawValue)?.isAvailable(in: defaults) ?? true },
                    isGranted: { _ in true },
                    allows: { _, _ in true },
                    reportUndeclared: { [self] _, capability in undeclared.append(capability.rawValue) }),
                backings: .init(
                    notify: .init(beep: {}, hud: { [self] icon, message in said.append("\(icon): \(message)") }),
                    open: .init(open: { _ in true }),
                    clipboard: .init(write: { _, _ in }, watching: watching),
                    processes: .inert,
                    storage: .init(read: { [self] in defaults.object(forKey: $0) },
                                   undeclaredKey: { [self] in undeclared.append($0) })))
        }
```
becomes
```swift
        @MainActor func broker(isGranted: @escaping (AppPermission) -> Bool = { _ in true },
                               beep: @escaping () -> Void = {},
                               hotkey: HotkeyBindings.Environment = .inert,
                               keystrokes: KeystrokesAccess.Backing = .inert) -> CapabilityBroker {
            CapabilityBroker(
                environment: .init(
                    isInstalled: { [self] id in AppFeature(rawValue: id.rawValue)?.isAvailable(in: defaults) ?? true },
                    isGranted: isGranted,
                    allows: { _, _ in true },
                    reportUndeclared: { [self] _, capability in undeclared.append(capability.rawValue) }),
                backings: .init(
                    notify: .init(beep: beep, hud: { [self] icon, message in said.append("\(icon): \(message)") }),
                    open: .init(open: { _ in true }),
                    clipboard: .init(write: { _, _ in }, watching: watching),
                    processes: .inert,
                    storage: .init(read: { [self] in defaults.object(forKey: $0) },
                                   undeclaredKey: { [self] in undeclared.append($0) }),
                    hotkey: hotkey,
                    keystrokes: keystrokes))
        }
```

In `Tests/PastePlainTests.swift`, add to `PasteRig`, after `menu`:

```swift
        /// A broker whose hub, preferences, clipboard, hotkey, grant, menus
        /// and paste helper are this rig's.
        func broker() -> CapabilityBroker {
            clipboard.broker(
                isGranted: { [unowned self] in $0 != .accessibility || self.trusted },
                beep: { [unowned self] in self.beeps += 1 },
                hotkey: .init(
                    makeHotkey: { [unowned self] _ in self.key },
                    savedShortcut: { [unowned self] role in
                        self.clipboard.defaults.string(forKey: role.storageKey)
                            .flatMap { GlobalShortcut(storageValue: $0) } ?? role.defaultShortcut
                    }),
                keystrokes: .init(
                    paste: { [unowned self] text, willPost, didPost in
                        self.pastes.append((text, willPost, didPost))
                    },
                    requestGrant: { [unowned self] in self.prompts += 1 },
                    menu: menu))
        }
```

One helper changes. No expectation does.

```swift
    static func bench(_ rig: PasteRig)
        -> (tool: PastePlainService, sync: () -> Void, run: () -> Void, suspend: () -> Void) {
        let tool = PastePlainService(environment: .init(
            defaults: rig.clipboard.defaults,
            hotkey: rig.key,
            isTrusted: { rig.trusted },
            beep: { rig.beeps += 1 },
            requestAccessibility: { rig.prompts += 1 },
            clipboard: ClipboardWatcher(environment: rig.clipboard.watching),
            menu: FrontAppMenu(environment: rig.menu),
            paste: { text, willPost, didPost in rig.pastes.append((text, willPost, didPost)) }))
        return (tool, { tool.syncWithPreferences() }, { tool.performPastePlain() }, { tool.suspend() })
    }
```
becomes
```swift
    static func bench(_ rig: PasteRig)
        -> (tool: PastePlainService, sync: () -> Void, run: () -> Void, suspend: () -> Void) {
        let host = ToolHost(broker: rig.broker(), tools: [PastePlainService.self])
        let id = PastePlainService.manifest.id
        return (host.tool(PastePlainService.self), { host.sync(id) }, { host.run(PastePlainService.paste) },
                { host.suspend(id) })
    }
```

Add `asTool(suite)` to the end of `run`, and add:

```swift
    /// What the tool declares, its command, and that it asks the broker for
    /// nothing it did not declare.
    static func asTool(_ suite: TestSuite) {
        let manifest = PastePlainService.manifest
        suite.expect(Set(manifest.capabilities.map(\.capability)) == [.hotkey, .keystrokes, .clipboardRead, .notify],
                     "Paste as plain text asks for exactly what it uses")
        suite.expect(manifest.grantsNeededToStart.isEmpty
                         && manifest.capabilities.flatMap(\.capability.ridesOn) == [.accessibility],
                     "it rides on Accessibility and starts without it: the first press asks")

        let rig = PasteRig()
        defer { rig.close() }
        rig.set(installed: true, on: true)
        rig.clipboard.copy("Plain words")
        let host = ToolHost(broker: rig.broker(), tools: [PastePlainService.self])
        let command = PastePlainService.paste
        let registry = ToolRegistry(isAvailable: { $0.isAvailable(in: rig.clipboard.defaults) })
        BuiltinTools.install(into: registry, tools: [PastePlainService.self], host: { host })
        suite.expect(ToolSurface.allCases.allSatisfy { surface in
            !registry.commands(on: surface).contains { $0.id.tool == manifest.id }
        }, "it adds no row, tile, wheel slot or shortcut entry of its own")

        // Every path once: a decision, two presses without the grant, and a
        // press with it while its shortcut is Command-V.
        host.sync(manifest.id)
        rig.trusted = false
        rig.key.onPress?()
        rig.key.onPress?()
        rig.trusted = true
        rig.save(commandV)
        host.sync(manifest.id)
        rig.key.onPress?()
        rig.clipboard.settle()
        rig.pastes[0].willPost()
        rig.pastes[0].didPost()
        suite.expect(rig.prompts == 1 && rig.beeps == 1 && rig.pastes.count == 1
                         && rig.clipboard.undeclared.isEmpty,
                     "it asks the broker for nothing its manifest does not declare")

        rig.set(installed: true, on: false)
        host.sync(manifest.id)
        suite.expect(host.running.isEmpty && registry.run(command),
                     "the command bar's row runs its command through the registry, while the shortcut is switched off")
        rig.clipboard.settle()
        suite.expect(rig.pastes.count == 2, "and the command pastes")
        rig.set(installed: false, on: true)
        suite.expect(!registry.run(command) && !host.canRun(command) && rig.clipboard.lane.isEmpty,
                     "removed in the hub, the command does nothing")
    }
```

In `Tests/ToolBrokerTests.swift`, `manifestsAgree(_:)`:

```swift
        let manifests = [PortManagerService.manifest, URLCleanerService.manifest]
```
becomes
```swift
        let manifests = [PortManagerService.manifest, URLCleanerService.manifest, PastePlainService.manifest]
```

Its expectations are untouched, and each now speaks for the new tool too: the grants its capabilities ride on equal `AppFeature.pastePlain.permissions`, which is `[.accessibility]`; its two preferences carry the defaults the app registers; `pastePlainEnabled` is the key its feature names; and it is handed to the host at launch because its manifest says `onLaunch`.

In `Tests/FeatureRuntimeTests.swift`, after the expectation "a feature that has become a tool is handed to the tool host", add:

```swift
        let pasteTool = FeatureBindingAction.tool(PastePlainService.manifest.id)
        suite.expect(actions(.pastePlain) == [pasteTool], "Paste as plain text is handed to the tool host too")

        // A macOS grant that changes while the app runs, and the end of a
        // shortcut recording, reach the tool host through that one action.
        defaults.set(true, forKey: AppFeature.pastePlain.availabilityKey)
        log.actions = []
        hub.permissionDidChange(.accessibility)
        suite.expect(log.actions.contains(pasteTool)
                         && !log.actions.contains(.tool(URLCleanerService.manifest.id)),
                     "a change to Accessibility hands the tool that rides on it to the tool host, and no other tool")
        log.actions = []
        hub.sync(GlobalShortcutRole.featuresToSilenceWhileRecording)
        suite.expect(log.actions.contains(pasteTool),
                     "the end of a shortcut recording hands the tool to the host, which takes its key again")
        defaults.set(false, forKey: AppFeature.pastePlain.availabilityKey)
        log.actions = []
        hub.permissionDidChange(.accessibility)
        suite.expect(!log.actions.contains(pasteTool), "a tool removed in the hub is not woken by a grant")
        defaults.set(true, forKey: AppFeature.pastePlain.availabilityKey)
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard`
Expected: a compile failure naming `manifest` or `paste`.

- [ ] **Step 3: Turn the service into the tool**

Replace `Sources/Vitruvian/Services/QuickTools/PastePlainService.swift` from line 9 (the doc comment `/// Pastes the clipboard as plain text on a global shortcut`) to the end of the file. Lines 1 to 8 (the header and the imports) stay as they are.

```swift
/// Pastes the clipboard as plain text on a global shortcut: strips fonts,
/// colors and links, pastes, and quietly puts the original rich content back
/// so later normal pastes keep their formatting. Requires Accessibility for
/// the synthesized ⌘V.
@MainActor
package final class PastePlainService: ObservableObject {
    @Published package private(set) var shortcutRegistrationFailed = false

    private let services: ToolServices

    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    package init(services: ToolServices) {
        self.services = services
    }

    /// Takes the shortcut. The tool host calls this each time it finds the
    /// tool installed and switched on, with or without Accessibility, so a
    /// second call only asks for the key it already holds. It is also how
    /// the key comes back after a shortcut recording let every key go, and
    /// how a newly recorded combination is taken.
    package func start() {
        services.hotkey.bind(.pastePlain,
                             onPress: { [weak self] in self?.pastePlainText() },
                             onRegistered: { [weak self] given in self?.shortcutRegistrationFailed = !given })
    }

    package func stop() {
        services.hotkey.unbind(.pastePlain)
        shortcutRegistrationFailed = false
    }

    package func canRun(_ command: CommandID) -> Bool {
        command == Self.paste
    }

    package func run(_ command: CommandID) {
        guard command == Self.paste else { return }
        pastePlainText()
    }

    /// One press of the shortcut, or one run of the command bar's row.
    private func pastePlainText() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        // Asked before anything is read.
        if let refusal = services.keystrokes.refusal {
            guard case .notGranted = refusal else { return }
            if promptedForAccessibility {
                services.notify.beep()
            } else {
                promptedForAccessibility = true
                services.keystrokes.requestGrant()
            }
            return
        }
        services.clipboard.readPlainText { [weak self] plain in
            guard let plain, !plain.isEmpty else { return }
            self?.pastePlain(plain)
        }
    }

    private func pastePlain(_ plain: String) {
        // An app that ships its own matching-style paste does this better
        // than any synthesized ⌘V: the destination decides the typing
        // attributes (a stripped string pasted normally can leave the
        // insertion point stuck with the styling of what it landed in,
        // issue #349), the pasteboard keeps the original formatting for
        // later pastes, and held modifier keys don't matter to a menu
        // press. The strip-and-restore dance below stays as the fallback
        // for every app without that command.
        if case .success(true) = services.keystrokes.pressFrontAppMenuItem(
            matching: [QuickToolsSupport.matchStyleEquivalent]) { return }

        // The paste types ⌘V. When ⌘V is this tool's own shortcut, the paste
        // lets go of it while it types and takes it again after.
        services.keystrokes.paste(plain)
    }
}

extension PastePlainService: BundledTool {
    /// Pastes the clipboard as plain text, once. The shortcut runs it, and
    /// so does the command bar's row. It asks for no surface: the row is the
    /// bar's own, and the shortcut is a `GlobalShortcutRole`.
    package static let paste: CommandID = {
        guard let id = ToolID(AppFeature.pastePlain.rawValue),
              let command = CommandID(tool: id, name: "paste")
        else { preconditionFailure("Paste as plain text's command is not valid") }
        return command
    }()

    package static let manifest: ToolManifest = {
        let feature = AppFeature.pastePlain
        guard let command = CommandDescriptor(id: paste, title: feature.rawValue, symbol: feature.symbolName,
                                              surfaces: []),
              let tool = ToolDescriptor(id: paste.tool, name: feature.rawValue, symbol: feature.symbolName,
                                        commands: [command]),
              let shortcut = CapabilityRequest(.hotkey, reason: "Pastes as plain text when you press its shortcut."),
              // It starts without Accessibility: the shortcut is taken at
              // once, and the first press asks.
              let keys = CapabilityRequest(
                  .keystrokes,
                  reason: "Presses Paste and Match Style in the app in front, or types the paste for you.",
                  startsWithoutGrant: true),
              let read = CapabilityRequest(.clipboardRead, reason: "Reads what you copied, to paste its text."),
              let say = CapabilityRequest(.notify, reason: "Beeps when it cannot paste."),
              let manifest = ToolManifest(
                  tool: tool, group: feature.group, capabilities: [shortcut, keys, read, say],
                  preferences: [
                      PreferenceDeclaration(key: DefaultsKey.pastePlainEnabled, default: .bool(false)),
                      PreferenceDeclaration(key: DefaultsKey.pastePlainShortcut,
                                            default: .string(GlobalShortcut.pastePlainDefault.storageValue)),
                  ],
                  activation: [.onLaunch, .onCommand], enabledBy: DefaultsKey.pastePlainEnabled)
        else { preconditionFailure("Paste as plain text's manifest is not valid") }
        return manifest
    }()
}
```

Read it against Task 1's file once more. What each member lost went to a place Tasks 1 to 4 built and tested:

- `syncWithPreferences()` is `ToolHost.sync`: `start()` when installed and switched on, `stop()` otherwise. Both set `shortcutRegistrationFailed` exactly as the two branches of the old function did.
- `suspend()` is `ToolHost.suspend`, which calls `stop()`.
- `performPastePlain()` is `pastePlainText()`, in the same order: the grant, then the read, then the paste. `environment.isTrusted()` is `services.keystrokes.refusal`; the beep and the prompt go through `services`.
- `pastePlain(_:)` kept its comment and its two steps. The two closures that let go of the key and took it back are inside `keystrokes.paste`.
- `savedShortcut` is the host's: `HotkeyBindings` reads the role's saved combination.

If the compiler asks for `required` on `init(services:)`, the class has stopped being `final`: put `final` back.

In `Services/Platform/Broker/HotkeyAccess.swift`, the id moves in. This is the same commit that removes `QuickToolHotkey(id: 10)` from the service, above:

```swift
        /// The app's own. No role has a key here yet. A role's id moves in
        /// with the tool that holds it, in the same change, so no id is
        /// ever made in two places (`hotkey_ids_are_unique`).
        @MainActor package static let live = Environment(makeHotkey: { _ in nil },
                                                         savedShortcut: { $0.savedShortcut })
```
becomes
```swift
        /// The app's own. A role's hotkey id is spelled here and nowhere
        /// else. It moves in with the tool that holds the role, in the same
        /// change, so no id is ever made in two places
        /// (`hotkey_ids_are_unique`). A role not listed has no key here.
        @MainActor package static let live = Environment(
            makeHotkey: { role in
                switch role {
                // Paste as plain text has had this id since before it was a tool.
                case .pastePlain: return QuickToolHotkey(id: 10)
                default: return nil
                }
            },
            savedShortcut: { $0.savedShortcut })
```

In `Services/Platform/BundledTools.swift`:

```swift
    package static let all: [any BundledTool.Type] = [PortManagerService.self, URLCleanerService.self]
```
becomes
```swift
    package static let all: [any BundledTool.Type] = [PortManagerService.self, URLCleanerService.self,
                                                      PastePlainService.self]
```

- [ ] **Step 4: Point the Settings section at the tool**

In `UI/Settings/PastePlainSettingsSection.swift`:

```swift
    @ObservedObject private var pastePlain = PastePlainService.shared
```
becomes
```swift
    @ObservedObject private var pastePlain = ToolHost.shared.tool(PastePlainService.self)
```

and both occurrences of

```swift
                    PastePlainService.shared.syncWithPreferences()
```
(one under the switch, one in the shortcut row, at different indents) become
```swift
                    ToolHost.shared.sync(PastePlainService.self)
```

The `@AppStorage(Preferences.pastePlainEnabled)` line stays: the manifest declares that key. `ShortcutPreferenceRow` binds the shortcut itself; it is the shared row every feature uses, and stays as it is.

- [ ] **Step 5: Point the command bar at the tool**

In `Services/CommandBar/CommandBarCatalog.swift`, the row keeps its id, title, subtitle, icon, shortcut hint, trouble mark and its delay. Only what runs after the delay changes:

```swift
                run: { _ in afterBeat { PastePlainService.shared.performPastePlain() } }))
```
becomes
```swift
                // Paste as plain text is a tool: its command runs through the registry.
                run: { _ in afterBeat { ToolRegistry.shared.run(PastePlainService.paste) } }))
```

The `if AppFeature.pastePlain.isAvailable` around the row stays. The command can run while the tool's switch is off (`ToolHost.canRun` asks the hub, not the switch), which is the row's gating today.

- [ ] **Step 6: Hand the tool to the host in `FeatureRuntime` and in the uninstall**

In `Services/FeatureRuntime.swift`, three edits.

```swift
        case .pastePlain: return [.pastePlain]
```
becomes
```swift
        // A tool: the tool host decides whether it runs.
        case .pastePlain: return [.tool(PastePlainService.manifest.id)]
```

Delete the `perform` arm:

```swift
        case .pastePlain: PastePlainService.shared.syncWithPreferences()
```

In `FeatureBindingAction`:

```swift
    case pastePlain, finderCutPaste, finderRename, shelf, diskImageInstaller
```
becomes
```swift
    case finderCutPaste, finderRename, shelf, diskImageInstaller
```

In `Services/SelfUninstall.swift`, in `suspend(_:)`. The `pastePlain` case of `InputInterceptor` stays: the teardown still lets go of this key, in the same place in its order.

```swift
        case .pastePlain: PastePlainService.shared.suspend()
```
becomes
```swift
        // A tool: the tool host stops it, which gives its shortcut back.
        case .pastePlain: ToolHost.shared.suspend(PastePlainService.manifest.id)
```

`App/AppDelegate.swift` is not edited.

- [ ] **Step 7: Run everything**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard --test_arg=--suite=platform --test_arg=--suite=features --test_arg=--suite=command-bar --test_arg=--suite=repository`
Expected: PASS. Every `PastePlainTests` expectation written in Task 1 passes unchanged against the tool.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `grep -rn "PastePlainService\.shared\|performPastePlain\|PastePlainService(environment" apps/desktop/vitruvian/Sources apps/desktop/vitruvian/Tests`
Expected: no output.

Run: `grep -rn "QuickToolHotkey(id: 10)" apps/desktop/vitruvian/Sources`
Expected: one line, in `Services/Platform/Broker/HotkeyAccess.swift`.

Run: `git diff --stat 41aaf8fb0 -- apps/desktop/vitruvian/Sources/Vitruvian/Services/TransientPaste.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/ShortcutCapture.swift apps/desktop/vitruvian/Sources/Vitruvian/App/AppDelegate.swift`
Expected: no output.

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest`
Expected: PASS, every suite reporting.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 8: Commit**

Append to the stage C entry in `UPSTREAM.md`:

```markdown
  - `Services/QuickTools/PastePlainService.swift`: Paste as plain text is a tool. It has a manifest and one command, is built by the tool host with the services that manifest allows, and holds its shortcut, asks for Accessibility, reads the clipboard, presses a menu item, pastes and beeps only through the broker. Its singleton, its hotkey and the `Environment` this entry added above are gone. Hotkey id 10 is now made in `Services/Platform/Broker/HotkeyAccess.swift`.
  - `Services/CommandBar/CommandBarCatalog.swift`: the "Paste as plain text" row runs the tool's command through the registry, after the same delay. It keeps its id.
  - `Services/FeatureRuntime.swift`: Paste as plain text's arm hands it to the tool host; its own binding action is gone.
  - `Services/SelfUninstall.swift`: a full uninstall lets go of Paste as plain text's shortcut through the tool host.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/QuickTools/PastePlainService.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/HotkeyAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/BundledTools.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/FeatureRuntime.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/SelfUninstall.swift apps/desktop/vitruvian/Tests/PastePlainTests.swift apps/desktop/vitruvian/Tests/URLCleanerTests.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/Tests/FeatureRuntimeTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): Paste as plain text reaches the system only through the broker"
```

---

### Task 7: Hold Paste as plain text's files to the broker in the lint

**Files:**
- Modify: `bazel/source_lints.py` (`MIGRATED_TOOLS`)
- Modify: `Tests/mutation_checks.py`, `UPSTREAM.md`

**Interfaces:**
- Produces: a third row in `MIGRATED_TOOLS`; five entries in `MUTATIONS`.

One thing changes in the lint: a row. Nothing is added to `TOOL_FILE_SINGLETONS` or to `BROKERED`, and `hotkey_ids_are_unique` is not edited: it already reads `QuickToolHotkey(id: 10)` where Task 6 put it. The tool's two files name `ToolHost` and `L10n`, which are on the list already.

- [ ] **Step 1: Add the row**

In `bazel/source_lints.py`, `MIGRATED_TOOLS` gains, after the `urlCleaner` row:

```python
    "pastePlain": {
        "files": [
            "Sources/Vitruvian/Services/QuickTools/PastePlainService.swift",
            "Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift",
        ],
        "types": ["PastePlainService"],
        # The manifest also declares `pastePlainShortcut`; the view that
        # binds it is the shortcut row every feature shares, which is not
        # one of these files.
        "keys": ["pastePlainEnabled"],
    },
```

Three files that serve the feature are not in the row, and Task 8 says so in the spec. `UI/Settings/ClipboardSettings.swift` is clipboard history's page; all it holds of this tool is the `if` that shows the section. `Core/QuickTools/QuickToolsSupport.swift` holds `matchStyleEquivalent` beside the other quick tools' helpers. `Services/CommandBar/CommandBarCatalog.swift` holds the hand-built row, which runs the command through the registry.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/bazel/source_lints.py`

Run: `bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 2: Prove the rules see the app**

One at a time, make each change, run `bazel test //apps/desktop/vitruvian:source_lints_test --test_output=errors` and confirm it FAILS naming the line. Undo each by reversing the edit by hand (not with `git checkout` or `git stash`), and confirm `git diff --stat -- <file>` prints nothing:

1. In `PastePlainService.swift`, add `_ = NSPasteboard.general` inside `stop()`. Expected: "reaches the clipboard directly".
2. In `PastePlainService.swift`, add `_ = Permissions.shared` inside `stop()`. Expected: "names the singleton Permissions".
3. In `PastePlainSettingsSection.swift`, add `@AppStorage(Preferences.clipboardHistoryEnabled) private var stray: Bool` under the other one. Expected: "binds the preference clipboardHistoryEnabled".
4. In `Services/Platform/Broker/KeystrokesAccess.swift`, add `_ = PastePlainService.manifest` inside `paste`. Expected: "names the tool type PastePlainService".
5. In `PastePlainService.swift`, add `private let spare = QuickToolHotkey(id: 10)` under `services`. Expected: two failures, "reaches a global hotkey directly" and "both take hotkey id 10". The second is the proof that the id is still watched in its new home.

Put the five failing outputs in the report.

- [ ] **Step 3: Plant five regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of `MUTATIONS` (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("a capability is used without the macOS grant it rides on", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift",
     "        if let missing = capability.ridesOn.first(where: { !environment.isGranted($0) }) {\n            return .notGranted(missing)\n        }\n",
     "",
     "a capability that rides on a macOS grant is refused without it"),
    ("the host waits for a grant the tool said it starts without", "platform",
     "Sources/Vitruvian/Core/Platform/ToolManifest.swift",
     "        capabilities.filter { !$0.startsWithoutGrant }.flatMap(\\.capability.ridesOn)\n",
     "        capabilities.flatMap(\\.capability.ridesOn)\n",
     "Accessibility false: a tool that needs it waits, and a tool that says it starts without it starts"),
    ("a paste presses the tool's own Command-V shortcut", "clipboard",
     "Sources/Vitruvian/Services/Platform/Broker/KeystrokesAccess.swift",
     "                      { released = hotkeys.release(of: tool, where: { $0.isStandardPasteCommand }) },\n",
     "                      {},\n",
     "a shortcut saved as Command-V is let go just before the paste is typed"),
    ("the menu walk presses an item that is switched off", "clipboard",
     "Sources/Vitruvian/Services/Platform/Broker/FrontAppMenu.swift",
     "        if wanted, item.isEnabled { return node }\n",
     "        if wanted { return node }\n",
     "a matching item that is switched off is passed over"),
    ("a press without Accessibility asks every time", "clipboard",
     "Sources/Vitruvian/Services/QuickTools/PastePlainService.swift",
     "                promptedForAccessibility = true\n",
     "",
     "every press after that only beeps, from the shortcut or from the command bar"),
```

Each "before" text must occur exactly once in its file, and must quote the file exactly: if the code differs from this plan, use the code. For each entry: apply it, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=<group> --test_output=errors`, confirm it fails with the sixth field among the messages, undo it, confirm `git diff --stat -- <file>` prints nothing. If a mutation is not detected, stop and report: do not adjust a test to fit.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/Tests/mutation_checks.py`

- [ ] **Step 4: Commit**

Append to the stage C entry in `UPSTREAM.md`:

```markdown
  - `bazel/source_lints.py`: Paste as plain text's two files join `MIGRATED_TOOLS`.
  - `Tests/mutation_checks.py`: five mutations (a capability used without the grant it rides on; the host waiting for a grant a tool starts without; a paste pressing the tool's own shortcut; the menu walk pressing a switched-off item; a press without Accessibility asking every time).
```

```bash
git add apps/desktop/vitruvian/bazel/source_lints.py apps/desktop/vitruvian/Tests/mutation_checks.py apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): hold Paste as plain text's files to the broker in the lint"
```

---

### Task 8: Document, close sub-project 2, and check by hand

**Files:**
- Modify: `AGENTS.md`, `UPSTREAM.md`
- Modify: `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md`
- Modify: `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md` (section 12, the row for sub-project 2)

- [ ] **Step 1: Write the rules down**

In `AGENTS.md`, in the bullet that begins "A feature that has become a tool has a manifest", change "the clipboard, its preferences, a link, a beep or a message, the listening-sockets report, ending a process" to "the clipboard, its preferences, a link, a beep or a message, the listening-sockets report, ending a process, a global shortcut, a paste or a menu press in the app in front".

In the bullet that begins "A tool's background work is in `start()` and `stop()`", replace

```markdown
  calls them: at launch, when the hub installs or removes the tool, and when
  its switch flips. A tool never asks whether it is installed or switched
  on. The run rule is `ToolHost.shouldRun(installed:switchedOn:holdsGrants:)`;
  no capability rides on a macOS grant yet, so its grants clause is tested
  through that function alone. `start()` is called every time the host finds
```
with
```markdown
  calls them: at launch, when the hub installs or removes the tool, when
  its switch flips, when a macOS grant it rides on changes
  (`FeatureRuntime.permissionDidChange`) and when a shortcut recording ends.
  A tool never asks whether it is installed or switched on. The run rule is
  `ToolHost.shouldRun(installed:switchedOn:holdsGrants:)`. A tool must hold
  the grants its capabilities ride on before it starts, unless the request
  says `startsWithoutGrant`: then the host starts it anyway, and each
  operation of that capability is refused with `notGranted` until the grant
  is there. `keystrokes` rides on Accessibility; nothing else rides on a
  grant yet. `start()` is called every time the host finds
```

Directly after the bullet that ends "`source_lints_test` fails on any other.", add:

```markdown
- The broker asks macOS about a grant at the moment of each call
  (`CapabilityBroker.Environment.live`). It does not read `Permissions`,
  whose published values are false all through launch and lag behind a
  change by up to a poll afterwards. A tool that needs a grant for a piece
  of work asks `services.keystrokes.refusal` before it reads or changes
  anything, and has the person asked with `requestGrant()`.
- A tool's shortcut that is a `GlobalShortcutRole` is taken with
  `services.hotkey.bind(role)` in `start()` and given back in `stop()`. The
  role's hotkey id is spelled in `HotkeyBindings.Environment.live` and
  nowhere else; `hotkey_ids_are_unique` reads it there. Such a tool is tied
  to its hub feature, so the key comes back after a shortcut recording
  through `FeatureRuntime.sync`, `ToolHost.sync` and `start()`: it needs no
  line in `ShortcutCapture.end()`.
- `keystrokes.paste` is `TransientPaste`, which is not to be edited to suit
  a tool: its delays are tuned by hand. The paste itself lets go of the
  calling tool's own key when that key is Command-V and takes it again
  after; a tool does not. `pressFrontAppMenuItem(matching:)` takes key
  equivalents (`MenuKeyEquivalent`), never titles. The walk is the host's
  (`FrontAppMenu`); which equivalents count is the tool's.
- `ToolHost.suspend(id)` stops one tool at once, whatever the run rule
  says, for the moments the app lets go of every input it holds
  (`SelfUninstall`). The next `sync` starts it again.
- A tool's section on a Settings page it shares with another feature is a
  view in a file of its own, listed for the tool in `MIGRATED_TOOLS`. The
  page decides whether it shows, and hands it what it may not read for
  itself, such as a grant, as a plain value.
```

- [ ] **Step 2: Bring the spec in line with what was built**

In `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md`:

- Section 5, the table: `capabilities` is "`[CapabilityRequest]`: a `Capability`, a reason, and whether the tool starts without the grants it rides on".
- Section 6, "As built": add that stage C added `CapabilityRequest.startsWithoutGrant` and `ToolManifest.grantsNeededToStart`, which is what "the tool declared it can start without" means in code, and `ToolHost.suspend(id)`. The grant clause of the run rule is reached by a real tool since stage C; Paste as plain text starts without Accessibility and asks at the first press.
- Section 6, "When the host re-decides": add that a change to a grant reaches the host with nothing built for it (`AppDelegate` subscribes to `Permissions`; `FeatureRuntime.permissionDidChange` syncs every feature that declares the grant; a tool's arm is `.tool(id)`), and so does the end of a shortcut recording (`ShortcutCapture.end` syncs every feature that has a `GlobalShortcutRole`).
- Section 7.1, check 3: "is granted" is asked of macOS at the moment of the call, not read from `Permissions`. Say why in one sentence: its values are published a main-queue hop late at launch and lag behind a change by up to a poll.
- Section 7.2, the table:
  - `clipboard.read`: add `readPlainText()`, the plain string, else the words of the RTF or HTML. First needed by Paste as plain text.
  - `hotkey`: `bind(role, onPress, onRegistered)`; `unbind(role)`. A press and "did macOS give the key" are replies handed to `bind`. A tool binds only a role of its own feature. Backed by `HotkeyBindings` over `QuickToolHotkey`, which claims with `SystemShortcutTakeover` itself.
  - `keystrokes`: `refusal`; `requestGrant()`; `paste(text)`; `pressFrontAppMenuItem(matching: key equivalents)`. Backed by `TransientPaste`, `Permissions.requestAccessibility` and `FrontAppMenu`.
- Section 7.2, the notes:
  - `keystrokes.paste`: add that it lets go of the calling tool's own key when that key is Command-V and takes it again once the paste is typed, and that `TransientPaste`'s call to clipboard history's `ignoreNextChange` sits behind it without having moved.
  - `pressFrontAppMenuItem`: it takes key equivalents only. Replace "a list of acceptable titles and key equivalents": the code it replaced never matched a title, on purpose.
- Section 8: the table of files has three rows. Add a sentence: a file that serves a tool and belongs to something else is not in its row. For Paste as plain text those are the Clipboard page (`ClipboardSettings.swift`), the shortcut row every feature shares, `QuickToolsSupport.swift` and the command bar's hand-built row.
- Section 10, by hand, Paste as plain text: replace the list with the fifteen checks of Step 5 below, in a sentence each. Add that `TransientPaste` has no unit test: its guarantee in this sub-project is that the file did not change.
- Section 11: mark stage C built. In its row, replace "`Permissions` in place before the host's first decision at launch" with "the broker asks macOS about a grant at each call, so nothing waits on `Permissions`". Its capabilities are `hotkey` and `keystrokes`; it also added `readPlainText` to `clipboard.read`. In the paragraph that lists what stage B left: `TransientPaste`'s `ignoreNextChange` is done (it sits behind `keystrokes.paste`); the rest still wait for the first tool that needs them.
- Section 13: add that the stage C plan is `docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-c.md`, and that it changes eight details of this spec, listed in its decisions table.

- [ ] **Step 3: Check the done-when list, item by item, against the code**

Section 1 of the spec lists five conditions. Check each as below and write the result under the list, in a short paragraph headed "As built, checked on <date>". Mark each **met** or **not met**. Do not mark one met on a promise.

| # | Condition | How to check | What to write |
|---|---|---|---|
| 1 | Each of the three has a manifest, registered at launch | `BundledTools.all` lists three types; `Sources/Vitruvian/main.swift` calls `BuiltinTools.install()`; `ToolBrokerTests.manifestsAgree` passes | Met, if all three hold. |
| 2 | In their files nothing touches a sensitive service except through the broker, and a lint proves it | `MIGRATED_TOOLS` has three rows; `source_lints_test` passes; the five failures of Task 7 Step 2 were seen | Met for the files in the rows. Name the files outside them (section 8, as edited in Step 2). |
| 3 | Their arms are gone from `FeatureRuntime`, their lines from the quit list | `grep -n "portManager\|urlCleaner\|pastePlain" Sources/Vitruvian/Services/FeatureRuntime.swift`; `grep -n "PortManager\|URLCleaner\|PastePlain" Sources/Vitruvian/App/AppDelegate.swift` | Met, with what the greps show said plainly: the URL cleaner's and Paste as plain text's arms are `.tool(id)`; the Port manager's is `[]`, because it has nothing to start; Paste as plain text never had a quit line; `SelfUninstall` keeps one line for it, which calls the host. |
| 4 | Their existing tests pass unchanged, and the new ones pass | the full test run of Step 4; `git log --stat` over `Tests/` for the three stages | Not met as written: say so. Existing expectations were kept, but not every line. List what changed: stage B, one helper's body in `ClipboardFeatureTests`; stage C, one call site in `ClipboardFeatureTests`; and in every stage the two expectations in `ToolPlatformTests` that pin the list of capabilities. |
| 5 | The by-hand checks are recorded with the Mac and macOS version | read the three pull requests (`gh pr list --state all --search "vitruvian broker"`, then `gh pr view <n>`) | Met only for the stages whose pull request holds the record today. Stage C's checks are run in Step 5 and recorded in Step 6; until then, write "not yet". |

Then, in `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`, section 12, the row for sub-project 2, replace the last cell

```markdown
Three features have manifests and reach services only through the broker. Spec: `2026-10-09-vitruvian-broker-and-bundled-tools-design.md`
```
with
```markdown
Three features have manifests and reach services only through the broker. Stage A (built): the manifest, the tool interface, the host, the broker and its two lints; the Port manager. Stage B (built): the host starts, stops and runs tools, and the broker watches the clipboard; the URL cleaner. Stage C (built): a global shortcut and keystrokes behind the broker, the first capability that rides on a macOS grant; Paste as plain text. Spec: `2026-10-09-vitruvian-broker-and-bundled-tools-design.md`; its section 1 says which of its five conditions are met
```

- [ ] **Step 4: Run everything**

With the display awake and the screen unlocked, from the repository root:

```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
git diff --stat 41aaf8fb0 -- apps/desktop/vitruvian/Sources/Vitruvian/Services/TransientPaste.swift
```

Expected: all pass, every unit suite reports, the build succeeds, and the last command prints nothing.

- [ ] **Step 5: Check by hand**

These steps are done by a person, at a Mac, with the built app. No unit test presses a real key, asks real Accessibility, posts a real keystroke or reads the real clipboard.

Build two copies to compare: this branch, and the commit this stage started from (`41aaf8fb0`). Run one at a time: they share one set of preferences.

```sh
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

For the copy to compare against, run the same build in a second worktree checked out at `41aaf8fb0`, and unzip it to `/tmp/vitruvian-before`.

macOS ties the Accessibility grant to how a copy is signed, so each of the two builds may show its switch on in System Settings › Privacy & Security › Accessibility and still not be trusted. If a build asks for Accessibility while its switch is on, remove its entry with the minus button and add it again. Do this before the checks, so that an untrusted build is not taken for a fault.

In the Features hub, have Paste as plain text, Clipboard history and Text snippets installed. Switch Paste as plain text and clipboard history on. In TextEdit make a new document, choose Format › Make Rich Text, type `Bold words`, make it bold and copy it. This is "the copy" below. The shortcut is Option-Shift-Command-V unless a check says otherwise.

1. **An app with Paste and Match Style.** In the TextEdit document, on a new line set in a large italic font, press the shortcut. `Bold words` arrives large and italic, not bold.
2. **An app without it.** In Terminal, at the prompt, press the shortcut. `Bold words` is typed.
3. **The clipboard holds the original afterwards.** Wait one second after check 2, go back to TextEdit and press plain Command-V. `Bold words` arrives bold.
4. **Clipboard history.** Open it. Note the entries checks 1 to 3 left. Do the same on the copy from before this change. The entries must be the same on both. Record what each build showed.
5. **A copy that is only HTML**, the one branch no unit test runs. In Terminal:
   ```sh
   swift -e 'import AppKit; let p = NSPasteboard.general; p.clearContents(); p.setString("<b>Bold</b> words", forType: .html)'
   ```
   Then press the shortcut at the prompt. `Bold words` is typed.
6. **Without Accessibility.** Make the copy again. In System Settings switch the app's Accessibility off. Press the shortcut in Terminal: the system's prompt or the app's guide appears, once, and nothing is pasted. Press again: a beep, and nothing else. Run "Paste as plain text" from the command bar: a beep.
7. **Granted while the app runs.** Switch Accessibility back on and press the shortcut in Terminal at once, without waiting. `Bold words` is typed. The app was not relaunched.
8. **Taken away while the app runs.** Switch it off again and press: a beep, not a second prompt. Switch it back on.
9. **Recording another shortcut does not kill this one.** In Settings, record a new shortcut for any other feature, for example the color picker. Press Paste as plain text's shortcut in Terminal: it pastes. Start a recording and leave it with Escape: it still pastes.
10. **Its own shortcut re-recorded.** In Settings › Clipboard record Control-Option-Command-P for Paste as plain text. The old combination no longer pastes plain text; the new one does. Settings › Shortcuts shows the new one.
11. **The saved shortcut is plain Command-V.** Record Command-V for it, accepting what the recorder asks. If the recorder will not take it, quit the app, run `defaults write com.vitruviansoftware.vitruvian pastePlainShortcut "command:9"` (the bundle identifier is the one in `Resources/Info.plist`) and open the app again. In Terminal press Command-V: `Bold words` is typed once, not twice and not in a loop. Press it again: once again. In the TextEdit document press Command-V: the words arrive in the surrounding style. Then put the shortcut back to Option-Shift-Command-V, and say in the record which of the two ways set it.
12. **Settings.** On Settings › Clipboard the section is in the same place, with the same header, switch, caption and shortcut row, on both builds. In the Features hub, follow Paste as plain text's link to its settings: the Clipboard page opens with the section outlined. Switch it off: in TextEdit the shortcut is TextEdit's own again, and the command bar's row still pastes plain text, a moment after the bar closes. Switch it on again.
13. **The command bar's row keeps its place.** On the copy from before this change, pin "Paste as plain text" in the command bar or give it a name. Quit. Open this branch's build: the row is where it was, pinned or named as before, and there is one of it.
14. **Removed and installed again.** In the Features hub remove Paste as plain text. The shortcut does nothing of ours, its row is gone from the command bar and its section from Settings. Install it again: it works, with its switch and its shortcut as they were left.
15. **Relaunch, and the neighbours.** Quit the app. In TextEdit the shortcut is TextEdit's own: the key was given back. Open the app and press the shortcut in Terminal as soon as the menu bar icon shows: it pastes, and nothing asks for Accessibility. Then, with a text snippet set up whose text has a line break in it, type its trigger in TextEdit: it expands as before. Snippets share the paste helper, which this stage did not touch.

Record the Mac model, the macOS version and the result of each of the fifteen in the pull request. Say plainly which, if any, were not done. Not checked by hand at all, because it removes the app: the full uninstall, whose one changed line is pinned by `PastePlainTests.runRule` ("a full uninstall lets go of the key at once").

- [ ] **Step 6: Finish the `UPSTREAM.md` entry, commit, and open the pull request**

Add as the first sub-bullet of the stage C entry in `UPSTREAM.md`:

```markdown
  - New files, none with an upstream header: `Core/Platform/MenuKeyEquivalent.swift` (a menu item's key equivalent, as a value), `Services/Platform/Broker/FrontAppMenu.swift` (the walk through the front app's menus), `Services/Platform/Broker/HotkeyAccess.swift` (a role's global shortcut), `Services/Platform/Broker/KeystrokesAccess.swift` (a paste and a menu press), `UI/Settings/PastePlainSettingsSection.swift` (the tool's section of the Clipboard page), with their tests in `Tests/PastePlainTests.swift` and `Tests/ToolBrokerTests.swift`. `Services/TransientPaste.swift` was not changed.
```

```bash
git add apps/desktop/vitruvian/AGENTS.md apps/desktop/vitruvian/UPSTREAM.md docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md
git commit -m "refactor(desktop): document shortcuts, keystrokes and grants behind the broker"
```

Open one pull request. Its description states what was run, on which Mac and macOS version, the fifteen hand checks and their results, and what remains untested: `TransientPaste` has no unit test and did not change; the command bar's row, the Settings section and the real key have only the hand checks; the full uninstall was not run by hand. Its title is a `refactor`: merging it cuts no release. Once the record is in the pull request, set condition 5 of Step 3 to what is then true, in a follow-up commit on the same branch.

---

## What stage C leaves

- **Text snippets still call `TransientPaste` directly.** They are not a tool. When they become one, `keystrokes.paste` needs two things it does not have: a way to delete the typed trigger just before the paste, and a reply when the paste fails. Both are callbacks of `TransientPaste` today.
- **`TransientPaste` has no unit test.** This stage's guarantee is that the file did not change. A test needs a seam in it, which is a change to hand-tuned timing and wants its own review.
- **`Permissions` still publishes a hop late and polls.** The broker no longer reads it. The Settings rows and the command bar's "needs permission" mark still do, so for up to 2.5 seconds after a grant they can say "not granted" while a press already pastes. That was so before this stage.
- **A role's hotkey id moves into `HotkeyBindings.Environment.live` when its feature becomes a tool**, one line each, in the commit that takes the hotkey out of the feature's service.
- **Titles in `pressFrontAppMenuItem`**, commands that take an argument, `storage.set`, a plain stream of clipboard changes, and an observer for a preference changed from outside the app. Each arrives with the first tool that needs it.
- **Sub-project 3's questions, now three.** How a tool in another process answers a `ClipboardRewriteRule` (stage B). How it hears `onPress` and `onRegistered`, which arrive more than once. And who the consent screen asks when a tool says it starts without a grant.
- **The three `AppFeature` cases, the `pastePlain` case of `GlobalShortcutRole`, and the Port manager's lean on the Kill process feature** stay. Removing a case is a later sub-project's.
- **Clipboard history and clipboard auto-clear** keep a timer each, and the Clipboard page stays theirs.
