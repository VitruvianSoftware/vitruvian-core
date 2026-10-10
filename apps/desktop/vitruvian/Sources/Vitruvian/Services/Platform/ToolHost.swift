// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Owns the live tools. It builds a tool the first time somebody needs it,
/// hands the same one to everybody after, starts and stops it as the hub,
/// its switch and its grants say, runs its commands, and stops them all at
/// quit. A view gets its tool here.
@MainActor
package final class ToolHost {
    package static let shared = ToolHost(broker: .shared, tools: BundledTools.all)

    private let broker: CapabilityBroker
    /// The tools the host may build, by id.
    private var types: [ToolID: any BundledTool.Type] = [:]
    private var tools: [ToolID: any BundledTool] = [:]
    /// The tools that have been built, in the order they were.
    package private(set) var built: [ToolID] = []
    /// The tools the host started and has not stopped, in the order it
    /// started them.
    package private(set) var running: [ToolID] = []

    package init(broker: CapabilityBroker, tools: [any BundledTool.Type] = []) {
        self.broker = broker
        for type in tools { types[type.manifest.id] = type }
    }

    // MARK: - Tools

    /// The one instance of `type`, built on first use. Two tool types may
    /// not share an id: asking for the second is a mistake in the app, and
    /// stops it rather than building a tool on every call.
    package func tool<T: BundledTool>(_ type: T.Type) -> T {
        let id = type.manifest.id
        // A type listed under this id is the one that gets built.
        let listed: any BundledTool.Type = types[id] ?? type
        let existing = tools[id] ?? build(listed)
        guard let tool = existing as? T else {
            preconditionFailure("\(T.self) and \(Swift.type(of: existing)) both claim the tool id \(id.rawValue)")
        }
        return tool
    }

    /// The manifest of the tool with this id, when the host holds one.
    package func manifest(for id: ToolID) -> ToolManifest? {
        types[id]?.manifest
    }

    private func build(_ type: any BundledTool.Type) -> any BundledTool {
        let manifest = type.manifest
        let tool = type.init(services: broker.services(for: manifest))
        types[manifest.id] = type
        tools[manifest.id] = tool
        built.append(manifest.id)
        return tool
    }

    // MARK: - Running

    /// The run rule: a tool should be running when it is installed in the
    /// hub, switched on when it has a switch (`nil` when it has none), and
    /// holding every macOS grant it needs to start
    /// (`ToolManifest.grantsNeededToStart`). This is the check each service
    /// made for itself before it became a tool. A tool that is not
    /// installed is not asked about the rest.
    nonisolated package static func shouldRun(installed: Bool, switchedOn: @autoclosure () -> Bool?,
                                              holdsGrants: @autoclosure () -> Bool) -> Bool {
        guard installed else { return false }
        if let on = switchedOn(), !on { return false }
        return holdsGrants()
    }

    /// Whether a tool should be running now: the run rule, told what the
    /// hub, the saved preferences and macOS say.
    package func shouldRun(_ manifest: ToolManifest) -> Bool {
        Self.shouldRun(
            installed: broker.environment.isInstalled(manifest.id),
            switchedOn: manifest.enabledBy.map { (broker.backings.storage.read($0) as? Bool) == true },
            holdsGrants: manifest.grantsNeededToStart.allSatisfy(broker.environment.isGranted))
    }

    /// Starts or stops the tool with this id so that it matches
    /// `shouldRun`. Called at launch, when the hub installs or removes the
    /// tool, when its switch flips and when a grant changes. A tool that
    /// should not run and was never built is left unbuilt.
    package func sync(_ id: ToolID) {
        guard let type = types[id] else { return }
        if shouldRun(type.manifest) {
            let tool = tools[id] ?? build(type)
            if !running.contains(id) { running.append(id) }
            tool.start()
        } else {
            running.removeAll { $0 == id }
            tools[id]?.stop()
        }
    }

    /// The same, for code that names the tool: a view whose switch for it
    /// just flipped. Nothing watches the preferences; whoever changes one
    /// says so.
    package func sync<T: BundledTool>(_ type: T.Type) {
        let id = type.manifest.id
        if types[id] == nil { types[id] = type }
        sync(id)
    }

    /// Stops the tool with this id at once, whatever the run rule says, and
    /// builds nothing. For the moments the app lets go of every input it
    /// holds, such as a full uninstall. The next `sync` starts it again.
    package func suspend(_ id: ToolID) {
        running.removeAll { $0 == id }
        tools[id]?.stop()
    }

    /// Stops every built tool, and builds none: first the running ones,
    /// last started first, then the rest, last built first.
    package func stopAll() {
        let rest = built.reversed().filter { !running.contains($0) }
        for id in Array(running.reversed()) + rest { tools[id]?.stop() }
        running = []
    }

    // MARK: - Commands

    /// Whether a command can run now: a manifest the host holds declares
    /// it, its tool is installed in the hub, and the tool says yes. The
    /// tool's own switch is not asked: it is for background work. Asking
    /// builds the tool.
    package func canRun(_ command: CommandID) -> Bool {
        guard let type = types[command.tool],
              type.manifest.tool.commands.contains(where: { $0.id == command }),
              broker.environment.isInstalled(command.tool) else { return false }
        return (tools[command.tool] ?? build(type)).canRun(command)
    }

    /// Runs a command on its tool, when it can run.
    package func run(_ command: CommandID) {
        guard canRun(command) else { return }
        tools[command.tool]?.run(command)
    }
}
