# Vitruvian Broker (stage B: the URL cleaner, and a host that starts and stops tools) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the URL cleaner onto the broker, so that no file belonging to it touches the clipboard, the saved preferences or an on-screen message except through the broker, and give the tool host the parts stage A left out: starting and stopping a tool, running its commands, and one action in `FeatureRuntime` for every tool.

**Architecture:** The broker gains one watch on the clipboard: one timer, at the URL cleaner's cadence, running only while a tool asks for it. A tool that rewrites copied links hands the broker a rule, and the broker runs the whole look (read, decide, check again, write) as one job on the clipboard lane, as the cleaner does today. The tool host learns which tools exist, decides whether each should run (installed, switched on, grants held), and calls `start` and `stop` to match. `FeatureRuntime` hands a tool to the host with one action. The URL cleaner's service class becomes the tool: it keeps its file and its rules, loses its singleton, its timer and its pasteboard code.

**Tech Stack:** Swift 6 (AppKit, SwiftUI), Bazel with `--config=macos-app`, the app's own `TestSuite` harness, `bazel/source_lints.py`.

**Spec:** `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md` (approved 2026-10-09). This is stage B of its section 11. It follows `docs/superpowers/plans/2026-10-09-vitruvian-broker-stage-a.md`.

All paths are relative to `apps/desktop/vitruvian/` unless they start with `docs/`.

## Decisions this plan makes

The spec's nine decisions stand. These are the ones the code forced while planning. Five change or narrow the spec (1, 2, 3, 4 and 11); Task 8 edits the spec to match.

| # | Decision | Why |
|---|---|---|
| 1 | **Rewriting a copied link is one operation that carries a rule**, `clipboard.rewriteLinks(rule:)`, not the spec's three steps (told of a change, read the text, `rewrite(ifChangeCount:with:)`). The rule is three small functions the broker calls on the clipboard lane in the middle of one look. **Changes the spec.** | Today one job on the lane reads the count, the types, the text and the HTML, decides, checks the count again and writes. Split into three messages it stops being one job, and four things change. Clipboard history, which shares the lane, can read the raw link between two of the steps: when the two timers fire in the same pass with the cleaner first, history shows one entry today and would show two. The text would be read before the types have said yes, so a password or a large promised copy is fetched only to be left alone. Link parsing and the 64 KB markup scan move to the main thread. A look that is waiting when the cleaner is switched off could still write. A function is the smallest thing that keeps all four. |
| 2 | **A rule is the second kind of function that may cross the broker**, beside a completion. Its three functions take and return plain values, are `@Sendable`, and capture no app state. **Changes the spec's rule that only plain values cross.** | A completion is the in-process form of a reply. A rule is the in-process form of a question the host asks the tool and waits for. Stage A already hands a `ProcessScanner` the other way for the same reason: work that cannot run on the main thread. Sub-project 3 must decide how an outside tool answers such a question while the host holds the clipboard lane, or whether outside tools get a slower form. |
| 3 | **The broker does not tell clipboard history to ignore a rewrite.** **Changes the spec**, which says it does and calls that today's code. | It is not today's code: `URLCleanerService` never calls `ignoreNextChange`. History records the cleaned link as a copy of its own. Telling it to ignore the change would make the cleaned link vanish from history, and the copy with it when history had not yet looked. |
| 4 | **`storage` hands out a reader**, `storage.reader()`, a `Sendable` value with `value(for:)`. There is no `set`. **Narrows the spec.** | The cleaner reads its rules on the clipboard lane, at the moment a link is about to be cleaned, and must keep doing so. The check happens when the reader is handed out, as with stage A's scanner. Nothing in the cleaner writes a preference: its views bind them with `@AppStorage`. An operation is added when a tool needs it. |
| 5 | **No plain stream of clipboard changes.** `clipboard.read` is `readText()` only. | The cleaner's watch is the rule-carrying one of decision 1. A stream with no user is a stream with no test. |
| 6 | **`clipboard.write` gains `writeLink`**, and the cleaner declares five capabilities: `storage`, `clipboard.read`, `clipboard.rewrite`, `clipboard.write`, `notify`. | The Copy buttons write a link as text and as a URL, signed as the app's own, and return the count the watch then compares against. Stage A's `write` does none of the three. The command-bar row says what it did in the heads-up panel, which is `notify.hud`. |
| 7 | **One timer, one look per watching tool per tick.** The broker's checks run when a watch starts, not at every look. | Each tool has its own "last count I saw" and its own rule. With one tool this is exactly today's work per tick. The host stops a tool that is removed in the hub, so a per-look check would only add a defaults read every 0.8 seconds. |
| 8 | **The host is told when a tool's switch flips; nothing watches the defaults.** Views call `ToolHost.shared.sync(X.self)`; the command bar's toggle rows already call `FeatureRuntime.sync`. | Each caller tells the service today, at the same moment. An observer would also fire for a settings restore and for `defaults write`, which do not re-sync today. |
| 9 | **The host calls `start()` every time it finds a tool should run**, so `start()` must be safe to call twice. | `syncWithPreferences()` did the same, and the cleaner's `start` already is. |
| 10 | **The run rule's third clause (every grant held) is written and not reached.** | No stage B capability rides on a grant, so no test can build a tool that lacks one. Its test arrives in stage C with `keystrokes`. |
| 11 | **`BuiltinTools` keeps registering every hub feature.** For a feature that has a manifest it registers the manifest's descriptor and wires each command to the host. **Changes the spec's wording** ("`BuiltinTools` stops registering a tool the host owns"). | Two existing tests pin that `BuiltinTools.install` alone registers every feature under the hub's name, and that the registry holds the manifest's descriptor. Registering in one place also keeps the registration order. |
| 12 | **The cleaner has one command, `urlCleaner/cleanClipboard`, and it asks for no surface.** The command bar's `action.cleanURL` row stays hand-built, keeps its id, title, keywords and icon, and runs the command through `ToolRegistry`. | A command that asked for the command bar would get a second row, `tool.urlCleaner/cleanClipboard`, beside the first. A command with no surface is listed nowhere and can still be run. |
| 13 | **`selection.cleanLink` stays a hand-built row that calls two methods on the tool**, `clean(_:)` and `copy(_:)`. It is not a command. | Its whole point is the text that was selected when the bar opened, and a command takes no argument in this sub-project. |
| 14 | **`FeatureBindingAction` gains `tool(ToolID)` and stops being `CaseIterable`.** The Port manager's arm stays `[]`. | A case with a value cannot be listed automatically, and nothing reads the list. A test pins that the Port manager binds nothing, and its manifest says `onShown`, not `onLaunch`. |
| 15 | **The Port manager's `start` and `run` do nothing, and `canRun` says no.** They are written out, not defaulted in the protocol. | A default would let the next tool forget `run` and fail silently. |
| 16 | **Task 1 gives today's `URLCleanerService` an `Environment`**, and Task 6 removes it again. | Decision 8 of the spec: tests first. The timer path and `copy()` reach `NSPasteboard.general` and a real timer; without a seam nothing can pin them before the move. |
| 17 | **Not in stage B:** merging clipboard history's or auto-clear's timer into the watch; `storage.set`; commands with arguments; a tool that may start without its grant; removing the `urlCleaner` case from `AppFeature`. | Each is another feature's change, or has no user yet. |

Three things the code does today that this plan keeps and does not fix:

- Clipboard history and the cleaner each have a 0.8 second timer. Whichever fires first after a copy goes first. When history goes first it records the raw link, and the cleaned one a tick later: two entries. Reading the code, that is the usual order when both are switched on at launch, because history's timer is created first. This was read, not run. The spec's hand check says "one entry, not two"; Task 8 compares against the build before this change instead.
- After `copy()` the cleaner settles on the change count it read before it signed the copy as the app's own. If signing moves the count, the next tick looks at the link once more. A cleaned link has nothing left to take out, so nothing shows.
- `clean()` and `copy()` do not ask whether the feature is installed in the hub. Every caller is behind the hub's switch, and the app closes a cleaner view when its feature is removed, so nothing reaches them uninstalled. After the move the broker does ask: uninstalled, `copy()` is refused and `clean()` uses the built-in rules alone. This is the one place a line of today's code behaves differently, and it is not pinned by a test on purpose. A person could meet it only in the instant between removing the feature and its view closing.

## Global Constraints

- The code in this plan was written against the branch head `87cf3b1c1` (`refactor/vitruvian-broker-stage-b`, which holds stage A) and has not been compiled. Where it does not compile or does not match the file, make the smallest change that keeps its meaning and record it as a deviation.
- Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header.
- Every change to a file whose line 2 says `Copyright (C) 2026 Vorssaint`, test files included, is named in `UPSTREAM.md` under "Modifications" in the same commit. Task 1 creates one entry, `- **<date>**: Tool platform, the broker, stage B (...)`, and later tasks append sub-bullets. Check line 2 of each file you change; do not trust a list.
- Module order is `Core <- Design <- Services <- UI <- App`. All of them and the tests build in Swift 6 mode. What another module uses is `package`. Every initializer is written out.
- **Nothing a user can see changes.** No new string. No new command, tile or row. Same timing: the clipboard is looked at every 0.8 seconds with a tolerance of 0.25, from a timer on the main run loop in the common modes, started at the moment the cleaner is switched on.
- **Nothing crosses the broker that could not be written as JSON**: no `NSPasteboard`, `CGEvent`, view type, or closure that captures app state. Two in-process forms are the exceptions. A completion closure the tool passes in is a reply. A `ClipboardRewriteRule` is a question the host asks the tool in the middle of one look: its functions take and return plain values, are `@Sendable`, and capture nothing but a `StorageReader`.
- Under `Services/Platform/Broker/` no file names a tool, in code. In a migrated tool's files no code names a service. Task 7 adds the URL cleaner to both lints.
- The URL cleaner's existing tests (`Tests/ClipboardFeatureTests.swift` near line 121, `Tests/RepositoryFeatureTests.swift`) pass with their expectations untouched. One helper's body changes in Task 6 because the function it called moves; the plan quotes before and after.
- Tests are behavioural. No test reads a source file as text, reads or writes the real clipboard, or waits for a timer. A clipboard in a test is `NSPasteboard.withUniqueName()`, released at the end.
- Three rules of the test target that this plan's tests must obey:
  - A defaults suite is opened with a name spelled as a literal on the line above (`let domain = "com.vitruviansoftware.vitruvian.tests.…"`). `PreferenceNamespaceTests` fails on a computed name.
  - A type declared in a test, nested ones included, is not named like a production type (`test_types_do_not_shadow_real_ones`).
  - A test enum has one `static func run`, reached from `Tests/TestGroups.swift` (`TestRegistrationContract`).
- The test module defaults to the main actor. A fake that a `@Sendable` closure captures is a `nonisolated final class …: @unchecked Sendable` that only the test's own thread touches, as `PortManagerRefreshTests.Processes` is.
- `UserDefaults` is not `Sendable` in this SDK. Where a `@Sendable` closure needs one, bind it first with `nonisolated(unsafe) let`, as `MouseAppExceptions` does, and say in a comment that it is safe to use from any thread.
- `Tests/mutation_checks.py` quotes exact source text. After editing it or any `.py` or `BUILD` file, run `bazel run //tools/format -- <path>`.
- Build and test through Bazel only, from the repository root, one command at a time:
  ```sh
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest
  ```
  One suite: add `--test_arg=--suite=platform` (repeat the flag for several). The cleaner's own tests are in `clipboard`.
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren 2>/dev/null)"
  ```
  Put this in the same command as the commit.
- Commit titles: `refactor(desktop): ...` for every task. Nothing here changes what a release build does.

## Review Focus

Failure modes most likely to reach a user. Each has a test in the task named, except where it says by hand.

1. **A copied link is cleaned late, twice, or not at all.** The timer's interval, tolerance and start moment, the first look that only notes where the clipboard stands, and the count the watch adopts after its own rewrite must all be today's. (Tasks 1, 4 and 6; the real timer by hand in Task 8.)
2. **The cleaner rewrites something it must leave alone**: a picture, a file, a secret, several items, a link whose HTML says more than the link, a copy another app replaced while the cleaner was deciding. (Tasks 1 and 3)
3. **Cleaning goes on after it is switched off or removed in the hub, or does not start at launch.** (Tasks 1, 5 and 6; launch by hand in Task 8.)
4. **Clipboard history records a copy differently.** The whole look must stay one job on the clipboard lane. (Task 3 keeps it one function; Task 4 asserts one lane job per tick; by hand in Task 8.)
5. **The Settings page and the menu panel show different states.** Both must observe one instance. (Task 6; by hand in Task 8.)
6. **A command-bar row moves, doubles, or stops working.** `action.cleanURL` and `selection.cleanLink` keep their ids. (Tasks 5 and 6; the rows themselves by hand in Task 8: no unit test builds the bar's action rows.)
7. **A refused call does work anyway.** (Tasks 2, 3 and 4)

---

### Task 1: Pin what the URL cleaner does today

**Files:**
- Modify: `Sources/Vitruvian/Services/URLCleanerService.swift`
- Create: `Tests/URLCleanerTests.swift`
- Modify: `Tests/TestGroups.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `GeneralPasteboardAccess`, `URLCleaning`, `Preferences`.
- Produces: `URLCleanerService.Environment` (`defaults`, `lane`, `main`, `pasteboard`, `every`) with `.live`, and `URLCleanerService.init(environment:)`. `pollPasteboard` gains a last parameter, `defaults:`. `URLCleanerTests.CleanerRig`, `URLCleanerTests.bench(_:)`, `URLCleanerTests.signingMovesTheCount()`.

Nothing the cleaner does changes in this task. It only stops reaching for `UserDefaults.standard`, `GeneralPasteboardAccess.shared`, `NSPasteboard.general`, `DispatchQueue.main` and `Timer` by name, so a test can stand in for each. The seam lasts five commits: Task 6 replaces it with `ToolServices`.

What each line of today's file does, and where it ends up. This table is the contract for the whole stage.

| Today, in `URLCleanerService` | After stage B |
|---|---|
| `syncWithPreferences()`: installed in the hub and switched on, then `start()`, else `stop()` | `ToolHost.shouldRun` and `ToolHost.sync` (Task 5) |
| `start()`: a timer every 0.8 s, tolerance 0.25, main run loop, common modes; does nothing if one is running | `ClipboardWatcher.start(for:)` (Task 4), called from the tool's `start()` |
| `baselinePasteboard()`: one read of the change count on the lane, adopted on the main thread | `ClipboardWatcher.baseline` (Task 4) |
| `cleanClipboardIfNeeded()`: skip while a look is in flight; one lane job per tick; adopt the count it answers; publish what was cleaned | `ClipboardWatcher.look` (Task 4); publishing stays in the tool |
| `pollPasteboard`: count, types, one item, text, clean, HTML, count again, write keeping the source and remote marks | `ClipboardRewrite.poll` (Task 3); the three decisions stay in the tool as a rule |
| `rules`: three saved strings, read on the lane when a link is about to be cleaned | the tool's rule, through a `StorageReader` (Tasks 2 and 6) |
| `copy()`: call off a waiting look; write text and URL; sign as the app's own; raise the count to at least the one read before signing | `ClipboardWatcher.writeLink` (Task 4) |
| `stop()`: stop the timer, call off a waiting look | `ClipboardWatcher.stop(for:)` (Task 4), called from the tool's `stop()` |
| `PollToken` | `ClipboardPollToken` (Task 3) |

- [ ] **Step 1: Write the failing test**

