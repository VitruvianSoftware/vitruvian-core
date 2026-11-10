# Home Speaker one rulebook: plan

**Spec:** `docs/superpowers/specs/2026-11-10-homespeaker-one-rulebook-design.md`. Read it first.
**Base:** `origin/main` at `677e0fa67`.

Four pull requests, one product each (the `release-scope` check needs it), landed in this order. Each is
built by `wren`, reviewed by `scout` (QA), accepted by `compass` (UAT) where a person can see the change,
with `quill` on the docs, and reviewed last by the lead.

| PR | Product | What | Tasks |
|---|---|---|---|
| A | home-speaker | Shared cases + the rulebook (`SettingsCatalog`, `SettingsActions`); app and extension use it | 1, 2 |
| B | home-speaker | `--state --json` / `--apply --json` on both programs | 3 |
| C | android-remote | Mac helper relays to the chosen program | 4 |
| D | android-remote | Phone shows the engine's wording; install/update sentence | 5 |
| docs | (with A–D) | Guide's parity checklist, helper API, stale spec reference | 6 |

## Rules for every task

- Work in the worktree the lead names; git writes only through `bazel run //tools/git:commit -- --agent wren …`
  and `bazel run //tools/git:push -- --agent wren`. Never `git commit`/`git push` directly.
