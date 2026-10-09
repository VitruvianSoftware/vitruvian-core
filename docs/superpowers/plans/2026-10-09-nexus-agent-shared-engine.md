# Nexus Agent shared engine (step 2a of the shared library) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nexus Agent's bot runner, `.env` handling, agent turns, session list and chat session state exist once, in the shared library, with everything app-specific handed in by the app.

**Architecture:** Vitruvian's `NexusAgentService` is split in place into an app-neutral base class (`NexusAgentEngine`) and what only Vitruvian needs (the floating window, the global shortcut, the notch). The base class and `NexusAgentQuickPromptSession` reach the app only through a small `NexusAgentHost` protocol. They then move to `NexusAgentCore`. Vitruvian's `NexusAgentService` stays, as a subclass of the engine, so no other Vitruvian file and no existing test changes.

**Tech Stack:** Swift 6 language mode (must also compile on Swift 6.1.2, the public mirror's toolchain), Combine, AppKit only where the code already uses it, Bazel (`--config=macos-app`), SwiftPM for the mirror, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, section 9 step 2 and section 6. This plan is the first half of that step. The second half (step 2b: the standalone app replaces its own `BotManager` and `ConfigManager` with the engine) changes what standalone users see and gets its own plan.

## Global Constraints

- **No behaviour change in Vitruvian.** `apps/desktop/vitruvian/Tests/NexusAgentTests.swift` is the proof: its 175 `suite.expect` checks pass with no edit to any condition or message. The only edits allowed in that file are ones the compiler forces (an import, a type name).
- **No change to the standalone app's code** (`apps/desktop/nexus-agent/macos/Sources/NexusAgent/`). It gains shared code it does not call yet.
- Nothing in `NexusAgentCore` imports a `Vitruvian*` module or SwiftUI. Foundation, Combine, Darwin, CoreGraphics and AppKit are allowed.
- Only files whose header names VitruvianSoftware alone, with no upstream author in `git log --follow`, may leave `apps/desktop/vitruvian`. Moved files carry the MIT header used in `apps/desktop/nexus-agent`.
- Code in `NexusAgentCore` compiles in Swift 6 mode on Swift 6.1.2. Do not silence concurrency checking with `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` unless the code moved already had it; if the older compiler needs one, say why in a comment and in the report.
- After any change under `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore`: run `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and add a line to the dated log in `apps/desktop/vitruvian/UPSTREAM.md`.
- `apps/desktop/nexus-agent/macos/BUILD` and `Package.swift` declare the same targets.
- Every Swift Bazel command needs `--config=macos-app`; Swift targets are `manual`, so name them.
- Before the last commit: `bazel run //:tidy`, then discard any change it makes to `gazelle_python.yaml`.
- `.github/workflows/presubmit.yaml` is generated (`bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml`); this plan should not need to change it.
- Vitruvian's `notch` and `switcher` test suites fail on a Mac whose screen is locked. That is the machine, not the change; every other suite must pass, and CI decides those two.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A setting read at the wrong time.** The engine used to read `Preferences` on every call (bot folder, auto-start, plan mode). A host that caches a value instead of reading it live changes behaviour when the user edits Settings while the app runs. Pinned by Task 1's host tests (change the stored value, read again).
2. **A turn that finishes while the window is hidden.** Today that posts a system notification and a notch notice, with the provider's name in the title. Losing either in the move is silent. Pinned by Task 1 and Task 3 (a recording host).
3. **A session built without a service.** `NexusAgentQuickPromptSession(environment:)` is constructed alone in tests, and `archive`/`unarchive` then fall back to `NexusAgentService.shared`. The engine cannot name that type. Pinned by Task 1 Step 3 and the existing `sessionArchiving` suite.
4. **The standalone gets Vitruvian's saved-settings key.** `"vitruvian.claude.hiddenSessionIds"` is read and written on `UserDefaults.standard`. It must come from the host, so the standalone does not inherit another app's key in step 2b. Pinned by Task 3.
5. **Swift 6.1.2 rejects what 6.4 accepts.** `Process`/`FileHandle` captured in a detached thread and in a termination handler are the likely spots. The `Nexus Agent Mirror Toolchain` CI job decides; Task 2 Step 6 says what to do if it is red.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentHost.swift` | new (written in Task 1 under Vitruvian, moved in Task 2) | the protocol and the strings value the engine asks its app for |
| `…/NexusAgentCore/NexusAgentEngine.swift` | new, from most of `NexusAgentService.swift` | bot runner, `.env`, agent turns, session list, archive |
| `…/NexusAgentCore/NexusAgentQuickPromptSession.swift` | moved | chat session state |
| `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/NexusAgentService.swift` | shrinks | Vitruvian's subclass: window, shortcut, notch docking, `shared` |
| `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/VitruvianNexusAgentHost.swift` | new | answers the host protocol from `Preferences`, strings, `Notifier`, `NotchService` |
| `apps/desktop/nexus-agent/macos/Tests/EngineHostTests.swift` | new | the seam, with a recording host |

---

### Task 1: Split the service in place, behind a host

Everything in this task stays inside `apps/desktop/vitruvian` and keeps `package` access. Nothing moves yet. The point is to make the logic change reviewable on its own, with the existing tests as the judge.

**Files:**
- Create: `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/NexusAgentHost.swift`
- Create: `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/NexusAgentEngine.swift`
- Create: `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/VitruvianNexusAgentHost.swift`
- Modify: `…/Services/NexusAgent/NexusAgentService.swift`, `…/Services/NexusAgent/NexusAgentQuickPromptSession.swift`
- Modify (compiler-forced only): `apps/desktop/vitruvian/Tests/NexusAgentTests.swift`

**Interfaces:**
- Produces, all `package` for now:

```swift
/// What the shared Nexus Agent code asks the app it runs in.
@MainActor
package protocol NexusAgentHost: AnyObject {
    /// The bot folder as the user configured it; empty means the standard one.
    var configuredBotDirectory: String { get }
    /// Whether the bot starts with the app.
    var startsBotAtLaunch: Bool { get }
    /// Plan mode, remembered between launches.
    var planMode: Bool { get set }
    /// Claude sessions the user archived here.
    var hiddenClaudeSessionIDs: [String] { get set }
    /// User-facing text, in the app's language right now.
    var strings: NexusAgentHostStrings { get }
    /// A turn paused for the user to approve a tool.
    func turnNeedsApproval(_ notice: NexusAgentTurnNotice)
    /// A turn ended. `isChatVisible` is false when the user cannot see it.
    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool)
}
```

`NexusAgentHostStrings` is a `Sendable` struct of `String` fields with a `package init` whose defaults are today's English text. Its fields are exactly the text the two files show a user: the five `NexusAgentFeatureStrings` fields the session reads (`untitledSession`, `missingAgent`, `agentFailed`, `replyStopped`, `emptyReply`) and one field for each hard-coded English fragment listed in Step 2. `NexusAgentTurnNotice` is a `Sendable` struct carrying exactly the values today's call sites compute before they call `Notifier` or `NotchService` (provider name, the reply or tool text, whether it failed); name its fields after what they hold.

- `package class NexusAgentEngine: NSObject, ObservableObject` (`@MainActor`), `init(environment: Environment, host: NexusAgentHost)`, holding everything in the service except the window, the shortcut and notch docking. `Environment` becomes `NexusAgentEngine.Environment`.
- `package final class NexusAgentService: NexusAgentEngine, NSWindowDelegate`, `init(environment: Environment)`, `static let shared`. Every member other Vitruvian files and the tests use today keeps its name, signature and observable behaviour.

- [ ] **Step 1: Record the baseline**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_output=errors`
Record which suites print `OK` and the `utilities` check count (530 on the starting commit). This is what "no behaviour change" is measured against.