Create `Tests/URLCleanerTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Foundation
import VitruvianCore
import VitruvianServices

/// The URL cleaner over a clipboard and a preference suite of its own, with
/// the clipboard lane, the main queue and the timer run by hand. Nothing here
/// touches the real clipboard, and no test waits for a timer.
@MainActor
enum URLCleanerTests {
    static let dirty = "https://example.com/path?utm_source=news&id=42"
    static let cleaned = "https://example.com/path?id=42"

    static func run(_ suite: TestSuite) {
        runRule(suite)
        automaticClean(suite)
        whatIsLeftAlone(suite)
        stopping(suite)
        copyByHand(suite)
        oneLook(suite)
    }

    /// The cleaner's outside world for one test. Only the test's own thread
    /// touches it.
    nonisolated final class CleanerRig: @unchecked Sendable {
        let board = NSPasteboard.withUniqueName()
        let defaults: UserDefaults
        var lane: [@Sendable () -> Void] = []
        var main: [() -> Void] = []
        /// The tick of each timer that is running, by the order it started.
        var ticks: [Int: () -> Void] = [:]
        var started: [(interval: TimeInterval, tolerance: TimeInterval)] = []
        var stopped = 0

        init() {
            let domain = "com.vitruviansoftware.vitruvian.tests.url-cleaner"
            let defaults = UserDefaults(suiteName: domain)!
            defaults.removePersistentDomain(forName: domain)
            self.defaults = defaults
            board.clearContents()
        }

        func close() {
            defaults.removePersistentDomain(forName: "com.vitruviansoftware.vitruvian.tests.url-cleaner")
            board.releaseGlobally()
        }

        /// Installs or removes the feature in the hub, and flips its own
        /// switch.
        func set(installed: Bool, enabled: Bool) {
            defaults.set(installed, forKey: AppFeature.urlCleaner.availabilityKey)
            defaults.set(enabled, forKey: DefaultsKey.urlCleanerEnabled)
        }

        /// Runs what waits on the lane, then what that handed to the main
        /// queue, until both are empty.
        func settle() {
            while !lane.isEmpty || !main.isEmpty {
                while !lane.isEmpty { lane.removeFirst()() }
                while !main.isEmpty { main.removeFirst()() }
            }
        }

        /// Fires every running timer once, as the run loop would.
        func tick() {
            for key in ticks.keys.sorted() { ticks[key]?() }
        }

        func startTimer(_ interval: TimeInterval, _ tolerance: TimeInterval,
                        _ tick: @escaping @MainActor () -> Void) -> () -> Void {
            let key = started.count
            started.append((interval, tolerance))
            ticks[key] = { MainActor.assumeIsolated { tick() } }
            return { [self] in
                ticks[key] = nil
                stopped += 1
            }
        }

        /// Copies as another app would: one item, its text, and the app's
        /// name when it gives one.
        func copy(_ text: String, source: String? = nil) {
            board.clearContents()
            if let source { board.setString(source, forType: .source) }
            board.setString(text, forType: .string)
        }

        var text: String? { board.string(forType: .string) }
    }

    /// The cleaner over `rig`, and how the app re-decides whether it runs.
    static func bench(_ rig: CleanerRig) -> (cleaner: URLCleanerService, sync: () -> Void) {
        let cleaner = URLCleanerService(environment: .init(
            defaults: rig.defaults,
            lane: { rig.lane.append($0) },
            main: { work in rig.main.append { MainActor.assumeIsolated { work() } } },
            pasteboard: { rig.board },
            every: { rig.startTimer($0, $1, $2) }))
        return (cleaner, { cleaner.syncWithPreferences() })
    }

    /// Whether this Mac's pasteboard counts the app's signature, written
    /// after the copy it signs, as one more change.
    static func signingMovesTheCount() -> Bool {
        let probe = NSPasteboard.withUniqueName()
        defer { probe.releaseGlobally() }
        probe.clearContents()
        probe.setString("a", forType: .string)
        let counted = probe.changeCount
        probe.declareVitruvianSource()
        return probe.changeCount != counted
    }

    /// Installed in the hub and switched on: the cleaner watches. Anything
    /// else: it does not.
    static func runRule(_ suite: TestSuite) {
        for installed in [false, true] {
            for enabled in [false, true] {
                let rig = CleanerRig()
                rig.set(installed: installed, enabled: enabled)
                let (cleaner, sync) = bench(rig)
                sync()
                let wanted = installed && enabled
                suite.expect(cleaner.isRunning == wanted && rig.ticks.count == (wanted ? 1 : 0),
                             "installed \(installed), switched on \(enabled): the cleaner "
                                 + (wanted ? "watches the clipboard" : "leaves the clipboard alone"))
                rig.close()
            }
        }

        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        suite.expect(rig.started.count == 1 && rig.started[0].interval == 0.8 && rig.started[0].tolerance == 0.25,
                     "the cleaner looks at the clipboard every 0.8 seconds, give or take a quarter")
        sync()
        suite.expect(rig.started.count == 1 && cleaner.isRunning,
                     "deciding again while it runs starts no second timer")
        rig.set(installed: true, enabled: false)
        sync()
        suite.expect(!cleaner.isRunning && rig.ticks.isEmpty && rig.stopped == 1,
                     "switching it off stops the timer at once")
        sync()
        suite.expect(rig.stopped == 1, "deciding again while it is off stops nothing twice")
        rig.set(installed: true, enabled: true)
        sync()
        suite.expect(cleaner.isRunning && rig.started.count == 2 && rig.ticks.count == 1,
                     "switching it back on starts a new timer")
    }

    static func automaticClean(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        // A link that was already on the clipboard when the cleaner started.
        rig.copy(dirty)
        let (cleaner, sync) = bench(rig)
        sync()
        suite.expect(rig.lane.count == 1, "starting takes one look, to know where the clipboard stands")
        rig.tick()
        suite.expect(rig.lane.count == 1, "a tick waits for the look before it to answer")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == dirty && cleaner.lastCleaned == nil,
                     "a link copied before the cleaner started is left alone")

        rig.copy(dirty, source: "com.example.reader")
        rig.tick()
        suite.expect(rig.lane.count == 1 && rig.text == dirty,
                     "a tick puts one look on the clipboard lane, and nothing changes until the lane runs it")
        rig.settle()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .URL) == cleaned
                         && rig.board.string(forType: .source) == "com.example.reader",
                     "a copied link with tracking parts is replaced, as text and as a link, and keeps the app it named")
        suite.expect(cleaner.lastCleaned == cleaned && cleaner.lastRemoved == URLCleaning.clean(dirty)?.removed
                         && !cleaner.lastRemoved.isEmpty,
                     "the cleaner says what it cleaned and what it took out")

        // Its own rewrite is not a new copy: a rule that would change the
        // cleaned link is not applied to it.
        rig.defaults.set("id", forKey: DefaultsKey.urlCleanerCustomParameters)
        rig.tick()
        rig.settle()
        suite.expect(rig.text == cleaned, "the cleaner does not look again at what it wrote itself")
        rig.copy("https://example.com/a?id=7&page=2")
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "https://example.com/a?page=2" && cleaner.lastRemoved == ["id"],
                     "a rule saved in Settings is read at the next copy")
        suite.expect(cleaner.clean("https://example.com/b?id=1&page=3")?.url == "https://example.com/b?page=3",
                     "the field in Settings cleans under the saved rules")
    }

    /// What the automatic clean must not touch.
    static func whatIsLeftAlone(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()
        func look() {
            rig.tick()
            rig.settle()
        }

        rig.copy("https://example.com/?id=42")
        var count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && cleaner.lastCleaned == nil,
                     "a link with nothing to take out is left exactly as it was copied")

        rig.copy("not a link ?utm_source=x")
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count, "text that is not a link is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a link beside a picture is the picture's fallback, and is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("secret", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a copy marked as a secret is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("<p>Read <a href=\"\(dirty)\">this</a> and <a href=\"https://other.example/\">that</a></p>",
                            forType: .html)
        count = rig.board.changeCount
        look()
        suite.expect(rig.board.changeCount == count && rig.text == dirty,
                     "a link whose HTML says more than the link is left alone")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .string)
        rig.board.setString("<a href=\"\(dirty)\">\(dirty)</a>", forType: .html)
        look()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .html) == nil,
                     "a link whose HTML only formats it is cleaned, and the formatting goes")

        rig.board.clearContents()
        rig.board.setString(dirty, forType: .URL)
        look()
        suite.expect(rig.text == cleaned && rig.board.string(forType: .URL) == cleaned,
                     "a link copied only as a link, with no text beside it, is cleaned too")
    }

    static func stopping(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()

        rig.copy(dirty)
        rig.tick()
        rig.set(installed: true, enabled: false)
        sync()
        suite.expect(!cleaner.isRunning && rig.ticks.isEmpty && rig.lane.count == 1,
                     "switching the cleaner off while a look waits stops the timer and leaves the look on the lane")
        rig.settle()
        suite.expect(rig.text == dirty && cleaner.lastCleaned == nil,
                     "a look that was waiting when the cleaner was switched off changes nothing")

        rig.set(installed: true, enabled: true)
        sync()
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(cleaner.isRunning && rig.text == dirty,
                     "switched back on, it starts from the clipboard as it is")

        rig.copy(dirty)
        rig.set(installed: false, enabled: true)
        sync()
        rig.tick()
        rig.settle()
        suite.expect(!cleaner.isRunning && rig.text == dirty, "removing the feature in the hub stops it")
    }

    static func copyByHand(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: true)
        let (cleaner, sync) = bench(rig)
        sync()
        rig.settle()
        let manual = "https://example.com/by-hand"

        // A copy by hand while a look waits calls the look off.
        rig.copy(dirty)
        rig.tick()
        cleaner.copy(manual)
        suite.expect(cleaner.lastCleaned == manual,
                     "a copy by hand is the last cleaned link at once, before the clipboard answers")
        rig.settle()
        suite.expect(rig.text == manual && rig.board.string(forType: .URL) == manual
                         && rig.board.string(forType: .source) == Bundle.main.bundleIdentifier,
                     "a copy by hand puts the link on the clipboard as text and as a link, signed as the app's own")
        suite.expect(cleaner.lastCleaned == manual && cleaner.lastRemoved.isEmpty,
                     "the look it called off reports nothing")

        // After its own copy the cleaner settles on the count it read before
        // it signed the copy. Whether signing moves the count is the
        // pasteboard's business; either way the next tick does what it does
        // today.
        let signingMoves = signingMovesTheCount()
        cleaner.copy(dirty)
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == (signingMoves ? cleaned : dirty),
                     "after a copy by hand the cleaner looks at the link again only if signing it moved the clipboard's count")

        rig.set(installed: true, enabled: false)
        sync()
        cleaner.copy(manual)
        rig.settle()
        suite.expect(rig.text == manual && !cleaner.isRunning,
                     "a copy by hand works while automatic cleaning is switched off")
    }

    /// One look at a clipboard, as the lane runs it. `since` is the count
    /// the cleaner last knew; `cancelled` is a look called off before it ran.
    static func look(at board: NSPasteboard, since: Int, cancelled: Bool = false)
        -> (changeCount: Int, cleaned: URLCleaning.Result?)? {
        let token = URLCleanerService.PollToken()
        if cancelled { token.cancel() }
        return URLCleanerService.pollPasteboard(sinceChangeCount: since, token: token, pasteboard: board,
                                                rules: URLCleaning.Rules.none)
            .map { (changeCount: $0.changeCount, cleaned: $0.cleaned) }
    }

    static func oneLook(_ suite: TestSuite) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString(dirty, forType: .string)
        let before = board.changeCount

        let same = look(at: board, since: before)
        suite.expect(same?.changeCount == before && same?.cleaned == nil && board.string(forType: .string) == dirty,
                     "a clipboard that has not changed since the last look is left alone")
        suite.expect(look(at: board, since: before - 1, cancelled: true) == nil
                         && board.string(forType: .string) == dirty && board.changeCount == before,
                     "a look that was called off answers nothing and changes nothing")
        let rewritten = look(at: board, since: before - 1)
        suite.expect(rewritten?.cleaned?.url == cleaned && rewritten?.changeCount == board.changeCount
                         && board.changeCount != before,
                     "a look that rewrites answers with the clipboard's count after the rewrite")
    }
}
```

In `Tests/TestGroups.swift`, the `clipboard` entry runs both:

```swift
            ("clipboard", { ClipboardFeatureTests.run(suite) }),
```
becomes
```swift
            ("clipboard", { ClipboardFeatureTests.run(suite); URLCleanerTests.run(suite) }),
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard`
Expected: a compile failure naming `environment` (`URLCleanerService` has no `init(environment:)`).

- [ ] **Step 3: Give the cleaner its seam**

Replace `Sources/Vitruvian/Services/URLCleanerService.swift` from line 10 (`@MainActor`) to the end of the file with the text below. Lines 1 to 9 (the header and the imports) stay as they are. Every comment that is in the file today is kept where its code is.

```swift
@MainActor
package final class URLCleanerService: ObservableObject {
    package static let shared = URLCleanerService(environment: .live)
    nonisolated private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)

    /// What the cleaner reaches outside itself. The app's is the saved
    /// preferences, the shared clipboard lane, the general pasteboard and a
    /// run-loop timer. A test passes a suite and a pasteboard of its own, and
    /// runs the lane, the main queue and the timer by hand.
    package struct Environment {
        /// Where the hub's switch, the cleaner's own switch and the rules
        /// are saved.
        package var defaults: UserDefaults
        /// Runs work on the clipboard lane, off the main thread.
        package var lane: (@escaping @Sendable () -> Void) -> Void
        /// Hands work from the lane back to the main thread.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        /// The pasteboard to watch, asked for on the lane.
        package var pasteboard: @Sendable () -> NSPasteboard
        /// Starts a repeating tick on the main thread, given its interval
        /// and its tolerance. Calling the result stops it.
        package var every: (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

        package init(defaults: UserDefaults,
                     lane: @escaping (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     pasteboard: @escaping @Sendable () -> NSPasteboard,
                     every: @escaping (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)) {
            self.defaults = defaults
            self.lane = lane
            self.main = main
            self.pasteboard = pasteboard
            self.every = every
        }

        @MainActor package static let live = Environment(
            defaults: .standard,
            lane: { GeneralPasteboardAccess.shared.async($0) },
            main: { work in DispatchQueue.main.async { work() } },
            pasteboard: { .general },
            every: { interval, tolerance, tick in
                let timer = Timer(timeInterval: interval, repeats: true) { _ in
                    // Added to the main run loop below, so it fires on the main thread.
                    MainActor.assumeIsolated { tick() }
                }
                timer.tolerance = tolerance
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            })
    }

    @Published package private(set) var isRunning = false
    @Published package private(set) var lastCleaned: String?
    /// Names the last automatic clean took out, so Settings can say what the
    /// silent rewrite did rather than only that it is running.
    @Published package private(set) var lastRemoved: [String] = []

    /// `cancelled` sits under `lock`, so it is `@unchecked Sendable`.
    package final class PollToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        package init() {}

        package func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        package var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    package struct PollResult {
        package let changeCount: Int
        package let cleaned: URLCleaning.Result?
    }

    private let environment: Environment
    private var stopTimer: (() -> Void)?
    private var lastChangeCount = 0
    private var pollInFlight = false
    private var pollToken: PollToken?

    package init(environment: Environment) {
        self.environment = environment
    }

    package func syncWithPreferences() {
        if AppFeature.urlCleaner.isAvailable(in: environment.defaults),
           environment.defaults[Preferences.urlCleanerEnabled] {
            start()
        } else {
            stop()
        }
    }

    package func clean(_ text: String) -> URLCleaning.Result? {
        URLCleaning.clean(text, rules: Self.rules(in: environment.defaults))
    }

    /// Writes on the shared lane and settles the change count on the main
    /// queue, where the poll compares against it. The caller never waits: the
    /// lane can be wedged behind an app that promised pasteboard content and
    /// stopped answering (issue #887).
    package func copy(_ urlString: String) {
        cancelPoll()
        lastCleaned = urlString
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            let pasteboard = board()
            let changeCount = Self.writeToPasteboard(urlString, to: pasteboard)
            // Unlike a rewrite of what another app copied, this link is ours.
            pasteboard.declareVitruvianSource()
            main {
                guard let self else { return }
                self.lastChangeCount = max(self.lastChangeCount, changeCount)
            }
        }
    }

    package func stop() {
        stopTimer?()
        stopTimer = nil
        cancelPoll()
        isRunning = false
    }

    private func start() {
        guard stopTimer == nil else {
            isRunning = true
            return
        }
        stopTimer = environment.every(0.8, 0.25) { [weak self] in self?.cleanClipboardIfNeeded() }
        isRunning = true
        baselinePasteboard()
    }

    /// Reads the initial change count away from the main thread. It shares the
    /// same serial lane as Clipboard History, so neither service can race
    /// AppKit's pasteboard type cache while starting up.
    private func baselinePasteboard() {
        guard !pollInFlight else { return }
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            guard !token.isCancelled else { return }
            let changeCount = board().changeCount
            main {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning else { return }
                self.lastChangeCount = changeCount
            }
        }
    }

    private func cleanClipboardIfNeeded() {
        guard !pollInFlight else { return }
        let sinceChangeCount = lastChangeCount
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        // UserDefaults is safe to use from any thread.
        nonisolated(unsafe) let defaults = environment.defaults
        environment.lane { [weak self] in
            guard !token.isCancelled else { return }
            let result = Self.pollPasteboard(sinceChangeCount: sinceChangeCount, token: token,
                                             pasteboard: board(), defaults: defaults)
            main {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning, let result else { return }
                self.lastChangeCount = result.changeCount
                if let cleaned = result.cleaned {
                    self.lastCleaned = cleaned.url
                    self.lastRemoved = cleaned.removed
                }
            }
        }
    }

    /// Runs only on GeneralPasteboardAccess. Reading the change count, types
    /// and payload plus any rewrite is one serialized transaction.
    /// `pasteboard` and `rules` are the general pasteboard and the stored
    /// rules, except in the tests, which pass a private pasteboard.
    /// `defaults` is where the stored rules are read when `rules` is nil.
    nonisolated package static func pollPasteboard(sinceChangeCount: Int, token: PollToken,
                                                   pasteboard: NSPasteboard = .general,
                                                   rules: URLCleaning.Rules? = nil,
                                                   defaults: UserDefaults = .standard) -> PollResult? {
        let changeCount = pasteboard.changeCount
        guard !token.isCancelled else { return nil }
        guard changeCount != sinceChangeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        // The types decide before any content is read: a picture or a file
        // is never fetched only to be left alone. Some "copy link" commands
        // put the link on the pasteboard only as a URL, with no text next
        // to it.

        // The rewrite is for a link something was actually taken out of. A
        // copy with nothing to remove is left exactly as the user put it,
        // because writing to the pasteboard discards whatever else the copy
        // carried, and a link the cleaner did not need to touch is the one
        // most likely to come back spelled differently.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard URLCleaning.canRewritePasteboard(types: types),
              // The rewrite writes one item, so a copy of several is left alone.
              pasteboard.pasteboardItems?.count == 1,
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: urlType),
              let cleaned = URLCleaning.clean(text, rules: rules ?? Self.rules(in: defaults)),
              !cleaned.removed.isEmpty,
              !token.isCancelled else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }
        // The rewrite drops the HTML, which is only right when the HTML adds
        // nothing to the link but formatting.
        if types.contains("public.html"),
           !URLCleaning.markupAddsOnlyFormatting(pasteboard.string(forType: .html) ?? "", to: text) {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        // The app the copy named as its source stays named, and a copy from
        // another device stays marked as one, so the clipboard history does
        // not credit the cleaned link to the app in front.
        let rewrittenChangeCount = writeToPasteboard(cleaned.url, source: pasteboard.string(forType: .source),
                                                     remote: types.contains("com.apple.is-remote-clipboard"),
                                                     to: pasteboard)
        return PollResult(changeCount: rewrittenChangeCount, cleaned: cleaned)
    }

    nonisolated private static func rules(in defaults: UserDefaults) -> URLCleaning.Rules {
        URLCleaning.rules(
            globalNames: defaults[Preferences.urlCleanerCustomParameters],
            siteNames: defaults[Preferences.urlCleanerSiteParameters],
            disabledNames: defaults[Preferences.urlCleanerDisabledParameters])
    }

    @discardableResult
    nonisolated private static func writeToPasteboard(_ urlString: String, source: String? = nil, remote: Bool = false,
                                                      to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        pasteboard.setString(urlString, forType: urlType)
        if let source { pasteboard.setString(source, forType: .source) }
        if remote { pasteboard.setData(Data(), forType: .remoteClipboard) }
        return pasteboard.changeCount
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
```

What changed, and nothing else may:

- `shared` is built with `.live`.
- `timer: Timer?` is `stopTimer`, the closure `environment.every` returns. The live `every` makes the same `Timer`, with the same tolerance, on the same run loop and mode.
- `GeneralPasteboardAccess.shared.async { }` is `environment.lane { }`. `DispatchQueue.main.async { }` is `main { }`. `copy()` used `async(_:then:)`, which is a lane job followed by a main-queue hop: the same two calls written out.
- `NSPasteboard.general` is `board()`, asked for on the lane.
- The static `rules` is `rules(in:)`. `pollPasteboard` takes `defaults` last and reads the rules from it only at the point it read them before: when a link is about to be cleaned.

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard --test_arg=--suite=repository --test_arg=--suite=harness`
Expected: PASS. If a `URLCleanerTests` expectation fails, the test is wrong about today's behaviour or the seam changed it: find out which before touching either. Do not adjust an expectation to pass. `harness` holds `PreferenceNamespaceTests`, which checks the new suite name; `repository` holds `TestRegistrationContract`, which checks the new test enum runs.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 5: See one of the new tests fail for the right reason**

In `URLCleanerService.swift`, comment out the line `self.lastChangeCount = result.changeCount`. Run the `clipboard` suite with `--test_output=errors`.
Expected: FAIL, with "the cleaner does not look again at what it wrote itself" among the messages. Put the line back by hand and confirm `git diff --stat -- apps/desktop/vitruvian/Sources/Vitruvian/Services/URLCleanerService.swift` shows only this task's change.

- [ ] **Step 6: Start the `UPSTREAM.md` entry and commit**

At the top of `## Modifications`, add (use the day's date):

