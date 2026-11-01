// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Two-column Settings shell (`⌘,`, `PrefsPanes.tsx`, `PrefOption.tsx`, `PrefsControls.tsx`,
/// `DynamicPreferencesRenderer.tsx`, `PrefsActionPrompt.tsx`, `SearchSuggestions.tsx`, `PreferenceTags.tsx`).
struct SettingsWindow: View {
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var app: AppModel
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var labels: LabelsModel
    let conversation: ConversationModel
    @ObservedObject var inboxPreferences: InboxPreferences
    @ObservedObject var composerPreferences: ComposerPreferences
    @ObservedObject var notificationPreferences: NotificationPreferences
    @ObservedObject var quickReplies: QuickReplies
    @ObservedObject var hotkeys: HotkeyRegistry
    @ObservedObject var lifecycle: SystemLifecycleModel
    @ObservedObject var dockPreferences: DockAndTrayPreferences
    @ObservedObject var accountsAndBridges: AccountsAndBridgesModel
    @ObservedObject var loginFlow: LoginFlowModel
    @ObservedObject var problemReport: ProblemReportModel
    @ObservedObject var appearance: AppearancePreferences = AppearancePreferences()
    @ObservedObject var aiPreferences: AIPreferences = AIPreferences()
    var storage: StorageModel? = nil
    var onOpenSystemNotificationSettings: () -> Void = {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    var onRestartNotificationCenter: () -> Void = {}

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                leftPane
                    .frame(width: 228)
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            }
            .disabled(lifecycle.isLocked)
            .blur(radius: lifecycle.isLocked ? 8 : 0)

            if lifecycle.isLocked {
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Courier is locked"))
                        .font(.headline)
                    Text(String(localized: "Unlock Courier to view or change settings."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .background(
            Button("") {
                guard !lifecycle.isLocked else { return }
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(lifecycle.isLocked)
            .opacity(0)
            .accessibilityHidden(true)
        )
        .onChange(of: lifecycle.isLocked) { _, isLocked in
            if isLocked {
                isSearchFocused = false
                navigation.isPresentingProblemReport = false
                accountsAndBridges.cancelRemoveAccount()
            }
        }
        .onAppear {
            navigation.bind(accountsAndBridges: accountsAndBridges)
            if let key = navigation.selectedAccountKey {
                accountsAndBridges.selectedAccountKey = key
            }
        }
        .onChange(of: navigation.selectedAccountKey) { _, key in
            if let key {
                accountsAndBridges.selectedAccountKey = key
            }
        }
        .sheet(isPresented: $navigation.isPresentingProblemReport) {
            ProblemReportSheet(
                model: problemReport,
                onDismiss: { navigation.isPresentingProblemReport = false }
            )
        }
    }

    // MARK: - Left Column (PrefsLeftPane + SearchSuggestions)

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if !navigation.suggestions.isEmpty {
                searchSuggestionsList
                    .padding(.horizontal, 12)
            } else {
                categoryList
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 8)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))
            TextField(String(localized: "Search Settings"), text: $navigation.searchQuery)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isSearchFocused)
                .accessibilityLabel(String(localized: "Search Settings"))
            if !navigation.searchQuery.isEmpty {
                Button {
                    navigation.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var searchSuggestionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Matching Settings"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)

                ForEach(navigation.suggestions) { suggestion in
                    suggestionRow(for: suggestion)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func suggestionRow(for suggestion: SettingDefinition) -> some View {
        Button {
            navigation.jump(to: suggestion)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(suggestion.breadcrumbTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let badge = suggestion.badge {
                        SettingBadgeView(badge: badge)
                    }
                }
                Text(suggestion.section)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(SettingsPaneID.allCases) { pane in
                categoryRow(for: pane)
            }
        }
    }

    private func categoryRow(for pane: SettingsPaneID) -> some View {
        let isSelected = navigation.selectedPane == pane
        let connectedCount = app.accounts.filter { $0.state == .connected }.count
        return Button {
            navigation.openPane(pane)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: pane.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(pane.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if pane == .accounts && connectedCount > 0 {
                    Text("\(connectedCount)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(
                                    isSelected
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.14)
                                )
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Column (PrefsRightPane)

    @ViewBuilder
    private var rightPane: some View {
        switch navigation.selectedPane {
        case .general:
            GeneralSettingsPane(
                inboxPreferences: inboxPreferences,
                composerPreferences: composerPreferences,
                labels: labels,
                inbox: inbox,
                conversation: conversation,
                lifecycle: lifecycle,
                isEntitled: { inbox.isEntitled($0) },
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .appearance:
            AppearanceSettingsPane(
                inboxPreferences: inboxPreferences,
                composerPreferences: composerPreferences,
                dockPreferences: dockPreferences,
                lifecycle: lifecycle,
                appearance: appearance,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .notifications:
            NotificationsSettingsPane(
                preferences: notificationPreferences,
                accounts: app.accounts,
                lifecycle: lifecycle,
                onOpenSystemNotificationSettings: onOpenSystemNotificationSettings,
                onRestartNotificationCenter: onRestartNotificationCenter,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .accounts:
            AccountsSettingsPane(
                model: accountsAndBridges,
                spaces: spaces,
                notifications: notificationPreferences,
                onAddAccount: { loginFlow.showPicker() },
                onReconnect: { network, accountID in loginFlow.begin(network: network, accountID: accountID) },
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .hotkeys:
            HotkeysSettingsPane(
                registry: hotkeys,
                lifecycle: lifecycle,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .quickReplies:
            QuickRepliesSettingsPane(
                quickReplies: quickReplies,
                lifecycle: lifecycle,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .bridges:
            BridgesSettingsPane(
                model: accountsAndBridges,
                onOpenAccountSettings: { network, accountID in
                    let key = accountID.isEmpty ? network : "\(network):\(accountID)"
                    navigation.openPane(.accounts, accountKey: key)
                },
                onAddAccount: { network in
                    if let network, !network.isEmpty {
                        loginFlow.begin(network: network)
                    } else {
                        loginFlow.showPicker()
                    }
                },
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .storage:
            StorageSettingsPane(
                model: storage ?? StorageModel(appModel: app, lifecycle: lifecycle),
                lifecycle: lifecycle,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .ai:
            AISettingsPane(
                preferences: aiPreferences,
                lifecycle: lifecycle,
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .plan:
            PlusSettingsPane(
                entitlement: AlwaysEntitled(),
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .integrations:
            IntegrationsSettingsPane(
                highlightedSettingID: navigation.highlightedSettingID
            )
        case .about:
            AboutSettingsPane(
                lifecycle: lifecycle,
                onReportProblem: {
                    navigation.isPresentingProblemReport = true
                },
                onShowKeyboardShortcuts: {
                    hotkeys.isShortcutsSheetPresented = true
                },
                highlightedSettingID: navigation.highlightedSettingID
            )
        }
    }
}
