// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

/// The menu-bar icon: an SF Symbol, drawn as a template by the system (it takes the menu bar's colour). It fills in
/// when there are unread chats.
struct MenuBarIcon: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        Image(systemName: inbox.unreadChatCount > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            .accessibilityLabel(String(localized: "Courier"))
    }
}

/// The menu-bar icon's menu: how many chats are unread, Open Courier, and Quit Courier.
struct MenuBarMenu: View {
    @ObservedObject var inbox: InboxModel
    let openCourier: () -> Void

    var body: some View {
        Text(unreadLine)
        Divider()
        Button(String(localized: "Open Courier"), action: openCourier)
        // Quit goes through the app's quit path, which stops the engine and then exits.
        Button(String(localized: "Quit Courier")) { NSApp.terminate(nil) }
    }

    private var unreadLine: String {
        switch inbox.unreadChatCount {
        case 0: String(localized: "No unread chats")
        case 1: String(localized: "1 unread chat")
        case let count: String(localized: "\(count) unread chats")
        }
    }
}

/// Brings the main window forward, opening it again if it was closed. A clicked notification and the menu both ask
/// for it, and neither has a SwiftUI environment to ask in, so the window scene registers the way to open it.
@MainActor
final class MainWindowOpener {
    private var open: (() -> Void)?

    func register(_ open: @escaping () -> Void) {
        self.open = open
    }

    func show() {
        NSApp.activate()
        // openWindow brings the window forward if it is open, and makes it again if the person closed it.
        open?()
    }
}

/// Hands the opener the window scene's `openWindow`.
struct OpenWindowRegistrar: View {
    let opener: MainWindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { opener.register { openWindow(id: "main") } }
    }
}

/// Keeps the Dock icon's badge at the number of unread chats that are not muted; none at zero.
@MainActor
final class DockBadge {
    private var subscription: AnyCancellable?

    init(inbox: InboxModel) {
        subscription = inbox.$rows.sink { rows in
            NSApp.dockTile.badgeLabel = NotificationPolicy.badgeLabel(count: NotificationPolicy.badgeCount(rows: rows))
        }
    }
}
