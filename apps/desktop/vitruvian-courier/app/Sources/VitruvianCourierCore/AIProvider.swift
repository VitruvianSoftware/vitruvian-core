// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

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

/// Spec §3 seam for chat AI features (Settings ▸ AI, AIPane, Draft with AI, Rewrite, Translate, Summarize).
/// Speech features (`TalkToTypeModel`, `VoiceNoteTranscriptStore`) use `SpeechEngine` directly rather than `AIProvider`.
/// `UnavailableAIProvider` is completely offline and never contacts any server.
public protocol AIProvider: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    var availableModels: [String] { get }
    func draftResponse(context: AIChatContext, draft: String, tone: AIRewriteTone?) async -> AIProviderDisposition
    func translate(text: String, targetLanguage: String) async -> AIProviderDisposition
    func summarize(context: AIChatContext) async -> AIProviderDisposition
}

public struct UnavailableAIProvider: AIProvider {
    private let customReason: String?

    public init(reason: String? = nil) {
        self.customReason = reason
    }

    public var hasCustomReason: Bool { customReason != nil }

    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        customReason ?? String(localized: "AI features aren’t available yet in Vitruvian Courier. Everything you write stays on this Mac.")
    }
    public var availableModels: [String] {
        []
    }
    public func draftResponse(context _: AIChatContext, draft _: String, tone _: AIRewriteTone?) async -> AIProviderDisposition {
        .unavailable(reason: customReason ?? String(localized: "Drafting with AI isn’t available yet in Vitruvian Courier."))
    }
    public func translate(text _: String, targetLanguage _: String) async -> AIProviderDisposition {
        .unavailable(reason: customReason ?? String(localized: "Message translation isn’t available yet in Vitruvian Courier."))
    }
    public func summarize(context _: AIChatContext) async -> AIProviderDisposition {
        .unavailable(reason: customReason ?? String(localized: "AI chat summaries aren’t available yet in Vitruvian Courier."))
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
    @Published public var customBaseURL: String {
        didSet {
            guard canMutate({ customBaseURL = oldValue }) else { return }
            set(customBaseURL, "customBaseURL")
        }
    }
    @Published public var selectedModelByProvider: [String: String] {
        didSet {
            guard canMutate({ selectedModelByProvider = oldValue }) else { return }
            set(selectedModelByProvider, "selectedModelByProvider")
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

    let didChange = PassthroughSubject<Void, Never>()

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
        let storedModel = defaults.string(forKey: Self.key("selectedModel")) ?? ""
        selectedModel = storedModel == "On-Device (Not available yet)" ? "" : storedModel
        customBaseURL = defaults.string(forKey: Self.key("customBaseURL")) ?? ""
        selectedModelByProvider = (defaults.dictionary(forKey: Self.key("selectedModelByProvider")) as? [String: String]) ?? [:]
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

    public func model(for provider: AIProviderKind) -> String? {
        let stored = selectedModelByProvider[provider.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false) ? stored : nil
    }

    public func setModel(_ model: String, for provider: AIProviderKind) {
        var updated = selectedModelByProvider
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            updated.removeValue(forKey: provider.rawValue)
        } else {
            updated[provider.rawValue] = trimmed
        }
        selectedModelByProvider = updated
        if selectedEngine == provider, !trimmed.isEmpty, selectedModel != trimmed {
            selectedModel = trimmed
        }
    }

    public static let lastTranslationLanguageHelp = String(localized: "At least one language stays on")

    /// True when `language` is the only remaining enabled translation language and its checkbox must be disabled.
    public func isLastEnabledTranslationLanguage(_ language: String) -> Bool {
        translationLanguages.count <= 1 && translationLanguages.contains(language)
    }

    /// Toggles `language` in `translationLanguages`, refusing to turn off the last remaining enabled language.
    @discardableResult
    public func setTranslationLanguage(_ language: String, enabled: Bool) -> Bool {
        if enabled {
            if !translationLanguages.contains(language) {
                var next = translationLanguages
                next.append(language)
                next.sort()
                translationLanguages = next
            }
            return true
        } else {
            guard !isLastEnabledTranslationLanguage(language) else {
                return false
            }
            var next = translationLanguages
            next.removeAll { $0 == language }
            translationLanguages = next
            return true
        }
    }

    private func set(_ value: Any, _ name: String) {
        defaults.set(value, forKey: Self.key(name))
        didChange.send()
    }
}

extension AIProvider {
    @MainActor
    public func provenanceFooter(preferences: AIPreferences) -> String {
        if let configured = self as? ConfiguredAIProvider {
            return configured.kind.provenanceFooter(model: configured.model)
        }
        let kind = preferences.selectedEngine
        let model = preferences.model(for: kind) ?? preferences.selectedModel
        return kind.provenanceFooter(model: model)
    }
}
