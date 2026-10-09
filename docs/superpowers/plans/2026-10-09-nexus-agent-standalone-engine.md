# Standalone Nexus Agent on the shared engine (step 2b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The standalone Nexus Agent app starts, stops and watches the bot, and reads and writes `.env`, through the shared engine, so those rules exist once.

**Architecture:** The standalone's `BotManager` and `ConfigManager` keep their names and the properties its views bind to, but stop doing the work themselves: `BotManager` becomes a thin mirror of a `NexusAgentEngine`, and `ConfigManager` reads and writes `.env` through `NexusAgentEnvFile`. One gap in the shared code is closed first, as an opt-in so Vitruvian is unaffected: the engine can write which program the bot runs (`CLI_PROVIDER`, `CLI_COMMAND_TEMPLATE`). The chat window (`QuickPromptWindow.swift`) is not touched; step 3 replaces it.

**Tech Stack:** Swift 6 mode in `NexusAgentCore` (must compile on Swift 6.1.2), Swift 5 mode in the app target, Combine, Bazel (`--config=macos-app`), SwiftPM for the mirror, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, section 9 step 2 (second half). Depends on step 2a (PR #2965).

## What changes for standalone users

These are deliberate. Each is the standalone adopting the rule Vitruvian already uses. The pull request description carries this table.

| | Before | After |
|---|---|---|
| Saving Settings | Rewrites `.env` from a template: comments and any key the app does not know (`AGY_BIN`, a hand-set `AGY_TIMEOUT_MS`) are lost; timeout forced back to 300000 | Changes only the keys the app owns, in place; comments, order and other keys are kept. A new file still gets the full template |
| `.env` file permissions | Default | Readable by the user alone (it holds the bot token) |
| Values with odd characters | Written raw | Trimmed; quoted when dotenv would otherwise cut them (a `#`, leading quote, outer spaces); the allowed-user list is tidied and line breaks are removed |
| Old `GEMINI_*` lines | Erased with everything else | Erased (they would override the new names) |
| Stopping the bot | Signals its process, then any process the PID file names, then **every** process matching `node src/bot.js` | Signals only the bot this app recorded; force-kills it if it has not stopped after 3 seconds. A bot started by hand with `bot.sh` is no longer killed |
| Is the bot running? | Any live process with the recorded PID | Only if that process is Node, so a recycled PID is not mistaken for the bot |
| Restart | Stop, wait a fixed 1.5 s, start | Start as soon as the old process is gone |
| Start with no token, no Node, or no bot | Launches anyway and fails in the log, or assumes a Homebrew path | Does not launch; the log panel says why |
| Node search | Homebrew, `/usr/local/bin`, `/usr/bin`; must exist | Homebrew, `/usr/local/bin`, `~/.local/bin`; must be executable |
| Log panel | Whole log file, plus the app's own "Bot started/stopped" lines | Last 16 KB of the log file; the app's own lines only for a start that could not happen |
| Both `AGY_*` and the old `GEMINI_*` name in `.env` | Whichever line came last won | The `AGY_*` name wins, as the bot itself reads it |
| An approval mode the app does not know | Shown as typed | Shown as "Default" (ask each time), which is how the bot treats it; Save writes that |
| A save that fails | Only printed to the console | Settings says it could not save, and the log panel gives the reason |
| The reason a start could not happen | n/a | The line stays in the log panel until the next successful start or save |
| Save & Restart when the save fails | Restarted the bot anyway | Does not restart; Settings says the save failed |
| Open Logs with no log file yet | Asked macOS to open the path; with no file nothing opened, and no file was created | Does nothing |
| A launch the system refuses | The system's error text in the log panel ("Failed to start bot: ...") | One plain line: the bot could not be started |
| The bot's environment | Homebrew folders added to PATH | `~/.local/bin` and the Homebrew folders added; the bot gets no keyboard input (stdin is empty) |

Unchanged, and worth knowing: an empty `AGY_APPROVAL_MODE=` line still shows as YOLO in Settings, and saving then writes `yolo`, although the bot treats an empty value as ask-each-time. That is the old behaviour; it changes with the chat window in step 3.

What does **not** change: which program the bot runs when a provider is chosen in Settings (still written to `.env`), the saved provider list, the hotkey, auto-start, the chat window.

## Global Constraints

- **Vitruvian's behaviour does not change.** Its unit tests pass with no existing check edited. In particular a Vitruvian save must still leave an existing `CLI_PROVIDER` / `CLI_COMMAND_TEMPLATE` line exactly as it found it.
- The standalone changes only as the table above says. Any other difference found while building is reported, not shipped silently.
- `apps/desktop/nexus-agent/macos/Sources/NexusAgent/QuickPromptWindow.swift` changes only where the compiler forces it.
- The app target cannot be unit-tested (`@main`). So logic goes in `NexusAgentCore`, with tests; what stays in the app target is wiring thin enough to check by reading.
- Nothing in `NexusAgentCore` imports a `Vitruvian*` module or SwiftUI, reads `UserDefaults`, or names an app's settings key. No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` is added. No syntax newer than Swift 6.0.
- After any change under `Sources/NexusAgentCore`: `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and one line in the dated log of `apps/desktop/vitruvian/UPSTREAM.md`.
- `macos/BUILD` and `macos/Package.swift` declare the same targets.
- Every Swift Bazel command needs `--config=macos-app`; name the `manual` targets.
- Before the last commit: `bazel run //:tidy`, then discard its change to `gazelle_python.yaml` if any.
- Do not start, stop or signal the real bot on this machine, and do not write to the real `~/.config/nexus-agent/.env`. Tests use fake file systems or temporary folders.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Choosing a provider must still change what the bot runs.** Today only the standalone writes `CLI_PROVIDER` and `CLI_COMMAND_TEMPLATE`. If the swap drops them, Settings silently stops controlling the bot. Pinned by Task 1.
2. **An existing `.env` with a hand-written comment and an unknown key** must come back from a save with both intact and the owned keys updated. Pinned by Task 1 (shared rule) and Task 3 (the standalone path).
3. **A start that cannot happen must say why.** The engine sets a `problem` silently; the standalone's log panel is the only place a user looks. Pinned by Task 2 (message for every case).
4. **The provider resets.** `engine.load()` rebuilds the configuration and with it the active provider. The standalone keeps its own provider choice in saved settings and must hand it to the engine on every save, not read it back from the engine. Pinned by Task 3 Step 2.
5. **The status view goes stale.** `BotManager` used to poll every 2 seconds from launch. The mirror must keep the engine polling for the life of the app. Pinned by Task 3 Step 1.

---

### Task 1: The engine can write which program the bot runs

**Files:**
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentSupport.swift` (`NexusAgentConfiguration`, `NexusAgentEnvFile`)
- Create: `apps/desktop/nexus-agent/macos/Tests/BotProviderEnvTests.swift`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`, `apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256`

**Interfaces:**
- Produces:

```swift
extension NexusAgentConfiguration {
    /// The program the bot should run, written to `.env` on save. Nil leaves
    /// the file's own `CLI_PROVIDER` and `CLI_COMMAND_TEMPLATE` lines alone,
    /// which is what an app that does not manage the bot's provider wants.
    public var botProvider: NexusAgentCLIProvider? { get set }   // stored, default nil
}
```

`NexusAgentEnvFile.render(_:over:)` keeps its signature. `NexusAgentEnvFile.providerKey == "CLI_PROVIDER"` and `commandTemplateKey == "CLI_COMMAND_TEMPLATE"` are added as `public static let`.

Rule, identical to what the standalone's `ConfigManager.save()` writes today: for the built-in Antigravity provider (`NexusAgentCLIProvider.antigravity.id`) → `CLI_PROVIDER=agy` and `CLI_COMMAND_TEMPLATE=` (empty); for any other provider → `CLI_PROVIDER=custom` and `CLI_COMMAND_TEMPLATE=<the provider's commandTemplate>`.

- [ ] **Step 1: Write the failing tests**

`BotProviderEnvTests.swift` (MIT header as the other test files; `import XCTest`, `import NexusAgentCore`):

```swift
final class BotProviderEnvTests: XCTestCase {
    private func value(_ key: String, in content: String) -> String? {
        NexusAgentEnvFile.values(in: content)[key]
    }

    func testWithoutABotProviderTheFilesProviderLinesAreLeftAlone() {
        let existing = "TELEGRAM_BOT_TOKEN=1:a\nCLI_PROVIDER=custom\nCLI_COMMAND_TEMPLATE=ollama run llama3\n"
        let saved = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "1:a"), over: existing)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "ollama run llama3")
    }

    func testAntigravityIsWrittenAsAgyWithNoTemplate() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .antigravity
        let existing = "TELEGRAM_BOT_TOKEN=1:a\nCLI_PROVIDER=custom\nCLI_COMMAND_TEMPLATE=ollama run llama3\n"
        let saved = NexusAgentEnvFile.render(configuration, over: existing)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "agy")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "")
    }

    func testAnyOtherProviderIsWrittenAsCustomWithItsTemplate() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .claude
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), NexusAgentCLIProvider.claude.commandTemplate)
    }

    func testANewFileCarriesTheChosenProvider() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .ollama
        let saved = NexusAgentEnvFile.render(configuration, over: nil)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), NexusAgentCLIProvider.ollama.commandTemplate)
        XCTAssertEqual(value("AGY_TIMEOUT_MS", in: saved), "300000")
    }

    func testCommentsAndUnknownKeysSurviveASave() {
        var configuration = NexusAgentConfiguration(botToken: "2:b", model: "m1")
        configuration.botProvider = .antigravity
        let existing = """
        # my notes
        TELEGRAM_BOT_TOKEN=1:a
        AGY_BIN=/opt/agy
        AGY_TIMEOUT_MS=900000
        """
        let saved = NexusAgentEnvFile.render(configuration, over: existing)
        XCTAssertTrue(saved.contains("# my notes"))
        XCTAssertEqual(value("AGY_BIN", in: saved), "/opt/agy")
        XCTAssertEqual(value("AGY_TIMEOUT_MS", in: saved), "900000")
        XCTAssertEqual(value("TELEGRAM_BOT_TOKEN", in: saved), "2:b")
        XCTAssertEqual(value("AGY_MODEL", in: saved), "m1")
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "agy")
    }

    func testATemplateThatDotenvWouldCutIsQuoted() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = NexusAgentCLIProvider(
            id: UUID(), name: "Mine", commandTemplate: "mytool --note a #1 {prompt}", isBuiltIn: false)
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "mytool --note a #1 {prompt}")
    }
}
```

Read `NexusAgentConfiguration`'s and `NexusAgentCLIProvider`'s real initialisers first and adapt the calls to them (argument labels, the id type); keep every asserted value.

- [ ] **Step 2: Run them to see them fail**

Run: `bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests --test_output=errors`
Expected: build failure, `botProvider` is not a member.

- [ ] **Step 3: Implement**

Add the stored `botProvider` to `NexusAgentConfiguration` (default `nil`; if the struct has an explicit memberwise `public init`, add a trailing defaulted parameter so no existing call changes). In `render`:
- existing file, `botProvider == nil`: no change from today.
- existing file, `botProvider != nil`: treat the two provider keys as owned for this call — rewrite every existing copy in place, append them with the other missing keys if absent — using `encoded` for the template.
- no file or blank file: the template's `CLI_PROVIDER=` and `CLI_COMMAND_TEMPLATE=` lines carry the chosen provider's values when one is set, `agy` and empty otherwise (as today).

`parse` does not read the provider keys back (an app that sets `botProvider` holds the choice itself). `NexusAgentConfiguration` equality includes the new field.

- [ ] **Step 4: Run all tests that build this code**

```
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test //apps/desktop/vitruvian:unit_tests --test_output=errors
```

Expected: PASS, and Vitruvian's count of checks unchanged.

- [ ] **Step 5: Re-pin, log, commit**

`bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared`; add to the dated log in `apps/desktop/vitruvian/UPSTREAM.md`:

```markdown
- **2026-10-09**: The shared `.env` rule can write which program the bot runs (`CLI_PROVIDER`, `CLI_COMMAND_TEMPLATE`) when the app sets `NexusAgentConfiguration.botProvider`. This app does not set it, so its saves leave those lines alone, as before.
```

Run `bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:source_lints_test --test_output=errors` (PASS), then:

```bash
git add apps/desktop/nexus-agent/macos apps/desktop/vitruvian
git commit -m "feat(nexus-agent): the shared .env rule can write which program the bot runs"
```

---

### Task 2: The engine says why a start could not happen

**Files:**
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentHost.swift` (`NexusAgentHostStrings`)
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentEngine.swift` (one computed property)
- Modify: `apps/desktop/nexus-agent/macos/Tests/EngineHostTests.swift`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`, the pin

