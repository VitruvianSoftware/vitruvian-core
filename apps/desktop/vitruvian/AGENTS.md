# Agent guide: apps/desktop/vitruvian

This guide adds to the root `AGENTS.md` for this subtree. Read
[`UPSTREAM.md`](UPSTREAM.md) first.

## Hard rules

- **This directory is GPL-3.0-or-later.** Never edit or remove an upstream
  `SPDX-License-Identifier` / `Copyright (C) 2026 Vorssaint` header. New files
  get `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 VitruvianSoftware`, never the monorepo's Apache/MIT
  header. Never copy code from here into Apache-licensed parts of the repo.
- **Log every change to an upstream file** with a dated entry under
  "Modifications" in `UPSTREAM.md` (GPL-3.0 §5(a)).
- **Never use upstream's brand or services.** No Vorssaint name, icon, bundle ID,
  update feed, upload/feedback server or community link in what the app shows or
  calls (see `TRADEMARKS.md`). Keep upstream's copyright lines, which are legal
  notices, not branding. Releases ship as DMGs from the `vitruvian` delivery
  unit (`publish.sh`); check anything that lands in the bundle (artwork, GIFs,
  strings) for upstream's brand first.

## Building

- Use Bazel with `--config=macos-app` (see `README.md`). The targets are
  `manual`, so name them explicitly. Do not wire `build.sh` into CI: it stays only
  because upstream tests read its text.
- `Core/`, `Design/` and `UI/` build in Swift 6 mode. Shared state there
  says what protects it: a lock or the main thread (`nonisolated(unsafe)`
  with a comment naming the guard), `@MainActor`, or `Sendable`. Isolate a
  type that Swift 5 modules use with `@preconcurrency @MainActor`, so its
  callers are not broken before their module moves to Swift 6.
- In `UI/`, AppKit glue (coordinators, delegates, NSView subclasses) is
  `@MainActor`; a main-queue observer reaches it through
  `MainActor.assumeIsolated`; a closure that runs on a background queue
  takes plain values, never the view or a service.
- A Services API that runs a caller's closure off the main thread takes it
  `@Sendable`. Otherwise a closure from `UI/` (Swift 6 mode) checks at run
  time that it is on the main thread, and stops the app when it is not.
- In a view, pass one of its methods as an optional action through a
  closure, `granted ? nil : { grant() }`, not by name, `granted ? nil :
  grant`. The named form makes the compiler fail with "failed to produce
  diagnostic" once the module is checked for Swift 6.
- A new preference goes in `Core/Preferences.swift` as a `Preference` with
  its default. `Defaults.registeredDefaults` registers it from there, views
  use `@AppStorage(Preferences.x) var x: Bool` (with the type written out),
  and nothing else spells out the default. Code reads and writes it as
  `defaults[Preferences.x]`, not by its `DefaultsKey`. `source_lints_test`
  counts what still reaches a declared key by name, and only lets that
  count fall.
- `Tests/mutation_checks.py` plants real regressions and requires each to fail
  its test. It runs weekly in CI. Moving or rewording code that a mutation
  quotes breaks that run, so update the mutation in the same change.
- After changing the test, fan-helper or Now Playing source lists in `build.sh`,
  or the extractions in `Tests/generate_sources.py`, run
  `bazel run //apps/desktop/vitruvian:sync_sources`.
- Swift has no Gazelle. `BUILD` is hand-written and carries `# gazelle:ignore`.
- `Core/` is its own module, `VitruvianCore`, which depends on no other app
  module:
  - What the app or tests use from it must be `package` (an implicit
    memberwise initializer is never visible outside, so write it out).
  - Every app and test file imports it.
  - The module is the whole folder. A file that needs a service, view or
    singleton does not belong there: put it under `Services/` or `UI/`.
- The folders have one direction: `Core` <- `Design` <- `Services` <- `UI` <-
  `App` (with `Support` and `main.swift`). Each of the first four is a module,
  so Bazel holds the direction: a file that names something from a later layer
  does not compile. Cut such an edge (move the type down, or put an interface in
  front of it) rather than working around it. `Design/` holds the AppKit and
  SwiftUI building blocks that services and views share (panels, backdrops,
  editors), and knows no feature.
