# Nexus Agent shared rules (step 1 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One copy of Nexus Agent's pure rules, built into both the standalone Mac app and the Vitruvian desktop app.

**Architecture:** Two Foundation-only files move from Vitruvian's `Core/NexusAgent/` into the standalone's existing `NexusAgentCore` library and become MIT. Vitruvian re-exports that library from `VitruvianCore`, so none of its other files change. The standalone drops its own copies of the same rules. Two guards are added: the standalone is built the mirror's way in this repo's CI, and a content pin forces every shared change to touch Vitruvian's folder so it ships in Vitruvian's release.

**Tech Stack:** Swift 6 (Xcode 27 here), Bazel (`rules_swift`, `--config=macos-app`), SwiftPM for the public mirror, XCTest, Python 3 for the pin check.

**Spec:** `docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`. This plan covers section 9 step 1 only. Steps 2, 3 and 4 each get their own plan once this one has settled the language-mode and release questions.

## Global Constraints

- No behaviour change in Vitruvian. The standalone changes only where Task 3's table says so.
- Only files whose header names VitruvianSoftware alone, with no upstream-authored lines in `git log`, may leave `apps/desktop/vitruvian`.
- Moved files carry the MIT header used in `apps/desktop/nexus-agent`.
- `macos/BUILD` and `macos/Package.swift` in `apps/desktop/nexus-agent` declare the same targets in the same commit.
- Every Swift Bazel command needs `--config=macos-app`. Vitruvian's and the standalone's Swift targets are tagged `manual`: name them explicitly.
- Never run a bare `git stash`. Never `cd` out of the worktree; use repo-root-relative paths.
- Vitruvian's module order `Core <- Design <- Services <- UI <- App` stays intact. `VitruvianCore` may depend on `NexusAgentCore`; nothing in `NexusAgentCore` may import a Vitruvian module.
- All changes ship through one pull request and the merge queue.

## Review Focus

1. **The mirror builds with an older Swift than this repo's CI** (`macos-15` there, `xcode-27` here). A newer-syntax line passes here and fails every mirror release. Pinned by Task 1 Step 7.
2. **A `.env` line with an empty value (`AGY_MODEL=`)** must leave the standalone's field untouched, as it does today. Pinned by Task 3 Step 1.
3. **`AGY_BIN` pointing at a file that is not executable.** Today the standalone uses it and fails at run time; after this change it falls back to the usual install folders. Pinned by Task 3 Step 1 and listed for James in the PR.
4. **A shared change that never reaches Vitruvian users.** Pinned by Task 5.
5. **A quoted title containing `archived:true`** must not hide a conversation in either app. Already tested on both sides; Task 3 Step 1 keeps the test alive under its new name.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentSupport.swift` | moved in | `.env` rules, agy discovery, stream parsing |
| `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentQuickPromptLayout.swift` | moved in | window geometry, session lists, archive rule, reply blocks |
| `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/AntigravityAnnotations.swift` | deleted | superseded by the Layout file |
| `apps/desktop/nexus-agent/macos/Tests/AntigravityAnnotationsTests.swift` | renamed to `ArchiveRuleTests.swift` | archive rule under its shared name |
| `apps/desktop/nexus-agent/macos/Tests/SharedRulesTests.swift` | new | standalone-facing rule differences |
| `apps/desktop/nexus-agent/macos/Tests/Ported*.swift` | new | the ten pure suites from Vitruvian |
| `apps/desktop/nexus-agent/macos/scripts/mirror_build_test.sh` | new | builds the package with SwiftPM |
| `apps/desktop/nexus-agent/macos/{BUILD,Package.swift}` | modified | Swift 6 for the core, visibility, guard |
| `apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgentCoreExport.swift` | new | re-export, as `FanControlKitExport.swift` does |
| `apps/desktop/vitruvian/bazel/pin_nexus_agent_shared.py` + `nexus_agent_shared.sha256` | new | the content pin |
| `apps/desktop/vitruvian/{BUILD,build.sh,bazel/sources.bzl,UPSTREAM.md,AGENTS.md}` | modified | dependency, source list, licence record, fork rule |
| `apps/desktop/vitruvian/Tests/NexusAgentTests.swift` | modified | ten ported suites removed |

---

### Task 1: Make `NexusAgentCore` a Swift 6 library both builds agree on

**Files:**
- Modify: `apps/desktop/nexus-agent/macos/BUILD`
- Modify: `apps/desktop/nexus-agent/macos/Package.swift`
- Create: `apps/desktop/nexus-agent/macos/scripts/mirror_build_test.sh`
- Regenerate: `.github/workflows/presubmit.yaml` (generated; never hand-edit)

**Interfaces:**
- Produces: Bazel targets `//apps/desktop/nexus-agent/macos:NexusAgentCore` (Swift 6 mode, visible to `//apps/desktop/vitruvian:__pkg__`), `:shared_sources` (filegroup of the core's `.swift` files, same visibility) and `:mirror_build_test`.

