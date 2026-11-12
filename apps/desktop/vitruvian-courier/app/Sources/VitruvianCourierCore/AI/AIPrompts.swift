// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum AIPrompts {
    public static let maxDraftMessages = 30
    public static let maxSummarizeMessages = 100

    public static func systemPrompt(
        base: String = "You are a helpful chat assistant in Courier.",
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) -> String {
        var parts: [String] = [base]
        let trimmedLanguage = responseLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLanguage.isEmpty {
            parts.append("Preferred response language: \(trimmedLanguage).")
        }
        let trimmedInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstructions.isEmpty {
            parts.append("Custom instructions: \(trimmedInstructions)")
        }
        return parts.joined(separator: "\n")
    }

    public static func instruction(for tone: AIRewriteTone) -> String {
        switch tone {
        case .fixGrammar:
            "Fix grammar and spelling."
        case .moreConcise:
            "Make it more concise."
        case .moreConfident:
            "Make it more confident."
        case .moreFriendly:
            "Make it more friendly."
        case .moreProfessional:
            "Make it more professional."
        case .moreVerbose:
            "Make it more verbose."
        }
    }

    public static func formatTranscript(
        from context: AIChatContext,
        limit: Int
    ) -> [String] {
        let nonEmpty = context.messages.compactMap { entry -> String? in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let speaker: String
            if entry.mine {
                speaker = "Me"
            } else {
                let trimmedName = entry.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
                speaker = trimmedName.isEmpty ? "Them" : trimmedName
            }
            return "\(speaker): \(text)"
        }
        return Array(nonEmpty.suffix(max(0, limit)))
    }

    public static func draft(
        context: AIChatContext,
        draft: String = "",
        tone: AIRewriteTone? = nil,
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) -> [AIChatTurn] {
        let system = systemPrompt(
            base: "You help draft and rewrite chat messages in Courier.",
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = formatTranscript(from: context, limit: maxDraftMessages)

        var userSections: [String] = []
        if !lines.isEmpty {
            userSections.append(lines.joined(separator: "\n"))
        }

        if !trimmedDraft.isEmpty {
            if let tone {
                userSections.append("\(instruction(for: tone)) Reply with only the message text.\n\n\(trimmedDraft)")
            } else {
                userSections.append("Rewrite my draft reply. Reply with only the message text.\n\n\(trimmedDraft)")
            }
        } else {
            if let tone {
                userSections.append("Write my next reply (\(instruction(for: tone))). Reply with only the message text.")
            } else {
                userSections.append("Write my next reply. Reply with only the message text.")
            }
        }

        return [
            AIChatTurn(role: .system, text: system),
            AIChatTurn(role: .user, text: userSections.joined(separator: "\n\n")),
        ]
    }

    public static func rewrite(
        text: String,
        tone: AIRewriteTone,
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) -> [AIChatTurn] {
        let system = systemPrompt(
            base: "You rewrite chat messages in Courier.",
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = "\(instruction(for: tone)) Reply with only the message text.\n\n\(trimmed)"
        return [
            AIChatTurn(role: .system, text: system),
            AIChatTurn(role: .user, text: userText),
        ]
    }

    public static func translate(
        text: String,
        targetLanguage: String,
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) -> [AIChatTurn] {
        let system = systemPrompt(
            base: "You translate chat messages in Courier.",
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = "Translate into \(targetLanguage). Reply with only the translation.\n\n\(trimmed)"
        return [
            AIChatTurn(role: .system, text: system),
            AIChatTurn(role: .user, text: userText),
        ]
    }

    public static func summarize(
        context: AIChatContext,
        responseLanguage: String = "English",
        customInstructions: String = ""
    ) -> [AIChatTurn] {
        let system = systemPrompt(
            base: "You summarize chat conversations in Courier.",
            responseLanguage: responseLanguage,
            customInstructions: customInstructions
        )
        let lines = formatTranscript(from: context, limit: maxSummarizeMessages)
        var userSections: [String] = []
        if !lines.isEmpty {
            userSections.append(lines.joined(separator: "\n"))
        }
        userSections.append("Summarize in at most 5 short bullet points.")
        return [
            AIChatTurn(role: .system, text: system),
            AIChatTurn(role: .user, text: userSections.joined(separator: "\n\n")),
        ]
    }
}
