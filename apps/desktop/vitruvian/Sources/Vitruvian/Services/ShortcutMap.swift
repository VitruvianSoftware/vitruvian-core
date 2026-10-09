// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A list of things that each may have a global shortcut of their own, kept
/// as one preference: `{"<key>": "<shortcut storage value>"}`. Command Bar
/// rows and tool commands both keep theirs this way.
package enum ShortcutMap {
    package enum AssignmentIssue: Equatable {
        /// Not a combination a global shortcut may use.
        case invalid
        /// Another key in the same map holds it.
        case occupied(String)
        /// The map holds as many as it may.
        case full
    }

    package static func decode(_ raw: String?) -> [String: GlobalShortcut] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.compactMapValues(GlobalShortcut.init(storageValue:))
    }

    package static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? {
        let stored = shortcuts.mapValues(\.storageValue)
        guard let data = try? JSONEncoder().encode(stored) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The map with `key` given `shortcut`, or cleared when it is nil. A
    /// combination another key holds moves to this one. Past `limit` a new
    /// key is not added; `assignmentIssue` says so first.
    package static func setting(_ shortcut: GlobalShortcut?, for key: String,
                                in shortcuts: [String: GlobalShortcut], limit: Int) -> [String: GlobalShortcut] {
        var next = shortcuts
        guard let shortcut else {
            next.removeValue(forKey: key)
            return next
        }
        for (otherKey, other) in next where other == shortcut && otherKey != key {
            next.removeValue(forKey: otherKey)
        }
        guard next[key] != nil || next.count < limit else { return next }
        next[key] = shortcut
        return next
    }

    package static func hasRoom(for key: String, in shortcuts: [String: GlobalShortcut], limit: Int) -> Bool {
        shortcuts[key] != nil || shortcuts.count < limit
    }

    package static func key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }

    /// A bare letter would take that letter away from every app on the Mac.
    package static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }

    package static func assignmentIssue(_ shortcut: GlobalShortcut, for key: String,
                                        in shortcuts: [String: GlobalShortcut], limit: Int) -> AssignmentIssue? {
        guard isUsable(shortcut) else { return .invalid }
        if let owner = self.key(for: shortcut, in: shortcuts), owner != key {
            return .occupied(owner)
        }
        return hasRoom(for: key, in: shortcuts, limit: limit) ? nil : .full
    }
}
