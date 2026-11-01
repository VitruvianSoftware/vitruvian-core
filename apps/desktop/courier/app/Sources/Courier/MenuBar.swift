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
/// Minimize to Menu Bar, Lock/Unlock App, and Quit Courier.
struct MenuBarMenu: View {
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var model: AppModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    @ObservedObject var dockPreferences: DockAndTrayPreferences
    let menuCoordinator: AppMenuCoordinator
    @ObservedObject var hotkeys: HotkeyRegistry
    var hotkeyDispatcher: HotkeyDispatcher? = nil
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
        Button(String(localized: "Command Bar…")) {
            if let hotkeyDispatcher {
                _ = hotkeyDispatcher.perform(HotkeyID.commandBar)
            } else {
                menuCoordinator.openCommandBar()
            }
        }
        .registryShortcut(HotkeyID.commandBar, in: hotkeys)
        .disabled(lifecycle.isLocked || (hotkeyDispatcher.map { !$0.canPerform(HotkeyID.commandBar) } ?? false))
        Button(String(localized: "Minimize to Menu Bar")) {
            if let hotkeyDispatcher {
                _ = hotkeyDispatcher.perform("Minimize To Menu Bar")
            } else {
                menuCoordinator.minimizeToMenuBar()
            }
        }
        .registryShortcut("Minimize To Menu Bar", in: hotkeys)
        .disabled(lifecycle.isLocked || (hotkeyDispatcher.map { !$0.canPerform("Minimize To Menu Bar") } ?? false))
        Button(lifecycle.isLocked ? String(localized: "Unlock Courier…") : String(localized: "Lock App")) {
            if lifecycle.isLocked {
                openCourier()
            }
            Task { await menuCoordinator.lockOrUnlockApp() }
        }
        Divider()
        // Quit goes through the app's quit path, which stops the engine and then exits.
        Button(String(localized: "Quit Courier")) {
            if let hotkeyDispatcher {
                _ = hotkeyDispatcher.perform("Quit App")
            } else {
                menuCoordinator.quitApp()
            }
        }
        .registryShortcut("Quit App", in: hotkeys)
        .disabled(lifecycle.isLocked || (hotkeyDispatcher.map { !$0.canPerform("Quit App") } ?? false))
    }

    private func openChat(_ roomID: String) {
        Task {
            _ = await menuCoordinator.openChatFromExternalMenu(roomID)
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
    private var openChatWindow: ((String) -> Void)?

    func register(
        _ open: @escaping () -> Void,
        openChatWindow: @escaping (String) -> Void = { _ in }
    ) {
        self.open = open
        self.openChatWindow = openChatWindow
    }

    func show() {
        NSApp.activate()
        // openWindow brings the window forward if it is open, and makes it again if the person closed it.
        open?()
    }

    func openChatInfo(_ roomID: String) {
        NSApp.activate()
        openChatWindow?(roomID)
    }
}

/// Hands the opener the window scene's `openWindow`.
struct OpenWindowRegistrar: View {
    let opener: MainWindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                opener.register(
                    { openWindow(id: "main") },
                    openChatWindow: { roomID in openWindow(id: WindowID.chatInfo, value: roomID) }
                )
            }
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

/// `File ▸ Open…` (`menu:File Open…`, `⌘O`) command item opening the file picker to attach files to the active composer.
struct FileOpenCommandItem: View {
    let composer: ComposerModel
    var hotkeys: HotkeyRegistry = HotkeyRegistry()
    var hotkeyDispatcher: HotkeyDispatcher? = nil
    let isDisabled: Bool

    var body: some View {
        Button(String(localized: "Open…")) {
            if let hotkeyDispatcher {
                _ = hotkeyDispatcher.perform("Chat: Send File")
            } else {
                AttachmentPicker.run(into: composer)
            }
        }
        .registryShortcut("Chat: Send File", in: hotkeys)
        .disabled(isDisabled || (hotkeyDispatcher.map { !$0.canPerform("Chat: Send File") } ?? false))
    }
}
