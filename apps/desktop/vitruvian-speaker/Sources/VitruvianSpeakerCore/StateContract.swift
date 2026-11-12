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

/// Machine-readable `--state --json` and `--apply --json '<changes>'` contract
/// shared by the standalone `VitruvianSpeaker` app binary and the Vitruvian
/// extension's `bin/tool`.
///
/// Design: `docs/superpowers/specs/2026-11-10-vitruvian-speaker-one-rulebook-design.md` (§3).
public enum VitruvianSpeakerStateContract {
    public static let contractVersion = 1

    /// Every operation name accepted by `--apply`. Tested against an explicit
    /// per-op test table in `StateContractTests` so no operation can be added
    /// without a corresponding test row.
    public static let supportedOperations: [String] = [
        "set",
        "setDefaultSpeaker",
        "removeSpeaker",
        "reset",
        "clearChatToken",
        "saveOAuthClient",
        "switchTo",
        "setSecret",
        "snooze",
        "setNetwork",
        "setReadAnyway",
        "importAntigravity",
        "agentHook",
        "removeLegacyAgent",
    ]

    /// Injectable seam for every file, process check, and environment lookup
    /// read or written by `--state` and `--apply`.
    ///
    /// Tests construct a `Seam` pointing exclusively at scratch files and fake
    /// closures so no real user file or running process is ever touched.
    public struct Seam: Sendable {
        public var program: VitruvianSpeakerProfile.Door
        public var vitruvianSpeakerVersion: @Sendable () -> String
        public var configFile: SpeakerConfigFile
        public var secrets: SecretStore
        public var history: BroadcastHistory
        public var monitorStatusFile: ChatMonitorStatusFile
        public var doorFile: DoorFile
        public var otherInstalled: @Sendable (DoorRecord?) -> Bool
        public var appRunning: @Sendable () -> Bool
        public var extensionRunning: @Sendable (DoorRecord?) -> Bool
        public var systemVoices: @Sendable () -> [LocalVoice]
        public var speakerVolume: @Sendable () -> Int?
        public var speakerOnline: @Sendable () -> [String: Bool]
        public var gwsInstalled: @Sendable () -> Bool
        public var antigravityTokensAvailable: @Sendable () -> Bool
        public var antigravityTokensURL: URL
        public var shippedOAuthClient: @Sendable () -> OAuthClient?
        public var agentHome: URL
        public var hookExecutablePath: String
        public var doorSwitchSeam: @Sendable () -> (any SettingsActions.DoorSwitchSeam)?
        public var now: @Sendable () -> Date
        public var calendar: Calendar
        /// Tells a running Vitruvian Speaker of this program that secrets changed,
        /// so it re-reads its login and restarts its chat monitor. Called once
        /// after a successful `--apply` that changed any secret. Silent unless
        /// the live seam sets it, so tests never post a real notification.
        public var credentialsChanged: @Sendable () -> Void
        /// Stops a launchd job (`launchctl bootout <target>`) for
        /// `removeLegacyAgent`. A no-op unless the live seam sets it, so tests
        /// never call the real `launchctl`.
        public var launchctlBootout: @Sendable (String) -> Void

        public init(
            program: VitruvianSpeakerProfile.Door,
            vitruvianSpeakerVersion: @escaping @Sendable () -> String = { VitruvianSpeakerVersion.current },
            configFile: SpeakerConfigFile,
            secrets: SecretStore,
            history: BroadcastHistory,
            monitorStatusFile: ChatMonitorStatusFile,
            doorFile: DoorFile,
            otherInstalled: @escaping @Sendable (DoorRecord?) -> Bool,
            appRunning: @escaping @Sendable () -> Bool,
            extensionRunning: @escaping @Sendable (DoorRecord?) -> Bool,
            systemVoices: @escaping @Sendable () -> [LocalVoice] = { [] },
            speakerVolume: @escaping @Sendable () -> Int? = { nil },
            speakerOnline: @escaping @Sendable () -> [String: Bool] = { [:] },
            gwsInstalled: @escaping @Sendable () -> Bool = { GwsChatClient.locate() != nil },
            antigravityTokensAvailable: @escaping @Sendable () -> Bool = { false },
            antigravityTokensURL: URL? = nil,
            shippedOAuthClient: @escaping @Sendable () -> OAuthClient? = { nil },
            agentHome: URL,
            hookExecutablePath: String,
            doorSwitchSeam: @escaping @Sendable () -> (any SettingsActions.DoorSwitchSeam)? = { nil },
            now: @escaping @Sendable () -> Date = { Date() },
            calendar: Calendar = .current,
            credentialsChanged: @escaping @Sendable () -> Void = {},
            launchctlBootout: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.program = program
            self.vitruvianSpeakerVersion = vitruvianSpeakerVersion
            self.configFile = configFile
            self.secrets = secrets
            self.history = history
            self.monitorStatusFile = monitorStatusFile
            self.doorFile = doorFile
            self.otherInstalled = otherInstalled
            self.appRunning = appRunning
            self.extensionRunning = extensionRunning
            self.systemVoices = systemVoices
            self.speakerVolume = speakerVolume
            self.speakerOnline = speakerOnline
            self.gwsInstalled = gwsInstalled
            self.antigravityTokensAvailable = antigravityTokensAvailable
            self.antigravityTokensURL = antigravityTokensURL
                ?? agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
            self.shippedOAuthClient = shippedOAuthClient
            self.agentHome = agentHome
            self.hookExecutablePath = hookExecutablePath
            self.doorSwitchSeam = doorSwitchSeam
            self.now = now
            self.calendar = calendar
            self.credentialsChanged = credentialsChanged
            self.launchctlBootout = launchctlBootout
        }

