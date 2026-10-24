// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Settings ▸ Messages (inventory 02 §1.2): the composer's settings, one row each, then privacy (Incognito, typing),
/// then the quick replies. These are this Mac's settings: the one shared `ComposerPreferences` and `QuickReplies` the
/// composers read, so a change holds at once. Undo send, send later and Incognito need a plan; without one their
/// rows say so.
struct MessagesSettingsPane: View {
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var quickReplies: QuickReplies
    let isEntitled: (Feature) -> Bool
    /// Turns Incognito on and off (`setIncognito`), which asks whether to also hide typing; never the preference
    /// itself, which would skip the question.
    let conversation: ConversationModel
    @State private var selectedReply: QuickReply.ID?
    @State private var editing: QuickReplyEdit?
    /// Turning Incognito on asked "Also hide that you're typing?" (`ConversationModel.asksToHideTyping`).
    @State private var asksToHideTyping = false

    var body: some View {
        Form {
            sending
            composing
            privacy
            Section(String(localized: "Messages")) {
                Picker(String(localized: "On double-clicking a message"), selection: $preferences.doubleClickMessage) {
                    Text(String(localized: "Reply")).tag(MessageDoubleClickAction.reply)
                    Text(String(localized: "React with \(preferences.quickReaction)")).tag(MessageDoubleClickAction.reactWith)
                    Text(String(localized: "Show the reaction picker")).tag(MessageDoubleClickAction.reactionPicker)
                    Text(String(localized: "Forward")).tag(MessageDoubleClickAction.forward)
                    Text(String(localized: "Show the menu")).tag(MessageDoubleClickAction.menu)
                    Text(String(localized: "Do nothing")).tag(MessageDoubleClickAction.nothing)
                }
                Picker(String(localized: "Quick reaction emoji"), selection: $preferences.quickReaction) {
                    ForEach(ConversationModel.quickReactions, id: \.self) { Text($0).tag($0) }
                    if !ConversationModel.quickReactions.contains(preferences.quickReaction) {
                        Text(preferences.quickReaction).tag(preferences.quickReaction)
                    }
                }
                .help(String(localized: "⌘⇧R reacts with it to the selected message."))
                Toggle(String(localized: "Include timestamps when copying messages with ⌘C"),
                       isOn: $preferences.copyWithTimestamps)
                Toggle(String(localized: "Hide deleted messages"), isOn: $preferences.hideDeletedMessages)
                    .help(String(localized: "Off, a deleted message leaves a line saying it was deleted."))
            }
            replies
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
        .sheet(item: $editing) { edit in QuickReplyEditor(edit: edit, quickReplies: quickReplies) }
        .onReceive(conversation.$asksToHideTyping) { asksToHideTyping = $0 }
        .alert(ConversationModel.hideTypingQuestion, isPresented: $asksToHideTyping) {
            Button(ConversationModel.hideTypingButton) { conversation.answerHideTyping(true) }
            Button(ConversationModel.keepShowingTypingButton, role: .cancel) { conversation.answerHideTyping(false) }
        }
    }

    // MARK: Privacy

    /// Incognito (02 §1.2), who sees my typing, and the composer's mark. Incognito reads "Available with a plan"
    /// without one; the mark's row is greyed while Incognito is off.
    private var privacy: some View {
        Section(String(localized: "Privacy")) {
            if isEntitled(.incognito) {
                Toggle(String(localized: "Incognito mode"), isOn: Binding(
                    get: { preferences.incognito }, set: { conversation.setIncognito($0) }))
                    .help(String(localized: "Chats stay unread when you open them, and no one is told you read their messages, until you reply or mark the chat read (⌘⇧U)."))
            } else {
                LabeledContent(String(localized: "Incognito mode"), value: String(localized: "Available with a plan"))
            }
            Toggle(String(localized: "Show recipients I’m typing"), isOn: $preferences.showTyping)
                .help(String(localized: "Networks that show typing are told while you write."))
            Toggle(String(localized: "Show the incognito mark in the message box"), isOn: $preferences.showIncognitoMark)
                .disabled(!(isEntitled(.incognito) && preferences.incognito))
        }
    }

    // MARK: Sending

    private var sending: some View {
        Section(String(localized: "Sending")) {
            if isEntitled(.undoSend) {
                Picker(String(localized: "Allow undo send (⌘Z) for"), selection: $preferences.undoSendMillis) {
                    ForEach(ComposerPreferences.undoSendValues, id: \.self) { Text(Self.undoTitle($0)).tag($0) }
                }
                .help(String(localized: "Each message waits this long before it goes, so ⌘Z can take it back."))
            } else {
                LabeledContent(String(localized: "Allow undo send (⌘Z) for"), value: String(localized: "Available with a plan"))
            }
            if isEntitled(.undoSend) {
                Toggle(String(localized: "Click pending messages to undo send"), isOn: $preferences.clickPendingToUndo)
                    .disabled(preferences.undoSendMillis == 0)
            } else {
                LabeledContent(String(localized: "Click pending messages to undo send"),
                               value: String(localized: "Available with a plan"))
            }
            if isEntitled(.sendLater) {
                Picker(String(localized: "Default for send later"), selection: $preferences.sendLaterDefault) {
                    Text(String(localized: "If no reply")).tag(SendLaterCondition.ifNoReply)
                    Text(String(localized: "Regardless")).tag(SendLaterCondition.always)
                }
                .help(String(localized: "“If no reply” doesn’t send it when someone else writes in the chat first."))
            } else {
                LabeledContent(String(localized: "Default for send later"), value: String(localized: "Available with a plan"))
            }
        }
    }

    static func undoTitle(_ millis: Int) -> String {
        switch millis {
        case 0: String(localized: "Off")
        case 750: String(localized: "0.75 seconds")
        case 1000: String(localized: "1 second")
        default: String(localized: "\(millis / 1000) seconds")
        }
    }

    // MARK: Composing

    private var composing: some View {
        Section(String(localized: "Composer")) {
            Picker(String(localized: "Press ↑ in the composer to"), selection: $preferences.upArrow) {
                Text(String(localized: "Move focus to the message list")).tag(UpArrowAction.focusMessages)
                Text(String(localized: "Edit your last message")).tag(UpArrowAction.editLast)
            }
            Toggle(String(localized: "Show formatting menu"), isOn: $preferences.showFormattingMenu)
                .help(String(localized: "A bar of formatting buttons over the text you select."))
        }
    }

    // MARK: Quick replies

    private var replies: some View {
        Section(String(localized: "Quick Replies")) {
            if quickReplies.all.isEmpty {
                Text(String(localized: "No quick replies yet."))
                    .foregroundStyle(.secondary)
            } else {
                List(quickReplies.all, selection: $selectedReply) { reply in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: ";" + reply.title)
                            .fontWeight(.medium)
                        Text(reply.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(reply.id)
                }
                .frame(minHeight: 110)
            }
            HStack {
                Button(String(localized: "Add…")) { editing = QuickReplyEdit(reply: nil) }
                    .disabled(quickReplies.all.count >= QuickReplies.maxCount)
                Button(String(localized: "Edit…")) {
                    if let reply = quickReplies.all.first(where: { $0.id == selectedReply }) {
                        editing = QuickReplyEdit(reply: reply)
                    }
                }
                .disabled(selectedReply == nil)
                Button(String(localized: "Delete")) {
                    if let id = selectedReply { quickReplies.remove(id) }
                    selectedReply = nil
                }
                .disabled(selectedReply == nil)
            }
            Text(String(localized: "Type ; and the title in a chat. {first_name}, {last_name} and {full_name} fill in the other person’s name."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A quick reply being added (nil) or changed.
struct QuickReplyEdit: Identifiable {
    let id = UUID()
    let reply: QuickReply?
}

/// Adds or changes a quick reply: its title (what follows ";") and its text.
private struct QuickReplyEditor: View {
    let edit: QuickReplyEdit
    let quickReplies: QuickReplies
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.reply == nil ? String(localized: "New Quick Reply") : String(localized: "Edit Quick Reply"))
                .font(.headline)
            TextField(String(localized: "Title"), text: $title)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            title = edit.reply?.title ?? ""
            text = edit.reply?.text ?? ""
        }
    }

    private func save() {
        do {
            if var reply = edit.reply {
                reply.title = title
                reply.text = text
                try quickReplies.update(reply)
            } else {
                try quickReplies.add(title: title, text: text)
            }
            dismiss()
        } catch let error as QuickReplyError {
            problem = MessageActionsModel.text(for: error)
        } catch {
            problem = String(localized: "That didn’t work. Try again.")
        }
    }
}