- `NotchService` names no service that follows it. When the island needs
  something new from one, add a hook to `NotchCollaborators` and wire it in
  `main.swift`, the composition root.
- Below `App/`, reach the running app through `appShell()` (the `AppShell`
  protocol), never `AppDelegate`. Add a requirement there when a service or
  view needs something new from it.
- A service shows SwiftUI content through `ServiceViews.factory`
  (`ServiceViewFactory`), never by naming a view. A new hosted view gets a
  method there and in `UI/UIServiceViewFactory.swift`.
- `Design/` is the `VitruvianDesign` module, which depends on Core alone. The
  same rules apply as for Core: what others use is `package`, initializers are
  spelled out, and every app and test file imports it. The exception is the
  files the fan helper or the Now Playing adapter also compile. A class that
  another module subclasses must be `open`, with its overrides `public`
  (`OverlayPanel`).
- `Services/` is the `VitruvianServices` module, which depends on Core and
  Design. The same rules apply again: every struct spells out its
  initializer, and a type that outside code builds as `Foo()` despite private
  stored properties spells out `package init() {}`. An extension member that a
  later layer declares is invisible to a service: put it in the lowest layer
  that uses it.
- `UI/` is the `VitruvianUI` module, which depends on Core, Design and
  Services; `App/`, `Support/` and `main.swift` are the app around it. The same
  rules apply. A SwiftUI view that `App/`, `Support/` or a test builds spells
  out its initializer, taking what the synthesized one took: its non-private
  stored properties, a `Binding` for a `@Binding`, the object for an
  `@ObservedObject`, closures `@escaping`.
- `FanControlKit/` is a third module, shared by Core and the privileged fan
  helper. Core re-exports it, so app code needs no extra import. Files that the
  helper also compiles import it directly.

## Conventions (from upstream)

- App lifecycle lives in `Sources/Vitruvian/App`, shared catalogs and preferences
  in `Core`, behavior in `Services`, views in `UI`, diagnostics in `Support`.
  Keep decisions outside views where tests can reach them. Pure logic goes in a
  `*Support.swift` file with injectable `UserDefaults`.
- A new feature needs an `AppFeature` case in `Core/FeatureCatalog.swift`. The
  compiler enforces its switch arms, including `FeatureRuntime.runBinding(for:)`.
  Permission re-syncs derive from `permissions`. The compiler does **not**
  enforce these, so check each one:
  - the quit cleanup: `AppDelegate`'s list and `QuitInputRelease`
  - `FeatureVisibilitySupport.features(for:)`
  - `Core/Defaults.swift` keys and defaults
  See `REFACTOR.md` for the plan to close those gaps too.
- An action a surface can trigger is a command. Add it as a `BuiltinCommand`
  case (`Core/Platform/BuiltinCommand.swift`) and give it a handler in
  `Services/Platform/BuiltinTools.swift`; the compiler asks for the handler.
  The radial menu, the Quick panel and the command bar run commands through
  `ToolRegistry`, and the command bar also lists them from it. Do not add a
  service call to a surface's own switch.
- A surface that lists tools has two sources: its own fixed list, and
  `ToolRegistry.extraCommands(on:)`, the commands that ask for that surface
  and that the fixed list does not already offer. Never list
  `commands(on:)` straight onto the Quick panel or the wheel: every built-in
  command is in it, and each would appear twice. A built-in command asks for
  a surface in `BuiltinTools.install` only when something there already runs
  it.
- A saved order may hold an id the app does not recognise right now: a tool
  that has not registered yet, or one that is switched off. Keep it where it
  is (`QuickToolsSupport.savedTileOrder`); drop only what is not well formed.
- To see a tool that is in no fixed list, build with
  `--define=vitruvian_sample_tool=true` (`Services/Platform/SampleTool.swift`).
