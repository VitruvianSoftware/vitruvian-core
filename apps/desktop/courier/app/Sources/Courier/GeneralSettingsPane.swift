// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Highlights and anchors a setting row so `SettingsNavigationModel.jump(to:)` scrolls to and highlights the real control.
struct SettingAnchorModifier: ViewModifier {
    let settingID: String
    let highlightedSettingID: String?

    private var isHighlighted: Bool {
        highlightedSettingID == settingID
    }

    func body(content: Content) -> some View {
        content
            .id(settingID)
            .accessibilityIdentifier(settingID)
            .padding(isHighlighted ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
    }
}

extension View {
    func settingAnchor(_ id: String, highlighted: String? = nil) -> some View {
        modifier(SettingAnchorModifier(settingID: id, highlightedSettingID: highlighted))
    }
}

/// Pill badge for experimental settings (`SettingBadge.labs`).
struct SettingBadgeView: View {
    let badge: SettingBadge

    var body: some View {
        Text(badge.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            .help(badge.tooltip)
    }
}

/// Settings ▸ General pane (`GeneralSettingsPane.swift`):
/// Privacy (Incognito mode, typing indicator), Reminders + customizable Time Suggestions editor,
/// Archiving rules + bulk archive older chats, Messages & Composer defaults, Downloads,
/// Startup & Security (Login Item, Touch ID App Lock, Time Format).
struct GeneralSettingsPane: View {
    @ObservedObject var inboxPreferences: InboxPreferences
    @ObservedObject var composerPreferences: ComposerPreferences
    @ObservedObject var labels: LabelsModel
    let inbox: InboxModel
    let conversation: ConversationModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    var isEntitled: (Feature) -> Bool
    var voiceRecorder: VoiceRecorderModel? = nil
    var highlightedSettingID: String? = nil

    @State private var newSuggestionText: String = ""
    @State private var sweepReadOnly: Bool = true
    @State private var sweepDays: Int = 28
    @State private var sweepCount: Int?
    @State private var counted: Bool = false
    @State private var generalProblem: String?

    private var activeVoiceRecorder: VoiceRecorderModel {
        voiceRecorder ?? conversation.composer.voiceRecorder
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                privacySection
                remindersSection
                archivingSection
                messagesAndComposerSection
                downloadsSection
                startupAndSecuritySection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section(String(localized: "Privacy")) {
            Group {
                if isEntitled(.incognito) {
                    Toggle(
                        SettingsNavigationModel.title(for: "general.incognito"),
                        isOn: Binding(
                            get: { composerPreferences.incognito },
                            set: { conversation.setIncognito($0) }
                        )
                    )
                    .help(String(localized: "Chats stay unread when you open them, and no one is told you read their messages, until you reply or mark the chat read (⌘⇧U)."))
                } else {
                    LabeledContent(
                        SettingsNavigationModel.title(for: "general.incognito"),
                        value: String(localized: "Available with a plan")
                    )
                }
            }
            .settingAnchor("general.incognito", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.showTyping"),
                isOn: $composerPreferences.showTyping
            )
            .help(String(localized: "Networks that show typing are told while you write."))
            .settingAnchor("general.showTyping", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.showIncognitoMark"),
                isOn: $composerPreferences.showIncognitoMark
            )
            .disabled(!(isEntitled(.incognito) && composerPreferences.incognito))
            .settingAnchor("general.showIncognitoMark", highlighted: highlightedSettingID)
        }
    }

    // MARK: - Reminders & Time Suggestions

