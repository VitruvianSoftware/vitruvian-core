// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CoreGraphics
import Foundation

/// How the island's Notifications page lays out its messages.
package enum NotchNotificationLayout: String, CaseIterable, Identifiable, Sendable {
    /// A card per message in a rail that scrolls sideways: the page as it
    /// always was.
    case cards
    /// A compact row per message, newest first, in a list that scrolls down.
    case list

    package var id: String { rawValue }

    /// What a saved value reads as. An absent or unknown value keeps the
    /// cards, so a Mac that never chose sees the page it always had.
    package init(saved: String?) {
        self = saved.flatMap(Self.init(rawValue:)) ?? .cards
    }
}

/// One app's notifications, newest first, as the list stacks them.
package struct NotchNotificationGroup: Equatable, Identifiable, Sendable {
    /// The app's name as the banner gave it. Empty when the banner named none.
    package let app: String
    package let items: [NotchSystemNotification]

    /// A banner that names no app is a group of its own, so it is keyed by
    /// itself and never merges with another nameless one.
    package var id: String { app.isEmpty ? "message:" + (items.first?.id.uuidString ?? "") : "app:" + app }
    package var newest: NotchSystemNotification { items[0] }
    package var count: Int { items.count }
    package var ids: Set<UUID> { Set(items.map(\.id)) }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(app: String, items: [NotchSystemNotification]) {
        self.app = app
        self.items = items
    }
}

/// One line of the list: a message on its own, an app's stack, or a message
/// shown inside a stack that is open.
package enum NotchNotificationListEntry: Equatable, Identifiable, Sendable {
    case single(NotchSystemNotification)
    case group(NotchNotificationGroup, expanded: Bool)
    case member(NotchSystemNotification, group: String)

    /// A message keeps its id whether it stands alone or sits in an open
    /// stack, so SwiftUI moves the row rather than replacing it.
    package var id: String {
        switch self {
        case .single(let item), .member(let item, _): return item.id.uuidString
        case .group(let group, _): return group.id
        }
    }
}

/// The list's rules, kept out of the view so tests reach them.
package enum NotchNotificationListSupport {
    package static func layout(in defaults: UserDefaults = .standard) -> NotchNotificationLayout {
        NotchNotificationLayout(saved: defaults[Preferences.notchNotificationsLayout])
    }

    /// Grouping belongs to the list. The cards never stack, whatever the
    /// switch says, so choosing Cards gives the page it always had.
    package static func groupsByApp(in defaults: UserDefaults = .standard) -> Bool {
        layout(in: defaults) == .list && defaults[Preferences.notchNotificationsGrouped]
    }

    /// Newest first. The inbox already puts each arrival in front; sorting
    /// by arrival time with the inbox's order breaking ties keeps that order
    /// for messages read in the same pass.
    package static func newestFirst(_ items: [NotchSystemNotification]) -> [NotchSystemNotification] {
        items.enumerated().sorted { lhs, rhs in
            lhs.element.received != rhs.element.received
                ? lhs.element.received > rhs.element.received : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// One group per app, ordered by each app's newest message, and each
    /// group's messages newest first. A message that names no app is a group
    /// of its own: two such banners may come from different apps.
    package static func groups(_ items: [NotchSystemNotification]) -> [NotchNotificationGroup] {
        var order: [String] = []
        var members: [String: [NotchSystemNotification]] = [:]
        for item in newestFirst(items) {
            let key = item.content.app.isEmpty ? "message:" + item.id.uuidString : "app:" + item.content.app
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(item)
        }
        return order.map { key in
            let items = members[key] ?? []
            return NotchNotificationGroup(app: items[0].content.app, items: items)
        }
    }

    /// What the list draws, top to bottom. Ungrouped, every message is a row
    /// of its own. Grouped, an app with one message is still a plain row; an
    /// app with more is one row, followed by its messages while it is open.
    package static func entries(_ items: [NotchSystemNotification], grouped: Bool,
                                expanded: Set<String>) -> [NotchNotificationListEntry] {
        guard grouped else { return newestFirst(items).map { .single($0) } }
        return groups(items).flatMap { group -> [NotchNotificationListEntry] in
            guard group.count > 1 else { return [.single(group.newest)] }
            let open = expanded.contains(group.id)
            return [.group(group, expanded: open)] + (open ? group.items.map { .member($0, group: group.id) } : [])
        }
    }

    /// Opens a closed stack and closes an open one.
    package static func toggling(_ group: String, in expanded: Set<String>) -> Set<String> {
        var next = expanded
        if next.remove(group) == nil { next.insert(group) }
        return next
    }

    /// Only stacks still on the page stay open, so an app that drops to one
    /// message and later gets another comes back closed.
    package static func expansion(_ expanded: Set<String>, keptFor items: [NotchSystemNotification]) -> Set<String> {
        expanded.intersection(groups(items).filter { $0.count > 1 }.map(\.id))
    }

    /// What VoiceOver reads for a stack: the app, how many, and the newest.
    package static func accessibilityLabel(for group: NotchNotificationGroup,
                                           text: NotchNotificationStrings) -> String {
        let newest = group.newest.content
        let summary = [newest.title, newest.subtitle, newest.body].filter { !$0.isEmpty }.joined(separator: ", ")
        return String(format: text.groupAccessibilityFormat, group.app.isEmpty ? text.title : group.app,
                      group.count, summary)
    }
}

/// The list's measurements. A row holds a header line (the app and time) and
/// one line of message, so about seven fit where the cards fit four.
package enum NotchNotificationListLayout {
    package static let rowHeight: CGFloat = 36
    /// A stack that is open needs only its header line, and room for its
    /// dismiss button.
    package static let openGroupHeight: CGFloat = NotchLayout.iconButtonSide
    package static let rowSpacing: CGFloat = 4
    package static let iconSize: CGFloat = 22
    package static let openGroupIconSize: CGFloat = 16
    package static let cornerRadius: CGFloat = 10
    package static let horizontalPadding: CGFloat = 10
    /// A message inside an open stack sits in from the stack's edge.
    package static let memberIndent: CGFloat = 14

    /// How many plain rows a page `height` tall shows whole.
    package static func visibleRows(height: CGFloat) -> Int {
        guard height.isFinite, height > 0 else { return 0 }
        return Int(((height + rowSpacing) / (rowHeight + rowSpacing)).rounded(.down))
    }
}
