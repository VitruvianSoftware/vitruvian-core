# The standalone app uses the shared chat (step 3c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The standalone Nexus Agent app shows the shared chat view, driven by the shared engine and session, and its own 3,900-line chat is deleted. After this, a chat fix is written once.

**Architecture:** The standalone keeps what is its own: the menu-bar app, the updater, Settings, and a window controller that owns the floating panel and the global hotkey. That controller stops building its own views and instead hosts `NexusAgentChatView` on the engine `BotManager` already owns, resizing the panel as the session's mode changes. `StandaloneHost` gets its real answers (notifications when a turn ends). The few things the standalone's chat could do that the shared view cannot yet are added to the shared view first, behind the chrome where they would otherwise change Vitruvian's look.

**Tech Stack:** SwiftUI and AppKit; Swift 6 mode in the shared libraries (must compile on Swift 6.1.2), Swift 5 mode in the app target; Carbon for the hotkey (unchanged); Bazel (`--config=macos-app`); SwiftPM for the mirror; XCTest; the snapshot tool from step 3b.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, section 9 step 3 (last part). Steps 3a (#2995) and 3b (#2999) come first.

## What changes for standalone users

This is the step users of the standalone see. The pull request description carries this table, and images of the new chat.

| | Before | After |
|---|---|---|
| The chat window | The standalone's own views | The same chat Vitruvian has |
| Closing and reopening the chat | The conversation on screen was lost | It is still there |
| Session list | agy conversations only, the newest 10 | agy and Claude conversations |
| Resuming a conversation | A placeholder line | Its history, and it follows a turn still running |
| Archive and unarchive | Not available | Available |
| Replies | Inline formatting only | Headings, lists, quotes, dividers, diagrams |
| A running turn | Typing dots | Tool steps, thinking, and a banner for running subagents |
| Follow-up box | One line | Grows to six lines |
| Filtering sessions | Typed in the prompt box | Its own field in the drawer |
| The input while a turn runs | Disabled | Stays enabled |
| A failed turn | The real error text, which then disappears | A retry strip that stays |
| A stopped turn | The error "Generation stopped" | The text so far, or "Reply stopped." |
| **agy and permissions** | The chat always ran agy with every permission prompt skipped, unless plan mode was on, whatever Settings said | The chat uses the approval mode set in Settings, as the bot does |
| **Claude with approval mode "plan"** | Ran with permissions bypassed | Runs in plan mode |
| A prompt containing the text `{model}` (custom commands) | Altered | Sent as typed |
| A custom command whose first word is `{prompt}` | Ran the prompt as a program | Refused |
| A repeated follow-up prompt | Stored in history twice | Stored once |
| Diagrams | None | Drawn with a script loaded from a public CDN, as in Vitruvian |
| The hint shown while ⌘ is held | Shown | Gone |
| Hotkey, menu bar, Settings, updater, bot control | — | Unchanged |

Kept, by adding to the shared view in Task 1: Clear All for a folder's conversations (with its confirmation), arrow keys and Return in the session list, the session row's context menu.

## Global Constraints

- **Vitruvian does not change.** All 44 snapshot images still match the step 3b baseline rendered from `origin/main` before this branch's first change, and its unit tests pass with no existing check edited. Anything added to the shared view that would show in Vitruvian is off unless the chrome turns it on.
- The standalone changes only as the table says. Any other difference found while building is reported.
- Nothing in `NexusAgentCore` or `NexusAgentUI` imports a `Vitruvian*` module, reads `UserDefaults`, names an app's settings key, or uses a singleton of either app. No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` added. No syntax newer than Swift 6.0, no API newer than macOS 14 without an availability check.
- The standalone's saved settings keep their keys and formats: hotkey, auto-start, providers, chosen provider, plan mode, worktree mode, prompt history. A user who updates loses nothing they saved.
- One owner per saved setting. Where `ConfigManager` and `StandaloneHost` both write a key today (the provider keys), exactly one of them owns it after this step and the other reads through it.
- The app target cannot be unit-tested. Logic goes in the shared libraries with tests; what stays in the app is wiring, checked by an isolated run (below) and by reading.
- After any change to shared sources: `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and one line in the dated log of `apps/desktop/vitruvian/UPSTREAM.md`.
- `macos/BUILD` and `macos/Package.swift` declare the same targets.
- Do not start the real bot or a real agent CLI, do not show a window on the user's screen, do not register a global hotkey, and do not read or write the real `~/.config/nexus-agent`, `~/.gemini`, `~/.claude` or the app's real preferences. Isolated runs use `CFFIXED_USER_HOME` and a stand-in program.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Permissions get looser somewhere.** The table makes the chat stricter (it honours the approval mode). Any path where the new chat skips a permission prompt the old one asked for is a defect. Pinned by Task 2's argument tests for each approval mode and provider.
2. **A saved setting is lost on update.** History, provider choice, custom providers, plan and worktree mode, hotkey. Pinned by Task 2's host tests against literal samples of what the old app stored.
3. **Two writers for one key.** The chat changes the provider through the engine; Settings saves providers through `ConfigManager`. Pinned by Task 2: choose in the chat, save in Settings, the choice survives; add a provider in Settings, it appears in the chat without a restart.
4. **The window misbehaves.** Size per mode, position, resize limits, Esc, ⌘W, ⌘N, click outside, pin, dragging by the background, the hotkey toggling it. No test can see these; pinned by Task 3's isolated run and its checklist.
5. **Vitruvian's look drifts.** Pinned by the 44 snapshots after every task that touches the shared view.

---

### Task 1: The shared view gains what only the standalone's chat had

**Files:** `apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/` (session drawer and row, chrome, strings); `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentQuickPromptSession.swift` only if selection state belongs there; `apps/desktop/vitruvian/Sources/Vitruvian/UI/NexusAgent/NexusAgentQuickPromptView.swift` (the wrapper supplies its own wording for two strings); tests beside the shared code; `apps/desktop/vitruvian/Tools/NexusAgentChatSnapshots.swift` (a third form: the default chrome).

The standalone's code is the reference (`QuickPromptWindow.swift`, `QuickPromptView`: the session list's context menu, Delete, Clear All and its confirmation, the ↑/↓/Return handling, the loading and "no matching" states).

- **Clear All**, with the standalone's confirmation wording, in the drawer, shown only when `chrome.offersClearAll` is true (default true; Vitruvian's wrapper passes false, so its drawer is unchanged). It calls the session's `deleteAll`, which must run off the main thread before a control exists for it (up to 200 `sqlite3` launches): move the delete-all work off-main with the list refreshed on return, and test that the main thread is not blocked (the call returns before the fake `runSqlite` is released).
- **Keyboard in the session list:** ↑ and ↓ move a selection, Return resumes it, as in the standalone. Selection state is view state. This is the same in both apps (it adds behaviour to Vitruvian that no snapshot shows; say so in the log line).
- **Delete confirmation:** single Delete stays as it is in both apps (no confirmation; that is the standalone's rule and Vitruvian's since 3a).
- **Neutral defaults:** the two default strings that carry Vitruvian's wording (`environmentHint`, `newChatShortcut`) become neutral; Vitruvian's wrapper passes today's text, so its images do not change.
- **Snapshot tool:** add the default chrome as a third form (no pin, no dock, clear backdrop, Clear All shown), light and dark, for the same nine states, written with a `standalone-` prefix. These have no baseline to match; they are for looking at, and they go in the pull request.

Tests first: the delete-all path off-main; a pure function for the selection movement (wraps or stops as the standalone does); `offersClearAll` false hides the control (assert through whatever the view exposes for testing, or cover it by the Vitruvian snapshots staying identical).

Then: the 44 Vitruvian snapshots match the baseline; look at the new `standalone-` images and describe them in the report.

Commit: `feat(nexus-agent): the shared chat can clear a folder's conversations and be driven by the keyboard`

---

### Task 2: One owner for each saved setting, and the host's real answers

**Files:** `apps/desktop/nexus-agent/macos/Sources/NexusAgent/StandaloneHost.swift`, `ConfigManager.swift`, a new `BackgroundNotifications.swift` (the existing `BackgroundNotificationManager`, moved out of `QuickPromptWindow.swift` unchanged); shared code only if a rule has to move into it to be testable; tests beside the shared code.

- **Providers:** `ConfigManager` stops keeping its own copy of the provider list and the chosen id. Its `providers`, `activeProviderId` and `activeProvider` read through the engine (`engine.providers`, `engine.activeProvider`) and its edits write through the host (`savedProviders`, `chosenProviderID`) then tell the engine to re-read, so the chat and Settings always agree. The stored keys and JSON are unchanged. The Settings view's bindings keep working (it adds, edits and removes custom providers and edits built-in templates: read `SettingsView.swift` for every operation and keep each).
- **Turn notices:** `StandaloneHost.turnFinished` posts through `BackgroundNotificationManager` exactly when the old chat did (read `notifyIfBackgrounded` and its callers: only when the chat is not visible or the app is in the background, with the old titles and body), and plays the old sound in the old cases. `turnNeedsApproval` posts a notification in the same style when the chat is not visible (the old chat had no equivalent; this is new and belongs in the table if kept — keep it only if the old chat would otherwise have notified for a turn that is now waiting).
- **`isChatVisible`:** the standalone's engine must answer it from the real window. The engine reads it from an overridable member today; give the standalone a small subclass or a closure seam on the engine (whichever is the smaller change to the shared code), so the host is told the truth.
- **Approval mode and the chat:** nothing to write; the shared session already builds arguments from the configuration. Write the tests that pin Review Focus 1: for agy, Claude, Ollama and a custom command, with each approval mode and with plan mode on and off, the arguments contain a skip-permissions flag only where the approval mode says so.

Tests first, in XCTest beside the shared code, with literal samples of what the OLD standalone stored for each key (take them from its code: `customProviders`, `builtInProviders_v3`, `activeProviderId`, `promptHistory`, `planMode`, `worktreeMode`, `hotkeyKey`, `hotkeyModifiers`, `autoStart`): each is read to the same meaning by the new code. Since `StandaloneHost` and `ConfigManager` live in the untestable app target, put any rule worth testing into `NexusAgentCore` as a pure function they both call.

Commit: `refactor(nexus-agent): the chat and Settings share one record of providers, and the host reports finished turns`

---

### Task 3: The window hosts the shared view, and the old chat is deleted

**Files:** `apps/desktop/nexus-agent/macos/Sources/NexusAgent/QuickPromptWindow.swift` (becomes the window controller only, and should be renamed `ChatWindowController.swift` with the type keeping its name `QuickPromptWindowController` so `App.swift`, `StatusView.swift` and `ConfigManager.swift` do not change), `App.swift` only if wiring requires it.

- The controller keeps: the panel, positioning, the Carbon hotkey and its fallbacks, show / dismiss / toggle, the click-outside monitor, pinning, `isMovableByWindowBackground`.
- It now builds ONE hosting view, once, with `NexusAgentChatView(engine: botManager.engine, strings: NexusAgentChatStrings(), chrome: …)`: the standalone's visual-effect backdrop as `chrome.backdrop`, a pin binding to its own pinned state, `showWindow` → its `show()`, no dock action, Clear All offered. Dismissing hides the panel and keeps the view, so the conversation survives.
- It resizes the panel when `engine.session.mode` changes, using the shared `NexusAgentQuickPromptLayout` (sizes, initial frame, frame for a mode from the current frame, resizable only in chat mode) with its existing spring animation.
- Keys the old views handled and the shared view does not: Esc (stop a running turn, else step back a mode, else dismiss — read what Vitruvian's service does and what the old standalone did, and keep the standalone's behaviour where they differ), ⌘W (dismiss), ⌘N (new chat). Handle them in the controller's local key monitor.
- Showing the chat calls `engine.load()` first, as Vitruvian's service does, so a change made in Settings or in `.env` is seen.
- Delete from the file: every chat view, `SessionFileReader`, `SessionInfo`, `ChatMessage`, `ApprovalRequest`, the three provider runners, `parseProviderTemplate`, `resolveExecutablePath`, `ollamaDefaultModel`, the theme, the shimmer and preference keys. Search the app target afterwards for anything now unused (`AgyInfo` members, `ConfigManager` fields only the old chat read) and remove it; search for anything the deleted code did that nothing does now, and report it.

**Verification by an isolated run.** Build a throwaway harness outside the repository (as was done for step 2b: compile the app target's sources except `App.swift`'s `@main`, link the shared libraries, run under `CFFIXED_USER_HOME` with a fake home) that: creates `BotManager`, `ConfigManager` and the window controller; builds the panel WITHOUT ordering it onto the screen and without registering the hotkey; sets a custom provider whose command is `/bin/echo` with the prompt; sends a prompt through the engine; pumps the run loop; and checks the session shows the echoed reply, the panel's size followed the mode (pill, then chat), a second "show" keeps the conversation, ⌘N clears it, the host posted no notification while "visible" and one when "hidden" (through a recording stand-in for the notification centre), the provider chosen in the chat is the one `ConfigManager` reports, and history has the prompt once. Render the hosted view to an image in pill and chat modes and look at them.

**Checklist by reading** (for what no run can show): each row of "What changes for standalone users" → the line that makes it true; each saved key → who writes it; each caller of the controller → the member it uses still exists.

Final: both apps build; `mirror_build_test` passes; the bot's tests pass; Vitruvian's unit tests, lints, pin pass; the 44 Vitruvian snapshots match the baseline; `bazel run //:tidy`.

Commit: `feat(nexus-agent): the standalone app's chat is the shared chat`

---

## Before opening the pull request

- [ ] The description carries the table, three or four of the `standalone-` images, the isolated run's results, and every difference found that is not in the table.
- [ ] `Nexus Agent Mirror Toolchain` is green. All checks green before it is queued.
- [ ] Title is `feat(nexus-agent): …`.