    private var remindersSection: some View {
        Section(String(localized: "Reminders")) {
            Picker(
                SettingsNavigationModel.title(for: "general.remindDefault"),
                selection: $inboxPreferences.remindDefault
            ) {
                Text(String(localized: "If no reply")).tag(RemindCondition.ifNoReply)
                Text(String(localized: "Always")).tag(RemindCondition.always)
            }
            .help(RemindHelp.condition)
            .settingAnchor("general.remindDefault", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.archiveAfterReminder"),
                isOn: $inboxPreferences.archiveAfterReminder
            )
            .help(String(localized: "The reminder brings it back to your inbox when it is due."))
            .settingAnchor("general.archiveAfterReminder", highlighted: highlightedSettingID)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(SettingsNavigationModel.title(for: "general.timeSuggestions"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(String(localized: "Reset")) {
                        inboxPreferences.resetTimeSuggestions()
                    }
                    .controlSize(.small)
                    .disabled(inboxPreferences.timeSuggestions == ReminderPresets.defaultSuggestions)
                }

                Text(String(localized: "Preset times offered in the Remind Me and Send Later menus (up to 8)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayoutTags(
                    items: inboxPreferences.timeSuggestions,
                    canRemove: inboxPreferences.timeSuggestions.count > ReminderPresets.minSuggestionsCount,
                    onRemove: { item in
                        inboxPreferences.removeTimeSuggestion(item)
                    }
                )

                HStack(spacing: 8) {
                    TextField(
                        String(localized: "Try “7am Tomorrow” or “In 3 weeks”"),
                        text: $newSuggestionText
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addSuggestion()
                    }

                    Button(String(localized: "Add")) {
                        addSuggestion()
                    }
                    .controlSize(.small)
                    .disabled(
                        newSuggestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        inboxPreferences.timeSuggestions.count >= ReminderPresets.maxSuggestionsCount
                    )
                }
            }
            .settingAnchor("general.timeSuggestions", highlighted: highlightedSettingID)
        }
    }

    private func addSuggestion() {
        if inboxPreferences.addTimeSuggestion(newSuggestionText) {
            newSuggestionText = ""
        }
    }

    // MARK: - Archiving

    private var archivingSection: some View {
        Section(String(localized: "Archiving")) {
            Toggle(
                SettingsNavigationModel.title(for: "general.markReadOnArchive"),
                isOn: $inboxPreferences.markReadOnArchive
            )
            .help(String(localized: "Your networks are told the chat was read, as when you open it."))
            .settingAnchor("general.markReadOnArchive", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "general.afterArchive"),
                selection: $inboxPreferences.afterArchive
            ) {
                afterChoices
            }
            .settingAnchor("general.afterArchive", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "general.afterToggleRead"),
                selection: $inboxPreferences.afterToggleRead
            ) {
                afterChoices
            }
            .settingAnchor("general.afterToggleRead", highlighted: highlightedSettingID)

            Group {
                if labels.canAutoArchive {
                    Picker(
                        SettingsNavigationModel.title(for: "general.autoArchive"),
                        selection: generalTrigger
                    ) {
                        Text(String(localized: "Never")).tag(AutoArchiveTrigger?.none)
                        Text(String(localized: "After I reply")).tag(AutoArchiveTrigger?.some(.afterReply))
                        Text(String(localized: "After I read them")).tag(AutoArchiveTrigger?.some(.afterRead))
                    }
                    .help(String(localized: "An archived chat comes back to your inbox when someone writes."))

                    Picker(String(localized: "Wait"), selection: generalDelay) {
                        ForEach(LabelsModel.generalDelays, id: \.self) {
                            Text(InboxSettingsPane.delay($0)).tag($0)
                        }
                    }
                    .disabled(labels.generalRule == nil)

                    if let generalProblem {
                        Text(generalProblem).foregroundStyle(.red)
                    }
                } else {
                    LabeledContent(
                        SettingsNavigationModel.title(for: "general.autoArchive"),
                        value: String(localized: "Available with a plan")
                    )
                }
            }
            .settingAnchor("general.autoArchive", highlighted: highlightedSettingID)

            VStack(alignment: .leading, spacing: 8) {
                SweepChoice(readOnly: $sweepReadOnly, days: $sweepDays)
                if counted {
                    SweepCount(count: sweepCount, rule: false) {
                        Task {
                            await Confirm.sweep(inbox, readOnly: sweepReadOnly, olderThanDays: sweepDays, space: "inbox")
                            await recount()
                        }
                    }
                }
            }
            .help(String(localized: "Archives these chats in your inbox once, now. Pinned chats stay where they are."))
            .task(id: "\(sweepReadOnly)|\(sweepDays)") { await recount() }
            .settingAnchor("general.bulkArchive", highlighted: highlightedSettingID)
        }
    }

