# Vitruvian sub-project 2: the capability broker and the first three bundled tools — design

**Date:** 2026-10-09 · **Status:** approved by James 2026-10-09, with every default in section 13 · **Owner:** compass
**Scope:** `apps/desktop/vitruvian` only. No SDK package, no outside code.
**Parent:** `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`
(sections 5, 6, 8, 10 and 11; sub-project 2 in section 12).

## 1. What this is

Sub-project 1 gave the app one list of commands. A feature is still wired in
by hand, though, and it still reaches the clipboard, the keyboard and other
sensitive services directly.

This sub-project adds the three things that turn a feature into a **tool**:

- a **manifest**: one value that says what the tool is, what it needs and
  what it adds;
- a **bundled tool interface**: how the app starts and stops a tool that is
  compiled in, and hands it what it may use;
- a **capability broker**: the one door to sensitive services. A tool gets
  through it only for what its manifest declares.

Then it moves three real features onto them, bundled: the **Port manager**,
the **URL cleaner** and **Paste as plain text**.

Nothing a user sees changes. Every step is a refactor that keeps behaviour
identical. The point is to prove the contract on our own work before
sub-project 3 puts a process boundary and a stranger's code behind it.

**Done when** all of these hold:

1. The three features each have a manifest, registered at launch.
2. In the files that belong to them, no code touches a sensitive service
   except through the broker. A lint proves it (section 8).
3. Their arms are gone from `FeatureRuntime`'s switches, and their lines are
   gone from the quit list in `AppDelegate`. The tool host does both jobs.
4. Their existing tests pass unchanged, and the new tests in section 10 pass.
5. The by-hand checks in section 10 are recorded with the Mac and macOS
   version they were run on.

**As built, checked on 2026-10-09** against the code at the end of stage C.
Two of the five are met as written. The sub-project is built; it is not done
by its own list.

1. **Met.** `BundledTools.all` lists the three types, each with a manifest.
   `main.swift` calls `BuiltinTools.install()`, which registers each from its
   manifest. `ToolBrokerTests.manifestsAgree` holds each manifest to its
   `AppFeature` and to the registered defaults.
2. **Met, for the files the lint lists.** `MIGRATED_TOOLS` has three rows and
   ten files, and `source_lints_test` passes. Files that serve a tool and
   belong to something else are outside it; section 8 names them.
3. **Not met as written.** No arm is gone: the switches are exhaustive, so
   each arm stays and says something else. The URL cleaner's and Paste as
   plain text's return `.tool(id)`, and their own actions and `perform` arms
   are gone. The Port manager's returns `[]`, as it did before this
   sub-project: it has no background work, so there is nothing to hand the
   host. The quit list names none of the three. The URL cleaner's line is
   gone; the other two never had one; `ToolHost.stopAll()` stops them.
   `SelfUninstall` keeps one line for Paste as plain text, which now calls
   `ToolHost.suspend`.
4. **Not met as written.** The tests pass, old and new. The expectations of
   the tests that were there before each stage were kept, but not every
   line. Two calls in `ClipboardFeatureTests` changed because the function
   they called moved into the broker: the body of one helper in stage B, one
   call site in stage C. Two expectations in `ToolPlatformTests`, written in
   stage A, changed on purpose. The list of capability names grew in stages
   B and C. "No capability rides on a macOS grant" became "one does:
   `keystrokes`, on Accessibility" in stage C.
