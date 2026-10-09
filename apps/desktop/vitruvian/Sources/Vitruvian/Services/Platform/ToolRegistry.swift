// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The app's live table of tools and their commands. A surface asks it what
/// to list and tells it what to run, and names no tool's service.
///
/// Main-actor isolated: every surface reads it on the main thread.
/// `@preconcurrency` keeps the services that call it, which are not
/// actor-isolated yet, free of diagnostics.
@preconcurrency @MainActor
package final class ToolRegistry: ObservableObject {
    package static let shared = ToolRegistry(isAvailable: { $0.isAvailable })

    /// The live half of a command: what its descriptor cannot say as data.
    package struct Handler {
        /// The title in a given language, read each time it is shown.
        package var title: @MainActor (AppLanguage) -> String
        /// False while the tool's own switch is off, beyond hub availability.
        package var isRunnable: @MainActor () -> Bool
        package var run: @MainActor () -> Void

        package init(title: @escaping @MainActor (AppLanguage) -> String,
                     isRunnable: @escaping @MainActor () -> Bool = { true },
                     run: @escaping @MainActor () -> Void) {
            self.title = title
            self.isRunnable = isRunnable
            self.run = run
        }
    }

    package enum RegistrationError: Error, Equatable {
        case duplicateTool(ToolID)
        case unknownCommand(CommandID)
    }

    /// Bumped on every change, so a view that lists commands redraws.
    @Published package private(set) var revision = 0

    private let isAvailable: (AppFeature) -> Bool
    private var order: [ToolID] = []
    private var tools: [ToolID: ToolDescriptor] = [:]
    private var handlers: [CommandID: Handler] = [:]

    package init(isAvailable: @escaping (AppFeature) -> Bool) {
        self.isAvailable = isAvailable
    }

    // MARK: - Registration

    package func register(_ tool: ToolDescriptor) throws {
        guard tools[tool.id] == nil else { throw RegistrationError.duplicateTool(tool.id) }
        tools[tool.id] = tool
        order.append(tool.id)
        revision += 1
    }

    package func setHandler(_ handler: Handler, for id: CommandID) throws {
        guard command(id) != nil else { throw RegistrationError.unknownCommand(id) }
        handlers[id] = handler
        revision += 1
    }

    package func unregister(_ id: ToolID) {
        guard let tool = tools.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        tool.commands.forEach { handlers[$0.id] = nil }
        revision += 1
    }

    // MARK: - Reading

    package func tool(_ id: ToolID) -> ToolDescriptor? { tools[id] }

    package func command(_ id: CommandID) -> CommandDescriptor? {
        tools[id.tool]?.commands.first { $0.id == id }
    }

    package func hasHandler(for id: CommandID) -> Bool { handlers[id] != nil }

    /// What a surface offers now: commands that asked for it, whose tool is
    /// switched on in the hub and that something can run. In registration
    /// order, then the tool's own order.
    package func commands(on surface: ToolSurface) -> [CommandDescriptor] {
        order.compactMap { tools[$0] }
            .filter { isToolAvailable($0.id) }
            .flatMap(\.commands)
            .filter { $0.surfaces.contains(surface) && handlers[$0.id] != nil }
    }

    package func title(for id: CommandID, language: AppLanguage) -> String? {
        guard command(id) != nil else { return nil }
        return handlers[id]?.title(language)
    }

    // MARK: - Running

    package func canRun(_ id: CommandID) -> Bool {
        guard isToolAvailable(id.tool) else { return false }
        return handlers[id]?.isRunnable() ?? false
    }

    @discardableResult
    package func run(_ id: CommandID) -> Bool {
        guard canRun(id), let handler = handlers[id] else { return false }
        handler.run()
        return true
    }

    /// A bundled tool follows its hub feature. An outside tool has none, and
    /// is available while it is registered.
    private func isToolAvailable(_ id: ToolID) -> Bool {
        guard let tool = tools[id] else { return false }
        guard let feature = tool.feature else { return true }
        return isAvailable(feature)
    }
}