- A global shortcut lives in one of several lists: `GlobalShortcutRole` (and
  the radial wheels it reads), window-layout actions, Command Bar rows, and
  tool commands. Anything that records one asks all of them before it saves:
  `GlobalShortcutRole.conflict`, `WindowLayoutService.shortcutConflictTitle`,
  then `ShortcutConflicts.title`, which covers rows and tool commands. A new
  list of shortcuts is added to `ShortcutConflicts`, not checked by hand at
  each recorder. A Reset button and an accepted macOS take-over write a
  combination too, so they ask the same lists before they save (the role
  and window-layout rows through `ShortcutConflicts.write`).
- A hotkey registrar that is tied to no hub feature must be re-synced in
  `ShortcutCapture.end()`: recording releases every key the app holds, and
  only each feature's own sync gives them back. Leaving this out fails
  silently, after the first shortcut the person records.
- One of the app's own commands that already has a `GlobalShortcutRole` does
  not also ask for the `shortcut` surface: that would give one action two
  combinations.
- `ToolShortcutRegistrar.assign` refuses a combination another tool command
  has saved and returns why; it never moves one. Its hotkey ids run from
  `ToolShortcutRegistrar.firstHotkeyID`, and `bazel/source_lints.py` keeps
  that run clear of the others.
- A feature that has become a tool has a manifest (`ToolManifest`), conforms
  to `BundledTool`, and is built by `ToolHost` with a `ToolServices`. It has
  no `static let shared`. Everything outside its own logic, it reaches
  through `services`: the clipboard, its preferences, a link, a beep or a
  message, the listening-sockets report, ending a process, a global
  shortcut, a paste or a menu press in the app in front. A view gets its
  tool with
  `ToolHost.shared.tool(X.self)` and calls the tool, never a service.
  `bazel/source_lints.py` holds the list of migrated tools and their files
  (`MIGRATED_TOOLS`). Its rule
  `migrated_tools_reach_services_through_the_broker` fails on a direct call
  from one of those files, and `the_broker_names_no_tool` fails when a
  broker file names a tool's type.
- The broker (`Services/Platform/Broker/`) names no tool. An operation is
  named for what it does to the system, never for the tool that wanted it,
  and takes and returns plain values; a completion closure the tool passes
  in stands for the reply, and a `ClipboardRewriteRule` for a question the
  host asks the tool. A capability is added with the first tool that
  needs it.
- Every broker operation calls its gate first and does nothing when refused.
  A test for a new operation asserts that a refused call did no work.
- A tool's background work is in `start()` and `stop()`, and `ToolHost`
  calls them: at launch, when the hub installs or removes the tool, when
  its switch flips, when a macOS grant its hub feature declares changes
  (`FeatureRuntime.permissionDidChange`) and when a shortcut recording ends.
  A tool never asks whether it is installed or switched on. The run rule is
  `ToolHost.shouldRun(installed:switchedOn:holdsGrants:)`. A capability says
  which macOS grants it rides on (`Capability.ridesOn`): `keystrokes` rides
  on Accessibility, and nothing else rides on a grant yet. A tool must hold
  those grants before the host starts it, unless its request says
  `startsWithoutGrant` (`ToolManifest.grantsNeededToStart`): then the host
  starts it anyway, and each operation of that capability is refused with
  `notGranted` until the grant is there. `start()` is called every time
  the host finds the tool should run, so it must be safe to call twice. A
  new tool is added
  to `BundledTools.all` (`Services/Platform/BundledTools.swift`), and its
  arm in `FeatureRuntime.actions(for:in:)` returns `.tool(id)` when its
  manifest says `onLaunch`.
- Nothing watches the preferences. Code that flips a tool's switch tells the
  host: a view calls `ToolHost.shared.sync(X.self)`, and the command bar's
  toggle rows go through `FeatureRuntime.shared.sync`.
- A tool's command is in its manifest, with the surfaces it asks for.
  `BuiltinTools.install` registers every hub feature, a tool from its
  manifest's descriptor, and wires each of its commands to `ToolHost.canRun`
  and `ToolHost.run`. It builds no host and no tool: the host is asked for
  when a command is first run or asked about. A row that existed before the
  tool keeps its id and runs the command through `ToolRegistry`; the command
  then asks for no surface, so no second row appears. A command takes no
  argument: a row that needs one, such as the selected text, calls a method
  on the tool.