    @ViewBuilder
    private var afterChoices: some View {
        Text(String(localized: "Open the next chat")).tag(AfterAction.selectNext)
        Text(String(localized: "Open the previous chat")).tag(AfterAction.selectPrevious)
        Text(String(localized: "Close the chat")).tag(AfterAction.closeChat)
        Text(String(localized: "Stay on it")).tag(AfterAction.nothing)
    }

    private var generalTrigger: Binding<AutoArchiveTrigger?> {
        Binding(
            get: { labels.generalRule?.trigger },
            set: { trigger in
                let minutes = labels.generalRule.map { Int($0.durationMS / 60_000) } ?? 0
                setGeneral(trigger, minutes: minutes)
            }
        )
    }

    private var generalDelay: Binding<Int> {
        Binding(
            get: { labels.generalRule.map { Int($0.durationMS / 60_000) } ?? 0 },
            set: { minutes in
                setGeneral(labels.generalRule?.trigger, minutes: minutes)
            }
        )
    }

    private func setGeneral(_ trigger: AutoArchiveTrigger?, minutes: Int) {
        generalProblem = nil
        Task {
            do {
                try await labels.setGeneral(trigger, minutes: minutes)
            } catch {
                generalProblem = EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again."))
            }
        }
    }

    private func recount() async {
        sweepCount = await inbox.archiveAllCount(readOnly: sweepReadOnly, olderThanDays: sweepDays, space: "inbox")
        counted = true
    }

    // MARK: - Messages & Composer

