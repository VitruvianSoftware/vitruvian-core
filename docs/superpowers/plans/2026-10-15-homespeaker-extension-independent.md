# HomeSpeaker extension without the app: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: proposed, 2026-10-15. Not started.** James approves the design first. It starts from `main` after pull request #3341 (the live-monitor work) merges, and builds on it: design section 9.

**Goal:** the HomeSpeaker extension (the Vitruvian tool in `apps/desktop/home-speaker`) does everything the standalone app does without the app being installed. The app keeps working on its own, unchanged. When both are installed, whichever the person opens first asks which to use. It offers to copy settings and sign-ins across, quits the other, and offers to switch it off or move it to the Trash.

**The design:** `docs/superpowers/specs/2026-10-15-homespeaker-extension-independent-design.md`. Read its verdict and sections 2, 4 and 7 before any task. Section numbers below are that document's.

**Architecture, in one paragraph:**
- `HomeSpeakerCore` gains a `HomeSpeakerProfile`, which says where settings, sign-ins, history and cross-process messages live, and a `HomeSpeakerEngine` built from one.
- The app runs on `.app`, which is today's paths exactly. The extension runs on `.extension`, its Vitruvian data folder.
- The app's command line moves into Core, so the extension's `bin/tool` takes the same flags. That is how the Claude Code hook runs it.
- A small shared file, `~/.gemini/speaker_door.json`, records which one is chosen, and where the extension lives.
- The tool stops starting the app's program and calls the engine in its own process.

```mermaid
flowchart TD
    P1["PR 1: Tasks 1 to 6. One engine, two profiles. Refactor, no release"] --> P2["PR 2: Tasks 7 to 11. Driver, choice, copy, mark. Refactor, no release"]
    M0["PR 3341 lands first: the monitor in the app, its status file, the e2e harness"] --> P1
    P2 --> P3["PR 3: Tasks 12 to 16. Switch on. feat: releases home-speaker 1.19.0"]
    P3 --> R["Release 1.19.0: app zip and tool zip"]
    R --> H["By hand: H1 to H14 on a real Mac"]
    R --> P4["PR 4: Task 17. Catalogue pins 1.19.0, signed"]
    P3 --> MF["Any later monitor feat lands after PR 3"]
    R -.-> P5["PR 5: Task 18. macagent follows the choice, if question 1 is yes"]
    classDef wait fill:#fff3cd,stroke:#b58900,color:#111
    classDef flight fill:#dbeafe,stroke:#1d4ed8,color:#111
    class P1,P2,P3,P4,P5 flight
    class R,H,M0,MF wait
```

Blue is a pull request an agent opens. Amber waits for a person or for the other session.

## Decisions this plan makes

The design's decisions stand. These are the ones a worker trips over.

| # | Decision | Why |
|---|---|---|
| 1 | **Three pull requests, and only the third releases.** PR 1 and PR 2 are titled `refactor(home-speaker): …`, with every commit `refactor`, `test` or `docs`. PR 3 is the one `feat`. | release-please releases on any `feat` or `fix` under the folder (`tools/release-scope/release_scope.py`). A release where nothing a person sees changes is what that check exists to stop. Until PR 3, the tool still starts the app's program. |
| 2 | **The `.app` profile is today's paths, names and words, byte for byte.** Task 1 holds that with a test that reads each path. Task 4 holds the command line's printed lines with goldens. | App users and `macagent` must not notice (design section 8). |
| 3 | **The `.shared` singletons stay, as the app engine's parts.** | Dozens of call sites, the app's views and `macagent`'s contract depend on them. Moving them all is not this plan. |
| 4 | **`ProcessDriver` stays, renamed in its role.** It no longer runs jobs for the extension. It is how the extension finds the app and runs the app's `--login-item disable` (Task 9). | Only an app can switch its own login item off. |
| 5 | **No Vitruvian app change and no SDK change.** If a task seems to need one, stop and report BLOCKED. | Design section 5. |
| 6 | **The extension's texts are English, as the tool's are today.** The app's new texts are English, as the app's are. | Neither has a strings table. |
| 7 | **This plan starts from `main` after #3341 merges, and builds on it.** It reuses #3341's monitor status file, control message, `--chat-monitor` flag, page rows, `Invalid` sentences, `spokenLines` and end-to-end harness. It adds no monitor type of its own. It makes the seven changes in design section 9's table, and only those, in #3341's code. | James asked for the plan to build on #3341, not against it. If #3341 changes before it merges, re-check that table first. |
| 8 | **Every new test target or file goes into both `Package.swift` and `BUILD`.** The macOS lane in `.github/workflows/ci.yaml:431-451` runs `./scripts/test.sh` and the Bazel tool targets by label. | `Package.swift` says "MUST MIRROR BUILD". A test in neither runs nowhere. |
| 9 | **Not in this plan:** the chat monitor's own behaviour (#3341's), words beside the mark, retiring the app, a protocol request to switch a tool off. | Design section 11. |

## Global Constraints

- **Nothing in this plan was built.** Every statement about code that exists was checked against `origin/main` at `6a72b0af7`, and against #3341's diff as it stood on 2026-10-15. Everything about code to be written is a design. If the code contradicts the plan, the code is right: stop and report BLOCKED with what you found.
- **TDD.** Each task:
  1. Write the failing test first, and keep it as RED evidence.
  2. Write the code.
  3. See it GREEN.
  4. Plant each listed regression and see the named test fail with the named message.
  5. Undo each by hand. `git diff --stat` must show only the task's change.
- **No test reaches this Mac's HomeSpeaker, home, Google, Slack or speakers.** This is the stage-F rule: `docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-f.md:75`, "A test must never reach this Mac's HomeSpeaker, home or conversations".
  - Unit tests build engines on `HomeSpeakerProfile.extension(dataFolder:)` or `.app`-shaped profiles in a temporary folder.
  - They use stand-ins for `HomeBroadcasting`, `VolumeControlling`, `LocalSpeaking`, `MediaPausing`, `ScriptRunner`, `LoginItemControlling`, `HomeDiscovering` and the new `OtherApp` parts.
  - Program-level tests (`tool/conformance_test.py`) set `HOME` and `CFFIXED_USER_HOME` to a scratch folder, `HOMESPEAKER_DATA_FOLDER` to a folder inside it, and `HOMESPEAKER_PROGRAM=""`. They keep the `block-network` tag.
  - No test posts a distributed notification under the app's names, `com.vitruviansoftware.homespeaker.*`. A running app on this Mac would act on it.
- **Build and test** from `apps/desktop/home-speaker`:
  - `./scripts/test.sh` runs SwiftPM, both test targets.
  - From the repository root, one command at a time:
    `bazel test --config=macos-app //apps/desktop/home-speaker:HomeSpeakerToolTests //apps/desktop/home-speaker:tool_conformance_test //apps/desktop/home-speaker:tool_version_test //apps/desktop/home-speaker:zip_tool_test //apps/desktop/home-speaker:sync_secrets_test //apps/desktop/home-speaker:publish_test`.
  - Before each pull request, `./scripts/publish.sh --dry-run`.
  - `:HomeSpeakerTests` exists in Bazel but CI never runs it (`AGENTS.md`). SwiftPM is the truth for it.
- **Licences.** `apps/desktop/home-speaker` is MIT, with the header every source carries. Nothing is copied from `apps/desktop/vitruvian` (GPL).
- **Swift 6.** The tool's targets compile with `swift.enable_v6`. `HomeSpeakerCore` does not. `ConfigManager` is `@MainActor`, and so is the kit's loop, which runs on the main thread (`HomeSpeakerTool/main.swift:21-23`).
- **Headless runs.** The command line in Core keeps `Entry.runHeadless`'s shape: a detached task, and the main queue serviced with `dispatchMain`. A plain `Task {}` in a `@main` or top-level entry inherits the main actor and deadlocks.
- **The shared checkout.** Work in a locked worktree from `origin/main`. Never stash, reset or check out in the primary checkout.
- **Release scope.** PR 1 to PR 3 change files only under `apps/desktop/home-speaker/` and `docs/`. `release-scope` must pass with no `Releases:` line. PR 3 releases `home-speaker` only.

