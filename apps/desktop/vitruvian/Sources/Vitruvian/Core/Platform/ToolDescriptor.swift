// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// A tool's stable identity. A bundled tool's id is its `AppFeature` raw
/// value, which is what users already have saved; an outside tool's is
/// reverse-DNS (`com.acme.deploys`). The dot is what tells them apart, so
/// the two can never collide.
package struct ToolID: Hashable, Sendable, CustomStringConvertible {
    package static let maxLength = 128

    package let rawValue: String

    package init?(_ rawValue: String) {
        guard Self.isValidPart(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    package var description: String { rawValue }

    /// True for an id with no dot: one of the app's own tools.
    package var isBundledForm: Bool { !rawValue.contains(".") }

    /// Letters, digits, dot, hyphen and underscore; no dot at either end.
    /// Ids are read back from saved state, so anything else is refused here
    /// instead of being trusted later.
    static func isValidPart(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= maxLength, !text.hasPrefix("."), !text.hasSuffix(".") else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
    }
}

/// One action of one tool, written `<tool id>/<name>`.
package struct CommandID: Hashable, Sendable, CustomStringConvertible {
    package let tool: ToolID
    package let name: String

    package init?(tool: ToolID, name: String) {
        guard ToolID.isValidPart(name) else { return nil }
        self.tool = tool
        self.name = name
    }

    /// Reads `<tool id>/<name>`. Exactly one slash: the tool id cannot hold
    /// one, and neither can the name.
    package init?(_ rawValue: String) {
        let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let tool = ToolID(String(parts[0])) else { return nil }
        self.init(tool: tool, name: String(parts[1]))
    }

    package var rawValue: String { "\(tool.rawValue)/\(name)" }
    package var description: String { rawValue }
}

/// Where a command may be offered. A command is listed only where its tool
/// asked for it.
package enum ToolSurface: String, Sendable, CaseIterable {
    case commandBar, radial, quickPanel
}

/// One command, as data. `title` is the plain fallback; a bundled tool's
/// title comes from its handler, in the current language.
package struct CommandDescriptor: Equatable, Sendable {
    package let id: CommandID
    package let title: String
    package let symbol: String
    package let surfaces: Set<ToolSurface>

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: CommandID, title: String, symbol: String, surfaces: Set<ToolSurface>) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.surfaces = surfaces
    }
}

/// One tool, as data: what a feature is today.
package struct ToolDescriptor: Equatable, Sendable {
    package let id: ToolID
    package let name: String
    package let symbol: String
    package let commands: [CommandDescriptor]

    /// Nil when a command belongs to another tool or is declared twice, so a
    /// tool that exists is always consistent.
    package init?(id: ToolID, name: String, symbol: String, commands: [CommandDescriptor]) {
        guard commands.allSatisfy({ $0.id.tool == id }),
              Set(commands.map(\.id)).count == commands.count else { return nil }
        self.id = id
        self.name = name
        self.symbol = symbol
        self.commands = commands
    }

    /// The hub feature behind a bundled tool; nil for an outside tool.
    package var feature: AppFeature? { AppFeature(rawValue: id.rawValue) }
}
