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

import AppKit
import Foundation
import RemoteMenuCore
import VitruvianToolKit
import VitruvianToolProtocol

/// Coordinates the Vitruvian Remote extension (`dev.vitruvian.remote`): manages
/// settings, coexistence with the standalone app, `vitruvian-remote-agent` supervision,
/// QR and 6-digit pairing, and Protocol 2 panel events and commands.
public final class RemoteToolController: @unchecked Sendable {
    public static let islandPanelID = "remote"
    public static let settingsPanelID = "settings"

    public enum Command {
        public static let pairWithQR = "pairWithQR"
        public static let restartAgent = "restartAgent"
        public static let toggleNotifications = "toggleNotifications"
        public static let togglePermissionHook = "togglePermissionHook"
        public static let copyMCPCommand = "copyMCPCommand"
        public static let openLog = "openLog"

        public static let all: [String] = [
            pairWithQR,
            restartAgent,
            toggleNotifications,
            togglePermissionHook,
            copyMCPCommand,
            openLog,
        ]
    }

    public let profile: RemoteProfile
    public let appProfile: RemoteProfile
    public let home: URL
    public let settingsStore: RemoteSettingsStore
    public let supervisor: AgentSupervisor
    private let pollSnapshot: @Sendable () -> StatusSnapshot
    private let resolveTailscaleAddress: @Sendable () -> String?
    private let checkStandaloneInstalled: @Sendable () -> Bool
    private let checkStandaloneAppBundleExists: @Sendable () -> Bool
    private let terminateStandaloneApp: @Sendable () -> Void
    private let trashStandaloneAppBundle: @Sendable () -> Void
    private var liveLock: LiveLock?

    public private(set) var section: RemotePages.SettingsSection = .general
    public private(set) var activeQR: RemotePages.ActiveQRSession?
    public private(set) var pairCodeDraft: String = ""
    public private(set) var confirmingUnpair: Bool = false
    public private(set) var confirmingUseExtension: Bool = false
    public private(set) var choiceDraft = RemotePages.ChoiceConfirmationDraft()
    public private(set) var notice: String?
    public private(set) var lastSnapshot: StatusSnapshot = StatusSnapshot(state: .down)
    private var lastStatusSent: RemotePages.StatusMark?

    public init(
        profile: RemoteProfile,
        appProfile: RemoteProfile? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        supervisor: AgentSupervisor? = nil,
        pollSnapshot: (@Sendable () -> StatusSnapshot)? = nil,
        resolveTailscaleAddress: @escaping @Sendable () -> String? = QRPairing.tailscaleAddress,
        checkStandaloneInstalled: (@Sendable () -> Bool)? = nil,
        checkStandaloneAppBundleExists: (@Sendable () -> Bool)? = nil,
        terminateStandaloneApp: @escaping @Sendable () -> Void = RemoteToolController.defaultTerminateStandaloneApp,
        trashStandaloneAppBundle: @escaping @Sendable () -> Void = RemoteToolController.defaultTrashStandaloneAppBundle
    ) {
        self.profile = profile
        let resolvedAppProfile = appProfile ?? .app(home: home)
        self.appProfile = resolvedAppProfile
        self.home = home
        self.settingsStore = RemoteSettingsStore(profile: profile)
        self.supervisor = supervisor ?? AgentSupervisor(profile: profile, home: home)
        let client = AgentClient(binaryURL: profile.agentBinaryURL)
        self.pollSnapshot = pollSnapshot ?? { client.snapshotSync() }
        self.resolveTailscaleAddress = resolveTailscaleAddress
        self.checkStandaloneInstalled = checkStandaloneInstalled ?? {
            RemoteCoexistence.isStandaloneInstalled(home: home)
        }
        self.checkStandaloneAppBundleExists = checkStandaloneAppBundleExists ?? {
            RemoteCoexistence.defaultAppBundlePaths(home: home).contains {
                FileManager.default.fileExists(atPath: $0)
            }
        }
        self.terminateStandaloneApp = terminateStandaloneApp
        self.trashStandaloneAppBundle = trashStandaloneAppBundle
    }

