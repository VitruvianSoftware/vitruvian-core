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
                       focus: delegate.messageFocus, detachedWindows: delegate.detachedWindows,
                       hotkeys: delegate.hotkeys,
                       hotkeyDispatcher: delegate.hotkeyDispatcher,
                       commandBar: delegate.commandBar,
                       appearance: delegate.appearance,
                       onOpenShortcutsSettings: {
                           delegate.settingsNavigation.openPane(.hotkeys)
                           delegate.menuCoordinator.openSettings(.shortcuts)
                       })
                .background(OpenWindowRegistrar(opener: delegate.windowOpener))
        }
        .defaultSize(width: 1020, height: 660)
        .commands {
            InboxCommands(inbox: delegate.inbox, login: delegate.login, spaces: delegate.spaces,
                          preferences: delegate.inbox.preferences, ui: delegate.inboxUI, search: delegate.search,
                          conversation: delegate.conversation, lifecycle: delegate.lifecycle,
                          menuCoordinator: delegate.menuCoordinator,
                          minimizeToMenuBar: delegate.minimizeToMenuBar,
                          hotkeys: delegate.hotkeys,
                          hotkeyDispatcher: delegate.hotkeyDispatcher)
            ConversationCommands(conversation: delegate.conversation, chatComposer: delegate.conversation.composer,
                                 paneComposer: delegate.conversation.thread.composer,
                                 messageActions: delegate.messageActions, focus: delegate.messageFocus,
                                 hotkeys: delegate.hotkeys,
                                 hotkeyDispatcher: delegate.hotkeyDispatcher,
                                 lifecycle: delegate.lifecycle)
        }

        // The windows the space bar, the menus and the chat menu open.
        Window(String(localized: "Edit Spaces"), id: WindowID.editSpaces) {
            LockableWindowContent(lifecycle: delegate.lifecycle) {
                EditSpacesWindow(spaces: delegate.spaces, inbox: delegate.inbox)
            }
        }
        .defaultSize(width: 360, height: 520)
        .windowResizability(.contentMinSize)

        WindowGroup(String(localized: "Label"), id: WindowID.label, for: LabelWindowTarget.self) { $target in
            if let target {
                LockableWindowContent(lifecycle: delegate.lifecycle) {
                    LabelEditorWindow(target: target, labels: delegate.labels, spaces: delegate.spaces,
                                      inbox: delegate.inbox)
                }
            }
        }
        .windowResizability(.contentSize)

        Window(String(localized: "Edit Labels"), id: WindowID.editLabels) {
            LockableWindowContent(lifecycle: delegate.lifecycle) {
                EditLabelsWindow(spaces: delegate.spaces, labels: delegate.labels)
            }
        }
        .defaultSize(width: 420, height: 360)

        WindowGroup(String(localized: "Auto-archive"), id: WindowID.autoArchive, for: String.self) { $spaceID in
            if let spaceID {
                LockableWindowContent(lifecycle: delegate.lifecycle) {
                    AutoArchiveWindow(spaceID: spaceID, spaces: delegate.spaces, labels: delegate.labels,
                                      inbox: delegate.inbox)
                }
            }
        }
        .windowResizability(.contentSize)

        WindowGroup(String(localized: "Chat Info"), id: WindowID.chatInfo, for: String.self) { $roomID in
            if let roomID {
                LockableWindowContent(lifecycle: delegate.lifecycle) {
                    ChatInfoWindow(roomID: roomID, conversation: delegate.conversation)
                }
            }
        }
        .defaultSize(width: 340, height: 620)
        .windowResizability(.contentMinSize)

        WindowGroup(String(localized: "Media Viewer"), id: WindowID.mediaViewer, for: MediaViewerTarget.self) { $target in
            LockableWindowContent(lifecycle: delegate.lifecycle) {
                MediaViewerWindow(
                    target: target ?? MediaViewerTarget(roomID: delegate.model.selectedRoomID, tab: .media),
                    appModel: delegate.model,
                    conversation: delegate.conversation,
                    preferences: delegate.composerPreferences
                )
            }
        }
        .defaultSize(width: 780, height: 560)
        .windowResizability(.contentMinSize)

        Settings {
            LockableWindowContent(lifecycle: delegate.lifecycle) {
                SettingsView(
                    appModel: delegate.model,
                    inbox: delegate.inbox,
                    spaces: delegate.spaces,
                    labels: delegate.labels,
                    conversation: delegate.conversation,
                    composerPreferences: delegate.composerPreferences,
                    quickReplies: delegate.quickReplies,
                    hotkeys: delegate.hotkeys,
                    lifecycle: delegate.lifecycle,
                    navigation: delegate.settingsNavigation,
                    notificationPreferences: delegate.notificationPreferences,
                    dockPreferences: delegate.dockPreferences,
                    accountsAndBridges: delegate.accountsAndBridges,
                    loginFlow: delegate.login,
                    problemReport: delegate.problemReport,
                    onRestartNotificationCenter: {
                        delegate.notifier.restartNotificationCenter()
                    }
                )
            }
        }
        .defaultSize(width: 820, height: 600)

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
                        hotkeys: delegate.hotkeys,
                        hotkeyDispatcher: delegate.hotkeyDispatcher,
                        openCourier: delegate.windowOpener.show)
        } label: {
            MenuBarIcon(spaces: delegate.spaces, dockPreferences: delegate.dockPreferences,
                        lifecycle: delegate.lifecycle)
        }
    }
}
