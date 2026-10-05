// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// What the open island hears: a click in another app, which can close it,
/// and this app's clicks and keys, which it can take before the app sees
/// them. `NotchService.Environment.Parts.openEvents` holds it; the app passes
/// `.system`, and a test can deliver its own.
package struct NotchOpenEvents {
    /// Starts both monitors and returns what `removeMonitor` takes. `local`
    /// answers whether the island took the event.
    package var addMonitors: (_ clickElsewhere: @escaping () -> Void,
                              _ local: @escaping (NSEvent) -> Bool) -> [Any]
    package var removeMonitor: (Any) -> Void

    package init(addMonitors: @escaping (_ clickElsewhere: @escaping () -> Void,
                                         _ local: @escaping (NSEvent) -> Bool) -> [Any],
                 removeMonitor: @escaping (Any) -> Void) {
        self.addMonitors = addMonitors
        self.removeMonitor = removeMonitor
    }

    package static var system: NotchOpenEvents {
        NotchOpenEvents(addMonitors: { clickElsewhere, local in
            var tokens: [Any] = []
            let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { _ in clickElsewhere() }) {
                tokens.append(token)
            }
            if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { event in
                local(event) ? nil : event
            }) { tokens.append(token) }
            return tokens
        }, removeMonitor: NSEvent.removeMonitor)
    }
}