- [ ] **Step 2: Write the host protocol and Vitruvian's answer to it**

Write `NexusAgentHost.swift` with the protocol above, `NexusAgentHostStrings` and `NexusAgentTurnNotice`.

The hard-coded English fragments that become string fields, each keeping its exact current text as the default (find them by content; line numbers are from the starting commit):
- `NexusAgentQuickPromptSession.swift` ~270 (the "Resumed …" line), ~416 (the "Using …" activity line), ~428 and ~473 (the " — Approval Required", " — Failed", " — Done" title suffixes)
- `NexusAgentService.swift` ~198 and ~201 (the same " — Failed" / " — Done" suffixes in the notification titles)

Where a fragment is a template around a value (a tool or provider name), make the field a function of that value or a prefix/suffix pair, whichever reproduces today's output byte for byte.

Write `VitruvianNexusAgentHost.swift`: a `@MainActor final class VitruvianNexusAgentHost: NexusAgentHost` built with `init(defaults: UserDefaults)`. It reads and writes **live**, never cached:
- `configuredBotDirectory` → `defaults[Preferences.nexusAgentBotDirectory]`
- `startsBotAtLaunch` → `defaults[Preferences.nexusAgentAutoStart]`
- `planMode` → `defaults[Preferences.nexusAgentPlanMode]`
- `hiddenClaudeSessionIDs` → the `"vitruvian.claude.hiddenSessionIds"` string array on `UserDefaults.standard`, exactly where the service reads and writes it today (it bypasses `environment.defaults` today; keep that)
- `strings` → built from `FeatureStrings.nexusAgent(L10n.shared.language)` for the five translated fields, defaults for the rest
- `turnNeedsApproval` → the `NotchService.shared.show(NotchNotice(event: .agents, …))` call the session makes today for an approval
- `turnFinished` → the session's notch notice for done/failed, the `NSSound` it plays, and, when `isChatVisible` is false, the two `Notifier.post` calls from the service's `init`, with the same titles, bodies and truncation

