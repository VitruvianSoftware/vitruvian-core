# What the shared chat must learn before the standalone can use it (step 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The shared engine and chat session can do everything the standalone app's own chat does today, so that switching the standalone to the shared chat view (step 3c) takes nothing away from its users.

**Architecture:** Five gaps are closed in `NexusAgentCore`, each behind the existing `NexusAgentHost` seam where an app's saved settings are involved: remembering the chosen provider and the user's own providers; running a provider's command template; choosing Ollama's model when none is set; keeping prompt history and worktree mode between launches; and deleting agy conversations. Vitruvian gains each of these as a side effect, because it runs the same engine. Its chat view gets the smallest additions needed to use them; the view itself moves in step 3b.

**Tech Stack:** Swift 6 mode in `NexusAgentCore` (must compile on Swift 6.1.2), XCTest beside it, Vitruvian's own test harness for its host, Bazel (`--config=macos-app`), SwiftPM for the mirror.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, section 9 step 3. That step is split in three: 3a (this plan) closes the feature gaps; 3b moves the chat view into a shared `NexusAgentUI` library; 3c switches the standalone to it. The split exists because a survey on 2026-10-09 found the standalone's chat has features Vitruvian's lacks, and the ruling is that the standalone loses nothing.

## What changes for users

**Standalone app:** nothing yet. It does not run on the shared chat until step 3c.

**Vitruvian's Quick Prompt:**

| | Before | After |
|---|---|---|
| The chosen provider | Forgotten every time the window is shown, and whenever the model or folder is saved | Remembered between shows and between launches |
| Providers offered | The three built in | The three built in, plus any the user has saved (none can be added from Vitruvian yet) |
| A provider that is a command template | Run as if it were agy | Its own command is run, with the prompt and model filled in |
| Ollama with no model set | Passed the literal model name `default` | The first model `ollama list` reports; a fixed fallback if that fails |
| Prompt history (up and down arrows) | Lost when the app quits | Kept, most recent 20 |
| Worktree mode | Lost when the app quits | Kept |
| Deleting a conversation | Not possible | Possible for agy conversations, one at a time or all for the folder, from the engine; the drawer gains a Delete item on each row |

## Global Constraints

- The standalone app's own sources (`apps/desktop/nexus-agent/macos/Sources/NexusAgent/`) change only in `StandaloneHost.swift`, to answer new host members from the settings keys that app already uses. Its chat window is not touched.
- Every behaviour ported from the standalone's chat (`QuickPromptWindow.swift`) into the shared library keeps that behaviour exactly, and each port is covered by tests written from the standalone's code as the specification. Where the standalone's behaviour looks like a bug, port it, test it, and report it; do not fix it silently.
- Vitruvian's existing checks pass unedited, except a check that asserts one of the "Before" rows above; each such edit is listed in the report with old and new expectation.
- Nothing in `NexusAgentCore` imports a `Vitruvian*` module or SwiftUI, reads `UserDefaults`, or names an app's settings key. Every saved setting goes through `NexusAgentHost`. No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` added. No syntax newer than Swift 6.0.
- New host members get a default in a protocol extension only when "the app does not support this" is a sensible answer; otherwise both hosts (`VitruvianNexusAgentHost`, `StandaloneHost`) and the test hosts implement them.
- The shared example files in `apps/desktop/nexus-agent/testdata/` stay the authority where a rule is also the bot's.
- After any change under `Sources/NexusAgentCore`: `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and one line in the dated log of `apps/desktop/vitruvian/UPSTREAM.md`.
- Subprocesses the engine starts go through `NexusAgentEngine.Environment` closures, so tests never launch a real `agy`, `claude`, `ollama` or `sqlite3` except where an existing test already does.
- Every Swift Bazel command needs `--config=macos-app`; name the `manual` targets. Before the last commit: `bazel run //:tidy`, then discard its change to `gazelle_python.yaml` if any.
- Do not start the real bot or any real agent CLI, and do not read or write the real `~/.config/nexus-agent`, `~/.gemini` or `~/.claude`.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **The provider is still forgotten on some path.** `load()`, `save()`, `start()` and showing the window all rebuild the configuration today. After this change the chosen provider must survive every one of them. Pinned by Task 1.
2. **A custom command is run through a shell.** The standalone splits the template into arguments itself; a port that hands the string to `sh -c` would let a prompt containing `;` or `$(…)` run commands. The prompt must reach the program as ONE argument, whatever it contains. Pinned by Task 2.
3. **Deleting the wrong conversations.** "Clear all" must remove only conversations of the current working folder, and only top-level ones, exactly as the standalone scopes it. Pinned by Task 5.
4. **History grows without bound or stores secrets it did not before.** Cap and de-duplication match the standalone. Pinned by Task 4.
5. **Vitruvian's settings bleed into the standalone or back.** Each host stores under its own app's keys; the shared library names none. Pinned by the existing source-scan test and by each task's host tests.