    /// Builds a controller configured from environment variables (for hermetic conformance
    /// tests) or the live Vitruvian tool execution environment.
    public static func fromEnvironment(
        env: [String: String] = ProcessInfo.processInfo.environment,
        programPath: String = CommandLine.arguments.first ?? ""
    ) -> RemoteToolController {
        let home: URL
        if let customHome = env["REMOTETOOL_HOME"], !customHome.isEmpty {
            home = URL(fileURLWithPath: customHome, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }

        let programURL = URL(fileURLWithPath: programPath)
        let resolvedFolders = RemoteProfile.extensionFolders(program: programURL)
        let dataFolder: URL
        if let customData = env["REMOTETOOL_DATA_FOLDER"], !customData.isEmpty {
            dataFolder = URL(fileURLWithPath: customData, isDirectory: true)
        } else if let resolved = resolvedFolders?.data {
            dataFolder = resolved
        } else {
            dataFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }

        let toolFolder: URL?
        if let customTool = env["REMOTETOOL_TOOL_FOLDER"], !customTool.isEmpty {
            toolFolder = URL(fileURLWithPath: customTool, isDirectory: true)
        } else if let resolved = resolvedFolders?.tool {
            toolFolder = resolved
        } else {
            let parent = programURL.deletingLastPathComponent().deletingLastPathComponent()
            toolFolder = FileManager.default.fileExists(atPath: parent.path) ? parent : nil
        }

        let extProfile = RemoteProfile.extension(
            dataFolder: dataFolder,
            toolFolder: toolFolder,
            home: home
        )
        let appProfile = RemoteProfile.app(home: home)

        let allowSpawn: Bool
        let runner: AgentSupervisor.CommandRunner
        if let cmdOverride = env["REMOTETOOL_AGENT_COMMAND"] {
            allowSpawn = false
            if cmdOverride.isEmpty {
                runner = { exe, args in
                    Self.simulatedCommandRunner(
                        exe: exe,
                        args: args,
                        profile: extProfile,
                        claudeSettingsURL: ClaudeHookInspector.defaultSettingsURL(home: home)
                    )
                }
            } else {
                runner = { _, args in
                    Runner.runSync(URL(fileURLWithPath: cmdOverride), args)
                }
            }
        } else {
            allowSpawn = true
            runner = Runner.runSync
        }

        let sup = AgentSupervisor(
            profile: extProfile,
            home: home,
            claudeSettingsURL: ClaudeHookInspector.defaultSettingsURL(home: home),
            allowChildSpawn: allowSpawn,
            runCommand: runner
        )

        let pollFn: (@Sendable () -> StatusSnapshot)?
        if let statusMode = env["REMOTETOOL_FAKE_STATUS"], !statusMode.isEmpty {
            pollFn = {
                switch statusMode {
                case "down":
                    return StatusSnapshot(state: .down)
                case "unpaired":
                    return StatusSnapshot(
                        state: .running(version: "1.9.1"),
                        health: AgentHealth(ok: true, agentVersion: "1.9.1", paired: false, sampleAgeMs: 200),
                        phone: PhoneLink(connected: false, tools: []),
                        tailnetReachable: true
                    )
                default:
                    return StatusSnapshot(
                        state: .running(version: "1.9.1"),
                        health: AgentHealth(
                            ok: true,
                            agentVersion: "1.9.1",
                            paired: true,
                            sampleAgeMs: 180,
                            notify: .init(configured: true, enabled: true)
                        ),
                        phone: PhoneLink(
                            connected: true,
                            device: .init(model: "Pixel Fold", android: "16"),
                            since: "2026-10-15T16:00:00Z",
                            tools: ["sms.list", "notifications.list"]
                        ),
                        tailnetReachable: true
                    )
                }
            }
        } else {
            pollFn = nil
        }

        let tsFn: @Sendable () -> String?
        if let fakeTS = env["REMOTETOOL_TAILSCALE_ADDRESS"] {
            tsFn = { fakeTS.isEmpty ? nil : fakeTS }
        } else {
            tsFn = QRPairing.tailscaleAddress
        }

        let standaloneFn: (@Sendable () -> Bool)?
        if let fakeStandalone = env["REMOTETOOL_STANDALONE_INSTALLED"] {
            standaloneFn = { fakeStandalone == "1" || fakeStandalone.lowercased() == "true" }
        } else {
            standaloneFn = nil
        }

        return RemoteToolController(
            profile: extProfile,
            appProfile: appProfile,
            home: home,
            supervisor: sup,
            pollSnapshot: pollFn,
            resolveTailscaleAddress: tsFn,
            checkStandaloneInstalled: standaloneFn
        )
    }

    /// Hermetic in-process simulation for `pair`, `token --rotate`, and `install-claude-hook`
    /// when `REMOTETOOL_AGENT_COMMAND=""` in conformance tests.
    private static func simulatedCommandRunner(
        exe: URL,
        args: [String],
        profile: RemoteProfile,
        claudeSettingsURL: URL
    ) -> CommandResult {
        guard let verb = args.first else {
            return CommandResult(exitStatus: 0, output: "")
        }
        switch verb {
        case "pair":
            guard let code = args.last, PairCode.normalize(code) != nil else {
                return CommandResult(exitStatus: 2, output: "Code must be six digits")
            }
            let payload = #"{"code":"\#(code)","expires":"2099-01-01T00:00:00Z","attempts":0}"#
            try? FileLock.writeAtomically(Data(payload.utf8), to: profile.pairJSONURL, permissions: 0o600)
            return CommandResult(exitStatus: 0, output: "pairing open for 5m0s: the phone showing \(code) may now claim a token.")
        case "token":
            if args.contains("--rotate") {
                try? FileManager.default.removeItem(at: profile.pairedURL)
                try? FileLock.writeAtomically(Data(String(repeating: "a", count: 64).utf8), to: profile.tokenURL, permissions: 0o600)
                return CommandResult(exitStatus: 0, output: "rotated token")
            }
            return CommandResult(exitStatus: 0, output: String(repeating: "b", count: 64))
        case "install-claude-hook":
            let remove = args.contains("--remove")
            if remove {
                try? FileLock.writeAtomically(Data("{}".utf8), to: claudeSettingsURL, permissions: 0o600)
                return CommandResult(exitStatus: 0, output: "removed hook")
            } else {
                let cmd = profile.hookCommandLine()
                let obj: [String: Any] = [
                    "hooks": [
                        "PermissionRequest": [
                            [
                                "matcher": "",
                                "hooks": [
                                    [
                                        "type": "command",
                                        "command": cmd,
                                        "timeout": 150,
                                    ],
                                ],
                            ],
                        ],
                    ],
                ]
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                    try? FileLock.writeAtomically(data, to: claudeSettingsURL, permissions: 0o600)
                }
                return CommandResult(exitStatus: 0, output: "added hook")
            }
        default:
            return CommandResult(exitStatus: 0, output: "")
        }
    }

