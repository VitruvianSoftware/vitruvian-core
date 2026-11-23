// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
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
    var aiProviderStore: AIProviderStore? = nil
    var storage: StorageModel? = nil
    var integrations: IntegrationsModel = IntegrationsModel(appModel: nil, enginePath: EngineLocation.enginePath())
    /// Settings ▸ About ▸ Updates. The app passes its own; the default one checks nothing until asked.
    var updates: UpdateModel = UpdateModel(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        appURL: Bundle.main.bundleURL, environment: SystemUpdateEnvironment(), quit: {})
    var onOpenSystemNotificationSettings: () -> Void = {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    var onRestartNotificationCenter: () -> Void = {}

    @FocusState private var isSearchFocused: Bool

    /// What the switches and other controls on the right use for "on": the chat theme's accent, as in the main window,
    /// unless that is nearly grey. Off stays neutral.
    private var controlTint: Color {
        let accent = appearance.effectiveTheme(for: nil).accentColorHex
        return Color(hex: SettingsControlTint.hex(forThemeAccent: accent)) ?? .accentColor
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                leftPane
                    .frame(width: 244)
                    .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                rightPane
                    .tint(controlTint)
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
                    Text(String(localized: "Vitruvian Courier is locked"))
                        .font(.headline)
                    Text(String(localized: "Unlock Vitruvian Courier to view or change settings."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(minWidth: SettingsWindowResizer.minimumSize.width, minHeight: SettingsWindowResizer.minimumSize.height)
        .background(SettingsWindowResizer())
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
        .onChange(of: navigation.selectedPane) { _, pane in
            if pane != .ai {
                aiProviderStore?.stopSettingsDetection()
            }
        }
        .onDisappear {
            aiProviderStore?.stopSettingsDetection()
        }
        .background(
            SettingsWindowDetectionObserver(
                onWindowClose: {
                    aiProviderStore?.stopSettingsDetection()
                },
                onWindowBecomeKey: {
                    if navigation.selectedPane == .ai, aiProviderStore?.isSettingsDetectionActive == false {
                        aiProviderStore?.startSettingsDetection()
                    }
                }
            )
        )
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
                accountCard
                    .padding(.horizontal, 12)
                categoryList
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Account card

    /// The card above the sidebar's rows. The app has no sign-in of its own, so it says how many accounts are connected
    /// and which plan this Mac is on, and opens Settings ▸ Accounts.
    private var accountCard: some View {
        SettingsAccountCardView(card: SettingsAccountCard.make(accounts: app.accounts)) {
            navigation.openPane(.accounts)
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
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    /// The panes, as a standard macOS source list: its own selection highlight, not a fill of ours.
    private var categoryList: some View {
        List(selection: selectedPane) {
            ForEach(SettingsSidebar.items) { item in
                categoryRow(for: item)
                    .tag(item.pane)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private var selectedPane: Binding<SettingsPaneID?> {
        Binding(
            get: { navigation.selectedPane },
            set: { pane in
                if let pane { navigation.openPane(pane) }
            }
        )
    }

    private func categoryRow(for item: SettingsSidebarItem) -> some View {
        let connectedCount = SettingsAccountCard.connectedCount(of: app.accounts)
        return HStack(spacing: 9) {
            SettingsIconTile(symbolName: item.symbolName, color: item.tile.color)
            Text(item.title)
            Spacer(minLength: 4)
            if item.pane == .accounts && connectedCount > 0 {
                Text("\(connectedCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
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
                store: aiProviderStore,
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
                model: integrations,
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
                highlightedSettingID: navigation.highlightedSettingID,
                updates: updates
            )
        }
    }
}


/// The coloured rounded square behind a Settings sidebar icon, as in macOS System Settings: a white symbol on a solid
/// colour, about 20 pt across.
struct SettingsIconTile: View {
    let symbolName: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.gradient)
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

extension SettingsTileColor {
    /// The system colour of the same name, which adapts to light and dark mode.
    var color: Color {
        switch self {
        case .gray: .gray
        case .indigo: .indigo
        case .red: .red
        case .blue: .blue
        case .brown: .brown
        case .green: .green
        case .teal: .teal
        case .orange: .orange
        case .purple: .purple
        case .pink: .pink
        case .mint: .mint
        case .cyan: .cyan
        }
    }
}

/// The card at the top of the Settings sidebar: how many accounts are connected, and the plan. A button that opens
/// Settings ▸ Accounts.
struct SettingsAccountCardView: View {
    let card: SettingsAccountCard
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(card.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.title), \(card.subtitle)")
        .accessibilityHint(String(localized: "Opens Accounts settings"))
    }
}

/// Makes the Settings window resizable. A SwiftUI `Settings` scene opens a window without the resizable style and
/// ignores `.windowResizability`, so the window is reached and given the style directly. How small it may go is
/// `SettingsView`'s `.frame(minWidth:minHeight:)` (`minimumSize`), which the hosting view hands to the window.
struct SettingsWindowResizer: NSViewRepresentable {
    static let minimumSize = CGSize(width: 980, height: 540)

    func makeNSView(context _: Context) -> NSView { ResizerView() }
    func updateNSView(_: NSView, context _: Context) {}

    static func makeResizable(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        // The scene pins the window's largest size to its content's; there is no largest size.
        window.contentMaxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private final class ResizerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            SettingsWindowResizer.makeResizable(window)
            // Again once SwiftUI has finished setting the window up, which it does after the view arrives.
            DispatchQueue.main.async { [weak window] in
                if let window { SettingsWindowResizer.makeResizable(window) }
            }
        }
    }
}
