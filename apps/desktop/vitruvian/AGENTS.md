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
  unit (`bazel run //apps/desktop/vitruvian:publish`); check anything that
  lands in the bundle (artwork, GIFs, strings) for upstream's brand first.

## Building

- Use Bazel with `--config=macos-app` (see `README.md`). The targets are
  `manual`, so name them explicitly. Do not wire `build.sh` into CI: it stays only
  because upstream tests read its text.
- The release path is Rust, in `bazel/src/`: `publish` -> `package_release`
  -> `make_dmg` (with `dmg_image_devices`) and `notarize`, plus
  `beta_publish_guard`, `ci_setup_signing` and `setup_signing`, each with a
  `bazel run` target of its name. Every command they run goes through
  `release_exec`'s `Runner`; change a release step in Rust together with the
  `FakeRunner` test that replays it. Do not bring back shell scripts for it.
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
  `:mutation_fixtures_test` holds you to it: it runs with the pull-request
  tests and fails when a mutation's quoted text is not in its file exactly
  once (`bazel test //apps/desktop/vitruvian:mutation_fixtures_test`).
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
- The island's Tools grid (`.quickPanel`) is for the app's own tools and for
  tools from outside with no island page of their own. An outside tool
  whose manifest has an island panel offers its actions on that page, so
  `extraCommands(on: .quickPanel)` leaves its commands out even when they
  ask for the grid (`ToolRegistry.hasIslandPage`, noted when the tool is
  registered). The command bar, the wheel and the Shortcuts page still list
  them. The rule reads the manifest, not the island switch.
