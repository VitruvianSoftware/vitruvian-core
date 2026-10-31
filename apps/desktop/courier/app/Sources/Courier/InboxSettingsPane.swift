// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Courier ▸ Settings (`⌘,`): delegates to the two-column `SettingsWindow` shell across all 8 panes.
struct SettingsView: View {
    var appModel: AppModel? = nil
    let inbox: InboxModel
    var spaces: SpacesModel? = nil
    let labels: LabelsModel
    /// Incognito is turned on and off through it, so that turning it on asks about typing.
    let conversation: ConversationModel
    /// The one object the composers read, and the quick replies they offer.
    let composerPreferences: ComposerPreferences
    let quickReplies: QuickReplies
    var hotkeys: HotkeyRegistry = HotkeyRegistry()
    var lifecycle: SystemLifecycleModel = SystemLifecycleModel()
    var navigation: SettingsNavigationModel = SettingsNavigationModel()
    var notificationPreferences: NotificationPreferences = NotificationPreferences()
    var dockPreferences: DockAndTrayPreferences = DockAndTrayPreferences()
    var accountsAndBridges: AccountsAndBridgesModel? = nil
    var loginFlow: LoginFlowModel? = nil
    var problemReport: ProblemReportModel? = nil
    var onRestartNotificationCenter: () -> Void = {}

    private var resolvedAppModel: AppModel {
        if let appModel {
            return appModel
        }
        return AppModel(
            supervisor: EngineSupervisor(
                enginePath: "/nonexistent/courier-engine",
                dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-settings"),
                environment: [:],
                launcher: FoundationProcessLauncher()
            ),
            lifecycle: lifecycle
        )
    }

    var body: some View {
        let resolvedApp = resolvedAppModel
        SettingsWindow(
            navigation: navigation,
            app: resolvedApp,
            inbox: inbox,
            spaces: spaces ?? SpacesModel(appModel: resolvedApp, inbox: inbox, lifecycle: lifecycle),
            labels: labels,
            conversation: conversation,
            inboxPreferences: inbox.preferences,
            composerPreferences: composerPreferences,
            notificationPreferences: notificationPreferences,
            quickReplies: quickReplies,
            hotkeys: hotkeys,
            lifecycle: lifecycle,
            dockPreferences: dockPreferences,
            accountsAndBridges: accountsAndBridges ?? AccountsAndBridgesModel(appModel: resolvedApp, lifecycle: lifecycle),
            loginFlow: loginFlow ?? LoginFlowModel(appModel: resolvedApp),
            problemReport: problemReport ?? ProblemReportModel(appModel: resolvedApp),
            onRestartNotificationCenter: onRestartNotificationCenter
        )
    }
}

/// Settings ▸ Inbox: how the chat list looks, archiving, reminders and requests. These are this Mac's settings;
/// the auto-archive rules are the engine's.
struct InboxSettingsPane: View {
    @ObservedObject var preferences: InboxPreferences
    @ObservedObject var labels: LabelsModel
    let inbox: InboxModel

    @State private var sweepReadOnly = true
    @State private var sweepDays = 28
    @State private var sweepCount: Int?
    @State private var counted = false
    @State private var generalProblem: String?