- The clipboard is looked at for tools in one place, `ClipboardWatcher`, on
  one timer that runs while a tool asks. (Clipboard history and auto-clear
  still have a timer each.) A tool that rewrites copies hands the broker a
  `ClipboardRewriteRule` with `clipboard.rewriteLinks(rule:)`. Its functions
  run on the clipboard lane in the middle of one look, so they take plain
  values, answer at once and capture no app state. Besides a completion, it
  is the only kind of function that crosses the broker.
- A tool reads a preference through `services.storage.reader()`, and only a
  key its manifest declares; there is no `set`. Its views may bind with
  `@AppStorage` the keys its row in `MIGRATED_TOOLS` lists, each of which
  the manifest must declare; `source_lints_test` fails on any other.
- The broker asks macOS about a grant at the moment of each call
  (`CapabilityBroker.Environment.live`). It does not read `Permissions`,
  whose published value is false for a turn of the main thread after it is
  first touched, so all through launch, and afterwards lags behind a change
  by up to a poll. A tool that needs a grant for a piece of work asks
  `services.keystrokes.refusal` before it reads or changes anything, and
  has the person asked with `requestGrant()`.
- A tool's shortcut that is a `GlobalShortcutRole` is taken with
  `services.hotkey.bind(role, onPress:onRegistered:)` in `start()` and given
  back with `unbind(role)` in `stop()`. The tool names its own role and
  never sees a hotkey id: the id is in the broker's table,
  `HotkeyBindings.Environment.live` (`Broker/HotkeyAccess.swift`), and
  nowhere else, and `hotkey_ids_are_unique` reads it there. A role of
  another feature, or one the table does not list, is refused. Such a tool
  is tied to its hub feature, so the key comes back after a shortcut
  recording through `FeatureRuntime.sync`, `ToolHost.sync` and `start()`: it
  needs no line in `ShortcutCapture.end()`.
- A tool reaches `Services/TransientPaste.swift` only through
  `keystrokes.paste`. Do not edit that file to suit a tool: its delays are
  tuned by hand against real apps, and it has no unit test. Text snippets
  still call it directly. The paste itself lets go of the calling tool's
  own key when that key is Command-V and takes it again after; a tool does
  not. `pressFrontAppMenuItem(matching:)` takes key equivalents
  (`MenuKeyEquivalent`), never titles. The walk is the host's
  (`FrontAppMenu`); which equivalents count is the tool's.
- `ToolHost.suspend(id)` stops one tool at once, whatever the run rule
  says, and builds nothing. It is for the moments the app lets go of every
  input it holds (`SelfUninstall`). The next `sync` starts it again.
- A tool's section on a Settings page it shares with another feature is a
  view in a file of its own, listed for the tool in `MIGRATED_TOOLS`. The
  page decides whether it shows, and hands it what it may not read for
  itself, such as a grant, as a plain value.
- Every user-facing string needs all 15 `AppLanguage` cases. Each strings file
  switches over them exhaustively, so a missing one is a compile error.
- User preferences must take part in settings backup. Machine-specific state and
  private content need an explicit exclusion.
- Tests check through `TestSuite` (`Tests/TestSuite.swift`) and run under Swift
  Testing, one case per suite listed in `Tests/TestGroups.swift`. A new
  contract runs from a suite there or from a contract that already runs;
  `TestRegistrationTests` fails on one that nothing runs. Write behavioral
  tests: no unit test reads a source file as text, and
  `bazel/source_lints.py` (`source_lints_test`) fails on one that does. A
  rule about how all of the code is written, not about what one piece of it
  does, is a lint: add it there, with a mutation that shows it fails.

## Features that are also standalone apps

Nexus Agent ships twice: as its own app (`apps/desktop/nexus-agent`) and as a
feature here. The code both share lives in the standalone's folder, under MIT,
and this app holds only what is specific to it.

- Change a shared rule in `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore`,
  never by copying it back here.
