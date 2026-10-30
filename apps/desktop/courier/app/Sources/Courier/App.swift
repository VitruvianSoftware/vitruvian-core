// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Courier", id: "main") {
            MainWindow(model: delegate.model, inbox: delegate.inbox, conversation: delegate.conversation,
                       login: delegate.login, spaces: delegate.spaces, preferences: delegate.inbox.preferences,
                       ui: delegate.inboxUI, search: delegate.search, lifecycle: delegate.lifecycle,
                       labels: delegate.labels, messageActions: delegate.messageActions,
                       scheduled: delegate.scheduled, composerPreferences: delegate.composerPreferences,
                       focus: delegate.messageFocus, detachedWindows: delegate.detachedWindows)
                .background(OpenWindowRegistrar(opener: delegate.windowOpener))
        }
        .defaultSize(width: 1020, height: 660)
        .commands {
            InboxCommands(inbox: delegate.inbox, login: delegate.login, spaces: delegate.spaces,
                          preferences: delegate.inbox.preferences, ui: delegate.inboxUI, search: delegate.search,
                          conversation: delegate.conversation, lifecycle: delegate.lifecycle,
                          menuCoordinator: delegate.menuCoordinator,
                          minimizeToMenuBar: delegate.minimizeToMenuBar)
            ConversationCommands(conversation: delegate.conversation, chatComposer: delegate.conversation.composer,
                                 paneComposer: delegate.conversation.thread.composer,
                                 messageActions: delegate.messageActions, focus: delegate.messageFocus)
        }

        // The windows the space bar, the menus and the chat menu open.
        Window(String(localized: "Edit Spaces"), id: WindowID.editSpaces) {
            EditSpacesWindow(spaces: delegate.spaces, inbox: delegate.inbox)
                .overlay {
                    if delegate.lifecycle.isLocked {
                        AppLockOverlay(model: delegate.lifecycle)
                    }
                }
        }
        .defaultSize(width: 360, height: 520)
        .windowResizability(.contentMinSize)

        WindowGroup(String(localized: "Label"), id: WindowID.label, for: LabelWindowTarget.self) { $target in
            if let target {
                LabelEditorWindow(target: target, labels: delegate.labels, spaces: delegate.spaces,
                                  inbox: delegate.inbox)
                    .overlay {
                        if delegate.lifecycle.isLocked {
                            AppLockOverlay(model: delegate.lifecycle)
                        }
                    }
            }
        }
        .windowResizability(.contentSize)

        Window(String(localized: "Edit Labels"), id: WindowID.editLabels) {
            EditLabelsWindow(spaces: delegate.spaces, labels: delegate.labels)
                .overlay {
                    if delegate.lifecycle.isLocked {
                        AppLockOverlay(model: delegate.lifecycle)
                    }
                }
        }
        .defaultSize(width: 420, height: 360)

        WindowGroup(String(localized: "Auto-archive"), id: WindowID.autoArchive, for: String.self) { $spaceID in
            if let spaceID {
                AutoArchiveWindow(spaceID: spaceID, spaces: delegate.spaces, labels: delegate.labels,
                                  inbox: delegate.inbox)
                    .overlay {
                        if delegate.lifecycle.isLocked {
                            AppLockOverlay(model: delegate.lifecycle)
                        }
                    }
            }
        }
        .windowResizability(.contentSize)

        WindowGroup(String(localized: "Chat Info"), id: WindowID.chatInfo, for: String.self) { $roomID in
            if let roomID {
                ChatInfoWindow(roomID: roomID, conversation: delegate.conversation)
                    .overlay {
                        if delegate.lifecycle.isLocked {
                            AppLockOverlay(model: delegate.lifecycle)
                        }
                    }
            }
        }
        .defaultSize(width: 340, height: 620)
        .windowResizability(.contentMinSize)

        WindowGroup(String(localized: "Media Viewer"), id: WindowID.mediaViewer, for: MediaViewerTarget.self) { $target in
            MediaViewerWindow(
                target: target ?? MediaViewerTarget(roomID: delegate.model.selectedRoomID, tab: .media),
                appModel: delegate.model,
                conversation: delegate.conversation,
                preferences: delegate.composerPreferences
            )
            .overlay {
                if delegate.lifecycle.isLocked {
                    AppLockOverlay(model: delegate.lifecycle)
                }
            }
        }
        .defaultSize(width: 780, height: 560)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(inbox: delegate.inbox, labels: delegate.labels, conversation: delegate.conversation,
                         composerPreferences: delegate.composerPreferences,
                         quickReplies: delegate.quickReplies)
                .overlay {
                    if delegate.lifecycle.isLocked {
                        AppLockOverlay(model: delegate.lifecycle)
                    }
                }
        }

        // The menu-bar icon. Closing the window leaves Courier running (spec §2), and this is how to get it back.
        MenuBarExtra(
            isInserted: Binding(
                get: { delegate.dockPreferences.showMenuBarIcon },
                set: { delegate.dockPreferences.showMenuBarIcon = $0 }
            )
        ) {
            MenuBarMenu(spaces: delegate.spaces, inbox: delegate.inbox, model: delegate.model,
                        lifecycle: delegate.lifecycle, dockPreferences: delegate.dockPreferences,
                        menuCoordinator: delegate.menuCoordinator,
                        openCourier: delegate.windowOpener.show)
        } label: {
            MenuBarIcon(spaces: delegate.spaces, dockPreferences: delegate.dockPreferences,
                        lifecycle: delegate.lifecycle)
        }
    }
}