Keep the order of effects the same as today within one turn.

- [ ] **Step 3: Split the class**

Create `NexusAgentEngine.swift` by moving code out of `NexusAgentService.swift` unchanged, then replacing each Vitruvian reference with a host call:

| Stays in `NexusAgentService` (subclass) | Moves to `NexusAgentEngine` |
|---|---|
| `shared`, `hotkey`, `panel`, `modeObserver`, the three event monitors, `isPinned`, `shortcutRegistrationFailed` | every other stored property, including `session`, `managedPID`, `pollTimer`, `didAutoStart` |
| `syncWithPreferences`, `suspend`, `prepareForQuit` | `Environment`, `Environment.live`, `Problem`, `stopGrace` |
| `isQuickPromptVisible`, `toggle/show/hideQuickPrompt`, `dockToNotch`, `KeyablePromptPanel`, `ensurePanel`, `apply`, `windowWillResize`, the monitors | paths, `load`, `save`, `updateActiveProvider`, `activeProvider` |
| | bot lifecycle and polling; `sendQuickPrompt`, `retryQuickPrompt`, `launchAgentProcess` |
| | every session, transcript and archive function |

Rules for the split:
- `syncWithPreferences` mixes both halves. Give the engine two methods that hold its part, with the bodies moved verbatim: one for "the feature was uninstalled: stop polling, stop the session, stop the bot, forget auto-start", one for "once per launch: refresh status and start the bot if the host says so". The subclass's `syncWithPreferences` calls them in today's order around its own shortcut and window lines. `prepareForQuit` likewise.
- The engine learns whether the chat is on screen through one overridable member, `var isChatVisible: Bool { false }`, which the subclass overrides with `panel?.isVisible == true`. The engine's `init` wires `session.onTurnFinished` to `host.turnFinished(_:isChatVisible:)`.
- A `@Published … private(set)` property the subclass must assign becomes settable from the subclass; one that only the engine assigns stays `private(set)`.
- The session's `service` reference becomes `weak var engine: NexusAgentEngine?`. Its fallback to `NexusAgentService.shared` in `archive` and `unarchive` cannot stay: read what the two instance wrappers (`archiveSession`, `unarchiveSession`) need, and make the session able to do the same work without an engine (they wrap `nonisolated static` functions; pass the host's hidden-id list where the `UserDefaults.standard` literal was). A session built alone must archive exactly as it does today.
- The session takes the host too: `init(environment:host:)`. `planMode` reads and writes through it; the strings come from it at the moment they are used, as today.
- `NexusAgentService.init(environment:)` builds `VitruvianNexusAgentHost(defaults: environment.defaults)` and passes it up.
- The test file constructs `NexusAgentQuickPromptSession(environment:)` and names `NexusAgentService.Environment`. Nested types are reachable through the subclass name; if the compiler disagrees add `package typealias Environment = NexusAgentEngine.Environment` to the subclass. For the session initialiser, change the call sites in the test to pass `host: VitruvianNexusAgentHost(defaults: <the same defaults the test's environment uses>)`. That is the only kind of test edit allowed.

- [ ] **Step 4: Build, then run the tests**

```
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_output=errors
bazel test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test --test_output=errors
```

Expected: the same suites `OK` as in Step 1 and `utilities: OK (530 checks)`. Then prove the count of conditions did not move:

`grep -c "suite.expect" apps/desktop/vitruvian/Tests/NexusAgentTests.swift` → 175, and `git diff --stat` on that file shows only the initialiser call sites.

- [ ] **Step 5: Prove the host is read live**

Add one suite to `NexusAgentTests.swift`, called from `run(_:)`, in the file's existing style:

```swift
    /// The host answers from the saved settings at the moment it is asked.
    private static func hostReadsLive(_ suite: TestSuite) {
        let name = "nexus-agent-host-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "a private defaults suite can be made")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        let host = VitruvianNexusAgentHost(defaults: defaults)

        defaults[Preferences.nexusAgentBotDirectory] = "~/one"
        suite.expect(host.configuredBotDirectory == "~/one", "the host reads the bot folder")
        defaults[Preferences.nexusAgentBotDirectory] = "~/two"
        suite.expect(host.configuredBotDirectory == "~/two", "a changed bot folder is seen without a restart")

        defaults[Preferences.nexusAgentAutoStart] = true
        suite.expect(host.startsBotAtLaunch, "the host reads start-with-app")
        defaults[Preferences.nexusAgentAutoStart] = false
        suite.expect(!host.startsBotAtLaunch, "a changed start-with-app is seen without a restart")

        host.planMode = true
        suite.expect(defaults[Preferences.nexusAgentPlanMode], "plan mode is saved through the host")
        suite.expect(host.strings.untitledSession
                     == FeatureStrings.nexusAgent(L10n.shared.language).untitledSession,
                     "text comes from the app's translations")
    }
```

Run the unit tests again. Expected: `utilities` rises by exactly 6.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/vitruvian
git commit -m "refactor(desktop): split Nexus Agent's service into an app-neutral engine and Vitruvian's window"
```

---

### Task 2: Move the engine, the session and the host protocol to the shared library

**Files:**
- Move: `apps/desktop/vitruvian/Sources/Vitruvian/Services/NexusAgent/{NexusAgentHost,NexusAgentEngine,NexusAgentQuickPromptSession}.swift` → `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`, `apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256`, and `build.sh` + `bazel/sources.bzl` only if either file is listed there

**Interfaces:**
- Consumes: Task 1's three files.
- Produces: the same declarations, `public`, in module `NexusAgentCore`. `NexusAgentEngine` is `open` with the members the subclass overrides or assigns marked `open`/`public` as the compiler requires.

- [ ] **Step 1: Licence check**

For each of `NexusAgentService.swift` and `NexusAgentQuickPromptSession.swift` (the history of the code being moved): read the first three lines and run `git log --follow --format='%an' -- <path>`. Expected: the header names VitruvianSoftware alone and every author is James Nguyen or a `vitruvian-*-agent[bot]`. Put the output in the report. If an upstream author appears, stop.

- [ ] **Step 2: Move and convert**

`git mv` the three files. In each: replace `package` access with `public` on every declaration (and `open` on the engine class and on members the Vitruvian subclass overrides), replace the two-line GPL header with the 19-line MIT notice from the top of `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/VersionCompare.swift`, and replace any "Adapted from the standalone…" paragraph with:

```swift
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).
```

Remove `import VitruvianCore` / `import VitruvianDesign` from the moved files. Anything that then fails to resolve is a Vitruvian dependency Task 1 missed: route it through the host, do not copy Vitruvian code across.

`grep -nE '^\s*package ' <the three files>` must print nothing.

- [ ] **Step 3: Build both ways**

```
bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentCore //apps/desktop/nexus-agent/macos:NexusAgent //apps/desktop/vitruvian:Vitruvian
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
```

Expected: all succeed. `mirror_build_test` proves the files compile under SwiftPM as well.

- [ ] **Step 4: Record the move and re-pin**

In `apps/desktop/vitruvian/UPSTREAM.md`, add two rows to the table under "Files released under MIT by their copyright holder" (date 2026-10-09; `Services/NexusAgent/NexusAgentService.swift` "in part: the engine" and `Services/NexusAgent/NexusAgentQuickPromptSession.swift`), and one line to the dated log in the style of the entries above it:

```markdown
- **2026-10-09**: Nexus Agent's bot runner, `.env` handling, agent turns, session list and chat session state moved to the shared `NexusAgentCore` library as `NexusAgentEngine` and `NexusAgentQuickPromptSession`. `NexusAgentService` here is now a subclass that adds the floating window, the shortcut and notch docking, and `VitruvianNexusAgentHost` answers the engine from this app's settings, translations and notch. No behaviour change.
```

Run `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared`, then `bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test --test_output=errors`. Expected: PASS.

- [ ] **Step 5: The full test set**

```
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_output=errors
grep -c "suite.expect" apps/desktop/vitruvian/Tests/NexusAgentTests.swift
```

Expected: the same suites `OK` as Task 1 Step 5; 181 (175 + 6).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/vitruvian apps/desktop/nexus-agent/macos/Sources/NexusAgentCore
git commit -m "refactor(desktop): build Vitruvian's Nexus Agent engine and chat session from the shared core"
```

