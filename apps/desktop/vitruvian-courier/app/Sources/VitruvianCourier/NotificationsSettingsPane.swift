// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import SwiftUI

/// Settings ▸ Notifications pane (`NotificationsSettingsPane.swift`):
/// Alert types & sounds, delay batching (Labs), repeat unread, OTP auto-copy, sound effects,
/// per-account notification overrides, and System Notification Center actions.
struct NotificationsSettingsPane: View {
    @ObservedObject var preferences: NotificationPreferences
    let accounts: [Account]
    @ObservedObject var lifecycle: SystemLifecycleModel
    var onOpenSystemNotificationSettings: () -> Void = {}
    var onRestartNotificationCenter: () -> Void = {}
    var highlightedSettingID: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                alertTypesSection
                timingAndCodesSection
                soundEffectsSection
                accountOverridesSection
                systemNotificationCenterSection
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

    private var alertTypesSection: some View {
        Section(String(localized: "Alert Types")) {
            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.messages"),
                isOn: $preferences.messageNotificationsEnabled
            )
            .settingAnchor("notifications.messages", highlighted: highlightedSettingID)

            soundPicker(
                String(localized: "Direct message sound"),
                selection: $preferences.messageSound,
                isEnabled: preferences.messageNotificationsEnabled
            )

            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.groups"),
                isOn: $preferences.groupNotificationsEnabled
            )
            .settingAnchor("notifications.groups", highlighted: highlightedSettingID)