- Shared code takes its settings, text, theme and host hooks as inputs. It
  never imports a `Vitruvian*` module.
- `build.sh` and `Package.swift` here cannot see the shared library. Bazel is
  the only build of this app; `build.sh` stays as the source list upstream's
  tests read.
- After changing shared code, run
  `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and add a line to
  the log in `UPSTREAM.md`. `nexus_agent_shared_pin_test` fails until you do.
- Nothing upstream wrote may leave this folder. A file leaves only if
  VitruvianSoftware wrote all of it, and `UPSTREAM.md` records it.
- The next standalone app that becomes a feature here follows the same shape.

## Tools that run as their own programs

A tool can be a separate program the app starts and talks to
(`docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md`).
All four stages of that work are built: the protocol, reading a tool's
manifest, the runtime that starts a tool, talks to it and stops it, the
screens, and what a tool's author works with. A person adds a tool in
Settings, under Features, in the section "Tools from outside": they pick its
folder and agree on one sheet. Every build has that section. There is no
store of tools.

What a tool's author works with is all in `packages/vitruvian-sdk`: a Swift
kit, the `vitruvian-tool` command, three samples and a guide
(`docs/writing-a-tool.md`). None of it is in the app, and the app links none
of it but the protocol.

- The protocol lives in `packages/vitruvian-sdk`, under MIT: JSON Schema in
  `protocol/`, the same messages as Swift in `Sources/VitruvianToolProtocol`.
  The schema is the source of truth. Change a message in the schema, the
  Swift type and an example, in one commit; the package's tests hold the
  three together and can only see a difference an example crosses.
- `Core` links `VitruvianToolProtocol`. A file that uses it imports it by
  name. It is not re-exported from `Core`, and it never imports a
  `Vitruvian*` module. Nothing is copied between the two folders: the
  package is MIT and this app is GPL.
- The rules the app refuses a tool's folder by are written twice: here, in
  `ExternalToolManifest.read(folder:)` and `ExternalToolStore.offer(from:)`,
  and in the package's `FolderCheck`, for `vitruvian-tool validate`. The
  package cannot use this app's code. One file of example folders,
  `packages/vitruvian-sdk/protocol/examples/folders.json`, is judged by both:
  `ToolFolderExamplesTests` here, `FolderCheckTests` there. It holds 22
  folders, and an example whose verdict is `manifest` also names the rule
  that is broken. Change such a rule in both places and add an example, in
  one commit. One rule came from there: a tool's program must be a file, so
  a named pipe with the execute permission is refused as no program.
- After changing a file under
  `packages/vitruvian-sdk/Sources/VitruvianToolProtocol`, run
  `bazel run //apps/desktop/vitruvian:pin_tool_protocol` and add a line to the
  log in `UPSTREAM.md`. `tool_protocol_pin_test` fails until you do.
- What the pin protects, exactly. For a change made only in the package, the
  presubmit planner lists `tool_protocol_pin_test` among the affected tests.
  That test is in this app's pipeline unit, so the unit is selected and the
  app's tests run; the pin test fails until the pin is updated here.
  This held only once a comment with a round bracket was taken out of the
  `pipeline_unit` call in `BUILD`: the planner reads the call up to the first
  closing bracket. Keep brackets out of that call's comments.
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
- The runtime is `Services/Platform/External/`. A transport carries bytes to
  one run of a program; a `ToolLink` speaks the protocol for that run; an
  `ExternalTool` owns the program from one run to the next and is the tool
  host's second kind of `HostedTool`; `ExternalToolStore` holds what is
  installed.
- Only `ProcessTransport.swift` reads or writes a pipe, and never on the
  main thread. Everything else there is `@MainActor` and never waits. Do not
  add a `Task`: the runtime uses Dispatch queues and main-actor closures.
- Every deadline, wait and limit is a number in `ToolLimits` counted on a
  `ToolClock`. A test moves a `ManualToolClock` by hand and never waits. A
  new limit goes in `ToolLimits`, with a check on each side of it.
- "Can it run?" for an outside tool is answered from the last
  `commands/state` and how the tool stands. It never sends a message: lists
  ask while they draw.