    private var messagesAndComposerSection: some View {
        Section(String(localized: "Messages & Composer")) {
            Picker(
                SettingsNavigationModel.title(for: "general.doubleClickMessage"),
                selection: $composerPreferences.doubleClickMessage
            ) {
                Text(String(localized: "Reply")).tag(MessageDoubleClickAction.reply)
                Text(String(localized: "React with \(composerPreferences.quickReaction)")).tag(MessageDoubleClickAction.reactWith)
                Text(String(localized: "Show the reaction picker")).tag(MessageDoubleClickAction.reactionPicker)
                Text(String(localized: "Forward")).tag(MessageDoubleClickAction.forward)
                Text(String(localized: "Show the menu")).tag(MessageDoubleClickAction.menu)
                Text(String(localized: "Do nothing")).tag(MessageDoubleClickAction.nothing)
            }
            .settingAnchor("general.doubleClickMessage", highlighted: highlightedSettingID)

            Group {
                if isEntitled(.undoSend) {
                    Picker(
                        SettingsNavigationModel.title(for: "general.undoSend"),
                        selection: $composerPreferences.undoSendMillis
                    ) {
                        ForEach(ComposerPreferences.undoSendValues, id: \.self) {
                            Text(MessagesSettingsPane.undoTitle($0)).tag($0)
                        }
                    }
                    .help(String(localized: "Each message waits this long before it goes, so ⌘Z can take it back."))
                } else {
                    LabeledContent(
                        SettingsNavigationModel.title(for: "general.undoSend"),
                        value: String(localized: "Available with a plan")
                    )
                }
            }
            .settingAnchor("general.undoSend", highlighted: highlightedSettingID)

            Group {
                if isEntitled(.undoSend) {
                    Toggle(
                        SettingsNavigationModel.title(for: "general.clickPendingToUndo"),
                        isOn: $composerPreferences.clickPendingToUndo
                    )
                    .disabled(composerPreferences.undoSendMillis == 0)
                } else {
                    LabeledContent(
                        SettingsNavigationModel.title(for: "general.clickPendingToUndo"),
                        value: String(localized: "Available with a plan")
                    )
                }
            }
            .settingAnchor("general.clickPendingToUndo", highlighted: highlightedSettingID)

            Group {
                if isEntitled(.sendLater) {
                    Picker(
                        SettingsNavigationModel.title(for: "general.sendLaterDefault"),
                        selection: $composerPreferences.sendLaterDefault
                    ) {
                        Text(String(localized: "If no reply")).tag(SendLaterCondition.ifNoReply)
                        Text(String(localized: "Regardless")).tag(SendLaterCondition.always)
                    }
                    .help(String(localized: "“If no reply” doesn’t send it when someone else writes in the chat first."))
                } else {
                    LabeledContent(
                        SettingsNavigationModel.title(for: "general.sendLaterDefault"),
                        value: String(localized: "Available with a plan")
                    )
                }
            }
            .settingAnchor("general.sendLaterDefault", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "general.upArrow"),
                selection: $composerPreferences.upArrow
            ) {
                Text(String(localized: "Move focus to the message list")).tag(UpArrowAction.focusMessages)
                Text(String(localized: "Edit your last message")).tag(UpArrowAction.editLast)
            }
            .settingAnchor("general.upArrow", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.copyWithTimestamps"),
                isOn: $composerPreferences.copyWithTimestamps
            )
            .settingAnchor("general.copyWithTimestamps", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.enableEmojiAutocomplete"),
                isOn: $composerPreferences.enableEmojiAutocomplete
            )
            .settingAnchor("general.enableEmojiAutocomplete", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.disableEmoticonReplacement"),
                isOn: $composerPreferences.disableEmoticonReplacement
            )
            .settingAnchor("general.disableEmoticonReplacement", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.autoSendGIFs"),
                isOn: $composerPreferences.autoSendGIFs
            )
            .settingAnchor("general.autoSendGIFs", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.autoPlayNextVoiceNote"),
                isOn: $composerPreferences.autoPlayNextVoiceNote
            )
            .settingAnchor("general.autoPlayNextVoiceNote", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "general.preferredMicrophone"),
                selection: $composerPreferences.preferredMicrophoneUID
            ) {
                Text(String(localized: "System Default")).tag("")
                ForEach(activeVoiceRecorder.availableDevices) { device in
                    Text(device.name).tag(device.uid)
                }
                if !composerPreferences.preferredMicrophoneUID.isEmpty,
                   !activeVoiceRecorder.availableDevices.contains(where: { $0.uid == composerPreferences.preferredMicrophoneUID }) {
                    Text(composerPreferences.preferredMicrophoneUID).tag(composerPreferences.preferredMicrophoneUID)
                }
            }
            .settingAnchor("general.preferredMicrophone", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.autoCopyOTP"),
                isOn: Binding(
                    get: { inboxPreferences.notifications.autoCopyOTP },
                    set: { inboxPreferences.notifications.autoCopyOTP = $0 }
                )
            )
            .help(String(localized: "Automatically copies 4–8 digit verification codes to your clipboard and notifies immediately."))
            .settingAnchor("general.autoCopyOTP", highlighted: highlightedSettingID)
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        Section(String(localized: "Downloads")) {
            LabeledContent(SettingsNavigationModel.title(for: "general.downloadsLocation")) {
                HStack(spacing: 8) {
                    Text((composerPreferences.downloadsDirectoryPath as NSString).abbreviatingWithTildeInPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(String(localized: "Choose…")) {
                        chooseDownloadsDirectory()
                    }
                }
            }
            .settingAnchor("general.downloadsLocation", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.alwaysAskWhereToSave"),
                isOn: $composerPreferences.alwaysAskWhereToSaveFiles
            )
            .settingAnchor("general.alwaysAskWhereToSave", highlighted: highlightedSettingID)
        }
    }

    private func chooseDownloadsDirectory() {
        let current = (composerPreferences.downloadsDirectoryPath as NSString).expandingTildeInPath
        guard let url = AppLockGate.shared.runOpenPanel(action: .settingsChange, configure: { panel in
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
            panel.prompt = String(localized: "Choose")
            panel.message = String(localized: "Choose a folder for downloaded attachments")
        })?.first else { return }
        composerPreferences.downloadsDirectoryPath = url.path
    }

    // MARK: - Startup & Security