- A registry command that is listed and cannot run now (`ToolRegistry.canRun`
  is false: a grant is missing, its tool said so in `commands/state`, or the
  tool's program is stopped) is handled by each surface in its own way. The
  command bar and the wheel leave it out, each for a reason its code states
  (`CommandBarCatalog.toolEntries`, `RadialMenuService.availableItems`). The
  Quick panel keeps its tile where it is, so the grid and the digits do not
  move, and draws it as a disabled button
  (`QuickLauncherService.isUnavailable`): no click, Return or digit runs it,
  and the panel stays open. On the Shortcuts page its row says it is
  inactive, and its key beeps. Do not hide such a tile, and do not give it a
  colour of its own: `.disabled` is how the app dims.
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
  that is here holds, and returns why; it never moves one away from a
  command that has a row. Its hotkey ids run from
  `ToolShortcutRegistrar.firstHotkeyID`, and `bazel/source_lints.py` keeps
  that run clear of the others.
- A saved tool-command shortcut holds its combination only while its
  command is here and asks for one, which is exactly while it has a row on
  the Shortcuts page (`ToolShortcutRegistrar.heldShortcuts`). The shortcut
  of a tool that is switched off, or not registered this launch, stays
  saved, is no key, and refuses nobody; it is a key again when the tool
  returns. If the keys were given to another tool command meanwhile, the
  absent entry goes. Ask `heldShortcuts`, never `shortcuts`, whether a
  combination is taken. Removing a tool from outside clears its commands'
  shortcuts (`ToolShortcutRegistrar.forget`); switching it off or updating
  it clears none.
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

## Features that were also standalone apps

Nexus Agent shipped twice, as its own app (`apps/desktop/nexus-agent`) and
as a feature here, until tools for everyone, stage F, made it the Nexus
Agent tool from the catalog (`apps/desktop/nexus-agent/macos`, id
`dev.vitruvian.nexus-agent`): the shared code stays in the standalone's
folder, this app links none of it, and the one thing of the feature left
here is `Services/NexusAgent/NexusAgentHandoff.swift`, which hands a person
who skipped the release that offered the tool their old settings. A
standalone app that would become a feature here is a tool instead
(`docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md`).

## Tools that run as their own programs

A tool can be a separate program the app starts and talks to
(`docs/superpowers/specs/2026-10-10-vitruvian-external-tools-design.md`).
All four stages of that work are built: the protocol, reading a tool's
manifest, the runtime that starts a tool, talks to it and stops it, the
screens, and what a tool's author works with. A person adds a tool on
the Extensions page of Settings (`SettingsPage.extensions`, in Essentials
right after Features): with "Add from Folder…" they pick its folder and
agree on one sheet. Every build has that page. Under what is installed, the
page lists the Vitruvian catalog's tools that are not installed
(`CatalogueSheetContent.notInstalled`): a curated list, kept in `catalog/`
at the repository's root, that the person installs a tool from through the
same sheet. There is no other store of tools. The catalog's card ends with one
line, "Build your own extension with the Vitruvian SDK.", whose name links to
the SDK's public repository (`AppInfo.sdkURL`); it sits below the card's
switch over the list, so it shows however the list stands. The Features
page keeps one line for them (`ExtensionsSummaryLine`): how many are added,
and a link to the page. Every way in, that line, the sidebar, the Settings search and
command bar, and an extension's island page in the Dynamic Island's
settings, goes to `ExtensionsPageSupport.destination`. The sidebar's row
counts the added tools the catalog lists a newer version of
(`ExtensionsPageContent.updates`), whether they came from the catalog or
from a folder.

Each row of the Installed list carries a pill, `ExternalToolRow.kind`: a package
whose manifest has any `panels` (island, Settings or window) is an
Extension, one with none is a Tool. The manifest's fields and the protocol
keep the word "tool" for both. A package that is held back has no manifest
the app reads, so it is badged Tool until it is updated. A row of the
catalog (`CatalogueRow.kindBadge`) carries the same pill when its
entry in `catalog/tools.json` lists `panels` (`[]` for Tool, non-empty for
Extension), and none when an older entry leaves `panels` out.
The page's words name every place an extension's page may be, never the
island alone, since some extensions only add a Settings part or a window.

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
  The planner reads the unit's targets from the `pipeline_unit` call in
  `BUILD`, so a target has to be written out in that call's `test_targets`
  to count; a call the planner cannot read stops the plan with an error
  instead of dropping the unit.
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
- A pick that cannot run is never silent. The command bar and the wheel
  leave out a command that cannot run, but both are made when they open,
  and a command can stop being runnable while one is open. Picking it then
  runs nothing and plays the alert sound, as a shortcut does
  (`CommandBarCatalog.toolEntries`, `RadialMenuService.run(_:registry:refuse:)`,
  `ToolShortcutRegistrar`). The row or slice itself stays until the surface
  is opened again: neither follows the registry while it is open. A new
  surface that runs a registry command checks what `ToolRegistry.run`
  gives back.
- What a tool asks of the app is done in `ExternalToolCalls`, through the
  tool's own `ToolServices`, so the broker refuses a service the manifest
  does not list in `uses`. Its `switch` over `ToolMethod` is exhaustive on
  purpose. A refusal is one of the protocol's codes, from
  `ExternalToolCalls.error(for:)`.
- A preference a tool saves goes to the app's own preferences under
  `<tool id>/<preference id>`. No file is written for it. Text saved that
  way is at most 4,096 characters, the protocol's
  `StorageLimits.maxTextLength`: `StorageAccess.set(_:for:)` refuses a
  longer one, for a tool's `storage/set` and for the person's own change
  alike. That number is the protocol's, not one of `ToolLimits`, because a
  tool's author is told it and `vitruvian-tool run` holds to it too.
- A tool's own settings are the preferences its manifest gives a `title`
  (`ExternalToolManifest.preferenceTitles`). `ExternalToolStore.settings(of:)`
  lists them and `setSetting(_:for:of:)` is the one way the person changes
  one. It saves under the key the tool reads, by the tool's own rules, but
  not behind the tool's `uses` or its switch: those say what the tool may
  ask, and here the person acts. A preference with no title is never
  listed and cannot be changed there, so no screen can show a raw id. A
  tool that is held back has no settings.
- After a change is saved, a tool that is running is sent the protocol's
  `preferences/changed`, once, with that one preference's id and value. It
  is a notice: the app does not wait. A tool that is not running, or has
  not answered `initialize`, is sent nothing and is not started; it reads
  the value when it next starts. Saving the value a setting already has
  does nothing.
- When the person changes the app's language, each tool that is running
  is sent the protocol's `language/changed`, once, with the new tag
  (`ExternalToolStore.languageChanged`, told by `ExternalToolStore.watch`
  over `L10n.shared.$language`). It is wired as `preferences/changed` is:
  a notice the app does not wait on, never sent before a tool has answered
  `initialize`, never to a tool that is stopped, switched off or held
  back, and it starts nothing. One thing differs. A tool that was greeted
  in a language the app changed before it answered is told the new one
  once it has answered (`ToolLink.languageChanged`), or it would keep the
  old one for its whole run. A tool started later gets the language from
  `initialize`, which reads it at each start.
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
- Ending a tool ends the programs it started (`ProcessTransport`,
  `ToolProcessGroup`). A tool is started with `Foundation.Process` and
  nothing else, which is the whole trust model: an ordinary child has the
  app's macOS permissions. Never start a tool with a spawn attribute of
  the app's own, and never one that disclaims responsibility for the
  child: that is what takes the permissions away. macOS gives a `Process`
  a process group of its own, led by the child, and `Process.terminate`
  signals that group. The app makes no group. It looks, once the child
  runs (`getpgid(child) == child`), and only then: the kill signals the
  group, and when the tool's process is gone and collected, what is left
  of its group is killed, once, at that moment (the sweep). A transport
  counts as running until that is done.
- The app never signals a group it did not see its own child lead: never
  group 0 or 1, never its own, never one the child is merely in
  (`ToolProcessGroup.led`). A tool it did not see lead a group is killed
  alone and nothing is swept, as before this was built. Nothing signals a
  tool's id after its process was collected, except the one sweep, and
  the sweep does nothing while any process has that id. Known and
  accepted: in the instant between the tool being collected and the
  sweep, macOS could in principle hand the id to a new process that makes
  a group of its own and exits again; the same instant always existed for
  the kill of the process itself.
- Out of reach, and said in the guide: a program that left the tool's
  group or session, which includes every program a Swift tool starts
  with `Process`; and everything, when the app itself crashes. A tool
  still ends when its input closes.
- A test that needs a program a tool started uses the fixture's `helper`
  commands and `ToolProcessTests.Helper`. It ends every helper it started
  that is still there, by its id and only while that id still runs the
  fixture. `pgrep -fl 'tool_fixture|bin/fixture'` prints nothing after a
  run.
- A test of the runtime uses `FakeTool`, which is no process. A test that
  needs a real one starts `tool_fixture` (`Tools/ToolFixture.swift`), waits
  only through `ToolRuntimeSupport.wait`, and kills the process and sees it
  gone before it returns. A test's folders are under the temporary folder,
  never the app's real support folder.
- A screen for tools from outside is a view over a plain value that says
  everything the view shows: `ToolAgreementContent`, `ToolRefusalMessage`,
  `ExternalToolRow`, `ExternalToolDetail`, `ExternalToolSetting`,
  `ToolRemovalContent`, `ToolRemovalNotice`
  (`UI/Settings/ExternalToolAgreementSheet.swift` and
  `ExternalToolsSection.swift`). The tests check the value. No test draws a
  view, and how a screen looks is checked by hand.
- The agreement sheet is the one safety moment. It says, in the app's words,
  that the tool can do anything the app can. It lists what the tool says it
  uses as the tool's statement, under a note that it is no limit. Its
  default button is Cancel (`ToolAgreementContent.defaultChoice`): Return
  must never add a tool. The same holds for removing one. The keyboard
  starts on Cancel too (`ToolAgreementContent.initialFocus`): with
  "Keyboard navigation" on, macOS puts focus on the first button of a
  custom sheet as it becomes the key window, whatever `onAppear`,
  `defaultFocus` or `prefersDefaultFocus` say, and Space presses it. The
  sheet moves that first focus once (`the_agreement_sheet_places_its_focus`);
  the agreeing button stays reachable with Tab. Only pressing Space in the
  app proves it.
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
  `remove` logs it.
- `remove` says what happened (`ExternalToolStore.Removal`): nobody added
  it, kept as asked, deleted, kept although deleting was asked because the
  program would not stop, with the folder, or not deleted: the program was
  gone and a folder that was to go is still there, with each such folder
  (`notDeleted`, from `ToolFolders.undeleted`). For those last two the
  person is told once, in one alert, after the tool's detail has closed
  and its row has gone (`ToolRemovalNotice`), with a button that shows the
  folder or folders in the Finder. `.deleted` now means nothing is left.
- A tool's preferences under `<tool id>/` are deleted only together with
  the folder of what it saved. When that folder stays, for any of three
  reasons (the person kept it, the program would not stop, it could not be
  deleted), they stay with it, and adding the tool again finds both.
  Nothing deletes either later, and there is no cleaner: a person who
  deletes the folder by hand leaves the preferences in the app's own
  until the tool is added again and removed with what it saved.
- The record of a removed tool is written away before anything is
  deleted, so a tool that is half deleted has no record at the next
  launch and is never listed or started. Its leftover folder is replaced
  when the tool is added again.
- One corner is still only a line in the system log: the program would
  not stop and the app's copy could not be deleted either. The alert is
  then the one about what was kept.
- Which button of the question before removal deletes what a tool saved is
  `ToolRemovalContent.Choice.deletesData`, and the view passes it on
  unchanged. What follows the folder picker is `ToolPicked.after`: nothing,
  the sheet, or a refusal. Both are values so the tests can check them.
- A tool's own words are drawn as plain `String` values, never as a
  `LocalizedStringKey` literal, so markdown and links in them are shown as
  written. Each has a line limit: on the sheet and in the detail the title
  takes 2 lines, the publisher and version 2, the description 3, a command
  2; in a row the name and the publisher each take 1. With 7 or more rows
  the lists scroll in a region 200 points high
  (`ToolAgreementContent.rowsDrawnWhole`, `listsHeight`), on the sheet and
  in the detail, so the statement and the buttons stay in view.
- The detail lists a tool's settings first, under the app's existing word
  for Settings (`panelSettings`), then its commands and what it says it
  uses. Each setting is one row of those lists, so sixteen of them scroll
  in the same region. A title takes 2 lines and is bounded to 60
  characters where it is drawn. A switch saves as it is turned; a field
  saves on Return, when the person moves on from it, and when the detail
  closes; a value the store refuses is put back. The values are read when
  the detail opens and do not follow a running tool that changes its own.
  The agreement sheet does not list preferences.
- The detail opens with the keyboard on Close
  (`ExternalToolDetail.initialFocus`), by the agreement sheet's mechanism:
  every control of the detail is bound to one focus
  (`ExternalToolDetail.Focus`), and the first focus macOS places, which
  would be the tool's first setting, is moved once
  (`a_tools_detail_places_its_focus`). So Space at open cannot turn a
  tool's switch. A control added to the detail gets a case of `Focus` and
  `.focused($focus, equals:)`, or the first focus can land on it unseen.
  A field saves when the detail's focus leaves it, read from that same
  focus. Only pressing Space in the app proves it.
- A tool's own words inside one of the app's sentences that has no line
  limit go through `ToolOwnWords.oneLine` first: an alert's title or
  message, and the app's short on-screen message. It gives one line of at
  most 120 characters, with every control character a space and the
  characters that set the direction of text taken out, so a name cannot
  reorder the sentence. The sheet's title and its line of versions use it
  too. A new alert that names a tool does the same.
- The detail shows the end of a tool's log: the newest 200 lines and at
  most 32 KB (`ExternalToolDetail.shownLog`), as plain text that can be
  selected. It is read when the detail opens and does not follow a running
  tool.
- The Extensions page, its sidebar row and the Features page's line
  redraw because they observe `ToolRegistry.shared`. The store
  bumps the registry's `revision` whenever a tool is added, removed,
  switched or stands differently. Nothing polls a tool.
- A feature of the app's that becomes a tool may hand the tool what it
  kept, once, when the tool is added: `ExternalToolStore.Parts` has
  `beforeAdding`, `added` and `removed` for it, and the Add button waits
  through `add(_:then:)`, never on the main thread. Nothing uses them now:
  the GitHub hand-off went after 3.50.1. Nothing in the app touches the
  Keychain either (`keychain_is_never_touched`): the app is signed ad hoc,
  so macOS asks the person again after every update before it lets a new
  build read an item an older one saved.
- The catalog (`docs/superpowers/plans/2026-10-12-vitruvian-tools-for-everyone-stage-c.md`)
  is in `Services/Platform/External/Catalogue/`. Nothing of it goes
  through the broker: it is the app's own code, not a tool.
  - `CatalogueSigning` checks the list's Ed25519 signature with the key
    built into the app, `CatalogueSigning.publicKey`. It is the same line as
    `catalog/public-key.txt`, and `//catalog:catalog_test` fails when they
    differ. A new key is a new release.
  - `CatalogueInstaller.prepare` turns an entry into a `ToolOffer` and
    nothing more, in a fixed order: the download, refused past its pinned
    size; its size and SHA-256; the zip's directory, refused when an entry
    would leave its folder, is a link or is encrypted; `/usr/bin/ditto`;
    a look over what it unpacked; the manifest's id and version; then
    `ExternalToolStore.offer`. A refusal at any step deletes what it wrote.
    It never makes a `ToolConsent`: the agreement sheet does, as for a
    folder, and `only_the_agreement_sheet_consents` holds it.
  - The Extensions page starts an install or update through
    `CatalogueInstalls.shared`, not its own state: one at a time, and what
    it comes to waits there until the page shows it, so leaving the page
    mid-download loses nothing. While one is fetched its row draws a
    spinner and every other Install or Update is disabled
    (`ExtensionsPageContent.installButton`).
  - The download runs off the main thread; the store is touched only on it.
    Tests hand in a table for the network (`FakeCatalogueFetcher`) and run
    the steps in order on the main thread; the zip is unpacked by the real
    ditto, under the temporary folder.
  - `CatalogueWatch` fetches the list each time the Extensions page opens, and at launch and
    once a day only while a tool from the catalog is installed, with the
    ETag of the list it kept. It keeps the last list that verified in
    `Catalog.json` in the app's support folder, verifies it again whenever
    it reads it, and refuses a list older than it. A record with
    `catalogue` set, written when a tool was installed from the catalog, is
    compared at that entry's version. A tool added from a folder is matched
    by its id and compared at the version the person agreed to, unless it
    is held back (`CatalogueWatch.comparedVersion`); only a newer version is
    offered, never the same or an older one. Its row's button says "Update
    from the catalog" (`ExternalToolRow.updateWords`), the download is
    checked as for any install, and the agreement sheet says the tool moves
    from its folder onto the catalog (`ToolOffer.movesFromFolder`). Agreeing
    replaces `Tools/<id>/`, keeps `ToolData/<id>/`, and records `catalogue`,
    so it is a tool from the catalog from then on. The list is still
    fetched on the app's own only while a tool from the catalog is
    installed: for a Mac with only folder tools, it is the list fetched
    when the Extensions page last opened.
  - `CatalogueSource.inUse` is the website's list. Only a by-hand build
    (`--define=vitruvian_sample_tool=true`) can point it at a rehearsal on
    this Mac, from `main.swift`, given `VITRUVIAN_CATALOGUE_URL` and
    `VITRUVIAN_CATALOGUE_KEY`; `bazel run //catalog:rehearse` serves one.
    The source rule `only_a_by_hand_build_rehearses_the_catalog` fails for
    any other line that does.
- Limits of stage C that are known and accepted:
  - Remove waits for the tool's own process only. Since 2026-10-12 a
    program the tool started is ended with it, when it is still in the
    tool's process group; one that left the group may outlive it and go on
    writing into a folder that was deleted.
  - "Changed" compares the manifest file's bytes. The program and the
    other files are not compared.
  - The fourteen languages other than English were written with the
    English and checked by rule. No reader of them has reviewed them.
  - That the sheet stays under 800 points high is arithmetic from the line
    limits. Nobody has seen it on a small display.
  - A tool's preferences have a screen since 2026-10-12, and a running
    tool is told when the language changes since the same day: both built
    and not seen in the app.
  - A records file that cannot be read is kept until the next tool is
    added. Then it is moved to `InstalledTools.unreadable.json`, replacing
    an earlier file of that name.
  - Nobody has opened the app with this stage in it. The plan's list "By
    hand" is what is left to see.

## Tools that draw: protocol 2

A tool whose manifest says `"protocol": "2"` may contribute `panels`, and
the app draws them (`docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md`,
section 8; the stage D plan). A tool of protocol 1 is read and run as
before: the app offers both versions at `initialize`, and the tool picks.

- A panel is in one of three places (`ToolPanelPlacement`): a section of
  the island, a part of the tool's detail in Settings, or a window the app
  owns. At most one in the island and one in Settings.
- A tool's island page is one of the island's own sections
  (`NotchSectionItem.tool`), beside the `NotchModule` pages in Explore and
  in the saved order (`notchModuleOrder`); reopening can land on it, and a
  quick-access button saved as `extension:<tool id>` opens it. The Tools
  page lists only quick tools and commands, and none of a tool that has
  an island page.
  `NotchService` owns which page shows (`currentSection`, `extensionPage`):
  it opens one tool's page at a time, closing the last first, since
  `ToolPanelHost.open` does neither; an island page of its own, the app
  panel or a detail closes it; a refused page leaves the island on Explore;
  and a page that goes with its tool, or is hidden, falls back to Explore.
  Whether the island is empty, and shows its Explore button, is
  `NotchService.hasNoSections`, over every section, never `modules` alone.
  Showing a tool's page is `ExternalToolStore.setShowsInIsland`, the same
  switch as its detail's; Explore's editor (`editingSections`) flips it and
  `NotchSupport.setModuleShown` for the island's own.
- Settings treats a tool's island page as a section too. The Content tab
  lists `NotchSupport.editorSections` and saves a move through
  `savedSectionOrder`. The island and the "When reopening" picker share one
  rule, `NotchSupport.reopeningTarget`: a saved page that is not showing,
  the island's own or a tool's, reopens the first section, and the picker
  (`reopeningChoice`) keeps it chosen and dimmed rather than naming another
  page. Core cannot see the tools, so a tool's quick-access button asks
  `NotchExtensionActions` (Services) for its title, symbol and whether it
  shows; the island draws it only while it lists the page
  (`NotchService.quickAccess`).
- The menu bar panel's Extensions tab (`PanelSectionID.extensions`,
  `UI/MenuPanel/ExtensionsSection.swift`) shows each extension's island
  page a second time, drawn by `ToolPanelView`, with no SDK change. It is
  one page and one session whichever place shows it: each card of the tab
  opens the page with `ToolPanelHost.openInMenuPanel` under a token of its
  own and lets go of that token alone with `closeInMenuPanel`, so the order
  cards come and go in (an updated extension's new card can appear before
  the old one goes) never closes another card's page;
  `close`, which the island calls, leaves open a page the tab still shows;
  and the island opening a page the tab has open takes it as it is, asking
  the tool nothing. Each card's header collapses and expands its body
  (`DefaultsKey.panelCollapsedExtensions`), and the tab is built only while
  the popover is up or the panel is inside the island, so a page is open
  only while its card is expanded and can be seen. It is on by default only
  while an extension has an island page (`PanelSectionID.shownByDefault`);
  the tab's inline edit mode (`MenuPanelExtensionsSupport`) reorders
  extensions (`DefaultsKey.panelExtensionOrder`) and toggles their
  visibility (`DefaultsKey.panelHiddenExtensions`) independently of the
  island's "Show in the Dynamic Island", and resets order, visibility and
  collapsed state together. Where Settings manages extensions is named once,
  `MenuPanelExtensions.openExtensionSettings`. A web page is one web view,
  which one place can hold: while the island shows a web page the tab draws
  a line in its place (`ToolPanelHost.defersToIsland`), with a button that
  opens the island on it (`MenuPanelExtensions.showInIsland`, through
  `NotchService.openExtensionSection`), and draws the page again when the
  island lets go. Known limit: two views of the tab at once (the popover and
  the panel inside the island) showing one web page still share that one web
  view. Opening the tab starts the program of every expanded extension it
  lists, one `ui/open` each.