- [ ] **Step 1: Write the mirror-build guard (the failing test)**

Create `apps/desktop/nexus-agent/macos/scripts/mirror_build_test.sh`, executable:

```bash
#!/usr/bin/env bash
# Builds the package with SwiftPM, the way VitruvianSoftware/nexus-agent does.
# Bazel is the build this repository runs, so a target missing from
# Package.swift stayed green here while every mirror release failed
# (2026-07-11 to 2026-08-20, #1511, #1851). This fails here instead.
set -euo pipefail

pkg="$TEST_SRCDIR/$TEST_WORKSPACE/apps/desktop/nexus-agent/macos"
work="$TEST_TMPDIR/pkg"
mkdir -p "$work"
cp -RL "$pkg/Package.swift" "$pkg/Sources" "$work/"

export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME"
xcrun swift build --package-path "$work" --scratch-path "$TEST_TMPDIR/build" \
    --cache-path "$TEST_TMPDIR/cache" --disable-sandbox
```

In `apps/desktop/nexus-agent/macos/BUILD`, add the load and the target, and list it in the pipeline unit:

```python
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "mirror_build_test",
    size = "large",
    srcs = ["scripts/mirror_build_test.sh"],
    data = ["Package.swift"] + glob(["Sources/**"]),
    env_inherit = ["DEVELOPER_DIR"],
    # SwiftPM wants the real toolchain and its own sandbox: run outside Bazel's.
    tags = ["local", "manual"],
    target_compatible_with = ["@platforms//os:macos"],
)
```

```python
pipeline_unit(
    name = "nexus-agent-macos",
    depends_on = ["nexus-agent-src"],
    persona = "frontend",
    runner = "xcode-27",
    test_targets = [
        ":NexusAgentTests",
        ":mirror_build_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
```

- [ ] **Step 2: Prove the guard catches the old failure**

Temporarily delete the `NexusAgentCore` target block from `Package.swift`, then run:

`bazel test --config=macos-app //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors`

Expected: FAIL with `no such module 'NexusAgentCore'`. Restore the block. If instead it fails on `xcrun` or the toolchain, fix the script before going on; do not weaken the check.

- [ ] **Step 3: Move both build definitions to Swift 6 for the core only**

`Package.swift`: change the first line to `// swift-tools-version: 6.0` and the targets to:

```swift
        .target(
            name: "NexusAgentCore",
            path: "Sources/NexusAgentCore"
        ),
        .executableTarget(
            name: "NexusAgent",
            dependencies: ["NexusAgentCore"],
            path: "Sources/NexusAgent",
            // The app shell is Swift 5 code. Only the shared core is Swift 6.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
```

Keep the existing "MUST MIRROR" and "STILL DIVERGENT" comments.

`BUILD`: replace the `NexusAgentCore` target and add the filegroup:

```python
# The shared core: built into this app AND into the Vitruvian desktop app
# (docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md).
# Swift 6 mode because Vitruvian's Core module is. Nothing here may import a
# Vitruvian module: the dependency runs one way, MIT into GPL.
swift_library(
    name = "NexusAgentCore",
    srcs = glob(["Sources/NexusAgentCore/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "NexusAgentCore",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = [
        "//apps/desktop/nexus-agent:__subpackages__",
        "//apps/desktop/vitruvian:__pkg__",
    ],
)

filegroup(
    name = "shared_sources",
    srcs = glob(["Sources/NexusAgentCore/**/*.swift"]),
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)
```

- [ ] **Step 4: Run both builds**

```
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent
```