```markdown
- **<date>**: Tool platform, the broker, stage B (`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-b.md`):
  - `Services/URLCleanerService.swift`: takes what it reaches outside itself (the saved preferences, the clipboard lane, the pasteboard, its timer) as an `Environment`, so its timer and its copy can be tested. Nothing it does changed.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/URLCleanerService.swift apps/desktop/vitruvian/Tests/URLCleanerTests.swift apps/desktop/vitruvian/Tests/TestGroups.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): pin what the URL cleaner does today"
```

---

### Task 2: Preferences through the broker, and a message on screen

**Files:**
- Modify: `Sources/Vitruvian/Core/Platform/ToolManifest.swift` (`Capability`)
- Create: `Sources/Vitruvian/Services/Platform/Broker/StorageAccess.swift`
- Modify: `Sources/Vitruvian/Services/Platform/Broker/NotifyAccess.swift`, `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift` (`Backings`), `Sources/Vitruvian/Services/Platform/ToolServices.swift`
- Modify: `Tests/ToolPlatformTests.swift`, `Tests/ToolBrokerTests.swift`

**Interfaces:**
- Consumes: `CapabilityBroker.refusal(of:for:)`, `Preference`, `QuickToolHUD`.
- Produces:
  - `Capability.storage`
  - `StorageReader: Sendable`: `value(for:) -> Value`
  - `StorageAccess`: `reader() -> Result<StorageReader, BrokerRefusal>`; `StorageAccess.Backing` (`read`, `undeclaredKey`) with `.live` and `.inert`
  - `NotifyAccess.hud(icon:message:) -> BrokerRefusal?`; `NotifyAccess.Backing.hud`
  - `ToolServices.storage`; `CapabilityBroker.Backings.storage`

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, `manifests(_:)`, one expectation changes on purpose: the stage adds a capability.

```swift
        suite.expect(Set(Capability.allCases.map(\.rawValue)) == ["notify", "open", "processes", "clipboard.write"],
                     "capabilities are named as the platform design names them")
```
becomes
```swift
        suite.expect(Set(Capability.allCases.map(\.rawValue))
                         == ["notify", "open", "processes", "clipboard.write", "storage"],
                     "capabilities are named as the platform design names them")
```

In `Tests/ToolBrokerTests.swift`, add `preferences(suite)` and `messages(suite)` to `run`, and add:

```swift
    /// Saved values a fake reads, and what it was asked. Only the test's own
    /// thread touches it.
    nonisolated final class PreferenceBox: @unchecked Sendable {
        var values: [String: Any] = [:]
        var reads: [String] = []
        var undeclared: [String] = []
    }

    static func preferences(_ suite: TestSuite) {
        let box = PreferenceBox()
        let world = World()
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in world.installed },
                               isGranted: { world.granted.contains($0) },
                               allows: { _, _ in world.allowed },
                               reportUndeclared: { _, capability in world.undeclared.append(capability) }),
            backings: .init(
                notify: .init(beep: {}), open: .init(open: { _ in true }),
                clipboard: .init(write: { _, _ in }), processes: .inert,
                storage: .init(read: { key in
                    box.reads.append(key)
                    return box.values[key]
                }, undeclaredKey: { box.undeclared.append($0) })))
        let declared = ToolManifest(
            tool: ToolDescriptor(id: ToolID("urlCleaner")!, name: "urlCleaner", symbol: "link", commands: [])!,
            group: .tools, capabilities: [CapabilityRequest(.storage, reason: "test")!],
            preferences: [PreferenceDeclaration(key: DefaultsKey.urlCleanerEnabled, default: .bool(false)),
                          PreferenceDeclaration(key: DefaultsKey.urlCleanerCustomParameters, default: .string(""))],
            activation: [.onLaunch], enabledBy: DefaultsKey.urlCleanerEnabled)!

        guard case .success(let reader) = broker.services(for: declared).storage.reader() else {
            suite.expect(false, "a tool that asks for it gets a reader for its preferences")
            return
        }
        suite.expect(reader.value(for: Preferences.urlCleanerEnabled) == false
                         && box.reads == [DefaultsKey.urlCleanerEnabled],
                     "a preference nothing saved reads as its default")
        box.values[DefaultsKey.urlCleanerEnabled] = true
        box.values[DefaultsKey.urlCleanerCustomParameters] = "ref"
        suite.expect(reader.value(for: Preferences.urlCleanerEnabled)
                         && reader.value(for: Preferences.urlCleanerCustomParameters) == "ref",
                     "a tool reads the preferences its manifest declares")
        box.values[DefaultsKey.urlCleanerCustomParameters] = 7
        suite.expect(reader.value(for: Preferences.urlCleanerCustomParameters) == "",
                     "a saved value of another type reads as the default")
        let before = box.reads.count
        suite.expect(reader.value(for: Preferences.urlCleanerSiteParameters) == "" && box.reads.count == before
                         && box.undeclared == [DefaultsKey.urlCleanerSiteParameters],
                     "a preference the manifest does not declare is not read, and is reported as a mistake")

        if case .failure(let refusal) = broker.services(for: manifest([])).storage.reader() {
            suite.expect(refusal == .notDeclared(.storage) && box.reads.count == before,
                         "a tool that did not ask gets no reader")
        } else {
            suite.expect(false, "a tool that did not ask gets no reader")
        }
        world.installed = false
        if case .failure(let refusal) = broker.services(for: declared).storage.reader() {
            suite.expect(refusal == .notInstalled, "a tool removed in the hub gets no reader")
        } else {
            suite.expect(false, "a tool removed in the hub gets no reader")
        }
    }

    static func messages(_ suite: TestSuite) {
        var said: [String] = []
        let broker = CapabilityBroker(
            environment: .init(isInstalled: { _ in true }, isGranted: { _ in true }, allows: { _, _ in true },
                               reportUndeclared: { _, _ in }),
            backings: .init(
                notify: .init(beep: {}, hud: { icon, message in said.append("\(icon): \(message)") }),
                open: .init(open: { _ in true }), clipboard: .init(write: { _, _ in }), processes: .inert))
        suite.expect(broker.services(for: manifest([.notify])).notify.hud(icon: "link", message: "Cleaned") == nil
                         && said == ["link: Cleaned"],
                     "a tool that asks for it can say something on screen")
        suite.expect(broker.services(for: manifest([])).notify.hud(icon: "link", message: "x") == .notDeclared(.notify)
                         && said.count == 1,
                     "a refused message is not shown")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `storage` or `hud`.

- [ ] **Step 3: Name the capability**

In `Core/Platform/ToolManifest.swift`:

```swift
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite: return []
        }
    }
```
becomes
```swift
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"
    /// Read the preferences the tool's manifest declares.
    case storage

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite, .storage: return []
        }
    }
```

- [ ] **Step 4: Write the `storage` capability**

Create `Sources/Vitruvian/Services/Platform/Broker/StorageAccess.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What a tool reads its preferences with. It is handed out after the
/// broker's checks pass, reads on any thread, and reads only the keys the
/// tool's manifest declares.
package struct StorageReader: Sendable {
    let keys: Set<String>
    let read: @Sendable (String) -> Any?
    let undeclared: @Sendable (String) -> Void

    /// The saved value, the registered default, or the preference's own
    /// default when neither is there or the saved value has another type.
    /// A key the manifest does not declare is a mistake in the tool: it is
    /// reported, nothing is read, and the preference's own default comes
    /// back.
    package func value<Value>(for preference: Preference<Value>) -> Value {
        guard keys.contains(preference.key) else {
            undeclared(preference.key)
            return preference.defaultValue
        }
        return read(preference.key).flatMap(Value.init(storedValue:)) ?? preference.defaultValue
    }
}

/// The `storage` capability: the preferences a tool's manifest declares.
/// Reading only. A view of the tool binds the same keys with `@AppStorage`.
@MainActor
package struct StorageAccess {
    package struct Backing {
        /// The saved value or the registered default, on any thread.
        package var read: @Sendable (String) -> Any?
        /// Told the key a tool asked for without declaring it.
        package var undeclaredKey: @Sendable (String) -> Void

        package init(read: @escaping @Sendable (String) -> Any?,
                     undeclaredKey: @escaping @Sendable (String) -> Void = { _ in }) {
            self.read = read
            self.undeclaredKey = undeclaredKey
        }

        @MainActor package static let live = Backing(
            read: { UserDefaults.standard.object(forKey: $0) },
            undeclaredKey: { assertionFailure("a tool read the preference \($0) without declaring it") })

        /// Holds nothing. For tests of other capabilities.
        package static var inert: Backing { Backing(read: { _ in nil }) }
    }

    let gate: () -> BrokerRefusal?
    let keys: Set<String>
    let backing: Backing

    /// A reader, once the checks pass. Ask each time a piece of work starts.
    package func reader() -> Result<StorageReader, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(StorageReader(keys: keys, read: backing.read, undeclared: backing.undeclaredKey))
    }
}
```

`value(for:)` is the body of `UserDefaults.subscript(_: Preference<Value>)` in `Core/Preference.swift`, with the read behind the key check. Read that subscript and keep the two alike.

In `ToolServices.swift`, add:

```swift
    package var storage: StorageAccess {
        StorageAccess(gate: gate(.storage), keys: Set(manifest.preferences.map(\.key)),
                      backing: broker.backings.storage)
    }
```

In `CapabilityBroker.Backings`:

```swift
        package var processes: ProcessesAccess.Backing

        package init(notify: NotifyAccess.Backing, open: OpenAccess.Backing, clipboard: ClipboardAccess.Backing,
                     processes: ProcessesAccess.Backing) {
            self.notify = notify
            self.open = open
            self.clipboard = clipboard
            self.processes = processes
        }

        @MainActor package static let live = Backings(notify: .live, open: .live, clipboard: .live, processes: .live)
```
becomes
```swift
        package var processes: ProcessesAccess.Backing
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
```

`storage` has a default so the three places stage A's tests build `Backings` do not change.

- [ ] **Step 5: Let a tool say something on screen**

Replace the body of `NotifyAccess` in `Broker/NotifyAccess.swift` (the header, the imports and the doc comment stay):

```swift
@MainActor
package struct NotifyAccess {
    package struct Backing {
        package var beep: () -> Void
        package var hud: (_ icon: String, _ message: String) -> Void

        package init(beep: @escaping () -> Void, hud: @escaping (String, String) -> Void = { _, _ in }) {
            self.beep = beep
            self.hud = hud
        }

        @MainActor package static let live = Backing(beep: { NSSound.beep() },
                                                    hud: { QuickToolHUD.show(icon: $0, message: $1) })
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

    /// A short message with a symbol beside it, in the app's own heads-up
    /// panel.
    @discardableResult
    package func hud(icon: String, message: String) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.hud(icon, message)
        return nil
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: PASS.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 7: Commit**

No file with an upstream header changed, so `UPSTREAM.md` gains nothing here.

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ToolManifest.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/StorageAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/NotifyAccess.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolPlatformTests.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift
git commit -m "refactor(desktop): let a tool read its preferences and say something on screen through the broker"
```

---

### Task 3: One look at the clipboard, in the broker

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/ClipboardRewrite.swift`
- Modify: `Sources/Vitruvian/Services/URLCleanerService.swift`
- Modify: `Tests/ToolBrokerTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Produces:
  - `ClipboardRewriteRule: Sendable`: `readsText`, `replacement`, `dropsMarkup`
  - `ClipboardReplacement: Equatable, Sendable`: `text`, `note`
  - `ClipboardPoll: Equatable, Sendable`: `changeCount`, `replaced`
  - `ClipboardPollToken` (today's `PollToken`, moved)
  - `ClipboardRewrite.poll(since:token:rule:pasteboard:) -> ClipboardPoll?`, `ClipboardRewrite.write(_:source:remote:to:) -> Int`
  - `URLCleanerService.rewriteRule(rules:) -> ClipboardRewriteRule`

The look moves word for word. What stays in the cleaner is the three things only it knows: which types it will touch, what a link becomes, and whether dropping the HTML loses anything. They become the rule. The cleaner still owns its timer after this task; `pollPasteboard` becomes a thin adapter, and Task 1's tests and the existing ones in `ClipboardFeatureTests` prove the move changed nothing.

- [ ] **Step 1: Write the failing test**

In `Tests/ToolBrokerTests.swift`, add `import AppKit` under `import Foundation`, add `oneLook(suite)` to `run`, and add:

```swift
    /// What a rule was asked, in order. Only the test's own thread touches
    /// it.
    nonisolated final class RuleLog: @unchecked Sendable {
        var asked: [String] = []
    }

    static func oneLook(_ suite: TestSuite) {
        // Handed to the rules below, which the look calls on this thread.
        nonisolated(unsafe) let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let log = RuleLog()
        func rule(reads: Bool = true, replacement: String? = "clean", drops: Bool = true,
                  during: @escaping @Sendable () -> Void = {}) -> ClipboardRewriteRule {
            ClipboardRewriteRule(
                readsText: { _ in
                    log.asked.append("types")
                    return reads
                },
                replacement: { text in
                    log.asked.append("text \(text)")
                    during()
                    return replacement.map { ClipboardReplacement(text: $0, note: ["n"]) }
                },
                dropsMarkup: { _, text in
                    log.asked.append("markup \(text)")
                    return drops
                })
        }
        func look(_ rule: ClipboardRewriteRule, token: ClipboardPollToken = ClipboardPollToken()) -> ClipboardPoll? {
            log.asked = []
            return ClipboardRewrite.poll(since: -1, token: token, rule: rule, pasteboard: board)
        }
        func copy(_ text: String, html: String? = nil) {
            board.clearContents()
            board.setString(text, forType: .string)
            if let html { board.setString(html, forType: .html) }
        }

        copy("dirty")
        var result = look(rule(reads: false))
        suite.expect(result?.replaced == nil && log.asked == ["types"] && board.string(forType: .string) == "dirty",
                     "a rule that says no to the types is never shown the text")
        result = look(rule(replacement: nil))
        suite.expect(result?.replaced == nil && log.asked == ["types", "text dirty"],
                     "a rule that offers nothing leaves the copy alone")

        copy("dirty", html: "<b>dirty</b>")
        result = look(rule(replacement: nil))
        suite.expect(log.asked == ["types", "text dirty"], "the HTML is not read for a copy the rule leaves alone")
        result = look(rule(drops: false))
        suite.expect(result?.replaced == nil && log.asked == ["types", "text dirty", "markup dirty"]
                         && board.string(forType: .html) != nil,
                     "a rule that will not drop the HTML leaves the copy alone")
        result = look(rule())
        suite.expect(result?.replaced == ClipboardReplacement(text: "clean", note: ["n"])
                         && board.string(forType: .string) == "clean" && board.string(forType: .URL) == "clean"
                         && board.string(forType: .html) == nil && result?.changeCount == board.changeCount,
                     "a replacement is written as text and as a link, and the look answers with the count after it")

        copy("dirty")
        result = look(rule(during: {
            board.clearContents()
            board.setString("other", forType: .string)
        }))
        suite.expect(result?.replaced == nil && board.string(forType: .string) == "other",
                     "a copy that changed while the rule was deciding is not overwritten")

        copy("dirty")
        let token = ClipboardPollToken()
        result = look(rule(during: { token.cancel() }), token: token)
        suite.expect(result?.replaced == nil && board.string(forType: .string) == "dirty",
                     "a look called off while the rule was deciding writes nothing")

        board.clearContents()
        board.writeObjects(["a" as NSString, "b" as NSString])
        result = look(rule())
        suite.expect(result?.replaced == nil && log.asked == ["types"] && board.pasteboardItems?.count == 2,
                     "a copy of several items is not read")
    }
```

The two cases with `during:` are new ground: they change the clipboard, or call the look off, from inside the look, which nothing could do while the decisions were hard-wired. They pin the second count check and the second token check, which Task 1 could not reach.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `ClipboardRewriteRule`.

- [ ] **Step 3: Write the look**

Create `Sources/Vitruvian/Services/Platform/Broker/ClipboardRewrite.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import UniformTypeIdentifiers
import VitruvianCore

/// What a tool wants done to a link somebody copied. The host asks these on
/// the clipboard lane, in the middle of one look at the clipboard, so each
/// takes plain values, answers at once and touches nothing else. Over a
/// process boundary each would be a question the host sends the tool and
/// waits for; here it is a function.
package struct ClipboardRewriteRule: Sendable {
    /// Asked first, with the names of the types on the clipboard and none
    /// of its content. False leaves the copy unread.
    package var readsText: @Sendable (_ types: [String]) -> Bool
    /// Asked with the text. What to put in its place, or nil to leave the
    /// copy as it is.
    package var replacement: @Sendable (_ text: String) -> ClipboardReplacement?
    /// Asked only when the copy also carries HTML, which the rewrite drops:
    /// whether dropping it loses nothing.
    package var dropsMarkup: @Sendable (_ html: String, _ text: String) -> Bool

    package init(readsText: @escaping @Sendable ([String]) -> Bool,
                 replacement: @escaping @Sendable (String) -> ClipboardReplacement?,
                 dropsMarkup: @escaping @Sendable (String, String) -> Bool) {
        self.readsText = readsText
        self.replacement = replacement
        self.dropsMarkup = dropsMarkup
    }
}

/// What a rule puts in place of a copied link.
package struct ClipboardReplacement: Equatable, Sendable {
    package let text: String
    /// Whatever the tool wants handed back with the result. The host does
    /// not read it.
    package let note: [String]

    package init(text: String, note: [String] = []) {
        self.text = text
        self.note = note
    }
}

/// What one look at the clipboard found.
package struct ClipboardPoll: Equatable, Sendable {
    /// The clipboard's change count: after the rewrite, when there was one.
    package let changeCount: Int
    /// What the copy was replaced with, or nil when it was left alone.
    package let replaced: ClipboardReplacement?

    package init(changeCount: Int, replaced: ClipboardReplacement?) {
        self.changeCount = changeCount
        self.replaced = replaced
    }
}

/// Calls off a look that is waiting on the lane, or running. `cancelled`
/// sits under `lock`, so it is `@unchecked Sendable`.
package final class ClipboardPollToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    package init() {}

    package func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    package var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// One look at the clipboard, and the write that may follow it.
package enum ClipboardRewrite {
    private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)

    /// Runs only on the clipboard lane. Reading the change count, the types
    /// and the content, asking the rule, and any rewrite are one job there,
    /// so nothing else that uses the lane sees the clipboard half way.
    /// Nil when the look was called off before it read anything.
    package static func poll(since sinceChangeCount: Int, token: ClipboardPollToken,
                             rule: ClipboardRewriteRule, pasteboard: NSPasteboard) -> ClipboardPoll? {
        let changeCount = pasteboard.changeCount
        guard !token.isCancelled else { return nil }
        guard changeCount != sinceChangeCount else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }

        // The types decide before any content is read. Some "copy link"
        // commands put the link on the pasteboard only as a URL, with no
        // text next to it.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard rule.readsText(types),
              // The rewrite writes one item, so a copy of several is left alone.
              pasteboard.pasteboardItems?.count == 1,
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: urlType),
              let replacement = rule.replacement(text),
              !token.isCancelled else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }
        // The rewrite drops the HTML, so the rule is asked whether that
        // loses anything.
        if types.contains("public.html"),
           !rule.dropsMarkup(pasteboard.string(forType: .html) ?? "", text) {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount else {
            return ClipboardPoll(changeCount: changeCount, replaced: nil)
        }

        // The app the copy named as its source stays named, and a copy from
        // another device stays marked as one, so the clipboard history does
        // not credit the rewritten link to the app in front.
        let rewrittenChangeCount = write(replacement.text, source: pasteboard.string(forType: .source),
                                         remote: types.contains("com.apple.is-remote-clipboard"),
                                         to: pasteboard)
        return ClipboardPoll(changeCount: rewrittenChangeCount, replaced: replacement)
    }

    /// Replaces the clipboard with a link, as text and as a URL, and
    /// answers with the change count after it.
    @discardableResult
    package static func write(_ link: String, source: String? = nil, remote: Bool = false,
                              to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
        pasteboard.setString(link, forType: urlType)
        if let source { pasteboard.setString(source, forType: .source) }
        if remote { pasteboard.setData(Data(), forType: .remoteClipboard) }
        return pasteboard.changeCount
    }
}
```

Put this beside Task 1's `pollPasteboard` and read them line against line. The order of the checks is the same. The three calls into `URLCleaning` are `rule.readsText`, `rule.replacement` (which also carries the "something was taken out" test) and `rule.dropsMarkup`. Nothing else differs.

- [ ] **Step 4: Have the cleaner use it**

In `Sources/Vitruvian/Services/URLCleanerService.swift`, five edits.

1. Delete the line:

```swift
    nonisolated private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)
