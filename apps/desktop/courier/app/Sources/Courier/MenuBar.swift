// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

/// The menu-bar icon: an SF Symbol, drawn as a template by the system (it takes the menu bar's colour). It fills in
/// when the inbox has unread chats according to the Dock badge count preference (unless the app is locked).
struct MenuBarIcon: View {
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var dockPreferences: DockAndTrayPreferences
    @ObservedObject var lifecycle: SystemLifecycleModel

    private var effectiveCount: Int {
        guard !lifecycle.isLocked else { return 0 }
        return SpacesModel.badgeCount(of: spaces.spaces, mode: dockPreferences.badgeMode)
    }

    var body: some View {
        Image(systemName: effectiveCount > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            .accessibilityLabel(String(localized: "Courier"))
    }
}

/// The menu-bar icon's menu: how many chats are unread, top unread and recent chats (`DockMenuModel`), Open Courier,
/// Lock/Unlock App, and Quit Courier.
struct MenuBarMenu: View {
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var model: AppModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    @ObservedObject var dockPreferences: DockAndTrayPreferences
    let openCourier: () -> Void

    private var dockMenu: DockMenuModel {
        DockMenuModel.build(
            isLocked: lifecycle.isLocked,
            inboxRows: inbox.rows,
            recentlyViewedRoomIDs: inbox.recentlyViewedRoomIDs,
            currentRoomID: model.selectedRoomID
        )
    }

    var body: some View {
        Text(unreadLine)
        if !dockMenu.unreadChats.isEmpty {
            Divider()
            Section(String(localized: "Unread Chats")) {
                ForEach(dockMenu.unreadChats) { item in
                    Button(item.title) {
                        openChat(item.roomID)
                    }
                }
            }
        }
        if !dockMenu.recentChats.isEmpty {
            Divider()
            Section(String(localized: "Recent Chats")) {
                ForEach(dockMenu.recentChats) { item in
                    Button(item.title) {
                        openChat(item.roomID)
                    }
                }
            }
        }
        Divider()
        Button(String(localized: "Open Courier"), action: openCourier)
        if lifecycle.isLocked {
            Button(String(localized: "Unlock Courier…")) {
                openCourier()
                Task { await lifecycle.unlock() }
            }
        } else {
            Button(String(localized: "Lock App")) {
                lifecycle.lockNow()
            }
        }
        Divider()
        // Quit goes through the app's quit path, which stops the engine and then exits.
        Button(String(localized: "Quit Courier")) { NSApp.terminate(nil) }
    }

    private func openChat(_ roomID: String) {
        openCourier()
        inbox.select(roomID)
        if lifecycle.isLocked {
            Task { await lifecycle.unlock() }
        }
    }

    private var unreadLine: String {
        if lifecycle.isLocked {
            return String(localized: "Courier is locked")
        }
        let count = SpacesModel.badgeCount(of: spaces.spaces, mode: dockPreferences.badgeMode)
        switch count {
        case 0: return String(localized: "No unread chats")
        case 1: return String(localized: "1 unread chat")
        default: return String(localized: "\(count) unread chats")
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

/// Keeps the Dock icon's badge synchronized with `SpacesModel.badgeCount(of:mode:)` and `SystemLifecycleModel.isLocked`.
@MainActor
final class DockBadge {
    private var subscription: AnyCancellable?

    init(
        spaces: SpacesModel,
        dockPreferences: DockAndTrayPreferences,
        lifecycle: SystemLifecycleModel
    ) {
        subscription = Publishers.CombineLatest3(
            spaces.$spaces,
            dockPreferences.$badgeMode,
            lifecycle.$isLocked
        )
        .map { spacesList, mode, isLocked -> String? in
            guard !isLocked else { return nil }
            let count = SpacesModel.badgeCount(of: spacesList, mode: mode)
            return NotificationPolicy.badgeLabel(count: count)
        }
        .removeDuplicates()
        .sink { label in
            NSApp.dockTile.badgeLabel = label
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
