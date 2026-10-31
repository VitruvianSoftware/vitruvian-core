// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Settings ▸ Accounts pane (`02` §1.4, `NetworksSettings.tsx` / `AccountView.tsx`):
/// connected accounts list, `+ Add Account` flow trigger, per-account status & reconnect,
/// Space Bar pin + Show in Inbox + Mute Space + Auto-Archive, per-account notification overrides,
/// Telegram Folders & Bots (`accounts.subAccounts` / `accounts.setSubAccount`),
/// official desktop app Dock cleanup, and destructive `Remove Account…` confirmation.
struct AccountsSettingsPane: View {
    @ObservedObject var model: AccountsAndBridgesModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var notifications: NotificationPreferences
    let onAddAccount: () -> Void
    let onReconnect: (_ network: String, _ accountID: String) -> Void
    var onOpenAutoArchive: ((String) -> Void)? = nil
    var highlightedSettingID: String? = nil
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            accountsSidebar
                .frame(width: 220)
            Divider()
            accountDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if model.bridges.isEmpty {
                await model.refresh()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.pendingRemoval != nil },
                set: { shown in if !shown { model.cancelRemoveAccount() } }
            )
        ) {
            if let removal = model.pendingRemoval {
                RemoveAccountConfirmationSheet(
                    confirmation: Binding(
                        get: { model.pendingRemoval ?? removal },
                        set: { model.pendingRemoval = $0 }
                    ),
                    onConfirm: {
                        Task { await model.confirmRemoveAccount() }
                    },
                    onCancel: {
                        model.cancelRemoveAccount()
                    }
                )
            }
        }
    }

    private struct AccountEntry: Identifiable {
        let key: String
        let network: String
        let displayName: String
        let accountID: String
        let remoteName: String
        let state: AccountState
        let error: String
        var id: String { key }
    }

    private var entries: [AccountEntry] {
        var out: [AccountEntry] = []
        for br in model.bridges {
            for acct in br.accounts {
                for login in acct.logins {
                    let key = AccountsAndBridgesModel.accountKey(network: br.network, accountID: login.accountID)
                    out.append(
                        AccountEntry(
                            key: key,
                            network: br.network,
                            displayName: br.displayName,
                            accountID: login.accountID,
                            remoteName: login.remoteName.isEmpty ? login.accountID : login.remoteName,
                            state: login.state,
                            error: login.error
                        )
                    )
                }
            }
        }
        return out
    }

    private var accountsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "Accounts"))
                    .font(.headline)
                Spacer()
                Button {
                    onAddAccount()
                } label: {
                    Label(String(localized: "Add Account"), systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(model.isLocked)
                .help(String(localized: "Connect a chat account"))
                .accessibilityLabel(String(localized: "Add Account"))
            }
            .padding(12)

            Divider()

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Text(String(localized: "No accounts connected"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Add Account…")) {
                        onAddAccount()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isLocked)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { entry in
                            let isSelected = model.selectedAccountKey == entry.key
                            Button {
                                model.selectedAccountKey = entry.key
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(statusColor(entry.state))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName)
                                            .font(.body.weight(isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                        Text(entry.remoteName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private var accountDetail: some View {
        if let selectedKey = model.selectedAccountKey,
           let entry = entries.first(where: { $0.key == selectedKey }) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard(entry)
                            .settingAnchor("accounts.connectedNetworks", highlighted: highlightedSettingID)
                        spaceAndInboxCard(entry)
                        notificationOverrideCard(entry)
                        subAccountsCard(entry)
                            .settingAnchor("accounts.subAccounts", highlighted: highlightedSettingID)
                        dockCleanupCard(entry)
                            .settingAnchor("accounts.dockCleanup", highlighted: highlightedSettingID)
                        developerActionsCard(entry)
                        if let error = model.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let toast = model.lastToast {
                            Text(toast)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    if let id = highlightedSettingID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: highlightedSettingID) { _, id in
                    if let id {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .task(id: entry.key) {
                if model.subAccountsByKey[entry.key] == nil {
                    await model.loadSubAccounts(network: entry.network, accountID: entry.accountID, forceRefresh: false)
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GroupBox {
                            VStack(spacing: 10) {
                                Image(systemName: "person.2.circle")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "Select an account to view its settings"))
                                    .foregroundStyle(.secondary)
                                Button(String(localized: "Add Account…")) {
                                    onAddAccount()
                                }
                                .disabled(model.isLocked)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                        }
                        .settingAnchor("accounts.connectedNetworks", highlighted: highlightedSettingID)

                        GroupBox(String(localized: "Sub-Accounts")) {
                            Text(String(localized: "Connect or select an account to expose spaces, folders, communities, or bots as dedicated views."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .settingAnchor("accounts.subAccounts", highlighted: highlightedSettingID)

                        GroupBox(String(localized: "macOS Dock")) {
                            Text(String(localized: "Connect or select an account to remove duplicate official app icons from your macOS Dock."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .settingAnchor("accounts.dockCleanup", highlighted: highlightedSettingID)

                        if let error = model.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let toast = model.lastToast {
                            Text(toast)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    if let id = highlightedSettingID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: highlightedSettingID) { _, id in
                    if let id {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func headerCard(_ entry: AccountEntry) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                NetworkBadge(network: entry.network, name: entry.displayName, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.displayName)
                            .font(.title3.weight(.semibold))
                        Text(stateLabel(entry.state))
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(entry.state).opacity(0.15))
                            .foregroundStyle(statusColor(entry.state))
                            .clipShape(Capsule())
                    }
                    Text(entry.remoteName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !entry.error.isEmpty {
                        Text(entry.error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if entry.state == .loggedOut || entry.state == .badCredentials || entry.state == .unknownError {
                    Button(String(localized: "Reconnect…")) {
                        onReconnect(entry.network, entry.accountID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLocked)
                }
                Button(role: .destructive) {
                    model.requestRemoveAccount(
                        network: entry.network,
                        accountID: entry.accountID,
                        remoteName: entry.remoteName,
                        displayName: entry.displayName
                    )
                } label: {
                    Text(String(localized: "Remove Account…"))
                }
                .disabled(model.isLocked)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func spaceAndInboxCard(_ entry: AccountEntry) -> some View {
        let accountSpace = spaces.spaces.first { $0.kind == .account && $0.network == entry.network }
        GroupBox(String(localized: "Space Bar & Inbox")) {
            VStack(alignment: .leading, spacing: 12) {
                if let space = accountSpace {
                    Toggle(
                        String(localized: "Show in Space Bar"),
                        isOn: Binding(
                            get: { !space.hidden },
                            set: { show in
                                let order = spaces.spaces.map(\.spaceID)
                                var hidden = spaces.spaces.filter(\.hidden).map(\.spaceID)
                                if show {
                                    hidden.removeAll { $0 == space.spaceID }
                                } else if !hidden.contains(space.spaceID) {
                                    hidden.append(space.spaceID)
                                }
                                Task { await spaces.saveLayout(order: order, hidden: hidden) }
                            }
                        )
                    )
                    .disabled(model.isLocked)

                    HStack {
                        Text(String(localized: "Show in Inbox"))
                        Spacer()
                        Picker(
                            String(localized: "Show in Inbox"),
                            selection: Binding(
                                get: { space.showInInbox },
                                set: { v in Task { await spaces.setShowInInbox(space.spaceID, v.rawValue) } }
                            )
                        ) {
                            Text(String(localized: "All Messages")).tag(ShowInInbox.all)
                            Text(String(localized: "Only DMs")).tag(ShowInInbox.dms)
                            Text(String(localized: "None")).tag(ShowInInbox.none)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .disabled(model.isLocked)
                    }

                    Toggle(
                        String(localized: "Mute Account Space"),
                        isOn: Binding(
                            get: { space.muted },
                            set: { v in Task { await spaces.setMuted(space.spaceID, v) } }
                        )
                    )
                    .disabled(model.isLocked)

                    HStack {
                        Text(String(localized: "Automatically archive read chats after a set time"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Auto-Archive…")) {
                            if let onOpenAutoArchive {
                                onOpenAutoArchive(space.spaceID)
                            } else {
                                openWindow(id: WindowID.autoArchive, value: space.spaceID)
                            }
                        }
                        .controlSize(.small)
                        .disabled(model.isLocked)
                    }
                } else {
                    Text(String(localized: "Account space will appear once chats sync."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func notificationOverrideCard(_ entry: AccountEntry) -> some View {
        let currentOverride = notifications.accountOverrides[entry.key]
            ?? notifications.accountOverrides[entry.accountID]
        let hasCustomOverride = currentOverride != nil
        return GroupBox(String(localized: "Notifications for this Account")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    String(localized: "Override global notification settings"),
                    isOn: Binding(
                        get: { hasCustomOverride },
                        set: { enabled in
                            if enabled {
                                notifications.accountOverrides[entry.key] = AccountNotificationOverride()
                            } else {
                                notifications.accountOverrides.removeValue(forKey: entry.key)
                                notifications.accountOverrides.removeValue(forKey: entry.accountID)
                            }
                        }
                    )
                )
                .disabled(model.isLocked)

                if let ov = currentOverride {
                    Toggle(
                        String(localized: "Desktop notifications"),
                        isOn: Binding(
                            get: { ov.enabled },
                            set: { v in
                                var next = ov
                                next.enabled = v
                                notifications.accountOverrides[entry.key] = next
                            }
                        )
                    )
                    .disabled(model.isLocked)

                    HStack {
                        Text(String(localized: "Sound"))
                        Spacer()
                        Picker(
                            String(localized: "Sound"),
                            selection: Binding(
                                get: { ov.sound?.rawValue ?? "" },
                                set: { v in
                                    var next = ov
                                    next.sound = v.isEmpty ? nil : NotificationSoundChoice(rawValue: v)
                                    notifications.accountOverrides[entry.key] = next
                                }
                            )
                        ) {
                            Text(String(localized: "Default")).tag("")
                            ForEach(NotificationSoundChoice.allCases, id: \.rawValue) { choice in
                                Text(choice.rawValue.capitalized).tag(choice.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .disabled(model.isLocked)
                    }

                    Toggle(
                        String(localized: "Include message preview"),
                        isOn: Binding(
                            get: { ov.showPreviews },
                            set: { v in
                                var next = ov
                                next.showPreviews = v
                                notifications.accountOverrides[entry.key] = next
                            }
                        )
                    )
                    .disabled(model.isLocked)
                }
            }
            .padding(8)
        }
    }

    private func subAccountsCard(_ entry: AccountEntry) -> some View {
        let items = model.subAccountsByKey[entry.key] ?? []
        let spacesItems = items.filter { $0.kind == "space" }
        let botItems = items.filter { $0.kind == "bot" }
        return GroupBox(String(localized: "Sub-Accounts")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "Expose spaces, folders, communities, or bots as dedicated views"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Refresh List")) {
                        Task {
                            await model.loadSubAccounts(
                                network: entry.network,
                                accountID: entry.accountID,
                                forceRefresh: true
                            )
                        }
                    }
                    .controlSize(.small)
                    .disabled(model.isLocked)
                }

                if items.isEmpty {
                    Text(String(localized: "No spaces or bots found for this account."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if !spacesItems.isEmpty {
                        Text(String(localized: "Spaces"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(spacesItems) { item in
                            subAccountRow(entry: entry, item: item)
                        }
                    }
                    if !botItems.isEmpty {
                        Text(String(localized: "Bots"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, spacesItems.isEmpty ? 0 : 4)
                        ForEach(botItems) { item in
                            subAccountRow(entry: entry, item: item)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func subAccountRow(entry: AccountEntry, item: SubAccountItem) -> some View {
        HStack(spacing: 10) {
            Toggle(
                item.title.isEmpty ? item.subID : item.title,
                isOn: Binding(
                    get: { item.enabled },
                    set: { v in
                        Task {
                            await model.updateSubAccount(
                                network: entry.network,
                                accountID: entry.accountID,
                                subID: item.subID,
                                enabled: v,
                                showInInbox: item.showInInbox
                            )
                        }
                    }
                )
            )
            .disabled(model.isLocked)
            Spacer()
            if item.enabled {
                Picker(
                    String(localized: "Inbox"),
                    selection: Binding(
                        get: { item.showInInbox },
                        set: { v in
                            Task {
                                await model.updateSubAccount(
                                    network: entry.network,
                                    accountID: entry.accountID,
                                    subID: item.subID,
                                    enabled: item.enabled,
                                    showInInbox: v
                                )
                            }
                        }
                    )
                ) {
                    Text(String(localized: "All")).tag(ShowInInbox.all)
                    Text(String(localized: "DMs")).tag(ShowInInbox.dms)
                    Text(String(localized: "None")).tag(ShowInInbox.none)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 90)
                .disabled(model.isLocked)
            }
        }
    }

    private func dockCleanupCard(_ entry: AccountEntry) -> some View {
        GroupBox(String(localized: "macOS Dock")) {
            HStack {
                if model.canOfferRemoveFromDock(network: entry.network) {
                    Text(String(localized: "The official \(entry.displayName) app is currently pinned in your macOS Dock."))
                        .font(.subheadline)
                    Spacer()
                    Button(String(localized: "Remove \(entry.displayName) from macOS Dock")) {
                        _ = model.removeOfficialAppFromDock(network: entry.network)
                    }
                    .disabled(model.isLocked)
                } else {
                    Text(String(localized: "No duplicate \(entry.displayName) icon is pinned in your macOS Dock."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(8)
        }
    }

    private func developerActionsCard(_ entry: AccountEntry) -> some View {
        GroupBox(String(localized: "Developer")) {
            HStack(spacing: 10) {
                Button(String(localized: "Copy Account ID")) {
                    model.copyAccountID(entry.accountID)
                }
                .disabled(model.isLocked)

                Button(String(localized: "Copy Bridge ID")) {
                    model.copyBridgeID(for: entry.network)
                }
                .disabled(model.isLocked)

                Button(String(localized: "Copy Info as JSON")) {
                    model.copyBridgeInfoJSON(for: entry.network)
                }
                .disabled(model.isLocked)

                Spacer()

                Button(String(localized: "Restart Bridge")) {
                    Task { await model.restartBridge(network: entry.network) }
                }
                .disabled(model.isLocked || model.busyNetworks.contains(entry.network))
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    private func statusColor(_ state: AccountState) -> Color {
        switch state {
        case .connected, .running: return .green
        case .connecting, .backfilling: return .blue
        case .transientDisconnect, .bridgeUnreachable: return .orange
        case .loggedOut, .badCredentials, .unknownError: return .red
        default: return .gray
        }
    }

    private func stateLabel(_ state: AccountState) -> String {
        AccountsAndBridgesModel.statusLabel(for: state)
    }
}

/// Plain-English destructive confirmation dialog for `Remove Account…`.
struct RemoveAccountConfirmationSheet: View {
    @Binding var confirmation: RemoveAccountConfirmation
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text(confirmation.title)
                    .font(.headline)
            }

            Text(confirmation.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(confirmation.logoutToggleLabel, isOn: $confirmation.logoutRemote)
                Toggle(confirmation.deleteChatsToggleLabel, isOn: $confirmation.deleteChats)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            HStack {
                Spacer()
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Remove Account"), role: .destructive) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
