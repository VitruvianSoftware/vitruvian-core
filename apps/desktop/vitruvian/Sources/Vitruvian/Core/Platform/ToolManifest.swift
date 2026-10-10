// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Something the host does on a tool's behalf that needs trust. The raw
/// values are the names in the platform design, and will be the names in
/// the protocol. A case is added when a tool first needs it.
package enum Capability: String, CaseIterable, Hashable, Sendable {
    /// A beep now; alerts and notifications when a tool needs them.
    case notify
    /// Open a link in the person's browser.
    case open
    /// See what is listening on a port, and end a process.
    case processes
    /// Put text on the clipboard.
    case clipboardWrite = "clipboard.write"

    /// The macOS grants no operation of this capability works without.
    package var ridesOn: [AppPermission] {
        switch self {
        case .notify, .open, .processes, .clipboardWrite: return []
        }
    }
}

/// A capability a tool asks for, and why, in a sentence a person could be
/// shown. Nobody is shown it yet; writing it is the cheapest check that the
/// capability is needed.
package struct CapabilityRequest: Equatable, Sendable {
    package let capability: Capability
    package let reason: String

    package init?(_ capability: Capability, reason: String) {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.capability = capability
        self.reason = reason
    }
}

/// One preference a tool owns: the key it is saved under today, unchanged,
/// and its default.
package struct PreferenceDeclaration: Equatable, Sendable {
    /// A saved value a manifest can state the default of.
    package enum Value: Equatable, Sendable {
        case bool(Bool)
        case string(String)
        case int(Int)
        case double(Double)

        /// The value as `UserDefaults` holds it, for comparing with what the
        /// app registers.
        package var defaultsValue: Any {
            switch self {
            case .bool(let value): return value
            case .string(let value): return value
            case .int(let value): return value
            case .double(let value): return value
            }
        }
    }

    package let key: String
    package let defaultValue: Value

    package init(key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// When the host should have a tool ready.
package enum Activation: String, Sendable {
    case onLaunch, onCommand, onShown
}

/// What a tool is, what it needs and what it adds, as one value. The fields
/// are the platform design's manifest fields that mean something for a tool
/// compiled into the app.
package struct ToolManifest: Equatable, Sendable {
    package let tool: ToolDescriptor
    package let group: FeatureGroup
    package let capabilities: [CapabilityRequest]
    package let preferences: [PreferenceDeclaration]
    package let activation: [Activation]
    /// The preference that switches the tool on, when it has one.
    package let enabledBy: String?

    package init?(tool: ToolDescriptor, group: FeatureGroup, capabilities: [CapabilityRequest],
                  preferences: [PreferenceDeclaration], activation: [Activation], enabledBy: String?) {
        let asked = capabilities.map(\.capability)
        let keys = preferences.map(\.key)
        guard Set(asked).count == asked.count, Set(keys).count == keys.count,
              enabledBy.map(keys.contains) ?? true else { return nil }
        self.tool = tool
        self.group = group
        self.capabilities = capabilities
        self.preferences = preferences
        self.activation = activation
        self.enabledBy = enabledBy
    }

    package var id: ToolID { tool.id }

    package func declares(_ capability: Capability) -> Bool {
        capabilities.contains { $0.capability == capability }
    }
}