5. **Not met.** None of the by-hand checks has been run by anyone, for any
   of the three stages. The pull requests of stages A (#3027) and B (#3037)
   list their checks and say "None are done". Stage C's fifteen are not done
   either. Nothing in section 10's by-hand list is known to work on a real
   Mac until somebody runs it.

## 2. What the assessment found

Two read-only assessments ran on 2026-10-09 against `main` at `3ad6ed46d`.
Counts marked *search* come from text searches, not a line-by-line tally.

**The three features are less clean than the parent design assumed.** It
picked them as the easiest. Each has a catch the broker has to answer.

- **The Port manager's dangerous half belongs to another feature.** Listing
  ports is one `lsof` call through the shared `Shell` helper. Killing a
  process goes through `KillProcessService`, which is a different, beta
  feature. `PortManagerService.terminate` does nothing unless that other
  feature is installed. The kill path includes an administrator-password
  prompt. Nothing tests it.
- **The URL cleaner does not read and write the clipboard. It rewrites it in
  place.** Every 0.8 seconds it checks whether the clipboard changed, and if
  the text is a link with tracking parts it replaces the contents, keeps
  another app's source marker, and relies on exact change counts so that
  clipboard history does not record the rewrite as a new copy. A broker that
  hands back a copy of the text and takes a new string cannot do this.
- **Paste as plain text is three sensitive things in one press.** A global
  hotkey; a walk through the front app's menus over Accessibility to press
  "Paste and Match Style"; and, when that fails, a paste dance that swaps the
  clipboard, synthesises Command-V with hard-coded delays, and restores the
  clipboard half a second later. The dance lives in `TransientPaste`, which
  text snippets also use. Nothing tests the press path.
- **None of the three has a registry command.** `BuiltinCommand` has fifteen
  cases and none is theirs. Their command-bar rows call services directly.
- **Their views call services directly too.** The Port manager and URL
  cleaner Settings pages and panel views reach `NSPasteboard`, `NSWorkspace`
  and `KillProcessService` from view code. Paste as plain text has no page;
  it is a section of the clipboard history page.

**What a feature costs to wire today.** Traced through the URL cleaner: 21
places. Eleven are exhaustive switches the compiler checks. The rest are by
convention: registered defaults, the quit list, the service's own "am I
installed and enabled" check, and each optional surface.

**What exists to build on.**

- The registry (`ToolDescriptor`, `ToolRegistry`, `BuiltinTools`) knows a
  tool's id, name, symbol and commands. It has no capabilities, preferences,
  activation, or start and stop.
- Shared helpers already sit in front of most sensitive services:
  `GeneralPasteboardAccess` (a serial lane for the clipboard), `TransientPaste`,
  `QuickToolHotkey`, `Shell` and `AdminShell`, `QuickToolHUD`, `Notifier`,
  `Permissions`, `PrivateFileStore`. None checks who is calling.
- Services follow one shape: a main-actor singleton with an injectable
  `Environment` struct, and tests that pass a fake one. The broker follows it.

**What the broker is up against.** In `Services` alone: 124 singletons and
about 1,070 `.shared` references; 80 direct Accessibility checks in 37 files;
51 direct clipboard uses in 24 files; 35 direct `CGEvent` constructions;
14 direct `Process()` launches (*search*). This sub-project does not try to
clear that. It draws the line around three tools and leaves everything
outside it as it is.

**Two corrections to the parent design.**

- Section 11.1 says each migration updates "the file map in
  `upstream/upstream.py`". There is no static file map. The tool derives
  renames from `git diff`. The rule that matters is the other one: logic
  stays in its existing file.
- Section 11 says migration 1 "proves the generated Settings page".
  Section 12 puts generated Settings pages in sub-project 4. This spec follows
  section 12: the three tools keep their hand-built views (section 7).

## 3. Decisions this spec makes

These are the calls that shape everything below. Each is a default, with what
it costs if it is wrong.

| # | Decision | Why | If wrong |
|---|---|---|---|
| 1 | The broker offers **operations, not raw services**. A tool asks to "rewrite the clipboard if it still holds what I saw", not for the pasteboard. | A raw service cannot cross a process boundary later, and cannot be checked. An operation can. | Operations are too narrow for the next tool, and the broker grows one per feature. Section 9 limits this. |
| 2 | **Add a `processes` capability** the parent design does not list: list listening ports, end a process. | The Port manager needs it, and the admin escalation behind "end a process" is exactly what must sit behind the broker. | One more capability to carry into the protocol. |
| 3 | **The Port manager keeps depending on the Kill process feature** for ending a process, as today. The broker's operation refuses when that feature is not installed. | Behaviour stays identical. Untangling two features is its own change. | The odd dependency is now written into the broker. It is one `guard`, easy to lift. |
| 4 | **One clipboard watcher in the broker**, at the URL cleaner's 0.8 seconds. Only migrated tools use it. Clipboard history and auto-clear keep their own timers. | A tool must not own a system timer. Merging all three watchers changes timing for features this sub-project does not touch. | Three watchers run until those features migrate, as now. |
| 5 | **Bundled tools keep their hand-built views.** A view talks to its tool, never to a service. | Generated pages are sub-project 4. The rule still removes sensitive calls from view code. | None for users. Sub-project 4 has more to convert. |
| 6 | **Bundled tools are always granted what they declare.** The broker still checks the macOS permission and that the tool is installed. | A consent screen for our own features is noise. The grant store exists so sub-project 3 only has to fill it. | None until external tools arrive. |
| 7 | **A tool's existing shortcut stays a `GlobalShortcutRole`**, with its saved key and hotkey id. The broker registers it. | Saved settings must not move (parent section 10). Part 3 already decided our own commands do not also ask for the shortcut surface. | Bundled and external tools bind hotkeys through two operations for a while. |
| 8 | **Characterisation tests come before each move.** The kill path and the paste path have no tests today. | "Behaviour identical" is a claim nobody can check without them. | Slower start to migrations 1 and 3. |
| 9 | **Three stages, three plans, at least three pull requests.** Port manager, then URL cleaner, then Paste as plain text. | Each adds capabilities the next needs, and each leaves the app shippable. | None. |

## 4. Architecture

```mermaid
flowchart TD
    M[Tool manifest - a plain value] --> H[Tool host]
    H -->|start, stop, run a command| T[Bundled tool]
    H -->|a handle scoped to this tool| T
    T -->|operations| B[Capability broker]
    B --> G{Declared? Installed? macOS grant?}
    G -->|yes| S[Shared services: clipboard lane, hotkeys, paste, shell, alerts]
    G -->|no| R[Refused, with a reason]
    H --> REG[Tool registry from sub-project 1]
    FR[FeatureRuntime] -->|one arm for every migrated tool| H
    V[The tool's views] -->|state and commands only| T
```

Four new parts. Each has one job and its own file.

- **Tool manifest** (`Core/Platform/ToolManifest.swift`). A plain value. It
  wraps the `ToolDescriptor` that exists and adds what is missing.
- **Tool host** (`Services/Platform/ToolHost.swift`). Owns the live tools:
  builds them, starts and stops them, registers their commands. It replaces
  the per-feature arms in `FeatureRuntime` and the per-feature lines in the
  quit list.
- **Capability broker** (`Services/Platform/Broker/`). Checks, then does the
  work by calling the shared helpers that exist. One file per capability.
- **Tool services** (`Services/Platform/ToolServices.swift`). The handle a
  tool is given. It carries the tool's id, so the tool cannot ask as someone
  else, and exposes one small interface per capability.

The parent design's rule holds here in its in-process form: a bundled tool
calls **the same operations, with the same names and the same plain-value
arguments**, that an external tool will send as messages. So every operation's
arguments and results are values that could be written as JSON. No closures
that capture app state, no `NSPasteboard`, no `CGEvent`, no view types cross
the broker.

Two in-process forms stand in for messages. A completion closure the tool
passes in is a reply. A `ClipboardRewriteRule` is a question the host asks the
tool in the middle of one look at the clipboard, and waits for: its three
functions take and return plain values, are `@Sendable`, and capture no app
state. It is a function and not a message because the whole look must stay
one job on the clipboard lane (section 7.2). Sub-project 3 decides how a tool
in another process answers it.

## 5. The manifest

`ToolManifest` in `Core`. Field names match section 6 of the parent design so
that the JSON schema in sub-project 3 is a transcription, not a redesign.

| Field | Type | For a bundled tool it comes from |
|---|---|---|
| `tool` | `ToolDescriptor` (id, name, symbol, commands) | as today |
| `group` | `FeatureGroup` | `AppFeature.group` |
| `capabilities` | `[CapabilityRequest]`: a `Capability`, a reason, and whether the tool starts without the grants the capability rides on | new |
| `preferences` | `[PreferenceDeclaration]`: storage key and default (a `PreferenceDeclaration.Value`, which carries the type) | the keys the feature has today, unchanged |
| `activation` | `[Activation]`: `.onLaunch`, `.onCommand`, `.onShown` | what `FeatureRuntime.actions(for:)` does today |
| `enabledBy` | a preference key, or none | `AppFeature.enabledKeys` |
| `runtime` | `.bundled` | fixed |

Not in this sub-project: `version`, `protocol`, `publisher`, `license`,
`homepage`, `platform`. They mean nothing for code compiled into the app, and
adding empty fields invites wrong values.

Rules the initializer enforces, returning nil otherwise (the pattern
`ToolDescriptor` uses):

- A capability is listed once.
- Every preference key is listed once, and the `enabledBy` key is one of them.
- A bundled-form id still names an `AppFeature`.

Rules a test enforces, because they compare against the app:

- **A manifest agrees with its `AppFeature`.** Group and symbol match. Every
  macOS permission the feature declares is implied by a capability the
  manifest declares (`keystrokes` implies Accessibility, and so on), and the
  reverse. This is what stops the two descriptions drifting while both exist.
- **Every preference key a manifest declares is registered with the same
  default, and no key belongs to two tools.** So settings backup keeps
  working with no per-tool list, and the "forgot to add it to the backup" gap
  closes for migrated tools. The test does not check "exactly the tool's
  keys": nothing in the app says which registered key belongs to which
  feature. The default's type in code is `PreferenceDeclaration.Value`; it is
  nested because `Core` already has a `PreferenceValue` protocol.

The reason text on a capability is not shown to anyone in this sub-project.
It is still required, in English, because writing it is the cheapest check
that the capability is needed. It becomes a localised string when the consent
screen exists.

## 6. The bundled tool interface and the host

```swift
@MainActor
package protocol BundledTool: AnyObject {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
    /// Begin whatever the tool does in the background. Called when the tool
    /// is installed, enabled, and has what its capabilities ride on.
    func start()
    /// Undo everything `start` did. Must be safe to call twice.
    func stop()
    /// Run one of the manifest's commands.
    func run(_ command: CommandID)
    /// Whether a command can run right now.
    func canRun(_ command: CommandID) -> Bool
}
```

**As built.** Stage A's protocol required only `manifest`, `init(services:)`
and `stop()`, and its host only built a tool on first use and stopped every
built tool at quit. Stage B added `start`, `run` and `canRun` to the
protocol, and to the host the run rule (`ToolHost.shouldRun`),
`ToolHost.sync`, `ToolHost.canRun` and `ToolHost.run`, with the
`FeatureRuntime` action `tool(ToolID)`. `start` is called every time the host
finds the tool should run, so it too must be safe to call twice. The host
learns which tools exist from one list, `BundledTools.all`. The Port manager
has no background work and no command: its `start` and `run` do nothing. The
rule's grant clause was written and tested as a plain function in stage B,
when no capability rode on a macOS grant.

Stage C added the first capability that does, `keystrokes`, on
Accessibility (`Capability.ridesOn`), so a real tool reaches the grant
clause. It also added `CapabilityRequest.startsWithoutGrant` and
`ToolManifest.grantsNeededToStart`. That is what "the tool declared it can
start without" means in code, and it is said for each capability, not once
for the tool: the host starts a tool when it holds the grants its
capabilities ride on, less the ones a request says it starts without. A
request for a capability that rides on nothing may not say so. Paste as
plain text says it for `keystrokes`: its shortcut is taken with or without
Accessibility, and the first press asks. Every `keystrokes` call is still
refused until the grant is there. Stage C also added `ToolHost.suspend(id)`,
which stops one tool at once whatever the rule says; a full uninstall calls
it.

A tool holds no singleton of its own and reaches for none. Everything it may
touch arrives through `services`. The existing service class for each feature
becomes its tool: `URLCleanerService` conforms to `BundledTool`, keeps its
file and its logic, and loses its `static let shared`.

**The host decides when a tool runs.** One function, `shouldRun(tool)`, is
true when all of these hold: the tool is installed in the Features hub; its
`enabledBy` preference is on, or it has none; every macOS permission its
capabilities ride on is granted, or the tool declared it can start without
(Paste as plain text does: it registers its hotkey and asks on first press).
The host calls `start` and `stop` so that the tool's state matches. That
replaces the "am I installed and enabled" check each service does for itself.

**When the host re-decides.** At launch; when the hub installs or removes a
tool; when a preference a manifest declares changes; when a macOS permission
changes. The first two and the last already reach `FeatureRuntime`. For
migrated tools `FeatureRuntime` gets one action, `.tool(ToolID)`, that calls
the host, and the tool's own arm in `actions(for:)` and `perform` goes.
The exhaustive switches stay exhaustive: the arm now says "this one is a
tool".

As built, a change to a grant reaches the host with nothing new built for
it. `AppDelegate` already subscribes to `Permissions`, and
`FeatureRuntime.permissionDidChange` syncs every feature that declares the
grant; a tool's arm is `.tool(id)`. The end of a shortcut recording reaches
it the same way: `ShortcutCapture.end` syncs every feature that has a
`GlobalShortcutRole`, the host calls `start`, and the tool takes its key
again.

As built, nothing watches the preferences. Whoever flips a tool's switch
tells the host, as each caller told the service before: a view calls
`ToolHost.shared.sync(X.self)`, and the command bar's toggle rows go through
`FeatureRuntime.sync`. An observer would also fire for a settings restore and
for `defaults write`, which do not re-sync today.

**At quit** the host stops every running tool, in the reverse of start order.
The tool's hand-written line leaves `AppDelegate`. Today that line builds the
URL cleaner's singleton at quit even when the feature is not installed; the
host never builds a tool it has not started.

**Commands.** `BuiltinTools` keeps registering every hub feature. For a
feature that has a manifest it registers the manifest's descriptor and sets
handlers that call the host's `canRun` and `run`, which call the tool's. It
asks for the host only when a command is run or asked about, so registering
builds no host and no tool. The command-bar rows that exist keep their saved
ids, so nobody's reordered or hidden rows move. As built for the URL cleaner:
the `action.cleanURL` row stays hand-built and runs the command
`urlCleaner/cleanClipboard` through the registry. That command asks for no
surface, or a second row would appear beside the first. The
`selection.cleanLink` row calls two methods on the tool, `clean` and `copy`,
because a command takes no argument. The Port manager has no
command today and gets none: adding one adds a string in 15 languages and a
row users did not ask for.

**Views.** A view gets its tool from the host and reads published state or
calls a command. It does not call a service. Where a view needs something
sensitive (the Port manager row copies a PID, opens a link), the tool offers
it as a method and the tool goes through the broker.

## 7. The broker

### 7.1 What a call goes through

Every operation runs the same three checks, in this order, before any work:

1. **Declared.** The calling tool's manifest lists the capability. If not,
   the call is refused and, in a debug build, traps: it is a programming
   error, never a user state.
2. **Installed.** The tool is installed in the hub. A tool removed while a
   call is in flight gets a refusal, not a crash.
3. **Granted.** Any macOS permission the capability rides on is granted, and
   the grant store says the user allows it. For a bundled tool the grant
   store always says yes (decision 6). As built, "is granted" is asked of
   macOS at the moment of each call, not read from `Permissions`: its
   values are published a main-queue hop late at launch, and afterwards lag
   behind a change by up to a poll (2.5 seconds after a grant, 60 after a
   revocation).

A refusal is a value, `BrokerRefusal`, with one of four reasons: those three,
and **unavailable**, when the host cannot offer the operation right now.
Ending a process while the Kill process feature is not installed is the
first case. The tool decides what to do: Paste as plain text beeps or asks for Accessibility
once, exactly as today.

The broker never shows UI of its own in this sub-project.

### 7.2 Capabilities and operations

Only what the three tools need. Each operation names the helper it calls
today, which is what keeps behaviour identical.

| Capability | Operations | Rides on | Backed by | First needed by |
|---|---|---|---|---|
| `notify` | `hud(icon, message)`; `beep()`. Stage A built `beep()`, stage B `hud`. | none | `QuickToolHUD`, `NSSound` | Port manager |
| `open` | `openURL(url)` | none | `NSWorkspace` | Port manager |
| `processes` | `scanner()` (start times and the listening-sockets report); `canTerminate`; `isProtected(pid, name)`; `terminate(pid, name, startedAt, force)` | none (admin prompt on demand) | `Shell` running `lsof`; `KillProcessService` | Port manager |
| `clipboard.write` | `write(text, kind)`; `writeLink(link)`, a link as text and as a URL, signed as the app's own, first needed by the URL cleaner | none | `GeneralPasteboardAccess`; the broker's watcher | Port manager |
| `clipboard.read` | `readText()`; `readPlainText()`, the plain string, else the words of the RTF or HTML, first needed by Paste as plain text. No plain stream of changes is built: none has a user. | none | the lane; the broker's watcher | URL cleaner |
| `clipboard.rewrite` | `rewriteLinks(rule)`; `stopRewritingLinks()`. `rewriteLinks` also needs `clipboard.read`. | none | the lane; the broker's watcher | URL cleaner |
| `storage` | `reader()`, which gives a value with `value(for:)`, for keys the manifest declares. No `set`. | none | `UserDefaults` | URL cleaner |
| `hotkey` | `bind(role, onPress, onRegistered)`; `unbind(role)`. A press, and whether macOS gave the key, are replies handed to `bind`. A tool binds only a role of its own feature, and never sees a hotkey id. | none | `HotkeyBindings` over `QuickToolHotkey`, which claims the key with `SystemShortcutTakeover` itself | Paste as plain text |
| `keystrokes` | `refusal`, which asks "may I?" and does nothing; `requestGrant()`; `paste(text)`; `pressFrontAppMenuItem(matching: key equivalents)` | Accessibility | `TransientPaste`; `Permissions.requestAccessibility`; `FrontAppMenu`, the Accessibility menu walk | Paste as plain text |

The listening-sockets report is `lsof`'s text, not parsed ports. The parser
and the stability rule are the tool's own logic and stay in its file.

Notes on the ones that are not obvious:

- **`clipboard.rewrite`** is the answer to the URL cleaner's catch.
  Rewriting a copied link is one operation that carries a rule,
  `clipboard.rewriteLinks(rule:)`. The tool hands the broker the rule. On
  each tick of the broker's one timer, the broker runs one job on the
  clipboard lane: read the count, ask the rule about the types, read the
  text, ask the rule for a replacement, ask about the HTML when there is
  any, check the count again, write. An earlier draft of this spec had three
  steps instead (the tool is told of a change, reads the text, then asks for
  a rewrite if the count is still the same). That was not built, because
  three messages are not one job, and four things would change. Clipboard
  history shares the lane and could read the raw link between two of the
  steps. The text would be read before the types have said yes, so a
  password or a large promised copy would be fetched only to be left alone.
  Link parsing and the scan of the HTML would move to the main thread. And a
  look still waiting when the cleaner is switched off could write. The
  broker keeps a foreign source marker and the remote-clipboard marker. It
  does **not** tell clipboard history to ignore the change. This spec said
  it did and called that today's code; it never was. The cleaner never
  called `ignoreNextChange`, and history records the cleaned link as a copy
  of its own. It is its own capability because replacing what the user
  copied is a bigger thing to allow than reading it or adding to it.
- **`keystrokes.paste`** is `TransientPaste` unchanged, timings included.
  Text snippets keep calling `TransientPaste` directly; they are not a tool
  yet. As built, the paste lets go of the calling tool's own key when that
  key is Command-V, and takes it again once the paste is typed: otherwise
  the tool would be pressed by its own paste. `TransientPaste`'s call to
  clipboard history's `ignoreNextChange` sits behind it without having
  moved.
- **`keystrokes.refusal` and `requestGrant()`** are there because the
  Accessibility check comes before the clipboard is read. A tool asks
  `refusal` first, so that without the grant nothing is read at all, and
  `requestGrant()` shows the system prompt and the app's guide. The memory
  of having asked once per launch stays in the tool.
- **`pressFrontAppMenuItem`** takes a list of key equivalents, as plain
  values (`MenuKeyEquivalent`: a character and the Accessibility modifier
  mask), and returns whether it pressed one. It takes no titles: the code
  it replaced never matched a title, on purpose, because titles change with
  the language. It presses only an item that is enabled. The walk, its
  0.35-second limit per element and its cap of 600 elements stay as they
  are.
- **`processes.terminate`** carries the process's start time, as the call
  does today, so a recycled PID is never killed by mistake.
- **`storage`** refuses a key the manifest did not declare. That one rule is
  what makes a manifest's preference list true. It hands out a reader, a
  value that can be read on any thread, because the cleaner reads its rules
  on the clipboard lane at the moment a link is about to be cleaned. The
  broker's checks run when the reader is handed out. There is no `set`:
  nothing in the cleaner writes a preference, and its views bind them with
  `@AppStorage`.

Not offered yet, though the parent design lists them: `windows`,
`screen.capture`, `audio.devices`, `calendar`, `files`, `metrics`, `network`,
`secrets`. No tool in this sub-project needs them. An operation is added when
a migration needs it, never ahead.

### 7.3 Shape in code

`CapabilityBroker` is a main-actor class with an `Environment` of closures
over the shared helpers and a `.live` value, the shape `ToolShortcutRegistrar`
and `FeatureRuntime` have. Tests build it with fakes. Each capability is a
small type in its own file under `Services/Platform/Broker/`, so the broker
does not become one large file.

`ToolServices` is what a tool holds: `services.clipboard`, `services.notify`
and so on. Asking for a capability the manifest does not declare returns a
facade whose every operation refuses, so a tool's code reads the same either
way and the mistake surfaces as a refusal a test can assert on.

## 8. "Only through the broker", made checkable

The done-when is worthless as a promise. It is a lint.

`migrated_tools_reach_services_through_the_broker` in `bazel/source_lints.py`
holds a table: tool id, and the files that belong to it (service, support,
views). In those files it fails on any of:

`NSPasteboard`, `GeneralPasteboardAccess`, `CGEvent`, `CGEventSource`,
`AXIsProcessTrusted`, `AXUIElement`, `QuickToolHotkey(`, `RegisterEventHotKey`,
`Process()`, `Shell.`, `AdminShell.`, `NSWorkspace.shared`, `UserDefaults`,
`Notifier.`, `QuickToolHUD.`, `TransientPaste`, and `.shared` on any type that
is not on a short allow-list.

The last one is the strong one: a migrated tool's files name no service
singleton at all. The allow-list as built is `ToolHost`, `L10n` (the
language a view draws in), `SettingsRouter` and `PanelInteractionState`. It
grows only by review. The table of files grows
by one row per migration, in the same pull request.

As built the table has three rows. A file that serves a tool and belongs to
something else is not in its row, so the rule does not check it. For Paste
as plain text those are the Clipboard page (`ClipboardSettings.swift`), the
shortcut row every feature shares, `QuickToolsSupport.swift` and the command
bar's hand-built row. For the URL cleaner they are the menu panel's view
that binds `panelUtilityURLCleaner` and the command bar's two rows.

The lint lists whole files, which is why Paste as plain text's Settings
section moved to a file of its own, `UI/Settings/PastePlainSettingsSection.swift`.
`ClipboardSettings.swift` rightly calls clipboard history's services, so it
cannot be in the row, and a section left inside it would be a view of a
migrated tool that nothing checks. It is still a section of the Clipboard
page, in the same place (section 13, default 4). The page decides whether it
shows and hands it the Accessibility grant as a plain value.

One exception, checked by the same rule: a view may bind a preference with
`@AppStorage`, but only to a key its tool's manifest declares. A toggle that
writes straight to defaults is how every Settings page works today, and
rewriting those bindings buys nothing while the key is one the tool owns.

A second rule keeps the other side honest: under `Services/Platform/Broker/`
no file may import or name a tool. The broker serves tools; it does not know
them.

Both rules get a planted-regression entry in `Tests/mutation_checks.py`.

## 9. Risks

- **The broker grows one operation per feature and becomes the app.** The
  defence is decision 1 plus a review rule: an operation is named for what it
  does to the system, never for the tool that wanted it. `clipboard.rewrite`
  passes. `cleanURLOnClipboard` would not. If the third migration needs more
  than two new operations that only it will ever use, stop and revisit.
- **Timing changes in the paste path.** The delays are tuned by hand against
  real apps. The plan moves `TransientPaste` behind the broker without
  editing it, and the by-hand list checks the apps that are known to be
  fussy.
- **Characterisation tests pin a bug.** They record what the code does, not
  what it should. Anything that looks wrong is written down, not fixed, in
  the migration; fixing it is a separate change.
- **Upstream keeps editing these files.** All three features and every helper
  behind the broker carry the upstream header, and URL cleaner fixes were
  ported as recently as #2814. Logic stays in its file; a service class gains
  a conformance and loses its singleton. Each migration logs every touched
  upstream file in `UPSTREAM.md`.
- **Two descriptions of one feature.** `AppFeature` and the manifest both
  exist until a later sub-project removes the enum case. The agreement test
  in section 5 is what keeps them from drifting.
- **The host starts something the old code did not, or the reverse.** The
  rule in section 6 is new code deciding old behaviour. Each migration has a
  table test: every combination of installed, enabled and permission, against
  what the old `syncWithPreferences` did.

## 10. Testing

Automated, in the existing `TestSuite` under the `platform` group:

- **Manifest rules**: each rejection in section 5, and the agreement test
  against `AppFeature` and the registered defaults.
- **Broker checks**: for every operation, the three refusals and the success,
  against fake services. A refused call does no work: the fake records zero
  calls.
- **`clipboard.rewrite`**: replaced when the count matches; left alone when
  it moved; foreign markers kept. Clipboard history is not told to ignore
  (section 7.2), so there is nothing to test there.
- **Host**: the start-and-stop table for each tool; stop is safe twice; quit
  stops in reverse order; a tool that was never started is never built.
- **Per migration**: the feature's existing tests unchanged; the
  characterisation tests written first (decision 8); one test that each
  command the manifest declares appears on each surface it names.
- **Lints**: the two rules in section 8, each with a mutation.

By hand, because no test presses a real key or reads the real clipboard.
Recorded in each pull request with the Mac and macOS version.

- **Port manager**: the list fills; a row's copy and open-in-browser work;
  ending a process works, including one that needs the admin prompt; with the
  Kill process feature removed, the end button does what it did before.
- **URL cleaner**: copy a link with tracking parts and it is cleaned within a
  second; clipboard history shows the entries it showed before the change;
  copy from an app that marks its source and the mark survives; switch the
  feature off and copying is left alone. History is compared with the build
  before, not with "one entry", because the two features have a timer each:
  when history's fires first it records the raw link, and then the cleaned
  one.
- **Paste as plain text**, fifteen checks. The stage C plan's Task 8 gives
  the steps for each, and a build from before the change to compare with.
  1. In an app with "Paste and Match Style" (TextEdit) the shortcut pastes
     the text in the style around it.
  2. In an app without it (Terminal) the shortcut types the text.
  3. A second later a plain Command-V still pastes the original, formatting
     included.
  4. Clipboard history shows the same entries as the build before.
  5. A copy that is only HTML pastes as its words. No unit test runs that
     branch.
  6. Without Accessibility the first press asks, once, and pastes nothing;
     the next beeps; the command bar's row beeps.
  7. Granted while the app runs, the very next press pastes, with no
     relaunch and no wait.
  8. Taken away while the app runs, a press beeps and does not ask again.
  9. Recording another feature's shortcut, or leaving a recording with
     Escape, does not kill this one.
  10. Its own shortcut re-recorded: the old combination stops and the new
      one works, and Settings › Shortcuts shows the new one.
  11. With the shortcut set to plain Command-V, one press pastes once, not
      twice and not in a loop.
  12. On Settings › Clipboard the section is where it was, with the same
      header, switch, caption and shortcut row; the hub's link opens the
      page with the section outlined; with the switch off the key is the
      front app's again and the command bar's row still pastes.
  13. The command bar's row keeps its place, its pin and its name across
      the two builds, and there is one of it.
  14. Removed in the hub, the shortcut, the row and the section go;
      installed again, it works with its switch and shortcut as they were.
  15. After quit the key is the front app's again; after a relaunch the
      first press pastes and nothing asks for Accessibility; a text snippet
      with a line break still expands.

  `TransientPaste` has no unit test. Its guarantee in this sub-project is
  that the file did not change. The full uninstall is not checked by hand,
  because it removes the app; its one changed line is pinned by
  `PastePlainTests.runRule`.

As of 2026-10-09 none of these lists has been run, for any stage (section 1,
condition 5).

## 11. Stages

Each is its own plan and at least one pull request, a `refactor`, and cuts no
release.

| Stage | Builds | Migrates | Capabilities added |
|---|---|---|---|
| A (built) | Manifest, tool interface, host, broker skeleton, both lints | Port manager | `notify`, `open`, `processes`, `clipboard.write` |
| B (built) | The broker's clipboard watcher, the host's start, stop and commands, the `FeatureRuntime` action | URL cleaner | `storage`, `clipboard.read`, `clipboard.rewrite`; also `writeLink` in `clipboard.write` and `hud` in `notify` |
| C (built) | Permission changes reaching the host, with the first test of the run rule's grant clause; a tool that may start without its grant; the broker asks macOS about a grant at each call, so nothing waits on `Permissions` | Paste as plain text | `hotkey`, `keystrokes`; also `readPlainText` in `clipboard.read` |

All three stages are built. Stages A and B are merged (#3027, #3037); each
pull request lists its by-hand checks and says none was done. Stage C's are
not done either (section 1, condition 5).

Stage B left these for stage C or later, each with the first tool that
needs it: commands that take an argument; `storage.set`; a plain stream of
clipboard changes; an observer for a preference changed from outside the
app; `TransientPaste`'s call to clipboard history's `ignoreNextChange`.
Stage C did the last: the call is real there and now sits behind
`keystrokes.paste`, without having moved. The rest still wait for the first
tool that needs them, and so do titles in the menu press. Clipboard history
and auto-clear keep a timer each until they migrate. How a tool in another
process answers a `ClipboardRewriteRule` is sub-project 3's question, as is
how it hears a press, which arrives more than once.

Stage A is the large one: it carries all the new structure and the feature
with the least to move. B and C are mostly one capability and one feature
each.

## 12. Out of scope

- External tools, the protocol, the runtime, the SDK package, the consent
  screen. Sub-project 3.
- Generated Settings pages. Sub-project 4.
- Removing any `AppFeature` case.
- Migrating Kill process, text snippets, clipboard history or any feature
  that shares a helper with the three.
- Clearing direct service use outside the three tools' files.
- Island, menu-bar or Quick panel contributions beyond what the three
  features have today.
- Any change a user can see.

## 13. Open questions

Each had a default. James accepted every one on 2026-10-09. They are
decisions now. The stage A plan is
`docs/superpowers/plans/2026-10-09-vitruvian-broker-stage-a.md`; it changes
three details of this spec, listed in its decisions table, and its last task
brings this document in line. The stage B plan is
`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-b.md`; it changes
five details of this spec, listed in its decisions table, and its last task
does the same. The stage C plan is
`docs/superpowers/plans/2026-10-10-vitruvian-broker-stage-c.md`; it changes
eight details of this spec, listed in its decisions table, and its last
task does the same.

1. **`processes` as a new capability** (decision 2). *Default: yes.*
2. **Keep the Port manager's dependency on Kill process** (decision 3).
   *Default: yes for now; untangle when Kill process migrates.*
3. **`clipboard.rewrite` as its own capability**, separate from write.
   *Default: yes. Replacing what the user copied deserves its own line on a
   consent screen.*
4. **Paste as plain text stays a section of the clipboard history page.**
   *Default: yes. Giving it a page is a visible change.*
5. **Order.** The parent design says Port manager first. It has the least to
   move but the most awkward dependency. *Default: keep the order; Stage A
   needs a tool with no background work to prove the host simply.*