---

### Task 1: The chosen provider, and the user's own providers, are remembered

**Files:** `NexusAgentHost.swift`, `NexusAgentEngine.swift`, `NexusAgentSupport.swift` (provider list helper) in `NexusAgentCore`; `VitruvianNexusAgentHost.swift` and `Core/Preferences.swift`/`DefaultsKey.swift` in Vitruvian (new keys, following that file's conventions and its namespace test); `StandaloneHost.swift`; `EngineHostTests.swift`; Vitruvian's `NexusAgentTests.swift` (one new suite); Vitruvian's chat view only where it lists providers.

**Interfaces — produces:**

```swift
// NexusAgentHost
/// The provider the user last chose, by id; nil if they never chose.
var chosenProviderID: UUID? { get set }
/// Providers beyond the built-in three: the user's own, and built-in ones whose command they edited.
var savedProviders: [NexusAgentCLIProvider] { get set }

// NexusAgentEngine
/// Built-in providers with the host's saved edits applied, then the host's own providers.
public var providers: [NexusAgentCLIProvider] { get }
```

Rules:
- `providers` = the three built-ins in their fixed order, each replaced by the host's saved copy when one has the same id (that is how an edited command template survives), followed by the host's providers whose id is not a built-in's.
- Whenever the engine rebuilds its configuration from the file (`load()`, after `save(_:)`, and anywhere else it assigns `configuration` from a parse), the active provider becomes the one in `providers` whose id is `host.chosenProviderID`, or Antigravity when there is none or the id is unknown.
- `updateActiveProvider(_:)` / the `activeProvider` setter also writes `host.chosenProviderID`.
- Standalone host: `chosenProviderID` ↔ `UserDefaults` string `activeProviderId`; `savedProviders` ↔ the JSON arrays under `customProviders` and `builtInProviders_v3`, decoded and encoded so that the standalone's existing `ConfigManager` reads and writes the same bytes it does today (check that `CLIProvider` and `NexusAgentCLIProvider` encode to the same JSON keys; if they do not, give the shared type the coding keys the stored data already uses, and test with a literal sample of the stored JSON).
- Vitruvian host: two new preference keys in Vitruvian's own namespace, read and written live.

**Tests (write first, see them fail):** in `EngineHostTests.swift` with the recording host — the active provider is Antigravity with nothing chosen; choosing Claude sets the host's id; `load()`, `save(_:)` and a second engine built on the same host all still report Claude; an unknown id falls back to Antigravity; a saved copy of a built-in with an edited template replaces the built-in at the same position; an own provider is listed after the built-ins; a literal sample of the standalone's stored JSON decodes to the same providers `ConfigManager` would show. In Vitruvian's suite: the host stores and returns both values through a private defaults suite, live.

Vitruvian's chat view: where it lists providers for the two provider menus, list `service.providers` instead of the built-in constant. No other view change.

Commit: `feat(nexus-agent): the chosen provider and the user's own providers are remembered`

---

### Task 2: A provider's command template is run as written

**Files:** `NexusAgentSupport.swift` (argument building, executable lookup), `NexusAgentEngine.swift`/`NexusAgentQuickPromptSession.swift` where a turn is launched; a new shared example file is NOT needed (the bot's template handling is `buildProviderArgs`, a different rule set; note any disagreement in the report); `EngineHostTests.swift` or a new `ProviderCommandTests.swift`.

**Specification — the standalone's code is the reference:** `QuickPromptWindow.swift` `sendToCLI` (how a provider is routed: by id, else by the first word of its template being `claude` or `ollama`, else as a custom command), `parseProviderTemplate` (how a template becomes an executable and an argument list, with `{prompt}` and `{model}` filled in), `resolveExecutablePath` (where the executable is looked for), `runCustomProvider` (how its output becomes the reply), and the plan-mode prompt wrapper (`[SYSTEM] … PLAN MODE` text put in front of the prompt).

Port into `NexusAgentCore` as pure functions plus the session's launch path:
- Routing identical to the standalone's.
- Template parsing identical, including quoting rules. The prompt is substituted as a single argument and is never re-split, re-quoted or passed through a shell.
- Executable lookup identical in the folders it searches and their order, expressed through `Environment` closures so tests supply a fake file system.
- For agy and Claude, plan mode stays as the flags the shared code already passes. For a custom command and for Ollama, which have no plan flag, plan mode puts the standalone's wrapper text in front of the prompt, word for word.
- A custom command's plain output becomes the assistant's reply as the standalone shows it; a non-zero exit is a failed turn with the standalone's message.

**Tests (first, failing):** a table of templates → (executable, arguments) covering: no placeholders; `{prompt}` alone; `{prompt}` and `{model}`; a quoted segment with spaces; `{prompt}` inside quotes; a prompt containing spaces, quotes, `;`, `$(rm -rf x)`, a newline and `{model}` literally (each arrives as one argument, unchanged); an empty model. Routing: a template starting with `claude` is run through the Claude path, one starting with `ollama` through the Ollama path, anything else as a custom command. Lookup: found in each folder in order; not found gives the standalone's "missing" outcome. Plan mode on a custom command puts the wrapper in front; on agy it does not. A fake turn through the session with a custom provider ends with the output as the reply and one `turnFinished` to the host.

Commit: `feat(nexus-agent): a provider's own command is run as written, with the prompt as one argument`

---

### Task 3: Ollama picks a real model when none is set

**Specification:** the standalone's `ollamaDefaultModel` (it runs `ollama list`, takes the first model name, and falls back to a fixed name). Port it behind an `Environment` closure that runs a command and returns its output, so tests feed it sample `ollama list` output: a normal table with a header row, an empty table, a failure. The shared code stops passing the literal `default`.

Commit: `fix(nexus-agent): Ollama with no model set uses the first model it has`

---

### Task 4: Prompt history and worktree mode are kept

**Interfaces — produces on `NexusAgentHost`:** `var promptHistory: [String] { get set }`, `var worktreeMode: Bool { get set }`.

Rules, from the standalone (`QuickPromptWindow.swift`, keys `promptHistory`, `worktreeMode`): the session loads both at creation; a sent prompt is added as the standalone adds it (same position, same cap of 20, same treatment of a prompt equal to the latest one); changing worktree mode writes it. Standalone host ↔ its existing `UserDefaults` keys. Vitruvian host ↔ two new keys in its namespace.

**Tests (first, failing):** a session built on a host with history shows it; sending adds, caps at 20 and treats a repeat as the standalone does; a second session on the same host sees it; worktree mode round-trips; Vitruvian's host stores both live.

Commit: `feat(nexus-agent): prompt history and worktree mode are kept between launches`

---

### Task 5: Deleting agy conversations

**Specification:** the standalone's `SessionFileReader` delete and "Clear All" (the SQL it runs through `sqlite3`, what it removes on disk beside the index row, and how "all" is scoped to the working folder and to top-level conversations). Port as engine functions through the existing `Environment`/sqlite path; add `delete(_:)` and `deleteAll(in:)` on the session, which refresh the list. Claude sessions are not deletable (the standalone never listed them); the functions refuse them.

Vitruvian's drawer row (`NexusAgentSessionRow`) gains a Delete item in a context menu for agy conversations, using an English string added to the host strings; no "Clear All" control is added to Vitruvian's view in this step (it arrives with the shared view in 3b).

**Tests (first, failing):** against a throwaway home folder with a real small SQLite index built by the test (as the existing archive tests do, if they do; otherwise through a fake `runSqlite` closure asserting the exact statements): deleting one conversation removes its row and its files and nothing else; "all" removes only top-level conversations of that folder and leaves another folder's and a nested one; a Claude session is refused; the list is refreshed.

Commit: `feat(nexus-agent): agy conversations can be deleted, one or all for a folder`

---

## Before opening the pull request

- [ ] The description carries the "What changes for users" table, every standalone behaviour that was ported and looked like a bug, and every existing expectation changed.
- [ ] `Nexus Agent Mirror Toolchain` is green (Swift 6.1.2). All checks green before it is queued.
- [ ] Title is `feat(desktop): …` (Vitruvian's users see new behaviour).