Expected: both tests PASS, the app builds. If the two existing core files fail Swift 6 checking, fix them in place (they are 59 and 50 lines); do not turn Swift 6 off.

- [ ] **Step 5: Regenerate CI**

Run: `bazel run //tools/ci:gen`
Expected: `.github/workflows/presubmit.yaml` gains `:mirror_build_test` in the `nexus-agent-macos` job and nothing else changes. Check with `git diff --stat`.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/nexus-agent/macos .github/workflows/presubmit.yaml
git commit -m "build(nexus-agent): Swift 6 core, and build the package the mirror's way in CI"
```

- [ ] **Step 7: Record what Swift the mirror builds with**

Run: `gh api repos/VitruvianSoftware/nexus-agent/actions/runs --jq '.workflow_runs[0] | {name, conclusion, created_at, html_url}'` and open the latest release run's "Build for arm64" log to read the `swift --version` SwiftPM prints.
Write the version into the PR description under "Mirror toolchain". If it is older than 6.0, stop and report: the tools-version bump would break the mirror, and the spec's fallback (Swift 5 mode with strict concurrency) applies instead.

---

### Task 2: Move the two rule files and re-export them into Vitruvian

**Files:**
- Move: `apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgent/NexusAgentSupport.swift` → `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentSupport.swift`
- Move: `apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgent/NexusAgentQuickPromptLayout.swift` → `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/NexusAgentQuickPromptLayout.swift`
- Create: `apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgentCoreExport.swift`
- Modify: `apps/desktop/vitruvian/BUILD` (the `VitruvianCore` target), `apps/desktop/vitruvian/build.sh:395`, `apps/desktop/vitruvian/bazel/sources.bzl` (generated), `apps/desktop/vitruvian/UPSTREAM.md`

**Interfaces:**
- Consumes: `//apps/desktop/nexus-agent/macos:NexusAgentCore` from Task 1.
- Produces: every type the two files declare, now `public` in module `NexusAgentCore`, with unchanged names and signatures. The ones later tasks call: `NexusAgentEnvFile.assignment(in: String) -> (key: String, value: String)?`, `NexusAgentSupport.locateAgent(named: String = "agy", environment: [String: String], home: String, isExecutable: (String) -> Bool) -> String?`, `NexusAgentSupport.parseModels(_: String) -> [(id: String, name: String)]`, `NexusAgentQuickPromptLayout.antigravityDataDirectories: [String]`, `NexusAgentQuickPromptLayout.antigravityAnnotationIsArchived(_: String) -> Bool`, `NexusAgentQuickPromptLayout.antigravityArchivedSessionIds(home: String) -> Set<String>`.

- [ ] **Step 1: Do the licence check and record it**

```bash
for f in NexusAgentSupport NexusAgentQuickPromptLayout; do
  p=apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgent/$f.swift
  sed -n 1,3p "$p"; git log --follow --format='%an <%ae>' -- "$p" | sort -u
done
```

Expected: each header reads `Copyright (C) 2026 VitruvianSoftware` and names no one else, and no author is an upstream (`vorssaint`) contributor. Paste the output into the PR description under "Licence check". If either file fails, stop and report; that file stays in Vitruvian.

- [ ] **Step 2: Move the files and convert them**

```bash
src=apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgent
dst=apps/desktop/nexus-agent/macos/Sources/NexusAgentCore
git mv $src/NexusAgentSupport.swift $src/NexusAgentQuickPromptLayout.swift $dst/
perl -0pi -e 's/^(\s*)package (?=(?:static|var|let|func|init|enum|struct|final|class|protocol|typealias|indirect|mutating|nonisolated|subscript|private\(set\))\b)/$1public /mg' \
  $dst/NexusAgentSupport.swift $dst/NexusAgentQuickPromptLayout.swift
grep -nE '^\s*package ' $dst/NexusAgentSupport.swift $dst/NexusAgentQuickPromptLayout.swift
```

Expected: the last command prints nothing. Any line it prints is a declaration form the pattern missed: change that `package` to `public` by hand.

In each moved file, replace the first two lines (`// SPDX-License-Identifier: GPL-3.0-or-later` and `// Copyright (C) 2026 VitruvianSoftware`) with the 19-line MIT notice copied verbatim from the top of `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/VersionCompare.swift`. Replace the "Adapted from the standalone Nexus Agent app…" paragraph that follows with:

```swift
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-08 (apps/desktop/vitruvian/UPSTREAM.md).
```

- [ ] **Step 3: Re-export from Vitruvian's Core**

Create `apps/desktop/vitruvian/Sources/Vitruvian/Core/NexusAgentCoreExport.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Nexus Agent's rules live in the standalone app's folder so both apps build
// from one copy (apps/desktop/nexus-agent/macos/Sources/NexusAgentCore, MIT).
// Everything else reaches them through Core, as it did when they lived here.
@_exported import NexusAgentCore
```

In `apps/desktop/vitruvian/BUILD`, change the `VitruvianCore` target's deps to:

```python
    deps = [
        ":FanControlKit",
        "//apps/desktop/nexus-agent/macos:NexusAgentCore",
    ],
```

- [ ] **Step 4: Fix the source list**

Delete line 395 of `apps/desktop/vitruvian/build.sh` (`        Sources/Vitruvian/Core/NexusAgent/NexusAgentSupport.swift`), then run:

`bazel run //apps/desktop/vitruvian:sync_sources`

Expected: `bazel/sources.bzl` loses the same one line.

- [ ] **Step 5: Run Vitruvian's tests unchanged**

```
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test --test_output=errors
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_output=errors
bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
```

Expected: all PASS, with the same check count for the Nexus Agent suite as on `main` (261 `suite.expect` calls in `Tests/NexusAgentTests.swift`, untouched in this task). A "cannot find type" error means a consumer module does not see the re-export: confirm `NexusAgentCoreExport.swift` is under `Core/`. A name clash with `AntigravityAnnotations` or `VersionCompare` is resolved by Task 3 (which deletes the first); if `VersionCompare` clashes, qualify the Vitruvian use as `VitruvianCore.VersionCompare`.

- [ ] **Step 6: Record the licence decision**

In `apps/desktop/vitruvian/UPSTREAM.md`, directly after the "Licensing: this directory is GPL, not Apache" section, add:

```markdown
### Files released under MIT by their copyright holder

The rule above stands for everything upstream wrote. Files that
VitruvianSoftware wrote alone can be released under another licence by
VitruvianSoftware. On 2026-10-08 James approved doing that for Nexus Agent so
the standalone app and this feature build from one copy
(`docs/superpowers/specs/2026-10-08-nexus-agent-shared-library-design.md`).

| Date | File, as it was named here | Now at |
|---|---|---|
| 2026-10-08 | `Core/NexusAgent/NexusAgentSupport.swift` | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/` |
| 2026-10-08 | `Core/NexusAgent/NexusAgentQuickPromptLayout.swift` | `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/` |

Each file was checked before it left: its header named VitruvianSoftware
alone and its history has no upstream author. Not legal advice.
```

Add one line to the dated change log at the end of the file, in the style of the entries above it:

```markdown
- **2026-10-08**: Nexus Agent's pure rules (`NexusAgentSupport`, `NexusAgentQuickPromptLayout`) moved to the shared `NexusAgentCore` library in `apps/desktop/nexus-agent` and are re-exported from `Core/NexusAgentCoreExport.swift`. No behaviour change.
```

- [ ] **Step 7: Commit**

```bash
git add apps/desktop/vitruvian apps/desktop/nexus-agent/macos/Sources/NexusAgentCore
git commit -m "refactor(desktop): build Vitruvian's Nexus Agent rules from the shared core"
```

---

### Task 3: The standalone uses the shared rules

**Files:**
- Delete: `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/AntigravityAnnotations.swift`
- Rename: `apps/desktop/nexus-agent/macos/Tests/AntigravityAnnotationsTests.swift` → `ArchiveRuleTests.swift`
- Create: `apps/desktop/nexus-agent/macos/Tests/SharedRulesTests.swift`
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgent/QuickPromptWindow.swift:1605-1609,1669`
- Modify: `apps/desktop/nexus-agent/macos/Sources/NexusAgent/ConfigManager.swift:194-205,314-321,348-356`

**Interfaces:**
- Consumes: the six functions listed under Task 2 "Produces".

What changes for a standalone user, and nothing else:

| Rule | Before | After |
|---|---|---|
| Archive rule | identical | identical |
| `agy models` parsing | a row with a blank name shows a blank name | shows the id |
| Finding `agy` | `AGY_BIN` used even if not executable | falls back to the install folders |
| Reading `.env` | quotes kept, `export ` and trailing ` # comment` not understood | read the way the bot's dotenv reads them |

- [ ] **Step 1: Write the tests under the shared names**

`git mv apps/desktop/nexus-agent/macos/Tests/AntigravityAnnotationsTests.swift apps/desktop/nexus-agent/macos/Tests/ArchiveRuleTests.swift`, keep its MIT header, and replace everything from `import XCTest` down with:

```swift
import XCTest

import NexusAgentCore

final class ArchiveRuleTests: XCTestCase {
    private typealias Layout = NexusAgentQuickPromptLayout

    func testArchivedInTheShapesAgyWrites() {
        XCTAssertTrue(Layout.antigravityAnnotationIsArchived(
            "archived:true archival_status_timestamp:{seconds:1787464769 nanos:503730000} marked_as_unread:false"))
        XCTAssertTrue(Layout.antigravityAnnotationIsArchived(
            #"title:"Daily Briefing"  archived: true  last_user_view_time:{seconds:1  nanos:2}"#))
    }

    func testNotArchivedWithoutTheField() {
        XCTAssertFalse(Layout.antigravityAnnotationIsArchived("last_user_view_time:{seconds:1790974412  nanos:316000000}"))
        XCTAssertFalse(Layout.antigravityAnnotationIsArchived("archived:false pinned:true"))
        XCTAssertFalse(Layout.antigravityAnnotationIsArchived(""))
    }

    func testATitleCannotPassForTheField() {
        XCTAssertFalse(Layout.antigravityAnnotationIsArchived(#"title:"why is archived:true ignored" pinned:true"#))
    }

    func testArchivedIDsAcrossDataDirectories() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("agy-annotations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let app = home.appendingPathComponent(".gemini/antigravity/annotations")
        let cli = home.appendingPathComponent(".gemini/antigravity-cli/annotations")
        for directory in [app, cli] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "archived:true".write(to: app.appendingPathComponent("a.pbtxt"), atomically: true, encoding: .utf8)
        try "pinned:true".write(to: app.appendingPathComponent("b.pbtxt"), atomically: true, encoding: .utf8)
        try "archived: true".write(to: cli.appendingPathComponent("c.pbtxt"), atomically: true, encoding: .utf8)
        try "archived:true".write(to: cli.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(Layout.antigravityArchivedSessionIds(home: home.path), ["a", "c"])
        XCTAssertEqual(Layout.antigravityArchivedSessionIds(home: home.appendingPathComponent("missing").path), [])
    }
}
```

Create `apps/desktop/nexus-agent/macos/Tests/SharedRulesTests.swift` with the same MIT header and:

```swift
import XCTest

import NexusAgentCore

/// The rules the standalone app took over from its own copies, at the points
/// where the shared rule reads an input differently than the old copy did.
final class SharedRulesTests: XCTestCase {
    func testEnvLinesReadAsTheBotReadsThem() {
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: #"TELEGRAM_BOT_TOKEN="1:abc""#)?.value, "1:abc")
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "export AGY_MODEL=m1")?.key, "AGY_MODEL")
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "AGY_MODEL=m1 # the fast one")?.value, "m1")
        XCTAssertNil(NexusAgentEnvFile.assignment(in: "# AGY_MODEL=m1"))
        XCTAssertNil(NexusAgentEnvFile.assignment(in: "no equals sign"))
    }

    /// The standalone skips an empty value so the field keeps its default.
    func testAnEmptyValueIsReportedAsEmpty() {
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "AGY_MODEL=")?.value, "")
    }

    func testAgyBinMustBeExecutable() {
        let found = NexusAgentSupport.locateAgent(
            environment: ["AGY_BIN": "/nowhere/agy"], home: "/Users/x",
            isExecutable: { $0 == "/opt/homebrew/bin/agy" })
        XCTAssertEqual(found, "/opt/homebrew/bin/agy")
        XCTAssertNil(NexusAgentSupport.locateAgent(environment: [:], home: "/Users/x", isExecutable: { _ in false }))
    }

    func testAModelRowWithABlankNameShowsItsID() {
        let models = NexusAgentSupport.parseModels("Fetching models…\nm1\tFast\nm2\t \n\n")
        XCTAssertEqual(models.map(\.id), ["m1", "m2"])
        XCTAssertEqual(models.map(\.name), ["Fast", "m2"])
    }
}
```

