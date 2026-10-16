// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import RemoteMenuCore
import VitruvianToolKit
import VitruvianToolProtocol

/// Pure UI state and Protocol 2 page builders for the Vitruvian Remote extension
/// (`dev.vitruvian.remote`).
public enum RemotePages {
    public enum SettingsSection: String, CaseIterable, Equatable, Sendable {
        case general
        case pairing
        case notifications
        case integrations

        public var blockID: String {
            switch self {
            case .general: return Block.tabGeneral
            case .pairing: return Block.tabPairing
            case .notifications: return Block.tabNotifications
            case .integrations: return Block.tabIntegrations
            }
        }

        public var title: String {
            switch self {
            case .general: return "General"
            case .pairing: return "Pairing & Bridge"
            case .notifications: return "Notifications"
            case .integrations: return "Integrations"
            }
        }
    }

    public struct ActiveQRSession: Equatable, Sendable {
        public var code: String
        public var address: String
        public var url: URL
        public var pngDataURL: String
        public var expiresAt: Date

        public init(code: String, address: String, url: URL, pngDataURL: String, expiresAt: Date) {
            self.code = code
            self.address = address
            self.url = url
            self.pngDataURL = pngDataURL
            self.expiresAt = expiresAt
        }
    }

    public struct ChoiceConfirmationDraft: Equatable, Sendable {
        public var copyFromStandalone: Bool
        public var disableStandaloneAtLogin: Bool
        public var trashStandaloneApp: Bool

        public init(
            copyFromStandalone: Bool = true,
            disableStandaloneAtLogin: Bool = true,
            trashStandaloneApp: Bool = false
        ) {
            self.copyFromStandalone = copyFromStandalone
            self.disableStandaloneAtLogin = disableStandaloneAtLogin
            self.trashStandaloneApp = trashStandaloneApp
        }
    }

    public struct State: Equatable, Sendable {
        public var profile: RemoteProfile
        public var role: RemoteRole
        public var settings: RemoteSettings
        public var snapshot: StatusSnapshot
        public var tailscaleAddress: String?
        public var isPairedOnDisk: Bool
        public var notifyEnabled: Bool
        public var hasNtfyToken: Bool
        public var hasPrometheusToken: Bool
        public var permissionHookInstalled: Bool
        public var section: SettingsSection
        public var activeQR: ActiveQRSession?
        public var pairCodeDraft: String
        public var confirmingUnpair: Bool
        public var confirmingUseExtension: Bool
        public var choiceDraft: ChoiceConfirmationDraft
        public var appSummary: RemoteSideSummary
        public var extensionSummary: RemoteSideSummary
        public var standaloneAppBundleExists: Bool
        public var notice: String?

        public init(
            profile: RemoteProfile,
            role: RemoteRole = .activeAlone,
            settings: RemoteSettings = RemoteSettings(),
            snapshot: StatusSnapshot = StatusSnapshot(state: .down),
            tailscaleAddress: String? = nil,
            isPairedOnDisk: Bool = false,
            notifyEnabled: Bool = true,
            hasNtfyToken: Bool = false,
            hasPrometheusToken: Bool = false,
            permissionHookInstalled: Bool = false,
            section: SettingsSection = .general,
            activeQR: ActiveQRSession? = nil,
            pairCodeDraft: String = "",
            confirmingUnpair: Bool = false,
            confirmingUseExtension: Bool = false,
            choiceDraft: ChoiceConfirmationDraft = ChoiceConfirmationDraft(),
            appSummary: RemoteSideSummary = RemoteSideSummary(door: .app),
            extensionSummary: RemoteSideSummary = RemoteSideSummary(door: .extension),
            standaloneAppBundleExists: Bool = false,
            notice: String? = nil
        ) {
            self.profile = profile
            self.role = role
            self.settings = settings
            self.snapshot = snapshot
            self.tailscaleAddress = tailscaleAddress
            self.isPairedOnDisk = isPairedOnDisk
            self.notifyEnabled = notifyEnabled
            self.hasNtfyToken = hasNtfyToken
            self.hasPrometheusToken = hasPrometheusToken
            self.permissionHookInstalled = permissionHookInstalled
            self.section = section
            self.activeQR = activeQR
            self.pairCodeDraft = pairCodeDraft
            self.confirmingUnpair = confirmingUnpair
            self.confirmingUseExtension = confirmingUseExtension
            self.choiceDraft = choiceDraft
            self.appSummary = appSummary
            self.extensionSummary = extensionSummary
            self.standaloneAppBundleExists = standaloneAppBundleExists
            self.notice = notice
        }
    }