            soundPicker(
                String(localized: "Group chat sound"),
                selection: $preferences.groupSound,
                isEnabled: preferences.groupNotificationsEnabled
            )

            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.requests"),
                isOn: $preferences.requestNotificationsEnabled
            )
            .help(String(localized: "A message request is someone you haven’t chatted with before writing to you."))
            .settingAnchor("notifications.requests", highlighted: highlightedSettingID)

            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.reactions"),
                isOn: $preferences.notifyOnReaction
            )
            .settingAnchor("notifications.reactions", highlighted: highlightedSettingID)

            SettingsSwitchRow(
                isOn: $preferences.typingNotificationsEnabled,
                title: SettingsNavigationModel.title(for: "notifications.typing")
            ) {
                HStack(spacing: 8) {
                    Text(SettingsNavigationModel.title(for: "notifications.typing"))
                    SettingBadgeView(badge: .labs)
                }
            }
            .help(String(localized: "Only on networks that send typing. Off, you’re told when the message arrives."))
            .settingAnchor("notifications.typing", highlighted: highlightedSettingID)

            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.inFocus"),
                isOn: $preferences.notifyWhenInFocus
            )
            .settingAnchor("notifications.inFocus", highlighted: highlightedSettingID)
        }
    }

    /// A sound's own row, under the alert it belongs to. It is greyed out while that alert is off, because the sound
    /// then never plays.
    private func soundPicker(
        _ title: String,
        selection: Binding<NotificationSoundChoice>,
        isEnabled: Bool
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(NotificationSoundChoice.allCases, id: \.self) { choice in
                Text(Self.soundLabel(choice)).tag(choice)
            }
        }
        .disabled(!isEnabled)
    }

    private var timingAndCodesSection: some View {
        Section(String(localized: "Timing & Verification Codes")) {
            Picker(selection: $preferences.delaySeconds) {
                ForEach(NotificationPreferences.allowedDelaySeconds, id: \.self) { seconds in
                    Text(Self.delayLabel(seconds)).tag(seconds)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(SettingsNavigationModel.title(for: "notifications.delay"))
                    SettingBadgeView(badge: .labs)
                }
            }
            .settingAnchor("notifications.delay", highlighted: highlightedSettingID)

            Text(NotificationPreferences.delayFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(
                SettingsNavigationModel.title(for: "notifications.repeatUnread"),
                selection: $preferences.repeatUnreadMinutes
            ) {
                ForEach(NotificationPreferences.allowedRepeatUnreadMinutes, id: \.self) { minutes in
                    Text(Self.repeatLabel(minutes)).tag(minutes)
                }
            }
            .settingAnchor("notifications.repeatUnread", highlighted: highlightedSettingID)

            SettingsSwitchRow(
                SettingsNavigationModel.title(for: "notifications.autoCopyOTP"),
                isOn: $preferences.autoCopyOTP
            )
            .help(String(localized: "Still notifies even if the chat is muted, and adds a Copy Code button."))
            .settingAnchor("notifications.autoCopyOTP", highlighted: highlightedSettingID)
        }
    }

    private var soundEffectsSection: some View {
        Section(String(localized: "Sound Effects")) {
            Picker(
                SettingsNavigationModel.title(for: "notifications.soundEffectsMode"),
                selection: $preferences.soundEffectsMode
            ) {
                Text(String(localized: "Never")).tag(SoundEffectsMode.never)
                Text(String(localized: "Sent messages only")).tag(SoundEffectsMode.sentOnly)
                Text(String(localized: "Received messages only")).tag(SoundEffectsMode.receivedOnly)
                Text(String(localized: "Sent and received messages")).tag(SoundEffectsMode.always)
            }
            .settingAnchor("notifications.soundEffectsMode", highlighted: highlightedSettingID)

            LabeledContent(SettingsNavigationModel.title(for: "notifications.soundEffectsVolume")) {
                HStack(spacing: 8) {
                    Slider(value: $preferences.soundEffectsVolume, in: 0.0 ... 1.0)
                        .frame(width: 160)
                    Text("\(Int((preferences.soundEffectsVolume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .disabled(preferences.soundEffectsMode == .never)
            .settingAnchor("notifications.soundEffectsVolume", highlighted: highlightedSettingID)
        }
    }

    private struct AccountOverrideRowItem: Identifiable {
        let id: String
        let network: String
        let displayTitle: String
        let remoteName: String
    }

    private var accountOverrideItems: [AccountOverrideRowItem] {
        var result: [AccountOverrideRowItem] = []
        for account in accounts {
            let displayTitle = account.displayName.isEmpty
                ? (NetworkNames.displayName(of: account.network) ?? account.network)
                : account.displayName
            if account.logins.isEmpty {
                result.append(
                    AccountOverrideRowItem(
                        id: account.network,
                        network: account.network,
                        displayTitle: displayTitle,
                        remoteName: account.remoteName
                    )
                )
            } else {
                for login in account.logins {
                    let key = login.accountID.isEmpty ? account.network : "\(account.network):\(login.accountID)"
                    result.append(
                        AccountOverrideRowItem(
                            id: key,
                            network: account.network,
                            displayTitle: displayTitle,
                            remoteName: login.remoteName
                        )
                    )
                }
            }
        }
        return result
    }

    private var accountOverridesSection: some View {
        Section(String(localized: "Per-Account Overrides")) {
            VStack(alignment: .leading, spacing: 10) {
                if accountOverrideItems.isEmpty {
                    Text(String(localized: "Connect an account to configure per-account notification alerts and previews."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(accountOverrideItems) { item in
                    let key = item.id
                    HStack(spacing: 12) {
                        NetworkBadge(network: item.network, name: item.displayTitle, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayTitle)
                                .font(.subheadline.weight(.medium))
                            if !item.remoteName.isEmpty {
                                Text(PhoneNumberFormat.display(item.remoteName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SettingsSwitchRow(
                            String(localized: "Alerts"),
                            isOn: Binding(
                                get: { preferences.accountOverrides[key]?.enabled ?? true },
                                set: { enabled in
                                    var entry = preferences.accountOverrides[key] ?? AccountNotificationOverride()
                                    entry.enabled = enabled
                                    preferences.accountOverrides[key] = entry
                                }
                            ),
                            fillsWidth: false
                        )
                        .controlSize(.small)

                        Toggle(
                            String(localized: "Previews"),
                            isOn: Binding(
                                get: { preferences.accountOverrides[key]?.showPreviews ?? true },
                                set: { show in
                                    var entry = preferences.accountOverrides[key] ?? AccountNotificationOverride()
                                    entry.showPreviews = show
                                    preferences.accountOverrides[key] = entry
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .disabled(!(preferences.accountOverrides[key]?.enabled ?? true))
                    }
                }
            }
            .settingAnchor("notifications.accountOverrides", highlighted: highlightedSettingID)
        }
    }

    private var systemNotificationCenterSection: some View {
        Section(String(localized: "System Notification Center")) {
            HStack(spacing: 12) {
                Button(SettingsNavigationModel.title(for: "notifications.systemSettings")) {
                    onOpenSystemNotificationSettings()
                }
                .settingAnchor("notifications.systemSettings", highlighted: highlightedSettingID)

                Button(SettingsNavigationModel.title(for: "notifications.restartCenter")) {
                    onRestartNotificationCenter()
                }
                .help(String(localized: "Clears delivered banners, restarts macOS NotificationCenter, and refreshes notification categories."))
                .settingAnchor("notifications.restartCenter", highlighted: highlightedSettingID)
            }
        }
    }

    static func soundLabel(_ choice: NotificationSoundChoice) -> String {
        switch choice {
        case .default: String(localized: "System Default")
        case .none: String(localized: "None")
        case .beeper: String(localized: "Vitruvian Courier Chime")
        case .sounds: String(localized: "Pop")
        case .double: String(localized: "Double Note")
        case .dreams: String(localized: "Dreams")
        case .not: String(localized: "Gentle")
        case .marimba: String(localized: "Marimba")
        case .rain: String(localized: "Rain")
        case .harp: String(localized: "Harp")
        case .record: String(localized: "Record")
        case .spirit: String(localized: "Spirit")
        }
    }

    static func delayLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: String(localized: "Off (immediately)")
        case 60: String(localized: "1 minute")
        case let s where s >= 60 && s % 60 == 0: String(localized: "\(s / 60) minutes")
        default: String(localized: "\(seconds) seconds")
        }
    }

    static func repeatLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: String(localized: "Never")
        default: String(localized: "After \(minutes) minutes")
        }
    }
}