    // MARK: - Lifecycle

    public func start(programPath: String = CommandLine.arguments.first ?? "") {
        if let lockURL = profile.liveLockURL {
            liveLock = try? LiveLock.hold(at: lockURL)
        }
        _ = try? RemoteChoiceFile.recordExtension(
            program: programPath,
            dataFolder: profile.settingsURL.deletingLastPathComponent().path,
            version: RemoteVersion.current,
            at: profile.choiceFileURL
        )
        let appSummary = RemoteSideSummary.inspect(appProfile)
        choiceDraft.copyFromStandalone = appSummary.hasDataToCopy || appSummary.hasMCPToken
        reconcileProcessAndPoll()
    }

    public func stop() {
        supervisor.stopSupervisedProcess()
        liveLock?.release()
        liveLock = nil
    }

    public func currentRole() -> RemoteRole {
        let choice = RemoteChoiceFile.read(at: profile.choiceFileURL)
        let standaloneInstalled = checkStandaloneInstalled()
        return RemoteRole.resolve(
            for: .extension,
            choice: choice,
            appInstalled: standaloneInstalled,
            extensionInstalled: true
        )
    }

    /// Reconciles the supervised agent process against the current role and settings,
    /// and polls the latest `StatusSnapshot`.
    @discardableResult
    public func reconcileProcessAndPoll() -> RemotePages.State {
        let role = currentRole()
        let settings = settingsStore.load()
        if role.isActive {
            if settings.autoStartAgent {
                _ = supervisor.startSupervisedProcess(settings: settings)
            }
            lastSnapshot = pollSnapshot()
        } else {
            supervisor.stopSupervisedProcess()
            lastSnapshot = StatusSnapshot(state: .down)
        }
        if let qr = activeQR, Date() >= qr.expiresAt {
            activeQR = nil
        }
        return currentState()
    }

