# Vitruvian external tools (stage A: the protocol package and the manifest read from a file) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write the tool protocol down once, in a new MIT package the app links, and teach the app to read a tool's manifest file. After this stage a tool author has schemas, Swift types and a script to check a tool against. The app can turn a folder into a `ToolManifest` or a reason it will not. Nothing in the app calls that reader yet, and a person sees no change.

**Architecture:** `packages/vitruvian-sdk` holds three things. `protocol/` is the source of truth: two JSON Schemas, a table of the messages, and example files. `Sources/VitruvianToolProtocol` is the same protocol as Swift: the JSON-RPC envelope, one message per line, every message's fields, the refusal codes, and the manifest file with the rules that need nothing but the file. `conformance/` is a Python script that plays the app's side to any tool, and one small reference tool it is proven against. Two tests read the same example files, one against the schemas and one against the Swift types, so the two cannot drift. In the app, `Core` links the Swift module and gains one file, `ExternalToolManifest.swift`, which reads a folder, applies the package's rules, checks the program on disk, and maps what it read onto the platform's closed lists.

**Tech Stack:** Swift 6 (Foundation only in the package), XCTest for the package, the app's own `TestSuite` harness, Python 3 with `jsonschema` from the repository's pip hub, Bazel with `--config=macos-app`, `tools/pipeline`.

**Spec:** `docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md` (approved 2026-10-10). This is stage A of its section 15. Its parents are `2026-10-08-vitruvian-tool-platform-design.md` and `2026-10-09-vitruvian-broker-and-bundled-tools-design.md`.

Paths that start with `Sources/`, `Tests/`, `bazel/` or name `BUILD`, `AGENTS.md` or `UPSTREAM.md` alone are relative to the folder the task says it works in. Every other path is from the repository root.

## Decisions this plan makes

The spec's twelve decisions stand. These are the ones the code and the repository forced while planning. Each says whether it changes the spec, adds to it, or only follows it. Task 7 edits the spec to match.

| # | Decision | Why |
|---|---|---|
| 1 | **The manifest's own rules live in the package, not in `Core`.** `ToolManifestFile.read(_:)` in `VitruvianToolProtocol` applies every rule of spec section 6 that needs only the file. `Core`'s reader calls it, then does the two things only the app can: check the program in the real folder, and map names onto the app's closed lists. **Changes the spec**, whose section 10 puts the rules in `Core`. | Stage D's `vitruvian-tool validate` must "check a folder the way the app will". It is MIT and cannot link the GPL app. Rules written twice drift, which is what decision 12 of the spec exists to prevent. The app's tests still go through `Core` and pin every rule. |
| 2 | **`uses` becomes `CapabilityRequest(usedByOutsideTool:)`**, a second initializer with an empty reason. The existing one, which returns nil without a reason, is untouched. **Adds to the spec.** | `CapabilityRequest` refuses a blank reason, and spec section 6 says an outside tool gives none. A made-up reason would be a sentence nobody wrote. |
| 3 | **An outside tool is never held back for a macOS grant.** Its request for a service that rides on one (`keystrokes`, on Accessibility) says `startsWithoutGrant`, so `grantsNeededToStart` is empty. Each call is still refused until the grant is there. **Adds to the spec.** | Spec section 9 lists "a macOS permission Vitruvian does not have" as a refusal of one request. A tool the host would not start could never be sent it. |
| 4 | **`uses` may name seven services**: `notify`, `open`, `clipboard.read`, `clipboard.write`, `keystrokes`, `processes`, `storage`. `hotkey` and `clipboard.rewrite` are the app's and are refused as unknown. Follows the spec (its section 9 table, and its decision 8). | The app's `Capability` has nine cases. Two have no message in protocol 1. |
| 5 | **Text in several languages is a map from a language tag to text, `en` required.** Any other tag is kept, known to the app or not. The text for a language is its own entry, else the entry for the language without its region (`pt` for `pt-BR`), else English. `ToolDescriptor.name` and `CommandDescriptor.title` hold the English. `ExternalToolManifest` keeps every language beside them (`name`, `summary`, `commandTitles`). **Adds to the spec.** | Both descriptors hold one plain string and stay that way, so no call site changes. The registry already takes a name and a title per language (`ToolRegistry.setName`, `Handler.title`); stage C hands it `text(for: language.rawValue)`. The app's fifteen `AppLanguage` raw values are the tags looked up. A tag the app lacks costs nothing to carry. |
| 6 | **Every outside tool is filed under `FeatureGroup.tools`.** **Adds to the spec.** | `ToolManifest.group` is required and the enum is closed. The manifest file has no group, and stage C gives outside tools a hub section of their own, so the value places nothing yet. |
| 7 | **The reader is `ExternalToolManifest.read(folder:)` and `read(_ data:)`, in `Core/Platform/ExternalToolManifest.swift`. Both return `Result<ExternalToolManifest, ManifestRefusal>`.** A refusal is an enum whose cases carry values (`.invalid(.unknownService("camera"))`), never a sentence. Stage A adds no string a person reads. | The stage C sheet has to say which part is wrong, in fifteen languages. Only it can write those sentences. |
| 8 | **`exec` is checked twice.** By its text, in the package: parts joined by `/`, none empty, `.` or `..`. Against the real folder, in `Core`: links are followed, and the program must be a file, inside the folder, that macOS will run. **Adds to the spec** two refusals it does not list: the program is missing, and the program is not executable. | A path with no `..` can still be a link out of the folder. The app runs a copy of the folder (spec decision 9), and a link out of it points at something the copy does not hold. The other two are cheaper to say at the sheet than at the first start. |
| 9 | **`publisher` is required. `description`, `license`, `icon`, `uses`, `contributes`, `preferences` and `activation` may be left out.** With no `activation` a tool is `onCommand`. `activation` may name `onCommand` and `onLaunch` only. **Adds to the spec.** | The sheet and the hub show the publisher beside the name. Requiring it now can be relaxed later without breaking a tool; the reverse cannot. `onShown` is the app's and has no meaning for a process. |
| 10 | **A preference is `{ id, type, default }`, all required. `type` is `string`, `boolean`, `integer` or `number`**, JSON Schema's own words. It is saved under `<tool id>/<preference id>` (`ExternalToolManifest.storageKey`). **Adds to the spec.** | `PreferenceDeclaration` needs a key and a default. A key shaped like a command id cannot collide with a built-in key or another tool's. Stage B writes the storage; if it wants another spelling it changes one function. |
| 11 | **An icon never refuses a manifest.** No icon, or one that is only spaces, is the plain puzzle piece (`puzzlepiece.extension`, what an unknown command draws today). A command with no icon takes its tool's. Follows the spec. | Whether this Mac has a symbol is known only when it is drawn. |
| 12 | **One Swift module, `VitruvianToolProtocol`: Foundation only, Swift 6 mode, visible to `//apps/desktop/vitruvian` and to nothing else outside its package.** `Core` imports it by name in the one file that uses it. It is not re-exported. | The module has about forty public names (`JSONValue`, `LogParams`, …). Re-exporting them from `Core`, as `NexusAgentCore` is, would put them in scope in every app file. |
| 13 | **The app pins the protocol's Swift sources**, as it pins the shared Nexus Agent code: `bazel/tool_protocol.sha256` and `tool_protocol_pin_test`. **Adds to the spec.** | Two reasons, and the second is already true in stage A. The app is released by path, so a change made only in the package would never ship in it. And the presubmit planner picks units by the tests that depend on a changed file, leaving out tests tagged `manual`; every Swift test of the app is `manual`. Without the pin, a change to the package alone would not run the app's unit at all. The pin test is not `manual`, so it is the edge that selects the unit. That is how a Nexus Agent change reaches the app's tests today. |
| 14 | **What is on the wire, where the spec leaves it open.** All of it **adds to the spec**; `protocol/README.md` is the full list. Method names are the spec's. A command is named by its bare id (`copyLatest`), never `<tool id>/<name>`: a tool only has its own. A request id is a whole number or a string. `shutdown` is a notice with no params. `commands/state` carries `runnable`, the whole list of commands that can run now. Everything a tool asks of the app is a request, so it can be refused; only `commands/state` and `log` are notices. A request that is simply done answers `{}`. A blank line is ignored. 1 MB is 1,048,576 bytes, not counting the line break. | Types need every one of these pinned. Each choice is the smallest that says what the spec says. |
| 15 | **Error codes.** JSON-RPC's own for a message that cannot be handled: -32700, -32600, -32601, -32602, -32603. The broker's four refusals: -32001 not listed in `uses` (with `data.service`), -32002 not installed, -32003 a macOS permission missing (with `data.permission`), -32004 not available right now. A tool's refusal to run a command: -32010. **Adds to the spec.** | JSON-RPC keeps -32000 to -32099 for the application. |
| 16 | **Three messages carry less or other than the broker's Swift call.** `keystrokes/pressMenuItem` takes key equivalents as a character and the names of the modifiers held with Command (`shift`, `option`, `control`), not the Accessibility bit mask. `processes/terminate` takes `pid`, `name` and `force`; the start time the broker wants is looked up by the app. `storage/get` and `storage/set` take the preference's id, not its saved key. **Adds to the spec.** | A bit mask and a kernel start time are the app's own units. Stage B converts. |
| 17 | **The schemas are two files, `manifest.schema.json` and `messages.schema.json`, with `methods.json` beside them**: the spec's two tables as data (who sends a message, whether it is answered, the `uses` entry it needs, the names of its params and result). | A response does not say which request it answers, so no schema can tie a result to its method. The table does. |
| 18 | **The drift test has two halves over the same example files.** `protocol_examples_test` (Python, `jsonschema` 4.26.0 from `@pip`) judges every example by the schemas. `VitruvianToolProtocolTests` (Swift) judges every example by the types, and compares each type's field names with its schema's by reflection. | See "What the drift test proves" below. |
| 19 | **`conformance/` is a Python 3 script with no dependencies**, run as `python3 conformance.py <tool folder> [--via PROGRAM]` or `bazel run //packages/vitruvian-sdk:conformance -- <tool folder>`. It checks five things: the handshake, a command run, an unknown command refused, the same command with every request the tool makes refused, and shutdown. The reference tool is 80 lines of Python. The folder is `conformance/`, lower case. **Changes the spec**, which writes `Conformance/`, and **adds** the unknown-command check. | It must run on the macOS runner with what is there and must not need the app. Python is on every Mac that has Xcode's tools, and a second implementation written from the schemas checks the protocol better than the Swift types checking themselves. The naming lint wants kebab-case outside a Swift source tree (`DIR003`). |
| 20 | **CI.** A new pipeline unit, `vitruvian-sdk`, on `xcode-27`, runs the package's three tests. The app's manifest tests run in its existing unit, in the `platform` suite. `.github/workflows/ci.yaml` and the app's `delivery` paths are not edited. | Decision 13 makes both edits unnecessary: a protocol change always changes the app's folder. |
| 21 | **No release configuration for the package.** No `release-please-config.json`, no `delivery`, no `publish.sh`. | Publishing is sub-project 4. With no configuration, no commit under `packages/vitruvian-sdk/` can cut a release, whatever its type. |
| 22 | **`Package.swift` mirrors `BUILD`** and is not built in CI, as in `packages/peripherals`. | Bazel is the only build CI runs. The file is there so a tool author can use SwiftPM in stage D. |
| 23 | **Not in stage A:** starting a process; the tool host's two kinds; any broker change; `storage` writing; the tool store; any screen or sentence; the kit; the `vitruvian-tool` command; a second sample; publishing; a mapping from a method to its Swift params type as library API (the test holds one; the kit will want it as a protocol). | Stages B to D. |

### What the drift test proves

It proves three things. Every example the files call valid is accepted by the schema and by the Swift types, and every example they call invalid is refused by both. Every field a schema declares is used by at least one valid example, and every Swift type has exactly the fields its schema definition declares. The table of messages in `methods.json` is the Swift enum `ToolMethod`, row for row.

It does not prove that a constraint written on one side only is on the other, unless an example crosses it. A `maxLength` added to the schema alone would pass. So the rule for a change is: the schema, the Swift type and an example, in one commit. Two manifest rules cannot be written in JSON Schema at all (no two commands share an id, no two preferences share an id); their examples are marked `"schema": false` and only the Swift side judges them.

`jsonschema` is in the pip hub because `mcp` depends on it, not because anything asks for it by name. If it ever leaves the lock, `protocol_examples_test` stops loading, loudly. The fix then is one line in `requirements/tools.in` and a re-lock, which is a dependency decision for that day.

## Global Constraints

- The code in this plan was written against `700c17ab8` (`docs/vitruvian-external-tools-full-trust`, one docs commit ahead of `main` at `db5251559`). **No Swift in it was compiled and nothing was run through Bazel.** The JSON files were parsed, the two Python tests and the conformance script were run against the reference tool, and the Python was formatted with `ruff format`, all in a scratch folder outside the repository, with Python 3.14 and `jsonschema` 4.26.0. Where code does not compile or does not match the file, make the smallest change that keeps its meaning and record it as a deviation.
- **Two licences.** Everything under `apps/desktop/vitruvian/` is GPL-3.0-or-later. Every new file there starts with exactly:
  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 VitruvianSoftware
  ```
  Never edit an existing `Copyright (C) 2026 Vorssaint` header. Everything under `packages/vitruvian-sdk/` is MIT. Every `.swift`, `.py` and `BUILD` file there starts with exactly the header `packages/peripherals` uses, as `//` comments in Swift and `#` comments in Python and `BUILD`:
  ```swift
  // Copyright (c) 2026 VitruvianSoftware
  //
  // Permission is hereby granted, free of charge, to any person obtaining a copy
  // of this software and associated documentation files (the "Software"), to deal
  // in the Software without restriction, including without limitation the rights
  // to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  // copies of the Software, and to permit persons to whom the Software is
  // furnished to do so, subject to the following conditions:
  //
  // The above copyright notice and this permission notice shall be included in
  // all copies or substantial portions of the Software.
  //
  // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  // IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  // FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  // AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  // LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  // OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  // SOFTWARE.
  ```
  **In this plan a listing whose first comment line is `// MIT-HEADER` or `# MIT-HEADER` stands for that header: replace that one line with the nineteen.** A shebang or a `// swift-tools-version` line stays above it. `.json` and `.md` files carry no header: the licence gate does not read them. Never copy code from the app's folder into the package.
- Every change to a file under `apps/desktop/vitruvian/` whose line 2 or 3 says `Copyright (C) 2026 Vorssaint` is named in `UPSTREAM.md` under "Modifications" in the same commit. This plan changes one such file, `Tests/mutation_checks.py`. Task 6 writes one entry that also records the new files and the new link to an MIT module. Check the header of each file you change; do not trust a list.
- **Nothing a user can see changes.** No new string in the app. No new command, tile, row or setting. Nothing under `Sources/Vitruvian/` outside `Core/Platform/` is edited. Nothing in the app calls `ExternalToolManifest`.
- In the app, module order is `Core <- Design <- Services <- UI <- App`. All of them and the tests build in Swift 6 mode. What another module uses is `package`. `Core` may import Foundation, `FanControlKit`, `NexusAgentCore` and now `VitruvianToolProtocol`, and nothing else.
- In the package, `VitruvianToolProtocol` imports Foundation only. It builds in Swift 6 mode and for macOS 14, the app's deployment target. What a tool author or the app uses is `public`, with its initializer written out. It imports no `Vitruvian*` module, ever: the dependency runs one way, MIT into GPL.
- A file or folder name follows `tools/lint-naming`: Swift files PascalCase, Python files snake_case, folders kebab-case except `Sources`, `Tests` and the module folders under them, which follow `packages/peripherals`. The lint's own rule would refuse a PascalCase module folder under `packages/` (`DIR003`); nothing in CI runs that lint over the repository, and `packages/peripherals` already has such folders.
- Existing tests keep their expectations. No expectation in an existing test changes in this stage. One line of `Tests/TestGroups.swift` gains a call.
- App tests are behavioural. No test reads a source file as text, starts a program, or waits for a timer. The folder tests make folders of empty files under the temporary folder and remove them. Three rules of the app's test target apply:
  - A type declared in a test is not named like a production type (`test_types_do_not_shadow_real_ones`). This plan declares one, `ExternalToolManifestTests`.
  - A test enum has one `static func run`, reached from `Tests/TestGroups.swift`.
  - A test builds a `package` type only through a `package` initializer. The new test builds no `ExternalToolManifest` and no `ManifestRefusal` by hand; it reads them.
- The app's test module defaults to the main actor. The package's test target does not, and builds in Swift 5 mode like `PeripheralsTests`.
- Swift notes, each with a fallback if the compiler disagrees:
  - `ToolManifestFile` has stored properties named `` `protocol` `` and `` `default` ``. Their JSON keys are `protocol` and `default`. Fallback: rename them `protocolVersion` and `defaultValue` and add a `CodingKeys` enum; then the reflection test compares against those names, so map them there too.
  - `JSONValue` decodes by trying `Bool`, then `Double`, then `String`. It relies on `JSONDecoder` refusing to read `true` as a number and `1` as a `Bool`. Fallback: decode with `JSONSerialization` and tell a `Bool` from a number with `CFGetTypeID(value) == CFBooleanGetTypeID()`.
  - A whole `Double` is written without a fraction (`20`, not `20.0`). `EnvelopeTests` and the example round trips rely on it only through `JSONValue` equality, which compares numbers, so the text does not matter.
  - `ManifestFileTests.caseName` reads an enum case's name with `Mirror`. Fallback: `String(describing: problem).prefix(while: { $0 != "(" })`.
  - `EmptyObject` asks for a keyed container so that `5` is not read as `{}`. Fallback: none needed; if the private key type will not compile, any `CodingKey` type does.
  - `ExternalToolManifest.group` is a computed `static var`, not a `static let`, so it does not depend on `FeatureGroup` being `Sendable` by declaration.
- After editing a `.py` or `BUILD` file, run `bazel run //tools/format -- <path>`. After adding a file under `packages/vitruvian-sdk/`, run `bazel run //tools/license:check` and `bazel run //tools/license:verify`; both must pass.
- After changing a `pipeline_unit`, regenerate the presubmit workflow and commit it. The Tidy Check job fails on a stale one:
  ```sh
  bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
  ```
- Build and test through Bazel only, from the repository root, one command at a time:
  ```sh
  bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests
  bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test
  bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform
  ```
  The package's Swift test is `manual`, so name it. The two Python tests are not, and need no `--config`.
- Commits are authored as the `wren` agent. In a git worktree the keys are in the main checkout:
  ```sh
  export AGENT_KEY_DIR=/Users/james/Workspace/gh/application/vitruvian/vitruvian-core/tools/sync-env-secrets/agent-keys
  eval "$(bazel run //tools/agent-app -- env wren 2>/dev/null)"
  ```
  Put this in the same command as the commit.
- Commit titles: `chore(vitruvian-sdk): ...` for a task that touches only the package and generated workflow files, `refactor(desktop): ...` for a task that touches the app. Neither cuts a release: no release configuration covers the package (decision 21), and `refactor` is not a releasing type for the app. `main` takes squash merges, so the pull request's title is the one that counts: it is a `refactor(desktop)`. Merging it does move the app's rolling beta, as every merge that touches the app's folder does.

## Review Focus

Failure modes most likely to cost something later. Each has a test in the task named, except where it says otherwise.

1. **The schema and the Swift type disagree about a message**, so a tool written from the schema is refused by the app. (Tasks 2, 3 and 4: the two halves of the drift test.)
2. **A line the framing cannot survive**: a line break inside a message, a line cut across two reads, a character of several bytes cut in the middle, a line over 1 MB that eats the app's memory. (Task 1)
3. **A manifest that should be refused is read**, or is read with part of it dropped: an id with no dot, an unknown service, a program outside the folder, a link out of the folder. (Task 4 for the rules, Task 6 through the app.)
4. **A refusal that does not say what is wrong.** Each one names the offending value. (Tasks 4 and 6)
5. **An outside tool that passes for one of the app's own.** An id with no dot is refused before a `ToolDescriptor` is ever made. (Task 6)
6. **A test that runs in no CI lane.** The package is new, its Swift test is `manual`, and the planner skips `manual` tests when it decides what a change affects. (Task 1 Step 6 and Task 6 Step 7 check the generated workflow.)
7. **A change to the package that never reaches the app's tests or its release.** (Task 6: the pin.)
8. **A release build that changed.** Nothing calls the reader. (Task 6 Step 8, by search; `selftest` in Task 7.)
9. **The conformance script passing a broken tool.** (Task 5: seven broken tools, each caught by the check meant for it.)

---

### Task 1: The package, with a message and a line

Works in `packages/vitruvian-sdk/`.

**Files:**
- Create: `LICENSE`, `.gitignore`, `Package.swift`, `BUILD`
- Create: `Sources/VitruvianToolProtocol/JSONValue.swift`, `Sources/VitruvianToolProtocol/JSONRPC.swift`, `Sources/VitruvianToolProtocol/LineFraming.swift`
- Create: `Tests/VitruvianToolProtocolTests/EnvelopeTests.swift`, `Tests/VitruvianToolProtocolTests/FramingTests.swift`
- Modify: `.github/workflows/presubmit.yaml` (generated)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `JSONValue` (`null`, `bool`, `number`, `string`, `array`, `object`; `init(encoding:)`, `decode(_:)`, `subscript(key:)`, `stringValue`, `boolValue`, `numberValue`, `arrayValue`, `objectValue`)
  - `RPCID` (`number`, `string`); `RPCErrorObject` (`code`, `message`, `data`); `RPCErrorCode` (five constants); `RPCMessage` (`request`, `notice`, `result`, `failure`)
  - `WireLimits.maxLineBytes`; `LineFraming.line(for:)`, `LineFraming.message(from:)`, `LineFraming.LineTooLong`; `LineSplitter` (`init(limit:)`, `append(_:)`, `Piece`)
  - Bazel: `//packages/vitruvian-sdk:VitruvianToolProtocol`, `:protocol_sources`, `:VitruvianToolProtocolTests`, and the pipeline unit `vitruvian-sdk`

The package starts with the part of the protocol that is not about tools at all: what one JSON-RPC message is, and how a message becomes one line. A message is read strictly. The framing never holds more than the limit in memory, whatever arrives.

- [ ] **Step 1: Make the package and write the failing tests**

Create `packages/vitruvian-sdk/LICENSE` as a byte-for-byte copy of `packages/peripherals/LICENSE`:

```sh
cp packages/peripherals/LICENSE packages/vitruvian-sdk/LICENSE
```

Create `packages/vitruvian-sdk/.gitignore`:

```
.build/
.swiftpm/
```

Create `packages/vitruvian-sdk/Package.swift`:

```swift
// swift-tools-version: 6.0
// MIT-HEADER

import PackageDescription

let package = Package(
    name: "VitruvianSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VitruvianToolProtocol", targets: ["VitruvianToolProtocol"]),
    ],
    targets: [
        // MUST MIRROR packages/vitruvian-sdk/BUILD, target for target. These
        // sources have two build definitions and CI only runs the Bazel one;
        // a target added to BUILD but not here (or the reverse) breaks
        // `swift build` silently (see packages/peripherals/Package.swift).
        //
        // The protocol, as Swift: Foundation only, Swift 6 mode. The Vitruvian
        // desktop app links this module, so it may import nothing of the app.
        .target(
            name: "VitruvianToolProtocol",
            path: "Sources/VitruvianToolProtocol"
        ),
        .testTarget(
            name: "VitruvianToolProtocolTests",
            dependencies: ["VitruvianToolProtocol"],
            path: "Tests/VitruvianToolProtocolTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

Create `packages/vitruvian-sdk/BUILD`:

```python
# MIT-HEADER

# //packages/vitruvian-sdk: what a tool that runs as its own program is built
# against. The protocol between such a tool and the Vitruvian desktop app, as
# JSON Schema (protocol/) and as Swift (Sources/VitruvianToolProtocol). See
# README.md.
#
# Swift has no Gazelle extension here, so this file is hand-written, and
# Gazelle is kept out of the folders below it: it would write BUILD files for
# the Python it finds there.
# gazelle:ignore
# gazelle:exclude Sources
# gazelle:exclude Tests
# gazelle:exclude conformance
# gazelle:exclude protocol
#
# MUST MIRROR Package.swift target for target (packages/peripherals/BUILD says
# why). The Swift targets are constrained to macOS so a Linux
# `bazel build //...` skips them.

load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The one list of the protocol's Swift sources: it is both what the module
# compiles and what the Vitruvian app's pin hashes
# (//apps/desktop/vitruvian:tool_protocol_pin_test), so the two cannot differ.
filegroup(
    name = "protocol_sources",
    srcs = glob(["Sources/VitruvianToolProtocol/**/*.swift"]),
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# The protocol as Swift types. Foundation only. Swift 6 mode because the app's
# Core module, which links it, is. Nothing here may import a Vitruvian module:
# the dependency runs one way, MIT into GPL. Visible to the app and to this
# package, and to nothing else until the package is published.
swift_library(
    name = "VitruvianToolProtocol",
    srcs = [":protocol_sources"],
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolProtocol",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# macOS-only and `manual`, like every swift_test in the repository, so the
# Linux lane never names it; the `vitruvian-sdk` pipeline unit below runs it by
# explicit label on xcode-27.
swift_test(
    name = "VitruvianToolProtocolTests",
    size = "small",
    srcs = glob(["Tests/VitruvianToolProtocolTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianToolProtocol"],
)

pipeline_unit(
    name = "vitruvian-sdk",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [":VitruvianToolProtocolTests"],
    tier = "L1",
    timeout_minutes = 30,
)
```

Create `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/EnvelopeTests.swift`:

```swift
// MIT-HEADER

import XCTest

import VitruvianToolProtocol

final class EnvelopeTests: XCTestCase {
    private func read(_ text: String) throws -> RPCMessage {
        try LineFraming.message(from: Data(text.utf8))
    }

    func testTheFourKindsOfMessageAreToldApart() throws {
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"language":"en-US"}}"#),
            .request(id: .number(1), method: "initialize", params: .object(["language": .string("en-US")])))
        XCTAssertEqual(try read(#"{"jsonrpc":"2.0","method":"shutdown"}"#),
                       .notice(method: "shutdown", params: nil))
        XCTAssertEqual(try read(#"{"jsonrpc":"2.0","id":"a-7","result":{}}"#),
                       .result(id: .string("a-7"), value: .object([:])))
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"method not found"}}"#),
            .failure(id: .number(2), error: RPCErrorObject(code: -32601, message: "method not found")))
        XCTAssertEqual(
            try read(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error"}}"#),
            .failure(id: nil, error: RPCErrorObject(code: RPCErrorCode.parseError, message: "parse error")))
    }

    func testWhatIsNotAMessageIsRefused() {
        let lines = [
            "not json",
            "[]",
            #"{"id":1,"method":"initialize"}"#,
            #"{"jsonrpc":"1.0","id":1,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":null,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":1.5,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":true,"method":"initialize"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":7}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","params":[1]}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","params":"text"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"log","result":{}}"#,
            #"{"jsonrpc":"2.0","id":1}"#,
            #"{"jsonrpc":"2.0","result":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{},"error":{"code":1,"message":"both"}}"#,
            #"{"jsonrpc":"2.0","error":{"code":1,"message":"no id"}}"#,
            #"{"jsonrpc":"2.0","id":1,"error":{"message":"no code"}}"#,
        ]
        for line in lines {
            XCTAssertThrowsError(try read(line), line)
        }
    }

    func testAMessageWrittenIsTheMessageRead() throws {
        let messages: [RPCMessage] = [
            .request(id: .number(7), method: "command/run", params: .object(["command": .string("copyLatest")])),
            .request(id: .string("t-1"), method: "notify/beep", params: nil),
            .notice(method: "commands/state", params: .object(["runnable": .array([.string("a"), .string("b")])])),
            .result(id: .number(7), value: .object(["value": .number(20.5), "on": .bool(true), "none": .null])),
            .failure(id: .number(7), error: RPCErrorObject(code: -32001, message: "not listed in uses",
                                                           data: .object(["service": .string("clipboard.write")]))),
            .failure(id: nil, error: RPCErrorObject(code: RPCErrorCode.parseError, message: "parse error")),
        ]
        for message in messages {
            let line = try LineFraming.line(for: message)
            XCTAssertEqual(try LineFraming.message(from: line.dropLast()), message)
        }
    }

    private struct Greeting: Codable, Equatable {
        let language: String
        let versions: [String]
    }

    func testAValueIsReadAsATypeAndWrittenBack() throws {
        let greeting = Greeting(language: "fr", versions: ["1"])
        let value = try JSONValue(encoding: greeting)
        XCTAssertEqual(value["language"], .string("fr"))
        XCTAssertEqual(value["versions"]?.arrayValue, [.string("1")])
        XCTAssertEqual(try value.decode(Greeting.self), greeting)
        XCTAssertEqual(try JSONValue.object(["language": .string("fr"), "versions": .array([]), "later": .null])
                           .decode(Greeting.self),
                       Greeting(language: "fr", versions: []), "a field the type does not have is ignored")
        XCTAssertThrowsError(try JSONValue.object(["language": .number(1)]).decode(Greeting.self))
        XCTAssertEqual(try JSONValue(encoding: 3), .number(3))
        XCTAssertNil(JSONValue.string("x")["language"])
    }
}
```

Create `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/FramingTests.swift`:

```swift
// MIT-HEADER

