// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The tool platform's values and registry, run over doubles: no tool runs.
enum ToolPlatformTests {
    static func run(_ suite: TestSuite) {
        ids(suite)
        descriptors(suite)
        builtins(suite)
        builtinTools(suite)
        registry(suite)
        radial(suite)
        wheel(suite)
        quickPanel(suite)
        commandBar(suite)
        housekeeping(suite)
        sampleTool(suite)
        tiles(suite)
        shortcutSurface(suite)
        shortcutMap(suite)
        commandShortcutStore(suite)
        shortcutRegistrar(suite)
        shortcutRegistrarUnregisteredCommand(suite)
        shortcutRegistrarKeepsItsKeys(suite)
        shortcutRegistrarRecording(suite)
        shortcutRegistrarSwitchedOff(suite)
        shortcutRegistrarRefusals(suite)
        shortcutRegistrarLimit(suite)
        shortcutRegistrarOwnToolsOnly(suite)
        shortcutRegistrarSaving(suite)
        shortcutConflicts(suite)
        shortcutSections(suite)
        shortcutRowDecision(suite)
        shortcutRowCommit(suite)
        shortcutRowAcceptsAStaleOffer(suite)
        shortcutRowState(suite)
    }

    static func ids(_ suite: TestSuite) {
        suite.expect(ToolID("screenshot")?.isBundledForm == true, "a bare name is a bundled tool id")
        suite.expect(ToolID("com.acme.deploys")?.isBundledForm == false, "a dotted name is an outside tool id")
        for bad in ["", ".", ".acme", "acme.", "a/b", "a b", "a\nb", String(repeating: "a", count: 129)] {
            suite.expect(ToolID(bad) == nil, "\(bad.debugDescription) is not a tool id")
        }

        let parsed = CommandID("screenshot/capture")
        suite.expect(parsed?.tool.rawValue == "screenshot" && parsed?.name == "capture",
                     "a command id splits into its tool and its name")
        suite.expect(parsed?.rawValue == "screenshot/capture", "a command id writes back what it read")
        suite.expect(CommandID("com.acme.deploys/open")?.tool.rawValue == "com.acme.deploys",
                     "an outside tool's command keeps the dotted tool id")
        for bad in ["", "noslash", "a/b/c", "/capture", "screenshot/", "a b/c", "a/b c"] {
            suite.expect(CommandID(bad) == nil, "\(bad.debugDescription) is not a command id")
        }
    }

    static func descriptors(_ suite: TestSuite) {
        let tool = ToolID("screenshot")!
        let capture = CommandDescriptor(id: CommandID(tool: tool, name: "capture")!, title: "Capture",
                                        symbol: "camera.viewfinder", surfaces: [.radial])!
        let made = ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [capture])
        suite.expect(made?.feature == .screenshot, "a bundled tool finds its feature by id")
        suite.expect(ToolDescriptor(id: ToolID("com.acme.deploys")!, name: "Deploys", symbol: "shippingbox",
                                    commands: [])?.feature == nil,
                     "an outside tool has no feature")