## Review Focus

Where a mistake costs most. Each has a test in the task named.

1. **App users notice nothing.** The `.app` profile's paths and message names, and the command line's printed lines, are today's (Task 1, `appProfileIsTodays`; Task 4, the goldens).
2. **Nothing is said twice.**
   - Each hook run does nothing when the other side is chosen and installed (Task 4, `aHookStandsAsideForTheChosenOther`).
   - The app never re-points the extension's hook (Task 5, `theAppLeavesTheExtensionsHookAlone`).
   - Messages are per side (Task 2, `theExtensionNeverPostsUnderTheAppsNames`).
   - The monitor starts only while active, after the other has gone quiet (Task 12, `theMonitorWaitsForTheOtherToStop`).
3. **Signing out of the quiet side never signs the active side out** (Task 8, `theQuietSideNeverRevokesASharedLogin`).
4. **Copy is a copy.** The source files are byte-identical afterwards. No token is ever drawn, logged or put in a notice (Task 8).
5. **The Trash, never a delete.** The app is never removed outright, and a copy already in the Trash is never "installed" (Task 9, Task 7).
6. **No test can reach this Mac's HomeSpeaker or home** (Task 13, `theFolderIsTheScratchHomes`; the conformance test).

## The strings

New words a person reads. The extension's and the app's use the same sentences.

| Where | Text |
|---|---|
| Both, the choice card's heading | HomeSpeaker is installed twice |
| Both, its body | The HomeSpeaker app and the Vitruvian extension can both speak on your speakers. Use one, so nothing is said twice. |
| Both, buttons | Use the extension · Use the app |
| Both, the copy step | Copy from the app · Copy from the extension · Keep what this one has |
| Both, the copy note | Sign-ins are copied, never shown. macOS permissions, such as pausing music, are asked for again. |
| Extension, after choosing it | The app has quit. · Turn off the app's Open at Login · Move HomeSpeaker.app to the Trash |
| Extension, the Trash warning | Your phone remote and scripts that call HomeSpeaker.app will stop working until they are pointed at the extension. |
| App, after choosing it | The extension is quiet now. To remove it: Vitruvian > Settings > Features > Tools from outside > HomeSpeaker > Remove. · Open Vitruvian |
| Both, the quiet one | The HomeSpeaker {app/extension} is in use, so this one stays quiet. · Use this one instead |
| Both, General | Which HomeSpeaker · This Mac uses the {app/extension}. · Use the {other} instead · Copy settings from the {other} |
| Extension, General, in place of the login switch | Runs whenever Vitruvian runs. To start it at login, turn on Vitruvian's Open at Login. |
| Extension, an old app | This copy of the app is older than 1.19 and will take the Claude Code hook back if it is opened again. Move it to the Trash, or update it. |
| Extension, an old extension seen by the app | (nothing: an extension older than 1.19 is not a second HomeSpeaker) |

---

## Pull request 1: one engine, two profiles (no release)

### Task 1: The profile and the engine

**Worker:** `wren`. **Commit:** `refactor(home-speaker): the engine knows where its files are`. Nothing a person sees changes.

**Files:**
- Create: `Sources/HomeSpeakerCore/Profile.swift`, `Sources/HomeSpeakerCore/Engine.swift`
- Modify: `Sources/HomeSpeakerCore/ConfigManager.swift`, `GoogleAuth.swift`, `GoogleHomeClient.swift`, `Announcer.swift`
- Create: `Tests/HomeSpeakerTests/ProfileTests.swift`
- Modify: `Package.swift` and `BUILD` only if a target changes (none expected)

**Interfaces:**
- Consumes:
  - `ConfigManager.init(configPath:historyPath:secrets:fileSystem:)` (`ConfigManager.swift:66-81`);
  - `SecretStore.init(fileURL:)` (`SecretStore.swift:129`);
  - `BroadcastHistory.init(fileURL:)` (`BroadcastHistory.swift:54`);
  - `GoogleAuth.init(store:session:)` (`GoogleAuth.swift:129`);
  - `GoogleHomeClient.init(auth:session:)` (`GoogleHomeClient.swift:61`);
  - `Announcer.init(home:local:…)` (`Announcer.swift:118`).
- Produces:
  - `public struct HomeSpeakerProfile: Sendable, Equatable` with:
    - `door: Door`, where `Door` is `.app` or `.extension`;
    - `settingsURL`, `historyURL`, `secretsURL`;
    - `monitorStatusURL`: #3341's `ChatMonitorStatusFile.url(beside: settingsURL)`, so the app's is #3341's file and the extension's is `<data>/speaker_monitor_status.json`;
    - `messagePrefix: String`;
    - `liveLockURL: URL?`;
    - `toolFolder: URL?`.
  - `static func app(home: URL) -> Self`: today's paths, prefix `com.vitruviansoftware.homespeaker`.
  - `static func extension(dataFolder: URL, toolFolder: URL?) -> Self`: `settings.json`, `history.json`, `secrets.json`, `running.lock` in `dataFolder`; prefix `dev.vitruvian.homespeaker`.
  - `static func extensionFolders(program: URL) -> (tool: URL, data: URL)?`: `…/Tools/<id>/bin/tool` gives `…/Tools/<id>` and `…/ToolData/<id>`. Nil for any other shape.
  - `@MainActor public final class HomeSpeakerEngine` with `profile`, `config: ConfigManager`, `secrets: SecretStore`, `history: BroadcastHistory`, `auth: GoogleAuth`, `home: GoogleHomeClient` and `announcer: Announcer`, plus `init(profile:session:local:)`. The pause and restore parts come in Task 2.
  - `HomeSpeakerEngine.app`: the engine whose parts the existing `.shared` singletons are.

- [ ] **Step 1: Write the failing tests** (`ProfileTests`):
  - `appProfileIsTodays`: each of the three URLs equals `ConfigManager.defaultConfigURL()`, `BroadcastHistory.defaultURL()` and `SecretStore.defaultURL()` for the same home, and the prefix is `com.vitruviansoftware.homespeaker`.
  - `extensionProfileLivesInItsDataFolder`: every URL is inside the given folder; none is under `.gemini` or `Application Support/HomeSpeaker`.
  - `extensionFoldersFromTheProgram`: a Vitruvian-shaped path gives both folders; `bazel-bin/…/built/homespeaker/bin/tool`, a relative path and `/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker` give nil.
  - `oneEngineOneSecretsFile`: an engine on a temporary extension profile. A login saved through `engine.secrets` is what `engine.auth` and `engine.home` read. The app's `SecretStore.shared` file is not touched (its modification date is unchanged, or it does not exist under the test's scratch home).
- [ ] **Step 2: Watch them fail.**
- [ ] **Step 3: Write the code.** `ConfigManager.shared`, `SecretStore.shared`, `BroadcastHistory.shared`, `GoogleAuth.shared` and `GoogleHomeClient.shared` become `HomeSpeakerEngine.app`'s parts, or stay as they are with `HomeSpeakerEngine.app` built from them. Either way, the same objects.
- [ ] **Step 4: Watch them pass**, and the whole of `./scripts/test.sh`. Record the counts.
- [ ] **Step 5: Plant the regressions**, each seen to fail:
  1. "the extension writes the app's secrets": `extension(...)`'s `secretsURL` returns `SecretStore.defaultURL()`. Fails `extensionProfileLivesInItsDataFolder`.
  2. "the engine's sign-in reads another file": `HomeSpeakerEngine.init` builds `GoogleAuth(store: .shared)`. Fails `oneEngineOneSecretsFile`.
  3. "a dev build guesses the data folder": `extensionFolders` returns the fixed home path for any program. Fails `extensionFoldersFromTheProgram`.
