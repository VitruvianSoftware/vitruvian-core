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
}
