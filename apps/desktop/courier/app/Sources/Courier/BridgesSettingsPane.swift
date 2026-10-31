// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The Bridges settings pane (`02` §1.7): lists the 5 on-device mautrix bridges with state badge,
/// module version, account count, expandable details, and per-bridge / per-account menus.
public struct BridgesSettingsPane: View {
    @ObservedObject var model: AccountsAndBridgesModel
    var onOpenAccountSettings: ((_ network: String, _ accountID: String) -> Void)?
    var onAddAccount: ((_ network: String?) -> Void)?

    public init(
        model: AccountsAndBridgesModel,
        onOpenAccountSettings: ((_ network: String, _ accountID: String) -> Void)? = nil,
        onAddAccount: ((_ network: String?) -> Void)? = nil
    ) {
        self.model = model
        self.onOpenAccountSettings = onOpenAccountSettings
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if model.bridges.isEmpty {
                    Text(String(localized: "No on-device bridges reported."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.bridges) { bridge in
                            bridgeCard(bridge)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            String(localized: "Restart Bridge?"),
            isPresented: Binding(
                get: { model.pendingRestartNetwork != nil },
                set: { if !$0 { model.cancelRestartBridge() } }
            ),
            presenting: model.pendingRestartNetwork
        ) { network in
            let title = model.bridges.first(where: { $0.network == network })?.displayName ?? network
            Button(String(localized: "Restart \(title) Bridge")) {
                Task { await model.confirmRestartBridge() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                model.cancelRestartBridge()
            }
        } message: { network in
            let title = model.bridges.first(where: { $0.network == network })?.displayName ?? network
            Text(String(localized: "Courier will disconnect and reconnect your \(title) accounts on this Mac."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Bridges"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "Each chat network runs inside Courier on this Mac. Expand a bridge to inspect its version, status, or accounts."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bridgeCard(_ bridge: BridgeInfo) -> some View {
        let isExpanded = model.expandedBridgeNetworks.contains(bridge.network)
        let isBusy = model.busyNetworks.contains(bridge.network)
        let logins = bridge.accounts.flatMap(\.logins)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.toggleBridgeExpanded(bridge.network)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        NetworkBadge(network: bridge.network, name: bridge.displayName, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(bridge.displayName)
                                    .font(.body.weight(.medium))
                                stateBadge(bridge.state)
                            }
                            Text(accountCountLabel(logins.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(bridge.version)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.quaternary))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(bridge.displayName) bridge, \(bridge.state)"))

                Menu {
                    Button(String(localized: "Restart Bridge")) {
                        model.requestRestartBridge(network: bridge.network)
                    }
                    .disabled(isBusy || model.isLocked)
                    Divider()
                    Button(String(localized: "Copy bridge ID")) {
                        model.copyBridgeID(for: bridge.network)
                    }
                    .disabled(model.isLocked)
                    Button(String(localized: "Copy bridge info as JSON")) {
                        model.copyBridgeInfoJSON(for: bridge.network)
                    }
                    .disabled(model.isLocked)
                    Divider()
                    Button(String(localized: "Add an account")) {
                        onAddAccount?(bridge.network)
                    }
                    .disabled(model.isLocked)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel(String(localized: "\(bridge.displayName) Bridge Actions"))
            }
            .padding(12)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text(String(localized: "Created:"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(formattedStarted(bridge.startedAt))
                                .font(.caption.monospaced())
                        }
                        GridRow {
                            Text(String(localized: "Version:"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(bridge.modulePath)@\(bridge.version)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        GridRow {
                            Text(String(localized: "Info:"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(bridge.message ?? bridge.error ?? bridge.state)
                                .font(.caption)
                        }
                    }

                    if !logins.isEmpty {
                        Divider()
                            .padding(.vertical, 2)
                        Text(String(localized: "Accounts"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(logins, id: \.accountID) { login in
                            bridgeAccountRow(bridge: bridge, login: login)
                        }
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func bridgeAccountRow(bridge: BridgeInfo, login: Login) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(login.state.rawValue))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(login.remoteName.isEmpty ? login.accountID : login.remoteName)
                    .font(.callout.weight(.medium))
                HStack(spacing: 6) {
                    Text(login.accountID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if !login.remoteName.isEmpty {
                        Text("· \(login.remoteName)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(login.state.rawValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Menu {
                Button(String(localized: "Account Settings…")) {
                    model.selectAccount(network: bridge.network, accountID: login.accountID)
                    onOpenAccountSettings?(bridge.network, login.accountID)
                }
                Divider()
                Button(String(localized: "Copy Account ID")) {
                    model.copyAccountID(login.accountID)
                }
                if !login.remoteName.isEmpty {
                    Button(String(localized: "Copy Remote ID")) {
                        model.copyRemoteID(login.remoteName)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel(String(localized: "Account actions for \(login.remoteName.isEmpty ? login.accountID : login.remoteName)"))
        }
        .padding(.vertical, 4)
    }

    private func stateBadge(_ state: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(state))
                .frame(width: 6, height: 6)
            Text(state)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(statusColor(state).opacity(0.14)))
    }

    private func statusColor(_ state: String) -> Color {
        switch state {
        case "OK", "RUNNING", "CONNECTED": return .green
        case "STARTING", "CONNECTING", "BACKFILLING", "TRANSIENT_DISCONNECT": return .orange
        case "DISCONNECTED", "BAD_CREDENTIALS", "STOPPED", "LOGGED_OUT", "UNKNOWN_ERROR", "BRIDGE_UNREACHABLE": return .red
        default: return .secondary
        }
    }

    private func accountCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 account")
            : String(localized: "\(count) accounts")
    }

    private func formattedStarted(_ ms: Int64) -> String {
        guard ms > 0 else { return String(localized: "Not started") }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