```

2. Replace the `PollToken` class, from its comment line to its closing brace:

```swift
    /// `cancelled` sits under `lock`, so it is `@unchecked Sendable`.
    package final class PollToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        package init() {}

        package func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        package var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }
```
with
```swift
    /// The token moved to the broker with the look it calls off.
    package typealias PollToken = ClipboardPollToken
```

3. In `copy(_:)`:

```swift
            let changeCount = Self.writeToPasteboard(urlString, to: pasteboard)
```
becomes
```swift
            let changeCount = ClipboardRewrite.write(urlString, to: pasteboard)
```

4. Replace `pollPasteboard`, from its doc comment to its closing brace, with:

```swift
    /// Runs only on GeneralPasteboardAccess. The look itself is the
    /// broker's; this hands it the cleaner's rule and reads its answer.
    /// `pasteboard` and `rules` are the general pasteboard and the stored
    /// rules, except in the tests, which pass a private pasteboard.
    /// `defaults` is where the stored rules are read when `rules` is nil.
    nonisolated package static func pollPasteboard(sinceChangeCount: Int, token: PollToken,
                                                   pasteboard: NSPasteboard = .general,
                                                   rules: URLCleaning.Rules? = nil,
                                                   defaults: UserDefaults = .standard) -> PollResult? {
        // UserDefaults is safe to use from any thread.
        nonisolated(unsafe) let store = defaults
        let poll = ClipboardRewrite.poll(since: sinceChangeCount, token: token,
                                         rule: rewriteRule(rules: { rules ?? Self.rules(in: store) }),
                                         pasteboard: pasteboard)
        return poll.map { poll in
            PollResult(changeCount: poll.changeCount,
                       cleaned: poll.replaced.map { URLCleaning.Result(url: $0.text, removed: $0.note) })
        }
    }

    /// What the automatic clean asks of each copy, on the clipboard lane.
    /// `rules` is read there, each time a link is about to be cleaned, so a
    /// rule changed in Settings holds from the next copy.
    nonisolated package static func rewriteRule(rules: @escaping @Sendable () -> URLCleaning.Rules)
        -> ClipboardRewriteRule {
        ClipboardRewriteRule(
            // The types decide before any content is read: a picture or a
            // file is never fetched only to be left alone.
            readsText: { URLCleaning.canRewritePasteboard(types: $0) },
            // The rewrite is for a link something was actually taken out of. A
            // copy with nothing to remove is left exactly as the user put it,
            // because writing to the pasteboard discards whatever else the copy
            // carried, and a link the cleaner did not need to touch is the one
            // most likely to come back spelled differently.
            replacement: { text in
                guard let cleaned = URLCleaning.clean(text, rules: rules()),
                      !cleaned.removed.isEmpty else { return nil }
                return ClipboardReplacement(text: cleaned.url, note: cleaned.removed)
            },
            // The rewrite drops the HTML, which is only right when the HTML adds
            // nothing to the link but formatting.
            dropsMarkup: { URLCleaning.markupAddsOnlyFormatting($0, to: $1) })
    }
```

5. Delete `writeToPasteboard`, from `@discardableResult` to its closing brace.

If the compiler says `URLCleaning.Rules` is not `Sendable` where the closure captures `rules`, add `, Sendable` to its declaration in `Core/URLCleaning.swift` (both of its maps are value types, so the conformance is free) and log that file in `UPSTREAM.md` with this task.

- [ ] **Step 5: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=clipboard`
Expected: PASS, with every `URLCleanerTests` and `ClipboardFeatureTests` expectation untouched. A failure in either means the move changed the look: fix `ClipboardRewrite.poll`, not a test.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 6: Commit**

Append to the stage B entry in `UPSTREAM.md`:

```markdown
  - `Services/URLCleanerService.swift`: one look at the clipboard and the write that follows it moved, word for word, to `Services/Platform/Broker/ClipboardRewrite.swift`. The cleaner hands the look its three decisions (which types it touches, what a link becomes, whether the HTML may go) as a rule.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker/ClipboardRewrite.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/URLCleanerService.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): move one look at the clipboard into the broker"
```

---

### Task 4: The broker's watch on the clipboard

**Files:**
- Create: `Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift`
- Modify: `Sources/Vitruvian/Core/Platform/ToolManifest.swift` (`Capability`)
- Modify: `Sources/Vitruvian/Services/Platform/Broker/ClipboardAccess.swift`, `Sources/Vitruvian/Services/Platform/Broker/CapabilityBroker.swift`, `Sources/Vitruvian/Services/Platform/ToolServices.swift`
- Modify: `Tests/ToolPlatformTests.swift`, `Tests/ToolBrokerTests.swift`, `Tests/URLCleanerTests.swift` (the rig)

**Interfaces:**
- Consumes: `ClipboardRewrite`, `ClipboardRewriteRule`, `ClipboardPollToken`, `GeneralPasteboardAccess`.
- Produces:
  - `Capability.clipboardRead`, `Capability.clipboardRewrite`
  - `ClipboardWatcher` (`@MainActor`): `Environment` (`lane`, `main`, `pasteboard`, `every`) with `.live` and `.inert`; `interval`, `tolerance`; `isWatching`; `start(for:rule:onRewrite:)`, `stop(for:)`, `readText(completion:)`, `writeLink(_:by:completion:)`
  - `ClipboardAccess`: `readText(completion:)`, `writeLink(_:completion:)`, `rewriteLinks(rule:onRewrite:)`, `stopRewritingLinks()`; `ClipboardAccess.Backing.watching`
  - `CapabilityBroker.clipboardWatcher`
  - `URLCleanerTests.CleanerRig`: `said`, `undeclared`, `watching`, `broker()`

The watcher is the cleaner's `start`, `stop`, `baselinePasteboard`, `cleanClipboardIfNeeded`, `copy` and `cancelPoll` from Task 1, with the cleaner's three stored properties (`lastChangeCount`, `pollInFlight`, `pollToken`) kept per watching tool. Nothing calls it from the app until Task 6.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolPlatformTests.swift`, `manifests(_:)`, the same expectation moves again, on purpose:

```swift
        suite.expect(Set(Capability.allCases.map(\.rawValue))
                         == ["notify", "open", "processes", "clipboard.write", "storage"],
                     "capabilities are named as the platform design names them")
```
becomes
```swift
        suite.expect(Set(Capability.allCases.map(\.rawValue))
                         == ["notify", "open", "processes", "clipboard.write", "storage", "clipboard.read",
                             "clipboard.rewrite"],
                     "capabilities are named as the platform design names them")
```

In `Tests/URLCleanerTests.swift`, add to `CleanerRig`, after `var stopped = 0`:

```swift
        /// What a tool said on screen, as "symbol: message".
        var said: [String] = []
        /// The capabilities and preference keys a tool used without
        /// declaring them.
        var undeclared: [String] = []
```

and after `var text: String? { ... }`:

```swift
        /// The clipboard, its lane and its timer, as the broker reaches them.
        var watching: ClipboardWatcher.Environment {
            ClipboardWatcher.Environment(
                lane: { [self] in lane.append($0) },
                main: { [self] work in main.append { MainActor.assumeIsolated { work() } } },
                pasteboard: { [self] in board },
                every: { [self] in startTimer($0, $1, $2) })
        }

        /// A broker whose hub, preferences, clipboard and screen are this
        /// rig's.
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

In `Tests/ToolBrokerTests.swift`, the manifest helper takes the tool's id:

```swift
    static func manifest(_ capabilities: [Capability]) -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID("portManager")!, name: "portManager", symbol: "network",
                                          commands: [])!,
```
becomes
```swift
    static func manifest(_ capabilities: [Capability], id: String = "portManager") -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID(id)!, name: id, symbol: "network",
                                          commands: [])!,
```

Add `clipboard(suite)` to `run`, and add:

```swift
    static func clipboard(_ suite: TestSuite) {
        let rig = URLCleanerTests.CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: false)
        rig.defaults.set(true, forKey: AppFeature.portManager.availabilityKey)
        let broker = rig.broker()
        let tool = broker.services(for: manifest([.clipboardRead, .clipboardWrite, .clipboardRewrite],
                                                 id: "urlCleaner")).clipboard
        let other = broker.services(for: manifest([.clipboardRead, .clipboardRewrite])).clipboard
        let none = broker.services(for: manifest([], id: "urlCleaner")).clipboard
        // Marks whatever is copied, every time it is asked: a watch that
        // took its own rewrite for a new copy would mark it twice.
        let mark = ClipboardRewriteRule(readsText: { _ in true },
                                        replacement: { ClipboardReplacement(text: $0 + "!", note: [$0]) },
                                        dropsMarkup: { _, _ in true })
        let never = ClipboardRewriteRule(readsText: { _ in false }, replacement: { _ in nil },
                                         dropsMarkup: { _, _ in true })
        var heard: [String] = []

        suite.expect(none.readText { _ in heard.append("read") } == .notDeclared(.clipboardRead)
                         && none.writeLink("x") { heard.append("wrote") } == .notDeclared(.clipboardWrite)
                         && none.rewriteLinks(rule: mark) { _ in heard.append("rewrote") } == .notDeclared(.clipboardRewrite)
                         && rig.lane.isEmpty && rig.started.isEmpty && heard.isEmpty,
                     "a refused clipboard call does no work and calls nothing back")
        let rewriteOnly = broker.services(for: manifest([.clipboardRewrite], id: "urlCleaner")).clipboard
        suite.expect(rewriteOnly.rewriteLinks(rule: mark) { _ in } == .notDeclared(.clipboardRead) && rig.started.isEmpty,
                     "watching reads what it rewrites, so it needs both capabilities")

        rig.copy("hello")
        var texts: [String?] = []
        suite.expect(tool.readText { texts.append($0) } == nil && texts.isEmpty && rig.lane.count == 1,
                     "reading waits for the clipboard lane")
        rig.settle()
        rig.board.clearContents()
        tool.readText { texts.append($0) }
        rig.settle()
        suite.expect(texts == ["hello", nil],
                     "a tool that asks for it reads the clipboard's text, and nothing from an empty one")

        var wrote = 0
        tool.writeLink("https://example.com/x") { wrote += 1 }
        rig.settle()
        suite.expect(rig.text == "https://example.com/x" && rig.board.string(forType: .URL) == "https://example.com/x"
                         && rig.board.string(forType: .source) == Bundle.main.bundleIdentifier && wrote == 1,
                     "a link a tool writes is on the clipboard as text and as a link, signed as the app's own")

        rig.copy("abc")
        suite.expect(tool.rewriteLinks(rule: mark) { heard.append($0.text) } == nil
                         && rig.started.count == 1 && rig.started[0].interval == ClipboardWatcher.interval
                         && rig.started[0].tolerance == ClipboardWatcher.tolerance && rig.lane.count == 1,
                     "the first watch starts the one timer and takes one look, to know where the clipboard stands")
        suite.expect(ClipboardWatcher.interval == 0.8 && ClipboardWatcher.tolerance == 0.25,
                     "the clipboard is looked at every 0.8 seconds, give or take a quarter")
        tool.rewriteLinks(rule: mark) { heard.append($0.text) }
        other.rewriteLinks(rule: never) { _ in heard.append("other") }
        suite.expect(rig.started.count == 1 && rig.ticks.count == 1,
                     "a tool watched for already keeps its watch, and a second tool shares the timer")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "abc" && heard.isEmpty,
                     "what was on the clipboard when a watch started is not a new copy")

        rig.copy("def")
        rig.tick()
        suite.expect(rig.lane.count == 2 && rig.text == "def", "a tick puts one look per watching tool on the lane")
        rig.settle()
        rig.tick()
        rig.settle()
        suite.expect(rig.text == "def!" && heard == ["def!"],
                     "a copy is rewritten once: the watch's own rewrite is not a new copy to it")

        rig.copy("ghi")
        rig.tick()
        tool.writeLink("own")
        rig.settle()
        suite.expect(rig.text == "own" && heard == ["def!"], "a tool's own write calls off its look that was waiting")
        rig.tick()
        rig.settle()
        suite.expect(rig.text == (URLCleanerTests.signingMovesTheCount() ? "own!" : "own"),
                     "after its own write a tool's watch looks again only if signing the write moved the clipboard's count")

        rig.copy("jkl")
        rig.tick()
        tool.stopRewritingLinks()
        suite.expect(rig.ticks.count == 1, "the timer runs while any tool is watched for")
        rig.settle()
        suite.expect(rig.text == "jkl", "a look that was waiting when its watch stopped changes nothing")
        rig.set(installed: false, enabled: false)
        suite.expect(tool.rewriteLinks(rule: mark) { _ in } == .notInstalled,
                     "a tool removed in the hub is refused a watch")
        suite.expect(tool.readText { _ in heard.append("read") } == .notInstalled
                         && tool.writeLink("x") == .notInstalled && rig.lane.isEmpty,
                     "a tool removed in the hub can no longer read or write the clipboard")
        other.stopRewritingLinks()
        other.stopRewritingLinks()
        suite.expect(rig.ticks.isEmpty && rig.stopped == 1,
                     "the timer stops with the last watch, and stopping twice is safe")
    }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `ClipboardWatcher`.

- [ ] **Step 3: Name the two capabilities**

In `Core/Platform/ToolManifest.swift`:

```swift
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"
    /// Read the preferences the tool's manifest declares.
    case storage

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite, .storage: return []
        }
    }
```
becomes
```swift
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"
    /// Read the text on the clipboard.
    case clipboardRead = "clipboard.read"
    /// Replace what the person copied, in place.
    case clipboardRewrite = "clipboard.rewrite"
    /// Read the preferences the tool's manifest declares.
    case storage

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite, .clipboardRead, .clipboardRewrite, .storage: return []
        }
    }