**Interfaces:**
- Produces: five new `NexusAgentHostStrings` fields with English defaults, and

```swift
extension NexusAgentEngine {
    /// The current problem in words, from the host's text; nil when there is none.
    public var problemDescription: String? { get }
}
```

Default text, one per `Problem` case:

| Case | Default |
|---|---|
| `missingToken` | `Add your Telegram bot token in Settings before starting the bot.` |
| `missingBot` | `The bot is not installed: src/bot.js was not found in the bot folder.` |
| `missingNode` | `Node.js was not found. Install Node, then start the bot again.` |
| `startFailed` | `The bot could not be started.` |
| `saveFailed` | `The settings could not be saved.` |

- [ ] **Step 1: Write the failing tests** in `EngineHostTests.swift`, using its existing rig and recording host:

```swift
    func testEveryProblemHasWords() {
        let strings = NexusAgentHostStrings()
        XCTAssertEqual(strings.problemMissingToken, "Add your Telegram bot token in Settings before starting the bot.")
        XCTAssertEqual(strings.problemMissingBot, "The bot is not installed: src/bot.js was not found in the bot folder.")
        XCTAssertEqual(strings.problemMissingNode, "Node.js was not found. Install Node, then start the bot again.")
        XCTAssertEqual(strings.problemStartFailed, "The bot could not be started.")
        XCTAssertEqual(strings.problemSaveFailed, "The settings could not be saved.")
    }
```