If, after the branch is pushed, the `Nexus Agent Mirror Toolchain` job is red: the error is Swift 6.1.2 rejecting something 6.4 accepts. Fix the code so both accept it (make the captured value `Sendable`, move it inside the closure, or pass it as a parameter). Do not relax the language mode.

---

### Task 3: Test the seam beside the shared code

**Files:**
- Create: `apps/desktop/nexus-agent/macos/Tests/EngineHostTests.swift`

**Interfaces:**
- Consumes: `NexusAgentEngine`, `NexusAgentEngine.Environment`, `NexusAgentHost`, `NexusAgentHostStrings`, `NexusAgentTurnNotice`, `NexusAgentQuickPromptSession` from `NexusAgentCore`.

- [ ] **Step 1: Write the tests**

`EngineHostTests.swift`, MIT header, `import XCTest`, `import NexusAgentCore`, one `@MainActor final class EngineHostTests: XCTestCase` with a `private final class RecordingHost: NexusAgentHost` whose properties are plain stored vars and whose two methods append what they were given to arrays. Build the engine's `Environment` from in-memory closures (a `[String: String]` of files, no real process is ever launched), the way `Rig` in `apps/desktop/vitruvian/Tests/NexusAgentTests.swift` does, using only `NexusAgentCore` types.

The tests, each asserting real behaviour of the engine or session through the host:

1. `testBotFolderComesFromTheHost`: with `configuredBotDirectory = ""` the engine's `botDirectory` is `<home>/.config/nexus-agent`; set it to `"~/elsewhere"` and the same engine now answers `<home>/elsewhere`, with no new engine built.
2. `testEnvFileIsReadFromTheHostsFolder`: put a `.env` with `TELEGRAM_BOT_TOKEN=1:abc` in the host's folder in the fake file system; after `load()` the engine's `configuration.botToken` is `1:abc`.
3. `testPlanModeIsTheHosts`: a session built with a host whose `planMode` is `true` starts with `planMode == true`; setting the session's `planMode = false` sets the host's.
4. `testArchivedClaudeSessionsAreKeptByTheHost`: archive a Claude session summary through a session built **without** an engine; the id is in the host's `hiddenClaudeSessionIDs` and nowhere in `UserDefaults.standard` under `"vitruvian.claude.hiddenSessionIds"` (read the key before and after and assert it did not change).
5. `testStartingWithoutABotReportsTheProblem`: with no `src/bot.js` in the fake file system, `start()` leaves `isRunning == false` and sets `problem` to the missing-bot case.
6. `testDefaultTextIsEnglish`: `NexusAgentHostStrings()` has non-empty values for every field (iterate with `Mirror` so a field added later is covered).

- [ ] **Step 2: Run them, and show one can fail**

Run: `bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests --test_output=errors`
Expected: PASS.

Then temporarily make the engine's `botDirectory` ignore the host (pass `""`), run again, and expect `testBotFolderComesFromTheHost` and `testEnvFileIsReadFromTheHostsFolder` to FAIL. Revert; `git status` shows the engine file unchanged.

- [ ] **Step 3: Tidy, verify everything, commit**

```
bazel run //:tidy
git checkout -- gazelle_python.yaml
bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test --test_output=errors
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
```

Expected: all PASS (the pin does not change: only a test file was added).

```bash
git add apps/desktop/nexus-agent/macos/Tests
git commit -m "test(nexus-agent): the engine asks its app for settings, text and notices"
```

---

## Before opening the pull request

- [ ] The description says: what moved, that Vitruvian's behaviour is unchanged and how that was measured (175 unchanged checks plus 6 new), the licence-check output, and that the standalone app is untouched until step 2b.
- [ ] `Nexus Agent Mirror Toolchain` is green on the pull request (Swift 6.1.2).
- [ ] Every check is green before it is queued.
