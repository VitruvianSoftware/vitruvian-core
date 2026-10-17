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
                       login: delegate.login)
                .background(OpenWindowRegistrar(opener: delegate.windowOpener))
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            InboxCommands(inbox: delegate.inbox, login: delegate.login)
            ConversationCommands(conversation: delegate.conversation)
        }

        // The menu-bar icon. Closing the window leaves Courier running (spec §2), and this is how to get it back.
        MenuBarExtra {
            MenuBarMenu(inbox: delegate.inbox, openCourier: delegate.windowOpener.show)
        } label: {
            MenuBarIcon(inbox: delegate.inbox)
        }
    }
}
