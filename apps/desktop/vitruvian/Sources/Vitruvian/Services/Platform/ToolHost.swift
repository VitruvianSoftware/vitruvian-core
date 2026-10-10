// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Owns the live tools. It builds a tool the first time somebody asks for
/// it, hands the same one to everybody after, and stops them all at quit.
/// A view gets its tool here.
@MainActor
package final class ToolHost {
    package static let shared = ToolHost(broker: .shared)

    private let broker: CapabilityBroker
    private var tools: [ToolID: any BundledTool] = [:]
    /// The tools that have been built, in the order they were.
    package private(set) var built: [ToolID] = []

    package init(broker: CapabilityBroker) {
        self.broker = broker
    }

    /// The one instance of `type`, built on first use. Two tool types may
    /// not share an id: asking for the second is a mistake in the app, and
    /// stops it rather than building a tool on every call.
    package func tool<T: BundledTool>(_ type: T.Type) -> T {
        let id = type.manifest.id
        if let existing = tools[id] {
            guard let tool = existing as? T else {
                preconditionFailure("\(T.self) and \(Swift.type(of: existing)) both claim the tool id \(id.rawValue)")
            }
            return tool
        }
        let tool = T(services: broker.services(for: type.manifest))
        tools[id] = tool
        built.append(id)
        return tool
    }

    /// Stops every built tool, last built first. Builds none.
    package func stopAll() {
        for id in built.reversed() { tools[id]?.stop() }
    }
}