    private var startupAndSecuritySection: some View {
        Section(String(localized: "Startup & Security")) {
            Toggle(
                SettingsNavigationModel.title(for: "general.openAtLogin"),
                isOn: $lifecycle.launchAtLogin
            )
            .settingAnchor("general.openAtLogin", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.keepMinimizedOnLaunch"),
                isOn: $lifecycle.startMinimized
            )
            .settingAnchor("general.keepMinimizedOnLaunch", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.quitOnClose"),
                isOn: Binding(
                    get: { lifecycle.quitOnMainWindowClose },
                    set: { lifecycle.quitOnMainWindowClose = $0 }
                )
            )
            .settingAnchor("general.quitOnClose", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "general.requireTouchID"),
                isOn: $lifecycle.autoLockEnabled
            )
            .help(String(localized: "Locks Courier on launch and after idle time; requires Touch ID or your Mac password."))
            .settingAnchor("general.requireTouchID", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "general.lockTimeout"),
                selection: $lifecycle.lockTimeout
            ) {
                ForEach(LockTimeoutChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .disabled(!lifecycle.autoLockEnabled)
            .settingAnchor("general.lockTimeout", highlighted: highlightedSettingID)

            if let errorMessage = lifecycle.lastErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker(
                SettingsNavigationModel.title(for: "general.timeFormat"),
                selection: $composerPreferences.timeFormat
            ) {
                ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                    Text(format.label).tag(format)
                }
            }
            .settingAnchor("general.timeFormat", highlighted: highlightedSettingID)
        }
    }
}

