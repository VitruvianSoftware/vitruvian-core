# The chat view moves into the shared library (step 3b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vitruvian's Nexus Agent chat view lives in a shared SwiftUI library that the standalone app can also use, and Vitruvian looks and behaves exactly as before.

**Architecture:** A new MIT library `NexusAgentUI` beside `NexusAgentCore` holds the chat view and its parts. The view no longer reaches for Vitruvian's singletons: it is handed the engine, its text, and a small set of app-specific actions and looks ("chrome"). Vitruvian keeps a thin view with the old name that gathers those from its own service, translations and backdrop and shows the shared view, so nothing else in Vitruvian changes. "Looks exactly as before" is proved, not asserted: a snapshot tool renders fixed chat states to images before the move and after it, and the images must match.

**Tech Stack:** SwiftUI and AppKit in Swift 6 mode (must compile on Swift 6.1.2), WebKit for diagrams (as today), Bazel (`--config=macos-app`), SwiftPM for the mirror, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, sections 5, 6, 7 and 9 (step 3). Step 3 is split in three; 3a (PR #2995) closed the feature gaps; this is 3b; 3c switches the standalone to the shared view.

## What changes for users

Nothing, in either app. Vitruvian's chat is the same view from a different folder. The standalone does not use it until 3c.

## Global Constraints

- **Vitruvian looks the same.** For every state the snapshot tool renders, the image after the move equals the image before it, pixel for pixel. A difference is a defect to fix, or, if it cannot be removed, a finding reported with both images.
- **Vitruvian behaves the same.** Its unit tests pass with no existing check edited. Every action in the view (send, stop, retry, new chat, sessions drawer, resume, archive, delete, provider and model menus, folder picker, plan and worktree toggles, pin, dock to notch, approval buttons, copy buttons, arrow-key history) calls what it called before.
- Nothing in `NexusAgentUI` imports a `Vitruvian*` module, reads `UserDefaults`, names an app's settings key, or uses a singleton of either app. It may import SwiftUI, AppKit, WebKit, Combine, Foundation and `NexusAgentCore`.
- Only files whose header names VitruvianSoftware alone, with no upstream author in `git log --follow`, may leave `apps/desktop/vitruvian`. `HUDBackdrop` and anything else upstream wrote stays in Vitruvian and is handed to the shared view. Moved files carry the MIT header used in `apps/desktop/nexus-agent`.
- The standalone app's own sources are not touched, except that its targets must still build with the new library present.
- `apps/desktop/nexus-agent/macos/BUILD` and `Package.swift` declare the same targets. The pin covers the new library's sources as well as the core's.
- No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` added. No syntax newer than Swift 6.0.
- After any change to shared sources: `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and one line in the dated log of `apps/desktop/vitruvian/UPSTREAM.md`.
- Every Swift Bazel command needs `--config=macos-app`; name the `manual` targets. Before the last commit: `bazel run //:tidy`, then discard its change to `gazelle_python.yaml` if any.
- Do not launch either app, and do not start a real agent CLI or the bot. The snapshot tool renders views off screen with fake data.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A look that changed without anyone seeing it.** No test looks at this view today. Pinned by the snapshot comparison (Task 1 builds it on the code as it is; Task 3 re-runs it).
2. **An action wired to nothing.** A closure that is optional and passed as nil silently removes a button; one passed but never called makes a button dead. Pinned by Task 3's wiring table and its tests of the Vitruvian wrapper.
3. **Text that fell back to English.** The view reads 23 strings, 14 of them translated into 15 languages. A wrapper that builds the text once, or from the wrong language, shows English or stale text after the user switches language. Pinned by Task 3 (strings rebuilt when the language changes; a non-English snapshot).
4. **The view updates stopped.** The view observes the service and its session. Handing it the engine as a plain value instead of an observed object freezes the chat. Pinned by the snapshot tool's "after a message arrives" pair and by reading.
5. **Rules that stopped being checked.** Vitruvian's source lints walk only Vitruvian's folder. The moved file leaves their reach, including the check that every SF Symbol the app draws exists. Pinned by Task 2's symbol test beside the shared code.

---

### Task 1: A snapshot tool, built on the code as it is now

**Files:**
- Create: `apps/desktop/vitruvian/Tools/NexusAgentChatSnapshots.swift` (or the nearest existing home for developer tools in that folder; follow `Tools/MakeIcon.swift` and its Bazel target as the pattern)
- Modify: `apps/desktop/vitruvian/BUILD` (one `manual` binary target, `nexus_agent_chat_snapshots`)

**Interfaces:**
- Produces: `bazel run --config=macos-app //apps/desktop/vitruvian:nexus_agent_chat_snapshots -- <output folder>` writes one PNG per state, with fixed names, and prints each name with its pixel size.

The tool builds a `NexusAgentService` on an in-memory `Environment` (as `Rig` does in `Tests/NexusAgentTests.swift`: fake files, no processes, a private `UserDefaults` suite, a fixed home path), puts the session into a known state, hosts the real view in an off-screen `NSHostingView` at a fixed size, scale 2, light and dark appearance, lets one run-loop turn pass, and writes the bitmap.

States, each in the floating-window form and the notch-embedded form (`embeddedInNotch: true`), light and dark:
1. Empty pill (no messages).
2. Drawer open with four sessions: two agy, one Claude, one archived, one with a long title.
3. Chat with: a user message; an assistant reply containing a heading, a list, inline code, a fenced code block and a quote; token and cost stats.
4. A running turn: activity text, elapsed time fixed at a known value, one tool step, a "thinking" block.
5. An approval card, undecided; and the same card after Allow.
6. A failed turn with the retry control.
7. Plan mode on and worktree mode on.
8. A subagent banner with two running subagents.
9. State 3 again with the app language set to a translated, non-English language.

Determinism: no animation in flight (set the states directly; disable animations for the render; the shimmer and typing dots are captured at their resting frame or excluded by fixing their phase), fixed dates and elapsed values, no network (the diagram card is not rendered: use no mermaid block), fixed window size.

- [ ] **Step 1: Write the tool and its target.**
- [ ] **Step 2: Run it twice into two folders and compare.** The two runs must be byte-identical for every image. A state that differs between two runs of the SAME code is not deterministic: fix its cause (an animation, a clock, a random id shown on screen) before going on, or drop that one element from the state and say so. This is the tool's own test: without it, a later difference means nothing.
- [ ] **Step 3: Keep the baseline.** Copy the images to a folder outside the repository (`/private/tmp/claude-501/chat-snapshots/before/`) and record in the report the list of files with a checksum each.
- [ ] **Step 4: Commit** the tool and target only: `test(vitruvian): a tool that renders the Nexus Agent chat's states to images`

---

### Task 2: The `NexusAgentUI` library exists, builds both ways, and is pinned

**Files:**
- Create: `apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/NexusAgentChatStrings.swift`, `NexusAgentChatChrome.swift`
- Create: `apps/desktop/nexus-agent/macos/Tests/ChatSymbolsTests.swift`
- Modify: `apps/desktop/nexus-agent/macos/BUILD`, `Package.swift`; `apps/desktop/vitruvian/BUILD` (pin inputs; `VitruvianUI` dependency)

**Interfaces — produces:**

```swift
/// Every piece of text the chat view shows, in the app's language right now.
public struct NexusAgentChatStrings: Sendable, Equatable {
    // One stored property per string the view reads today: the 23 fields of
    // Vitruvian's NexusAgentFeatureStrings that the view uses, with the same
    // names, and one more for each English literal hard-coded in the view
    // ("Permission Request", "Agent Environment", "Copy", …), named for what
    // it says. Defaults are today's English text, so `init()` is the
    // standalone's answer.
    public init(/* every field, defaulted */)
}

/// What differs between the apps around the same chat.
@MainActor
public struct NexusAgentChatChrome {
    /// Drawn behind the floating chat. Vitruvian passes its own backdrop.
    public var backdrop: AnyView
    /// True inside Vitruvian's notch: no backdrop, the drawer always open.
    public var isEmbedded: Bool
    /// The pin button's state; nil hides the button.
    public var isPinned: Binding<Bool>?
    /// Brings the chat window forward again (after the folder picker closes).
    public var showWindow: () -> Void
    /// The dock-into-notch button's action and its tooltip; nil hides the button.
    public var dockToNotch: (() -> Void)?
    public var dockToNotchHelp: String
    /// The URL scheme the diagram web view uses to report an error.
    public var errorScheme: String
    public init(/* every field; defaults: clear backdrop, not embedded, no pin, no-op show, no dock, "nexus-agent-error" */)
}
```

Build:
- `macos/BUILD`: a second filegroup `shared_ui_sources` over `Sources/NexusAgentUI/**/*.swift`; `swift_library(name = "NexusAgentUI", srcs = [":shared_ui_sources"], features = ["swift.enable_v6"], module_name = "NexusAgentUI", deps = [":NexusAgentCore"])` with the same visibility as the core; `NexusAgentLib` (the standalone app) depends on it; `NexusAgentTests` gets both filegroups as `data`.
- `macos/Package.swift`: `.target(name: "NexusAgentUI", dependencies: ["NexusAgentCore"], path: "Sources/NexusAgentUI")`, and the executable depends on it.
- `apps/desktop/vitruvian/BUILD`: the pin's binary and test take BOTH filegroups (args and data); `VitruvianUI` depends on `//apps/desktop/nexus-agent/macos:NexusAgentUI`.

- [ ] **Step 1: A failing test for the symbols.** `ChatSymbolsTests.swift`: read every `.swift` file under `Sources/NexusAgentUI` (through the runfiles, as `EngineHostTests` reads the core's sources; fail if none is found once Task 3 has moved the view — for now assert the two files of this task are found), collect every string literal passed as `systemName:` or `systemSymbolName:`, and assert `NSImage(systemSymbolName:accessibilityDescription:)` is non-nil for each. Include one test that feeds the collector a line with a made-up symbol name and asserts it is caught, so the test is known to bite.
- [ ] **Step 2: Write the two files, the targets and the pin wiring.** `mirror_build_test` must pass (the library builds under SwiftPM), both apps must build, and the pin test must fail until re-pinned and pass after.
- [ ] **Step 3: Commit:** `build(nexus-agent): a shared NexusAgentUI library, pinned with the core`

---

### Task 3: Move the view, and prove the look did not change

**Files:**
- Move: `apps/desktop/vitruvian/Sources/Vitruvian/UI/NexusAgent/NexusAgentQuickPromptView.swift` → `apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/` (split into a few files by responsibility as they are moved: the root view; message bubble and its parts; code and diagram blocks; controls and badges; the session row — no logic change, only where declarations live)
- Create: `apps/desktop/vitruvian/Sources/Vitruvian/UI/NexusAgent/NexusAgentQuickPromptView.swift` (the thin Vitruvian view with the old name and the old initialiser)
- Modify: `apps/desktop/vitruvian/Tests/SourceNames.swift` (symbols only the moved view drew), `apps/desktop/vitruvian/Tools/NexusAgentChatSnapshots.swift` only if it must name the wrapper differently, `apps/desktop/vitruvian/UPSTREAM.md`, the pin

**Interfaces — produces:**

```swift
// NexusAgentUI
public struct NexusAgentChatView: View {
    public init(engine: NexusAgentEngine, strings: NexusAgentChatStrings, chrome: NexusAgentChatChrome)
}

// Vitruvian, unchanged for its callers
package struct NexusAgentQuickPromptView: View {
    package init(embeddedInNotch: Bool = false)
}
```

Rules for the move:
- Licence check first (header and `git log --follow` authors of the view file), output in the report.
- The moved code changes only where it touched Vitruvian: `NexusAgentService.shared` and every `service` property become the observed `engine` (`@ObservedObject`), with the engine's `session` observed as it is today; `service.isPinned`, `showQuickPrompt()` and `dockToNotch()` become the chrome's members; `L10n`/`FeatureStrings` reads become the handed-in strings; `HUDBackdrop` becomes `chrome.backdrop`; `embeddedInNotch` becomes `chrome.isEmbedded`; the `vitruvian-error` scheme becomes `chrome.errorScheme`. Every English literal the view hard-codes becomes a string field whose default is that literal.
- The Vitruvian wrapper observes `NexusAgentService.shared` and `L10n.shared`, and on every body evaluation builds the strings from `FeatureStrings.nexusAgent(L10n.shared.language)` and the chrome from the service (`isPinned` as a binding to the service's property, `showWindow` → `showQuickPrompt()`, `dockToNotch` → `dockToNotch()` with today's tooltip text, `backdrop` → `HUDBackdrop` exactly as the old view configured it, `errorScheme` → `"vitruvian-error"`, `isEmbedded` → its parameter). The pin and dock buttons show in exactly the cases they show today (read the old view: they are not hidden when embedded).
- Declarations become `public` where the wrapper or the standalone will need them and stay internal otherwise.

- [ ] **Step 1: Write the wiring table before moving anything.** In the report: every place the old view calls into the service, `L10n`, strings, the backdrop or the notch, with file and line, and what it becomes. Every row must be accounted for after the move.
- [ ] **Step 2: Move, split, rewire, and write the wrapper.**
- [ ] **Step 3: Build and test.** Both apps build; `NexusAgentTests`, `mirror_build_test`, Vitruvian `unit_tests`, source lints, sources-in-sync all pass. `ChatSymbolsTests` now finds the moved files and every symbol resolves; remove from Vitruvian's `SourceNames.swift` the symbols no Vitruvian source draws any more (the lint says which).
- [ ] **Step 4: Render again and compare.** Run the snapshot tool into `/private/tmp/claude-501/chat-snapshots/after/` and compare every image with its baseline, byte for byte. Report the result per image. For any difference: produce a third image marking the differing pixels, find the cause and fix it; repeat until none differ. If a difference cannot be removed, stop and report it with the three images.
- [ ] **Step 5: Tests of the wrapper's wiring.** In Vitruvian's `NexusAgentTests.swift`, one new suite: the chrome the wrapper builds pins and unpins the service (set through the binding, read the service; set the service, read the binding); `showWindow` and `dockToNotch` call the service (observe their effect on a `Rig`, as the existing `pinningAndRetry` and `notchIntegration` suites do); the strings built for two different languages differ in a translated field and are equal in an untranslated one; the embedded flag is passed through. If the wrapper's builders are private to a view body, extract them as `static` functions on the wrapper so they can be tested without rendering.
- [ ] **Step 6: Re-pin, log, tidy, commit.** Log line: the chat view moved to the shared `NexusAgentUI` library; `NexusAgentQuickPromptView` here is now a thin view that hands it this app's service, translations, backdrop and notch action; images of 30-odd chat states rendered before and after are identical; add the moved file to the table of files released under MIT.

```bash
git commit -m "refactor(desktop): Vitruvian's Nexus Agent chat view comes from the shared library"
```

---

## Before opening the pull request

- [ ] The description says: what moved; that the look was compared by rendering N states before and after (give N and the result); what the wrapper hands in; which lint rules no longer reach the moved file and what replaces the symbol check; that the standalone is untouched until 3c.
- [ ] `Nexus Agent Mirror Toolchain` is green (Swift 6.1.2 builds the SwiftUI library). All checks green before it is queued.
- [ ] Title is `refactor(desktop): …` (no user-visible change).
