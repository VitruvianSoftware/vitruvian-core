# Shared test cases for the bot and the apps (step 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three rules that exist in both JavaScript (the Telegram bot) and Swift (the two Mac apps) are checked against one set of examples, so changing a rule on one side fails the other side's tests.

**Architecture:** The examples are JSON files in `apps/desktop/nexus-agent/testdata/`. A JavaScript test runs them through the bot's own code (and through the `dotenv` package the bot uses); an XCTest runs the same files through the shared Swift library. Where the two sides disagree today, **the bot is the authority**: it is what actually runs, so the apps change to show and write what the bot will do. That direction can never loosen what the bot is allowed to do.

**Tech Stack:** Node `node:test` (ESM) under Bazel `js_test`; `dotenv` 17; Swift 6 mode in `NexusAgentCore` (must compile on Swift 6.1.2); XCTest; Bazel runfiles for the data files.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`, section 9 step 4: "Start with the archive rule, then approval-mode parsing and `.env` reading."

## What changes for users

> **Correction (2026-10-09, found while building):** this plan first said the bot does not recognise an approval mode in capitals. That is false. Running the bot showed it lower-cases the value, so `YOLO` and `PLAN` work exactly like `yolo` and `plan`. Only padding with spaces (which reaches the bot only from inside quotes) makes it an unknown mode. The rows and sentences below that repeated the claim are corrected.

The bot does not change. The apps change only where they disagreed with the bot:

| In `.env` | The bot does (unchanged) | The apps showed | The apps now |
|---|---|---|---|
| An approval mode padded with spaces inside quotes (`" plan "`) | Does not recognise it: no permission flag, so tools that need approval are refused | The mode as if it were spelled properly (Plan) | "Default", which is what the bot does. Vitruvian's own chat turns follow the same reading |
| An unquoted value with a `#` in it (`KEY=a#b`) | Reads `a` | `a#b` | `a` |
| Other lines the two read differently (see Task 3) | dotenv's reading | Their own | dotenv's reading, for every case in the shared file |

A value the apps write is unaffected: they already quote any value containing `#`.

## Global Constraints

- **The bot's behaviour does not change.** JavaScript edits are limited to new test files, and to an `export` keyword or a pure extraction with identical behaviour if a rule cannot otherwise be reached by a test. `src/bot.js` is not edited.
- The shared JSON files are the single source of examples. Neither test may hard-code an expected value that is in a JSON file, and neither may skip a case. A case that one side cannot satisfy is a finding to report, not a line to delete.
- Each test must fail if its data file is missing, unreadable or empty.
- Nothing in `NexusAgentCore` imports a `Vitruvian*` module or SwiftUI, reads `UserDefaults`, or names an app's settings key. No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency` added. No syntax newer than Swift 6.0.
- After any change under `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore`: `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and one line in the dated log of `apps/desktop/vitruvian/UPSTREAM.md`.
- Vitruvian's and the standalone's existing tests may change ONLY where they assert one of the readings this plan deliberately changes; each such edit is listed in the report with the old and new expectation.
- Every Swift Bazel command needs `--config=macos-app`; name the `manual` targets. JavaScript tests run on Linux in CI: no macOS-only paths or tools in them.
- `.github/workflows/presubmit.yaml` is generated: `bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml`.
- Before the last commit: `bazel run //:tidy`, then discard its change to `gazelle_python.yaml` if any.
- Do not start the real bot, and do not read or write the real `~/.config/nexus-agent/.env`.
- Every commit ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A test that cannot fail.** A loop over zero cases passes. Each test asserts it ran at least the number of cases in the file, and Task 1 proves each test fails when one expected value in the JSON is changed.
2. **The examples drift from the bot.** The expected values must come from running the bot's code, never from reading it and guessing. Task 2 and Task 3 say how each table is produced.
3. **The apps now show "Default" for a mode they used to show as YOLO.** That is the intended change; the risk is a save then writing `default` over a value the user typed. Pinned by Task 2 Step 4.
4. **Reading and writing disagree.** After Task 3 the apps read `.env` as dotenv does; what they WRITE must still be read back by dotenv as the same value. Pinned by the round-trip file in Task 3.
5. **The data files do not reach the test under Bazel.** A test that silently finds no file is the failure this step exists to prevent. Pinned by the missing-file assertion in every test.

## File Structure

