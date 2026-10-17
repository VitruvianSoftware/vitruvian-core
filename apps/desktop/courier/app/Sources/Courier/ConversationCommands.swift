// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The Message menu: the keys that work in an open chat, even while typing (⌘↓ jumps to the newest message
/// from the box too).
struct ConversationCommands: Commands {
    @ObservedObject var conversation: ConversationModel

    var body: some Commands {
        CommandMenu(String(localized: "Message")) {
            Button(String(localized: "Reply")) { conversation.replyToSelected() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(conversation.selectedMessageID == nil)
            Button(String(localized: "Attach Files…")) { AttachmentPicker.run(into: conversation.composer) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(conversation.roomID == nil)
            Divider()
            Button(String(localized: "Jump to Newest Message")) { conversation.jumpToBottom() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(conversation.roomID == nil)
        }
    }
}
