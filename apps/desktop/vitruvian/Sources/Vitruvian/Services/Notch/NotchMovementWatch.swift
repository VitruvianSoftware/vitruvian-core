// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// Monitors on pointer movement, in this app and usually in the others,
/// kept only while the island needs them. Each move runs `moved`; a pointer
/// at rest costs nothing.
package final class NotchMovementWatch {
    /// How the monitors reach the system. The app passes `.system(matching:)`.
    package struct Environment {
        /// Starts watching movement, in this app and in others, and returns
        /// what `removeMonitor` takes.
        package var addMonitors: (_ moved: @escaping () -> Void) -> [Any]
        package var removeMonitor: (Any) -> Void

        package init(addMonitors: @escaping (_ moved: @escaping () -> Void) -> [Any],
                     removeMonitor: @escaping (Any) -> Void) {
            self.addMonitors = addMonitors
            self.removeMonitor = removeMonitor
        }

        /// Movement in this app, and in the others unless `inOtherApps` is false.
        package static func system(matching events: NSEvent.EventTypeMask, inOtherApps: Bool = true) -> Environment {
            Environment(addMonitors: { moved in
                var tokens: [Any] = []
                if inOtherApps, let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { _ in moved() }) {
                    tokens.append(token)
                }
                if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
                    moved()
                    return event
                }) { tokens.append(token) }
                return tokens
            }, removeMonitor: NSEvent.removeMonitor)
        }
    }

    private let environment: Environment
    private let moved: () -> Void
    private var monitors: [Any] = []

    package init(environment: Environment, moved: @escaping () -> Void) {
        self.environment = environment
        self.moved = moved
    }

    package var isWatching: Bool { !monitors.isEmpty }

    /// Installs the monitors unless they are already watching.
    package func start() {
        guard monitors.isEmpty else { return }
        monitors = environment.addMonitors { [weak self] in self?.moved() }
    }

    package func stop() {
        monitors.forEach(environment.removeMonitor)
        monitors.removeAll()
    }
}