    public enum Block {
        // Coexistence / handoff
        public static let chooseExtension = "chooseExtension"
        public static let chooseStandaloneApp = "chooseStandaloneApp"
        public static let copyFromStandalone = "copyFromStandalone"
        public static let disableStandaloneAtLogin = "disableStandaloneAtLogin"
        public static let trashStandaloneApp = "trashStandaloneApp"
        public static let confirmUseExtension = "confirmUseExtension"
        public static let cancelChoiceStep = "cancelChoiceStep"
        public static let switchToExtension = "switchToExtension"
        public static let switchToStandaloneApp = "switchToStandaloneApp"
        public static let copyFromStandaloneNow = "copyFromStandaloneNow"

        // Status rows
        public static let statusAgent = "statusAgent"
        public static let statusPhone = "statusPhone"
        public static let statusTailnet = "statusTailnet"
        public static let statusNotifications = "statusNotifications"
        public static let statusClaudeHook = "statusClaudeHook"

        // Island actions
        public static let islandToggleNotifications = "islandToggleNotifications"
        public static let islandTogglePermissionHook = "islandTogglePermissionHook"
        public static let islandRestartAgent = "islandRestartAgent"
        public static let islandPairWithQR = "islandPairWithQR"
        public static let islandDismissQR = "islandDismissQR"
        public static let islandPairCodeField = "islandPairCodeField"
        public static let islandPairWithCode = "islandPairWithCode"
        public static let islandAskUnpair = "islandAskUnpair"
        public static let islandConfirmUnpair = "islandConfirmUnpair"
        public static let islandCancelUnpair = "islandCancelUnpair"

        // Settings tabs
        public static let tabGeneral = "tabGeneral"
        public static let tabPairing = "tabPairing"
        public static let tabNotifications = "tabNotifications"
        public static let tabIntegrations = "tabIntegrations"

        // Settings > General
        public static let autoStartAgent = "autoStartAgent"
        public static let tailscaleEnabled = "tailscaleEnabled"
        public static let intervalSeconds = "intervalSeconds"
        public static let restartAgent = "restartAgent"
        public static let openLog = "openLog"

        // Settings > Pairing & Bridge
        public static let settingsPairWithQR = "settingsPairWithQR"
        public static let settingsDismissQR = "settingsDismissQR"
        public static let settingsPairCodeField = "settingsPairCodeField"
        public static let settingsPairWithCode = "settingsPairWithCode"
        public static let settingsAskUnpair = "settingsAskUnpair"
        public static let settingsConfirmUnpair = "settingsConfirmUnpair"
        public static let settingsCancelUnpair = "settingsCancelUnpair"
        public static let permissionHookToggle = "permissionHookToggle"
        public static let permissionWaitSeconds = "permissionWaitSeconds"
        public static let mcpBridgeStatus = "mcpBridgeStatus"
        public static let copyMCPCommand = "copyMCPCommand"

        // Settings > Notifications
        public static let notifyEnabledToggle = "notifyEnabledToggle"
        public static let ntfyURL = "ntfyURL"
        public static let ntfyTopic = "ntfyTopic"
        public static let ntfyTokenStatus = "ntfyTokenStatus"
        public static let ntfyTokenField = "ntfyTokenField"
        public static let clearNtfyToken = "clearNtfyToken"

        // Settings > Integrations
        public static let execDir = "execDir"
        public static let ghExtraRepos = "ghExtraRepos"
        public static let kubeconfig = "kubeconfig"
        public static let kubeContext = "kubeContext"
        public static let prometheusURL = "prometheusURL"
        public static let prometheusTokenStatus = "prometheusTokenStatus"
        public static let prometheusTokenField = "prometheusTokenField"
        public static let clearPrometheusToken = "clearPrometheusToken"
        public static let settingsFilePath = "settingsFilePath"
        public static let configDirPath = "configDirPath"
        public static let logFilePath = "logFilePath"
    }

    // MARK: - Closed-Island Status Mark

    public struct StatusMark: Equatable, Sendable {
        public var state: StatusState
        public var text: String
        public var icon: String?