        let stray = CommandDescriptor(id: CommandID("colorPicker/pick")!, title: "Pick", symbol: "eyedropper",
                                      surfaces: [.radial])!
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [stray]) == nil,
                     "a tool cannot declare another tool's command")
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [capture, capture]) == nil,
                     "a tool cannot declare one command twice")
    }

    static func builtins(_ suite: TestSuite) {
        for command in BuiltinCommand.allCases {
            suite.expect(CommandID(command.rawValue) != nil, "\(command.rawValue) is a command id")
            suite.expect(command.id.tool.rawValue == command.feature.rawValue,
                         "\(command.rawValue) belongs to the tool of its own feature")
        }
        suite.expect(Set(BuiltinCommand.allCases.map(\.rawValue)).count == BuiltinCommand.allCases.count,
                     "no built-in command id repeats")
        for tool in RadialMenuTool.allCases {
            suite.expect(tool.command.feature == tool.feature,
                         "every radial tool runs the command of its own feature")
        }
        suite.expect(Set(RadialMenuTool.allCases.map(\.command)).count == RadialMenuTool.allCases.count,
                     "no two radial tools share a command")
    }

    /// A registry over doubles: `off` holds the features switched off in the hub.
    final class World {
        var off: Set<AppFeature> = []
        var ran: [String] = []
        var language = "first"
        lazy var registry = ToolRegistry(isAvailable: { [unowned self] in !self.off.contains($0) })

        func add(_ toolID: String, _ name: String, surfaces: Set<ToolSurface>, runnable: Bool = true) throws {
            let tool = ToolID(toolID)!
            let id = CommandID(tool: tool, name: name)!
            let command = CommandDescriptor(id: id, title: "plain \(name)", symbol: "star", surfaces: surfaces)!
            try registry.register(ToolDescriptor(id: tool, name: toolID, symbol: "star", commands: [command])!)
            try registry.setHandler(.init(title: { [unowned self] _ in "\(self.language) \(name)" },
                                          isRunnable: { runnable },
                                          run: { [unowned self] in self.ran.append(id.rawValue) }),
                                    for: id)
        }
    }

    static func commandBar(_ suite: TestSuite) {
        let world = World()
        do {
            try world.add("com.acme.deploys", "open", surfaces: [.commandBar])
            try world.add("screenshot", "capture", surfaces: [.radial])
            try world.add("com.acme.paused", "wake", surfaces: [.commandBar], runnable: false)
        } catch {
            suite.expect(false, "registering three distinct tools succeeds, got \(error)")
        }
        let rows = CommandBarCatalog.toolEntries(registry: world.registry, language: .systemDefault)
        suite.expect(!rows.contains { $0.id == "tool.com.acme.paused/wake" },
                     "the bar offers only commands that can run now")
        suite.expect(rows.map(\.id) == ["tool.com.acme.deploys/open"],
                     "the bar lists the commands that asked for it, and only those")
        suite.expect(rows.first?.title == "first open" && rows.first?.subtitle == "com.acme.deploys",
                     "a row is titled by its command and filed under its tool")
        suite.expect(rows.first?.stableKey == rows.first?.id,
                     "a row's name and pin survive under its command id")
        rows.first?.run(nil)
        suite.expect(world.ran == ["com.acme.deploys/open"], "Return on a row runs its command")

        world.registry.unregister(ToolID("com.acme.deploys")!)
        suite.expect(CommandBarCatalog.toolEntries(registry: world.registry, language: .systemDefault).isEmpty,
                     "a removed tool leaves no row behind")
    }

    static func builtinTools(_ suite: TestSuite) {
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)

        for feature in AppFeature.allCases {
            suite.expect(registry.tool(ToolID(feature.rawValue)!)?.feature == feature,
                         "\(feature.rawValue) is registered as a tool under its own id")
        }
        for feature in AppFeature.allCases {
            suite.expect(registry.name(for: ToolID(feature.rawValue)!, language: .systemDefault)
                             == feature.hubTitle(Strings.localized(.systemDefault), hub: FeatureStrings.hub(.systemDefault)),
                         "\(feature.rawValue) is named as the hub names it, not by its raw id")
        }
        for command in BuiltinCommand.allCases {
            suite.expect(registry.command(command.id) != nil && registry.hasHandler(for: command.id),
                         "\(command.rawValue) has a descriptor and a handler")
            suite.expect(registry.title(for: command.id, language: .systemDefault)?.isEmpty == false,
                         "\(command.rawValue) has a title")
        }
        suite.expect(Set(registry.commands(on: .radial).map(\.id)) == Set(BuiltinCommand.allCases.map(\.id)),
                     "every built-in command can sit on a wheel")
        suite.expect(registry.commands(on: .commandBar).isEmpty,
                     "built-in commands leave the bar to its hand-built rows")

        // Installing again must not disturb what is there.
        BuiltinTools.install(into: registry)
        suite.expect(registry.commands(on: .radial).count == BuiltinCommand.allCases.count,
                     "installing twice registers nothing twice")
    }

    static func registry(_ suite: TestSuite) {
        let world = World()
        let registry = world.registry
        let capture = CommandID("screenshot/capture")!
        let open = CommandID("com.acme.deploys/open")!
        do {
            try world.add("screenshot", "capture", surfaces: [.radial, .quickPanel])
            try world.add("com.acme.deploys", "open", surfaces: [.radial, .commandBar])
            try world.add("shelf", "summon", surfaces: [.radial], runnable: false)
        } catch {
            suite.expect(false, "registering three distinct tools succeeds, got \(error)")
        }

        suite.expect(registry.commands(on: .radial).map(\.id.rawValue)
                         == ["screenshot/capture", "com.acme.deploys/open", "shelf/summon"],
                     "a surface lists its commands in registration order")
        suite.expect(registry.commands(on: .commandBar).map(\.id) == [open],
                     "a command is listed only where its tool asked for it")
        suite.expect(registry.commands(on: .quickPanel).map(\.id) == [capture],
                     "a command is listed only where its tool asked for it")

        suite.expect(registry.run(capture) && registry.run(open) && world.ran == [capture.rawValue, open.rawValue],
                     "running a command calls its handler once")

        suite.expect(registry.title(for: capture, language: .systemDefault) == "first capture",
                     "a title comes from the handler")
        world.language = "second"
        suite.expect(registry.title(for: capture, language: .systemDefault) == "second capture",
                     "a title follows the language of the moment it is read")

        let summon = CommandID("shelf/summon")!
        world.ran = []
        suite.expect(!registry.canRun(summon) && !registry.run(summon) && world.ran.isEmpty,
                     "a command its handler calls not runnable does not run")

        world.off = [.screenshot]
        suite.expect(!registry.commands(on: .radial).contains { $0.id == capture }
                         && !registry.canRun(capture) && !registry.run(capture) && world.ran.isEmpty,
                     "a command of a switched-off tool neither lists nor runs")
        suite.expect(registry.canRun(open), "an outside tool is not tied to a hub feature")
        world.off = []

        var refused: ToolRegistry.RegistrationError?
        do { try world.add("screenshot", "capture", surfaces: [.radial]) } catch {
            refused = error as? ToolRegistry.RegistrationError
        }
        suite.expect(refused == .duplicateTool(ToolID("screenshot")!), "a tool registers once")
        suite.expect(registry.run(capture) && world.ran == [capture.rawValue],
                     "the first registration keeps working after a refused second one")

        let missing = CommandID("screenshot/missing")!
        var unknown: ToolRegistry.RegistrationError?
        do { try registry.setHandler(.init(title: { _ in "" }, run: {}), for: missing) } catch {
            unknown = error as? ToolRegistry.RegistrationError
        }
        suite.expect(unknown == .unknownCommand(missing), "a handler needs a declared command")
        suite.expect(!registry.run(missing) && !registry.canRun(missing) && registry.title(for: missing, language: .systemDefault) == nil,
                     "an id nothing declared neither runs nor has a title")

        let deploys = open.tool
        suite.expect(registry.name(for: deploys, language: .systemDefault) == "com.acme.deploys",
                     "a tool with no name provider is named by its descriptor")
        suite.expect(registry.name(for: ToolID("com.acme.nothing")!, language: .systemDefault) == nil,
                     "a tool nothing registered has no name")
        let revisionBeforeName = registry.revision
        do { try registry.setName({ [unowned world] _ in "\(world.language) deploys" }, for: deploys) } catch {
            suite.expect(false, "naming a registered tool succeeds, got \(error)")
        }
        suite.expect(registry.name(for: deploys, language: .systemDefault) == "second deploys",
                     "a tool's name comes from its provider")
        world.language = "third"
        suite.expect(registry.name(for: deploys, language: .systemDefault) == "third deploys",
                     "a tool's name follows the language of the moment it is read")
        suite.expect(registry.revision > revisionBeforeName, "naming a tool is a change surfaces can see")
        world.language = "second"
        var unnamed: ToolRegistry.RegistrationError?
        do { try registry.setName({ _ in "ghost" }, for: ToolID("com.acme.ghost")!) } catch {
            unnamed = error as? ToolRegistry.RegistrationError
        }
        suite.expect(unnamed == .unknownTool(ToolID("com.acme.ghost")!), "a name needs a registered tool")

        let before = registry.revision
        registry.unregister(ToolID("com.acme.deploys")!)
        suite.expect(registry.tool(open.tool) == nil && registry.command(open) == nil && !registry.run(open)
                         && registry.commands(on: .commandBar).isEmpty && registry.revision > before
                         && !registry.hasHandler(for: open),
                     "an unregistered tool takes its commands and handlers with it")

        let reborn = ToolDescriptor(id: open.tool, name: "com.acme.deploys", symbol: "star", commands: [
            CommandDescriptor(id: open, title: "plain open", symbol: "star", surfaces: [.radial, .commandBar])!,
        ])!
        do { try registry.register(reborn) } catch { suite.expect(false, "a removed tool can register again, got \(error)") }
        suite.expect(!registry.hasHandler(for: open) && registry.commands(on: .commandBar).isEmpty && !registry.run(open),
                     "a tool registered again does not inherit the handlers of the one removed")
        suite.expect(registry.name(for: open.tool, language: .systemDefault) == "com.acme.deploys",
                     "a tool registered again does not inherit the name provider of the one removed")
    }

    static func radial(_ suite: TestSuite) {
        let item = RadialMenuItem(kind: .command, name: "Deploys", payload: "com.acme.deploys/open")
        suite.expect(item.commandID == CommandID("com.acme.deploys/open"), "a command slice reads its command id")
        suite.expect(RadialMenuItem(kind: .tool, payload: "com.acme.deploys/open").commandID == nil,
                     "only a command slice has a command id")
        suite.expect(RadialMenuSupport.isValidPayload(item), "a well-formed command id is a valid target")
        for bad in ["", "noslash", "a/b/c"] {
            suite.expect(!RadialMenuSupport.isValidPayload(RadialMenuItem(kind: .command, payload: bad)),
                         "\(bad.debugDescription) is not a valid command target")
        }
        suite.expect(!item.effectiveSymbolName.isEmpty, "a command slice has a symbol to draw")

        let saved = [item, RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)]
        let data = try? JSONEncoder().encode(saved)
        let loaded = data.flatMap { try? JSONDecoder().decode([RadialMenuItem].self, from: $0) }
        suite.expect(loaded == saved, "a wheel with a command slice saves and loads unchanged")
    }

    static func wheel(_ suite: TestSuite) {
        let world = World()
        do {
            try world.add("com.acme.deploys", "open", surfaces: [.radial])
            try world.add("com.acme.paused", "wake", surfaces: [.radial], runnable: false)
        } catch {
            suite.expect(false, "registering two distinct tools succeeds, got \(error)")
        }
        let open = RadialMenuItem(kind: .command, payload: "com.acme.deploys/open")
        let paused = RadialMenuItem(kind: .command, payload: "com.acme.paused/wake")
        let gone = RadialMenuItem(kind: .command, payload: "com.acme.gone/open")
        let app = RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")
        let screenshot = RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)
        let folder = RadialMenuItem(kind: .submenu, children: [gone, open])
        let emptyFolder = RadialMenuItem(kind: .submenu, children: [gone, paused])

        func shown(_ items: [RadialMenuItem], toolsRun: Bool = true) -> [RadialMenuItem] {
            RadialMenuService.availableItems(items, registry: world.registry,
                                             isFeatureAvailable: { _ in true },
                                             toolIsRunnable: { _ in toolsRun })
        }
        suite.expect(shown([open, paused, gone, app]) == [open, app],
                     "the wheel shows a command slice only while its command can run")
        suite.expect(shown([screenshot]) == [screenshot] && shown([screenshot], toolsRun: false).isEmpty,
                     "a built-in tool slice follows its own rule, as before")
        let kept = shown([folder, emptyFolder])
        suite.expect(kept.count == 1 && kept.first?.children == [open],
                     "a folder keeps the slices that can run, and goes when none can")

        // A command slice draws its command's own symbol unless the person chose one.
        suite.expect(open.resolvedSymbolName(registry: world.registry) == "star",
                     "a command slice draws its command's symbol")
        var chosen = open
        chosen.symbolName = "bolt"
        suite.expect(chosen.resolvedSymbolName(registry: world.registry) == "bolt",
                     "a symbol the person chose wins")
        suite.expect(gone.resolvedSymbolName(registry: world.registry) == gone.defaultSymbolName
                         && app.resolvedSymbolName(registry: world.registry) == app.effectiveSymbolName,
                     "a slice with no command to ask draws what it drew before")

        // The editor's Tool picker: the app's tools, then commands no tool slice runs.
        let choices = RadialToolChoice.all(tools: [.screenshot, .keepAwake], registry: world.registry, keeping: gone)
        suite.expect(choices.map(\.tag) == ["tool:screenshot", "tool:keepAwake", "command:com.acme.deploys/open",
                                            "command:com.acme.gone/open"],
                     "the Tool picker lists the app's tools, then runnable commands, then the slice's own missing one")
        suite.expect(RadialToolChoice.all(tools: [.screenshot], registry: ToolRegistry(isAvailable: { _ in true }),
                                          keeping: screenshot).map(\.tag) == ["tool:screenshot"],
                     "with no command on offer, the Tool picker lists exactly the app's tools")
        var edited = RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue)
        RadialToolChoice.apply("command:com.acme.deploys/open", to: &edited)
        suite.expect(edited.kind == .command && edited.payload == "com.acme.deploys/open",
                     "choosing a command makes the slice a command slice")
        RadialToolChoice.apply("tool:keepAwake", to: &edited)
        suite.expect(edited.kind == .tool && edited.payload == "keepAwake", "choosing a tool makes it a tool slice again")
        suite.expect(RadialToolChoice.tag(of: open) == "command:com.acme.deploys/open"
                         && RadialToolChoice.tag(of: screenshot) == "tool:screenshot",
                     "a slice knows which choice it is")

        // A slice saved before the picker listed commands passes through it untouched,
        // whether it is a built-in tool, a command that runs, or one that is not registered.
        let named = RadialMenuItem(kind: .tool, name: "Shot", symbolName: "bolt", payload: RadialMenuTool.screenshot.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // the default key order is not stable between two encodes
        for saved in [named, screenshot, open, paused, gone] {
            var through = saved
            if let tag = RadialToolChoice.tag(of: saved) { RadialToolChoice.apply(tag, to: &through) }
            let savedJSON = try? encoder.encode([saved])
            suite.expect(savedJSON != nil && through == saved && (try? encoder.encode([through])) == savedJSON,
                         "a \(saved.kind.rawValue) slice read as a choice and applied again saves as the same JSON")
            let offered = RadialToolChoice.all(tools: [.screenshot], registry: world.registry, keeping: saved)
            suite.expect(RadialToolChoice.tag(of: saved).map { tag in offered.contains { $0.tag == tag } } == true,
                         "the Tool picker always has the choice the slice already is")
        }
        let keepAwake = RadialMenuItem(kind: .tool, payload: RadialMenuTool.keepAwake.rawValue)
        let language = L10n.shared.language
        suite.expect(RadialToolChoice.all(tools: [.screenshot], registry: world.registry, keeping: keepAwake).last?.title
                         == RadialMenuTool.keepAwake.feature.hubTitle(Strings.localized(language),
                                                                      hub: FeatureStrings.hub(language)),
                     "a built-in tool that is switched off is still listed under its own name")
        suite.expect(shown([gone]).isEmpty && RadialMenuSupport.isValidPayload(gone),
                     "a slice whose command is not registered stays valid and is only left off the wheel")
    }

    static func quickPanel(_ suite: TestSuite) {
        let expected: [QuickLauncherItem: BuiltinCommand] = [
            .keepAwake: .keepAwakeToggle, .micMute: .micMuteToggle, .screenOCR: .screenOCRCapture,
            .screenshot: .screenshotCapture, .screenRecorder: .screenRecorderToggle,
            .colorPicker: .colorPickerPick, .cameraPreview: .cameraPreviewShow,
            .scratchpad: .scratchpadShow, .clipboard: .clipboardHistoryShow, .cleaning: .cleaningModeActivate,
        ]
        for item in QuickLauncherItem.allCases {
            suite.expect(item.command == expected[item], "\(item.rawValue) runs the command it always ran")
            if let command = item.command {
                suite.expect(command.feature == item.feature, "\(item.rawValue)'s command belongs to its feature")
            }
        }
        let hosted: Set<QuickLauncherItem> = [.windowLayout, .homebrew, .media, .urlCleaner, .uninstaller,
                                              .cleaner, .toggles]
        suite.expect(Set(QuickLauncherItem.allCases.filter { $0.command == nil }) == hosted,
                     "only the utilities the panel hosts itself have no command")
    }

    static func housekeeping(_ suite: TestSuite) {
        // Ids and descriptors refuse what would mislead later.
        suite.expect(ToolID("com..acme") == nil, "an id cannot hold two dots in a row")
        suite.expect(CommandID("screenshot/a..b") == nil, "a command name cannot hold two dots in a row")
        let tool = ToolID("com.acme.deploys")!
        let open = CommandID(tool: tool, name: "open")!
        suite.expect(CommandDescriptor(id: open, title: " ", symbol: "star", surfaces: [.radial]) == nil
                         && CommandDescriptor(id: open, title: "Open", symbol: "", surfaces: [.radial]) == nil,
                     "a command needs a title and a symbol")
        suite.expect(ToolDescriptor(id: tool, name: "", symbol: "star", commands: []) == nil
                         && ToolDescriptor(id: tool, name: "Deploys", symbol: " ", commands: []) == nil,
                     "a tool needs a name and a symbol")
        suite.expect(ToolDescriptor(id: ToolID("notAFeature")!, name: "X", symbol: "star", commands: []) == nil,
                     "an id with no dot must name one of the app's own features")
        suite.expect(ToolDescriptor(id: ToolID("screenshot")!, name: "X", symbol: "star", commands: []) != nil,
                     "an id that names a feature is one of the app's own tools")

        // A change of hub availability is something a surface can see.
        let world = World()
        let before = world.registry.revision
        world.registry.noteAvailabilityChanged()
        suite.expect(world.registry.revision == before + 1, "a hub change is a change surfaces can see")

        // A surface offers a registry command only when its own fixed list does not.
        do {
            try world.add("screenshot", "capture", surfaces: [.radial, .quickPanel, .commandBar])
            try world.add("com.acme.deploys", "open", surfaces: [.radial, .quickPanel, .commandBar])
        } catch {
            suite.expect(false, "registering two distinct tools succeeds, got \(error)")
        }
        suite.expect(world.registry.extraCommands(on: .radial).map(\.id.rawValue) == ["com.acme.deploys/open"],
                     "the wheel is offered only what no built-in tool slice runs")
        suite.expect(world.registry.extraCommands(on: .quickPanel).map(\.id.rawValue) == ["com.acme.deploys/open"],
                     "the panel is offered only what no built-in tile runs")
        suite.expect(world.registry.extraCommands(on: .commandBar).count == 2,
                     "the bar has no fixed list of commands to hold back")

        // The app's own tools, as a release build registers them.
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        let tiles = Set(QuickLauncherItem.allCases.compactMap { $0.command?.id })
        suite.expect(Set(shipped.commands(on: .quickPanel).map(\.id)) == tiles,
                     "a built-in command asks for the panel only when a tile runs it")
        suite.expect(shipped.extraCommands(on: .quickPanel).isEmpty && shipped.extraCommands(on: .radial).isEmpty,
                     "with only the app's own tools, no surface gains an entry")
    }

    static func sampleTool(_ suite: TestSuite) {
        let registry = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: registry)
        suite.expect(registry.tool(SampleTool.id) == nil,
                     "the app's own tools do not include the sample")

        var said: [String] = []
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(registry.extraCommands(on: .quickPanel).map(\.id) == [SampleTool.hello]
                         && registry.extraCommands(on: .radial).map(\.id) == [SampleTool.hello]
                         && registry.commands(on: .commandBar).map(\.id) == [SampleTool.hello],
                     "the sample is the one tool outside every fixed list, on all three surfaces")
        suite.expect(registry.run(SampleTool.hello) && said.count == 1 && !said[0].isEmpty,
                     "running the sample says something once")
        suite.expect(registry.name(for: SampleTool.id, language: .systemDefault)?.isEmpty == false
                         && registry.title(for: SampleTool.hello, language: .systemDefault)?.isEmpty == false,
                     "the sample has a name and a title to show")

        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(registry.commands(on: .commandBar).count == 1, "installing the sample twice registers it once")
    }

    static func shortcutSurface(_ suite: TestSuite) {
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        suite.expect(shipped.commands(on: .shortcut).isEmpty,
                     "the app's own commands keep the shortcuts they have, and ask for no second one")
        SampleTool.install(into: shipped, say: { _ in })
        suite.expect(shipped.commands(on: .shortcut).map(\.id) == [SampleTool.hello]
                         && shipped.extraCommands(on: .shortcut).map(\.id) == [SampleTool.hello],
                     "a tool outside the fixed lists can ask for a shortcut")
    }

    static func tiles(_ suite: TestSuite) {
        // A tile reads and writes one id, whichever kind it is.
        let enumTile = QuickLauncherTile(rawValue: "screenshot")
        let commandTile = QuickLauncherTile(rawValue: "dev.vitruvian.sample/hello")
        suite.expect(enumTile == .builtin(.screenshot) && enumTile?.rawValue == "screenshot"
                         && enumTile?.builtin == .screenshot && enumTile?.commandID == nil,
                     "a built-in tile keeps the id users already have saved")
        suite.expect(commandTile == .command(SampleTool.hello) && commandTile?.rawValue == "dev.vitruvian.sample/hello"
                         && commandTile?.commandID == SampleTool.hello && commandTile?.builtin == nil,
                     "a command tile is known by its command id")
        for bad in ["", "notATile", "a/b/c", "not an id", "screenshot/"] {
            suite.expect(QuickLauncherTile(rawValue: bad) == nil, "\(bad.debugDescription) is not a tile")
        }

        // Showing: the saved order decides; what it does not name goes after, in the order given.
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "b", "x/1"], saved: []) == ["a", "b", "x/1"],
                     "with nothing saved, tiles keep the order they come in")
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "b", "x/1"], saved: ["x/1", "b", "gone/1", "a"])
                         == ["x/1", "b", "a"],
                     "a saved order places every tile it names")
        suite.expect(QuickToolsSupport.tileOrder(live: ["a", "new", "b", "x/1"], saved: ["b", "a"])
                         == ["b", "a", "new", "x/1"],
                     "a tile the saved order does not name goes after those it does")

        // Saving: an id that is not showing now keeps its place.
        let wellFormed: (String) -> Bool = { QuickLauncherTile(rawValue: $0) != nil }
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["screenshot", "keepAwake"],
                                                      previous: ["keepAwake", "dev.vitruvian.sample/hello", "screenshot"],
                                                      isWellFormed: wellFormed)
                         == ["screenshot", "dev.vitruvian.sample/hello", "keepAwake"],
                     "a tile that is not showing now keeps its place in the saved order")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["keepAwake", "screenshot"],
                                                      previous: ["", "a/b/c", "not an id", "keepAwake"],
                                                      isWellFormed: wellFormed)
                         == ["keepAwake", "screenshot"],
                     "a malformed id is dropped from the saved order, and the rest is kept")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: ["keepAwake"],
                                                      previous: ["micMute", "micMute", "keepAwake"],
                                                      isWellFormed: wellFormed)
                         == ["micMute", "keepAwake"],
                     "an id saved twice is kept once")
        suite.expect(QuickToolsSupport.savedTileOrder(afterMoving: [], previous: [], isWellFormed: wellFormed).isEmpty,
                     "nothing showing and nothing saved saves nothing")
    }

    /// Review Focus 2 and 3: one combination, one owner, and what is saved
    /// holds whether or not its command is registered now.
    static func shortcutConflicts(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let free = GlobalShortcut(keyCode: 0, modifiers: [.control])
        let rows = ["app.bundle.mail": optionB]
        let commands = ["dev.vitruvian.sample/hello": optionN, "com.acme.gone/open": free]
        func holder(_ shortcut: GlobalShortcut, row: String? = nil, command: CommandID? = nil) -> ShortcutConflicts.Holder? {
            ShortcutConflicts.holder(of: shortcut, rows: rows, commands: commands,
                                     excludingRow: row, excludingCommand: command)
        }
        suite.expect(holder(optionB) == .commandBarRow("app.bundle.mail"),
                     "a combination a Command Bar row holds is taken")
        suite.expect(holder(optionN) == .toolCommand("dev.vitruvian.sample/hello"),
                     "a combination a tool command holds is taken")
        suite.expect(holder(free) == .toolCommand("com.acme.gone/open"),
                     "a command that is not registered now still holds its combination")
        suite.expect(holder(optionB, row: "app.bundle.mail") == nil
                         && holder(optionN, command: SampleTool.hello) == nil,
                     "a row or a command does not clash with itself")
        suite.expect(holder(optionB, row: "app.bundle.notes") == .commandBarRow("app.bundle.mail")
                         && holder(optionN, command: CommandID("com.acme.gone/open")) == .toolCommand("dev.vitruvian.sample/hello")
                         && holder(optionB, command: SampleTool.hello) == .commandBarRow("app.bundle.mail")
                         && holder(optionN, row: "app.bundle.mail") == .toolCommand("dev.vitruvian.sample/hello"),
                     "leaving one row or command out frees no other holder's combination")
        suite.expect(holder(GlobalShortcut(keyCode: 1, modifiers: [.command])) == nil,
                     "a combination nothing holds is free")
        suite.expect(ShortcutConflicts.holder(of: optionB, rows: [:], commands: ["not an id": optionB, " ": optionN],
                                              excludingRow: nil, excludingCommand: nil) == .toolCommand("not an id")
                         && ShortcutConflicts.holder(of: optionN, rows: [:], commands: [" ": optionN],
                                                     excludingRow: nil, excludingCommand: nil) == nil,
                     "a saved id no command can have still holds its combination; an entry with no id holds nothing")

        // The name a refusal shows. It is never empty, whoever the holder is.
        func name(_ holder: ShortcutConflicts.Holder) -> String {
            ShortcutConflicts.name(of: holder,
                                   rowTitle: { $0 == "app.bundle.mail" ? "Mail" : nil },
                                   rowFallback: "Rows with their own shortcut",
                                   commandTitle: { $0 == SampleTool.hello ? "Say hello" : nil })
        }
        suite.expect(name(.commandBarRow("app.bundle.mail")) == "Mail"
                         && name(.toolCommand("dev.vitruvian.sample/hello")) == "Say hello",
                     "a holder the app can name is named as its own row names it")
        suite.expect(name(.commandBarRow("app.bundle.gone")) == "Rows with their own shortcut"
                         && name(.toolCommand("com.acme.gone/open")) == "com.acme.gone/open"
                         && name(.toolCommand("not an id")) == "not an id",
                     "a holder the app cannot name now is still named: a row by the list it is in, a command by its id")
    }

    static func shortcutMap(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let bare = GlobalShortcut(keyCode: 11, modifiers: [])

        var map = ShortcutMap.setting(optionB, for: "a", in: [:], limit: 2)
        suite.expect(map == ["a": optionB] && ShortcutMap.key(for: optionB, in: map) == "a",
                     "a key gets its shortcut, and the shortcut finds its key")
        suite.expect(ShortcutMap.decode(ShortcutMap.encode(map)) == map, "a map reads back what it wrote")
        suite.expect(ShortcutMap.decode(nil).isEmpty && ShortcutMap.decode("not json").isEmpty
                         && ShortcutMap.decode(#"{"a":"nonsense"}"#).isEmpty,
                     "what cannot be read is no shortcut, and nothing crashes")

        map = ShortcutMap.setting(optionB, for: "b", in: map, limit: 2)
        suite.expect(map == ["b": optionB], "a combination given to another key moves to it")
        map = ShortcutMap.setting(optionN, for: "a", in: map, limit: 2)
        suite.expect(ShortcutMap.setting(GlobalShortcut(keyCode: 0, modifiers: [.control]), for: "c", in: map, limit: 2) == map
                         && !ShortcutMap.hasRoom(for: "c", in: map, limit: 2)
                         && ShortcutMap.hasRoom(for: "a", in: map, limit: 2),
                     "a full map takes no new key, and an existing key can still change")
        suite.expect(ShortcutMap.setting(nil, for: "a", in: map, limit: 2) == ["b": optionB],
                     "clearing a key removes it")

        suite.expect(ShortcutMap.assignmentIssue(bare, for: "a", in: map, limit: 2) == .invalid,
                     "a bare key is refused: it would take that key from every app")
        suite.expect(ShortcutMap.assignmentIssue(optionB, for: "a", in: map, limit: 2) == .occupied("b"),
                     "a combination another key holds is refused, and names its holder")
        suite.expect(ShortcutMap.assignmentIssue(GlobalShortcut(keyCode: 0, modifiers: [.control]), for: "c", in: map, limit: 2) == .full,
                     "a full map says so")
        suite.expect(ShortcutMap.assignmentIssue(optionN, for: "a", in: map, limit: 2) == nil,
                     "a key may keep the combination it has")
    }

    static func commandShortcutStore(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let hello = SampleTool.hello
        let raw = ToolCommandShortcuts.encode([hello.rawValue: optionB, "com.acme.gone/open": optionN, "not an id": optionB])
        let map = ToolCommandShortcuts.decode(raw)
        suite.expect(map.count == 3, "ids that name nothing now, or are not ids at all, are carried, not dropped")
        suite.expect(ToolCommandShortcuts.shortcut(for: hello, in: map) == optionB,
                     "a command finds its shortcut")
        suite.expect(ToolCommandShortcuts.holder(of: optionN, in: map, excluding: nil) == "com.acme.gone/open",
                     "a command that is not registered still holds its combination")
        suite.expect(ToolCommandShortcuts.holder(of: optionN, in: map, excluding: CommandID("com.acme.gone/open")) == nil,
                     "a command does not clash with itself")
        suite.expect(ToolCommandShortcuts.takeOverKey(for: hello) == "toolCommandShortcuts.dev.vitruvian.sample/hello",
                     "a command's take-over is kept under the name its hotkey is claimed with")
        suite.expect(Preferences.toolCommandShortcuts.defaultValue.isEmpty && ToolCommandShortcuts.limit == CommandBarRowShortcuts.limit,
                     "no command starts with a shortcut, and the list has the command bar's limit")

        // The preference itself: registered, backed up, and reading never rewrites it.
        suite.expect(Defaults.registeredDefaults[DefaultsKey.toolCommandShortcuts] as? String == "",
                     "the preference is registered with no shortcuts")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.toolCommandShortcuts),
                     "tool command shortcuts travel with a settings backup")

        let domain = "com.vitruviansoftware.vitruvian.tests.toolCommandShortcuts"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults[Preferences.toolCommandShortcuts] = raw ?? ""
        let before = defaults.string(forKey: DefaultsKey.toolCommandShortcuts)
        let read = ToolCommandShortcuts.decode(defaults[Preferences.toolCommandShortcuts])
        _ = ToolCommandShortcuts.shortcut(for: hello, in: read)
        _ = ToolCommandShortcuts.holder(of: optionB, in: read, excluding: hello)
        suite.expect(read.count == 3 && before != nil
                         && defaults.string(forKey: DefaultsKey.toolCommandShortcuts) == before,
                     "reading saved shortcuts, malformed and unregistered ids included, leaves the saved text byte for byte as it was")
        for stored in ["not json", #"{"com.acme.gone/open":"nonsense"}"#, "[]"] {
            defaults[Preferences.toolCommandShortcuts] = stored
            let empty = ToolCommandShortcuts.decode(defaults[Preferences.toolCommandShortcuts])
            suite.expect(empty.isEmpty && defaults.string(forKey: DefaultsKey.toolCommandShortcuts) == stored,
                         "unreadable saved text reads as no shortcuts, does not crash, and is not deleted: \(stored)")
        }
    }

    // MARK: - The registrar

    /// A hotkey that registers nothing, and records what it was asked. It
    /// behaves as `QuickToolHotkey` does: asked again for the combination it
    /// holds, it does nothing. Not main-actor isolated, like the protocol it
    /// stands in for; the registrar only ever touches it on the main thread.
    nonisolated final class FakeHotkey: ToolHotkey {
        let id: UInt32
        var onPress: (() -> Void)?
        var registered: (shortcut: GlobalShortcut, storageKey: String)?
        /// How many times it took a key from the system.
        var registrations = 0
        /// Whether macOS would give the key now.
        private let accepts: () -> Bool
        init(id: UInt32, accepts: @escaping () -> Bool) {
            self.id = id
            self.accepts = accepts
        }

        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            guard enabled else {
                unregister()
                return true
            }
            if registered?.shortcut == shortcut { return true }
            unregister()
            guard accepts() else { return false }
            registered = (shortcut, storageKey)
            registrations += 1
            return true
        }

        func unregister() { registered = nil }
    }

    /// A registrar over doubles: its own registry, a dictionary for what is
    /// saved, and hotkeys that register nothing.
    final class RegistrarBench {
        let registry: ToolRegistry
        var saved: [String: GlobalShortcut] = [:]
        var saves = 0
        var made: [FakeHotkey] = []
        var beeps = 0
        var refusing = false
        var recording = false
        var takeOvers: [String] = []
        private(set) var registrar: ToolShortcutRegistrar!

        init(registry: ToolRegistry = ToolRegistry(isAvailable: { _ in true })) {
            self.registry = registry
            registrar = ToolShortcutRegistrar(environment: .init(
                registry: registry,
                shortcuts: { [unowned self] in self.saved },
                save: { [unowned self] in
                    self.saved = $0
                    self.saves += 1
                },
                makeHotkey: { [unowned self] id in
                    let hotkey = FakeHotkey(id: id, accepts: { [unowned self] in !self.refusing })
                    self.made.append(hotkey)
                    return hotkey
                },
                isRecording: { [unowned self] in self.recording },
                refuse: { [unowned self] in self.beeps += 1 },
                setTakeOver: { [unowned self] key, on in self.takeOvers.append("\(key)=\(on)") }))
        }

        var live: [FakeHotkey] { made.filter { $0.registered != nil } }

        /// What `ShortcutCapture.begin` does to every quick tool key.
        func releaseEveryKey() { for hotkey in made { hotkey.unregister() } }
    }

    static func shortcutRegistrar(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let optionM = GlobalShortcut(keyCode: 46, modifiers: [.option])
        let optionK = GlobalShortcut(keyCode: 40, modifiers: [.option])
        let bench = RegistrarBench()
        let registry = bench.registry
        let registrar = bench.registrar!
        var said: [String] = []
        let hello = SampleTool.hello

        // Saved before its tool registers: nothing is held. No command asks
        // for a shortcut yet, so this is the registrar's early return only;
        // `shortcutRegistrarUnregisteredCommand` has the case with one asking.
        bench.saved = [hello.rawValue: optionB, "com.acme.gone/open": optionN, "not an id": optionK]
        registrar.sync()
        suite.expect(bench.live.isEmpty && bench.made.isEmpty,
                     "with no command asking for a shortcut, nothing that is saved holds a key")

        // The tool registers: the registrar hears it and takes the key.
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionB
                         && bench.live[0].registered?.storageKey == ToolCommandShortcuts.takeOverKey(for: hello)
                         && bench.live[0].id >= ToolShortcutRegistrar.firstHotkeyID,
                     "a tool that registers gets the key its command was given, without being told to sync")
        suite.expect(bench.saved.count == 3 && bench.saves == 0, "syncing drops nothing from what is saved")

        bench.live[0].onPress?()
        suite.expect(said.count == 1 && bench.beeps == 0, "pressing the key runs the command once")

        // Unregistering the tool releases the key and keeps what is saved.
        registry.unregister(SampleTool.id)
        suite.expect(bench.live.isEmpty && bench.saved[hello.rawValue] == optionB && bench.saves == 0,
                     "a tool that leaves gives its key back and keeps its shortcut for its return")
        SampleTool.install(into: registry, say: { said.append($0) })
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionB,
                     "a tool that returns gets its key back")

        // Assigning and clearing.
        suite.expect(registrar.assign(optionM, to: hello) == nil
                         && bench.saved[hello.rawValue] == optionM && bench.saved["com.acme.gone/open"] == optionN
                         && bench.saved["not an id"] == optionK
                         && bench.live.count == 1 && bench.live[0].registered?.shortcut == optionM,
                     "a free combination given to a command is saved, its key follows, and no other entry is touched")
        suite.expect(bench.takeOvers.isEmpty, "giving a shortcut leaves the take-over choice alone")
        registrar.assign(nil, to: hello)
        suite.expect(bench.saved[hello.rawValue] == nil && bench.live.isEmpty && bench.saved["not an id"] == optionK,
                     "clearing a shortcut releases its key")
        suite.expect(bench.takeOvers == ["\(ToolCommandShortcuts.takeOverKey(for: hello))=false"],
                     "clearing a shortcut gives a macOS shortcut it took over back")

        // Another app holds the combination.
        bench.refusing = true
        registrar.assign(optionB, to: hello)
        suite.expect(registrar.refused == [hello] && bench.saved[hello.rawValue] == optionB && bench.live.isEmpty,
                     "a combination macOS refuses is reported, and stays saved")
        registrar.sync()
        suite.expect(registrar.refused == [hello] && bench.saved[hello.rawValue] == optionB,
                     "a refusal stands for as long as macOS keeps refusing")
        bench.refusing = false
        registrar.sync()
        suite.expect(registrar.refused.isEmpty && bench.live.count == 1, "a refusal clears when the key can be taken")
        bench.refusing = true
        registrar.assign(optionM, to: hello)
        suite.expect(registrar.refused == [hello], "a refusal is reported for a changed combination too")
        registrar.assign(nil, to: hello)
        suite.expect(registrar.refused.isEmpty, "a cleared shortcut is not reported as refused")
        bench.refusing = false
        registrar.assign(optionB, to: hello)

        // A command that cannot run just now says no.
        var runnable = false
        var ran = 0
        let deploys = ToolID("com.acme.deploys")!
        let open = CommandID(tool: deploys, name: "open")!
        try? registry.register(ToolDescriptor(id: deploys, name: "Deploys", symbol: "shippingbox", commands: [
            CommandDescriptor(id: open, title: "Open", symbol: "shippingbox", surfaces: [.shortcut])!,
        ])!)
        try? registry.setHandler(.init(title: { _ in "Open" }, isRunnable: { runnable }, run: { ran += 1 }), for: open)
        // Its saved entry is not here to use it, and still blocks the combination.
        let savedBefore = bench.saved
        let savesBefore = bench.saves
        let takeOversBefore = bench.takeOvers
        suite.expect(registrar.assign(optionN, to: open) == .occupied("com.acme.gone/open")
                         && bench.saved == savedBefore && bench.saves == savesBefore
                         && bench.takeOvers == takeOversBefore
                         && bench.saved[open.rawValue] == nil
                         && !bench.live.contains { $0.registered?.shortcut == optionN },
                     "a combination another command has saved is refused, even if that command is not here, and nothing changes")
        bench.saved["com.acme.gone/open"] = nil
        registrar.assign(optionN, to: open)
        let openKey = bench.live.first { $0.registered?.shortcut == optionN }
        openKey?.onPress?()
        suite.expect(openKey != nil && ran == 0 && bench.beeps == 1,
                     "a key whose command cannot run just now says no, and runs nothing")
        runnable = true
        openKey?.onPress?()
        suite.expect(ran == 1 && bench.beeps == 1, "and runs it once it can")

        // A command that stops asking for a shortcut, while another still
        // asks and holds its key: the registrar reads what is saved, and
        // must pass this one over.
        registry.unregister(SampleTool.id)
        let quiet = ToolDescriptor(id: SampleTool.id, name: "Sample tool", symbol: "hand.wave", commands: [
            CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave", surfaces: [.radial])!,
        ])!
        try? registry.register(quiet)
        try? registry.setHandler(.init(title: { _ in "Say hello" }, run: {}), for: hello)
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionN
                         && bench.saved[open.rawValue] == optionN,
                     "a command that still asks for a shortcut keeps its key when another stops asking")
        suite.expect(!bench.live.contains { $0.registered?.shortcut == optionB }
                         && bench.saved[hello.rawValue] == optionB,
                     "a command that no longer asks for a shortcut holds no key")
    }

    /// A saved shortcut holds a key only if its command is registered and
    /// asks for one. One command asks here, so the registrar does read what
    /// is saved and has to pass over the entries that are nobody's.
    static func shortcutRegistrarUnregisteredCommand(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let optionK = GlobalShortcut(keyCode: 40, modifiers: [.option])
        let bench = RegistrarBench()
        let deploys = ToolID("com.acme.deploys")!
        let open = CommandID(tool: deploys, name: "open")!
        try? bench.registry.register(ToolDescriptor(id: deploys, name: "Deploys", symbol: "shippingbox", commands: [
            CommandDescriptor(id: open, title: "Open", symbol: "shippingbox", surfaces: [.shortcut])!,
        ])!)
        try? bench.registry.setHandler(.init(title: { _ in "Open" }, run: {}), for: open)
        // The sample tool is not registered in this registry.
        bench.saved = [open.rawValue: optionN, SampleTool.hello.rawValue: optionB, "not an id": optionK]
        bench.registrar.sync()
        suite.expect(bench.live.contains { $0.registered?.shortcut == optionN
            && $0.registered?.storageKey == ToolCommandShortcuts.takeOverKey(for: open) },
                     "a registered command that asks for a shortcut holds the key it was given")
        suite.expect(bench.live.count == 1 && bench.made.count == 1
                         && !bench.live.contains { $0.registered?.shortcut == optionB || $0.registered?.shortcut == optionK },
                     "a shortcut whose command is not registered holds no key")
        suite.expect(bench.saved.count == 3 && bench.saves == 0, "and it stays saved for when its command registers")
    }

    /// `assign` never moves a combination from one command to another, and
    /// says why it refused.
    static func shortcutRegistrarRefusals(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionM = GlobalShortcut(keyCode: 46, modifiers: [.option])
        let bench = RegistrarBench()
        let hello = SampleTool.hello
        SampleTool.install(into: bench.registry, say: { _ in })

        // Full: every place is held by a command that is not here.
        for index in 0 ..< ToolCommandShortcuts.limit {
            bench.saved["com.acme.full/c\(index)"] = GlobalShortcut(keyCode: Int64(100 + index), modifiers: [.option])
        }
        let full = bench.saved
        suite.expect(bench.registrar.assign(optionB, to: hello) == .full
                         && bench.saved == full && bench.saves == 0 && bench.made.isEmpty && bench.takeOvers.isEmpty,
                     "a 65th command is told the list is full, and nothing is saved or taken")

        // A command that already has a place may change its shortcut on a full list.
        bench.saved["com.acme.full/c0"] = nil
        bench.saved[hello.rawValue] = optionM
        suite.expect(bench.registrar.assign(optionB, to: hello) == nil
                         && bench.saved[hello.rawValue] == optionB && bench.saved.count == ToolCommandShortcuts.limit
                         && bench.live.count == 1 && bench.live[0].registered?.shortcut == optionB,
                     "a command that already has a shortcut can change it when the list is full")

        // Its own combination again: allowed, and the key it holds is left alone.
        let key = bench.live.first
        let made = bench.made.count
        suite.expect(bench.registrar.assign(optionB, to: hello) == nil
                         && bench.live.count == 1 && bench.live.first === key
                         && key?.registrations == 1 && bench.made.count == made,
                     "giving a command the combination it already has changes nothing and takes no key twice")

        // No modifier.
        let before = bench.saved
        let saves = bench.saves
        suite.expect(bench.registrar.assign(GlobalShortcut(keyCode: 11, modifiers: []), to: hello) == .invalid
                         && bench.saved == before && bench.saves == saves && key?.registered?.shortcut == optionB,
                     "a combination with no modifier is refused, and the command keeps what it had")

        // Clearing always works, even on a full list.
        suite.expect(bench.registrar.assign(nil, to: hello) == nil && bench.saved[hello.rawValue] == nil
                         && bench.live.isEmpty,
                     "clearing a shortcut succeeds")
    }

    /// A sync that changes nothing must not let go of a key: taking it again
    /// can fail if another app grabs it in between.
    static func shortcutRegistrarKeepsItsKeys(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let bench = RegistrarBench()
        let hello = SampleTool.hello
        bench.saved = [hello.rawValue: optionB]
        SampleTool.install(into: bench.registry, say: { _ in })
        let first = bench.live.first
        let made = bench.made.count
        bench.registrar.sync()
        bench.registry.noteAvailabilityChanged()
        bench.registrar.sync()
        suite.expect(first != nil && bench.made.count == made && first?.registrations == 1
                         && bench.live.count == 1 && bench.live.first === first,
                     "a sync that changes nothing neither lets go of a key nor takes it again")

        // Another command arriving leaves the first one's key and id alone.
        let deploys = ToolID("com.acme.deploys")!
        let open = CommandID(tool: deploys, name: "open")!
        bench.saved[open.rawValue] = optionN
        try? bench.registry.register(ToolDescriptor(id: deploys, name: "Deploys", symbol: "shippingbox", commands: [
            CommandDescriptor(id: open, title: "Open", symbol: "shippingbox", surfaces: [.shortcut])!,
        ])!)
        try? bench.registry.setHandler(.init(title: { _ in "Open" }, run: {}), for: open)
        suite.expect(bench.live.count == 2 && first?.registrations == 1 && first?.registered?.shortcut == optionB
                         && Set(bench.live.map(\.id)).count == 2,
                     "a second command gets a key and an id of its own, and the first keeps both of its")

        // A changed combination is taken by the same hotkey, under the same id.
        bench.registrar.assign(GlobalShortcut(keyCode: 46, modifiers: [.option]), to: hello)
        suite.expect(first?.registered?.shortcut == GlobalShortcut(keyCode: 46, modifiers: [.option])
                         && first?.registrations == 2 && bench.live.count == 2,
                     "a changed combination is taken under the id the command already had")

        // A bare key is never taken, however it came to be saved.
        bench.saved[hello.rawValue] = GlobalShortcut(keyCode: 11, modifiers: [])
        bench.registrar.sync()
        suite.expect(bench.live.count == 1 && first?.registered == nil,
                     "a saved combination with no modifier holds no key")
    }

    /// Review Focus 1: recording a shortcut releases every key the app holds.
    /// The registrar holds none while a recording runs, and has every one
    /// back at the sync that follows it.
    static func shortcutRegistrarRecording(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let bench = RegistrarBench()
        let hello = SampleTool.hello
        bench.saved = [hello.rawValue: optionB]
        SampleTool.install(into: bench.registry, say: { _ in })
        let ids = bench.live.map(\.id)
        suite.expect(ids.count == 1, "the command holds its key before a recording")

        // `ShortcutCapture.begin`.
        bench.recording = true
        bench.releaseEveryKey()
        bench.registry.noteAvailabilityChanged()
        suite.expect(bench.live.isEmpty, "a change in the registry during a recording takes no key")
        bench.registrar.sync()
        suite.expect(bench.live.isEmpty, "a sync during a recording takes no key")
        bench.registrar.assign(optionN, to: hello)
        suite.expect(bench.live.isEmpty && bench.saved[hello.rawValue] == optionN,
                     "a shortcut given during a recording is saved, and holds no key until the recording ends")

        // `ShortcutCapture.end`.
        bench.recording = false
        bench.registrar.sync()
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionN
                         && bench.live.map(\.id) == ids,
                     "the sync at the end of a recording gives the key back, under the id it had")

        // A recording that ends with nothing changed: cancelled, or another shortcut's.
        bench.recording = true
        bench.releaseEveryKey()
        bench.recording = false
        bench.registrar.sync()
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionN,
                     "a key released by someone else's recording is back at the next sync")

        // A refusal found before a recording is not forgotten by it.
        bench.refusing = true
        bench.registrar.assign(optionB, to: hello)
        bench.recording = true
        bench.registrar.sync()
        suite.expect(bench.registrar.refused == [hello], "a recording does not clear what macOS refused")
        bench.recording = false
        bench.refusing = false
        bench.registrar.sync()
        suite.expect(bench.registrar.refused.isEmpty && bench.live.count == 1, "and the refusal clears afterwards")
    }

    /// Review Focus 3, for a tool the hub switches off.
    static func shortcutRegistrarSwitchedOff(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        var on = true
        let bench = RegistrarBench(registry: ToolRegistry(isAvailable: { _ in on }))
        let tool = ToolID("screenshot")!
        let capture = CommandID(tool: tool, name: "capture")!
        try? bench.registry.register(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [
            CommandDescriptor(id: capture, title: "Capture", symbol: "camera.viewfinder", surfaces: [.shortcut])!,
        ])!)
        try? bench.registry.setHandler(.init(title: { _ in "Capture" }, run: {}), for: capture)
        bench.registrar.assign(optionB, to: capture)
        suite.expect(bench.live.count == 1, "a switched-on tool's command holds its key")
        let saves = bench.saves

        on = false
        bench.registry.noteAvailabilityChanged()
        suite.expect(bench.live.isEmpty && bench.saved[capture.rawValue] == optionB && bench.saves == saves,
                     "a tool switched off gives its key back, and its shortcut stays saved")
        on = true
        bench.registry.noteAvailabilityChanged()
        suite.expect(bench.live.count == 1 && bench.live[0].registered?.shortcut == optionB && bench.saves == saves,
                     "a tool switched back on has its key again")
    }

    /// Decision 6: at most 64 keys, every id inside the run.
    static func shortcutRegistrarLimit(_ suite: TestSuite) {
        let bench = RegistrarBench()
        let tool = ToolID("com.acme.many")!
        let ids = (0 ..< 70).map { CommandID(tool: tool, name: "c\($0)")! }
        for (index, id) in ids.enumerated() {
            bench.saved[id.rawValue] = GlobalShortcut(keyCode: Int64(index), modifiers: [.option])
        }
        try? bench.registry.register(ToolDescriptor(id: tool, name: "Many", symbol: "square.grid.3x3", commands: ids.map {
            CommandDescriptor(id: $0, title: $0.name, symbol: "square", surfaces: [.shortcut])!
        })!)
        for id in ids { try? bench.registry.setHandler(.init(title: { _ in id.name }, run: {}), for: id) }
        let first = ToolShortcutRegistrar.firstHotkeyID
        let run = first ..< first + UInt32(ToolCommandShortcuts.limit)
        suite.expect(bench.live.count == ToolCommandShortcuts.limit
                         && bench.made.allSatisfy { run.contains($0.id) }
                         && Set(bench.live.map(\.id)).count == ToolCommandShortcuts.limit,
                     "seventy saved shortcuts hold sixty-four keys, each with its own id inside the run")
        suite.expect(bench.saved.count == 70 && bench.saves == 0, "and the ones past the limit stay saved")

        // Commands leaving and returning never push an id out of the run.
        for _ in 0 ..< 3 {
            bench.registry.unregister(tool)
            try? bench.registry.register(ToolDescriptor(id: tool, name: "Many", symbol: "square.grid.3x3", commands: ids.map {
                CommandDescriptor(id: $0, title: $0.name, symbol: "square", surfaces: [.shortcut])!
            })!)
            for id in ids { try? bench.registry.setHandler(.init(title: { _ in id.name }, run: {}), for: id) }
        }
        suite.expect(bench.live.count == ToolCommandShortcuts.limit && bench.made.allSatisfy { run.contains($0.id) }
                         && Set(bench.live.map(\.id)).count == ToolCommandShortcuts.limit,
                     "ids stay inside the run however often commands come and go")
    }

    /// A release build registers the app's own tools only, and none of their
    /// commands asks for a shortcut: the registrar takes no key and writes
    /// nothing, whatever is saved.
    static func shortcutRegistrarOwnToolsOnly(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let bench = RegistrarBench()
        BuiltinTools.install(into: bench.registry)
        let own = bench.registry.commands(on: .radial).first?.id
        suite.expect(own != nil && bench.registry.commands(on: .shortcut).isEmpty,
                     "none of the app's own commands asks for a shortcut")
        bench.saved = [SampleTool.hello.rawValue: optionB, (own?.rawValue ?? "screenshot/capture"): optionN]
        bench.registrar.sync()
        bench.registry.noteAvailabilityChanged()
        suite.expect(bench.made.isEmpty && bench.saves == 0 && bench.saved.count == 2
                         && bench.registrar.refused.isEmpty && bench.takeOvers.isEmpty,
                     "with the app's own tools only, the registrar takes no key and writes nothing")
    }

    /// Review Focus 4: giving one command a shortcut deletes no other entry,
    /// readable or not. This goes through the store the app uses.
    static func shortcutRegistrarSaving(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let optionM = GlobalShortcut(keyCode: 46, modifiers: [.option])
        let optionK = GlobalShortcut(keyCode: 40, modifiers: [.option])
        let domain = "com.vitruviansoftware.vitruvian.tests.toolShortcutRegistrar"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        func stored() -> [String: String] {
            guard let data = defaults.string(forKey: DefaultsKey.toolCommandShortcuts)?.data(using: .utf8) else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }

        let hello = SampleTool.hello
        // A command that is here, one that is not, an id that is not an id,
        // and a value that is not a combination.
        let before = [hello.rawValue: optionB.storageValue, "com.acme.gone/open": optionN.storageValue,
                      "not an id": optionM.storageValue, "com.acme.odd/open": "nonsense"]
        defaults[Preferences.toolCommandShortcuts] = String(data: try! JSONEncoder().encode(before), encoding: .utf8)!
        let text = defaults.string(forKey: DefaultsKey.toolCommandShortcuts)

        let registry = ToolRegistry(isAvailable: { _ in true })
        var made: [FakeHotkey] = []
        let registrar = ToolShortcutRegistrar(environment: .init(
            registry: registry,
            shortcuts: { ToolCommandShortcuts.load(from: defaults) },
            save: { ToolCommandShortcuts.save($0, to: defaults) },
            makeHotkey: { id in
                let hotkey = FakeHotkey(id: id, accepts: { true })
                made.append(hotkey)
                return hotkey
            },
            isRecording: { false }, refuse: {}, setTakeOver: { _, _ in }))
        SampleTool.install(into: registry, say: { _ in })
        registrar.sync()
        suite.expect(made.count == 1 && defaults.string(forKey: DefaultsKey.toolCommandShortcuts) == text,
                     "syncing over a saved list with unreadable entries leaves the saved text byte for byte as it was")
        suite.expect(registrar.shortcuts.count == 3, "the registrar reads every entry that holds a combination")

        let third = CommandID("com.acme.new/run")!
        registrar.assign(optionK, to: third)
        var expected = before
        expected[third.rawValue] = optionK.storageValue
        suite.expect(stored() == expected,
                     "giving a third command a shortcut keeps every other entry: unregistered, malformed and unreadable")
        registrar.assign(nil, to: third)
        suite.expect(stored() == before, "clearing it again leaves the list as it was")

        // An unreadable entry is replaced when its own command is given a combination.
        registrar.assign(optionK, to: CommandID("com.acme.odd/open")!)
        expected = before
        expected["com.acme.odd/open"] = optionK.storageValue
        suite.expect(stored() == expected, "a command whose saved value was unreadable can be given a shortcut")

        // The last entry cleared leaves no stored text behind.
        defaults[Preferences.toolCommandShortcuts] = String(
            data: try! JSONEncoder().encode([hello.rawValue: optionB.storageValue]), encoding: .utf8)!
        registrar.assign(nil, to: hello)
        suite.expect(defaults.object(forKey: DefaultsKey.toolCommandShortcuts) == nil
                         && defaults[Preferences.toolCommandShortcuts].isEmpty,
                     "clearing the last shortcut returns the preference to its default")
    }

    // MARK: - The Shortcuts page

    /// What the page lists: nothing with only the app's own tools, and
    /// otherwise the same sections in the same order at every launch.
    static func shortcutSections(_ suite: TestSuite) {
        let shipped = ToolRegistry(isAvailable: { _ in true })
        BuiltinTools.install(into: shipped)
        suite.expect(ToolCommandShortcutSection.all(registry: shipped, language: .systemDefault).isEmpty,
                     "with only the app's own tools, the Shortcuts page gains no section")
        SampleTool.install(into: shipped, say: { _ in })
        let sections = ToolCommandShortcutSection.all(registry: shipped, language: .systemDefault)
        suite.expect(sections.count == 1 && sections[0].toolID == SampleTool.id
                         && sections[0].name == "Sample tool"
                         && sections[0].commands.map(\.id) == [SampleTool.hello],
                     "a tool whose commands ask for a shortcut gets a section under its own name")

        // Two tools, registered in either order, list the same way.
        func install(_ text: String, _ names: [String], surfaces: Set<ToolSurface> = [.shortcut], into registry: ToolRegistry) {
            let tool = ToolID(text)!
            let ids = names.map { CommandID(tool: tool, name: $0)! }
            try? registry.register(ToolDescriptor(id: tool, name: text, symbol: "square", commands: ids.map {
                CommandDescriptor(id: $0, title: $0.name, symbol: "square", surfaces: surfaces)!
            })!)
            for id in ids { try? registry.setHandler(.init(title: { _ in id.name }, run: {}), for: id) }
        }
        let forward = ToolRegistry(isAvailable: { _ in true })
        install("com.acme.alpha", ["zoom", "arrange"], into: forward)
        install("com.acme.beta", ["open"], into: forward)
        install("com.acme.quiet", ["hum"], surfaces: [.radial], into: forward)
        let backward = ToolRegistry(isAvailable: { _ in true })
        install("com.acme.quiet", ["hum"], surfaces: [.radial], into: backward)
        install("com.acme.beta", ["open"], into: backward)
        install("com.acme.alpha", ["zoom", "arrange"], into: backward)
        let listed = ToolCommandShortcutSection.all(registry: forward, language: .systemDefault)
        suite.expect(listed.map(\.toolID.rawValue) == ["com.acme.alpha", "com.acme.beta"]
                         && listed.first?.commands.map(\.id.name) == ["zoom", "arrange"]
                         && listed == ToolCommandShortcutSection.all(registry: backward, language: .systemDefault),
                     "sections are in the order of their tool ids whatever order the tools registered in, a tool's commands stay in the order it declared them, and a tool with no command asking has no section")
    }

    /// Review Focus 2: what the row does with a combination, every branch.
    /// The order is the other rows' order: a role, window layout, Command
    /// Bar rows and other tool commands, then the list's own rules, then macOS.
    static func shortcutRowDecision(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionM = GlobalShortcut(keyCode: 46, modifiers: [.option])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option])
        let optionK = GlobalShortcut(keyCode: 40, modifiers: [.option])
        let optionW = GlobalShortcut(keyCode: 13, modifiers: [.option])
        let commandSpace = GlobalShortcut(keyCode: 49, modifiers: [.command])
        let hello = SampleTool.hello
        let other = "com.acme.gone/open"
        let optionJ = GlobalShortcut(keyCode: 38, modifiers: [.option])
        // Mail's combination is also a role's and a window-layout action's;
        // Notes' is the row's alone, so only the row check can refuse it.
        let rows = ["app.bundle.mail": optionM, "app.bundle.notes": optionJ]
        var saved = [hello.rawValue: optionB, other: optionN]
        var takenOver = false
        func decide(_ shortcut: GlobalShortcut) -> ToolCommandShortcutSave {
            ToolCommandShortcutSave.decide(shortcut, for: hello, saved: saved, checks: .init(
                roleHolder: { $0 == optionK || $0 == optionM ? "Keep awake" : nil },
                windowLayoutHolder: { $0 == optionW || $0 == optionM ? "Left half" : nil },
                otherHolder: { shortcut in
                    ShortcutConflicts.holder(of: shortcut, rows: rows, commands: saved,
                                             excludingRow: nil, excludingCommand: hello).map {
                        ShortcutConflicts.name(of: $0, rowTitle: { $0 == "app.bundle.notes" ? "Notes" : "Mail" },
                                               rowFallback: "Rows", commandTitle: { _ in nil })
                    }
                },
                commandName: { "named " + $0 },
                conflictsWithMacOS: { $0 == commandSpace },
                takenOver: takenOver))
        }
        let free = GlobalShortcut(keyCode: 0, modifiers: [.control])
        suite.expect(decide(free) == .save(clearTakeOver: true),
                     "a combination nothing holds is saved, and a stale take-over is dropped")
        suite.expect(decide(optionK) == .refuse(.held(by: "Keep awake")),
                     "a combination a role holds is refused, naming the role")
        suite.expect(decide(optionW) == .refuse(.held(by: "Left half")),
                     "a combination a window-layout action holds is refused, naming the action")
        suite.expect(decide(optionM) == .refuse(.held(by: "Keep awake")),
                     "with several holders the role is named first, as on the other rows")
        suite.expect(decide(optionJ) == .refuse(.held(by: "Notes")),
                     "a combination only a Command Bar row holds is refused, naming the row")
        saved[hello.rawValue] = nil
        suite.expect(decide(optionN) == .refuse(.held(by: other)),
                     "a combination another tool command holds is refused, even one not registered now")
        saved[hello.rawValue] = optionB
        suite.expect(decide(optionB) == .save(clearTakeOver: true),
                     "a command may record the combination it already has")
        let rowHeld = GlobalShortcut(keyCode: 46, modifiers: [.control])
        suite.expect(ToolCommandShortcutSave.decide(rowHeld, for: hello, saved: saved, checks: .init(
            roleHolder: { _ in nil }, windowLayoutHolder: { _ in nil },
            otherHolder: { $0 == rowHeld ? "Mail" : nil }, commandName: { $0 },
            conflictsWithMacOS: { _ in true }, takenOver: false)) == .refuse(.held(by: "Mail")),
                     "a combination a Command Bar row holds is refused before macOS is asked")
        suite.expect(decide(GlobalShortcut(keyCode: 11, modifiers: [])) == .refuse(.invalid),
                     "a bare key is refused")

        // A check that misses another command's entry: the list's own rule still refuses it.
        let blind = ToolCommandShortcutSave.Checks(
            roleHolder: { _ in nil }, windowLayoutHolder: { _ in nil }, otherHolder: { _ in nil },
            commandName: { "named " + $0 }, conflictsWithMacOS: { _ in false }, takenOver: false)
        suite.expect(ToolCommandShortcutSave.decide(optionN, for: hello, saved: saved, checks: blind)
                         == .refuse(.held(by: "named " + other)),
                     "the list itself refuses a combination another command has saved")

        // Full: every place is held by a command that is not here.
        var full: [String: GlobalShortcut] = [:]
        for index in 0 ..< ToolCommandShortcuts.limit {
            full["com.acme.full/c\(index)"] = GlobalShortcut(keyCode: Int64(100 + index), modifiers: [.option])
        }
        suite.expect(ToolCommandShortcutSave.decide(free, for: hello, saved: full, checks: blind) == .refuse(.full),
                     "a command with no place in a full list is refused")
        suite.expect(ToolCommandShortcutSave.decide(commandSpace, for: hello, saved: full, checks: .init(
            roleHolder: { _ in nil }, windowLayoutHolder: { _ in nil }, otherHolder: { _ in nil },
            commandName: { $0 }, conflictsWithMacOS: { _ in true }, takenOver: false)) == .refuse(.full),
                     "a full list refuses before macOS is asked, so no take-over is offered that could not be kept")
        full["com.acme.full/c0"] = nil
        full[hello.rawValue] = optionB
        suite.expect(ToolCommandShortcutSave.decide(free, for: hello, saved: full, checks: blind) == .save(clearTakeOver: true),
                     "a command that has a place may change its combination in a full list")

        // macOS answers the combination.
        suite.expect(decide(commandSpace) == .offerTakeOver,
                     "a combination macOS answers is offered as a take-over, not saved")
        saved[hello.rawValue] = commandSpace
        takenOver = true
        suite.expect(decide(commandSpace) == .save(clearTakeOver: false),
                     "the combination already taken over is saved again without asking, and stays taken over")
        suite.expect(decide(free) == .save(clearTakeOver: true),
                     "moving off a taken-over combination drops the take-over")

        // What `assign` says is the last word, and each reason has its message.
        suite.expect(ToolCommandShortcutSave.refusal(for: .invalid, commandName: { $0 }) == .invalid
                         && ToolCommandShortcutSave.refusal(for: .full, commandName: { $0 }) == .full
                         && ToolCommandShortcutSave.refusal(for: .occupied(other), commandName: { "named " + $0 })
                         == .held(by: "named " + other),
                     "each reason `assign` gives for refusing has its own refusal")
        let s = Strings.localized(.enUS)
        let limitFormat = FeatureStrings.commandBar(.enUS).rowShortcutsLimitFormat
        func message(_ refusal: ToolCommandShortcutSave.Refusal) -> String {
            refusal.message(s, limitFormat: limitFormat)
        }
        suite.expect(message(.invalid) == s.shortcutInvalid
                         && message(.held(by: "Say hello")) == String(format: s.shortcutConflictFormat, "Say hello")
                         && message(.held(by: "Say hello")).contains("Say hello")
                         && message(.full) == String(format: limitFormat, ToolCommandShortcuts.limit)
                         && message(.full).contains("\(ToolCommandShortcuts.limit)"),
                     "every refusal has a message of its own: \(message(.invalid)) / \(message(.held(by: "Say hello"))) / \(message(.full))")
    }

    /// The step after the decision: the take-over choice is written before
    /// the key is taken, only when it changes, and put back if the registrar
    /// refuses. Everything it touches is a closure that records the call.
    static func shortcutRowCommit(_ suite: TestSuite) {
        let commandSpace = GlobalShortcut(keyCode: 49, modifiers: [.command])
        let free = GlobalShortcut(keyCode: 0, modifiers: [.control])
        let other = "com.acme.gone/open"
        var flag = false
        var calls: [String] = []
        var issue: ShortcutMap.AssignmentIssue?
        let blind = ToolCommandShortcutSave.Checks(
            roleHolder: { _ in nil }, windowLayoutHolder: { _ in nil }, otherHolder: { _ in nil },
            commandName: { "named " + $0 }, conflictsWithMacOS: { _ in true }, takenOver: false)
        func commit(_ shortcut: GlobalShortcut, _ takeOver: ToolCommandShortcutSave.TakeOver,
                    startingWith on: Bool) -> ToolCommandShortcutSave.Outcome {
            flag = on
            calls = []
            return ToolCommandShortcutSave.commit(
                shortcut, takeOver: takeOver, checks: blind,
                isTakenOver: { flag },
                setTakeOver: {
                    flag = $0
                    calls.append("take-over \($0 ? "on" : "off")")
                },
                assign: {
                    calls.append("assign \($0.storageValue) with take-over \(flag ? "on" : "off")")
                    return issue
                })
        }
        let assignSpaceOn = "assign \(commandSpace.storageValue) with take-over on"
        let assignFreeOff = "assign \(free.storageValue) with take-over off"

        // Accepting the offer.
        suite.expect(commit(commandSpace, .accept, startingWith: false) == .saved
                         && calls == ["take-over on", assignSpaceOn] && flag,
                     "accepting a take-over switches it on and then takes the key, in that order: \(calls)")
        suite.expect(commit(commandSpace, .accept, startingWith: true) == .saved
                         && calls == [assignSpaceOn] && flag,
                     "a take-over that is already on is not written again: \(calls)")
        issue = .full
        suite.expect(commit(commandSpace, .accept, startingWith: false) == .refused(.full)
                         && calls == ["take-over on", assignSpaceOn, "take-over off"] && !flag,
                     "a take-over the full list refuses is switched back off: \(calls)")
        issue = .occupied(other)
        suite.expect(commit(commandSpace, .accept, startingWith: false) == .refused(.held(by: "named " + other))
                         && calls == ["take-over on", assignSpaceOn, "take-over off"] && !flag,
                     "a take-over refused because another command has the combination is switched back off: \(calls)")
        suite.expect(commit(commandSpace, .accept, startingWith: true) == .refused(.held(by: "named " + other))
                         && calls == [assignSpaceOn] && flag,
                     "a refused take-over that was on before stays on, and is never written: \(calls)")
        issue = .invalid
        suite.expect(commit(commandSpace, .accept, startingWith: false) == .refused(.invalid) && !flag,
                     "a take-over refused as not a usable combination is switched back off")

        // A plain save of a combination macOS does not answer.
        issue = nil
        suite.expect(commit(free, .clear, startingWith: true) == .saved
                         && calls == ["take-over off", assignFreeOff] && !flag,
                     "a plain save over a taken-over combination gives the macOS shortcut back first: \(calls)")
        suite.expect(commit(free, .clear, startingWith: false) == .saved && calls == [assignFreeOff] && !flag,
                     "a plain save with no take-over to drop does not write the take-over choice: \(calls)")
        issue = .full
        suite.expect(commit(free, .clear, startingWith: true) == .refused(.full)
                         && calls == ["take-over off", assignFreeOff, "take-over on"] && flag,
                     "a refused plain save leaves the take-over as it was: \(calls)")

        // The combination already taken over, recorded again.
        issue = nil
        suite.expect(commit(commandSpace, .keep, startingWith: true) == .saved && calls == [assignSpaceOn] && flag,
                     "saving the taken-over combination again leaves the take-over alone: \(calls)")
        issue = .full
        suite.expect(commit(commandSpace, .keep, startingWith: true) == .refused(.full)
                         && calls == [assignSpaceOn] && flag,
                     "and a refusal of it writes nothing")

        // Through a real registrar: a refusal saves nothing and takes no key.
        let bench = RegistrarBench()
        let hello = SampleTool.hello
        SampleTool.install(into: bench.registry, say: { _ in })
        for index in 0 ..< ToolCommandShortcuts.limit {
            bench.saved["com.acme.full/c\(index)"] = GlobalShortcut(keyCode: Int64(100 + index), modifiers: [.option])
        }
        let full = bench.saved
        var writes: [Bool] = []
        flag = false
        let outcome = ToolCommandShortcutSave.commit(
            commandSpace, takeOver: .accept, checks: blind,
            isTakenOver: { flag },
            setTakeOver: {
                flag = $0
                writes.append($0)
            },
            assign: { bench.registrar.assign($0, to: hello) })
        suite.expect(outcome == .refused(.full) && writes == [true, false] && !flag
                         && bench.saved == full && bench.saves == 0 && bench.live.isEmpty,
                     "a take-over the registrar refuses saves nothing, takes no key, and ends switched off")
        bench.saved["com.acme.full/c0"] = nil
        writes = []
        let accepted = ToolCommandShortcutSave.commit(
            commandSpace, takeOver: .accept, checks: blind,
            isTakenOver: { flag },
            setTakeOver: {
                flag = $0
                writes.append($0)
            },
            assign: { bench.registrar.assign($0, to: hello) })
        suite.expect(accepted == .saved && writes == [true] && flag && bench.saved[hello.rawValue] == commandSpace
                         && bench.live.count == 1 && bench.live[0].registered?.shortcut == commandSpace,
                     "a take-over the registrar accepts is saved and holds its key")
    }

    /// The offer stays up while the person records on other rows. By the
    /// time it is accepted something else may hold the combination, so the
    /// holders are asked again, in the usual order.
    static func shortcutRowAcceptsAStaleOffer(_ suite: TestSuite) {
        let commandSpace = GlobalShortcut(keyCode: 49, modifiers: [.command])
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let hello = SampleTool.hello
        var role: GlobalShortcut?
        var layout: GlobalShortcut?
        var row: GlobalShortcut?
        var flag = false
        var calls: [String] = []
        let checks = ToolCommandShortcutSave.Checks(
            roleHolder: { $0 == role ? "Keep awake" : nil },
            windowLayoutHolder: { $0 == layout ? "Left half" : nil },
            otherHolder: { $0 == row ? "Mail" : nil },
            commandName: { $0 }, conflictsWithMacOS: { $0 == commandSpace }, takenOver: false)
        func accept() -> ToolCommandShortcutSave.Outcome {
            calls = []
            return ToolCommandShortcutSave.commit(
                commandSpace, takeOver: .accept, checks: checks,
                isTakenOver: { flag },
                setTakeOver: {
                    flag = $0
                    calls.append("take-over \($0)")
                },
                assign: { _ in
                    calls.append("assign")
                    return nil
                })
        }
        suite.expect(ToolCommandShortcutSave.decide(commandSpace, for: hello, saved: [:], checks: checks) == .offerTakeOver,
                     "the offer is made while nothing else holds the combination")

        // A holder appears while the offer is up.
        row = commandSpace
        suite.expect(accept() == .refused(.held(by: "Mail")) && calls.isEmpty && !flag,
                     "accepting an offer for a combination a Command Bar row or tool command took meanwhile is refused, naming it, and nothing is written: \(calls)")
        layout = commandSpace
        suite.expect(accept() == .refused(.held(by: "Left half")) && calls.isEmpty && !flag,
                     "a window-layout action that took it meanwhile is named before the row: \(calls)")
        role = commandSpace
        suite.expect(accept() == .refused(.held(by: "Keep awake")) && calls.isEmpty && !flag,
                     "a role that took it meanwhile is named first: \(calls)")

        // Only that exact combination counts.
        role = optionB
        layout = optionB
        row = optionB
        suite.expect(accept() == .saved && calls == ["take-over true", "assign"] && flag,
                     "a holder of some other combination does not stop the offer being accepted: \(calls)")
    }

    /// Review Focus 3 and 5: what a row shows. The saved combination stays
    /// shown when macOS refuses the key, and comes back with its tool.
    static func shortcutRowState(_ suite: TestSuite) {
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option])
        let optionM = GlobalShortcut(keyCode: 46, modifiers: [.option])
        var on = true
        var runnable = true
        let bench = RegistrarBench(registry: ToolRegistry(isAvailable: { _ in on }))
        let tool = ToolID("screenshot")!
        let capture = CommandID(tool: tool, name: "capture")!
        try? bench.registry.register(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [
            CommandDescriptor(id: capture, title: "Capture", symbol: "camera.viewfinder", surfaces: [.shortcut])!,
        ])!)
        try? bench.registry.setHandler(.init(title: { _ in "Capture" }, isRunnable: { runnable }, run: {}), for: capture)
        func state() -> ToolCommandShortcutRowState {
            ToolCommandShortcutRowState(command: capture, registry: bench.registry, registrar: bench.registrar)
        }
        func listed() -> [CommandID] {
            ToolCommandShortcutSection.all(registry: bench.registry, language: .systemDefault).flatMap(\.commands).map(\.id)
        }
        suite.expect(state() == .init(shortcut: nil, isRefused: false, isActive: false),
                     "a command starts with no shortcut, and is not active")

        bench.registrar.assign(optionB, to: capture)
        suite.expect(state() == .init(shortcut: optionB, isRefused: false, isActive: true),
                     "a recorded shortcut is shown, and active while its command can run")

        runnable = false
        suite.expect(listed() == [capture] && state() == .init(shortcut: optionB, isRefused: false, isActive: false),
                     "a command that is listed but cannot run now keeps its row and its shortcut, and reads inactive")
        runnable = true

        // Another app holds the combination.
        bench.refusing = true
        bench.registrar.assign(optionM, to: capture)
        suite.expect(state() == .init(shortcut: optionM, isRefused: true, isActive: false)
                         && bench.saved[capture.rawValue] == optionM,
                     "a key macOS refuses is reported, and the saved combination stays shown")

        // The line under the row, while the saved key is one macOS refused.
        let refusedState = state()
        suite.expect(refusedState.caption(error: nil, isRecording: false, isOfferingTakeOver: false) == .unavailable,
                     "a row whose key macOS refused says the shortcut is unavailable")
        suite.expect(refusedState.caption(error: "Taken", isRecording: false, isOfferingTakeOver: false) == .error("Taken"),
                     "when an attempt is refused on a row whose saved key is unavailable, the attempt's error is the one shown")
        suite.expect(refusedState.caption(error: nil, isRecording: true, isOfferingTakeOver: false) == .recording,
                     "the next recording clears the error and shows the recording hint")
        suite.expect(refusedState.caption(error: nil, isRecording: false, isOfferingTakeOver: false) == .unavailable,
                     "and once the error is cleared the unavailable caption shows again")
        suite.expect([nil, "Taken"].allSatisfy { error in
            [false, true].allSatisfy { refusedState.caption(error: error, isRecording: $0, isOfferingTakeOver: false) != nil }
        }, "a row whose key macOS refused never shows no caption at all")
        suite.expect(refusedState.caption(error: nil, isRecording: false, isOfferingTakeOver: true) == nil,
                     "while a take-over is offered the offer stands in for the unavailable caption")
        suite.expect(refusedState.caption(error: "Taken", isRecording: true, isOfferingTakeOver: false) == .error("Taken"),
                     "an error raised while recording is shown over the recording hint")
        bench.refusing = false
        bench.registrar.sync()
        suite.expect(state() == .init(shortcut: optionM, isRefused: false, isActive: true),
                     "when macOS gives the key after all, the report goes")
        suite.expect(state().caption(error: nil, isRecording: false, isOfferingTakeOver: false) == nil
                         && state().caption(error: "Taken", isRecording: false, isOfferingTakeOver: false) == .error("Taken")
                         && state().caption(error: nil, isRecording: true, isOfferingTakeOver: false) == .recording,
                     "a row whose key works shows an error or the recording hint, and otherwise nothing")

        // Switched off: no row, the shortcut kept; back on: the row shows it again.
        let saves = bench.saves
        on = false
        bench.registry.noteAvailabilityChanged()
        suite.expect(listed().isEmpty && bench.saved[capture.rawValue] == optionM && bench.saves == saves,
                     "a tool that is switched off has no row, and its saved shortcut is untouched")
        on = true
        bench.registry.noteAvailabilityChanged()
        suite.expect(listed() == [capture] && state() == .init(shortcut: optionM, isRefused: false, isActive: true),
                     "when the tool returns its row shows the saved combination again")

        // A refused `assign` saves nothing, so the row keeps showing what is saved.
        bench.saved["com.acme.gone/open"] = optionB
        let issue = bench.registrar.assign(optionB, to: capture)
        suite.expect(issue.map { ToolCommandShortcutSave.refusal(for: $0, commandName: { $0 }) } == .held(by: "com.acme.gone/open")
                         && state().shortcut == optionM,
                     "a combination `assign` refuses is not shown as saved")

        // Clearing.
        bench.takeOvers = []
        bench.registrar.assign(nil, to: capture)
        suite.expect(state() == .init(shortcut: nil, isRefused: false, isActive: false)
                         && bench.takeOvers == ["\(ToolCommandShortcuts.takeOverKey(for: capture))=false"],
                     "a cleared shortcut shows as none, and its take-over is switched off")
    }
}
