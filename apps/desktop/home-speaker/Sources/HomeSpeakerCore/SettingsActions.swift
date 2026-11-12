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

/// One set of settings and secret actions for the Home Speaker engine.
///
/// Every surface (the macOS menu-bar app, the Vitruvian extension, and the
/// Android remote bridge) changes settings, secrets, and the active door
/// choice through these functions under the engine's existing file locks
/// (`SpeakerConfigFile`, `SecretStore`, and `DoorFile`).
public enum SettingsActions {

    // MARK: - Values, Results & Refusals

    /// A typed setting value passed to `set(key:value:)`.
    public enum Value: Sendable, Equatable {
        case bool(Bool)
        case int(Int)
        case string(String)

        public var kindDescription: String {
            switch self {
            case .bool: return "toggle (Bool)"
            case .int: return "number (Int)"
            case .string: return "string"
            }
        }
    }

    /// Why a settings action was refused before writing.
    public enum Refusal: Error, LocalizedError, Sendable, Equatable {
        case unknownKey(String)
        case wrongKind(key: String, expected: SettingsCatalog.Kind, got: Value)
        case invalidChoice(key: String, value: String, allowed: [String])
        case outOfRange(key: String, value: Int, min: Int, max: Int)
        case invalidTime(key: String, value: String)
        case invalidAddress(key: String, reason: String)
        case missingToken(key: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .unknownKey(let key):
                return "Unknown setting key \"\(key)\"."
            case .wrongKind(let key, let expected, let got):
                return "Setting \"\(key)\" expects a \(expected.rawValue) value, not \(got.kindDescription)."
            case .invalidChoice(let key, let value, let allowed):
                let list = allowed.isEmpty ? "none" : allowed.joined(separator: ", ")
                return "Value \"\(value)\" is not a valid choice for \"\(key)\" (allowed: \(list))."
            case .outOfRange(let key, _, let min, let max):
                switch key {
                case SettingsCatalog.Key.announceVolume.rawValue:
                    return "The announcement volume is a whole number from \(min) to \(max)"
                case SettingsCatalog.Key.pauseMediaExtraSeconds.rawValue:
                    return "Resume after is a number of seconds from \(min) to \(max)"
                case SettingsCatalog.Key.pollIntervalSeconds.rawValue:
                    return "The poll interval is a whole number of seconds from \(min) to \(max)"
                case SettingsCatalog.Key.speakerVolume.rawValue:
                    return "A volume is a whole number from \(min) to \(max)"
                case "snooze":
                    return "Snooze is a whole number of minutes from \(min) to \(max)"
                default:
                    return "Value must be between \(min) and \(max)"
                }
            case .invalidTime(_, _):
                return "Quiet hours take a time as HH:mm, such as 22:00"
            case .invalidAddress(_, let reason):
                return reason
            case .missingToken(_, let reason):
                return reason
            }
        }
    }

    /// What `set(key:value:)` changed, plus any clamp warning.
    public struct SetResult: Equatable {
        public let key: SettingsCatalog.Key
        public let appliedValue: Value
        public let clamped: Bool
        public let warning: String?
        public let config: SpeakerConfig

        public init(
            key: SettingsCatalog.Key,
            appliedValue: Value,
            clamped: Bool = false,
            warning: String? = nil,
            config: SpeakerConfig
        ) {
            self.key = key
            self.appliedValue = appliedValue
            self.clamped = clamped
            self.warning = warning
            self.config = config
        }
    }

    /// What `removeSpeaker` changed.
    public struct RemoveSpeakerResult: Equatable {
        public let removedKey: String
        public let wasPresent: Bool
        public let defaultTarget: String
        public let config: SpeakerConfig

        public init(removedKey: String, wasPresent: Bool, defaultTarget: String, config: SpeakerConfig) {
            self.removedKey = removedKey
            self.wasPresent = wasPresent
            self.defaultTarget = defaultTarget
            self.config = config
        }
    }

    /// What `saveOAuthClientOverride` stored.
    public struct OAuthClientOverrideResult: Sendable, Equatable {
        public let clientId: String?
        public let hasClientSecret: Bool
        public let cleared: Bool
        public let keptExistingSecret: Bool

        public init(clientId: String?, hasClientSecret: Bool, cleared: Bool, keptExistingSecret: Bool) {
            self.clientId = clientId
            self.hasClientSecret = hasClientSecret
            self.cleared = cleared
            self.keptExistingSecret = keptExistingSecret
        }
    }

    /// Which chat service token to clear.
    public enum ChatToken: String, CaseIterable, Sendable, Equatable {
        case slack
        case beeper
        case courier

        public init(_ app: ChatApp) {
            switch app {
            case .beeper: self = .beeper
            case .courier: self = .courier
            }
        }
    }

    /// What `clearChatToken` changed.
    public struct ClearChatTokenResult: Sendable, Equatable {
        public let token: ChatToken
        public let courierSwitchedOff: Bool

        public init(token: ChatToken, courierSwitchedOff: Bool) {
            self.token = token
            self.courierSwitchedOff = courierSwitchedOff
        }
    }

    // MARK: - 1. Set a Setting by Catalog Key

    /// Sets one setting identified by raw `SettingsCatalog` key under `file`'s lock.
    @discardableResult
    public static func set(
        key rawKey: String,
        value: Value,
        in file: SpeakerConfigFile,
        secrets: SecretStore? = nil,
        systemVoices: [LocalVoice] = []
    ) throws -> SetResult {
        guard let key = SettingsCatalog.Key(rawValue: rawKey) else {
            throw Refusal.unknownKey(rawKey)
        }
        return try set(key: key, value: value, in: file, secrets: secrets, systemVoices: systemVoices)
    }

    /// Sets one setting identified by `SettingsCatalog.Key` under `file`'s lock.
    @discardableResult
    public static func set(
        key: SettingsCatalog.Key,
        value: Value,
        in file: SpeakerConfigFile,
        secrets: SecretStore? = nil,
        systemVoices: [LocalVoice] = []
    ) throws -> SetResult {
        let loadedSecrets = secrets?.load()
        var probe: SpeakerConfig
        switch file.read() {
        case .loaded(let cfg):
            probe = cfg
        case .missing:
            probe = SpeakerConfig()
        case .unreadable(let err):
            throw err
        }
        // Validate against current state before taking the write lock so a
        // refused change never writes to disk.
        _ = try applySet(
            key: key,
            value: value,
            to: &probe,
            secrets: loadedSecrets,
            systemVoices: systemVoices
        )

        var outcome: SetResult?
        var callbackError: Error?
        try file.modify { config in
            do {
                outcome = try applySet(
                    key: key,
                    value: value,
                    to: &config,
                    secrets: loadedSecrets,
                    systemVoices: systemVoices
                )
            } catch {
                callbackError = error
            }
        }
        if let callbackError { throw callbackError }
        return outcome!
    }

    /// Pure in-memory validation, clamping, and mutation for `set(key:value:)`.
    @discardableResult
    public static func applySet(
        key: SettingsCatalog.Key,
        value: Value,
        to config: inout SpeakerConfig,
        secrets: Secrets? = nil,
        systemVoices: [LocalVoice] = [],
        clampNumbers: Bool = true
    ) throws -> SetResult {
        let catalog = SettingsCatalog(config: config, systemVoices: systemVoices)
        let entry = catalog.entry(key)

        switch (entry.kind, value) {
        case (.toggle, .bool(let flag)):
            if key == .courierEnabled, flag, !config.effectiveChatMonitor.courierEnabled,
               let secrets, secrets.token(for: .courier) == nil {
                throw Refusal.missingToken(key: key.rawValue, reason: "Save a Courier token first")
            }
            applyToggle(key, flag, to: &config)
            return SetResult(key: key, appliedValue: .bool(flag), config: config)

        case (.choice, .string(let choice)):
            let allowed = entry.choices.map(\.value)
            let isValidTargetAlias = (key == .defaultTarget && config.targets[choice] != nil)
            guard isValidTargetAlias || allowed.contains(choice) else {
                throw Refusal.invalidChoice(key: key.rawValue, value: choice, allowed: allowed)
            }
            applyChoice(key, choice, to: &config)
            return SetResult(key: key, appliedValue: .string(choice), config: config)

        case (.number, .int(let rawNumber)):
            let limits = entry.limits!
            if !clampNumbers, rawNumber < limits.min || rawNumber > limits.max {
                throw Refusal.outOfRange(key: key.rawValue, value: rawNumber, min: limits.min, max: limits.max)
            }
            let clampedValue = limits.clamp(rawNumber)
            let wasClamped = clampedValue != rawNumber
            let warning = wasClamped
                ? "\(entry.label) clamped from \(rawNumber) to \(clampedValue) (allowed \(limits.min)...\(limits.max))."
                : nil
            applyNumber(key, clampedValue, to: &config)
            return SetResult(
                key: key,
                appliedValue: .int(clampedValue),
                clamped: wasClamped,
                warning: warning,
                config: config
            )

        case (.text, .string(let rawText)):
            let applied = try applyText(key, rawText, to: &config)
            return SetResult(key: key, appliedValue: .string(applied), config: config)

        case (.time, .string(let rawTime)):
            let trimmed = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = SettingsCatalog.normalizedQuietHour(trimmed) else {
                throw Refusal.invalidTime(key: key.rawValue, value: rawTime)
            }
            if key == .quietHoursStart {
                config.quietHoursStart = normalized
            } else if key == .quietHoursEnd {
                config.quietHoursEnd = normalized
            }
            return SetResult(key: key, appliedValue: .string(normalized), config: config)

        default:
            throw Refusal.wrongKind(key: key.rawValue, expected: entry.kind, got: value)
        }
    }

    /// Convenience in-memory `applySet` accepting a raw string representation
    /// (as delivered by UI events), parsing booleans/numbers according to the
    /// catalog entry's kind, checking `hasCourierToken`, and returning `true`
    /// when the effective setting value in `config` changed.
    @discardableResult
    public static func applySet(
        key: SettingsCatalog.Key,
        value rawValue: String,
        to config: inout SpeakerConfig,
        clampNumbers: Bool = true,
        hasCourierToken: Bool = true,
        systemVoices: [LocalVoice] = []
    ) throws -> Bool {
        let catalog = SettingsCatalog(config: config, systemVoices: systemVoices)
        let entry = catalog.entry(key)
        let beforeEffective = effectiveValue(for: key, in: config)

        let parsedValue: Value
        switch entry.kind {
        case .toggle:
            guard let flag = Bool(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                throw Refusal.wrongKind(key: key.rawValue, expected: .toggle, got: .string(rawValue))
            }
            parsedValue = .bool(flag)
        case .number:
            let limits = entry.limits!
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key == .pauseMediaExtraSeconds {
                guard let seconds = Double(trimmed), seconds.isFinite else {
                    throw Refusal.outOfRange(key: key.rawValue, value: limits.min - 1, min: limits.min, max: limits.max)
                }
                if !clampNumbers, seconds < Double(limits.min) || seconds > Double(limits.max) {
                    throw Refusal.outOfRange(key: key.rawValue, value: limits.min - 1, min: limits.min, max: limits.max)
                }
                parsedValue = .int(Int(seconds.rounded()))
            } else {
                guard let number = Int(trimmed) else {
                    throw Refusal.outOfRange(key: key.rawValue, value: limits.min - 1, min: limits.min, max: limits.max)
                }
                parsedValue = .int(number)
            }
        case .choice, .text, .time:
            parsedValue = .string(rawValue)
        }

        let syntheticSecrets: Secrets? = hasCourierToken ? Secrets(courierToken: "present") : Secrets()
        _ = try applySet(
            key: key,
            value: parsedValue,
            to: &config,
            secrets: syntheticSecrets,
            systemVoices: systemVoices,
            clampNumbers: clampNumbers
        )
        return effectiveValue(for: key, in: config) != beforeEffective
    }

    /// Returns the catalog value for `key` under `config`, filling in the
    /// catalog's default quiet-hour times when unset and `speakerVolume` (or
    /// the catalog's default volume) for `.speakerVolume`.
    public static func catalogValue(
        for key: SettingsCatalog.Key,
        in config: SpeakerConfig,
        speakerVolume: Int? = nil
    ) -> Value {
        switch key {
        case .speakerVolume:
            return .int(speakerVolume ?? SettingsCatalog.speakerVolumeLimits.defaultValue)
        case .quietHoursStart:
            return .string(config.quietHoursStart.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursStart)
        case .quietHoursEnd:
            return .string(config.quietHoursEnd.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursEnd)
        default:
            return effectiveValue(for: key, in: config)
        }
    }

    private static func effectiveValue(for key: SettingsCatalog.Key, in config: SpeakerConfig) -> Value {
        switch key {
        case .enabled: return .bool(config.enabled)
        case .announceVolumeEnabled: return .bool(config.effectiveAnnounceVolumeEnabled)
        case .pauseMedia: return .bool(config.effectivePauseMedia)
        case .quietHoursEnabled: return .bool(config.quietHoursEnabled ?? false)
        case .speakHome: return .bool(config.effectiveSpeakHome)
        case .homeCastVoice: return .bool(config.effectiveHomeCastVoice)
        case .speakLocal: return .bool(config.effectiveSpeakLocal)
        case .speakPhone: return .bool(config.effectiveSpeakPhone)
        case .phonePauseMedia: return .bool(config.effectivePhonePauseMedia)
        case .phoneHeadphonesOnly: return .bool(config.effectivePhoneHeadphonesOnly)
        case .announceClaudeCode: return .bool(config.announces(.claudeCode))
        case .announceAntigravity: return .bool(config.announces(.antigravity))
        case .announceOpenCode: return .bool(config.announces(.opencode))
        case .announceSource: return .string(config.effectiveAnnounceSource.rawValue)
        case .slackEnabled: return .bool(config.effectiveChatMonitor.slackEnabled)
        case .googleChatEnabled: return .bool(config.effectiveChatMonitor.googleChatEnabled)
        case .beeperEnabled: return .bool(config.effectiveChatMonitor.beeperEnabled)
        case .courierEnabled: return .bool(config.effectiveChatMonitor.courierEnabled)
        case .muteOwnMessages: return .bool(config.effectiveChatMonitor.muteOwnMessages)
        case .speechLength: return .string(config.effectiveSpeechLength.rawValue)
        case .announcementStyle: return .string(config.effectiveAnnouncementStyle.rawValue)
        case .styleModel: return .string(config.effectiveStyleModel.rawValue)
        case .defaultTarget: return .string(config.defaultTarget)
        case .localEngine: return .string(config.effectiveLocalEngine.rawValue)
        case .geminiVoice: return .string(config.effectiveGeminiVoice)
        case .localVoice: return .string(config.effectiveLocalVoice)
        case .googleChatSource: return .string(config.effectiveChatMonitor.googleChatSource.rawValue)
        case .beeperAnnounce: return .string(config.effectiveChatMonitor.beeperAnnounce.rawValue)
        case .courierAnnounce: return .string(config.effectiveChatMonitor.courierAnnounce.rawValue)
        case .speakerVolume: return .int(0)
        case .announceVolume: return .int(config.effectiveAnnounceVolume)
        case .pauseMediaExtraSeconds: return .int(Int(config.effectivePauseMediaExtraSeconds))
        case .pollIntervalSeconds: return .int(config.effectiveChatMonitor.pollIntervalSeconds)
        case .customStylePrompt: return .string(config.customStylePrompt ?? "")
        case .gwsAccount: return .string(config.effectiveChatMonitor.gwsAccount)
        case .beeperAddress: return .string(config.effectiveChatMonitor.beeperAddress)
        case .courierAddress: return .string(config.effectiveChatMonitor.courierAddress)
        case .quietHoursStart: return .string(config.quietHoursStart ?? "")
        case .quietHoursEnd: return .string(config.quietHoursEnd ?? "")
        }
    }

    private static func applyToggle(_ key: SettingsCatalog.Key, _ flag: Bool, to config: inout SpeakerConfig) {
        switch key {
        case .enabled:
            config.enabled = flag
        case .announceVolumeEnabled:
            config.announceVolumeEnabled = flag
        case .pauseMedia:
            config.pauseMedia = flag
        case .quietHoursEnabled:
            config.quietHoursEnabled = flag
        case .speakHome:
            config.speakHome = flag
        case .homeCastVoice:
            config.homeCastVoice = flag
        case .speakLocal:
            config.speakLocal = flag
        case .speakPhone:
            config.speakPhone = flag
        case .phonePauseMedia:
            config.phonePauseMedia = flag
        case .phoneHeadphonesOnly:
            config.phoneHeadphonesOnly = flag
        case .announceClaudeCode:
            config.announceClaudeCode = flag
        case .announceAntigravity:
            config.announceAntigravity = flag
        case .announceOpenCode:
            config.announceOpenCode = flag
        case .slackEnabled:
            config.effectiveChatMonitor.slackEnabled = flag
        case .googleChatEnabled:
            config.effectiveChatMonitor.googleChatEnabled = flag
        case .beeperEnabled:
            config.effectiveChatMonitor.beeperEnabled = flag
        case .courierEnabled:
            config.effectiveChatMonitor.courierEnabled = flag
        case .muteOwnMessages:
            config.effectiveChatMonitor.muteOwnMessages = flag
        default:
            break
        }
    }

    private static func applyChoice(_ key: SettingsCatalog.Key, _ choice: String, to config: inout SpeakerConfig) {
        switch key {
        case .speechLength:
            if let v = SpeechLength(rawValue: choice) { config.speechLength = v }
        case .announceSource:
            if let v = AnnounceSourceLabel(rawValue: choice) { config.announceSource = v }
        case .announcementStyle:
            if let v = AnnouncementStyle(rawValue: choice) { config.announcementStyle = v }
        case .styleModel:
            if let v = StyleModel(rawValue: choice) { config.styleModel = v }
        case .defaultTarget:
            config.defaultTarget = choice
        case .localEngine:
            if let v = LocalVoiceEngine(rawValue: choice) { config.localEngine = v }
        case .geminiVoice:
            config.geminiVoice = choice
        case .localVoice:
            config.localVoice = choice.isEmpty ? nil : choice
        case .googleChatSource:
            if let v = ChatMonitorConfig.GoogleChatSource(rawValue: choice) {
                config.effectiveChatMonitor.googleChatSource = v
            }
        case .beeperAnnounce:
            if let v = ChatMonitorConfig.BeeperAnnounce(rawValue: choice) {
                config.effectiveChatMonitor.beeperAnnounce = v
            }
        case .courierAnnounce:
            if let v = ChatMonitorConfig.BeeperAnnounce(rawValue: choice) {
                config.effectiveChatMonitor.courierAnnounce = v
            }
        default:
            break
        }
    }

    private static func applyNumber(_ key: SettingsCatalog.Key, _ number: Int, to config: inout SpeakerConfig) {
        switch key {
        case .speakerVolume:
            // Hardware speaker volume is sent to the Google Home device; the
            // catalog validates and clamps the requested percentage here.
            break
        case .announceVolume:
            config.announceVolume = number
        case .pauseMediaExtraSeconds:
            config.pauseMediaExtraSeconds = Double(number)
        case .pollIntervalSeconds:
            config.effectiveChatMonitor.pollIntervalSeconds = number
        default:
            break
        }
    }

    private static func applyText(_ key: SettingsCatalog.Key, _ rawText: String, to config: inout SpeakerConfig) throws -> String {
        switch key {
        case .customStylePrompt:
            config.customStylePrompt = rawText
            return rawText
        case .gwsAccount:
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            config.effectiveChatMonitor.gwsAccount = trimmed
            return trimmed
        case .beeperAddress:
            if let problem = ChatAppClient.addressProblem(rawText, app: .beeper) {
                throw Refusal.invalidAddress(key: key.rawValue, reason: problem.localizedDescription)
            }
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            config.effectiveChatMonitor.beeperAddress = trimmed
            return trimmed
        case .courierAddress:
            if let problem = ChatAppClient.addressProblem(rawText, app: .courier) {
                throw Refusal.invalidAddress(key: key.rawValue, reason: problem.localizedDescription)
            }
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            config.effectiveChatMonitor.courierAddress = trimmed
            return trimmed
        default:
            return rawText
        }
    }

    // MARK: - 2. Remove a Speaker

    /// Removes one speaker alias under `file`'s lock and picks the next
    /// default speaker by name (`SpeakerConfig.removeTarget`).
    @discardableResult
    public static func removeSpeaker(_ key: String, in file: SpeakerConfigFile) throws -> RemoveSpeakerResult {
        var outcome: RemoveSpeakerResult?
        try file.modify { config in
            outcome = removeSpeaker(key, from: &config)
        }
        return outcome!
    }

    /// Pure in-memory helper for removing a speaker alias.
    @discardableResult
    public static func removeSpeaker(_ key: String, from config: inout SpeakerConfig) -> RemoveSpeakerResult {
        let wasPresent = config.targets[key] != nil
        config.removeTarget(key)
        return RemoveSpeakerResult(
            removedKey: key,
            wasPresent: wasPresent,
            defaultTarget: config.defaultTarget,
            config: config
        )
    }

    // MARK: - 3. Save Google Sign-In Client Override

    /// Saves or clears the Google OAuth client override under `store`'s lock,
    /// following the single rule across all surfaces:
    /// - Trim both `id` and `secret`.
    /// - A blank client ID clears both `oauthClientIdOverride` and `oauthClientSecretOverride`.
    /// - A blank secret with an UNCHANGED client ID keeps the stored secret.
    /// - A blank secret with a CHANGED client ID clears the stored secret.
    /// - A non-blank secret replaces the stored secret.
    @discardableResult
    public static func saveOAuthClientOverride(
        id: String,
        secret: String?,
        in store: SecretStore
    ) throws -> OAuthClientOverrideResult {
        var outcome: OAuthClientOverrideResult?
        try store.update { secrets in
            outcome = applyOAuthClientOverride(id: id, secret: secret, to: &secrets)
        }
        return outcome!
    }

    /// Pure in-memory rule for updating `Secrets`'s Google OAuth client override.
    @discardableResult
    public static func applyOAuthClientOverride(
        id: String,
        secret: String?,
        to secrets: inout Secrets
    ) -> OAuthClientOverrideResult {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = (secret ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedId.isEmpty else {
            secrets.oauthClientIdOverride = nil
            secrets.oauthClientSecretOverride = nil
            return OAuthClientOverrideResult(
                clientId: nil,
                hasClientSecret: false,
                cleared: true,
                keptExistingSecret: false
            )
        }

        let unchangedId = (secrets.oauthClientIdOverride == trimmedId)
        secrets.oauthClientIdOverride = trimmedId

        let keptExistingSecret: Bool
        if !trimmedSecret.isEmpty {
            secrets.oauthClientSecretOverride = trimmedSecret
            keptExistingSecret = false
        } else if unchangedId {
            keptExistingSecret = !(secrets.oauthClientSecretOverride ?? "").isEmpty
        } else {
            secrets.oauthClientSecretOverride = nil
            keptExistingSecret = false
        }

        return OAuthClientOverrideResult(
            clientId: secrets.oauthClientIdOverride,
            hasClientSecret: !(secrets.oauthClientSecretOverride ?? "").isEmpty,
            cleared: false,
            keptExistingSecret: keptExistingSecret
        )
    }

    // MARK: - 4. Clear a Chat Token

    /// Clears a chat service token in `store` under its lock. Clearing the
    /// Courier token also switches `courierEnabled` off in `configFile` (under
    /// `SpeakerConfigFile`'s lock) when Courier was enabled.
    @discardableResult
    public static func clearChatToken(
        _ token: ChatToken,
        in store: SecretStore,
        configFile: SpeakerConfigFile? = nil
    ) throws -> ClearChatTokenResult {
        try store.update { secrets in
            applyClearChatToken(token, to: &secrets)
        }

        var courierSwitchedOff = false
        if token == .courier, let configFile,
           case .loaded(let existing) = configFile.read(),
           existing.effectiveChatMonitor.courierEnabled {
            try configFile.modify { config in
                _ = applyClearChatToken(token, to: &config)
            }
            courierSwitchedOff = true
        }

        return ClearChatTokenResult(token: token, courierSwitchedOff: courierSwitchedOff)
    }

    /// Pure in-memory helper clearing `token` in `Secrets`.
    public static func applyClearChatToken(_ token: ChatToken, to secrets: inout Secrets) {
        switch token {
        case .slack:
            secrets.slackToken = nil
        case .beeper:
            secrets.beeperToken = nil
        case .courier:
            secrets.courierToken = nil
        }
    }

    /// Pure in-memory helper updating `SpeakerConfig` when `token` is cleared
    /// (switches `courierEnabled` off when `token == .courier` and Courier was enabled).
    @discardableResult
    public static func applyClearChatToken(_ token: ChatToken, to config: inout SpeakerConfig) -> Bool {
        guard token == .courier, config.effectiveChatMonitor.courierEnabled else { return false }
        config.effectiveChatMonitor.courierEnabled = false
        return true
    }

    // MARK: - 5. Switch to the App or the Extension (Unified Path)

    /// Injectable seam for every external effect in the app/extension switch
    /// flow (`speaker_door.json`, profile copy, coding-agent hook re-pointing,
    /// quitting/opening the other program, login item, Trash, and Vitruvian).
    public protocol DoorSwitchSeam {
        /// Which side is driving this switch (`app` or `extension`).
        var me: HomeSpeakerProfile.Door { get }
        /// Attribution written to `chosen_by` in `speaker_door.json`.
        var chosenBy: String { get }
        /// Current timestamp for `chosen_at`.
        func now() -> Date
        /// True when the calling program itself sits in a Trash folder.
        func inTrash() -> Bool
        /// Reads `speaker_door.json`.
        func readDoor() -> DoorRecord?
        /// True when the other side is installed and usable.
        func otherInstalled(record: DoorRecord?) -> Bool
        /// Resolves the profile for `side`, or nil when unavailable.
        func profile(for side: HomeSpeakerProfile.Door, record: DoorRecord?) -> HomeSpeakerProfile?
        /// Resolves the executable path for `side` when `repointHooks` or
        /// presence validation should run for it.
        func program(for side: HomeSpeakerProfile.Door, record: DoorRecord?) -> String?
        /// Copies settings, secrets, and history from `source` to `destination`.
        func copy(from source: HomeSpeakerProfile, to destination: HomeSpeakerProfile) throws -> CopyReport
        /// Tells `destination` that its sign-ins changed.
        func credentialsChanged(in destination: HomeSpeakerProfile)
        /// Writes `chosen`, `chosenAt`, and `chosenBy` to `speaker_door.json` under its lock.
        func writeChoice(_ side: HomeSpeakerProfile.Door, at date: Date, chosenBy: String) throws
        /// Re-points stale coding-agent hooks to `program`, returning any failure sentences.
        func repointHooks(to side: HomeSpeakerProfile.Door, program: String) -> [String]
        /// Refreshes the caller's own active/quiet role after a choice change.
        func refreshRole()
        /// When the extension chooses itself, asks the running app to quit.
        func quitOther() -> Bool
        /// True when the other program is currently running.
        func isOtherRunning() -> Bool
        /// When the extension chooses the app and the app is not running,
        /// opens the app and turns its Open at Login back on, returning any
        /// report sentences (`DoorWords.couldNotOpen`, `DoorWords.loginItemOn`, or problem).
        func openOtherAndEnableLoginItem() -> [String]
        /// Turns off the app's Open at Login (step 3 offer).
        func turnOffLoginItem() throws
        /// Moves `HomeSpeaker.app` to the Trash (step 3 offer).
        func moveToTrash() throws
        /// Quits the calling app after step 3 offers succeed.
        func quitSelf()
        /// Opens Vitruvian (`false` if it could not be opened).
        func openVitruvian() -> Bool
    }

    /// Outcome of `finishSwitch(compare:copy:seam:)`.
    public enum SwitchOutcome: Equatable {
        /// Concurrent choice detected in `speaker_door.json`; nothing written.
        case choiceChanged(report: [String])
        /// Caller is in the Trash; nothing written.
        case abortedInTrash
        /// Stopped on step 2 (`compare`) due to missing target, copy error, or partial copy.
        case stayOnCompare(DoorCompare, report: [String])
        /// Completed a `.copyOnly` request without changing `speaker_door.json`.
        case copiedOnly(report: [String])
        /// Chose `.app`.
        case appChosen(report: [String])
        /// Chose `.extension` (offers to turn off login item and move app to Trash).
        case extensionChosen(AppSwitch.Offers, report: [String])
    }

    /// Outcome of `applySwitchOffers(_:seam:)`.
    public struct SwitchOffersResult: Sendable, Equatable {
        public let report: [String]
        public let failed: Bool

        public init(report: [String], failed: Bool) {
            self.report = report
            self.failed = failed
        }
    }

    /// Step 2 of switching or copying: builds a `DoorCompare` snapshot when
    /// the caller is not in the Trash and the other side is installed.
    public static func beginSwitch(
        from: HomeSpeakerProfile.Door,
        into: HomeSpeakerProfile.Door,
        purpose: DoorCompare.Purpose,
        seam: any DoorSwitchSeam
    ) throws -> DoorCompare? {
        guard !seam.inTrash() else { return nil }
        let record = seam.readDoor()
        guard seam.otherInstalled(record: record) else { return nil }
        if purpose == .choose, into != seam.me, seam.program(for: into, record: record) == nil {
            throw SwitchRefused(
                into == .app ? DoorWords.appNotFound : DoorWords.extensionNotFound
            )
        }
        guard let source = seam.profile(for: from, record: record),
              let destination = seam.profile(for: into, record: record) else {
            return nil
        }
        return DoorCompare(
            purpose: purpose,
            from: from,
            into: into,
            source: DoorSnapshot(profile: source),
            destination: DoorSnapshot(profile: destination),
            seenChoice: record?.chosen,
            seenChosenAt: record?.chosenAt
        )
    }

    /// Error thrown when `beginSwitch` refuses because the target program is missing.
    public struct SwitchRefused: Error, LocalizedError, Sendable, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    /// Unified step 2 completion (`Copy` or `Keep`) combining the app's and the
    /// extension's switch sequences:
    /// 1. Check `speaker_door.json` has not changed since step 2 started; if it
    ///    changed, refresh role and abort with `DoorWords.choiceChanged`.
    /// 2. Refuse if the caller is in the Trash.
    /// 3. Verify the other side is installed and its program/profile can be
    ///    found (`extensionNotFound` / `appNotFound`).
    /// 4. When `copy == true`, copy settings, secrets, and history (`seam.copy`),
    ///    notifying `seam.credentialsChanged(in: destination)` (including on
    ///    `DoorCopyPartial` when `signInsWritten` is true).
    /// 5. If `compare.purpose == .copyOnly`, stop here without touching
    ///    `speaker_door.json`, hooks, or running processes.
    /// 6. Write `chosen`, `chosenAt`, and `chosenBy` under `DoorFile`'s lock.
    /// 7. Re-point stale coding-agent hooks (`AgentIntegration`) to the chosen
    ///    side's executable when known.
    /// 8. Apply process lifecycle steps:
    ///    - Choosing `.extension`: when run from the extension, ask the app to
    ///      quit (`seam.quitOther()`); refresh local role; return `.extensionChosen`.
    ///    - Choosing `.app`: when run from the extension and the app is not
    ///      running, open the app and turn its login item on
    ///      (`seam.openOtherAndEnableLoginItem()`); refresh local role; return `.appChosen`.
    public static func finishSwitch(
        compare initialCompare: DoorCompare,
        copy: Bool,
        seam: any DoorSwitchSeam
    ) -> SwitchOutcome {
        var compare = initialCompare

        // 1. Never override a choice made elsewhere since step 2 began.
        let record = seam.readDoor()
        if record?.chosen != compare.seenChoice || record?.chosenAt != compare.seenChosenAt {
            seam.refreshRole()
            return .choiceChanged(report: [DoorWords.choiceChanged])
        }

        // 2. A program in the Trash writes nothing.
        guard !seam.inTrash() else {
            return .abortedInTrash
        }

        // 3. Verify the other side is present and profiles/programs resolve.
        let otherSide: HomeSpeakerProfile.Door = seam.me == .app ? .extension : .app
        let notFoundWord = otherSide == .extension ? DoorWords.extensionNotFound : DoorWords.appNotFound
        guard seam.otherInstalled(record: record),
              let source = seam.profile(for: compare.from, record: record),
              let destination = seam.profile(for: compare.into, record: record) else {
            compare.problem = notFoundWord
            return .stayOnCompare(compare, report: [])
        }
        if compare.purpose == .choose, compare.into != seam.me,
           seam.program(for: compare.into, record: record) == nil {
            compare.problem = compare.into == .app ? DoorWords.appNotFound : DoorWords.extensionNotFound
            return .stayOnCompare(compare, report: [])
        }

        // 4. Copy settings, sign-ins, and history when requested.
        var report: [String] = []
        compare.problem = nil
        if copy {
            do {
                report = try seam.copy(from: source, to: destination).lines
            } catch let partial as DoorCopyPartial {
                if partial.signInsWritten {
                    seam.credentialsChanged(in: destination)
                }
                return .stayOnCompare(compare, report: partial.copied + partial.notCopied)
            } catch {
                compare.problem = error.localizedDescription
                return .stayOnCompare(compare, report: [])
            }
            seam.credentialsChanged(in: destination)
        }

        // 5. Copy-only stops before touching the choice file or hooks.
        guard compare.purpose == .choose else {
            return .copiedOnly(report: report)
        }

        // 6. Write the choice under `DoorFile`'s lock.
        do {
            try seam.writeChoice(compare.into, at: seam.now(), chosenBy: seam.chosenBy)
        } catch {
            compare.problem = error.localizedDescription
            return .stayOnCompare(compare, report: report)
        }

        // 7. Re-point stale coding-agent hooks to the chosen side's program.
        if let targetProgram = seam.program(for: compare.into, record: record) {
            report += seam.repointHooks(to: compare.into, program: targetProgram)
        }

        // 8. Process lifecycle & role refresh.
        if compare.into == .extension {
            if seam.me == .extension {
                _ = seam.quitOther()
            }
            seam.refreshRole()
            return .extensionChosen(AppSwitch.Offers(), report: report)
        } else {
            if seam.me == .extension, !seam.isOtherRunning() {
                report += seam.openOtherAndEnableLoginItem()
            }
            seam.refreshRole()
            return .appChosen(report: report)
        }
    }

    /// Executes the post-switch step 3 offers (turning off the app's Open at
    /// Login first, then moving `HomeSpeaker.app` to the Trash, and when run
    /// from the app with no failures, quitting the app).
    public static func applySwitchOffers(
        _ offers: AppSwitch.Offers,
        seam: any DoorSwitchSeam
    ) -> SwitchOffersResult {
        var lines: [String] = []
        var failed = false
        if offers.loginItem {
            do {
                try seam.turnOffLoginItem()
                lines.append(DoorWords.loginItemOff)
            } catch {
                failed = true
                lines.append(error.localizedDescription)
            }
        }
        if offers.trash {
            do {
                try seam.moveToTrash()
                lines.append(DoorWords.inTheTrash)
            } catch {
                failed = true
                lines.append(error.localizedDescription)
            }
        }
        if !failed, seam.me == .app {
            seam.quitSelf()
        }
        return SwitchOffersResult(report: lines, failed: failed)
    }

    /// Re-points every coding agent's stale HomeSpeaker hook in `home` to
    /// `program`. Agents without an existing HomeSpeaker hook are untouched.
    public static func repointStaleHooks(
        home: URL,
        to program: String,
        bootout: @escaping @Sendable (String) -> Void = { _ in }
    ) -> [String] {
        let integration = AgentIntegration(home: home, executablePath: program, bootout: bootout)
        var problems: [String] = []
        for agent in CodingAgent.allCases where agent.supportsHook {
            guard case .stale = integration.status(of: agent).hook else { continue }
            do {
                try integration.installHook(for: agent)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        return problems
    }

    // MARK: - 6. Reset Settings

    /// Resets settings in `file` under its lock to the engine's defaults while
    /// preserving the discovered home (`structureId`, `structureName`),
    /// speakers (`targets`, `defaultTarget`), `customVoices`, and any foreign
    /// JSON keys on disk.
    @discardableResult
    public static func resetSettings(in file: SpeakerConfigFile) throws -> SpeakerConfig {
        var resetConfig = SpeakerConfig()
        try file.modify { config in
            resetConfig = resetSettings(preservingDiscoveryFrom: config)
            config = resetConfig
        }
        return resetConfig
    }

    /// Pure in-memory reset: returns a fresh default `SpeakerConfig` keeping
    /// the discovered home, known homes, speakers, and custom voices from `existing`.
    public static func resetSettings(preservingDiscoveryFrom existing: SpeakerConfig) -> SpeakerConfig {
        var fresh = SpeakerConfig(
            defaultTarget: existing.defaultTarget,
            structureId: existing.structureId,
            structureName: existing.structureName,
            targets: existing.targets
        )
        fresh.homes = existing.homes
        fresh.customVoices = existing.customVoices
        return fresh
    }

    // MARK: - 7. Set Secret, Snooze, Chat Networks, Antigravity Import & Agent Hooks

    /// Secret keys accepted by `SettingsActions.setSecret` and `--apply`'s
    /// `"setSecret"` operation.
    public enum SecretName: String, CaseIterable, Sendable, Equatable {
        case slack
        case beeper
        case courier
        case geminiKey
    }

    /// Outcome of setting or clearing a secret via `SettingsActions.setSecret`.
    public struct SetSecretResult: Equatable, Sendable {
        public let name: SecretName
        public let cleared: Bool
        public let courierSwitchedOff: Bool

        public init(name: SecretName, cleared: Bool, courierSwitchedOff: Bool) {
            self.name = name
            self.cleared = cleared
            self.courierSwitchedOff = courierSwitchedOff
        }
    }

    /// Pure in-memory secret update: trims `value`, stores it on `secrets`
    /// when non-empty, or clears it when empty.
    public static func applySetSecret(_ name: SecretName, value: String, to secrets: inout Secrets) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: String? = trimmed.isEmpty ? nil : trimmed
        switch name {
        case .slack:
            secrets.slackToken = stored
        case .beeper:
            secrets.beeperToken = stored
        case .courier:
            secrets.courierToken = stored
        case .geminiKey:
            secrets.geminiApiKey = stored
        }
    }

    /// Pure in-memory secret + config update: updates `secrets` and, when
    /// clearing `.courier`, switches `courier_enabled` off on `config` (reusing
    /// `applyClearChatToken`).
    @discardableResult
    public static func applySetSecret(
        _ name: SecretName,
        value: String,
        to secrets: inout Secrets,
        config: inout SpeakerConfig
    ) -> SetSecretResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleared = trimmed.isEmpty
        applySetSecret(name, value: value, to: &secrets)
        let courierSwitchedOff: Bool
        if cleared, name == .courier {
            courierSwitchedOff = applyClearChatToken(.courier, to: &config)
        } else {
            courierSwitchedOff = false
        }
        return SetSecretResult(name: name, cleared: cleared, courierSwitchedOff: courierSwitchedOff)
    }

    /// Saves or clears `name` in `store` under its lock, and when clearing
    /// `.courier`, switches `courier_enabled` off in `configFile`.
    @discardableResult
    public static func setSecret(
        _ name: SecretName,
        value: String,
        in store: SecretStore,
        configFile: SpeakerConfigFile? = nil
    ) throws -> SetSecretResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleared = trimmed.isEmpty
        try store.update { secrets in
            applySetSecret(name, value: value, to: &secrets)
        }

        var courierSwitchedOff = false
        if cleared, name == .courier, let configFile,
           case .loaded(let existing) = configFile.read(),
           existing.effectiveChatMonitor.courierEnabled {
            try configFile.modify { config in
                _ = applyClearChatToken(.courier, to: &config)
            }
            courierSwitchedOff = true
        }
        return SetSecretResult(name: name, cleared: cleared, courierSwitchedOff: courierSwitchedOff)
    }

    /// Allowed snooze duration range in minutes (1–240).
    public static let minSnoozeMinutes = 1
    public static let maxSnoozeMinutes = 240

    /// Pure in-memory snooze update: sets `config.snoozeUntil` to
    /// `now + minutes * 60` when `minutes` is in `1...240` (throwing
    /// `Refusal.outOfRange` outside that range), or clears `snoozeUntil` when
    /// `minutes` is `nil`.
    @discardableResult
    public static func applySnooze(
        minutes: Int?,
        now: Date = Date(),
        to config: inout SpeakerConfig
    ) throws -> Date? {
        guard let minutes else {
            config.snoozeUntil = nil
            return nil
        }
        guard (minSnoozeMinutes...maxSnoozeMinutes).contains(minutes) else {
            throw Refusal.outOfRange(
                key: "snooze",
                value: minutes,
                min: minSnoozeMinutes,
                max: maxSnoozeMinutes
            )
        }
        let until = now.addingTimeInterval(TimeInterval(minutes * 60))
        config.snoozeUntil = until
        return until
    }

    /// Writes `snoozeUntil` in `configFile` under its lock.
    @discardableResult
    public static func snooze(
        minutes: Int?,
        now: Date = Date(),
        in configFile: SpeakerConfigFile
    ) throws -> Date? {
        if let minutes, !(minSnoozeMinutes...maxSnoozeMinutes).contains(minutes) {
            throw Refusal.outOfRange(
                key: "snooze",
                value: minutes,
                min: minSnoozeMinutes,
                max: maxSnoozeMinutes
            )
        }
        var outcome: Date?
        try configFile.modify { config in
            outcome = try? applySnooze(minutes: minutes, now: now, to: &config)
        }
        return outcome
    }

    /// Pure in-memory chat network mute/unmute update using
    /// `ChatMonitorConfig.setNetwork(_:of:reading:)`.
    public static func applySetNetwork(
        app: ChatApp,
        key: String,
        reading: Bool,
        to config: inout SpeakerConfig
    ) {
        config.effectiveChatMonitor.setNetwork(key, of: app, reading: reading)
    }

    /// Updates `app`'s muted-networks list in `configFile` under its lock.
    public static func setNetwork(
        app: ChatApp,
        key: String,
        reading: Bool,
        in configFile: SpeakerConfigFile
    ) throws {
        try configFile.modify { config in
            applySetNetwork(app: app, key: key, reading: reading, to: &config)
        }
    }

    /// Pure in-memory `chat_monitor.courier_read_anyway` update using
    /// `ChatMonitorConfig.setReadAnyway(_:_:)`.
    public static func applySetReadAnyway(
        key: String,
        on isOn: Bool,
        to config: inout SpeakerConfig
    ) {
        config.effectiveChatMonitor.setReadAnyway(key, isOn)
    }

    /// Updates `chat_monitor.courier_read_anyway` in `configFile` under its lock.
    public static func setReadAnyway(
        key: String,
        on isOn: Bool,
        in configFile: SpeakerConfigFile
    ) throws {
        try configFile.modify { config in
            applySetReadAnyway(key: key, on: isOn, to: &config)
        }
    }

    /// Reads and parses Google Home credentials from an Antigravity token file,
    /// returning `nil` when missing or unusable.
    public static func readAntigravityTokens(
        at url: URL = SecretStore.antigravityTokensURL
    ) -> GoogleCredentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SecretStore.parseAntigravityTokens(data)
    }

    /// Pure in-memory update storing imported Antigravity credentials on `secrets`.
    public static func applyImportAntigravity(
        _ credentials: GoogleCredentials,
        to secrets: inout Secrets
    ) {
        secrets.google = credentials
    }

    /// Imports Google Home credentials from `url` into `store` via
    /// `SecretStore.importFromAntigravity(at:)`.
    @discardableResult
    public static func importAntigravity(
        from url: URL = SecretStore.antigravityTokensURL,
        in store: SecretStore
    ) throws -> Bool {
        try store.importFromAntigravity(at: url)
    }

    /// Coding-agent hook actions shared by Settings and `--apply`'s `"agentHook"`.
    public enum AgentHookAction: String, CaseIterable, Sendable, Equatable {
        case install
        case remove
        case addInstruction
        /// Renames a rival hook file so a reply is not spoken twice.
        case disableRival
    }

    /// Resolves the wire agent name (`"claude_code"`, `"antigravity"`,
    /// `"opencode"`) to `CodingAgent`.
    public static func codingAgent(for wireName: String) -> CodingAgent? {
        switch wireName {
        case "claude_code":
            return .claudeCode
        case "antigravity":
            return .antigravity
        case "opencode":
            return .opencode
        default:
            return nil
        }
    }

    /// Canonical wire name for `agent` in `--state` and `--apply`.
    public static func wireName(for agent: CodingAgent) -> String {
        switch agent {
        case .claudeCode:
            return "claude_code"
        case .antigravity:
            return "antigravity"
        case .opencode:
            return "opencode"
        }
    }

    /// Runs `action` (`install`, `remove`, `addInstruction`, or `disableRival`) for `agent`
    /// through `AgentIntegration(home: home, executablePath: executablePath)`.
    public static func performAgentHook(
        agent: CodingAgent,
        action: AgentHookAction,
        home: URL,
        executablePath: String
    ) throws {
        let integration = AgentIntegration(
            home: home,
            executablePath: executablePath,
            bootout: { _ in }
        )
        switch action {
        case .install:
            try integration.installHook(for: agent)
        case .remove:
            try integration.removeHook(for: agent)
        case .addInstruction:
            try integration.addBroadcastInstruction(for: agent)
        case .disableRival:
            try integration.disableRivalHook(for: agent)
        }
    }
}