- `ToolPanelHost` (`Services/Platform/External/ToolPanelHost.swift`) is the
  one place that knows what a panel shows: for each open panel the last page
  its tool sent, read away from the main thread by `ToolPanelTree.read` and
  drawn on it. It draws at most four of the pages a tool sends unprompted in
  a second, the last of the ones between; a tool that sends more than forty
  in one second for a panel is stopped by its link as a flood. A page over
  256 KB or 200 blocks, or one with a block of a known kind that is not well
  formed, is not drawn: the panel keeps the page it had and the tool's log
  says why. A block of a kind the app does not know is drawn as its
  `fallback`, or left out.
- A page is drawn by `BlockTreeView` from a plain value,
  `BlockTreeContent`, which the tests check; no test draws a view. A tool's
  words are drawn with `Text(verbatim:)`, never as markdown or as a link,
  each with a line limit and cut to 2,000 characters. The look is the app's:
  a tool picks a style from a short list, never a colour, font or size.
- A panel ends with its tool's program: every page the tool had open closes.
  While a panel is open the tool is not stopped for being idle. Collapsing
  the island closes a tool's island page and tells the tool.
- A `link` block opens through the tool's own `open` service, and only a
  web or mail address. A refusal plays the alert sound.
- A web panel (`UI/ToolPanels/ToolWebPanel.swift`) loads `entry` with
  `loadFileURL(_:allowingReadAccessTo:)` scoped to the app's copy of the
  tool's folder. Its navigation delegate refuses any address outside that
  folder, by `ToolWebPolicy`, and every new window. The page's own network
  use is not stopped: the tool is trusted like an app. `ToolPanelHost` holds
  every page (`ToolWebPage`) and lets go of it when its panel closes or its
  tool ends; nothing else keeps a `WKWebView` of a tool's.