```

- [ ] **Step 4: Write the watcher**

Create `Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The broker's hold on the clipboard: the one timer that looks at it for
/// the tools that ask, and the reads and writes those tools make. Every
/// touch of the pasteboard runs on the shared clipboard lane, off the main
/// thread, and nobody waits for it: the lane can be wedged behind an app
/// that promised content and stopped answering (issue #887).
///
/// The timer runs only while a tool is watched for. The broker's checks
/// run when a watch starts; the tool host stops a tool that is removed.
@MainActor
package final class ClipboardWatcher {
    /// What the watcher reaches. The app's is the shared clipboard lane,
    /// the general pasteboard and a run-loop timer. A test passes a
    /// pasteboard of its own and runs the lane, the main queue and the
    /// timer by hand.
    package struct Environment {
        /// Runs work on the clipboard lane, off the main thread.
        package var lane: (@escaping @Sendable () -> Void) -> Void
        /// Hands work from the lane back to the main thread.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        /// The pasteboard, asked for on the lane.
        package var pasteboard: @Sendable () -> NSPasteboard
        /// Starts a repeating tick on the main thread, given its interval
        /// and its tolerance. Calling the result stops it.
        package var every: (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)

        package init(lane: @escaping (@escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     pasteboard: @escaping @Sendable () -> NSPasteboard,
                     every: @escaping (TimeInterval, TimeInterval, @escaping @MainActor () -> Void) -> (() -> Void)) {
            self.lane = lane
            self.main = main
            self.pasteboard = pasteboard
            self.every = every
        }

        @MainActor package static let live = Environment(
            lane: { GeneralPasteboardAccess.shared.async($0) },
            main: { work in DispatchQueue.main.async { work() } },
            pasteboard: { .general },
            every: { interval, tolerance, tick in
                let timer = Timer(timeInterval: interval, repeats: true) { _ in
                    // Added to the main run loop below, so it fires on the main thread.
                    MainActor.assumeIsolated { tick() }
                }
                timer.tolerance = tolerance
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            })

        /// Runs nothing and starts no timer. For tests of other
        /// capabilities.
        package static var inert: Environment {
            Environment(lane: { _ in }, main: { _ in }, pasteboard: { .general }, every: { _, _, _ in {} })
        }
    }

    /// How often the clipboard is looked at, and how far the system may
    /// move a look to save power. These are the cadence the link cleaner
    /// has always had; a copy is noticed within a second.
    package static let interval: TimeInterval = 0.8
    package static let tolerance: TimeInterval = 0.25

    /// One tool's watch: its rule, and where it last saw the clipboard.
    @MainActor
    private final class Watch {
        let tool: ToolID
        let rule: ClipboardRewriteRule
        let onRewrite: @MainActor (ClipboardReplacement) -> Void
        var lastChangeCount = 0
        var lookInFlight = false
        var token: ClipboardPollToken?

        init(tool: ToolID, rule: ClipboardRewriteRule, onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) {
            self.tool = tool
            self.rule = rule
            self.onRewrite = onRewrite
        }
    }

    private let environment: Environment
    private var watches: [Watch] = []
    private var stopTimer: (() -> Void)?

    package init(environment: Environment) {
        self.environment = environment
    }

    /// True while the timer runs.
    package var isWatching: Bool { stopTimer != nil }

    // MARK: - Watching

    /// Starts looking at the clipboard for `tool`, and replacing a copied
    /// link when `rule` says so. `onRewrite` hears each replacement, on the
    /// main thread. A tool that is watched for already keeps its watch, so
    /// the timer's beat is not disturbed.
    package func start(for tool: ToolID, rule: ClipboardRewriteRule,
                       onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) {
        guard held(by: tool) == nil else { return }
        let watch = Watch(tool: tool, rule: rule, onRewrite: onRewrite)
        watches.append(watch)
        if stopTimer == nil {
            stopTimer = environment.every(Self.interval, Self.tolerance) { [weak self] in self?.tick() }
        }
        baseline(watch)
    }

    /// Stops looking for `tool`. A look of its that is waiting on the lane
    /// does nothing when its turn comes. The timer stops with the last
    /// watch.
    package func stop(for tool: ToolID) {
        guard let index = watches.firstIndex(where: { $0.tool == tool }) else { return }
        let watch = watches.remove(at: index)
        callOff(watch)
        guard watches.isEmpty else { return }
        stopTimer?()
        stopTimer = nil
    }

    /// The watch `tool` holds, when it has one.
    private func held(by tool: ToolID) -> Watch? {
        watches.first { $0.tool == tool }
    }

    private func tick() {
        for watch in watches { look(watch) }
    }

    /// Reads the change count the clipboard stands at when a watch starts,
    /// away from the main thread, so what was copied before is never taken
    /// for a new copy. It shares the lane with Clipboard History, so
    /// neither can race AppKit's pasteboard type cache while starting up.
    private func baseline(_ watch: Watch) {
        guard !watch.lookInFlight else { return }
        let token = ClipboardPollToken()
        watch.token = token
        watch.lookInFlight = true
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self, weak watch] in
            guard !token.isCancelled else { return }
            let changeCount = board().changeCount
            main {
                guard let self, let watch, watch.token === token else { return }
                watch.token = nil
                watch.lookInFlight = false
                guard self.watches.contains(where: { $0 === watch }) else { return }
                watch.lastChangeCount = changeCount
            }
        }
    }

    /// One look for one watch. Skipped while its last look has not
    /// answered, so a wedged lane never piles looks up.
    private func look(_ watch: Watch) {
        guard !watch.lookInFlight else { return }
        let sinceChangeCount = watch.lastChangeCount
        let token = ClipboardPollToken()
        watch.token = token
        watch.lookInFlight = true
        let rule = watch.rule
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self, weak watch] in
            guard !token.isCancelled else { return }
            let result = ClipboardRewrite.poll(since: sinceChangeCount, token: token, rule: rule, pasteboard: board())
            main {
                guard let self, let watch, watch.token === token else { return }
                watch.token = nil
                watch.lookInFlight = false
                guard self.watches.contains(where: { $0 === watch }), let result else { return }
                watch.lastChangeCount = result.changeCount
                if let replaced = result.replaced { watch.onRewrite(replaced) }
            }
        }
    }

    private func callOff(_ watch: Watch) {
        watch.token?.cancel()
        watch.token = nil
        watch.lookInFlight = false
    }

    // MARK: - Reading and writing

    /// The clipboard's text, read on the lane and handed back on the main
    /// thread. Nil when it holds none.
    package func readText(completion: @escaping @MainActor (String?) -> Void) {
        let board = environment.pasteboard
        let main = environment.main
        environment.lane {
            let text = board().string(forType: .string)
            main { completion(text) }
        }
    }

    /// Replaces the clipboard with a link `tool` made itself: as text and
    /// as a URL, signed as the app's own. A look of that tool's that is
    /// waiting is called off first, and once the write is done its watch
    /// counts the clipboard as seen up to the count read before signing, so
    /// the tool's own write is not a new copy to it.
    package func writeLink(_ link: String, by tool: ToolID, completion: @escaping @MainActor () -> Void) {
        if let watch = held(by: tool) { callOff(watch) }
        let board = environment.pasteboard
        let main = environment.main
        environment.lane { [weak self] in
            let pasteboard = board()
            let changeCount = ClipboardRewrite.write(link, to: pasteboard)
            // Unlike a rewrite of what another app copied, this link is the app's own.
            pasteboard.declareVitruvianSource()
            main {
                if let self, let watch = self.held(by: tool) {
                    watch.lastChangeCount = max(watch.lastChangeCount, changeCount)
                }
                completion()
            }
        }
    }
}
```

Read it against Task 1's file, method by method: `start(for:)` against `start()`, `baseline` against `baselinePasteboard`, `look` against `cleanClipboardIfNeeded`, `callOff` against `cancelPoll`, `writeLink` against `copy`, `stop(for:)` against `stop()`. Where the cleaner checked `self.isRunning`, the watcher checks that the watch is still one of its watches. Where the cleaner assigned the count (`=`) or raised it (`max`), the watcher does the same. Two things the cleaner did that are not here stay in the tool: publishing what was cleaned, and `isRunning`.

- [ ] **Step 5: Offer the operations**

Replace the body of `ClipboardAccess` in `Broker/ClipboardAccess.swift`, from its doc comment to the end of the file (the header and the imports stay):

```swift
/// The clipboard capabilities: writing text, reading text, and rewriting a
/// copied link in place. Each operation checks its own capability.
@MainActor
package struct ClipboardAccess {
    package struct Backing {
        /// Replace the clipboard with `text`, then say on the main thread
        /// whether it took.
        package var write: (_ text: String, _ completion: @escaping @MainActor (Bool) -> Void) -> Void
        /// The clipboard, its lane and its timer, for reading, for writing
        /// a link and for the watch.
        package var watching: ClipboardWatcher.Environment

        package init(write: @escaping (String, @escaping @MainActor (Bool) -> Void) -> Void,
                     watching: ClipboardWatcher.Environment = .inert) {
            self.write = write
            self.watching = watching
        }

        @MainActor package static let live = Backing(write: { text, completion in
            GeneralPasteboardAccess.shared.async({
                NSPasteboard.general.clearContents()
                NSPasteboard.general.declareVitruvianSource()
                return NSPasteboard.general.setString(text, forType: .string)
            }, then: { copied in
                completion(copied)
            })
        }, watching: .live)
    }

    let gate: (Capability) -> BrokerRefusal?
    let backing: Backing
    let watcher: ClipboardWatcher
    let tool: ToolID

    /// Replaces the clipboard with `text`. `completion` hears whether it
    /// took; it is not called when the call is refused.
    @discardableResult
    package func write(_ text: String, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate(.clipboardWrite) { return refusal }
        backing.write(text, completion)
        return nil
    }

    /// Replaces the clipboard with a link the tool made: as text and as a
    /// URL, signed as the app's own. The tool's watch, when it has one,
    /// does not take the write for a new copy. `completion` is called once
    /// the write is done, and not when the call is refused.
    @discardableResult
    package func writeLink(_ link: String, completion: @escaping @MainActor () -> Void = {}) -> BrokerRefusal? {
        if let refusal = gate(.clipboardWrite) { return refusal }
        watcher.writeLink(link, by: tool, completion: completion)
        return nil
    }

    /// Reads the clipboard's text. `completion` hears it on the main
    /// thread, nil when there is none; it is not called when the call is
    /// refused.
    @discardableResult
    package func readText(completion: @escaping @MainActor (String?) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRead) { return refusal }
        watcher.readText(completion: completion)
        return nil
    }

    /// Watches the clipboard and, each time somebody copies, asks `rule`
    /// whether to put something in the copy's place. The whole look (read,
    /// ask, check the copy is still the one read, write) is one job on the
    /// clipboard lane. `onRewrite` hears each replacement on the main
    /// thread. It reads what it rewrites, so it needs both capabilities.
    @discardableResult
    package func rewriteLinks(rule: ClipboardRewriteRule,
                              onRewrite: @escaping @MainActor (ClipboardReplacement) -> Void) -> BrokerRefusal? {
        if let refusal = gate(.clipboardRewrite) ?? gate(.clipboardRead) { return refusal }
        watcher.start(for: tool, rule: rule, onRewrite: onRewrite)
        return nil
    }

    /// Stops the watch `rewriteLinks` started. Never refused: a tool that
    /// was removed in the hub must still be able to stop.
    package func stopRewritingLinks() {
        watcher.stop(for: tool)
    }
}
```

In `ToolServices.swift`:

```swift
    package var clipboard: ClipboardAccess {
        ClipboardAccess(gate: gate(.clipboardWrite), backing: broker.backings.clipboard)
    }
```
becomes
```swift
    package var clipboard: ClipboardAccess {
        ClipboardAccess(gate: { [broker, manifest] capability in broker.refusal(of: capability, for: manifest) },
                        backing: broker.backings.clipboard, watcher: broker.clipboardWatcher, tool: manifest.id)
    }
```

In `CapabilityBroker.swift`:

```swift
    package let environment: Environment
    package let backings: Backings

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
    }
```
becomes
```swift
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

- [ ] **Step 6: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=clipboard --test_arg=--suite=utilities`
Expected: PASS. `utilities` is there for the Port manager, whose copy goes through `ClipboardAccess.write`.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 7: Commit**

No file with an upstream header changed.

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ToolManifest.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/Broker apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/ToolServices.swift apps/desktop/vitruvian/Tests/ToolPlatformTests.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/Tests/URLCleanerTests.swift
git commit -m "refactor(desktop): watch the clipboard in one place, for the tools that ask"
```

(`git add` of the `Broker` directory is fine here: every file in it is this plan's or stage A's. Check `git status --short` first.)

---

### Task 5: The host starts, stops and runs tools

**Files:**
- Modify: `Sources/Vitruvian/Services/Platform/BundledTool.swift`, `Sources/Vitruvian/Services/Platform/ToolHost.swift`, `Sources/Vitruvian/Services/Platform/BuiltinTools.swift`
- Create: `Sources/Vitruvian/Services/Platform/BundledTools.swift`
- Modify: `Sources/Vitruvian/Services/FeatureRuntime.swift` (`perform`, `FeatureBindingAction`)
- Modify: `Sources/Vitruvian/Services/PortManager/PortManagerService.swift`
- Modify: `Tests/ToolBrokerTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Produces:
  - `BundledTool` gains `start()`, `run(_:)`, `canRun(_:)`
  - `BundledTools.all: [any BundledTool.Type]`
  - `ToolHost`: `init(broker:tools:)`, `running`, `shouldRun(_:)`, `sync(_ id: ToolID)`, `sync(_ type:)`, `manifest(for:)`, `canRun(_:)`, `run(_:)`; `stopAll()` stops running tools first
  - `BuiltinTools.install(into:host:)`
  - `FeatureBindingAction.tool(ToolID)`

What the host's rule replaces, which is the contract its test pins:

| Today, in each service's `syncWithPreferences()` | The host |
|---|---|
| installed in the hub and switched on: `start()` | `shouldRun` is true: build the tool if needed, `start()` |
| anything else: `stop()` | `shouldRun` is false: `stop()` if the tool was ever built, nothing otherwise |
| `start()` is called on every sync, and does nothing the second time | the same: `start()` on every sync that finds the tool should run |
| the quit list touches `.shared`, building a service that never ran | `stopAll()` stops what was built, and builds nothing |

No `FeatureRuntime` arm produces `.tool` until Task 6. The action exists first so that Task 6 changes one arm.

- [ ] **Step 1: Write the failing tests**

In `Tests/ToolBrokerTests.swift`, the probe tool grows with the protocol. No expectation changes.

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
```
becomes
```swift
    final class ProbeTool: BundledTool {
        static let manifest = ToolBrokerTests.manifest([.notify])
        static var built = 0
        let services: ToolServices
        var starts = 0
        var stops = 0
        init(services: ToolServices) {
            self.services = services
            Self.built += 1
        }
        func start() { starts += 1 }
        func stop() {
            stops += 1
            ToolBrokerTests.events.append("portManager stop")
        }
        func run(_ command: CommandID) {}
        func canRun(_ command: CommandID) -> Bool { false }
    }
```

Add `hostRunsTools(suite)` to `run`, and add:

```swift
    /// What the probes below were asked, in order.
    static var events: [String] = []

    /// A tool with a switch and a command, to watch the host start, stop
    /// and run it.
    final class LifecycleProbe: BundledTool {
        static let probe = CommandID("homebrew/probe")!
        static let manifest = ToolManifest(
            tool: ToolDescriptor(id: ToolID("homebrew")!, name: "homebrew", symbol: "shippingbox",
                                 commands: [CommandDescriptor(id: probe, title: "probe", symbol: "shippingbox",
                                                              surfaces: [])!])!,
            group: .tools, capabilities: [],
            preferences: [PreferenceDeclaration(key: "probeSwitch", default: .bool(false))],
            activation: [.onLaunch, .onCommand], enabledBy: "probeSwitch")!
        static var built = 0
        init(services: ToolServices) { Self.built += 1 }
        func start() { ToolBrokerTests.events.append("start") }
        func stop() { ToolBrokerTests.events.append("stop") }
        func run(_ command: CommandID) { ToolBrokerTests.events.append("run \(command.name)") }
        func canRun(_ command: CommandID) -> Bool { true }
    }

    static func hostRunsTools(_ suite: TestSuite) {
        let rig = URLCleanerTests.CleanerRig()
        defer { rig.close() }
        let feature = AppFeature.homebrew
        let id = LifecycleProbe.manifest.id
        let command = LifecycleProbe.probe
        func set(installed: Bool, on: Bool) {
            rig.defaults.set(installed, forKey: feature.availabilityKey)
            rig.defaults.set(on, forKey: "probeSwitch")
        }

        // The run rule, against every combination.
        for installed in [false, true] {
            for on in [false, true] {
                LifecycleProbe.built = 0
                events = []
                let host = ToolHost(broker: rig.broker(), tools: [LifecycleProbe.self])
                set(installed: installed, on: on)
                host.sync(id)
                let runs = installed && on
                suite.expect(host.shouldRun(LifecycleProbe.manifest) == runs && events == (runs ? ["start"] : [])
                                 && LifecycleProbe.built == (runs ? 1 : 0) && host.running == (runs ? [id] : []),
                             "installed \(installed), switched on \(on): the host "
                                 + (runs ? "starts the tool" : "leaves the tool unbuilt"))
            }
        }

        LifecycleProbe.built = 0
        events = []
        let host = ToolHost(broker: rig.broker(), tools: [LifecycleProbe.self, ProbeTool.self])
        rig.defaults.set(true, forKey: AppFeature.portManager.availabilityKey)
        set(installed: true, on: true)
        host.sync(ProbeTool.manifest.id)
        host.sync(id)
        host.sync(id)
        suite.expect(events == ["start", "start"] && host.running == [ProbeTool.manifest.id, id]
                         && LifecycleProbe.built == 1 && host.tool(ProbeTool.self).starts == 1,
                     "deciding again while a tool runs starts the same tool again, as a sync always did")
        set(installed: true, on: false)
        host.sync(id)
        host.sync(id)
        suite.expect(events.suffix(2) == ["stop", "stop"] && host.running == [ProbeTool.manifest.id],
                     "switching a tool off stops it, and stopping twice is safe")
        set(installed: true, on: true)
        host.sync(id)
        events = []
        host.stopAll()
        suite.expect(events == ["stop", "portManager stop"] && host.running.isEmpty && LifecycleProbe.built == 1,
                     "quitting stops what is running, last started first, and builds nothing")

        // Commands.
        set(installed: true, on: false)
        events = []
        suite.expect(host.canRun(command),
                     "a command can run while the tool's switch is off: the switch is for background work")
        host.run(command)
        suite.expect(events == ["run probe"], "the host hands a command to its tool")
        suite.expect(!host.canRun(CommandID("homebrew/unknown")!) && !host.canRun(CommandID("screenshot/capture")!),
                     "the host runs only a command that a manifest it holds declares")

        // The registry runs a tool's command through the host.
        let registry = ToolRegistry(isAvailable: { $0.isAvailable(in: rig.defaults) })
        BuiltinTools.install(into: registry, host: host)
        suite.expect(registry.tool(id) == LifecycleProbe.manifest.tool && registry.hasHandler(for: command)
                         && registry.name(for: id, language: .systemDefault)
                             == feature.hubTitle(Strings.localized(.systemDefault), hub: FeatureStrings.hub(.systemDefault)),
                     "a tool the host holds is registered as its manifest describes it, under the hub's name")
        suite.expect(ToolSurface.allCases.allSatisfy { surface in
            !registry.commands(on: surface).contains { $0.id == command }
        }, "a command that asks for no surface is listed on none")
        suite.expect(registry.run(command) && events == ["run probe", "run probe"],
                     "the registry runs a tool's command through the host")
        set(installed: false, on: true)
        host.run(command)
        suite.expect(!host.canRun(command) && !registry.run(command) && events == ["run probe", "run probe"],
                     "a tool removed in the hub runs no command")
    }
```

`LifecycleProbe` borrows the id of a hub feature that has no built-in command (`homebrew`), because a tool id with no dot must name a feature. It is a test double and touches nothing of Homebrew's.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: a compile failure naming `tools:` or `sync`.

- [ ] **Step 3: Complete the interface**

Replace the protocol in `Services/Platform/BundledTool.swift`:

```swift
/// A tool compiled into the app. It says what it is in `manifest`, is built
/// with the services that manifest allows, and reaches nothing else: no
/// singleton, no system service. It never asks whether it is installed or
/// switched on: the tool host does, and calls `start` and `stop`.
@MainActor
package protocol BundledTool: AnyObject {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
    /// Begin whatever the tool does in the background. The host calls it
    /// every time it finds the tool installed, switched on and holding its
    /// grants, so it must be safe to call twice.
    func start()
    /// Undo everything `start` did. Safe to call twice.
    func stop()
    /// Run one of the manifest's commands.
    func run(_ command: CommandID)
    /// Whether a command can run right now.
    func canRun(_ command: CommandID) -> Bool
}
```

Create `Sources/Vitruvian/Services/Platform/BundledTools.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The features that have become tools. The host starts, stops and runs
/// only what is listed here; a migration adds one line.
@MainActor
package enum BundledTools {
    package static let all: [any BundledTool.Type] = [PortManagerService.self]
}
```

In `Services/PortManager/PortManagerService.swift`:

```swift
    package func stop() {}
```
becomes
```swift
    /// Nothing runs in the background: the list is read when a view asks.
    package func start() {}

    package func stop() {}

    /// The Port manager has no command.
    package func run(_ command: CommandID) {}

    package func canRun(_ command: CommandID) -> Bool { false }
```

- [ ] **Step 4: Teach the host**

Replace `Services/Platform/ToolHost.swift` from the doc comment of `ToolHost` to the end of the file:

```swift
/// Owns the live tools. It builds a tool the first time somebody needs it,
/// hands the same one to everybody after, starts and stops it as the hub,
/// its switch and its grants say, runs its commands, and stops them all at
/// quit. A view gets its tool here.
@MainActor
package final class ToolHost {
    package static let shared = ToolHost(broker: .shared, tools: BundledTools.all)

    private let broker: CapabilityBroker
    /// The tools the host may build, by id.
    private var types: [ToolID: any BundledTool.Type] = [:]
    private var tools: [ToolID: any BundledTool] = [:]
    /// The tools that have been built, in the order they were.
    package private(set) var built: [ToolID] = []
    /// The tools the host started and has not stopped, in the order it
    /// started them.
    package private(set) var running: [ToolID] = []

    package init(broker: CapabilityBroker, tools: [any BundledTool.Type] = []) {
        self.broker = broker
        for type in tools { types[type.manifest.id] = type }
    }

    // MARK: - Tools

    /// The one instance of `type`, built on first use. Two tool types may
    /// not share an id: asking for the second is a mistake in the app, and
    /// stops it rather than building a tool on every call.
    package func tool<T: BundledTool>(_ type: T.Type) -> T {
        let id = type.manifest.id
        // A type listed under this id is the one that gets built.
        let listed: any BundledTool.Type = types[id] ?? type
        let existing = tools[id] ?? build(listed)
        guard let tool = existing as? T else {
            preconditionFailure("\(T.self) and \(Swift.type(of: existing)) both claim the tool id \(id.rawValue)")
        }
        return tool
    }

    /// The manifest of the tool with this id, when the host holds one.
    package func manifest(for id: ToolID) -> ToolManifest? {
        types[id]?.manifest
    }

    private func build(_ type: any BundledTool.Type) -> any BundledTool {
        let manifest = type.manifest
        let tool = type.init(services: broker.services(for: manifest))
        types[manifest.id] = type
        tools[manifest.id] = tool
        built.append(manifest.id)
        return tool
    }

    // MARK: - Running

    /// Whether a tool should be running now: installed in the hub, switched
    /// on when it has a switch, and holding every macOS grant its
    /// capabilities ride on. This is the check each service made for
    /// itself before it became a tool.
    package func shouldRun(_ manifest: ToolManifest) -> Bool {
        guard broker.environment.isInstalled(manifest.id) else { return false }
        if let key = manifest.enabledBy, (broker.backings.storage.read(key) as? Bool) != true { return false }
        return manifest.capabilities.flatMap(\.capability.ridesOn).allSatisfy(broker.environment.isGranted)
    }

    /// Starts or stops the tool with this id so that it matches
    /// `shouldRun`. Called at launch, when the hub installs or removes the
    /// tool, when its switch flips and when a grant changes. A tool that
    /// should not run and was never built is left unbuilt.
    package func sync(_ id: ToolID) {
        guard let type = types[id] else { return }
        if shouldRun(type.manifest) {
            let tool = tools[id] ?? build(type)
            if !running.contains(id) { running.append(id) }
            tool.start()
        } else {
            running.removeAll { $0 == id }
            tools[id]?.stop()
        }
    }

    /// The same, for code that names the tool: a view whose switch for it
    /// just flipped. Nothing watches the preferences; whoever changes one
    /// says so.
    package func sync<T: BundledTool>(_ type: T.Type) {
        let id = type.manifest.id
        if types[id] == nil { types[id] = type }
        sync(id)
    }

    /// Stops every built tool, and builds none: first the running ones,
    /// last started first, then the rest, last built first.
    package func stopAll() {
        let rest = built.reversed().filter { !running.contains($0) }
        for id in Array(running.reversed()) + rest { tools[id]?.stop() }
        running = []
    }

    // MARK: - Commands

    /// Whether a command can run now: a manifest the host holds declares
    /// it, its tool is installed in the hub, and the tool says yes. The
    /// tool's own switch is not asked: it is for background work. Asking
    /// builds the tool.
    package func canRun(_ command: CommandID) -> Bool {
        guard let type = types[command.tool],
              type.manifest.tool.commands.contains(where: { $0.id == command }),
              broker.environment.isInstalled(command.tool) else { return false }
        return (tools[command.tool] ?? build(type)).canRun(command)
    }

    /// Runs a command on its tool, when it can run.
    package func run(_ command: CommandID) {
        guard canRun(command) else { return }
        tools[command.tool]?.run(command)
    }
}
```

The third clause of `shouldRun` is not reached in this stage: no capability rides on a grant yet. It must still be right. It asks the same `ridesOn` and the same `isGranted` that `CapabilityBroker.refusal(of:for:)` asks.

- [ ] **Step 5: Register a tool from its manifest**

In `Services/Platform/BuiltinTools.swift`:

```swift
    package static func install(into registry: ToolRegistry = .shared) {
        // A built-in command asks for the panel only when a tile runs it:
        // the others have no tile today, and listing them would put new
        // tiles in front of everyone.
        let tiled = Set(QuickLauncherItem.allCases.compactMap(\.command))
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            let own = BuiltinCommand.allCases.filter { $0.feature == feature }
```
becomes
```swift
    package static func install(into registry: ToolRegistry = .shared, host: ToolHost = .shared) {
        // A built-in command asks for the panel only when a tile runs it:
        // the others have no tile today, and listing them would put new
        // tiles in front of everyone.
        let tiled = Set(QuickLauncherItem.allCases.compactMap(\.command))
        for feature in AppFeature.allCases {
            guard let id = ToolID(feature.rawValue), registry.tool(id) == nil else { continue }
            // A feature that has become a tool says what it is in its
            // manifest, and its commands run through the tool host. Its
            // commands are the manifest's alone: it has no `BuiltinCommand`.
            if let manifest = host.manifest(for: id) {
                try? registry.register(manifest.tool)
                try? registry.setName(titleProvider(for: feature), for: id)
                for command in manifest.tool.commands {
                    try? registry.setHandler(.init(title: titleProvider(for: feature),
                                                   isRunnable: { host.canRun(command.id) },
                                                   run: { host.run(command.id) }),
                                             for: command.id)
                }
                continue
            }
            let own = BuiltinCommand.allCases.filter { $0.feature == feature }
```

Change the type's doc comment to say so:

```swift
/// Puts the app's own tools in the registry: one tool per hub feature, and a
/// handler for each built-in command. This is the only place that knows
/// which service call a built-in command runs.
```
becomes
```swift
/// Puts the app's own tools in the registry: one tool per hub feature, and a
/// handler for each command. This is the only place that knows which service
/// call a built-in command runs. A feature that has become a tool is
/// registered from its manifest, and its commands run through the tool host.
```

- [ ] **Step 6: Give `FeatureRuntime` its action for tools**

In `Services/FeatureRuntime.swift`, in `perform(_:)`, after the last arm:

```swift
        case .fanControl: FanControlService.shared.syncWithPreferences()
        }
```
becomes
```swift
        case .fanControl: FanControlService.shared.syncWithPreferences()
        case .tool(let id): ToolHost.shared.sync(id)
        }
```

and the enum:

```swift
/// One thing a feature's binding does to a live service, named so a test can
/// read a feature's bindings without bringing any service to life. Most sync
/// a service with its preferences; the `stop…`, `cancel…`, `close…` and
/// `reset…` ones tear down what an uninstalled feature left running.
package enum FeatureBindingAction: Hashable, CaseIterable {
```
becomes
```swift
/// One thing a feature's binding does to a live service, named so a test can
/// read a feature's bindings without bringing any service to life. Most sync
/// a service with its preferences; the `stop…`, `cancel…`, `close…` and
/// `reset…` ones tear down what an uninstalled feature left running. `tool`
/// hands a feature that has become a tool to the tool host, which decides
/// whether it runs.
package enum FeatureBindingAction: Hashable {
```

and its last line:

```swift
    case appUpdates, monitorPlan, monitorAlerts, fanControl
}
```
becomes
```swift
    case appUpdates, monitorPlan, monitorAlerts, fanControl
    /// A feature that has become a tool: the tool host starts or stops it.
    case tool(ToolID)
}
```

`CaseIterable` goes because a case with a value cannot be listed automatically. Check that nothing reads the list before removing it:

Run: `grep -rn "FeatureBindingAction.allCases" apps/desktop/vitruvian/Sources apps/desktop/vitruvian/Tests`
Expected: no output.

- [ ] **Step 7: Run the tests and the build**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_arg=--suite=features --test_arg=--suite=utilities`
Expected: PASS. `ToolPlatformTests.builtinTools` and `ToolBrokerTests.manifestsAgree` pass unchanged: `BuiltinTools` still registers every feature, the Port manager's from its manifest.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 8: Commit**

Append to the stage B entry in `UPSTREAM.md`:

```markdown
  - `Services/FeatureRuntime.swift`: one binding action, `tool`, hands a feature that has become a tool to the tool host. `FeatureBindingAction` is no longer `CaseIterable`; nothing read the list.
  - `Services/PortManager/PortManagerService.swift`: says it has nothing to start and no command, now that the tool interface asks.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform apps/desktop/vitruvian/Sources/Vitruvian/Services/FeatureRuntime.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/PortManager/PortManagerService.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): let the tool host start, stop and run tools"
```

---

### Task 6: The URL cleaner becomes a tool

**Files:**
- Modify: `Sources/Vitruvian/Services/URLCleanerService.swift`
- Modify: `Sources/Vitruvian/UI/Settings/URLCleanerSettings.swift` (lines near 39, 64 to 67, 325 to 334)
- Modify: `Sources/Vitruvian/UI/MenuPanel/PanelURLCleanerView.swift` (lines near 12, 61 to 63, 148 to 157)
- Modify: `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift` (lines near 633 to 641, 1682 to 1697, 1930 to 1962)
- Modify: `Sources/Vitruvian/Services/FeatureRuntime.swift` (`actions(for:in:)`, `perform`, `FeatureBindingAction`)
- Modify: `Sources/Vitruvian/App/AppDelegate.swift` (`applicationWillTerminate`)
- Modify: `Sources/Vitruvian/Services/Platform/BundledTools.swift`
- Modify: `Tests/URLCleanerTests.swift`, `Tests/ClipboardFeatureTests.swift`, `Tests/ToolBrokerTests.swift`, `Tests/FeatureRuntimeTests.swift`, `UPSTREAM.md`

**Interfaces:**
- Consumes: `BundledTool`, `ToolServices` (`storage`, `clipboard`, `notify`), `ToolHost`, `ClipboardRewriteRule`.
- Produces, on `URLCleanerService`: `static let manifest`, `static let cleanClipboard`, `init(services:)`, `start()`, `run(_:)`, `canRun(_:)`, `pasteboardText(_:)`. `clean(_:)`, `copy(_:)`, `stop()`, `rewriteRule(rules:)` and the published state keep their names. `static let shared`, `Environment`, `syncWithPreferences()`, `pollPasteboard`, `PollToken` and `PollResult` are gone.

The class keeps its name and its file, as the Port manager did.

Every caller of the singleton today, and what it becomes:

| Where | Today | After |
|---|---|---|
| `URLCleanerSettings.swift:39`, `PanelURLCleanerView.swift:12` | `@ObservedObject private var cleaner = URLCleanerService.shared` | `ToolHost.shared.tool(URLCleanerService.self)` |
| `URLCleanerSettings.swift:66`, `PanelURLCleanerView.swift:62` | `URLCleanerService.shared.syncWithPreferences()` when the switch flips | `ToolHost.shared.sync(URLCleanerService.self)` |
| `URLCleanerSettings.swift:329`, `PanelURLCleanerView.swift:152` | the Paste button reads `NSPasteboard.general` on the lane | `cleaner.pasteboardText { }` |
| both views | `cleaner.clean(input)`, `cleaner.copy(url)`, `cleaner.isRunning`, `cleaner.lastRemoved` | unchanged |
| `CommandBarCatalog.swift:640` | the `action.cleanURL` row runs `cleanClipboardURL()` | `ToolRegistry.shared.run(URLCleanerService.cleanClipboard)` |
| `CommandBarCatalog.swift:1935` | `cleanClipboardURL()` reads the pasteboard, cleans, copies, shows a HUD | deleted; it is the tool's `run(_:)` |
| `CommandBarCatalog.swift:1683`, `1691` | the `selection.cleanLink` row: `URLCleanerService.shared.clean(text)`, `.copy(cleaned.url)` | the same two calls on `ToolHost.shared.tool(URLCleanerService.self)` |
| `FeatureRuntime.swift:369`, `473` | the arm `[.urlCleaner]`, and `URLCleanerService.shared.syncWithPreferences()` | the arm `[.tool(id)]`; the `perform` arm and the case go |
| `AppDelegate.swift:340` | `URLCleanerService.shared.stop()` at quit | deleted; `ToolHost.shared.stopAll()` above it covers it |
| `ClipboardFeatureTests.swift:123` | `URLCleanerService.pollPasteboard`, `PollResult`, `PollToken` | `ClipboardRewrite.poll` with the cleaner's rule |

Three places name the cleaner's strings and nothing of its service, and do not change: `UI/Settings/SettingsView.swift:1248` (`urlCleanerClearButton`), `UI/Settings/WhatsAppDownloadsSettings.swift:515` (`urlCleanerManualTitle`), and `UI/Settings/SettingsView.swift:574`, which builds `URLCleanerSettings()`. The Quick panel's tile (`QuickLauncherItem.urlCleaner`) runs no command: it shows `PanelURLCleanerView` inside the panel, so `QuickLauncherService` and `QuickLauncherView` do not change either. Calls into `Core/URLCleaning.swift` from the views stay direct: they clean a string and reach nothing.

- [ ] **Step 1: Move the tests onto the tool**

In `Tests/URLCleanerTests.swift`, two helpers change. No expectation does.

```swift
    static func bench(_ rig: CleanerRig) -> (cleaner: URLCleanerService, sync: () -> Void) {
        let cleaner = URLCleanerService(environment: .init(
            defaults: rig.defaults,
            lane: { rig.lane.append($0) },
            main: { work in rig.main.append { MainActor.assumeIsolated { work() } } },
            pasteboard: { rig.board },
            every: { rig.startTimer($0, $1, $2) }))
        return (cleaner, { cleaner.syncWithPreferences() })
    }
```
becomes
```swift
    static func bench(_ rig: CleanerRig) -> (cleaner: URLCleanerService, sync: () -> Void) {
        let host = ToolHost(broker: rig.broker(), tools: [URLCleanerService.self])
        return (host.tool(URLCleanerService.self), { host.sync(URLCleanerService.manifest.id) })
    }
```

and

```swift
        let token = URLCleanerService.PollToken()
        if cancelled { token.cancel() }
        return URLCleanerService.pollPasteboard(sinceChangeCount: since, token: token, pasteboard: board,
                                                rules: URLCleaning.Rules.none)
            .map { (changeCount: $0.changeCount, cleaned: $0.cleaned) }
```
becomes
```swift
        let token = ClipboardPollToken()
        if cancelled { token.cancel() }
        return ClipboardRewrite.poll(since: since, token: token,
                                     rule: URLCleanerService.rewriteRule(rules: { .none }), pasteboard: board)
            .map { poll in
                (changeCount: poll.changeCount,
                 cleaned: poll.replaced.map { URLCleaning.Result(url: $0.text, removed: $0.note) })
            }
```

Add `commands(suite)` to `run`, and add:

```swift
    /// The command bar's "Clean URL" row, the Paste buttons, and what the
    /// tool asked the broker for along the way.
    static func commands(_ suite: TestSuite) {
        let rig = CleanerRig()
        defer { rig.close() }
        rig.set(installed: true, enabled: false)
        let host = ToolHost(broker: rig.broker(), tools: [URLCleanerService.self])
        let command = URLCleanerService.cleanClipboard
        let s = L10n.shared.s
        func runCommand() {
            rig.said = []
            host.run(command)
            rig.settle()
        }

        suite.expect(host.canRun(command) && host.running.isEmpty,
                     "the command runs while automatic cleaning is switched off")
        rig.board.clearContents()
        runCommand()
        suite.expect(rig.said == ["link: \(s.urlCleanerNoURL)"], "an empty clipboard says there is no link")
        rig.copy("not a link")
        runCommand()
        suite.expect(rig.said == ["link: \(s.urlCleanerNoURL)"] && rig.text == "not a link",
                     "text that is not a link says so and is left alone")
        rig.copy("https://example.com/?id=42")
        let count = rig.board.changeCount
        runCommand()
        suite.expect(rig.said == ["checkmark.circle: \(s.urlCleanerNoChange)"] && rig.board.changeCount == count,
                     "a link with nothing to take out says so and is left alone")
        rig.copy(dirty)
        runCommand()
        let removed = (URLCleaning.clean(dirty)?.removed ?? []).joined(separator: ", ")
        suite.expect(rig.text == cleaned && rig.board.string(forType: .URL) == cleaned
                         && rig.said == ["link: " + String(format: s.urlCleanerRemovedFormat, removed)],
                     "a link with tracking parts is cleaned, and the message names what was taken out")

        let cleaner = host.tool(URLCleanerService.self)
        var pasted: [String] = []
        rig.copy("pasted")
        cleaner.pasteboardText { pasted.append($0) }
        rig.settle()
        rig.board.clearContents()
        cleaner.pasteboardText { pasted.append($0) }
        rig.settle()
        suite.expect(pasted == ["pasted", ""],
                     "a Paste button reads the clipboard's text, and an empty clipboard as empty text")

        let registry = ToolRegistry(isAvailable: { $0.isAvailable(in: rig.defaults) })
        BuiltinTools.install(into: registry, host: host)
        rig.copy(dirty)
        suite.expect(ToolSurface.allCases.allSatisfy { surface in
            !registry.commands(on: surface).contains { $0.id.tool == command.tool }
        }, "the cleaner adds no row, tile, wheel slot or shortcut of its own")
        suite.expect(registry.run(command), "the command bar's row runs the cleaner's command through the registry")
        rig.settle()
        suite.expect(rig.text == cleaned, "and the command does its work")
        rig.set(installed: false, enabled: false)
        rig.copy(dirty)
        suite.expect(!registry.run(command) && rig.lane.isEmpty, "removed in the hub, the command does nothing")
        suite.expect(rig.undeclared.isEmpty, "the cleaner asks for nothing its manifest does not declare")
    }
```

In `Tests/ClipboardFeatureTests.swift`, one helper's body changes because the function it called moved. The four expectations below it are untouched.

```swift
        func poll() -> URLCleanerService.PollResult? {
            URLCleanerService.pollPasteboard(sinceChangeCount: -1, token: URLCleanerService.PollToken(),
                                             pasteboard: cleanerBoard, rules: URLCleaning.Rules.none)
        }
```
becomes
```swift
        func poll() -> (changeCount: Int, cleaned: URLCleaning.Result?)? {
            ClipboardRewrite.poll(since: -1, token: ClipboardPollToken(),
                                  rule: URLCleanerService.rewriteRule(rules: { .none }), pasteboard: cleanerBoard)
                .map { poll in
                    (changeCount: poll.changeCount,
                     cleaned: poll.replaced.map { URLCleaning.Result(url: $0.text, removed: $0.note) })
                }
        }
