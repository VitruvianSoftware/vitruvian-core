// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Courier", id: "main") {
            MainWindow(model: delegate.model, inbox: delegate.inbox, conversation: delegate.conversation)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            InboxCommands(inbox: delegate.inbox)
            ConversationCommands(conversation: delegate.conversation)
        }
    }
}