- **Never run a built Home Speaker program** (the app binary or the extension's `bin/tool`) outside a test.
  An unknown argument starts the menu bar app, which re-points James's real Claude Code hook. If a test
  must run a program, it sets `HOME` and `CFFIXED_USER_HOME` to a scratch folder AND neutralises
  process-level actions (quit, open, login items): a scratch home does not hide running apps.
- Never touch James's real `~/.gemini/`, `~/.claude/`, `~/Library/Application Support/HomeSpeaker/` or the
  extension's `ToolData` folder. Never start the real Mac helper (`vitruvian-remote-agent`).
- Headless Swift entries keep the main thread running its loop; never `dispatchMain()`.
- Every fix ships with the check that would catch it again, shown failing first.
- Home Speaker verification (all must pass):
  `bazel test --config=macos-app //apps/desktop/home-speaker:HomeSpeakerTests //apps/desktop/home-speaker:HomeSpeakerToolTests //apps/desktop/home-speaker:HomeSpeakerViewTests //apps/desktop/home-speaker:tool_conformance_test //apps/desktop/home-speaker:tool_version_test`
  and `bazel build --config=macos-app //apps/desktop/home-speaker/...`.
- Remote verification: `bazel test //apps/mobile/android-remote/macagent:macagent_test //apps/mobile/android-remote:derive_test //apps/mobile/android-remote:wire_test`.

## Task 1 — Shared cases and `SettingsCatalog` (PR A)

Add `apps/desktop/home-speaker/testdata/` with JSON cases and a short README naming who reads them. Cases
cover, at minimum: every choice list and its labels (speech length, announcement style, style model, voice
engine, Gemini voices, chat announce mode, Google Chat source), numeric limits and steps (volume, announce
volume, pause margin, poll interval), visibility rules, quiet hours (parsing, overnight window, half-hour
choices including an off-grid saved time), speaker order and display line, removing the default speaker,
the "speaks on" summary (including the phone's "This phone" substitution), and the chat monitor status
believed only while its owner runs. Write the cases from the ENGINE's current behaviour, except the one
deliberate wording change: "Apple (On-device)" becomes "Apple (on this Mac)".

Add `SettingsCatalog` to `HomeSpeakerCore`, built from the existing enums and `SpeakerConfig` rules, plus
what is missing (a `GoogleChatSource` label; the half-hour time choices with the off-grid rule). A Swift
test reads every case and checks the catalog against it.

Done when: the cases exist, the Swift test reads them all (a deliberately wrong case makes it fail), and
the verification passes.

## Task 2 — `SettingsActions`; the app and the extension stop carrying rules (PR A)

Add `SettingsActions` to `HomeSpeakerCore`: set a value (checked, clamped), remove a speaker, save the
sign-in client (keep the secret when the ID is unchanged and the secret field is empty; one rule for
everyone), clear a chat token (switching Courier off when its token goes), switch to the app or the
extension (choice file, hook re-pointing, quitting the other one: today in `AppSwitch.swift` and again in
`HomeSpeakerTool.swift` ~1393-1503), reset. All writes under the existing locks.

Change `Sources/HomeSpeaker/SettingsView.swift`, `MenuBarView.swift`, `ChatAppSection.swift` and
`Sources/HomeSpeakerToolCore/HomeSpeakerTool.swift`, `Pages.swift`, `DoorPages.swift`, `Account.swift`,
`Config.swift`, `OtherApp.swift` to call the catalog and the actions, deleting their own copies. Layout
does not change. Look: the existing view snapshot tests (`HomeSpeakerViewTests`) must show only the one
label change; render and look at the changed images.

Done when: no choice list, label, limit, visibility rule or switch step is written in the app or the
extension (list any left, with the reason); the verification passes; the snapshot difference is only the
label.

## Task 3 — `--state --json` and `--apply --json` (PR B)

On both programs, through `CommandLine.swift` and the extension's `main.swift` (same engine). Shapes as in
spec section 3; contract version 1. `--apply` uses `SettingsActions` only. On the program that is not the
chosen one, `--apply` refuses with JSON naming the chosen program; `--state` always answers. Failures are
JSON with a non-zero exit, as `--volume`. Unknown keys in the settings file survive. Check that the running
extension notices an external settings change (the app already watches); add the watch if missing.

Tests through the command functions, not by running the program: every operation, the refusal, unknown-key
preservation, a concurrent write from a second "process" (two writers under the lock), and a golden
`--state` document checked into `testdata/` that Task 4 reuses.

## Task 4 — The Mac helper relays (PR C)

In `apps/mobile/android-remote/macagent/rs/src/homespeaker.rs`: keep pairing, the phone bridge and
`phone-say`, the HTTP API paths, clipboard speech, and the choice-file read that picks the program
(`:2067-2090`). Replace every read and write of Home Speaker's settings, secrets, history and status
files, the door writing (`:3090`) and the hook re-pointing (`:1695-1751`) with calls to the chosen program's
`--state` / `--apply` (bounded time, as `--volume` today). Run `--version` once; below the minimum answer
`{available:false, reason:"Update Home Speaker on <Mac> (have X, need Y)"}`. Not installed keeps today's
"not installed" answer. Keep the endpoint field names the phone reads; map from the program's document.

Tests: against the golden `--state` from Task 3 and a fake runner (no real program); every endpoint;
too-old and missing. Report how many lines of Rust left.

## Task 5 — The phone shows the engine's wording (PR D)

In `apps/mobile/android-remote/src/main/kotlin/dev/vitruvian/remote/state/` (`Wire.kt`, `AgentClient.kt`,
`Derive.kt`, `RemoteState.kt`): take labels, choices, limits and visibility from the payload; delete the
local copies (the label functions, choice lists, clamps). Keep one substitution: "Your phone" is shown as
"This phone". Missing or too old: one sentence, no settings screen. Tests: `DeriveTest`, `WireTest`
against the golden document; a test that fails if a label constant comes back.

## Task 6 — Docs (with each PR)

`apps/desktop/home-speaker/AGENTS.md`: the parity checklist's helper and phone rows become "the shared
cases pass"; name `testdata/`; fix the stale `./scripts/test.sh` instructions (the script is gone; give the
Bazel targets). `apps/mobile/android-remote/macagent/API.md`: the HomeSpeaker section says the answers come
from Home Speaker's `--state`, and the update sentence. `docs/superpowers/specs/2026-10-15-homespeaker-extension-independent-design.md`:
note that `macagent/homespeaker.go` is now `rs/src/homespeaker.rs`.

## UAT (compass), per PR

A: the app's Settings and menu, and the extension's pages (rendered snapshots), show the same wording as
before except the one label. B: `--state` describes James-like settings correctly (from a scratch copy).
C and D: against a scratch Home Speaker data folder and the golden document, every acceptance criterion in
spec section 6 that can be checked without James's phone; list the ones only James can check on the Fold.