/// Settings ▸ Appearance pane: Chat list appearance, Conversation view, Composer controls (including Primary & Secondary composer buttons), and System (Menu bar icon, Dock badge count).
struct AppearanceSettingsPane: View {
    @ObservedObject var inboxPreferences: InboxPreferences
    @ObservedObject var composerPreferences: ComposerPreferences
    @ObservedObject var dockPreferences: DockAndTrayPreferences
    @ObservedObject var lifecycle: SystemLifecycleModel
    var highlightedSettingID: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                chatListSection
                conversationSection
                composerSection
                systemSection
            }
            .formStyle(.grouped)
            .disabled(lifecycle.isLocked)
            .onChange(of: highlightedSettingID, initial: true) { _, targetID in
                if let targetID {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var chatListSection: some View {
        Section(String(localized: "Chat list")) {
            Toggle(
                SettingsNavigationModel.title(for: "appearance.showSpaceBar"),
                isOn: $inboxPreferences.showSpaceBar
            )
            .settingAnchor("appearance.showSpaceBar", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.regularPinnedRows"),
                isOn: $inboxPreferences.regularPinnedRows
            )
            .help(String(localized: "Off, pinned chats sit above the list as small pictures."))
            .settingAnchor("appearance.regularPinnedRows", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.showUnreadCounts"),
                isOn: $inboxPreferences.showUnreadCounts
            )
            .settingAnchor("appearance.showUnreadCounts", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.showPreviews"),
                isOn: $inboxPreferences.showPreviews
            )
            .settingAnchor("appearance.showPreviews", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.compactList"),
                isOn: $inboxPreferences.compactList
            )
            .settingAnchor("appearance.compactList", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.showNetworkIcons"),
                isOn: $inboxPreferences.showNetworkIcons
            )
            .settingAnchor("appearance.showNetworkIcons", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.colorNetworkIcons"),
                isOn: $inboxPreferences.colorNetworkIcons
            )
            .disabled(!inboxPreferences.showNetworkIcons)
            .settingAnchor("appearance.colorNetworkIcons", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.hoverAction"),
                selection: $inboxPreferences.hoverAction
            ) {
                Text(String(localized: "Archive")).tag(HoverAction.archive)
                Text(String(localized: "Mark Read or Unread")).tag(HoverAction.toggleRead)
                Text(String(localized: "Menu")).tag(HoverAction.menu)
                Text(String(localized: "None")).tag(HoverAction.nothing)
            }
            .settingAnchor("appearance.hoverAction", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.doubleClickChat"),
                selection: $inboxPreferences.doubleClickAction
            ) {
                Text(String(localized: "Opens it in a new window")).tag(DoubleClickAction.openInNewWindow)
                Text(String(localized: "Archives it")).tag(DoubleClickAction.archive)
                Text(String(localized: "Marks it read or unread")).tag(DoubleClickAction.toggleRead)
                Text(String(localized: "Mutes or unmutes it")).tag(DoubleClickAction.toggleMute)
                Text(String(localized: "Moves it to Low Priority or back")).tag(DoubleClickAction.toggleLowPriority)
                Text(String(localized: "Does nothing")).tag(DoubleClickAction.nothing)
            }
            .settingAnchor("appearance.doubleClickChat", highlighted: highlightedSettingID)
        }
    }

    private var conversationSection: some View {
        Section(String(localized: "Conversation")) {
            Toggle(
                SettingsNavigationModel.title(for: "appearance.showMessageTimestamps"),
                isOn: $composerPreferences.showMessageTimestamps
            )
            .settingAnchor("appearance.showMessageTimestamps", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.hideDeletedMessages"),
                isOn: $composerPreferences.hideDeletedMessages
            )
            .help(String(localized: "Off, a deleted message leaves a line saying it was deleted."))
            .settingAnchor("appearance.hideDeletedMessages", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.showMembershipEvents"),
                isOn: $composerPreferences.showChatUpdatesInTimeline
            )
            .settingAnchor("appearance.showMembershipEvents", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.loadExternalEmbeds"),
                isOn: $composerPreferences.loadExternalEmbedsAutomatically
            )
            .settingAnchor("appearance.loadExternalEmbeds", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.quickReaction"),
                selection: $composerPreferences.quickReaction
            ) {
                ForEach(ConversationModel.quickReactions, id: \.self) { Text($0).tag($0) }
                if !ConversationModel.quickReactions.contains(composerPreferences.quickReaction) {
                    Text(composerPreferences.quickReaction).tag(composerPreferences.quickReaction)
                }
            }
            .help(String(localized: "⌘⇧R reacts with it to the selected message."))
            .settingAnchor("appearance.quickReaction", highlighted: highlightedSettingID)
        }
    }

    private var composerSection: some View {
        Section(String(localized: "Composer")) {
            Toggle(
                SettingsNavigationModel.title(for: "appearance.enableSpellcheck"),
                isOn: $composerPreferences.enableSpellcheck
            )
            .settingAnchor("appearance.enableSpellcheck", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.showFormattingMenu"),
                isOn: $composerPreferences.showFormattingMenu
            )
            .help(String(localized: "A bar of formatting buttons over the text you select."))
            .settingAnchor("appearance.showFormattingMenu", highlighted: highlightedSettingID)

            Toggle(
                SettingsNavigationModel.title(for: "appearance.disableOutgoingLinkPreviews"),
                isOn: $composerPreferences.disableOutgoingLinkPreviews
            )
            .settingAnchor("appearance.disableOutgoingLinkPreviews", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.primaryComposerButton"),
                selection: $composerPreferences.primaryComposerButton
            ) {
                ForEach(PrimaryComposerButton.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .settingAnchor("appearance.primaryComposerButton", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.secondaryComposerButton"),
                selection: $composerPreferences.secondaryComposerButton
            ) {
                ForEach(SecondaryComposerButton.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .settingAnchor("appearance.secondaryComposerButton", highlighted: highlightedSettingID)
        }
    }

    private var systemSection: some View {
        Section(String(localized: "System")) {
            Toggle(
                SettingsNavigationModel.title(for: "appearance.showMenuBarIcon"),
                isOn: $dockPreferences.showMenuBarIcon
            )
            .settingAnchor("appearance.showMenuBarIcon", highlighted: highlightedSettingID)

            Picker(
                SettingsNavigationModel.title(for: "appearance.dockBadgeCount"),
                selection: $dockPreferences.badgeMode
            ) {
                Text(String(localized: "Unread chats (unmuted)")).tag(DockBadgeMode.unreadChats)
                Text(String(localized: "All unread chats")).tag(DockBadgeMode.allChats)
                Text(String(localized: "None")).tag(DockBadgeMode.none)
            }
            .settingAnchor("appearance.dockBadgeCount", highlighted: highlightedSettingID)
        }
    }
}

private struct FlowLayoutTags: View {
    let items: [String]
    let canRemove: Bool
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if canRemove {
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Remove \(item)"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }
}