- [ ] **Step 6: Commit.**

### Task 2: Each side's messages, and "is anyone alive to put the volume back"

**Worker:** `wren`. **Commit:** `refactor(home-speaker): cross-process messages are named per profile`.

**Files:**
- Modify: `Sources/HomeSpeakerCore/MediaPause.swift` (`MediaPauseRequest`, `:589-645`), `SpeakerVolume.swift` (`VolumeRestoreRequest`, `:330-380`), `SignOutNotice.swift` (`:29-132`), `Engine.swift`
- Create: `Sources/HomeSpeakerCore/LiveLock.swift`, `Tests/HomeSpeakerTests/MessageNamesTests.swift`

**Interfaces:**
- Produces:
  - Each request and notice takes its name from a `HomeSpeakerProfile`: `<prefix>.media-pause`, `.volume-restore`, `.signed-out`, `.credentials-changed`, and #3341's `.chat-monitor-control`, through `profile.messageName(_:)`. `ChatMonitorControlNotice` already takes `name:`; its callers pass the profile's.
  - `profile.ownerRunning() -> Bool`: is the process that runs this side's monitor alive? The app checks for its running app (today's `isAppRunning`). The extension checks `LiveLock.isHeld(at: liveLockURL)`. #3341's `ChatMonitorStatus.believed(appRunning:)` and `Pages.Chat.appRunning` are renamed `ownerRunning` and fed by it. These are the named edits design section 9 allows.
  - The process's profile is set once, at the program's start, through `HomeSpeakerProfile.useForThisProcess(_:)`, before anything posts or listens. The default is `.app`, so the app and old callers are unchanged.
  - `VolumeRestoreRequest.canRestore()` asks the profile:
    - `.app`: today's check, a running app with the bundle id;
    - `.extension`: `LiveLock.isHeld(at: liveLockURL)`.
  - `LiveLock`: `hold(at:) throws -> LiveLock`, which keeps an exclusive `flock` until released or the process ends, and `static isHeld(at:) -> Bool`, which tries a non-blocking lock and lets go at once.
  - `HomeSpeakerEngine` gains `mediaPause: MediaPauseCoordinator`, `volumeRestore: VolumeRestoreCoordinator` and `listen() -> [NSObjectProtocol]`. The last starts both listeners and the two notices on the profile's names.

- [ ] **Step 1: Write the failing tests** (`MessageNamesTests`):
  - `theAppsNamesAreTodays`: the five names equal today's literals, #3341's control message included.
  - `theExtensionNeverPostsUnderTheAppsNames`: with the extension profile, every name starts with `dev.vitruvian.homespeaker.`. This is checked on the names, not by posting.
  - `aHeldLockIsSeen` and `aReleasedLockIsNot`, in a temporary folder.
  - `canRestoreAsksTheLockForTheExtension`: the extension profile with no lock held gives false, even while an app with the app's bundle id runs. That case is checked through an injected list of running apps; nothing real is posted.
- [ ] **Step 2: Watch them fail.**
- [ ] **Step 3: Write the code.**
- [ ] **Step 4: Watch them pass.**
- [ ] **Step 5: Plant the regressions:**
  1. "the extension's hook pauses the app's music": `MediaPauseRequest`'s name ignores the profile. Fails `theExtensionNeverPostsUnderTheAppsNames`.
  2. "a raised volume is left raised": the extension's `canRestore` checks the app's bundle id. Fails `canRestoreAsksTheLockForTheExtension`.
  3. "the lock is never let go": `isHeld` takes the lock and keeps it. Fails `aReleasedLockIsNot` on its second call.
- [ ] **Step 6: Commit.**

### Task 3: The sign-in client comes from the profile

**Worker:** `wren`. **Commit:** `refactor(home-speaker): the Google sign-in client is passed in, not read from the bundle`.

**Files:**
- Modify: `Sources/HomeSpeakerCore/GoogleAuth.swift` (`OAuthClient.resolve`, `:72-89`; `signIn`, `:217-223`), `Profile.swift`, `Sources/HomeSpeakerToolCore/Account.swift` (`hasOAuthClient`, `hasBundledOAuthClient`)
- Create: `Sources/HomeSpeakerCore/OAuthClientFile.swift`
- Modify: `Tests/HomeSpeakerTests/HomeSpeakerCoreTests.swift`; create `Tests/HomeSpeakerToolTests/AccountTests.swift`

**Interfaces:**
- Produces:
  - `OAuthClient.resolve(secrets:shipped:) -> OAuthClient?`. The order is unchanged: the person's own client, then `shipped`, then a saved login's client.
  - `HomeSpeakerProfile.shippedClient: OAuthClient?`:
    - `.app`: the `Info.plist`'s `GoogleOAuthClientID` and `GoogleOAuthClientSecret`, as today;
    - `.extension`: `OAuthClientFile.read(toolFolder/google-oauth-client.json)`.
  - `OAuthClientFile`: `{"client_id": "...", "client_secret": "..."}`. A missing or empty file is nil. It is never written by the program.

- [ ] **Step 1: Failing tests:**
  - `theOwnClientWins`, `theShippedClientIsNext` and `aSavedLoginsClientIsLast`.
  - `anEmptyShippedFileIsNone`.
  - `theExtensionNeverReadsTheMainBundle`: the extension profile's `shippedClient` is nil with no file, even when `Bundle.main` has a client id. The bundle is injected.
  - `hasBundledOAuthClient` in `AccountTests` reads the profile.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the extension signs in with whatever bundle runs it": `.extension`'s `shippedClient` reads `Bundle.main`. Fails `theExtensionNeverReadsTheMainBundle`.
  2. "the shipped client beats the person's own": swap the first two branches. Fails `theOwnClientWins`.
- [ ] **Step 6: Commit.**

### Task 4: The command line moves into Core, and a hook stands aside for the chosen other

**Worker:** `wren`. **Commit:** `refactor(home-speaker): the command line lives in Core and runs on any engine`.

**Files:**
- Create: `Sources/HomeSpeakerCore/CommandLine.swift`
- Modify: `Sources/HomeSpeaker/Entry.swift` (it shrinks to: call `HomeSpeakerCommandLine.run`, else `HomeSpeakerApp.main()`), `Sources/HomeSpeakerCore/ClaudeStopHook.swift` (`run`, `DetachedAnnouncement.launch`), `AppCommands.swift` (the out-of-date "keychain-held" comment at `:25`)
- Create: `Tests/HomeSpeakerTests/CommandLineTests.swift`, with golden files under `Tests/HomeSpeakerTests/Goldens/`

**Interfaces:**
- Consumes: `Entry.announce`, the volume block, `--sign-in`, `run(_ command:)` and `--help` (`Entry.swift:26-246` on `6a72b0af7`), as #3341 left them: its `--chat-monitor start|stop` and `AnnounceOutcome.spokenLines` move too. Also `AppCommandParser` and `AppCommandRunner`.
- Produces:
  - `public enum HomeSpeakerCommandLine`, with:
    - `static func recognizes(_ arguments: [String]) -> Bool`;
    - `static func run(_ arguments: [String], engine: HomeSpeakerEngine, parts: Parts) -> Never`, which prints, exits and keeps today's exit codes;
    - a pure `static func outcome(...) async -> CLIOutput` per flag, for the tests.
  - `Parts` holds what the real run injects:
    - opening the browser;
    - the login item (`SystemLoginItem` for the app; a refusal for the extension: "the extension runs while Vitruvian runs; it has no login item of its own");
    - `standsAside: () -> Bool` (below).
  - **The hook guard:** `--claude-stop-hook` and `--announce` print `{}` (the hook) or nothing, and exit 0 without speaking, when `standsAside()` is true. Task 7 supplies the real `standsAside`: the choice file names the other side, and the other side is installed. Until then it is `{ false }`.
  - `DetachedAnnouncement.launch` keeps `Bundle.main.executablePath`. For `bin/tool`, that is the tool's own program. A test holds it.

