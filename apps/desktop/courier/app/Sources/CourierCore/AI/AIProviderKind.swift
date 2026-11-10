// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public typealias AIEngineChoice = AIProviderKind

public enum AIProviderKind: String, CaseIterable, Codable, Sendable {
    case appleIntelligence
    case ollama
    case lmStudio
    case unslothStudio
    case anthropic
    case googleAIStudio
    case openAI
    case customOpenAICompatible

    public static let localProviders: [AIProviderKind] = [
        .appleIntelligence,
        .ollama,
        .lmStudio,
        .unslothStudio,
    ]

    public static let cloudProviders: [AIProviderKind] = [
        .anthropic,
        .googleAIStudio,
        .openAI,
        .customOpenAICompatible,
    ]

    public var label: String {
        switch self {
        case .appleIntelligence:
            String(localized: "Apple Intelligence")
        case .ollama:
            String(localized: "Ollama")
        case .lmStudio:
            String(localized: "LM Studio")
        case .unslothStudio:
            String(localized: "Unsloth Studio")
        case .anthropic:
            String(localized: "Anthropic")
        case .googleAIStudio:
            String(localized: "Google AI Studio")
        case .openAI:
            String(localized: "OpenAI")
        case .customOpenAICompatible:
            String(localized: "OpenAI-Compatible")
        }
    }

    public var isLocal: Bool {
        switch self {
        case .appleIntelligence, .ollama, .lmStudio, .unslothStudio:
            true
        case .anthropic, .googleAIStudio, .openAI, .customOpenAICompatible:
            false
        }
    }

    /// Cloud providers and Unsloth Studio require an API key (`true`);
    /// Custom OpenAI-compatible accepts an optional key (`false`);
    /// Ollama, LM Studio, and Apple Intelligence do not use an API key (`false`).
    public var needsKey: Bool {
        switch self {
        case .anthropic, .googleAIStudio, .openAI, .unslothStudio:
            true
        case .appleIntelligence, .ollama, .lmStudio, .customOpenAICompatible:
            false
        }
    }

    /// Whether the provider accepts an API key (required for cloud providers and Unsloth Studio, optional for Custom OpenAI-compatible).
    public var acceptsKey: Bool {
        switch self {
        case .anthropic, .googleAIStudio, .openAI, .unslothStudio, .customOpenAICompatible:
            true
        case .appleIntelligence, .ollama, .lmStudio:
            false
        }
    }

    /// Application bundle name under `/Applications` for local server providers.
    public var localAppBundleName: String? {
        switch self {
        case .ollama:
            "Ollama.app"
        case .lmStudio:
            "LM Studio.app"
        case .unslothStudio:
            "Unsloth.app"
        default:
            nil
        }
    }

    public func provenanceFooter(model: String) -> String {
        if isLocal {
            return String(localized: "via \(model) · on this Mac")
        }
        return String(localized: "via \(model) · sent to \(label)")
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .appleIntelligence:
            nil
        case .ollama:
            URL(string: "http://127.0.0.1:11434/v1")
        case .lmStudio:
            URL(string: "http://127.0.0.1:1234/v1")
        case .unslothStudio:
            URL(string: "http://127.0.0.1:8888/v1")
        case .anthropic:
            URL(string: "https://api.anthropic.com")
        case .googleAIStudio:
            URL(string: "https://generativelanguage.googleapis.com")
        case .openAI:
            URL(string: "https://api.openai.com/v1")
        case .customOpenAICompatible:
            nil
        }
    }

    public var privacyNotice: String {
        if isLocal {
            return String(localized: "Stays on this Mac.")
        }
        return String(localized: "Messages you use with AI are sent to \(label).")
    }
}