and `testAStartThatCannotHappenSaysWhy`: on a fresh rig `problemDescription` is nil; with no `src/bot.js`, after `start()` it equals the missing-bot text; with the bot installed and a real token in the fake `.env` but no executable Node, after `start()` it equals the missing-Node text; with the bot installed and no token, the missing-token text. Build each case from the rig's fake file system and `isExecutable` closure the way the existing tests do.

- [ ] **Step 2: Run to see them fail** (same command as Task 1 Step 2; expected: the new members do not exist).

- [ ] **Step 3: Implement** the five fields (with the defaults above, added to the struct's `public init` as trailing defaulted parameters) and `problemDescription` as a `switch` over `problem` reading `host.strings` at the moment it is asked.

- [ ] **Step 4: Run** the Task 1 Step 4 command. Expected: PASS. Vitruvian does not show these strings yet and its behaviour is unchanged.

- [ ] **Step 5: Re-pin, log, commit**

Log line: `- **2026-10-09**: The shared engine can describe its current problem in words (`problemDescription`), for an app that has only a log panel to show it in. Not used here.`

```bash
git add apps/desktop/nexus-agent/macos apps/desktop/vitruvian
git commit -m "feat(nexus-agent): the engine says in words why the bot could not start"
```

---

### Task 3: The standalone uses the engine

**Files:**
- Create: `apps/desktop/nexus-agent/macos/Sources/NexusAgent/StandaloneHost.swift`
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgent/BotManager.swift`, `ConfigManager.swift`, `App.swift`
- Modify only if the compiler forces it: `StatusView.swift`, `SettingsView.swift`, `QuickPromptWindow.swift`

**Interfaces:**
- Consumes: `NexusAgentEngine(environment: .live, host:)`, its `isRunning`, `pid`, `logLines`, `problem`, `problemDescription`, `start()`, `stop(then:)`, `restart()`, `openLog()`, `startPolling()`, `refreshStatus()`, `load()`, `save(_:)`, `configuration`; `NexusAgentConfiguration.botProvider`; `NexusAgentEnvFile`.
- Produces: `BotManager` and `ConfigManager` with every member their callers use today unchanged in name and type.

- [ ] **Step 1: The host and the bot mirror**

`StandaloneHost.swift`: `@MainActor final class StandaloneHost: NexusAgentHost` answering from this app's existing saved settings:
- `configuredBotDirectory` → `""` (the standard folder, as today)
- `startsBotAtLaunch` → `UserDefaults.standard.bool(forKey: "autoStart")`
- `planMode` → get/set `UserDefaults.standard` key `"planMode"`
- `hiddenClaudeSessionIDs` → get/set string array under a new key `"hiddenClaudeSessionIds"`
- `strings` → `NexusAgentHostStrings()`
- `turnNeedsApproval` → nothing; `turnFinished` → nothing. The chat window does not run on the engine yet and posts its own notifications. Say so in a comment; step 3 of the design fills these in.

`BotManager` keeps `@Published var isRunning`, `lastLogLines`, `pid`, and `start()`, `stop()`, `restart()`, `openLogs()`, but holds a `NexusAgentEngine` and does none of the work:
- `init` builds `StandaloneHost` and the engine, subscribes to the engine's `$isRunning`, `$pid`, `$logLines` and `$problem` (Combine, stored cancellables) and copies them into its own published properties, then calls `engine.startPolling()` once so status is live for the life of the app, as the old 2-second timer was. It never calls `stopPolling`.
- `lastLogLines` is the engine's `logLines`, followed by `engine.problemDescription` as one more line when there is a problem.
- `start`, `stop`, `restart`, `openLogs` forward to the engine.
- Expose the engine as `let engine: NexusAgentEngine` for `ConfigManager`.
- Delete everything else in the file: the `Process` handling, the PID-file code, the timer, `pkill`.

- [ ] **Step 2: `.env` through the shared rule**

`ConfigManager` keeps every `@Published` field, its provider storage in `UserDefaults`, its hotkey handling, `CLIProvider` and `AgyInfo`. Change only how `.env` is read and written:
- It is given the engine (`init(engine:)`; `App.swift` passes `botManager.engine`).
- `load()`: `engine.load()`, then copy `engine.configuration` into the published fields (`botToken`, `allowedUserIds`, `workingDirectory`, `model`, `approvalMode` as the mode's raw string, `effort` as the effort's raw string, an unset effort as `""`). Keep the existing fall-back to `.env.example` when there is no `.env`: read it with `NexusAgentEnvFile.parse` and copy the same way. Remove `parseEnv`.
- `save()`: build a `NexusAgentConfiguration` from the published fields (`NexusAgentApprovalMode.parse`, `NexusAgentEffort.parse`), set `botProvider` from the app's own `activeProvider` mapped to `NexusAgentCLIProvider` (same id, name, command template, built-in flag), and call `engine.save(_:)`. The `UserDefaults` writes and the hotkey update stay exactly as they are. Remove the hand-written template.
- The provider choice is always taken from `ConfigManager`'s own saved settings, never read back from `engine.configuration` (the engine resets it on every load).

`App.swift`: create `BotManager` first, then `ConfigManager(engine: botManager.engine)`. Leave the auto-start block as it is.

- [ ] **Step 3: Build both ways**

```
bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
```

Expected: success. Then confirm nothing is left behind: a search of `Sources/NexusAgent` for `pkill`, `AGY_TIMEOUT_MS` and `parseEnv` finds nothing.

- [ ] **Step 4: Check the wiring by reading, and write it down**

The app target has no tests. In the report, for each row of "What changes for standalone users" name the line that makes it true, and for each caller of `BotManager` and `ConfigManager` (`App.swift`, `StatusView.swift`, `SettingsView.swift`, `QuickPromptWindow.swift`) confirm the member it uses still exists with the same type. List any difference not in the table.

- [ ] **Step 5: Tidy, full verification, commit**

```
bazel run //:tidy
git checkout -- gazelle_python.yaml
bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test --test_output=errors
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
```

```bash
git add apps/desktop/nexus-agent/macos
git commit -m "fix(nexus-agent): the standalone app runs the bot and saves .env through the shared engine"
```

---

## Before opening the pull request

- [ ] The description carries the "What changes for standalone users" table, the one behaviour that is new shared capability (Task 1, opt-in, unused by Vitruvian), and a plain statement that the standalone's bot control was checked by reading and by build, not by starting the real bot.
- [ ] `Nexus Agent Mirror Toolchain` is green (Swift 6.1.2).
- [ ] Title is `fix(nexus-agent): …` so the standalone's changes reach its release notes.