- The page reaches the app only through `window.vitruvian.call`, which the
  host passes to the tool's program as `ui/event` with `event: "bridge"`,
  after the tool's `uses` allow it, under the link's own flood rule. The
  program acts; the page never reaches a service of the app directly.
- A window opens only when the person asks: from the tool's detail, or in
  answer to what they did in another panel of the tool (`ui/event`'s
  `open`). `ToolPanelWindows` makes and closes the windows the host lists.
- `ui/badge` is behind `notify`. The badge stays across runs of the
  program and goes when the tool is switched off or removed.
- Whether the island lists a tool's page is the switch "Show in the Dynamic
  Island" in its detail, kept in `InstalledTools.json` as `showsInIsland`,
  written only once it is off.
- The app's words for panels are two: `panelNotShown` and `showInIsland` in
  `ExternalToolStrings`. Everything else on a panel is the tool's.
- Known limits: a tool's tile in the island is not reached with the arrow
  keys or Return, only with the pointer; a picture is read on the main thread
  each time its page is drawn; nobody has seen a panel in the app.

## Checking the app by hand, from the shell

`Tools/ByHand.swift` is a command that lists and presses the controls of the
running app through the macOS Accessibility API. It is how the checks by
hand of the tools from outside (the spec's section 15) were done on
2026-10-12. It is a development tool: `manual`, in no bundle and no release,
built in CI so it keeps compiling, and run by no test.

```sh
bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- open-settings
bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- tools
bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- add-tool "$PWD/bazel-bin/packages/vitruvian-sdk/built/hello-swift" --agree
bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- run-command "Say hello from Swift"
bazel run --config=macos-app //apps/desktop/vitruvian:by-hand -- remove-tool "Hello, in Swift" --delete-data
```

Run it with no command for the whole list: `windows`, `dump`, `find`,
`focused` and `message` only look; `press`, `select`, `set-value`,
`focus-field`, `choose` and `scroll-end` do one thing; `open-settings`,
`page`, `tools`, `add-tool`, `remove-tool`, `run-command`, `quit` and
`launch` each do one step of a check. It exits with 0 when done, 1 when
what was asked for is not there, 2 when the app is not running, 3 when the
terminal has no Accessibility.

Before you use it:

- **It drives the app that is running, the person's own.** Tell them before
  you start, and do not use it while they or another session are using the
  Mac: three commands send keys, and keys go to whichever app is in front.
  The command brings Vitruvian forward and sends nothing unless the
  keyboard is then on it.
- **Save first, compare after.** The clipboard
  (`pbpaste > "$TMPDIR/clip.before"`), the app's settings
  (`defaults export com.vitruviansoftware.vitruvian "$TMPDIR/settings.before.plist"`)
  and a listing of its support folder. A check that copies, or flips a
  switch by mistake, shows up in the comparison and nowhere else.
- It finds the app by its bundle id and needs the terminal to have
  Accessibility already. It never asks for, grants or changes a permission.
  The app must be in English: it presses buttons by their English names
  (`ByHandRules.Words`).
- **Keys go through System Events** (`osascript`), as the terminal's own
  would. Posting raw key events was tried first: a folder picker took
  neither Command-Shift-G nor the typed path that way, and chose whatever
  folder it was showing. Run against the released app (3.42.0) on
  2026-10-12: `open-settings`, `page`, `tools`, `add-tool` with a path that
  holds a space, `focused`, `press`, `run-command` for a command that is
  there and one that is not, `remove-tool`, `quit` and `launch`.
- **Do not script another app to help a check.** `tell application "Finder"`
  from the shell put a macOS prompt on the person's screen asking to let the
  terminal control Finder. Open a folder with `open`, close a window through
  System Events, and leave that prompt to the person if it ever appears.
- **A sound can only be heard.** The system log shows no alert sound and the
  power assertions cannot tell one from music that is already playing. Ask the
  person to listen, say when, and play a plain `osascript -e beep` first so
  both know the Mac's alert sound is audible.
- **Never click a place on the screen by its coordinates.** A panel that had
  closed left the click to land on another app's window.

What doing the checks taught, each held in `Tools/ByHandRules.swift` and by
`ByHandRulesTests`:

- Press by exact name, and of several controls with that name the last: a
  sheet's controls come after its window's. A loose match for a button once
  turned an unrelated feature off. `press` takes no part of a name.
- The Extensions page starts at its title, which the sidebar's row shares:
  the steps read from the last "Extensions" before "Add from Folder…"
  (`ByHandRules.pageStart`). Until 2026-10-15 the tools were the last card
  of the Features page, which is lazy: it had to be scrolled to its end,
  twice, before the card was there to find.
- In the command bar Return runs the top result, which is often a longer
  title that starts the same. `run-command` reads the results and moves to
  the row that is the command before Return, and runs nothing when the bar
  does not offer it. Pressing a result through the Accessibility API does
  nothing.
- A tool's row is found by the tool's whole name, and only when one row has
  it.
- A press that opens a folder picker, an alert or a sheet is answered late
  or not at all: the app is held in what it opened, and the Accessibility
  API gives back "cannot complete" (-25204) for a press that worked. That
  answer counts as pressed (`ByHandRules.answer(toPress:)`), and the step
  then waits, a few seconds at most, for what the press was to open, and
  says what it pressed and did not see when it never comes.
- Every cell and row of a list says it is focused. `focused` lists only
  what a key acts on, a button, field, switch, pop-up or slider, and with a
  sheet open only what is in the last sheet (`ByHandRules.keyTargets`).
- A step goes where it needs to be by itself: `tools`, `add-tool` and
  `remove-tool` open Settings on the Extensions page;
  `run-command` opens Settings on Command Bar, and leaves the bar closed.
- `add-tool` types the folder's whole path into the picker as it is, so a
  space in it is a character. Without `--agree` it leaves the agreement
  sheet open and says where the keyboard is: the start of the Space and
  Return check.

How far it is proven: against the app (3.42.0, macOS 27, 2026-10-12)
`windows`, `open-settings`, `page` and `tools` worked. That run found four
faults in `add-tool`, `run-command` and `focused`, mended since; nobody has
run those three, `remove-tool`, `quit` or `launch` against the app after
the mending. On 2026-10-15 `tools`, `add-tool` and `remove-tool` moved from
the Features page's card to the Extensions page, and nobody has run them
against an app that has the page. `select N`, from `dump`, is the way the first scripts selected
a page. It takes no screenshots: use `screencapture`.

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
