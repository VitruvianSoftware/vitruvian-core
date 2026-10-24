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
                       ui: delegate.inboxUI, search: delegate.search, labels: delegate.labels,
                       messageActions: delegate.messageActions, scheduled: delegate.scheduled,
                       composerPreferences: delegate.composerPreferences, focus: delegate.messageFocus)
                .background(OpenWindowRegistrar(opener: delegate.windowOpener))
        }
        .defaultSize(width: 1020, height: 660)
        .commands {
            InboxCommands(inbox: delegate.inbox, login: delegate.login, spaces: delegate.spaces,
                          preferences: delegate.inbox.preferences, ui: delegate.inboxUI, search: delegate.search,
                          conversation: delegate.conversation)
            ConversationCommands(conversation: delegate.conversation, chatComposer: delegate.conversation.composer,
                                 paneComposer: delegate.conversation.thread.composer,
                                 messageActions: delegate.messageActions, focus: delegate.messageFocus)
        }

        // The windows the space bar, the menus and the chat menu open.
        Window(String(localized: "Edit Spaces"), id: WindowID.editSpaces) {
            EditSpacesWindow(spaces: delegate.spaces, inbox: delegate.inbox)
        }
        .defaultSize(width: 360, height: 520)
        .windowResizability(.contentMinSize)

        WindowGroup(String(localized: "Label"), id: WindowID.label, for: LabelWindowTarget.self) { $target in
            if let target {
                LabelEditorWindow(target: target, labels: delegate.labels, spaces: delegate.spaces,
                                  inbox: delegate.inbox)
            }
        }
        .windowResizability(.contentSize)

        Window(String(localized: "Edit Labels"), id: WindowID.editLabels) {
            EditLabelsWindow(spaces: delegate.spaces, labels: delegate.labels)
        }
        .defaultSize(width: 420, height: 360)

        WindowGroup(String(localized: "Auto-archive"), id: WindowID.autoArchive, for: String.self) { $spaceID in
            if let spaceID {
                AutoArchiveWindow(spaceID: spaceID, spaces: delegate.spaces, labels: delegate.labels,
                                  inbox: delegate.inbox)
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(inbox: delegate.inbox, labels: delegate.labels, conversation: delegate.conversation,
                         composerPreferences: delegate.composerPreferences,
                         quickReplies: delegate.quickReplies)
        }

        // The menu-bar icon. Closing the window leaves Courier running (spec §2), and this is how to get it back.
        MenuBarExtra {
            MenuBarMenu(spaces: delegate.spaces, openCourier: delegate.windowOpener.show)
        } label: {
            MenuBarIcon(spaces: delegate.spaces)
        }
    }
}
