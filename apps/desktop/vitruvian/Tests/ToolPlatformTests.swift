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
        registry(suite)
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
                                        symbol: "camera.viewfinder", surfaces: [.radial])
        let made = ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [capture])
        suite.expect(made?.feature == .screenshot, "a bundled tool finds its feature by id")
        suite.expect(ToolDescriptor(id: ToolID("com.acme.deploys")!, name: "Deploys", symbol: "shippingbox",
                                    commands: [])?.feature == nil,
                     "an outside tool has no feature")

        let stray = CommandDescriptor(id: CommandID("colorPicker/pick")!, title: "Pick", symbol: "eyedropper",
                                      surfaces: [.radial])
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
            let command = CommandDescriptor(id: id, title: "plain \(name)", symbol: "star", surfaces: surfaces)
            try registry.register(ToolDescriptor(id: tool, name: toolID, symbol: "star", commands: [command])!)
            try registry.setHandler(.init(title: { [unowned self] _ in "\(self.language) \(name)" },
                                          isRunnable: { runnable },
                                          run: { [unowned self] in self.ran.append(id.rawValue) }),
                                    for: id)
        }
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

        let before = registry.revision
        registry.unregister(ToolID("com.acme.deploys")!)
        suite.expect(registry.tool(open.tool) == nil && registry.command(open) == nil && !registry.run(open)
                         && registry.commands(on: .commandBar).isEmpty && registry.revision > before,
                     "an unregistered tool takes its commands and handlers with it")
    }
}
