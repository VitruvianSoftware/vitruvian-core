// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import CourierCore
import SwiftUI

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