| File | Responsibility |
|---|---|
| `apps/desktop/nexus-agent/testdata/README.md` | what the files are, who reads them, that the bot is the authority |
| `apps/desktop/nexus-agent/testdata/archive-annotations.json` | annotation text → archived or not |
| `apps/desktop/nexus-agent/testdata/approval-modes.json` | `AGY_APPROVAL_MODE` value → the agy flags |
| `apps/desktop/nexus-agent/testdata/env-lines.json` | one `.env` line → key and value, or nothing |
| `apps/desktop/nexus-agent/testdata/env-written-values.json` | a value → the line the apps write for it |
| `apps/desktop/nexus-agent/src/shared-cases.test.js` | runs all four through the bot's code and dotenv |
| `apps/desktop/nexus-agent/macos/Tests/SharedCasesTests.swift` | runs all four through `NexusAgentCore` |
| `apps/desktop/nexus-agent/BUILD`, `src/BUILD`, `macos/BUILD` | the data reaches both tests; the JS test is in the CI unit |

---

### Task 1: The wiring, proved on the rule both sides already agree on

**Files:**
- Create: `apps/desktop/nexus-agent/testdata/README.md`, `testdata/archive-annotations.json`
- Create: `apps/desktop/nexus-agent/src/shared-cases.test.js`
- Create: `apps/desktop/nexus-agent/macos/Tests/SharedCasesTests.swift`
- Modify: `apps/desktop/nexus-agent/BUILD`, `apps/desktop/nexus-agent/src/BUILD`, `apps/desktop/nexus-agent/macos/BUILD`, `.github/workflows/presubmit.yaml` (generated)

**Interfaces:**
- Produces: a JSON shape every file follows — `{ "rule": "<one sentence>", "cases": [ { "name": "<plain words>", ... } ] }` — and one helper per language that loads a file by name and fails the test if it is missing or has no cases.

- [ ] **Step 1: Write the data file**

`archive-annotations.json`, cases with fields `name`, `text`, `archived`. Take the texts from the two existing hand-copied twins (`src/annotations.test.js` and `macos/Tests/ArchiveRuleTests.swift`): the two archived shapes agy writes, no field, `archived:false`, empty text, a quoted title containing `archived:true`, and `archived: true` followed later by `archived:false` (the last value wins). At least seven cases.

- [ ] **Step 2: Write both tests, failing first**

`src/shared-cases.test.js` (`node:test`, `node:assert/strict`, ESM like the other tests): a `loadCases(file)` that resolves `../testdata/<file>` from `import.meta.url`, parses it, and asserts `cases.length > 0`; one `test` that runs every archive case through `annotationIsArchived` from `./annotations.js` and asserts the result equals `archived`, naming the case in the failure message.

`macos/Tests/SharedCasesTests.swift` (MIT header like the other test files): a `loadCases(_ file:)` that finds `apps/desktop/nexus-agent/testdata/<file>` the way `EngineHostTests.swift` finds the shared sources (runfiles `TEST_SRCDIR` with `TEST_WORKSPACE` then `_main`, falling back to a path relative to `#filePath`), decodes it with `JSONSerialization`, and fails with `XCTFail` naming the path if the file is missing or has no cases; one test that runs every archive case through `NexusAgentSessionSummary.antigravityAnnotationIsArchived`.

Wire the data:
- `apps/desktop/nexus-agent/BUILD`: a `js_library` (rules_js, as `src/BUILD` loads it) named `testdata` over `glob(["testdata/*.json"])`, and a `filegroup` named `testdata_files` over the same glob.
- `src/BUILD`: a `js_test` named `shared_cases_test` in the style of `annotations_test`, with `data` holding `:annotations`, `//apps/desktop/nexus-agent:testdata`, and (from Task 3) the dotenv package; add it to the `nexus-agent-src` pipeline unit's `test_targets`.
- `macos/BUILD`: add `//apps/desktop/nexus-agent:testdata_files` to the `data` of `NexusAgentTests`.

Run both before the data file exists at the path the test expects (or with the `data` line removed) and record that each FAILS with a missing-file message, not a pass over zero cases.

- [ ] **Step 3: Make them pass**

```
bazel test //apps/desktop/nexus-agent/src:shared_cases_test --test_output=errors
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests --test_output=errors
```

- [ ] **Step 4: Prove the tests bite**

Change one `archived` value in the JSON; both tests must FAIL naming that case. Revert.

- [ ] **Step 5: Remove the hand-copied twins**

