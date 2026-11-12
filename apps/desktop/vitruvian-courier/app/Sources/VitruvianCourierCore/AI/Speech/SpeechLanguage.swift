// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Maps Vitruvian Courier's transcription language choices (`"Auto-Detect"` or a named language from
/// `AIPreferences.supportedTranslationLanguages`) to an Apple `Locale` or an OpenAI Whisper ISO-639-1 code.
public enum SpeechLanguage {
    public static let autoDetect = "Auto-Detect"

    private struct Mapping {
        let appleIdentifier: String
        let whisperISO639_1: String
    }

    private static let namedMappings: [String: Mapping] = [
        "Arabic": Mapping(appleIdentifier: "ar-SA", whisperISO639_1: "ar"),
        "Chinese (Simplified)": Mapping(appleIdentifier: "zh-CN", whisperISO639_1: "zh"),
        "Chinese (Traditional)": Mapping(appleIdentifier: "zh-TW", whisperISO639_1: "zh"),
        "Dutch": Mapping(appleIdentifier: "nl-NL", whisperISO639_1: "nl"),
        "English": Mapping(appleIdentifier: "en-US", whisperISO639_1: "en"),
        "French": Mapping(appleIdentifier: "fr-FR", whisperISO639_1: "fr"),
        "German": Mapping(appleIdentifier: "de-DE", whisperISO639_1: "de"),
        "Hindi": Mapping(appleIdentifier: "hi-IN", whisperISO639_1: "hi"),
        "Italian": Mapping(appleIdentifier: "it-IT", whisperISO639_1: "it"),
        "Japanese": Mapping(appleIdentifier: "ja-JP", whisperISO639_1: "ja"),
        "Korean": Mapping(appleIdentifier: "ko-KR", whisperISO639_1: "ko"),
        "Polish": Mapping(appleIdentifier: "pl-PL", whisperISO639_1: "pl"),
        "Portuguese": Mapping(appleIdentifier: "pt-BR", whisperISO639_1: "pt"),
        "Russian": Mapping(appleIdentifier: "ru-RU", whisperISO639_1: "ru"),
        "Spanish": Mapping(appleIdentifier: "es-ES", whisperISO639_1: "es"),
        "Turkish": Mapping(appleIdentifier: "tr-TR", whisperISO639_1: "tr"),
        "Vietnamese": Mapping(appleIdentifier: "vi-VN", whisperISO639_1: "vi"),
    ]

    /// True when `language` means automatic/current-Mac language rather than a pinned language.
    public static func isAutoDetect(_ language: String) -> Bool {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare(autoDetect) == .orderedSame
    }

    /// Resolves the `Locale` Apple on-device speech recognition should use.
    /// `"Auto-Detect"` resolves to `currentLocale` (`Locale.current` on this Mac).
    public static func appleLocale(for language: String, currentLocale: Locale = .current) -> Locale {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isAutoDetect(trimmed) else {
            return currentLocale
        }
        if let mapped = namedMappings[trimmed] {
            return Locale(identifier: mapped.appleIdentifier)
        }
        if let matched = namedMappings.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame })?.value {
            return Locale(identifier: matched.appleIdentifier)
        }
        return Locale(identifier: trimmed)
    }

    /// Resolves the ISO-639-1 two-letter language code for OpenAI Whisper.
    /// Returns `nil` for `"Auto-Detect"` so Whisper omits the `language` form field.
    public static func whisperCode(for language: String) -> String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isAutoDetect(trimmed) else {
            return nil
        }
        if let mapped = namedMappings[trimmed] {
            return mapped.whisperISO639_1
        }
        if let matched = namedMappings.first(where: { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame })?.value {
            return matched.whisperISO639_1
        }
        let locale = Locale(identifier: trimmed)
        if let code = locale.language.languageCode?.identifier.lowercased(),
           code.count == 2,
           code.allSatisfy(\.isLetter)
        {
            return code
        }
        return nil
    }

    /// Human-readable language label for status and error messages (`"Not available for <language>"`).
    public static func displayName(for language: String, currentLocale: Locale = .current) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAutoDetect(trimmed) else {
            return trimmed
        }
        if let code = currentLocale.language.languageCode?.identifier,
           let localized = Locale.current.localizedString(forLanguageCode: code),
           !localized.isEmpty
        {
            return localized
        }
        if let localized = Locale.current.localizedString(forIdentifier: currentLocale.identifier),
           !localized.isEmpty
        {
            return localized
        }
        return currentLocale.identifier
    }
}