- What a tool asks of the app is done in `ExternalToolCalls`, through the
  tool's own `ToolServices`, so the broker refuses a service the manifest
  does not list in `uses`. Its `switch` over `ToolMethod` is exhaustive on
  purpose. A refusal is one of the protocol's codes, from
  `ExternalToolCalls.error(for:)`.
- A preference a tool saves goes to the app's own preferences under
  `<tool id>/<preference id>`. No file is written for it. A saved string has
  no limit of its own: the 1 MB line is the only one.
- A tool is added in two steps, and there is no third way.
  `ExternalToolStore.offer(from:)` reads the folder the person picked and
  changes nothing: no copy, no program, no file. `ExternalToolStore.add`
  takes a `ToolConsent` to that offer. Only the agreement sheet may make a
  `ToolConsent`: the source rule `only_the_agreement_sheet_consents` fails
  for any other file of the app that does. There is no development switch
  and no build define for tools from outside: every build adds one the same
  way.
- What is added is what was shown. An offer names its manifest's exact
  bytes (`ToolFingerprint`, their SHA-256). `add` reads the folder again and
  refuses when they differ, and checks the app's copy the same way. That is
  also all "changed" means for an update: one byte of the manifest differs.
  The program and the other files are not compared.
- The store remembers. `InstalledTools.json`, in the app's support folder,
  holds each added tool's id, its switch and what was agreed (`ToolRecord`,
  `ToolAgreement`). `main.swift` calls `restore()` once at launch. A file
  that cannot be read means no tools and deletes nothing; it is moved aside,
  never written over, the first time a tool is added after. It is not a
  preference and is in no settings backup.
- A copy that is not what the person agreed to is held back
  (`Listed.isHeld`): never started, still listed. Only choosing its folder
  again, and agreeing again, brings it back.
- A tool that is switched off is out of the host and the registry, so
  `isInstalled` is false for it and every request is refused.
- `Tools/<id>/` is the app's copy of a tool's folder and `ToolData/<id>/`
  is what the tool saved, both under the app's support folder. Adding a
  tool again replaces `Tools/<id>/` whole and keeps `ToolData/<id>/`.
  Nothing else is deleted until the person removes the tool.
- `ToolFolders.install` and `ToolFolders.delete` are the only code that
  copies or deletes for a tool.
  An id is one folder name: no slash, no two dots in a row, no dot first. A
  `Tools` or `ToolData` folder that is a link to another place is refused
  (`linkedElsewhere`). A link inside the picked folder is copied as a link.
  A folder over `ToolLimits.folderBytes` or `folderItems` is refused before
  anything is copied (`ToolFolders.weight`), and so is one whose program
  macOS has quarantined. The app never clears a quarantine.
- Three limits are known and accepted. A tool that closes its output and
  keeps running is noticed only when three requests go unanswered. A tool's
  last line with no line break is dropped. After the last kill at quit the
  app does not wait to see the process gone.
- A test of the runtime uses `FakeTool`, which is no process. A test that
  needs a real one starts `tool_fixture` (`Tools/ToolFixture.swift`), waits
  only through `ToolRuntimeSupport.wait`, and kills the process and sees it
  gone before it returns. A test's folders are under the temporary folder,
  never the app's real support folder.
- A screen for tools from outside is a view over a plain value that says
  everything the view shows: `ToolAgreementContent`, `ToolRefusalMessage`,
  `ExternalToolRow`, `ExternalToolDetail`, `ToolRemovalContent`
  (`UI/Settings/ExternalToolAgreementSheet.swift` and
  `ExternalToolsSection.swift`). The tests check the value. No test draws a
  view, and how a screen looks is checked by hand.
- The agreement sheet is the one safety moment. It says, in the app's words,
  that the tool can do anything the app can. It lists what the tool says it
  uses as the tool's statement, under a note that it is no limit. Its
  default button is Cancel (`ToolAgreementContent.defaultChoice`): Return
  must never add a tool. The same holds for removing one.