Delete from `src/annotations.test.js` and from `macos/Tests/ArchiveRuleTests.swift` the cases now in the JSON file (the pure text → bool checks). Keep the tests that touch the file system (archived ids across data folders). Regenerate CI, write `testdata/README.md` (what the files are; both tests read them; the bot is the authority; add a case here, not in one language's test), run both test commands again, and commit:

```bash
git add apps/desktop/nexus-agent .github/workflows/presubmit.yaml
git commit -m "test(nexus-agent): one set of archive-rule examples, read by the bot's tests and the apps' tests"
```

---

### Task 2: Approval modes, with the bot as the authority

**Files:**
- Create: `apps/desktop/nexus-agent/testdata/approval-modes.json`
- Modify: `src/shared-cases.test.js`, `macos/Tests/SharedCasesTests.swift`
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentSupport.swift` (`NexusAgentApprovalMode.parse`)
- Modify, only where they assert the old reading: `macos/Tests/PortedRulesTests.swift`, `apps/desktop/vitruvian/Tests/NexusAgentTests.swift`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`, the pin

**Interfaces:**
- Consumes: `approvalArgs(mode)` exported from `src/agy.js`; `NexusAgentApprovalMode.parse(_:)` and `.agyArguments`.
- Produces: `approval-modes.json` cases `{ "name", "value", "args" }`, where `value` is the string after the `=` as the bot receives it (JSON `null` for "the key is absent") and `args` is the list of agy flags.

- [ ] **Step 1: Produce the table from the bot**

Importing `agy.js` reads the environment and the session store at load. Follow the pattern in `src/sessions.test.js` (set the environment variables it needs to a temporary folder, then `await import`). Run `approvalArgs` on each of these and record what it RETURNS — do not write expectations by reading the code: absent (use the module's own default handling; if the function takes only a string, record how the bot turns an absent key into its default and represent that as the `null` case), `""`, `yolo`, `YOLO`, `Yolo`, ` yolo ` (with spaces), `plan`, `PLAN`, ` plan `, `accept-edits`, `accept_edits`, `auto_edit`, `AUTO_EDIT`, `default`, `bogus`, `acceptEdits`. Write them to the JSON file with plain-word names ("capitals are recognised", "spaces around yolo are not removed").

- [ ] **Step 2: Add the test on both sides; the Swift side fails**

JavaScript: every case through `approvalArgs`, deep-equal to `args`. Swift: every case through `NexusAgentApprovalMode.parse(value).agyArguments`, equal to `args`.

Run both. Expected: JavaScript PASSES (the table came from it). Swift FAILS on the padded cases. Record the failing case names.

- [ ] **Step 3: Make the apps read it as the bot does**

Change `NexusAgentApprovalMode.parse` so every case passes: it recognises exactly the spellings the bot recognises, with no trimming and no case folding beyond what the bot does. Keep the function's signature and the enum's cases. Update its doc comment to say the bot is the authority and point at the shared file.

- [ ] **Step 4: A save must not rewrite what the user typed into something the bot reads differently**

In `SharedCasesTests.swift` add: for every case whose `value` is not null, parse it, render a configuration with that mode over an `.env` containing `AGY_APPROVAL_MODE=<value>` (use `NexusAgentEnvFile.render`), read the saved value back, and assert the bot's flags for the SAVED value (look them up in the same table by value; if the saved value is not in the table, fail) equal the flags for the ORIGINAL value. In words: saving never changes what the bot will do.

- [ ] **Step 5: Update the tests that asserted the old reading**

`PortedRulesTests.testModes` asserts that ` PLAN ` parses as plan "as the bot reads them", which the bot does not. Change only the expectations this plan deliberately changes, in that file and in Vitruvian's `NexusAgentTests.swift` if it asserts the same; list each old and new expectation in the report.

- [ ] **Step 6: Run everything, re-pin, log, commit**

```
bazel test //apps/desktop/nexus-agent/src:shared_cases_test --test_output=errors
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test //apps/desktop/vitruvian:unit_tests --test_output=errors
bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared
bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:source_lints_test --test_output=errors
```

Log line for `UPSTREAM.md`: `- **2026-10-09**: An approval mode in `.env` is now read exactly as the bot reads it: a value padded with spaces (which only reaches the bot from inside quotes) is not a mode the bot knows, so it shows as Default here too and this app's own chat turns pass no permission flag for it. Capitals are still recognised, because the bot recognises them. The examples are shared with the bot's tests (`apps/desktop/nexus-agent/testdata/approval-modes.json`).`

```bash
git add apps/desktop/nexus-agent apps/desktop/vitruvian
git commit -m "fix(nexus-agent): the apps read an approval mode exactly as the bot does"
```

---

### Task 3: `.env` lines, read as dotenv reads them and written so dotenv reads them back

**Files:**
- Create: `apps/desktop/nexus-agent/testdata/env-lines.json`, `testdata/env-written-values.json`
- Modify: `src/shared-cases.test.js`, `src/BUILD` (dotenv in `data`), `macos/Tests/SharedCasesTests.swift`
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentSupport.swift` (`NexusAgentEnvFile.assignment(in:)`, and `encoded` only if the round trip requires it)
- Modify, only where they assert the old reading: `macos/Tests/SharedRulesTests.swift`, `PortedRulesTests.swift`, `BotProviderEnvTests.swift`, `apps/desktop/vitruvian/Tests/NexusAgentTests.swift`
- Modify: `apps/desktop/vitruvian/UPSTREAM.md`, the pin

**Interfaces:**
- Consumes: `dotenv.parse` (the package version the bot uses), `NexusAgentEnvFile.assignment(in:)`, `NexusAgentEnvFile.encoded(_:)`.
- Produces:
  - `env-lines.json` cases `{ "name", "line", "key", "value" }`, with `key` and `value` JSON `null` when the line assigns nothing.
  - `env-written-values.json` cases `{ "name", "value", "line" }`, where `line` is exactly what the apps write after the `=`.

- [ ] **Step 1: Produce the reading table from dotenv**

For each line, run `dotenv.parse(line)` and record the single key and value it returns, or null when it returns nothing. Lines to include, at least: `K=v`; `K=`; `K=""`; `K=''`; ` K = v ` (spaces around); `K=a b`; `K=a # c`; `K=a#b`; `K=#x`; `K="a # b"`; `K='a # b'`; `K="a" # c`; `K='a'#c`; `export K=v`; `export<TAB>K=v` (a real tab); `K: v`; `# K=v`; a blank line; `no equals sign`; `K="unterminated`; `K="a\nb"` (backslash n inside double quotes); `K='a\nb'`; `K="a\"b"`; `K="a" b`; `K=a=b`; `K.L=v`; `K-L=v`; `1K=v`; a key with a non-ASCII letter; `K=v` with a trailing carriage return. Give each a plain-word name.

- [ ] **Step 2: Add the reading test on both sides; the Swift side fails**

JavaScript: `dotenv.parse(line)` gives exactly `{[key]: value}` or `{}`. Swift: `NexusAgentEnvFile.assignment(in: line)` gives the same key and value, or nil. JavaScript passes; record which cases Swift fails.

- [ ] **Step 3: Make the apps read lines as dotenv does**

Change `assignment(in:)` until every case passes. If a case would need behaviour that a one-line reader cannot have (a value that continues on the next line), leave that case OUT of the file and say so in the README and the report; do not add a case and then exempt one side.

- [ ] **Step 4: The writing table, and the round trip**

For each of these values, record in `env-written-values.json` what `NexusAgentEnvFile.encoded` produces today (run it): a plain word; an empty string; a value with inner spaces; with leading and trailing spaces; with a `#` with a space before it; with a `#` and no space; starting with `#`; starting with a double quote; containing a single quote; containing a double quote; containing both quote kinds and a `#`; a Telegram-style token `123456:ABC-def_ghi`; a path with spaces; a command template `claude -p {prompt} --model {model}`; a value with `=`; a value with a backslash.

Tests:
- Swift: `encoded(value) == line` for every case.
- JavaScript: `dotenv.parse("K=" + line).K === value` for every case — what the apps write, the bot reads back as the same value.
- Swift as well: `assignment(in: "K=" + line)?.value == value`.

A case the round trip cannot satisfy is a real defect in how the apps write `.env`. Fix `encoded` if a correct encoding exists that dotenv reads back (dotenv supports single quotes, double quotes and backticks, and expands `\n` only inside double quotes). If no encoding can carry the value, keep the case in the file with a third field `"lossy": true`, have BOTH tests assert that the bot reads something different from `value` for it (so the limit stays visible and a future fix flips the test), and report it. The existing `BotProviderEnvTests.testATemplateWithAHashAndBothQuoteKindsIsAKnownLimit` pins one such value today: bring it in line with whatever this step establishes.

- [ ] **Step 5: Update the tests that asserted the old reading**, as in Task 2 Step 5: only expectations this plan deliberately changes, each listed.

- [ ] **Step 6: Tidy, run everything, re-pin, log, regenerate CI if `src/BUILD` targets changed, commit**

```
bazel run //:tidy
git checkout -- gazelle_python.yaml
bazel test //apps/desktop/nexus-agent/src:all --test_output=errors
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test //apps/desktop/vitruvian:unit_tests --test_output=errors
bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent
bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared
bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test --test_output=errors
```

Log line for `UPSTREAM.md`: `- **2026-10-09**: A line of `.env` is now read exactly as the bot's dotenv reads it (for one: an unquoted value ends at a `#`, with or without a space before it). The examples, and the check that what this app writes is read back unchanged, are shared with the bot's tests (`apps/desktop/nexus-agent/testdata/env-lines.json`, `env-written-values.json`).`

```bash
git add apps/desktop/nexus-agent apps/desktop/vitruvian .github/workflows/presubmit.yaml
git commit -m "fix(nexus-agent): the apps read and write .env lines the way the bot's dotenv does"
```

---

## Before opening the pull request

- [ ] The description carries the "What changes for users" table, every existing expectation that was changed (old → new), every case left out or marked lossy and why, and the list of bot-versus-app disagreements this step did NOT cover (effort and thinking, model list line endings, session titles, binary discovery, the command line for a turn), so they are not lost.
- [ ] `Nexus Agent Mirror Toolchain` is green (Swift 6.1.2).
- [ ] Title is `fix(nexus-agent): …`.