import XCTest

import VitruvianToolProtocol

final class FramingTests: XCTestCase {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    func testAMessageIsOneLine() throws {
        let message = RPCMessage.request(id: .number(1), method: "keystrokes/paste",
                                         params: .object(["text": .string("two\nlines\r\nand a / slash")]))
        let line = try LineFraming.line(for: message)
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1, "the only line break is the one that ends the line")
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertTrue(text.contains(#""method":"keystrokes/paste""#), "a slash is written as a slash: \(text)")
        XCTAssertEqual(try LineFraming.message(from: line.dropLast()), message)
    }

    func testAMessageOverTheLimitIsNotWritten() {
        let long = String(repeating: "x", count: WireLimits.maxLineBytes)
        let message = RPCMessage.notice(method: "log", params: .object(["message": .string(long)]))
        XCTAssertThrowsError(try LineFraming.line(for: message)) { error in
            XCTAssertTrue(error is LineFraming.LineTooLong)
        }
    }

    func testBytesBecomeLinesWhereverTheyAreCut() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(bytes(#"{"a":"#)), [])
        XCTAssertEqual(splitter.append(bytes("1}\n{\"b\":2}\n{\"c\"")), [.line(bytes(#"{"a":1}"#)), .line(bytes(#"{"b":2}"#))])
        XCTAssertEqual(splitter.append(bytes(":3}")), [])
        XCTAssertEqual(splitter.append(bytes("\n")), [.line(bytes(#"{"c":3}"#))])

        // A character of several bytes cut in the middle arrives whole.
        let accented = bytes("{\"n\":\"Déploiements\"}\n")
        var cut = LineSplitter()
        var pieces: [LineSplitter.Piece] = []
        for byte in accented { pieces += cut.append(Data([byte])) }
        XCTAssertEqual(pieces, [.line(accented.dropLast())])
    }

    func testEmptyLinesAreNotLines() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(bytes("\n  \n\r\n{}\r\n\t\n")), [.line(bytes("{}\r"))])
    }

    func testALineOverTheLimitIsReportedOnceAndTheNextLineIsRead() {
        var splitter = LineSplitter(limit: 8)
        XCTAssertEqual(splitter.append(bytes("12345678\n")), [.line(bytes("12345678"))], "the limit itself is allowed")
        XCTAssertEqual(splitter.append(bytes("123456789")), [.oversized], "said as soon as it is known")
        XCTAssertEqual(splitter.append(bytes("more of the same line")), [])
        XCTAssertEqual(splitter.append(bytes(" and its end\nok\n")), [.line(bytes("ok"))])
        XCTAssertEqual(splitter.append(bytes("1234")), [])
        XCTAssertEqual(splitter.append(bytes("56789\nok\n")), [.oversized, .line(bytes("ok"))],
                       "a line that goes over when its end arrives")
        XCTAssertEqual(splitter.append(bytes("123456789\nok\n")), [.oversized, .line(bytes("ok"))])
    }

    func testTheLimitIsTheDesigns() {
        XCTAssertEqual(WireLimits.maxLineBytes, 1_048_576)
        XCTAssertEqual(LineSplitter().limit, WireLimits.maxLineBytes)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests`
Expected: FAIL before anything compiles. `protocol_sources` globs a folder that does not exist yet, so Bazel stops with "glob pattern 'Sources/VitruvianToolProtocol/**/*.swift' didn't match anything".

- [ ] **Step 3: Write the value, the message and the line**

Create `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/JSONValue.swift`:

```swift
// MIT-HEADER

import Foundation

/// Any JSON value. Parts of a message whose shape depends on the message,
/// such as `params`, are held as one until they are read as a type.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// Every JSON number, whole or not. A whole number up to 2^53 is exact.
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// What `value` is when written as JSON.
    public init<Value: Encodable>(encoding value: Value) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Reads the value as `type`. Fields the type does not have are ignored.
    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }

    /// The field `key` of an object; nil for anything else.
    public subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
```

Create `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/JSONRPC.swift`:

```swift
// MIT-HEADER

import Foundation

/// What ties an answer to its request: a whole number or a string, chosen by
/// whoever sends the request.
public enum RPCID: Hashable, Sendable {
    case number(Int)
    case string(String)
}

extension RPCID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// Why a request was not done.
public struct RPCErrorObject: Codable, Equatable, Sendable, Error {
    public let code: Int
    /// A few English words for a log. Never shown to the person as it is.
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// The JSON-RPC 2.0 codes for a message that could not be handled at all.
public enum RPCErrorCode {
    /// The line was not JSON.
    public static let parseError = -32700
    /// It was JSON and not a message.
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// One JSON-RPC 2.0 message: what one line on the link holds.
public enum RPCMessage: Equatable, Sendable {
    /// A message that is answered.
    case request(id: RPCID, method: String, params: JSONValue?)
    /// A message that is not answered.
    case notice(method: String, params: JSONValue?)
    /// The answer to a request that was done.
    case result(id: RPCID, value: JSONValue)
    /// The answer to a request that was not done. The id is nil when the
    /// request could not be read at all.
    case failure(id: RPCID?, error: RPCErrorObject)
}

extension RPCMessage: Codable {
    private enum Key: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        func refuse(_ key: Key, _ why: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: why)
        }
        guard try container.decode(String.self, forKey: .jsonrpc) == "2.0" else {
            throw refuse(.jsonrpc, "jsonrpc is not 2.0")
        }
        if container.contains(.method) {
            guard !container.contains(.result), !container.contains(.error) else {
                throw refuse(.method, "a message is a method or an answer, never both")
            }
            let method = try container.decode(String.self, forKey: .method)
            let params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
            if let params, params.objectValue == nil {
                throw refuse(.params, "params is not an object")
            }
            if container.contains(.id) {
                let id = try container.decode(RPCID.self, forKey: .id)
                self = .request(id: id, method: method, params: params)
            } else {
                self = .notice(method: method, params: params)
            }
        } else if container.contains(.error) {
            guard !container.contains(.result) else {
                throw refuse(.error, "an answer is a result or an error, never both")
            }
            // A null id is allowed here and nowhere else; a missing one is not.
            var id: RPCID?
            if try !container.decodeNil(forKey: .id) {
                id = try container.decode(RPCID.self, forKey: .id)
            }
            let error = try container.decode(RPCErrorObject.self, forKey: .error)
            self = .failure(id: id, error: error)
        } else {
            let id = try container.decode(RPCID.self, forKey: .id)
            let value = try container.decode(JSONValue.self, forKey: .result)
            self = .result(id: id, value: value)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode("2.0", forKey: .jsonrpc)
        switch self {
        case .request(let id, let method, let params):
            try container.encode(id, forKey: .id)
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case .notice(let method, let params):
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case .result(let id, let value):
            try container.encode(id, forKey: .id)
            try container.encode(value, forKey: .result)
        case .failure(let id, let error):
            if let id {
                try container.encode(id, forKey: .id)
            } else {
                try container.encodeNil(forKey: .id)
            }
            try container.encode(error, forKey: .error)
        }
    }
}
```

Create `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/LineFraming.swift`:

```swift
// MIT-HEADER

import Foundation

/// The limits that belong to the link itself.
public enum WireLimits {
    /// The longest line either side may send, in bytes, not counting the
    /// line break that ends it: 1 MB.
    public static let maxLineBytes = 1_048_576
}

/// One message per line: how a message becomes bytes on the link, and back.
public enum LineFraming {
    /// A message too long to send.
    public struct LineTooLong: Error, Equatable, Sendable {
        public let bytes: Int
    }

    /// The message as one line of UTF-8, ending with its line break. The
    /// line never holds a line break of its own: JSON writes one inside a
    /// string as `\n`.
    public static func line(for message: RPCMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(message)
        guard line.count <= WireLimits.maxLineBytes else { throw LineTooLong(bytes: line.count) }
        line.append(0x0A)
        return line
    }

    /// Reads one line, without its line break, as a message. Throws when the
    /// line is not a JSON-RPC 2.0 message.
    public static func message(from line: Data) throws -> RPCMessage {
        try JSONDecoder().decode(RPCMessage.self, from: line)
    }
}

/// Cuts a stream of bytes into lines. Bytes arrive in pieces of any size; a
/// line is given out once its line break has arrived. It never holds more
/// than `limit` bytes, however long a line the other side sends.
public struct LineSplitter: Sendable {
    public enum Piece: Equatable, Sendable {
        /// One line, without its line break. Never empty or only spaces.
        case line(Data)
        /// A line went over the limit. Given out once, as soon as it is
        /// known; the rest of that line is thrown away.
        case oversized
    }

    public let limit: Int
    private var pending = Data()
    private var discarding = false

    public init(limit: Int = WireLimits.maxLineBytes) {
        self.limit = limit
    }

    public mutating func append(_ bytes: Data) -> [Piece] {
        var pieces: [Piece] = []
        var rest = bytes[bytes.startIndex...]
        while let lineBreak = rest.firstIndex(of: 0x0A) {
            let head = rest[rest.startIndex..<lineBreak]
            rest = rest[rest.index(after: lineBreak)...]
            if discarding {
                discarding = false
            } else if pending.count + head.count > limit {
                pieces.append(.oversized)
            } else {
                pending.append(head)
                if !pending.allSatisfy(Self.isBlank) { pieces.append(.line(pending)) }
            }
            pending = Data()
        }
        guard !discarding else { return pieces }
        if pending.count + rest.count > limit {
            pending = Data()
            discarding = true
            pieces.append(.oversized)
        } else {
            pending.append(rest)
        }
        return pieces
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests --test_output=errors`
Expected: PASS, ten tests in two classes.

If `testWhatIsNotAMessageIsRefused` fails on the line with `"id":true` or `"id":1.5`, the decoder on this macOS reads more loosely than this plan assumes: see the `JSONValue` note in Global Constraints, and apply the same fallback to `RPCID`.

- [ ] **Step 5: Format, and check the licence gate**

```sh
bazel run //tools/format -- packages/vitruvian-sdk/BUILD
bazel run //tools/license:check
bazel run //tools/license:verify
```

Expected: the formatter changes nothing or reorders attributes; both licence commands pass. If `license:check` names a file under `packages/vitruvian-sdk/`, its header is missing or is not the nineteen lines.

- [ ] **Step 6: Give the tests a CI lane, and prove they are in it**

```sh
bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
git diff --stat -- .github/workflows/presubmit.yaml
grep -n "vitruvian-sdk" .github/workflows/presubmit.yaml
```

Expected: the file changed. The `grep` shows four things: `"vitruvian-sdk"` in `ALL_UNITS`; a job `unit-vitruvian-sdk` that runs on `xcode-27`; its line `bazel test "${extra_flags[@]}" "${cache_flags[@]}" //packages/vitruvian-sdk:VitruvianToolProtocolTests`, with `extra_flags=(--config=macos-app)` above it; and `unit-vitruvian-sdk` in the last job's `needs`. If any is missing, stop: the tests would run in no lane.

How the unit is chosen for a pull request: the planner (`tools/pipeline/plan`) maps each changed file to its nearest `BUILD`, and a unit whose package that is runs. Every file of this package has `packages/vitruvian-sdk/BUILD` as its nearest, because the folders below it have none.

- [ ] **Step 7: Commit**

```bash
git add packages/vitruvian-sdk/LICENSE packages/vitruvian-sdk/.gitignore packages/vitruvian-sdk/Package.swift packages/vitruvian-sdk/BUILD packages/vitruvian-sdk/Sources packages/vitruvian-sdk/Tests .github/workflows/presubmit.yaml
git commit -m "chore(vitruvian-sdk): a package for the tool protocol, with a message and a line"
```

---

### Task 2: The protocol, written down

Works in `packages/vitruvian-sdk/`.

**Files:**
- Create: `protocol/manifest.schema.json`, `protocol/messages.schema.json`, `protocol/methods.json`
- Create: `protocol/examples/manifests.json`, `protocol/examples/messages.json`
- Create: `protocol/protocol_examples_test.py`, `protocol/README.md`
- Modify: `BUILD`, `.github/workflows/presubmit.yaml` (generated)

**Interfaces:**
- Consumes: `@pip//jsonschema` (already in `requirements/all.txt`, 4.26.0).
- Produces:
  - `manifest.schema.json`: the manifest, with `$defs` `localizedText`, `contributes`, `command`, `preference`, `runtime`
  - `messages.schema.json`: one message, with `$defs` for the four kinds of message, `error`, `refusalData`, `empty`, and each message's params and result
  - `methods.json`: seventeen rows of `{ method, sender, kind, uses, params, result }`
  - the two example files, in the shapes their `about` fields describe
  - Bazel: `:protocol_examples_test`

This is the source of truth. Tasks 3 and 4 write the Swift to match it, and the examples written here are what both sides are judged by.

- [ ] **Step 1: Write the examples and the failing test**

Create `packages/vitruvian-sdk/protocol/examples/manifests.json`:

```json
{
  "about": "Manifests the schema and the Swift reader must judge alike. Each example is `base` with the top-level fields in `change` replaced; a field changed to null is left out. `problem` is the case of ManifestProblem the Swift reader gives, and `names` are words its reason carries. `schema: false` marks the two rules JSON Schema cannot say, so the schema accepts those manifests.",
  "base": {
    "id": "com.acme.deploys",
    "name": { "en": "Deploys", "fr": "Déploiements" },
    "description": { "en": "Copies the address of your latest deploy." },
    "version": "1.2.0",
    "protocol": "1",
    "publisher": "Acme",
    "license": "MIT",
    "icon": "shippingbox",
    "uses": ["clipboard.write", "notify", "storage"],
    "contributes": { "commands": [{"id": "copyLatest", "title": {"en": "Copy latest deploy"}, "icon": "link", "surfaces": ["commandBar", "radial", "shortcut"]}] },
    "preferences": [{"id": "project", "type": "string", "default": ""}],
    "activation": ["onCommand"],
    "runtime": { "kind": "external", "exec": "bin/deploys" }
  },
  "examples": [
    { "about": "the example in the design", "valid": true, "change": {} },
    { "about": "only what is required", "valid": true, "change": {"description": null, "license": null, "icon": null, "uses": null, "contributes": null, "preferences": null, "activation": null} },
    { "about": "fields a later version might add are ignored", "valid": true, "change": {"future": {"anything": 1}, "runtime": {"kind": "external", "exec": "bin/deploys", "arguments": ["--fast"]}} },
    {
      "about": "every kind of preference, every surface, both activations",
      "valid": true,
      "change": {
        "contributes": {
          "commands": [
            { "id": "copy.latest", "title": {"en": "Copy latest deploy"}, "surfaces": ["commandBar", "radial", "quickPanel", "shortcut"] },
            { "id": "open-dashboard", "title": {"en": "Open the dashboard", "pt-BR": "Abrir o painel"} }
          ]
        },
        "preferences": [
          { "id": "project", "type": "string", "default": "acme" },
          { "id": "notify", "type": "boolean", "default": true },
          { "id": "limit", "type": "integer", "default": 20 },
          { "id": "ratio", "type": "number", "default": 0.5 },
          { "id": "whole", "type": "number", "default": 3 }
        ],
        "activation": ["onLaunch", "onCommand"]
      }
    },
    { "about": "an id with no dot is a built-in feature's", "valid": false, "problem": "idWithoutDot", "names": ["deploys"], "change": {"id": "deploys"} },
    { "about": "an id with a character ids do not have", "valid": false, "problem": "idNotWellFormed", "names": ["com.acme/deploys"], "change": {"id": "com.acme/deploys"} },
    { "about": "an id that ends with a dot", "valid": false, "problem": "idNotWellFormed", "change": {"id": "com.acme."} },
    { "about": "a protocol the app does not speak", "valid": false, "problem": "unsupportedProtocol", "names": ["2"], "change": {"protocol": "2"} },
    { "about": "a kind of runtime a file may not name", "valid": false, "problem": "unsupportedRuntime", "names": ["bundled"], "change": {"runtime": {"kind": "bundled", "exec": "bin/deploys"}} },
    { "about": "a program above the folder", "valid": false, "problem": "programLeavesFolder", "names": ["../deploys"], "change": {"runtime": {"kind": "external", "exec": "../deploys"}} },
    { "about": "a program that climbs out part way along", "valid": false, "problem": "programLeavesFolder", "change": {"runtime": {"kind": "external", "exec": "bin/../../deploys"}} },
    { "about": "a program named from the root of the disk", "valid": false, "problem": "programLeavesFolder", "change": {"runtime": {"kind": "external", "exec": "/usr/bin/true"}} },
    { "about": "no program", "valid": false, "problem": "programLeavesFolder", "change": {"runtime": {"kind": "external", "exec": ""}} },
    { "about": "no runtime", "valid": false, "problem": "malformed", "names": ["runtime"], "change": {"runtime": null} },
    { "about": "no publisher", "valid": false, "problem": "malformed", "names": ["publisher"], "change": {"publisher": null} },
    { "about": "a name that is not a language map", "valid": false, "problem": "malformed", "names": ["name"], "change": {"name": "Deploys"} },
    { "about": "a name with no English", "valid": false, "problem": "noEnglish", "names": ["name"], "change": {"name": {"fr": "Déploiements"}} },
    { "about": "a name that is only spaces", "valid": false, "problem": "blankText", "names": ["name"], "change": {"name": {"en": "  "}} },
    { "about": "a version that is only spaces", "valid": false, "problem": "blankText", "names": ["version"], "change": {"version": " "} },
    { "about": "a service the app does not have", "valid": false, "problem": "unknownService", "names": ["camera"], "change": {"uses": ["notify", "camera"]} },
    { "about": "a service built-in tools have and version 1 does not offer", "valid": false, "problem": "unknownService", "names": ["hotkey"], "change": {"uses": ["hotkey"]} },
    { "about": "a service listed twice", "valid": false, "problem": "duplicateService", "names": ["notify"], "change": {"uses": ["notify", "notify"]} },
    { "about": "a way of starting that version 1 does not have", "valid": false, "problem": "unknownActivation", "names": ["onShown"], "change": {"activation": ["onShown"]} },
    {
      "about": "a surface the app does not have",
      "valid": false,
      "problem": "unknownSurface",
      "names": ["copyLatest", "island"],
      "change": { "contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}, "surfaces": ["commandBar", "island"]}]} }
    },
    {
      "about": "a command id with a space",
      "valid": false,
      "problem": "commandNotWellFormed",
      "names": ["copy latest"],
      "change": { "contributes": {"commands": [{"id": "copy latest", "title": {"en": "Copy"}}]} }
    },
    {
      "about": "a command title with no English",
      "valid": false,
      "problem": "noEnglish",
      "names": ["copyLatest"],
      "change": { "contributes": {"commands": [{"id": "copyLatest", "title": {"de": "Kopieren"}}]} }
    },
    {
      "about": "two commands with one id",
      "valid": false,
      "schema": false,
      "problem": "duplicateCommand",
      "names": ["copyLatest"],
      "change": { "contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}}, {"id": "copyLatest", "title": {"en": "Copy again"}}]} }
    },
    {
      "about": "a kind of preference the app does not have",
      "valid": false,
      "problem": "unknownPreferenceType",
      "names": ["project", "color"],
      "change": { "preferences": [{"id": "project", "type": "color", "default": "red"}] }
    },
    { "about": "a default of another type", "valid": false, "problem": "defaultOfWrongType", "names": ["limit"], "change": {"preferences": [{"id": "limit", "type": "integer", "default": "20"}]} },
    {
      "about": "a whole-number preference with a fraction for its default",
      "valid": false,
      "problem": "defaultOfWrongType",
      "names": ["limit"],
      "change": { "preferences": [{"id": "limit", "type": "integer", "default": 1.5}] }
    },
    { "about": "a preference id with a slash", "valid": false, "problem": "preferenceNotWellFormed", "names": ["a/b"], "change": {"preferences": [{"id": "a/b", "type": "string", "default": ""}]} },
    {
      "about": "two preferences with one id",
      "valid": false,
      "schema": false,
      "problem": "duplicatePreference",
      "names": ["project"],
      "change": { "preferences": [{"id": "project", "type": "string", "default": ""}, {"id": "project", "type": "boolean", "default": false}] }
    }
  ]
}
```

Create `packages/vitruvian-sdk/protocol/examples/messages.json`:

```json
{
  "about": "Messages the schema and the Swift types must read alike. A result or failure names, in `answers`, the method it answers. `unknownFields: true` marks a message that carries a field version 1 does not have: both sides accept it, and the Swift types drop the field.",
  "examples": [
    { "about": "the app starts", "valid": true, "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersions": ["1"], "language": "en-US", "dataFolder": "/Users/example/Library/Application Support/Vitruvian/ToolData/com.acme.deploys"}} },
    { "about": "the tool picks a version", "valid": true, "answers": "initialize", "message": {"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "1", "toolVersion": "1.2.0"}} },
    { "about": "run a command", "valid": true, "message": {"jsonrpc": "2.0", "id": 2, "method": "command/run", "params": {"command": "copyLatest"}} },
    { "about": "the command ran", "valid": true, "answers": "command/run", "message": {"jsonrpc": "2.0", "id": 2, "result": {}} },
    { "about": "the tool would not run it", "valid": true, "answers": "command/run", "message": {"jsonrpc": "2.0", "id": 2, "error": {"code": -32010, "message": "command refused"}} },
    { "about": "preferences changed", "valid": true, "message": {"jsonrpc": "2.0", "method": "preferences/changed", "params": {"values": {"project": "acme", "notify": false, "limit": 20}}} },
    { "about": "the language changed", "valid": true, "message": {"jsonrpc": "2.0", "method": "language/changed", "params": {"language": "fr"}} },
    { "about": "stop", "valid": true, "message": {"jsonrpc": "2.0", "method": "shutdown"} },
    { "about": "which commands can run", "valid": true, "message": {"jsonrpc": "2.0", "method": "commands/state", "params": {"runnable": ["copyLatest"]}} },
    { "about": "no command can run", "valid": true, "message": {"jsonrpc": "2.0", "method": "commands/state", "params": {"runnable": []}} },
    { "about": "an on-screen message, with a string id", "valid": true, "message": {"jsonrpc": "2.0", "id": "t-1", "method": "notify/hud", "params": {"icon": "checkmark.circle", "message": "Copied"}} },
    { "about": "the message was shown", "valid": true, "answers": "notify/hud", "message": {"jsonrpc": "2.0", "id": "t-1", "result": {}} },
    { "about": "the alert sound", "valid": true, "message": {"jsonrpc": "2.0", "id": 3, "method": "notify/beep"} },
    { "about": "the sound was played", "valid": true, "answers": "notify/beep", "message": {"jsonrpc": "2.0", "id": 3, "result": {}} },
    { "about": "open a link", "valid": true, "message": {"jsonrpc": "2.0", "id": 4, "method": "open/url", "params": {"url": "https://example.com/deploys/41"}} },
    { "about": "the link was opened", "valid": true, "answers": "open/url", "message": {"jsonrpc": "2.0", "id": 4, "result": {"opened": true}} },
    { "about": "read the clipboard", "valid": true, "message": {"jsonrpc": "2.0", "id": 5, "method": "clipboard/readText"} },
    { "about": "the clipboard's text", "valid": true, "answers": "clipboard/readText", "message": {"jsonrpc": "2.0", "id": 5, "result": {"text": "hello"}} },
    { "about": "a clipboard with no text", "valid": true, "answers": "clipboard/readText", "message": {"jsonrpc": "2.0", "id": 5, "result": {}} },
    { "about": "write the clipboard", "valid": true, "message": {"jsonrpc": "2.0", "id": 6, "method": "clipboard/writeText", "params": {"text": "https://example.com/deploys/41"}} },
    { "about": "the clipboard took it", "valid": true, "answers": "clipboard/writeText", "message": {"jsonrpc": "2.0", "id": 6, "result": {"written": true}} },
    { "about": "paste into the app in front", "valid": true, "message": {"jsonrpc": "2.0", "id": 7, "method": "keystrokes/paste", "params": {"text": "two\nlines"}} },
    { "about": "the paste was typed", "valid": true, "answers": "keystrokes/paste", "message": {"jsonrpc": "2.0", "id": 7, "result": {}} },
    { "about": "press Paste and Match Style", "valid": true, "message": {"jsonrpc": "2.0", "id": 8, "method": "keystrokes/pressMenuItem", "params": {"equivalents": [{"character": "V", "modifiers": ["shift", "option"]}, {"character": "V", "modifiers": []}]}} },
    { "about": "an item was pressed", "valid": true, "answers": "keystrokes/pressMenuItem", "message": {"jsonrpc": "2.0", "id": 8, "result": {"pressed": true}} },
    { "about": "end a process", "valid": true, "message": {"jsonrpc": "2.0", "id": 9, "method": "processes/terminate", "params": {"pid": 4242, "name": "node", "force": false}} },
    { "about": "the process was asked to end", "valid": true, "answers": "processes/terminate", "message": {"jsonrpc": "2.0", "id": 9, "result": {}} },
    { "about": "read a preference", "valid": true, "message": {"jsonrpc": "2.0", "id": 10, "method": "storage/get", "params": {"key": "project"}} },
    { "about": "the preference's value", "valid": true, "answers": "storage/get", "message": {"jsonrpc": "2.0", "id": 10, "result": {"value": "acme"}} },
    { "about": "save a preference", "valid": true, "message": {"jsonrpc": "2.0", "id": 11, "method": "storage/set", "params": {"key": "limit", "value": 20}} },
    { "about": "the preference was saved", "valid": true, "answers": "storage/set", "message": {"jsonrpc": "2.0", "id": 11, "result": {}} },
    { "about": "a line for the log", "valid": true, "message": {"jsonrpc": "2.0", "method": "log", "params": {"message": "fetched 3 deploys"}} },
    { "about": "refused: the service is not in uses", "valid": true, "answers": "clipboard/writeText", "message": {"jsonrpc": "2.0", "id": 6, "error": {"code": -32001, "message": "not listed in uses", "data": {"service": "clipboard.write"}}} },
    { "about": "refused: Vitruvian lacks a permission", "valid": true, "answers": "keystrokes/paste", "message": {"jsonrpc": "2.0", "id": 7, "error": {"code": -32003, "message": "Vitruvian lacks a macOS permission", "data": {"permission": "accessibility"}}} },
    { "about": "refused: not available right now", "valid": true, "answers": "processes/terminate", "message": {"jsonrpc": "2.0", "id": 9, "error": {"code": -32004, "message": "not available right now"}} },
    { "about": "a line that could not be read has no id to answer", "valid": true, "message": {"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "parse error"}} },
    { "about": "a method version 1 does not have is still a message", "valid": true, "message": {"jsonrpc": "2.0", "id": 12, "method": "island/notice", "params": {"text": "later"}} },
    { "about": "a field version 1 does not have is ignored", "valid": true, "unknownFields": true, "message": {"jsonrpc": "2.0", "id": 13, "method": "command/run", "params": {"command": "copyLatest", "argument": "later"}} },
    { "about": "not version 2.0", "valid": false, "message": {"jsonrpc": "1.0", "id": 1, "method": "notify/beep"} },
    { "about": "no version", "valid": false, "message": {"id": 1, "method": "notify/beep"} },
    { "about": "a request whose id is null", "valid": false, "message": {"jsonrpc": "2.0", "id": null, "method": "notify/beep"} },
    { "about": "an id with a fraction", "valid": false, "message": {"jsonrpc": "2.0", "id": 1.5, "method": "notify/beep"} },
    { "about": "params that are a list", "valid": false, "message": {"jsonrpc": "2.0", "id": 1, "method": "notify/beep", "params": ["loud"]} },
    { "about": "neither a method nor an answer", "valid": false, "message": {"jsonrpc": "2.0", "id": 1} },
    { "about": "a result and a failure at once", "valid": false, "message": {"jsonrpc": "2.0", "id": 1, "result": {}, "error": {"code": -32603, "message": "both"}} },
    { "about": "a method and a result at once", "valid": false, "message": {"jsonrpc": "2.0", "id": 1, "method": "notify/beep", "result": {}} },
    { "about": "a failure with no code", "valid": false, "message": {"jsonrpc": "2.0", "id": 1, "error": {"message": "no code"}} },
    { "about": "initialize with no language", "valid": false, "message": {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersions": ["1"], "dataFolder": "/tmp"}} },
    { "about": "run a command with no params", "valid": false, "message": {"jsonrpc": "2.0", "id": 2, "method": "command/run"} },
    { "about": "a command that is a number", "valid": false, "message": {"jsonrpc": "2.0", "id": 2, "method": "command/run", "params": {"command": 7}} },
    { "about": "runnable commands that are not a list", "valid": false, "message": {"jsonrpc": "2.0", "method": "commands/state", "params": {"runnable": "copyLatest"}} },
    { "about": "a process id that is text", "valid": false, "message": {"jsonrpc": "2.0", "id": 9, "method": "processes/terminate", "params": {"pid": "4242", "name": "node", "force": false}} },
    { "about": "an answer to initialize with no version picked", "valid": false, "answers": "initialize", "message": {"jsonrpc": "2.0", "id": 1, "result": {"toolVersion": "1.2.0"}} },
    { "about": "an answer to open/url that is not yes or no", "valid": false, "answers": "open/url", "message": {"jsonrpc": "2.0", "id": 4, "result": {"opened": "yes"}} }
  ]
}
```

Create `packages/vitruvian-sdk/protocol/protocol_examples_test.py`:

```python
# MIT-HEADER
"""The protocol's examples, judged by its schemas.

Three things are checked, and the Swift tests check the same three against the
Swift types (Tests/VitruvianToolProtocolTests/ProtocolExamplesTests.swift), so
the schemas and the types cannot drift apart unnoticed:

  1. every example the files call valid passes its schema, and every example
     they call invalid fails it;
  2. the valid examples between them use every field the schemas declare, so
     a field one side has and the other lacks shows up as a failure there;
  3. methods.json and messages.schema.json name the same messages.
"""

import json
import os
import sys

from jsonschema import Draft202012Validator

HERE = os.path.dirname(os.path.abspath(__file__))
ENVELOPES = ("request", "notice", "result", "failure")
REFUSALS_WITH_DATA = (-32001, -32003)


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return json.load(handle)


def cover(node, instance, root, seen, where):
    """Notes each declared field `instance` uses, as (definition, field)."""
    if "$ref" in node:
        where = node["$ref"].rsplit("/", 1)[-1]
        node = root["$defs"][where]
    if isinstance(instance, dict):
        for key, child in node.get("properties", {}).items():
            if key in instance:
                seen.add((where, key))
                cover(child, instance[key], root, seen, where)
    elif isinstance(instance, list) and "items" in node:
        for item in instance:
            cover(node["items"], item, root, seen, where)


def declared(root, top):
    """Every (definition, field) the schema declares."""
    pairs = {(top, key) for key in root.get("properties", {})}
    for name, node in root.get("$defs", {}).items():
        pairs |= {(name, key) for key in node.get("properties", {})}
    return pairs


def unused(root, top, seen):
    return [
        f"no valid example uses {where}.{key}"
        for where, key in sorted(declared(root, top) - seen)
    ]


def manifest_problems():
    schema = load("manifest.schema.json")
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    file = load("examples/manifests.json")
    problems, seen = [], set()
    for example in file["examples"]:
        manifest = dict(file["base"])
        for key, value in example["change"].items():
            if value is None:
                manifest.pop(key, None)
            else:
                manifest[key] = value
        accepted = validator.is_valid(manifest)
        expected = example["valid"] or example.get("schema") is False
        if accepted != expected:
            problems.append(
                f"manifest '{example['about']}': the schema says {accepted}, the example {expected}"
            )
        if example["valid"]:
            cover(schema, manifest, schema, seen, "manifest")
        elif "problem" not in example:
            problems.append(
                f"manifest '{example['about']}': an invalid example names its problem"
            )
    return problems + unused(schema, "manifest", seen)


def kind_of(message):
    if "method" in message:
        return "request" if "id" in message else "notice"
    return "failure" if "error" in message else "result"


def message_problems():
    schema = load("messages.schema.json")
    Draft202012Validator.check_schema(schema)
    whole = Draft202012Validator(schema)
    table = {row["method"]: row for row in load("methods.json")["methods"]}
    problems, seen, shown, answered = [], set(), set(), set()

    def part(name):
        return Draft202012Validator(
            {"$ref": f"#/$defs/{name}", "$defs": schema["$defs"]}
        )

    for example in load("examples/messages.json")["examples"]:
        message, about = example["message"], example["about"]
        accepted = whole.is_valid(message)
        kind = kind_of(message)
        row = table.get(example.get("answers", message.get("method")))
        if accepted and kind == "result":
            accepted = part(row["result"]).is_valid(message["result"])
        if accepted != example["valid"]:
            problems.append(
                f"message '{about}': the schema says {accepted}, the example {example['valid']}"
            )
        if not example["valid"]:
            continue
        cover(schema, message, schema, seen, "message")
        cover({"$ref": f"#/$defs/{kind}"}, message, schema, seen, kind)
        if kind in ("request", "notice") and row:
            shown.add(row["method"])
            if row["kind"] != kind:
                problems.append(
                    f"message '{about}': methods.json calls {row['method']} a {row['kind']}"
                )
            if row["params"]:
                cover(
                    {"$ref": f"#/$defs/{row['params']}"},
                    message["params"],
                    schema,
                    seen,
                    row["params"],
                )
        if kind == "result":
            answered.add(row["method"])
            cover(
                {"$ref": f"#/$defs/{row['result']}"},
                message["result"],
                schema,
                seen,
                row["result"],
            )
        if kind == "failure" and message["error"]["code"] in REFUSALS_WITH_DATA:
            cover(
                {"$ref": "#/$defs/refusalData"},
                message["error"]["data"],
                schema,
                seen,
                "refusalData",
            )

    for method, row in table.items():
        if method not in shown:
            problems.append(f"no valid example shows {method}")
        if row["kind"] == "request" and method not in answered:
            problems.append(f"no valid example answers {method}")
        if (row["kind"] == "request") != (row["result"] is not None):
            problems.append(f"{method}: a request has a result and a notice has none")
        for name in (row["params"], row["result"]):
            if name and name not in schema["$defs"]:
                problems.append(
                    f"{method}: messages.schema.json has no definition {name}"
                )
    named = {
        name
        for row in table.values()
        for name in (row["params"], row["result"])
        if name
    }
    for name in schema["$defs"]:
        if name.endswith(("Params", "Result")) and name not in named:
            problems.append(f"methods.json names no message that carries {name}")
    for envelope in ("request", "notice"):
        bound = {
            branch["if"]["properties"]["method"]["const"]: branch["then"]["properties"][
                "params"
            ]["$ref"]
            for branch in schema["$defs"][envelope]["allOf"]
        }
        wanted = {
            method: f"#/$defs/{row['params']}"
            for method, row in table.items()
            if row["kind"] == envelope and row["params"]
        }
        if bound != wanted:
            problems.append(
                f"the {envelope} definition ties methods to params otherwise than methods.json does"
            )
    return problems + unused(schema, "message", seen)


def main():
    problems = manifest_problems() + message_problems()
    for problem in problems:
        print(problem, file=sys.stderr)
    print("protocol examples: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
```

In `packages/vitruvian-sdk/BUILD`, add a load above the two Swift ones:

```python
load("@aspect_rules_py//py:defs.bzl", "py_test")
```

Add, between the loads and `protocol_sources`:

```python
# The protocol as it is written down: the schemas, the table of messages, and
# the examples both halves of the drift test read.
PROTOCOL_FILES = glob(["protocol/**/*.json"])
```

Give `VitruvianToolProtocolTests` the files, for Tasks 3 and 4, by adding one attribute above `tags`:

```python
    data = PROTOCOL_FILES,
```

Add, after `VitruvianToolProtocolTests`:

```python
# The examples, judged by the schemas. Not `manual` and not tied to macOS: it
# is plain Python, so the Linux lane runs it too.
py_test(
    name = "protocol_examples_test",
    size = "small",
    srcs = ["protocol/protocol_examples_test.py"],
    data = PROTOCOL_FILES,
    main = "protocol/protocol_examples_test.py",
    deps = ["@pip//jsonschema"],
)
```

And in the `pipeline_unit`, replace

```python
    test_targets = [":VitruvianToolProtocolTests"],
```
with
```python
    test_targets = [
        ":VitruvianToolProtocolTests",
        ":protocol_examples_test",
    ],
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bazel test //packages/vitruvian-sdk:protocol_examples_test --test_output=errors`
Expected: FAIL with `FileNotFoundError` for `manifest.schema.json`: the examples are there and nothing yet says what they mean.

- [ ] **Step 3: Write the schemas and the table**

Create `packages/vitruvian-sdk/protocol/manifest.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Vitruvian tool manifest",
  "description": "The file vitruvian-tool.json at the top of a tool's folder. It says what the tool is, which of the app's services it calls, what it adds, and which program to start. A field this schema does not name is ignored, which is how a later version adds one. Two rules are not written here because JSON Schema cannot say them: no two commands share an id, no two preferences share an id; and the whole file is at most 65,536 bytes.",
  "type": "object",
  "required": ["id", "name", "version", "protocol", "publisher", "runtime"],
  "properties": {
    "id": {
      "description": "The tool's identity, in reverse-DNS form, for example com.acme.deploys. Letters, digits, hyphens and underscores in parts joined by single dots. It must have a dot: an id with none belongs to a feature built into the app. At most 128 characters. It never changes between versions of a tool.",
      "type": "string",
      "maxLength": 128,
      "pattern": "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$"
    },
    "name": { "description": "What the tool is called, shown as written.", "$ref": "#/$defs/localizedText" },
    "description": {
      "description": "One sentence on what the tool does, shown as written.",
      "$ref": "#/$defs/localizedText"
    },
    "version": {
      "description": "The tool's own version, as its author writes it.",
      "type": "string",
      "pattern": "\\S"
    },
    "protocol": { "description": "The protocol version the tool speaks.", "const": "1" },
    "publisher": {
      "description": "Who made the tool. Shown beside its name. The app does not check it.",
      "type": "string",
      "pattern": "\\S"
    },
    "license": {
      "description": "The licence the tool is offered under, for example an SPDX identifier.",
      "type": "string"
    },
    "icon": {
      "description": "An SF Symbol name. A name this Mac does not have draws as a plain puzzle piece.",
      "type": "string"
    },
    "uses": {
      "description": "The app services the tool calls. The app refuses a call to a service that is not listed. This is not a list of what the tool is allowed to do: a tool is a separate program and can do anything the app can.",
      "type": "array",
      "uniqueItems": true,
      "items": {
        "enum": ["notify", "open", "clipboard.read", "clipboard.write", "keystrokes", "processes", "storage"]
      }
    },
    "contributes": { "description": "What the tool adds to the app.", "$ref": "#/$defs/contributes" },
    "preferences": {
      "description": "The settings the tool keeps through the app. At most 16.",
      "type": "array",
      "maxItems": 16,
      "items": { "$ref": "#/$defs/preference" }
    },
    "activation": {
      "description": "When the app starts the tool. onCommand: the first time one of its commands runs. onLaunch: with the app. Left out, it is onCommand.",
      "type": "array",
      "items": { "enum": ["onCommand", "onLaunch"] }
    },
    "runtime": { "description": "How the tool runs.", "$ref": "#/$defs/runtime" }
  },
  "$defs": {
    "localizedText": {
      "description": "A piece of text in one or more languages, keyed by language tag (en, fr, pt-BR). English, under en, is required. The app shows the entry for the language in use, then the entry for that language without its region, then English.",
      "type": "object",
      "required": ["en"],
      "additionalProperties": { "type": "string", "pattern": "\\S" }
    },
    "contributes": {
      "description": "What the tool adds to the app. Version 1 has commands only.",
      "type": "object",
      "properties": {
        "commands": {
          "description": "The tool's commands. At most 32.",
          "type": "array",
          "maxItems": 32,
          "items": { "$ref": "#/$defs/command" }
        }
      }
    },
    "command": {
      "description": "One thing the tool can be asked to do.",
      "type": "object",
      "required": ["id", "title"],
      "properties": {
        "id": {
          "description": "The command's name within the tool. The same characters as a tool id; a dot is not needed. The app knows the command as <tool id>/<this id>.",
          "type": "string",
          "maxLength": 128,
          "pattern": "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)*$"
        },
        "title": { "description": "What the command is called in a list.", "$ref": "#/$defs/localizedText" },
        "icon": { "description": "An SF Symbol name. Left out, the tool's icon is used.", "type": "string" },
        "surfaces": {
          "description": "Where the command is offered: the command bar, the radial menu, the Quick panel, and as a shortcut the person records.",
          "type": "array",
          "items": { "enum": ["commandBar", "radial", "quickPanel", "shortcut"] }
        }
      }
    },
    "preference": {
      "description": "One setting. The tool reads and writes it with storage/get and storage/set.",
      "type": "object",
      "required": ["id", "type", "default"],
      "properties": {
        "id": {
          "description": "The setting's name within the tool. The same characters as a command id.",
          "type": "string",
          "maxLength": 128,
          "pattern": "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)*$"
        },
        "type": { "description": "What kind of value it holds.", "enum": ["string", "boolean", "integer", "number"] },
        "default": { "description": "The value before anything is saved. It is of the type named." }
      },
      "allOf": [
        {
          "if": { "properties": {"type": {"const": "string"}} },
          "then": { "properties": {"default": {"type": "string"}} }
        },
        {
          "if": { "properties": {"type": {"const": "boolean"}} },
          "then": { "properties": {"default": {"type": "boolean"}} }
        },
        {
          "if": { "properties": {"type": {"const": "integer"}} },
          "then": { "properties": {"default": {"type": "integer"}} }
        },
        {
          "if": { "properties": {"type": {"const": "number"}} },
          "then": { "properties": {"default": {"type": "number"}} }
        }
      ]
    },
    "runtime": {
      "description": "The program the app starts.",
      "type": "object",
      "required": ["kind", "exec"],
      "properties": {
        "kind": {
          "description": "external: a separate program. The only kind a manifest file may name.",
          "const": "external"
        },
        "exec": {
          "description": "The program, as a path inside the tool's folder, with / between its parts. No part is empty, . or .., so the path cannot leave the folder.",
          "type": "string",
          "pattern": "^(?!\\.{1,2}(/|$))[^/]+(/(?!\\.{1,2}(/|$))[^/]+)*$"
        }
      }
    }
  }
}
```

Create `packages/vitruvian-sdk/protocol/methods.json`:

```json
{
  "about": "Every message of protocol version 1. `sender` is who sends it. A `request` is answered; a `notice` is not. `uses` is the entry the tool's manifest must list in `uses` before the app will do it. `params` and `result` name a definition in messages.schema.json; null means the message carries none.",
  "protocol": "1",
  "methods": [
    { "method": "initialize", "sender": "app", "kind": "request", "uses": null, "params": "initializeParams", "result": "initializeResult" },
    { "method": "command/run", "sender": "app", "kind": "request", "uses": null, "params": "commandRunParams", "result": "empty" },
    { "method": "preferences/changed", "sender": "app", "kind": "notice", "uses": null, "params": "preferencesChangedParams", "result": null },
    { "method": "language/changed", "sender": "app", "kind": "notice", "uses": null, "params": "languageChangedParams", "result": null },
    { "method": "shutdown", "sender": "app", "kind": "notice", "uses": null, "params": null, "result": null },
    { "method": "commands/state", "sender": "tool", "kind": "notice", "uses": null, "params": "commandsStateParams", "result": null },
    { "method": "notify/hud", "sender": "tool", "kind": "request", "uses": "notify", "params": "notifyHUDParams", "result": "empty" },
    { "method": "notify/beep", "sender": "tool", "kind": "request", "uses": "notify", "params": null, "result": "empty" },
    { "method": "open/url", "sender": "tool", "kind": "request", "uses": "open", "params": "openURLParams", "result": "openURLResult" },
    { "method": "clipboard/readText", "sender": "tool", "kind": "request", "uses": "clipboard.read", "params": null, "result": "clipboardReadTextResult" },
    { "method": "clipboard/writeText", "sender": "tool", "kind": "request", "uses": "clipboard.write", "params": "clipboardWriteTextParams", "result": "clipboardWriteTextResult" },
    { "method": "keystrokes/paste", "sender": "tool", "kind": "request", "uses": "keystrokes", "params": "keystrokesPasteParams", "result": "empty" },
    { "method": "keystrokes/pressMenuItem", "sender": "tool", "kind": "request", "uses": "keystrokes", "params": "keystrokesPressMenuItemParams", "result": "keystrokesPressMenuItemResult" },
    { "method": "processes/terminate", "sender": "tool", "kind": "request", "uses": "processes", "params": "processesTerminateParams", "result": "empty" },
    { "method": "storage/get", "sender": "tool", "kind": "request", "uses": "storage", "params": "storageGetParams", "result": "storageGetResult" },
    { "method": "storage/set", "sender": "tool", "kind": "request", "uses": "storage", "params": "storageSetParams", "result": "empty" },
    { "method": "log", "sender": "tool", "kind": "notice", "uses": null, "params": "logParams", "result": null }
  ]
}
```

Create `packages/vitruvian-sdk/protocol/messages.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Vitruvian tool protocol, version 1: one message",
  "description": "One line on the link between the app and a tool: a JSON-RPC 2.0 message, in UTF-8, with no line break inside it, at most 1,048,576 bytes long. methods.json lists every message; each message's params and result are a definition below. A field this schema does not name is ignored, which is how a later version adds one.",
  "type": "object",
  "required": ["jsonrpc"],
  "properties": { "jsonrpc": {"description": "Always the text 2.0.", "const": "2.0"} },
  "oneOf": [
    { "$ref": "#/$defs/request" },
    { "$ref": "#/$defs/notice" },
    { "$ref": "#/$defs/result" },
    { "$ref": "#/$defs/failure" }
  ],
  "$defs": {
    "id": {
      "description": "What ties an answer to its request. A whole number or a string, chosen by whoever sends the request. The app counts up from 1.",
      "type": ["integer", "string"]
    },
    "request": {
      "description": "A message that is answered. The answer is a result or a failure with the same id.",
      "type": "object",
      "required": ["id", "method"],
      "properties": {
        "id": { "$ref": "#/$defs/id" },
        "method": {
          "description": "Which message this is. One the receiver does not know is answered with failure -32601.",
          "type": "string"
        },
        "params": { "description": "What the message carries. Always an object.", "type": "object" }
      },
      "not": { "anyOf": [{"required": ["result"]}, {"required": ["error"]}] },
      "allOf": [
        {
          "if": { "properties": {"method": {"const": "initialize"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/initializeParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "command/run"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/commandRunParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "notify/hud"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/notifyHUDParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "open/url"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/openURLParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "clipboard/writeText"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/clipboardWriteTextParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "keystrokes/paste"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/keystrokesPasteParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "keystrokes/pressMenuItem"}} },
          "then": {
            "required": ["params"],
            "properties": { "params": {"$ref": "#/$defs/keystrokesPressMenuItemParams"} }
          }
        },
        {
          "if": { "properties": {"method": {"const": "processes/terminate"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/processesTerminateParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "storage/get"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/storageGetParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "storage/set"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/storageSetParams"}} }
        }
      ]
    },
    "notice": {
      "description": "A message that is not answered. It has no id.",
      "type": "object",
      "required": ["method"],
      "properties": {
        "method": {
          "description": "Which message this is. One the receiver does not know is ignored.",
          "type": "string"
        },
        "params": { "description": "What the message carries. Always an object.", "type": "object" }
      },
      "not": { "anyOf": [{"required": ["id"]}, {"required": ["result"]}, {"required": ["error"]}] },
      "allOf": [
        {
          "if": { "properties": {"method": {"const": "preferences/changed"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/preferencesChangedParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "language/changed"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/languageChangedParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "commands/state"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/commandsStateParams"}} }
        },
        {
          "if": { "properties": {"method": {"const": "log"}} },
          "then": { "required": ["params"], "properties": {"params": {"$ref": "#/$defs/logParams"}} }
        }
      ]
    },
    "result": {
      "description": "The answer to a request that was done.",
      "type": "object",
      "required": ["id", "result"],
      "properties": {
        "id": { "$ref": "#/$defs/id" },
        "result": { "description": "What the request's row in methods.json names. Always an object in version 1." }
      },
      "not": { "anyOf": [{"required": ["method"]}, {"required": ["error"]}] }
    },
    "failure": {
      "description": "The answer to a request that was not done.",
      "type": "object",
      "required": ["id", "error"],
      "properties": {
        "id": {
          "description": "The request's id, or null when the request could not be read at all.",
          "type": ["integer", "string", "null"]
        },
        "error": { "$ref": "#/$defs/error" }
      },
      "not": { "anyOf": [{"required": ["method"]}, {"required": ["result"]}] }
    },
    "error": {
      "description": "Why a request was not done. Codes: -32700 the line was not JSON; -32600 it was not a message; -32601 the method is not known; -32602 its params are wrong; -32603 something broke inside. A refusal by the app: -32001 the service is not listed in the tool's uses; -32002 the tool is not installed; -32003 Vitruvian lacks a macOS permission the service needs; -32004 not available right now. A refusal by the tool: -32010 the command was not run. A tool must cope with any request being refused.",
      "type": "object",
      "required": ["code", "message"],
      "properties": {
        "code": { "description": "The reason, as a number.", "type": "integer" },
        "message": {
          "description": "The reason, in a few English words, for a log. Never shown to the person as it is.",
          "type": "string"
        },
        "data": { "description": "More about the reason. For -32001 and -32003 it is a refusalData." }
      },
      "allOf": [
        {
          "if": { "properties": {"code": {"enum": [-32001, -32003]}}, "required": ["data"] },
          "then": { "properties": {"data": {"$ref": "#/$defs/refusalData"}} }
        }
      ]
    },
    "refusalData": {
      "description": "What a refusal names.",
      "type": "object",
      "properties": {
        "service": { "description": "For -32001: the entry missing from the tool's uses.", "type": "string" },
        "permission": {
          "description": "For -32003: the macOS permission Vitruvian lacks, for example accessibility.",
          "type": "string"
        }
      }
    },
    "empty": {
      "description": "Nothing to say: an object with no fields. It is the result of a request that was simply done.",
      "type": "object"
    },
    "initializeParams": {
      "description": "The first message. Until it is answered neither side sends anything else.",
      "type": "object",
      "required": ["protocolVersions", "language", "dataFolder"],
      "properties": {
        "protocolVersions": {
          "description": "The protocol versions the app speaks.",
          "type": "array",
          "items": { "type": "string" }
        },
        "language": {
          "description": "The language the app is in, as a tag such as en-US, fr or pt-BR.",
          "type": "string"
        },
        "dataFolder": {
          "description": "The folder the tool may keep its own files in. It is also the folder the tool is started in.",
          "type": "string"
        }
      }
    },
    "initializeResult": {
      "description": "The tool's answer to initialize. A tool that picks a version the app did not offer is stopped.",
      "type": "object",
      "required": ["protocolVersion", "toolVersion"],
      "properties": {
        "protocolVersion": {
          "description": "The one version, of those offered, the tool will speak.",
          "type": "string"
        },
        "toolVersion": { "description": "The tool's own version.", "type": "string" }
      }
    },
    "commandRunParams": {
      "description": "Run one of the tool's commands. The answer is empty when it ran, or failure -32010 when the tool would not run it.",
      "type": "object",
      "required": ["command"],
      "properties": {
        "command": {
          "description": "The command's id as the manifest writes it, without the tool's id in front.",
          "type": "string"
        }
      }
    },
    "preferencesChangedParams": {
      "description": "Some of the tool's preferences were changed from outside the tool.",
      "type": "object",
      "required": ["values"],
      "properties": { "values": {"description": "Each changed preference's id and its new value.", "type": "object"} }
    },
    "languageChangedParams": {
      "description": "The person changed the app's language.",
      "type": "object",
      "required": ["language"],
      "properties": { "language": {"description": "The new language, as a tag.", "type": "string"} }
    },
    "commandsStateParams": {
      "description": "Which of the tool's commands can run now. The tool sends it whenever that changes; each one replaces the last. Until the first one, all of them can.",
      "type": "object",
      "required": ["runnable"],
      "properties": {
        "runnable": {
          "description": "The ids of the commands that can run. A command not listed cannot.",
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "notifyHUDParams": {
      "description": "Show the app's short on-screen message.",
      "type": "object",
      "required": ["icon", "message"],
      "properties": {
        "icon": { "description": "An SF Symbol name, drawn beside the message.", "type": "string" },
        "message": { "description": "The words, shown as the tool wrote them.", "type": "string" }
      }
    },
    "openURLParams": {
      "description": "Open a link in the person's default app for it.",
      "type": "object",
      "required": ["url"],
      "properties": { "url": {"description": "The link.", "type": "string"} }
    },
    "openURLResult": {
      "description": "Whether the link was opened.",
      "type": "object",
      "required": ["opened"],
      "properties": { "opened": {"description": "False when macOS had nothing to open it with.", "type": "boolean"} }
    },
    "clipboardReadTextResult": {
      "description": "The text on the clipboard.",
      "type": "object",
      "properties": {
        "text": {
          "description": "The clipboard's text. Left out when the clipboard holds no text.",
          "type": "string"
        }
      }
    },
    "clipboardWriteTextParams": {
      "description": "Replace the clipboard with this text, marked as Vitruvian's own so clipboard history files it correctly.",
      "type": "object",
      "required": ["text"],
      "properties": { "text": {"description": "The text.", "type": "string"} }
    },
    "clipboardWriteTextResult": {
      "description": "Whether the clipboard took the text.",
      "type": "object",
      "required": ["written"],
      "properties": { "written": {"description": "False when the clipboard would not take it.", "type": "boolean"} }
    },
    "keystrokesPasteParams": {
      "description": "Paste this text into the app in front. The clipboard is put back afterwards.",
      "type": "object",
      "required": ["text"],
      "properties": { "text": {"description": "The text.", "type": "string"} }
    },
    "keystrokesPressMenuItemParams": {
      "description": "Press a menu item of the app in front, found by its key equivalent and never by its title.",
      "type": "object",
      "required": ["equivalents"],
      "properties": {
        "equivalents": {
          "description": "The key equivalents that count. The first enabled item that has one of them is pressed.",
          "type": "array",
          "items": { "$ref": "#/$defs/keyEquivalent" }
        }
      }
    },
    "keyEquivalent": {
      "description": "A menu item's key equivalent. Command is always part of it.",
      "type": "object",
      "required": ["character", "modifiers"],
      "properties": {
        "character": { "description": "The key, as the menu shows it, for example V.", "type": "string" },
        "modifiers": {
          "description": "The keys held with Command.",
          "type": "array",
          "items": { "enum": ["shift", "option", "control"] }
        }
      }
    },
    "keystrokesPressMenuItemResult": {
      "description": "Whether an item was pressed.",
      "type": "object",
      "required": ["pressed"],
      "properties": {
        "pressed": { "description": "False when no enabled item has one of the key equivalents.", "type": "boolean" }
      }
    },
    "processesTerminateParams": {
      "description": "End a process, with the app's checks and its administrator prompt when one is needed.",
      "type": "object",
      "required": ["pid", "name", "force"],
      "properties": {
        "pid": { "description": "The process's id.", "type": "integer" },
        "name": {
          "description": "The process's name, shown if the app has to ask for an administrator password.",
          "type": "string"
        },
        "force": { "description": "True to end it at once; false to ask it to quit.", "type": "boolean" }
      }
    },
    "storageGetParams": {
      "description": "Read one of the preferences the manifest declares.",
      "type": "object",
      "required": ["key"],
      "properties": { "key": {"description": "The preference's id.", "type": "string"} }
    },
    "storageGetResult": {
      "description": "The preference's value.",
      "type": "object",
      "required": ["value"],
      "properties": {
        "value": {
          "description": "The saved value, or the manifest's default when nothing is saved.",
          "type": ["string", "boolean", "number"]
        }
      }
    },
    "storageSetParams": {
      "description": "Save one of the preferences the manifest declares.",
      "type": "object",
      "required": ["key", "value"],
      "properties": {
        "key": { "description": "The preference's id.", "type": "string" },
        "value": {
          "description": "The new value, of the type the manifest names.",
          "type": ["string", "boolean", "number"]
        }
      }
    },
    "logParams": {
      "description": "A line for the tool's log in Settings.",
      "type": "object",
      "required": ["message"],
      "properties": { "message": {"description": "The line.", "type": "string"} }
    }
  }
}
```

- [ ] **Step 4: Run the test**

Run: `bazel test //packages/vitruvian-sdk:protocol_examples_test --test_output=errors`
Expected: PASS, printing `protocol examples: OK`.

If it fails to load with an error about `rpds` or a missing wheel on the Mac, `jsonschema`'s compiled dependency has no wheel for this runner. Run it on Linux only: add `target_compatible_with = ["@platforms//os:linux"]` to the target, take it out of the pipeline unit's `test_targets`, and record the deviation. The Linux `build-test` job in `ci.yaml` still runs it, because it tests every affected target that is not `manual`.

- [ ] **Step 5: Prove the test sees drift**

One at a time, make each change, run the test, confirm it FAILS with the message given, and undo the change by hand (not with `git checkout` or `git stash`; the files are not committed yet):

1. In `messages.schema.json`, give `openURLParams` a second property, `"inBackground": { "type": "boolean" }`. Expected: `no valid example uses openURLParams.inBackground`.
2. In `messages.schema.json`, remove `"language"` from `initializeParams`'s `required`. Expected: `message 'initialize with no language': the schema says True, the example False`.
3. In `methods.json`, delete the last row. Expected: `methods.json names no message that carries logParams`.
4. In `manifest.schema.json`, add `"hotkey"` to the list under `uses`. Expected: `manifest 'a service built-in tools have and version 1 does not offer': the schema says True, the example False`.

- [ ] **Step 6: Describe it in plain words**

Create `packages/vitruvian-sdk/protocol/README.md`:

````markdown
# The Vitruvian tool protocol, version 1

A tool is a program the Vitruvian app starts and talks to. This folder says
how they talk. It is the source of truth: the Swift types in
`../Sources/VitruvianToolProtocol` and the script in `../conformance` are
written to match it, and tests fail when they stop matching.

| File | What it is |
|---|---|
| `manifest.schema.json` | `vitruvian-tool.json`, the file at the top of a tool's folder |
| `messages.schema.json` | one message, and what each message carries |
| `methods.json` | every message: who sends it, whether it is answered, what it needs |
| `examples/` | manifests and messages, valid and not, that both sides are tested against |

Every field has a description in its schema. This page is the overview.

## The link

The app starts the tool's program in a folder the tool may keep files in. The
program's standard input and standard output are the link. Its standard error
is its log.

- One message per line, in UTF-8. A line ends with a line break (`\n`) and
  has none inside it. JSON never needs one: inside a string it is written `\n`.
- A line is at most 1,048,576 bytes, not counting its line break.
- An empty line is ignored. Anything else that is not a message is an error.
- The tool's standard output carries nothing but messages. Print to standard
  error instead.

## A message

A message is JSON-RPC 2.0. There are four kinds.

```json
{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"copyLatest"}}
{"jsonrpc":"2.0","method":"commands/state","params":{"runnable":["copyLatest"]}}
{"jsonrpc":"2.0","id":2,"result":{}}
{"jsonrpc":"2.0","id":2,"error":{"code":-32010,"message":"command refused"}}
```

- A **request** has an `id` and is answered, with a **result** or a
  **failure** that carries the same `id`.
- A **notice** has no `id` and is not answered.
- An `id` is a whole number or a string. Whoever sends the request picks it.
- `params` is always an object. A message that carries nothing leaves it out.
- A request that was simply done is answered with `{}`.
- A field you do not know is ignored. That is how a later version adds one.
  A request you do not know is answered with failure -32601. A notice you do
  not know is ignored.

## What the app sends

| Message | Kind | Meaning |
|---|---|---|
| `initialize` | request | The first message. It carries the protocol versions the app speaks, the language in use and the tool's data folder. The tool answers with the version it picked and its own version. Until it has, neither side sends anything else. |
| `command/run` | request | Run this command. `command` is the id the manifest gives it. Answer `{}` when it ran, or failure -32010 when you will not run it. |
| `preferences/changed` | notice | These preferences have new values. |
| `language/changed` | notice | The person changed the app's language. |
| `shutdown` | notice | Stop. The app then closes the tool's input. The tool exits with 0 within two seconds. |

## What a tool sends

A tool may do any of this itself. It is a separate program with everything the
app has. These messages are for what is better done through the app.

| Message | Kind | In `uses` | Meaning |
|---|---|---|---|
| `commands/state` | notice | | Which commands can run now. Send it whenever that changes. Until the first one, all of them can. |
| `notify/hud` | request | `notify` | Show the app's short on-screen message, with a symbol. |
| `notify/beep` | request | `notify` | The alert sound. |
| `open/url` | request | `open` | Open a link. |
| `clipboard/readText` | request | `clipboard.read` | The clipboard's text. |
| `clipboard/writeText` | request | `clipboard.write` | Replace the clipboard with this text, marked as Vitruvian's so clipboard history files it correctly. |
| `keystrokes/paste` | request | `keystrokes` | Paste this text into the app in front. |
| `keystrokes/pressMenuItem` | request | `keystrokes` | Press the menu item with one of these key equivalents in the app in front. |
| `processes/terminate` | request | `processes` | End this process, with the app's checks and its administrator prompt. |
| `storage/get`, `storage/set` | request | `storage` | Read or write one of the preferences the manifest declares. |
| `log` | notice | | A line for the tool's log in Settings. |

## Being refused

Any request can be refused. A refusal is a failure with one of these codes.

| Code | Who | Meaning |
|---|---|---|
| -32001 | app | The service is not listed in the tool's `uses`. `data.service` names it. |
| -32002 | app | The tool is not installed. |
| -32003 | app | Vitruvian lacks a macOS permission the service needs. `data.permission` names it. |
| -32004 | app | Not available right now. |
| -32010 | tool | The tool will not run the command. |

The other codes are JSON-RPC's own: -32700 not JSON, -32600 not a message,
-32601 unknown method, -32602 wrong params, -32603 something broke inside.

A failure's `message` is a few English words for a log. It is never shown to
the person as it is.

## The manifest

`vitruvian-tool.json` says what the tool is. `id`, `name`, `version`,
`protocol`, `publisher` and `runtime` are required.

- **The id has a dot** (`com.acme.deploys`) and is at most 128 characters.
- **Text is a map of languages**, `{ "en": "Deploys", "fr": "Déploiements" }`.
  English is required. It is shown as written.
- **`uses` lists the app services the tool calls.** It is not a list of what
  the tool is allowed to do.
- **A name the app does not know refuses the tool**: a service, a surface, a
  kind of preference, a way of starting. The reason names it.
- **`runtime.exec` stays inside the folder.**
- **Limits**: the file 65,536 bytes, 32 commands, 16 preferences.

## Changing the protocol

A new message or field needs no new version when an old tool or an old app can
ignore it. Anything an old one would misread needs version 2.

A change is three things in one commit: the schema, the Swift type, and an
example in `examples/`. The tests hold the three together, and they can only
see a difference an example crosses.
````

- [ ] **Step 7: Format, regenerate, and commit**

```sh
bazel run //tools/format -- packages/vitruvian-sdk/BUILD packages/vitruvian-sdk/protocol/protocol_examples_test.py
bazel run //tools/license:check
bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
bazel test //packages/vitruvian-sdk:protocol_examples_test
```

Expected: the test still passes after formatting, and the generated job's `bazel test` line now names both targets.

```bash
git add packages/vitruvian-sdk/BUILD packages/vitruvian-sdk/protocol .github/workflows/presubmit.yaml
git commit -m "chore(vitruvian-sdk): the tool protocol as JSON Schema, with examples"
```

---

### Task 3: The messages, as Swift

Works in `packages/vitruvian-sdk/`.

**Files:**
- Create: `Sources/VitruvianToolProtocol/Messages.swift`
- Create: `Tests/VitruvianToolProtocolTests/ProtocolFiles.swift`, `Tests/VitruvianToolProtocolTests/ProtocolExamplesTests.swift`

**Interfaces:**
- Consumes: Task 1's `JSONValue`, `RPCMessage`, `RPCErrorObject`, `LineFraming`; Task 2's `protocol/methods.json`, `protocol/messages.schema.json`, `protocol/examples/messages.json`.
- Produces:
  - `ProtocolVersion.current`, `ProtocolVersion.supported`
  - `AppService` (seven cases; raw values are the names in `uses`)
  - `ToolMethod` (seventeen cases; `sender`, `isAnswered`, `service`)
  - `RefusalCode` (five cases; `message`, `error(service:permission:)`, `init?(_:)`), `RefusalData`
  - `EmptyObject`, and one struct for each message's params and result: `InitializeParams`, `InitializeResult`, `CommandRunParams`, `PreferencesChangedParams`, `LanguageChangedParams`, `CommandsStateParams`, `NotifyHUDParams`, `OpenURLParams`, `OpenURLResult`, `ClipboardReadTextResult`, `ClipboardWriteTextParams`, `ClipboardWriteTextResult`, `KeystrokesPasteParams`, `KeyEquivalent`, `KeystrokesPressMenuItemParams`, `KeystrokesPressMenuItemResult`, `ProcessesTerminateParams`, `StorageGetParams`, `StorageGetResult`, `StorageSetParams`, `LogParams`
  - test support: `ProtocolFiles.data(_:)`, `ProtocolFiles.json(_:)`, `ProtocolFiles.fields(of:)`, `ProtocolFiles.fields(declaredBy:)`

Each type's stored properties are spelled exactly as the field is on the wire, so no type needs coding keys, and a test can compare a type's fields with its schema's by reflection.

How each message lines up with what the broker does for a built-in tool today. Stage B writes the code on the right; nothing here calls it.

| Message | The broker's operation |
|---|---|
| `notify/hud`, `notify/beep` | `NotifyAccess.hud(icon:message:)`, `beep()` |
| `open/url` | `OpenAccess.url(_:)`, whose `Bool` is `opened` |
| `clipboard/readText` | `ClipboardAccess.readText(completion:)`; no text is a result with no `text` |
| `clipboard/writeText` | `ClipboardAccess.write(_:completion:)`, whose `Bool` is `written` |
| `keystrokes/paste` | `KeystrokesAccess.paste(_:)` |
| `keystrokes/pressMenuItem` | `KeystrokesAccess.pressFrontAppMenuItem(matching:)`; a `KeyEquivalent`'s modifier names become `MenuKeyEquivalent.modifierMask` (shift 1, option 2, control 4) |
| `processes/terminate` | `ProcessesAccess.terminate(pid:name:startedAt:force:completion:)`; the app supplies `startedAt` |
| `storage/get`, `storage/set` | `StorageAccess.reader()`; writing does not exist yet |
| a failure with a `RefusalCode` | `BrokerRefusal`: `notDeclared` is -32001, `notInstalled` -32002, `notGranted` -32003, `unavailable` -32004 |

- [ ] **Step 1: Write the failing tests**

Create `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ProtocolFiles.swift`:

```swift
// MIT-HEADER

import XCTest

import VitruvianToolProtocol

/// The files under `protocol/` and `conformance/`, as the tests read them.
enum ProtocolFiles {
    /// A file of the package, by its path from the package's folder. Bazel
    /// puts it among the test's runfiles; SwiftPM and Xcode find it beside
    /// the sources. A file that cannot be found fails the test.
    static func data(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/packages/vitruvian-sdk/\(path)")
            }
        }
        // Outside Bazel: this file is three folders below the package.
        var package = URL(fileURLWithPath: "\(file)")
        for _ in 0..<3 { package.deleteLastPathComponent() }
        candidates.append(package.appendingPathComponent(path).path)
        for candidate in candidates {
            if let data = FileManager.default.contents(atPath: candidate) { return data }
        }
        XCTFail("\(path) is missing; looked in \(candidates)", file: file, line: line)
        return Data()
    }

    static func json(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> JSONValue {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data(path, file: file, line: line)) else {
            XCTFail("\(path) is not JSON", file: file, line: line)
            return .null
        }
        return value
    }

    /// The names of the fields a value of a Swift type holds.
    static func fields(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// The names of the fields a schema's definition declares.
    static func fields(declaredBy definition: JSONValue?) -> Set<String> {
        Set((definition?["properties"]?.objectValue ?? [:]).keys)
    }
}
```

Create `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ProtocolExamplesTests.swift`:

```swift
// MIT-HEADER

import XCTest

import VitruvianToolProtocol

/// The Swift types, held to the schemas. `protocol/protocol_examples_test.py`
/// checks the same example files against the schemas themselves, so an
/// example both sides agree on is a message they read alike.
final class ProtocolExamplesTests: XCTestCase {
    /// Reads `value` as `type` and writes it back.
    private static func again<Shape: Codable>(_ value: JSONValue, as type: Shape.Type) throws -> JSONValue {
        try JSONValue(encoding: value.decode(type))
    }

    /// A message's params, read as the type that message carries.
    private static func params(_ method: ToolMethod, _ value: JSONValue) throws -> JSONValue {
        switch method {
        case .initialize: return try again(value, as: InitializeParams.self)
        case .commandRun: return try again(value, as: CommandRunParams.self)
        case .preferencesChanged: return try again(value, as: PreferencesChangedParams.self)
        case .languageChanged: return try again(value, as: LanguageChangedParams.self)
        case .commandsState: return try again(value, as: CommandsStateParams.self)
        case .notifyHUD: return try again(value, as: NotifyHUDParams.self)
        case .openURL: return try again(value, as: OpenURLParams.self)
        case .clipboardWriteText: return try again(value, as: ClipboardWriteTextParams.self)
        case .keystrokesPaste: return try again(value, as: KeystrokesPasteParams.self)
        case .keystrokesPressMenuItem: return try again(value, as: KeystrokesPressMenuItemParams.self)
        case .processesTerminate: return try again(value, as: ProcessesTerminateParams.self)
        case .storageGet: return try again(value, as: StorageGetParams.self)
        case .storageSet: return try again(value, as: StorageSetParams.self)
        case .log: return try again(value, as: LogParams.self)
        case .shutdown, .notifyBeep, .clipboardReadText: return try again(value, as: EmptyObject.self)
        }
    }

    /// A request's result, read as the type that request is answered with.
    /// Nil for a notice, which has no answer.
    private static func result(_ method: ToolMethod, _ value: JSONValue) throws -> JSONValue? {
        switch method {
        case .initialize: return try again(value, as: InitializeResult.self)
        case .openURL: return try again(value, as: OpenURLResult.self)
        case .clipboardReadText: return try again(value, as: ClipboardReadTextResult.self)
        case .clipboardWriteText: return try again(value, as: ClipboardWriteTextResult.self)
        case .keystrokesPressMenuItem: return try again(value, as: KeystrokesPressMenuItemResult.self)
        case .storageGet: return try again(value, as: StorageGetResult.self)
        case .commandRun, .notifyHUD, .notifyBeep, .keystrokesPaste, .processesTerminate, .storageSet:
            return try again(value, as: EmptyObject.self)
        case .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log:
            return nil
        }
    }

    /// One value of each type a message carries, under the name of its
    /// definition in `messages.schema.json`.
    private static let shapes: [(String, Any)] = [
        ("error", RPCErrorObject(code: 0, message: "")),
        ("refusalData", RefusalData()),
        ("empty", EmptyObject()),
        ("initializeParams", InitializeParams(protocolVersions: [], language: "", dataFolder: "")),
        ("initializeResult", InitializeResult(protocolVersion: "", toolVersion: "")),
        ("commandRunParams", CommandRunParams(command: "")),
        ("preferencesChangedParams", PreferencesChangedParams(values: [:])),
        ("languageChangedParams", LanguageChangedParams(language: "")),
        ("commandsStateParams", CommandsStateParams(runnable: [])),
        ("notifyHUDParams", NotifyHUDParams(icon: "", message: "")),
        ("openURLParams", OpenURLParams(url: "")),
        ("openURLResult", OpenURLResult(opened: false)),
        ("clipboardReadTextResult", ClipboardReadTextResult(text: nil)),
        ("clipboardWriteTextParams", ClipboardWriteTextParams(text: "")),
        ("clipboardWriteTextResult", ClipboardWriteTextResult(written: false)),
        ("keystrokesPasteParams", KeystrokesPasteParams(text: "")),
        ("keystrokesPressMenuItemParams", KeystrokesPressMenuItemParams(equivalents: [])),
        ("keyEquivalent", KeyEquivalent(character: "", modifiers: [])),
        ("keystrokesPressMenuItemResult", KeystrokesPressMenuItemResult(pressed: false)),
        ("processesTerminateParams", ProcessesTerminateParams(pid: 0, name: "", force: false)),
        ("storageGetParams", StorageGetParams(key: "")),
        ("storageGetResult", StorageGetResult(value: .null)),
        ("storageSetParams", StorageSetParams(key: "", value: .null)),
        ("logParams", LogParams(message: "")),
    ]

    /// The definitions that are the message itself, read by `RPCMessage`.
    private static let envelopes: Set<String> = ["id", "request", "notice", "result", "failure"]

    func testTheMethodTableIsTheSchemasTable() {
        let rows = ProtocolFiles.json("protocol/methods.json")["methods"]?.arrayValue ?? []
        XCTAssertEqual(rows.compactMap { $0["method"]?.stringValue }, ToolMethod.allCases.map(\.rawValue),
                       "the same messages, in the same order")
        for row in rows {
            guard let name = row["method"]?.stringValue, let method = ToolMethod(rawValue: name) else { continue }
            XCTAssertEqual(row["sender"]?.stringValue, method.sender.rawValue, name)
            XCTAssertEqual(row["kind"]?.stringValue, method.isAnswered ? "request" : "notice", name)
            XCTAssertEqual(row["uses"]?.stringValue, method.service?.rawValue, name)
        }
        XCTAssertEqual(ProtocolFiles.json("protocol/methods.json")["protocol"]?.stringValue, ProtocolVersion.current)
    }

    func testEachTypeHasTheFieldsItsDefinitionDeclares() {
        let definitions = ProtocolFiles.json("protocol/messages.schema.json")["$defs"]
        for (name, value) in Self.shapes {
            XCTAssertEqual(ProtocolFiles.fields(of: value), ProtocolFiles.fields(declaredBy: definitions?[name]), name)
        }
        XCTAssertEqual(Set(Self.shapes.map(\.0)).union(Self.envelopes), Set((definitions?.objectValue ?? [:]).keys),
                       "every definition has a Swift type, and every type a definition")
        let modifiers = definitions?["keyEquivalent"]?["properties"]?["modifiers"]?["items"]?["enum"]?.arrayValue
        XCTAssertEqual(modifiers?.compactMap(\.stringValue), KeyEquivalent.Modifier.allCases.map(\.rawValue))
    }

    func testEveryExampleIsReadAsTheSchemaReadsIt() throws {
        let examples = ProtocolFiles.json("protocol/examples/messages.json")["examples"]?.arrayValue ?? []
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let about = example["about"]?.stringValue ?? "?"
            let valid = example["valid"]?.boolValue ?? false
            do {
                try Self.read(example)
                XCTAssertTrue(valid, "\(about): the schema refuses it and the Swift types read it")
            } catch {
                XCTAssertFalse(valid, "\(about): the schema accepts it and the Swift types do not: \(error)")
            }
        }
    }

    /// Reads one example as the app or a tool would, and throws where it
    /// cannot be read. A valid example must also come back as it went in.
    private static func read(_ example: JSONValue) throws {
        struct Changed: Error {
            let from: JSONValue
            let to: JSONValue
        }
        // What a type reads and writes back is what it was given, unless
        // the example carries a field version 1 does not have.
        func same(_ written: JSONValue, _ given: JSONValue) throws {
            if example["unknownFields"]?.boolValue != true, written != given {
                throw Changed(from: given, to: written)
            }
        }
        let original = example["message"] ?? .null
        let message = try LineFraming.message(from: JSONEncoder().encode(original))
        let written = try JSONValue(encoding: message)
        if written != original { throw Changed(from: original, to: written) }
        switch message {
        case .request(_, let name, let params), .notice(let name, let params):
            // A method version 1 does not have is still a message.
            guard let method = ToolMethod(rawValue: name) else { return }
            let carried = params ?? .object([:])
            try same(Self.params(method, carried), carried)
        case .result(_, let value):
            guard let method = (example["answers"]?.stringValue).flatMap(ToolMethod.init(rawValue:)),
                  let answered = try Self.result(method, value) else { return }
            try same(answered, value)
        case .failure(_, let error):
            guard let refusal = RefusalCode(error), refusal == .notInUses || refusal == .permissionMissing,
                  let data = error.data else { return }
            try same(Self.again(data, as: RefusalData.self), data)
        }
    }

    func testARefusalIsAFailureWithItsCode() {
        XCTAssertEqual(RefusalCode.allCases.map(\.rawValue), [-32001, -32002, -32003, -32004, -32010])
        let missing = RefusalCode.permissionMissing.error(permission: "accessibility")
        XCTAssertEqual(missing.code, -32003)
        XCTAssertEqual(missing.data, .object(["permission": .string("accessibility")]))
        XCTAssertEqual(RefusalCode(missing), .permissionMissing)
        XCTAssertEqual(RefusalCode.notInUses.error(service: .clipboardWrite).data,
                       .object(["service": .string("clipboard.write")]))
        XCTAssertNil(RefusalCode.unavailable.error().data)
        XCTAssertNil(RefusalCode(RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "method not found")))
        XCTAssertEqual(Set(RefusalCode.allCases.map(\.message)).count, RefusalCode.allCases.count)
    }

    func testEveryServiceAMessageNeedsIsOneAManifestMayList() {
        XCTAssertEqual(Set(ToolMethod.allCases.compactMap(\.service)), Set(AppService.allCases))
        XCTAssertEqual(ToolMethod.allCases.filter { $0.sender == .app }.map(\.rawValue),
                       ["initialize", "command/run", "preferences/changed", "language/changed", "shutdown"])
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests`
Expected: FAIL to compile, with "cannot find 'ToolMethod' in scope" among the errors.

- [ ] **Step 3: Write the messages**

Create `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/Messages.swift`:

```swift
// MIT-HEADER

import Foundation

/// The versions of the protocol this library speaks.
public enum ProtocolVersion {
    public static let current = "1"
    public static let supported = [current]
}

/// An app service a tool may call. A tool's manifest lists the ones it
/// calls in `uses`, by these names.
public enum AppService: String, CaseIterable, Sendable {
    case notify
    case open
    case clipboardRead = "clipboard.read"
    case clipboardWrite = "clipboard.write"
    case keystrokes
    case processes
    case storage
}

/// Every message of protocol version 1, by its name on the link.
/// `protocol/methods.json` is the same table, and a test holds the two
/// together.
public enum ToolMethod: String, CaseIterable, Sendable {
    case initialize
    case commandRun = "command/run"
    case preferencesChanged = "preferences/changed"
    case languageChanged = "language/changed"
    case shutdown
    case commandsState = "commands/state"
    case notifyHUD = "notify/hud"
    case notifyBeep = "notify/beep"
    case openURL = "open/url"
    case clipboardReadText = "clipboard/readText"
    case clipboardWriteText = "clipboard/writeText"
    case keystrokesPaste = "keystrokes/paste"
    case keystrokesPressMenuItem = "keystrokes/pressMenuItem"
    case processesTerminate = "processes/terminate"
    case storageGet = "storage/get"
    case storageSet = "storage/set"
    case log

    public enum Sender: String, Sendable {
        case app, tool
    }

    /// Who sends it.
    public var sender: Sender {
        switch self {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown:
            return .app
        case .commandsState, .notifyHUD, .notifyBeep, .openURL, .clipboardReadText, .clipboardWriteText,
             .keystrokesPaste, .keystrokesPressMenuItem, .processesTerminate, .storageGet, .storageSet, .log:
            return .tool
        }
    }

    /// True for a request, which is answered; false for a notice.
    public var isAnswered: Bool {
        switch self {
        case .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log:
            return false
        case .initialize, .commandRun, .notifyHUD, .notifyBeep, .openURL, .clipboardReadText,
             .clipboardWriteText, .keystrokesPaste, .keystrokesPressMenuItem, .processesTerminate, .storageGet,
             .storageSet:
            return true
        }
    }

    /// The service the tool's manifest must list in `uses` before the app
    /// will do this; nil when it needs none.
    public var service: AppService? {
        switch self {
        case .initialize, .commandRun, .preferencesChanged, .languageChanged, .shutdown, .commandsState, .log:
            return nil
        case .notifyHUD, .notifyBeep: return .notify
        case .openURL: return .open
        case .clipboardReadText: return .clipboardRead
        case .clipboardWriteText: return .clipboardWrite
        case .keystrokesPaste, .keystrokesPressMenuItem: return .keystrokes
        case .processesTerminate: return .processes
        case .storageGet, .storageSet: return .storage
        }
    }
}

/// Why a request was refused, as the code of its failure.
public enum RefusalCode: Int, CaseIterable, Sendable {
    /// The app: the service is not listed in the tool's `uses`.
    case notInUses = -32001
    /// The app: the tool is not installed.
    case notInstalled = -32002
    /// The app: Vitruvian lacks a macOS permission the service needs.
    case permissionMissing = -32003
    /// The app: not available right now.
    case unavailable = -32004
    /// The tool: it would not run the command.
    case commandRefused = -32010

    /// A few English words for a log.
    public var message: String {
        switch self {
        case .notInUses: return "not listed in uses"
        case .notInstalled: return "tool not installed"
        case .permissionMissing: return "Vitruvian lacks a macOS permission"
        case .unavailable: return "not available right now"
        case .commandRefused: return "command refused"
        }
    }

    /// The failure that says so. `service` goes with `notInUses`, and
    /// `permission` with `permissionMissing`.
    public func error(service: AppService? = nil, permission: String? = nil) -> RPCErrorObject {
        var fields: [String: JSONValue] = [:]
        if let service { fields["service"] = .string(service.rawValue) }
        if let permission { fields["permission"] = .string(permission) }
        return RPCErrorObject(code: rawValue, message: message, data: fields.isEmpty ? nil : .object(fields))
    }

    /// The refusal a failure carries; nil for any other failure.
    public init?(_ error: RPCErrorObject) {
        self.init(rawValue: error.code)
    }
}

/// What a refusal names, in a failure's `data`.
public struct RefusalData: Codable, Equatable, Sendable {
    /// With `notInUses`: the entry missing from the tool's `uses`.
    public let service: String?
    /// With `permissionMissing`: the macOS permission Vitruvian lacks.
    public let permission: String?

    public init(service: String? = nil, permission: String? = nil) {
        self.service = service
        self.permission = permission
    }
}

/// Nothing to say: `{}`. The params of a message that carries none, and the
/// result of a request that was simply done.
public struct EmptyObject: Codable, Equatable, Sendable {
    private struct NoKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init() {}

    public init(from decoder: any Decoder) throws {
        _ = try decoder.container(keyedBy: NoKey.self)
    }

    public func encode(to encoder: any Encoder) throws {
        _ = encoder.container(keyedBy: NoKey.self)
    }
}

// MARK: - What the app sends

public struct InitializeParams: Codable, Equatable, Sendable {
    /// The protocol versions the app speaks.
    public let protocolVersions: [String]
    /// The language the app is in, as a tag such as `en-US`.
    public let language: String
    /// The folder the tool may keep its own files in.
    public let dataFolder: String

    public init(protocolVersions: [String], language: String, dataFolder: String) {
        self.protocolVersions = protocolVersions
        self.language = language
        self.dataFolder = dataFolder
    }
}

public struct InitializeResult: Codable, Equatable, Sendable {
    /// The one version, of those offered, the tool will speak.
    public let protocolVersion: String
    public let toolVersion: String

    public init(protocolVersion: String, toolVersion: String) {
        self.protocolVersion = protocolVersion
        self.toolVersion = toolVersion
    }
}

public struct CommandRunParams: Codable, Equatable, Sendable {
    /// The command's id as the manifest writes it, without the tool's id.
    public let command: String

    public init(command: String) {
        self.command = command
    }
}

public struct PreferencesChangedParams: Codable, Equatable, Sendable {
    /// Each changed preference's id and its new value.
    public let values: [String: JSONValue]

    public init(values: [String: JSONValue]) {
        self.values = values
    }
}

public struct LanguageChangedParams: Codable, Equatable, Sendable {
    public let language: String

    public init(language: String) {
        self.language = language
    }
}

// MARK: - What a tool sends

public struct CommandsStateParams: Codable, Equatable, Sendable {
    /// The ids of the commands that can run now. One not listed cannot.
    public let runnable: [String]

    public init(runnable: [String]) {
        self.runnable = runnable
    }
}

public struct NotifyHUDParams: Codable, Equatable, Sendable {
    /// An SF Symbol name.
    public let icon: String
    public let message: String

    public init(icon: String, message: String) {
        self.icon = icon
        self.message = message
    }
}

public struct OpenURLParams: Codable, Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct OpenURLResult: Codable, Equatable, Sendable {
    public let opened: Bool

    public init(opened: Bool) {
        self.opened = opened
    }
}

public struct ClipboardReadTextResult: Codable, Equatable, Sendable {
    /// Nil when the clipboard holds no text.
    public let text: String?

    public init(text: String?) {
        self.text = text
    }
}

public struct ClipboardWriteTextParams: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct ClipboardWriteTextResult: Codable, Equatable, Sendable {
    public let written: Bool

    public init(written: Bool) {
        self.written = written
    }
}

public struct KeystrokesPasteParams: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// A menu item's key equivalent. Command is always part of it.
public struct KeyEquivalent: Codable, Equatable, Sendable {
    /// The names `modifiers` may hold.
    public enum Modifier: String, CaseIterable, Sendable {
        case shift, option, control
    }

    /// The key, as the menu shows it.
    public let character: String
    /// The keys held with Command, by `Modifier` name.
    public let modifiers: [String]

    public init(character: String, modifiers: [String]) {
        self.character = character
        self.modifiers = modifiers
    }
}

public struct KeystrokesPressMenuItemParams: Codable, Equatable, Sendable {
    /// The key equivalents that count.
    public let equivalents: [KeyEquivalent]

    public init(equivalents: [KeyEquivalent]) {
        self.equivalents = equivalents
    }
}

public struct KeystrokesPressMenuItemResult: Codable, Equatable, Sendable {
    public let pressed: Bool

    public init(pressed: Bool) {
        self.pressed = pressed
    }
}

public struct ProcessesTerminateParams: Codable, Equatable, Sendable {
    public let pid: Int
    public let name: String
    /// True to end it at once; false to ask it to quit.
    public let force: Bool

    public init(pid: Int, name: String, force: Bool) {
        self.pid = pid
        self.name = name
        self.force = force
    }
}

public struct StorageGetParams: Codable, Equatable, Sendable {
    /// The preference's id, as the manifest writes it.
    public let key: String

    public init(key: String) {
        self.key = key
    }
}

public struct StorageGetResult: Codable, Equatable, Sendable {
    public let value: JSONValue

    public init(value: JSONValue) {
        self.value = value
    }
}

public struct StorageSetParams: Codable, Equatable, Sendable {
    public let key: String
    public let value: JSONValue

    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public struct LogParams: Codable, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests --test_output=errors`
Expected: PASS, fifteen tests in three classes.

If `testEveryExampleIsReadAsTheSchemaReadsIt` reports "the schema accepts it and the Swift types do not" with a `Changed` error, the type read the example and wrote back something else. The error holds both values. A number written back as text of another kind, or a field dropped, is a real difference between the type and the schema: fix the type, not the example.

- [ ] **Step 5: Prove the tests see drift**

One at a time, make each change, run the test, confirm it FAILS in the test named, and undo it by hand so that `git diff --stat` shows only this task's new files:

1. In `Messages.swift`, rename `OpenURLResult.opened` to `didOpen` (the property, its initializer parameter and the assignment). Expected: `testEachTypeHasTheFieldsItsDefinitionDeclares` fails for `openURLResult`, and `testEveryExampleIsReadAsTheSchemaReadsIt` for "the link was opened".
2. In `Messages.swift`, move `.notifyBeep` from the `true` arm of `isAnswered` to the `false` arm. Expected: `testTheMethodTableIsTheSchemasTable` fails for `notify/beep`.
3. In `protocol/messages.schema.json`, give `logParams` a second property, `"level": { "type": "string" }`. Expected: `testEachTypeHasTheFieldsItsDefinitionDeclares` fails for `logParams`. (The Python test fails too, for want of an example.)

- [ ] **Step 6: Commit**

```sh
bazel run //tools/license:check
bazel run //tools/license:verify
```

```bash
git add packages/vitruvian-sdk/Sources/VitruvianToolProtocol/Messages.swift packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ProtocolFiles.swift packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ProtocolExamplesTests.swift
git commit -m "chore(vitruvian-sdk): every protocol message as a Swift type, held to its schema"
```

---

### Task 4: The manifest, as Swift, with its rules

Works in `packages/vitruvian-sdk/`.

**Files:**
- Create: `Sources/VitruvianToolProtocol/ToolManifestFile.swift`
- Create: `Tests/VitruvianToolProtocolTests/ManifestFileTests.swift`

**Interfaces:**
- Consumes: `JSONValue`, `AppService`, `ProtocolVersion`; `protocol/manifest.schema.json`, `protocol/examples/manifests.json`; `ProtocolFiles`.
- Produces:
  - `ManifestLimits` (`maxBytes`, `maxCommands`, `maxPreferences`, `maxNameLength`)
  - `LocalizedText` (`byLanguage`, `english`, `text(for:)`)
  - `SurfaceName`, `ActivationName`, `PreferenceKind` (`accepts(_:)`)
  - `ToolManifestFile` with `Contributes`, `Command`, `Preference`, `Runtime`; `fileName`, `externalRuntime`; `read(_:) -> Result<ToolManifestFile, ManifestProblem>`; `problems()`
  - `ManifestProblem` (twenty-two cases, each carrying the value it is about)
  - `ManifestRules.isWellFormedName(_:)`, `ManifestRules.staysInsideFolder(_:)`

Every rule of spec section 6 that can be judged from the file alone is here, and each is an example in `protocol/examples/manifests.json`:

| Rule in the spec | The problem it gives |
|---|---|
| The id has a dot and is at most 128 characters | `idWithoutDot`, `idNotWellFormed` |
| Unknown fields are ignored | none: the types have no field for them |
| An unknown service, surface or preference type refuses, named | `unknownService`, `unknownSurface`, `unknownPreferenceType` |
| `exec` stays inside the folder | `programLeavesFolder` (by its text; Task 6 adds the folder) |
| The icon is an SF Symbol name | none: an icon never refuses (decision 11) |
| The manifest 64 KB, 32 commands, 16 preferences | `tooLarge`, `tooManyCommands`, `tooManyPreferences` |
| English is required (spec decision 10) | `noEnglish`, `blankText` |

The rest are what the types force: a file that is not JSON or lacks a field (`notJSON`, `malformed`), a protocol or runtime this version does not have (`unsupportedProtocol`, `unsupportedRuntime`), a way of starting it does not have (`unknownActivation`), a name written twice (`duplicateService`, `duplicateCommand`, `duplicatePreference`), an id that is not well formed (`commandNotWellFormed`, `preferenceNotWellFormed`), and a default that is not of its type (`defaultOfWrongType`).

- [ ] **Step 1: Write the failing tests**

Create `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ManifestFileTests.swift`:

```swift
// MIT-HEADER

import XCTest

import VitruvianToolProtocol

/// The manifest's Swift type and its rules, held to `manifest.schema.json`
/// through the examples both read.
final class ManifestFileTests: XCTestCase {
    private var file: JSONValue { ProtocolFiles.json("protocol/examples/manifests.json") }

    /// The example manifest with some top-level fields replaced. A field
    /// replaced by null is left out.
    private func manifest(changing change: [String: JSONValue] = [:]) -> Data {
        var fields = file["base"]?.objectValue ?? [:]
        for (key, value) in change {
            fields[key] = value == .null ? nil : value
        }
        return (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
    }

    private func problem(_ change: [String: JSONValue]) -> ManifestProblem? {
        if case .failure(let problem) = ToolManifestFile.read(manifest(changing: change)) { return problem }
        return nil
    }

    /// The name of a problem's case, without what it carries.
    private func caseName(_ problem: ManifestProblem) -> String {
        Mirror(reflecting: problem).children.first?.label ?? String(describing: problem)
    }

    func testEveryExampleIsJudgedAsTheSchemaJudgesIt() {
        let examples = file["examples"]?.arrayValue ?? []
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let about = example["about"]?.stringValue ?? "?"
            switch ToolManifestFile.read(manifest(changing: example["change"]?.objectValue ?? [:])) {
            case .success:
                XCTAssertEqual(example["valid"], .bool(true), "\(about): refused by the examples, read by Swift")
            case .failure(let problem):
                XCTAssertEqual(example["valid"], .bool(false), "\(about): \(problem)")
                XCTAssertEqual(caseName(problem), example["problem"]?.stringValue, about)
                for name in example["names"]?.arrayValue ?? [] {
                    XCTAssertTrue("\(problem)".contains(name.stringValue ?? "?"), "\(about): \(problem) names \(name)")
                }
            }
        }
    }

    func testTheTypeHasTheFieldsTheSchemaDeclares() throws {
        let schema = ProtocolFiles.json("protocol/manifest.schema.json")
        let read = try ToolManifestFile.read(manifest()).get()
        let command = try XCTUnwrap(read.contributes?.commands?.first)
        let preference = try XCTUnwrap(read.preferences?.first)
        XCTAssertEqual(ProtocolFiles.fields(of: read), ProtocolFiles.fields(declaredBy: schema))
        XCTAssertEqual(ProtocolFiles.fields(of: try XCTUnwrap(read.contributes)),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["contributes"]))
        XCTAssertEqual(ProtocolFiles.fields(of: command), ProtocolFiles.fields(declaredBy: schema["$defs"]?["command"]))
        XCTAssertEqual(ProtocolFiles.fields(of: preference),
                       ProtocolFiles.fields(declaredBy: schema["$defs"]?["preference"]))
        XCTAssertEqual(ProtocolFiles.fields(of: read.runtime), ProtocolFiles.fields(declaredBy: schema["$defs"]?["runtime"]))
        XCTAssertEqual(Set((schema["$defs"]?.objectValue ?? [:]).keys),
                       ["localizedText", "contributes", "command", "preference", "runtime"])
    }

    func testTheListsAreTheSchemasLists() {
        let schema = ProtocolFiles.json("protocol/manifest.schema.json")
        func listed(_ node: JSONValue?) -> [String] {
            (node?["items"]?["enum"]?.arrayValue ?? node?["enum"]?.arrayValue ?? []).compactMap(\.stringValue)
        }
        let command = schema["$defs"]?["command"]?["properties"]
        let preference = schema["$defs"]?["preference"]?["properties"]
        XCTAssertEqual(listed(schema["properties"]?["uses"]), AppService.allCases.map(\.rawValue))
        XCTAssertEqual(listed(schema["properties"]?["activation"]), ActivationName.allCases.map(\.rawValue))
        XCTAssertEqual(listed(command?["surfaces"]), SurfaceName.allCases.map(\.rawValue))
        XCTAssertEqual(listed(preference?["type"]), PreferenceKind.allCases.map(\.rawValue))
        XCTAssertEqual(schema["properties"]?["protocol"]?["const"]?.stringValue, ProtocolVersion.current)
        XCTAssertEqual(schema["$defs"]?["runtime"]?["properties"]?["kind"]?["const"]?.stringValue,
                       ToolManifestFile.externalRuntime)
        XCTAssertEqual(schema["properties"]?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(command?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(preference?["id"]?["maxLength"]?.numberValue, Double(ManifestLimits.maxNameLength))
        XCTAssertEqual(schema["$defs"]?["contributes"]?["properties"]?["commands"]?["maxItems"]?.numberValue,
                       Double(ManifestLimits.maxCommands))
        XCTAssertEqual(schema["properties"]?["preferences"]?["maxItems"]?.numberValue,
                       Double(ManifestLimits.maxPreferences))
    }

    func testTheLimits() {
        XCTAssertEqual(ManifestLimits.maxBytes, 65_536)
        XCTAssertEqual(ManifestLimits.maxCommands, 32)
        XCTAssertEqual(ManifestLimits.maxPreferences, 16)
        XCTAssertEqual(ManifestLimits.maxNameLength, 128)

        func commands(_ count: Int) -> JSONValue {
            .object(["commands": .array((0..<count).map { index in
                .object(["id": .string("c\(index)"), "title": .object(["en": .string("Command \(index)")])])
            })])
        }
        XCTAssertNil(problem(["contributes": commands(32)]))
        XCTAssertEqual(problem(["contributes": commands(33)]), .tooManyCommands(33))

        func preferences(_ count: Int) -> JSONValue {
            .array((0..<count).map { index in
                .object(["id": .string("p\(index)"), "type": .string("boolean"), "default": .bool(false)])
            })
        }
        XCTAssertNil(problem(["preferences": preferences(16)]))
        XCTAssertEqual(problem(["preferences": preferences(17)]), .tooManyPreferences(17))

        let longest = "com." + String(repeating: "a", count: 124)
        XCTAssertNil(problem(["id": .string(longest)]))
        XCTAssertEqual(problem(["id": .string(longest + "a")]), .idNotWellFormed(longest + "a"))

        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let large = manifest(changing: ["description": .object(["en": .string(padding)])])
        XCTAssertEqual(ToolManifestFile.read(large), .failure(.tooLarge(bytes: large.count)))
    }

    func testWhatIsNotAManifestAtAll() {
        XCTAssertEqual(ToolManifestFile.read(Data("not json".utf8)), .failure(.notJSON))
        XCTAssertEqual(ToolManifestFile.read(Data("[]".utf8)), .failure(.notJSON))
        XCTAssertEqual(ToolManifestFile.read(Data()), .failure(.notJSON))
        XCTAssertEqual(problem(["contributes": .object(["commands": .array([.object(["id": .string("a")])])])]),
                       .malformed(field: "contributes.commands[0].title"))
        XCTAssertEqual(problem(["runtime": .object(["kind": .string("external")])]), .malformed(field: "runtime.exec"))
    }

    func testEveryProblemIsListed() {
        let broken = ToolManifestFile.read(manifest(changing: [
            "id": .string("deploys"),
            "uses": .array([.string("camera")]),
            "runtime": .object(["kind": .string("bundled"), "exec": .string("../x")]),
        ]))
        XCTAssertEqual(broken, .failure(.idWithoutDot("deploys")), "the first problem is the one given")
        let all = (try? JSONDecoder().decode(ToolManifestFile.self, from: manifest(changing: [
            "id": .string("deploys"),
            "uses": .array([.string("camera")]),
            "runtime": .object(["kind": .string("bundled"), "exec": .string("../x")]),
        ])))?.problems()
        XCTAssertEqual(all, [.idWithoutDot("deploys"), .unknownService("camera"), .unsupportedRuntime("bundled"),
                             .programLeavesFolder("../x")])
    }

    func testNamesAndPaths() {
        for name in ["a", "copyLatest", "copy.latest", "a-b_c.9", String(repeating: "a", count: 128)] {
            XCTAssertTrue(ManifestRules.isWellFormedName(name), name)
        }
        for name in ["", ".a", "a.", "a..b", "a b", "a/b", "é", String(repeating: "a", count: 129)] {
            XCTAssertFalse(ManifestRules.isWellFormedName(name), name)
        }
        for path in ["deploys", "bin/deploys", "bin/v1.2/deploys", "...", "bin/..deploys"] {
            XCTAssertTrue(ManifestRules.staysInsideFolder(path), path)
        }
        for path in ["", "/bin/deploys", "../deploys", "bin/../deploys", "bin/./deploys", "bin//deploys", "bin/", ".", ".."] {
            XCTAssertFalse(ManifestRules.staysInsideFolder(path), path)
        }
    }

    func testTextIsFoundForALanguage() {
        let text = LocalizedText(["en": "Deploys", "fr": "Déploiements", "pt": "Implantações", "zh-Hans": "部署"])
        XCTAssertEqual(text.text(for: "fr"), "Déploiements")
        XCTAssertEqual(text.text(for: "pt-BR"), "Implantações", "a region falls back to its language")
        XCTAssertEqual(text.text(for: "zh-Hans"), "部署")
        XCTAssertEqual(text.text(for: "zh-TW"), "Deploys", "another script of the language is not a match")
        XCTAssertEqual(text.text(for: "en-US"), "Deploys")
        XCTAssertEqual(text.text(for: "ja"), "Deploys", "anything else is English")
        XCTAssertNil(LocalizedText(["fr": "Déploiements"]).text(for: "de"))
    }

    func testAKindOfPreferenceTakesItsOwnValues() {
        XCTAssertTrue(PreferenceKind.string.accepts(.string("")))
        XCTAssertTrue(PreferenceKind.boolean.accepts(.bool(false)))
        XCTAssertTrue(PreferenceKind.integer.accepts(.number(20)))
        XCTAssertTrue(PreferenceKind.number.accepts(.number(0.5)) && PreferenceKind.number.accepts(.number(3)))
        XCTAssertFalse(PreferenceKind.integer.accepts(.number(1.5)))
        XCTAssertFalse(PreferenceKind.boolean.accepts(.number(1)))
        XCTAssertFalse(PreferenceKind.string.accepts(.null))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests`
Expected: FAIL to compile, with "cannot find 'ToolManifestFile' in scope" among the errors.

- [ ] **Step 3: Write the manifest and its rules**

Create `packages/vitruvian-sdk/Sources/VitruvianToolProtocol/ToolManifestFile.swift`:

```swift
// MIT-HEADER

import Foundation

/// The limits a manifest is held to. They keep the app's lists sane; they
/// are not a safety measure.
public enum ManifestLimits {
    /// The largest manifest file, in bytes: 64 KB.
    public static let maxBytes = 65_536
    public static let maxCommands = 32
    public static let maxPreferences = 16
    /// The longest tool id, command id or preference id, in characters.
    public static let maxNameLength = 128
}

/// A piece of text in one or more languages, keyed by language tag (`en`,
/// `fr`, `pt-BR`). It is shown as the tool wrote it.
public struct LocalizedText: Equatable, Sendable {
    public let byLanguage: [String: String]

    public init(_ byLanguage: [String: String]) {
        self.byLanguage = byLanguage
    }

    public var english: String? { byLanguage["en"] }

    /// The text for a language: its own entry, else the entry for the
    /// language without its region (`pt` for `pt-BR`), else English.
    public func text(for languageTag: String) -> String? {
        if let exact = byLanguage[languageTag] { return exact }
        if let base = languageTag.split(separator: "-").first, let text = byLanguage[String(base)] {
            return text
        }
        return english
    }
}

extension LocalizedText: Codable {
    public init(from decoder: any Decoder) throws {
        byLanguage = try decoder.singleValueContainer().decode([String: String].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(byLanguage)
    }
}

/// Where a command may be offered.
public enum SurfaceName: String, CaseIterable, Sendable {
    case commandBar, radial, quickPanel, shortcut
}

/// When the app starts a tool.
public enum ActivationName: String, CaseIterable, Sendable {
    case onCommand, onLaunch
}

/// The kinds of value a preference may hold.
public enum PreferenceKind: String, CaseIterable, Sendable {
    case string, boolean, integer, number

    /// Whether `value` is of this kind.
    public func accepts(_ value: JSONValue) -> Bool {
        switch (self, value) {
        case (.string, .string), (.boolean, .bool), (.number, .number): return true
        case (.integer, .number(let number)): return Int(exactly: number) != nil
        default: return false
        }
    }
}

/// `vitruvian-tool.json`, as it is written: the file at the top of a tool's
/// folder. `protocol/manifest.schema.json` describes the same file, and a
/// test holds the two together. Lists whose members the app must know
/// (`uses`, surfaces, preference types, activation) are held as the text the
/// file has, so that a name nobody knows can be reported by name.
public struct ToolManifestFile: Codable, Equatable, Sendable {
    public struct Contributes: Codable, Equatable, Sendable {
        public let commands: [Command]?
    }

    public struct Command: Codable, Equatable, Sendable {
        /// The command's name within the tool.
        public let id: String
        public let title: LocalizedText
        /// An SF Symbol name; the tool's icon when left out.
        public let icon: String?
        public let surfaces: [String]?
    }

    public struct Preference: Codable, Equatable, Sendable {
        /// The setting's name within the tool.
        public let id: String
        public let type: String
        public let `default`: JSONValue
    }

    public struct Runtime: Codable, Equatable, Sendable {
        public let kind: String
        /// The program, as a path inside the tool's folder.
        public let exec: String
    }

    public static let fileName = "vitruvian-tool.json"
    public static let externalRuntime = "external"

    public let id: String
    public let name: LocalizedText
    public let description: LocalizedText?
    public let version: String
    public let `protocol`: String
    public let publisher: String
    public let license: String?
    public let icon: String?
    public let uses: [String]?
    public let contributes: Contributes?
    public let preferences: [Preference]?
    public let activation: [String]?
    public let runtime: Runtime
}

/// What is wrong with a manifest. Each case carries what is needed to say
/// which part of the file it is about; the words are the caller's.
public enum ManifestProblem: Error, Equatable, Sendable {
    /// The file is larger than `ManifestLimits.maxBytes`.
    case tooLarge(bytes: Int)
    /// The file is not JSON, or is not a JSON object.
    case notJSON
    /// A field that must be there is missing, or holds the wrong kind of
    /// value. `field` is where: `runtime.exec`, `contributes.commands[0].id`.
    case malformed(field: String)
    case idNotWellFormed(String)
    /// An id with no dot is a built-in feature's.
    case idWithoutDot(String)
    case unsupportedProtocol(String)
    case unsupportedRuntime(String)
    /// A text with no `en` entry.
    case noEnglish(field: String)
    /// A text, or one language of it, that is empty or only spaces.
    case blankText(field: String)
    case unknownService(String)
    case duplicateService(String)
    case unknownActivation(String)
    case tooManyCommands(Int)
    case commandNotWellFormed(String)
    case duplicateCommand(String)
    case unknownSurface(command: String, surface: String)
    case tooManyPreferences(Int)
    case preferenceNotWellFormed(String)
    case duplicatePreference(String)
    case unknownPreferenceType(preference: String, type: String)
    case defaultOfWrongType(preference: String)
    /// `runtime.exec` is not a path that stays inside the tool's folder.
    case programLeavesFolder(String)
}

/// The rules about names and paths, for anything that checks one alone.
public enum ManifestRules {
    /// Letters, digits, dot, hyphen and underscore; no dot at either end and
    /// no two dots together; at most `ManifestLimits.maxNameLength` long.
    public static func isWellFormedName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= ManifestLimits.maxNameLength, !text.hasPrefix("."),
              !text.hasSuffix("."), !text.contains("..") else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
    }

    /// Whether `path`, read from a tool's folder, cannot name anything
    /// outside it: parts joined by `/`, none of them empty, `.` or `..`.
    /// This reads the text only. A link inside the folder can still point
    /// out of it; whoever has the folder checks that.
    public static func staysInsideFolder(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ToolManifestFile {
    /// Reads a manifest and applies every rule that needs only the file.
    /// The first problem found is the one given.
    public static func read(_ data: Data) -> Result<ToolManifestFile, ManifestProblem> {
        guard data.count <= ManifestLimits.maxBytes else { return .failure(.tooLarge(bytes: data.count)) }
        let file: ToolManifestFile
        do {
            file = try JSONDecoder().decode(ToolManifestFile.self, from: data)
        } catch let error as DecodingError {
            return .failure(problem(for: error))
        } catch {
            return .failure(.notJSON)
        }
        if let problem = file.problems().first { return .failure(problem) }
        return .success(file)
    }

    /// Everything wrong with a manifest that could be read, in the order
    /// the fields are written.
    public func problems() -> [ManifestProblem] {
        var found: [ManifestProblem] = []
        if !ManifestRules.isWellFormedName(id) {
            found.append(.idNotWellFormed(id))
        } else if !id.contains(".") {
            found.append(.idWithoutDot(id))
        }
        found += Self.textProblems(name, field: "name")
        if let summary = description { found += Self.textProblems(summary, field: "description") }
        if ManifestRules.isBlank(version) { found.append(.blankText(field: "version")) }
        if !ProtocolVersion.supported.contains(`protocol`) { found.append(.unsupportedProtocol(`protocol`)) }
        if ManifestRules.isBlank(publisher) { found.append(.blankText(field: "publisher")) }

        var services = Set<String>()
        for service in uses ?? [] {
            if AppService(rawValue: service) == nil {
                found.append(.unknownService(service))
            } else if !services.insert(service).inserted {
                found.append(.duplicateService(service))
            }
        }

        let commands = contributes?.commands ?? []
        if commands.count > ManifestLimits.maxCommands { found.append(.tooManyCommands(commands.count)) }
        var commandNames = Set<String>()
        for command in commands {
            guard ManifestRules.isWellFormedName(command.id) else {
                found.append(.commandNotWellFormed(command.id))
                continue
            }
            if !commandNames.insert(command.id).inserted { found.append(.duplicateCommand(command.id)) }
            found += Self.textProblems(command.title, field: "contributes.commands[\(command.id)].title")
            for surface in command.surfaces ?? [] where SurfaceName(rawValue: surface) == nil {
                found.append(.unknownSurface(command: command.id, surface: surface))
            }
        }

        let settings = preferences ?? []
        if settings.count > ManifestLimits.maxPreferences {
            found.append(.tooManyPreferences(settings.count))
        }
        var preferenceNames = Set<String>()
        for preference in settings {
            guard ManifestRules.isWellFormedName(preference.id) else {
                found.append(.preferenceNotWellFormed(preference.id))
                continue
            }
            if !preferenceNames.insert(preference.id).inserted {
                found.append(.duplicatePreference(preference.id))
            }
            guard let kind = PreferenceKind(rawValue: preference.type) else {
                found.append(.unknownPreferenceType(preference: preference.id, type: preference.type))
                continue
            }
            if !kind.accepts(preference.default) { found.append(.defaultOfWrongType(preference: preference.id)) }
        }

        for name in activation ?? [] where ActivationName(rawValue: name) == nil {
            found.append(.unknownActivation(name))
        }
        if runtime.kind != Self.externalRuntime { found.append(.unsupportedRuntime(runtime.kind)) }
        if !ManifestRules.staysInsideFolder(runtime.exec) { found.append(.programLeavesFolder(runtime.exec)) }
        return found
    }

    private static func textProblems(_ text: LocalizedText, field: String) -> [ManifestProblem] {
        guard text.english != nil else { return [.noEnglish(field: field)] }
        return text.byLanguage.values.contains(where: ManifestRules.isBlank) ? [.blankText(field: field)] : []
    }

    /// Where a file that would not decode went wrong.
    private static func problem(for error: DecodingError) -> ManifestProblem {
        func field(_ path: [any CodingKey]) -> ManifestProblem {
            guard !path.isEmpty else { return .notJSON }
            let text = path.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
            return .malformed(field: String(text.drop(while: { $0 == "." })))
        }
        switch error {
        case .keyNotFound(let key, let context): return field(context.codingPath + [key])
        case .typeMismatch(_, let context), .valueNotFound(_, let context): return field(context.codingPath)
        case .dataCorrupted(let context): return field(context.codingPath)
        @unknown default: return .notJSON
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests --test_output=errors`
Expected: PASS, twenty-four tests in four classes.

If `testEveryExampleIsJudgedAsTheSchemaJudgesIt` fails for one example, read which side is out of step before changing anything. The Python test passed in Task 2, so the schema and the example agree. The Swift rule is what is wrong, unless the example is one of the two marked `"schema": false`.

- [ ] **Step 5: Prove the tests see drift**

One at a time, make each change, run the test, confirm it FAILS in the test named, and undo it by hand:

1. In `ToolManifestFile.swift`, in `problems()`, delete the `else if` arm that gives `.idWithoutDot`. Expected: `testEveryExampleIsJudgedAsTheSchemaJudgesIt` fails for "an id with no dot is a built-in feature's".
2. In `ToolManifestFile.swift`, add `case island` to `SurfaceName`. Expected: `testTheListsAreTheSchemasLists` fails, and so does the example "a surface the app does not have".
3. In `ToolManifestFile.swift`, add `public let homepage: String?` to `ToolManifestFile`. Expected: `testTheTypeHasTheFieldsTheSchemaDeclares` fails.

- [ ] **Step 6: Commit**

```sh
bazel run //tools/license:check
bazel run //tools/license:verify
```

```bash
git add packages/vitruvian-sdk/Sources/VitruvianToolProtocol/ToolManifestFile.swift packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ManifestFileTests.swift
git commit -m "chore(vitruvian-sdk): the tool manifest as a Swift type, with the rules a file must keep"
```

---

### Task 5: The app's side as a script, and a tool to prove it on

Works in `packages/vitruvian-sdk/`.

**Files:**
- Create: `conformance/conformance.py` (executable), `conformance/conformance_test.py`
- Create: `conformance/reference-tool/vitruvian-tool.json`, `conformance/reference-tool/bin/reference_tool.py` (executable)
- Modify: `BUILD`, `protocol/protocol_examples_test.py`, `Tests/VitruvianToolProtocolTests/ManifestFileTests.swift`
- Modify: `.github/workflows/presubmit.yaml` (generated)

**Interfaces:**
- Consumes: Python 3's standard library. Nothing of the app, and nothing of the Swift module.
- Produces:
  - `conformance.py <tool folder> [--via PROGRAM] [--expect-refusal]`: prints one line for each of five checks (`ok`, `NOT OK` or `skipped`), exits 0 when all passed
  - `conformance.main(arguments)`, for the test
  - Bazel: `:conformance` (a `py_binary`), `:conformance_test`

The script is a second, independent reading of `protocol/`: it shares no code with the Swift module. It does not validate a tool's messages against the schemas, because it must run with nothing installed; it checks the shape of every line by hand and the order of the conversation.

What "any tool can be run against it" means: a tool is a folder with a `vitruvian-tool.json`. The script reads `runtime.exec` from it, starts that program in a fresh empty folder, and talks to it over its standard input and output. A tool whose program is a script with no interpreter line, or a file that is not executable, is started with `--via`.

- [ ] **Step 1: Write the reference tool and the failing test**

Create `packages/vitruvian-sdk/conformance/reference-tool/vitruvian-tool.json`:

```json
{
  "id": "dev.vitruvian.reference",
  "name": { "en": "Reference tool" },
  "description": { "en": "Says hello. The smallest tool that speaks protocol 1." },
  "version": "0.1.0",
  "protocol": "1",
  "publisher": "VitruvianSoftware",
  "license": "MIT",
  "icon": "hand.wave",
  "uses": ["notify"],
  "contributes": {
    "commands": [{"id": "hello", "title": {"en": "Say hello"}, "icon": "hand.wave", "surfaces": ["commandBar"]}]
  },
  "activation": ["onCommand"],
  "runtime": { "kind": "external", "exec": "bin/reference_tool.py" }
}
```

Create `packages/vitruvian-sdk/conformance/reference-tool/bin/reference_tool.py`:

```python
#!/usr/bin/env python3
# MIT-HEADER
"""The smallest tool that speaks the Vitruvian tool protocol, version 1.

It has one command, `hello`, which asks the app to show a short message. It is
what the conformance script is proven against, and it uses nothing but Python:
the protocol is one JSON message per line on standard input and output.
"""

import json
import sys


def send(message):
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    asked = 0
    # A request of ours the app has not answered yet, and the `command/run`
    # it is part of.
    waiting = {}
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method = message.get("method")
        if method == "initialize":
            if "1" not in message["params"]["protocolVersions"]:
                error = {"code": -32602, "message": "this tool speaks protocol 1 only"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            result = {"protocolVersion": "1", "toolVersion": "0.1.0"}
            send({"jsonrpc": "2.0", "id": message["id"], "result": result})
            send(
                {
                    "jsonrpc": "2.0",
                    "method": "commands/state",
                    "params": {"runnable": ["hello"]},
                }
            )
        elif method == "command/run":
            if message["params"]["command"] != "hello":
                error = {"code": -32602, "message": "no such command"}
                send({"jsonrpc": "2.0", "id": message["id"], "error": error})
                continue
            asked += 1
            waiting[asked] = message["id"]
            params = {"icon": "hand.wave", "message": "Hello from the reference tool"}
            send(
                {
                    "jsonrpc": "2.0",
                    "id": asked,
                    "method": "notify/hud",
                    "params": params,
                }
            )
        elif method == "shutdown":
            return 0
        elif method is None and message.get("id") in waiting:
            run = waiting.pop(message["id"])
            if "error" in message:
                error = {
                    "code": -32010,
                    "message": "command refused",
                    "data": message["error"],
                }
                send({"jsonrpc": "2.0", "id": run, "error": error})
            else:
                send({"jsonrpc": "2.0", "id": run, "result": {}})
        elif method is not None and "id" in message:
            error = {"code": -32601, "message": "method not found"}
            send({"jsonrpc": "2.0", "id": message["id"], "error": error})
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Create `packages/vitruvian-sdk/conformance/conformance_test.py`:

```python
# MIT-HEADER
"""The conformance script, proven two ways: the reference tool passes it, and
a tool that breaks the protocol fails the check meant to catch it."""

import contextlib
import io
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import conformance

REFERENCE = os.path.join(HERE, "reference-tool")

# A tool that goes wrong in the way BROKEN_HOW names, and is otherwise the
# reference tool without its request to the app.
BROKEN_TOOL = """
import json, os, sys, time
how = os.environ["BROKEN_HOW"]
def send(message):
    sys.stdout.write(json.dumps(message) + "\\n")
    sys.stdout.flush()
for line in sys.stdin:
    message = json.loads(line)
    method = message.get("method")
    if method == "initialize":
        if how == "speaks first":
            send({"jsonrpc": "2.0", "method": "log", "params": {"message": "starting"}})
        if how == "not json":
            sys.stdout.write("starting up\\n")
        version = "2" if how == "wrong version" else "1"
        send({"jsonrpc": "2.0", "id": message["id"], "result": {"protocolVersion": version, "toolVersion": "0"}})
    elif method == "command/run":
        if how == "never answers":
            continue
        known = message["params"]["command"] == "hello"
        if known or how == "runs anything":
            send({"jsonrpc": "2.0", "id": message["id"], "result": {}})
        else:
            send({"jsonrpc": "2.0", "id": message["id"], "error": {"code": -32602, "message": "no such command"}})
    elif method == "shutdown" and how == "exits with 3":
        sys.exit(3)
if how == "will not exit":
    time.sleep(30)
"""

# How a tool goes wrong, and the line the script must print for it.
BROKEN = {
    "speaks first": "NOT OK   handshake: something other than the answer to initialize came first",
    "not json": "NOT OK   handshake: a line that is not JSON",
    "wrong version": "NOT OK   handshake: the tool did not pick version 1",
    "never answers": "NOT OK   a command: no answer within 2 seconds",
    "runs anything": "NOT OK   unknown: a command the tool does not have was answered as done",
    "exits with 3": "NOT OK   shutdown: exited with 3",
    "will not exit": "NOT OK   shutdown: still running 2 seconds after shutdown",
}


def check(folder, *options):
    """What the script printed for the tool in `folder`, and its exit status."""
    printed = io.StringIO()
    with contextlib.redirect_stdout(printed):
        status = conformance.main([folder, "--via", sys.executable, *options])
    return status, printed.getvalue()


def main():
    problems = []

    status, printed = check(REFERENCE, "--expect-refusal")
    wanted = [
        "ok       handshake",
        "ok       a command: hello: ran",
        "ok       unknown",
        "1 refused",
        "exited with 0",
    ]
    if status != 0 or not all(piece in printed for piece in wanted):
        problems.append(f"the reference tool does not pass:\n{printed}")

    with open(
        os.path.join(REFERENCE, "vitruvian-tool.json"), encoding="utf-8"
    ) as handle:
        manifest = json.load(handle)
    manifest["runtime"]["exec"] = "broken.py"
    with tempfile.TemporaryDirectory() as folder:
        with open(
            os.path.join(folder, "vitruvian-tool.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump(manifest, handle)
        with open(os.path.join(folder, "broken.py"), "w", encoding="utf-8") as handle:
            handle.write(BROKEN_TOOL)
        for how, line in BROKEN.items():
            os.environ["BROKEN_HOW"] = how
            status, printed = check(folder)
            if status != 1 or line not in printed:
                problems.append(f"a tool that {how} is not caught:\n{printed}")
        os.environ["BROKEN_HOW"] = "nothing"
        status, printed = check(folder, "--expect-refusal")
        if status != 1 or "--expect-refusal was given" not in printed:
            problems.append(
                f"a tool that asks for nothing passes --expect-refusal:\n{printed}"
            )
        status, printed = check(folder)
        if status != 0 or "nothing was refused" not in printed:
            problems.append(f"a tool that only answers does not pass:\n{printed}")

    for problem in problems:
        print(problem, file=sys.stderr)
    print("conformance: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
```

In `packages/vitruvian-sdk/BUILD`, replace the load of `py_test` with

```python
load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
```

Under `PROTOCOL_FILES`, add:

```python
# The smallest tool that speaks the protocol. The conformance script is proven
# against it, and its manifest is read by both halves of the drift test.
REFERENCE_TOOL = glob(["conformance/reference-tool/**"])

REFERENCE_MANIFEST = "conformance/reference-tool/vitruvian-tool.json"
```

Change the `data` of `VitruvianToolProtocolTests` and of `protocol_examples_test` from `PROTOCOL_FILES` to:

```python
    data = PROTOCOL_FILES + [REFERENCE_MANIFEST],
```

Add, after `protocol_examples_test`:

```python
# bazel run //packages/vitruvian-sdk:conformance -- <a tool's folder>
#
# Plays the app's side of the protocol to any tool. Plain Python with no
# dependencies, so a tool's author can also run the file itself.
py_binary(
    name = "conformance",
    srcs = ["conformance/conformance.py"],
    main = "conformance/conformance.py",
)

# The reference tool passes, and seven tools that each break the protocol in
# one way are each caught. It starts real processes: Python ones, a few
# seconds in all.
py_test(
    name = "conformance_test",
    size = "small",
    srcs = [
        "conformance/conformance.py",
        "conformance/conformance_test.py",
    ],
    data = REFERENCE_TOOL,
    main = "conformance/conformance_test.py",
)
```

And add `":conformance_test",` to the pipeline unit's `test_targets`, between the two that are there.

- [ ] **Step 2: Run the test to see it fail**

Run: `bazel test //packages/vitruvian-sdk:conformance_test --test_output=errors`
Expected: FAIL at loading: `conformance/conformance.py` is named in `srcs` and does not exist.

- [ ] **Step 3: Write the script**

Create `packages/vitruvian-sdk/conformance/conformance.py`:

```python
#!/usr/bin/env python3
# MIT-HEADER
"""Plays the app's side of the Vitruvian tool protocol, version 1, to a tool.

    python3 conformance.py <tool folder> [--via PROGRAM] [--expect-refusal]

`<tool folder>` holds a vitruvian-tool.json. The program its manifest names is
started the way the app starts it: in a folder of its own, with this script on
its standard input and output. `--via` starts it through another program, for
example a Python interpreter, when the file cannot be run by itself.

Five things are checked, in order, and the first failure stops the run:

  handshake   the tool answers `initialize` first, with version 1
  a command   its first command is run and answered
  unknown     a command it does not have is answered with a failure
  refusals    the command is run again with every request the tool makes
              refused, and is still answered
  shutdown    after `shutdown` and the end of its input, the tool exits with 0

Every line the tool writes must be one JSON-RPC 2.0 message, at most 1 MB.
While a command runs, the script answers the tool's requests as the app would:
a service the manifest's `uses` does not list is refused with -32001.

It needs Python 3 and nothing else, and it does not need the app. It exits
with 0 when every check passed.
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time

MAX_LINE_BYTES = 1_048_576
FIRST_ANSWER_SECONDS = 10
ANSWER_SECONDS = 2
EXIT_SECONDS = 2

INVALID_PARAMS = -32602
METHOD_NOT_FOUND = -32601
NOT_IN_USES = -32001
UNAVAILABLE = -32004

# Each request a tool may make: the entry of `uses` it needs, and what the app
# answers once it has done the work.
SERVICES = {
    "notify/hud": ("notify", {}),
    "notify/beep": ("notify", {}),
    "open/url": ("open", {"opened": True}),
    "clipboard/readText": ("clipboard.read", {"text": "conformance"}),
    "clipboard/writeText": ("clipboard.write", {"written": True}),
    "keystrokes/paste": ("keystrokes", {}),
    "keystrokes/pressMenuItem": ("keystrokes", {"pressed": True}),
    "processes/terminate": ("processes", {}),
    "storage/get": ("storage", None),
    "storage/set": ("storage", {}),
}


class Failure(Exception):
    """A check the tool did not pass."""


def is_id(value):
    return isinstance(value, (int, str)) and not isinstance(value, bool)


def kind_of(message):
    """request, notice, result or failure; a Failure for anything else."""
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        raise Failure(f"a line that is not a JSON-RPC 2.0 message: {message!r}")
    if "method" in message:
        answers = "result" in message or "error" in message
        if not isinstance(message["method"], str) or answers:
            raise Failure(f"a message that is not well formed: {message!r}")
        if not isinstance(message.get("params", {}), dict):
            raise Failure(f"params that are not an object: {message!r}")
        if "id" not in message:
            return "notice"
        if is_id(message["id"]):
            return "request"
    elif "error" in message and "result" not in message:
        error = message["error"]
        if (
            isinstance(error, dict)
            and isinstance(error.get("code"), int)
            and not isinstance(error.get("code"), bool)
            and isinstance(error.get("message"), str)
            and (is_id(message.get("id", False)) or message.get("id", False) is None)
        ):
            return "failure"
    elif "result" in message and is_id(message.get("id")):
        return "result"
    raise Failure(f"a message that is not well formed: {message!r}")


class Link:
    """The tool's process, with its standard output read a line at a time."""

    def __init__(self, command, folder):
        self.process = subprocess.Popen(
            command, cwd=folder, stdin=subprocess.PIPE, stdout=subprocess.PIPE
        )
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        while True:
            line = self.process.stdout.readline(MAX_LINE_BYTES + 2)
            self.lines.put(line)
            if not line:
                return

    def send(self, message):
        try:
            self.process.stdin.write(
                json.dumps(message, separators=(",", ":")).encode() + b"\n"
            )
            self.process.stdin.flush()
        except OSError:
            raise Failure("the tool closed its input") from None

    def receive(self, deadline, seconds):
        """The tool's next message, before `deadline`, which is `seconds` long."""
        while True:
            try:
                line = self.lines.get(timeout=max(0.0, deadline - time.monotonic()))
            except queue.Empty:
                raise Failure(f"no answer within {seconds} seconds") from None
            if not line:
                raise Failure("the tool exited")
            if not line.endswith(b"\n"):
                raise Failure("a line longer than 1 MB, or one cut short")
            if not line.strip():
                continue
            try:
                return json.loads(line)
            except ValueError:
                raise Failure(f"a line that is not JSON: {line[:80]!r}") from None

    def close(self):
        """Ends the tool if it is still running."""
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()


class Run:
    """One tool put through the checks."""

    def __init__(self, link, manifest, data_folder):
        self.link = link
        self.data_folder = data_folder
        self.uses = set(manifest.get("uses", []))
        self.commands = [
            c["id"] for c in manifest.get("contributes", {}).get("commands", [])
        ]
        self.values = {p["id"]: p["default"] for p in manifest.get("preferences", [])}
        self.next_id = 0
        self.refused = 0

    def request(self, method, params):
        self.next_id += 1
        self.link.send(
            {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        )
        return self.next_id

    def fail(self, request, code, message, data=None):
        error = {"code": code, "message": message}
        if data is not None:
            error["data"] = data
        self.link.send({"jsonrpc": "2.0", "id": request["id"], "error": error})

    def serve(self, request, refuse_all):
        """Answers one request from the tool as the app would."""
        method, params = request["method"], request.get("params", {})
        if method not in SERVICES:
            return self.fail(request, METHOD_NOT_FOUND, "method not found")
        service, result = SERVICES[method]
        if service not in self.uses:
            self.refused += 1
            return self.fail(
                request, NOT_IN_USES, "not listed in uses", {"service": service}
            )
        if refuse_all:
            self.refused += 1
            return self.fail(request, UNAVAILABLE, "not available right now")
        if service == "storage":
            if params.get("key") not in self.values:
                return self.fail(
                    request, INVALID_PARAMS, "not a preference the manifest declares"
                )
            if method == "storage/set":
                self.values[params["key"]] = params.get("value")
            else:
                result = {"value": self.values[params["key"]]}
        return self.link.send({"jsonrpc": "2.0", "id": request["id"], "result": result})

    def answer(self, request_id, seconds, refuse_all=False):
        """Plays the app until the tool answers request `request_id`."""
        deadline = time.monotonic() + seconds
        while True:
            message = self.link.receive(deadline, seconds)
            kind = kind_of(message)
            if kind == "request":
                self.serve(message, refuse_all)
            elif kind in ("result", "failure"):
                if message.get("id") != request_id:
                    raise Failure(
                        f"an answer to a request that was not waiting: {message!r}"
                    )
                return kind, message

    def handshake(self):
        params = {
            "protocolVersions": ["1"],
            "language": "en-US",
            "dataFolder": self.data_folder,
        }
        sent = self.request("initialize", params)
        message = self.link.receive(
            time.monotonic() + FIRST_ANSWER_SECONDS, FIRST_ANSWER_SECONDS
        )
        if kind_of(message) != "result" or message.get("id") != sent:
            raise Failure(
                f"something other than the answer to initialize came first: {message!r}"
            )
        result = message["result"]
        if not isinstance(result, dict) or result.get("protocolVersion") != "1":
            raise Failure(f"the tool did not pick version 1: {result!r}")
        if not isinstance(result.get("toolVersion"), str):
            raise Failure(f"the tool did not say its own version: {result!r}")
        return f"version 1, tool {result['toolVersion']}"

    def a_command(self):
        if not self.commands:
            return "the manifest declares no command"
        kind, message = self.answer(
            self.request("command/run", {"command": self.commands[0]}), ANSWER_SECONDS
        )
        if kind == "result" and not isinstance(message["result"], dict):
            raise Failure(f"a result that is not an object: {message!r}")
        return f"{self.commands[0]}: " + (
            "ran" if kind == "result" else f"refused, {message['error']['message']}"
        )

    def unknown(self):
        sent = self.request("command/run", {"command": "conformance.no-such-command"})
        kind, message = self.answer(sent, ANSWER_SECONDS)
        if kind != "failure":
            raise Failure(
                f"a command the tool does not have was answered as done: {message!r}"
            )
        return f"failure {message['error']['code']}"

    def refusals(self):
        if not self.commands:
            return "the manifest declares no command"
        before = self.refused
        sent = self.request("command/run", {"command": self.commands[0]})
        self.answer(sent, ANSWER_SECONDS, refuse_all=True)
        count = self.refused - before
        return (
            f"{count} refused"
            if count
            else "the tool asked the app for nothing, so nothing was refused"
        )

    def shutdown(self):
        self.link.send({"jsonrpc": "2.0", "method": "shutdown"})
        self.link.process.stdin.close()
        try:
            status = self.link.process.wait(timeout=EXIT_SECONDS)
        except subprocess.TimeoutExpired:
            raise Failure(
                f"still running {EXIT_SECONDS} seconds after shutdown"
            ) from None
        if status != 0:
            raise Failure(f"exited with {status}")
        return "exited with 0"


def main(arguments=None):
    parser = argparse.ArgumentParser(
        description="Check a tool against the Vitruvian tool protocol, version 1."
    )
    parser.add_argument(
        "folder", help="the tool's folder, which holds vitruvian-tool.json"
    )
    parser.add_argument("--via", help="start the tool's program through this program")
    parser.add_argument(
        "--expect-refusal",
        action="store_true",
        help="fail unless the refusals check refused something",
    )
    options = parser.parse_args(arguments)
    # `bazel run` starts a program in its own folder; this is where the person was.
    folder = os.path.abspath(
        os.path.join(os.environ.get("BUILD_WORKING_DIRECTORY", ""), options.folder)
    )
    with open(os.path.join(folder, "vitruvian-tool.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    program = os.path.join(folder, manifest["runtime"]["exec"])
    command = [options.via, program] if options.via else [program]

    passed = True
    with tempfile.TemporaryDirectory(prefix="vitruvian-conformance-") as data_folder:
        link = Link(command, data_folder)
        run = Run(link, manifest, data_folder)
        checks = [
            ("handshake", run.handshake),
            ("a command", run.a_command),
            ("unknown", run.unknown),
            ("refusals", run.refusals),
            ("shutdown", run.shutdown),
        ]
        try:
            for name, check in checks:
                if not passed:
                    print(f"skipped  {name}")
                    continue
                try:
                    print(f"ok       {name}: {check()}")
                except Failure as failure:
                    passed = False
                    print(f"NOT OK   {name}: {failure}")
            if passed and options.expect_refusal and run.refused == 0:
                passed = False
                print(
                    "NOT OK   refusals: nothing was refused, and --expect-refusal was given"
                )
        finally:
            link.close()
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
```

Mark the two programs executable, so that Git records it:

```sh
chmod +x packages/vitruvian-sdk/conformance/conformance.py packages/vitruvian-sdk/conformance/reference-tool/bin/reference_tool.py
```

- [ ] **Step 4: Run the test**

Run: `bazel test //packages/vitruvian-sdk:conformance_test --test_output=errors`
Expected: PASS, printing `conformance: OK`, in about five seconds. Two of the broken tools are caught by a two-second deadline each.

Then run the script as a tool's author would, both ways:

```sh
bazel run //packages/vitruvian-sdk:conformance -- packages/vitruvian-sdk/conformance/reference-tool --expect-refusal
python3 packages/vitruvian-sdk/conformance/conformance.py packages/vitruvian-sdk/conformance/reference-tool
```

Expected, from each:

```
ok       handshake: version 1, tool 0.1.0
ok       a command: hello: ran
ok       unknown: failure -32602
ok       refusals: 1 refused
ok       shutdown: exited with 0
```

If the first form cannot find the folder, the `BUILD_WORKING_DIRECTORY` line in `main` is not doing its job: `bazel run` starts a program in its own folder, and that variable is where the person was.

- [ ] **Step 5: Hold the reference tool's manifest to the schema and to the Swift rules**

In `packages/vitruvian-sdk/protocol/protocol_examples_test.py`, in `manifest_problems`, replace

```python
    return problems + unused(schema, "manifest", seen)
```
with
```python
    reference = load("../conformance/reference-tool/vitruvian-tool.json")
    if not validator.is_valid(reference):
        problems.append("the reference tool's manifest does not pass the schema")
    return problems + unused(schema, "manifest", seen)
```

In `packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ManifestFileTests.swift`, add as the last test of the class:

```swift
    func testTheReferenceToolsManifestIsRead() throws {
        let data = ProtocolFiles.data("conformance/reference-tool/\(ToolManifestFile.fileName)")
        let manifest = try ToolManifestFile.read(data).get()
        XCTAssertEqual(manifest.id, "dev.vitruvian.reference")
        XCTAssertEqual(manifest.uses, [AppService.notify.rawValue])
        XCTAssertEqual(manifest.contributes?.commands?.map(\.id), ["hello"])
        XCTAssertEqual(manifest.runtime.exec, "bin/reference_tool.py")
    }
```

Run: `bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test`
Run: `bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests`
Expected: PASS, all three.

- [ ] **Step 6: Format, regenerate, and commit**

```sh
bazel run //tools/format -- packages/vitruvian-sdk/BUILD packages/vitruvian-sdk/conformance/conformance.py packages/vitruvian-sdk/conformance/conformance_test.py packages/vitruvian-sdk/conformance/reference-tool/bin/reference_tool.py packages/vitruvian-sdk/protocol/protocol_examples_test.py
bazel run //tools/license:check
bazel run //tools/license:verify
bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test
git ls-files -s packages/vitruvian-sdk/conformance | grep 100755
```

Expected: the tests pass after formatting. The generated job names all three targets. The last command, run after the `git add` below, lists exactly two files: `conformance.py` and `reference_tool.py`.

```bash
git add packages/vitruvian-sdk/BUILD packages/vitruvian-sdk/conformance packages/vitruvian-sdk/protocol/protocol_examples_test.py packages/vitruvian-sdk/Tests/VitruvianToolProtocolTests/ManifestFileTests.swift .github/workflows/presubmit.yaml
git commit -m "chore(vitruvian-sdk): a conformance script that plays the app's side, and a reference tool"
```

---

### Task 6: The app reads a tool's manifest

Works in `apps/desktop/vitruvian/`.

**Files:**
- Create: `Sources/Vitruvian/Core/Platform/ExternalToolManifest.swift`
- Create: `Tests/ExternalToolManifestTests.swift`
- Create: `bazel/tool_protocol.sha256` (written by a command)
- Modify: `Sources/Vitruvian/Core/Platform/ToolManifest.swift` (one initializer added)
- Modify: `BUILD`, `bazel/pin_nexus_agent_shared.py`
- Modify: `Tests/TestGroups.swift`, `Tests/mutation_checks.py`, `UPSTREAM.md`
- Modify: `.github/workflows/presubmit.yaml` (generated)

**Interfaces:**
- Consumes: `VitruvianToolProtocol` (`ToolManifestFile`, `ManifestProblem`, `ManifestLimits`, `LocalizedText`, `JSONValue`, `PreferenceKind`); the app's `ToolID`, `CommandID`, `ToolSurface`, `CommandDescriptor`, `ToolDescriptor`, `Capability`, `CapabilityRequest`, `PreferenceDeclaration`, `Activation`, `ToolManifest`, `FeatureGroup`.
- Produces:
  - `CapabilityRequest.init(usedByOutsideTool:)`
  - `ManifestRefusal` (`noManifest`, `invalid(ManifestProblem)`, `notOfferedHere(String)`, `programMissing(String)`, `programOutsideFolder(String)`, `programNotExecutable(String)`)
  - `ExternalToolManifest` (`manifest`, `name`, `summary`, `commandTitles`, `version`, `publisher`, `license`, `protocolVersion`, `program`; `defaultSymbol`, `group`, `storageKey(tool:preference:)`, `read(folder:fileManager:)`, `read(_:)`, `value(_:ofKind:)`)
  - Bazel: `:pin_tool_protocol`, `:tool_protocol_pin_test`

How a manifest file lands on the platform's types. The left column is the file; the right is what a built-in tool already has.

| In `vitruvian-tool.json` | In the app |
|---|---|
| `id` | `ToolID`. It must have a dot, so `ToolDescriptor.feature` is nil and it can never pass for one of the app's features. |
| `name.en`, `icon` | `ToolDescriptor.name`, `.symbol` |
| `name`, `description` in every language | `ExternalToolManifest.name`, `.summary` |
| `contributes.commands[].id` | `CommandID(tool:name:)`, written `<tool id>/<id>` |
| a command's `title.en`, `icon`, `surfaces` | `CommandDescriptor.title`, `.symbol`, `.surfaces` (`ToolSurface`) |
| a command's `title` in every language | `ExternalToolManifest.commandTitles[CommandID]` |
| `uses` | `ToolManifest.capabilities`, each a `CapabilityRequest(usedByOutsideTool:)` |
| `preferences[]` | `PreferenceDeclaration(key: "<tool id>/<id>", default:)` |
| `activation` | `ToolManifest.activation`; `[.onCommand]` when left out |
| nothing | `ToolManifest.group` is `.tools`; `enabledBy` is nil |
| `version`, `publisher`, `license`, `protocol`, `runtime.exec` | `ExternalToolManifest.version`, `.publisher`, `.license`, `.protocolVersion`, `.program` |

- [ ] **Step 1: Link the module**

In `BUILD`, in `VitruvianCore`, replace

```python
    deps = [
        ":FanControlKit",
        "//apps/desktop/nexus-agent/macos:NexusAgentCore",
    ],
)
```
with
```python
    deps = [
        ":FanControlKit",
        "//apps/desktop/nexus-agent/macos:NexusAgentCore",
        # The tool protocol's types (MIT, packages/vitruvian-sdk): the app and
        # a tool read each message from one definition. Core imports it by
        # name where it is used; it is not re-exported.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)
```

In `unit_tests_bin`, replace

```python
        # NexusAgentTests checks what the app hands the shared chat view.
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
    ],
)
```
with
```python
        # NexusAgentTests checks what the app hands the shared chat view.
        "//apps/desktop/nexus-agent/macos:NexusAgentUI",
        # ExternalToolManifestTests names the manifest file's own types.
        "//packages/vitruvian-sdk:VitruvianToolProtocol",
    ],
)
```

Run: `bazel build --config=macos-app //apps/desktop/vitruvian:VitruvianCore`
Expected: it builds. Nothing imports the module yet.

Three checks that read the sources as text are not touched by this link, and must stay green without an edit:

- `sources_in_sync_test` compares `bazel/sources.bzl` with `build.sh`. `Core/` is a glob in `BUILD` and in neither list, so a new `Core` file changes nothing it reads. `build.sh` and `Package.swift` cannot see the new module, as they cannot see `NexusAgentCore`; `AGENTS.md` already says Bazel is the only build of this app.
- `source_lints_test`, rule `modules_import_what_they_name`, knows the app's four modules only. It cannot tell that a file needs `import VitruvianToolProtocol`; the compiler does.
- `source_lints_test`, rule `package_signatures_name_no_internal_type`, looks for types declared in the app. The new file's `package` members name `LocalizedText`, `ManifestProblem` and `JSONValue`, which are `public` in the package, and no internal type of the app.

- [ ] **Step 2: Write the failing tests**

Create `Tests/ExternalToolManifestTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// A tool's manifest file, read into the platform's own manifest. Nothing
/// here starts a program: the folders are made in the temporary folder and
/// hold empty files.
enum ExternalToolManifestTests {
    static func run(_ suite: TestSuite) {
        theDesignsExample(suite)
        whatIsLeftOut(suite)
        refusals(suite)
        services(suite)
        listsAgree(suite)
        languages(suite)
        folders(suite)
    }

    /// The manifest in the design, section 6, with a publisher.
    static let example = """
        {
          "id": "com.acme.deploys",
          "name": { "en": "Deploys", "fr": "Déploiements" },
          "description": { "en": "Copies the address of your latest deploy." },
          "version": "1.2.0",
          "protocol": "1",
          "publisher": "Acme",
          "license": "MIT",
          "icon": "shippingbox",
          "uses": ["clipboard.write", "notify", "storage"],
          "contributes": {
            "commands": [
              { "id": "copyLatest", "title": { "en": "Copy latest deploy" }, "icon": "link",
                "surfaces": ["commandBar", "radial", "shortcut"] }
            ]
          },
          "preferences": [ { "id": "project", "type": "string", "default": "" } ],
          "activation": ["onCommand"],
          "runtime": { "kind": "external", "exec": "bin/deploys" }
        }
        """

    /// The example with some of its top-level fields replaced, as the bytes
    /// of a file. `change` is a JSON object; a field it sets to null is left
    /// out.
    static func file(_ change: String = "{}") -> Data {
        var fields = object(example)
        for (key, value) in object(change) {
            if value is NSNull {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    static func object(_ text: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:]
    }

    static func tool(_ change: String = "{}") -> ExternalToolManifest? {
        try? ExternalToolManifest.read(file(change)).get()
    }

    static func refusal(_ change: String) -> ManifestRefusal? {
        if case .failure(let refusal) = ExternalToolManifest.read(file(change)) { return refusal }
        return nil
    }

    /// `count` things written as JSON, in a list.
    static func list(_ count: Int, _ item: (Int) -> String) -> String {
        "[" + (0..<count).map(item).joined(separator: ",") + "]"
    }

    static func theDesignsExample(_ suite: TestSuite) {
        guard let tool = tool() else {
            suite.expect(false, "the manifest in the design is read")
            return
        }
        let id = ToolID("com.acme.deploys")!
        let command = CommandID(tool: id, name: "copyLatest")!
        let manifest = tool.manifest
        suite.expect(manifest.id == id && manifest.tool.name == "Deploys" && manifest.tool.symbol == "shippingbox"
                         && manifest.tool.feature == nil,
                     "an outside tool has its own id, its English name and its icon, and is no hub feature")
        suite.expect(manifest.tool.commands
                         == [CommandDescriptor(id: command, title: "Copy latest deploy", symbol: "link",
                                               surfaces: [.commandBar, .radial, .shortcut])!],
                     "a command is the tool's id, a slash and its own, with its English title and its surfaces")
        suite.expect(manifest.capabilities.map(\.capability) == [.clipboardWrite, .notify, .storage]
                         && manifest.capabilities.allSatisfy { $0.reason.isEmpty && !$0.startsWithoutGrant },
                     "uses becomes the capabilities the tool declares, in order, with no reasons")
        suite.expect(manifest.preferences
                         == [PreferenceDeclaration(key: "com.acme.deploys/project", default: .string(""))]
                         && ExternalToolManifest.storageKey(tool: id, preference: "project")
                         == "com.acme.deploys/project",
                     "a preference is saved under the tool's id, a slash and its own")
        suite.expect(manifest.activation == [.onCommand] && manifest.group == .tools && manifest.enabledBy == nil,
                     "it starts on its first command, is filed under Tools and has no switch of its own")
        suite.expect(tool.version == "1.2.0" && tool.publisher == "Acme" && tool.license == "MIT"
                         && tool.protocolVersion == "1" && tool.program == "bin/deploys",
                     "what only an outside tool carries is kept: version, publisher, licence, protocol, program")
        suite.expect(tool.name.byLanguage == ["en": "Deploys", "fr": "Déploiements"]
                         && tool.summary?.english == "Copies the address of your latest deploy."
                         && tool.commandTitles == [command: LocalizedText(["en": "Copy latest deploy"])],
                     "every language the author wrote is kept beside the English the descriptors hold")
    }

    static func whatIsLeftOut(_ suite: TestSuite) {
        let bare = tool(#"""
            {"description": null, "license": null, "icon": null, "uses": null, "contributes": null,
             "preferences": null, "activation": null}
            """#)
        suite.expect(bare?.manifest.capabilities.isEmpty == true && bare?.manifest.tool.commands.isEmpty == true
                         && bare?.manifest.preferences.isEmpty == true && bare?.manifest.activation == [.onCommand]
                         && bare?.manifest.tool.symbol == "puzzlepiece.extension" && bare?.summary == nil
                         && bare?.license == nil,
                     "only the required fields: no capability, command or preference, a plain puzzle piece, "
                         + "started on its first command")
        let borrowed = tool(#"{"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}}]}}"#)
        suite.expect(borrowed?.manifest.tool.commands.first?.symbol == "shippingbox"
                         && borrowed?.manifest.tool.commands.first?.surfaces.isEmpty == true,
                     "a command with no icon takes the tool's, and with no surfaces is listed nowhere")
        suite.expect(tool(#"{"icon": "  "}"#)?.manifest.tool.symbol == "puzzlepiece.extension",
                     "an icon that is only spaces is no icon")
        let later = tool(#"""
            {"future": {"anything": 1},
             "runtime": {"kind": "external", "exec": "bin/deploys", "arguments": ["--fast"]},
             "contributes": {"islandNotices": [], "commands": [
               {"id": "copyLatest", "title": {"en": "Copy latest deploy"}, "icon": "link",
                "surfaces": ["commandBar", "radial", "shortcut"], "argument": "later"}]}}
            """#)
        suite.expect(later != nil && later == tool(),
                     "fields a later protocol might add are ignored, wherever they are")
        suite.expect(tool(#"{"activation": ["onLaunch", "onCommand", "onLaunch"]}"#)?.manifest.activation
                         == [.onLaunch, .onCommand],
                     "each way of starting is kept once, in the order written")
    }

    static func refusals(_ suite: TestSuite) {
        let manyCommands = list(33) { #"{"id": "c\#($0)", "title": {"en": "Command"}}"# }
        let manyPreferences = list(17) { #"{"id": "p\#($0)", "type": "boolean", "default": false}"# }
        let cases: [(String, ManifestRefusal, String)] = [
            ("an id with no dot, which is a built-in feature's", .invalid(.idWithoutDot("pastePlain")),
             #"{"id": "pastePlain"}"#),
            ("an id with a character ids do not have", .invalid(.idNotWellFormed("com.acme/deploys")),
             #"{"id": "com.acme/deploys"}"#),
            ("a service the app does not have", .invalid(.unknownService("camera")),
             #"{"uses": ["notify", "camera"]}"#),
            ("a service built-in tools have and the protocol does not offer", .invalid(.unknownService("hotkey")),
             #"{"uses": ["hotkey"]}"#),
            ("a service listed twice", .invalid(.duplicateService("notify")), #"{"uses": ["notify", "notify"]}"#),
            ("a surface the app does not have", .invalid(.unknownSurface(command: "copyLatest", surface: "island")),
             #"{"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}, "surfaces": ["island"]}]}}"#),
            ("a kind of preference the app does not have",
             .invalid(.unknownPreferenceType(preference: "project", type: "color")),
             #"{"preferences": [{"id": "project", "type": "color", "default": "red"}]}"#),
            ("a default of another type", .invalid(.defaultOfWrongType(preference: "limit")),
             #"{"preferences": [{"id": "limit", "type": "integer", "default": "20"}]}"#),
            ("a way of starting only built-in tools have", .invalid(.unknownActivation("onShown")),
             #"{"activation": ["onShown"]}"#),
            ("a program above the folder", .invalid(.programLeavesFolder("../deploys")),
             #"{"runtime": {"kind": "external", "exec": "../deploys"}}"#),
            ("a program named from the root of the disk", .invalid(.programLeavesFolder("/usr/bin/true")),
             #"{"runtime": {"kind": "external", "exec": "/usr/bin/true"}}"#),
            ("a program that climbs out part way along", .invalid(.programLeavesFolder("bin/../../deploys")),
             #"{"runtime": {"kind": "external", "exec": "bin/../../deploys"}}"#),
            ("a kind of runtime a file may not name", .invalid(.unsupportedRuntime("bundled")),
             #"{"runtime": {"kind": "bundled", "exec": "bin/deploys"}}"#),
            ("a protocol the app does not speak", .invalid(.unsupportedProtocol("2")), #"{"protocol": "2"}"#),
            ("a name with no English", .invalid(.noEnglish(field: "name")), #"{"name": {"fr": "Déploiements"}}"#),
            ("a name that is only spaces", .invalid(.blankText(field: "name")), #"{"name": {"en": " "}}"#),
            ("no publisher", .invalid(.malformed(field: "publisher")), #"{"publisher": null}"#),
            ("no runtime", .invalid(.malformed(field: "runtime")), #"{"runtime": null}"#),
            ("two commands with one id", .invalid(.duplicateCommand("copyLatest")),
             #"""
             {"contributes": {"commands": [{"id": "copyLatest", "title": {"en": "Copy"}},
                                           {"id": "copyLatest", "title": {"en": "Copy again"}}]}}
             """#),
            ("two preferences with one id", .invalid(.duplicatePreference("project")),
             #"""
             {"preferences": [{"id": "project", "type": "string", "default": ""},
                              {"id": "project", "type": "boolean", "default": false}]}
             """#),
            ("more commands than a tool may have", .invalid(.tooManyCommands(33)),
             #"{"contributes": {"commands": \#(manyCommands)}}"#),
            ("more preferences than a tool may have", .invalid(.tooManyPreferences(17)),
             #"{"preferences": \#(manyPreferences)}"#),
        ]
        for (what, wanted, change) in cases {
            let got = refusal(change)
            suite.expect(got == wanted, "\(what) is refused, and the reason names it: \(String(describing: got))")
        }

        let longest = "com." + String(repeating: "a", count: ToolID.maxLength - 4)
        suite.expect(tool(#"{"id": "\#(longest)"}"#)?.manifest.id.rawValue == longest
                         && refusal(#"{"id": "\#(longest)a"}"#) == .invalid(.idNotWellFormed(longest + "a")),
                     "an id may be 128 characters and no longer")
        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let padded = file(#"{"description": {"en": "\#(padding)"}}"#)
        suite.expect(ExternalToolManifest.read(padded) == .failure(.invalid(.tooLarge(bytes: padded.count))),
                     "a manifest over 64 KB is refused before it is read as JSON")
        suite.expect(ExternalToolManifest.read(Data("not json".utf8)) == .failure(.invalid(.notJSON)),
                     "a file that is not JSON is refused, not crashed on")
    }

    static func services(_ suite: TestSuite) {
        let typing = tool(#"{"uses": ["keystrokes", "clipboard.read"]}"#)
        suite.expect(typing?.manifest.capabilities.first?.startsWithoutGrant == true
                         && typing?.manifest.grantsNeededToStart == []
                         && typing?.manifest.declares(.keystrokes) == true,
                     "an outside tool that uses keystrokes starts without Accessibility, and is refused call by call")
        suite.expect(typing?.manifest.capabilities.last?.startsWithoutGrant == false,
                     "a service that rides on no grant has nothing to start without")
        suite.expect(CapabilityRequest(.open, reason: " ") == nil,
                     "a built-in tool's request still needs its reason")
    }

    /// The protocol's lists and the app's. Every name a manifest may hold has
    /// a place in the app, so `notOfferedHere` is not reached today; it is
    /// what a future protocol name meets in an app that does not have it.
    static func listsAgree(_ suite: TestSuite) {
        suite.expect(AppService.allCases.allSatisfy { Capability(rawValue: $0.rawValue) != nil },
                     "every service the protocol offers is one of the app's capabilities")
        suite.expect(Set(Capability.allCases.map(\.rawValue)).subtracting(AppService.allCases.map(\.rawValue))
                         == ["clipboard.rewrite", "hotkey"],
                     "two capabilities are for built-in tools only: rewriting the clipboard, and a hotkey")
        suite.expect(Set(SurfaceName.allCases.map(\.rawValue)) == Set(ToolSurface.allCases.map(\.rawValue)),
                     "the protocol's surfaces are the app's")
        suite.expect(ActivationName.allCases.allSatisfy { Activation(rawValue: $0.rawValue) != nil },
                     "every way of starting the protocol has is one the app has")
        let samples: [(PreferenceKind, JSONValue, PreferenceDeclaration.Value)] = [
            (.string, .string("a"), .string("a")), (.boolean, .bool(true), .bool(true)),
            (.integer, .number(20), .int(20)), (.number, .number(0.5), .double(0.5)),
        ]
        suite.expect(samples.map(\.0) == PreferenceKind.allCases
                         && samples.allSatisfy { ExternalToolManifest.value($0.1, ofKind: $0.0.rawValue) == $0.2 },
                     "every kind of preference the protocol has is a value the app can hold")
        suite.expect(ExternalToolManifest.value(.string("#fff"), ofKind: "color") == nil
                         && ExternalToolManifest.value(.number(1.5), ofKind: "integer") == nil,
                     "a kind the app has no value for is nil, for the reader to refuse by name")
        let names = ["com.acme.deploys", "copyLatest", "a-b_c.9", "", ".a", "a.", "a..b", "a b", "a/b", "é",
                     String(repeating: "a", count: 128), String(repeating: "a", count: 129)]
        suite.expect(names.allSatisfy { ManifestRules.isWellFormedName($0) == (ToolID($0) != nil) }
                         && ManifestLimits.maxNameLength == ToolID.maxLength,
                     "the protocol and the app agree on what a well-formed id is")
        suite.expect(ProtocolVersion.supported == ["1"] && WireLimits.maxLineBytes == 1_048_576,
                     "the app links protocol version 1, with its 1 MB line")
    }

    static func languages(_ suite: TestSuite) {
        let named = tool(#"{"name": {"en": "Deploys", "fr": "Déploiements", "pt": "Implantações", "zh-Hans": "部署"}}"#)
        suite.expect(named?.manifest.tool.name == "Deploys", "the descriptor holds the English name")
        suite.expect(named?.name.text(for: AppLanguage.fr.rawValue) == "Déploiements"
                         && named?.name.text(for: AppLanguage.ptBR.rawValue) == "Implantações"
                         && named?.name.text(for: AppLanguage.zhHans.rawValue) == "部署"
                         && named?.name.text(for: AppLanguage.zhTW.rawValue) == "Deploys"
                         && named?.name.text(for: AppLanguage.enUS.rawValue) == "Deploys",
                     "a language is its own entry, else its language without the region, else English")
        suite.expect(AppLanguage.allCases.allSatisfy { named?.name.text(for: $0.rawValue)?.isEmpty == false },
                     "every language the app has gets a name")
    }

    static func folders(_ suite: TestSuite) {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("vitru-tool-manifest-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }

        // A folder under `root` holding a manifest and a program, each
        // unless nil.
        func make(_ name: String, manifest: Data? = ExternalToolManifestTests.file(), program: String? = "bin/deploys",
                  mode: Int = 0o755) -> URL {
            let made = root.appendingPathComponent(name)
            try? files.createDirectory(at: made.appendingPathComponent("bin"), withIntermediateDirectories: true)
            if let manifest {
                files.createFile(atPath: made.appendingPathComponent("vitruvian-tool.json").path, contents: manifest)
            }
            if let program {
                files.createFile(atPath: made.appendingPathComponent(program).path, contents: Data(),
                                 attributes: [.posixPermissions: mode])
            }
            return made
        }
        func refused(_ folder: URL) -> ManifestRefusal? {
            if case .failure(let refusal) = ExternalToolManifest.read(folder: folder) { return refusal }
            return nil
        }

        suite.expect((try? ExternalToolManifest.read(folder: make("whole")).get()) == tool(),
                     "a folder with a manifest and its program is read as the manifest alone is")
        suite.expect(refused(make("empty", manifest: nil)) == .noManifest
                         && refused(root.appendingPathComponent("nowhere")) == .noManifest,
                     "a folder with no manifest, or no folder at all, is refused")
        suite.expect(refused(make("no-program", program: nil)) == .programMissing("bin/deploys"),
                     "a manifest whose program is not there is refused")
        suite.expect(refused(make("not-runnable", mode: 0o644)) == .programNotExecutable("bin/deploys"),
                     "a program macOS will not run is refused")
        let holdsFolder = make("holds-a-folder", program: nil)
        try? files.createDirectory(at: holdsFolder.appendingPathComponent("bin/deploys"),
                                   withIntermediateDirectories: true)
        suite.expect(refused(holdsFolder) == .programMissing("bin/deploys"),
                     "a folder where the program should be is no program")

        let outside = make("outside", manifest: nil, program: "bin/real")
        let linked = make("linked", program: nil)
        try? files.createSymbolicLink(at: linked.appendingPathComponent("bin/deploys"),
                                      withDestinationURL: outside.appendingPathComponent("bin/real"))
        suite.expect(refused(linked) == .programOutsideFolder("bin/deploys"),
                     "a program that is a link to a file outside the folder is refused")
        let within = make("within", program: "bin/real")
        try? files.createSymbolicLink(at: within.appendingPathComponent("bin/deploys"),
                                      withDestinationURL: within.appendingPathComponent("bin/real"))
        suite.expect(refused(within) == nil, "a link to a file inside the folder is the tool's own business")

        let padding = String(repeating: "x", count: ManifestLimits.maxBytes)
        let padded = file(#"{"description": {"en": "\#(padding)"}}"#)
        suite.expect(refused(make("large", manifest: padded)) == .invalid(.tooLarge(bytes: padded.count)),
                     "a manifest over 64 KB on disk is refused by its size")
        suite.expect(refused(make("breaks-a-rule", manifest: file(#"{"id": "deploys"}"#)))
                         == .invalid(.idWithoutDot("deploys")),
                     "a manifest that breaks a rule is refused for that rule, whatever the folder holds")
    }
}
```

In `Tests/TestGroups.swift`, replace

```swift
            ("platform", { ToolPlatformTests.run(suite); ToolBrokerTests.run(suite) }),
```
with
```swift
            ("platform", {
                ToolPlatformTests.run(suite)
                ToolBrokerTests.run(suite)
                ExternalToolManifestTests.run(suite)
            }),
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform`
Expected: FAIL to compile, with "cannot find 'ExternalToolManifest' in scope" among the errors.

- [ ] **Step 4: Let a request be made without a reason, for an outside tool only**

In `Sources/Vitruvian/Core/Platform/ToolManifest.swift`, in `CapabilityRequest`, replace

```swift
        self.capability = capability
        self.reason = reason
        self.startsWithoutGrant = startsWithoutGrant
    }
}
```
with
```swift
        self.capability = capability
        self.reason = reason
        self.startsWithoutGrant = startsWithoutGrant
    }

    /// A service an outside tool's manifest lists in `uses`. It has no
    /// reason: nobody is asked to approve an outside tool's services one by
    /// one, so its manifest gives none. Such a tool is never held back for a
    /// macOS grant either: it starts, and each call of a capability that
    /// rides on a grant is refused until the grant is there.
    package init(usedByOutsideTool capability: Capability) {
        self.capability = capability
        self.reason = ""
        self.startsWithoutGrant = !capability.ridesOn.isEmpty
    }
}
```

The first `self.capability = capability` in the file is the one to match: the three lines appear once.

- [ ] **Step 5: Write the reader**

Create `Sources/Vitruvian/Core/Platform/ExternalToolManifest.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// Why a folder is not a tool the app can add. Each case carries what is
/// needed to say which part is wrong; the words are for whoever shows it.
package enum ManifestRefusal: Error, Equatable, Sendable {
    /// The folder has no `vitruvian-tool.json`, or the file cannot be read.
    case noManifest
    /// The file breaks one of the manifest's own rules.
    case invalid(ManifestProblem)
    /// The manifest names something the protocol has and this app does not:
    /// a service, a surface, a kind of preference, or a way of starting.
    case notOfferedHere(String)
    /// There is no file at the program's path.
    case programMissing(String)
    /// The program is, through a link, a file outside the tool's folder.
    case programOutsideFolder(String)
    /// The program is not a file macOS will run.
    case programNotExecutable(String)
}

/// A tool that runs as its own program, as its manifest file describes it:
/// the manifest the platform already has for a built-in tool, and what only
/// an outside tool carries.
///
/// Nothing in the app reads one yet. The runtime that starts such a tool,
/// and the sheet that asks before adding it, come later.
package struct ExternalToolManifest: Equatable, Sendable {
    /// The tool as the rest of the platform knows a tool. Its name and its
    /// commands' titles are the English ones.
    package let manifest: ToolManifest
    /// The tool's name in every language its author wrote it in.
    package let name: LocalizedText
    /// One sentence on what the tool does.
    package let summary: LocalizedText?
    /// Each command's title in every language its author wrote it in.
    package let commandTitles: [CommandID: LocalizedText]
    package let version: String
    package let publisher: String
    package let license: String?
    /// The protocol version the tool speaks.
    package let protocolVersion: String
    /// The program to start, as a path inside the tool's folder.
    package let program: String

    /// What a tool or a command with no icon draws.
    package static let defaultSymbol = "puzzlepiece.extension"
    /// The hub group every outside tool is filed under.
    package static var group: FeatureGroup { .tools }

    /// The key a tool's preference is saved under: the tool's id, a slash,
    /// and the preference's id, as a command's id is written. No built-in
    /// preference has a slash in its key, and no two tools share an id.
    package static func storageKey(tool: ToolID, preference: String) -> String {
        "\(tool.rawValue)/\(preference)"
    }

    /// Reads the tool in `folder`: its manifest, and that the program the
    /// manifest names is a file inside the folder that macOS will run.
    package static func read(folder: URL,
                             fileManager: FileManager = .default) -> Result<ExternalToolManifest, ManifestRefusal> {
        let path = folder.appendingPathComponent(ToolManifestFile.fileName).path
        // Asked before the file is read, so a huge file is never loaded.
        if let size = (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int,
           size > ManifestLimits.maxBytes {
            return .failure(.invalid(.tooLarge(bytes: size)))
        }
        guard let data = fileManager.contents(atPath: path) else { return .failure(.noManifest) }
        switch read(data) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let tool):
            if let refusal = programRefusal(tool.program, in: folder, fileManager: fileManager) {
                return .failure(refusal)
            }
            return .success(tool)
        }
    }

    /// Reads a manifest's bytes: every rule that needs no folder.
    package static func read(_ data: Data) -> Result<ExternalToolManifest, ManifestRefusal> {
        switch ToolManifestFile.read(data) {
        case .failure(let problem): return .failure(.invalid(problem))
        case .success(let file): return tool(from: file)
        }
    }

    /// Maps a manifest file that passed its own rules onto the app's lists.
    /// Those lists are closed: a name the protocol has and the app does not
    /// is a refusal that names it, never a crash and never a tool with part
    /// of its manifest dropped.
    static func tool(from file: ToolManifestFile) -> Result<ExternalToolManifest, ManifestRefusal> {
        guard let id = ToolID(file.id), !id.isBundledForm else {
            return .failure(.invalid(.idNotWellFormed(file.id)))
        }

        var capabilities: [CapabilityRequest] = []
        for service in file.uses ?? [] {
            guard let capability = Capability(rawValue: service) else { return .failure(.notOfferedHere(service)) }
            capabilities.append(CapabilityRequest(usedByOutsideTool: capability))
        }

        var commands: [CommandDescriptor] = []
        var titles: [CommandID: LocalizedText] = [:]
        for command in file.contributes?.commands ?? [] {
            var surfaces = Set<ToolSurface>()
            for name in command.surfaces ?? [] {
                guard let surface = ToolSurface(rawValue: name) else { return .failure(.notOfferedHere(name)) }
                surfaces.insert(surface)
            }
            guard let commandID = CommandID(tool: id, name: command.id),
                  let descriptor = CommandDescriptor(id: commandID, title: command.title.english ?? "",
                                                     symbol: symbol(command.icon ?? file.icon), surfaces: surfaces)
            else { return .failure(.invalid(.commandNotWellFormed(command.id))) }
            commands.append(descriptor)
            titles[commandID] = command.title
        }

        var preferences: [PreferenceDeclaration] = []
        for preference in file.preferences ?? [] {
            guard let value = value(preference.default, ofKind: preference.type) else {
                return .failure(.notOfferedHere(preference.type))
            }
            preferences.append(PreferenceDeclaration(key: storageKey(tool: id, preference: preference.id),
                                                     default: value))
        }

        var activation: [Activation] = []
        for name in file.activation ?? [] {
            guard let when = Activation(rawValue: name) else { return .failure(.notOfferedHere(name)) }
            if !activation.contains(when) { activation.append(when) }
        }
        if activation.isEmpty { activation = [.onCommand] }

        // Not reached while the file's own rules hold: they are the rules
        // these two initializers check again.
        guard let descriptor = ToolDescriptor(id: id, name: file.name.english ?? "", symbol: symbol(file.icon),
                                              commands: commands),
              let manifest = ToolManifest(tool: descriptor, group: group, capabilities: capabilities,
                                          preferences: preferences, activation: activation, enabledBy: nil)
        else { return .failure(.invalid(.malformed(field: "id"))) }

        return .success(ExternalToolManifest(manifest: manifest, name: file.name, summary: file.description,
                                             commandTitles: titles, version: file.version,
                                             publisher: file.publisher, license: file.license,
                                             protocolVersion: file.`protocol`, program: file.runtime.exec))
    }

    /// An icon as a symbol name; the plain puzzle piece when there is none.
    /// Whether this Mac has the symbol is for whoever draws it.
    static func symbol(_ icon: String?) -> String {
        guard let icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return defaultSymbol }
        return icon
    }

    /// A preference's default as the app holds one; nil for a kind of
    /// preference the app has no value for.
    package static func value(_ json: JSONValue, ofKind kind: String) -> PreferenceDeclaration.Value? {
        switch (PreferenceKind(rawValue: kind), json) {
        case (.string?, .string(let text)): return .string(text)
        case (.boolean?, .bool(let flag)): return .bool(flag)
        case (.integer?, .number(let number)): return Int(exactly: number).map(PreferenceDeclaration.Value.int)
        case (.number?, .number(let number)): return .double(number)
        default: return nil
        }
    }

    /// Why the program at `program` cannot be started from `folder`, or nil
    /// when it can. Links are followed first: the app runs a copy of the
    /// folder, and a link out of it would point at something the copy does
    /// not hold.
    static func programRefusal(_ program: String, in folder: URL, fileManager: FileManager) -> ManifestRefusal? {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let file = folder.appendingPathComponent(program).resolvingSymlinksInPath().standardizedFileURL
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return .programMissing(program)
        }
        let inside = file.pathComponents.count > root.count && Array(file.pathComponents.prefix(root.count)) == root
        guard inside else { return .programOutsideFolder(program) }
        guard fileManager.isExecutableFile(atPath: file.path) else { return .programNotExecutable(program) }
        return nil
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`
Expected: PASS. `ToolPlatformTests` and `ToolBrokerTests` report as before; in particular "a capability with no reason is not a request" and "capabilities are named as the platform design names them" still hold.

If "a link to a file outside the folder is refused" fails with `nil`, the two paths were resolved differently. `resolvingSymlinksInPath()` drops a leading `/private` when what is left exists, and the temporary folder is under `/private/var`. Both paths go through the same call, so they should agree; if they do not, compare `URL.resourceValues(forKeys: [.canonicalPathKey])` of each instead.

Run: `bazel test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test`
Expected: PASS, both, with no edit to either script or to `bazel/sources.bzl`.

- [ ] **Step 7: Pin the protocol's sources, so a change to them reaches this app**

In `bazel/pin_nexus_agent_shared.py`, make these six changes. The file keeps its name: it now pins two sets.

Replace the docstring's first line and its paragraph

```python
"""Pins the shared Nexus Agent sources this app is built from.

Those sources live in apps/desktop/nexus-agent. This app releases only when a
file under apps/desktop/vitruvian changes, so a fix made only there would ship
in the standalone app and never in this one, with nothing saying so. The pin
makes every such change also change this folder.
"""
```
with
```python
"""Pins the sources this app is built from that live outside its folder.

Two sets of them do: the shared Nexus Agent code, in apps/desktop/nexus-agent,
and the tool protocol's Swift code, in packages/vitruvian-sdk. This app is
tested and released only when a file under apps/desktop/vitruvian changes, so
a change made only there would reach neither this app's tests nor its next
release, with nothing saying so. A pin makes every such change also change
this folder. `--name` says which set; the default is the Nexus Agent's.
"""
```

Replace

```python
PIN = "apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256"
```
with
```python
# Each set: what to call it, and the target that pins it again.
PINS = {
    "nexus_agent_shared": ("The shared Nexus Agent code", "pin_nexus_agent_shared"),
    "tool_protocol": ("The tool protocol's Swift code", "pin_tool_protocol"),
}
```

Replace

```python
    parser.add_argument("--check", metavar="PIN_FILE")
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    current = digest(args.sources)
```
with
```python
    parser.add_argument("--check", metavar="PIN_FILE")
    parser.add_argument("--name", default="nexus_agent_shared", choices=sorted(PINS))
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    current = digest(args.sources)
    what, target = PINS[args.name]
    pin = f"apps/desktop/vitruvian/bazel/{args.name}.sha256"
```

Replace

```python
            "The shared Nexus Agent code changed and this app's pin did not.\n"
            "  1. bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared\n"
```
with
```python
            f"{what} changed and this app's pin did not.\n"
            f"  1. bazel run //apps/desktop/vitruvian:{target}\n"
```

Replace

```python
            "Run with: bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared",
```
with
```python
            f"Run with: bazel run //apps/desktop/vitruvian:{target}",
```

Replace

```python
    Path(root, PIN).write_text(current + "\n")
    print(f"pinned {current[:12]} in {PIN}")
```
with
```python
    Path(root, pin).write_text(current + "\n")
    print(f"pinned {current[:12]} in {pin}")
```

With no `--name` the script does exactly what it did: the two existing targets pass none.

In `BUILD`, add after `nexus_agent_shared_pin_test`:

```python
# The same guard for the tool protocol's Swift sources (packages/vitruvian-sdk),
# which VitruvianCore links. It does two jobs. A change to them must also
# change this folder, or this app would never release it. And it is the only
# test here that depends on them and is not `manual`, so it is what makes the
# presubmit planner run this app's unit when only the package changed.
TOOL_PROTOCOL = ["//packages/vitruvian-sdk:protocol_sources"]

TOOL_PROTOCOL_ARGS = [
    "--name",
    "tool_protocol",
] + ["$(rootpaths %s)" % group for group in TOOL_PROTOCOL]

py_binary(
    name = "pin_tool_protocol",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = TOOL_PROTOCOL_ARGS,
    data = TOOL_PROTOCOL,
    main = "bazel/pin_nexus_agent_shared.py",
)

py_test(
    name = "tool_protocol_pin_test",
    size = "small",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = [
        "--check",
        "$(rootpath bazel/tool_protocol.sha256)",
    ] + TOOL_PROTOCOL_ARGS,
    data = ["bazel/tool_protocol.sha256"] + TOOL_PROTOCOL,
    main = "bazel/pin_nexus_agent_shared.py",
)
```

In the `pipeline_unit`, replace

```python
        ":nexus_agent_shared_pin_test",
        ":unit_tests",
```
with
```python
        ":nexus_agent_shared_pin_test",
        ":tool_protocol_pin_test",
        ":unit_tests",
```

And in the comment at the top of `BUILD`, after the three lines about `:nexus_agent_shared_pin_test`, add:

```python
#   :tool_protocol_pin_test
#                         the tool protocol's Swift sources match the pin in
#                         bazel/tool_protocol.sha256 (Linux-safe)
```

Write the pin, then check both pins:

```sh
printf 'not pinned yet\n' > apps/desktop/vitruvian/bazel/tool_protocol.sha256
bazel run //tools/format -- apps/desktop/vitruvian/BUILD apps/desktop/vitruvian/bazel/pin_nexus_agent_shared.py
bazel test //apps/desktop/vitruvian:tool_protocol_pin_test --test_output=errors
```

Expected: FAIL, saying "The tool protocol's Swift code changed and this app's pin did not." and naming `pin_tool_protocol`. That is the test seeing a stale pin.

```sh
bazel run //apps/desktop/vitruvian:pin_tool_protocol
bazel test //apps/desktop/vitruvian:tool_protocol_pin_test //apps/desktop/vitruvian:nexus_agent_shared_pin_test
git diff --stat -- apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256
```

Expected: `pinned <twelve hex digits> in apps/desktop/vitruvian/bazel/tool_protocol.sha256`; both tests PASS; the last command prints nothing, because the Nexus Agent's pin did not move.

Regenerate the presubmit workflow and check the lane:

```sh
bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
grep -n "tool_protocol_pin_test" .github/workflows/presubmit.yaml
```

Expected: one line, the `bazel test` line of the `vitruvian-desktop-macos` job. The app's manifest tests are in `:unit_tests`, which that same line already names.

- [ ] **Step 8: Prove nothing calls the reader**

```sh
git grep -n "ExternalToolManifest\|ManifestRefusal\|usedByOutsideTool\|VitruvianToolProtocol" -- apps/desktop/vitruvian/Sources
```

Expected: matches in `Core/Platform/ExternalToolManifest.swift`, and one in `Core/Platform/ToolManifest.swift` (the new initializer). No other file. A release build therefore runs no line of this stage.

- [ ] **Step 9: Plant two regressions the tests must catch**

In `Tests/mutation_checks.py`, add to the end of `MUTATIONS` (each entry is name, test group, file, text before, text after, the failing expectation's message):

```python
    ("a tool's program may be a link out of its folder", "platform",
     "Sources/Vitruvian/Core/Platform/ExternalToolManifest.swift",
     "        guard inside else { return .programOutsideFolder(program) }\n",
     "",
     "a program that is a link to a file outside the folder is refused"),
    ("an outside tool waits for a macOS grant before it starts", "platform",
     "Sources/Vitruvian/Core/Platform/ToolManifest.swift",
     "        self.startsWithoutGrant = !capability.ridesOn.isEmpty\n",
     "        self.startsWithoutGrant = false\n",
     "an outside tool that uses keystrokes starts without Accessibility, and is refused call by call"),
```

Each "before" text must occur exactly once in its file, and must quote the file exactly: if the code differs from this plan, use the code. For each entry: apply it, run `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_arg=--suite=platform --test_output=errors`, confirm it fails with the sixth field among the messages, undo it by hand, and confirm `git diff --stat -- <file>` shows only this task's own change. If a mutation is not detected, stop and report: do not adjust a test to fit.

Run: `bazel run //tools/format -- apps/desktop/vitruvian/Tests/mutation_checks.py`

- [ ] **Step 10: Log it, and commit**

In `UPSTREAM.md`, under "## Modifications", add as the first entry of the list, above the stage C entry:

```markdown
- **<date>**: Tool platform, tools that run as their own programs, stage A (`docs/superpowers/plans/2026-10-10-vitruvian-external-tools-stage-a.md`):
  - `Core` now links `VitruvianToolProtocol`, an MIT module in `packages/vitruvian-sdk` that VitruvianSoftware wrote: the tool protocol's messages and the manifest file, with the rules a manifest must keep. Nothing upstream wrote is in it, and it imports nothing of this app. Its Swift sources are pinned in `bazel/tool_protocol.sha256`; `tool_protocol_pin_test` fails when they change and the pin does not.
  - New files, none with an upstream header: `Core/Platform/ExternalToolManifest.swift` (reads a tool's folder into a `ToolManifest`, or a reason it cannot be added), with its tests in `Tests/ExternalToolManifestTests.swift`. Nothing in the app calls it yet, so no build behaves differently.
  - `Core/Platform/ToolManifest.swift`: `CapabilityRequest` gains a second initializer, for a service an outside tool's manifest lists, which has no reason. The one built-in tools use is unchanged.
  - `bazel/pin_nexus_agent_shared.py`: takes `--name`, so it also pins the tool protocol's sources. With no `--name` it does what it did.
  - `BUILD`: `VitruvianCore` and the unit tests depend on the module; `pin_tool_protocol` and `tool_protocol_pin_test`.
  - `Tests/TestGroups.swift`: the `platform` suite also runs `ExternalToolManifestTests`.
  - `Tests/mutation_checks.py`: two mutations (a tool's program that is a link out of its folder; an outside tool held back for a macOS grant).
```

`<date>` is the day of the commit, as `2026-10-10` is written elsewhere in the log.

```bash
git add apps/desktop/vitruvian/BUILD apps/desktop/vitruvian/bazel/pin_nexus_agent_shared.py apps/desktop/vitruvian/bazel/tool_protocol.sha256 apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ExternalToolManifest.swift apps/desktop/vitruvian/Sources/Vitruvian/Core/Platform/ToolManifest.swift apps/desktop/vitruvian/Tests/ExternalToolManifestTests.swift apps/desktop/vitruvian/Tests/TestGroups.swift apps/desktop/vitruvian/Tests/mutation_checks.py apps/desktop/vitruvian/UPSTREAM.md .github/workflows/presubmit.yaml
git commit -m "refactor(desktop): read a tool's manifest file into the platform's manifest"
```

---

### Task 7: Document, bring the spec in line, and run everything

**Files:**
- Create: `packages/vitruvian-sdk/README.md`
- Modify: `apps/desktop/vitruvian/AGENTS.md`
- Modify: `docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md`

- [ ] **Step 1: Say what the package is**

Create `packages/vitruvian-sdk/README.md`:

````markdown
# vitruvian-sdk

What you build a Vitruvian tool against.

A tool is a separate program, in any language, that the Vitruvian desktop app
starts and talks to in JSON over the program's standard input and output. It
adds commands to the app: to the command bar, the radial menu, the Quick
panel, and as shortcuts.

**A tool is trusted like an app.** It runs as you, with every permission
Vitruvian has. The app does not limit or check what it does.

This package is being built in stages. What is here today:

| Folder | What it is |
|---|---|
| [`protocol/`](protocol/README.md) | The protocol, version 1: the manifest and every message as JSON Schema, with examples. The source of truth. Start here. |
| `Sources/VitruvianToolProtocol` | The same protocol as Swift types: the messages, one message per line, the manifest file and its rules. The app links this module. |
| `conformance/` | A script that plays the app's side to your tool, and the smallest tool that passes it. |

Still to come: a Swift library to write a tool with, a `vitruvian-tool`
command, and samples. The app cannot add a tool yet. Nothing here is published
anywhere; the package is used from this repository.

## A tool, in short

A folder with a manifest and a program:

```
reference-tool/
  vitruvian-tool.json
  bin/reference_tool.py
```

`conformance/reference-tool` is exactly that, in 80 lines of Python with no
dependencies. Read it beside [`protocol/README.md`](protocol/README.md).

## Checking a tool

```sh
python3 conformance/conformance.py path/to/your-tool
```

It needs Python 3 and nothing else, and it does not need the app. It starts
your tool's program the way the app does and checks five things: the
handshake, a command, a command you do not have, the same command with every
request you make refused, and shutdown. It exits with 0 when all five pass.

- `--via PROGRAM` starts your program through another one, for example
  `--via python3` for a script that is not executable.
- `--expect-refusal` fails unless something was refused. Use it when your
  command calls the app, to be sure the refusal path ran.

From this repository the same script is
`bazel run //packages/vitruvian-sdk:conformance -- path/to/your-tool`.

## Working on the package

```sh
bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test
```

The first needs a Mac. It checks the Swift types against the example files.
The second checks the same example files against the schemas, and the
conformance script against the reference tool. Together they keep the schemas
and the Swift types from drifting apart: see "Changing the protocol" in
[`protocol/README.md`](protocol/README.md).

`BUILD` and `Package.swift` describe the same targets and must be changed
together. CI builds with Bazel only.

After changing a file under `Sources/VitruvianToolProtocol`, the Vitruvian app
must take the change too:
`bazel run //apps/desktop/vitruvian:pin_tool_protocol`, and a line in
`apps/desktop/vitruvian/UPSTREAM.md`.

## Licence

MIT. See [`LICENSE`](LICENSE). The Vitruvian app that links this package is
GPL-3.0-or-later; nothing from the app's folder may be copied here.
````

- [ ] **Step 2: Write the rules down for the app**

In `apps/desktop/vitruvian/AGENTS.md`, add a section directly above "## Porting from upstream":

```markdown
## Tools that run as their own programs

A tool can be a separate program the app starts and talks to
(`docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md`).
Stage A of that work is built: the protocol, and reading a tool's manifest.
Nothing in the app starts a tool yet.

- The protocol lives in `packages/vitruvian-sdk`, under MIT: JSON Schema in
  `protocol/`, the same messages as Swift in `Sources/VitruvianToolProtocol`.
  The schema is the source of truth. Change a message in the schema, the
  Swift type and an example, in one commit; the package's tests hold the
  three together and can only see a difference an example crosses.
- `Core` links `VitruvianToolProtocol`. A file that uses it imports it by
  name. It is not re-exported from `Core`, and it never imports a
  `Vitruvian*` module.
- After changing a file under
  `packages/vitruvian-sdk/Sources/VitruvianToolProtocol`, run
  `bazel run //apps/desktop/vitruvian:pin_tool_protocol` and add a line to the
  log in `UPSTREAM.md`. `tool_protocol_pin_test` fails until you do. The pin
  is also what makes CI run this app's tests for a change made only in the
  package.
- A manifest's own rules are in the package (`ToolManifestFile.read`), so
  the command-line tool a tool's author runs applies the same ones. This app
  adds what only it can know, in `Core/Platform/ExternalToolManifest.swift`:
  the program is a file inside the folder that macOS will run, and every
  name maps onto the app's closed lists (`Capability`, `ToolSurface`,
  `Activation`, `PreferenceDeclaration.Value`). A name the app does not have
  is a refusal that names it, never a crash and never a tool with part of
  its manifest dropped.
- `ManifestRefusal` and `ManifestProblem` carry values, never sentences.
  Whoever shows one writes the words, in all fifteen languages.
- An outside tool's id has a dot; a built-in tool's has none. Its
  capabilities are made with `CapabilityRequest(usedByOutsideTool:)`, which
  has no reason. A built-in tool never uses that initializer.
- `ToolDescriptor.name` and `CommandDescriptor.title` of an outside tool are
  its English text. Its other languages are in `ExternalToolManifest.name`
  and `.commandTitles`; a surface asks `text(for: language.rawValue)`.
```

- [ ] **Step 3: Bring the spec in line with what was built**

In `docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md`:

- Section 4, decision 12: add that the app imports the module by name in `Core` and does not re-export it, and that its sources are pinned in the app's folder (`tool_protocol_pin_test`), for the two reasons in this plan's decision 13.
- Section 6, under "Rules", add four:
  - `id`, `name`, `version`, `protocol`, `publisher` and `runtime` are required; everything else may be left out, and a tool with no `activation` is `onCommand`.
  - `uses` may name `notify`, `open`, `clipboard.read`, `clipboard.write`, `keystrokes`, `processes` and `storage`. `hotkey` and `clipboard.rewrite` are built-in tools' and are refused as unknown.
  - A preference is `{ id, type, default }`; `type` is `string`, `boolean`, `integer` or `number`, and the default is of that type.
  - Text in several languages is a map from a language tag to text. A language is its own entry, else its language without the region, else English.
- Section 6, the rule "`exec` stays inside the folder": add that it is checked by its text and, in the app, against the real folder with links followed; and that a program that is missing, or that macOS will not run, is refused too.
- Section 6, the rule about the icon: add that an icon never refuses a manifest.
- Section 9: after the first paragraph, add that `packages/vitruvian-sdk/protocol/` is the full statement of version 1 and that this section is its summary. Then record what stage A pinned down: a request id is a whole number or a string; a command is named by its bare id; `shutdown` is a notice; everything a tool asks of the app is a request, and `commands/state` and `log` are notices; `commands/state` carries the whole list of commands that can run; a request that is simply done answers `{}`; a blank line is ignored; 1 MB is 1,048,576 bytes without the line break.
- Section 9, "A refusal": add the codes. -32001 not listed in `uses`, -32002 not installed, -32003 a macOS permission missing, -32004 not available right now; -32010 for a tool that will not run a command; JSON-RPC's own five for a message that cannot be handled.
- Section 9, the table of what a tool asks: `keystrokes/pressMenuItem` takes a list of key equivalents, each a character and the modifiers held with Command; `processes/terminate` takes a process id, its name and whether to force.
- Section 10, first bullet: replace "in `Core`, with the rules of section 6" with "in `Core` (`ExternalToolManifest`), which applies the rules of section 6. The rules that need only the file are in the package's `ToolManifestFile.read`, so the command-line tool applies the same ones; `Core` adds the checks against the real folder and the mapping onto the app's closed lists".
- Section 11, the table: `Conformance/` is `conformance/` and `Samples/` will be `samples/`, lower case, as the repository's naming lint wants outside a Swift source tree. `protocol/` also holds `methods.json`, the table of messages, and `examples/`. The conformance script is Python 3 with no dependencies and checks five things: the handshake, a command, an unknown command, the command again with every request refused, and shutdown. The reference tool it is proven against is `conformance/reference-tool`; stage D's plain-Python sample grows from it or replaces it.
- Section 11, the sentence about the drift test: replace it with the three things the test proves and the one it does not, from "What the drift test proves" in this plan.
- Section 15: mark stage A built. In its row, add "and a pin of the protocol's sources in the app".
- Section 16: add that the stage A plan changes or adds to this spec in the ways its decisions table lists.

- [ ] **Step 4: Run everything**

With the display awake and the screen unlocked, from the repository root, one command at a time:

```sh
bazel test --config=macos-app //packages/vitruvian-sdk:VitruvianToolProtocolTests
bazel test //packages/vitruvian-sdk:protocol_examples_test //packages/vitruvian-sdk:conformance_test
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/vitruvian:selftest //apps/desktop/vitruvian:fan_helper_selftest
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:nexus_agent_shared_pin_test //apps/desktop/vitruvian:tool_protocol_pin_test
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian //apps/desktop/vitruvian:VitruvianLibWithSampleTool
bazel run //tools/license:check
bazel run //tools/license:verify
bazel run //:tidy
bazel run //tools/pipeline:gen -- --format=workflow --output-file=.github/workflows/presubmit.yaml
git status --short
```

Expected: every test passes and every unit suite reports. The app builds with the module linked, which is the first time the package is compiled for the app's deployment target, macOS 14. `//:tidy` and the generator change nothing, so `git status` shows only this task's three files. If `//:tidy` writes a `BUILD` file under `packages/vitruvian-sdk/`, one of the `gazelle:exclude` lines of Task 1 is not doing its job: fix the line, delete the file, and do not commit it. If it reformats a `.json` or `.py` file of the package, keep what it wrote, run the package's three tests again, and add the file to this commit: the Tidy Check job would have asked for the same.

There is nothing to check by hand in this stage: it has no screen and starts no program from the app. Say so in the pull request, and that `selftest` passing is the evidence that a release build still launches.

- [ ] **Step 5: Commit, and open the pull request**

```bash
git add packages/vitruvian-sdk/README.md apps/desktop/vitruvian/AGENTS.md docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md
git commit -m "refactor(desktop): document the tool protocol package and the manifest reader"
```

Open one pull request, titled `refactor(desktop): the tool protocol package, and a tool's manifest read from a file`. `main` takes squash merges, so that title is the commit; it cuts no release. Its description states what was run and on which Mac and macOS version, that nothing a person can see changed, and what remains untested: `Package.swift` is not built by CI; the conformance script has been run against one tool; and the reader has no caller.

---

## What stage A leaves for stage B

- **The reader has no caller.** Stage B's development switch is the first: it reads one folder with `ExternalToolManifest.read(folder:)` and hands the result to the tool host.
- **Nothing turns a method into its Swift types except a test.** `ProtocolExamplesTests` holds the table from `ToolMethod` to params and result. The runtime needs it as code: either a `switch` of its own or a small protocol in the package (`associatedtype Result`, `static var method`). The kit in stage D wants the second.
- **Three conversions the wire leaves to the app** (decision 16): modifier names to `MenuKeyEquivalent.modifierMask`; a process id to the start time `ProcessesAccess.terminate` wants; a preference's id to its saved key, `ExternalToolManifest.storageKey`.
- **The saved key of a preference is decided and unused.** `storage` cannot write yet, and a key with a slash has not met `UserDefaults`, settings backup or a full uninstall. If any of them objects, change `storageKey` and its one expectation.
- **`startsWithoutGrant` is set for every outside tool that uses `keystrokes`.** The host's run rule then starts it without Accessibility. Stage B decides whether the host's rule is even asked for an outside tool, which starts on a command and not at launch.
- **`ManifestRefusal.notOfferedHere` cannot be reached today**, because a test holds the protocol's lists inside the app's. It is what a newer package meets in an older app; it has no test that reaches it through a file.
- **The limits of spec section 7 that are behaviour, not wire**: the two deadlines, the message rate, the count of lines that are not messages, the restart waits, the log's size. `LineSplitter` reports an over-long line as `.oversized`; what to do about it is the runtime's.
- **The conformance script knows one tool.** It does not validate a tool's messages against the schemas, and it has no check for a flood or a hang. Stage D's samples are its next two subjects.
- **`jsonschema` is a dependency by accident** (it arrives with `mcp`). If stage D makes the package's tests matter more, name it in `requirements/tools.in`.
- **`Package.swift` is unbuilt.** Stage D, which is for tool authors who use SwiftPM, should build it once in CI or by hand and say which.
- **Stage C's words.** Every `ManifestProblem` and `ManifestRefusal` case needs a sentence in fifteen languages. There are twenty-two and six; many can share one sentence with the value put in.
