// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

public enum AIEngineChoice: String, CaseIterable, Codable, Sendable {
    case appleIntelligence
    case openAI
    case customOpenAICompatible

    public var label: String {
        switch self {
        case .appleIntelligence: String(localized: "Apple Intelligence (On-Device)")
        case .openAI: String(localized: "OpenAI")
        case .customOpenAICompatible: String(localized: "Custom OpenAI-Compatible Endpoint")
        }
    }
}

public enum AIRewriteTone: String, CaseIterable, Codable, Sendable {
    case fixGrammar
    case moreConcise
    case moreConfident
    case moreFriendly
    case moreProfessional
    case moreVerbose

    public var label: String {
        switch self {
        case .fixGrammar: String(localized: "Fix grammar and spelling")
        case .moreConcise: String(localized: "Make more concise")
        case .moreConfident: String(localized: "Make more confident")
        case .moreFriendly: String(localized: "Make more friendly")
        case .moreProfessional: String(localized: "Make more professional")
        case .moreVerbose: String(localized: "Make more verbose")
        }
    }
}

public enum AIProviderDisposition: Equatable, Sendable {
    case unavailable(reason: String)
    case text(String)
}

/// Spec §3 seam for AI features (Settings ▸ AI, AIPane, Talk to Type, Draft with AI, Translate, Whisper transcription).
/// Iteration 1's `UnavailableAIProvider` is completely offline and never contacts any server.
public protocol AIProvider: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    var availableModels: [String] { get }
    func draftResponse(roomID: String, prompt: String, tone: AIRewriteTone?) async -> AIProviderDisposition
    func translate(text: String, targetLanguage: String) async -> AIProviderDisposition
    func summarize(roomID: String, eventIDs: [String]) async -> AIProviderDisposition
    func transcribeVoiceNote(roomID: String, eventID: String) async -> AIProviderDisposition
    func startTalkToType() async -> AIProviderDisposition
}

public struct UnavailableAIProvider: AIProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "AI features aren’t available yet in Courier. Everything you write stays on this Mac.")
    }
    public var availableModels: [String] {
        [String(localized: "On-Device (Not available yet)")]
    }
    public func draftResponse(roomID _: String, prompt _: String, tone _: AIRewriteTone?) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Drafting with AI isn’t available yet in Courier."))
    }
    public func translate(text _: String, targetLanguage _: String) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Message translation isn’t available yet in Courier."))
    }
    public func summarize(roomID _: String, eventIDs _: [String]) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "AI chat summaries aren’t available yet in Courier."))
    }
    public func transcribeVoiceNote(roomID _: String, eventID _: String) async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Voice-note transcription isn’t available yet in Courier."))
    }
    public func startTalkToType() async -> AIProviderDisposition {
        .unavailable(reason: String(localized: "Talk to Type isn’t available yet in Courier."))
    }
}

@MainActor
public final class AIPreferences: ObservableObject {
    @Published public var enableContextualAI: Bool {
        didSet {
            guard canMutate({ enableContextualAI = oldValue }) else { return }
            set(enableContextualAI, "enableContextualAI")
        }
    }
    @Published public var selectedEngine: AIEngineChoice {
        didSet {
            guard canMutate({ selectedEngine = oldValue }) else { return }
            set(selectedEngine.rawValue, "selectedEngine")
        }
    }
    @Published public var selectedModel: String {
        didSet {
            guard canMutate({ selectedModel = oldValue }) else { return }
            set(selectedModel, "selectedModel")
        }
    }
    @Published public var responseLanguage: String {
        didSet {
            guard canMutate({ responseLanguage = oldValue }) else { return }
            set(responseLanguage, "responseLanguage")
        }
    }
    @Published public var translationLanguages: [String] {
        didSet {
            guard canMutate({ translationLanguages = oldValue }) else { return }
            set(translationLanguages, "translationLanguages")
        }
    }
    @Published public var mentionAIInChats: Bool {
        didSet {
            guard canMutate({ mentionAIInChats = oldValue }) else { return }
            set(mentionAIInChats, "mentionAIInChats")
        }
    }
    @Published public var aiMentionsSystemPrompt: String {
        didSet {
            guard canMutate({ aiMentionsSystemPrompt = oldValue }) else { return }
            set(aiMentionsSystemPrompt, "aiMentionsSystemPrompt")
        }
    }
    @Published public var useWhisperForTalkToType: Bool {
        didSet {
            guard canMutate({ useWhisperForTalkToType = oldValue }) else { return }
            set(useWhisperForTalkToType, "useWhisperForTalkToType")
        }
    }
    @Published public var autoTranscribeVoiceNotes: Bool {
        didSet {
            guard canMutate({ autoTranscribeVoiceNotes = oldValue }) else { return }
            set(autoTranscribeVoiceNotes, "autoTranscribeVoiceNotes")
        }
    }
    @Published public var transcriptionLanguage: String {
        didSet {
            guard canMutate({ transcriptionLanguage = oldValue }) else { return }
            set(transcriptionLanguage, "transcriptionLanguage")
        }
    }
    @Published public var enableSlashCommands: Bool {
        didSet {
            guard canMutate({ enableSlashCommands = oldValue }) else { return }
            set(enableSlashCommands, "enableSlashCommands")
        }
    }

    public static let supportedTranslationLanguages: [String] = [
        "Arabic", "Chinese (Simplified)", "Chinese (Traditional)", "Dutch",
        "English", "French", "German", "Hindi", "Italian", "Japanese",
        "Korean", "Polish", "Portuguese", "Russian", "Spanish", "Turkish", "Vietnamese",
    ]

    public static func key(_ name: String) -> String { "courier.ai." + name }

    private let defaults: UserDefaults
    private var isInitializing = true
    private var isRevertingLockedSetting = false

    private func canMutate(_ revert: () -> Void) -> Bool {
        guard !isInitializing, !isRevertingLockedSetting else { return false }
        guard AppLockGate.isCurrentActionAllowedForSettings else {
            isRevertingLockedSetting = true
            revert()
            isRevertingLockedSetting = false
            return false
        }
        return true
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: Self.key(name)) as? Bool ?? fallback
        }
        func string(_ name: String, _ fallback: String) -> String {
            let stored = defaults.string(forKey: Self.key(name))
            return (stored?.isEmpty == false) ? stored! : fallback
        }

        enableContextualAI = bool("enableContextualAI", false)
        selectedEngine = defaults.string(forKey: Self.key("selectedEngine"))
            .flatMap(AIEngineChoice.init(rawValue:)) ?? .appleIntelligence
        selectedModel = string("selectedModel", String(localized: "On-Device (Not available yet)"))
        responseLanguage = string("responseLanguage", "English")
        if let storedLanguages = defaults.stringArray(forKey: Self.key("translationLanguages")), !storedLanguages.isEmpty {
            translationLanguages = storedLanguages
        } else {
            translationLanguages = ["English"]
        }
        mentionAIInChats = bool("mentionAIInChats", false)
        aiMentionsSystemPrompt = defaults.string(forKey: Self.key("aiMentionsSystemPrompt")) ?? ""
        useWhisperForTalkToType = bool("useWhisperForTalkToType", false)
        autoTranscribeVoiceNotes = bool("autoTranscribeVoiceNotes", false)
        transcriptionLanguage = string("transcriptionLanguage", "Auto-Detect")
        enableSlashCommands = bool("enableSlashCommands", true)
        isInitializing = false
    }

    private func set(_ value: Any, _ name: String) {
        defaults.set(value, forKey: Self.key(name))
    }
}