- [ ] **Step 1: Failing tests:**
  - Goldens of today's printed lines and exit codes, made by running today's `Entry` paths against stand-ins:
    - `--say` with broadcasting off, quiet hours, no speaker, nothing to say, spoken home, and spoken on this Mac;
    - `--volume` with no speaker, available, and an error;
    - `--set-volume 101` and `--set-volume x`;
    - `--sign-out --chat`;
    - `--discover` with two homes;
    - `--chat-monitor start` and `--chat-monitor stop`: the line printed and the message posted, under the profile's name, to a recording poster;
    - `--help`;
    - `--version`.
  - `everyGoldenStillMatches`.
  - `aHookStandsAsideForTheChosenOther`: with `standsAside` true, the hook prints `{}`, exits 0, and the broadcaster stand-in is never called.
  - `aDeliberateSayDoesNotStandAside`: with `standsAside` true, `--say` still speaks and adds the stderr line "note: the HomeSpeaker {other} is the one in use".
  - `theExtensionHasNoLoginItem`.
- [ ] **Step 2: Record the goldens from today's code first**, then watch the new tests fail against the not-yet-moved code.
- [ ] **Step 3: Move the code.** `Entry.swift` ends at about 30 lines.
- [ ] **Step 4: Watch them pass.**
- [ ] **Step 5: Plant:**
  1. "the hook speaks for the side that was not chosen": drop the guard. Fails `aHookStandsAsideForTheChosenOther`.
  2. "a script's `--say` is silenced": apply the guard to `--say`. Fails `aDeliberateSayDoesNotStandAside`.
  3. "the volume JSON changed shape" (`macagent` parses it): drop `sortedKeys`. Fails `everyGoldenStillMatches`.
- [ ] **Step 6: Commit.**

### Task 5: Hooks can run the extension's program, and the app stops taking them back

**Worker:** `wren`. **Commit:** `refactor(home-speaker): a hook may run the extension, and the app leaves it there`.

**Files:**
- Modify: `Sources/HomeSpeakerCore/AgentIntegration.swift` (`isHomeSpeakerProgram`, `:208-210`; `repairHookIfMoved`, `:436-443`; `hookStatus`)
- Modify: `Tests/HomeSpeakerTests/SharedFoundationTests.swift` or create `Tests/HomeSpeakerTests/HookOwnerTests.swift`

**Interfaces:**
- Produces:
  - `isHomeSpeakerProgram(_:)` is true for `…/HomeSpeaker` (today) and for `…/Tools/dev.vitruvian.homespeaker/bin/tool`.
  - `HookStatus` gains the hook's program.
  - `repairHookIfMoved(extensionProgramExists:choice:)` re-points to itself only when:
    - the hook's program does not exist; or
    - it is another copy of the app; or
    - it is the extension's program and the choice file names the app.

    It never re-points while the hook runs the extension's existing program and the choice is the extension or absent.
  - `installHook` writes the program it was built with. One HomeSpeaker hook per agent, as `mergeHook` keeps it today.

