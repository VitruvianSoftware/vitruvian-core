// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The Message menu: the keys that work in an open chat, even while typing (Task 12's table). Each acts on the
/// selected message: the chat's, or after a click in the thread pane, the pane's, from the pane (`from: .thread`).
/// ⌘↓ is Show Replies on a selected thread root and otherwise jumps to the newest message. Format lists the formatting
/// keys, which the composer's text view also takes itself while it has the keyboard. ⌘Z, ⌘⇧Z and ⌘C are in the Edit
/// menu (InboxCommands).
struct ConversationCommands: Commands {
    @ObservedObject var conversation: ConversationModel
    /// Watched for which one has the keyboard: the Format items act on that one only.
    @ObservedObject var chatComposer: ComposerModel
    @ObservedObject var paneComposer: ComposerModel
    let messageActions: MessageActionsModel
    @ObservedObject var focus: MessageFocus

    var body: some Commands {
        CommandMenu(String(localized: "Message")) {
            Button(String(localized: "Edit…"), action: edit)
                .keyboardShortcut("t", modifiers: .command)
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Reply")) { reply() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(selected == nil)
            // The title and the action follow the same selection: Show Replies on a thread root selected in the
            // chat, otherwise the newest message.
            Button(showRepliesTarget == nil ? String(localized: "Jump to Newest Message") : String(localized: "Show Replies")) {
                if let root = showRepliesTarget { conversation.openThread(root) } else { conversation.jumpToBottom() }
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
            Button(String(localized: "Send Message and Archive")) { composer.submit(archive: true) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Create Quick Reply from Draft…"), action: messageActions.requestQuickReplyFromDraft)
                .disabled(!messageActions.canCreateQuickReply)
            Divider()
            formatting
            Divider()
            Button(String(localized: "Attach Files…")) { AttachmentPicker.run(into: conversation.composer) }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(conversation.roomID == nil)
            Divider()
            Button(conversation.isShowingChatInfo ? String(localized: "Hide Chat Info") : String(localized: "Show Chat Info"),
                   action: conversation.toggleChatInfo)
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(conversation.roomID == nil)
            Button(String(localized: "Show Sender Profile")) {
                Task { await conversation.showSenderCardForSelectedMessage() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(conversation.roomID == nil)
        }
    }

    /// The composer the keys type into: the thread pane's after a click there, else the chat's.
    private var composer: ComposerModel {
        focus.inPane && conversation.thread.roomID != nil ? conversation.thread.composer : conversation.composer
    }

    /// Format ▸ the formatting keys, on the selection of the composer whose text view has the keyboard in the key
    /// window, and off otherwise: never on a composer's old selection from another window or field. (The text view
    /// takes the keys itself first; these are for the menu.) A kind the chat doesn't keep says why, as the bar does.
    private var formatting: some View {
        let typing = [chatComposer, paneComposer].first { $0.hasKeyboard }
        return Menu(String(localized: "Format")) {
            ForEach(FormattingBar.order, id: \.self) { kind in
                Button(FormattingBar.title(of: kind) + (kind == .link ? "…" : "")) {
                    guard let typing, typing.hasKeyboard else { return }
                    typing.formattingKey(kind, in: typing.selection)
                }
                .modifier(FormatShortcut(kind: kind))
                .disabled(typing == nil)
            }
        }
    }

    /// The message the keys act on, and where it was selected.
    private var selected: (id: String, source: MessageSource)? {
        focus.target(chatSelection: conversation.selectedMessageID)
    }

    /// The thread root ⌘↓ opens: the message selected in the chat, when it has replies.
    private var showRepliesTarget: String? {
        guard let selected, selected.source == .chat,
              conversation.message(selected.id, from: .chat)?.thread != nil else { return nil }
        return selected.id
    }

    private func offers(_ action: MessageAction) -> Bool {
        guard let selected, let message = conversation.message(selected.id, from: selected.source) else { return false }
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
    private func reply() {
        guard let selected, let message = conversation.message(selected.id, from: selected.source),
              let action = conversation.replyAction(for: message) else { return }
        Task { await messageActions.perform(action, on: selected.id, from: selected.source) }
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

/// The formatting keys of Task 12's table, as the Format menu shows them. None is ⌘K or ⌘F.
private struct FormatShortcut: ViewModifier {
    let kind: TextEntity.Kind

    func body(content: Content) -> some View {
        switch kind {
        case .bold: content.keyboardShortcut("b", modifiers: .command)
        case .italic: content.keyboardShortcut("i", modifiers: .command)
        case .strikethrough: content.keyboardShortcut("x", modifiers: [.command, .shift])
        case .pre: content.keyboardShortcut("c", modifiers: [.command, .option])
        case .blockquote: content.keyboardShortcut("9", modifiers: [.command, .shift])
        case .bulletList: content.keyboardShortcut("8", modifiers: [.command, .shift])
        case .orderedList: content.keyboardShortcut("7", modifiers: [.command, .shift])
        case .link: content.keyboardShortcut("k", modifiers: [.command, .shift])
        default: content // code is `, and a spoiler has no key
        }
    }
}