- [ ] **Step 2: Run them**

Run: `bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests --test_output=errors`
Expected: PASS. These rules already exist after Task 2, so the tests pin them rather than drive them. What must fail first is the build in Step 4, when the old copy is deleted before its callers are switched.

- [ ] **Step 3: Switch the app's callers**

`QuickPromptWindow.swift`, in `SessionFileReader`:

```swift
    static var dataDirectories: [URL] {
        NexusAgentQuickPromptLayout.antigravityDataDirectories.map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0)
        }
    }
```

and in `listSessions(workingDirectory:)`:

```swift
        let archived = NexusAgentQuickPromptLayout.antigravityArchivedSessionIds(home: NSHomeDirectory())
```

`ConfigManager.swift`: add `import NexusAgentCore` beside the existing imports, then replace the top of `parseEnv` (the line loop down to the `switch`) so the `switch key { … }` body stays exactly as it is:

```swift
    private func parseEnv(_ content: String) {
        for line in content.components(separatedBy: .newlines) {
            // An empty value is skipped, as before: the field keeps its default.
            guard let (key, value) = NexusAgentEnvFile.assignment(in: line), !value.isEmpty else { continue }

            switch key {
```

In `AgyInfo`:

```swift
    /// AGY_BIN, then the usual install locations, then nil.
    static func locate() -> String? {
        NexusAgentSupport.locateAgent(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(),
                                      isExecutable: FileManager.default.isExecutableFile(atPath:))
    }
```

```swift
    /// `agy models` prints a "Fetching…" line, then `id<TAB>display name` rows.
    static func parseModels(_ raw: String) -> [Model] {
        NexusAgentSupport.parseModels(raw).map { Model(id: $0.id, name: $0.name) }
    }
```

- [ ] **Step 4: Delete the old copy**

```bash
git rm apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/AntigravityAnnotations.swift
grep -rn "AntigravityAnnotations" apps/desktop
```

Expected: the grep prints nothing.

- [ ] **Step 5: Run everything that builds this code**

```
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test //apps/desktop/vitruvian:unit_tests --test_output=errors
bazel build --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgent
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/nexus-agent/macos
git commit -m "refactor(nexus-agent): use the shared rules for .env, agy discovery and archiving"
```

---

### Task 4: Move the pure-rule tests beside the code

**Files:**
- Create: `apps/desktop/nexus-agent/macos/Tests/PortedRulesTests.swift`
- Modify: `apps/desktop/vitruvian/Tests/NexusAgentTests.swift`

Ten suites in Vitruvian's `NexusAgentTests.swift` reference only the moved types (checked 2026-10-08): `envFile` (15 checks), `modes` (6), `locations` (8), `stream` (6), `quickPromptLayout` (8), `sessionIndex` (8), `replyBlocks` (3), `markdownBlocks` (17), `turnMetrics` (3), `claudeSessionTitles` (12): 86 checks. The other fifteen suites touch the service, the session or the notch and stay where they are.

**Interfaces:**
- Consumes: module `NexusAgentCore`.

- [ ] **Step 1: Port the ten suites**

Create `apps/desktop/nexus-agent/macos/Tests/PortedRulesTests.swift` with the MIT header, `import XCTest`, `import CoreGraphics`, `import NexusAgentCore`, and one `final class PortedRulesTests: XCTestCase`. For each of the ten functions, copy its body unchanged into a method named `test<Name>` (`envFile` → `testEnvFile`) and apply exactly these rewrites:

| Vitruvian harness | XCTest |
|---|---|
| `private static func envFile(_ suite: TestSuite) {` | `func testEnvFile() {` |
| `suite.expect(<condition>, <message>)` | `XCTAssertTrue(<condition>, <message>)` |
| `suite.expectClose(a, b, label)` | `XCTAssertEqual(a, b, accuracy: 0.0001, label)` |

Worked example, the first check of `modes`:

```swift
    func testModes() {
        XCTAssertTrue(NexusAgentApprovalMode.parse(nil) == .yolo && NexusAgentApprovalMode.parse("") == .standard
                      && NexusAgentApprovalMode.parse(" PLAN ") == .plan
                      && NexusAgentApprovalMode.parse("accept_edits") == .acceptEdits
                      && NexusAgentApprovalMode.parse("auto_edit") == .acceptEdits
                      && NexusAgentApprovalMode.parse("bogus") == .standard,
                      "approval modes parse as the bot reads them")
```

Change no condition and no message. A helper a suite calls that lives elsewhere in `NexusAgentTests.swift` is copied in as a `private` method; if that helper needs a Vitruvian type, the suite is not pure after all: leave it in Vitruvian and say so in the PR.

- [ ] **Step 2: Count, then run**

```bash
grep -c "XCTAssert" apps/desktop/nexus-agent/macos/Tests/PortedRulesTests.swift
```

Expected: 86 (fewer only by the checks of a suite left behind in Step 1, which must be named in the PR).

Run: `bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests --test_output=errors`
Expected: PASS.

- [ ] **Step 3: Prove a ported test can fail**

In `NexusAgentCore/NexusAgentSupport.swift`, temporarily change `case "plan": return .plan` to `return .standard`, run the same command, and expect `testModes` to FAIL. Revert.

- [ ] **Step 4: Remove the ported suites from Vitruvian**

In `apps/desktop/vitruvian/Tests/NexusAgentTests.swift`, delete the ten functions and their ten calls in `run(_:)`. Then:

```bash
grep -c "suite.expect" apps/desktop/vitruvian/Tests/NexusAgentTests.swift
```

Expected: 175 (261 − 86).

Run: `bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests --test_output=errors`
Expected: PASS, and the Nexus Agent suite prints 175 checks.

Run: `grep -n "NexusAgent" apps/desktop/vitruvian/Tests/mutation_checks.py`
Expected: no output (true on 2026-10-08), so the weekly mutation checks do not depend on a removed suite. If it prints a line, keep the suite that line needs in Vitruvian and say so in the PR.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/nexus-agent/macos/Tests apps/desktop/vitruvian/Tests/NexusAgentTests.swift
git commit -m "test(nexus-agent): the shared rules' tests live beside the shared rules"
```

---

### Task 5: A shared change always touches Vitruvian, and the rule for the next fork

**Files:**
- Create: `apps/desktop/vitruvian/bazel/pin_nexus_agent_shared.py`
- Create: `apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256`
- Modify: `apps/desktop/vitruvian/BUILD`, `apps/desktop/vitruvian/AGENTS.md`

Why a pin and not a diff check: each app releases when its own folder changes. A pin file inside Vitruvian's folder that must match the shared sources forces every shared change to carry a Vitruvian change in the same commit, and it runs inside Bazel on Linux like `sources_in_sync_test`.

**Interfaces:**
- Consumes: `//apps/desktop/nexus-agent/macos:shared_sources` from Task 1.
- Produces: `//apps/desktop/vitruvian:nexus_agent_shared_pin_test` and the runnable `//apps/desktop/vitruvian:pin_nexus_agent_shared`.

- [ ] **Step 1: Write the pin tool**

Create `apps/desktop/vitruvian/bazel/pin_nexus_agent_shared.py`:

```python
#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
"""Pins the shared Nexus Agent sources this app is built from.

Those sources live in apps/desktop/nexus-agent. This app releases only when a
file under apps/desktop/vitruvian changes, so a fix made only there would ship
in the standalone app and never in this one, with nothing saying so. The pin
makes every such change also change this folder.
"""

import argparse
import hashlib
import os
import sys
from pathlib import Path

PIN = "apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256"


def digest(paths):
    h = hashlib.sha256()
    for path in sorted(paths):
        h.update(path.encode())
        h.update(b"\0")
        h.update(Path(path).read_bytes())
        h.update(b"\0")
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", metavar="PIN_FILE")
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    current = digest(args.sources)

    if args.check:
        pinned = Path(args.check).read_text().strip()
        if pinned == current:
            return 0
        print(
            "The shared Nexus Agent code changed and this app's pin did not.\n"
            "  1. bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared\n"
            "  2. add a line for the change to the log in apps/desktop/vitruvian/UPSTREAM.md\n"
            "Both go in the same commit, so the change ships in Vitruvian's next release.",
            file=sys.stderr,
        )
        return 1

    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not root:
        print("Run with: bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared", file=sys.stderr)
        return 2
    Path(root, PIN).write_text(current + "\n")
    print(f"pinned {current[:12]} in {PIN}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Create `apps/desktop/vitruvian/bazel/nexus_agent_shared.sha256` containing the single line `unpinned`.

In `apps/desktop/vitruvian/BUILD`, beside `sources_in_sync_test`, using the `py_binary` and `py_test` rules that file already loads:

```python
# Every change to the shared Nexus Agent sources must also change this folder,
# or this app would never release it (bazel/pin_nexus_agent_shared.py).
SHARED_NEXUS_AGENT = "//apps/desktop/nexus-agent/macos:shared_sources"

