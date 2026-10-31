// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
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
    /// Turns Incognito on and off (`setIncognito`), which asks whether to also hide typing (the app asks it, for
    /// every way Incognito is turned on: `HideTypingQuestion`); never the preference itself, which would skip the
    /// question.
    let conversation: ConversationModel
    var voiceRecorder: VoiceRecorderModel? = nil
    @State private var selectedReply: QuickReply.ID?

    private var activeVoiceRecorder: VoiceRecorderModel {
        voiceRecorder ?? conversation.composer.voiceRecorder
    }

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
                Toggle(String(localized: "Show chat updates in timeline"), isOn: $preferences.showChatUpdatesInTimeline)
                Toggle(
                    String(localized: "Disable link previews in outgoing messages"),
                    isOn: $preferences.disableOutgoingLinkPreviews
                )
                Toggle(
                    String(localized: "Load external embeds automatically"),
                    isOn: $preferences.loadExternalEmbedsAutomatically
                )
                Toggle(
                    String(localized: "Automatically play the next voice note"),
                    isOn: $preferences.autoPlayNextVoiceNote
                )
                MicrophoneDevicePicker(
                    preferences: preferences,
                    voiceRecorder: activeVoiceRecorder
                )
            }
            downloads
            replies
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
        .sheet(item: $quickReplies.editing) { edit in QuickReplyEditor(edit: edit, quickReplies: quickReplies) }
    }

    // MARK: Downloads

    private var downloads: some View {
        Section(String(localized: "Downloads")) {
            LabeledContent(String(localized: "Downloads location")) {
                HStack(spacing: 8) {
                    Text((preferences.downloadsDirectoryPath as NSString).abbreviatingWithTildeInPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(String(localized: "Choose…")) {
                        chooseDownloadsDirectory()
                    }
                }
            }
            Toggle(
                String(localized: "Always ask where to save files before downloading"),
                isOn: $preferences.alwaysAskWhereToSaveFiles
            )
        }
    }

    private func chooseDownloadsDirectory() {
        let current = (preferences.downloadsDirectoryPath as NSString).expandingTildeInPath
        guard let url = AppLockGate.shared.runOpenPanel(action: .settingsChange, configure: { panel in
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
            panel.prompt = String(localized: "Choose")
            panel.message = String(localized: "Choose a folder for downloaded attachments")
        })?.first else { return }
        preferences.downloadsDirectoryPath = url.path
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
            Toggle(String(localized: "Enable emoji autocomplete"), isOn: $preferences.enableEmojiAutocomplete)
                .accessibilityIdentifier("settings.composing.enableEmojiAutocomplete")
            Toggle(
                String(localized: "Disable automatic replacement of emoticons with emojis"),
                isOn: $preferences.disableEmoticonReplacement
            )
            .accessibilityIdentifier("settings.composing.disableEmoticonReplacement")
            Toggle(
                String(localized: "Automatically send GIFs after selection"),
                isOn: $preferences.autoSendGIFs
            )
            .accessibilityIdentifier("settings.composing.autoSendGIFs")
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
                Button(String(localized: "Add…")) { quickReplies.editing = QuickReplyEdit(reply: nil) }
                    .disabled(quickReplies.all.count >= QuickReplies.maxCount)
                Button(String(localized: "Edit…")) {
                    if let reply = quickReplies.all.first(where: { $0.id == selectedReply }) {
                        quickReplies.editing = QuickReplyEdit(reply: reply)
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

private struct MicrophoneDevicePicker: View {
    @ObservedObject var preferences: ComposerPreferences
    @ObservedObject var voiceRecorder: VoiceRecorderModel

    var body: some View {
        Picker(String(localized: "Microphone"), selection: $preferences.preferredMicrophoneUID) {
            Text(String(localized: "System Default")).tag("")
            ForEach(voiceRecorder.availableDevices) { device in
                Text(device.name).tag(device.uid)
            }
            if !preferences.preferredMicrophoneUID.isEmpty,
               !voiceRecorder.availableDevices.contains(where: { $0.uid == preferences.preferredMicrophoneUID }) {
                Text(preferences.preferredMicrophoneUID).tag(preferences.preferredMicrophoneUID)
            }
        }
        .help(String(localized: "The microphone used when recording voice notes (⌘⇧A)."))
    }
}