    var body: some View {
        Form {
            chatList
            archiving
            reminders
            Section(String(localized: "Notifications")) {
                Toggle(String(localized: "Notify me about message requests"), isOn: $preferences.requestNotifications)
                    .help(String(localized: "A message request is someone you haven’t chatted with before writing to you."))
                Toggle(String(localized: "Notify me when someone starts typing"), isOn: $preferences.typingNotifications)
                    .help(String(localized: "Only on networks that send typing. Off, you’re told when the message arrives."))
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
        // The archive-all tool's Undo shows here, where its button is.
        .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
    }

    // MARK: Chat list

    private var chatList: some View {
        Section(String(localized: "Chat list")) {
            Toggle(String(localized: "Show the space bar"), isOn: $preferences.showSpaceBar)
            Toggle(String(localized: "Show pinned chats as full rows"), isOn: $preferences.regularPinnedRows)
                .help(String(localized: "Off, pinned chats sit above the list as small pictures."))
            Toggle(String(localized: "Show unread counts"), isOn: $preferences.showUnreadCounts)
            Toggle(String(localized: "Show message previews"), isOn: $preferences.showPreviews)
            Toggle(String(localized: "Compact chat list"), isOn: $preferences.compactList)
            Toggle(String(localized: "Show network icons"), isOn: $preferences.showNetworkIcons)
            Toggle(String(localized: "Colour network icons"), isOn: $preferences.colorNetworkIcons)
                .disabled(!preferences.showNetworkIcons)
            Picker(String(localized: "Button on a chat you point at"), selection: $preferences.hoverAction) {
                Text(String(localized: "Archive")).tag(HoverAction.archive)
                Text(String(localized: "Mark Read or Unread")).tag(HoverAction.toggleRead)
                Text(String(localized: "Menu")).tag(HoverAction.menu)
                Text(String(localized: "None")).tag(HoverAction.nothing)
            }
            Picker(String(localized: "Double-clicking a chat"), selection: $preferences.doubleClickAction) {
                Text(String(localized: "Opens it in a new window")).tag(DoubleClickAction.openInNewWindow)
                Text(String(localized: "Archives it")).tag(DoubleClickAction.archive)
                Text(String(localized: "Marks it read or unread")).tag(DoubleClickAction.toggleRead)
                Text(String(localized: "Mutes or unmutes it")).tag(DoubleClickAction.toggleMute)
                Text(String(localized: "Moves it to Low Priority or back")).tag(DoubleClickAction.toggleLowPriority)
                Text(String(localized: "Does nothing")).tag(DoubleClickAction.nothing)
            }
        }
    }

    // MARK: Archiving

    private var archiving: some View {
        Section(String(localized: "Archiving")) {
            Toggle(String(localized: "Mark chats read when I archive them"), isOn: $preferences.markReadOnArchive)
                .help(String(localized: "Your networks are told the chat was read, as when you open it."))
            Picker(String(localized: "After archiving the open chat"), selection: $preferences.afterArchive) {
                afterChoices
            }
            Picker(String(localized: "After marking the open chat read or unread"), selection: $preferences.afterToggleRead) {
                afterChoices
            }
            if labels.canAutoArchive {
                Picker(String(localized: "Archive chats by themselves"), selection: generalTrigger) {
                    Text(String(localized: "Never")).tag(AutoArchiveTrigger?.none)
                    Text(String(localized: "After I reply")).tag(AutoArchiveTrigger?.some(.afterReply))
                    Text(String(localized: "After I read them")).tag(AutoArchiveTrigger?.some(.afterRead))
                }
                .help(String(localized: "An archived chat comes back to your inbox when someone writes."))
                Picker(String(localized: "Wait"), selection: generalDelay) {
                    ForEach(LabelsModel.generalDelays, id: \.self) { Text(Self.delay($0)).tag($0) }
                }
                .disabled(labels.generalRule == nil)
                if let generalProblem {
                    Text(generalProblem).foregroundStyle(.red)
                }
            } else {
                LabeledContent(String(localized: "Archive chats by themselves"), value: String(localized: "Available with a plan"))
            }
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
        Binding(get: { labels.generalRule?.trigger }, set: { trigger in
            let minutes = labels.generalRule.map { Int($0.durationMS / 60_000) } ?? 0
            setGeneral(trigger, minutes: minutes)
        })
    }

    private var generalDelay: Binding<Int> {
        Binding(get: { labels.generalRule.map { Int($0.durationMS / 60_000) } ?? 0 }, set: { minutes in
            setGeneral(labels.generalRule?.trigger, minutes: minutes)
        })
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

    static func delay(_ minutes: Int) -> String {
        switch minutes {
        case 0: String(localized: "No time")
        case 1: String(localized: "1 minute")
        case 60: String(localized: "1 hour")
        case 1440: String(localized: "1 day")
        case 10080: String(localized: "1 week")
        case let m where m % 60 == 0: String(localized: "\(m / 60) hours")
        default: String(localized: "\(minutes) minutes")
        }
    }

    private func recount() async {
        sweepCount = await inbox.archiveAllCount(readOnly: sweepReadOnly, olderThanDays: sweepDays, space: "inbox")
        counted = true
    }

    // MARK: Reminders

    private var reminders: some View {
        Section(String(localized: "Reminders")) {
            Picker(String(localized: "Remind me"), selection: $preferences.remindDefault) {
                Text(String(localized: "If no reply")).tag(RemindCondition.ifNoReply)
                Text(String(localized: "Always")).tag(RemindCondition.always)
            }
            .help(RemindHelp.condition)
            Toggle(String(localized: "Archive a chat when I set a reminder on it"), isOn: $preferences.archiveAfterReminder)
                .help(String(localized: "The reminder brings it back to your inbox when it is due."))
        }
    }
}