        public init(state: StatusState, text: String, icon: String? = nil) {
            self.state = state
            self.text = text
            self.icon = icon
        }
    }

    /// Computes the closed-island status mark for `state`.
    public static func statusMark(for state: State, now: Date = Date()) -> StatusMark {
        switch state.role {
        case .quietChosen:
            return StatusMark(state: .none, text: "")
        case .quietAsking:
            return StatusMark(
                state: .attention,
                text: "Both Vitruvian Remote and the extension are installed — choose one",
                icon: "exclamationmark.triangle"
            )
        case .activeAlone, .activeChosen, .activeAsking:
            break
        }

        switch state.snapshot.state {
        case .notInstalled, .down, .stale:
            return StatusMark(
                state: .failure,
                text: state.snapshot.agentLine,
                icon: "exclamationmark.triangle"
            )
        case .running:
            if state.snapshot.tailnetReachable == false {
                return StatusMark(
                    state: .failure,
                    text: "Phone can't reach this Mac over Tailscale",
                    icon: "wifi.exclamationmark"
                )
            }
            let paired = state.snapshot.health?.paired ?? state.isPairedOnDisk
            if !paired {
                return StatusMark(
                    state: .attention,
                    text: "No phone paired",
                    icon: "iphone.slash"
                )
            }
            if state.snapshot.phone?.connected == true {
                return StatusMark(
                    state: .ok,
                    text: state.snapshot.phoneLine(now: now) ?? "Phone connected",
                    icon: "iphone.radiowaves.left.and.right"
                )
            }
            return StatusMark(
                state: .ok,
                text: "Phone paired · Agent running",
                icon: "iphone"
            )
        }
    }

    // MARK: - Dynamic Island Page

    public static func islandPage(_ state: State, now: Date = Date()) -> UITree {
        var blocks: [UIBlock] = []
        if let notice = state.notice, !notice.isEmpty {
            blocks.append(text(.plain(notice), style: .caption))
            blocks.append(divider())
        }

        switch state.role {
        case .quietAsking:
            blocks += coexistenceAskingBlocks(state)
            return UITree(blocks: blocks)
        case .quietChosen:
            blocks += coexistenceQuietChosenBlocks()
            return UITree(blocks: blocks)
        case .activeAlone, .activeChosen, .activeAsking:
            break
        }

        blocks += liveStatusBlocks(state, now: now)
        blocks.append(divider())

        if state.settings.notificationsConfigured {
            blocks.append(
                toggle(
                    Block.islandToggleNotifications,
                    .plain("Push notifications"),
                    isOn: state.notifyEnabled
                )
            )
        }
        blocks.append(
            toggle(
                Block.islandTogglePermissionHook,
                .plain("Answer Claude Code prompts on phone"),
                isOn: state.permissionHookInstalled
            )
        )
        blocks.append(
            button(
                Block.islandRestartAgent,
                .plain(state.snapshot.state.isHealthy ? "Restart Agent" : "Start Agent")
            )
        )

        blocks.append(divider())
        blocks += pairingBlocks(
            state,
            qrButtonID: Block.islandPairWithQR,
            dismissQRButtonID: Block.islandDismissQR,
            codeFieldID: Block.islandPairCodeField,
            codeButtonID: Block.islandPairWithCode,
            askUnpairID: Block.islandAskUnpair,
            confirmUnpairID: Block.islandConfirmUnpair,
            cancelUnpairID: Block.islandCancelUnpair
        )

        return UITree(blocks: blocks)
    }

    // MARK: - Settings Page

    public static func settingsPage(_ state: State, now: Date = Date()) -> UITree {
        var blocks: [UIBlock] = []
        if let notice = state.notice, !notice.isEmpty {
            blocks.append(text(.plain(notice), style: .caption))
            blocks.append(divider())
        }

        switch state.role {
        case .quietAsking:
            blocks += coexistenceAskingBlocks(state)
            return UITree(blocks: blocks)
        case .quietChosen:
            blocks += coexistenceQuietChosenBlocks()
            return UITree(blocks: blocks)
        case .activeAlone, .activeChosen, .activeAsking:
            break
        }

        // Section tabs
        for sec in SettingsSection.allCases {
            blocks.append(
                button(
                    sec.blockID,
                    .plain(sec.title),
                    style: state.section == sec ? .prominent : nil
                )
            )
        }
        blocks.append(divider())

        switch state.section {
        case .general:
            blocks += generalSectionBlocks(state, now: now)
        case .pairing:
            blocks += pairingSectionBlocks(state)
        case .notifications:
            blocks += notificationsSectionBlocks(state)
        case .integrations:
            blocks += integrationsSectionBlocks(state)
        }

        return UITree(blocks: blocks)
    }

