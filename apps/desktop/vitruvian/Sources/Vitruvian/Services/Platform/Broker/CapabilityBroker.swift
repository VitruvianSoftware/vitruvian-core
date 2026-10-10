// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Why the broker would not do something.
package enum BrokerRefusal: Error, Equatable, Sendable {
    /// The tool's manifest does not list the capability. A mistake in the
    /// tool, never something a person did.
    case notDeclared(Capability)
    /// The tool is not installed in the Features hub.
    case notInstalled
    /// A macOS grant the capability rides on is missing.
    case notGranted(AppPermission)
    /// The host cannot offer this right now: the person has not allowed it,
    /// or what it depends on is not there.
    case unavailable
}

/// The one door to the services that need trust. A tool reaches it through
/// `ToolServices`, which carries the tool's manifest, so a tool cannot ask
/// as another. Every operation asks `refusal(of:for:)` before it does
/// anything.
///
/// The broker names no tool. The files beside this one each serve one
/// capability.
@MainActor
package final class CapabilityBroker {
    package static let shared = CapabilityBroker(environment: .live, backings: .live)

    package struct Environment {
        package var isInstalled: (ToolID) -> Bool
        package var isGranted: (AppPermission) -> Bool
        /// Whether the person allows this tool this capability. Always true
        /// for a tool compiled into the app; a consent screen fills this in
        /// when tools from outside arrive.
        package var allows: (ToolID, Capability) -> Bool
        package var reportUndeclared: (ToolID, Capability) -> Void

        package init(isInstalled: @escaping (ToolID) -> Bool,
                     isGranted: @escaping (AppPermission) -> Bool,
                     allows: @escaping (ToolID, Capability) -> Bool,
                     reportUndeclared: @escaping (ToolID, Capability) -> Void) {
            self.isInstalled = isInstalled
            self.isGranted = isGranted
            self.allows = allows
            self.reportUndeclared = reportUndeclared
        }

        /// The app as it is: a tool with the id of a hub feature follows
        /// that feature; the two macOS grants the app watches are read
        /// from `Permissions`; a compiled-in tool is always allowed.
        @MainActor package static let live = Environment(
            isInstalled: { id in AppFeature(rawValue: id.rawValue)?.isAvailable ?? true },
            isGranted: { permission in
                switch permission {
                case .accessibility: return Permissions.shared.accessibility
                case .screenRecording: return Permissions.shared.screenRecording
                default: return true
                }
            },
            allows: { _, _ in true },
            reportUndeclared: { id, capability in
                assertionFailure("\(id) used \(capability.rawValue) without declaring it")
            })
    }

    /// What each capability calls to do its work.
    package struct Backings {
        package var notify: NotifyAccess.Backing
        package var open: OpenAccess.Backing
        package var clipboard: ClipboardAccess.Backing
        package var processes: ProcessesAccess.Backing

        package init(notify: NotifyAccess.Backing, open: OpenAccess.Backing, clipboard: ClipboardAccess.Backing,
                     processes: ProcessesAccess.Backing) {
            self.notify = notify
            self.open = open
            self.clipboard = clipboard
            self.processes = processes
        }

        @MainActor package static let live = Backings(notify: .live, open: .live, clipboard: .live, processes: .live)
    }

    package let environment: Environment
    package let backings: Backings

    package init(environment: Environment, backings: Backings) {
        self.environment = environment
        self.backings = backings
    }

    /// The handle for one tool.
    package func services(for manifest: ToolManifest) -> ToolServices {
        ToolServices(manifest: manifest, broker: self)
    }

    /// Why `tool` may not use `capability` now, or nil when it may. The
    /// order is fixed: a mistake in the tool is said before any state of
    /// the person's Mac.
    package func refusal(of capability: Capability, for tool: ToolManifest) -> BrokerRefusal? {
        guard tool.declares(capability) else {
            environment.reportUndeclared(tool.id, capability)
            return .notDeclared(capability)
        }
        guard environment.isInstalled(tool.id) else { return .notInstalled }
        if let missing = capability.ridesOn.first(where: { !environment.isGranted($0) }) {
            return .notGranted(missing)
        }
        guard environment.allows(tool.id, capability) else { return .unavailable }
        return nil
    }
}