- [ ] **Step 1: Failing tests:**
  - `theExtensionsProgramIsAHomeSpeaker`.
  - `aRandomToolIsNot`: a path `…/Tools/other.tool/bin/tool`.
  - `theAppLeavesTheExtensionsHookAlone`: settings in a temporary home, with the hook on the extension's existing program and no choice. The app's repair writes nothing (the file's bytes are unchanged).
  - `theAppTakesTheHookBackWhenChosen`: the same, with the choice set to the app.
  - `theAppRepairsAHookToAMissingProgram`.
  - `installingOneReplacesTheOther`: install with the app program, then with the extension program. Exactly one HomeSpeaker hook.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the app steals the hook at launch": today's `repairHookIfMoved` body. Fails `theAppLeavesTheExtensionsHookAlone`.
  2. "any program called tool is HomeSpeaker": match on the last component only. Fails `aRandomToolIsNot`.
- [ ] **Step 6: Commit.**

### Task 6: The Keychain check, the monitor's sign-in, and pull request 1

**Worker:** `wren`. **Commit:** `refactor(home-speaker): no source touches the Keychain, and the monitor can take an engine's sign-in`.

**Files:**
- Modify: `Tests/HomeSpeakerTests/ProductionReadinessTests.swift` (the source scan)
- Modify, **only if the monitor session agreed** (design section 9, ask 2): `Sources/HomeSpeakerCore/ChatMonitorService.swift`. `init` gains `auth: GoogleAuth = .shared`, passed to `GoogleChatClient(auth:)` where it is built today with no argument (`:451` on `6a72b0af7`). If they do it themselves, this task waits for theirs and only adds the test.
- Create: `Tests/HomeSpeakerTests/MonitorEngineTests.swift`

**Interfaces:** after #3341, `ChatMonitorService.init(configManager:secrets:home:announcer:statusFile:auth:)`. No new monitor type: the extension uses #3341's `ChatMonitorService`, `ChatMonitorStatusFile` and `ChatMonitorControlNotice` as they are (design section 9).

- [ ] **Step 1: Failing tests:**
  - `noSourceTouchesTheKeychain`: no `SecItem` and no `import Security` in any `Sources/` file.
  - `theMonitorReadsChatWithItsEnginesSignIn`: a monitor built from an engine on a temporary extension profile asks that engine's `GoogleAuth` for its Chat token. A stand-in `URLSession` records the bearer token, which is the temporary login's, never the app's.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "a Keychain call slips in": add `import Security` to a source file. Fails `noSourceTouchesTheKeychain`.
  2. "the extension reads Google Chat with the app's sign-in": build `GoogleChatClient()` with no argument. Fails `theMonitorReadsChatWithItsEnginesSignIn`.
- [ ] **Step 6: Commit.**
- [ ] **Step 7: Run everything** (Global Constraints) and open **pull request 1**: `refactor(home-speaker): one engine that knows where its files are`. The body says nothing a person sees changes, so no release. Check `release-scope` is green. Tell the monitor session the pull request's number, through James.

---

## Pull request 2: the extension's own parts, not yet switched on (no release)

### Task 7: The choice file, and who runs

**Worker:** `wren`. **Commit:** `refactor(home-speaker): one file records which HomeSpeaker is in use`.

**Files:**
- Create: `Sources/HomeSpeakerCore/Door.swift`, `Tests/HomeSpeakerTests/DoorTests.swift`

**Interfaces:**
- Produces:
  - `public struct DoorRecord: Codable, Equatable`, the design's JSON (section 7.1), with today's merge-on-write rule: keys this version does not know survive.
  - `public struct DoorFile`:
    - `init(url:)`, defaulting to `~/.gemini/speaker_door.json`;
    - `read() -> DoorRecord?`;
    - `update(_ change: (inout DoorRecord) -> Void) throws`, under `FileLock` on `speaker_door.json.lock`.
  - `public enum DoorRole: Equatable { case active, activeAsking, waitingAsking, quiet(other: Door) }`.
  - `DoorRole.decide(me: Door, otherInstalled: Bool, chosen: Door?) -> DoorRole`: exactly design table 7.3.
  - `OtherDoorPresence`:
    - `appInstalled(locate:)`, with any path containing `/.Trash/` excluded;
    - `extensionInstalled(record:fileExists:minimumVersion: "1.19.0")`.
  - `standsAside(me:)`, for Task 4's guard: true exactly when `decide` gives `.quiet`.

- [ ] **Step 1: Failing tests:**
  - `eachRowOfTheTable`: eight cases, one per row and side.
  - `aStaleChoiceIsIgnoredWhenTheOtherIsGone`.
  - `theAppInTheTrashIsNotInstalled`: `~/.Trash/HomeSpeaker.app` and `/Users/x/.Trash/HomeSpeaker 2.app`.
  - `anOldExtensionIsNotASecondHomeSpeaker`: versions 1.17.0 and 1.18.0.
  - `aMissingExtensionProgramIsNotInstalled`.
  - `unknownKeysSurvive`.
  - `twoWritersBothLand`: two `update`s from two `DoorFile`s on one file.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the Trash counts as installed": drop the exclusion. Fails `theAppInTheTrashIsNotInstalled`.
  2. "undecided silences the app": `decide(.app, true, nil)` gives `.waitingAsking`. Fails `eachRowOfTheTable`.
  3. "an old extension is asked to run alone": drop the version check. Fails `anOldExtensionIsNotASecondHomeSpeaker`.
- [ ] **Step 6: Commit.**

### Task 8: Comparing the two, and copying one into the other

**Worker:** `wren`. **Commit:** `refactor(home-speaker): compare the app and the extension, and copy one into the other`.

**Files:**
- Create: `Sources/HomeSpeakerCore/DoorCopy.swift`, `Tests/HomeSpeakerTests/DoorCopyTests.swift`
- Modify: `Sources/HomeSpeakerCore/GoogleAuth.swift` (`signOut`, `:310`): the quiet side's sign-out does not revoke a login the other side holds

**Interfaces:**
- Produces:
  - `public struct DoorSnapshot: Equatable`:
    - `settingsRead: ConfigFileRead`, `settingsChanged: Date?`;
    - `googleEmail: String?`, `hasHomeLogin`, `hasChatLogin`, `hasSlackToken`, `hasOwnClient`;
    - `homeName: String?`, `speakerCount`, `defaultSpeaker: String?`;
    - `outputs` (home, this Mac or both), `quietHours: String?`, `chatSources: [String]`, `historyCount`.

    It is built from a profile's three files. It holds no token, by construction: a test checks every stored property's type.
  - `DoorCopy.suggest(chosen: DoorSnapshot, other: DoorSnapshot) -> Suggestion`, with `Suggestion` either `.copyFromOther` or `.keep`. The rules are design section 7.4, step 2.
  - `DoorCopy.copy(from: HomeSpeakerProfile, to: HomeSpeakerProfile) throws -> CopyReport`:
    - settings through `SpeakerConfigFile.write`;
    - `Secrets` through one `SecretStore.update`;
    - history merged by id, newest 30.

    It throws, writing nothing, when the destination's settings file does not read. `CopyReport` lists what was copied, in words, with no value of any token.
  - `GoogleAuth.signOut(purpose:revoke:)` is unchanged. The new `HomeSpeakerEngine.signOut(chatOnly:otherSecrets:)` passes `revoke: false` when the other side's `Secrets` holds the same refresh token.

- [ ] **Step 1: Failing tests:**
  - `aSnapshotHoldsNoToken`.
  - `suggestCopyWhenTheChosenIsEmpty`, `suggestKeepWhenOnlyTheChosenIsSetUp` and `suggestTheNewerWhenBothAre`.
  - `copyCopiesSettingsSecretsAndHistory`.
  - `theSourceIsUntouched`: its three files are byte-identical before and after.
  - `historyIsMergedNotReplaced`: 20 and 20 with 5 shared give 30, newest first, no duplicates.
  - `anUnreadableDestinationStopsTheCopy`.
  - `theReportNamesNoToken`: a Slack token `xoxp-secret-123` and a refresh token `1//secret` appear in no line.
  - `theQuietSideNeverRevokesASharedLogin`: a stand-in revoke endpoint is never called when the tokens match, and is called when they differ.
  - `theCopiedSecretsAre0600`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "copy moves": delete the source's secrets after writing. Fails `theSourceIsUntouched`.
  2. "the quiet side signs both out": always `revoke: true`. Fails `theQuietSideNeverRevokesASharedLogin`.
  3. "the history is overwritten": write the source's list. Fails `historyIsMergedNotReplaced`.
  4. "a token in the report": add `slackToken` to a report line. Fails `theReportNamesNoToken`.
- [ ] **Step 6: Commit.**

### Task 9: Closing the other one

**Worker:** `wren`. **Commit:** `refactor(home-speaker): quit the app, switch its login item off, or move it to the Trash`.

**Files:**
- Create: `Sources/HomeSpeakerToolCore/OtherApp.swift`, `Tests/HomeSpeakerToolTests/OtherAppTests.swift`
- Modify: `Sources/HomeSpeakerToolCore/Speaker.swift`: `ProcessDriver` keeps `locate`, `isAppRunning`, `arguments` and `result`. The tool no longer gives it jobs from Task 12 on.

**Interfaces:**
- Produces:
  - `public protocol OtherAppControlling`, with:
    - `isRunning`;
    - `version: String?`, from the bundle's `Info.plist`, read afresh;
    - `quit(timeout:) async -> Bool`, which calls `terminate()` on the running app (activation policy not `.prohibited`) and waits;
    - `turnOffLoginItem() async -> Result<Void, String>`, which runs the app's own `--login-item disable` and parses `login item: disabled`. An app older than 1.13.2 has no such flag (`AppCommands.swift` arrived in #3325): the result is a failure that names System Settings > General > Login Items;
    - `moveToTrash() throws -> URL`, which is `NSWorkspace.recycle` only.
  - `SystemOtherApp`, the real one.
  - `OtherAppPlan.forChoosingTheExtension(appVersion:) -> [Step]`: quit always; the login item offered and ticked; the Trash offered and not ticked; with an app older than 1.19, the login item step is not optional and the old-app warning is shown.

- [ ] **Step 1: Failing tests**, with injected running apps, process runner and workspace:
  - `quitAsksOnlyTheMenuBarApp`: a `.prohibited` command-line run is never terminated.
  - `aLoginItemFailureIsSaid`.
  - `aVeryOldAppIsToldWhereToLook`: version 1.13.1 gives the System Settings sentence and runs nothing.
  - `theTrashIsRecycleNeverRemove`: the stand-in workspace records `recycle`. A stand-in `FileManager.removeItem` is never called.
  - `anOldAppMustLoseItsLoginItem`.
  - `aNewAppIsOfferedNotForced`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the app is deleted": `moveToTrash` calls `removeItem`. Fails `theTrashIsRecycleNeverRemove`.
  2. "a script's `--say` is killed": terminate every process with the bundle id. Fails `quitAsksOnlyTheMenuBarApp`.
  3. "an old app is left at login": treat every version as new. Fails `anOldAppMustLoseItsLoginItem`.
- [ ] **Step 6: Commit.**

### Task 10: The extension's jobs, in its own process

**Worker:** `wren`. **Commit:** `refactor(home-speaker): the tool's jobs can run on its own engine`.

**Files:**
- Create: `Sources/HomeSpeakerToolCore/EngineDriver.swift`, `Tests/HomeSpeakerToolTests/EngineDriverTests.swift`

**Interfaces:**
- Consumes: `SpeakerDriver` and `Job`/`JobResult` (`Speaker.swift:26-97`); the engine; Task 4's per-flag `outcome` functions.
- Produces:
  - `public final class EngineDriver: SpeakerDriver`. `isInstalled` is always true. `program` is the tool's own program, for the hook.
  - `run(_:then:)` runs each `Job` through the same Core function the command line uses. It answers the same `JobResult` the tool's state machine already handles. Then `HomeSpeakerTool.finished` needs no change, which is the point.
  - `.app(.loginItem)` answers `.failed("the extension runs while Vitruvian runs")`. The page stops asking for it in Task 14.
  - `.signIn` opens the browser through the link's `open/url` when a link is given, else through `NSWorkspace`.
  - `.say` records the history in `engine.history` with source `"Say"`, as `--say` does.

- [ ] **Step 1: Failing tests**, with an engine on a temporary profile and stand-ins for Google, this Mac's speech and media:
  - `sayAnswersAsTheProgramDid`: each `--say` golden of Task 4 maps to the same `JobResult` `ProcessDriver.result` gives for that output.
  - `volumeAnswersAsTheProgramDid`, for set, mute and unmute.
  - `discoverWithoutSaveListsHomes` and `discoverWithSaveSavesToTheExtensionsSettings`: the app's settings file is not written.
  - `signOutClearsTheExtensionsSecretsOnly`.
  - `aSayIsRecordedInTheExtensionsHistory`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "discovery saves into the app's settings": use `ConfigManager.shared`. Fails `discoverWithSaveSavesToTheExtensionsSettings`.
  2. "a spoken line is not recorded": drop the append. Fails `aSayIsRecordedInTheExtensionsHistory`.
- [ ] **Step 6: Commit.**

### Task 11: The mark on the closed island, and pull request 2

**Worker:** `wren`. **Commit:** `refactor(home-speaker): what the closed-island mark says`.

**Files:**
- Create: `Sources/HomeSpeakerToolCore/Status.swift`, `Tests/HomeSpeakerToolTests/StatusTests.swift`

**Interfaces:**
- Produces:
  - `public struct StatusInputs: Equatable`, with:
    - `role: DoorRole`;
    - `signInProblem: String?`;
    - `monitorProblem: String?`, from #3341's `Pages.Chat.runtimeError`, which is `ChatMonitorStatus.lastError` believed only while its owner runs;
    - `setUp: Bool`, `speaking: Bool`, `quietUntil: String?`;
    - `broadcasting: Bool`, `defaultSpeaker: String?`.
  - `public struct MarkChoice: Equatable { state: StatusState; icon: String?; text: String? }`.
  - `public static func mark(_ inputs: StatusInputs) -> MarkChoice`: exactly design section 6's table, worst row first.

- [ ] **Step 1: Failing tests:** one test per row of the table, plus `failureBeatsSpeaking`, `quietSideShowsNothing` and `undecidedBeatsEverythingButFailure`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the quiet one nags": `.quiet` gives `attention`. Fails `quietSideShowsNothing`.
  2. "a broken sign-in hides behind speaking": swap the two rows. Fails `failureBeatsSpeaking`.
- [ ] **Step 6: Commit.**
- [ ] **Step 7: Run everything** and open **pull request 2**: `refactor(home-speaker): the extension's own driver, choice and copy, not yet switched on`. No release. `release-scope` is green.

---

## Pull request 3: switch it on (releases home-speaker 1.19.0)

### Task 12: The tool's program runs on its own engine

**Worker:** `wren`. **Commit:** `feat(home-speaker): the extension speaks, signs in and finds speakers without the app`.

**Files:**
- Modify: `Sources/HomeSpeakerTool/main.swift`, `Sources/HomeSpeakerToolCore/HomeSpeakerTool.swift`, `Account.swift`, `Config.swift`
- Modify: `Tests/HomeSpeakerToolTests/HomeSpeakerToolTests.swift`, `IslandTests.swift`, `SettingsTests.swift`, `SharedFileTests.swift` (which held the shared file, and now holds that the extension does *not* read it)
- Create: `Tests/HomeSpeakerToolTests/DoorRoleTests.swift`

**What `main.swift` does, in order:**
1. Work out the profile:
   - `HOMESPEAKER_DATA_FOLDER` if set;
   - else `HomeSpeakerProfile.extensionFolders(program:)` from its own real path;
   - else, when started by Vitruvian, `initialize`'s `dataFolder`, with the tool folder as the program's grandparent.

   Call `useForThisProcess`.
2. If `HomeSpeakerCommandLine.recognizes(arguments)`: run it on the extension engine, with `standsAside` from the choice file, and exit. A program whose path gives no profile, with no variable set, refuses: "run the installed extension, or set HOMESPEAKER_DATA_FOLDER".
3. Otherwise:
   - hold `running.lock`;
   - `engine.listen()`;
   - write the `extension` block of the choice file;
   - build #3341's `ChatMonitorService` from the engine: `configManager: engine.config`, `secrets: engine.secrets`, `home: engine.home`, `announcer: engine.announcer`, `auth: engine.auth` (Task 6), and `statusFile: ChatMonitorStatusFile(url: profile.monitorStatusURL)`. Listen with `ChatMonitorControlNotice.listen(name: profile.messageName(.chatMonitorControl), monitor:)`, so `bin/tool --chat-monitor` reaches it;
   - build `HomeSpeakerTool` with `EngineDriver`, accounts on `engine.secrets`, `FileConfigStore(url: profile.settingsURL)`, #3341's `monitorStatusURL: profile.monitorStatusURL`, and `controlChatMonitor` calling that monitor's `start()` and `stop()` in this process (#3341 posts a notification to the app);
   - run the kit's loop.
4. On the five-second tick, already there, re-read the choice file and the other side's presence. On a role change:
   - `active`: install nothing new; start the monitor only once the other is not running, or 5 s have passed since the choice was written.
   - Not active: stop the monitor.
   - Then redraw and send the mark.
5. Send `ui/status` from `StatusInputs` after each change, only when `link.supports(.status)`.

**Interfaces:**
- `Parts` loses `isAppRunning` and `homeSpeakerVersion` as reasons to say "HomeSpeaker isn't running". #3341's `controlChatMonitor` refusal "HomeSpeaker isn't running: open it" becomes a refusal only while `.quiet` ("The HomeSpeaker app is in use, so its monitor is the one that runs"). It gains `role: () -> DoorRole`, `other: OtherAppControlling`, `door: DoorFile`, `copy`, and `sendStatus: (MarkChoice) -> Void`.
- `say`, `speakerJob` and `setupJob` refuse while `.quiet`: "The HomeSpeaker app is in use, so this one stays quiet". They work while `.waitingAsking`: a person's own request is not a duplicate.

- [ ] **Step 1: Failing tests:**
  - `noJobStartsTheAppsProgram`: a `ProcessDriver` stand-in that fails the test if called.
  - `theExtensionNeverReadsTheAppsSettings`: a settings file at the app's path with `enabled: false` changes nothing the extension shows.
  - `quietRefusesSpeech` and `waitingAllowsSpeechByHand`.
  - `theMonitorStartsOnlyWhenActive`.
  - `theMonitorWaitsForTheOtherToStop`: active, with the app still running, does not start; after it quits, it starts; after 5 s, it starts anyway.
  - `theMonitorStopsWhenTheAppIsChosen`.
  - `startAndStopRunInThisProcess`: #3341's Start and Stop buttons start and stop the extension's monitor. A recording poster sees nothing posted under the app's name.
  - `theStatusFileIsTheExtensions`: after a poll with stand-in sources, `<data>/speaker_monitor_status.json` holds it and the scratch home's `.gemini/speaker_monitor_status.json` does not exist.
  - `theMarkFollowsTheRole`.
  - `noStatusForAnAppWithoutTheFeature`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the extension still drives the app": `main.swift` builds `ProcessDriver`. Fails `noJobStartsTheAppsProgram`.
  2. "both monitors run for a moment": start at once on becoming active. Fails `theMonitorWaitsForTheOtherToStop`.
  3. "a quiet extension still speaks": drop the `.quiet` refusal. Fails `quietRefusesSpeech`.
  4. "Start asks the app": keep #3341's `ChatMonitorControlNotice.post` as `controlChatMonitor`. Fails `startAndStopRunInThisProcess`.
- [ ] **Step 6: Commit.**

### Task 13: The manifest, the release's zip, and the conformance test

**Worker:** `wren`. **Commit:** `feat(home-speaker): the extension ships its sign-in client and shows a mark on the closed island`.

**Files:**
- Modify: `tool/vitruvian-tool.json`:
  - `contributes.status: {"placement": "island"}`;
  - `sayClipboard` gains the `shortcut` surface;
  - the description loses "through HomeSpeaker";
  - `uses` unchanged: `open` already covers the sign-in's browser page.
- Modify: `scripts/zip-tool.sh`, which writes `homespeaker/google-oauth-client.json` from `HOMESPEAKER_GOOGLE_CLIENT_ID` and `HOMESPEAKER_GOOGLE_CLIENT_SECRET` when set, and nothing when not, as `bundle.sh:57-60` does. Also `scripts/zip-tool_test.sh` and `scripts/publish.sh` (pass the two variables through).
- Modify: `BUILD` (`tool-folder` stays without the client file: CI has no secrets), `tool/conformance_test.py`
- Modify: `Tests/HomeSpeakerToolTests/HomeSpeakerToolTests.swift`

**Interfaces:**
- `conformance_test.py` keeps #3341's end-to-end harness (`Driver`, `is_tree`, the five sections) and changes only where it looks:
  - it sets `HOMESPEAKER_DATA_FOLDER=<scratch>/data`, alongside `HOME`, `CFFIXED_USER_HOME` and `HOMESPEAKER_PROGRAM=""`. #3341's stand-in HomeSpeaker program goes: the extension never runs the app's program, and a test that still needed it would be testing the old tool;
  - the settings and secrets it reads back, and the paths the Files rows must name, are `<data>/settings.json` and `<data>/secrets.json`, not `<home>/.gemini/speaker_broadcast.json`;
  - the island's controls are drawn because the extension is installed by definition, not because a program was found.
  - It still requires `sayClipboard: refused`. The reason is now that the speaker is not set up, not that HomeSpeaker is missing.
  - It also checks that nothing was written outside the scratch folder: the scratch home's `.gemini` does not exist afterwards.
- A new Swift test, `theFolderIsTheScratchHomes`, starts the built program with the scratch variables and `--version`, and checks the profile it reports (a hidden `--where` flag prints the three paths) is under the scratch folder.

- [ ] **Step 1: Failing tests:**
  - the end-to-end run, with the paths above: it fails first, because the tool still writes `.gemini`;
  - the zip test, with the client variables set: the zip holds the file with both values;
  - the zip test, with them unset: no file;
  - the conformance test's new checks;
  - `theFolderIsTheScratchHomes`.
- [ ] **Step 2 to 4.** `bazel test` the four tool targets.
- [ ] **Step 5: Plant:**
  1. "the release ships no sign-in client": drop the write. Fails the zip test.
  2. "a test writes this Mac's settings": unset `HOMESPEAKER_DATA_FOLDER` in the conformance test. It must fail on the scratch check, not succeed on the real folder.
- [ ] **Step 6: Commit.**

### Task 14: The extension's pages: the choice, the copy, and parity

**Worker:** `wren`. **Commit:** `feat(home-speaker): the extension asks which HomeSpeaker to use, and offers to copy settings`.

**Files:**
- Create: `Sources/HomeSpeakerToolCore/DoorPages.swift`
- Modify: `Sources/HomeSpeakerToolCore/Pages.swift`. Only `island`, `settings`, `general`, `loginItem`, `speakerBlocks`, the quiet-hours rows and the files rows. Not the chat functions (design section 9).
- Modify: `HomeSpeakerTool.swift` (events for the new blocks)
- Create: `Tests/HomeSpeakerToolTests/DoorPagesTests.swift`; modify `PagesTests.swift`, `IslandTests.swift`

**What changes on the pages:**
- **Choice card**, at the top of the island and of General, while `.waitingAsking`:
  - step 1, pick;
  - step 2, the side-by-side summary from two `DoorSnapshot`s, with the suggested button first;
  - step 3, the app has quit, with the two offers as toggles and a **Done** button.

  The strings table above.
- **Quiet card**, in place of the island's body, while `.quiet`: one line and **Use this one instead**.
- **General's "Which HomeSpeaker" row**, while the app is installed: switch, and copy again.
- **Removed:** "HomeSpeaker is not installed on this Mac" (`Pages.swift:279`, `:480`), "Needs HomeSpeaker running to put it back" (`:542`), "HomeSpeaker isn't running, so nothing is reading chat" (`appNotReadingChat`, `:181`), and the login-item switch.
- **#3341's chat rows stay as they are**, fed by the extension's own monitor. `Pages.Chat.appRunning` is renamed `ownerRunning` (Task 2) and the Start and Stop buttons show whenever a source is on and this side is active.
- **Added:**
  - the line that the extension runs while Vitruvian runs;
  - the real restore report (`engine.volumeRestore.lastReport`);
  - **Quieter** and **Louder** (±10) beside the typed volume;
  - quiet hours as a `choice` of 48 half hours when `supports(.choice)`, else the typed field;
  - Files shows the extension's three paths.

- [ ] **Step 1: Failing tests:**
  - `theCardShowsWhileWaiting`, `theQuietCardReplacesTheIsland` and `noCardWhenAlone`.
  - `theSummaryNamesNoToken`.
  - `theSuggestedButtonIsFirst`.
  - `copyThenQuitThenOffer`: tapping through calls copy, then quit, then shows the offers, in that order, with recording stand-ins.
  - `trashNeedsItsOwnTick`.
  - `noPageSaysHomeSpeakerIsMissing`.
  - `louderAddsTenAndStopsAt100`.
  - `quietHoursPickerOnNewApps`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "the app is quit before the copy reads it": swap copy and quit. Fails `copyThenQuitThenOffer`. The copy must read the app's files while it is still the writer.
  2. "the Trash is ticked by default". Fails `trashNeedsItsOwnTick`.
  3. "louder goes past 100". Fails `louderAddsTenAndStopsAt100`.
- [ ] **Step 6: Commit.**

### Task 15: The app learns the choice

**Worker:** `wren`. **Commit:** `feat(home-speaker): the app asks which HomeSpeaker to use, and stays quiet when it is not the one`.

**Files:**
- Modify: `Sources/HomeSpeaker/App.swift`, `MenuBarView.swift`, `SettingsView.swift`
- Create: `Sources/HomeSpeaker/DoorWindow.swift`
- Modify: `Sources/HomeSpeakerCore/ConfigManager.swift`: the folder watcher also re-reads `speaker_door.json`, and publishes `role`
- Create: `Tests/HomeSpeakerTests/AppRoleTests.swift`

**What the app does:**
- **At launch,** before it starts anything, it computes its role from the choice file and `OtherDoorPresence.extensionInstalled`:
  - `active`: today's start-up, all of it.
  - `activeAsking`: today's start-up, plus the choice window.
  - `quiet`:
    - no chat monitor, no media or restore listener, and no hook repair;
    - its login item is left as the person set it: the extension's offer already switched it off, if they wanted that;
    - a small window: "The HomeSpeaker extension is in use, so this app stays quiet", with **Use the app instead** and **Quit**.
- **On a change** of the choice file while running: going quiet stops the monitor and the listeners within a second; becoming active starts them.
- **Choosing the extension from the app** runs the same three steps:
  1. copy into the extension's data folder, whose path comes from the choice file;
  2. write the choice;
  3. turn its own login item off (ticked by default), offer to move itself to the Trash, and quit.
- **Choosing the app** writes the choice, offers the copy from the extension, and shows how to remove the extension, with **Open Vitruvian**.
- **Settings > General** gets the "Which HomeSpeaker" row.

- [ ] **Step 1: Failing tests**, on the role logic and a stand-in start-up recorder, not on SwiftUI:
  - `aloneStartsAsToday`: the same list of things started as today.
  - `askingStartsAsTodayAndAsks`.
  - `quietStartsNothing`.
  - `goingQuietStopsTheMonitor`.
  - `quietNeverRepairsTheHook`.
  - `anOldExtensionIsNotAsked`.
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:**
  1. "a quiet app still reads Slack": start the monitor regardless. Fails `quietStartsNothing`.
  2. "the app silences itself before anyone chose": `activeAsking` starts nothing. Fails `askingStartsAsTodayAndAsks`.
- [ ] **Step 6: Commit.**

### Task 16: `sync-secrets`, the guides, and pull request 3

**Worker:** `wren`. **Commit:** `feat(home-speaker): sync-secrets can fill the extension's Slack token`.

**Files:**
- Modify: `scripts/sync-secrets.sh`, which takes `--extension` and writes the token into the extension's `secrets.json` (path from the choice file), under the same lock rules. Also `scripts/sync-secrets_test.sh`.
- Modify: `README.md` (the two ways to run HomeSpeaker), `AGENTS.md`:
  - the "shared contract" paragraph says `speaker_broadcast.json` is the app's;
  - the extension's files are in its data folder;
  - `speaker_door.json` is the one file both read.
- Modify: `docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md:531`. Add one sentence after "the tool is a second door": "Changed 2026-10-15: the tool runs on its own; see 2026-10-15-homespeaker-extension-independent-design.md."

- [ ] **Step 1: Failing test:** `sync_secrets_test` case "--extension writes the extension's file and not the app's".
- [ ] **Step 2 to 4.**
- [ ] **Step 5: Plant:** "--extension writes the app's file". Fails that case.
- [ ] **Step 6: Commit.**
- [ ] **Step 7: Run everything:**
  - `./scripts/test.sh`;
  - the Bazel targets;
  - `bazel build --config=macos-app //apps/desktop/home-speaker/... //apps/desktop/home-speaker:HomeSpeaker`;
  - `./scripts/publish.sh --dry-run`;
  - `//:tidy`.

  Record the counts.
- [ ] **Step 8: Open pull request 3:** `feat(home-speaker): the extension runs without the app, and asks which to use when both are installed`. Its body:
  - what an existing user sees (below);
  - the by-hand checks, still open;
  - the live-monitor session told it may land its `feat` after this merges.

  `release-scope` must name only `home-speaker`. Do not arm auto-merge: James approves.

### What an existing user sees after updating

- **App only:** nothing changes.
- **App and extension, extension updated first:**
  - Vitruvian shows the agreement sheet again, because the manifest now declares a status.
  - Then the island asks which HomeSpeaker to use. The app keeps working until they answer.
  - **Use the extension** shows both sides, offers the copy, quits the app, and offers to turn its login item off and to move it to the Trash.
  - **Use the app** makes the extension quiet.
- **App and extension, app updated first:** the app asks nothing until the extension has updated and run once, because a 1.17 or 1.18 extension is not a second HomeSpeaker.
- **Extension only, new:** set up in the island. It never looks at the app's files.

---

## After the release

### Task 17: The catalogue pins 1.19.0 (pull request 4)

**Worker:** `wren`. **Commit:** `chore(catalog): HomeSpeaker 1.19.0, which runs without the app`.

- [ ] Update `catalog/tools.json`'s HomeSpeaker entry:
  - version, `download.url`, `sha256` and `size`, from the released `HomeSpeaker-1.19.0-tool.zip`;
  - the summary without "through HomeSpeaker";
  - `minimumAppVersion` 3.48.0, for the status mark;
  - `sayClipboard`'s surfaces.

  Do the same in `apps/web/vitruviansoftware-dev/tools/catalog/tools.json` and `_data/tools.yml`, if they mirror it (check with `catalog_test.py`).
- [ ] Sign it as #3285 did. The signing key is a person's step: ask James.
- [ ] `bazel test //catalog/...`. Open the pull request, and check `release-scope`.

### Task 18: `macagent` follows the choice (pull request 5, only if question 1 is yes)

**Worker:** `wren`. **Commit:** `feat(android-remote): the Mac agent drives whichever HomeSpeaker is in use`.

- [ ] `apps/mobile/android-remote/macagent/homespeaker.go` reads `~/.gemini/speaker_door.json`. When `chosen` is `extension` and its program exists, it uses:
  - `extension.data_folder`'s `settings.json`, `history.json` and `secrets.json`;
  - `extension.program` for `--say` and the volume flags.

  Otherwise, today's paths. Tests in `homespeaker_test.go` for both, and for a stale choice.
- [ ] `macagent/API.md` says so. Its own pull request: android-remote releases.

---

## By hand

Only a person at the screen can confirm these. An agent can drive the app through Accessibility, but **James is asked first**, each time. Use pull request 3's build: `bazel build --config=macos-app //apps/desktop/home-speaker:tool-folder`. Put `google-oauth-client.json` into the built folder by hand from `.env` before adding it. Add it in Vitruvian with "Update from Folder…". Record each check in the pull request with the Mac and macOS version, or say it was not done.

1. **H1. Alone.** Move HomeSpeaker.app to the Trash. In the extension:
   - sign in to Google Home;
   - find speakers;
   - pick one;
   - Speak;
   - read and set the volume, and Quieter and Louder;
   - mute and unmute;
   - quiet hours.

   Each works. Nothing appears in `~/.gemini/speaker_history.json`.
2. **H2. The hook.** Install the Claude Code hook from the extension. `~/.claude/settings.json` shows the extension's `bin/tool`. Finish a Claude Code reply: it is spoken once. With Vitruvian quit, it is still spoken, because the hook runs without Vitruvian.
3. **H3. This Mac's voice.** Speak on this Mac only, with a premium voice.
4. **H4. Local Network.** No Local Network prompt appears at any point, sign-in included. System Settings > Privacy > Local Network does not list Vitruvian for this.
5. **H5. Media pause.** Play music in Music and a YouTube tab in Chrome. Test media pause: macOS asks "Vitruvian" for each, once. It pauses and resumes.
6. **H6. Announce at a set volume.** The volume goes up for the announcement, comes back, and Settings shows the report.
7. **H7. The closed island.** The mark shows broadcasting, then quiet hours, then off, and a sign-in error (revoke the token at myaccount.google.com).
8. **H8. Both installed, extension first.** Restore the app (1.19). Open the island: the card. The app keeps speaking Claude replies while undecided. Choose the extension, copy, Done:
   - the app quits;
   - its login item is off in System Settings;
   - the hook points at the extension;
   - one reply is spoken once.
9. **H9. Both installed, app first.** Reset the choice (delete `speaker_door.json`). Launch the app: the window. Choose the app. The extension goes quiet within 5 s. Its mark disappears. **Open Vitruvian** opens it.
10. **H10. Undo.** From the extension's General, **Use the extension instead**, and back. The settings changed in between come across when copied.
11. **H11. An old app.** With HomeSpeaker 1.17.0, choose the extension:
    - the old-app warning shows;
    - its login item is turned off;
    - reopening the old app takes the hook back.

    This proves the warning is true.
12. **H12. No double speech.** With Slack monitoring on in both before choosing (the live-monitor work's build), send one Slack message: it is spoken once.
13. **H13. The quiet side's sign-out.** In the quiet app, Sign Out. The extension still speaks.
14. **H14. Remove.** Remove the extension in Vitruvian with "delete data". The app, chosen again, repairs the hook that now points at nothing.

## Not verified

Distrust these first.

- **Nothing in this plan was compiled.** Type names, initializer shapes and file splits for code to be written are a design. Line numbers for code that exists were read at `6a72b0af7`.
- **That loopback needs no Local Network permission under Vitruvian** (H4), and **that the Automation prompt names Vitruvian** (H5).
- **That a 3.45 to 3.47 Vitruvian accepts the manifest with `contributes.status`.** If it refuses, the catalogue's `minimumAppVersion` of 3.48.0 already covers it. A folder added by hand to an older app would be refused, with the reason.
- **That `NSRunningApplication.terminate()` quits HomeSpeaker** without an Automation prompt. Believed true for an app of the same user. H8.
- **That `NSWorkspace.recycle` can move `/Applications/HomeSpeaker.app`** without a password for an admin user, and what it asks otherwise. H8.
- **#3341 as it will merge.** This plan was written against its diff on 2026-10-15, before it merged. If it changes, design section 9's table is where to look first.
- **release-please's version numbers** assume #3341 releases home-speaker 1.18.0 and nothing else in `apps/desktop/home-speaker` releases before this plan's PR 3, which would then be 1.19.0. The version gates ("an extension older than 1.19 is not a second HomeSpeaker") must use PR 3's real version: check `.release-please-manifest.json` when Task 7 is written.