    // MARK: - Coexistence Blocks

    private static func coexistenceAskingBlocks(_ state: State) -> [UIBlock] {
        var blocks: [UIBlock] = [
            heading(.plain("Choose One Vitruvian Remote")),
            text(
                .plain("Both the standalone Vitruvian Remote setup and the Vitruvian extension are installed on this Mac. Only one should run the agent on port 7411."),
                style: .caption
            ),
            row(
                "summaryStandalone",
                .plain("Standalone setup"),
                subtitle: .plain(state.appSummary.summaryLine),
                icon: "macwindow"
            ),
            row(
                "summaryExtension",
                .plain("Vitruvian extension"),
                subtitle: .plain(state.extensionSummary.summaryLine),
                icon: "puzzlepiece.extension"
            ),
        ]

        if state.confirmingUseExtension {
            blocks.append(divider())
            blocks.append(
                toggle(
                    Block.copyFromStandalone,
                    .plain("Copy pairing, tokens, and settings from the standalone setup"),
                    isOn: state.choiceDraft.copyFromStandalone
                )
            )
            blocks.append(
                toggle(
                    Block.disableStandaloneAtLogin,
                    .plain("Stop the standalone LaunchAgent at login"),
                    isOn: state.choiceDraft.disableStandaloneAtLogin
                )
            )
            if state.standaloneAppBundleExists {
                blocks.append(
                    toggle(
                        Block.trashStandaloneApp,
                        .plain("Move VitruvianRemote.app to the Trash"),
                        isOn: state.choiceDraft.trashStandaloneApp
                    )
                )
            }
            blocks.append(
                button(
                    Block.confirmUseExtension,
                    .plain("Switch to the Extension"),
                    style: .prominent
                )
            )
            blocks.append(
                button(
                    Block.cancelChoiceStep,
                    .plain("Back")
                )
            )
        } else {
            blocks.append(
                button(
                    Block.chooseExtension,
                    .plain("Use the Vitruvian Extension"),
                    style: .prominent
                )
            )
            blocks.append(
                button(
                    Block.chooseStandaloneApp,
                    .plain("Keep Using the Standalone App")
                )
            )
        }
        return blocks
    }

    private static func coexistenceQuietChosenBlocks() -> [UIBlock] {
        [
            heading(.plain("Standalone App in Use")),
            text(
                .plain("Vitruvian Remote is running through the standalone app. This extension is quiet so the two never conflict on port 7411."),
                style: .caption
            ),
            button(
                Block.switchToExtension,
                .plain("Use the Vitruvian Extension Instead"),
                style: .prominent
            ),
        ]
    }

    // MARK: - Live Status Blocks