- The app's words about these tools are `ExternalToolStrings`
  (`Core/ExternalToolStrings.swift`), in all fifteen languages. A tool's
  name, publisher, description and command titles are shown as the tool
  wrote them and are never translated by the app. A text added there
  changes `ExternalToolStringsTests.count`.
- The person is told once per tool, per run of the app, that a tool stopped
  working: at its first crash, in the app's short on-screen message
  (`ExternalToolStore.tellStopped`). It is also a line in the system log.
- `ExternalToolStore.remove(_:deletingData:)` deletes the app's copy of a
  tool and, when asked, what it saved: `ToolData/<id>/` and the preferences
  under `<tool id>/`. `ToolFolders.delete` can reach `Tools/<id>` and
  `ToolData/<id>` and nothing else.
- Remove waits for the tool's program to be gone before it deletes
  anything (`ToolHost.removeAndSeeOut`). The program is told goodbye, asked
  to end after half a second, and killed a quarter of a second later; the
  app looks for a quarter more. The three waits are in `ToolLimits`. The
  wait is on the main thread, so removing a tool that ignores everything
  holds the app for up to one second. A program still there after the kill
  keeps what it saved, whatever was asked: its copy and its record go, and
  `remove` logs it. `remove` returns true either way, so the screen cannot
  say the data was kept. No text exists for that yet.
- Which button of the question before removal deletes what a tool saved is
  `ToolRemovalContent.Choice.deletesData`, and the view passes it on
  unchanged. What follows the folder picker is `ToolPicked.after`: nothing,
  the sheet, or a refusal. Both are values so the tests can check them.
- A tool's own words are drawn as plain `String` values, never as a
  `LocalizedStringKey` literal, so markdown and links in them are shown as
  written. Each has a line limit: on the sheet and in the detail the title
  takes 2 lines, the publisher and version 2, the description 3, a command
  2; in a row the name and the publisher each take 1. With 7 or more rows
  the two lists scroll in a region 200 points high
  (`ToolAgreementContent.rowsDrawnWhole`, `listsHeight`), on the sheet and
  in the detail, so the statement and the buttons stay in view.
- The detail shows the end of a tool's log: the newest 200 lines and at
  most 32 KB (`ExternalToolDetail.shownLog`), as plain text that can be
  selected. It is read when the detail opens and does not follow a running
  tool.
- The card redraws because it observes `ToolRegistry.shared`. The store
  bumps the registry's `revision` whenever a tool is added, removed,
  switched or stands differently. Nothing polls a tool.
- Limits of stage C that are known and accepted:
  - Remove waits for the tool's own process only. A child the tool started
    is not waited for and may outlive it.
  - "Changed" compares the manifest file's bytes. The program and the
    other files are not compared.
  - The fourteen languages other than English were written with the
    English and checked by rule. No reader of them has reviewed them.
  - That the sheet stays under 800 points high is arithmetic from the line
    limits. Nobody has seen it on a small display.
  - A tool's preferences have no screen, and nothing tells a running tool
    that a preference or the language changed.
  - A records file that cannot be read is kept until the next tool is
    added. Then it is moved to `InstalledTools.unreadable.json`, replacing
    an earlier file of that name.
  - Nobody has opened the app with this stage in it. The plan's list "By
    hand" is what is left to see.

## Porting from upstream

- Follow `UPSTREAM.md`, "Tracking and porting upstream". Start a port with
  `bazel run //apps/desktop/vitruvian:track_upstream -- port <sha>...`. Never copy
  upstream files over this tree: that undoes the rename and the refactor.
- Update the ledger (`upstream/ledger.tsv`) in the same PR: `ported` with the PR
  number, or `skipped` with why. `bazel test //apps/desktop/vitruvian:upstream_test`
  checks it.
- A port is not done while the tool's report lists a brand-review line. Nothing
  may point at upstream's brand, servers, update feed or repository.

## Verifying

`bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests
//apps/desktop/vitruvian:selftest` is the minimum before claiming a change works.
Tests and `--selftest` do not exercise windows, permissions or hardware. For those,
describe what you actually ran and on which Mac and macOS version, and state what
remains untested.