```

In `Tests/ToolBrokerTests.swift`, `manifestsAgree(_:)` checks the new manifest, and three more things about every manifest:

```swift
        let manifests = [PortManagerService.manifest]
        let registry = ToolRegistry(isAvailable: { _ in true })
```
becomes
```swift
        let manifests = [PortManagerService.manifest, URLCleanerService.manifest]
        suite.expect(BundledTools.all.map { $0.manifest.id } == manifests.map(\.id),
                     "every tool the host holds is checked here")
        let registry = ToolRegistry(isAvailable: { _ in true })
```

and, inside the loop, after the "declares each preference with the default the app registers" expectation:

```swift
            suite.expect((manifest.enabledBy.map { [$0] } ?? []) == feature.enabledKeys,
                         "\(manifest.id) is switched on by the key its feature names")
            suite.expect(FeatureRuntime.actions(for: feature, in: .standard).contains(.tool(manifest.id))
                             == manifest.activation.contains(.onLaunch),
                         "\(manifest.id) is handed to the tool host at launch exactly when its manifest says so")
```

In `Tests/FeatureRuntimeTests.swift`, after the "an on-demand tool has nothing to start or stop" expectation, add:

```swift
        suite.expect(actions(.urlCleaner) == [.tool(URLCleanerService.manifest.id)],
                     "a feature that has become a tool is handed to the tool host")
```

Nothing in that file pinned the cleaner's old action, so no expectation there changes. The expectation just above it, that the Port manager binds nothing, stays as it is.

- [ ] **Step 2: Run it to make sure it fails**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard`
Expected: a compile failure naming `manifest` or `cleanClipboard`.

- [ ] **Step 3: Turn the service into the tool**

Replace `Sources/Vitruvian/Services/URLCleanerService.swift` from line 10 (`@MainActor`) to the end of the file. Lines 1 to 9 (the header and the imports) stay as they are.

```swift
@MainActor
package final class URLCleanerService: ObservableObject {
    @Published package private(set) var isRunning = false
    @Published package private(set) var lastCleaned: String?
    /// Names the last automatic clean took out, so Settings can say what the
    /// silent rewrite did rather than only that it is running.
    @Published package private(set) var lastRemoved: [String] = []

    private let services: ToolServices
    /// True while the broker watches the clipboard for this tool.
    private var watching = false

    package init(services: ToolServices) {
        self.services = services
    }

    package func clean(_ text: String) -> URLCleaning.Result? {
        URLCleaning.clean(text, rules: Self.rules(try? services.storage.reader().get()))
    }

    /// Writes on the shared lane and settles the change count on the main
    /// queue, where the watch compares against it. The caller never waits: the
    /// lane can be wedged behind an app that promised pasteboard content and
    /// stopped answering (issue #887).
    package func copy(_ urlString: String) {
        lastCleaned = urlString
        services.clipboard.writeLink(urlString)
    }

    /// The text on the clipboard, for a Paste button: empty when it holds
    /// none. Through the shared lane: a direct read would both race the
    /// clipboard services on AppKit's pasteboard cache and hang the button
    /// (and with it the app) on a promised flavour nobody renders any more.
    package func pasteboardText(_ completion: @escaping @MainActor (String) -> Void) {
        services.clipboard.readText { completion($0 ?? "") }
    }

    /// Starts the automatic clean. The tool host calls this each time it
    /// finds the cleaner installed and switched on, so a second call only
    /// confirms it is running.
    package func start() {
        guard !watching else {
            isRunning = true
            return
        }
        guard case .success(let storage) = services.storage.reader() else { return }
        let rule = Self.rewriteRule(rules: { Self.rules(storage) })
        let refusal = services.clipboard.rewriteLinks(rule: rule) { [weak self] replaced in
            guard let self, self.isRunning else { return }
            self.lastCleaned = replaced.text
            self.lastRemoved = replaced.note
        }
        guard refusal == nil else { return }
        watching = true
        isRunning = true
    }

    package func stop() {
        services.clipboard.stopRewritingLinks()
        watching = false
        isRunning = false
    }

    package func canRun(_ command: CommandID) -> Bool {
        command == Self.cleanClipboard
    }

    /// Cleans the link on the clipboard once and says what it did. Reads
    /// through the shared lane like every other clipboard row: a direct
    /// main-thread read races the lane's readers and freezes the app on a
    /// promised flavour nobody is left to render (issue #887).
    package func run(_ command: CommandID) {
        guard command == Self.cleanClipboard else { return }
        let notify = services.notify
        services.clipboard.readText { [weak self] raw in
            guard let self else { return }
            let s = L10n.shared.s
            guard let raw,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notify.hud(icon: "link", message: s.urlCleanerNoURL)
                return
            }
            let cleaned = self.clean(raw)
            switch URLCleaning.outcome(for: cleaned, input: raw) {
            case .notAURL:
                notify.hud(icon: "link", message: s.urlCleanerNoURL)
            case .unchanged:
                notify.hud(icon: "checkmark.circle", message: s.urlCleanerNoChange)
            case .rewritten:
                cleaned.map { self.copy($0.url) }
                notify.hud(icon: "link", message: s.urlCleanerCleaned)
            case .removed(let names):
                cleaned.map { self.copy($0.url) }
                notify.hud(icon: "link",
                           message: String(format: s.urlCleanerRemovedFormat,
                                           names.joined(separator: ", ")))
            }
        }
    }

    /// What the automatic clean asks of each copy, on the clipboard lane.
    /// `rules` is read there, each time a link is about to be cleaned, so a
    /// rule changed in Settings holds from the next copy.
    nonisolated package static func rewriteRule(rules: @escaping @Sendable () -> URLCleaning.Rules)
        -> ClipboardRewriteRule {
        ClipboardRewriteRule(
            // The types decide before any content is read: a picture or a
            // file is never fetched only to be left alone.
            readsText: { URLCleaning.canRewritePasteboard(types: $0) },
            // The rewrite is for a link something was actually taken out of. A
            // copy with nothing to remove is left exactly as the user put it,
            // because writing to the pasteboard discards whatever else the copy
            // carried, and a link the cleaner did not need to touch is the one
            // most likely to come back spelled differently.
            replacement: { text in
                guard let cleaned = URLCleaning.clean(text, rules: rules()),
                      !cleaned.removed.isEmpty else { return nil }
                return ClipboardReplacement(text: cleaned.url, note: cleaned.removed)
            },
            // The rewrite drops the HTML, which is only right when the HTML adds
            // nothing to the link but formatting.
            dropsMarkup: { URLCleaning.markupAddsOnlyFormatting($0, to: $1) })
    }

    /// The saved rules. With no reader, the built-in rules alone.
    nonisolated private static func rules(_ storage: StorageReader?) -> URLCleaning.Rules {
        URLCleaning.rules(
            globalNames: storage?.value(for: Preferences.urlCleanerCustomParameters),
            siteNames: storage?.value(for: Preferences.urlCleanerSiteParameters),
            disabledNames: storage?.value(for: Preferences.urlCleanerDisabledParameters))
    }
}

extension URLCleanerService: BundledTool {
    /// Cleans the link on the clipboard once. The command bar's "Clean URL"
    /// row runs it. It asks for no surface: the row is the bar's own.
    package static let cleanClipboard: CommandID = {
        guard let id = ToolID(AppFeature.urlCleaner.rawValue),
              let command = CommandID(tool: id, name: "cleanClipboard")
        else { preconditionFailure("the URL cleaner's command is not valid") }
        return command
    }()

    package static let manifest: ToolManifest = {
        let feature = AppFeature.urlCleaner
        guard let clean = CommandDescriptor(id: cleanClipboard, title: feature.rawValue, symbol: feature.symbolName,
                                            surfaces: []),
              let tool = ToolDescriptor(id: cleanClipboard.tool, name: feature.rawValue, symbol: feature.symbolName,
                                        commands: [clean]),
              let storage = CapabilityRequest(.storage, reason: "Remembers whether automatic cleaning is on, and your rules."),
              let read = CapabilityRequest(.clipboardRead, reason: "Reads a link you copied, to clean it."),
              let rewrite = CapabilityRequest(.clipboardRewrite, reason: "Replaces a link you copied with the cleaned link."),
              let write = CapabilityRequest(.clipboardWrite, reason: "Copies a link you cleaned by hand."),
              let say = CapabilityRequest(.notify, reason: "Says what was taken out of a link."),
              let manifest = ToolManifest(
                  tool: tool, group: feature.group, capabilities: [storage, read, rewrite, write, say],
                  preferences: [
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerEnabled, default: .bool(false)),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerCustomParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerSiteParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.urlCleanerDisabledParameters, default: .string("")),
                      PreferenceDeclaration(key: DefaultsKey.panelUtilityURLCleaner, default: .bool(true)),
                  ],
                  activation: [.onLaunch, .onCommand, .onShown], enabledBy: DefaultsKey.urlCleanerEnabled)
        else { preconditionFailure("the URL cleaner's manifest is not valid") }
        return manifest
    }()
}
```

Read it against Task 1's file once more. What each member lost went to a place Tasks 3 to 5 built and tested:

- `syncWithPreferences()` is `ToolHost.sync`. `start()` is no longer private, because the host calls it.
- `start()` kept its first three lines' meaning: a second call only sets `isRunning`. The timer and the first look are the watcher's.
- `copy()` kept setting `lastCleaned` before the write. Calling off a waiting look and raising the count are inside `writeLink`.
- `stop()` kept setting `isRunning`. The timer and the waiting look are the watcher's.
- `run(_:)` is `CommandBarCatalog.cleanClipboardURL()`, line for line, with the pasteboard read and the four `QuickToolHUD.show` calls going through `services`.
- The publishing of `lastCleaned` and `lastRemoved` is the `onRewrite` closure, behind the same `isRunning` check.

If the compiler asks for `required` on `init(services:)`, the class has stopped being `final`: put `final` back.

In `Services/Platform/BundledTools.swift`:

```swift
    package static let all: [any BundledTool.Type] = [PortManagerService.self]
```
becomes
```swift
    package static let all: [any BundledTool.Type] = [PortManagerService.self, URLCleanerService.self]
```

- [ ] **Step 4: Point the views at the tool**

In both `UI/Settings/URLCleanerSettings.swift` and `UI/MenuPanel/PanelURLCleanerView.swift`:

```swift
    @ObservedObject private var cleaner = URLCleanerService.shared
```
becomes
```swift
    @ObservedObject private var cleaner = ToolHost.shared.tool(URLCleanerService.self)
```

and the Paste button's function, the same text in both files:

```swift
    private func paste() {
        GeneralPasteboardAccess.shared.async({
            NSPasteboard.general.string(forType: .string) ?? ""
        }, then: { pasted in
            self.input = pasted
        })
    }
```
becomes
```swift
    private func paste() {
        cleaner.pasteboardText { pasted in
            self.input = pasted
        }
    }
```

The comment above `paste()` moved to `pasteboardText`; replace it in both views with:

```swift
    /// The tool reads through the shared clipboard lane.
```

In `URLCleanerSettings.swift`:

```swift
                Toggle(l10n.s.urlCleanerEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        URLCleanerService.shared.syncWithPreferences()
                    }
```
becomes
```swift
                Toggle(l10n.s.urlCleanerEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        ToolHost.shared.sync(URLCleanerService.self)
                    }
```

In `PanelURLCleanerView.swift`:

```swift
                .onChange(of: autoClean) { _, _ in
                    URLCleanerService.shared.syncWithPreferences()
                }
```
becomes
```swift
                .onChange(of: autoClean) { _, _ in
                    ToolHost.shared.sync(URLCleanerService.self)
                }
```

The four `@AppStorage` lines in each view stay. They bind `urlCleanerEnabled`, `urlCleanerCustomParameters`, `urlCleanerSiteParameters` and `urlCleanerDisabledParameters`, and the manifest declares all four. Leave `import AppKit` in both files.

- [ ] **Step 5: Point the command bar at the tool**

In `Services/CommandBar/CommandBarCatalog.swift`, three edits.

1. The row keeps its id, title, subtitle, keywords and icon. Only what Return does changes:

```swift
                id: "action.cleanURL",
                title: bar.actionCleanURL,
                subtitle: area(.urlCleaner),
                keywords: s.urlCleanerName,
                icon: .symbol("link"),
                run: { _ in cleanClipboardURL() }))
```
becomes
```swift
                id: "action.cleanURL",
                title: bar.actionCleanURL,
                subtitle: area(.urlCleaner),
                keywords: s.urlCleanerName,
                icon: .symbol("link"),
                // The cleaner is a tool: its command runs through the registry.
                run: { _ in ToolRegistry.shared.run(URLCleanerService.cleanClipboard) }))
```

2. The selection row keeps its id and its HUD:

```swift
        if AppFeature.urlCleaner.isAvailable,
           let cleaned = URLCleanerService.shared.clean(text), cleaned.url != text {
```
becomes
```swift
        if AppFeature.urlCleaner.isAvailable,
           let cleaned = ToolHost.shared.tool(URLCleanerService.self).clean(text), cleaned.url != text {
```
and
```swift
                    URLCleanerService.shared.copy(cleaned.url)
```
becomes
```swift
                    ToolHost.shared.tool(URLCleanerService.self).copy(cleaned.url)
```

3. Delete `cleanClipboardURL()` whole: from the comment line `/// Reads through the shared lane like every other clipboard row: a direct` to its closing brace, the line before `/// Brightness lands on the display under the pointer`.

- [ ] **Step 6: Hand the cleaner to the host in `FeatureRuntime`, and take it off the quit list**

In `Services/FeatureRuntime.swift`, three edits.

```swift
        case .urlCleaner: return [.urlCleaner]
```
becomes
```swift
        // A tool: the tool host decides whether it runs.
        case .urlCleaner: return [.tool(URLCleanerService.manifest.id)]
```

Delete the `perform` arm:

```swift
        case .urlCleaner: URLCleanerService.shared.syncWithPreferences()
```

In `FeatureBindingAction`:

```swift
    case pastePlain, finderCutPaste, finderRename, shelf, urlCleaner, diskImageInstaller
```
becomes
```swift
    case pastePlain, finderCutPaste, finderRename, shelf, diskImageInstaller
```

In `App/AppDelegate.swift`, `applicationWillTerminate`, delete the line:

```swift
        URLCleanerService.shared.stop()
```

`ToolHost.shared.stopAll()`, at the top of that function since stage A, stops the cleaner when it was started, and builds nothing when it was not. The cleaner now stops a few lines earlier in the list than it did. Nothing in between depends on it.

- [ ] **Step 7: Run everything**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=clipboard --test_arg=--suite=platform --test_arg=--suite=features --test_arg=--suite=command-bar`
Expected: PASS. Every `URLCleanerTests` expectation written in Task 1 passes unchanged against the tool.

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian`
Expected: builds.

Run: `grep -rn "URLCleanerService.shared\|URLCleanerService.PollToken\|URLCleanerService.pollPasteboard\|cleanClipboardURL" apps/desktop/vitruvian/Sources apps/desktop/vitruvian/Tests`
Expected: no output.

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest`
Expected: PASS, every suite reporting.

Run: `bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

- [ ] **Step 8: Commit**

Append to the stage B entry in `UPSTREAM.md`:

```markdown
  - `Services/URLCleanerService.swift`: the URL cleaner is a tool. It has a manifest and one command, is built by the tool host with the services that manifest allows, and reads its rules, reads and rewrites the clipboard and shows its message only through the broker. Its singleton, its timer, its pasteboard code and the `Environment` this entry added above are gone.
  - `UI/Settings/URLCleanerSettings.swift`, `UI/MenuPanel/PanelURLCleanerView.swift`: get the tool from the host, tell the host when the switch flips, and ask the tool for the clipboard's text, where they called the service's singleton and the pasteboard.
  - `Services/CommandBar/CommandBarCatalog.swift`: the "Clean URL" row runs the tool's command through the registry, and the selection row calls the tool. `cleanClipboardURL()` moved into the tool. Both rows keep their ids.
  - `Services/FeatureRuntime.swift`: the URL cleaner's arm hands it to the tool host; its own binding action is gone.
  - `App/AppDelegate.swift`: the URL cleaner's line left the quit list. The tool host stops it, and no longer builds it at quit when it never ran.
  - `Tests/ClipboardFeatureTests.swift`: the link cleaner's four checks call the look where it lives now. Their expectations are unchanged.
```

```bash
git add apps/desktop/vitruvian/Sources/Vitruvian/Services/URLCleanerService.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/Settings/URLCleanerSettings.swift apps/desktop/vitruvian/Sources/Vitruvian/UI/MenuPanel/PanelURLCleanerView.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/FeatureRuntime.swift apps/desktop/vitruvian/Sources/Vitruvian/App/AppDelegate.swift apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/BundledTools.swift apps/desktop/vitruvian/Tests/URLCleanerTests.swift apps/desktop/vitruvian/Tests/ClipboardFeatureTests.swift apps/desktop/vitruvian/Tests/ToolBrokerTests.swift apps/desktop/vitruvian/Tests/FeatureRuntimeTests.swift apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): the URL cleaner reaches the system only through the broker"
```

---

### Task 7: Hold the URL cleaner's files to the broker in the lint

**Files:**
- Modify: `bazel/source_lints.py`
- Modify: `Tests/mutation_checks.py`, `UPSTREAM.md`

**Interfaces:**
- Produces: a second row in `MIGRATED_TOOLS`; `@AppStorage(Preferences.x)` read by the rule; `migrated_tool_key_problems`.

Three things change in the lint, and nothing is added to `TOOL_FILE_SINGLETONS` or taken out of `BROKERED`. The cleaner's files name `ToolHost`, `L10n` and `PanelInteractionState`, which are on the list already.

- [ ] **Step 1: Add the row**

In `bazel/source_lints.py`, `MIGRATED_TOOLS` gains:

```python
    "urlCleaner": {
        "files": [
            "Sources/Vitruvian/Services/URLCleanerService.swift",
            "Sources/Vitruvian/Core/URLCleaning.swift",
            "Sources/Vitruvian/UI/Settings/URLCleanerSettings.swift",
            "Sources/Vitruvian/UI/MenuPanel/PanelURLCleanerView.swift",
        ],
        "types": ["URLCleanerService", "URLCleaning"],
        "keys": [
            "urlCleanerEnabled",
            "urlCleanerCustomParameters",
            "urlCleanerSiteParameters",
            "urlCleanerDisabledParameters",
        ],
    },
```

`URLCleaning` is in `types` so that the broker can never call the cleaner's rules directly: they reach it only as a `ClipboardRewriteRule`. `panelUtilityURLCleaner` is not in `keys`: the manifest declares it, but the view that binds it is `MenuPanelView.swift`, which is not one of the cleaner's files.