    private static func liveStatusBlocks(_ state: State, now: Date) -> [UIBlock] {
        var blocks: [UIBlock] = []
        let agentSubtitle: String
        if let ts = state.tailscaleAddress {
            agentSubtitle = "Tailscale \(ts):7411"
        } else {
            agentSubtitle = "Loopback 127.0.0.1:7411 · Tailscale not connected"
        }
        blocks.append(
            row(
                Block.statusAgent,
                .plain(state.snapshot.agentLine),
                subtitle: .plain(agentSubtitle),
                icon: state.snapshot.state.isHealthy ? "waveform.path.ecg" : "exclamationmark.triangle"
            )
        )

        let paired = state.snapshot.health?.paired ?? state.isPairedOnDisk
        let phoneTitle = state.snapshot.phoneLine(now: now)
            ?? (paired ? "Phone paired (agent offline)" : "No phone paired")
        let phoneSubtitle: String?
        if let tools = state.snapshot.phone?.tools, state.snapshot.phone?.connected == true {
            phoneSubtitle = tools.isEmpty
                ? "Phone bridge connected"
                : "\(tools.count) phone tool\(tools.count == 1 ? "" : "s") ready on /mcp/phone"
        } else {
            phoneSubtitle = nil
        }
        let phoneIcon: String
        if state.snapshot.phone?.connected == true {
            phoneIcon = "iphone.radiowaves.left.and.right"
        } else if paired {
            phoneIcon = "iphone"
        } else {
            phoneIcon = "iphone.slash"
        }
        blocks.append(
            row(
                Block.statusPhone,
                .plain(phoneTitle),
                subtitle: phoneSubtitle.map(UIText.plain),
                icon: phoneIcon
            )
        )

        if let tailnetWarning = state.snapshot.tailnetLine {
            blocks.append(
                row(
                    Block.statusTailnet,
                    .plain(tailnetWarning),
                    icon: "wifi.exclamationmark"
                )
            )
        }

        let notifyTitle: String
        if let line = state.snapshot.notificationsLine {
            notifyTitle = line
        } else if state.settings.notificationsConfigured {
            notifyTitle = state.notifyEnabled ? "Push notifications on" : "Push notifications off"
        } else {
            notifyTitle = "Push notifications not set up"
        }
        let notifySubtitle = state.settings.notificationsConfigured
            ? "Topic: \(state.settings.ntfyTopic)"
            : nil
        blocks.append(
            row(
                Block.statusNotifications,
                .plain(notifyTitle),
                subtitle: notifySubtitle.map(UIText.plain),
                icon: state.notifyEnabled && state.settings.notificationsConfigured ? "bell.badge" : "bell.slash"
            )
        )

        blocks.append(
            row(
                Block.statusClaudeHook,
                .plain(
                    state.permissionHookInstalled
                        ? "Claude Code permission prompts go to phone"
                        : "Claude Code permission hook off"
                ),
                subtitle: .plain("Waits up to \(state.settings.clampedPermissionWaitSeconds)s before Mac dialog"),
                icon: state.permissionHookInstalled ? "checkmark.shield" : "shield.slash"
            )
        )

        return blocks
    }

    // MARK: - Pairing Blocks (Shared by Island and Settings)

    private static func pairingBlocks(
        _ state: State,
        qrButtonID: String,
        dismissQRButtonID: String,
        codeFieldID: String,
        codeButtonID: String,
        askUnpairID: String,
        confirmUnpairID: String,
        cancelUnpairID: String
    ) -> [UIBlock] {
        var blocks: [UIBlock] = [
            heading(.plain("Pair a Phone")),
            button(
                qrButtonID,
                .plain(state.activeQR != nil ? "New QR Code" : "Pair with QR Code"),
                style: .prominent,
                enabled: state.tailscaleAddress != nil
            ),
        ]

        if state.tailscaleAddress == nil {
            blocks.append(
                text(
                    .plain("Connect Tailscale on this Mac to pair with a QR code, or enter the 6-digit code shown on the phone below."),
                    style: .caption
                )
            )
        }

        if let qr = state.activeQR {
            blocks.append(
                image(
                    qr.pngDataURL,
                    alt: .plain("Pairing QR code for \(qr.url.absoluteString)"),
                    height: 200
                )
            )
            blocks.append(
                text(
                    .plain("Scan with your phone's camera (\(qr.address) · code \(qr.code)). Open the link, tap Open in Vitruvian Remote, then confirm on the phone."),
                    style: .caption
                )
            )
            blocks.append(
                button(
                    dismissQRButtonID,
                    .plain("Hide QR Code")
                )
            )
        }

        blocks.append(
            field(
                codeFieldID,
                title: .plain("Or enter the 6-digit code shown on the phone"),
                value: state.pairCodeDraft,
                placeholder: .plain("482917")
            )
        )
        blocks.append(
            button(
                codeButtonID,
                .plain("Pair with 6-Digit Code")
            )
        )

        let paired = (state.snapshot.health?.paired == true) || state.isPairedOnDisk
        if paired {
            if state.confirmingUnpair {
                blocks.append(
                    text(
                        .plain("Unpairing issues a new bearer token so every previously paired phone must pair again."),
                        style: .caption
                    )
                )
                blocks.append(
                    button(
                        confirmUnpairID,
                        .plain("Unpair All Phones"),
                        style: .destructive
                    )
                )
                blocks.append(
                    button(
                        cancelUnpairID,
                        .plain("Cancel")
                    )
                )
            } else {
                blocks.append(
                    button(
                        askUnpairID,
                        .plain("Unpair All Phones…")
                    )
                )
            }
        }

        return blocks
    }

