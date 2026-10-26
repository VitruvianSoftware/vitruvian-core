// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

/// The menu-bar icon: an SF Symbol, drawn as a template by the system (it takes the menu bar's colour). It fills in
/// when the inbox has unread chats that nothing mutes, the Dock badge's count.
struct MenuBarIcon: View {
    @ObservedObject var spaces: SpacesModel

    var body: some View {
        Image(systemName: spaces.badgeCount > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            .accessibilityLabel(String(localized: "Courier"))
    }
}

/// The menu-bar icon's menu: how many chats are unread (the Dock badge's count), Open Courier, and Quit Courier.
struct MenuBarMenu: View {
    @ObservedObject var spaces: SpacesModel
    let openCourier: () -> Void

    var body: some View {
        Text(unreadLine)
        Divider()
        Button(String(localized: "Open Courier"), action: openCourier)
        // Quit goes through the app's quit path, which stops the engine and then exits.
        Button(String(localized: "Quit Courier")) { NSApp.terminate(nil) }
    }

    private var unreadLine: String {
        switch spaces.badgeCount {
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

/// Keeps the Dock icon's badge at the engine's count of the inbox's unread or marked-unread chats that nothing
/// mutes (SpacesModel.badgeCount); none at zero. It follows the inbox space, whatever space or filter is shown.
@MainActor
final class DockBadge {
    private var subscription: AnyCancellable?

    init(spaces: SpacesModel) {
        subscription = spaces.badgeCountPublisher.sink { count in
            NSApp.dockTile.badgeLabel = NotificationPolicy.badgeLabel(count: count)
        }
    }
}

/// `File ▸ Open…` (`menu:File Open…`) command item opening the file picker to attach files to the active composer.
/// Note: `⌘O` is already bound on `Message ▸ Attach Files…` in `ConversationCommands.swift`, so the duplicate
/// `.keyboardShortcut("o", modifiers: .command)` is omitted here to avoid a menu shortcut clash.
struct FileOpenCommandItem: View {
    let composer: ComposerModel
    let isDisabled: Bool

    var body: some View {
        Button(String(localized: "Open…")) {
            AttachmentPicker.run(into: composer)
        }
        .disabled(isDisabled)
    }
}