    public func currentState() -> RemotePages.State {
        let role = currentRole()
        let settings = settingsStore.load()
        return RemotePages.State(
            profile: profile,
            role: role,
            settings: settings,
            snapshot: lastSnapshot,
            tailscaleAddress: resolveTailscaleAddress(),
            isPairedOnDisk: settingsStore.isPairedOnDisk,
            notifyEnabled: settingsStore.notifyEnabledOnDisk,
            hasNtfyToken: settingsStore.hasNtfyToken,
            hasPrometheusToken: settingsStore.hasPrometheusToken,
            permissionHookInstalled: supervisor.isPermissionHookInstalled(),
            section: section,
            activeQR: activeQR,
            pairCodeDraft: pairCodeDraft,
            confirmingUnpair: confirmingUnpair,
            confirmingUseExtension: confirmingUseExtension,
            choiceDraft: choiceDraft,
            appSummary: RemoteSideSummary.inspect(appProfile),
            extensionSummary: RemoteSideSummary.inspect(profile),
            standaloneAppBundleExists: checkStandaloneAppBundleExists(),
            notice: notice
        )
    }

    public func syncClosedIslandStatus(to app: App) {
        let mark = RemotePages.statusMark(for: currentState())
        guard mark != lastStatusSent else { return }
        if (try? app.status(mark.state, text: mark.text.isEmpty ? nil : .plain(mark.text), icon: mark.icon)) != nil {
            lastStatusSent = mark
        }
    }

    // MARK: - Panel Builders

    public func islandPage() -> UITree {
        let state = reconcileProcessAndPoll()
        return RemotePages.islandPage(state)
    }

    public func settingsPage() -> UITree {
        let state = reconcileProcessAndPoll()
        return RemotePages.settingsPage(state)
    }

    // MARK: - Event Handling

    public func handleIslandEvent(_ event: PanelEvent, app: App? = nil) -> PanelAnswer {
        handleEvent(event, in: Self.islandPanelID, app: app)
    }

    public func handleSettingsEvent(_ event: PanelEvent, app: App? = nil) -> PanelAnswer {
        handleEvent(event, in: Self.settingsPanelID, app: app)
    }