    // MARK: - Settings Sections

    private static func generalSectionBlocks(_ state: State, now: Date) -> [UIBlock] {
        var blocks: [UIBlock] = []
        if state.role == .activeChosen {
            blocks.append(heading(.plain("Which Vitruvian Remote")))
            blocks.append(
                row(
                    "activeDoorRow",
                    .plain("Using the Vitruvian extension"),
                    subtitle: .plain("The standalone setup is quiet so only one agent runs on port 7411."),
                    icon: "puzzlepiece.extension"
                )
            )
            blocks.append(
                button(
                    Block.copyFromStandaloneNow,
                    .plain("Copy Settings & Pairing from Standalone Setup")
                )
            )
            blocks.append(
                button(
                    Block.switchToStandaloneApp,
                    .plain("Use the Standalone App Instead")
                )
            )
            blocks.append(divider())
        }

        blocks.append(heading(.plain("Agent & Network")))
        blocks += liveStatusBlocks(state, now: now)
        blocks.append(
            toggle(
                Block.autoStartAgent,
                .plain("Keep the agent running while Vitruvian is open"),
                isOn: state.settings.autoStartAgent
            )
        )
        blocks.append(
            toggle(
                Block.tailscaleEnabled,
                .plain("Listen on Tailscale IPv4 (100.64.0.0/10)"),
                isOn: state.settings.tailscale
            )
        )
        blocks.append(
            field(
                Block.intervalSeconds,
                title: .plain("Metrics refresh interval (1–60 seconds)"),
                value: "\(state.settings.clampedIntervalSeconds)",
                placeholder: .plain("2")
            )
        )
        blocks.append(
            button(
                Block.restartAgent,
                .plain(state.snapshot.state.isHealthy ? "Restart Agent" : "Start Agent"),
                style: .prominent
            )
        )
        blocks.append(
            button(
                Block.openLog,
                .plain("Open Agent Log")
            )
        )
        return blocks
    }

    private static func pairingSectionBlocks(_ state: State) -> [UIBlock] {
        var blocks = pairingBlocks(
            state,
            qrButtonID: Block.settingsPairWithQR,
            dismissQRButtonID: Block.settingsDismissQR,
            codeFieldID: Block.settingsPairCodeField,
            codeButtonID: Block.settingsPairWithCode,
            askUnpairID: Block.settingsAskUnpair,
            confirmUnpairID: Block.settingsConfirmUnpair,
            cancelUnpairID: Block.settingsCancelUnpair
        )

        blocks.append(divider())
        blocks.append(heading(.plain("Claude Code Permission Prompts")))
        blocks.append(
            toggle(
                Block.permissionHookToggle,
                .plain("Send Claude Code permission prompts to paired phone"),
                isOn: state.permissionHookInstalled
            )
        )
        blocks.append(
            field(
                Block.permissionWaitSeconds,
                title: .plain("Phone wait timeout before Mac dialog (5–140 seconds)"),
                value: "\(state.settings.clampedPermissionWaitSeconds)",
                placeholder: .plain("120")
            )
        )

        blocks.append(divider())
        blocks.append(heading(.plain("Phone MCP Bridge (/mcp/phone)")))
        let mcpSubtitle: String
        if let tools = state.snapshot.phone?.tools, state.snapshot.phone?.connected == true {
            mcpSubtitle = tools.isEmpty
                ? "Phone connected (no tools advertised)"
                : "Exposed tools: \(tools.joined(separator: ", "))"
        } else {
            mcpSubtitle = "Loopback HTTP MCP endpoint on http://127.0.0.1:7411/mcp/phone"
        }
        blocks.append(
            row(
                Block.mcpBridgeStatus,
                .plain(
                    state.snapshot.phone?.connected == true
                        ? "\(state.snapshot.phone?.device?.model ?? "Phone") bridge connected"
                        : "Phone bridge waiting for phone link"
                ),
                subtitle: .plain(mcpSubtitle),
                icon: "cable.connector.horizontal"
            )
        )
        blocks.append(
            text(.plain(state.profile.mcpAddCommand), style: .caption)
        )
        blocks.append(
            button(
                Block.copyMCPCommand,
                .plain("Copy Claude Code MCP Setup Command")
            )
        )
        return blocks
    }

