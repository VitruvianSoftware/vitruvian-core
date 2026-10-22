// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The Message menu: the keys that work in an open chat, even while typing (Task 12's table). Each acts on the
/// selected message: the chat's, or after a click in the thread pane, the pane's, from the pane (`from: .thread`).
/// ⌘↓ is Show Replies on a selected thread root and otherwise jumps to the newest message. ⌘Z and ⌘⇧Z are in the Edit
/// menu (InboxCommands); the formatting keys are the composer's own (ComposerTextView).
struct ConversationCommands: Commands {
    @ObservedObject var conversation: ConversationModel
    let messageActions: MessageActionsModel
    @ObservedObject var focus: MessageFocus

    var body: some Commands {
        CommandMenu(String(localized: "Message")) {
            Button(String(localized: "Edit…"), action: edit)
                .keyboardShortcut("t", modifiers: .command)
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Reply")) { act(.reply) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selected == nil)
            Button(showsReplies ? String(localized: "Show Replies") : String(localized: "Jump to Newest Message")) {
                conversation.showRepliesOrJumpToBottom()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(conversation.roomID == nil)
            Button(String(localized: "Quick React")) { quickReact() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(selected == nil)
            Button(String(localized: "Forward…"), action: forward)
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Open First Link"), action: openLink)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(selected == nil)
            Divider()
            Button(String(localized: "Send Later…"), action: messageActions.requestSendLater)
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Send Message and Archive")) {
                (focus.inPane ? conversation.thread.composer : conversation.composer).submit(archive: true)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(conversation.roomID == nil)
            Button(String(localized: "Create Quick Reply from Draft…"), action: messageActions.requestQuickReplyFromDraft)
                .disabled(!messageActions.canCreateQuickReply)
            Divider()
            Button(String(localized: "Attach Files…")) { AttachmentPicker.run(into: conversation.composer) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(conversation.roomID == nil)
        }
    }

    /// The message the keys act on, and where it was selected.
    private var selected: (id: String, source: MessageSource)? {
        if focus.inPane, let id = focus.paneSelection { return (id, .thread) }
        return conversation.selectedMessageID.map { ($0, .chat) }
    }

    private var showsReplies: Bool {
        conversation.selectedMessage?.thread != nil && !focus.inPane
    }

    private func message(_ id: String) -> TimelineMessage? {
        for case let .message(message) in conversation.items + conversation.thread.items where message.id == id {
            return message
        }
        return nil
    }

    private func offers(_ action: MessageAction) -> Bool {
        guard let selected, let message = message(selected.id) else { return false }
        return conversation.availableActions(for: message).actions.contains(action)
    }

    /// ⌘T: the selected message, or my last one the chat still lets me edit.
    private func edit() {
        if let selected, selected.source == .thread {
            Task { await messageActions.perform(.edit, on: selected.id, from: .thread) }
        } else {
            conversation.editSelectedOrLast()
        }
    }

    /// ⌘R: Reply, or where replies are thread replies, Reply in Thread.
    private func act(_ action: MessageAction) {
        guard let selected else { return }
        let chosen = action == .reply && !offers(.reply) && offers(.replyInThread) ? MessageAction.replyInThread : action
        Task { await messageActions.perform(chosen, on: selected.id, from: selected.source) }
    }

    /// ⌘⇧R: the quick reaction (Settings ▸ Messages).
    private func quickReact() {
        guard let selected else { return }
        if selected.source == .chat {
            Task { await conversation.quickReactToSelected() }
        } else if offers(.react) {
            let key = conversation.preferences?.quickReaction ?? "❤️"
            Task { await conversation.react(to: selected.id, key: key) }
        }
    }

    /// ⌘⇧F: the forward picker, or "Select a message to forward".
    private func forward() {
        if let selected, selected.source == .thread {
            Task { await messageActions.perform(.forward, on: selected.id, from: .thread) }
        } else {
            messageActions.forwardSelected()
        }
    }

    /// ⌘⇧H: the selected message's first link, in the browser.
    private func openLink() {
        guard let selected else { return }
        Task { await messageActions.perform(.openFirstLink, on: selected.id, from: selected.source) }
    }
}