    private func handleEvent(_ event: PanelEvent, in panelID: String, app: App?) -> PanelAnswer {
        guard let block = event.block else { return .keep }
        notice = nil

        switch block {
        // --- Coexistence / Choice ---
        case RemotePages.Block.chooseExtension, RemotePages.Block.switchToExtension:
            let appSummary = RemoteSideSummary.inspect(appProfile)
            choiceDraft.copyFromStandalone = appSummary.hasDataToCopy || appSummary.hasMCPToken
            confirmingUseExtension = true
            if currentRole() == .quietChosen {
                performSwitchToExtension()
            }

        case RemotePages.Block.cancelChoiceStep:
            confirmingUseExtension = false

        case RemotePages.Block.copyFromStandalone:
            if let on = event.isOn {
                choiceDraft.copyFromStandalone = on
            }

        case RemotePages.Block.disableStandaloneAtLogin:
            if let on = event.isOn {
                choiceDraft.disableStandaloneAtLogin = on
            }

        case RemotePages.Block.trashStandaloneApp:
            if let on = event.isOn {
                choiceDraft.trashStandaloneApp = on
            }

        case RemotePages.Block.confirmUseExtension:
            performSwitchToExtension()

        case RemotePages.Block.chooseStandaloneApp, RemotePages.Block.switchToStandaloneApp:
            performSwitchToStandaloneApp()

        case RemotePages.Block.copyFromStandaloneNow:
            if let res = try? RemoteDataCopy.copy(from: appProfile, to: profile, home: home) {
                _ = supervisor.restartAgent(settings: res.copiedSettings)
                lastSnapshot = pollSnapshot()
                notice = "Copied settings and \(res.copiedFiles.count) credential file(s) from the standalone setup."
            } else {
                notice = "Could not copy from the standalone setup."
            }

        // --- Section Tabs ---
        case RemotePages.Block.tabGeneral:
            section = .general
        case RemotePages.Block.tabPairing:
            section = .pairing
        case RemotePages.Block.tabNotifications:
            section = .notifications
        case RemotePages.Block.tabIntegrations:
            section = .integrations

        // --- Agent & Network ---
        case RemotePages.Block.autoStartAgent:
            if let on = event.isOn {
                _ = try? settingsStore.update { $0.autoStartAgent = on }
                if on {
                    _ = supervisor.startSupervisedProcess(settings: settingsStore.load())
                    lastSnapshot = pollSnapshot()
                } else {
                    supervisor.stopSupervisedProcess()
                    lastSnapshot = StatusSnapshot(state: .down)
                }
                notice = on ? "Agent will start automatically." : "Auto-start turned off."
            }

        case RemotePages.Block.tailscaleEnabled:
            if let on = event.isOn {
                let updated = (try? settingsStore.update { $0.tailscale = on }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = on ? "Tailscale listener enabled." : "Tailscale listener disabled (loopback only)."
            }

        case RemotePages.Block.intervalSeconds:
            if let raw = event.text {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed), (RemoteSettings.minIntervalSeconds...RemoteSettings.maxIntervalSeconds).contains(val) {
                    let updated = (try? settingsStore.update { $0.intervalSeconds = val }) ?? settingsStore.load()
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                    notice = "Metrics refresh interval set to \(val)s."
                } else {
                    notice = "Refresh interval must be a whole number between 1 and 60 seconds."
                }
            }

        case RemotePages.Block.islandRestartAgent, RemotePages.Block.restartAgent:
            let res = supervisor.restartAgent(settings: settingsStore.load())
            lastSnapshot = pollSnapshot()
            notice = res.succeeded ? "Agent restarted." : (res.output.isEmpty ? "Could not restart agent." : res.output)

        case RemotePages.Block.openLog:
            openAgentLog(app: app)

        // --- Pairing ---
        case RemotePages.Block.islandPairWithQR, RemotePages.Block.settingsPairWithQR:
            startQRPairing()

        case RemotePages.Block.islandDismissQR, RemotePages.Block.settingsDismissQR:
            activeQR = nil

        case RemotePages.Block.islandPairCodeField, RemotePages.Block.settingsPairCodeField:
            if let text = event.text {
                pairCodeDraft = text
                if event.kind == .submit {
                    submitPairCode(text)
                }
            }

        case RemotePages.Block.islandPairWithCode, RemotePages.Block.settingsPairWithCode:
            submitPairCode(pairCodeDraft)

        case RemotePages.Block.islandAskUnpair, RemotePages.Block.settingsAskUnpair:
            confirmingUnpair = true

        case RemotePages.Block.islandCancelUnpair, RemotePages.Block.settingsCancelUnpair:
            confirmingUnpair = false

        case RemotePages.Block.islandConfirmUnpair, RemotePages.Block.settingsConfirmUnpair:
            confirmingUnpair = false
            let res = supervisor.rotateToken()
            lastSnapshot = pollSnapshot()
            notice = res.succeeded
                ? "Rotated bearer token — all previously paired phones are now unpaired."
                : (res.output.isEmpty ? "Could not rotate token." : res.output)

        // --- Claude Permission Hook & MCP Bridge ---
        case RemotePages.Block.islandTogglePermissionHook, RemotePages.Block.permissionHookToggle:
            if let on = event.isOn {
                let res = supervisor.setPermissionHookEnabled(on)
                notice = res.succeeded
                    ? (on ? "Claude Code permission hook enabled." : "Claude Code permission hook removed.")
                    : (res.output.isEmpty ? "Could not update ~/.claude/settings.json." : res.output)
            }

        case RemotePages.Block.permissionWaitSeconds:
            if let raw = event.text {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int(trimmed),
                   (RemoteSettings.minPermissionWaitSeconds...RemoteSettings.maxPermissionWaitSeconds).contains(val)
                {
                    let updated = (try? settingsStore.update { $0.permissionWaitSeconds = val }) ?? settingsStore.load()
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                    notice = "Permission prompt wait set to \(val)s."
                } else {
                    notice = "Wait timeout must be a whole number between 5 and 140 seconds."
                }
            }

        case RemotePages.Block.copyMCPCommand:
            copyMCPSetupCommand(app: app)

        // --- Notifications ---
        case RemotePages.Block.islandToggleNotifications, RemotePages.Block.notifyEnabledToggle:
            if let on = event.isOn {
                try? settingsStore.setNotifyEnabledOnDisk(on)
                _ = supervisor.restartAgent(settings: settingsStore.load())
                lastSnapshot = pollSnapshot()
                notice = on ? "Push notifications enabled." : "Push notifications muted."
            }

        case RemotePages.Block.ntfyURL:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.ntfyURL = text }) ?? settingsStore.load()
                if updated.notificationsConfigured || updated.ntfyURL.isEmpty {
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                }
                notice = updated.ntfyURL.isEmpty ? "Cleared ntfy URL." : "Saved ntfy URL."
            }

        case RemotePages.Block.ntfyTopic:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.ntfyTopic = text }) ?? settingsStore.load()
                if updated.notificationsConfigured || updated.ntfyTopic.isEmpty {
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                }
                notice = updated.ntfyTopic.isEmpty ? "Cleared ntfy topic." : "Saved ntfy topic."
            }

        case RemotePages.Block.ntfyTokenField:
            if let text = event.text {
                try? settingsStore.saveNtfyToken(text)
                let updated = settingsStore.load()
                if updated.notificationsConfigured {
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                }
                notice = settingsStore.hasNtfyToken ? "Saved ntfy bearer token (0600)." : "Cleared ntfy bearer token."
            }

        case RemotePages.Block.clearNtfyToken:
            try? settingsStore.clearNtfyToken()
            let updated = settingsStore.load()
            if updated.notificationsConfigured {
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
            }
            notice = "Cleared ntfy bearer token."

        // --- Integrations ---
        case RemotePages.Block.execDir:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.execDir = text }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = updated.execDir.isEmpty ? "Cleared working directory." : "Saved working directory."
            }

        case RemotePages.Block.ghExtraRepos:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.ghExtraRepos = text }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = updated.ghExtraRepos.isEmpty ? "Cleared extra GitHub repositories." : "Saved extra GitHub repositories."
            }

        case RemotePages.Block.kubeconfig:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.kubeconfig = text }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = updated.kubeconfig.isEmpty ? "Cleared kubeconfig path." : "Saved kubeconfig path."
            }

        case RemotePages.Block.kubeContext:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.kubeContext = text }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = updated.kubeContext.isEmpty ? "Cleared kubeconfig context." : "Saved kubeconfig context."
            }

        case RemotePages.Block.prometheusURL:
            if let text = event.text {
                let updated = (try? settingsStore.update { $0.prometheusURL = text }) ?? settingsStore.load()
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
                notice = updated.prometheusURL.isEmpty ? "Cleared Prometheus URL." : "Saved Prometheus URL."
            }

        case RemotePages.Block.prometheusTokenField:
            if let text = event.text {
                try? settingsStore.savePrometheusToken(text)
                let updated = settingsStore.load()
                if !updated.prometheusURL.isEmpty {
                    _ = supervisor.restartAgent(settings: updated)
                    lastSnapshot = pollSnapshot()
                }
                notice = settingsStore.hasPrometheusToken ? "Saved Prometheus bearer token (0600)." : "Cleared Prometheus bearer token."
            }

        case RemotePages.Block.clearPrometheusToken:
            try? settingsStore.clearPrometheusToken()
            let updated = settingsStore.load()
            if !updated.prometheusURL.isEmpty {
                _ = supervisor.restartAgent(settings: updated)
                lastSnapshot = pollSnapshot()
            }
            notice = "Cleared Prometheus bearer token."

        default:
            return .keep
        }

        if let app {
            syncClosedIslandStatus(to: app)
        }
        let state = currentState()
        return .page(panelID == Self.islandPanelID ? RemotePages.islandPage(state) : RemotePages.settingsPage(state))
    }

    // MARK: - Commands

    public func runCommand(_ commandID: String, app: App) throws {
        switch commandID {
        case Command.pairWithQR:
            startQRPairing()
            if let qr = activeQR {
                try? app.showMessage("Pairing code \(qr.code) open for 5m (\(qr.address))", icon: "qrcode")
            } else if let msg = notice {
                throw CommandRefused(msg)
            }
        case Command.restartAgent:
            let res = supervisor.restartAgent(settings: settingsStore.load())
            lastSnapshot = pollSnapshot()
            syncClosedIslandStatus(to: app)
            if res.succeeded {
                try? app.showMessage("Vitruvian Remote agent restarted", icon: "arrow.clockwise")
            } else {
                throw CommandRefused(res.output.isEmpty ? "Could not restart agent" : res.output)
            }
        case Command.toggleNotifications:
            let settings = settingsStore.load()
            guard settings.notificationsConfigured else {
                throw CommandRefused("Configure ntfy URL and topic in Vitruvian Remote settings first")
            }
            let next = !settingsStore.notifyEnabledOnDisk
            try settingsStore.setNotifyEnabledOnDisk(next)
            _ = supervisor.restartAgent(settings: settings)
            lastSnapshot = pollSnapshot()
            syncClosedIslandStatus(to: app)
            try? app.showMessage(next ? "Push notifications enabled" : "Push notifications muted", icon: "bell")
        case Command.togglePermissionHook:
            let next = !supervisor.isPermissionHookInstalled()
            let res = supervisor.setPermissionHookEnabled(next)
            if res.succeeded {
                try? app.showMessage(
                    next ? "Claude Code permission hook enabled" : "Claude Code permission hook removed",
                    icon: "checkmark.shield"
                )
            } else {
                throw CommandRefused(res.output.isEmpty ? "Could not update Claude Code settings" : res.output)
            }
        case Command.copyMCPCommand:
            copyMCPSetupCommand(app: app)
            try? app.showMessage("Copied Claude Code Phone MCP command", icon: "doc.on.doc")
        case Command.openLog:
            openAgentLog(app: app)
        default:
            throw CommandRefused("Unknown command \(commandID)")
        }
    }

    // MARK: - Internal Helpers

    private func performSwitchToExtension() {
        let wasHookInstalled = supervisor.isPermissionHookInstalled()
        if choiceDraft.copyFromStandalone {
            _ = try? RemoteDataCopy.copy(from: appProfile, to: profile, home: home)
        }
        _ = try? RemoteChoiceFile.choose(.extension, at: profile.choiceFileURL)
        confirmingUseExtension = false
        supervisor.stopStandaloneAgent(disableLaunchAgentAtLogin: choiceDraft.disableStandaloneAtLogin)
        if supervisor.allowChildSpawn {
            terminateStandaloneApp()
            if choiceDraft.trashStandaloneApp {
                trashStandaloneAppBundle()
            }
        }
        if wasHookInstalled {
            _ = supervisor.setPermissionHookEnabled(true)
        }
        let settings = settingsStore.load()
        _ = supervisor.startSupervisedProcess(settings: settings)
        lastSnapshot = pollSnapshot()
        notice = choiceDraft.copyFromStandalone
            ? "Switched to the Vitruvian extension and copied your standalone pairing and settings."
            : "Switched to the Vitruvian extension."
    }

    private func performSwitchToStandaloneApp() {
        let wasHookInstalled = supervisor.isPermissionHookInstalled()
        supervisor.stopSupervisedProcess()
        _ = try? RemoteChoiceFile.choose(.app, at: profile.choiceFileURL)
        confirmingUseExtension = false
        if supervisor.allowChildSpawn {
            let appSupervisor = AgentSupervisor(profile: appProfile, home: home)
            if wasHookInstalled {
                _ = appSupervisor.setPermissionHookEnabled(true)
            }
            let appSettings = RemoteSettingsStore(profile: appProfile).load()
            _ = appSupervisor.restartAgent(settings: appSettings)
        }
        lastSnapshot = StatusSnapshot(state: .down)
        notice = "Switched to the standalone Vitruvian Remote setup."
    }

    private func startQRPairing() {
        guard let address = resolveTailscaleAddress() else {
            notice = "Tailscale is not connected on this Mac. Connect Tailscale or pair with the 6-digit code shown on the phone."
            return
        }
        let code = QRPairing.newCode()
        guard let url = QRPairing.pageURL(address: address, code: code),
              let pngDataURL = QRPairing.pngDataURL(for: url.absoluteString)
        else {
            notice = "Could not build pairing QR code."
            return
        }
        let res = supervisor.pair(code: code)
        guard res.succeeded else {
            notice = res.output.isEmpty ? "Could not open pairing window." : res.output
            return
        }
        activeQR = RemotePages.ActiveQRSession(
            code: code,
            address: address,
            url: url,
            pngDataURL: pngDataURL,
            expiresAt: Date().addingTimeInterval(5 * 60)
        )
        notice = "Pairing open for 5 minutes (code \(code))."
    }

    private func submitPairCode(_ rawCode: String) {
        guard let code = PairCode.normalize(rawCode) else {
            notice = "Code must be six ASCII digits (for example, 482917)."
            return
        }
        let res = supervisor.pair(code: code)
        if res.succeeded {
            pairCodeDraft = ""
            notice = "Pairing open for 5 minutes: the phone showing \(code) can now claim a token."
        } else {
            notice = res.output.isEmpty ? "Pairing failed." : res.output
        }
    }

    private func copyMCPSetupCommand(app: App?) {
        let cmd = profile.mcpAddCommand
        if let app, (try? app.setClipboardText(cmd)) == true {
            notice = "Copied Claude Code MCP command to the clipboard."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        notice = "Copied Claude Code MCP command to the clipboard."
    }

    private func openAgentLog(app: App?) {
        let logURL = profile.logURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let app, (try? app.open(logURL.absoluteString)) == true {
            notice = "Opened \(logURL.lastPathComponent)."
            return
        }
        NSWorkspace.shared.open(logURL)
        notice = "Opened \(logURL.lastPathComponent)."
    }

    public static func defaultTerminateStandaloneApp() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: RemoteProfile.appBundleID) {
            app.terminate()
        }
    }

    public static func defaultTrashStandaloneAppBundle() {
        for path in RemoteCoexistence.defaultAppBundlePaths() where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.recycle([url], completionHandler: nil)
        }
    }
}
