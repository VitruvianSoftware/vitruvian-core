// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Owns the live tools. It builds a tool the first time somebody needs it,
/// hands the same one to everybody after, starts and stops it as the hub,
/// its switch and its grants say, runs its commands, and stops them all at
/// quit. A view gets its tool here.
///
/// It holds two kinds of tool behind `HostedTool`. One compiled into the
/// app is listed by its type and built on first use. One that runs as its
/// own program is handed over already made, with its manifest (`add`).
@MainActor
package final class ToolHost {
    package static let shared = ToolHost(broker: .shared, tools: BundledTools.all)

    /// Waits, for at most so many seconds, until the condition holds.
    package typealias Wait = @MainActor (TimeInterval, () -> Bool) -> Void

    private let broker: CapabilityBroker
    private let limits: ToolLimits
    private let wait: Wait
    /// The tools the host may build, by id.
    private var types: [ToolID: any BundledTool.Type] = [:]
    /// The manifests of the tools that were handed over made, by id.
    private var added: [ToolID: ToolManifest] = [:]
    private var tools: [ToolID: any HostedTool] = [:]
    /// The tools that have been built, in the order they were.
    package private(set) var built: [ToolID] = []
    /// The tools the host started and has not stopped, in the order it
    /// started them.
    package private(set) var running: [ToolID] = []

    package init(broker: CapabilityBroker, tools: [any BundledTool.Type] = [], limits: ToolLimits = .standard,
                 wait: @escaping Wait = ToolHost.wait) {
        self.broker = broker
        self.limits = limits
        self.wait = wait
        for type in tools { types[type.manifest.id] = type }
    }

    /// Looks every few milliseconds, without turning the run loop: at quit
    /// nothing else will run on the main thread again.
    package static func wait(upTo seconds: TimeInterval, until done: () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !done(), ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
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
        types[id]?.manifest ?? added[id]
    }

    /// Takes a tool that runs as its own program, already made. False, and
    /// nothing changes, when the id has no dot, which is how the app's own
    /// tools are named, or when the host already holds a tool with it.
    @discardableResult
    package func add(_ tool: any HostedTool, manifest: ToolManifest) -> Bool {
        let id = manifest.id
        guard !id.isBundledForm, types[id] == nil, added[id] == nil else { return false }
        added[id] = manifest
        tools[id] = tool
        built.append(id)
        return true
    }

    /// Stops a tool that was handed over with `add`, and lets go of it. A
    /// tool compiled into the app is never removed.
    package func remove(_ id: ToolID) {
        guard added.removeValue(forKey: id) != nil else { return }
        tools.removeValue(forKey: id)?.stop()
        built.removeAll { $0 == id }
        running.removeAll { $0 == id }
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
        guard let manifest = manifest(for: id) else { return }
        if shouldRun(manifest), let tool = tools[id] ?? types[id].map(build) {
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
    ///
    /// This is for quit. A tool that runs as its own program has only been
    /// told goodbye by `stop`, and no timer of its link will run again. So
    /// the host waits here, without turning the run loop, for such programs
    /// to leave: two seconds, then it has each asked to end, one more, then
    /// it has each killed. With no such tool running it does not wait.
    package func stopAll() {
        let rest = built.reversed().filter { !running.contains($0) }
        for id in Array(running.reversed()) + rest { tools[id]?.stop() }
        running = []
        var lingering = tools.values.filter { !$0.hasEnded }
        for seconds in [limits.goodbyeWait, limits.endWait] where !lingering.isEmpty {
            wait(seconds) { lingering.allSatisfy { $0.hasEnded } }
            for tool in lingering where !tool.hasEnded { tool.escalate() }
            lingering = lingering.filter { !$0.hasEnded }
        }
    }

    // MARK: - Commands

    /// Whether a command can run now: a manifest the host holds declares
    /// it, its tool is installed, and the tool says yes. The tool's own
    /// switch is not asked: it is for background work. Asking builds a
    /// tool compiled into the app, and never starts a program.
    package func canRun(_ command: CommandID) -> Bool {
        guard let manifest = manifest(for: command.tool),
              manifest.tool.commands.contains(where: { $0.id == command }),
              broker.environment.isInstalled(command.tool),
              let tool = tools[command.tool] ?? types[command.tool].map(build) else { return false }
        return tool.canRun(command)
    }

    /// Runs a command on its tool, when it can run.
    package func run(_ command: CommandID) {
        guard canRun(command) else { return }
        tools[command.tool]?.run(command)
    }
}