py_binary(
    name = "pin_nexus_agent_shared",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = ["$(rootpaths %s)" % SHARED_NEXUS_AGENT],
    data = [SHARED_NEXUS_AGENT],
    main = "bazel/pin_nexus_agent_shared.py",
)

py_test(
    name = "nexus_agent_shared_pin_test",
    size = "small",
    srcs = ["bazel/pin_nexus_agent_shared.py"],
    args = [
        "--check",
        "$(rootpath bazel/nexus_agent_shared.sha256)",
        "$(rootpaths %s)" % SHARED_NEXUS_AGENT,
    ],
    data = [
        "bazel/nexus_agent_shared.sha256",
        SHARED_NEXUS_AGENT,
    ],
    main = "bazel/pin_nexus_agent_shared.py",
)
```

Add `":nexus_agent_shared_pin_test"` to the `test_targets` of the `vitruvian-desktop-macos` pipeline unit at the bottom of that file, after `":sources_in_sync_test"`.

- [ ] **Step 2: Watch it fail**

Run: `bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test --test_output=errors`
Expected: FAIL with "The shared Nexus Agent code changed and this app's pin did not."

- [ ] **Step 3: Pin, and watch it pass**

```
bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared
bazel test //apps/desktop/vitruvian:nexus_agent_shared_pin_test --test_output=errors
```

Expected: the pin file now holds 64 hex characters; the test PASSES.

- [ ] **Step 4: Prove it catches a real edit**

Add a blank line to the end of `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore/VersionCompare.swift`, rerun the test, expect FAIL. Remove the blank line, expect PASS.

- [ ] **Step 5: Write the rule down**

In `apps/desktop/vitruvian/AGENTS.md`, add a section:

```markdown
## Features that are also standalone apps

Nexus Agent ships twice: as its own app (`apps/desktop/nexus-agent`) and as a
feature here. The code both share lives in the standalone's folder, under MIT,
and this app holds only what is specific to it.

- Change a shared rule in `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore`,
  never by copying it back here.
- Shared code takes its settings, text, theme and host hooks as inputs. It
  never imports a `Vitruvian*` module.
- After changing shared code, run
  `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and add a line to
  the log in `UPSTREAM.md`. `nexus_agent_shared_pin_test` fails until you do.
- Nothing upstream wrote may leave this folder. A file leaves only if
  VitruvianSoftware wrote all of it, and `UPSTREAM.md` records it.
- The next standalone app that becomes a feature here follows the same shape.
```

- [ ] **Step 6: Regenerate CI, run the whole set, commit**

```
bazel run //tools/ci:gen
bazel test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:nexus_agent_shared_pin_test --test_output=errors
bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests //apps/desktop/nexus-agent/macos:NexusAgentTests //apps/desktop/nexus-agent/macos:mirror_build_test --test_output=errors
```

Expected: all PASS.

```bash
git add apps/desktop/vitruvian .github/workflows
git commit -m "build(desktop): pin the shared Nexus Agent sources so shared fixes ship in Vitruvian"
```

---

## Before opening the pull request

- [ ] The PR description carries: the Task 3 "what changes for a standalone user" table, the licence-check output (Task 2 Step 1), the mirror's Swift version (Task 1 Step 7), and any suite left behind in Task 4.
- [ ] Every check is green before asking for review.
- [ ] After merge and export, look at the mirror: `gh run list --repo VitruvianSoftware/nexus-agent --limit 3`. A red run there is this change's to fix forward.
