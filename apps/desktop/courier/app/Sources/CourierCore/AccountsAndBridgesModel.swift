// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

/// Service for inspecting and removing an official messaging app's tile from the macOS Dock (`02` §1.4).
public protocol DockTileService: Sendable {
    func isAppInDock(bundleIdentifier: String) -> Bool
    func removeAppFromDock(bundleIdentifier: String) -> Bool
}

public struct MACDockTileService: DockTileService {
    public init() {}

    public func isAppInDock(bundleIdentifier: String) -> Bool {
        guard let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
              let persistentApps = dockDefaults.array(forKey: "persistent-apps") as? [[String: Any]] else {
            return false
        }
        return persistentApps.contains { entry in
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let bundleID = tileData["bundle-identifier"] as? String else {
                return false
            }
            return bundleID.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }

    public func removeAppFromDock(bundleIdentifier: String) -> Bool {
        guard MainActor.assumeIsolated({ AppLockGate.shared.canPerform(.settingsChange) }),
              let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
              var persistentApps = dockDefaults.array(forKey: "persistent-apps") as? [[String: Any]] else {
            return false
        }
        let originalCount = persistentApps.count
        persistentApps.removeAll { entry in
            guard let tileData = entry["tile-data"] as? [String: Any],
                  let bundleID = tileData["bundle-identifier"] as? String else {
                return false
            }
            return bundleID.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        guard persistentApps.count < originalCount else { return false }
        dockDefaults.set(persistentApps, forKey: "persistent-apps")
        dockDefaults.synchronize()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        proc.arguments = ["Dock"]
        try? proc.run()
        return true
    }
}

/// Destructive confirmation state for removing a connected account (`02` §1.4).
public struct RemoveAccountConfirmation: Equatable, Identifiable, Sendable {
    public let network: String
    public let displayName: String
    public let accountID: String
    public let remoteName: String
    public var logoutRemote: Bool
    public var deleteChats: Bool

    public var id: String { "\(network):\(accountID)" }

    public init(
        network: String,
        displayName: String,
        accountID: String,
        remoteName: String,
        logoutRemote: Bool,
        deleteChats: Bool = false
    ) {
        self.network = network
        self.displayName = displayName
        self.accountID = accountID
        self.remoteName = remoteName
        self.logoutRemote = logoutRemote
        self.deleteChats = deleteChats
    }

    public var accountLabel: String {
        remoteName.isEmpty ? accountID : remoteName
    }

    public var title: String {
        String(localized: "Remove \(displayName) account?")
    }

    /// Plain-English description of what removing this account deletes.
    public var message: String {
        let remotePart: String
        if logoutRemote {
            remotePart = String(localized: "This will sign out \(accountLabel) on \(displayName) and remove its login from Courier.")
        } else {
            remotePart = String(localized: "This will disconnect \(accountLabel) from Courier without signing out your \(displayName) session.")
        }
        let localPart: String
        if deleteChats {
            localPart = String(localized: "All local chats and messages for this account on this Mac will be permanently deleted.")
        } else {
            localPart = String(localized: "Your existing local chats and messages will stay on this Mac unless you choose to delete them.")
        }
        return "\(remotePart) \(localPart)"
    }

    public var logoutToggleLabel: String {
        if network == "slack" {
            return String(localized: "Also sign out on Slack (revokes your web session)")
        }
        return String(localized: "Also sign out / unlink on \(displayName)")
    }

    public var deleteChatsToggleLabel: String {
        String(localized: "Delete local chat history on this Mac")
    }
}

/// Model driving Settings ▸ Accounts and Settings ▸ Bridges (`02` §1.4, §1.8).
@MainActor
public final class AccountsAndBridgesModel: ObservableObject {
    @Published public private(set) var bridges: [BridgeInfo] = []
    @Published public private(set) var subAccountsByKey: [String: [SubAccountItem]] = [:]
    @Published public var selectedAccountKey: String? // "network:accountID"
    @Published public var expandedBridgeNetworks: Set<String> = []
    @Published public private(set) var busyNetworks: Set<String> = []
    @Published public private(set) var lastToast: String?
    @Published public private(set) var lastError: String?
    @Published public var pendingRemoval: RemoveAccountConfirmation?
    @Published public var pendingRestartNetwork: String?

    private let appModel: AppModel
    private let dockTileService: DockTileService
    private let pasteboard: TextPasteboard
    private weak var explicitLifecycle: SystemLifecycleModel?
    private weak var observedLifecycle: SystemLifecycleModel?
    private var lockObserver: AnyCancellable?

    public init(
        appModel: AppModel,
        dockTileService: DockTileService = MACDockTileService(),
        pasteboard: TextPasteboard = SystemPasteboard(),
        lifecycle: SystemLifecycleModel? = nil
    ) {
        self.appModel = appModel
        self.dockTileService = dockTileService
        self.pasteboard = pasteboard
        self.explicitLifecycle = lifecycle

        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
                self?.dismissAllPresentations()
            }

        appModel.onConnect { [weak self] _ in
            await self?.refresh()
        }
        appModel.onChange { [weak self] change in
            switch change {
            case .bridge, .spaces:
                Task { @MainActor in
                    await self?.refresh()
                }
            default:
                break
            }
        }
    }

    public func dismissAllPresentations() {
        pendingRemoval = nil
        pendingRestartNetwork = nil
    }

    private var resolvedLifecycle: SystemLifecycleModel {
        explicitLifecycle ?? observedLifecycle ?? AppLockGate.shared.lifecycle
    }

    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.settingsChange, lifecycle: resolvedLifecycle)
    }

    nonisolated public static func accountKey(network: String, accountID: String) -> String {
        "\(network):\(accountID)"
    }

    /// Plain-English status words for a bridge or account connection state (`02` §1.4).
    /// Never returns raw uppercase protocol codes (`CONNECTED`, `BAD_CREDENTIALS`, etc.).
    nonisolated public static func statusLabel(for state: AccountState) -> String {
        statusLabel(for: state.rawValue)
    }

    nonisolated public static func statusLabel(for rawState: String) -> String {
        switch rawState {
        case "CONNECTED", "RUNNING", "OK":
            return String(localized: "Connected")
        case "STARTING":
            return String(localized: "Starting…")
        case "CONNECTING":
            return String(localized: "Connecting…")
        case "BACKFILLING":
            return String(localized: "Syncing…")
        case "TRANSIENT_DISCONNECT":
            return String(localized: "Reconnecting…")
        case "BRIDGE_UNREACHABLE":
            return String(localized: "Unreachable")
        case "BAD_CREDENTIALS":
            return String(localized: "Signed out — reconnect")
        case "LOGGED_OUT":
            return String(localized: "Signed out")
        case "UNKNOWN_ERROR", "DISCONNECTED":
            return String(localized: "Connection error")
        case "UNCONFIGURED":
            return String(localized: "Not linked")
        case "NOT_STARTED", "STOPPED":
            return String(localized: "Not started")
        default:
            let cleaned = rawState
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard let first = cleaned.first else {
                return String(localized: "Disconnected")
            }
            return first.uppercased() + cleaned.dropFirst()
        }
    }

    /// Per-network default for `logout_remote`: Slack defaults to `false` because `SlackClient.LogoutRemote`
    /// calls `auth.signout`, revoking the workspace `xoxc-` cookie token across browser sessions.
    /// WhatsApp, Signal, Telegram, and Google Messages default to `true`.
    public static func defaultLogoutRemote(for network: String) -> Bool {
        network != "slack"
    }

    /// Official desktop bundle ID for each supported network (`nil` for Google Messages).
    public static func officialDockBundleID(for network: String) -> String? {
        switch network {
        case "whatsapp": return "net.whatsapp.WhatsApp"
        case "signal": return "org.whispersystems.signal-desktop"
        case "telegram": return "ru.keepcoder.Telegram"
        case "slack": return "com.tinyspeck.slackmacgap"
        case "gmessages": return nil
        default: return nil
        }
    }

    public func canOfferRemoveFromDock(network: String) -> Bool {
        guard let bundleID = Self.officialDockBundleID(for: network) else { return false }
        return dockTileService.isAppInDock(bundleIdentifier: bundleID)
    }

    @discardableResult
    public func removeOfficialAppFromDock(network: String) -> Bool {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return false
        }
        guard let bundleID = Self.officialDockBundleID(for: network) else { return false }
        let removed = dockTileService.removeAppFromDock(bundleIdentifier: bundleID)
        if removed {
            lastToast = String(localized: "Removed from Dock")
        }
        return removed
    }

    public func refresh() async {
        guard !isLocked, let client = appModel.client else { return }
        do {
            let res: BridgesResult = try await client.call("bridges.list", Empty())
            bridges = res.bridges
            // Read again, so an earlier failure to read (an engine restarting, say) no longer stands.
            lastError = nil
            if selectedAccountKey == nil {
                for br in res.bridges {
                    for acct in br.accounts {
                        if let firstLogin = acct.logins.first {
                            selectedAccountKey = Self.accountKey(network: br.network, accountID: firstLogin.accountID)
                            return
                        }
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func requestRestartBridge(network: String) {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return
        }
        pendingRestartNetwork = network
    }

    public func cancelRestartBridge() {
        pendingRestartNetwork = nil
    }

    public func confirmRestartBridge() async {
        guard let network = pendingRestartNetwork else { return }
        pendingRestartNetwork = nil
        await restartBridge(network: network)
    }

    public func restartBridge(network: String) async {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return
        }
        guard let client = appModel.client else { return }
        busyNetworks.insert(network)
        defer { busyNetworks.remove(network) }
        do {
            let _: Empty = try await client.call("bridges.restart", BridgeRestartParams(network: network))
            lastError = nil
            lastToast = String(localized: "Bridge restarted")
            await refresh()
            await appModel.refreshAccounts()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func requestRemoveAccount(
        network: String,
        accountID: String,
        remoteName: String = "",
        displayName: String? = nil
    ) {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return
        }
        let resolvedDisplayName = displayName
            ?? bridges.first(where: { $0.network == network })?.displayName
            ?? appModel.accounts.first(where: { $0.network == network })?.displayName
            ?? network.capitalized
        let resolvedRemoteName: String
        if !remoteName.isEmpty {
            resolvedRemoteName = remoteName
        } else {
            resolvedRemoteName = bridges
                .first(where: { $0.network == network })?
                .accounts
                .flatMap(\.logins)
                .first(where: { $0.accountID == accountID })?
                .remoteName ?? accountID
        }
        pendingRemoval = RemoveAccountConfirmation(
            network: network,
            displayName: resolvedDisplayName,
            accountID: accountID,
            remoteName: resolvedRemoteName,
            logoutRemote: Self.defaultLogoutRemote(for: network),
            deleteChats: false
        )
    }

    public func cancelRemoveAccount() {
        pendingRemoval = nil
    }

    public func confirmRemoveAccount() async {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        await removeAccount(
            network: pending.network,
            accountID: pending.accountID,
            logoutRemote: pending.logoutRemote,
            deleteChats: pending.deleteChats
        )
    }

    public func removeAccount(
        network: String,
        accountID: String,
        logoutRemote: Bool? = nil,
        deleteChats: Bool = false
    ) async {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return
        }
        guard let client = appModel.client else { return }
        let resolvedLogout = logoutRemote ?? Self.defaultLogoutRemote(for: network)
        busyNetworks.insert(network)
        defer { busyNetworks.remove(network) }
        do {
            let _: Empty = try await client.call(
                "accounts.remove",
                AccountRemoveParams(
                    network: network,
                    accountID: accountID,
                    logoutRemote: resolvedLogout,
                    deleteChats: deleteChats
                )
            )
            let key = Self.accountKey(network: network, accountID: accountID)
            subAccountsByKey.removeValue(forKey: key)
            if selectedAccountKey == key {
                selectedAccountKey = nil
            }
            lastError = nil
            lastToast = String(localized: "Account removed")
            await refresh()
            await appModel.refreshAccounts()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func loadSubAccounts(network: String, accountID: String, forceRefresh: Bool = false) async {
        guard !isLocked, let client = appModel.client else { return }
        do {
            let res: SubAccountsResult = try await client.call(
                "accounts.subAccounts",
                SubAccountsParams(
                    network: network,
                    accountID: accountID,
                    refresh: forceRefresh ? true : nil
                )
            )
            subAccountsByKey[Self.accountKey(network: network, accountID: accountID)] = res.subAccounts
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func updateSubAccount(
        network: String,
        accountID: String,
        subID: String,
        enabled: Bool? = nil,
        showInInbox: ShowInInbox? = nil
    ) async {
        guard !isLocked else {
            lastError = String(localized: "Courier is locked")
            return
        }
        guard let client = appModel.client else { return }
        do {
            let _: Empty = try await client.call(
                "accounts.setSubAccount",
                SetSubAccountParams(
                    network: network,
                    accountID: accountID,
                    subID: subID,
                    enabled: enabled,
                    showInInbox: showInInbox
                )
            )
            let key = Self.accountKey(network: network, accountID: accountID)
            if var current = subAccountsByKey[key],
               let idx = current.firstIndex(where: { $0.subID == subID }) {
                var updated = current[idx]
                updated = SubAccountItem(
                    network: updated.network,
                    accountID: updated.accountID,
                    subID: updated.subID,
                    title: updated.title,
                    avatarURI: updated.avatarURI,
                    kind: updated.kind,
                    enabled: enabled ?? updated.enabled,
                    showInInbox: showInInbox ?? updated.showInInbox
                )
                current[idx] = updated
                subAccountsByKey[key] = current
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func bridgeJSON(for network: String) -> String? {
        guard let br = bridges.first(where: { $0.network == network }) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(br) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func copyAccountID(_ accountID: String) {
        guard !isLocked, !accountID.isEmpty else { return }
        pasteboard.setString(accountID)
        lastToast = String(localized: "Account ID copied")
    }

    public func copyRemoteID(_ remoteID: String) {
        guard !isLocked, !remoteID.isEmpty else { return }
        pasteboard.setString(remoteID)
        lastToast = String(localized: "Remote ID copied")
    }

    public func copyBridgeID(for network: String) {
        guard !isLocked else { return }
        let id = bridges.first(where: { $0.network == network })?.bridgeID ?? network
        pasteboard.setString(id)
        lastToast = String(localized: "Bridge ID copied")
    }

    public func copyBridgeInfoJSON(for network: String) {
        guard !isLocked, let json = bridgeJSON(for: network) else { return }
        pasteboard.setString(json)
        lastToast = String(localized: "Bridge info copied")
    }

    public func toggleBridgeExpanded(_ network: String) {
        if expandedBridgeNetworks.contains(network) {
            expandedBridgeNetworks.remove(network)
        } else {
            expandedBridgeNetworks.insert(network)
        }
    }

    public func selectAccount(network: String, accountID: String) {
        selectedAccountKey = Self.accountKey(network: network, accountID: accountID)
    }

    /// Populates model state directly for snapshot and unit tests without a running engine.
    public func setSnapshotStateForTesting(
        bridges: [BridgeInfo],
        subAccountsByKey: [String: [SubAccountItem]] = [:],
        selectedAccountKey: String? = nil,
        expandedBridgeNetworks: Set<String> = []
    ) {
        self.bridges = bridges
        self.subAccountsByKey = subAccountsByKey
        self.selectedAccountKey = selectedAccountKey
        self.expandedBridgeNetworks = expandedBridgeNetworks
    }
}
