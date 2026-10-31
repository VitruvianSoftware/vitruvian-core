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
    @ObservedObject var hotkeys: HotkeyRegistry
    @ObservedObject var hotkeyDispatcher: HotkeyDispatcher
    @ObservedObject var lifecycle: SystemLifecycleModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            FileOpenCommandItem(
                composer: composer,
                hotkeys: hotkeys,
                hotkeyDispatcher: hotkeyDispatcher,
                isDisabled: !hotkeyDispatcher.canPerform("Chat: Send File")
            )
        }
        CommandMenu(String(localized: "Message")) {
            Button(String(localized: "Edit…")) {
                _ = hotkeyDispatcher.perform("Message: Edit")
            }
            .registryShortcut("Message: Edit", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Edit"))
            Button(String(localized: "Reply")) {
                _ = hotkeyDispatcher.perform("Message: Quote & Reply")
            }
            .registryShortcut("Message: Quote & Reply", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Quote & Reply"))
            // The title and the action follow the same selection: Show Replies on a thread root selected in the
            // chat, otherwise the newest message.
            let showRepliesOrScrollID = showRepliesOrScrollCommandID
            Button(showRepliesOrJumpMenuTitle) {
                _ = hotkeyDispatcher.perform(showRepliesOrScrollID)
            }
            .registryShortcut(showRepliesOrScrollID, in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform(showRepliesOrScrollID))
            Button(String(localized: "Quick React")) {
                _ = hotkeyDispatcher.perform("Message: Quick React")
            }
            .registryShortcut("Message: Quick React", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Quick React"))
            Button(String(localized: "Forward…")) {
                _ = hotkeyDispatcher.perform("Message: Forward")
            }
            .registryShortcut("Message: Forward", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Forward"))
            Button(String(localized: "Open First Link")) {
                _ = hotkeyDispatcher.perform("Message: Open First Link")
            }
            .registryShortcut("Message: Open First Link", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Open First Link"))
            Divider()
            Button(String(localized: "Send Later…")) {
                _ = hotkeyDispatcher.perform("Message: Send Later")
            }
            .registryShortcut("Message: Send Later", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Send Later"))
            Button(String(localized: "Send Message and Archive")) {
                _ = hotkeyDispatcher.perform("Message: Send Message and Archive")
            }
            .registryShortcut("Message: Send Message and Archive", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Send Message and Archive"))
            Button(String(localized: "Create Quick Reply from Draft…"), action: messageActions.requestQuickReplyFromDraft)
                .disabled(!messageActions.canCreateQuickReply || lifecycle.isLocked)
            Divider()
            formatting
                .disabled(lifecycle.isLocked)
            Divider()
            Button(String(localized: "Attach Files…")) {
                _ = hotkeyDispatcher.perform("Chat: Send File")
            }
            .registryShortcut("Chat: Send File", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Chat: Send File"))
            Button(String(localized: "Download Attachments")) {
                _ = hotkeyDispatcher.perform("Download Attachments")
            }
            .registryShortcut("Download Attachments", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Download Attachments"))
            Button(String(localized: "Record Voice Note")) {
                _ = hotkeyDispatcher.perform("Message: Record Audio")
            }
            .registryShortcut("Message: Record Audio", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Record Audio"))
            Button(sendGIFMenuTitle) {
                _ = hotkeyDispatcher.perform("Message: Send GIF")
            }
            .registryShortcut("Message: Send GIF", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Send GIF"))
            Button(sendStickerMenuTitle) {
                _ = hotkeyDispatcher.perform("Message: Send Sticker")
            }
            .registryShortcut("Message: Send Sticker", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Message: Send Sticker"))
            Divider()
            Button(chatInfoMenuTitle) {
                _ = hotkeyDispatcher.perform("Toggle Chat Info")
            }
            .registryShortcut("Toggle Chat Info", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Toggle Chat Info"))
            Button(calendarMenuTitle,
                   action: conversation.toggleCalendar)
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(lifecycle.isLocked)
            Button(String(localized: "Show Sender Profile")) {
                _ = hotkeyDispatcher.perform("Open User Profile")
            }
            .registryShortcut("Open User Profile", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Open User Profile"))
            Button(String(localized: "Delete Chat…")) {
                _ = hotkeyDispatcher.perform("Chat: Delete")
            }
            .registryShortcut("Chat: Delete", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Chat: Delete"))
        }
    }

    var showRepliesOrScrollCommandID: String {
        guard !lifecycle.isLocked else { return "Scroll to the bottom of a chat" }
        return hotkeyDispatcher.showRepliesTarget == nil
            ? "Scroll to the bottom of a chat"
            : "Show Replies"
    }

    var showRepliesOrJumpMenuTitle: String {
        guard !lifecycle.isLocked else { return String(localized: "Jump to Newest Message") }
        return hotkeyDispatcher.showRepliesTarget == nil
            ? String(localized: "Jump to Newest Message")
            : String(localized: "Show Replies")
    }

    var sendGIFMenuTitle: String {
        guard !lifecycle.isLocked else { return String(localized: "Send GIF…") }
        return composer.sendGIFMenuTitle
    }

    var sendStickerMenuTitle: String {
        guard !lifecycle.isLocked else { return String(localized: "Send Sticker…") }
        return composer.sendStickerMenuTitle
    }

    var chatInfoMenuTitle: String {
        guard !lifecycle.isLocked else { return String(localized: "Show Chat Info") }
        return conversation.isShowingChatInfo ? String(localized: "Hide Chat Info") : String(localized: "Show Chat Info")
    }

    var calendarMenuTitle: String {
        guard !lifecycle.isLocked else { return String(localized: "Show Calendar") }
        return conversation.isShowingCalendar ? String(localized: "Hide Calendar") : String(localized: "Show Calendar")
    }

    /// The composer the keys type into: the thread pane's after a click there, else the chat's.
    private var composer: ComposerModel {
        hotkeyDispatcher.activeComposer
    }

    /// Format ▸ the formatting keys, on the selection of the composer whose text view has the keyboard in the key
    /// window, and off otherwise: never on a composer's old selection from another window or field. (The text view
    /// takes the keys itself first; these are for the menu.) A kind the chat doesn't keep says why, as the bar does.
    private var formatting: some View {
        let typing = [chatComposer, paneComposer].first { $0.hasKeyboard }
        return Menu(String(localized: "Format")) {
            ForEach(FormattingBar.order, id: \.self) { kind in
                Button(FormattingBar.title(of: kind) + (kind == .link ? "…" : "")) {
                    guard !lifecycle.isLocked, let typing, typing.hasKeyboard else { return }
                    typing.formattingKey(kind, in: typing.selection)
                }
                .modifier(FormatShortcut(kind: kind))
                .disabled(typing == nil || lifecycle.isLocked)
            }
        }
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