- [ ] **Step 2: Read `@AppStorage(Preferences.x)`**

The cleaner's views bind their preferences as `@AppStorage(Preferences.urlCleanerEnabled)`. The rule reads only a quoted key or `DefaultsKey.x` today, and would report "it cannot read".

```python
_APP_STORAGE_KEY = re.compile(r'"([^"\\]*)"|DefaultsKey\.(\w+)')
```
becomes
```python
_APP_STORAGE_KEY = re.compile(r'"([^"\\]*)"|DefaultsKey\.(\w+)|Preferences\.(\w+)')
```

and in `migrated_tool_problems`:

```python
                    name = key and (key.group(1) or key.group(2))
```
becomes
```python
                    name = key and (key.group(1) or key.group(2) or key.group(3))
```

In the rule's self-test, add two lines to the end of `sample`:

```python
            "@AppStorage(Preferences.panelUtilityPortManager) private var typed: Bool",
            "@AppStorage(Preferences.somethingElse) private var stray: Bool",
```

and one entry to the expected list, between the `sample:13` entry and the `moved is listed` entry:

```python
        "sample:15 binds the preference somethingElse with @AppStorage; the tool "
        "sample may bind ['panelUtilityPortManager']",
```

- [ ] **Step 3: Keep the keys honest**

The rule reads `DefaultsKey.x` and `Preferences.x` as the key `x`. That holds only while the three are spelled alike, and a view may bind only a key the manifest declares. Add, above `migrated_tools_reach_services_through_the_broker`:

```python
def migrated_tool_key_problems(tools, source_of, defaults_keys, preferences):
    """Each preference a migrated tool's views may bind that its manifest does
    not declare, or that `DefaultsKey` and `Preferences` do not both spell as
    the key itself. The scan above reads `DefaultsKey.x` and `Preferences.x`
    as the key `x`, which holds only while the three agree."""
    problems = []
    for tool, row in tools.items():
        declared = set()
        for path in row["files"]:
            declared.update(
                re.findall(
                    r"PreferenceDeclaration\(\s*key:\s*DefaultsKey\.(\w+)",
                    source_of(path) or "",
                )
            )
        for key in row["keys"]:
            if key not in declared:
                problems.append(
                    f"the tool {tool} may bind the preference {key} in a view, "
                    "and no manifest in its files declares it"
                )
            named = re.search(
                r"static let " + re.escape(key) + r'\s*=\s*"' + re.escape(key) + r'"',
                defaults_keys,
            )
            typed = re.search(
                r"static let "
                + re.escape(key)
                + r"\s*=\s*Preference\(\s*DefaultsKey\."
                + re.escape(key)
                + r"\b",
                preferences,
            )
            if not (named and typed):
                problems.append(
                    f"the tool {tool} lists the preference {key}, which DefaultsKey "
                    "and Preferences do not both declare under that name"
                )
    return problems
```

In `migrated_tools_reach_services_through_the_broker`, before the last `problems.extend(...)`, test it on a sample and then run it on the app:

```python
    key_sample = migrated_tool_key_problems(
        {"sample": {"files": ["tool"], "types": [], "keys": ["alpha", "beta", "gamma"]}},
        {
            "tool": "PreferenceDeclaration(key: DefaultsKey.alpha, default: .bool(true)),\n"
            "PreferenceDeclaration(key: DefaultsKey.beta, default: .bool(true))"
        }.get,
        'static let alpha = "alpha"\nstatic let beta = "other"\nstatic let gamma = "gamma"',
        "static let alpha = Preference(DefaultsKey.alpha, default: true)\n"
        "static let beta = Preference(DefaultsKey.beta, default: true)\n"
        "static let gamma = Preference(\n    DefaultsKey.gamma, default: true)",
    )
    if key_sample != [
        "the tool sample lists the preference beta, which DefaultsKey and "
        "Preferences do not both declare under that name",
        "the tool sample may bind the preference gamma in a view, and no "
        "manifest in its files declares it",
    ]:
        problems.append(
            "the scan finds a key spelled apart and a key no manifest declares, "
            "and not a key declared and spelled alike"
        )
    problems.extend(
        migrated_tool_key_problems(
            MIGRATED_TOOLS,
            repo.sources.get,
            repo.source(APP_PREFIX + "Core/DefaultsKey.swift"),
            repo.source(PREFERENCES_PATH),
        )
    )
```

- [ ] **Step 4: Prove the rules see the app**

Run: `bazel run //tools/format -- apps/desktop/vitruvian/bazel/source_lints.py`

Run: `bazel test //apps/desktop/vitruvian:source_lints_test`
Expected: PASS.

Then, one at a time, make each change, run the test and confirm it FAILS naming the line. Undo each by reversing the edit by hand (not with `git checkout` or `git stash`), and confirm `git diff --stat -- <file>` prints nothing:

1. In `URLCleanerSettings.swift`, add `_ = NSPasteboard.general` inside `paste()`.
2. In `URLCleanerService.swift`, add `_ = ClipboardHistoryService.shared` inside `stop()`.
3. In `PanelURLCleanerView.swift`, add `@AppStorage(Preferences.clipboardHistoryEnabled) private var stray: Bool` under the other four.
4. In `Services/Platform/Broker/ClipboardRewrite.swift`, add `_ = URLCleaning.allSites` inside `write`.

Put the four failing outputs in the report.

- [ ] **Step 5: Plant four regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of `MUTATIONS` (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("the clipboard is rewritten after it changed under the look", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/ClipboardRewrite.swift",
     "        guard pasteboard.changeCount == changeCount else {\n            return ClipboardPoll(changeCount: changeCount, replaced: nil)\n        }\n",
     "",
     "a copy that changed while the rule was deciding is not overwritten"),
    ("a watch takes its own rewrite for a new copy", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/ClipboardWatcher.swift",
     "                watch.lastChangeCount = result.changeCount\n",
     "",
     "a copy is rewritten once: the watch's own rewrite is not a new copy to it"),
    ("a tool reads a preference its manifest does not declare", "platform",
     "Sources/Vitruvian/Services/Platform/Broker/StorageAccess.swift",
     "        guard keys.contains(preference.key) else {\n            undeclared(preference.key)\n            return preference.defaultValue\n        }\n",
     "",
     "a preference the manifest does not declare is not read, and is reported as a mistake"),
    ("the host starts a tool that is switched off", "platform",
     "Sources/Vitruvian/Services/Platform/ToolHost.swift",
     "        if let key = manifest.enabledBy, (broker.backings.storage.read(key) as? Bool) != true { return false }\n",
     "",
     "installed true, switched on false: the host leaves the tool unbuilt"),
```

Each "before" text must occur exactly once in its file, and must quote the file exactly: if the code differs from this plan, use the code. For each entry: apply it, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`, confirm it fails with the sixth field among the messages, undo it, confirm `git diff --stat -- <file>` prints nothing. If a mutation is not detected, stop and report: do not adjust a test to fit.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/Tests/mutation_checks.py`

- [ ] **Step 6: Commit**

Append to the stage B entry in `UPSTREAM.md`:

```markdown
  - `bazel/source_lints.py`: the URL cleaner's four files join `MIGRATED_TOOLS`. The rule now reads `@AppStorage(Preferences.x)`, and fails when a key a tool's views may bind is not declared by its manifest, or is not spelled alike in `DefaultsKey` and `Preferences`.
  - `Tests/mutation_checks.py`: four mutations (a rewrite after the clipboard changed under the look; a watch taking its own rewrite for a new copy; a tool reading a preference it did not declare; the host starting a tool that is switched off).
```

```bash
git add apps/desktop/vitruvian/bazel/source_lints.py apps/desktop/vitruvian/Tests/mutation_checks.py apps/desktop/vitruvian/UPSTREAM.md
git commit -m "refactor(desktop): hold the URL cleaner's files to the broker in the lint"
```

---

### Task 8: Document, and check by hand

**Files:**
- Modify: `AGENTS.md`, `UPSTREAM.md`
- Modify: `docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md`

- [ ] **Step 1: Write the rules down**

In `AGENTS.md`, directly after the bullet that ends "A test for a new operation asserts that a refused call did no work.", add:

```markdown
- A tool's background work is in `start()` and `stop()`, and `ToolHost`
  calls them: at launch, when the hub installs or removes the tool, when its
  switch flips and when a grant changes. A tool never asks whether it is
  installed or switched on. `start()` is called every time the host finds
  the tool should run, so it must be safe to call twice. A new tool is added
  to `BundledTools.all`, and its arm in `FeatureRuntime.actions(for:in:)`
  returns `.tool(id)` when its manifest says `onLaunch`.
- Nothing watches the preferences. Code that flips a tool's switch tells the
  host: a view calls `ToolHost.shared.sync(X.self)`, and the command bar's
  toggle rows go through `FeatureRuntime.sync`.
- A tool's command is in its manifest, with the surfaces it asks for.
  `BuiltinTools` registers the manifest's descriptor and wires the command
  to `ToolHost.run`. A row that existed before the tool keeps its id and
  runs the command through `ToolRegistry`; the command then asks for no
  surface, so no second row appears. A command takes no argument: a row
  that needs one, such as the selected text, calls a method on the tool.
- The clipboard is looked at in one place, `ClipboardWatcher`, on one timer
  that runs while a tool asks. A tool that rewrites copies hands the broker
  a `ClipboardRewriteRule`. Its functions run on the clipboard lane in the
  middle of one look, so they take plain values, answer at once and capture
  no app state. Besides a completion, it is the only kind of function that
  crosses the broker.
- A tool reads a preference through `services.storage.reader()`, and only a
  key its manifest declares. Its views may bind those keys with
  `@AppStorage`; `source_lints_test` fails on any other.
```

In the bullet above them that begins "A feature that has become a tool has a manifest", change "the clipboard, a link, a beep, the listening-sockets report, ending a process" (it wraps across two lines) to "the clipboard, its preferences, a link, a beep or a message, the listening-sockets report, ending a process".

- [ ] **Step 2: Bring the spec in line with what was built**

In the spec:

- Section 4, last paragraph: after "no view types cross the broker", add that two in-process forms stand in for messages. A completion closure is a reply. A `ClipboardRewriteRule` is a question the host asks the tool in the middle of one clipboard look and waits for; its functions take and return plain values and capture no app state. Sub-project 3 decides how a tool in another process answers it.
- Section 6, "As built in stage A": retitle it "As built" and say that stage B added `start`, `run`, `canRun`, the run rule (`ToolHost.shouldRun`), `ToolHost.sync` and the `FeatureRuntime` action `tool(ToolID)`. The grant clause of the rule is written and first reached in stage C.
- Section 6, "When the host re-decides": add that nothing watches the preferences. Whoever flips a tool's switch tells the host, as each caller told the service before.
- Section 6, "Commands": `BuiltinTools` keeps registering every hub feature. For a feature with a manifest it registers the manifest's descriptor and sets handlers that call the host. The `action.cleanURL` row stays hand-built and runs `urlCleaner/cleanClipboard`, which asks for no surface. The `selection.cleanLink` row calls two methods on the tool, because a command takes no argument.
- Section 7.2, the table:
  - `notify`: `hud(icon, message)` is built in stage B.
  - `clipboard.write`: add `writeLink(link)`, a link as text and as a URL, signed as the app's own. First needed by the URL cleaner.
  - `clipboard.read`: `readText()` only. No plain stream of changes is built; none has a user.
  - `clipboard.rewrite`: `rewriteLinks(rule)` and `stopRewritingLinks()`, replacing `rewrite(ifChangeCount:, with:)`. Backed by the lane and the broker's watcher.
  - `storage`: `reader()`, which gives a value with `value(for:)`. No `set`.
- Section 7.2, the note on `clipboard.rewrite`: replace it. The tool hands the broker a rule. On each tick the broker runs one job on the clipboard lane: read the count, ask the rule about the types, read the text, ask the rule for a replacement, ask about the HTML when there is any, check the count again, write. One job, because clipboard history shares the lane and must never see the clipboard half way, and because the types must say yes before any content is read. The broker keeps a foreign source marker and the remote-clipboard marker. It does **not** tell clipboard history to ignore the change: today's code never did, and history records the cleaned link as a copy of its own.
- Section 10, by hand, URL cleaner: "clipboard history shows one entry, not two" becomes "clipboard history shows the entries it showed before the change". Add why: the two features have a timer each, and when history's fires first it records the raw link and then the cleaned one.
- Section 11: mark stage B built, with the pull request number once it exists. Its capabilities are `storage`, `clipboard.read`, `clipboard.rewrite`; it also added `writeLink` to `clipboard.write` and `hud` to `notify`.
- Section 13: add that the stage B plan is `docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-b.md`, and that it changes five details of this spec, listed in its decisions table.

- [ ] **Step 3: Run everything**

With the display awake and the screen unlocked, from the repository root:

```sh
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
```

Expected: all pass, every unit suite reports, the build succeeds.

- [ ] **Step 4: Check by hand**

These steps are done by a person, at a Mac, with the built app. No unit test reads the real clipboard, fires a real timer or opens the command bar.

Build two copies to compare: this branch, and the commit this branch started from (the stage A merge, before Task 1). Run one at a time: they share one set of preferences.

```sh
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
rm -rf /tmp/vitruvian && ditto -x -k bazel-bin/apps/desktop/vitruvian/Vitruvian.zip /tmp/vitruvian && open /tmp/vitruvian/Vitruvian.app
```

For the copy to compare against, run the same build in a second worktree checked out at that commit, and unzip it to `/tmp/vitruvian-before`.

In the Features hub, have Clean URL and Clipboard history installed. Switch clipboard history on. The link used below is `https://example.com/path?utm_source=news&id=42`.

1. Settings › Clean URL: switch automatic cleaning on. "Active now" appears under the switch.
2. Copy the link in any app. Within about a second, paste it somewhere: it reads `https://example.com/path?id=42`. The Settings page names `utm_source` as what was taken out.
3. Open clipboard history. Note the entries that copy left. Do steps 1 to 3 on the copy from before this change, starting each app fresh. The entries must be the same on both. Expect two when both features were on at launch (the raw link, then the cleaned one): that is today's behaviour, not a fault of this change. Record what each build showed.
4. A copy that names its source keeps the name. In Terminal:
   ```sh
   swift -e 'import AppKit; let p = NSPasteboard.general; p.clearContents(); p.setString("com.example.reader", forType: NSPasteboard.PasteboardType("org.nspasteboard.source")); p.setString("https://example.com/path?utm_source=news&id=42", forType: .string)'
   sleep 2
   swift -e 'import AppKit; let p = NSPasteboard.general; print(p.string(forType: .string) ?? "-", p.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) ?? "-")'
   ```
   Expected output: `https://example.com/path?id=42 com.example.reader`.
5. In a browser, use Copy Image on a picture. Paste into Preview or Notes: the picture arrives. Copy `https://example.com/?id=42`: it pastes unchanged.
6. Switch automatic cleaning off. "Active now" goes. Copy the link, wait two seconds, paste: it still has `utm_source`.
7. Open the menu panel's Clean URL, and the Quick panel's tile. The switch shows the state Settings shows, and flipping it in one shows in the other. Paste fills the field from the clipboard. Copy puts the cleaned link on the clipboard and the line under the field says it was copied.
8. On the copy from before this change, open the command bar, find "Clean URL", and pin it or give it a name. Quit. Open this branch's build: the row is where it was, pinned or named as before, and there is one of it. With the link on the clipboard, run it: the heads-up message names `utm_source` and the clipboard holds the cleaned link. With plain text on the clipboard, run it: the message says there is no link.
9. Select the link in a text editor and open the command bar. The selection's "Clean URL" row is offered. Run it: the cleaned link is on the clipboard and the message names `utm_source`.
10. In the command bar, run the row that turns Clean URL on, then the one that turns it off. Settings shows "Active now" come and go.
11. In the Features hub, remove Clean URL. Copy the link: it is left alone. Its rows are gone from the command bar. Install it again: it works as before, with the switch as it was left.
12. With automatic cleaning on, quit and reopen the app. Copy the link: it is cleaned. Nothing was switched on by hand.

Record the Mac model, the macOS version and the result of each of the twelve in the pull request. Say plainly which, if any, were not done.

- [ ] **Step 5: Finish the `UPSTREAM.md` entry, commit, and open the pull request**

Add as the first sub-bullet of the stage B entry in `UPSTREAM.md`:

```markdown
  - New files, none with an upstream header: `Services/Platform/Broker/StorageAccess.swift` (a tool's preferences), `Services/Platform/Broker/ClipboardRewrite.swift` (one look at the clipboard), `Services/Platform/Broker/ClipboardWatcher.swift` (the one timer that looks, for the tools that ask), `Services/Platform/BundledTools.swift` (the list of tools), with their tests in `Tests/ToolBrokerTests.swift` and `Tests/URLCleanerTests.swift`.
```

```bash
git add apps/desktop/vitruvian/AGENTS.md apps/desktop/vitruvian/UPSTREAM.md docs/superpowers/specs/2026-10-09-vitruvian-broker-and-bundled-tools-design.md
git commit -m "refactor(desktop): document a tool's start, its commands and its clipboard watch"
```

Open one pull request. Its description states what was run, on which Mac and macOS version, the twelve hand checks and their results, and what remains untested: the command bar's two rows have no unit test, only checks 8 and 9. Its title is a `refactor`: merging it cuts no release.

---

## What stage B leaves for stage C

- The `hotkey` and `keystrokes` capabilities, and with `keystrokes` the first macOS grant a capability rides on. That brings the first test of the run rule's grant clause, of `notGranted`, and of a permission change reaching the host. The path is there already: `FeatureRuntime.permissionDidChange` syncs every feature that declares the permission, and a tool's arm is `.tool(id)`.
- A way for a manifest to say its tool may start without its grant. Paste as plain text registers its hotkey and asks on first press.
- `CapabilityBroker.Environment.live.isGranted` reads `Permissions.shared`. Its init publishes the grants one main-queue hop later, so it would answer false if the broker were the very first thing to touch `Permissions`. The URL cleaner needs no grant, so this is still not reached. Stage C must make sure `Permissions` exists before the host's first decision at launch, and test it.
- Commands that take an argument. Until then a row that needs one calls a method on the tool, as `selection.cleanLink` does.
- `storage.set`, a plain stream of clipboard changes, and an observer for a preference changed from outside the app. Each arrives with the first tool that needs it.
- How a tool in another process answers a `ClipboardRewriteRule` while the host holds the clipboard lane. That is sub-project 3's question, and this stage's decision 2 is what it has to answer.
- Clipboard history and clipboard auto-clear still have a timer each. Merging them into the broker's watch is theirs to do when they migrate, and it is the change that could make "one entry, not two" true.
- `TransientPaste`, which Paste as plain text and text snippets share, and which calls `ClipboardHistoryService.ignoreNextChange`. That call is real there, and belongs behind `keystrokes.paste`.