        /// Builds the default seam for `engine` on the standalone app or the
        /// extension when no custom seam was injected.
        public static func live(
            for profile: VitruvianSpeakerProfile,
            doorFile: DoorFile = DoorFile(),
            otherInstalled: @escaping @Sendable (DoorRecord?) -> Bool = { record in
                OtherDoorPresence.extensionInstalled(
                    record: record,
                    fileExists: { FileManager.default.fileExists(atPath: $0) }
                )
            },
            agentHome: URL = FileManager.default.homeDirectoryForCurrentUser,
            hookExecutablePath: String = AgentIntegration.runningExecutable(),
            now: @escaping @Sendable () -> Date = { Date() },
            launchctlBootout: @escaping @Sendable (String) -> Void = AgentIntegration.launchctlBootout,
            doorSwitchSeam: @escaping @Sendable () -> (any SettingsActions.DoorSwitchSeam)?
        ) -> Seam {
            // From `agentHome`, as `init` does, so a seam built for another
            // home never reads this account's Antigravity tokens.
            let antigravityURL = agentHome.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
            return Seam(
                program: profile.door,
                vitruvianSpeakerVersion: { VitruvianSpeakerVersion.current },
                configFile: SpeakerConfigFile(url: profile.settingsURL),
                secrets: SecretStore(fileURL: profile.secretsURL),
                history: BroadcastHistory(fileURL: profile.historyURL),
                monitorStatusFile: ChatMonitorStatusFile(url: profile.monitorStatusURL),
                doorFile: doorFile,
                otherInstalled: otherInstalled,
                appRunning: { VitruvianSpeakerProfile.isAppRunning(among: VitruvianSpeakerProfile.runningApps()) },
                extensionRunning: { record in
                    let extProfile = profile.door == .extension ? profile : AppStartup.extensionProfile(record: record)
                    guard let lockURL = extProfile?.liveLockURL else { return false }
                    return LiveLock.isHeld(at: lockURL)
                },
                systemVoices: { LocalSpeaker.shared.englishVoices() },
                speakerVolume: { nil },
                speakerOnline: { [:] },
                gwsInstalled: { GwsChatClient.locate() != nil },
                antigravityTokensAvailable: {
                    guard let data = try? Data(contentsOf: antigravityURL) else { return false }
                    return SecretStore.parseAntigravityTokens(data) != nil
                },
                antigravityTokensURL: antigravityURL,
                shippedOAuthClient: { profile.shippedClient },
                agentHome: agentHome,
                hookExecutablePath: hookExecutablePath,
                doorSwitchSeam: doorSwitchSeam,
                now: now,
                credentialsChanged: {
                    CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: profile))
                },
                launchctlBootout: launchctlBootout
            )
        }
    }

    // MARK: - `--state --json`

    /// Builds and formats the `--state --json` CLI output (always exit 0).
    public static func stateOutput(seam: Seam) -> CLIOutput {
        let object = stateObject(seam: seam)
        return CLIOutput(stdout: [encodeJSON(object)], exitCode: 0)
    }

    /// Builds the complete `--state` dictionary for `seam`.
    ///
    /// Never includes any secret token, refresh token, access token, OAuth
    /// client secret, or Gemini API key — only boolean presence flags and
    /// non-secret identifiers (email, public OAuth client ID).
    public static func stateObject(seam: Seam) -> [String: Any] {
        let now = seam.now()
        let doorRecord = seam.doorFile.read()
        let otherInstalled = seam.otherInstalled(doorRecord)
        let selfInstalled = !OtherDoorPresence.isInTrash(seam.hookExecutablePath)
        let appInstalled = seam.program == .app ? selfInstalled : otherInstalled
        let extensionInstalled = seam.program == .extension ? selfInstalled : otherInstalled
        let chosen = doorRecord?.chosen
        let role = DoorRole.decide(me: seam.program, otherInstalled: otherInstalled, chosen: chosen)
        let activeDoor: VitruvianSpeakerProfile.Door
        if case .quiet(let other) = role {
            activeDoor = other
        } else {
            activeDoor = seam.program
        }

        let appRunning = seam.appRunning()
        let extensionRunning = seam.extensionRunning(doorRecord)
        let ownerRunning = seam.program == .app ? appRunning : extensionRunning
        let chosenRunning: Bool
        switch chosen {
        case .app?:
            chosenRunning = appRunning
        case .extension?:
            chosenRunning = extensionRunning
        case nil:
            chosenRunning = appRunning
        }

        let configRead = seam.configFile.read()
        let config: SpeakerConfig
        let configInitialized: Bool
        let configProblem: String?
        switch configRead {
        case .loaded(let loaded):
            config = loaded
            configInitialized = true
            configProblem = nil
        case .missing:
            config = SpeakerConfig()
            configInitialized = false
            configProblem = nil
        case .unreadable(let err):
            config = SpeakerConfig()
            configInitialized = true
            configProblem = err.localizedDescription
        }

        let voices = seam.systemVoices()
        let speakerVol = seam.speakerVolume()
        let catalog = SettingsCatalog(config: config, systemVoices: voices)
        let settingsArray: [[String: Any]] = catalog.entries.map { entry in
            var item: [String: Any] = [
                "key": entry.key,
                "label": entry.label,
                "kind": entry.kind.rawValue,
                "value": jsonValue(SettingsActions.catalogValue(for: entry.id, in: config, speakerVolume: speakerVol)),
                "shown": entry.shown,
            ]
            if !entry.choices.isEmpty {
                item["choices"] = entry.choices.map { ["value": $0.value, "label": $0.label] }
            }
            if let limits = entry.limits {
                item["limits"] = [
                    "min": limits.min,
                    "max": limits.max,
                    "step": limits.step,
                    "default_value": limits.defaultValue,
                ]
            }
            return item
        }

        let onlineByKey = seam.speakerOnline()
        let speakersArray: [[String: Any]] = config.uniqueTargets().map { target in
            var dict: [String: Any] = [
                "key": target.key,
                "id": target.device.id,
                "name": target.device.name,
                "room": target.device.room ?? NSNull(),
                "type": target.device.type,
                "display_line": target.device.displayLine,
                "is_default": target.key == config.defaultTarget,
            ]
            if let online = onlineByKey[target.key] {
                dict["online"] = online
            }
            return dict
        }

        let loadedSecrets = seam.secrets.load()
        let signedIn = !(loadedSecrets.google?.refreshToken ?? "").isEmpty
        let email = loadedSecrets.google?.email ?? loadedSecrets.googleChat?.email
        let hasOAuthClient = OAuthClient.resolve(secrets: loadedSecrets, shipped: seam.shippedOAuthClient()) != nil
        let customClientId = (loadedSecrets.oauthClientIdOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomSecret = !(loadedSecrets.oauthClientSecretOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAntigravity = seam.antigravityTokensAvailable()
        let hasGeminiKey = !(loadedSecrets.geminiApiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let signInDict: [String: Any] = [
            "signed_in": signedIn,
            "email": email ?? NSNull(),
            "has_oauth_client": hasOAuthClient,
            "client_override_present": !customClientId.isEmpty,
            "custom_oauth_client_id": customClientId,
            "has_custom_oauth_secret": hasCustomSecret,
            "has_antigravity_tokens": hasAntigravity,
            "has_gemini_key": hasGeminiKey,
        ]

        let chatConfig = config.effectiveChatMonitor
        let hasSlackToken = !(loadedSecrets.slackToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasGoogleChatToken = !(loadedSecrets.googleChat?.refreshToken ?? "").isEmpty
        let hasChatAccess = loadedSecrets.hasChatAccess
        let hasBeeperToken = loadedSecrets.token(for: .beeper) != nil
        let hasCourierToken = loadedSecrets.token(for: .courier) != nil
        let gwsInstalled = seam.gwsInstalled()

        let rawStatus = seam.monitorStatusFile.read() ?? ChatMonitorStatus(isRunning: false, pid: 0)
        let believedStatus = rawStatus.believed(ownerRunning: ownerRunning)
        let monitorRunning = ownerRunning && believedStatus.isRunning

        let beeperList = BeeperNetworkList(
            listed: monitorRunning ? believedStatus.beeperNetworkStates : nil,
            muted: chatConfig.beeperMutedNetworks
        )
        let beeperNetworks: [[String: Any]] = beeperList.rows.map { row in
            [
                "key": row.key,
                "name": row.name,
                "state": row.state.rawValue,
            ]
        }

        let courierList = BeeperNetworkList(
            listed: monitorRunning ? believedStatus.courierNetworkStates : nil,
            muted: chatConfig.courierMutedNetworks
        )
        let courierNetworks: [[String: Any]] = courierList.rows.map { row in
            var entry: [String: Any] = [
                "key": row.key,
                "name": row.name,
                "state": row.state.rawValue,
            ]
            if chatConfig.courierReadAnyway.contains(row.key) {
                entry["read_anyway"] = true
            }
            return entry
        }

        let monitorDict: [String: Any] = [
            "is_running": believedStatus.isRunning,
            "last_poll_at": believedStatus.lastPollDate.map(SpeakerConfig.formatISO8601UTC) ?? NSNull(),
            "last_error": believedStatus.lastError ?? NSNull(),
            "slack_identity": believedStatus.slackIdentity ?? NSNull(),
            "active_google_chat_backend": believedStatus.activeGoogleChatBackend ?? NSNull(),
            "pid": Int(believedStatus.pid),
        ]

        let chatDict: [String: Any] = [
            "sources": [
                "slack": [
                    "enabled": chatConfig.slackEnabled,
                    "token_present": hasSlackToken,
                ],
                "google_chat": [
                    "enabled": chatConfig.googleChatEnabled,
                    "token_present": hasGoogleChatToken,
                    "has_chat_access": hasChatAccess,
                    "source": chatConfig.googleChatSource.rawValue,
                    "gws_account": chatConfig.gwsAccount,
                    "gws_installed": gwsInstalled,
                ],
                "beeper": [
                    "enabled": chatConfig.beeperEnabled,
                    "token_present": hasBeeperToken,
                    "announce": chatConfig.beeperAnnounce.rawValue,
                    "address": chatConfig.beeperAddress,
                ],
                "courier": [
                    "enabled": chatConfig.courierEnabled,
                    "token_present": hasCourierToken,
                    "announce": chatConfig.courierAnnounce.rawValue,
                    "address": chatConfig.courierAddress,
                ],
            ],
            "has_slack_token": hasSlackToken,
            "has_google_chat_token": hasGoogleChatToken,
            "has_chat_access": hasChatAccess,
            "has_beeper_token": hasBeeperToken,
            "has_courier_token": hasCourierToken,
            "gws_installed": gwsInstalled,
            "beeper_networks": beeperNetworks,
            "beeper_networks_listed": beeperList.isListed,
            "courier_networks": courierNetworks,
            "courier_networks_listed": courierList.isListed,
            "monitor": monitorDict,
        ]

        let integration = AgentIntegration(
            home: seam.agentHome,
            executablePath: seam.hookExecutablePath,
            bootout: { _ in }
        )
        var hooksDict: [String: Any] = [:]
        var agentWarnings: [String] = []
        for agent in CodingAgent.allCases {
            let status = integration.status(of: agent)
            let hookState: String
            let staleCommand: Any
            switch status.hook {
            case .installed:
                hookState = "installed"
                staleCommand = NSNull()
            case .notInstalled:
                hookState = "not_installed"
                staleCommand = NSNull()
            case .stale(let cmd):
                hookState = "stale"
                staleCommand = cmd
            }
            if config.announces(agent), let warning = status.speaksTwiceWarning {
                agentWarnings.append(warning)
            }
            hooksDict[agentSnakeKey(agent)] = [
                "agent": agentDashName(agent),
                "display_name": agent.displayName,
                "is_installed": status.isInstalled,
                "hook_state": hookState,
                "stale_command": staleCommand,
                "hook_program": status.hookProgram ?? NSNull(),
                "configured_by_instruction": status.configuredByInstruction,
                "speaks_twice": status.speaksTwice,
                "speaks_twice_warning": status.speaksTwiceWarning ?? NSNull(),
            ]
        }

        var warnings: [String] = []
        if let configProblem {
            warnings.append(configProblem)
        }
        if config.enabled {
            if !config.effectiveSpeakHome && !config.effectiveSpeakLocal && !config.effectiveSpeakPhone {
                warnings.append("All outputs are off, so nothing is spoken anywhere.")
            }
            if (config.geminiSpeaks || config.showsStyleGeminiKey) && !hasGeminiKey {
                warnings.append("No Gemini API key saved.")
            }
            if chatConfig.anySourceEnabled {
                let setupProblems = ChatMonitorService.setupProblems(
                    config: chatConfig,
                    hasSlackToken: hasSlackToken,
                    hasChatScopes: hasChatAccess,
                    gwsInstalled: gwsInstalled,
                    hasBeeperToken: hasBeeperToken,
                    hasCourierToken: hasCourierToken
                ).map(\.localizedDescription)
                warnings.append(contentsOf: setupProblems)
                if monitorRunning,
                   let runtimeErr = believedStatus.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !runtimeErr.isEmpty,
                   !setupProblems.contains(where: { runtimeErr.contains($0) }) {
                    warnings.append(runtimeErr)
                }
            }
            warnings.append(contentsOf: agentWarnings)
        }

        let quietStart = config.quietHoursStart.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursStart
        let quietEnd = config.quietHoursEnd.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursEnd
        let quietHoursDict: [String: Any] = [
            "enabled": config.quietHoursEnabled ?? false,
            "start": quietStart,
            "end": quietEnd,
            "active": config.isInQuietHours(at: now, calendar: seam.calendar),
        ]

        let snoozeUntilValue: Any
        if config.isSnoozed(at: now), let until = config.snoozeUntil {
            snoozeUntilValue = SpeakerConfig.formatISO8601UTC(until)
        } else {
            snoozeUntilValue = NSNull()
        }

        let localVoiceName = voices.first(where: { $0.id == config.effectiveLocalVoice })?.name
            ?? (config.effectiveLocalVoice.split(separator: ".").last.map(String.init) ?? config.effectiveLocalVoice)
        let availableVoicesArray: [[String: Any]] = voices.map { voice in
            [
                "id": voice.id,
                "name": voice.name,
                "language": voice.language,
                "quality": voice.quality.label.lowercased(),
                "label": voice.pickerLabel,
            ]
        }
        let customVoicesArray: [[String: Any]] = (config.customVoices ?? []).map { voice in
            [
                "id": voice.id,
                "name": voice.name,
            ]
        }

        let homesArray: [[String: Any]] = Self.knownHomes(for: config).map { home in
            [
                "id": home.id,
                "name": home.name,
                "selected": !config.structureId.isEmpty && home.id == config.structureId,
            ]
        }

        let recentArray: [[String: Any]] = seam.history.load().map { item in
            [
                "id": item.id.uuidString,
                "text": item.text,
                "target": item.targetName,
                "source": item.source,
                "at": SpeakerConfig.formatISO8601UTC(item.timestamp),
            ]
        }

        return [
            "contract_version": Self.contractVersion,
            "speaker_version": seam.vitruvianSpeakerVersion(),
            "program": seam.program.rawValue,
            "chosen": chosen?.rawValue ?? NSNull(),
            "chosen_running": chosenRunning,
            "app_installed": appInstalled,
            "extension_installed": extensionInstalled,
            "other_installed": otherInstalled,
            "active_door": activeDoor.rawValue,
            "app_running": appRunning,
            "extension_running": extensionRunning,
            "owner_running": ownerRunning,
            "config_initialized": configInitialized,
            "config_problem": configProblem ?? NSNull(),
            "structure_id": config.structureId,
            "structure_name": config.structureName ?? "",
            "homes": homesArray,
            "quiet_hours": quietHoursDict,
            "snooze_until": snoozeUntilValue,
            "outputs_label": config.activeOutputsLabel,
            "outputs_footer": config.outputsFooter,
            "warnings": warnings,
            "local_voice_name": localVoiceName,
            "available_voices": availableVoicesArray,
            "custom_voices": customVoicesArray,
            "settings": settingsArray,
            "speakers": speakersArray,
            "sign_in": signInDict,
            "chat": chatDict,
            "hooks": hooksDict,
            "legacy_launch_agent": integration.isLegacyLaunchAgentInstalled(),
            "recent": recentArray,
            "last": recentArray.first ?? NSNull(),
        ]
    }

    /// Every Google Home structure Vitruvian Speaker knows: the list from the last
    /// saved discovery (`config.homes`), falling back to the saved home when
    /// older configs carry only `structureId` / `structureName`. If `config`
    /// names a `structureId` absent from `config.homes`, it is appended so the
    /// active home is always represented.
    public static func knownHomes(for config: SpeakerConfig) -> [HomeStructure] {
        var seen = Set<String>()
        var result: [HomeStructure] = []
        for home in config.homes ?? [] where !home.id.isEmpty && seen.insert(home.id).inserted {
            let name = (home.id == config.structureId ? config.structureName : nil) ?? home.name
            result.append(HomeStructure(id: home.id, name: name.isEmpty ? home.id : name))
        }
        if !config.structureId.isEmpty, seen.insert(config.structureId).inserted {
            let fallbackName = config.structureName ?? config.structureId
            result.append(HomeStructure(id: config.structureId, name: fallbackName.isEmpty ? config.structureId : fallbackName))
        }
        return result
    }

    // MARK: - `--apply --json '<changes>'`

    private struct IndexedApplyError: Error {
        let opIndex: Int?
        let code: String
        let message: String
        let chosen: String?

        init(opIndex: Int? = nil, code: String, message: String, chosen: String? = nil) {
            self.opIndex = opIndex
            self.code = code
            self.message = message
            self.chosen = chosen
        }
    }

    private struct PendingSwitch {
        let opIndex: Int
        let side: VitruvianSpeakerProfile.Door
        let copy: Bool
        let compare: DoorCompare
        let switchSeam: any SettingsActions.DoorSwitchSeam
    }

    /// Validates and applies `<changes>` atomically under `seam.configFile`'s
    /// lock through `SettingsActions`.
    ///
    /// - When run on a program that is NOT the chosen one (`speaker_door.json`
    ///   names the other program), refuses with code `not_chosen` and names the
    ///   chosen program.
    /// - When any operation is refused, writes nothing and exits non-zero (1)
    ///   with `{"ok":false,"error":{"op_index":n,"code":...,"message":...}}`.
    /// - On success, answers with `{"ok":true,"results":[...],"state":<state>}`
    ///   and exits 0.
    public static func applyOutput(_ rawJSON: String, seam: Seam) -> CLIOutput {
        // 1. Parse top-level JSON envelope first so malformed input is caught cleanly.
        guard let data = rawJSON.data(using: .utf8),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return applyFailure(
                IndexedApplyError(code: "invalid_json", message: "Changes payload must be a valid JSON object.")
            )
        }

        guard let version = intFromJSON(envelope["contract_version"]) else {
            return applyFailure(
                IndexedApplyError(
                    code: "invalid_contract_version",
                    message: "Missing or non-integer \"contract_version\"."
                )
            )
        }
        guard version == Self.contractVersion else {
            return applyFailure(
                IndexedApplyError(
                    code: "unsupported_contract_version",
                    message: "Unsupported contract_version \(version) (expected \(Self.contractVersion))."
                )
            )
        }

        guard let operations = envelope["operations"] as? [[String: Any]] else {
            return applyFailure(
                IndexedApplyError(
                    code: "invalid_operations",
                    message: "\"operations\" must be a JSON array of operation objects."
                )
            )
        }
        // An empty list is a caller's mistake, not a request: say so rather
        // than answer "ok" for a change that never happened.
        guard !operations.isEmpty else {
            return applyFailure(
                IndexedApplyError(
                    code: "no_operations",
                    message: "\"operations\" is empty; send at least one operation."
                )
            )
        }

        // 2. Refuse when another program is the chosen one in speaker_door.json.
        let doorRecord = seam.doorFile.read()
        if let chosen = doorRecord?.chosen, chosen != seam.program {
            return applyFailure(
                IndexedApplyError(
                    opIndex: 0,
                    code: "not_chosen",
                    message: "The Vitruvian Speaker \(chosen.rawValue) is the chosen program; run --apply on \(chosen.rawValue) instead.",
                    chosen: chosen.rawValue
                )
            )
        }

        // 3. Execute the batch transactionally under configFile's lock.
        var secretsChanged = false
        do {
            let results: [[String: Any]] = try seam.configFile.modifyTransaction { config, writeConfig in
                var workingSecrets = seam.secrets.load()
                var cachedVoices: [LocalVoice]?
                func voices() -> [LocalVoice] {
                    if let cachedVoices { return cachedVoices }
                    let loaded = seam.systemVoices()
                    cachedVoices = loaded
                    return loaded
                }
                var secretMutations: [(inout Secrets, inout [[String: Any]]) -> Void] = []
                var hookMutations: [() throws -> Void] = []
                var configDirty = false
                var pendingSwitch: PendingSwitch?
                var opResults: [[String: Any]] = []

                for (index, opDict) in operations.enumerated() {
                    guard let opName = opDict["op"] as? String, !opName.isEmpty else {
                        throw IndexedApplyError(
                            opIndex: index,
                            code: "missing_op",
                            message: "Operation at index \(index) is missing a string \"op\" field."
                        )
                    }

                    switch opName {
                    case "set":
                        guard let rawKey = opDict["key"] as? String, !rawKey.isEmpty else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"set\" operation requires a non-empty \"key\" string."
                            )
                        }
                        guard let key = SettingsCatalog.Key(rawValue: rawKey) else {
                            let refusal = SettingsActions.Refusal.unknownKey(rawKey)
                            throw indexedError(from: refusal, at: index)
                        }
                        guard let rawVal = opDict["value"], !(rawVal is NSNull) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_value",
                                message: "\"set\" operation for \"\(rawKey)\" requires a \"value\"."
                            )
                        }
                        guard let parsedValue = parseSettingsValue(rawVal) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "wrong_kind",
                                message: "Unsupported value type for setting \"\(rawKey)\"."
                            )
                        }
                        let clampNumbers = (opDict["clamp"] as? Bool) ?? true
                        do {
                            let res = try SettingsActions.applySet(
                                key: key,
                                value: parsedValue,
                                to: &config,
                                secrets: workingSecrets,
                                systemVoices: voices(),
                                clampNumbers: clampNumbers
                            )
                            configDirty = true
                            var entryResult: [String: Any] = [
                                "op": "set",
                                "key": res.key.rawValue,
                                "value": jsonValue(res.appliedValue),
                                "clamped": res.clamped,
                            ]
                            if let warning = res.warning {
                                entryResult["warning"] = warning
                            }
                            opResults.append(entryResult)
                        } catch let refusal as SettingsActions.Refusal {
                            throw indexedError(from: refusal, at: index)
                        }

                    case "setDefaultSpeaker":
                        guard let rawKey = opDict["key"] as? String else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"setDefaultSpeaker\" operation requires a \"key\" string."
                            )
                        }
                        do {
                            let res = try SettingsActions.applySet(
                                key: .defaultTarget,
                                value: .string(rawKey),
                                to: &config,
                                secrets: workingSecrets,
                                systemVoices: voices()
                            )
                            configDirty = true
                            opResults.append([
                                "op": "setDefaultSpeaker",
                                "key": res.key.rawValue,
                                "value": jsonValue(res.appliedValue),
                            ])
                        } catch let refusal as SettingsActions.Refusal {
                            throw indexedError(from: refusal, at: index)
                        }

                    case "removeSpeaker":
                        guard let rawKey = opDict["key"] as? String, !rawKey.isEmpty else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"removeSpeaker\" operation requires a non-empty \"key\" string."
                            )
                        }
                        let res = SettingsActions.removeSpeaker(rawKey, from: &config)
                        configDirty = true
                        opResults.append([
                            "op": "removeSpeaker",
                            "key": res.removedKey,
                            "was_present": res.wasPresent,
                            "default_target": res.defaultTarget,
                        ])

                    case "reset":
                        config = SettingsActions.resetSettings(preservingDiscoveryFrom: config)
                        configDirty = true
                        opResults.append([
                            "op": "reset",
                            "default_target": config.defaultTarget,
                        ])

                    case "clearChatToken":
                        let tokenRaw = (opDict["token"] as? String) ?? (opDict["service"] as? String)
                        guard let tokenRaw, let token = SettingsActions.ChatToken(rawValue: tokenRaw) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_token",
                                message: "\"clearChatToken\" requires \"token\" to be one of: slack, beeper, courier."
                            )
                        }
                        SettingsActions.applyClearChatToken(token, to: &workingSecrets)
                        let courierSwitchedOff = SettingsActions.applyClearChatToken(token, to: &config)
                        secretMutations.append { lockedSecrets, _ in
                            SettingsActions.applyClearChatToken(token, to: &lockedSecrets)
                        }
                        if courierSwitchedOff {
                            configDirty = true
                        }
                        opResults.append([
                            "op": "clearChatToken",
                            "token": token.rawValue,
                            "courier_switched_off": courierSwitchedOff,
                        ])

                    case "saveOAuthClient":
                        guard let clientId = opDict["client_id"] as? String else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_client_id",
                                message: "\"saveOAuthClient\" requires a string \"client_id\" field."
                            )
                        }
                        let clientSecret = opDict["client_secret"] as? String
                        let res = SettingsActions.applyOAuthClientOverride(
                            id: clientId,
                            secret: clientSecret,
                            to: &workingSecrets
                        )
                        secretMutations.append { lockedSecrets, results in
                            let lockedRes = SettingsActions.applyOAuthClientOverride(
                                id: clientId,
                                secret: clientSecret,
                                to: &lockedSecrets
                            )
                            results[index] = [
                                "op": "saveOAuthClient",
                                "client_id": lockedRes.clientId ?? NSNull(),
                                "has_client_secret": lockedRes.hasClientSecret,
                                "cleared": lockedRes.cleared,
                                "kept_existing_secret": lockedRes.keptExistingSecret,
                            ]
                        }
                        opResults.append([
                            "op": "saveOAuthClient",
                            "client_id": res.clientId ?? NSNull(),
                            "has_client_secret": res.hasClientSecret,
                            "cleared": res.cleared,
                            "kept_existing_secret": res.keptExistingSecret,
                        ])

                    case "switchTo":
                        guard operations.count == 1 else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "switch_must_be_alone",
                                message: "Send \"switchTo\" on its own in a single-operation --apply batch."
                            )
                        }
                        guard let sideRaw = opDict["side"] as? String,
                              let targetSide = VitruvianSpeakerProfile.Door(rawValue: sideRaw) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_side",
                                message: "\"switchTo\" requires \"side\" to be \"app\" or \"extension\"."
                            )
                        }
                        let copyFlag = (opDict["copy"] as? Bool) ?? false
                        guard let switchSeam = seam.doorSwitchSeam() else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "switch_refused",
                                message: "Door switching is not configured on this command-line seam."
                            )
                        }
                        let sourceSide: VitruvianSpeakerProfile.Door = targetSide == .app ? .extension : .app
                        do {
                            guard let compare = try SettingsActions.beginSwitch(
                                from: sourceSide,
                                into: targetSide,
                                purpose: .choose,
                                seam: switchSeam
                            ) else {
                                let notFound = targetSide == .extension ? DoorWords.extensionNotFound : DoorWords.appNotFound
                                throw IndexedApplyError(
                                    opIndex: index,
                                    code: "switch_refused",
                                    message: switchSeam.inTrash()
                                        ? "This copy of Vitruvian Speaker is in the Trash and cannot switch doors."
                                        : notFound
                                )
                            }
                            pendingSwitch = PendingSwitch(
                                opIndex: index,
                                side: targetSide,
                                copy: copyFlag,
                                compare: compare,
                                switchSeam: switchSeam
                            )
                            opResults.append([
                                "op": "switchTo",
                                "side": targetSide.rawValue,
                            ])
                        } catch let refused as SettingsActions.SwitchRefused {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "switch_refused",
                                message: refused.message
                            )
                        }

                    case "setSecret":
                        guard let rawName = opDict["name"] as? String,
                              let secretName = SettingsActions.SecretName(rawValue: rawName) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_secret_name",
                                message: "\"setSecret\" requires \"name\" to be one of: slack, beeper, courier, geminiKey."
                            )
                        }
                        guard let rawValue = opDict["value"] as? String else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_value",
                                message: "\"setSecret\" for \"\(secretName.rawValue)\" requires a string \"value\"."
                            )
                        }
                        let res = SettingsActions.applySetSecret(
                            secretName,
                            value: rawValue,
                            to: &workingSecrets,
                            config: &config
                        )
                        secretMutations.append { lockedSecrets, _ in
                            SettingsActions.applySetSecret(secretName, value: rawValue, to: &lockedSecrets)
                        }
                        if res.courierSwitchedOff {
                            configDirty = true
                        }
                        var entryResult: [String: Any] = [
                            "op": "setSecret",
                            "name": secretName.rawValue,
                            "cleared": res.cleared,
                        ]
                        if secretName == .courier {
                            entryResult["courier_switched_off"] = res.courierSwitchedOff
                        }
                        opResults.append(entryResult)

                    case "snooze":
                        let hasClear = opDict["clear"] != nil && !(opDict["clear"] is NSNull)
                        let hasMinutes = opDict["minutes"] != nil && !(opDict["minutes"] is NSNull)
                        if hasClear && hasMinutes {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_snooze",
                                message: "\"snooze\" accepts either \"minutes\" (1...240) or \"clear\": true, not both."
                            )
                        }
                        if hasClear {
                            guard boolFromJSON(opDict["clear"]) == true else {
                                throw IndexedApplyError(
                                    opIndex: index,
                                    code: "invalid_snooze",
                                    message: "\"snooze\" with \"clear\" requires \"clear\": true."
                                )
                            }
                            _ = try SettingsActions.applySnooze(minutes: nil, now: seam.now(), to: &config)
                            configDirty = true
                            opResults.append([
                                "op": "snooze",
                                "cleared": true,
                                "snooze_until": NSNull(),
                            ])
                        } else if hasMinutes {
                            guard let minutes = intFromJSON(opDict["minutes"]) else {
                                throw IndexedApplyError(
                                    opIndex: index,
                                    code: "wrong_kind",
                                    message: "\"snooze\" requires \"minutes\" to be an integer."
                                )
                            }
                            do {
                                let until = try SettingsActions.applySnooze(
                                    minutes: minutes,
                                    now: seam.now(),
                                    to: &config
                                )
                                configDirty = true
                                opResults.append([
                                    "op": "snooze",
                                    "minutes": minutes,
                                    "snooze_until": until.map(SpeakerConfig.formatISO8601UTC) ?? NSNull(),
                                ])
                            } catch let refusal as SettingsActions.Refusal {
                                throw indexedError(from: refusal, at: index)
                            }
                        } else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_snooze",
                                message: "\"snooze\" requires either \"minutes\" (1...240) or \"clear\": true."
                            )
                        }

                    case "setNetwork":
                        guard let rawApp = opDict["app"] as? String,
                              let app = ChatApp(rawValue: rawApp) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_app",
                                message: "\"setNetwork\" requires \"app\" to be \"beeper\" or \"courier\"."
                            )
                        }
                        guard let rawKey = opDict["key"] as? String else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"setNetwork\" requires a non-empty \"key\" string."
                            )
                        }
                        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedKey.isEmpty else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"setNetwork\" requires a non-empty \"key\" string."
                            )
                        }
                        guard let reading = boolFromJSON(opDict["reading"]) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "wrong_kind",
                                message: "\"setNetwork\" requires \"reading\" to be a boolean."
                            )
                        }
                        SettingsActions.applySetNetwork(app: app, key: trimmedKey, reading: reading, to: &config)
                        configDirty = true
                        opResults.append([
                            "op": "setNetwork",
                            "app": app.rawValue,
                            "key": trimmedKey,
                            "reading": reading,
                        ])

                    case "setReadAnyway":
                        guard let rawKey = opDict["key"] as? String else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"setReadAnyway\" requires a non-empty \"key\" string."
                            )
                        }
                        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedKey.isEmpty else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "missing_key",
                                message: "\"setReadAnyway\" requires a non-empty \"key\" string."
                            )
                        }
                        guard let isOn = boolFromJSON(opDict["on"]) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "wrong_kind",
                                message: "\"setReadAnyway\" requires \"on\" to be a boolean."
                            )
                        }
                        SettingsActions.applySetReadAnyway(key: trimmedKey, on: isOn, to: &config)
                        configDirty = true
                        opResults.append([
                            "op": "setReadAnyway",
                            "key": trimmedKey,
                            "on": isOn,
                        ])

                    case "importAntigravity":
                        guard let imported = SettingsActions.readAntigravityTokens(at: seam.antigravityTokensURL) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "no_antigravity_tokens",
                                message: "No Google Home login found in the Antigravity token file."
                            )
                        }
                        SettingsActions.applyImportAntigravity(imported, to: &workingSecrets)
                        secretMutations.append { lockedSecrets, _ in
                            SettingsActions.applyImportAntigravity(imported, to: &lockedSecrets)
                        }
                        opResults.append([
                            "op": "importAntigravity",
                            "imported": true,
                        ])

                    case "agentHook":
                        // A hook writes the coding agent's own file, outside
                        // this transaction, so a later failure could not undo
                        // it: like a switch, it is sent on its own.
                        guard operations.count == 1 else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "hook_must_be_alone",
                                message: "Send \"agentHook\" on its own in a single-operation --apply batch."
                            )
                        }
                        guard let rawAgent = opDict["agent"] as? String,
                              let agent = SettingsActions.codingAgent(for: rawAgent) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_agent",
                                message: "\"agentHook\" requires \"agent\" to be one of: claude_code, antigravity, opencode."
                            )
                        }
                        guard let rawAction = opDict["action"] as? String,
                              let action = SettingsActions.AgentHookAction(rawValue: rawAction) else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_action",
                                message: "\"agentHook\" requires \"action\" to be one of: install, remove, addInstruction, disableRival."
                            )
                        }
                        if action == .install, !AgentIntegration.isVitruvianSpeakerProgram(seam.hookExecutablePath) {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "invalid_hook_program",
                                message: "Refusing to install a hook pointing to a non-Vitruvian Speaker executable."
                            )
                        }
                        hookMutations.append {
                            try SettingsActions.performAgentHook(
                                agent: agent,
                                action: action,
                                home: seam.agentHome,
                                executablePath: seam.hookExecutablePath
                            )
                        }
                        opResults.append([
                            "op": "agentHook",
                            "agent": SettingsActions.wireName(for: agent),
                            "action": action.rawValue,
                        ])

                    case "removeLegacyAgent":
                        // Like a hook, it acts outside this transaction (a
                        // launchd job and a file in LaunchAgents), so it is
                        // sent on its own.
                        guard operations.count == 1 else {
                            throw IndexedApplyError(
                                opIndex: index,
                                code: "legacy_must_be_alone",
                                message: "Send \"removeLegacyAgent\" on its own in a single-operation --apply batch."
                            )
                        }
                        let integration = AgentIntegration(
                            home: seam.agentHome,
                            executablePath: seam.hookExecutablePath,
                            bootout: seam.launchctlBootout
                        )
                        let wasInstalled = integration.isLegacyLaunchAgentInstalled()
                        if wasInstalled {
                            hookMutations.append { try integration.removeLegacyLaunchAgent() }
                        }
                        opResults.append([
                            "op": "removeLegacyAgent",
                            "removed": wasInstalled,
                        ])

                    default:
                        throw IndexedApplyError(
                            opIndex: index,
                            code: "unknown_op",
                            message: "Unknown operation \"\(opName)\"."
                        )
                    }
                }

                // All operations in the batch passed validation. Execute the
                // single pending door switch first; if it fails, write nothing.
                if let pending = pendingSwitch {
                    let outcome = SettingsActions.finishSwitch(
                        compare: pending.compare,
                        copy: pending.copy,
                        seam: pending.switchSeam
                    )
                    switch outcome {
                    case .appChosen(let report), .extensionChosen(_, let report), .copiedOnly(let report):
                        opResults[pending.opIndex]["report"] = report
                    case .choiceChanged(let report):
                        throw IndexedApplyError(
                            opIndex: pending.opIndex,
                            code: "switch_refused",
                            message: report.first ?? DoorWords.choiceChanged
                        )
                    case .abortedInTrash:
                        throw IndexedApplyError(
                            opIndex: pending.opIndex,
                            code: "switch_refused",
                            message: "This copy of Vitruvian Speaker is in the Trash and cannot switch doors."
                        )
                    case .stayOnCompare(let cmp, let report):
                        throw IndexedApplyError(
                            opIndex: pending.opIndex,
                            code: "switch_refused",
                            message: cmp.problem ?? report.first ?? "Could not complete switch."
                        )
                    }
                }

                if !secretMutations.isEmpty {
                    try seam.secrets.update { lockedSecrets in
                        for mutate in secretMutations {
                            mutate(&lockedSecrets, &opResults)
                        }
                    }
                }
                for performHook in hookMutations {
                    do {
                        try performHook()
                    } catch {
                        // An agentHook is alone in its batch, so it is op 0.
                        throw IndexedApplyError(
                            opIndex: 0,
                            code: "agent_hook_failed",
                            message: error.localizedDescription
                        )
                    }
                }
                writeConfig = configDirty
                secretsChanged = !secretMutations.isEmpty
                return opResults
            }

            // A running Vitruvian Speaker of this program learns of new secrets
            // only after the batch has succeeded.
            if secretsChanged { seam.credentialsChanged() }

            let response: [String: Any] = [
                "ok": true,
                "results": results,
                "state": stateObject(seam: seam),
            ]
            return CLIOutput(stdout: [encodeJSON(response)], exitCode: 0)
        } catch let err as IndexedApplyError {
            return applyFailure(err)
        } catch let err as ConfigFileError {
            return applyFailure(
                IndexedApplyError(code: "config_unreadable", message: err.localizedDescription)
            )
        } catch {
            return applyFailure(
                IndexedApplyError(code: "apply_failed", message: error.localizedDescription)
            )
        }
    }

    // MARK: - Helpers

    private static func indexedError(from refusal: SettingsActions.Refusal, at index: Int) -> IndexedApplyError {
        let code: String
        switch refusal {
        case .unknownKey:
            code = "unknown_key"
        case .wrongKind:
            code = "wrong_kind"
        case .invalidChoice:
            code = "invalid_choice"
        case .outOfRange:
            code = "out_of_range"
        case .invalidTime:
            code = "invalid_time"
        case .invalidAddress:
            code = "invalid_address"
        case .missingToken:
            code = "missing_token"
        }
        return IndexedApplyError(
            opIndex: index,
            code: code,
            message: refusal.localizedDescription
        )
    }

    private static func applyFailure(_ err: IndexedApplyError) -> CLIOutput {
        var errorDict: [String: Any] = [
            "code": err.code,
            "message": err.message,
        ]
        if let opIndex = err.opIndex {
            errorDict["op_index"] = opIndex
        }
        if let chosen = err.chosen {
            errorDict["chosen"] = chosen
        }
        let payload: [String: Any] = [
            "ok": false,
            "error": errorDict,
        ]
        return CLIOutput(stdout: [encodeJSON(payload)], exitCode: 1)
    }

    /// JSON error output when `--apply` exceeds its headless time limit.
    public static func timedOutOutput() -> CLIOutput {
        applyFailure(IndexedApplyError(code: "timed_out", message: "timed out"))
    }

    private static func parseSettingsValue(_ raw: Any) -> SettingsActions.Value? {
        if let s = raw as? String {
            return .string(s)
        }
        if let num = raw as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            let doubleVal = num.doubleValue
            guard doubleVal.isFinite, doubleVal == doubleVal.rounded() else {
                return nil
            }
            return .int(num.intValue)
        }
        return nil
    }

    private static func intFromJSON(_ raw: Any?) -> Int? {
        guard let num = raw as? NSNumber, CFGetTypeID(num) != CFBooleanGetTypeID() else {
            return nil
        }
        let d = num.doubleValue
        guard d.isFinite, d == d.rounded() else { return nil }
        return num.intValue
    }

    private static func boolFromJSON(_ raw: Any?) -> Bool? {
        guard let num = raw as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() else {
            return nil
        }
        return num.boolValue
    }

    private static func jsonValue(_ value: SettingsActions.Value) -> Any {
        switch value {
        case .bool(let b): return b
        case .int(let n): return n
        case .string(let s): return s
        }
    }

    private static func agentSnakeKey(_ agent: CodingAgent) -> String {
        switch agent {
        case .claudeCode: return "claude_code"
        case .antigravity: return "antigravity"
        case .opencode: return "opencode"
        }
    }

    private static func agentDashName(_ agent: CodingAgent) -> String {
        switch agent {
        case .claudeCode: return "claude-code"
        case .antigravity: return "antigravity"
        case .opencode: return "opencode"
        }
    }

    public static func encodeJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