    private static func notificationsSectionBlocks(_ state: State) -> [UIBlock] {
        var blocks: [UIBlock] = [
            heading(.plain("Push Notifications (ntfy)")),
            text(
                .plain("Publishes high-priority push notifications to your ntfy topic when Claude Code waits on a permission prompt or an agent task needs attention."),
                style: .caption
            ),
            toggle(
                Block.notifyEnabledToggle,
                .plain("Enable push notifications"),
                isOn: state.notifyEnabled,
                enabled: state.settings.notificationsConfigured
            ),
            field(
                Block.ntfyURL,
                title: .plain("ntfy server URL (--ntfy-url)"),
                value: state.settings.ntfyURL,
                placeholder: .plain("https://ntfy.example.dev")
            ),
            field(
                Block.ntfyTopic,
                title: .plain("ntfy topic (--ntfy-topic)"),
                value: state.settings.ntfyTopic,
                placeholder: .plain("vitruvian-remote")
            ),
            row(
                Block.ntfyTokenStatus,
                .plain(
                    state.hasNtfyToken
                        ? "ntfy bearer token saved (0600)"
                        : "No ntfy bearer token saved"
                ),
                icon: state.hasNtfyToken ? "key.fill" : "key"
            ),
            field(
                Block.ntfyTokenField,
                title: .plain("Save or replace ntfy bearer token (optional)"),
                value: "",
                placeholder: .plain("tk_..."),
                kind: .secret
            ),
        ]
        if state.hasNtfyToken {
            blocks.append(
                button(
                    Block.clearNtfyToken,
                    .plain("Clear ntfy Token"),
                    style: .destructive
                )
            )
        }
        return blocks
    }

    private static func integrationsSectionBlocks(_ state: State) -> [UIBlock] {
        var blocks: [UIBlock] = [
            heading(.plain("Command Execution & GitHub")),
            field(
                Block.execDir,
                title: .plain("Working directory for /v1/exec commands (--exec-dir)"),
                value: state.settings.execDir,
                placeholder: .plain("~/Workspace/vitruvian-core")
            ),
            field(
                Block.ghExtraRepos,
                title: .plain("Extra GitHub repositories for /v1/prs (--gh-extra-repos)"),
                value: state.settings.ghExtraRepos,
                placeholder: .plain("owner/repo1,owner/repo2")
            ),
            divider(),
            heading(.plain("Kubernetes & Prometheus")),
            field(
                Block.kubeconfig,
                title: .plain("Kubeconfig file for /v1/k8s (--kubeconfig)"),
                value: state.settings.kubeconfig,
                placeholder: .plain("~/.kube/cluster.yaml")
            ),
            field(
                Block.kubeContext,
                title: .plain("Kubeconfig context (--kube-context)"),
                value: state.settings.kubeContext,
                placeholder: .plain("default")
            ),
            field(
                Block.prometheusURL,
                title: .plain("Prometheus base URL for /v1/promql (--prometheus-url)"),
                value: state.settings.prometheusURL,
                placeholder: .plain("https://grafana.example.dev/api/datasources/proxy/uid/Prometheus")
            ),
            row(
                Block.prometheusTokenStatus,
                .plain(
                    state.hasPrometheusToken
                        ? "Prometheus bearer token saved (0600)"
                        : "No Prometheus bearer token saved"
                ),
                icon: state.hasPrometheusToken ? "key.fill" : "key"
            ),
            field(
                Block.prometheusTokenField,
                title: .plain("Save or replace Prometheus bearer token (optional)"),
                value: "",
                placeholder: .plain("glsa_..."),
                kind: .secret
            ),
        ]
        if state.hasPrometheusToken {
            blocks.append(
                button(
                    Block.clearPrometheusToken,
                    .plain("Clear Prometheus Token"),
                    style: .destructive
                )
            )
        }
        blocks.append(divider())
        blocks.append(heading(.plain("Files")))
        blocks.append(
            row(
                Block.settingsFilePath,
                .plain("Settings file"),
                trailing: .plain(state.profile.settingsURL.path)
            )
        )
        blocks.append(
            row(
                Block.configDirPath,
                .plain("Credentials & pairing directory"),
                trailing: .plain(state.profile.configDirURL.path)
            )
        )
        blocks.append(
            row(
                Block.logFilePath,
                .plain("Agent log file"),
                trailing: .plain(state.profile.logURL.path)
            )
        )
        return blocks
    }
}
